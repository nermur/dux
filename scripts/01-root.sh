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

ROOT_DISK=$(lsblk -no PARTUUID,NAME | grep -B1 "luks-*" | head -1 | cut -f1 -d' ')

if [[ ! -d "/sys/firmware/efi" ]]; then
    GET_PART=$(\df /boot | grep /dev | cut -f1 -d' ')
else
    GET_PART=$(\df /boot/efi | grep /dev | cut -f1 -d' ')
fi
BOOT_PART=$(lsblk -no PARTUUID ${GET_PART})

# Caches result of 'nproc'
NPROC=$(nproc)

# sudo: Allow users in group 'wheel' to elevate to superuser without prompting for a password (until 03-finalize.sh).
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/custom_settings

mkdir "${mkdir_flags}" {/etc/{modules-load.d,NetworkManager/conf.d,modprobe.d,tmpfiles.d,pacman.d/hooks,X11,fonts,systemd/user,conf.d},/boot,/home/"${WHICH_USER}"/.config/{fontconfig/conf.d,systemd/user},/usr/share/libalpm/scripts}

_package_installers() {
    if [[ ${hardware_printers_and_scanners} -eq 1 ]]; then
        # Also requires nss-mdns; installed by default.
        PKGS+="cups cups-filters ghostscript gsfonts cups-pk-helper sane system-config-printer simple-scan "
        # Also requires avahi-daemon.service; enabled by default.
        SERVICES+="cups.socket cups-browsed.service "
        _printer_config() {
            chattr -f -i /etc/nsswitch.conf
            sed -i "s/hosts:.*/hosts: files mymachines myhostname mdns_minimal [NOTFOUND=return] resolve/" /etc/nsswitch.conf
            chattr -f +i /etc/nsswitch.conf
        }
        trap _printer_config EXIT
    fi
    [[ ${hardware_fingerprint_reader} -eq 1 ]] &&
        PKGS+="fprintd imagemagick "

    [[ ${hardware_wifi_and_bluetooth} -eq 1 ]] &&
        PKGS+="iwd bluez bluez-utils "

    [[ ${bootloader_type} -eq 2 ]] &&
        PKGS+="refind "
    [[ -d "/sys/firmware/efi" ]] &&
        PKGS+="efibootmgr "

    PKGS+="gnome-logs dconf-editor flatpak gsettings-desktop-schemas xdg-desktop-portal xdg-desktop-portal-gtk ibus \
    kconfig ark dolphin kde-cli-tools kdegraphics-thumbnailers kimageformats qt5-imageformats ffmpegthumbs taglib openexr libjxl android-udev \
    irqbalance zram-generator power-profiles-daemon thermald dbus-broker gamemode lib32-gamemode iptables-nft \
    dnsmasq openresolv libnewt pigz pbzip2 strace usbutils avahi nss-mdns \
    man-db man-pages pacman-contrib bat \
    trash-cli rebuild-detector base-devel "
    _pkgs_add
}

_bootloader_setup() {
    case $(systemd-detect-virt) in
    "none")
        if [[ ${CPU_VENDOR} = "AuthenticAMD" ]]; then
            PKGS+="amd-ucode "
            MICROCODE="initrd=amd-ucode.img initrd=initramfs-%v.img"
        elif [[ ${CPU_VENDOR} = "GenuineIntel" ]]; then
            PKGS+="intel-ucode "
            MICROCODE="initrd=intel-ucode.img initrd=initramfs-%v.img"
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

    if [[ ${use_disk_encryption} -eq 1 ]]; then
        REQUIRED_PARAMS="rd.luks.name=${ROOT_DISK}=lukspart rd.luks.options=discard root=/dev/mapper/lukspart rootflags=subvol=@root rw"
    else
        REQUIRED_PARAMS="root=/dev/disk/by-partuuid/${ROOT_DISK} rootflags=subvol=@root rw"
    fi

    # https://access.redhat.com/sites/default/files/attachments/201501-perf-brief-low-latency-tuning-rhel7-v1.1.pdf
    # acpi_osi=Linux: tell BIOS to load their ACPI tables for Linux.
    COMMON_PARAMS="loglevel=3 sysrq_always_enabled=1 quiet add_efi_memmap acpi_osi=Linux nmi_watchdog=0 skew_tick=1 mce=ignore_ce nosoftlockup ${MICROCODE:-}"

    if [[ ${bootloader_type} -eq 1 ]]; then
        _setup_grub2_bootloader() {
            if [[ $(</sys/firmware/efi/fw_platform_size) -eq 64 ]]; then
                grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Manjaro
            elif [[ $(</sys/firmware/efi/fw_platform_size) -eq 32 ]]; then
                grub-install --target=i386-efi --efi-directory=/boot --bootloader-id=Manjaro
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

    elif [[ ${bootloader_type} -eq 2 ]]; then
        _setup_refind_bootloader() {
            # x86_64-efi: rEFInd overrides GRUB2 without issues.
            refind-install
            # Tell rEFInd to detect the initramfs for linux-lts & linux automatically.
            sed -i '/^#extra_kernel_version_strings/s/^#//' /boot/efi/EFI/refind/refind.conf
            \cp "${cp_flags}" "${GIT_DIR}"/files/etc/pacman.d/hooks/refind.hook "/etc/pacman.d/hooks/"
        }
        _refind_bootloader_config() {
            cat <<EOF >"${BOOT_CONF}"
"Boot using standard options"  "${MITIGATIONS_OFF:-} ${REQUIRED_PARAMS} ${COMMON_PARAMS}"

"Boot to single-user mode"  "single ${MITIGATIONS_OFF:-} ${REQUIRED_PARAMS} ${COMMON_PARAMS}"

"Boot with minimal options"  "${MITIGATIONS_OFF:-} ${REQUIRED_PARAMS} ${MICROCODE:-}"
EOF
        }
        _setup_refind_bootloader
        _refind_bootloader_config
    fi
}

