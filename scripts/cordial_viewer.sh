#!/usr/bin/env bash
set -euo pipefail
ENVFILE="${TEMPLE_ENV_FILE:-$HOME/.config/templo-roblox-panel/env}"
if [[ -r "$ENVFILE" ]]; then set -a; source "$ENVFILE"; set +a; fi
ID="${1:?instance id}"; ACTION="${2:-status}"
[[ "$ID" =~ ^[1-4]$ ]] || { echo 'invalid id' >&2; exit 2; }
ROOT="${TEMPLE_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BASE="$ROOT/runtime/cordial"
DIR="$BASE/rb$ID"; mkdir -p "$DIR"
DISPLAY_BASE="${TEMPLE_DISPLAY_BASE:-200}"; DNUM=$((DISPLAY_BASE+ID)); DISPLAY=:$DNUM; export DISPLAY
VNC_PORT=$(( ${TEMPLE_VNC_BASE:-5910}+ID )); WEB_PORT=$(( ${TEMPLE_WEB_BASE:-6090}+ID ))
VPID="$DIR/x11vnc.pid"; WPID="$DIR/websockify.pid"
alive(){ local f="$1" m="$2" p; [[ -f "$f" ]] || return 1; p=$(cat "$f" 2>/dev/null||true); [[ "$p" =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null && tr '\0' ' ' <"/proc/$p/cmdline" | grep -Fq "$m"; }
stop_one(){ local f="$1" m="$2" p; if alive "$f" "$m"; then p=$(cat "$f"); kill -TERM "$p" 2>/dev/null||true; for _ in {1..15}; do kill -0 "$p" 2>/dev/null||break; sleep .1; done; fi; rm -f "$f"; }
status(){ local v=false w=false; alive "$VPID" x11vnc && v=true||true; alive "$WPID" websockify && w=true||true; printf '{"id":%d,"display":"%s","vnc_port":%d,"web_port":%d,"vnc":%s,"web":%s}\n' "$ID" "$DISPLAY" "$VNC_PORT" "$WEB_PORT" "$v" "$w"; }
case "$ACTION" in
  start)
    stop_one "$WPID" websockify; stop_one "$VPID" x11vnc
    [[ -S "/tmp/.X11-unix/X$DNUM" ]] || { echo "display $DISPLAY unavailable" >&2; exit 3; }
    x11vnc -display "$DISPLAY" -rfbport "$VNC_PORT" -localhost -forever -shared -nopw -noxdamage -quiet >>"$DIR/x11vnc.log" 2>&1 & echo $! >"$VPID"
    sleep .4
    websockify --web="${NOVNC_WEB:-/usr/share/novnc}" "$WEB_PORT" "127.0.0.1:$VNC_PORT" >>"$DIR/websockify.log" 2>&1 & echo $! >"$WPID"
    sleep .4; status ;;
  stop)
    stop_one "$WPID" websockify
    stop_one "$VPID" x11vnc
    status ;;
  status) status ;;
  *) echo 'usage: cordial_viewer.sh ID {start|stop|status}' >&2; exit 2 ;;
esac
