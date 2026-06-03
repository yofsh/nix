import { readFileSync, readdirSync } from "fs";
import type { DaemonModule, DaemonContext } from "../types.ts";
import { run, closeControllers, nowSec } from "../util.ts";

function listIfaces(): string[] {
  try {
    return readdirSync("/sys/class/net").sort();
  } catch {
    return [];
  }
}

function findWiface(): string {
  for (const n of listIfaces()) {
    if (n.startsWith("wl")) return n;
  }
  return "";
}

function findEiface(): string {
  const prefixes = ["eth", "enp", "eno", "ens"];
  for (const n of listIfaces()) {
    if (prefixes.some((p) => n.startsWith(p)) && !n.startsWith("enp0s")) {
      return n;
    }
  }
  // fallback: include enp0s* too
  for (const n of listIfaces()) {
    if (prefixes.some((p) => n.startsWith(p))) return n;
  }
  return "";
}

function readIfaceFile(iface: string, name: string): string {
  try {
    return readFileSync(`/sys/class/net/${iface}/${name}`, "utf-8").trim();
  } catch {
    return "";
  }
}

function ipv4For(iface: string): string {
  const out = run(["ip", "-4", "-o", "addr", "show", "dev", iface]);
  const m = out.match(/inet (\d+\.\d+\.\d+\.\d+)/);
  return m ? m[1] : "";
}

// ---------------------------------------------------------------------------
// search helper (mirrors the Python search() utility)
// ---------------------------------------------------------------------------

function search(
  pattern: string | RegExp,
  src: string,
  group = 1,
): string | null {
  const re = typeof pattern === "string" ? new RegExp(pattern) : pattern;
  const m = re.exec(src);
  if (!m) return null;
  return m[group] ?? null;
}

function searchInt(pattern: string | RegExp, src: string, group = 1): number | null {
  const v = search(pattern, src, group);
  if (v === null) return null;
  const n = parseInt(v, 10);
  return isNaN(n) ? null : n;
}

function searchFloat(pattern: string | RegExp, src: string, group = 1): number | null {
  const v = search(pattern, src, group);
  if (v === null) return null;
  const n = parseFloat(v);
  return isNaN(n) ? null : n;
}

// ---------------------------------------------------------------------------
// WiFi
// ---------------------------------------------------------------------------

interface WifiStatus {
  connected: boolean;
  iface: string;
  ssid?: string;
  bssid?: string;
  freq?: number;
  signal_dbm?: number | null;
  rx_bytes?: number;
  tx_bytes?: number;
  rx_rate?: number;
  tx_rate?: number;
  tx_mbps?: number;
  rx_mbps?: number;
  tx_mod?: string;
  rx_mod?: string;
  channel?: string;
  width?: string;
  txpower?: string;
  signal_avg_dbm?: number | null;
  tx_retries?: number;
  tx_packets?: number;
  tx_failed?: number;
  beacon_loss?: number;
  connected_time?: number;
  gen?: string;
  band?: string;
  mlo?: boolean;
  ip?: string;
  dns?: string[];
}

