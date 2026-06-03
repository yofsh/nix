import type { DaemonModule, DaemonContext } from "../types.ts";

const MOD_BITS: [number, string][] = [
  [64, "SUPER"],
  [8, "ALT"],
  [4, "CTRL"],
  [1, "SHIFT"],
];

const MOD_ORDER: Record<string, number> = { SUPER: 0, CTRL: 1, ALT: 2, SHIFT: 3 };

const COMMAND_NAMES: Record<string, string> = {
  firefox: "Firefox",
  "google-chrome-stable": "Google Chrome",
  obsidian: "Obsidian",
  pactl: "PulseAudio control",
  wpctl: "WirePlumber control",
  playerctl: "Media player control",
  light: "Screen brightness",
  hyprlock: "Lock screen",
  wofi: "App launcher (wofi)",
  vicinae: "App launcher (vicinae)",
  htop: "System monitor (htop)",
  btop: "System monitor (btop)",
  glances: "System monitor (glances)",
  systemctl: "Systemd control",
  shutdown: "Shutdown",
  reboot: "Reboot",
  "xdg-open": "Open URL",
  "wl-paste": "Clipboard paste",
  foot: "Terminal (foot)",
  nvim: "Neovim",
  gping: "Graphical ping",
  nmcli: "Network manager",
  curl: "Fetch URL",
  journalctl: "System journal",
  killall: "Kill process",
  powerprofilesctl: "Power profile control",
};

const XF86_NAMES: Record<string, string> = {
  XF86AudioRaiseVolume: "Volume Up",
  XF86AudioLowerVolume: "Volume Down",
  XF86AudioMute: "Mute Audio",
  XF86AudioMicMute: "Mute Microphone",
  XF86MonBrightnessUp: "Brightness Up",
  XF86MonBrightnessDown: "Brightness Down",
  XF86AudioPlay: "Media Play",
  XF86AudioPause: "Media Pause",
  XF86AudioNext: "Media Next",
  XF86AudioPrev: "Media Previous",
};

const KEY_NAMES: Record<string, string> = {
  RETURN: "Enter",
  escape: "Esc",
  grave: "`",
  minus: "-",
  plus: "+",
  equal: "=",
  bracketleft: "[",
  bracketright: "]",
  backslash: "\\",
  period: ".",
  comma: ",",
  TAB: "Tab",
  "mouse:272": "LMB",
  "mouse:273": "RMB",
  mouse_down: "Scroll Down",
  mouse_up: "Scroll Up",
  left: "←",
  right: "→",
  up: "↑",
  down: "↓",
  ...XF86_NAMES,
};

const MOD_ICONS: Record<string, string> = {
  SUPER: "\u{F0633}",
  CTRL: "\u{F0634}",
  ALT: "\u{F0635}",
  SHIFT: "\u{F0636}",
};

const DIRECTIONS: Record<string, string> = { l: "left", r: "right", u: "up", d: "down" };

const LAYOUT_MSGS: Record<string, string> = {
  rollnext: "Roll next",
  rollprev: "Roll previous",
  swapnext: "Swap with next",
  swapprev: "Swap with previous",
  togglesplit: "Toggle split",
  swapsplit: "Swap split",
  orientationbottom: "Orientation bottom",
  orientationtop: "Orientation top",
  orientationleft: "Orientation left",
  orientationright: "Orientation right",
  orientationcenter: "Orientation center",
  orientationnext: "Orientation next",
  orientationprev: "Orientation previous",
  promote: "Promote to master",
};

function modmaskToMods(modmask: number): string {
  const parts = MOD_BITS.filter(([bit]) => modmask & bit).map(([, name]) => name);
  parts.sort((a, b) => (MOD_ORDER[a] ?? 99) - (MOD_ORDER[b] ?? 99));
  return parts.join(" ");
}

