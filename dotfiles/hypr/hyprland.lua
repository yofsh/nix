local term  = "foot"
local speed = 3
local step  = 25

-- Host detection (reads /etc/hostname)
local function read_hostname()
  local f = io.open("/etc/hostname", "r")
  if not f then return "" end
  local h = (f:read("*l") or ""):gsub("%s+$", "")
  f:close()
  return h
end

local LAPTOP_MON = { output = "eDP-1", mode = "2880x1800@120", position = "375x1440", scale = 1.6666, vrr = 1, bitdepth = 10 }
local EXT_MON    = {
  output = "DP-3",
  mode = "5120x1440@240",
  position = "0x0",
  scale = 1.0,
  vrr = 1,
  bitdepth = 10,
  -- cm = "auto",
  -- sdrbrightness = 1.0,
  -- sdrsaturation = 1.0,
}
local TV_MON     = {
  output = "HDMI-A-2",
  mode = "3840x2160@143.99",
  position = "0x0",
  scale = 1,
  vrr = 2,
  bitdepth = 10,
  cm = "hdredid",
  sdrbrightness = 1.0,
  sdrsaturation = 1.0,
}

local hosts      = {
  ares   = { monitors = { LAPTOP_MON, EXT_MON, TV_MON }, primary = "DP-3", secondary = "eDP-1" },
  athena = { monitors = { LAPTOP_MON }, primary = "eDP-1", secondary = "eDP-1" },
}

local host       = hosts[read_hostname()] or hosts.ares
for _, m in ipairs(host.monitors) do hl.monitor(m) end

local screen = host.primary
local laptop = host.secondary

------------------------------------------------------------------------
-- Global config
------------------------------------------------------------------------

hl.config({
  general    = {
    gaps_in     = 2,
    gaps_out    = 4,
    border_size = 0,
    col         = {
      active_border   = { colors = { "rgba(33ccff44)", "rgba(bab34e44)" }, angle = 45 },
      inactive_border = "rgba(59595900)",
    },
    layout      = "dwindle",
  },

  decoration = {
    rounding     = 0,
    dim_special  = 0.4,
    dim_inactive = true,
    dim_strength = 0.25,
    blur         = {
      enabled           = true,
      size              = 9,
      passes            = 3,
      brightness        = 0.8,
      vibrancy_darkness = 1,
    },
    shadow       = { enabled = false },
  },

  animations = {
    enabled = false,
  },

  input      = {
    kb_layout                   = "us,ru,ua",
    kb_options                  = "caps:menu",
    natural_scroll              = false,
    repeat_rate                 = 80,
    repeat_delay                = 190,
    follow_mouse                = 0,
    float_switch_override_focus = 0,
    sensitivity                 = 0,
    touchpad                    = {
      natural_scroll = false,
      scroll_factor  = 0.333,
    },
  },

  misc       = {
    disable_splash_rendering = true,
    disable_hyprland_logo    = true,
    focus_on_activate        = true,
  },

  -- Don't warp the pointer to a window when focus jumps to it (keybind focus,
  -- workspace switch, claude-sessions widget click). Keeps mouse + focus
  -- decoupled, consistent with input.follow_mouse = 0.
  cursor     = {
    no_warps = true,
  },

  debug      = {
    overlay      = false,
    disable_logs = 1,
    vfr          = true,
  },

  render     = {
    cm_enabled  = true,
    cm_auto_hdr = 2,
  },

  binds      = { workspace_back_and_forth = true },

  -- when only one window is on a screen, pad it to this aspect ratio (centered)
  -- instead of stretching full-width on the ultrawide. bump to "21 9" for wider.
  layout     = {
    single_window_aspect_ratio = "16 9",
  },

  dwindle    = { preserve_split = true },

  master     = {
    orientation                   = "center",
    slave_count_for_center_master = 0,
    drop_at_cursor                = true,
  },

  scrolling  = {
    column_width             = 0.25,
    explicit_column_widths   = "0.15, 0.333, 0.45, 0.666",
    fullscreen_on_one_column = false, -- don't stretch a lone column full-width
    focus_fit_method         = 0,     -- 0 = center focused column, 1 = fit (left-park)
  },

  xwayland   = {
    force_zero_scaling   = false,
    use_nearest_neighbor = false,
  },

})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

local curves = {
  def       = { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } },
  sp        = { type = "spring", mass = 1, stiffness = 70, dampening = 10 },
  overshoot = { type = "bezier", points = { { 0.5, 0.9 }, { 0.1, 1.1 } } },
  rubber    = { type = "spring", mass = 1, stiffness = 70, dampening = 10 },
}
for name, def in pairs(curves) do hl.curve(name, def) end

local animCurve = "def"

------------------------------------------------------------------------
-- Animations (per-leaf)
------------------------------------------------------------------------

local function animate(a)
  if a.curve then
    local field = curves[a.curve] and curves[a.curve].type or "bezier"
    a[field]    = a.curve
    a.curve     = nil
  end
  hl.animation(a)
end

for _, anim in ipairs({
  { leaf = "windows",     enabled = true,  speed = speed, curve = animCurve, style = "popin 10%" },
  { leaf = "windowsOut",  enabled = true,  speed = speed, curve = animCurve, style = "popin 10%" },
  { leaf = "border",      enabled = true,  speed = speed, curve = animCurve },
  { leaf = "borderangle", enabled = true,  speed = speed, curve = animCurve },
  { leaf = "fade",        enabled = true,  speed = speed, curve = animCurve },
  { leaf = "fadeLayers",  enabled = false },
  { leaf = "layers",      enabled = false },
  { leaf = "workspaces",  enabled = false, speed = speed, curve = animCurve },
}) do animate(anim) end

------------------------------------------------------------------------
-- Custom layouts
------------------------------------------------------------------------

-- Evenly-sized columns: each window occupies an equal vertical slice.
hl.layout.register("columns", {
  recalculate = function(ctx)
    local n = #ctx.targets
    if n == 0 then return end
    for i, target in ipairs(ctx.targets) do
      target:place(ctx:column(i, n))
    end
  end,
})

-- Square-ish grid: ceil(sqrt(n)) columns, windows flow into cells.
hl.layout.register("grid", {
  recalculate = function(ctx)
    local n = #ctx.targets
    if n == 0 then return end
    local cols = math.ceil(math.sqrt(n))
    for i, target in ipairs(ctx.targets) do
      target:place(ctx:grid_cell(i, cols))
    end
  end,
})

