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

	if [[ ${amd_graphics_force_radeon} -ne 1 ]]; then
		local PARAMS="radeon.si_support=0 amdgpu.si_support=1 radeon.cik_support=0 amdgpu.cik_support=1"
		_modify_kernel_parameters
	fi

	if [[ ${amd_graphics_sysfs} -eq 1 ]]; then
		local PARAMS="amdgpu.ppfeaturemask=0xffffffff"
		_modify_kernel_parameters
	fi
}

_nouveau_setup() {
	PKGS+="xf86-video-nouveau "
	\cp "${cp_flags}" "${GIT_DIR}"/files/etc/modprobe.d/nouveau.conf "/etc/modprobe.d/"

	_nouveau_reclocking() {
		# Kernel parameter only; reclocking later (say, after graphical.target) is likely to crash the GPU.
		NOUVEAU_RECLOCK="nouveau.config=NvClkMode=$((16#0f))"
		local PARAMS="${NOUVEAU_RECLOCK}"
		_modify_kernel_parameters
	}

	# Works fine, though using X11 instead of Wayland is bad on Nouveau
	printf "needs_root_rights = no" >/etc/X11/Xwrapper.config

	_nouveau_custom_parameters() {
		if [[ ${nouveau_custom_parameters} -eq 1 ]]; then
			# atomic=0: Atomic mode-setting reduces potential flickering while also being quicker, the result is buttery-smooth rendering under Wayland; disabled due to instability
			# NvMSI=1: Message Signaled Interrupts lowers system latency ("DPC latency" on Windows) while increasing GPU performance
			#
			# init_on_alloc=0 init_on_free=0: https://gitlab.freedesktop.org/xorg/driver/xf86-video-nouveau/-/issues/547
			# cipher=0: https://gitlab.freedesktop.org/xorg/driver/xf86-video-nouveau/-/issues/547#note_1097449
			local PARAMS="init_on_alloc=0 init_on_free=0 nouveau.atomic=0 nouveau.config=NvMSI=1 nouveau.config=cipher=0"
			_modify_kernel_parameters

			_nouveau_reclocking
		fi
	}
}

_nvidia_setup() {
	# Xorg will break on trying to load Nouveau first if this file exists
	[[ -e "/etc/X11/xorg.conf.d/20-nouveau.conf" ]] &&
		rm -f /etc/X11/xorg.conf.d/20-nouveau.conf

	\cp "${cp_flags}" "${GIT_DIR}"/files/etc/modprobe.d/nvidia.conf "/etc/modprobe.d/"

	_nvidia_enable_drm() {
		local PARAMS="nvidia-drm.modeset=1"
		_modify_kernel_parameters
	}

	_nvidia_force_max_performance() {
		if [[ ${nvidia_force_max_performance} -eq 1 ]]; then
			sudo -H -u "${WHICH_USER}" bash -c "${SYSTEMD_USER_ENV} DENY_SUPERUSER=1 cp ${cp_flags} ${GIT_DIR}/files/home/.config/systemd/user/nvidia-max-performance.service /home/${WHICH_USER}/.config/systemd/user/"
			sudo -H -u "${WHICH_USER}" bash -c "${SYSTEMD_USER_ENV} systemctl --user enable nvidia-max-performance.service"

			# Allow the "Prefer Maximum Performance" PowerMizer setting on laptops
			local PARAMS="nvidia.NVreg_RegistryDwords=OverrideMaxPerf=0x1"
			_modify_kernel_parameters
		fi
	}

	_nvidia_sysfs() {
		# Running Xorg rootless breaks clock/power/fan control: https://gitlab.com/leinardi/gwe/-/issues/92
		printf "needs_root_rights = yes" >/etc/X11/Xwrapper.config

		# GreenWithEnvy: Overclocking, power & fan control, GPU graphs; akin to MSI Afterburner
		nvidia-xconfig --cool-bits=28
		FLATPAKS+="com.leinardi.gwe "
	}

	[[ ${nvidia_force_pcie_gen2} -eq 1 ]] &&
		sed -i "s/NVreg_EnablePCIeGen3=1/NVreg_EnablePCIeGen3=0/" /etc/modprobe.d/nvidia.conf
	[[ ${nvidia_stream_memory_operations} -eq 1 ]] &&
		sed -i "s/NVreg_EnableStreamMemOPs=0/NVreg_EnableStreamMemOPs=1/" /etc/modprobe.d/nvidia.conf

	_nvidia_enable_drm
	[[ ${nvidia_force_max_performance} -eq 1 ]] && _nvidia_force_max_performance
	[[ ${nvidia_sysfs} -eq 1 ]] && _nvidia_sysfs
}

# grep: -P/--perl-regexp benched faster than -E/--extended-regexp
# shellcheck disable=SC2249
case $(lspci | grep -P "VGA|3D|Display" | grep -Po "NVIDIA|AMD/ATI") in
*"NVIDIA"*)
	if [[ ${no_nvidia_tweaks} -ne 1 ]] && [[ ${nvidia_driver_series} -eq 4 ]]; then
		_nouveau_setup
	elif [[ ${no_nvidia_tweaks} -ne 1 ]] && ((1 >= nvidia_driver_series <= 3)); then
		_nvidia_setup
	fi
	;;&
*"AMD/ATI"*)
	_amd_setup
	;;
esac

if [[ ${IS_CHROOT} -eq 0 ]] && [[ ${PARAMS_CHANGED} -eq 1 ]]; then
	grub-mkconfig -o /boot/grub/grub.cfg
fi

_flatpaks_add || :
