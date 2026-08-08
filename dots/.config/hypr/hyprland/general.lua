-- MONITOR CONFIG
-- eDP-1: 笔记本内屏  2560x1600@165  150% 缩放
hl.monitor({
    output   = "eDP-1",
    mode     = "2560x1600@165",
    scale    = "auto",
    bitdepth = 10
})

-- HDMI-A-3: 外接显示器  3840x2160@144  自动缩放  (0,0) 为主屏
hl.monitor({
    output   = "HDMI-A-3",
    mode     = "3840x2160@144",
    position = "0x0",
    scale    = "auto",
    bitdepth = 10,
    
})

hl.gesture({
    fingers = 3,
    direction = "swipe",
    action = "move"
})
hl.gesture({
    fingers = 3,
    direction = "pinch",
    action = "fullscreen"
})
hl.gesture({
    fingers = 4,
    direction = "horizontal",
    action = "workspace"
})
if hl.plugin.scrolloverview then
    hl.plugin.scrolloverview.gesture({ fingers = 4, direction = "vertical" })
    hl.config({
        plugin = {
            scrolloverview = {
                scale = 0.3,
                workspace_gap = 80,
                layout = "vertical",
                wallpaper = 0,
                blur = false,
                shadow = {
                    enabled = true,
                    range = 30,
                    render_power = 3,
                    color = 0xee1a1a1a,
                },
            },
        },
    })
end

hl.config({
    gestures = {
        workspace_swipe_distance = 700,
        workspace_swipe_cancel_ratio = 0.2,
        workspace_swipe_min_speed_to_force = 5,
        workspace_swipe_direction_lock = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new = true
    },
    general = {
        -- Gaps and border
        gaps_in = 4,
        gaps_out = 5,
        gaps_workspaces = 50,

        border_size = 4,

        col = {
            active_border = "rgba(0DB7D455)",
            inactive_border = "rgba(31313633)"
        },
        resize_on_border = true,

        no_focus_fallback = true,
        layout = "scrolling",
        allow_tearing = true, -- This just allows the `immediate` window rule to work
        snap = {
            enabled = true,
            window_gap = 4,
            monitor_gap = 5,
            respect_gaps = true
        }
    },
    decoration = {
        -- 2 = circle, higher = squircle, 4 = very obvious squircle
        -- Fuck clearly visible squircles. 100% Apple brainrot.
        rounding_power = 2.5,
        rounding = 18,

        blur = {
            enabled = true,
            xray = true,
            special = false,
            new_optimizations = true,
            size = 10,
            passes = 3,
            brightness = 1,
            noise = 0.05,
            contrast = 0.89,
            vibrancy = 0.5,
            vibrancy_darkness = 0.5,
            popups = false,
            popups_ignorealpha = 0.6,
            input_methods = true,
            input_methods_ignorealpha = 0.8
        },
        shadow = {
            enabled = true,
            range = 20,
            offset = {0, 2},
            render_power = 4,
            color = "rgba(00000020)"

        },
        -- Dim
        dim_inactive = true,
        dim_strength = 0.05,
        dim_special = 0.2
    },
    animations = {
        enabled = true
    },
    scrolling = {
        column_width = 0.5,
        focus_fit_method = 1,
        follow_focus = true,
        follow_min_visible = 0.4,
        wrap_focus = false,
        wrap_swapcol = false,
        direction = "right",
    },
    render = {
          cm_auto_hdr = 1,  -- 全屏 HDR 自动切，桌面保持 SDR
    },
})