function parseWifi(iface: string): WifiStatus | null {
  if (!iface) return null;

  const link = run(["iw", "dev", iface, "link"]);
  if (!link.trim() || link.includes("Not connected")) {
    return { connected: false, iface };
  }

  const station = run(["iw", "dev", iface, "station", "dump"]);
  const info = run(["iw", "dev", iface, "info"]);

  const out: WifiStatus = {
    connected: true,
    iface,
    ssid: search(/SSID: (.+)/, link) || "",
    bssid: search(/Connected to ([0-9a-f:]{17})/, link) || "",
    freq: searchFloat(/freq: ([\d.]+)/, link) || 0.0,
    signal_dbm: searchInt(/signal: (-?\d+)/, link),
    rx_bytes: searchInt(/RX: (\d+) bytes/, link) || 0,
    tx_bytes: searchInt(/TX: (\d+) bytes/, link) || 0,
    tx_mbps: 0.0,
    rx_mbps: 0.0,
    tx_mod: "",
    rx_mod: "",
    channel: "",
    width: "",
    txpower: "",
    signal_avg_dbm: searchInt(/signal avg:\s*(-?\d+)/, station),
    tx_retries: searchInt(/tx retries:\s*(\d+)/, station) || 0,
    tx_packets: searchInt(/tx packets:\s*(\d+)/, station) || 0,
    tx_failed: searchInt(/tx failed:\s*(\d+)/, station) || 0,
    beacon_loss: searchInt(/beacon loss:\s*(\d+)/, station) || 0,
    connected_time: searchInt(/connected time:\s*(\d+)/, station) || 0,
  };

  // tx bitrate
  const txm = link.match(/tx bitrate: ([\d.]+) (M|G)Bit\/s\s*(.*)/i);
  if (txm) {
    out.tx_mbps =
      parseFloat(txm[1]) * (txm[2].toLowerCase() === "g" ? 1000.0 : 1.0);
    out.tx_mod = txm[3].trim();
  }

  // rx bitrate
  const rxm = link.match(/rx bitrate: ([\d.]+) (M|G)Bit\/s\s*(.*)/i);
  if (rxm) {
    out.rx_mbps =
      parseFloat(rxm[1]) * (rxm[2].toLowerCase() === "g" ? 1000.0 : 1.0);
    out.rx_mod = rxm[3].trim();
  }

  // channel & width from iw info
  const chm = info.match(/channel (\d+) \([\d.]+ MHz\), width: (\d+ MHz)/);
  if (chm) {
    out.channel = chm[1];
    out.width = chm[2];
  }

  const txpow = info.match(/txpower ([\d.]+) dBm/);
  if (txpow) {
    out.txpower = txpow[1];
  }

  // Wi-Fi generation hint
  const txMod = out.tx_mod!;
  const freq = out.freq!;
  if (txMod.includes("EHT")) {
    out.gen = "7";
  } else if (txMod.includes("HE")) {
    out.gen = freq >= 5925 ? "6E" : "6";
  } else if (txMod.includes("VHT")) {
    out.gen = "5";
  } else if (txMod.includes("MCS")) {
    out.gen = "4";
  } else {
    out.gen = "?";
  }

  out.band = bandLabel(freq);
  out.mlo = /^MLD |Link \d+ BSSID/m.test(link);

  out.ip = ipv4For(iface);
  return out;
}

// ---------------------------------------------------------------------------
// Ethernet
// ---------------------------------------------------------------------------

interface EthernetStatus {
  connected: boolean;
  iface: string;
  operstate: string;
  speed_mbps: number;
  duplex: string;
  mac: string;
  ip: string;
  rx_bytes: number;
  tx_bytes: number;
  rx_rate?: number;
  tx_rate?: number;
  dns?: string[];
}

function parseEthernet(iface: string): EthernetStatus | null {
  if (!iface) return null;

  const op = readIfaceFile(iface, "operstate");
  const speedRaw = readIfaceFile(iface, "speed");
  const duplex = readIfaceFile(iface, "duplex");
  const mac = readIfaceFile(iface, "address");
  const rx = readIfaceFile(iface, "statistics/rx_bytes");
  const tx = readIfaceFile(iface, "statistics/tx_bytes");

  const speed = parseInt(speedRaw, 10);

  return {
    connected: op === "up",
    iface,
    operstate: op,
    speed_mbps: isNaN(speed) ? 0 : speed,
    duplex,
    mac,
    ip: ipv4For(iface),
    rx_bytes: /^\d+$/.test(rx) ? parseInt(rx, 10) : 0,
    tx_bytes: /^\d+$/.test(tx) ? parseInt(tx, 10) : 0,
  };
}

// ---------------------------------------------------------------------------
// Gateway
// ---------------------------------------------------------------------------

interface GatewayStatus {
  gateway: string;
  dev: string;
  src: string;
}

function parseGateway(): GatewayStatus {
  const out = run(["ip", "route", "get", "1.1.1.1"]);
  const gw = out.match(/via (\S+)/);
  const dev = out.match(/dev (\S+)/);
  const src = out.match(/src (\S+)/);
  return {
    gateway: gw ? gw[1] : "",
    dev: dev ? dev[1] : "",
    src: src ? src[1] : "",
  };
}

// ---------------------------------------------------------------------------
// DNS
// ---------------------------------------------------------------------------

type ResolvectlMap = Record<string, string[]>;

