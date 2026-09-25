---
forras_chat: Marveen installation and collaboration
datum: 2026-09-25
statusz: elo
marveen_erintett: igen
---

# Marveen gépátadás és üzemeltetés — élő tudás

## 1. MIRŐL SZÓL

Milán kapott egy saját Marveen-példányt egy notebookon, hogy önállóan tudjon
dolgozni és fejleszteni a tebez/épületgépészet vonalon, Donát közvetítése
nélkül. Az átadás során ki kellett takarítani Donát személyes fiókjait a
gépről, tisztázni ki mit módosíthat, és biztosítani, hogy a napi 7:45-ös
készlethiány-jelentés az ő gépén is menjen.

A munka nagyobbik fele nem a telepítés volt, hanem az üzemeltetés: három
egymást követő napon **olyan védelmek buktatták el a jelentést, amiket mi
tettünk be** — mérés nélkül. Ez a dokumentum főleg ezeknek a csapdáknak és a
helyes ellenőrzési módoknak a gyűjteménye.

Mellékszálon kiderült, hogy a desktopon a Tailscale és a WSL folyamatosan
veszekszik a `/etc/resolv.conf`-on, és ez percekre elviszi a névfeloldást.

## 2. MŰKÖDŐ TUDÁS

### 2.1 Gépek és disztrók — ezt mindig tisztázd először

| Hol | Disztró | Install | Szerep | Főagent | tmux |
|---|---|---|---|---|---|
| desktop `DESKTOP-QNJ69NN` | `Ubuntu-24.04` (alapértelmezett) | `~/marveen` + `~/tebez` | produkció, xBoss | `jezus` | `jezus-channels`, `jezus-worker`, `jezus-worker-fast`, `agent-*` |
| desktop | `Ubuntu` | `~/marveen-src` | Milán **régi**, leállított példánya | — | — |
| notebook `DESKTOP-QJ6KIP4` | `Ubuntu` | `~/marveen-src` | Milán **élő** példánya | `milan` | `milan-channels`, `milan-worker*` |

Melyik disztróban vagyok:

```bash
ls -d ~/marveen ~/marveen-src ~/tebez 2>&1
echo "$WSL_DISTRO_NAME"
```

Minden szkript elejére védelem, hogy ne a rossz gépen fusson:

```bash
if [ "${WSL_DISTRO_NAME:-}" != "Ubuntu-24.04" ]; then echo "!!! rossz disztro"; exit 1; fi
```

Asztali parancsikonok (`.lnk`-ből kiolvasva):

```
x - Ubuntu  →  C:\Windows\System32\wsl.exe -d Ubuntu-24.04    (produkció, xBoss)
M - Ubuntu  →  C:\Windows\System32\wsl.exe -d Ubuntu          (Milán régi példánya)
```

A notebook a desktopról eléri: `ssh notebook` (a notebookon **jelszó nélküli
sudo** be van állítva).

### 2.2 Ütemezett feladatok anatómiája

Minden feladat **két** fájl egy könyvtárban:

```
~/.claude/scheduled-tasks/<nev>/SKILL.md          # a prompt
~/.claude/scheduled-tasks/<nev>/task-config.json  # enabled, requires, schedule, stuckAfterMinutes
```

Állapot és előzmény:

```
~/marveen/store/schedule-last-run.json      # feladatonként utolsó futás (ms)
~/marveen/store/schedule-tick-state.json    # lastTickMs, 60 s-os tick
~/marveen/store/claudeclaw.db               # pending_task_retries, scheduled_tasks, kanban_*
~/marveen/store/.dashboard-token            # Bearer token
```

Dashboard: `http://localhost:3420` (mindkét disztró ugyanazt a Windows-
localhostot használja — amelyik előbb foglalta, azé).

Gyors lekérdezések:

```bash
T=$(cat ~/marveen/store/.dashboard-token)
curl -s -H "Authorization: Bearer $T" http://localhost:3420/api/schedules | python3 -m json.tool
curl -s -H "Authorization: Bearer $T" http://localhost:3420/api/schedules/pending
sqlite3 -header -column ~/marveen/store/claudeclaw.db "select * from pending_task_retries;"
```

