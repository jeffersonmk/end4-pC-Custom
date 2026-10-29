#!/usr/bin/env bash
# Installs the root helper and a sudoers rule limited to that single file.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
user="${SUDO_USER:-$USER}"
[[ -d /usr/share/sddm/themes/corners ]] || { echo "Tema 'corners' não encontrado em /usr/share/sddm/themes."; exit 1; }
tmp="$(mktemp)"
echo "$user ALL=(root) NOPASSWD: /usr/local/bin/sddm-corners-apply" > "$tmp"
visudo -cf "$tmp" >/dev/null
sudo -S -p '' install -o root -g root -m 755 "$here/sddm-corners-apply" /usr/local/bin/sddm-corners-apply
sudo -S -p '' install -o root -g root -m 440 "$tmp" /etc/sudoers.d/sddm-corners-apply
rm -f "$tmp"
echo "Instalado. O shell agora pode aplicar o tema do SDDM sem senha (apenas esse helper)."
