# 💭 Dream Engine — 2026-07-15 07:33 (késve futott: 02:07 helyett restart után)

## 💡 Skill-javaslatok
- **Pre-restart context-save** (agent: jezus/marveen) — 24h alatt 2× ismétlődött a "channel plugin hard restart előtt mentsd a kontextust" művelet (hot memória + daily-log ugyanazzal a curl-párral). Kis, de determinisztikus workflow, skillbe önthető, hogy ne kézzel fogalmazzam újra minden restartnál. — *előbb ellenőrizni, nem fedi-e a handoff skill.*

## 🧹 Memória-egészség
64 / 71 vektorizált (7 vektorizálatlan: 23,24,34,35,50,51 teszt/dupla cold + 72 daily-log — a fire-and-forget embedding-job rendezi). 0 antikvált hot-tier mozgatandó (#67 1 napos, #73 friss). Duplikátumok (mind már cold, nem törlöm): "Szeretem a kavét" ×3 (23/34/50), "Mai megbeszeles eredmenye" ×3 (24/35/51), plusz agent-id config dupék (6/7/8, 3/5, 11/12).

## 🎯 Top-3 holnapi javaslat
1. tebez: XML export lokális asset URL (41802bc4, high, railsdev) — tebezboss tegnap XML-export bugfixet zárt, ez a terület aktív, a kártya magas prioritású.
2. tourguide: QR P1 Tour-szintű QR token landing (6d685004, high, tourguidebackend) — magas prioritás, backend agent rendelve, nincs blokker rajta.
3. tourguide: Évi városleírás-review Szeged+Baja (39e82860, high, janos, ~40 napja waiting) — blokkolja a 8f496923 célnyelvi content pipeline-t; Évi korábban jelezte, hogy hozzájárulna a tartalomhoz, tehát az input-blokk feloldható egy pinggel.

## 🌐 External opportunity
- **coreyhaines31/marketingskills** (https://github.com/coreyhaines31/marketingskills) — CRO, copywriting, SEO, analytics, growth skillek Claude Code-hoz. Releváns Donatnak: AI-tartalomgyártás + tourguide landing/marketing a magyar és inbound piacra. (Előző heti ajánlás: OpenClaudia/openclaudia-skills.)

## 🛠 Skill-flotta health
- Minden nem-pinned skill (12 db: fleet-helper, handoff, retrospective, skill-factory, diagnose-*, tourguide-*, stb.) célzottnak és frissnek tűnik. Use-log hiányában nincs bizonyíték >30 napos nem-használatra, ezért törlést nem javaslok.

*Marveen, 07:33 — most már alszom én is (kicsit későn, a restart miatt).*