-- Two-row deck: fills columns left-to-right; only columns that need a 2nd
-- window split into 2 rows (top half = window i, bottom half = window i+cols).
-- Columns grow past 5 once both rows are full; max 2 rows.
hl.layout.register("deck", {
  recalculate = function(ctx)
    local n = #ctx.targets
    if n == 0 then return end
    if n <= 5 then
      for i, target in ipairs(ctx.targets) do
        target:place(ctx:column(i, n))
      end
      return
    end

    local cols = math.max(5, math.ceil(n / 2))
    local area = ctx.area
    local col_w = area.width / cols
    local half_h = area.height / 2

    for i, target in ipairs(ctx.targets) do
      local c, row
      if i <= cols then c, row = i, 1 else c, row = i - cols, 2 end

      local has_pair = (cols + c) <= n -- this column also has a row-2 window
      local x = area.x + (c - 1) * col_w
      local box
      if not has_pair then
        box = { x = x, y = area.y, width = col_w, height = area.height }
      elseif row == 1 then
        box = { x = x, y = area.y, width = col_w, height = half_h }
      else
        box = { x = x, y = area.y + half_h, width = col_w, height = half_h }
      end
      target:place(box)
    end
  end,
})

------------------------------------------------------------------------
-- Workspace rules
------------------------------------------------------------------------

for i = 1, 6 do
  hl.workspace_rule({ workspace = tostring(i), monitor = screen })
end
hl.workspace_rule({ workspace = "5", layout = "scrolling", layout_opts = { direction = "right" } })
hl.workspace_rule({ workspace = "6", layout = "lua:columns" })

for i = 8, 10 do
  hl.workspace_rule({ workspace = tostring(i), monitor = laptop, layout_opts = { orientation = "left" } })
end
-- ws7: gaming workspace — default dwindle layout, pinned to the main monitor
hl.workspace_rule({ workspace = "7", monitor = screen })
hl.workspace_rule({ workspace = "8", layout = "lua:deck" })

------------------------------------------------------------------------
-- Special workspaces (scratchpads)
------------------------------------------------------------------------

local term_rule = "[float; size (monitor_w*0.7) (monitor_h*0.7); move (monitor_w*0.15) 16] "
    .. term .. [[ sh -c "printf '\n%.0s' {1..100}; exec $SHELL"]]

local specials = {
  { key = "B",     name = "bt",    desc = "Bluetooth", cmd = "[float; size 900 (monitor_h*0.7); center] foot -e 'bt-tui'" },
  { key = "B",     name = "wifi",  desc = "WiFi",      cmd = "[float; size 900 (monitor_h*0.7); center] foot -e 'wifi-tui'", mod = "SUPER + SHIFT" },
  { key = "G",     name = "audio", desc = "Wiremix",   cmd = "[float; size 1100 (monitor_h*0.6); center] foot -e 'wiremix'" },
  -- { key = "N",     name = "obsidian", desc = "Obsidian",  cmd = "[float; size 1500 (monitor_h*0.9); center] obsidian" }, -- disabled: SUPER+N now cycles Claude sessions
  { key = "grave", name = "term",  desc = "Terminal",  cmd = term_rule },
  -- { key = "R",     name = "gpt",      desc = "GPT",       cmd = "firefox --new-window 'https://gpt.yof.sh'" }, -- disabled: SUPER+R opens the submap launcher
  { key = "M",     name = "music", desc = "Music",     cmd = "firefox --new-window 'https://music.youtube.com'" },
  { key = "W",     name = "tg",    desc = "Telegram",  cmd = "Telegram" },
}
for _, s in ipairs(specials) do
  hl.workspace_rule({ workspace = "special:" .. s.name, monitor = screen, on_created_empty = s.cmd })
  hl.bind((s.mod or "SUPER") .. " + " .. s.key, hl.dsp.workspace.toggle_special(s.name),
    { description = "Scratchpad: " .. s.desc })
end

hl.bind("SUPER + escape", hl.dsp.workspace.toggle_special(), { description = "Toggle current scratchpad" })
hl.bind("SUPER + SHIFT + escape", hl.dsp.window.move({ workspace = "special", follow = true }),
  { description = "Move window to special workspace" })
hl.bind("SUPER + CTRL + escape", hl.dsp.window.move({ workspace = "special", follow = false }),
  { description = "Move window silently to special workspace" })

------------------------------------------------------------------------
-- Lid switch
------------------------------------------------------------------------

hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("powerprofilesctl set power-saver; hypr-lid on"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("powerprofilesctl set balanced; hypr-lid off"), { locked = true })

------------------------------------------------------------------------
-- Autostart
------------------------------------------------------------------------

hl.on("hyprland.start", function()
  hl.exec_cmd("grep -q closed /proc/acpi/button/lid/LID/state && hypr-lid on")
  hl.exec_cmd("awww-daemon")
  hl.exec_cmd("hyprlock --immediate-render")
  hl.exec_cmd("hypridle")
  hl.exec_cmd("hyprsunset")
  hl.exec_cmd("udiskie")
  hl.exec_cmd("foot --server")
  hl.exec_cmd("hypr-watch-monitors")
  hl.exec_cmd("hypr-watch-windows")
  hl.exec_cmd("qs-daemon")
  hl.exec_cmd("sleep 2 && quickshell")
end)

------------------------------------------------------------------------
-- Workspace navigation 1-10 (loop)
------------------------------------------------------------------------

local digits = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }
for i, d in ipairs(digits) do
  local ws = tostring(i)
  hl.bind("SUPER + " .. d, hl.dsp.focus({ workspace = ws }), { description = "Workspace " .. ws })
  hl.bind("SUPER + SHIFT + " .. d, hl.dsp.window.move({ workspace = ws, follow = true }),
    { description = "Move window to workspace " .. ws })
  hl.bind("SUPER + CTRL + " .. d, hl.dsp.window.move({ workspace = ws, follow = false }),
    { description = "Move silently to workspace " .. ws })
end

hl.bind("SUPER + TAB", hl.dsp.focus({ workspace = "e+1" }), { repeating = true, description = "Next workspace" })
hl.bind("SUPER + SHIFT + TAB", hl.dsp.focus({ workspace = "e-1" }),
  { repeating = true, description = "Previous workspace" })

hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })
hl.bind("SUPER + SHIFT + mouse_down", hl.dsp.focus({ direction = "r" }), { description = "Focus right" })
hl.bind("SUPER + SHIFT + mouse_up", hl.dsp.focus({ direction = "l" }), { description = "Focus left" })

------------------------------------------------------------------------
-- Direction loops (focus / move / resize, arrows + hjkl)
------------------------------------------------------------------------

local dirs = {
  { arrow = "left",  vim = "h", dir = "l", dx = -step, dy = 0,     name = "left" },
  { arrow = "right", vim = "l", dir = "r", dx = step,  dy = 0,     name = "right" },
  { arrow = "up",    vim = "k", dir = "u", dx = 0,     dy = -step, name = "up" },
  { arrow = "down",  vim = "j", dir = "d", dx = 0,     dy = step,  name = "down" },
}
for _, d in ipairs(dirs) do
  for _, k in ipairs({ d.arrow, d.vim }) do
    hl.bind("SUPER + " .. k, hl.dsp.focus({ direction = d.dir }), { description = "Focus " .. d.name })
    hl.bind("SUPER + ALT + " .. k, hl.dsp.window.resize({ x = d.dx, y = d.dy, relative = true }),
      { repeating = true, description = "Resize " .. d.name })
  end
  hl.bind("SUPER + SHIFT + " .. d.arrow, hl.dsp.window.move({ direction = d.dir }),
    { description = "Move window " .. d.name })
end

hl.bind("SUPER + CTRL + SHIFT + right", hl.dsp.window.cycle_next(), { description = "Cycle next window" })
hl.bind("SUPER + CTRL + SHIFT + left", hl.dsp.window.cycle_next({ next = false }),
  { description = "Cycle previous window" })

------------------------------------------------------------------------
-- Mouse drag / resize
------------------------------------------------------------------------

hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { description = "Drag window" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { description = "Resize window" })

------------------------------------------------------------------------
-- Terminal & launcher
------------------------------------------------------------------------

hl.bind("SUPER + RETURN", hl.dsp.exec_cmd(term), { description = "Terminal" })
hl.bind("SUPER + CTRL + RETURN",
  hl.dsp.exec_cmd(term .. [[ --working-directory "$(cat ~/.cache/last-dir 2>/dev/null || echo ~)"]]),
  { description = "Terminal in last dir" })
hl.bind("SUPER + SHIFT + RETURN", hl.dsp.exec_cmd("[float; size (monitor_w*0.4) (monitor_h*0.95); center] " .. term),
  { description = "Floating terminal" })
hl.bind("SUPER + CTRL + SHIFT + RETURN",
  hl.dsp.exec_cmd("[float; size (monitor_w*0.4) (monitor_h*0.95); center] " ..
    term .. [[ --working-directory "$(cat ~/.cache/last-dir 2>/dev/null || echo ~)"]]),
  { description = "Floating terminal in last dir" })

hl.bind("SUPER + D", hl.dsp.exec_cmd("vicinae toggle"), { description = "App launcher (vicinae)" })
hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd("wofi -i -M=fuzzy --show drun --allow-images"),
  { description = "App launcher (wofi)" })

------------------------------------------------------------------------
-- Notifications (quickshell)
------------------------------------------------------------------------

hl.bind("SUPER + E", hl.dsp.exec_cmd("qs ipc call notif close"), { description = "Close notification" })
hl.bind("SUPER + SHIFT + E", hl.dsp.exec_cmd("qs ipc call notif historyPop"),
  { description = "Notification history pop" })
hl.bind("SUPER + CTRL + SHIFT + E", hl.dsp.exec_cmd("qs ipc call notif closeAll"),
  { description = "Close all notifications" })
hl.bind("SUPER + SHIFT + period", hl.dsp.exec_cmd("qs ipc call notif context"),
  { description = "Notification default action" })
hl.bind("SUPER + period", hl.dsp.exec_cmd("hypr-notif-actions"),
  { description = "Notification action picker" })

------------------------------------------------------------------------
-- Audio mute toggles
------------------------------------------------------------------------

hl.bind("SUPER + CTRL + SHIFT + S", hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"),
  { description = "Mute microphone" })
