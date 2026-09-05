#!/usr/bin/env bash
set -euo pipefail
ENVFILE="${TEMPLE_ENV_FILE:-$HOME/.config/templo-roblox-panel/env}"
if [[ -r "$ENVFILE" ]]; then set -a; source "$ENVFILE"; set +a; fi
ID="${1:?instance id}"; ACTION="${2:-status}"
[[ "$ID" =~ ^[1-4]$ ]] || { echo 'invalid id' >&2; exit 2; }
BASE="${TEMPLE_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; DIR="$BASE/runtime/cordial/rb$ID"; mkdir -p "$DIR"
CAGE="${TEMPLE_CAGE_BIN:-$(command -v cage || true)}"
ENG="${CORDIAL_ENGINE_DIR:-$HOME/.var/app/io.github.luohoa97.Cordial/data/cordial/engine}"
VIEW="$BASE/scripts/cordial_viewer.sh"
DISPLAY_BASE="${TEMPLE_DISPLAY_BASE:-200}"; DNUM=$((DISPLAY_BASE+ID)); DISPLAY=:$DNUM
XVPID="$DIR/xvfb.pid"; CAGEPID="$DIR/cage.pid"; LOG="$DIR/cordial.log"
READY="$DIR/ready.marker"; DESIRED="$DIR/desired"
export DISPLAY
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
export PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"
alive_file(){ local f="$1" p; [[ -f "$f" ]] || return 1; p=$(cat "$f" 2>/dev/null||true); [[ "$p" =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null; }
xalive(){ local p; alive_file "$XVPID" || return 1; p=$(cat "$XVPID"); tr '\0' ' ' <"/proc/$p/cmdline" | grep -Fq "Xvfb $DISPLAY" && [[ -S "/tmp/.X11-unix/X$DNUM" ]]; }
cage_alive(){ local p; alive_file "$CAGEPID" || return 1; p=$(cat "$CAGEPID"); tr '\0' ' ' <"/proc/$p/cmdline" | grep -Fq -- "--profile rb$ID"; }
engine_pid(){ pgrep -f "^cordial-run .*--profile rb$ID" | head -1; }
engine(){ engine_pid >/dev/null 2>&1; }
set_desired(){ printf '%s\n' "$1" >"$DESIRED"; }
desired_on(){ [[ ! -f "$DESIRED" ]] || [[ "$(cat "$DESIRED" 2>/dev/null||true)" == on ]]; }
mark_ready(){
  engine || { rm -f "$READY"; return 1; }
  [[ -f "$READY" ]] && return 0
  [[ -f "$LOG" ]] && grep -qm1 '\[roblox\] app ready:' "$LOG" && { touch "$READY"; return 0; }
  return 1
}
ready(){ engine && [[ -f "$READY" ]]; }
viewer_ok(){
  "$VIEW" "$ID" status 2>/dev/null | grep -q '"vnc":true.*"web":true' || return 1
  curl -fsS --max-time 1 "http://127.0.0.1:$(( ${TEMPLE_WEB_BASE:-6090}+ID ))/vnc.html" >/dev/null 2>&1
}
apply_limits(){
  local p cg unit
  p=$(engine_pid 2>/dev/null || true); [[ -n "$p" ]] || return 0
  renice 10 -p "$p" >/dev/null 2>&1 || true
  cg=$(awk -F: '$1=="0"{print $3}' "/proc/$p/cgroup" 2>/dev/null || true); unit=${cg##*/}
  if [[ "$unit" == app-flatpak-io.github.luohoa97.Cordial-*.scope ]] && [[ -S "$XDG_RUNTIME_DIR/bus" ]]; then
    systemctl --user set-property "$unit" CPUQuota="${TEMPLE_CPU_QUOTA:-60%}" CPUWeight="${TEMPLE_CPU_WEIGHT:-20}" >/dev/null 2>&1 || true
  fi
}
status(){
  local x=false c=false e=false r=false v d=false
  xalive && x=true||true; cage_alive && c=true||true; engine && e=true||true
  mark_ready >/dev/null 2>&1 && r=true||true; desired_on && d=true||true
  v=$("$VIEW" "$ID" status 2>/dev/null||echo '{}')
  printf '{"id":%d,"profile":"rb%d","display":"%s","desired":%s,"xvfb":%s,"cage":%s,"engine":%s,"ready":%s,"viewer":%s}\n' "$ID" "$ID" "$DISPLAY" "$d" "$x" "$c" "$e" "$r" "$v"
}
start_x(){
  if xalive; then return; fi
  rm -f "/tmp/.X${DNUM}-lock"
  Xvfb "$DISPLAY" -screen 0 "${TEMPLE_RESOLUTION:-960x600}x24" -nolisten tcp +extension GLX +render -noreset >>"$DIR/xvfb.log" 2>&1 & echo $! >"$XVPID"
  for _ in {1..30}; do [[ -S "/tmp/.X11-unix/X$DNUM" ]] && return; sleep .1; done
  echo "Xvfb $DISPLAY failed" >&2; return 3
}
start_one(){
  [[ -n "$CAGE" && -x "$CAGE" ]] || { echo "cage is not installed" >&2; return 5; }
  set_desired on
  [[ -s "$ENG/base.apk" && -s "$ENG/lib/x86_64/libroblox.so" ]] || { echo "Roblox engine missing; run: templo setup" >&2; return 6; }
  start_x
  if cage_alive && engine; then
    apply_limits; viewer_ok || "$VIEW" "$ID" start >/dev/null 2>&1||true; mark_ready >/dev/null 2>&1||true; status; return
  fi
  "$VIEW" "$ID" stop >/dev/null 2>&1||true; rm -f "$READY"; : >"$LOG"
  if cage_alive; then p=$(cat "$CAGEPID"); kill -TERM "$p" 2>/dev/null||true; for _ in {1..20}; do kill -0 "$p" 2>/dev/null||break; sleep .1; done; fi
  engine && pkill -TERM -f "^cordial-run .*--profile rb$ID" >/dev/null 2>&1 || true
  nohup nice -n "${TEMPLE_NICE:-10}" "$CAGE" -- env CORDIAL_SECRET_STORE=file CORDIAL_NO_VULKAN=1 CORDIAL_RESOLUTION="${TEMPLE_RESOLUTION:-960x600}" CORDIAL_DPI_SCALE="${TEMPLE_DPI_SCALE:-1.0}" CORDIAL_GAMEMODE=0 CORDIAL_PRESENT_MODE=fifo flatpak run --command=cordial-run io.github.luohoa97.Cordial --lib-dir "$ENG/lib/x86_64" --apk "$ENG/base.apk" --host-libc --game-activity --run 0 --profile "rb$ID" >>"$LOG" 2>&1 & echo $! >"$CAGEPID"
  for _ in {1..40}; do engine && break; cage_alive || break; sleep .2; done
  engine || { echo "Cordial rb$ID failed" >&2; tail -n 80 "$LOG" >&2; return 4; }
  apply_limits; "$VIEW" "$ID" start >/dev/null
  for _ in {1..20}; do mark_ready >/dev/null 2>&1 && break; sleep .5; done
  status
}
stop_one(){
  set_desired off; "$VIEW" "$ID" stop >/dev/null 2>&1||true
  if cage_alive; then p=$(cat "$CAGEPID"); kill -TERM "$p" 2>/dev/null||true; for _ in {1..20}; do kill -0 "$p" 2>/dev/null||break; sleep .1; done; fi
  pkill -TERM -f "^cordial-run .*--profile rb$ID" >/dev/null 2>&1 || true
  if xalive; then p=$(cat "$XVPID"); kill -TERM "$p" 2>/dev/null||true; for _ in {1..20}; do kill -0 "$p" 2>/dev/null||break; sleep .1; done; fi
  rm -f "$CAGEPID" "$XVPID" "$READY"; status
}
ensure_one(){
  desired_on || { status; return; }
  if ! xalive || ! cage_alive || ! engine; then start_one; return; fi
  apply_limits; viewer_ok || "$VIEW" "$ID" start >/dev/null 2>&1||true
  mark_ready >/dev/null 2>&1||true; status
}
case "$ACTION" in
  start) start_one ;;
  stop) stop_one ;;
  ensure) ensure_one ;;
  status) status ;;
  *) echo 'usage: cordial_session.sh ID {start|stop|ensure|status}' >&2; exit 2 ;;
esac
