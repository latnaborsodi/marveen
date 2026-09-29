---
name: "marveen-uzemeltetes"
description: "Donát Marveen/xBoss flottájának és a tebez-prod szervernek az üzemeltetési puskája: parancsok, hibaelhárítás, frissítés. Desktop Ubuntu-24.04 = produkció/xBoss; desktop Ubuntu = Milán régi, leállított példánya; Milán ügynöke Milán laptopján fut (RustDesk). Használd ha Donát a flotta indításáról, állapotáról, Marveen-frissítésről kérdez, ha egy agent elakadt vagy nem válaszol, vagy ha a tebez szerveren kell parancsot futtatnia. Kifejezések: puska, xboss, flotta, agent nem válaszol, ping, néma, elhalt, MCP cső, /mcp, 401, OAuth revoked, channels failed, kimaradt ütemezés, melyik gépen, melyik disztró, laptop, rustdesk, milan-ugynoke, milan_tebez_bot, kinai-marketing, tebez szerver, ssh deploy, RS3 szinkron, tebez_bot_ro, psql, dashboard, triázs, synonyms gem, deploy key, gmail auth, refresh token, napindító, CODEOWNERS, NAV Online Számla, GA4, Merchant Center, Google Ads, xbossbezzegh, Apps Script, appsscript.json, built-commit, bukás-teszt, rád vár digest."
---

# Marveen / xBoss üzemeltetési puska (Donát)

Donát flottájának napi üzemeltetése: parancsok, tipikus hibák, frissítés.
Minden parancs **WSL** (Ubuntu) környezetben fut.

---

## NYITOTT TEENDŐK (frissítsd, ha lezárul)

- **CI deploy-kulcs (2026-09-07, folyamatban):** kulcs + `SYNONYMS_DEPLOY_KEY`
  secret kész, xBoss ága `ci/synonyms-deploy-key`. A merge UTÁNI main-futás
  zöldjén (nem a PR zöldjén!) → `GH_PRIVATE_GEM_TOKEN` secret törlése +
  `tebez-agent-bot` fiók törölhető; `rm ~/.ssh/synonyms_ci`.
- **NAV Online Számla MCP (2026-09-10, MILÁNON a labda):** repó klónozva
  `/home/donat/nav-online-invoice-mcp`, build kész, `.env` sablon a helyén
  (600, gitignore-olt, `NAV_BASE_URL` SZÁNDÉKOSAN nincs benne). Donátnak
  **nincs hozzáférése a Bezzegh Kft. NAV-fiókjához**, ezért a technikai
  felhasználót **Milán hozza létre** az onlineszamla.nav.gov.hu-n, a cég
  nevében, **kizárólag lekérdezési joggal** (2026-09-10-i döntés: éles fiók,
  nem teszt — a teszt-rendszernek külön regisztrációja van, amiben Milán
  elveszne, a lekérdezési jog pedig önmagában is kizárja a beküldést).
  A mentés után a képernyő **egyszer** írja ki a négy értéket (felhasználónév,
  jelszó, XML aláírókulcs, cserekulcs) — elnavigálás után újat kell generálni.
  **Az átadás telefonon, diktálva megy**, nem emailben és nem Telegramon.
  Utána `query_taxpayer` próba. Külön: `npm audit` javítás ágon.
- **Google Ads adat — még nyitva (2026-09-10):** az Ads-adathoz ütemezett
  szkript kell, amit a mi Read only jogunk nem enged létrehozni. Az Ads
  fejlesztői token (MCC-n át, napok) nem előfeltétel.
  A Merchant Center rész MEGJÖTT, lásd lent.

### FIGYELEM: a szolgálati fiók LETILTVA (2026-09-10 este)
A Google felfüggesztette a `xbossbezzegh@gmail.com` fiókot, "több fiókkal együtt
szabálysértés / bot által létrehozott" indoklással. Donát fellebbez.
**Áll:** a `bezzegh-analytics-export` tábla és a napi GA4 export, a GA4 / Ads /
Merchant Center olvasói hozzáférés, a `google-drive-bezzegh` MCP kapcsolat.
**NE** futtass rá semmit, **NE** hitelesítsd újra, és **NE** javasolj pótfiókot: az
megerősítené azt a mintát, ami miatt letiltották. Ha a fellebbezés nem jön be, a
következő út céges Workspace-fiók a `bezzeghkft.hu` domainen, de az cégdöntés.
**Amit nem érint:** a NAV Online Számla út (külön hitelesítés, helyi `.env`), és a
`gmail` / `google-calendar` / `google-drive` MCP kapcsolatok, mert azok Donát saját
fiókján futnak. A szkriptek jók, maradnak.
Az alábbi szakasz a letiltás ELŐTTI állapotot írja le, és akkor válik újra érvényessé,
ha van működő fiók.

### Elkészült: GA4 → Google Sheets riport-útvonal (2026-09-10)
A szolgálati fiók `xbossbezzegh@gmail.com` (2FA). Hozzáférések Milántól:
GA4 **Megtekintő** a `bezzeghkft.hu` tulajdonon (**405123784**), Google Ads
**Read only** a **922-227-0048** fiókon, Merchant Center **Csak olvasás** a
Bezzegh Épületgépészet fiókon (kereskedői azonosító **5339008587**,
2026-09-10). Ezzel mind a három adatforrás megvan.

