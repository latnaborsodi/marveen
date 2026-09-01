#!/bin/bash
# Epuletgepeszet napi hianycikk-jelentes -- osszeallito.
# Ez a script csak a report.json-t allitja ossze (nem formaz emailt, nem kuld).
# Az email formazasa (format_email.py) es kuldese (mcp__email__send_email) a
# hivo felelossege -- kezi futtatasnal ellenorzesre, ütemezett futasnal (07:45,
# Donat + Milan jovahagyva 2026-08-28) a napi feladat promptjaban.
#
# 2026-08-30 utan a tebez-prod hozzaferes a korlatozott `tebez_report_restricted`
# kulcson keresztul megy (lasd tebez-prod-mate-ssh-ops skill) -- nincs tobbe scp/
# altalanos parancs, csak harom forced command: ures (teljes futas), skip-refresh,
# log-tail. A tkods lista STDIN-en megy be, az offers.json STDOUT-on jon vissza,
# a folyamatjelzo uzenetek STDERR-re irodnak a szerveren.
#
# Hasznalat: bash scripts/epuletgepeszet-report/build_report.sh [--skip-refresh]
#   --skip-refresh: kihagyja a scrape-single celzott frissitest (gyorsabb teszt,
#                   a mar meglevo (esetleg regebbi) beszallitoi adatot hasznalja)

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "$DIR/../.." && pwd)"
WORK="$INSTALL_DIR/store/epuletgepeszet-report"
mkdir -p "$WORK"

WRAPPER_CMD=""
[ "${1:-}" = "--skip-refresh" ] && WRAPPER_CMD="skip-refresh"

echo "[1/4] Hianycikkek lekerdezese (RS3, kozvetlen) ..."
~/.rbenv/shims/ruby "$DIR/fetch_shortages.rb" --out "$WORK/shortages.json"

echo "[2/4] Hianycikk-lista kinyerese parositashoz ..."
python3 -c "
import json
d = json.load(open('$WORK/shortages.json'))
tkods = sorted({p['tkod'] for p in d['termek_osszesito']})
open('$WORK/tkods.txt','w',encoding='utf-8').write('\n'.join(tkods))
print(f'{len(tkods)} hianycikk')
"

echo "[3/4] Parositas + celzott frissites tebez-prod-on, korlatozott kulcson (ez eltarthat par percig) ..."
ssh -o BatchMode=yes -o ConnectTimeout=8 tebez-prod $WRAPPER_CMD \
  < "$WORK/tkods.txt" > "$WORK/offers.json" 2> "$WORK/refresh.log" \
  || { echo "HIBA, lasd $WORK/refresh.log"; tail -40 "$WORK/refresh.log"; exit 1; }
tail -20 "$WORK/refresh.log"

echo "[4/4] Osszefuzes ..."
python3 "$DIR/merge_report.py" "$WORK/shortages.json" "$WORK/offers.json" "$WORK/report.json"

echo "Kesz: $WORK/report.json"
