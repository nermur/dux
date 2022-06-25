#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

SDDM_CONF="/etc/sddm.conf.d/kde_settings.conf"

# That's for riced GNOME only.
_move2bkup {/home/"${WHICH_USER}"/.zsh_dux_environmentd,/home/"${WHICH_USER}"/.config/environment.d/gnome.conf}
sed -i '/[ -f ".zsh_dux_environmentd" ] && source .zsh_dux_environmentd/d' "/home/${WHICH_USER}/.zprofile" >&/dev/null || :

# kconfig: for kwriteconfig5
pacman -S --noconfirm --ask=4 --asdeps kconfig plasma-meta

_setup_sddm() {
	mkdir -p "/etc/sddm.conf.d/"
	\cp "${cp_flags}" "${GIT_DIR}/files${SDDM_CONF}" "/etc/sddm.conf.d/"

	if [[ "${sddm_autologin}" -eq 1 ]]; then
		kwriteconfig5 --file "${SDDM_CONF}" --group "Autologin" --key "Session" "${sddm_autologin_session_type}"
		kwriteconfig5 --file "${SDDM_CONF}" --group "Autologin" --key "User" "${WHICH_USER}"
	fi

	systemctl disable entrance.service gdm.service lightdm.service lxdm.service xdm.service >&/dev/null || :
	SERVICES+="sddm.service "
}

if [[ ${kde_install_virtual_keyboard} -eq 1 ]]; then
	PKGS+="qt5-virtualkeyboard "
	kwriteconfig5 --file "${SDDM_CONF}" --group "General" --key "InputMethod" "qtvirtualkeyboard"
fi

[[ ${kde_use_kwinft} -eq 1 ]] &&
	PKGS+="kwinft "

PKGS+="plasma-wayland-session colord-kde kwallet-pam kwalletmanager konsole spectacle aspell aspell-en networkmanager \
xdg-desktop-portal xdg-desktop-portal-kde \
sddm sddm-kcm \
lib32-libappindicator-gtk2 lib32-libappindicator-gtk3 libappindicator-gtk2 libappindicator-gtk3 \
kcm-wacomtablet "
_pkgs_add

# Incase GNOME was used previously.
kwriteconfig5 --delete --file /home/"${WHICH_USER}"/.config/konsolerc --group "UiSettings" --key "ColorScheme"
kwriteconfig5 --delete --file /home/"${WHICH_USER}"/.config/konsolerc --group "UiSettings" --key "WindowColorScheme"

_setup_sddm

sudo -H -u "${WHICH_USER}" kwriteconfig5 --file /home/"${WHICH_USER}"/.config/ktimezonedrc --group "TimeZones" --key "LocalZone" "${system_timezone}"

# KDE Plasma's network applet won't work without this.
SERVICES+="NetworkManager.service "
# These conflict with NetworkManager.
systemctl disable connman.service systemd-networkd.service iwd.service >&/dev/null || :

# shellcheck disable=SC2086
_systemctl enable ${SERVICES}
