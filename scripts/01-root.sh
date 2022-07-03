#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

TOTAL_RAM=$(($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / (1024 * 1024)))
CPU_VENDOR=$(grep -m1 'vendor' /proc/cpuinfo | cut -f2 -d' ')
# Also covers GCC's -mtune
MARCH=$(gcc -march=native -Q --help=target | grep -oP '(?<=-march=).*' -m1 | awk '{$1=$1};1')

ROOT_PART=$(lsblk -no PARTUUID,NAME | grep -B1 "luks-*" | head -1 | cut -f1 -d' ')
if [[ -n ${ROOT_PART} ]]; then
    export DISK_ENCRYPTED=1
elif [[ -z ${ROOT_PART} ]]; then
    GET_ROOT=$(\df /var | grep /dev | cut -f1 -d' ')
    ROOT_PART=$(lsblk -no PARTUUID "${GET_ROOT}")
fi

if [[ ! -d "/sys/firmware/efi" ]]; then
    GET_BOOT=$(\df /boot | grep /dev | cut -f1 -d' ')
else
    GET_BOOT=$(\df /boot/efi | grep /dev | cut -f1 -d' ')
fi
BOOT_PART=$(lsblk -no PARTUUID "${GET_BOOT}")

# Caches result of 'nproc'
NPROC=$(nproc)

# sudo: Allow users in group 'wheel' to elevate to superuser without prompting for a password (until 03-finalize.sh).
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/custom_settings

mkdir "${mkdir_flags}" {/etc/{modules-load.d,NetworkManager/conf.d,modprobe.d,tmpfiles.d,pacman.d/hooks,X11,fonts,systemd/user,conf.d},/boot,/home/"${WHICH_USER}"/.config/{fontconfig/conf.d,systemd/user},/usr/share/libalpm/scripts}

if [[ ${auto_remove_software} -eq 1 ]]; then
    REMOVE_PKGS+="kcalc okular gwenview ksystemlog plasma-systemmonitor "
    _remove_installed_pkgs
fi

_package_installers() {
    if [[ ${hardware_printers_and_scanners} -eq 1 ]]; then
        # Also requires nss-mdns; installed by default.
        PKGS+="cups cups-filters ghostscript gsfonts cups-pk-helper sane system-config-printer simple-scan "
        # Also requires avahi-daemon.service; enabled by default.
        SERVICES+="cups.socket cups-browsed.service "
    fi

    PKGS+="gnome-logs dconf-editor flatpak gsettings-desktop-schemas xdg-desktop-portal xdg-desktop-portal-gtk ibus \
    kconfig \
    iwd bluez bluez-utils \
    irqbalance zram-generator power-profiles-daemon thermald dbus-broker gamemode lib32-gamemode \
    libnewt pigz pbzip2 strace usbutils avahi nss-mdns \
    man-db man-pages pacman-contrib bat \
    trash-cli rebuild-detector base-devel \
    grub grub-btrfs "
    _pkgs_add
}

