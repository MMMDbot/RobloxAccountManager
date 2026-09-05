#!/usr/bin/env bash
set -u
ENVFILE="${TEMPLE_ENV_FILE:-$HOME/.config/templo-roblox-panel/env}"
[[ -r "$ENVFILE" ]] && { set -a; source "$ENVFILE"; set +a; }
BASE="${TEMPLE_BASE:-/opt/templo-roblox-panel}"
PORT="${TEMPLE_PANEL_PORT:-8090}"
errors=0; warnings=0
ok(){ printf '🟢 %s\n' "$*"; }
warn(){ printf '🟡 %s\n' "$*"; warnings=$((warnings+1)); }
fail(){ printf '🔴 %s\n' "$*"; errors=$((errors+1)); }
command_ok(){ command -v "$1" >/dev/null 2>&1 && ok "$1 instalado" || fail "$1 no encontrado"; }
echo 'Templo Roblox Panel · diagnóstico'
[[ "$(uname -m)" == x86_64 ]] && ok 'Arquitectura x86_64' || fail "Arquitectura no soportada: $(uname -m)"
if [[ -r /etc/os-release ]]; then . /etc/os-release; [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04* ]] && ok "$PRETTY_NAME" || warn "SO no validado: ${PRETTY_NAME:-desconocido}"; fi
for c in python3 flatpak Xvfb cage x11vnc websockify curl jq xdotool xclip; do command_ok "$c"; done
[[ -d "$BASE/app" && -x "$BASE/scripts/cordial_session.sh" ]] && ok "Instalación: $BASE" || fail "Instalación incompleta: $BASE"
flatpak info io.github.luohoa97.Cordial >/dev/null 2>&1 && ok 'Cordial Flatpak instalado' || fail 'Cordial Flatpak no instalado'
ENG="${CORDIAL_ENGINE_DIR:-$HOME/.var/app/io.github.luohoa97.Cordial/data/cordial/engine}"
[[ -s "$ENG/base.apk" && -s "$ENG/lib/x86_64/libroblox.so" ]] && ok 'Motor Roblox x86_64 preparado' || warn 'Motor Roblox pendiente: usa templo setup'
if systemctl --user is-active --quiet templo-panel.service 2>/dev/null; then ok 'Panel systemd activo'; else warn 'Panel systemd no activo'; fi
if curl -fsS --max-time 4 "http://127.0.0.1:$PORT/health" >/tmp/templo-health.$$ 2>/dev/null; then
  running=$(jq -r '.roblox_sessions_running // 0' /tmp/templo-health.$$); ready=$(jq -r '.roblox_sessions_ready // 0' /tmp/templo-health.$$)
  ok "Panel HTTP responde · running=$running ready=$ready"
else fail "Panel HTTP no responde en :$PORT"; fi
rm -f /tmp/templo-health.$$
for i in 1 2 3 4; do
  if [[ -x "$BASE/scripts/cordial_session.sh" ]]; then
    st=$("$BASE/scripts/cordial_session.sh" "$i" status 2>/dev/null || echo '{}')
    e=$(jq -r '.engine // false' <<<"$st"); r=$(jq -r '.ready // false' <<<"$st"); w=$(jq -r '.viewer.web // false' <<<"$st")
    [[ "$e/$r/$w" == true/true/true ]] && ok "rb$i engine/ready/viewer OK" || warn "rb$i engine=$e ready=$r viewer=$w"
  fi
done
mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo); (( mem_kb >= 6000000 )) && ok 'RAM suficiente para 4 clientes' || warn 'Menos de 6 GB RAM; 4 clientes pueden saturar el equipo'
free_kb=$(df -Pk "$HOME" | awk 'NR==2{print $4}'); (( free_kb >= 3000000 )) && ok 'Espacio libre >= 3 GB' || warn 'Menos de 3 GB libres'
printf '\nResultado: %d error(es), %d aviso(s)\n' "$errors" "$warnings"
(( errors == 0 ))
