#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

clear

if [[ ${IS_CHROOT} -eq 1 ]]; then
    echo -e "\nERROR: Do not run this script inside a chroot!\n"
    exit 1
fi

if [[ ${bootloader_type} -eq 1 ]]; then
    PKGS+="grub-btrfs "
    _pkgs_add
elif [[ ${bootloader_type} -eq 2 ]]; then
    # trbs, the developer of python-pid, uses an expired PGP key.
    gpg --recv-keys 13FFEEE3DF809D320053C587D6E95F20305701A1
    PKGS_AUR+="refind-btrfs "
    _pkgs_aur_add
fi

# Snapper refuses to create a config if this directory exists.
btrfs property set -ts /.snapshots ro false || :
umount -flRq /.snapshots || :
_move2bkup {/.snapshots,/etc/snapper/configs/root} &&
    mkdir "${mkdir_flags}" /etc/snapper/configs

if [[ ${DEBUG} -eq 1 ]]; then
    snapper -q delete-config || :
    snapper -q -c root create-config /
else
    snapper -q delete-config &>/dev/null || :
    snapper -q -c root create-config / &>/dev/null
fi
cp "${cp_flags}" "${GIT_DIR}"/files/etc/snapper/configs/root "/etc/snapper/configs/"

if [[ ${bootloader_type} -eq 1 ]]; then
    _grub_btrfs_pacman_hook() {
        _move2bkup "/usr/share/libalpm/scripts/grub-mkconfig"
        _move2bkup "/etc/pacman.d/hooks/zz_snap-pac-grub-post.hook"

        cp "${cp_flags}" "${GIT_DIR}"/files/usr/share/libalpm/scripts/grub-mkconfig "/usr/share/libalpm/scripts/"
        cp "${cp_flags}" "${GIT_DIR}"/files/etc/pacman.d/hooks/zz_snap-pac-grub-post.hook "/etc/pacman.d/hooks/"

        # GRUB_BTRFS_LIMIT="10": Don't display more than 10 snapshots.
        # GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND="false": Don't specify every snapshot found, instead say "Found 10 snapshot(s)".
        # GRUB_BTRFS_SHOW_TOTAL_SNAPSHOTS_FOUND="true": Required to say "Found 10 snapshot(s)".
        sed -i -e "s/.GRUB_BTRFS_LIMIT/GRUB_BTRFS_LIMIT/" -e "s/.GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND/GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND/" -e "s/.GRUB_BTRFS_SHOW_TOTAL_SNAPSHOTS_FOUND/GRUB_BTRFS_SHOW_TOTAL_SNAPSHOTS_FOUND/" \
            -e "s/GRUB_BTRFS_LIMIT.*/GRUB_BTRFS_LIMIT=\"10\"/" \
            -e "s/GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND.*/GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND=\"false\"/" \
            -e "s/GRUB_BTRFS_SHOW_TOTAL_SNAPSHOTS_FOUND.*/GRUB_BTRFS_SHOW_TOTAL_SNAPSHOTS_FOUND=\"true\"/" \
            "/etc/default/grub-btrfs/config"
    }
    _grub_btrfs_pacman_hook
elif [[ ${bootloader_type} -eq 2 ]]; then
    SERVICES+="refind-btrfs.service snapper-boot.timer "
fi

SERVICES+="snapper-cleanup.timer snapper-timeline.timer "
# shellcheck disable=SC2086
_systemctl enable ${SERVICES}
