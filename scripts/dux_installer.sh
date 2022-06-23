#!/bin/bash
# shellcheck disable=SC2086
set +H
# "|| return" is used as an error handler.
# NOTE: set -e has to be present in the scripts executed here for this to work.
set -eo pipefail

# Prevent installation issues arising from there being an inaccurate system time.
timedatectl set-ntp true
wait
systemctl restart systemd-timesyncd.service
wait

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

if ! grep -q "'archiso'" /etc/mkinitcpio.d/linux.preset; then
	echo -e "\nERROR: Do not run this script outside of the Arch Linux ISO!\n"
	exit 1
fi

mkdir -p "${GIT_DIR}/logs"
# Makes scripts below executable.
chmod +x -R "${GIT_DIR}"

clear

_password_prompt() {
	read -rp "Enter a new password for the username \"${WHICH_USER}\": " DESIREDPW
	if [[ -z ${DESIREDPW} ]]; then
		echo -e "\nNo password was entered, please try again.\n"
		_password_prompt
	fi

	read -rp $'\nPlease repeat your password: ' PWCODE
	if [[ ${DESIREDPW} == "${PWCODE}" ]]; then
		export PWCODE
	else
		echo -e "\nPasswords do not match, please try again.\n"
		_password_prompt
	fi
}
_password_prompt

_01() {
	("${GIT_DIR}/scripts/01-root.sh") |& tee "${GIT_DIR}/logs/01-root.log" || return
}
_01

_02() {
	(sudo -u "${WHICH_USER}" DENY_SUPERUSER=1 ${SYSTEMD_USER_ENV} bash "${GIT_DIR}/scripts/02-nonroot.sh") |& tee "${GIT_DIR}/logs/02-nonroot.sh" || return
}
_02

_pipewire() {
	("${GIT_DIR}/scripts/Pipewire.sh") |& tee "${GIT_DIR}/logs/Pipewire.log" || return
}
_pipewire

_gpu() {
	[[ ${disable_gpu} -ne 1 ]] &&
		("${GIT_DIR}/scripts/GPU.sh") |& tee "${GIT_DIR}/logs/GPU.log" || return
}
_gpu

_desktop_environment() {
	case ${desktop_environment} in
	1)
		("${GIT_DIR}/scripts/GNOME.sh") |& tee "${GIT_DIR}/logs/GNOME.log" || return
		;;
	2)
		("${GIT_DIR}/scripts/KDE.sh") |& tee "${GIT_DIR}/logs/KDE.log" || return
		;;
	*)
		printf "\nNOTICE: No desktop environment was selected.\n"
		;;
	esac
}
_desktop_environment

_03() {
	("${GIT_DIR}/scripts/03-finalize.sh") |& tee "${GIT_DIR}/logs/03-finalize.log" || return
}
_03

# Set correct permissions.
_permissions() {
	(chown -R "${WHICH_USER}:${WHICH_USER}" "${GIT_DIR}")
}
_permissions

whiptail --yesno "A reboot is required to complete installation.\nAfter rebooting, read through 0.3_booted.adoc.\nReboot now?" 0 0 &&
	reboot -f
