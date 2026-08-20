# 💭 Dream Engine — 2026-08-20 02:08

## 💡 Skill-javaslatok
- **Heartbeat-reflexió küszöb újragondolása** (flotta-szintű, folyamat-javaslat): a memoria-heartbeat "A = 5+ tool-hívás → KÖTELEZŐ skill-akció" szabálya rutin ütemezett futásokra (dream-engine, ORKUTYA, kanban-audit) is ráugrik, így ezek minden alkalommal csak egy "skip-skill" memóriát termelnek. Ez ma a 3. egymást követő éjszaka (08-18, 08-19, 08-20), tehát a saját 08-19-es jegyzet feltétele teljesült. Javaslat: az A-kritérium zárja ki azokat a futásokat, amelyek egy dokumentált scheduled-task saját eljárását hajtják végre. Ez a memoria-heartbeat task-config szerkesztése, ezért Donat döntésére hagyom.
- A tegnapi valódi tanulságok (telegram MCP kiesés → Bot API fallback; VS Code-os duplikált plugin-betöltés) már futás közben skillbe kerültek (`telegram-reply-chatid`, `channel-plugin-duplicate-socket`), nincs további skillesíthető minta.

## 🧹 Memória-egészség
106 / 106 vektorizált (100%). 0 antikvált hot-tier (nincs 7 napnál régebben nem érintett hot memória). 5 duplikált content-csoport van, de mindegyik már rendezett állapot: csoportonként legfeljebb egy warm példány maradt, a többi cold — teendő nincs. Áthelyezés nem történt.

## 🎯 Top-3 holnapi javaslat
1. **tebez (railsdev)**: `0535741d` Unified XML szűkítés + `71f88c76` Mapei MAP_ prefix — a két egyetlen `high` prioritású, nem-tourguide kártya, mindkettő 07-21 óta mozdulatlan `planned`-ben, miközben a Mapei/unified szál volt a nyár utolsó aktív adat-témája.
2. **tourguide (janos/Évi)**: `39e82860` + `8f496923` városleírás-review és célnyelvi content — `waiting` státuszban 06-04 óta, kizárólag Évi inputjára várnak. Egy rövid emlékeztető feloldhatja, vagy le kell zárni a kártyákat, ha a szál elhalt.
3. **flotta (marveen)**: a 9 db "Modell-váltás" kártya (`23be3767` … `69c0e689`) 07-15 óta `planned` — az agentek időközben `claude-sonnet-5` / `claude-opus-4-7` modelleken futnak, tehát a kártyák vagy elavultak, vagy egy konkrét célmodell hiányzik belőlük. Érdemes egyben lezárni vagy pontosítani.

## 🌐 External opportunity
- Skip — heti limit. Az utolsó külső körre 2026-08-17 02:09-kor került sor (`store/external-ops-last-run`), a 7 napos ablak még nem telt le.

## 🛠 Skill-flotta health
- Nem megítélhető: a `skill_usage` tábla üres (0 sor), így nincs használati adat az antikváltság méréséhez. 19 nem-pinned skill van, mind projekt-specifikus és a legutóbbi hetekben született vagy patchelve lett — törlést egyik esetében sem javaslok mérés nélkül.

## ⚠️ Hibák
- `skill_usage` tábla üres → Bucket 5 nem mérhető (ismétlődő megfigyelés, 08-17 óta változatlan).
- `daily_logs` az elmúlt 7 napban mindössze 2 bejegyzést tartalmaz (mindkettő 08-19, telegram-csatorna incidens), így a Bucket 3 súlyozása kanban-adatból és a kártyák korából származik, nem aktivitás-mérésből.

*Marveen, 02:09 — most már alszom én is.*