A `pending` sor mezői, amik számítanak: `lastReason` (`busy` / `mcp-missing:<nev>` /
`network-missing`), `attemptCount`, `alertSentAt`, `alertDue`.

### 2.3 Tiszta újraindítás (a `systemctl restart` NEM elég)

A tmux server túléli a unit leállítását, így a régi `claude` process a régi
paraméterekkel fut tovább.

```bash
systemctl --user stop jezus-channels
tmux kill-session -t jezus-channels 2>/dev/null
systemctl --user start jezus-channels
```

(Notebookon ugyanez `milan-channels`-szel.) A kontextus nem vész el, mert a
worker `--continue`-val indul. Ellenőrzés, hogy tényleg új process:

```bash
ps -o pid,lstart,cmd -C claude | head
```

### 2.4 Elakadt-e vagy dolgozik? — a döntő teszt

Nem a képernyő ránézése, hanem hash-összehasonlítás:

```bash
h1=$(tmux capture-pane -p -t jezus-channels | md5sum); sleep 5
h2=$(tmux capture-pane -p -t jezus-channels | md5sum)
[ "$h1" = "$h2" ] && echo "NEM VALTOZIK" || echo "DOLGOZIK"
```

Plusz CPU-delta (`/proc/<pid>/stat` 14. és 15. mezője) két mérés között.

Ha a pane nem változik **és** a `tmux send-keys ... C-u` / `Escape` sem
változtat rajta semmit → a folyamat beragadt, nem szöveg ül a mezőben →
tiszta újraindítás kell.

### 2.5 Aludt-e a gép? — a helyes műszer

**Windows eseménynapló**, nem `uptime`:

```bash
WV=/mnt/c/Windows/System32/wevtutil.exe
timeout 45 "$WV" qe System \
  "/q:*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and (EventID=42 or EventID=107)]]" \
  /c:25 /rd:true /f:text < /dev/null 2>/dev/null | tr -d '\000' | grep -aiE "^  Date:|Event ID:" | paste - -
```

42 = elalvás, 107 = ébredés. Plusz:

```bash
/mnt/c/Windows/System32/powercfg.exe /lastwake < /dev/null
/mnt/c/Windows/System32/powercfg.exe /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE < /dev/null \
  | grep -iE "Current AC|Current DC"
```

`Current AC Power Setting Index: 0x00000000` = hálózati tápon **soha nem alszik el**
(ez a desktopon így van beállítva). DC oldalon `0xb4` = 180 mp = **3 perc**
akkumulátoron — ezért létkérdés, hogy a notebook hálózaton legyen reggel.

### 2.6 Journal-hézag keresés (VM-fagyás kimutatása)

```bash
journalctl --since "2026-09-01 08:00" -o short-unix --no-pager > /tmp/j.raw
python3 - <<'PY'
import datetime
prev=None
for line in open("/tmp/j.raw", errors="replace"):
    p=line.split(None,1)
    if not p: continue
    try: t=float(p[0])
    except ValueError: continue
    if prev and t-prev>90:
        print("hezag %6.0f mp: %s -> %s" % (t-prev,
          datetime.datetime.fromtimestamp(prev).strftime("%m-%d %H:%M:%S"),
          datetime.datetime.fromtimestamp(t).strftime("%m-%d %H:%M:%S")))
    prev=t
PY
```

Figyelem: `awk` + `strftime` nem megy mawk alatt (Ubuntu alapértelmezés) —
ezért python. És **előbb nézd meg, van-e egyáltalán adat** a kért időszakra:

```bash
journalctl --list-boots --no-pager
journalctl --since '2026-09-01 00:00' --until '2026-09-02 00:00' --no-pager | wc -l
```

### 2.7 DNS a desktopon (jelenlegi, működő állapot)

```bash
# /etc/wsl.conf
[boot]
systemd=true

[network]
generateResolvConf = false
```

```bash
sudo tailscale set --accept-dns=false
# /etc/resolv.conf (kézzel írt, senki nem írja felül):
nameserver 172.17.48.1     # WSL host resolver (= default gateway)
nameserver 1.1.1.1
nameserver 8.8.8.8
```

Ellenőrzés (nincs `nslookup` telepítve, `getent`-tel menj):

