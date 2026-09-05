#!/usr/bin/env bash
set -euo pipefail
ENVFILE="${TEMPLE_ENV_FILE:-$HOME/.config/templo-roblox-panel/env}"
if [[ -r "$ENVFILE" ]]; then set -a; source "$ENVFILE"; set +a; fi
ACTION="${1:-status}"
BASE="${TEMPLE_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DIR="$BASE/runtime/setup"; mkdir -p "$DIR"
DNUM="${TEMPLE_SETUP_DISPLAY:-200}"; DISPLAY=:$DNUM; export DISPLAY
VNC_PORT="${TEMPLE_SETUP_VNC_PORT:-5910}"; WEB_PORT="${TEMPLE_SETUP_WEB_PORT:-6090}"
ENG="${CORDIAL_ENGINE_DIR:-$HOME/.var/app/io.github.luohoa97.Cordial/data/cordial/engine}"
XPID="$DIR/xvfb.pid"; CPID="$DIR/cordial.pid"; VPID="$DIR/x11vnc.pid"; WPID="$DIR/websockify.pid"
alive(){ local f="$1" p; [[ -f "$f" ]] || return 1; p=$(cat "$f" 2>/dev/null||true); [[ "$p" =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null; }
engine_ready(){ [[ -s "$ENG/base.apk" && -s "$ENG/lib/x86_64/libroblox.so" ]]; }
stop_pid(){ local f="$1" p; if alive "$f"; then p=$(cat "$f"); kill -TERM "$p" 2>/dev/null||true; for _ in {1..20}; do kill -0 "$p" 2>/dev/null||break; sleep .1; done; fi; rm -f "$f"; }
status(){ local e=false x=false c=false v=false w=false; engine_ready&&e=true||true; alive "$XPID"&&x=true||true; alive "$CPID"&&c=true||true; alive "$VPID"&&v=true||true; alive "$WPID"&&w=true||true; printf '{"engine_ready":%s,"display":":%s","xvfb":%s,"cordial":%s,"vnc":%s,"web":%s,"vnc_port":%s,"web_port":%s}\n' "$e" "$DNUM" "$x" "$c" "$v" "$w" "$VNC_PORT" "$WEB_PORT"; }
case "$ACTION" in
  start)
    command -v flatpak >/dev/null || { echo 'flatpak missing' >&2; exit 3; }
    flatpak info io.github.luohoa97.Cordial >/dev/null 2>&1 || { echo 'Cordial Flatpak missing' >&2; exit 4; }
    if ! alive "$XPID"; then
      rm -f "/tmp/.X${DNUM}-lock"
      Xvfb "$DISPLAY" -screen 0 960x600x24 -nolisten tcp +extension GLX +render -noreset >>"$DIR/xvfb.log" 2>&1 & echo $! >"$XPID"
      for _ in {1..30}; do [[ -S "/tmp/.X11-unix/X$DNUM" ]] && break; sleep .1; done
    fi
    if ! alive "$CPID"; then
      DISPLAY="$DISPLAY" nohup flatpak run io.github.luohoa97.Cordial >>"$DIR/cordial.log" 2>&1 & echo $! >"$CPID"
    fi
    stop_pid "$VPID"; stop_pid "$WPID"
    x11vnc -display "$DISPLAY" -rfbport "$VNC_PORT" -localhost -forever -shared -nopw -noxdamage -quiet >>"$DIR/x11vnc.log" 2>&1 & echo $! >"$VPID"
    sleep .4
    websockify --web="${NOVNC_WEB:-/usr/share/novnc}" "$WEB_PORT" "127.0.0.1:$VNC_PORT" >>"$DIR/websockify.log" 2>&1 & echo $! >"$WPID"
    sleep .4; status ;;
  stop)
    stop_pid "$WPID"; stop_pid "$VPID"; stop_pid "$CPID"; stop_pid "$XPID"; status ;;
  status) status ;;
  *) echo 'usage: cordial_setup.sh {start|stop|status}' >&2; exit 2 ;;
esac
