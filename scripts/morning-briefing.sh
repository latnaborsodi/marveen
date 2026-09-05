#!/bin/bash
# Marveen - Reggeli napindító
# Trigger: systemd user timer (Linux, <agent>-morning.timer) vagy LaunchAgent
# (macOS), naponta 7:27-kor. Naponta legfeljebb egyszer küld (lásd a guardot).
#
# 2026-08-27: a küldés NEM a telegram plugin reply tooljával megy többé, hanem
# közvetlen Bot API hívással. Ok: a spawnolt session saját telegram plugin
# példányt indított, az pedig SIGTERM-elte a főágens server.ts-ét (a bot.pid-ben
# találtat), majd kilépéskor magával vitte a pollert is. Élesben mérve
# 2026-08-27-én: napindító 07:27:09 indul, 07:29:28 kilép, 07:29 "plugin
# disappeared", 180s grace, 07:32:51-re áll csak helyre a csatorna. Az a ~3,5
# perc süketség naponta ismétlődött, és mivel a bejövő Telegram sehol nem
# perzisztál, az akkor érkező üzenet véglegesen elveszett.
#
# A modell tehát MEGÍRJA a szöveget (stdout), a küldést a script végzi curl-lel.
# Így a spawnolt sessionnek nincs szüksége plugin példányra.

export PATH="$HOME/.local/bin:$HOME/.bun/bin:/home/linuxbrew/.linuxbrew/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

INSTALL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE="$(command -v claude)"
[ -z "$CLAUDE" ] && echo "ERROR: claude not found on PATH" >&2 && exit 1
LOG="$INSTALL_DIR/store/morning.log"
GATE="$INSTALL_DIR/scripts/hooks/outgoing-copy-gate.py"

# Load config
if [ -f "$INSTALL_DIR/.env" ]; then
  export $(grep -v '^#' "$INSTALL_DIR/.env" | xargs)
fi

CHAT_ID="${ALLOWED_CHAT_ID:-0}"
CALENDAR_ID="${HEARTBEAT_CALENDAR_ID:-primary}"

