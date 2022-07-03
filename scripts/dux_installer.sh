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

# Make a backup of the system now before touching anything else.
pacman -S --quiet --noconfirm --ask=4 --needed timeshift timeshift-autosnap-manjaro
timeshift --create --comments "Before applying Dux"

_01() {
    ("${GIT_DIR}/scripts/01-root.sh") |& tee "${GIT_DIR}/logs/01-root.log" || return
}
_01

_02() {
    (sudo -u "${WHICH_USER}" DENY_SUPERUSER=1 ${SYSTEMD_USER_ENV} bash "${GIT_DIR}/scripts/02-nonroot.sh") |& tee "${GIT_DIR}/logs/02-nonroot.log" || return
}
_02

_pipewire() {
    ("${GIT_DIR}/scripts/Pipewire.sh") |& tee "${GIT_DIR}/logs/Pipewire.log" || return
}
_pipewire

_gpu() {
    [[ ${disable_gpu_tweaks} -ne 1 ]] &&
        ("${GIT_DIR}/scripts/GPU.sh") |& tee "${GIT_DIR}/logs/GPU.log" || return
}
_gpu

if [[ ${XDG_SESSION_DESKTOP} = "GNOME" ]] && [[ ${auto_gnome_rice} -eq 1 ]]; then
    ("${GIT_DIR}/scripts/rice_GNOME.sh") |& tee "${GIT_DIR}/logs/rice_GNOME.log" || return

    (sudo -H -u "${WHICH_USER}" DENY_SUPERUSER=1 ${SYSTEMD_USER_ENV} bash "${GIT_DIR}/scripts/non-SU/rice_GNOME_part2.sh") |& tee "${GIT_DIR}/logs/rice_GNOME_part2.log" || return

elif [[ ${XDG_SESSION_DESKTOP} = "KDE" ]] && [[ ${automatic_kde_rice} -eq 1 ]]; then
    ("${GIT_DIR}/scripts/rice_KDE.sh") |& tee "${GIT_DIR}/logs/rice_KDE.log" || return

    (sudo -H -u "${WHICH_USER}" DENY_SUPERUSER=1 ${SYSTEMD_USER_ENV} bash "${GIT_DIR}/scripts/non-SU/rice_KDE_part2.sh") |& tee "${GIT_DIR}/logs/rice_KDE_part2.log" || return
fi

_03() {
    ("${GIT_DIR}/scripts/03-finalize.sh") |& tee "${GIT_DIR}/logs/03-finalize.log" || return
}
_03

# OBS Studio installer depends on kernel headers being present, thus it's past _03.
_software_catalog(){
    [[ ${auto_software_catalog} -eq 1 ]] &&
        ("${GIT_DIR}/scripts/software_catalog.sh") |& tee "${GIT_DIR}/logs/software_catalog.log" || return
}
_software_catalog

whiptail --yesno "A reboot is required to complete installation.\nAfter rebooting, read through 0.3_booted.adoc.\nReboot now?" 0 0 &&
    reboot -f