_bootloader_setup() {
    case $(systemd-detect-virt) in
    "none")
        if [[ ${CPU_VENDOR} = "AuthenticAMD" ]]; then
            PKGS+="amd-ucode "
        elif [[ ${CPU_VENDOR} = "GenuineIntel" ]]; then
            PKGS+="intel-ucode "
        fi
        ;;
    "kvm")
        PKGS+="qemu-guest-agent "
        ;;
    "vmware")
        PKGS+="open-vm-tools "
        SERVICES+="vmtoolsd.service vmware-vmblock-fuse.service "
        ;;
    "oracle")
        PKGS+="virtualbox-guest-utils "
        SERVICES+="vboxservice.service "
        ;;
    "microsoft")
        PKGS+="hyperv "
        SERVICES+="hv_fcopy_daemon.service hv_kvp_daemon.service hv_vss_daemon.service "
        ;;
    *)
        printf "\nWARNING: 'systemd-detect-virt' did not return an expected string.\n"
        ;;
    esac

    [[ ${no_mitigations} -eq 1 ]] &&
        MITIGATIONS_OFF="ibt=off mitigations=off"

    if [[ ${DISK_ENCRYPTED} -eq 1 ]]; then
        REQUIRED_PARAMS="rd.luks.name=${ROOT_PART}=dux rd.luks.options=discard root=/dev/mapper/dux rootflags=subvol=@ rw"
    else
        REQUIRED_PARAMS="root=/dev/disk/by-partuuid/${ROOT_PART} rootflags=subvol=@ rw"
    fi

    # https://www.kernel.org/doc/Documentation/x86/x86_64/boot-options.txt
    #
    # https://www.intel.com/content/www/us/en/developer/articles/technical/optimizing-computer-applications-for-latency-part-1-configuring-the-hardware.html
    #
    # http://developer.amd.com/wp-content/resources/56263-Performance-Tuning-Guidelines-PUB.pdf
    #
    # loglevel=3: silence more of the boot process graphically; info will still be in logs.
    # acpi_osi=Linux: tell BIOS to load their ACPI tables for Linux.
    COMMON_PARAMS="loglevel=3 sysrq_always_enabled=1 quiet add_efi_memmap acpi_osi=Linux skew_tick=1 mce=ignore_ce nowatchdog tsc=reliable"

    _setup_grub2_bootloader() {
        if [[ $(</sys/firmware/efi/fw_platform_size) -eq 64 ]]; then
            grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Manjaro
        elif [[ $(</sys/firmware/efi/fw_platform_size) -eq 32 ]]; then
            grub-install --target=i386-efi --efi-directory=/boot/efi --bootloader-id=Manjaro
        else
            grub-install --target=i386-pc "${BOOT_PART//[0-9]/}"
        fi
    }

    _grub2_bootloader_config() {
        sed -i -e "s/.GRUB_CMDLINE_LINUX/GRUB_CMDLINE_LINUX/" \
            -e "s/.GRUB_CMDLINE_LINUX_DEFAULT/GRUB_CMDLINE_LINUX_DEFAULT/" \
            -e "s/.GRUB_DISABLE_OS_PROBER/GRUB_DISABLE_OS_PROBER/" \
            "${BOOT_CONF}" # can't allow these to be commented out

        sed -i -e "s|GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${MITIGATIONS_OFF:-} ${REQUIRED_PARAMS}\"|" \
            -e "s|GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${COMMON_PARAMS}\"|" \
            -e "s|GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=false|" \
            "${BOOT_CONF}"
    }
    _setup_grub2_bootloader
    _grub2_bootloader_config
}
_system_configuration() {
    # gamemode: Allows for maximum performance while a specific program is running.
    groupadd --force -g 385 gamemode
    # Why 'video': https://github.com/Hummer12007/brightnessctl/issues/63
    usermod -a -G video,gamemode "${WHICH_USER}"

    # Better output, and package downloads.
    sed -i -e 's/^#Color/Color/' \
        -e '/^#ParallelDownloads/s/^#//' \
        -e "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf

    # Why 'noatime': https://archive.is/wjH73
    sed 's/,defaults 0 0/,defaults,noatime,compress=zstd:1 0 0/' /etc/fstab
    if ! grep -q "/sys/kernel/debug" /etc/fstab >&/dev/null; then
        echo -e "# Some useful configuration is gone if this isn't mounted\ndebugfs    /sys/kernel/debug      debugfs  defaults  0 0" >>/etc/fstab
    fi

    sed -i -e "s/-march=x86-64 -mtune=generic/-march=${MARCH} -mtune=${MARCH}/" \
        -e 's/.RUSTFLAGS.*/RUSTFLAGS="-C opt-level=2 -C target-cpu=native"/' \
        -e "s/.MAKEFLAGS.*/MAKEFLAGS=\"-j${NPROC} -l${NPROC}\"/" \
        -e "s/xz -c -z -/xz -c -z -T ${NPROC} -/" \
        -e "s/bzip2 -c -f/pbzip2 -c -f/" \
        -e "s/gzip -c -f -n/pigz -c -f -n/" \
        -e "s/zstd -c -z -q -/zstd -c -z -q -T${NPROC} -/" \
        -e "s/lrzip -q/lrzip -q -p ${NPROC}/" /etc/makepkg.conf

    sed -i "s/.DefaultEnvironment.*/DefaultEnvironment=\"GNUMAKEFLAGS=-j${NPROC} -l${NPROC}\" \"MAKEFLAGS=-j${NPROC} -l${NPROC}\"/" \
        /etc/systemd/{system.conf,user.conf}

    # Root-less Xorg to lower its memory usage and increase overall security.
    \cp "${cp_flags}" "${GIT_DIR}"/files/etc/X11/Xwrapper.config "/etc/X11/"

    if ! grep -q 'PRUNENAMES = ".snapshots"' /etc/updatedb.conf >&/dev/null; then
        # Tells mlocate to ignore Btrfs snapshots; avoids slowdowns and excessive memory usage.
        printf 'PRUNENAMES = ".snapshots"' >>/etc/updatedb.conf
    fi

    # Disable the Baloo indexer.
    if hash balooctl >&/dev/null; then
        balooctl suspend
        balooctl disable
    fi

    # Disables late microcode updates, which Linux 5.19 defaults to doing:
    # https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=9784edd73a08ea08d0ce5606e1f0f729df688c59
    ln -s /dev/null /etc/tmpfiles.d/linux-firmware.conf &>/dev/null || :

    # Ensure "net.ipv4.tcp_congestion_control = bbr" is a valid option.
    \cp "${cp_flags}" "${GIT_DIR}"/files/etc/modules-load.d/tcp_bbr.conf "/etc/modules-load.d/"

    # zRAM is a swap type that helps performance more often than not, and doesn't decrease longevity of drives.
    \cp "${cp_flags}" "${GIT_DIR}"/files/etc/systemd/zram-generator.conf "/etc/systemd/" &&
        sed -i "s/max-zram-size = ~post_chroot.sh~/max-zram-size = ${TOTAL_RAM}/" /etc/systemd/zram-generator.conf

    # Configures some kernel parameters; also contains memory management settings specific to zRAM.
    \cp "${cp_flags}" "${GIT_DIR}"/files/etc/sysctl.d/99-custom.conf "/etc/sysctl.d/"

    # Use overall best I/O scheduler for each drive type (NVMe, SSD, HDD).
    \cp "${cp_flags}" "${GIT_DIR}"/files/etc/udev/rules.d/60-io-schedulers.rules "/etc/udev/rules.d/"

    # https://wiki.archlinux.org/title/zsh#On-demand_rehash
    \cp "${cp_flags}" "${GIT_DIR}"/files/etc/pacman.d/hooks/zsh.hook "/etc/pacman.d/hooks/"

    # Flatpak requires this for "--filesystem=xdg-config/fontconfig:ro"
    \cp "${cp_flags}" "${GIT_DIR}"/files/etc/fonts/local.conf "/etc/fonts/"

    # Tell NetworkManager to use iwd by default for increased WiFi reliability and speed.
    \cp "${cp_flags}" "${GIT_DIR}/files/etc/NetworkManager/conf.d/wifi_backend.conf" "/etc/NetworkManager/conf.d/"

    # Makes our font and cursor settings work inside Flatpak.
    FLATPAK_PARAMS="--filesystem=xdg-config/fontconfig:ro --filesystem=/home/${WHICH_USER}/.icons/:ro --filesystem=/home/${WHICH_USER}/.local/share/icons/:ro --filesystem=/usr/share/icons/:ro"
    if [[ ${DEBUG} -eq 1 ]]; then
        # shellcheck disable=SC2086
        flatpak -vv override ${FLATPAK_PARAMS}
    else
        # shellcheck disable=SC2086
        flatpak override ${FLATPAK_PARAMS}
    fi

    # Ensure the default shell is Zsh.
    chsh -s /bin/zsh
}

