local home_dir = os.getenv("HOME")

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Language (Chinese)
hl.env("LANG", "zh_CN.UTF-8")
hl.env("LANGUAGE", "zh_CN")

-- Applications
local function unique_paths(str)
    local seen = {}
    local result = {}
    for path in string.gmatch(str or "", "([^:]+)") do
        -- hl.env does not expand $VARS; skip unresolved placeholders and blanks
        if path ~= "" and not path:match("^%$[%w_]+$") and not seen[path] then
            seen[path] = true
            table.insert(result, path)
        end
    end
    return table.concat(result, ":")
end

local xdg_data_dirs_old = os.getenv("XDG_DATA_DIRS") or ""
hl.env("XDG_DATA_DIRS", unique_paths(table.concat({
    home_dir .. "/.local/share/flatpak/exports/share",
    "/var/lib/flatpak/exports/share",
    "/usr/local/share",
    "/usr/share",
    xdg_data_dirs_old,
}, ":")))

-- Input method
hl.env("QT_IM_MODULE", "fcitx")
hl.env("XMODIFIERS", "@im=fcitx")

-- Themes
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XDG_MENU_PREFIX", "plasma-")

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")

-- Cursor (XWayland)
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "48")
