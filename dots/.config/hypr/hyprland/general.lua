-- MONITOR CONFIG
-- eDP-1: 笔记本内屏  2560x1600@165  150% 缩放
hl.monitor({
    output   = "eDP-1",
    mode     = "2560x1600@165",
    scale    = auto,
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
hl.plugin.scrolloverview.gesture({ fingers = 4, direction = "vertical" })

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
    render = {
          cm_auto_hdr = 1,  -- 全屏 HDR 自动切，桌面保持 SDR
    },
})
-- Curves (Niri-inspired with Hyprland bezier spring approximation)
hl.curve("niriOpen", {
    type = "bezier",
    points = {{0.19, 1.0}, {0.22, 1.0}}
})
hl.curve("niriClose", {
    type = "bezier",
    points = {{0.33, 0.0}, {0.66, 1.0}}
})
hl.curve("niriSpring1000", {
    type = "bezier",
    points = {{0.15, 1.0}, {0.05, 1.0}}
})
hl.curve("niriSpring800", {
    type = "bezier",
    points = {{0.2, 1.0}, {0.08, 1.0}}
})
hl.curve("standardDecel", {
    type = "bezier",
    points = {{0, 0}, {0, 1}}
})
-- windows (Niri: window-open 150ms ease-out-expo / window-close 150ms ease-out-quad)
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 1.5,
    bezier = "niriOpen",
    
})
hl.animation({
    leaf = "fadeIn",
    enabled = true,
    speed = 1.5,
    bezier = "niriOpen"
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 1.5,
    bezier = "niriClose",
    
})
hl.animation({
    leaf = "fadeOut",
    enabled = true,
    speed = 1.5,
    bezier = "niriClose"
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 3,
    bezier = "niriSpring800",
    style = "slide"
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 10,
    bezier = "niriSpring800"
})

-- layers
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 1.5,
    bezier = "niriOpen",
    
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 1.5,
    bezier = "niriClose",
    style = "slide"
})
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 1.5,
    bezier = "niriOpen"
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 6,
    bezier = "niriClose"
})

-- workspaces (Niri: spring damping=1 stiffness=1000)
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 4,
    bezier = "niriSpring1000",
    style = "slide"
})

-- specialWorkspace
hl.animation({
    leaf = "specialWorkspaceIn",
    enabled = true,
    speed = 1.5,
    bezier = "niriOpen",
    style = "slidevert"
})
hl.animation({
    leaf = "specialWorkspaceOut",
    enabled = true,
    speed = 1.0,
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
            clickfinger_behavior = true,
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
        swallow_regex = "(foot|kitty|allacritty|Alacritty)",
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
