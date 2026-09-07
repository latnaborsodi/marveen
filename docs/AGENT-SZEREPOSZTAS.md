# Ágens-szereposztás

Ez a dokumentum rögzíti, melyik ágens mit csinál, és főleg azt, hogy mit NEM.
Ha egy feladat érkezik és nem egyértelmű, kié, ez a fájl dönt.

Utolsó módosítás: 2026-09-07

## tebez

A tebez a Bezzegh Kft. adattárháza (Rails webapp + PostgreSQL, forrás az RS3).

| Szerep | Ki csinálja |
|---|---|
| Implementáció, fejlesztés, PR nyitás | Milán ügynöke (`milan-ugynoke-bot`) |
| PR review és tesztelés | a tebez csapat: `tebezboss`, `pydev`, `railsdev`, `architect`, `tester` |

**A tebez csapat saját implementációt NEM indít.** Nem ír fejlesztői kódot a
tebez repóba, nem nyit feature PR-t, nem vállal be fejlesztési tételt akkor sem,
ha közvetlenül kap rá kérést. A csapat kimenete review és teszt: hibalista,
reprodukciós lépés, javaslat, zöld vagy piros verdikt Milán ügynöke PR-jére.

Ide tartozik a négy jóváhagyott fejlesztés (tebez#71) és a FIFO ár kezelése is:
mindkettő Milán ügynökéé. (Donát döntése, 2026-09-07. Előtte a szereposztás nem
volt leírva, és emiatt egy FIFO-döntés tévesen a tebez csapathoz került
delegálva; a delegálást ugyanaznap visszavontuk.)

### Miért így

Két csapat ugyanabban a repóban párhuzamosan fejlesztve egymásra ír. A review és
teszt viszont pont akkor ér a legtöbbet, ha nem az írja, aki a kódot is írta.

## Tételátadás

Milán ügynöke és xBoss között a tételátadás **issue-n** megy a `latnaborsodi/tebez`
repóban, `xboss` címkével, nem csoportüzenetben (tebez#70, 2026-09-06). A Telegram
nem kézbesíti egyik bot üzenetét a másiknak, ezért a csoportba írt tétel sosem
érkezik meg.

## Marveen (ez a repó)

A marveen kódbázis xBoss (`jezus`) területe. A tebez csapat ide nem fejleszt.
Ha egy marveen-beli szkriptre érkezik kérés (például `scripts/usage-collect.py`),
az xBossé, akkor is, ha a kérés a tebez szálon jött.
