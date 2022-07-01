#!/bin/bash
# shellcheck disable=SC2120
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"
source "${GIT_DIR}/configs/virtual_machines.sh"

HOOK_DIR="etc/libvirt/hooks/qemu.d"

_base_setup() {
    PKGS+="qemu-desktop libvirt virt-manager edk2-ovmf iptables-nft dnsmasq virglrenderer hwloc dmidecode usbutils swtpm "
    _pkgs_add

    mkdir -p /etc/{modprobe.d,udev/rules.d}
    mkdir -p /"${HOOK_DIR}"/"${domain_name}"/{prepare/begin,started/begin,release/end}

    \cp "${cp_flags}" "${GIT_DIR}"/files/etc/modprobe.d/custom_kvm.conf "/etc/modprobe.d/"
    \cp "${cp_flags}" "${GIT_DIR}"/files/etc/udev/rules.d/99-qemu.rules "/etc/udev/rules.d/"
    \cp "${cp_flags}" "${GIT_DIR}"/files/etc/libvirt/hooks/qemu "/etc/libvirt/hooks"

    # qemu: If using QEMU directly is desired instead of libvirt.
    # video: Virtio OpenGL acceleration.
    # kvm: Hypervisor hardware acceleration.
    # libvirt: Access to virutal machines made through libvirt.
    usermod -a -G qemu,video,kvm,libvirt "${WHICH_USER}"

    local PARAMS="intel_iommu=on iommu=pt"
    _modify_kernel_parameters

    [[ ${REGENERATE_GRUB2_CONFIG} -eq 1 ]] &&
        grub-mkconfig -o /boot/grub/grub.cfg

    # Don't use Copy-on-Write (CoW) for virtual machine disks.
    chattr +C "/var/lib/libvirt/images"
}

_core_isolation() {
    PKGS_AUR+="vfio-isolate "
    \cp "${cp_flags}" "${GIT_DIR}"/files/"${HOOK_DIR}"/domain/prepare/begin/core-isolation.sh "/${HOOK_DIR}/${domain_name}/prepare/begin/" &&
        ln -f /"${HOOK_DIR}"/"${domain_name}"/prepare/begin/core-isolation.sh "/${HOOK_DIR}/${domain_name}/release/end/core-isolation.sh"
}

_dynamic_hugepages() {
    PKGS+="ripgrep "
    KVM_GROUPID=$(getent group kvm | sed 's/[^0-9]*//g')

    if ! grep -q "/dev/hugepages2M|/dev/hugepages1G" /etc/fstab; then
        cat <<EOF >>/etc/fstab
hugetlbfs       /dev/hugepages2M     hugetlbfs     mode=1770,gid=${KVM_GROUPID},pagesize=2M   0 0
hugetlbfs       /dev/hugepages1G     hugetlbfs     mode=1770,gid=${KVM_GROUPID},pagesize=1G   0 0
EOF
    fi

    if ! grep -q "hugetlbfs_mount = [ \"/dev/hugepages2M\", \"/dev/hugepages1G\" ]" /etc/libvirt/qemu.conf; then
        cat <<'EOF' >>/etc/libvirt/qemu.conf
hugetlbfs_mount = [ "/dev/hugepages2M", "/dev/hugepages1G" ]
EOF
    fi

    \cp "${cp_flags}" "${GIT_DIR}"/files/"${HOOK_DIR}"/domain/prepare/begin/hugepages.sh "/${HOOK_DIR}/${domain_name}/prepare/begin/" &&
        ln -f /"${HOOK_DIR}"/"${domain_name}"/prepare/begin/hugepages.sh "/${HOOK_DIR}/${domain_name}/release/end/hugepages.sh"

}

_base_setup
[[ ${core_isolation} -eq 1 ]] && _core_isolation
[[ ${dynamic_hugepages} -eq 1 ]] && _dynamic_hugepages
systemctl enable --now libvirtd.service &&
    virsh net-autostart default

chmod +x -R "/etc/libvirt/hooks"

whiptail --yesno "A reboot is required to complete installing virtual machine support.\nReboot now?" 0 0 &&
    reboot -f
