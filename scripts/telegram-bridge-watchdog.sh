
#!/bin/bash

LOG="$HOME/marveen/store/bridge-watchdog.log"

MAXUP=420   # 7 perc

ts=$(systemctl --user show jezus-channels -p ActiveEnterTimestamp --value)

started=$(date -d "$ts" +%s 2>/dev/null || echo 0)

now=$(date +%s)

up=$(( now - started ))

if [ "$started" -gt 0 ] && [ "$up" -ge "$MAXUP" ]; then

  echo "$(date '+%F %T') preemptive restart (uptime ${up}s)" >> "$LOG"

  systemctl --user restart jezus-channels

fi

