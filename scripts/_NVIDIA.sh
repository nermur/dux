#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

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

	# Have to rebuild initramfs to apply new kernel module config changes by /etc/modprobe.d
	REGENERATE_INITRAMFS=1
}

_nvidia_setup() {
	PKGS+="xorg-server-devel nvidia-prime "
	\cp "${cp_flags}" "${GIT_DIR}"/files/etc/modprobe.d/nvidia.conf "/etc/modprobe.d/"

	[[ ${nvidia_force_pcie_gen2} -eq 1 ]] &&
		sed -i "s/NVreg_EnablePCIeGen3=1/NVreg_EnablePCIeGen3=0/" /etc/modprobe.d/nvidia.conf

	[[ ${nvidia_stream_memory_operations} -eq 1 ]] &&
		sed -i "s/NVreg_EnableStreamMemOPs=0/NVreg_EnableStreamMemOPs=1/" /etc/modprobe.d/nvidia.conf

	_nvidia_enable_drm() {
		local PARAMS="nvidia-drm.modeset=1"
		_modify_kernel_parameters

		if ! grep -q "MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)" /etc/mkinitcpio.conf; then
			echo "MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)" >>/etc/mkinitcpio.conf
		fi
	}
	_nvidia_enable_drm

	_nvidia_force_max_performance() {
		if [[ ${nvidia_force_max_performance} -eq 1 ]]; then
			sudo -H -u "${WHICH_USER}" bash -c "${SYSTEMD_USER_ENV} DENY_SUPERUSER=1 cp ${cp_flags} ${GIT_DIR}/files/home/.config/systemd/user/nvidia-max-performance.service /home/${WHICH_USER}/.config/systemd/user/"
			sudo -H -u "${WHICH_USER}" bash -c "${SYSTEMD_USER_ENV} systemctl --user enable nvidia-max-performance.service"

			# Allow the "Prefer Maximum Performance" PowerMizer setting on laptops
			local PARAMS="nvidia.NVreg_RegistryDwords=OverrideMaxPerf=0x1"
			_modify_kernel_parameters
		fi
	}
	_nvidia_force_max_performance

	_nvidia_after_install() {
		# Running Xorg rootless breaks clock/power/fan control: https://gitlab.com/leinardi/gwe/-/issues/92
		printf "needs_root_rights = yes" >/etc/X11/Xwrapper.config

		# GreenWithEnvy: Overclocking, power & fan control, GPU graphs; akin to MSI Afterburner
		nvidia-xconfig --cool-bits=28
		FLATPAKS+="com.leinardi.gwe "

		# Xorg will break on trying to load Nouveau first if this file exists
		[[ -e "/etc/X11/xorg.conf.d/20-nouveau.conf" ]] &&
			chattr -f -i /etc/X11/xorg.conf.d/20-nouveau.conf &&
			rm -f /etc/X11/xorg.conf.d/20-nouveau.conf

		REGENERATE_INITRAMFS=1
	}
	trap _nvidia_after_install EXIT
}

case ${nvidia_driver_series} in
1)
	_nvidia_setup
	PKGS+="nvidia-dkms egl-wayland nvidia-utils opencl-nvidia libxnvctrl \
				lib32-nvidia-utils lib32-opencl-nvidia "
	;;
2)
	_nvidia_setup
	PKGS+="egl-wayland nvidia-470xx-dkms nvidia-470xx-utils opencl-nvidia-470xx libxnvctrl-470xx \
				lib32-nvidia-470xx-utils lib32-opencl-nvidia-470xx "
	;;
3) # Settings for current drivers seem to work fine for 390.xxx
	_nvidia_setup
	PKGS+="egl-wayland nvidia-390xx-dkms nvidia-390xx-utils opencl-nvidia-390xx libxnvctrl-390xx \
				lib32-nvidia-390xx-utils lib32-opencl-nvidia-390xx "
	;;
4)
	_nouveau_setup
	;;
*)
	printf "\nWARNING: No valid 'nvidia_driver_series' option was specified!\n"
	;;
esac

_pkgs_add
_pkgs_aur_add || :
_flatpaks_add || :

if [[ ${IS_CHROOT} -eq 0 ]]; then
	[[ ${REGENERATE_INITRAMFS} -eq 1 ]] &&
		_build_initramfs

	[[ ${REGENERATE_GRUB2_CONFIG} -eq 1 ]] &&
		grub-mkconfig -o /boot/grub/grub.cfg
fi

cleanup() {
	mkdir "${mkdir_flags}" "${BACKUPS}/etc/modprobe.d"
	chown -R "${WHICH_USER}:${WHICH_USER}" "${BACKUPS}/etc/modprobe.d"
}
trap cleanup EXIT
