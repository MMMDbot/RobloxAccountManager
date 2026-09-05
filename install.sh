#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[ERROR] línea $LINENO: $BASH_COMMAND" >&2' ERR
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${TEMPLE_INSTALL_DIR:-/opt/templo-roblox-panel}"
PANEL_HOST="${TEMPLE_PANEL_HOST:-0.0.0.0}"
PANEL_PORT="${TEMPLE_PANEL_PORT:-8090}"
REPO_URL="$(git -C "$SRC" remote get-url origin 2>/dev/null || true)"
REPO_BRANCH="$(git -C "$SRC" branch --show-current 2>/dev/null || true)"
NO_START=0
while (($#)); do case "$1" in
  --install-dir) INSTALL_DIR="$2"; shift 2;;
  --bind) PANEL_HOST="$2"; shift 2;;
  --port) PANEL_PORT="$2"; shift 2;;
  --no-start) NO_START=1; shift;;
  -h|--help) echo "uso: ./install.sh [--install-dir DIR] [--bind IP] [--port 8090] [--no-start]"; exit 0;;
  *) echo "opción desconocida: $1" >&2; exit 2;; esac; done
[[ -f "$SRC/app/main.py" ]] || { echo 'Ejecuta install.sh desde el repositorio clonado.' >&2; exit 2; }
[[ "$(uname -m)" == x86_64 ]] || { echo 'Solo x86_64 está soportado.' >&2; exit 3; }
. /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04* ]] || { echo "Ubuntu 24.04 x86_64 requerido; detectado ${PRETTY_NAME:-?}." >&2; exit 3; }
if [[ $EUID -eq 0 ]]; then
  RUN_USER="${SUDO_USER:-}"; [[ -n "$RUN_USER" && "$RUN_USER" != root ]] || { echo 'No ejecutes como root directo; usa sudo desde tu usuario normal.' >&2; exit 4; }
  SUDO=()
else
  RUN_USER="$USER"; command -v sudo >/dev/null || { echo 'sudo es requerido.' >&2; exit 4; }; sudo -v; SUDO=(sudo)
fi
USER_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"; USER_UID="$(id -u "$RUN_USER")"; USER_GID="$(id -g "$RUN_USER")"
run_user(){ if [[ "$(id -un)" == "$RUN_USER" ]]; then env HOME="$USER_HOME" "$@"; else sudo -u "$RUN_USER" -H env HOME="$USER_HOME" "$@"; fi; }
user_systemctl(){ run_user env XDG_RUNTIME_DIR="/run/user/$USER_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_UID/bus" systemctl --user "$@"; }
echo "[1/8] Dependencias del sistema"
"${SUDO[@]}" apt-get update
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip flatpak xvfb x11vnc novnc websockify cage curl jq ca-certificates git rsync x11-utils xdotool dbus-x11
for c in python3 flatpak Xvfb cage x11vnc websockify curl jq rsync; do command -v "$c" >/dev/null || { echo "Falta $c después de apt." >&2; exit 5; }; done
echo "[2/8] Instalando archivos en $INSTALL_DIR"
"${SUDO[@]}" mkdir -p "$INSTALL_DIR"; "${SUDO[@]}" chown "$USER_UID:$USER_GID" "$INSTALL_DIR"
user_systemctl stop templo-roblox.target templo-rb@1.service templo-rb@2.service templo-rb@3.service templo-rb@4.service templo-panel.service 2>/dev/null || true
run_user rsync -a --delete --exclude '.git/' --exclude '.venv/' --exclude 'data/' --exclude 'runtime/' "$SRC/" "$INSTALL_DIR/"
run_user mkdir -p "$INSTALL_DIR/data" "$INSTALL_DIR/runtime"
echo "[3/8] Entorno Python"
run_user python3 -m venv "$INSTALL_DIR/.venv"
run_user "$INSTALL_DIR/.venv/bin/python3" -m pip install --upgrade pip wheel
run_user "$INSTALL_DIR/.venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"
run_user "$INSTALL_DIR/.venv/bin/python3" -m py_compile "$INSTALL_DIR/app/main.py"
echo "[4/8] Cordial"
run_user flatpak remote-add --user --if-not-exists cordial https://luohoa97.github.io/cordial/cordial.flatpakrepo
run_user flatpak install --user -y cordial io.github.luohoa97.Cordial
run_user flatpak info io.github.luohoa97.Cordial >/dev/null
help="$(run_user flatpak run --command=cordial-run io.github.luohoa97.Cordial --help 2>&1 || true)"
grep -q -- '--profile' <<<"$help" || { echo 'Esta versión de Cordial no expone --profile; instalación detenida para evitar una configuración incompatible.' >&2; exit 6; }
echo "[5/8] Configuración ultrabaja y runtime"
CFGDIR="$USER_HOME/.config/templo-roblox-panel"; run_user mkdir -p "$CFGDIR"
ENVFILE="$CFGDIR/env"
if [[ ! -f "$ENVFILE" ]]; then run_user cp "$INSTALL_DIR/config.example.env" "$ENVFILE"; fi
run_user python3 - "$ENVFILE" "$INSTALL_DIR" "$PANEL_HOST" "$PANEL_PORT" "$REPO_URL" "$REPO_BRANCH" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); vals={}
for line in p.read_text().splitlines():
    if line and not line.lstrip().startswith('#') and '=' in line:
        k,v=line.split('=',1); vals[k]=v
