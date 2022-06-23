#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

if [[ ${IS_CHROOT} -eq 1 ]]; then
    echo -e "\nERROR: Do not run this script inside a chroot!\n"
	exit 1
fi

_gnome_flatpak() {
	FLATPAKS+="org.kde.KStyle.Kvantum//5.15-21.08 org.gtk.Gtk3theme.adw-gtk3-dark "
	_flatpaks_add

	flatpak override --env=QT_STYLE_OVERRIDE=kvantum --filesystem=xdg-config/Kvantum:ro
}

PKGS+="kvantum qt6-svg qt5ct qt6ct papirus-icon-theme "

[[ ${gnome_extension_appindicator} -eq 1 ]] &&
	PKGS+="lib32-libappindicator-gtk2 lib32-libappindicator-gtk3 libappindicator-gtk2 libappindicator-gtk3 gnome-shell-extension-appindicator "

PKGS_AUR+="papirus-folders-git "
_pkgs_add
_pkgs_aur_add

papirus-folders -C adwaita --theme Papirus-Dark

_gnome_flatpak

[[ ${DUX_INSTALLER} -ne 1 ]] &&
	(sudo -H -u "${WHICH_USER}" DENY_SUPERUSER=1 ${SYSTEMD_USER_ENV} bash "/home/${WHICH_USER}/dux/scripts/non-SU/rice_GNOME_part2.sh") |& tee "${GIT_DIR}/logs/rice_GNOME_part2.log"
