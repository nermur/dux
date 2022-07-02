#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

clear

# Install Paru, an AUR helper.
if ! hash paru >&/dev/null; then
	[[ -d "/home/${WHICH_USER}/paru-bin" ]] &&
		trash-put -rf /home/"${WHICH_USER}"/paru-bin

	git clone https://aur.archlinux.org/paru-bin.git /home/"${WHICH_USER}"/paru-bin
	cd /home/"${WHICH_USER}"/paru-bin
	makepkg -si --noconfirm
fi

_set_font_preferences() {
	\cp "${cp_flags}" /etc/fonts/local.conf "/home/${WHICH_USER}/.config/fontconfig/conf.d/"
}

_other_user_files() {
	if ! grep -q '[ -f ".zsh_dux" ] && source .zsh_dux' "/home/${WHICH_USER}/.zshrc.local" >&/dev/null; then
		printf '\n[ -f ".zsh_dux" ] && source .zsh_dux' >>"/home/${WHICH_USER}/.zshrc.local"
	fi
	\cp "${cp_flags}" "${GIT_DIR}"/files/home/.zsh_dux "/home/${WHICH_USER}/"
}

_set_font_preferences
_other_user_files
