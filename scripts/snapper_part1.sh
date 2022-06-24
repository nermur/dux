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

PKGS+="snapper "
_pkgs_add

# Snapper refuses to create a config if this directory exists.
btrfs property set -ts /.snapshots ro false || :
umount -flRq /.snapshots || :

rm -f {/.snapshots,/etc/conf.d/snapper}
rm -rf /etc/snapper/configs

mkdir "${mkdir_flags}" /etc/snapper/configs
touch /etc/conf.d/snapper

if [[ ${DEBUG} -eq 1 ]]; then
    snapper delete-config || :
    snapper create-config /
else
    snapper -q delete-config &>/dev/null || :
    snapper -q create-config / &>/dev/null
fi
\cp "${cp_flags}" "${GIT_DIR}"/files/etc/snapper/configs/root "/etc/snapper/configs/"