vals.update(TEMPLE_BASE=sys.argv[2],TEMPLE_PANEL_HOST=sys.argv[3],TEMPLE_PANEL_PORT=sys.argv[4]); vals['TEMPLE_REPO_URL']=sys.argv[5]; vals['TEMPLE_REPO_BRANCH']=sys.argv[6] or 'cordial-linux-panel'
order=['TEMPLE_BASE','TEMPLE_PANEL_HOST','TEMPLE_PANEL_PORT','TEMPLE_RESOLUTION','TEMPLE_DPI_SCALE','TEMPLE_DISPLAY_BASE','TEMPLE_VNC_BASE','TEMPLE_WEB_BASE','TEMPLE_CPU_QUOTA','TEMPLE_CPU_WEIGHT','TEMPLE_NICE','TEMPLE_SUPERVISOR_INTERVAL','TEMPLE_SETUP_DISPLAY','TEMPLE_SETUP_VNC_PORT','TEMPLE_SETUP_WEB_PORT','TEMPLE_REPO_URL','TEMPLE_REPO_BRANCH']
p.write_text('\n'.join(f'{k}={vals[k]}' for k in order if k in vals)+'\n'); p.chmod(0o600)
PY
run_user python3 "$INSTALL_DIR/scripts/configure_flags.py"
echo "[6/8] Servicios systemd de usuario"
"${SUDO[@]}" loginctl enable-linger "$RUN_USER"
"${SUDO[@]}" systemctl start "user@$USER_UID.service" || true
UNITDIR="$USER_HOME/.config/systemd/user"; run_user mkdir -p "$UNITDIR"
run_user python3 - "$INSTALL_DIR" "$UNITDIR" <<'PY'
from pathlib import Path
import sys
base=Path(sys.argv[1]); out=Path(sys.argv[2]); src=base/'packaging/systemd'
for name in ['templo-panel.service.in','templo-rb@.service.in']:
    text=(src/name).read_text().replace('__INSTALL_DIR__',str(base))
    (out/name.removesuffix('.in')).write_text(text)
(out/'templo-roblox.target').write_text((src/'templo-roblox.target').read_text())
PY
run_user mkdir -p "$USER_HOME/.local/bin"
run_user ln -sfn "$INSTALL_DIR/templo" "$USER_HOME/.local/bin/templo"
run_user chmod +x "$INSTALL_DIR/templo" "$INSTALL_DIR/doctor.sh" "$INSTALL_DIR/update.sh" "$INSTALL_DIR/uninstall.sh" "$INSTALL_DIR/scripts/"*.sh "$INSTALL_DIR/scripts/configure_flags.py" 2>/dev/null || true
user_systemctl daemon-reload
user_systemctl enable templo-panel.service templo-rb@1.service templo-rb@2.service templo-rb@3.service templo-rb@4.service templo-roblox.target
if (( NO_START == 0 )); then user_systemctl restart templo-panel.service; user_systemctl restart templo-rb@1.service templo-rb@2.service templo-rb@3.service templo-rb@4.service; user_systemctl start templo-roblox.target; fi
echo "[7/8] Verificación"
if (( NO_START == 0 )); then
  for _ in {1..30}; do curl -fsS --max-time 2 "http://127.0.0.1:$PANEL_PORT/health" >/dev/null 2>&1 && break; sleep 1; done
  curl -fsS --max-time 4 "http://127.0.0.1:$PANEL_PORT/health" >/dev/null || { echo 'El panel no respondió después de instalar.' >&2; user_systemctl status templo-panel.service --no-pager || true; exit 7; }
fi
ENG="$USER_HOME/.var/app/io.github.luohoa97.Cordial/data/cordial/engine"
if [[ ! -s "$ENG/base.apk" || ! -s "$ENG/lib/x86_64/libroblox.so" ]]; then
  echo '[INFO] Roblox aún no está descargado. Se inicia el visor de preparación en :6090.'
  if (( NO_START == 0 )); then run_user env TEMPLE_BASE="$INSTALL_DIR" "$INSTALL_DIR/scripts/cordial_setup.sh" start >/dev/null || true; fi
fi
echo "[8/8] Instalación completada"
run_user env TEMPLE_BASE="$INSTALL_DIR" "$INSTALL_DIR/doctor.sh" || true
IP="$(hostname -I | awk '{print $1}')"
echo "Panel: http://${IP:-127.0.0.1}:$PANEL_PORT"
if [[ ! -s "$ENG/base.apk" ]]; then echo "Preparación Roblox: http://${IP:-127.0.0.1}:6090/vnc.html?autoconnect=1&resize=scale"; echo 'Pulsa Download Roblox; los cuatro supervisores arrancarán automáticamente al terminar.'; fi
echo "CLI: $USER_HOME/.local/bin/templo"
