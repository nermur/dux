#!/bin/bash
# shellcheck disable=SC2086
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

_snapper() {
	(bash "/home/${WHICH_USER}/dux/scripts/snapper.sh") |& tee "${GIT_DIR}/logs/snapper.log"
}
_snapper

# Scripts in "_do_last" have to forcefully logout to apply changes.
_do_last() {
	export DUX_INSTALLER=1
	if [[ ${desktop_environment} -eq 1 ]] && [[ ${allow_gnome_rice} -eq 1 ]]; then
		_gnome_rice() {
			(bash "/home/${WHICH_USER}/dux/scripts/rice_GNOME.sh") |& tee "${GIT_DIR}/logs/rice_GNOME.log"
			(sudo -H -u "${WHICH_USER}" DENY_SUPERUSER=1 ${SYSTEMD_USER_ENV} bash "/home/${WHICH_USER}/dux/scripts/non-SU/rice_GNOME_part2.sh") |& tee "${GIT_DIR}/logs/rice_GNOME_part2.log"
		}
		_gnome_rice
	elif [[ ${desktop_environment} -eq 2 ]] && [[ ${allow_kde_rice} -eq 1 ]]; then
		_kde_rice() {
			(bash "/home/${WHICH_USER}/dux/scripts/rice_KDE.sh") |& tee "${GIT_DIR}/logs/rice_KDE.log"
			(sudo -H -u "${WHICH_USER}" DENY_SUPERUSER=1 ${SYSTEMD_USER_ENV} bash "/home/${WHICH_USER}/dux/scripts/non-SU/rice_KDE_part2.sh") |& tee "${GIT_DIR}/logs/rice_KDE_part2.log"
		}
		_kde_rice
	fi

	chown -R "${WHICH_USER}:${WHICH_USER}" /home/"${WHICH_USER}"/{dux,dux_backups}
}
trap _do_last EXIT
