#!/bin/bash
# Marveen - Reggeli napindító
# Trigger: systemd user timer (Linux, <agent>-morning.timer) vagy LaunchAgent
# (macOS), naponta 7:27-kor. Naponta legfeljebb egyszer küld (lásd a guardot).

export PATH="$HOME/.local/bin:$HOME/.bun/bin:/home/linuxbrew/.linuxbrew/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

INSTALL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE="$(command -v claude)"
[ -z "$CLAUDE" ] && echo "ERROR: claude not found on PATH" >&2 && exit 1
LOG="$INSTALL_DIR/store/morning.log"

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

[ -z "$TELEGRAM_BOT_TOKEN" ] && echo "ERROR: TELEGRAM_BOT_TOKEN nincs beállítva (.env)" >> "$LOG" 2>&1 && exit 1

BRIEFING="$($CLAUDE --dangerously-skip-permissions \
  --settings '{"enabledPlugins":{"telegram@claude-plugins-official":false}}' \
  -p "Reggeli napindító - állítsd össze az üzenet SZÖVEGÉT (ne küldd el, ne használj semmilyen Telegram/reply toolt -- a végső szöveget add vissza válaszként, ez kerül kiküldésre).

1. Email check: ha nem érhető el azonnal, ToolSearch-csel keresd meg a connect_all és get_unseen_messages eszközöket (email MCP). Hívd meg előbb a connect_all-t, utána a get_unseen_messages-t -- szűrd ki a spam/promo emaileket
2. Naptár: ha nem érhető el azonnal, ToolSearch-csel keresd meg a 'calendar' kulcsszóra a Google Calendar MCP list_events eszközét (a tool neve alahúzásos: list_events, nem list-events). Ha megtalálod, kérdezd le a mai nap eseményeit a(z) $CALENDAR_ID naptárból (Europe/Budapest timezone). Ha a ToolSearch után sem található ilyen eszköz, egyszerűen HAGYD KI a naptár blokkot a végleges szövegből -- ne írj arról semmit, hogy a naptár nincs bekötve vagy nem elérhető, ez a lépés ilyenkor néma legyen
3. AI hírek: WebSearch \"AI news [tegnapi dátum]\"

Tömör, lényegre törő. Ékezetesen írj magyarul. A válaszod KIZÁRÓLAG a kiküldendő üzenet szövege legyen, semmi más (se bevezető, se magyarázat, se markdown code fence).")"

echo "--- Összeállított szöveg ---" >> "$LOG"
echo "$BRIEFING" >> "$LOG"
echo "--- vége ---" >> "$LOG"

if [ -z "$BRIEFING" ]; then
  echo "ERROR: üres briefing szöveg, nem küldöm el" >> "$LOG" 2>&1
  echo "=== Kész (hiba) $(date) ===" >> "$LOG"
  exit 1
fi

HTTP_CODE="$(curl -s -o "$INSTALL_DIR/store/.morning-send-response.json" -w '%{http_code}' \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT_ID}" \
  --data-urlencode "parse_mode=MarkdownV2" \
  --data-urlencode "text=${BRIEFING}")"

if [ "$HTTP_CODE" = "200" ]; then
  echo "$TODAY" > "$STAMP"
  echo "=== Elküldve (HTTP $HTTP_CODE) $(date) ===" >> "$LOG"
else
  echo "ERROR: sendMessage HTTP $HTTP_CODE, válasz: $(cat "$INSTALL_DIR/store/.morning-send-response.json" 2>/dev/null)" >> "$LOG"
  echo "=== Kész (hiba) $(date) ===" >> "$LOG"
  exit 1
fi
