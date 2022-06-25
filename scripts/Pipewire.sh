#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"

PKGS+="manjaro-pipewire alsa-firmware sof-firmware alsa-ucm-conf \
pipewire wireplumber pipewire-alsa pipewire-pulse pipewire-jack pipewire-zeroconf pipewire-v4l2 \
lib32-pipewire lib32-pipewire-jack gst-plugin-pipewire \
libpulse lib32-libpulse alsa-plugins lib32-alsa-plugins alsa-lib lib32-alsa-lib "
_pkgs_add

# Maintain Pipewire performance without resorting to adding ${WHICH_USER} to 'realtime' group
mkdir "${mkdir_flags}" /etc/security/limits.d
cat <<EOF >/etc/security/limits.d/"${WHICH_USER}".conf
${WHICH_USER}	soft	memlock	64
${WHICH_USER}	hard	memlock	128
EOF