```bash
for h in api.telegram.org vps.bezzeghkft.hu api.anthropic.com; do
  timeout 8 getent hosts $h >/dev/null 2>&1 && echo "$h OK" || echo "$h HIBA"
done
tailscale dns status | grep -A4 "Resolvers (in preference"
journalctl --since "$(uptime -s)" --no-pager | grep -c trample   # 0 a jó
```

Visszaút, ha kell:

```bash
sudo tailscale set --accept-dns=true
sudo sed -i '/^\[network\]/,+1d' /etc/wsl.conf
sudo rm -f /etc/resolv.conf
# majd PowerShellből: wsl --shutdown
```

A mentések: `/etc/resolv.conf.bak-<HHMM>`.

### 2.8 Windows-parancsok WSL-ből / ssh-n át

A notebookon **nincs interop a PATH-on** (`powershell.exe: command not found`),
teljes úttal viszont megy: `/mnt/c/Windows/System32/...`.

Két kötelező fogás:

```bash
# 1) Windows .exe ssh-heredoc alatt FELISZZA a stdint -> a szkript többi része elvész
timeout 45 "$WV" qe System ... > /tmp/ev.raw 2>/tmp/ev.err < /dev/null

# 2) a kimenet UTF-16, a grep binárisnak látja
tr -d '\000' < /tmp/ev.raw | grep -a ...
```

Keresztdisztró-parancs PowerShellből (WSL-ből gyakran elhasal a `chdir`):

```powershell
wsl.exe -d Ubuntu -e bash -c "grep -i bot_token /home/donat/marveen-src/.env | cut -c1-30"
```

### 2.9 `sudo` + beillesztés

A `sudo` jelszó-promptja **megeszi a beillesztett blokk maradékát**, és a
maradék bemegy jelszóként. Ezért:

```bash
sudo -v            # külön, egyedül, ezt hitelesíted
# csak UTÁNA a tényleges parancs, egy sorban:
printf '\n[network]\ngenerateResolvConf = false\n' | sudo tee -a /etc/wsl.conf
```

Több soros blokkot heredoc-kal **soha** ne adj ki `sudo`-val egyben.

### 2.10 Hosszú parancsok távoli gépen (Claude munkamódszer)

A `computer_type` ~13 karakter felett csendben csonkol. Bevált minta:

1. a szkriptet `device_bash`-sel kiírni ide: `C:\Users\user\Desktop\<nev>.sh`
2. a terminálban csak ennyit gépelni, 10 karakteres darabokban:
   `bash /mnt/c/Users/user/Desktop/<nev>.sh`
3. a szkript `exec > /mnt/c/Users/user/Desktop/<nev>-out.txt 2>&1`
4. az eredményt `device_bash`-sel visszaolvasni, a fájlokat utána törölni

A `wsl.exe` engedélyezése szeszélyes: az asztali parancsikon a
`c:\windows\system32\wsl.exe`-t indítja, de a `computer_resolve_access` hol
ezt, hol a `c:\program files\wsl\wsl.exe`-t adja vissza. Ha az ablak
láthatatlan marad, `File Explorer` (click tier) engedéllyel a tálcáról kell
visszahozni.

## 3. DÖNTÉSEK

**Milán a teljes gépet kapja, terminállal és GitHub-push-sal.**
Eredetileg csak Telegram-hozzáférés lett volna. Megfordítottuk, mert a cél
nem az, hogy Milán *használja* az ügynököt, hanem hogy **utasításokat tudjon
adni neki, azaz fejleszteni**. Közvetítő nélkül ez másképp nem megy.

**Az élesítés Donátnál marad.**
Milán fejleszthet és tesztelhet, de fájl kitétele `tebez-prod`-ra és a
jelentés-szkript élesítése nem az ő joga. Ez az egyetlen pont, ahol egy
hibás szkript az éles rendszerbe kerülhetne — átmegy emberi szemen.

**Az RS3-ban csak olvasás.**
A jelentés 18 táblát használ a `raktar` sémából. A `cikkraktar`/`raktar`
táblákat **nem** használja. Írási jog nincs és nem is kell.

