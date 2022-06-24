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

if hash timeshift >&/dev/null; then
    pacman -Rdd --noconfirm --ask=4 timeshift timeshift-autosnap-manjaro
fi

PKGS+="snapper "
_pkgs_add

if [[ ${DEBUG} -eq 1 ]]; then
    snapper create-config / || :
else
    snapper -q create-config / &>/dev/null || :
fi
\cp "${cp_flags}" "${GIT_DIR}"/files/etc/snapper/configs/root "/etc/snapper/configs/"