function parseResolvectlDns(): ResolvectlMap {
  const raw = run(["resolvectl", "dns"], 1000);
  if (!raw) return {};
  const out: ResolvectlMap = {};
  for (const line of raw.split("\n")) {
    const m = line.match(/^\s*Link\s+\d+\s+\(([^)]+)\):\s*(.*)$/);
    if (m) {
      out[m[1]] = m[2].trim().split(/\s+/).filter(Boolean);
    } else if (line.startsWith("Global:")) {
      const servers = line.split(":")[1].trim().split(/\s+/).filter(Boolean);
      if (servers.length) out["__global__"] = servers;
    }
  }
  return out;
}

function parseNmcliDns(iface: string): string[] {
  const raw = run(["nmcli", "-g", "IP4.DNS", "device", "show", iface], 1000);
  return raw
    .replace(/\|/g, " ")
    .split(/\s+/)
    .filter(Boolean);
}

function parseResolvConf(): string[] {
  const servers: string[] = [];
  try {
    const text = readFileSync("/etc/resolv.conf", "utf-8");
    for (const line of text.split("\n")) {
      const m = line.match(/^\s*nameserver\s+(\S+)/);
      if (m) servers.push(m[1]);
    }
  } catch {
    // ignore
  }
  return servers;
}

function dnsFor(iface: string, resolvectlMap: ResolvectlMap): string[] {
  if (!iface) return [];
  if (resolvectlMap[iface]?.length) {
    return resolvectlMap[iface].slice(0, 4);
  }
  const nm = parseNmcliDns(iface);
  if (nm.length) return nm.slice(0, 4);
  return [];
}

// ---------------------------------------------------------------------------
// Tailscale
// ---------------------------------------------------------------------------

interface TailscaleStatus {
  installed: boolean;
  state?: string;
  running?: boolean;
  hostname?: string;
  dns_name?: string;
  ips?: string[];
  exit_node?: string;
  peer_total?: number;
  peer_online?: number;
  health?: string[];
  magic_dns?: string;
}

function parseTailscale(): TailscaleStatus {
  const raw = run(["tailscale", "status", "--json"], 2000);
  if (!raw.trim()) return { installed: false };

  let data: any;
  try {
    data = JSON.parse(raw);
  } catch {
    return { installed: true, state: "error" };
  }

  const state: string = data.BackendState ?? "Unknown";
  const selfNode = data.Self ?? {};
  const ips: string[] = data.TailscaleIPs ?? selfNode.TailscaleIPs ?? [];

  const peers: Record<string, any> = data.Peer ?? {};
  const peerTotal = Object.keys(peers).length;
  let peerOnline = 0;
  let exitNode = "";
  for (const p of Object.values(peers)) {
    if ((p as any).Online) peerOnline++;
    if ((p as any).ExitNode) {
      exitNode = (p as any).HostName || (p as any).DNSName || "";
    }
  }

  const health: string[] = data.Health ?? [];

  return {
    installed: true,
    state,
    running: state === "Running",
    hostname: selfNode.HostName ?? "",
    dns_name: (selfNode.DNSName ?? "").replace(/\.$/, ""),
    ips,
    exit_node: exitNode,
    peer_total: peerTotal,
    peer_online: peerOnline,
    health,
    magic_dns: data.MagicDNSSuffix ?? "",
  };
}

// ---------------------------------------------------------------------------
// Collect all status
// ---------------------------------------------------------------------------

interface NetStatus {
  ts: number;
  gateway: GatewayStatus;
  dns: string[];
  wifi: WifiStatus | null;
  ethernet: EthernetStatus | null;
  tailscale: TailscaleStatus;
  wifi_enabled: boolean;
}

function checkWifiRadio(): boolean {
  return run(["nmcli", "radio", "wifi"]).trim() === "enabled";
}

interface WifiScanNetwork extends ScannedAP {
  group_first: boolean;
  ssid_count: number;
  known: boolean;
}

function getWifiGen(caps: Set<string>, freq: number): string {
  if (caps.has("EHT")) return "7";
  if (caps.has("HE")) return freq >= 5925 ? "6E" : "6";
  if (caps.has("VHT")) return "5";
  if (caps.has("HT")) return "4";
  return "?";
}

function dbmToPct(dbm: number): number {
  if (dbm >= -40) return 100;
  if (dbm <= -80) return 0;
  return Math.round((dbm + 80) * 2.5);
}

function bandLabel(freq: number): string {
  if (freq >= 5925) return "6 GHz";
  if (freq >= 5000) return "5 GHz";
  if (freq > 0) return "2.4 GHz";
  return "";
}

