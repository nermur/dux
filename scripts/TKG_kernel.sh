#!/bin/bash
# shellcheck disable=SC1091
set +H
set -e

export DENY_SUPERUSER=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
unset DENY_SUPERUSER

CPU_VENDOR=$(grep -m1 'vendor' /proc/cpuinfo | cut -f2 -d' ')
MARCH=$(gcc -march=native -Q --help=target | grep -oP '(?<=-march=).*' -m1 | awk '{$1=$1};1')

case $(gcc -march=native -Q --help=target | grep -e '-march=' | cut -f3 | sed '2d') in
# AMD
"k8-sse3") MARCH_TKG="k8sse3" ;;
"btver1") MARCH_TKG="bobcat" ;;
"btver2") MARCH_TKG="jaguar" ;;
"bdver1") MARCH_TKG="bulldozer" ;;
"bdver2") MARCH_TKG="piledriver" ;;
"bdver3") MARCH_TKG="steamroller" ;;
"bdver4") MARCH_TKG="excavator" ;;
"znver1") MARCH_TKG="zen" ;;
"znver2") MARCH_TKG="zen2" ;;
"znver3") MARCH_TKG="zen3" ;;
    # Intel
"skylake-avx512") MARCH_TKG="skylakex" ;;
"icelake-client") MARCH_TKG="icelake" ;;
"icelake-server") MARCH_TKG="icelake" ;;
"goldmont-plus") MARCH_TKG="goldmontplus" ;;
*) ;;
esac

if [[ ! -d "/home/${WHICH_USER}/linux-tkg" ]]; then
    git clone https://github.com/Frogging-Family/linux-tkg "/home/${WHICH_USER}/linux-tkg"
else
    cd /home/"${WHICH_USER}"/linux-tkg &&
        if git rev-parse --git-dir 2>&1; then
            git pull
        else
            cd .. && rm -rf "/home/${WHICH_USER}/linux-tkg"
            git clone https://github.com/Frogging-Family/linux-tkg "/home/${WHICH_USER}/linux-tkg"
            cd /home/"${WHICH_USER}"/linux-tkg
        fi
fi

mkdir -p /home/"${WHICH_USER}"/.config/frogminer
cp "${cp_flags}" /home/"${WHICH_USER}"/linux-tkg/customization.cfg /home/"${WHICH_USER}"/.config/frogminer/linux-tkg.cfg

sed -i -e 's/_distro.*/_distro="Arch"/' \
    -e 's/_force_all_threads.*/_force_all_threads="false"/' \
    -e 's/_menunconfig.*/_menunconfig="false"/' \
    -e 's/_diffconfig.*/_diffconfig="false"/' \
    -e 's/_cpusched.*/_cpusched="upds"/' \
    -e 's/_compiler.*/_compiler="gcc"/' \
    -e 's/_sched_yield_type.*/_sched_yield_type="0"/' \
    -e 's/_rr_interval.*/_rr_interval="default"/' \
    -e 's/_tickless.*/_tickless="1"/' \
    -e 's/_acs_override.*/_acs_override="false"/' \
    -e 's/_bcachefs.*/_bcachefs="false"/' \
    -e 's/_anbox.*/_anbox="true"/' \
    -e 's/_timer_freq.*/_timer_freq="500"/' \
    -e 's/_tcp_cong_alg.*/_tcp_cong_alg="bbr"/' \
    /home/"${WHICH_USER}"/.config/frogminer/linux-tkg.cfg

case "${CPU_VENDOR}" in
"AuthenticAMD")
    # SMT forces shared CPU cycles (resource usage) with all CPU logical cores.
    # Linux's SMT is bad for software that need to be left to their vices (video games, virtual machines).
    sed -i 's/_runqueue_sharing.*/_runqueue_sharing="mc-llc"/' /home/"${WHICH_USER}"/.config/frogminer/linux-tkg.cfg
    ;;
"GenuineIntel")
    sed -i 's/_runqueue_sharing.*/_runqueue_sharing="mc"/' /home/"${WHICH_USER}"/.config/frogminer/linux-tkg.cfg
    ;;
*)
    echo -e "NOTICE: Unsupported CPU vendor!\nSupported CPU vendors: AMD, Intel."
    ;;
esac

if [[ -n "${MARCH_TKG}" ]]; then
    sed -i "s/_processor_opt.*/_processor_opt=\"${MARCH_TKG}\"/" /home/"${WHICH_USER}"/.config/frogminer/linux-tkg.cfg
else
    sed -i "s/_processor_opt.*/_processor_opt=\"${MARCH}\"/" /home/"${WHICH_USER}"/.config/frogminer/linux-tkg.cfg
fi

echo -e "\nYou can now compile linux-tkg.\nOptionally, check /home/${WHICH_USER}/.config/frogminer/linux-tkg.cfg to see if the configuration is to your liking."