hl.bind("SUPER + CTRL + S", hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle"), { description = "Mute audio" })

------------------------------------------------------------------------
-- Voice / LLM
------------------------------------------------------------------------

hl.bind("SUPER + V", hl.dsp.exec_cmd("voice -q -m dictate --paste"), { description = "Voice dictate" })
hl.bind("SUPER + ALT + V", hl.dsp.exec_cmd("voice -q -r -m claude"), { description = "Voice → Claude (replay)" })
hl.bind("SUPER + CTRL + V", hl.dsp.exec_cmd([[MAX_THINKING_TOKENS=0 CLAUDE_EXTRA_ARGS="--model sonnet" voice -m claude]]),
  { description = "Voice → Claude (sonnet)" })
hl.bind("SUPER + SHIFT + V", hl.dsp.exec_cmd("voice -m stream"), { description = "Voice → stream" })
hl.bind("SUPER + CTRL + SHIFT + V", hl.dsp.exec_cmd("share-mobile"), { description = "Share with mobile" })

hl.bind("ALT + grave", hl.dsp.submap("AI"), { description = "AI submap" })
hl.define_submap("AI", "reset", function()
  -- Screen (around cursor)
  hl.bind("S", hl.dsp.exec_cmd("llm -S -n"), { description = "Screen → LLM" })
  hl.bind("A", hl.dsp.exec_cmd("llm -S -n --dmenu"), { description = "Screen → ask (dmenu)" })
  hl.bind("L", hl.dsp.exec_cmd("llm -S --lens"), { description = "Screen → Google Lens" })
  hl.bind("V", hl.dsp.exec_cmd("llm -S -n -V"), { description = "Screen → voice" })
  -- Select region
  hl.bind("I", hl.dsp.exec_cmd("llm -n -w -i"), { description = "Region → LLM" })
  hl.bind("D", hl.dsp.exec_cmd("llm -n -w -i --dmenu"), { description = "Region → ask (dmenu)" })
  hl.bind("G", hl.dsp.exec_cmd("llm -i --lens"), { description = "Region → Google Lens" })
  hl.bind("O", hl.dsp.exec_cmd("ocr"), { description = "OCR" })
  -- Text (no image)
  hl.bind("grave", hl.dsp.exec_cmd("llm -n -w"), { description = "LLM (text)" })
  hl.bind("SHIFT + grave", hl.dsp.exec_cmd("llm -n -w -V"), { description = "LLM (voice)" })
  hl.bind("escape", hl.dsp.submap("reset"))
end)

------------------------------------------------------------------------
-- Vision / barcode / bluetooth status
------------------------------------------------------------------------

hl.bind("SUPER + I", hl.dsp.exec_cmd("ocr"), { description = "OCR" })
hl.bind("SUPER + SHIFT + I", hl.dsp.exec_cmd("llm -i --lens"), { description = "Reverse image search" })
hl.bind("SUPER + O", hl.dsp.exec_cmd("barcode"), { description = "Scan barcode" })
hl.bind("SUPER + U", hl.dsp.exec_cmd("bt-audio toggle"), { description = "Bluetooth audio profile toggle" })

------------------------------------------------------------------------
-- F-keys
------------------------------------------------------------------------

hl.bind("SUPER + F2",
  hl.dsp.exec_cmd(
    [[hyprctl clients -j | jq -e '.[] | select(.class == "firefox")' > /dev/null && hyprctl dispatch focuswindow class:firefox || firefox]]),
  { description = "Firefox (focus or launch)" })
hl.bind("SUPER + SHIFT + F2", hl.dsp.exec_cmd("google-chrome-stable"), { description = "Chrome" })
hl.bind("SUPER + CTRL + F2", hl.dsp.exec_cmd("google-chrome-stable"), { description = "Chrome" })
hl.bind("SUPER + F3", hl.dsp.exec_cmd("setsid " .. term .. [[ -e zsh -c 'source ~/.zshrc; nvim']]),
  { description = "Neovim" })

local debug_overlay = false
local function toggle_debug_overlay()
  debug_overlay = not debug_overlay
  hl.config({ debug = { overlay = debug_overlay } })
end
hl.bind("SUPER + F10", toggle_debug_overlay, { description = "Toggle debug overlay (FPS)" })
hl.bind("CTRL + F11", toggle_debug_overlay, { description = "Toggle debug overlay (FPS)" })

for _, l in ipairs({ { k = "F4", layout = "dwindle" }, { k = "F5", layout = "master" }, { k = "F6", layout = "scrolling" } }) do
  local layout = l.layout
  hl.bind("SUPER + " .. l.k, function()
    hl.config({ general = { layout = layout } })
  end, { description = "Layout → " .. layout })
end

hl.bind("SUPER + CTRL + W",
  hl.dsp.exec_cmd([[[float; size 593 740; center] ]] ..
    term .. [[ --title 'FT Weather' -e sh -c 'curl -s v2.wttr.in/Blanes | less -r']]), { description = "Weather" })
hl.bind("SUPER + CTRL + P",
  hl.dsp.exec_cmd([[[float] ]] .. term .. [[ --title 'FT WIFIPW' -e sh -c 'nmcli dev wifi show-password; read']]),
  { description = "Show WiFi password" })

hl.bind("SUPER + CTRL + J", hl.dsp.exec_cmd(term .. [[ -e sh -c 'journalctl -f -n3000 | lnav -t']]),
  { description = "Journal viewer" })

hl.bind("SUPER + F7", hl.dsp.exec_cmd("meeting-check cam"), { description = "Meeting: camera check" })
hl.bind("SUPER + F8", hl.dsp.exec_cmd("meeting-check mic"), { description = "Meeting: microphone check" })

------------------------------------------------------------------------
-- Screenshots
------------------------------------------------------------------------

hl.bind("SUPER + S", hl.dsp.exec_cmd("screenshot -r -c -n"), { description = "Screenshot region → clipboard" })
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("screenshot -r -e -n"), { description = "Screenshot region → edit" })
hl.bind("SUPER + ALT + S", hl.dsp.exec_cmd("screenshot -f -e -n"), { description = "Screenshot full → edit" })
hl.bind("SUPER + CTRL + ALT + S", hl.dsp.exec_cmd("screenshot -w -c -n"),
  { description = "Screenshot window → clipboard" })

------------------------------------------------------------------------
-- System monitors (floating)
------------------------------------------------------------------------

for _, m in ipairs({
  { keys = "CTRL + SHIFT + escape", title = "htop",    cmd = "htop",    desc = "htop" },
  { keys = "CTRL + SHIFT + F1",     title = "btop",    cmd = "btop",    desc = "btop" },
  { keys = "CTRL + SHIFT + F2",     title = "glances", cmd = "glances", desc = "glances" },
}) do
  hl.bind(m.keys,
    hl.dsp.exec_cmd("[float; size (monitor_w*0.96) (monitor_h*0.96); center] " ..
      term .. " --title 'FT " .. m.title .. "' -e '" .. m.cmd .. "'"),
    { description = "System monitor: " .. m.desc })
end

------------------------------------------------------------------------
-- Media keys
------------------------------------------------------------------------

for _, v in ipairs({
  { key = "XF86AudioRaiseVolume",  cmd = "pactl set-sink-volume @DEFAULT_SINK@ +5%",      desc = "Volume up" },
  { key = "XF86AudioLowerVolume",  cmd = "pactl set-sink-volume @DEFAULT_SINK@ -5%",      desc = "Volume down" },
  { key = "XF86AudioMute",         cmd = "pactl set-sink-mute @DEFAULT_SINK@ toggle",     desc = "Mute" },
  { key = "XF86AudioMicMute",      cmd = "pactl set-source-mute @DEFAULT_SOURCE@ toggle", desc = "Mute microphone" },
  { key = "XF86MonBrightnessUp",   cmd = "brightnessctl set 5%+",                         desc = "Brightness up" },
  { key = "XF86MonBrightnessDown", cmd = "brightnessctl set 5%-",                         desc = "Brightness down" },
  { key = "XF86AudioPlay",         cmd = "playerctl play-pause",                          desc = "Play/Pause" },
  { key = "XF86AudioPause",        cmd = "playerctl play-pause",                          desc = "Play/Pause" },
  { key = "XF86AudioNext",         cmd = "playerctl next",                                desc = "Next track" },
  { key = "XF86AudioPrev",         cmd = "playerctl prev",                                desc = "Previous track" },
}) do
  hl.bind(v.key, hl.dsp.exec_cmd(v.cmd), { description = v.desc })
end

-- locked: also fire when lockscreen active
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