type ScannedAP = {
  ssid: string; bssid: string; signal: number; signal_dbm: number;
  security: string; freq: number; channel: string; channel_width: string;
  streams: number; band: string; gen: string; active: boolean;
  wps: boolean; mu_mimo: boolean; twt: boolean; clients: string; util: string;
};

function getChannelWidth(block: string): string {
  const m = block.match(/channel width: \d+ \(([^)]+)\)/);
  if (m) return m[1];
  if (block.includes("HT20/HT40")) return "40 MHz";
  if (block.includes("HT20")) return "20 MHz";
  return "";
}

function getMaxStreams(block: string): number {
  let max = 0;
  for (const m of block.matchAll(/(\d+) streams: MCS/g)) {
    const n = parseInt(m[1], 10);
    if (n > max) max = n;
  }
  return max;
}

function parseIwScan(text: string): ScannedAP[] {
  const blocks = text.split(/(?=BSS [0-9a-f:]{17})/);
  const aps: ScannedAP[] = [];

  for (const block of blocks) {
    if (!block.trim()) continue;

    const bssidM = block.match(/BSS ([0-9a-f:]{17})/);
    if (!bssidM) continue;

    const ssidM = block.match(/SSID: ([^\t\n]+)/);
    const ssid = ssidM ? ssidM[1].trim() : "";
    if (!ssid) continue;

    const freqM = block.match(/freq: ([\d.]+)/);
    const freq = freqM ? parseFloat(freqM[1]) : 0;

    const sigM = block.match(/signal: (-?[\d.]+)/);
    const signal = sigM ? parseFloat(sigM[1]) : -100;

    let security = "Open";
    if (block.includes("RSN:")) security = "WPA2";
    else if (block.includes("WPA:")) security = "WPA";
    if (block.includes("802.1X")) security = "Enterprise";

    const authM = block.match(/Authentication suites: ([^\t\n*]+)/);
    const auth = authM ? authM[1].trim() : "";
    if (auth.includes("PSK") && auth.includes("SAE")) security = "WPA2/3";
    else if (auth.includes("SAE")) security = "WPA3";

    const caps = new Set<string>();
    if (/HT capabilities:|HT operation:/.test(block)) caps.add("HT");
    if (/VHT capabilities:|VHT operation:/.test(block)) caps.add("VHT");
    if (/HE capabilities:|HE Operation:/.test(block)) caps.add("HE");
    if (/EHT capabilities:|EHT Operation:/.test(block)) caps.add("EHT");

    const chM = block.match(/primary channel: (\d+)/);
    const clientsM = block.match(/station count: (\d+)/);
    const utilM = block.match(/channel utilisation: (\d+\/\d+)/);

    aps.push({
      ssid,
      bssid: bssidM[1],
      signal: dbmToPct(signal),
      signal_dbm: signal,
      security,
      freq,
      channel: chM ? chM[1] : "",
      channel_width: getChannelWidth(block),
      streams: getMaxStreams(block),
      band: bandLabel(freq),
      gen: getWifiGen(caps, freq),
      active: block.includes("-- associated"),
      wps: block.includes("WPS:") || block.includes("Wi-Fi Protected Setup"),
      mu_mimo: block.includes("MU Beamformer"),
      twt: block.includes("TWT Responder"),
      clients: clientsM ? clientsM[1] : "",
      util: utilM ? utilM[1] : "",
    });
  }
  return aps;
}

function savedWifiSSIDs(): Set<string> {
  const raw = run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"], 1000);
  const ssids = new Set<string>();
  for (const line of raw.split("\n")) {
    const parts = line.split(":");
    if (parts.length >= 2 && parts[parts.length - 1].trim() === "802-11-wireless") {
      ssids.add(parts.slice(0, -1).join(":"));
    }
  }
  return ssids;
}