-- Curves (Niri animation parity)
-- window-open: cubic-bezier(0.05, 0.9, 0.1, 1.05)
hl.curve("niriOpen", {
    type = "bezier",
    points = {{0.05, 0.9}, {0.10, 1.05}}
})
-- window-close: ease-out-expo (snappier than quad)
hl.curve("niriClose", {
    type = "bezier",
    points = {{0.16, 1.0}, {0.3, 1.0}}
})
-- spring damping=0.8 stiffness=400 approximation (with visible bounce)
hl.curve("niriSpring", {
    type = "bezier",
    points = {{0.12, 1.12}, {0.04, 1.04}}
})
hl.curve("standardDecel", {
    type = "bezier",
    points = {{0, 0}, {0, 1}}
})
-- plugin (scroll-overview): workspace insert/remove fades
-- pre-registered so the plugin picks these up instead of its defaults
-- insert: decelerate (ease in fast, settle) ; remove: quick expo fade-out
hl.curve("scrolloverviewWorkspaceInsertFade", {
    type = "bezier",
    points = {{0, 0}, {0, 1}}
})
hl.curve("scrolloverviewWorkspaceRemoveFade", {
    type = "bezier",
    points = {{0.16, 1.0}, {0.3, 1.0}}
})
-- windows (Niri: window-open 500ms / window-close 150ms)
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 2.0,
    bezier = "niriOpen",
})
hl.animation({
    leaf = "fadeIn",
    enabled = true,
    speed = 2.0,
    bezier = "niriOpen"
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 2.0,
    bezier = "niriClose",
})
hl.animation({
    leaf = "fadeOut",
    enabled = true,
    speed = 2.0,
    bezier = "niriClose"
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 3.5,
    bezier = "niriSpring",
    style = "slide"
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 10,
    bezier = "niriSpring"
})

-- layers
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 2.0,
    bezier = "niriOpen",
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 3.0,
    bezier = "niriClose",
    style = "slide"
})
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 2.0,
    bezier = "niriOpen"
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 3.0,
    bezier = "niriClose"
})

-- workspaces (Niri: spring damping=0.8 stiffness=400)
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 3.5,
    bezier = "niriSpring",
    style = "slidevert"
})
-- fade windows when switching workspaces (Niri slides + fades)
hl.animation({
    leaf = "fadeSwitch",
    enabled = true,
    speed = 2.0,
    bezier = "niriClose"
})
-- popups (menus, tooltips): fade in/out instead of popping
hl.animation({
    leaf = "fadePopupsIn",
    enabled = true,
    speed = 2.0,
    bezier = "niriOpen"
})
hl.animation({
    leaf = "fadePopupsOut",
    enabled = true,
    speed = 3.0,
    bezier = "niriClose"
})
-- shadow fades with the window
hl.animation({
    leaf = "fadeShadow",
    enabled = true,
    speed = 2.0,
    bezier = "niriOpen"
})
-- dim transitions smoothly
hl.animation({
    leaf = "fadeDim",
    enabled = true,
    speed = 2.0,
    bezier = "niriOpen"
})

-- specialWorkspace
hl.animation({
    leaf = "specialWorkspaceIn",
    enabled = true,
    speed = 2.0,
    bezier = "niriOpen",
    style = "slidevert"
})
hl.animation({
    leaf = "specialWorkspaceOut",
    enabled = true,
    speed = 3.5,
    bezier = "niriClose",
    style = "slidevert"
})

-- zoom
hl.animation({
    leaf = "zoomFactor",
    enabled = true,
    speed = 3,
    bezier = "standardDecel"
})
hl.config({
    input = {
        kb_layout = "us",
        numlock_by_default = true,
        repeat_delay = 250,
        repeat_rate = 35,

        follow_mouse = 1,
        off_window_axis_events = 2,

        touchpad = {
            natural_scroll = true,
            disable_while_typing = true,
            clickfinger_behavior = false,
            tap_to_click = true,
            tap_and_drag = true,
            drag_lock = 1,
            scroll_factor = 0.7
        }
    },

    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        vrr = 0,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
        animate_manual_resizes = false,
        animate_mouse_windowdragging = false,
        enable_swallow = false,
        on_focus_under_fullscreen = 2,
        allow_session_lock_restore = true,
        session_lock_xray = true,
        initial_workspace_tracking = false,
        focus_on_activate = true
    },

    binds = {
        scroll_event_delay = 0,
        hide_special_on_workspace_change = true
    },

    cursor = {
        zoom_factor = 1,
        zoom_rigid = false,
        zoom_disable_aa = true,
        hotspot_padding = 1
    },
    xwayland = {
        force_zero_scaling = false,
        use_nearest_neighbor = false

    }
})