- Tábla: `bezzegh-analytics-export`, a szolgálati fiók Drive-jában,
  azonosító `18TnFectOR5J4RC2cWDFv89Ehx-RpRlH0ixLgP606aH4`. Nincs megosztva.
- Három lap: `napi` (HOZZÁFŰZŐ, egy sor naponta), `forrasok` és `celoldalak`
  (FELÜLÍRÓ, naponkénti top 100, 28 napos ablak).
- Apps Script `napiFrissites`, napi időzítés 6–7 óra között (GMT+02:00).
  A `napi` lap egyszer visszatöltve egy évre (`egyszeriVisszatoltes`).
- GA4 adatmegőrzés: **14 hónap**, visszaállító kapcsoló bekapcsolva.
- Az Ads-adat NEM ezen az úton jön; az még nyitva van.

**A szolgálati fiók MCP-bekötése, szétválasztva.** A meglévő három kapcsolat
tokene érintetlen: `~/.gmail-mcp/credentials.json`,
`~/.config/google-calendar-mcp/tokens.json`,
`~/.config/google-drive-mcp/tokens.json`. A szolgálati Drive külön bejegyzés
(`google-drive-bezzegh`), saját kulcs- és token-útvonallal
`~/.mcp-bezzegh/google-drive/` alatt. A hitelesítő parancsra IS rá kell tenni
a környezeti változókat, nem elég a szerver-bejegyzésbe:
`GOOGLE_DRIVE_OAUTH_CREDENTIALS`, `GOOGLE_DRIVE_MCP_TOKEN_PATH`,
`GOOGLE_DRIVE_MCP_SCOPES` — enélkül az alapértelmezés Donát tokenjét írja
felül. **Hitelesítés előtt mindig másolat a régi tokenről**, utána
időbélyeg-ellenőrzés mindkét fájlon. (`openid` nem érvényes scope-alias, a
`userinfo.email` teljes URL-lel viszont igen — ez tölti ki az e-mail mezőt,
és ez a bizonyíték, hogy melyik fiók van bent.)

**Amit szándékosan NEM kötöttünk be: a szolgálati Gmailt.** A csomag
jogosultságai be vannak égetve (`gmail.modify` + `gmail.settings.basic`),
tehát írna, és a postafiók-beállításokhoz (szűrő, továbbítás) is hozzáférne.
Egy ilyen postafiókra bárki írhat, vagyis idegen szöveg tudna tartós szabályt
létrehozni. Ezért nincs postafiók az útvonalban — a védelem a Google oldalán
áll, nem ígéreten.

### Külső hozzáférés-kérés menete
Ami a Bezzegh cég fiókjaihoz tartozik (Google, NAV), **Donátnak nincs joga
hozzá — az Milán területe.** Kérje Milántól, **üzleti nyelven, szakszó
nélkül** (MCC, API, token, `.env` NEM mehet bele). A kérés mondja ki, hogy
**csak olvasás**, és hogy ezt a szolgáltató garantálja. Titok soha nem megy
emailben vagy chatben — telefonos diktálás.

### Egyéb nyitott tételek
- **Webshop-platform döntés (issue #76):** két ELLENTMONDÓ elemzés (xBoss:
  maradjon OpenCart / Nagy Projekt: WooCommerce). Tisztázandó: (1) mi történik
  ma a webshopos megrendelésekkel; (2) van-e az RS3-nak támogatott integrációs
  felülete a szállítótól. Kifelé nem kell RS3-API, befelé (megrendelés → ERP)
  igen, és azt csak a szállító adhatja.
- Milán laptopja: `scripts/milan-laptop-setup.sh` (linger, vmIdleTimeout,
  Restart=always).
- Dashboard Terminal mint hitelesített forrás (xBoss PR-kérés 2026-09-06).
- Bozó Judit számlamásolat: piszkozat vár Donátra (Gmail piszkozatok).
- FIFO a vasanyagnál (`mv_termek_fedezet`): Milán dönt.

---

## MUNKAMEGOSZTÁS (2026-09-07-i állapot)

- **xBoss** (Telegram, Donát privát csatornája): minden, ami parancsot
  igényel a desktopon vagy a tebez-prodon; a **marveen kódbázis az ő
  területe**. Sávok: `docs/AGENT-SZEREPOSZTAS.md` (zöld = csinálja; sárga =
  előre leírja, 5 perc; piros = csak Donát: secret, sudo, DB-írás,
  jogosultság, pénz).
- **Milán ügynöke** (`@milan_tebez_bot`, Milán laptopja): **a tebez Nagy
  Projektet Ő fejleszti**, PR-t ő nyit. xBoss tebez-csapata **csak review-z és
  tesztel, saját implementációt nem indít** (2026-09-07).
- **A tebez-csoport Milán és az ügynöke munkaterülete. Donát NEM szól bele.**
- **Claude (Cowork, ez a chat)**: gondolkodás, xBoss javaslatainak
  ellenőrzése, puska, és amikor MAGA az xBoss áll.
- **Milán maga (nem az ügynöke)**: céges fiókok, jogosultságok. Neki Donát ír
  közvetlenül, **nem boton keresztül** — a `milan_tebez_bot` feladatvégző,
  nem üzenetközvetítő, xBoss pedig nem éri el.