function listWifiNetworks(rescan: boolean): WifiScanNetwork[] {
  const wiface = findWiface();
  if (!wiface) return [];
  if (rescan) {
    run(["nmcli", "device", "wifi", "rescan"], 5000);
    Bun.sleepSync(2000);
  }
  const raw = run(["iw", "dev", wiface, "scan", "dump"], 5000);
  const aps = raw.trim() ? parseIwScan(raw) : [];

  const knownSSIDs = savedWifiSSIDs();

  // Count APs per SSID
  const counts: Record<string, number> = {};
  for (const ap of aps) counts[ap.ssid] = (counts[ap.ssid] || 0) + 1;

  // Best signal per SSID group (for group ordering)
  const bestSignal: Record<string, number> = {};
  const hasActive: Record<string, boolean> = {};
  for (const ap of aps) {
    bestSignal[ap.ssid] = Math.max(bestSignal[ap.ssid] ?? -999, ap.signal);
    if (ap.active) hasActive[ap.ssid] = true;
  }

  // Sort: active groups first, then groups by best signal, then APs within group by signal
  aps.sort((a, b) => {
    const aAct = hasActive[a.ssid] ? 1 : 0;
    const bAct = hasActive[b.ssid] ? 1 : 0;
    if (aAct !== bAct) return bAct - aAct;
    const aBest = bestSignal[a.ssid] ?? -999;
    const bBest = bestSignal[b.ssid] ?? -999;
    if (aBest !== bBest) return bBest - aBest;
    if (a.ssid !== b.ssid) return a.ssid.toLowerCase() < b.ssid.toLowerCase() ? -1 : 1;
    return b.signal - a.signal;
  });

  const seen = new Set<string>();
  return aps.map((ap) => ({
    ...ap,
    group_first: !seen.has(ap.ssid) && (seen.add(ap.ssid), true),
    ssid_count: counts[ap.ssid] || 1,
    known: knownSSIDs.has(ap.ssid),
  }));
}

function collectStatus(): NetStatus {
  const wiface = findWiface();
  const eiface = findEiface();
  const resolvectl = parseResolvectlDns();

  const wifi = wiface ? parseWifi(wiface) : null;
  if (wifi) wifi.dns = dnsFor(wiface, resolvectl);

  const ethernet = eiface ? parseEthernet(eiface) : null;
  if (ethernet) ethernet.dns = dnsFor(eiface, resolvectl);

  const gateway = parseGateway();

  // Effective system DNS = whichever DNS the default-route iface uses.
  // Falls back to resolvectl global or /etc/resolv.conf as last resort.
  let sysDns = dnsFor(gateway.dev, resolvectl);
  if (!sysDns.length) {
    sysDns = (resolvectl["__global__"] ?? []).slice(0, 4);
  }
  if (!sysDns.length) {
    sysDns = parseResolvConf().slice(0, 4);
  }

  return {
    ts: nowSec(),
    gateway,
    dns: sysDns,
    wifi,
    ethernet,
    tailscale: parseTailscale(),
    wifi_enabled: checkWifiRadio(),
  };
}

