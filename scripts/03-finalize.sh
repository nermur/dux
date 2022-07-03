#!/bin/bash
# shellcheck disable=SC2034
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

clear

# Undo the masked Pacman hooks for initramfs.
pacman -S --quiet --noconfirm --ask=4 --overwrite="*" mkinitcpio

systemctl mask systemd-oomd.service

_cleanup() {
    # Do network changes last.
    PKGS+="iptables-nft "
    _pkgs_add

    chown -R "${WHICH_USER}:${WHICH_USER}" "${GIT_DIR}"
    echo "%wheel ALL=(ALL) ALL" >/etc/sudoers.d/custom_settings
}
trap _cleanup EXIT
