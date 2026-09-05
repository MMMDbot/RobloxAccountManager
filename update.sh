#!/usr/bin/env bash
set -Eeuo pipefail
ENVFILE="${TEMPLE_ENV_FILE:-$HOME/.config/templo-roblox-panel/env}"
[[ -r "$ENVFILE" ]] || { echo "No existe $ENVFILE" >&2; exit 2; }
set -a; source "$ENVFILE"; set +a
BASE="${TEMPLE_BASE:-/opt/templo-roblox-panel}"
REPO="${TEMPLE_REPO_URL:-}"
[[ -n "$REPO" ]] || { echo 'TEMPLE_REPO_URL no está configurado. Actualiza volviendo a ejecutar install.sh desde un clon Git.' >&2; exit 3; }
command -v git >/dev/null || { echo 'git no instalado' >&2; exit 4; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "Descargando $REPO"
git clone --depth=1 --branch "${TEMPLE_REPO_BRANCH:-cordial-linux-panel}" --single-branch "$REPO" "$tmp/repo"
args=(--install-dir "$BASE" --bind "${TEMPLE_PANEL_HOST:-0.0.0.0}" --port "${TEMPLE_PANEL_PORT:-8090}")
exec "$tmp/repo/install.sh" "${args[@]}"