### Nyugtázási szabály (2026-09-09)
xBoss **minden bejövő feladatra azonnal nyugtáz egy sorral**, mielőtt bármit
elkezd, és megírja, mit fog csinálni.

### "Rád vár" digest (2026-09-09, kibővítve 2026-09-10)
- xBoss **reggel és 16:00-kor** külön üzenetet küld: minden nyitott, Donátra
  váró tétel, egy sor per tétel. Három napnál régebbi tétel jelölve.
- **KÉT BLOKK, 2026-09-10 óta:**
  - **DÖNTÉS VÁR RÁD** = `donat-dontes` címke. Olyan döntés, amit csak Donát hozhat meg.
  - **MUNKA VÁR RÁD** = `donat-munka` címke. Olyan lépés, amit csak Donát tud
    elvégezni: böngészős engedélyezés, jelszó beírása, kattintás a Google vagy a
    NAV felületén, PR jóváhagyás.
- **Miért kellett a második blokk.** A #86-nál a döntés megszületett, a
  `donat-dontes` címke lekerült, de a végrehajtás egy része (szkript beillesztése,
  bukás-teszt) Donátnál maradt, és így kiesett volna a listából. Pont az a helyzet,
  ami miatt a digest egyáltalán létezik.
- **Egy tétel csak akkor számít rá várónak, ha valamelyik címkével GitHub issue
  van róla.** Ami csak Telegramon hangzott el, az nem tétel.
- **A munka-blokknál kötelező a KÖVETKEZŐ KONKRÉT LÉPÉS**, nem elég a téma. Az
  issue törzsébe `[KOVETKEZO: ...]` alakban kerül, és a digest külön sorban kiírja.
  Ha hiányzik, a digest ezt hangosan jelzi, nem hallgatja el.
- Egy issue, amin **mindkét címke** rajta van, csak a döntés-blokkban jelenik meg:
  amíg a döntés nincs meg, a munka úgysem indulhat.
- **A digest elavulhat.** Ha a chatben döntés születik, a hozzá tartozó
  issue-t is javítani kell, különben másnap reggel a régi állapot jön vissza.
- **A GitHub címke-indexe pár másodpercet késik.** Címke fel- vagy levétele után
  azonnal futtatva a digest még a régi állapotot mutatja. Futtasd újra, mielőtt
  hibát jelentesz.

### Csatorna-hitelesség (provenance-kapu)
- Hiteles = Telegram, Donát chat_id-jéről. Dashboard Terminal = "boríték
  nélküli": kérdés jó, jóváhagyást/jogosultságot/secretet nem hajt végre.
- **Ágens sosem ad magának hozzáférést.**

### Telegram-korlátok
- **Bot nem látja másik bot üzenetét** → agens→agens átadás PR-leírásban vagy
  GitHub issue-ban. Címkék: `donat-dontes`, `xboss`.
- Régi üzeneteket a Bot API nem ad vissza → bemásolás a Cowork-chatbe.
- Csoport-id: szupercsoport `t.me/c/<szám>` → `-100<szám>`; sima csoport →
  címsor `#-4…`. Ne alakítsd szupercsoporttá.
- Ha egy csoportüzenetre **mindkét bot** válaszol, a hostnév dönt:
  `DESKTOP-QJ6KIP4`/`marveen-src` = Milán gépe, nem xBoss.
- **Az „elküldtem" nem bizonyíték.** 2026-09-10-én xBoss úgy hitte, kiadott egy
  parancsot; az soha nem ért át, és negyed óra ment el kölcsönös várakozással.
  Ha egy üzenetben nincs futtatható parancs, mondd ki, hogy nincs mit kiadni.

---

## GOOGLE OAUTH (Gmail / Naptár / Drive MCP) — 2026-09-07-én VÉGLEG megoldva

Google Cloud projekt **gmail-1957**, app **Donat MCP**, Donát fiókja.
`gmail` → `@gongrzhe/server-gmail-autoauth-mcp` (`~/.gmail-mcp/credentials.json`),
`google-calendar` → `@cocal/google-calendar-mcp` (`GOOGLE_OAUTH_CREDENTIALS` env),
`google-drive` → `@piotr-agier/google-drive-mcp` (env a `~/.claude.json`-ból).

**Miért bukott el ~100-szor:**
1. Az app **Testing** módban volt → 7 nap után minden refresh token eldobva.
2. Már engedélyezett appnál a Google újra-authkor nem ad refresh tokent.
3. Rossz sorrend: visszavonás/auth a Publish előtt.

**Végleges eljárás (ebben a sorrendben):**
1. `console.cloud.google.com` → gmail-1957 → **Google Auth Platform** →
   **Audience** → Publish app. Ha szürke: **Branding** kötelezők (App name,
   support email, developer contact, home page + privacy + ToS
   `https://zivtool.com`, `/privacy`, `/terms`, Authorised domain
   `zivtool.com` **séma nélkül**). Save → Publish app → "In production".