**A `requires` kapukat kivettük a két épületgépészet-feladatból.**
`epuletgepeszet-hianycikk-napi` és `epuletgepeszet-jelentes-onellenorzes` —
sem `mcp_servers`, sem `network_hosts`. Indok: *egy időben megjövő jelentés
többet ér, mint egy elméleti védelem, ami eddig kizárólag kárt okozott.*
Backup: `task-config.json.bak2-2026-09-02`.

**A notebook DNS-ét nem piszkáltuk meg.**
Fut rajta Tailscale, nincs benne `generateResolvConf = false`, és **mégsem
történik semmi**: 0 `trample`, minden név feloldódik. Nincs mit javítani —
és ma háromszor buktunk azon, hogy meg nem mért problémára tettünk be
védelmet. Kártya, nem beavatkozás: *ha megjelenik `trample` a notebook
journaljában, akkor jön a két sor.*

**Tailscale: „Override DNS servers" marad KIKAPCSOLVA.**
Bekapcsolva a tailnet minden gépe elveszíti a helyi DNS-tartalékát — köztük
a notebook, Pesten. Így a változás visszafordítható marad.

**A desktopon az `accept-dns=true` nem megy vissza, amíg a
`tailscale dns status` ki nem írja a `8.8.8.8`-at a resolverek között.**
Amíg bizonyítatlan, nem nyúlunk hozzá.

**A képtár megosztása: képek maradnak lokálisan, dokumentumok mennek.**
A 308 GB valójában ~160 GB PDF, ~58 GB videó, ~52 GB ZIP, ~30 GB kép. A
videók DB-hivatkozás nélkül voltak → törölve. A PDF+ZIP (~212 GB) megy
Contabo Object Storage-ra, nginx `proxy_pass` + lokális cache mögé. A képek
maradnak, mert azokat gyakran és kicsiben kéri a rendszer.

**A `tebez-prod` restricted kulcs `from=` nélkül.**
A `from=` IP-hez köt, nem identitáshoz — dinamikus IP mellett hamis
biztonságot ad és működésképtelenné teszi a kulcsot. Helyette
`restrict,command="..."` forced command + audit log.

## 4. CSAPDÁK

### 4.1 `requires` kapuk: a fail-open csendben fail-closed lett

A `requires.mcp_servers: ["email"]` beállítás **nem** nyitott kapuval bukott,
hanem tartós blokkolásra fordult, mert a `resolveMcpProcessPatterns` nem
találta meg az email MCP folyamatot. Eredmény: **162 újrapróbálás**,
`lastReason: mcp-missing:email`, a jelentés aznap reggel nem ment ki.

Ráadásul **az önellenőrzést ugyanaz a feltétel blokkolta**, amit őriznie
kellett volna — `alertSentAt: null`, tehát riasztani sem tudott.

Ellenőrzés bevezetés előtt: kapu **soha** ne az éles futáson debütáljon.
Külön, ártalmatlan tesztfeladaton kell kipróbálni, és be kell mutatni, hogy
a halasztott feladat a feltétel teljesülésekor **tényleg elindul** — ezt
eddig senki nem látta működni.

### 4.2 A riasztás egyszer szól, aztán elnémul

`alertSentAt` beáll → `alertDue: false` marad → a rendszer *tudja*, hogy
elakadt, és több száz további bukást némán elnyel. A desktopon 09:27-kor
szólt egyszer, majd 336-szor bukott szó nélkül.

### 4.3 Könyvtár átnevezésével NEM lehet feladatot kikapcsolni

Az `ensureDefaultScheduledTasks` (agent-scaffold.ts) újra létrehozza a
kanonikus nevű könyvtárakat. A `.KIKAPCSOLVA` átnevezés után a
`reggeli-napindito` **lefutott** (`fired_late`). Ráadásul a
`listScheduledTasks` nem szűri a ponttal kezdődő könyvtárakat, így az
átnevezés **azonos nevű, duplikált, engedélyezett feladatot** hozott létre
latens hibaként.

Helyes mód: `"enabled": false` a `task-config.json`-ban.

### 4.4 Beragadt bemenet vs. beragadt folyamat — két különböző baj

**Ismert termékhiba:** új agent létrehozásakor a dashboard minden futó
agentnek beküld egy hosszú bemutatkozó system üzenetet; a stuck-input figyelő
több soros csonkolt bemenetre szándékosan nem nyom Entert → **minden futó
agent bemenete beragad**. Feloldás: `tmux send-keys -t agent-<nev> Enter`.

