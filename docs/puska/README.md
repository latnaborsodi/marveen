# Puska-forrás mentés

## Miért van itt ez a fájl

A `marveen-uzemeltetes` puska forrása egy **Cowork-oldali skill**
(`skillId: skill_015NruWx6KmWVEX4iDFnirHV`), aminek a gépen csak a helyi
megvalósulása él:

```
~/AppData/Roaming/Claude/local-agent-mode-sessions/skills-plugin/<plugin-uuid>/<session-uuid>/skills/marveen-uzemeltetes/SKILL.md
```

**Ez a fájl NEM verziókövetett és NEM a mérvadó példány.** A `manifest.json` a skillhez
saját, szerver-oldali `updatedAt` időbélyeget tart. Ha a kliens újraszinkronizálja a
tartalmat (plugin-frissítés, vagy egy mentés a Cowork-oldali szerkesztőből), akkor a
**szerver változata felülírja a lemezen lévőt**, és minden helyben tett szerkesztés
nyomtalanul eltűnik.

Két ember írja ugyanazt a fájlt: Donát a Cowork-oldali mentéssel, xBoss közvetlenül a
lemezen. A kettő nem lát rá egymásra, tehát a későbbi felülírja a korábbit, figyelmeztetés
nélkül.

## Mi ez a másolat

A lemezen lévő SKILL.md pillanatképe, hogy egy szinkron ne vihesse el a munkát. Ha a
helyi fájl kiürül vagy visszaugrik egy régebbi állapotra, innen visszaállítható:

```bash
SRC=$(ls -t /mnt/c/Users/user/AppData/Roaming/Claude/local-agent-mode-sessions/skills-plugin/*/*/skills/marveen-uzemeltetes/SKILL.md | head -1)
cp docs/puska/marveen-uzemeltetes-SKILL.md "$SRC"
python3 scripts/marveen-puska-generate.py
```

## Amit mértem (2026-09-11)

- **Egyetlen példány van a lemezen**, nincs második, szinkronizált másolat.
- **A manifest frissítése önmagában NEM írja felül a SKILL.md-t**: a `manifest.json`
  11:48-kor újraíródott, a 09:44 és 10:43 közötti szerkesztéseim utána is megvoltak.
- **A szerver viszont régebbi állapotot ismer**: a manifest szerint a skill
  `updatedAt` értéke `2026-09-10T08:26:57Z`, vagyis a mai (09-11-i) kiegészítéseimről
  a szerver nem tud. Egy tartalom-újraszinkron tehát visszaállítaná a tegnapi szöveget.
