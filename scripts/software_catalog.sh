#!/bin/bash
# shellcheck disable=SC2154
set +H

export KEEP_GOING=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
unset KEEP_GOING
source "${GIT_DIR}/configs/settings.sh"
source "${GIT_DIR}/configs/software_catalog.sh"

if [[ ${IS_CHROOT} -eq 1 ]]; then
	echo -e "\nERROR: Do not run this script inside a chroot!\n"
	exit 1
fi

mkdir "${mkdir_flags}" /home/"${WHICH_USER}"/.config/systemd/user
chown -R "${WHICH_USER}:${WHICH_USER}" "/home/${WHICH_USER}/.config/systemd/user"

chmod +x -R "${GIT_DIR}"

[[ ${helvum} -eq 1 ]] &&
	PKGS+="helvum "

[[ ${spotify} -eq 1 ]] &&
	PKGS_AUR+="spotify "

[[ ${spotify_adblock} -eq 1 ]] &&
	PKGS_AUR+="spotify-adblock-git spotify-remove-ad-banner "

[[ ${nomachine} -eq 1 ]] &&
	PKGS_AUR+="nomachine "

[[ ${easyeffects} -eq 1 ]] &&
	PKGS+="easyeffects "

if [[ ${opensnitch} -eq 1 ]]; then
	PKGS_AUR+="opensnitch "
	SERVICES+="opensnitchd.service "
fi

[[ ${ttf_merriweather} -eq 1 ]] &&
	PKGS_AUR+="ttf-merriweather "

[[ ${vorta} -eq 1 ]] &&
	FLATPAKS+="com.borgbase.Vorta "

if [[ ${dolphin} -eq 1 ]]; then
	PKGS+="kconfig ark dolphin kde-cli-tools kdegraphics-thumbnailers kimageformats qt5-imageformats ffmpegthumbs taglib openexr libjxl android-udev "
	_config_dolphin() {
		local CONF="/home/${WHICH_USER}/.config/dolphinrc"
		kwriteconfig5 --file "${CONF}" --group "General" --key "ShowFullPath" "true"
		kwriteconfig5 --file "${CONF}" --group "General" --key "ShowSpaceInfo" "false"
		kwriteconfig5 --file "/home/${WHICH_USER}/.config/kdeglobals" --group "PreviewSettings" --key "MaximumRemoteSize" "10485760"
		# Disable the Baloo indexer.
		balooctl suspend
		balooctl disable
	}
fi

if [[ ${mpv} -eq 1 ]]; then
	PKGS+="mpv "
	trap 'sudo -H -u "${WHICH_USER}" bash -c "${SYSTEMD_USER_ENV} DENY_SUPERUSER=1 ${GIT_DIR}/scripts/non-SU/software_catalog/mpv_config.sh"' EXIT
fi

[[ ${visual_studio_code} -eq 1 ]] &&
	PKGS_AUR+="visual-studio-code-bin "

[[ ${onlyoffice} -eq 1 ]] &&
	FLATPAKS+="org.onlyoffice.desktopeditors "

[[ ${evince} -eq 1 ]] &&
	PKGS+="evince "

if [[ ${obs_studio} -eq 1 ]]; then
	# v4l2loopback = for Virtual Camera; a good universal way to screenshare.
	PKGS+="obs-studio v4l2loopback-dkms "
	if hash pipewire >&/dev/null; then
		PKGS+="pipewire-v4l2 lib32-pipewire-v4l2 "
	fi
	# Autostart OBS to make it a sort of NVIDIA ShadowPlay or AMD ReLive.
	_obs_autorun() {
		sudo -H -u "${WHICH_USER}" bash -c "${SYSTEMD_USER_ENV} DENY_SUPERUSER=1 cp ${cp_flags} ${GIT_DIR}/files/home/.config/systemd/user/obs-studio.service /home/${WHICH_USER}/.config/systemd/user/"
		sudo -H -u "${WHICH_USER}" bash -c "${SYSTEMD_USER_ENV} systemctl --user enable obs-studio.service"
	}
fi

[[ ${foliate} -eq 1 ]] &&
	PKGS+="foliate "

[[ ${qbittorrent} -eq 1 ]] &&
	PKGS+="qbittorrent "

if [[ ${nomacs} -eq 1 ]]; then
	PKGS+="kconfig nomacs "
	_config_nomacs() {
		mkdir -p "/home/${WHICH_USER}/.config/nomacs"
		local CONF="/home/${WHICH_USER}/.config/nomacs/Image Lounge.conf"
		kwriteconfig5 --file "${CONF}" --group "DisplaySettings" --key "themeName312" "System.css"
		if [[ ${auto_gnome_rice} -eq 1 ]] || [[ ${auto_kde_rice} -eq 1 ]]; then
			kwriteconfig5 --file "${CONF}" --group "DisplaySettings" --key "defaultIconColor" "false"
			kwriteconfig5 --file "${CONF}" --group "DisplaySettings" --key "iconColorRGBA" "4294967295"
		fi
	}
fi

[[ ${yt_dlp} -eq 1 ]] &&
	PKGS+="aria2 atomicparsley ffmpeg rtmpdump yt-dlp "

[[ ${evolution} -eq 1 ]] &&
	PKGS+="evolution "

[[ ${discord} -eq 1 ]] &&
	FLATPAKS+="com.discordapp.Discord "

[[ ${telegram} -eq 1 ]] &&
	FLATPAKS+="org.telegram.desktop "

[[ ${github_desktop} -eq 1 ]] &&
	PKGS_AUR+="github-desktop-bin "

if [[ ${cxx_toolbox} -eq 1 ]]; then
	PKGS+="gdb gperftools valgrind pwndbg rz-cutter rz-ghidra "
	PKGS_AUR+="lib32-gperftools "
fi

[[ ${task_manager} -eq 1 ]] &&
	PKGS+="gnome-system-monitor "

# Anki specifically forces the Qt stylesheets, so Kvantum and others don't work; this is not a Flatpak bug.
[[ ${anki} -eq 1 ]] &&
	FLATPAKS+="net.ankiweb.Anki "

if [[ ${vg_toolbox} -eq 1 ]]; then
	PKGS+="lutris mangohud lib32-mangohud "
	PKGS_AUR+="goverlay-bin "
	FLATPAKS+="net.davidotek.pupgui2 "
fi

# Control Flatpak settings per application
FLATPAKS+="com.github.tchx84.Flatseal "

_pkgs_add
_pkgs_aur_add
_flatpaks_add

# shellcheck disable=SC2086
_systemctl enable --now ${SERVICES}

[[ ${nomacs} -eq 1 ]] && _config_nomacs
[[ ${dolphin} -eq 1 ]] && _config_dolphin
[[ ${obs_studio} -eq 1 ]] && _obs_autorun
[[ ${nomachine} -eq 1 ]] && systemctl disable nxserver.service

_cleanup() {
	chown -R "${WHICH_USER}:${WHICH_USER}" "/home/${WHICH_USER}"
}