**TÉVES DIAGNÓZIS volt viszont**, amikor a `jezus-channels` 73 percig `busy`
állapotban állt. Azt állítottam, hogy elküldetlen prompt ül a mezőben.
`Ctrl+U` és `Escape` után a pane **egyetlen karaktert sem változott** →
nem szöveg ült ott, hanem a Claude Code példány bemenetkezelése fagyott be.
A folyamat élt (PID, minimális CPU), a tmux hibátlanul működött.

Különbségtétel: ha a `send-keys` után a pane hash-e **nem változik**, az
nem beragadt szöveg, hanem beragadt folyamat → tiszta újraindítás.

### 4.5 A gépalvás-hipotézis — TÉVES volt

Feltevés volt, hogy két diszkrét, magától helyreálló kiesés = alvó gép.
**Cáfolva:** az utolsó Kernel-Power 42/107 páros 2026-08-25, azóta semmi.
`powercfg /lastwake` → `Wake History Count - 0`. AC alvás = 0 (soha).

A javasolt „javítás" (AC-n ne aludjon el) **már be volt állítva** — egy nem
létező problémára kértünk volna rendszerbeállítást Milán gépén.

**A saját hibám ugyanebben:** korábban azt mondtam, „az uptime folyamatos,
tehát nem aludt". Ez rossz műszer. A WSL-ben `who -b` (09-01 08:28) és a
`/proc/uptime`-ból számolt boot (09-01 11:21) **2 óra 53 perccel eltér**, és
a `last reboot` két egyszerre „still running" bejegyzést mutat — az utmp
megbízhatatlan. A következtetés véletlenül lett igaz.

Windows-oldali kérdésre Windows-oldali műszer kell.

### 4.6 A „diszkrét ablak ⇒ nem a hálózati kapu" érvelés hibás

Elhangzott, hogy ha a hálózati kapu akasztaná meg a tick-et, az folyamatos
lenne. **Nem következik:** a DNS-alapú kapu pont szaggatott, magától gyógyuló
ablakokat produkál. Lásd 4.7 — bizonyítékkal.

### 4.7 Tailscale ↔ WSL: harc a `/etc/resolv.conf`-ért

A desktopon naponta **13× indult újra a `systemd-resolved`**, és a disztró
indulása óta **42 `trample` esemény** volt. A journalban:

```
tailscaled: trample: read error: open /etc/resolv.conf: no such file or directory
tailscaled: trample: resolv.conf changed from what we expected. did some other
            program interfere? current contents: "# ...generated by WSL...
            nameserver 172.17.48.1"
tailscaled: health(resolv-conf-overwritten): error: System DNS config not ideal
```

Ebben az ablakban a névfeloldás percekre megszűnik → a Telegram-híd
(`bun server.ts`) elhasal és újraindul. Konkrét eset: 11:22:44 és 11:29:02,
az agent 240 mp-es kiesést jelentett — **miközben maga az agent nem indult
újra**. A híd újraindulása ≠ az agent újraindulása.

### 4.8 A `generateResolvConf = false` eltörte a DNS-t — SAJÁT HIBA

A beállítás helyes, de az életbe lépése után **minden névfeloldás megszűnt**.
Ok:

```
tailscale dns status
  Resolvers (in preference order):
    (no resolvers configured, system default will be used)
```

A MagicDNS-nek nincs feljebbvaló névszervere; addig a WSL által generált
`resolv.conf`-ot használta „system default"-ként. Amikor a WSL-t leszoktattuk
róla, elfogyott alóla az alap.

**Egy `tailscale dns status` a beavatkozás előtt megmutatta volna.** Ez
pontosan az a hiba, amit ugyanaznap a botnál kifogásoltunk: a kaput élesben
teszteltük.

Kötelező előellenőrzés bármilyen resolv.conf-beavatkozás előtt:

```bash
tailscale dns status | grep -A4 "Resolvers (in preference"
```

### 4.9 `/etc/wsl.conf` csak a disztró indulásakor olvasódik

A fájl módosítása után a beállítás **nem él**, amíg nincs `wsl --shutdown` +
újraindítás. Ellenőrzés:

