import { Subprocess } from "bun";
import type { DaemonModule, DaemonContext } from "../types.ts";
import { run } from "../util.ts";

interface BtDevice {
  mac: string;
  name: string;
  paired: boolean;
  connected: boolean;
  icon: string;
  battery: number | null;
}

interface BtController {
  powered: boolean;
  discoverable: boolean;
  pairable: boolean;
  discovering: boolean;
  name: string;
  address: string;
}

function parseController(): BtController | null {
  const raw = run(["bluetoothctl", "show"], 3000);
  if (!raw) return null;
  return {
    powered: /Powered: yes/i.test(raw),
    discoverable: /Discoverable: yes/i.test(raw),
    pairable: /Pairable: yes/i.test(raw),
    // Use our own tracking — KernelExperimental AdvMonitor makes
    // the adapter report Discovering=yes permanently (passive scan).
    discovering: scanActive,
    name: raw.match(/Alias: (.+)/)?.[1] || raw.match(/Name: (.+)/)?.[1] || "",
    address: raw.match(/Controller ([0-9A-F:]+)/)?.[1] || "",
  };
}

function parseDevices(): BtDevice[] {
  const allRaw = run(["bluetoothctl", "devices"], 3000);
  const pairedRaw = run(["bluetoothctl", "devices", "Paired"], 3000);
  const connectedRaw = run(["bluetoothctl", "devices", "Connected"], 3000);

  const pairedMacs = new Set(
    pairedRaw.split("\n").map((l) => l.match(/Device ([0-9A-F:]+)/)?.[1]).filter(Boolean),
  );
  const connectedMacs = new Set(
    connectedRaw.split("\n").map((l) => l.match(/Device ([0-9A-F:]+)/)?.[1]).filter(Boolean),
  );

  const devices: BtDevice[] = [];
  for (const line of allRaw.split("\n")) {
    const m = line.match(/Device ([0-9A-F:]+) (.+)/);
    if (!m) continue;
    const mac = m[1];
    const name = m[2];

    const info = run(["bluetoothctl", "info", mac]);
    const icon = info.match(/Icon: (.+)/)?.[1] || "device";
    const batteryMatch = info.match(/Battery Percentage:.*\((\d+)\)/);
    const battery = batteryMatch ? parseInt(batteryMatch[1]) : null;

    devices.push({
      mac,
      name,
      paired: pairedMacs.has(mac),
      connected: connectedMacs.has(mac),
      icon,
      battery,
    });
  }

  devices.sort((a, b) => {
    if (a.connected !== b.connected) return a.connected ? -1 : 1;
    if (a.paired !== b.paired) return a.paired ? -1 : 1;
    return a.name.localeCompare(b.name);
  });

  return devices;
}

// Persistent bluetoothctl session for scan management.
// BlueZ ties discovery to the D-Bus client connection, so we keep one alive.
// We track scan state ourselves to avoid stacking multiple discovery sessions.
let btctl: Subprocess<"pipe", "pipe", "pipe"> | null = null;
let scanActive = false;

function ensureBtctl(): Subprocess<"pipe", "pipe", "pipe"> {
  if (btctl && btctl.exitCode === null) return btctl;
  scanActive = false;
  btctl = Bun.spawn(["bluetoothctl"], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });
  return btctl;
}

function sendBtctl(cmd: string): void {
  const p = ensureBtctl();
  p.stdin.write(cmd + "\n");
}

async function killBtctl(): Promise<void> {
  if (btctl) {
    const p = btctl;
    btctl = null;
    scanActive = false;
    try { p.kill(); } catch {}
    try { await p.exited; } catch {}
  }
}

async function macAction(
  req: Request,
  verb: string,
  timeout: number,
  okRe: RegExp,
  okMsg: string,
): Promise<Response> {
  try {
    const { mac } = (await req.json()) as { mac: string };
    const out = run(["bluetoothctl", verb, mac], timeout);
    const ok = okRe.test(out);
    return Response.json({
      success: ok,
      message: ok ? okMsg : out.trim().split("\n").pop() || "Failed",
    });
  } catch (e: any) {
    return Response.json({ success: false, message: e.message || "error" });
  }
}

export function create(): DaemonModule {
  return {
    name: "bt",

    init(_ctx: DaemonContext) {},

    async shutdown() {
      await killBtctl();
    },

    routes: {
      status: async (): Promise<Response> => {
        const controller = parseController();
        const devices = controller?.powered ? parseDevices() : [];
        return Response.json({ controller, devices });
      },

      "toggle-scan": async (): Promise<Response> => {
        if (scanActive) {
          sendBtctl("scan off");
          scanActive = false;
        } else {
          sendBtctl("scan on");
          scanActive = true;
        }
        await new Promise((r) => setTimeout(r, 300));
        return Response.json({ success: true, discovering: scanActive });
      },

      connect: (req: Request) => macAction(req, "connect", 8000, /Connection successful/i, "Connected"),
      disconnect: (req: Request) => macAction(req, "disconnect", 5000, /Successful disconnected/i, "Disconnected"),
      pair: (req: Request) => macAction(req, "pair", 10000, /Pairing successful/i, "Paired"),
      remove: (req: Request) => macAction(req, "remove", 5000, /removed/i, "Removed"),

      "toggle-power": async (): Promise<Response> => {
        const ctrl = parseController();
        const cmd = ctrl?.powered ? "off" : "on";
        run(["bluetoothctl", "power", cmd], 3000);
        return Response.json({ success: true, powered: cmd === "on" });
      },

      "toggle-discoverable": async (): Promise<Response> => {
        const ctrl = parseController();
        const cmd = ctrl?.discoverable ? "off" : "on";
        run(["bluetoothctl", "discoverable", cmd], 3000);
        if (cmd === "on") run(["bluetoothctl", "pairable", "on"], 1000);
        return Response.json({ success: true, discoverable: cmd === "on" });
      },
    },
  };
}
