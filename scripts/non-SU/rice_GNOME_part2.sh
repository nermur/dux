#!/bin/bash
# shellcheck disable=SC2154
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

# Generate font cache so new fonts work correctly.
fc-cache -f

_set_configs() {
	mkdir "${mkdir_flags}" /home/"${WHICH_USER}"/.config/{environment.d,gtk-3.0,gtk-4.0,Kvantum,qt5ct,qt6ct}

	if [[ ${gnome_no_titlebars} -eq 1 ]]; then
		\cp "${cp_flags}" "${GIT_DIR}"/files/home/.config/gtk-3.0/gtk.css "/home/${WHICH_USER}/.config/gtk-3.0/"
		gsettings set org.gnome.desktop.wm.preferences titlebar-uses-system-font "false"
		gsettings set org.gnome.desktop.wm.preferences titlebar-font ""
	fi

	\cp "${cp_flags}" "${GIT_DIR}"/files/home/.gtkrc-2.0 "/home/${WHICH_USER}/"
	\cp "${cp_flags}" "${GIT_DIR}"/files/home/.config/environment.d/gnome.conf "/home/${WHICH_USER}/.config/environment.d/"
	\cp "${cp_flags}" "${GIT_DIR}"/files/home/.config/qt5ct/qt5ct.conf "/home/${WHICH_USER}/.config/qt5ct/"
	\cp "${cp_flags}" "${GIT_DIR}"/files/home/.config/qt6ct/qt6ct.conf "/home/${WHICH_USER}/.config/qt6ct/"

	\cp "${cp_flags}" "${GIT_DIR}"/files/home/.config/gtk-3.0/settings.ini "/home/${WHICH_USER}/.config/gtk-3.0"
	\cp "${cp_flags}" -R "${GIT_DIR}"/files/home/.config/gtk-4.0 "/home/${WHICH_USER}/.config"

	kwriteconfig5 --file /home/"${WHICH_USER}"/.config/Kvantum/kvantum.kvconfig --group "General" --key "theme" "KvGnomeDark"

	kwriteconfig5 --file /home/"${WHICH_USER}"/.config/konsolerc --group "UiSettings" --key "ColorScheme" "KvGnomeDark"
	kwriteconfig5 --file /home/"${WHICH_USER}"/.config/konsolerc --group "UiSettings" --key "WindowColorScheme" "KvGnomeDark"

	\cp "${cp_flags}" "${GIT_DIR}"/files/home/.zsh_dux_environmentd "/home/${WHICH_USER}/"
	if ! grep -q '[ -f ".zsh_dux_environmentd" ] && source .zsh_dux_environmentd' "/home/${WHICH_USER}/.zprofile"; then
		printf '\n[ -f ".zsh_dux_environmentd" ] && source .zsh_dux_environmentd' >>"/home/${WHICH_USER}/.zprofile"
	fi
}
_set_configs

_org_gnome_desktop() {
	local SCHEMA="org.gnome.desktop"
	gsettings set "${SCHEMA}".interface document-font-name "${gnome_document_font_name}"
	gsettings set "${SCHEMA}".interface font-name "${gnome_font_name}"
	gsettings set "${SCHEMA}".interface monospace-font-name "${gnome_monospace_font_name}"

	gsettings set "${SCHEMA}".interface font-antialiasing "${gnome_font_aliasing}"
	gsettings set "${SCHEMA}".interface font-hinting "${gnome_font_hinting}"

	gsettings set "${SCHEMA}".interface color-scheme "prefer-dark"
	gsettings set "${SCHEMA}".interface gtk-theme "adw-gtk3-dark"
	gsettings set "${SCHEMA}".interface icon-theme "Papirus-Dark"

	gsettings set "${SCHEMA}".interface enable-animations "${gnome_animations}"

	gsettings set "${SCHEMA}".peripherals.mouse accel-profile "${gnome_mouse_accel_profile}"
	gsettings set "${SCHEMA}".privacy remember-app-usage "${gnome_remember_app_usage}"
	gsettings set "${SCHEMA}".privacy remember-recent-files "${gnome_remember_recent_files}"

	[[ ${gnome_disable_idle} -eq 1 ]] &&
		gsettings set "${SCHEMA}".session idle-delay "0"
}
_org_gnome_desktop

gsettings set org.gnome.shell disabled-extensions "[]"
# If an extension doesn't exist, it'll be ignored.
gsettings set org.gnome.shell enabled-extensions "['appindicatorsupport@rgcjonas.gmail.com', 'pop-shell@system76.com', 'pamac-updates@manjaro.org']"

[[ ${gnome_center_new_windows} -eq 1 ]] &&
	gsettings set org.gnome.mutter center-new-windows "true"

whiptail --yesno "Logging out is required to complete the rice.\nLogout now?" 0 0 &&
	loginctl kill-user "${WHICH_USER}"