2. `myaccount.google.com/permissions` → Donat MCP → **Delete all**.
3. Desktop WSL, sorban:
   `npx @gongrzhe/server-gmail-autoauth-mcp auth && grep -c refresh_token ~/.gmail-mcp/credentials.json` → `1`
   `export GOOGLE_OAUTH_CREDENTIALS=$(grep -o '"GOOGLE_OAUTH_CREDENTIALS": *"[^"]*"' ~/.claude.json | head -1 | cut -d'"' -f4) && npx @cocal/google-calendar-mcp auth`
   `python3 -c "import json,os;v=json.load(open(os.path.expanduser('~/.claude.json')))['mcpServers']['google-drive'].get('env',{});[print(f'export {k}=\"{x}\"') for k,x in v.items()]" > /tmp/drive.env && source /tmp/drive.env && npx -y @piotr-agier/google-drive-mcp auth`
4. xBoss futó sessionje a régi tokent tartja memóriában → **tiszta
   újraindulás** (`systemctl --user restart jezus-channels`), NEM `/mcp` menü.
5. Ellenőrzés: élő hívás mindhármon.

**Kinek a postafiókja:** Donát levelei NEM mennek Milán laptopjára.

### Böngészős buktatók a Google-felületeken (2026-09-10)
- **Többfiókos böngésző.** A `/u/0/` az elsőként bejelentkezett fiók, az
  Donáté. A szolgálati fiók más index (nála `/u/2/`), és a `sheets.new` a
  rossz fiókba hoz létre táblát. Böngészős lépésnél MINDIG írd oda az
  indexet, és ellenőriztesd az avatart.
- **Az Apps Script nem kezeli a többfiókos állapotot.** A
  `script.google.com/accounts?authuser=2` mindig „nem sikerült megnyitni a
  fájlt" hibára fut. Megoldás: **privát ablak, kizárólag a szolgálati
  fiókkal** bejelentkezve.
- **Ha a Services melletti + gomb nem nyílik meg:** Project Settings →
  „Show 'appsscript.json' manifest file in editor", és a szolgáltatást kézzel
  a manifestbe (`dependencies.enabledAdvancedServices`, pl. `AnalyticsData` /
  `analyticsdata` / `v1beta`). Ugyanaz az eredmény.
- **A meghívó Accept linkje 403-at ad többfiókos böngészőben.** Ugyanaz a
  minta, mint az Apps Scriptnél: a link az elsőként bejelentkezett fiókkal
  próbál elfogadni. Privát ablak, kizárólag a szolgálati fiókkal.
- **A meghívó levél a Kukába kerülhet.** A Merchant Center meghívója
  2026-09-10-én oda ment. Ha nincs meg a levél, a Kukában keresd, `Restore`,
  és csak utána kattints az Accept linkre. Ne kérj új meghívót elsőre.
- Jogszint-ellenőrzés: GA4 → Adminisztrálás → Tulajdon-hozzáférés kezelése;
  Ads → Admin → Access and security → **Users** fül (a Summary fül csak
  biztonsági feladatokat mutat).

### Szolgálati fiókhoz NE ingyenes Gmail (2026-09-10-en megfizetve)

A Google 2026-09-10-en felfuggesztette a `xbossbezzegh@gmail.com` szolgalati fiokot.
A fellebbezes sikeres volt, 09-11-en visszaadtak, de a tanulsag marad.

**Az ok nem egyetlen muvelet volt, hanem a suruseg.** Egy friss, ingyenes Gmail, ami
UGYANAZNAP tobb API-hozzaferest es tobb OAuth-hitelesitest kap, kiveri a Google
automatikus szurojet. A fiok maga szabalyos volt, a mintazat nem.

**A helyes ut: ceges Workspace-fiok sajat domainen.** Ez cegdontes es penzbe kerul,
ezert nem magatol ertetodo, de a kovetkezo hasonlo esetnel EZZEL kezdjunk, ne egy
ingyenes Gmaillel. Donat a fellebbezesben ra is kerdezett, hogy ez-e a helyes ut;
ha erkezik ra valasz, ide kerul.

**Amig maradunk ingyenes fiokon, oszd szet idoben, es hagyj kihuto idot.** A
visszaallitas utan igy mentunk: a fiokhoz tobb NAPIG hozza sem nyultunk (09-11 pentektol
09-14 hetfoig), utana kulon lepesekben egy olvasas-proba, csak szukseg eseten
ujrahitelesites, es csak azutan, mas napon az Apps Script. Egy nap egy uj hozzaferes,
nem harom, es a visszaallitas utani elso napokban inkabb nulla.

**Es meg valami, ami ebbol kovetkezik:** ujrahitelesites elott MINDIG probalj egy
olvasast a meglevo tokennel. Lehet, hogy tulelte a felfuggesztest, es akkor a
hitelesitesi kor nemcsak felesleges, hanem pont az a fajta OAuth-esemeny, ami a
tiltast kivaltotta.

---

## GITHUB-FIÓKOK ÉS KULCSOK (tebez)

| Fiók / kulcs | Kié | Mire |
|---|---|---|
| `latnaborsodi` | Donát | admin; **egyetlen code owner** |
| `kendre62` | Kovács Endre | collaborator |
| `milan-ugynoke-bot` | Milán ügynöke | write 09-06 óta; commit-szerző `Milan (agent)`; tokenjén 09-08 óta **Actions: Read** |
| `tebez-agent-bot` | saját, 08-09 | privát `synonyms` gem CI-letöltése; deploy-kulcsra áll át → törölhető |
| synonyms deploy-kulcsok | prod, mate, laptop, CI | gem letöltés SSH-val, read-only |
| hiánycikk SSH-wrapper | Milán ügynöke | `command="/usr/local/bin/tebez-report-wrapper.sh"` |
| `tebez-bot` kulcs (09-08) | Milán ügynöke | `restrict,command="…/scripts/tebez-bot-wrapper.sh"` — `status`, `logtail`, `rs3-sync`, `psql-select`; más REJECT, napló `/var/log/tebez-bot-wrapper.log` |

