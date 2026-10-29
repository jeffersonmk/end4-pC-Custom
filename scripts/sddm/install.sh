#!/usr/bin/env bash
# Installs the root helper and a sudoers rule limited to that single file.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
user="${SUDO_USER:-$USER}"

if [[ "${LC_ALL:-${LANG:-}}" == pt* ]]; then
  T_TITLE="Configuração do tema de login (SDDM) - uma única vez"
  T_WHAT="O que este script vai fazer:"
  T_L1="1. Copiar um pequeno helper para /usr/local/bin/sddm-corners-apply (dono: root)."
  T_L2="2. Criar uma regra sudoers (/etc/sudoers.d/sddm-corners-apply) que permite ao usuário '$user' rodar SOMENTE esse arquivo sem senha."
  T_PASS=">>> Será pedida a SUA SENHA de usuário (a mesma do sudo). Ao digitar, nada aparece na tela - é normal. Digite e aperte Enter."
  T_ASK="Continuar? [s/N] "
  T_YES="s"
  T_CANCEL="Cancelado. Nada foi alterado."
  T_NOTHEME="Tema 'corners' não encontrado em /usr/share/sddm/themes. Instale-o antes (paru -S sddm-theme-corners-git)."
  T_DONE="Pronto! Instalado com sucesso. Volte ao shell: Configurações > Login screen > Aplicar no SDDM."
  T_PRESS="Aperte Enter para fechar..."
else
  T_TITLE="Login screen (SDDM) setup - one time only"
  T_WHAT="What this script will do:"
  T_L1="1. Copy a small helper to /usr/local/bin/sddm-corners-apply (owned by root)."
  T_L2="2. Create a sudoers rule (/etc/sudoers.d/sddm-corners-apply) letting user '$user' run ONLY that file without a password."
  T_PASS=">>> You will be asked for YOUR user password (the sudo password). Nothing shows while you type - that is normal. Type it and press Enter."
  T_ASK="Continue? [y/N] "
  T_YES="y"
  T_CANCEL="Cancelled. Nothing was changed."
  T_NOTHEME="Theme 'corners' not found in /usr/share/sddm/themes. Install it first (paru -S sddm-theme-corners-git)."
  T_DONE="Done! Installed. Go back to the shell: Settings > Login screen > Apply to SDDM."
  T_PRESS="Press Enter to close..."
fi

pause() { [[ -t 0 ]] && { read -r -p "$T_PRESS" _ || true; }; }
trap 'pause' EXIT

echo
echo "== $T_TITLE =="
echo
echo "$T_WHAT"
echo "  $T_L1"
echo "  $T_L2"
echo
echo "$T_PASS"
echo
[[ -d /usr/share/sddm/themes/corners ]] || { echo "$T_NOTHEME"; exit 1; }
read -r -p "$T_ASK" ans
[[ "${ans,,}" == "$T_YES"* ]] || { echo "$T_CANCEL"; exit 0; }

tmp="$(mktemp)"
echo "$user ALL=(root) NOPASSWD: /usr/local/bin/sddm-corners-apply" > "$tmp"
visudo -cf "$tmp" >/dev/null
sudo -S -p '' install -o root -g root -m 755 "$here/sddm-corners-apply" /usr/local/bin/sddm-corners-apply
sudo -S -p '' install -o root -g root -m 440 "$tmp" /etc/sudoers.d/sddm-corners-apply
rm -f "$tmp"
echo
echo "$T_DONE"