function formatPretty(mods: string, key: string, description: string): string {
  const parts = mods ? mods.split(" ").map((m) => MOD_ICONS[m] || m) : [];
  parts.push(KEY_NAMES[key] || (key.length === 1 ? key.toUpperCase() : key));
  return `${parts.join(" ")} — ${description}`;
}

function describeExec(args: string): string {
  let cmd = args.trim();
  if (!cmd) return "Execute command";
  cmd = cmd.replace(/^\[.*?\]\s*/, "");
  while (/^[A-Z_]+=/.test(cmd)) {
    cmd = cmd.replace(/^[A-Z_]+="[^"]*"\s*/, "");
    cmd = cmd.replace(/^[A-Z_]+='[^']*'\s*/, "");
    cmd = cmd.replace(/^[A-Z_]+=\S+\s+/, "");
  }
  if (!cmd) return "Execute command";
  const tokens = cmd.split(/\s+/);
  const base = tokens[0].split("/").pop()!;
  const rest = cmd.slice(tokens[0].length).trim();
  if (COMMAND_NAMES[base]) return rest ? `${COMMAND_NAMES[base]}: ${rest}` : COMMAND_NAMES[base];
  if (base.endsWith(".sh")) {
    const name = base.slice(0, -3);
    return rest ? `Run ${name}: ${rest}` : `Run ${name}`;
  }
  return rest ? `Run ${base}: ${rest}` : `Run ${base}`;
}

function autoDescribe(dispatcher: string, args: string): string {
  const d = (dispatcher || "").trim().toLowerCase();
  const a = (args || "").trim();

  if (d === "exec") return describeExec(a);
  if (d === "workspace") {
    return a.startsWith("e+") || a.startsWith("e-")
      ? `Switch to workspace (relative): ${a}` : `Switch to workspace ${a}`;
  }
  if (d === "movetoworkspace") return a === "special" ? "Move window to special workspace" : `Move window to workspace ${a}`;
  if (d === "movetoworkspacesilent") return a === "special" ? "Move window silently to special workspace" : `Move window silently to workspace ${a}`;
  if (d === "togglespecialworkspace") return a ? `Toggle special workspace: ${a}` : "Toggle special workspace";
  if (d === "movefocus") return `Focus ${DIRECTIONS[a] || a}`;
  if (d === "movewindow") return !a ? "Move window (mouse)" : `Move window ${DIRECTIONS[a] || a}`;
  if (d === "resizewindow") return "Resize window (mouse)";
  if (d === "resizeactive") return `Resize active window: ${a}`;
  if (d === "killactive") return "Kill active window";
  if (d === "togglefloating") return "Toggle floating";
  if (d === "fullscreen") return "Toggle fullscreen";
  if (d === "pseudo") return "Toggle pseudo-tiling";
  if (d === "pin") return "Pin window";
  if (d === "cyclenext") return a === "prev" ? "Cycle to previous window" : "Cycle to next window";
  if (d === "exit") return "Exit Hyprland";
  if (d === "layoutmsg") return `Layout: ${LAYOUT_MSGS[a] || a}`;
  if (d === "submap") return `Enter submap: ${a}`;
  if (d.includes(":")) {
    const [plugin, action] = d.split(":", 2);
    return a ? `${plugin}: ${action} ${a}`.trimEnd() : `${plugin}: ${action}`;
  }
  return `${d} ${a}`.trim() || d;
}

interface BindEntry {
  mods: string;
  key: string;
  dispatcher: string;
  args: string;
  description: string;
  pretty: string;
  type: string;
}

interface Submap {
  name: string;
  label: string;
  activator?: { mods: string; key: string };
  binds: BindEntry[];
}