hl.bind("SUPER + ALT + D", hl.dsp.exec_cmd("dark-mode-toggle"), { description = "Toggle dark mode" })
hl.bind("SUPER + equal", hl.dsp.exec_cmd("playerctl play-pause"), { description = "Play/Pause" })
hl.bind("SUPER + bracketright", hl.dsp.exec_cmd("playerctl next"), { description = "Next track" })
hl.bind("SUPER + bracketleft", hl.dsp.exec_cmd("playerctl previous"), { description = "Previous track" })

------------------------------------------------------------------------
-- Wallpaper (global)
------------------------------------------------------------------------

hl.bind("SUPER + SHIFT + bracketright", hl.dsp.exec_cmd("wallpaper -s next"), { description = "Next wallpaper" })
hl.bind("SUPER + SHIFT + bracketleft", hl.dsp.exec_cmd("wallpaper -s prev"), { description = "Previous wallpaper" })
hl.bind("SUPER + SHIFT + backslash", hl.dsp.exec_cmd("wallpaper random"), { description = "Random wallpaper" })

------------------------------------------------------------------------
-- Display scaling
------------------------------------------------------------------------

hl.bind("SUPER + SHIFT + F5", hl.dsp.exec_cmd("hypr-scale -"), { description = "Scale screen smaller" })
hl.bind("SUPER + SHIFT + F6", hl.dsp.exec_cmd("hypr-scale +"), { description = "Scale screen larger" })

------------------------------------------------------------------------
-- Window management
------------------------------------------------------------------------

hl.bind("SUPER + SHIFT + Q", hl.dsp.window.close(), { description = "Close active window" })
hl.bind("SUPER + SHIFT + CTRL + Q", hl.dsp.window.kill(), { description = "Force kill active window" })
hl.bind("SUPER + SHIFT + CTRL + ALT + Q", hl.dsp.exit(), { description = "Exit Hyprland" })
hl.bind("SUPER + A", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
hl.bind("SUPER + SHIFT + A", hl.dsp.window.pin(), { description = "Pin window" })
hl.bind("SUPER + P", hl.dsp.window.pseudo({ action = "toggle" }), { description = "Toggle pseudo-tiling" })
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }),
  { description = "Fullscreen" })
hl.bind("SUPER + F", hl.dsp.window.fullscreen_state({ internal = 2, client = 0, action = "toggle" }),
  { description = "Maximize (client-unaware)" })

hl.bind("SUPER + CTRL + SHIFT + W", hl.dsp.exec_cmd("pkill quickshell; quickshell &"),
  { description = "Restart quickshell" })
hl.bind("SUPER + ALT + N", hl.dsp.exec_cmd("qs ipc call network toggle"), { description = "Network popup" })
hl.bind("SUPER + ALT + P", hl.dsp.exec_cmd("hypr-pip-toggle"), { description = "Toggle picture-in-picture" })

-- Cycle focus through running Claude Code sessions (bar order)
hl.bind("SUPER + N", hl.dsp.exec_cmd("cc-session-focus next"), { description = "Next Claude session" })
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("cc-session-focus prev"), { description = "Previous Claude session" })

------------------------------------------------------------------------
-- Master layout
------------------------------------------------------------------------

hl.bind("SUPER + CTRL + SHIFT + right", hl.dsp.layout("swapwithmaster master"), { description = "Promote to master" })
-- hl.bind("SUPER + R", hl.dsp.layout("rollnext"), { repeating = true, description = "Roll next" })
hl.bind("SUPER + SHIFT + R", hl.dsp.layout("rollprev"), { repeating = true, description = "Roll previous" })
hl.bind("SUPER + Q", hl.dsp.layout("togglesplit"), { description = "Toggle split" })
hl.bind("SUPER + CTRL + Q", hl.dsp.layout("swapsplit"), { description = "Swap split" })

------------------------------------------------------------------------
-- Smart home (global)
------------------------------------------------------------------------

hl.bind("SUPER + ALT + W", hl.dsp.exec_cmd("ha toggle switch.smart_plug_socket_1"), { description = "Toggle socket 1" })
hl.bind("SUPER + ALT + E", hl.dsp.exec_cmd("ha toggle light.svet_v_spalne"), { description = "Toggle bedroom light" })

------------------------------------------------------------------------
-- Lock screen & reload
------------------------------------------------------------------------

hl.bind("SUPER + CTRL + l", hl.dsp.exec_cmd("hyprctl switchxkblayout all 0 && hyprlock"), { description = "Lock screen" })
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"), { description = "Reload Hyprland" })

------------------------------------------------------------------------
-- Keyboard layout
------------------------------------------------------------------------

-- Caps Lock = Menu keysym (via kb_options caps:menu)
hl.bind("Menu", hl.dsp.exec_cmd("hypr-lang-toggle"), { description = "Layout: toggle EN / RU (Caps Lock)" })
hl.bind("CTRL + Menu", hl.dsp.exec_cmd("hyprctl switchxkblayout all 2"),
  { description = "Layout → Ukrainian (Ctrl+Caps)" })

------------------------------------------------------------------------
-- Helper: exec then reset submap
------------------------------------------------------------------------

local function exec_then_reset(cmd)
  return function()
    hl.dispatch(hl.dsp.exec_cmd(cmd))
    hl.dispatch(hl.dsp.submap("reset"))
  end
end

------------------------------------------------------------------------
-- Bookmarks submap (auto-reset)
------------------------------------------------------------------------

hl.bind("SUPER + CTRL + H", hl.dsp.submap("Bookmarks"), { description = "Bookmarks submap" })
hl.define_submap("Bookmarks", "reset", function()
  for _, b in ipairs({
    { key = "h", url = "http://hermes:8123/",        desc = "Home Assistant" },
    { key = "a", url = "http://hermes:3001/",        desc = "AdGuard" },
    { key = "f", url = "http://192.168.1.149:5000/", desc = "Frigate" },
    { key = "u", url = "http://192.168.1.149:8123/", desc = "Home Assistant (LAN)" },
  }) do
    hl.bind(b.key, hl.dsp.exec_cmd("xdg-open '" .. b.url .. "'"), { description = b.desc })
  end
  hl.bind("escape", hl.dsp.submap("reset"))
end)

------------------------------------------------------------------------
-- Monitor stats submap (manual exit)
------------------------------------------------------------------------

