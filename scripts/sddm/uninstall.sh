#!/usr/bin/env bash
set -euo pipefail
sudo -S -p '' rm -f /usr/local/bin/sddm-corners-apply /etc/sudoers.d/sddm-corners-apply
[[ -f /usr/share/sddm/themes/corners/theme.conf.orig ]] && \
  echo "Backup do theme.conf original: /usr/share/sddm/themes/corners/theme.conf.orig (restaure com sudo cp se quiser)."
echo "Removido."