### Ki fér SSH-val a tebez-prodhoz (mérve 2026-09-11)

**Egyetlen interaktív fiók: `deploy`**, és annak `(ALL) NOPASSWD: ALL` a sudo joga.
Vagyis aki bármelyik kulccsal belép, az jelszó nélkül root. A 600-as fájljogosultság
ezért nem véd titkot a gépen: nincs más felhasználó, akitől védene.

Hat kulcs van a `deploy` `authorized_keys`-ében:

| kulcs | kié | korlát |
|---|---|---|
| `user@DESKTOP-QNJ69NN` (RSA + ed25519) | ez a desktop (xBoss/Donát) | **nincs** |
| `ond-worker` | **a mate worker gép** (régi nevén Ond), 5.189.187.17 | **nincs** |
| `github-actions-deploy-tebez` | GitHub Actions deploy workflow | **nincs** |
| `tebez-report-restricted` | hiánycikk-riport | `command=/usr/local/bin/tebez-report-wrapper.sh` |
| `milan-ugynoke tebez-bot-wrapper` | Milán ügynöke | `command=…/scripts/tebez-bot-wrapper.sh` |

**`ond-worker` = mate worker.** Ezt 2026-09-11-en egyszer már kinyomoztam, ne kelljen
megint: a név sehol nem szerepel a repókban. Donát azonosította a
`docs/sessions/SESSION_267.md` és `SESSION_287.md` alapján (a mate worker régi neve Ond).
**Mire használja:** kizárólag `git fetch`-re deploy közben. A deploy workflow a mate-et
NEM GitHubról, hanem a tebez szerverről húzatja, tehát a mate `origin`-ja
`deploy@75.119.137.104`. Mérve: a megőrzött naplók mind a 12 belépése másodpercekre esik
egy Deploy futástól, kivétel nélkül.

**Következmény, amit érdemes fejben tartani:** a GitHub Actions kulcsa korlátlan, tehát
egy `.github/workflows` alatti változtatás root-hozzáférést ér a szerveren. Ma ezt
egyedül a CODEOWNERS zárja, és az **csak az ügynökre fog, a Donát fiókjáról dolgozó
xBossra nem** (mérve 2026-09-11: a tulajdonos saját PR-jére a GitHub nem kér
kód-tulajdonosi jóváhagyást).

---

## PARANCSOK ÁTADÁSA DONÁTNAK (kötelező forma)

**EGY üzenet = EGY egysoros parancs + MELYIK GÉPEN + mit várunk.**
- Több parancs → EGY sor `&&`-del, végén `&& echo KESZ`. Kettőnél több
  lépés → szkript `scripts/` alá, PR-ben.
- Titkot SOHA ne kérj vissza; `.env` csak `| cut -c1-30`.
- Botnak szóló üzenetet **szó szerint**, idézetként; **soha placeholder** —
  2026-09-10-én egy `[ide másold be…]` helyőrző szó szerint ment át, és
  értelmetlen üzenetet okozott. Kész szöveget adj.
- Böngészős lépésnél írd le, hol kattint, és kérj képernyőt.
- Ha Donát sürget: a legrövidebb utat mondd, ne magyarázz.
- **Időbecslést csak mérésből mondj.** A „tíz perc" 2026-09-10-én másfél óra
  lett, mert a böngészős buktatókat senki nem mérte fel.

---

## ELŐSZÖR: melyik GÉPEN vagy?

| Hely | Prompt | Install | Állapot |
|---|---|---|---|
| Donát desktop, `Ubuntu-24.04` | `donat@desktop` | `~/marveen` + `~/tebez` | **FUT** — produkció, xBoss (`jezus`) |
| Donát desktop, `Ubuntu` | `donat@DESKTOP-QNJ69NN` | `~/marveen-src` | **LEÁLLÍTVA 08-30 óta**, ne indítsd (409) |
| **Milán laptopja** | `milan-ugynoke@laptop` (host `DESKTOP-QJ6KIP4`) | `marveen-src`, unit `milan-channels` | FUT; RustDesk → Windows Terminal → `wsl` |
| tebez-prod | `deploy@contabo` | `/var/www/tebez` | FUT |

Hibakeresés előtt: `echo $WSL_DISTRO_NAME; hostname; ls -d ~/marveen ~/marveen-src ~/tebez 2>&1`

**A prompt eleje minden kimeneten megmutatja, hol futott a parancs.**

**Terminál:** a régi Windows konzolban a tmux/Claude rajzjelei elromlanak
(`─` → `a`, `❯` → `É`) — a Linux-oldal rendben van, a **megjelenítő** hibás.
Megoldás: **Windows Terminal** (Win+R → `wt.exe`).

---

## DESKTOP-produkció (xBoss) — `Ubuntu-24.04`