hl.bind("SUPER + CTRL + E", hl.dsp.submap("Monitor"), { description = "System stats submap" })
hl.define_submap("Monitor", function()
  for _, m in ipairs({
    { key = "E",         qs = "ping",            desc = "Pings" },
    { key = "SHIFT + E", qs = "ping fast",       desc = "Pings 0.5s" },
    { key = "S",         qs = "temperature",     desc = "Sensors" },
    { key = "B",         qs = "battery",         desc = "Battery" },
    { key = "W",         qs = "weather",         desc = "Weather" },
    { key = "M",         qs = "system",          desc = "System stats" },
    { key = "P",         qs = "cpu",             desc = "Processes" },
    { key = "K",         qs = "khal",            desc = "Khal agenda" },
    { key = "F",         qs = "focus",           desc = "Focus timer" },
    { key = "U",         qs = "app-usage",       desc = "Wellbeing / usage" },
    { key = "C",         qs = "claude-usage",    desc = "Claude usage" },
    { key = "A",         qs = "claude-sessions", desc = "Claude sessions" },
    { key = "J",         qs = "printjobs",       desc = "Print queue" },
  }) do
    hl.bind(m.key, hl.dsp.exec_cmd("qs ipc call " .. m.qs .. " toggle"), { description = m.desc })
  end
  hl.bind("N", hl.dsp.exec_cmd("qs ipc call network togglePopup"), { description = "Network" })
  hl.bind("escape", function()
    for _, w in ipairs({ "temperature", "battery", "weather", "system", "cpu", "khal", "network", "focus", "app-usage", "claude-usage", "claude-sessions", "printjobs" }) do
      hl.dispatch(hl.dsp.exec_cmd("qs ipc call " .. w .. " close"))
    end
    hl.dispatch(hl.dsp.submap("reset"))
  end, { description = "Close all & exit" })
end)

------------------------------------------------------------------------
-- Translate submap (auto-reset)
------------------------------------------------------------------------

local langs = { { k = "Z", lang = "en" }, { k = "X", lang = "ru" }, { k = "C", lang = "es" } }
local dict_keys = { { k = "Q", lang = "en" }, { k = "W", lang = "ru" }, { k = "E", lang = "es" } }
local claude_langs = {
  { k = "A", lang = "en", label = "EN" },
  { k = "S", lang = "ru", label = "RU" },
  { k = "D", lang = "es", label = "ES" },
}

