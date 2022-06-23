#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

if [[ ${IS_CHROOT} -eq 1 ]]; then
    echo -e "\nERROR: Do not run this script inside a chroot!\n"
	exit 1
fi

kwriteconfig5 --group "General" --key "XftAntialias" "true"
kwriteconfig5 --group "General" --key "XftHintStyle" "${kde_font_hinting}"
kwriteconfig5 --group "General" --key "XftSubPixel" "${kde_font_aliasing}"
kwriteconfig5 --group "General" --key "fixed" "${kde_fixed_width_font},-1,5,50,0,0,0,0,0"
kwriteconfig5 --group "General" --key "font" "${kde_general_font},-1,5,50,0,0,0,0,0"
kwriteconfig5 --group "General" --key "menuFont" "${kde_menu_font},-1,5,50,0,0,0,0,0"
kwriteconfig5 --group "General" --key "smallestReadableFont" "${kde_small_font},-1,5,50,0,0,0,0,0"
kwriteconfig5 --group "General" --key "toolBarFont" "${kde_toolbar_font},-1,5,50,0,0,0,0,0"
kwriteconfig5 --group "WM" --key "activeFont" "Liberation Sans,10,-1,5,75,0,0,0,0,0,Bold"

kwriteconfig5 --group "Icons" --key "Theme" "Papirus-Dark"
kwriteconfig5 --group "KDE" --key "LookAndFeelPackage" "org.kde.breezedark.desktop"

if [[ ${kwin_animations} = false ]]; then
    kwriteconfig5 --group "KDE" --key "AnimationDurationFactor" "0"
elif [[ ${kwin_animations} = true ]]; then
    kwriteconfig5 --delete --group "KDE" --key "AnimationDurationFactor"
fi

if [[ ${kde_mouse_accel_flat} = true ]]; then
    kwriteconfig5 --file /home/"${WHICH_USER}"/.config/kcminputrc --group "Mouse" --key "XLbInptAccelProfileFlat" "true"
elif [[ ${kde_mouse_accel_flat} = false ]]; then
    kwriteconfig5 --delete --file /home/"${WHICH_USER}"/.config/kcminputrc --group "Mouse" --key "XLbInptAccelProfileFlat"
fi

if [[ ${kwin_disable_titlebars} -eq 1 ]]; then
    # Doesn't disable GTK's CSD.
    _no_titlebars() {
        local CONF="/home/${WHICH_USER}/.config/breezerc"

        kwriteconfig5 --file "${CONF}" --group "Windeco Exception 0" --key "BorderSize" "3"
        kwriteconfig5 --file "${CONF}" --group "Windeco Exception 0" --key "Enabled" "true"
        kwriteconfig5 --file "${CONF}" --group "Windeco Exception 0" --key "ExceptionPattern" ".*"
        kwriteconfig5 --file "${CONF}" --group "Windeco Exception 0" --key "ExceptionType" "0"
        kwriteconfig5 --file "${CONF}" --group "Windeco Exception 0" --key "HideTitleBar" "true"
        kwriteconfig5 --file "${CONF}" --group "Windeco Exception 0" --key "Mask" "16"
    }
    _no_titlebars
fi

_other_customizations() {
    local DIR="/home/${WHICH_USER}/.config"

    kwriteconfig5 --file "${DIR}"/breezerc --group "Common" --key "ShadowSize" "${kwin_shadow_size}"

    # Disable sound notification played while changing volume
    kwriteconfig5 --file "${DIR}"/plasmarc --group "OSD" --key "Enabled" "false"

    # Provides a good alt-tab experience that's similar to Windows 10
    kwriteconfig5 --file "${DIR}"/kwinrc --group "TabBox" --key "HighlightWindows" "false"
    kwriteconfig5 --file "${DIR}"/kwinrc --group "TabBox" --key "LayoutName" "thumbnail_grid"

    kwriteconfig5 --file "${DIR}"/krunnerrc --group "Plugins" --key "browserhistoryEnabled" "false"
    kwriteconfig5 --file "${DIR}"/krunnerrc --group "Plugins" --key "browsertabsEnabled" "false"
    kwriteconfig5 --file "${DIR}"/krunnerrc --group "Plugins" --key "webshortcutsEnabled" "false"
}
_other_customizations

# Logout to apply changes now.
loginctl kill-user "${WHICH_USER}"
