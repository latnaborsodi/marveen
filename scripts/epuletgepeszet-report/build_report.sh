#!/bin/bash
# Epuletgepeszet napi hianycikk-jelentes -- osszeallito.
# Meg NEM kuld emailt es NEM ütemezett -- kezi futtatasra, ellenorzesre.
#
# Hasznalat: bash scripts/epuletgepeszet-report/build_report.sh [--skip-refresh]
#   --skip-refresh: kihagyja a scrape-single celzott frissitest (gyorsabb teszt,
#                   a mar meglevo (esetleg regebbi) beszallitoi adatot hasznalja)

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "$DIR/../.." && pwd)"
WORK="$INSTALL_DIR/store/epuletgepeszet-report"
mkdir -p "$WORK"

SKIP_REFRESH=""
[ "${1:-}" = "--skip-refresh" ] && SKIP_REFRESH="--skip-refresh"

echo "[1/5] Hianycikkek lekerdezese (RS3, kozvetlen) ..."
~/.rbenv/shims/ruby "$DIR/fetch_shortages.rb" --out "$WORK/shortages.json"

echo "[2/5] Hianycikk-lista kinyerese parositashoz ..."
python3 -c "
import json
d = json.load(open('$WORK/shortages.json'))
tkods = sorted({p['tkod'] for p in d['termek_osszesito']})
open('$WORK/tkods.txt','w',encoding='utf-8').write('\n'.join(tkods))
print(f'{len(tkods)} hianycikk')
"

echo "[3/5] Feltoltes tebez-prod-ra ..."
scp -i ~/.ssh/id_milan_servers -o BatchMode=yes -o ConnectTimeout=8 \
  "$DIR/refresh_and_match.rb" "$WORK/tkods.txt" \
  tebez-prod:/tmp/ >/dev/null

echo "[4/5] Parositas + celzott frissites tebez-prod-on (ez eltarthat par percig) ..."
ssh -i ~/.ssh/id_milan_servers -o BatchMode=yes -o ConnectTimeout=8 tebez-prod \
  "cd /var/www/tebez && set -a && source <(sed 's/\r\$//' .env) 2>/dev/null; set +a; \
   TEBEZ_DIR=/var/www/tebez /home/deploy/.rbenv/shims/ruby /tmp/refresh_and_match.rb \
     --tkods /tmp/tkods.txt --out /tmp/offers.json $SKIP_REFRESH" \
  > "$WORK/refresh.log" 2>&1 || { echo "HIBA, lasd $WORK/refresh.log"; tail -40 "$WORK/refresh.log"; exit 1; }
tail -20 "$WORK/refresh.log"

echo "[5/5] Eredmeny letoltese es osszefuzese ..."
scp -i ~/.ssh/id_milan_servers -o BatchMode=yes -o ConnectTimeout=8 \
  tebez-prod:/tmp/offers.json "$WORK/offers.json" >/dev/null

python3 "$DIR/merge_report.py" "$WORK/shortages.json" "$WORK/offers.json" "$WORK/report.json"

echo "Kesz: $WORK/report.json"