hl.bind("SUPER + X", hl.dsp.submap("Translate"), { description = "Translate submap" })
hl.define_submap("Translate", "reset", function()
  for _, x in ipairs(langs) do
    hl.bind(x.k, hl.dsp.exec_cmd("translate " .. x.lang), { description = "Translate " .. x.lang })
    hl.bind("SHIFT + " .. x.k, hl.dsp.exec_cmd("translate " .. x.lang .. " replace"),
      { description = "Translate " .. x.lang .. " (replace)" })
  end
  for _, x in ipairs(claude_langs) do
    hl.bind(x.k, hl.dsp.exec_cmd("claude-text " .. x.lang), { description = "Claude " .. x.label })
    hl.bind("SHIFT + " .. x.k, hl.dsp.exec_cmd("claude-text " .. x.lang .. " replace"),
      { description = "Claude " .. x.label .. " (replace)" })
  end
  for _, x in ipairs(dict_keys) do
    hl.bind(x.k, hl.dsp.exec_cmd(
      [[sh -c 'text=$(wl-paste -p); encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$text"); xdg-open "https://translate.google.com/details?sl=auto&tl=]] ..
      x.lang .. [[&text=$encoded&op=translate"']]
    ), { description = "Dict " .. string.upper(x.lang) })
  end
  hl.bind("F", hl.dsp.exec_cmd("claude-text fix replace"), { description = "Fix grammar" })
  hl.bind("G", hl.dsp.exec_cmd("claude-text formal replace"), { description = "Formalize" })
  hl.bind("escape", hl.dsp.submap("reset"))
end)

------------------------------------------------------------------------
-- YTS submap (auto-reset)
------------------------------------------------------------------------

hl.bind("SUPER + T", hl.dsp.submap("YTS"), { description = "YTS submap" })
hl.define_submap("YTS", "reset", function()
  for _, y in ipairs({
    { key = "L", cmd = "[float; size 1400 (monitor_h*0.8); center] foot -e yts list", desc = "📋 List summaries" },
    { key = "S", cmd = "yts summarize \"$(wl-paste --no-newline)\"", desc = "📝 Summarize clipboard" },
    { key = "A", cmd = "[float; size 1400 (monitor_h*0.8); center] foot -e yts ask", desc = "💬 Ask about video" },
    { key = "T", cmd = "[float; size (monitor_w*0.5) (monitor_h*0.5); center] foot -e yts status", desc = "📊 Status" },
    { key = "R", cmd = "foot -e yts retry", desc = "🔄 Retry failed" },
  }) do
    hl.bind(y.key, hl.dsp.exec_cmd(y.cmd), { description = y.desc })
  end
  hl.bind("escape", hl.dsp.submap("reset"))
end)

------------------------------------------------------------------------
-- Screenshot submap (auto-reset)
------------------------------------------------------------------------

-- Reached via the Submap launcher (SUPER + R → C), no direct keybind.
hl.define_submap("Screenshot", "reset", function()
  for _, s in ipairs({
    { key = "R", flag = "-r", desc = "Region" },
    { key = "W", flag = "-w", desc = "Window" },
    { key = "F", flag = "-f", desc = "Fullscreen" },
  }) do
    hl.bind(s.key, hl.dsp.exec_cmd("screenshot " .. s.flag .. " -c -n"),
      { description = s.desc .. " → clipboard" })
    hl.bind("SHIFT + " .. s.key, hl.dsp.exec_cmd("screenshot " .. s.flag .. " -e -n"),
      { description = s.desc .. " → edit" })
    hl.bind("ALT + " .. s.key, hl.dsp.exec_cmd("screenshot " .. s.flag .. " -u -n"),
      { description = s.desc .. " → upload" })
  end
  hl.bind("escape", hl.dsp.submap("reset"))
end)

------------------------------------------------------------------------
-- Record submap (auto-reset)
------------------------------------------------------------------------

-- Reached via the Submap launcher (SUPER + R → F), no direct keybind.
hl.define_submap("Record", "reset", function()
  for _, r in ipairs({
    { key = "R", type = "region", desc = "Region" },
    { key = "W", type = "window", desc = "Window" },
    { key = "F", type = "full",   desc = "Fullscreen" },
  }) do
    hl.bind(r.key, hl.dsp.exec_cmd("screencast " .. r.type),
      { description = r.desc .. " (toggle)" })
  end
  hl.bind("escape", hl.dsp.submap("reset"))
end)

------------------------------------------------------------------------
-- Wallpaper submap (manual exit; Gallery exits)
------------------------------------------------------------------------

hl.bind("SUPER + backslash", hl.dsp.submap("Wallpaper"), { description = "Wallpaper submap" })
hl.define_submap("Wallpaper", function()
  hl.bind("bracketright", hl.dsp.exec_cmd("wallpaper -s next"), { repeating = true, description = "Next" })
  hl.bind("bracketleft", hl.dsp.exec_cmd("wallpaper -s prev"), { repeating = true, description = "Prev" })
  for _, w in ipairs({
    { key = "r", arg = "random",   desc = "Random saved" },
    { key = "o", arg = "oled",     desc = "Download OLED" },
    { key = "n", arg = "nature",   desc = "Download Nature" },
    { key = "p", arg = "panorama", desc = "Download Panorama" },
    { key = "c", arg = "colorful", desc = "Download Colorful" },
    { key = "e", arg = "night",    desc = "Download Night" },
    { key = "t", arg = "contrast", desc = "Download Contrast" },
    { key = "s", arg = "",         desc = "Download Random" },
  }) do
    hl.bind(w.key, hl.dsp.exec_cmd("wallpaper " .. w.arg), { description = w.desc })
  end
  hl.bind("SHIFT + d", hl.dsp.exec_cmd("wallpaper delete"), { description = "Delete current" })
  hl.bind("g", exec_then_reset("qs ipc call wallpaper toggle"), { description = "Gallery" })
  hl.bind("escape", hl.dsp.submap("reset"))
end)

------------------------------------------------------------------------
-- Master Layout submap (manual exit)
------------------------------------------------------------------------

hl.bind("SUPER + CTRL + R", hl.dsp.submap("Master Layout"), { description = "Master layout submap" })
hl.define_submap("Master Layout", function()
  hl.bind("R", hl.dsp.layout("swapnext"), { description = "Swap with next" })
  hl.bind("SHIFT + R", hl.dsp.layout("swapprev"), { description = "Swap with previous" })

  for _, o in ipairs({
    { key = "J", arg = "orientationbottom", desc = "Orient bottom" },
    { key = "K", arg = "orientationtop",    desc = "Orient top" },
    { key = "H", arg = "orientationleft",   desc = "Orient left" },
    { key = "L", arg = "orientationright",  desc = "Orient right" },
    { key = "G", arg = "orientationcenter", desc = "Orient center" },
    { key = "U", arg = "orientationnext",   desc = "Orient next" },
    { key = "I", arg = "orientationprev",   desc = "Orient previous" },
  }) do
    hl.bind(o.key, hl.dsp.layout(o.arg), { description = o.desc })
  end
  hl.bind("escape", hl.dsp.submap("reset"))
end)

------------------------------------------------------------------------
-- Bedroom (Home Assistant) submap (manual exit)
------------------------------------------------------------------------

local lights = {
  { key = "Z", entity = "light.wled_bed", preset = "select.wled_bed_preset", label = "Bed LED", icon = "🛏️" },
  { key = "X", entity = "light.wled_monitor", preset = "select.wled_monitor_preset", label = "Monitor LED", icon = "🖥️" },
  { key = "C", entity = "light.power_light", preset = "select.power_light_preset", label = "Power light", icon = "💡" },
}
local scenes = {
  { key = "A", scene = "scene.bedroom_full_daylight", desc = "☀️ Full daylight" },
  { key = "S", scene = "scene.bedroom_soft_daylight", desc = "🌤️ Soft daylight" },
  { key = "D", scene = "scene.bedroom_evening_light", desc = "🌆 Evening" },
  { key = "F", scene = "scene.bedroom_night", desc = "🌙 Night" },
}
local covers = {
  { key = "V", entity = "cover.rf_remote_bedroom_blinds_cover", label = "Blinds", icon = "🪟" },
  { key = "B", entity = "cover.zb_curtain_1", label = "Curtain", icon = "🏠" },
}

hl.bind("SUPER + ALT + B", hl.dsp.submap("Bedroom"), { description = "Bedroom controls submap" })
hl.define_submap("Bedroom", function()
  for _, l in ipairs(lights) do
    hl.bind(l.key, hl.dsp.exec_cmd("ha toggle " .. l.entity), { description = l.icon .. " " .. l.label .. " toggle" })
    hl.bind("SHIFT + " .. l.key, hl.dsp.exec_cmd("ha up " .. l.entity),
      { repeating = true, description = l.icon .. " " .. l.label .. " brighter" })
    hl.bind("CTRL + " .. l.key, hl.dsp.exec_cmd("ha down " .. l.entity),
      { repeating = true, description = l.icon .. " " .. l.label .. " dimmer" })
    hl.bind("ALT + " .. l.key, hl.dsp.exec_cmd("ha next_preset " .. l.preset),
      { description = l.icon .. " " .. l.label .. " next preset" })
    hl.bind("ALT + SHIFT + " .. l.key, hl.dsp.exec_cmd("ha prev_preset " .. l.preset),
      { description = l.icon .. " " .. l.label .. " prev preset" })
  end
  for _, s in ipairs(scenes) do
    hl.bind(s.key, hl.dsp.exec_cmd("ha scene " .. s.scene), { description = s.desc })
  end
  for _, c in ipairs(covers) do
    hl.bind(c.key, hl.dsp.exec_cmd("ha toggle " .. c.entity), { description = c.icon .. " " .. c.label .. " toggle" })
    hl.bind("SHIFT + " .. c.key, hl.dsp.exec_cmd("ha open " .. c.entity),
      { description = c.icon .. " " .. c.label .. " up" })
    hl.bind("CTRL + " .. c.key, hl.dsp.exec_cmd("ha close " .. c.entity),
      { description = c.icon .. " " .. c.label .. " down" })
  end
  hl.bind("escape", hl.dsp.submap("reset"))
end)

------------------------------------------------------------------------
-- Resize submap (manual exit, repeating)
------------------------------------------------------------------------

hl.bind("ALT + R", hl.dsp.submap("resize"), { description = "Resize submap" })
hl.define_submap("resize", function()
  for _, d in ipairs(dirs) do
    hl.bind(d.arrow, hl.dsp.window.resize({ x = d.dx, y = d.dy, relative = true }),
      { repeating = true, description = "Resize " .. d.name })
  end
  hl.bind("escape", hl.dsp.submap("reset"))
end)

------------------------------------------------------------------------
-- Services submap (auto-reset)
------------------------------------------------------------------------

local function tui(cmd) return "[float; size (monitor_w*0.8) (monitor_h*0.8); center] " .. term .. " -e " .. cmd end

hl.bind("CTRL + SHIFT + ALT + S", hl.dsp.submap("Services"), { description = "Services submap" })
hl.define_submap("Services", "reset", function()
  for _, s in ipairs({
    { key = "Q", cmd = "pkill quickshell; quickshell &",                                                                                                    desc = "Restart quickshell" },
    { key = "S", cmd = tui("systemctl-tui"),                                                                                                                desc = "systemctl-tui" },
    { key = "K", cmd = tui("kmon"),                                                                                                                         desc = "kmon" },
    { key = "J", cmd = tui([[sh -c 'journalctl -f -n3000 | lnav -t']]),                                                                                     desc = "journal" },
    { key = "W", cmd = "[float; size (monitor_w*0.6) (monitor_h*0.7); center] " .. term .. " -e wifi-tui",                                                  desc = "wifi" },
    { key = "Z", cmd = tui("sysz"),                                                                                                                         desc = "sysz" },
    { key = "A", cmd = [[pkill librepodsd; sleep 0.5 && ~/dev/librepods/linux/build/librepodsd & notify-send -i audio-headphones "LibrePods restarted"]],   desc = "Restart LibrePods" },
    { key = "P", cmd = [[systemctl --user restart pipewire pipewire-pulse wireplumber && notify-send -i audio-volume-high "PipeWire restarted"]],           desc = "Restart PipeWire" },
    { key = "O", cmd = [[systemctl --user restart xdg-desktop-portal xdg-desktop-portal-hyprland && notify-send -i preferences-system "Portal restarted"]], desc = "Restart Portal" },
    { key = "B", cmd = [[sudo systemctl restart bluetooth && notify-send -i bluetooth "Bluetooth restarted"]],                                              desc = "Restart Bluetooth" },
  }) do
    hl.bind(s.key, hl.dsp.exec_cmd(s.cmd), { description = s.desc })
  end
  hl.bind("escape", hl.dsp.submap("reset"))
end)

------------------------------------------------------------------------
-- Power submap (auto-reset)
------------------------------------------------------------------------

hl.bind("SUPER + ALT + escape", hl.dsp.submap("Power"), { description = "Power submap" })
hl.define_submap("Power", "reset", function()
  hl.bind("s", hl.dsp.exec_cmd("systemctl suspend"), { description = "Suspend" })
  hl.bind("SHIFT + s", hl.dsp.exec_cmd("shutdown now"), { description = "Shutdown" })
  hl.bind("l", hl.dsp.exec_cmd("hyprctl switchxkblayout all 0 && hyprlock"), { description = "Lock" })
  hl.bind("r", hl.dsp.exec_cmd("reboot"), { description = "Reboot" })
  hl.bind("b", hl.dsp.exec_cmd("systemctl reboot --firmware-setup"), { description = "Reboot → firmware setup" })
  hl.bind("escape", hl.dsp.submap("reset"))
end)

------------------------------------------------------------------------
-- Submap launcher / aggregator (left-hand keys jump to any submap)
------------------------------------------------------------------------

hl.bind("SUPER + R", hl.dsp.submap("Launcher"), { description = "Launcher submap" })
hl.define_submap("Launcher", function()
  for _, s in ipairs({
    { key = "A", target = "AI", desc = "🤖 AI" },
    { key = "B", target = "Bookmarks", desc = "🔖 Bookmarks" },
    { key = "C", target = "Screenshot", desc = "📸 Screenshot" },
    { key = "D", target = "Bedroom", desc = "🛏️ Bedroom" },
    { key = "E", target = "Monitor", desc = "📊 System stats" },
    { key = "F", target = "Record", desc = "🎥 Record" },
    { key = "G", target = "Master Layout", desc = "🪟 Master layout" },
    { key = "Q", target = "Power", desc = "⏻ Power" },
    { key = "R", target = "resize", desc = "↔ Resize" },
    { key = "S", target = "Services", desc = "🔧 Services" },
    { key = "T", target = "Translate", desc = "🌐 Translate" },
    { key = "V", target = "YTS", desc = "🎬 YTS" },
    { key = "W", target = "Wallpaper", desc = "🖼 Wallpaper" },
  }) do
    hl.bind(s.key, hl.dsp.submap(s.target), { description = s.desc })
  end
  hl.bind("escape", hl.dsp.submap("reset"))
end)

------------------------------------------------------------------------
-- Layer rules
------------------------------------------------------------------------

for _, r in ipairs({
  { match = { namespace = "^(quickshell)$" },           blur = true },
  { match = { namespace = "^(quickshell)$" },           ignore_alpha = 0 },
  { match = { namespace = "^(quickshell)$" },           animation = "off" },
  { match = { namespace = "^(quickshell-wallpaper)$" }, animation = "off" },
  { match = { namespace = "^(selection)$" },            animation = "off" },
}) do hl.layer_rule(r) end

------------------------------------------------------------------------
-- Window rules
------------------------------------------------------------------------

local tg_class = "^(org\\.telegram\\.desktop)"
for _, r in ipairs({
  { workspace = "special:tg" },
  { focus_on_activate = false },
  { pseudo = true,            size = { "900", "monitor_h*0.95" } },
}) do
  r.match = { class = tg_class }
  hl.window_rule(r)
end

hl.window_rule({ match = { class = "^(steam)$" }, workspace = "7" })
hl.window_rule({ match = { class = "^(steam_app_\\d+|gamescope)$" }, workspace = "7" })
hl.window_rule({ match = { class = "^(com\\.gabm\\.satty)$" }, float = true, max_size = { 2592, 1296 } })
hl.window_rule({ match = { class = "^(imv)$" }, float = true, size = { "monitor_w*0.5", "monitor_h*0.95" } })

local pip_title = "^(Picture-in-Picture)"
for _, r in ipairs({
  { float = true },
  { pin = true },
  { size = { "800", "450" } },
  { move = { "monitor_w-820", "monitor_h-470" } },
}) do
  r.match = { initial_title = pip_title }
  hl.window_rule(r)
end

hl.window_rule({ match = { float = false, workspace = "w[tv1]" }, border_size = 0 })
