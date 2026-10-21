#!/bin/bash
# Claude Code Notification hook (Linux). Inside Maestri, a click on the notification raises the Maestri window; outside it, a plain desktop notification.

DATA=$(cat)
MESSAGE=$(printf '%s' "$DATA" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("message",""))
except Exception: pass' 2>/dev/null)
[ -z "$MESSAGE" ] && MESSAGE="Claude Code needs you"

command -v notify-send >/dev/null 2>&1 || exit 0

if [ "$TERM_PROGRAM" != "Maestri" ]; then
  notify-send -a "Claude Code" "Claude Code" "$MESSAGE" >/dev/null 2>&1
  exit 0
fi

ICON=$(ls /opt/Maestri/resources/icons/*.png 2>/dev/null | head -1)
MAESTRI_BIN=/opt/Maestri/maestri-app

setsid -f bash -c '
  ACTION=$(notify-send -a Maestri ${ICON:+-i "$ICON"} \
    -h "string:x-canonical-private-synchronous:maestri-$MAESTRI_TERMINAL_ID" \
    --action=open=Open "Maestri" "$MESSAGE" 2>/dev/null)
  if [ "$ACTION" = "open" ] && [ -x "$MAESTRI_BIN" ]; then
    setsid -f "$MAESTRI_BIN" >/dev/null 2>&1
  fi
' >/dev/null 2>&1 </dev/null

exit 0