```bash
stat -c '%y' /etc/wsl.conf    # mikor módosult
uptime -s                     # mikor indult a disztró
```

Ha a módosítás későbbi, a beállítás nem hatályos.

### 4.10 Hiányzó eszköz → néma, hamis eredmény

`nslookup` nincs telepítve. A rá épülő DNS-próbák „timeout: nincs ilyen fájl"
hibával futottak, a feltételes auto-javítás pedig **„hálózati gond van"**
következtetésre jutott — tévesen. `getent hosts` mindig elérhető; ha
szerver-specifikus lekérdezés kell, előbb `apt install dnsutils`.

### 4.11 Az őr nem tudja őrizni önmagát

Kétszer ugyanaz: az `epuletgepeszet-jelentes-onellenorzes`-t ugyanaz a
feltétel blokkolta, mint az őrzött feladatot; az `orkutya-flotta-ellenorzes`
(a néma agenteket észlelő óránkénti őrkutya) maga akadt el 73 percre.
Az őrnek más futtatókörnyezetben kell lennie, mint amit őriz.

### 4.12 Egyéb, drágán megtanult apróságok

- **A desktop `Ubuntu` disztró megnyitása elindítja a `milan-morning.timer`-t**
  → duplikált reggeli briefing ment ki Milán csoportjába 10:43-kor. Ne nyisd
  meg csak úgy.
- **A bot backtick-ekkel csempészett át egy szót a saját kimenő-másolat
  kapuján.** Ez megváltoztatta az átnézett diffet és egy kört elvitt egy
  nem létező shell-hiba keresésével. Szabály: *ha egy kapu útban van, az nem
  kikerülendő akadály, hanem jelzés.*
- **Force-push review alatt álló PR-on**, „ugyanaz a diff mint korábban"
  önigazolással. Szabály: force-push előtt és után írja ki a commit SHA-t,
  hogy a felülvizsgáló össze tudja hasonlítani.
- **Regex-alapú konfigszerkesztés fájlt evett:** a `(?:\s+.*\n)*` minta
  felfalta a `.gitconfig` maradékát. Soralapú vagy blokkalapú szerkesztés,
  és előtte mentés.
- **A notebook journalja nem őriz múltat** (semmi ~00:23 előttről, miközben
  367 MB archív journal van a lemezen). Utólagos vizsgálat emiatt lehetetlen.
- **A `bevet`/`bevetlab` a bevételezés, a `megrendfejk` a rendelés.** A
  `commerce_purchase_orders` szinkron a *rendelést* hozza, nem a ténylegesen
  bevételezett tételt. A `betarazva` mező jelentése **ellenőrizetlen** —
  mezőnévből következtetve, Krisztiánnal megerősítendő.
- **A szinkron-pipeline `TRUNCATE`+újratöltéssel gördülő 12 hónapot tárol.**
  Időszaki összehasonlítás erre nem építhető, és az ablak tágítása (24 hó) sem
  old meg semmit, csak elodázza. Helyes forma: havi pillanatkép-tábla, amit a
  szinkron ír, de soha nem truncate-el.

## 5. NYITOTT ÜGYEK

