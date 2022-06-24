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

mkinitcpio -P

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

_cleanup() {
    chown -R "${WHICH_USER}:${WHICH_USER}" "${GIT_DIR}"
    echo "%wheel ALL=(ALL) ALL" >/etc/sudoers.d/custom_settings
}
trap _cleanup EXIT
