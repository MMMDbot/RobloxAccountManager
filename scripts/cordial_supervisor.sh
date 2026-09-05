#!/usr/bin/env bash
set -u
ENVFILE="${TEMPLE_ENV_FILE:-$HOME/.config/templo-roblox-panel/env}"
if [[ -r "$ENVFILE" ]]; then set -a; source "$ENVFILE"; set +a; fi
ID="${1:?instance id}"
[[ "$ID" =~ ^[1-4]$ ]] || exit 2
BASE="${TEMPLE_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SESSION="$BASE/scripts/cordial_session.sh"
LOG="$BASE/runtime/cordial/rb$ID/supervisor.log"
mkdir -p "$(dirname "$LOG")"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
while :; do
  ENG="${CORDIAL_ENGINE_DIR:-$HOME/.var/app/io.github.luohoa97.Cordial/data/cordial/engine}"
  if [[ -s "$ENG/base.apk" && -s "$ENG/lib/x86_64/libroblox.so" ]]; then
    if [[ "$ID" == 1 ]]; then "$BASE/scripts/cordial_setup.sh" stop >/dev/null 2>&1 || true; fi
    "$SESSION" "$ID" ensure >>"$LOG" 2>&1 || true
    sleep "${TEMPLE_SUPERVISOR_INTERVAL:-15}"
  else
    sleep 30
  fi
done
