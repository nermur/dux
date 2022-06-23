#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

if [[ ${IS_CHROOT} -eq 1 ]]; then
    echo -e "\nERROR: Do not run this script inside a chroot!\n"
	exit 1
fi

PKGS+="kvantum qt6-svg papirus-icon-theme "
PKGS_AUR+="papirus-folders-git "
_pkgs_add
_pkgs_aur_add

[[ ${DUX_INSTALLER} -ne 1 ]] &&
    (sudo -H -u "${WHICH_USER}" DENY_SUPERUSER=1 ${SYSTEMD_USER_ENV} bash "/home/${WHICH_USER}/dux/scripts/non-SU/rice_KDE_part2.sh") |& tee "${GIT_DIR}/logs/rice_KDE_part2.log"