tmux: `jezus-channels`, `agent-*`, `jezus-worker`, `jezus-worker-fast`.
Dashboard http://localhost:3420, Bearer `~/marveen/store/.dashboard-token`.
Belépés: user `donat`, jelszó `~/marveen/store/.dashboard-password-donat`.

### Dashboard Terminal (Claude ír xBossnak)
Csapat → xBoss → Terminal. `Terminal input` mező → `type` egysoros szöveg →
**`\r` karakter a `type`-pal** (`key Enter` nem megy). Eleje:
`Donát (Claude-on át, dashboard Terminal): …`.

### Aliasok
`flotta`, `xboss`, `flottastart <tebez|tourguide|kinai|mind>`, `mup`,
`tebez` (= `ssh -o ServerAliveInterval=30 deploy@75.119.137.104`).
Rutin: `xboss` → `flottastart tebez` → `flotta`. Napindító 07:30, triázs 07:00.

### A puska HTML-változata
`scripts/marveen-puska-generate.py` félóránként újragenerálja a
`C:\Users\user\Desktop\marveen-puska.html`-t EBBŐL a SKILL.md-ből. Stílus:
`templates/marveen-puska.css` és `templates/marveen-puska.html.tpl`.
Ütemezett feladat: `marveen-puska`, `type=command`. **Ami csak a HTML-ben van
és nem itt, azt a következő generálás elveszíti — mindent ide írj.**

### Claude-login a desktopon
Új terminálablak (NEM tmux): `claude` → `/login` → 1. Claude account with
subscription → böngésző → `/exit`. Windows- és WSL-login külön.

---

## MILÁN ÜGYNÖKE — Milán laptopján

Van: GitHub write + Actions: Read (`gh run view --log-failed` — BLOCKED
PR-nél ELŐSZÖR; a "BLOCKED" gyakran PIROS check), hiánycikk SSH-wrapper,
`tebez-bot-wrapper.sh`. Nincs: shell a szerveren, `sudo`, env, DB-írás.

- **Él-e:** csoportban `@milan_tebez_bot ping — egy szóval válaszolj` → "pong".
- **Dolgozott-e:** `git log --all --author="Milan (agent)" --since=today --format='%ci %h %s'`
- **Csatorna némán leszakad (RUTIN):** RustDesk → `wsl`:
  `systemctl --user stop milan-channels && tmux kill-session -t milan-channels 2>/dev/null; systemctl --user start milan-channels && sleep 45 && tmux capture-pane -pt milan-channels | tail -4`
- `/login`, `/usage` Milán gépén: ÚJ terminálablakban, SOHA a bot tmux-ablakában.

---

## KERESZTDISZTRÓ / TITKOK

**Jelszót tartalmazó parancsot SOHA ne parancssorból (2026-09-11-en megfizetve).**
A `sudo` minden parancsot teljes szöveggel naplóz az `auth.log`-ba, tehát egy
`psql -c "ALTER ROLE ... PASSWORD '...'"` hívás után a jelszó ott ül nyílt szövegben,
hetekig, a naplórotáció végéig. Így találtam meg a `tebez_bot_ro` jelszavát egy egy
hónapos naplóban. Ez a fajta szivárgás nem a kódban van, hanem a szokásban.

Helyette:
- **jelszóváltás:** `psql` `\password <szerep>` -- interaktív, nem kerül se a naplóba,
  se a shell-előzménybe. Nem-interaktív futtatásnál a két új jelszót szabványos
  bemeneten add át (`cat pw | ssh ... 'sudo -u postgres psql -c "\password szerep"'`),
  így sem a parancssorba, sem a naplóba nem kerül bele.
- **utána a `~/.pgpass`** is frissítendő a szerveren, különben a bot-wrapper
  `psql-select` ága némán eltörik. A frissítést is szabványos bemenetről csináld, ne
  parancssori argumentummal, és utána `chmod 600`.
- **ellenőrzés:** kapcsolódj a `.pgpass`-on át (jelszó megadása nélkül), és futtasd le a
  wrapper mindhárom lekérdezését.

Ha egy jelszó mégis bekerült a naplóba, a napló törlése nem megoldás (rotált és tömörített
példányok is vannak): **a jelszót kell cserélni.**

**A `PGPASSWORD` sem biztonságos, és nem csak az előzmény miatt.** A környezeti változóval
indított parancs **futás közben látszik a folyamatlistában** (`ps`, `/proc/<pid>/environ`),
tehát a gépen bárki kiolvashatja, amíg fut. Nem elég annyit mondani, hogy "nem került a
naplóba". Ellenőrzésre is a `~/.pgpass` a helyes út, jelszó megadása nélkül.
PowerShellből `wsl.exe -d Ubuntu -e grep -i bot_token /home/donat/marveen-src/.env`.
Titkot csonkolva: `| cut -c1-30`. Kikerült titok: BotFather `/revoke` /
`ALTER ROLE … PASSWORD`, `.env`/`.pgpass`, restart.

---

## Tipikus hibák

### xBoss néma — HÁROM lehetőség, ne ugorj a halálra
2026-09-09-én egy nap alatt mindhárom előfordult.

