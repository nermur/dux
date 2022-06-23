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
if [[ ${use_disk_encryption} -eq 1 ]]; then
	if cryptsetup status "lukspart" | grep -q "inactive"; then
		echo -e "\nERROR: Forgot to mount the LUKS2 partition as 'lukspart'?\n"
		exit 1
	fi
fi

mkdir -p "${GIT_DIR}/logs"
# Makes scripts below executable.
chmod +x -R "${GIT_DIR}"

clear

_password_prompt() {
	read -rp "Enter a new password for the username \"${INITIAL_USER}\": " DESIREDPW
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
	("${GIT_DIR}/scripts/01-pre_chroot.sh") |& tee "${GIT_DIR}/logs/01-pre_chroot.log" || return
}
_01

# /mnt needs access to Dux's contents.
[[ -d "/mnt/root/dux" ]] &&
	rm -rf "/mnt/root/dux"
cp -f -R "${GIT_DIR}" "/mnt/root"

_02() {
	(arch-chroot /mnt "${GIT_DIR}/scripts/02-post_chroot_root.sh") |& tee "${GIT_DIR}/logs/02-post_chroot_root.log" || return
}
_02

_03() {
	(arch-chroot /mnt sudo -u "${INITIAL_USER}" DENY_SUPERUSER=1 ${SYSTEMD_USER_ENV} bash "/home/${INITIAL_USER}/dux/scripts/03-post_chroot_user.sh") |& tee "${GIT_DIR}/logs/03-post_chroot_user.log" || return
}
_03

_pipewire() {
	(arch-chroot /mnt "${GIT_DIR}/scripts/Pipewire.sh") |& tee "${GIT_DIR}/logs/Pipewire.log" || return
}
_pipewire

_gpu() {
	[[ ${disable_gpu} -ne 1 ]] &&
		(arch-chroot /mnt "${GIT_DIR}/scripts/GPU.sh") |& tee "${GIT_DIR}/logs/GPU.log" || return
}
_gpu

_desktop_environment() {
	case ${desktop_environment} in
	1)
		(arch-chroot /mnt "${GIT_DIR}/scripts/GNOME.sh") |& tee "${GIT_DIR}/logs/GNOME.log" || return
		;;
	2)
		(arch-chroot /mnt "${GIT_DIR}/scripts/KDE.sh") |& tee "${GIT_DIR}/logs/KDE.log" || return
		;;
	*)
		printf "\nNOTICE: No desktop environment was selected.\n"
		;;
	esac
}
_desktop_environment

_04() {
	(arch-chroot /mnt "${GIT_DIR}/scripts/04-finalize.sh") |& tee "${GIT_DIR}/logs/04-finalize.log" || return
}
_04

rm -rf "/mnt/root/dux/logs"
cp -f -R "${GIT_DIR}/logs" "/mnt/root/dux"

rm -rf "/mnt/home/${INITIAL_USER:?}/dux/logs"
cp -f -R "${GIT_DIR}/logs" "/mnt/home/${INITIAL_USER}/dux"

# Set correct permissions.
_permissions() {
	(arch-chroot /mnt "chown" -R "${INITIAL_USER}:${INITIAL_USER}" /home/"${INITIAL_USER}"/{dux,dux_backups})
}
_permissions

whiptail --yesno "A reboot is required to complete installation.\nAfter rebooting, read through 0.3_booted.adoc.\nReboot now?" 0 0 &&
	reboot -f
