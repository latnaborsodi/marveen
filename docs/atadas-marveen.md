---
forras_chat: Git merge conflict resolution
datum: 2026-09-25
statusz: elo
marveen_erintett: igen
---

# Átadás — Marveen: upstream-szinkron, build-törés és javítás

**Dátum:** 2026-09-24
**Repo:** `latnaborsodi/marveen` (fork, `origin`) ← `Szotasz/marveen` (`upstream`)
**Környezet:** WSL Ubuntu-24.04 (`donat@DESKTOP-QNJ69NN`), install gyökér `~/marveen`

> Párdokumentum: `atadas-tebez.md` (a tebez repót érintő ügyek).

---

## 1. Összefoglaló

Egy `mup` (fork-szinkron) 150 upstream commitot hozott le, két fájlon konfliktussal. A `--theirs`-es feloldás kidobott egy fork-only funkciót, amitől a build elszállt. A funkciót visszatettük — már külön modulba, hogy a következő merge ne ehesse meg. A dashboard végig futott, kiesés nem volt.

---

## 2. Az upstream merge

```
mup   →   fetch upstream, merge, push, update.sh
```

**Konfliktus:** `src/db.ts`, `src/web/inbound-probe.ts`
**Feloldás:** mindkettő kód → `git checkout --theirs`, majd `git add` + `git commit --no-edit`
**Merge commit:** `2af2df8` (`merge: upstream szinkron (1f2c2c0)`)

A bevált elv (a `marveen-uzemeltetes` skillből): kód / lockfile / settings-sablon = `--theirs`, saját skill / doksi = `--ours`, `.gitignore` = a kettő uniója.

---

## 3. A build-törés és javítása

### Tünet

```
src/__tests__/inbound-probe.test.ts(5,68): error TS2305:
Module '"../web/inbound-probe.js"' has no exported member 'checkBotTokenHealth'.
```

Az `update.sh` kétszer próbálkozott, majd visszaállt a korábbi dist-re — a dashboard végig futott.

### Ok