**A három ok:**
1. **Tényleg nem fut / nem kapta meg** az üzenetet.
2. **Él, csak nem nyugtázott** — dolgozik némán.
3. **Az MCP-cső elszakadt a sessionről** — él és dolgozik, de semmi nem tud
   kimenni. A sessionben kiadott **`/mcp`** hozza vissza.

**Diagnosztika, desktop WSL-ben, egyesével:**

1. `tmux capture-pane -pt jezus-channels | tail -6`
   - Üres `❯` = ÉL, csak nem kapta meg az üzenetet.
   - "Brewed / Thinking / Churned / Cooked" = **dolgozik** → nem halott.
   - Parkolt szöveg a `❯` sornál = hiányzik egy Enter →
     `tmux send-keys -t jezus-channels Enter`
2. `tmux capture-pane -pt jezus-channels -S -80 | grep -iE "telegram|409|token|error|poll" | tail -10`
   Üres = nincs hiba, nem szállt el.
3. `echo "unit: $(systemctl --user is-active jezus-channels)"; ps aux | grep -E "[c]laude --continue" | cut -c1-110`
   Nézd a `claude --continue` INDULÁSI IDEJÉT. **Ha az üzeneted a respawn
   körül ment, elveszett.** Küldd újra.
4. **Ha a session dolgozik, de semmi nem jön ki: az MCP-cső szakadt el.**
   Feloldás: `/mcp` a sessionben.
5. Ha egyik sem: tiszta újraindítás, majd újra ping.
   `systemctl --user stop jezus-channels && tmux kill-session -t jezus-channels 2>/dev/null; systemctl --user start jezus-channels && sleep 45 && tmux capture-pane -pt jezus-channels | tail -4`

**Gyors kizárás:** ha a napi digest megérkezett Telegramon, a kifelé menő cső
él — akkor a 3. ok kiesik.

**Ami NEM bizonyíték:**
- A friss puska-HTML az asztalon — az `type=command` feladat agent nélkül is fut.
- A nyugtázás hiánya.

### Agent-létrehozás kiüti a futó agenteket
`tmux send-keys -t agent-<nev> Enter` egyesével.

### Agent némán áll
Beragadt menü → `Escape`, `Enter`; ismétlődő jóváhagyás → `add-yess`.

### Stuck-input fagyás / óránkénti (:52) hard restart
#1177 + #1178 (v1.36.0). A :52-es respawn tétlenül ártalmatlan.

### jezus-worker-fast "Not logged in"
Saját `.claude-config` credentials üresre cserélődik restartkor → globális
configgal fusson.

### 401 login-javítás (flotta tokenje)
`~/.claude/settings.json` `env.CLAUDE_CODE_OAUTH_TOKEN`: `claude setup-token` →
```bash
python3 - <<'PY'
import json, os
p = os.path.expanduser('~/.claude/settings.json')
d = json.load(open(p)) if os.path.exists(p) else {}
d.setdefault('env', {})['CLAUDE_CODE_OAUTH_TOKEN'] = os.environ['CLAUDE_CODE_OAUTH_TOKEN']
json.dump(d, open(p,'w'), indent=2); print('OK')
PY
```
→ `xboss` → `claude -p "ping"`.

### "channels failed" / 409
Ugyanaz a bot-token máshol pollozik (desktop `Ubuntu` disztró!).

### Telegram-válasz nem jön
`~/.claude/channels/telegram/access.json` (`allowlist`, `groups`).
`ALLOWED_CHAT_ID` a `.env`-ben.

### Dashboard Unauthorized / nem tölt
Üres Bearer (rossz disztró); böngészőben 401 → belépés. `mup` 1–2 percre leviszi.

### "Kimaradt ütemezés" / WSL nem indul
`.wslconfig` `vmIdleTimeout=-1`, `enable-linger donat`; `wsl --shutdown`;
`sc.exe query WSLService`/`vmcompute` RUNNING.

### `~/.claude.json` szerkesztése után
Újraindulás ELŐTT mérd meg, hogy a fájl ép-e és minden MCP-bejegyzés
megvan-e. Ha az újraindulás után derül ki, hogy hibás, egyszerre esik ki
minden kapcsolat. Szerkesztés előtt másolat.

---

## Marveen frissítése
Upstream `Szotasz/marveen` — csak Szotasz merge-el; addig xBoss a PR-ágat a
fork main-be merge-eli, majd `mup` (konfliktus: kód/lockfile/sablon/
upstream-skill `--theirs`, saját skill/doksi `--ours`). `~/marveen` MAGA a
futó telepítés.

**Az utolsó jó verzió jelölője a `dist/.built-commit`.** (NEM
`~/marveen-last-good.txt` — az nem létezik.) Az `update.sh` sikertelen
fordítás után `reset --hard`-dal visszaáll az abban álló commitra.
2026-09-08 óta ugyanezen a ponton kapu a ledger-tesztkészlet is.
Emberi szemnek: `cat ~/marveen/dist/.built-commit`.

---

## tebez-prod
`tebez` alias; belépés után MINDIG
`export PATH=$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH`.
DB olvasás `psql -h 127.0.0.1 -U tebez_bot_ro -d tebez_production -qtAc "..."`
(`.pgpass` csak 127.0.0.1); admin `cd /tmp && sudo -u postgres psql tebez_production -c "..."`;
RS3 szinkron `ruby lib/rs3/commerce_source.rb invoices --since 2022-01-01`
(napi 03:00 UTC); hosszú futás `nohup … > /tmp/x.log 2>&1 &`; `sudo systemctl
restart tebez-queue`; logok `web/log/rs3_commerce_sync_*.log`.

