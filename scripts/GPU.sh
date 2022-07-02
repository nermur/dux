#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

_amd_setup() {
	\cp "${cp_flags}" "${GIT_DIR}"/files/etc/modprobe.d/amdgpu.conf "/etc/modprobe.d/"

	\cp "${cp_flags}" "${GIT_DIR}"/files/etc/modprobe.d/radeon.conf "/etc/modprobe.d/"

	if [[ ${amd_graphics_force_radeon} -eq 1 ]]; then
		echo "MODULES+=(radeon)" >>/etc/mkinitcpio.conf
	else
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
	# Early load KMS driver
	if ! grep -q "i915" /etc/mkinitcpio.conf; then
		echo -e "\nMODULES+=(i915)" >>/etc/mkinitcpio.conf
	fi

	REGENERATE_INITRAMFS=1
}

# grep: -P/--perl-regexp benched faster than -E/--extended-regexp
# shellcheck disable=SC2249
case $(lspci | grep -P "VGA|3D|Display" | grep -Po "NVIDIA|AMD/ATI|Intel") in
*"NVIDIA"*)
	_nvidia_setup() {
		if [[ ${avoid_nvidia_gpus} -ne 1 ]] && [[ ${DUX_INSTALLER} -ne 1 ]]; then
			(bash "${GIT_DIR}/scripts/_NVIDIA.sh") |& tee "${GIT_DIR}/logs/_NVIDIA.log"
		fi
	}
	_nvidia_setup || :
	;;&
*"AMD/ATI"*)
	_amd_setup
	;;&
*"Intel"*)
	_intel_setup
	;;
esac

if [[ ${IS_CHROOT} -eq 0 ]]; then
	[[ ${REGENERATE_INITRAMFS} -eq 1 ]] &&
		_build_initramfs

	[[ ${PARAMS_CHANGED} -eq 1 ]] &&
		grub-mkconfig -o /boot/grub/grub.cfg
fi

cleanup() {
	mkdir "${mkdir_flags}" "${BACKUPS}/etc/modprobe.d"
	chown -R "${WHICH_USER}:${WHICH_USER}" "${BACKUPS}/etc/modprobe.d"
}
trap cleanup EXIT
