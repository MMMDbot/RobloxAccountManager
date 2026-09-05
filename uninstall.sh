#!/usr/bin/env bash
set -Eeuo pipefail
PURGE=0; YES=0
while (($#)); do case "$1" in --purge-data) PURGE=1;; --yes|-y) YES=1;; *) echo "opción desconocida: $1" >&2; exit 2;; esac; shift; done
ENVFILE="${TEMPLE_ENV_FILE:-$HOME/.config/templo-roblox-panel/env}"
[[ -r "$ENVFILE" ]] && { set -a; source "$ENVFILE"; set +a; }
BASE="${TEMPLE_BASE:-/opt/templo-roblox-panel}"
if (( YES == 0 )); then read -r -p "¿Desinstalar Templo Roblox Panel? [y/N] " ans; [[ "$ans" =~ ^[Yy]$ ]] || exit 0; fi
systemctl --user disable --now templo-roblox.target templo-rb@1.service templo-rb@2.service templo-rb@3.service templo-rb@4.service templo-panel.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/templo-panel.service" "$HOME/.config/systemd/user/templo-rb@.service" "$HOME/.config/systemd/user/templo-roblox.target"
systemctl --user daemon-reload || true
if [[ -f "$BASE/data/panel.db" ]]; then mkdir -p "$HOME/.local/share/templo-roblox-panel-backups"; cp -a "$BASE/data/panel.db" "$HOME/.local/share/templo-roblox-panel-backups/panel-$(date +%Y%m%d-%H%M%S).db"; fi
rm -f "$HOME/.local/bin/templo"
rm -rf "$BASE"
if (( PURGE )); then
  rm -rf "$HOME/.var/app/io.github.luohoa97.Cordial/data/cordial/profiles/rb1" "$HOME/.var/app/io.github.luohoa97.Cordial/data/cordial/profiles/rb2" "$HOME/.var/app/io.github.luohoa97.Cordial/data/cordial/profiles/rb3" "$HOME/.var/app/io.github.luohoa97.Cordial/data/cordial/profiles/rb4"
  flatpak uninstall --user -y io.github.luohoa97.Cordial || true
fi
rm -rf "$HOME/.config/templo-roblox-panel"
echo 'Desinstalación completada. El backup de panel.db se conservó en ~/.local/share/templo-roblox-panel-backups.'