_config_dolphin() {
    local CONF="/home/${WHICH_USER}/.config/dolphinrc"
    kwriteconfig5 --file "${CONF}" --group "General" --key "ShowFullPath" "true"
    kwriteconfig5 --file "${CONF}" --group "General" --key "ShowSpaceInfo" "false"
    kwriteconfig5 --file "/home/${WHICH_USER}/.config/kdeglobals" --group "PreviewSettings" --key "MaximumRemoteSize" "10485760"
    balooctl suspend
    balooctl disable
}

_config_networkmanager() {
    local DIR="etc/NetworkManager/conf.d"

    # Use openresolv instead of systemd-resolvconf.
    \cp "${cp_flags}" "${GIT_DIR}"/files/"${DIR}"/rc-manager.conf "/${DIR}/"

    # Use dnsmasq instead of systemd-resolved.
    \cp "${cp_flags}" "${GIT_DIR}"/files/"${DIR}"/dns.conf "/${DIR}/"
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
    echo -e "# Some useful configuration is gone if this isn't mounted\ndebugfs    /sys/kernel/debug      debugfs  defaults  0 0" >>/etc/fstab

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
        # Tells mlocate to ignore Snapper's Btrfs snapshots; avoids slowdowns and excessive memory usage.
        printf 'PRUNENAMES = ".snapshots"' >>/etc/updatedb.conf
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

    # Makes our font and cursor settings work inside Flatpak.
    FLATPAK_PARAMS="--filesystem=xdg-config/fontconfig:ro --filesystem=/home/${WHICH_USER}/.icons/:ro --filesystem=/home/${WHICH_USER}/.local/share/icons/:ro --filesystem=/usr/share/icons/:ro"
    if [[ ${DEBUG} -eq 1 ]]; then
        # shellcheck disable=SC2086
        flatpak -vv override ${FLATPAK_PARAMS}
    else
        # shellcheck disable=SC2086
        flatpak override ${FLATPAK_PARAMS}
    fi
}

_package_installers

# This'll prevent many unnecessary initramfs generations, speeding up the install process drastically.
ln -sf /dev/null /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
ln -sf /dev/null /usr/share/libalpm/hooks/90-mkinitcpio-install.hook

_config_dolphin
_config_networkmanager
_bootloader_setup
_system_configuration

# Default services, regardless of options selected.
SERVICES+="fstrim.timer btrfs-scrub@-.timer \
irqbalance.service dbus-broker.service power-profiles-daemon.service thermald.service rfkill-unblock@all avahi-daemon.service "

# shellcheck disable=SC2086
_systemctl enable ${SERVICES}

_prepare_02() {
    # Syntax errors in /etc/nsswitch.conf will break /etc/passwd, /etc/group, and /etc/hosts (breaking the whole OS until repaired).
    chattr -f +i /etc/nsswitch.conf
    chown -R "${WHICH_USER}:${WHICH_USER}" "/home/${WHICH_USER}"
    chmod +x -R "${GIT_DIR}" >&/dev/null || :
}
trap _prepare_02 EXIT