**Postgres szerepek:** `tebez_web` = az alkalmazásé. `tebez_bot_ro` = csak
`SELECT` (`commerce_invoices`, `commerce_supplier_invoices`,
`commerce_supplier_invoice_lines`, `commerce_products`,
`solid_queue_recurring_executions`). Új lekérdezéshez új `GRANT`.

### RS3 `szamlafej.fizetve` szótár
I = kifizetve; N = kiállított, nem fizetett; Ö = **szállítólevél**
(dokumentumtípus, sosem kintlévőség); S/s sztornó pár; T túlfizetés.
Forgalmi riport: nyitott Ö beleszámít; pénzügyi: csak I, fizmód szerint.

### FIFO
A riportok az RS3 `fifoatlagar` mezőjét használják nyersen, 2026-09-07 óta
gyanús. A rétegeket az ELEJÉTŐL le kell játszani — az eladás-lekérdezésbe
dátumszűrés nem tehető, csak az átlagolás szűkíthető. **Különben a régi,
olcsó rétegek fogyasztatlanul maradnak, és a számolt önköltség rendszeresen
hibás lesz.**

### Deploy — ha piros
`git log --oneline -1`, `systemctl show -p ActiveEnterTimestamp tebez tebez-queue tebez-taskrunner`,
`stat -c '%y' .git/FETCH_HEAD`; ha kell `sudo systemctl restart tebez tebez-taskrunner`.
Ha a pull ideje KORÁBBI a `tebez` restartjánál, a lemezen lévő és a futó kód
együtt van. A `tebez-queue` csak `web/app/jobs/` változásra indul újra.

---

## Git-fegyelem (~/tebez)
Ágon, PR + auto-merge, main védett, deploy csak `deploy.yml`, éles DB
agenteknek csak olvasás. `docs/AGENT-SZEREPOSZTAS.md`.

**CODEOWNERS-kapu (2026-09-08):** a `main` védelme **ruleset** (`protect-main`,
Settings → Rulesets — a klasszikus Branches oldal ezért üres), benne
"Require review from Code Owners" bekapcsolva. A `.github/CODEOWNERS`-ben
felsorolt útvonalakon (FIFO/önköltség, `lib/suppliers/pricing/`, a döntési
riportok, Merchant feed, `web/db/migrate/`, `schema.rb`, `.github/workflows/`,
`tebez-bot-wrapper.sh`) a PR csak Donát jóváhagyásával olvad be.

**CI-tanulság (2026-09-04):** a `| tee ci-*.log` a GitHub Actions
alapértelmezett `bash -e` shelljében ELNYELI a bukást. Ezért áll a
`ci.yml`-ben `defaults.run.shell: bash` (`-eo pipefail`).

**A visszatérő minta és a szabály belőle:** a védelem *látszik*, ezért senki
nem nézi meg újra. **Minden új kapunál kötelező egy szándékos bukás-teszt,
mielőtt késznek mondjuk.** A bukás-teszt azt mérje, ami elromolhat: a
szolgálati fiók bekötésénél nem az volt a kérdés, hogy az új kapcsolat megy-e,
hanem hogy Donát régi három kapcsolata sértetlen maradt-e.

**Kódátvétel agenstől: olvasd át, mielőtt lefut.** 2026-09-10-én egy
GA4-export szkriptben két hiba volt, amit csak átolvasás fogott meg: a Sheets
a beírt dátumszöveget Date értékké alakítja, ezért a duplikáció-védelem soha
nem talált egyezést; és a „naponkénti top 100" valójában a teljes ablak
globális top listája volt. Mindkettő csendben rontotta volna az adatot.

**Jóváhagyott Nagy Projekt (#71, Milán ügynöke csinálja):** központi adatréteg
→ Pénzügy menü → visszáru mini CRM → Logisztika menü. Külön ág, PR, csak
additív migráció. 09-08 óta ide tartozik a Merchant feed / RS3 XML menüpont is.

---

## kinai-marketing agent
Réka marketingügynöke, `marketer-isolated`. `flottastart kinai`. Nincs a
`mind` ágban. Outbox-mintán kér jóváhagyást.

---

## Aliasok újratelepítése
```bash
cat >> ~/.bashrc <<'EOF'
alias flotta='curl -s -H "Authorization: Bearer $(cat ~/marveen/store/.dashboard-token)" http://localhost:3420/api/agents | python3 ~/flotta.py'
alias xboss='bash ~/.claude/skills/ejjeli-mod/scripts/start-marveen.sh && sleep 8 && curl -s -o /dev/null -w "Dashboard HTTP: %{http_code}\n" http://localhost:3420/'
alias flottastart='bash ~/marveen/flotta-start.sh'
alias mup='bash ~/marveen/sync-upstream.sh'
alias tebez='ssh -o ServerAliveInterval=30 deploy@75.119.137.104'
EOF
source ~/.bashrc
```

---

## Nyelvi szabály
Donáttal magyarul, tömören. Parancsok, kód angolul.
**Egy üzenet = egy egysoros parancs + melyik gépen + mit várunk.**

