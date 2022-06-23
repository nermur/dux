#!/bin/bash
# shellcheck disable=SC2034
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

clear

# Now is the right time to generate a initramfs.
pacman -S --quiet --noconfirm --ask=4 --overwrite="*" mkinitcpio
_move2bkup "/etc/mkinitcpio.conf" &&
    cp "${cp_flags}" "${GIT_DIR}"/files/etc/mkinitcpio.conf "/etc/"

PKGS+="linux linux-headers "
_pkgs_add || :

if lspci | grep -P "VGA|3D|Display" | grep -q "NVIDIA"; then
    HAS_NVIDIA_GPU=1
fi

if [[ ${HAS_NVIDIA_GPU} -eq 1 ]] && ((1 >= nvidia_driver_series <= 3)); then
    (bash "${GIT_DIR}/scripts/_NVIDIA.sh") |& tee "${GIT_DIR}/logs/_NVIDIA.log" || return
else
    # Still ran inside _NVIDIA.sh
    [[ ${bootloader_type} -eq 1 ]] &&
        grub-mkconfig -o /boot/grub/grub.cfg
fi

_snapper() {
    (bash "${GIT_DIR}/scripts/snapper.sh") |& tee "${GIT_DIR}/logs/snapper.log"
}
_snapper

export DUX_INSTALLER=1
if [[ ${XDG_SESSION_DESKTOP} = "GNOME" ]] && [[ ${allow_gnome_rice} -eq 1 ]]; then
    _gnome_rice() {
        (bash "/home/${WHICH_USER}/dux/scripts/rice_GNOME.sh") |& tee "${GIT_DIR}/logs/rice_GNOME.log"
        (sudo -H -u "${WHICH_USER}" DENY_SUPERUSER=1 ${SYSTEMD_USER_ENV} bash "/home/${WHICH_USER}/dux/scripts/non-SU/rice_GNOME_part2.sh") |& tee "${GIT_DIR}/logs/rice_GNOME_part2.log"
    }
    _gnome_rice
elif [[ ${XDG_SESSION_DESKTOP} = "KDE" ]] && [[ ${allow_kde_rice} -eq 1 ]]; then
    _kde_rice() {
        (bash "/home/${WHICH_USER}/dux/scripts/rice_KDE.sh") |& tee "${GIT_DIR}/logs/rice_KDE.log"
        (sudo -H -u "${WHICH_USER}" DENY_SUPERUSER=1 ${SYSTEMD_USER_ENV} bash "/home/${WHICH_USER}/dux/scripts/non-SU/rice_KDE_part2.sh") |& tee "${GIT_DIR}/logs/rice_KDE_part2.log"
    }
    _kde_rice
fi

_cleanup() {
    chown -R "${WHICH_USER}:${WHICH_USER}" "${GIT_DIR}"
    echo "%wheel ALL=(ALL) ALL" >/etc/sudoers.d/custom_settings
}
trap _cleanup EXIT