export function create(): DaemonModule {
  let cached: NetStatus | null = null;
  let timer: ReturnType<typeof setInterval> | null = null;
  const streamControllers = new Set<ReadableStreamDefaultController<Uint8Array>>();
  const encoder = new TextEncoder();

  const prevBytes: Record<string, { rx: number; tx: number; ts: number }> = {};
  const trafficHistory: Array<{ rx: number; tx: number }> = [];
  const MAX_TRAFFIC_HISTORY = 600; // 5 minutes at 2Hz

  function attachRates(
    entry: { iface: string; connected: boolean; rx_rate?: number; tx_rate?: number } | null,
    now: number,
  ) {
    if (!entry?.connected || !entry.iface) return;
    const rx = parseInt(readIfaceFile(entry.iface, "statistics/rx_bytes"), 10) || 0;
    const tx = parseInt(readIfaceFile(entry.iface, "statistics/tx_bytes"), 10) || 0;
    const prev = prevBytes[entry.iface];
    if (prev && prev.ts > 0) {
      const dt = now - prev.ts;
      if (dt > 0.1) {
        entry.rx_rate = Math.max(0, (rx - prev.rx) / dt);
        entry.tx_rate = Math.max(0, (tx - prev.tx) / dt);
      }
    }
    prevBytes[entry.iface] = { rx, tx, ts: now };
  }

  function tick() {
    try {
      cached = collectStatus();
      attachRates(cached.wifi, cached.ts);
      attachRates(cached.ethernet, cached.ts);
      const rxR = (cached.wifi?.rx_rate || 0) + (cached.ethernet?.rx_rate || 0);
      const txR = (cached.wifi?.tx_rate || 0) + (cached.ethernet?.tx_rate || 0);
      trafficHistory.push({ rx: rxR, tx: txR });
      if (trafficHistory.length > MAX_TRAFFIC_HISTORY) trafficHistory.shift();
    } catch (e) {
      cached = {
        ts: nowSec(),
        gateway: { gateway: "", dev: "", src: "" },
        dns: [],
        wifi: null,
        ethernet: null,
        tailscale: { installed: false },
      } as any;
      (cached as any).error = String(e);
    }
    const line = encoder.encode(JSON.stringify(cached) + "\n");
    for (const ctrl of streamControllers) {
      try {
        ctrl.enqueue(line);
      } catch {
        streamControllers.delete(ctrl);
      }
    }
  }

  return {
    name: "net",

    init(ctx: DaemonContext) {
      tick();
      timer = setInterval(tick, 500);
      ctx.signal.addEventListener("abort", () => {
        if (timer) {
          clearInterval(timer);
          timer = null;
        }
        closeControllers(streamControllers);
      });
    },

    routes: {
      status: (_req: Request) => {
        if (!cached) {
          return Response.json(
            { error: "not ready", ts: nowSec() },
            { status: 503 },
          );
        }
        return Response.json({ ...cached, traffic_history: trafficHistory });
      },

      "wifi-list": async () => {
        try {
          const networks = listWifiNetworks(false);
          return Response.json({ networks, count: networks.length });
        } catch (e) {
          return Response.json({ error: String(e), networks: [], count: 0 }, { status: 500 });
        }
      },

      "wifi-scan": async () => {
        try {
          const networks = listWifiNetworks(true);
          return Response.json({ networks, count: networks.length });
        } catch (e) {
          return Response.json({ error: String(e), networks: [], count: 0 }, { status: 500 });
        }
      },

      "wifi-toggle": async () => {
        const enabled = checkWifiRadio();
        run(["nmcli", "radio", "wifi", enabled ? "off" : "on"], 3000);
        return Response.json({ enabled: !enabled });
      },

      "wifi-connect": async (req: Request) => {
        let body: { ssid: string; bssid?: string; password?: string; known?: boolean };
        try {
          body = await req.json();
        } catch {
          return Response.json({ error: "invalid JSON body" }, { status: 400 });
        }
        if (!body.ssid) {
          return Response.json({ error: "ssid required" }, { status: 400 });
        }
        if (body.known) {
          const proc = Bun.spawnSync(["nmcli", "--wait", "0", "connection", "up", body.ssid], { timeout: 5000 });
          const exitOk = proc.exitCode === 0;
          const msg = proc.stdout.toString().trim() || (exitOk ? "Activating…" : proc.stderr.toString().trim());
          return Response.json({ success: exitOk, message: msg });
        }
        const cmd = ["nmcli", "--wait", "0", "device", "wifi", "connect", body.ssid];
        if (body.bssid) {
          run(["nmcli", "device", "wifi", "rescan"], 5000);
          Bun.sleepSync(2000);
          cmd.push("bssid", body.bssid);
        }
        if (body.password) cmd.push("password", body.password);
        const proc = Bun.spawnSync(cmd, { timeout: 10000 });
        const exitOk = proc.exitCode === 0;
        const msg = proc.stdout.toString().trim() || (exitOk ? "Activating…" : proc.stderr.toString().trim());
        return Response.json({ success: exitOk, message: msg });
      },

      "tailscale-toggle": async () => {
        const ts = parseTailscale();
        if (!ts.installed) {
          return Response.json({ error: "tailscale not installed" }, { status: 404 });
        }
        if (ts.running) {
          run(["tailscale", "down"], 5000);
        } else {
          run(["tailscale", "up"], 10000);
        }
        return Response.json({ was_running: ts.running, running: !ts.running });
      },

      stream: (req: Request) => {
        const stream = new ReadableStream<Uint8Array>({
          start(controller) {
            streamControllers.add(controller);
            // Send current state + full traffic history on connect
            if (cached) {
              const initial = { ...cached, traffic_history: trafficHistory };
              controller.enqueue(
                encoder.encode(JSON.stringify(initial) + "\n"),
              );
            }
            req.signal.addEventListener("abort", () => {
              streamControllers.delete(controller);
              try {
                controller.close();
              } catch {}
            });
          },
          cancel() {},
        });

        return new Response(stream, {
          headers: {
            "Content-Type": "application/x-ndjson",
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
          },
        });
      },
    },

    shutdown() {
      if (timer) {
        clearInterval(timer);
        timer = null;
      }
      closeControllers(streamControllers);
    },
  };
}