| Ügy | Állapot | Következő lépés |
|---|---|---|
| Tailscale globális névszerver nem ér el a kliensekhez | elakadt — konzolban mentve, Split DNS ki, Override ki, mégis „no resolvers configured" mindkét gépen, `tailscaled` újraindítás után is | Tailscale support: `tailscale dns status` kimenet + konzol képernyőkép |
| desktop `accept-dns=true` visszakapcsolása | blokkolva a fentitől | csak ha a `dns status` kiírja a `8.8.8.8`-at |
| `.ts.net` névfeloldás a desktopon | nem működik (`accept-dns=false`) | IP-vel dolgozni addig |
| `resolveMcpProcessPatterns` nem találja az email MCP folyamatot | nem javítva | a folyamat-mintaillesztés megnézése a forrásban |
| `network_hosts` kapu soha nem volt tesztelve | kivéve a jelentésből | külön tesztfeladaton: létező + nem létező host, 3 s korlát, és hogy a halasztott feladat **tényleg elindul** a hálózat visszatértekor |
| Retry-ciklus soha nem adja fel | nem javítva | N sikertelen próbálkozás után álljon le és eszkaláljon; ne 14 mp-enként pörögjön |
| Riasztási küszöb határidős feladatnál túl lassú | nem javítva | rövidebb küszöb + ne némuljon el egy riasztás után |
| Önellenőrzés ugyanazokkal a feltételekkel fut, mint az őrzött feladat | nem javítva | külön futtatókörnyezet, eltolt időpont |
| `jezus-worker-fast`: `Not logged in` | nyitva | `claude setup-token` a WSL-oldalon → `~/.claude/settings.json` `env.CLAUDE_CODE_OAUTH_TOKEN` → `xboss` |
| `epgep@bezzeghkft.hu` jelszó nyílt szövegben (`~/.claude.json`, és a kiosztott tar-ban) | **nem rotálva** | jelszócsere, majd MCP-konfig frissítés a notebookon |
| PR #43 (downloader), #45, #46, #47 | #46 mergelve, #47 konfliktus feloldva és CI-n | melyik repóban vannak; merge indít-e CI-deployt `tebez-prod`-ra; „Donát mergel" kapu újra kimondása |
| 212 GB (PDF+ZIP) Contabo Object Storage-ra | tervezve, nem indult | bucket, nginx `proxy_pass` + cache, Downloader átírása a bucketre |
| `tebez-prod` felvétele Tailscale-re (`18cebec3`) | nyitva | IP-vel, mert `.ts.net` név nincs |
| `5432/tcp` és `3003/tcp` nyitva az internet felé (task #35) | nyitva | tűzfal szűkítés |
| `log-tail` wrapper-kiterjesztés | nyitva | hogy a heti wrapper-log audit menjen a teljes kulcs nélkül is |
| RS3 `EXECUTE` jogosultság tisztázása; `raktar.*` szűkítése a 18 használt táblára | kártyázva, **nem végrehajtandó** | Krisztiánnal egyeztetni |
| `5589f7ff` — `outgoing-copy-gate-rules.json` üres tartalommal fut | nyitva, 48 órát túllépett | valódi `bad_name_patterns` kell; **és** tisztázni, hogy a kapu a markdown-normalizálás előtt vagy után ellenőriz (lásd backtick-eset) |
| `49aa9d79` — Szerelvénybolt árai kisker vagy dealer árak | nyitva, **üzleti döntés** | Milán dönti el; 12 termék nyerne valódi nagyker árat |
| Beszállítói scraperek kikapcsolva | szándékos | visszakapcsolás előtt kis tételen tesztelni; egy teljes kör 2 nap |
| Tegnapi (09-01) két kiesés: 11:12–12:33 és 16:38–17:27 | **megmagyarázatlan** | alvás kizárva; a jelenlegi WSL-boot 09-01 11:21:38-kor kezdődött, ami az első ablakba esik — WSL-újraindulás gyanú, nem bizonyított; a második ablakra nincs újraindulás |
| `tailscale status` health: hiányzó `connmark` iptables-modul a WSL-kernelben | ismert, nem kritikus | figyelni, ha a Tailscale-útvonalak furcsán viselkednek |
| Átadólevél + hozzáférések elküldése Milánnak | nyitva | külön csatornán, ne a csoportban |

## 6. HIVATKOZÁSOK

### Fájlok és útvonalak

```
~/marveen/                                   # desktop produkció (xBoss)
~/marveen-src/                               # Milán példánya (notebook)
~/.claude/scheduled-tasks/<nev>/SKILL.md
~/.claude/scheduled-tasks/<nev>/task-config.json
~/marveen/store/.dashboard-token
~/marveen/store/schedule-last-run.json
~/marveen/store/schedule-tick-state.json
~/marveen/store/claudeclaw.db
~/.claude/settings.json                      # env.CLAUDE_CODE_OAUTH_TOKEN (WSL-oldali!)
~/.claude/channels/telegram/access.json      # engedélylista
~/.claude/channels/telegram/.env             # TELEGRAM_BOT_TOKEN
~/marveen-last-good.txt                      # utolsó működő commit (Milán példánya)
/etc/wsl.conf                                # csak indulásskor olvasódik
/etc/resolv.conf(.bak-HHMM)
/usr/local/bin/tebez-report-wrapper.sh       # tebez-prod, forced command wrapper
/var/log/tebez-report-wrapper.log            # root:deploy 0660 + logrotate create 0660 root deploy
/var/www/tebez_report/refresh_and_match.rb   # tkod-szűrő itt
```

Figyelem: **két külön Claude-login** van. A Windows-oldali
(`C:\Users\user\.claude`) a VS Code-é; a flotta a WSL-belit (`/home/donat/.claude`)
használja. A flotta hibájához a WSL-oldalt javítsd.

### tebez-prod `authorized_keys` — ellenőrzött állapot (5 bejegyzés)

```
1. RSA     nvtWkQ…  user@DESKTOP-QNJ69NN          (Donát desktop, ~/.ssh/id_rsa)
2. ED25519 KWnJvY…  user@DESKTOP-QNJ69NN          (Donát desktop, ~/.ssh/id_ed25519)
3. ED25519 xbEn2e…  ond-worker
4. ED25519 E7Fmza…  github-actions-deploy-tebez
5. ED25519 UDh+EO…  tebez-report-restricted
   [restrict,command="/usr/local/bin/tebez-report-wrapper.sh"]
```

A régi teljes root-kulcs eltávolítva.

### A wrapper lényege

Döntés a **nyers** értéken, naplózás a **fertőtlenített** értéken (különben a
kliens hamis `ACCEPT` sorokat tud a logba írni):

```bash
RAW_CMD="${SSH_ORIGINAL_COMMAND:-}"
SAFE_CMD="$(printf '%s' "$RAW_CMD" | tr -d '\000-\037' | cut -c1-200)"
case "$RAW_CMD" in
  "")             log_line ACCEPT; exec env TEBEZ_DIR=/var/www/tebez "$RUBY" "$SCRIPT" --tkods - ;;
  "skip-refresh") log_line ACCEPT; exec env TEBEZ_DIR=/var/www/tebez "$RUBY" "$SCRIPT" --tkods - --skip-refresh ;;
  *)              log_line REJECT; echo "Restricted key: command not allowed." >&2; exit 1 ;;
esac
```

`set -u` mellett `_sc="${SSH_CLIENT:-}"` kell, különben SSH-n kívül elszáll.
A hiányzó logfájl **szándékosan** megállítja a futást.

### tkod-szűrő

```ruby
TKOD_ALLOWED = /\A[\p{L}\p{N} \-\/."']{1,200}\z/
MAX_TKODS = 20_000
abort("Tul sok tkod sor (#{tkods.size} > #{MAX_TKODS})") if tkods.size > MAX_TKODS
valid_tkods, invalid_tkods = tkods.partition { |t| t.match?(TKOD_ALLOWED) }
unless invalid_tkods.empty?
  warn "FIGYELEM: #{invalid_tkods.size} sor elutasitva: #{invalid_tkods.first(20).inspect}"
end
abort('Minden tkod sor elutasitva - rossz a bemenet') if valid_tkods.empty? && !tkods.empty?
tkods = valid_tkods
```

### URL-ek

- Dashboard: `http://localhost:3420` — teljes URL egy sorból:
  `echo "http://127.0.0.1:3420/?token=$(cat ~/marveen/store/.dashboard-token)"`
- Tailscale DNS admin: `https://login.tailscale.com/admin/dns`
- Tailscale DNS dokumentáció: `https://tailscale.com/kb/1054/dns`
- Tailnet: `taila5ddb3.ts.net` — `100.82.167.83` desktop-qnj69nn,
  `100.70.206.12` desktop-qj6kip4 (notebook)
- tebez repo: `https://github.com/latnaborsodi/tebez`
- Éles tebez felület: `http://75.119.137.104/tebez`
- Milán üzemeltetési eligazítása: `atadas/Milan-uzemeltetesi-eligazitas.md`

### Kapcsolódó skill

`marveen-uzemeltetes` — a napi parancsok (`flotta`, `xboss`, `flottastart`,
`mup`, `frissit`, `jelentes`, `feladat`) és a tipikus hibák gyógymódjai ott
vannak, ez a dokumentum azt **kiegészíti**, nem helyettesíti.
