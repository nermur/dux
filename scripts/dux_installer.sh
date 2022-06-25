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

export DUX_INSTALLER=1

mkdir -p "${GIT_DIR}/logs"
# Makes scripts below executable.
chmod +x -R "${GIT_DIR}"

clear

# Prevents many unnecessary initramfs generations, speeding up the install process drastically.
ln -sf /dev/null /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
ln -sf /dev/null /usr/share/libalpm/hooks/90-mkinitcpio-install.hook
_repair_mkinitcpio() {
    [[ ! -s "/usr/share/libalpm/hooks/60-mkinitcpio-remove.hook" || ! -s "/usr/share/libalpm/hooks/90-mkinitcpio-install.hook" ]] &&
        pacman -S --quiet --noconfirm --ask=4 --overwrite="*" mkinitcpio
}
trap _repair_mkinitcpio EXIT

_snapper_part1() {
    ("${GIT_DIR}/scripts/snapper_part1.sh") |& tee "${GIT_DIR}/logs/snapper_part1.log"
}
_snapper_part1

# Make a backup of the system now before touching anything else.
snapper create -t single -d "Before Dux installation"

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

if [[ ${XDG_SESSION_DESKTOP} = "GNOME" ]] && [[ ${allow_gnome_rice} -eq 1 ]]; then
    _gnome_rice() {
        ("${GIT_DIR}/scripts/rice_GNOME.sh") |& tee "${GIT_DIR}/logs/rice_GNOME.log"
        (sudo -H -u "${WHICH_USER}" DENY_SUPERUSER=1 ${SYSTEMD_USER_ENV} bash "${GIT_DIR}/scripts/non-SU/rice_GNOME_part2.sh") |& tee "${GIT_DIR}/logs/rice_GNOME_part2.log"
    }
    _gnome_rice
elif [[ ${XDG_SESSION_DESKTOP} = "KDE" ]] && [[ ${allow_kde_rice} -eq 1 ]]; then
    _kde_rice() {
        ("${GIT_DIR}/scripts/rice_KDE.sh") |& tee "${GIT_DIR}/logs/rice_KDE.log"
        (sudo -H -u "${WHICH_USER}" DENY_SUPERUSER=1 ${SYSTEMD_USER_ENV} bash "${GIT_DIR}/scripts/non-SU/rice_KDE_part2.sh") |& tee "${GIT_DIR}/logs/rice_KDE_part2.log"
    }
    _kde_rice
fi

_snapper_part2() {
    ("${GIT_DIR}/scripts/snapper_part2.sh") |& tee "${GIT_DIR}/logs/snapper_part2.log"
}
_snapper_part2

_03() {
    ("${GIT_DIR}/scripts/03-finalize.sh") |& tee "${GIT_DIR}/logs/03-finalize.log" || return
    _repair_mkinitcpio(){}
}
_03

whiptail --yesno "A reboot is required to complete installation.\nAfter rebooting, read through 0.3_booted.adoc.\nReboot now?" 0 0 &&
    reboot -f