function build(binds: any[]): { global: BindEntry[]; submaps: Submap[] } {
  const globalBinds: BindEntry[] = [];
  const submaps = new Map<string, { binds: BindEntry[]; label: string; activator: { mods: string; key: string } | null }>();
  const submapActivators = new Map<string, { mods: string; key: string }>();
  const pendingActivators: { mods: string; key: string; description: string }[] = [];

  for (const b of binds) {
    const dispatcher = (b.dispatcher || "").trim();
    const args = (b.arg || "").trim();
    const submap = (b.submap || "").trim();
    const mods = modmaskToMods(b.modmask || 0);
    const key = (b.key || "").trim();

    if (dispatcher === "submap" && args === "reset") continue;

    let description = (b.description || "").trim();
    if (!description) description = autoDescribe(dispatcher, args);

    // Detect submap activators: global binds with dispatcher "submap" (conf)
    // or description ending in " submap" (lua, where dispatcher is "__lua")
    if (!submap) {
      if (dispatcher === "submap" && args) {
        submapActivators.set(args, { mods, key });
      } else if (/\bsubmap$/i.test(description)) {
        // For __lua binds, try to match by submap name in known submaps later
        pendingActivators.push({ mods, key, description });
      }
    }

    let flags = "";
    if (b.locked) flags += "l";
    if (b.release) flags += "r";
    if (b.repeat) flags += "e";
    if (b.mouse) flags += "m";
    if (b.non_consuming) flags += "n";
    if (b.longPress) flags += "p";

    const entry: BindEntry = {
      mods,
      key,
      dispatcher,
      args,
      description,
      pretty: formatPretty(mods, key, description),
      type: "bind" + flags,
    };

    if (submap) {
      if (!submaps.has(submap)) submaps.set(submap, { binds: [], label: submap, activator: null });
      submaps.get(submap)!.binds.push(entry);
    } else {
      globalBinds.push(entry);
    }
  }

  // Match pending activators (from __lua dispatcher) to known submap names.
  // Strategy: exact → contains → leftover 1:1 assignment.
  const submapNames = [...submaps.keys()];
  const unmatchedActivators: typeof pendingActivators = [];
  for (const pa of pendingActivators) {
    const descLower = pa.description.toLowerCase().replace(/\s*submap$/, "").trim();
    let match = submapNames.find((n) => n.toLowerCase() === descLower);
    if (!match) match = submapNames.find((n) => descLower.includes(n.toLowerCase()));
    if (match && !submapActivators.has(match)) {
      submapActivators.set(match, { mods: pa.mods, key: pa.key });
    } else if (!match) {
      unmatchedActivators.push(pa);
    }
  }
  // Assign leftover activators to submaps that have no activator yet (1:1)
  const unmatchedSubmaps = submapNames.filter((n) => !submapActivators.has(n));
  for (let i = 0; i < Math.min(unmatchedActivators.length, unmatchedSubmaps.length); i++) {
    submapActivators.set(unmatchedSubmaps[i], { mods: unmatchedActivators[i].mods, key: unmatchedActivators[i].key });
  }

  const submapsList: Submap[] = [];
  for (const [name, sm] of submaps) {
    const entry: Submap = { name, label: sm.label, binds: sm.binds };
    const activator = submapActivators.get(name);
    if (activator) entry.activator = activator;
    submapsList.push(entry);
  }

  return { global: globalBinds, submaps: submapsList };
}

function loadBinds(): { global: BindEntry[]; submaps: Submap[] } {
  const proc = Bun.spawnSync(["hyprctl", "binds", "-j"], { timeout: 2000 });
  return build(JSON.parse(proc.stdout.toString()));
}

export function create(): DaemonModule {
  let cached: { global: BindEntry[]; submaps: Submap[] } | null = null;

  return {
    name: "keybinds",

    init(_ctx: DaemonContext) {
      try {
        cached = loadBinds();
      } catch {}
    },

    routes: {
      list: (_req: Request) => {
        if (!cached) {
          try {
            cached = loadBinds();
          } catch (e) {
            return Response.json({ error: String(e) }, { status: 500 });
          }
        }
        return Response.json(cached);
      },

      reload: (_req: Request) => {
        try {
          cached = loadBinds();
          return Response.json({ ok: true });
        } catch (e) {
          return Response.json({ error: String(e) }, { status: 500 });
        }
      },
    },
  };
}