_grub_btrfs_pacman_hook() {
    # GRUB_BTRFS_LIMIT="10": Don't display more than 10 snapshots.
    # GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND="false": Don't specify every snapshot found, instead say "Found 10 snapshot(s)".
    # GRUB_BTRFS_SHOW_TOTAL_SNAPSHOTS_FOUND="true": Required to say "Found 10 snapshot(s)".
    sed -i -e "s/.GRUB_BTRFS_LIMIT/GRUB_BTRFS_LIMIT/" -e "s/.GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND/GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND/" -e "s/.GRUB_BTRFS_SHOW_TOTAL_SNAPSHOTS_FOUND/GRUB_BTRFS_SHOW_TOTAL_SNAPSHOTS_FOUND/" \
        -e "s/GRUB_BTRFS_LIMIT.*/GRUB_BTRFS_LIMIT=\"10\"/" \
        -e "s/GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND.*/GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND=\"false\"/" \
        -e "s/GRUB_BTRFS_SHOW_TOTAL_SNAPSHOTS_FOUND.*/GRUB_BTRFS_SHOW_TOTAL_SNAPSHOTS_FOUND=\"true\"/" \
        "/etc/default/grub-btrfs/config"
}

_package_installers
_bootloader_setup
_system_configuration
_grub_btrfs_pacman_hook

# Default services, regardless of options selected.
SERVICES+="fstrim.timer btrfs-scrub@-.timer \
irqbalance.service dbus-broker.service power-profiles-daemon.service thermald.service rfkill-unblock@all avahi-daemon.service "

# shellcheck disable=SC2086
_systemctl enable ${SERVICES}

_prepare_02() {
    chown -R "${WHICH_USER}:${WHICH_USER}" "/home/${WHICH_USER}" || :
    chmod +x -R "${GIT_DIR}" >&/dev/null || :
}
trap _prepare_02 EXIT
