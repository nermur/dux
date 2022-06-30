#!/bin/bash
# shellcheck disable=SC2034,SC2249
set -a

# Supported printer list: https://www.openprinting.org/printers
hardware_printers_and_scanners="1"

# 1: GRUB2
# 2: rEFInd
bootloader_type="2"
# If UEFI isn't available, GRUB2 is forced.
[[ ! -d "/sys/firmware/efi" ]] &&
    bootloader_type="1"

# 0: Massive performance penalty on CPUs older than AMD Zen 2 or Intel 10th gen,
# and caused a boot failure bug for Linux 5.18:
# https://bugs.archlinux.org/task/74891?project=1&pagenum=1
no_mitigations="1"

# Automatically installs software specified in configs/software_catalog.sh
auto_software_catalog="1"

# Uninstalls low-quality software Manjaro may include by default.
auto_remove_software="1"

# === Desktop Environment: GNOME ===
# It's not recommended to run the non-riced/vanilla GNOME.
auto_gnome_rice="1"

    # Prioritizes mouse & keyboard instead of mouse oriented window management, and frees up screen space.
    gnome_no_titlebars="1"

    gnome_document_font_name="Liberation Sans 11"
    gnome_font_name="Liberation Sans 11"
    gnome_monospace_font_name="Hack 10" # This is actually font size 11; it's a GNOME quirk.

    gnome_font_aliasing="rgba" # rgba, greyscale, none
    # "full" is intended for Liberation Sans, for others it's usually "slight".
    gnome_font_hinting="full" # none, slight, medium, full

    gnome_mouse_accel_profile="flat"    # flat, adaptive, default
    gnome_remember_app_usage="false"    # true, false
    gnome_remember_recent_files="false" # true, false
    gnome_animations="false"            # true, false
    
    # Support for tray icons.
    gnome_extension_appindicator="1"
    # Recommended to use alongside 'gnome_no_titlebars'.
    gnome_extension_pop_shell="0"
    
    # Don't automatically turn off the screen.
    gnome_disable_idle="1"

    # GNOME's "smart" window placement puts new windows in unpredictable places, sometimes at the top-most left corner.
    gnome_center_new_windows="1"

# === Desktop Environment: KDE ===
auto_kde_rice="1"

    kde_general_font="Liberation Sans,11"
    kde_fixed_width_font="Hack,11"
    kde_small_font="Liberation Sans,9"
    kde_toolbar_font="Liberation Sans,10"
    kde_menu_font="Liberation Sans,10"

    # "false" to use the default mouse acceleration profile (Adaptive).
    kde_mouse_accel_flat="true"

    # hintnone, hintslight, hintmedium, hintfull
    # hintfull note: Fonts will look squished in some software; not an issue for GNOME.
    kde_font_hinting="hintslight"

    # none, rgb, bgr, vrgb (Vertical RGB), vbgr (Vertical BGR)
    kde_font_aliasing="rgb"

    # Disables window titlebars to prioritize mouse & keyboard instead of mouse oriented window management;
    # KDE doesn't seem great with this, unlike GNOME.
    kwin_disable_titlebars="0"

    kwin_animations="false" # true, false

    # Controls window drop-shadows: ShadowNone, ShadowSmall, ShadowMedium, ShadowLarge, ShadowVeryLarge
    kwin_shadow_size="ShadowNone"

# === Graphics Card options ===
# 1: Skip installing any and all GPU software.
disable_gpu="0"

# 1: Disable installing drivers for NVIDIA GPUs.
avoid_nvidia_gpus="0"
avoid_intel_gpus="0"
avoid_amd_gpus="0"

# 1: Proprietary current
# 2: Proprietary 470.xxx
# 3: Proprietary 390.xxx (For Fermi 1.0 to Maxwell 1.0)
# 4: Open-source (For Maxwell 1.0 or older)
# Warning: Non open-source drivers can cause Linux to fail booting; check if the Linux kernel used is compatible!
nvidia_driver_series="1"

case ${nvidia_driver_series} in
[1-3])
    # Enforce "Prefer Maximum Performance" (some GPUs lag hard without this).
    nvidia_force_max_performance="0"

    # Disable PCIe Gen 3.0 support (not recommended; only if needed for stability).
    nvidia_force_pcie_gen2="0"

    # https://docs.nvidia.com/cuda/cuda-driver-api/group__CUDA__MEMOP.html#group__CUDA__MEMOP
    nvidia_stream_memory_operations="0"
    ;;
4)
    # Increases stability and performance for Nouveau drivers.
    nouveau_custom_parameters="1"
    ;;
esac

# Force 'radeon' driver (GCN2 and below only, but not recommended).
amd_graphics_force_radeon="0"

# Allows adjusting clocks and voltages; GameMode can use this to automatically set/unset max performance.
amd_graphics_sysfs="1"