A `checkBotTokenHealth` **fork-only** funkció volt (Tier 2 bot-token guard a deafness-respawn előtt; commit `225c435`, `tag: pre-upstream-2026-06-06`, PR #6). Az upstream-ben nem létezik. A `--theirs` az egész `inbound-probe.ts`-t upstream-verzióra cserélte, így a definíció és a hívás is eltűnt — a hozzá tartozó teszt viszont konfliktusmentesen bennmaradt, és importálta a nem létező exportot.

Diagnosztikai parancs, ami ezt kimutatta:

```bash
git show HEAD^1:src/web/inbound-probe.ts | grep -n "checkBotTokenHealth"   # ours: 303, 341
git show HEAD^2:src/web/inbound-probe.ts | grep -n "checkBotTokenHealth"   # theirs: semmi
```

### Javítás — 1. lépés (`d6b7a77`)

Új fájl: **`src/web/bot-token-health.ts`** — a `checkBotTokenHealth` ide költözött, változatlan viselkedéssel (`getMe`, 8s timeout, `{ok, statusCode?}`).
Az `inbound-probe.ts` végére egy sor: `export { checkBotTokenHealth }` (a teszt-import így tovább működik).

### Javítás — 2. lépés (`d82c05f`)

A guard visszakapcsolása a hívási helyen:

- `checkInboundProbeDeafness` sync → **async** (`Promise<void>`)
- a `if (!needsRespawn) return` után token-ellenőrzés; 401/403 → `logger.error` + respawn kihagyva, egyéb hiba → `logger.warn` + halasztás a következő tickre
- token forrása a mai upstream kódhoz igazítva: `readEnvFile(['TELEGRAM_BOT_TOKEN'])` (a régi `TELEGRAM_BOT_TOKEN` konstans már nem létezik a fájlban)
- a hívó (egy darab, fire-and-forget): `void checkInboundProbeDeafness(...).catch(...)`

**Szándékos eltérés az eredetitől:** a régi verzió 401/403-nál `notifyChannel`-lel Telegramra is riasztott. Ez öncsalás volt — ha épp a bot-token érvénytelen, az az üzenet sose ér célba. Most csak logol. Ha kell riasztás erre az esetre, más csatornán kell megoldani (pl. dashboard-értesítés) — lásd a nyitott ügyeket.

---

## 4. Tesztelés éles installban

A suite **szándékosan megtagadja** a futást az éles checkout-ban (`src/__tests__/setup/assert-not-live-install.ts`), mert mutálná a `store/`, `.env`, `.claude/skills/` tartalmát. A „264 failed" ilyenkor **nem** valódi bukás.

Helyes futtatás külön worktree-ből (ne `/tmp`-ben — a hook-path guard elutasítja):

```bash
cd ~/marveen
git worktree add --detach ~/claw-test main
cd ~/claw-test && npm ci && npx vitest run src/__tests__/inbound-probe.test.ts
cd ~/marveen && git worktree remove ~/claw-test    # takarítás
```

**Eredmény:** 22/22 zöld, benne mind a 8 `checkBotTokenHealth` teszt.

---

## 5. Tanulság — fork-only patchek kezelése

Ez a törés bármikor megismétlődhet. Az elv, amit mostantól követünk:

> Fork-only funkció **soha ne** olyan fájlban éljen, amit az upstream aktívan szerkeszt. Külön modul + egysoros re-export — így a merge legfeljebb egy sort érint, nem a fél fájlt.

Hosszabb távon a jobb megoldás ezeket PR-ként felküldeni upstreamre.

---

## 6. Környezeti ügy: WSL óracsúszás

A WSL órája ~2 nappal a Windows mögött járt (`update.sh` aug. 15-öt írt, miközben Windows-oldalon aug. 17 volt). `hwclock` nincs telepítve WSL-ben.

**Miért tartozik ide:** az `inbound-probe` deafness-logika és a heartbeat időbélyegeket hasonlít össze. Csúszó óra mellett téves respawnokat vagy elmaradó észlelést okozhat — tehát közvetlenül a 3. fejezetben javított kódot érinti. Az ütemezett feladatok is félrecsúsznak tőle.

**Javasolt javítás:**

```bash
sudo date -s "$(powershell.exe -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'" | tr -d '\r')"
date
sudo systemctl restart systemd-timesyncd && timedatectl | head -8
```

Az óraugrás után az ütemező „lemaradást" láthat és bepótolna feladatokat, ezért utána:

```bash
xboss
flotta
```

**Állapot: ellenőrizetlen** — a javítás lefutása nem lett visszaigazolva.

---

## 7. Melléktörténet: Telegram Desktop nem indult

Nem volt köze a flottához, de félrevitte a diagnózist („miért nem indul a telegramom?" — a bot-bridge végig futott). A log kulcssorai:

```
Socket connected, this is not the first application instance, sending show command…
Could not rename log_start0.txt to log.txt: Cannot remove source file
FATAL: Could not move logging to log.txt
```

Már futott egy példány (tray/zombie), ami fogta a `log.txt`-t. Javítás WSL-ből:

```bash
cd /mnt/c && powershell.exe -NoProfile -Command 'Get-Process Telegram -ErrorAction SilentlyContinue | Stop-Process -Force; Remove-Item "$env:APPDATA\Telegram Desktop\log*.txt" -Force -ErrorAction SilentlyContinue; Start-Process "$env:APPDATA\Telegram Desktop\Telegram.exe"'
```

**Megoldva.**

---

## 8. Nyitott ügyek

| # | Ügy | Állapot |
|---|-----|---------|
| 1 | **WSL óracsúszás** javításának lefuttatása és ellenőrzése (6. pont) | Ellenőrizetlen |
| 2 | Fork-only patchek végigfésülése a merge-diffben, kiszervezés külön modulokba (5. pont) | Nyitott |
| 3 | 401/403 bot-token riasztás alternatív csatornán (3. pont) | Nyitott |

---

## 9. Commitok és fájlok

| Commit | Tartalom |
|--------|----------|
| `2af2df8` | upstream merge (150 commit, `db.ts` + `inbound-probe.ts` konfliktus `--theirs`-szel) |
| `d6b7a77` | `src/web/bot-token-health.ts` létrehozása + re-export (build feloldása) |
| `d82c05f` | guard visszakapcsolása: async `checkInboundProbeDeafness` + token-ellenőrzés respawn előtt |

**Új fájl:** `src/web/bot-token-health.ts`
**Módosítva:** `src/web/inbound-probe.ts`