# Same-day dedup guard: the briefing must go out at most once per calendar
# day no matter how many times the trigger fires (a timer-unit re-activation
# on a systemd user-manager restart, a Persistent= catch-up, or a manual
# re-run). MORNING_FORCE=1 bypasses the guard for deliberate re-sends.
STAMP="$INSTALL_DIR/store/.morning-last-sent"
TODAY="$(date +%F)"
if [ "${MORNING_FORCE:-0}" != "1" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$TODAY" ]; then
  echo "=== Reggeli napindító $(date) -- SKIP: ma már elküldve (guard: $STAMP) ===" >> "$LOG"
  exit 0
fi

echo "=== Reggeli napindító $(date) ===" >> "$LOG"

cd "$INSTALL_DIR"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BODY="$WORK/body.txt"
GATE_ERR="$WORK/gate.err"

# A spawnolt session NE töltse be a telegram plugint: enélkül venné át a
# bot.pid-et a főágenstől. A --channels flag elhagyása önmagában nem elég,
# mert az enabledPlugins user- ES project-szinten is true erre a repóra.
GEN_ARGS=(--dangerously-skip-permissions
  --settings '{"enabledPlugins":{"telegram@claude-plugins-official":false}}')

PROMPT_BASE="Reggeli napindító szövegének MEGÍRÁSA. NE küldd el sehova, nincs is hozzá eszközöd.

1. Email check: search_emails az elmúlt 12 órából, szűrd ki a spam/promo emaileket
2. Naptár: list-events a mai napra a $CALENDAR_ID naptárból (Europe/Budapest timezone)
3. AI hírek: WebSearch \"AI news [tegnapi dátum]\"

Formátum: Telegram MarkdownV2. Félkövér EGY csillaggal (*szöveg*). A ( ) . - + = ! { } [ ] | ~ > # karaktereket escape-eld backslash-sel. Ne használj Markdown fejlécet. Ha egy szekcióban nincs esemény, hagyd ki a szekciót.

Tömör, lényegre törő. Ékezetesen írj magyarul, teljes ékezettel.

A VÁLASZOD KIZÁRÓLAG a kiküldendő üzenet szövege legyen. Semmi bevezető, semmi magyarázat, semmi kódblokk-jelölés."

echo "--- generálás ---" >> "$LOG"
"$CLAUDE" "${GEN_ARGS[@]}" -p "$PROMPT_BASE" > "$BODY" 2>> "$LOG"

if [ ! -s "$BODY" ]; then
  echo "HIBA: a generálás üres szöveget adott, nem küldök semmit." >> "$LOG"
  exit 1
fi

# --- kimenő-szöveg kapu -----------------------------------------------------
# A reply tool megkerülésével a PreToolUse hook nem futna le magától, pedig a
# napindító pont a legrendszeresebb kimenő magyar szövegünk. Ezért ugyanazt a
# kaput hívjuk meg kézzel, a hook szerződése szerinti payloaddal (0 = mehet,
# 2 = tiltva). Egy javítási kört engedünk, utána nem küldünk.
run_gate() {
  python3 -c 'import json,sys; sys.stdout.write(json.dumps({"tool_name":"mcp__plugin_telegram_telegram__reply","tool_input":{"text":open(sys.argv[1],encoding="utf-8").read()}}))' "$BODY" \
    | python3 "$GATE" > /dev/null 2>"$GATE_ERR"
}

if ! run_gate; then
  echo "--- kapu elutasította, egy javítási kör ---" >> "$LOG"
  cat "$GATE_ERR" >> "$LOG"
  "$CLAUDE" "${GEN_ARGS[@]}" -p "$PROMPT_BASE

Az alábbi szöveget a kimenő-szöveg kapu elutasította. Javítsd a felsorolt hibákat, a tartalmat tartsd meg. Újra: a válaszod KIZÁRÓLAG a javított üzenet szövege legyen.

--- SZÖVEG ---
$(cat "$BODY")

--- KAPU HIBÁI ---
$(cat "$GATE_ERR")" > "$WORK/body2.txt" 2>> "$LOG"
  if [ -s "$WORK/body2.txt" ]; then mv "$WORK/body2.txt" "$BODY"; fi
  if ! run_gate; then
    echo "HIBA: a kapu a javítás után is tiltja, nem küldök. Részletek fent." >> "$LOG"
    cat "$GATE_ERR" >> "$LOG"
    exit 1
  fi
fi

# --- küldés Bot API-val -----------------------------------------------------
if [ "${MORNING_DRY_RUN:-0}" = "1" ]; then
  echo "--- DRY RUN, nem küldök. A szöveg: ---" >> "$LOG"
  cat "$BODY" >> "$LOG"
  echo "=== Kész $(date) (dry run) ===" >> "$LOG"
  cat "$BODY"
  exit 0
fi

if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
  echo "HIBA: nincs TELEGRAM_BOT_TOKEN, nem tudok küldeni." >> "$LOG"
  exit 1
fi

API="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"

send() {  # $1 = fájl, $2 = parse_mode ("" = sima szöveg)
  if [ -n "$2" ]; then
    curl -sS --max-time 30 -X POST "$API" \
      --data-urlencode "chat_id=$CHAT_ID" \
      --data-urlencode "text@$1" \
      --data-urlencode "parse_mode=$2"
  else
    curl -sS --max-time 30 -X POST "$API" \
      --data-urlencode "chat_id=$CHAT_ID" \
      --data-urlencode "text@$1"
  fi
}

RESP="$(send "$BODY" MarkdownV2)"
if ! printf '%s' "$RESP" | grep -q '"ok":true'; then
  # Egy rossz escape a MarkdownV2-ben 400-at ad, és ilyenkor a napindító
  # TELJESEN elmaradna. Inkább menjen ki formázás nélkül, mint sehogy.
  echo "FIGYELEM: MarkdownV2 küldés elutasítva, sima szöveggel újrapróbálom." >> "$LOG"
  echo "$RESP" >> "$LOG"
  python3 -c 'import re,sys; p=sys.argv[1]; t=open(p,encoding="utf-8").read(); open(p+".plain","w",encoding="utf-8").write(re.sub(r"\\([^\w\s])",r"\1",t))' "$BODY"
  RESP="$(send "$BODY.plain" "")"
fi

if printf '%s' "$RESP" | grep -q '"ok":true'; then
  echo "$TODAY" > "$STAMP"
  echo "--- elküldve ---" >> "$LOG"
else
  echo "HIBA: a küldés nem sikerült, a napi guard NEM lép életbe." >> "$LOG"
  echo "$RESP" >> "$LOG"
fi

echo "=== Kész $(date) ===" >> "$LOG"
