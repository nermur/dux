#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

_pkgs_aur_add() {
	[[ -n ${PKGS_AUR} ]] &&
		# -Sdd bypasses a dependency cycle problem proprietary NVIDIA drivers have (only if different proprietary version is installed, say 'nvidia-lts')
		sudo -H -u "${WHICH_USER}" bash -c "${SYSTEMD_USER_ENV} DENY_SUPERUSER=1 paru -Sdd --quiet --noconfirm --useask --needed --skipreview ${PKGS_AUR}"
}

PKGS+="lib32-mesa lib32-ocl-icd lib32-vulkan-icd-loader mesa ocl-icd vulkan-icd-loader "

_amd_setup() {
	PKGS+="libva-mesa-driver mesa-vdpau libva-vdpau-driver \
	lib32-libva-mesa-driver lib32-mesa-vdpau lib32-libva-vdpau-driver "
	_move2bkup "/etc/modprobe.d/amdgpu.conf" &&
		cp "${cp_flags}" "${GIT_DIR}"/files/etc/modprobe.d/amdgpu.conf "/etc/modprobe.d/"

	_move2bkup "/etc/modprobe.d/radeon.conf" &&
		cp "${cp_flags}" "${GIT_DIR}"/files/etc/modprobe.d/radeon.conf "/etc/modprobe.d/"

	if [[ ${amd_graphics_force_radeon} -eq 1 ]]; then
		_move2bkup "/etc/modprobe.d/amdgpu.conf"
		echo "MODULES+=(radeon)" >>/etc/mkinitcpio.conf
	else
		_move2bkup "/etc/modprobe.d/radeon.conf"
		echo "MODULES+=(amdgpu)" >>/etc/mkinitcpio.conf
		_amd_graphics_sysfs() {
			if [[ ${amd_graphics_sysfs} -eq 1 ]]; then
				local PARAMS="amdgpu.ppfeaturemask=0xffffffff"
				_modify_kernel_parameters
			fi
		}
		_amd_graphics_sysfs
	fi

	REGENERATE_INITRAMFS=1
}

_intel_setup() {
	PKGS+="intel-media-sdk vulkan-intel "

	[[ ${intel_video_accel} -eq 1 ]] &&
		PKGS+="libva-intel-driver lib32-libva-intel-driver "
	[[ ${intel_video_accel} -eq 2 ]] &&
		PKGS+="intel-media-driver "

	# Early load KMS driver
	if ! grep -q "i915" /etc/mkinitcpio.conf; then
		echo -e "\nMODULES+=(i915)" >>/etc/mkinitcpio.conf
	fi

	REGENERATE_INITRAMFS=1
}

# grep: -P/--perl-regexp benched faster than -E/--extended-regexp
# shellcheck disable=SC2249
case $(lspci | grep -P "VGA|3D|Display" | grep -Po "NVIDIA|AMD/ATI|Intel|VMware SVGA|Red Hat") in
*"NVIDIA"*)
	_nvidia_setup() {
		if [[ ${avoid_nvidia_gpus} -ne 1 ]]; then
			(bash "${GIT_DIR}/scripts/_NVIDIA.sh") |& tee "${GIT_DIR}/logs/_NVIDIA.log" || return
		fi
	}
	_nvidia_setup
	;;&
*"AMD/ATI"*)
	[[ ${avoid_amd_gpus} -ne 1 ]] &&
		_amd_setup
	;;&
*"Intel"*)
	[[ ${avoid_intel_gpus} -ne 1 ]] &&
		_intel_setup
	;;&
*"VMware"*)
	PKGS+="xf86-video-vmware "
	;;&
*"Red Hat"*)
	PKGS+="xf86-video-qxl spice-vdagent qemu-guest-agent "
	;;
esac

_pkgs_add
_pkgs_aur_add || :
_flatpaks_add || :

if [[ ${IS_CHROOT} -eq 0 ]]; then
	[[ ${REGENERATE_INITRAMFS} -eq 1 ]] &&
		mkinitcpio -P

	[[ ${REGENERATE_GRUB2_CONFIG} -eq 1 ]] &&
		grub-mkconfig -o /boot/grub/grub.cfg
fi

cleanup() {
	mkdir "${mkdir_flags}" "${BACKUPS}/etc/modprobe.d"
	chown -R "${WHICH_USER}:${WHICH_USER}" "${BACKUPS}/etc/modprobe.d"
}
trap cleanup EXIT
