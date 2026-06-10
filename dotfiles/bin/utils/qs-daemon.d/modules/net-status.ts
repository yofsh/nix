import { readFileSync, readdirSync } from "fs";
import { networkInterfaces } from "os";
import type { DaemonModule, DaemonContext } from "../types.ts";
import { run, closeControllers, nowSec } from "../util.ts";

// ─── net-status ───────────────────────────────────────────────────────────────
// Single source of truth for network status, consumed by the bar widget AND the
// popup over one always-on `net/stream`. The bar widget is a PURE CONSUMER — it
// does no spawning of its own; everything it shows comes from this stream.
//
// Two tiers, by cost:
//   • FAST tick (2 Hz, /net/stream) is SPAWN-FREE. Every field it computes comes
//     from sysfs/procfs or libuv getifaddrs — no subprocesses:
//       signal  → /proc/net/wireless          up/down/speed → /sys/class/net/<if>/…
//       rx/tx   → …/statistics/{rx,tx}_bytes   ipv4 → os.networkInterfaces()
//       gateway → /proc/net/route             dns  → /run/systemd/resolve/resolv.conf
//       wifi radio → /sys/class/rfkill/*
//   • The Wi-Fi connection state shown in the bar (connected/connecting/
//     disconnected) is ALSO spawn-free: derived from operstate + carrier. It is
//     coarse (no NetworkManager substates) on purpose — that keeps nmcli OUT of
//     the always-on path entirely.
//   • SLOW detail (SSID, Wi-Fi gen/band/bitrate/MLO, channel, station stats) is
//     for the POPUP only and needs `iw` (NOT nmcli). It is not polled per tick:
//     the spawn-free tick watches the Wi-Fi operstate and, on a change (a sysfs
//     "edge"), refreshes the `iw` detail once; a slow SLOW_MS poll is the safety
//     net. The fast tick merges the cache; spawns happen only on real change.
//
// Spawning per-tick (the old design: ~8 spawns × 2 Hz) is what we deliberately
// avoid here — see dotfiles/quickshell/CLAUDE.md "Daemon is the single source".
// nmcli appears ONLY in the user-driven routes below (wifi-list/scan/connect/
// toggle); those may spawn freely since they're on-demand and transient.
// ───────────────────────────────────────────────────────────────────────────────

const SLOW_MS = 5000; // safety re-poll for wifi detail + tailscale (events do the rest)

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

// ─── spawn-free primitives (sysfs / procfs / getifaddrs) ──────────────────────

// IPv4 address of an interface via libuv getifaddrs — no `ip` subprocess.
function ipv4For(iface: string): string {
  if (!iface) return "";
  const addrs = networkInterfaces()[iface] || [];
  for (const a of addrs) {
    if ((a.family === "IPv4" || (a as any).family === 4) && !a.internal) return a.address;
  }
  return "";
}

// Wi-Fi signal in dBm from /proc/net/wireless (only lists associated ifaces).
function wifiSignalDbm(iface: string): number | null {
  try {
    const t = readFileSync("/proc/net/wireless", "utf-8");
    for (const line of t.split("\n")) {
      const c = line.indexOf(":");
      if (c < 0) continue;
      if (line.slice(0, c).trim() !== iface) continue;
      // cols after "iface:": status  link  level  noise  …  (values carry a "." suffix)
      const cols = line.slice(c + 1).trim().split(/\s+/);
      const level = parseFloat(cols[2]);
      return isNaN(level) ? null : Math.round(level);
    }
  } catch {}
  return null;
}

// Default gateway + dev from /proc/net/route (hex, little-endian) — no `ip route`.
function hexLeToIp(hex: string): string {
  if (hex.length !== 8) return "";
  const o: number[] = [];
  for (let i = 0; i < 4; i++) o.push(parseInt(hex.slice(i * 2, i * 2 + 2), 16));
  return o.reverse().join(".");
}

function parseGateway(): GatewayStatus {
  let raw: string;
  try { raw = readFileSync("/proc/net/route", "utf-8"); } catch { return { gateway: "", dev: "", src: "" }; }
  let best: { gw: string; dev: string; metric: number } | null = null;
  const lines = raw.split("\n");
  for (let i = 1; i < lines.length; i++) {
    const f = lines[i].trim().split(/\s+/);
    if (f.length < 11) continue;
    if (f[1] !== "00000000") continue;            // default route only
    if (!(parseInt(f[3], 16) & 0x2)) continue;    // RTF_GATEWAY
    const metric = parseInt(f[6], 10) || 0;
    if (!best || metric < best.metric) best = { gw: hexLeToIp(f[2]), dev: f[0], metric };
  }
  if (!best) return { gateway: "", dev: "", src: "" };
  return { gateway: best.gw, dev: best.dev, src: ipv4For(best.dev) };
}

// Effective upstream DNS from systemd-resolved's real resolv.conf (falls back to
// /etc/resolv.conf). The 127.0.0.53 stub is skipped so we surface real servers.
function dnsCheap(): string[] {
  for (const p of ["/run/systemd/resolve/resolv.conf", "/etc/resolv.conf"]) {
    try {
      const out: string[] = [];
      for (const line of readFileSync(p, "utf-8").split("\n")) {
        const m = line.match(/^\s*nameserver\s+(\S+)/);
        if (m && m[1] !== "127.0.0.53") out.push(m[1]);
      }
      if (out.length) return out.slice(0, 4);
    } catch {}
  }
  return [];
}

// Wi-Fi radio soft/hard-block state from rfkill — no `nmcli radio`.
function checkWifiRadio(): boolean {
  try {
    for (const d of readdirSync("/sys/class/rfkill")) {
      const base = `/sys/class/rfkill/${d}`;
      let type = "";
      try { type = readFileSync(`${base}/type`, "utf-8").trim(); } catch {}
      if (type !== "wlan") continue;
      const soft = readFileSync(`${base}/soft`, "utf-8").trim();
      const hard = readFileSync(`${base}/hard`, "utf-8").trim();
      return soft === "0" && hard === "0";
    }
  } catch {}
  return true; // assume enabled when rfkill is unreadable
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
  status?: string;          // coarse sysfs state: connected | connecting | disconnected
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

// SLOW path: the expensive `iw`-derived Wi-Fi detail. Returns {} when not
// associated. Signal/IP/byte-counters are intentionally NOT here — those are
// cheap and read fresh each tick by buildWifi().
function fetchWifiDetail(iface: string): Partial<WifiStatus> {
  if (!iface) return {};
  const link = run(["iw", "dev", iface, "link"]);
  if (!link.trim() || link.includes("Not connected")) return {};

  const station = run(["iw", "dev", iface, "station", "dump"]);
  const info = run(["iw", "dev", iface, "info"]);

  const out: Partial<WifiStatus> = {
    ssid: search(/SSID: (.+)/, link) || "",
    bssid: search(/Connected to ([0-9a-f:]{17})/, link) || "",
    freq: searchFloat(/freq: ([\d.]+)/, link) || 0.0,
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
  const txMod = out.tx_mod || "";
  const freq = out.freq || 0;
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
  return out;
}

// Coarse Wi-Fi state from sysfs alone — no nmcli. operstate "up" = associated +
// configured; "dormant" or a present carrier without "up" = mid-connect; else
// down. Deliberately omits NetworkManager's fine substates (those need nmcli).
function wifiCoarseStatus(iface: string): string {
  const op = readIfaceFile(iface, "operstate");
  if (op === "up") return "connected";
  if (op === "dormant" || readIfaceFile(iface, "carrier") === "1") return "connecting";
  return "disconnected";
}

// FAST path: spawn-free Wi-Fi status. When connected, merges the cached `iw`
// detail (for the popup) with cheap live fields (signal/ip/bytes). Otherwise
// reports only the coarse sysfs status.
function buildWifi(detail: Partial<WifiStatus>): WifiStatus | null {
  const iface = findWiface();
  if (!iface) return null;
  const status = wifiCoarseStatus(iface);
  if (status === "connected") {
    return {
      ...detail,
      connected: true,
      iface,
      status,
      signal_dbm: wifiSignalDbm(iface),
      ip: ipv4For(iface),
      rx_bytes: parseInt(readIfaceFile(iface, "statistics/rx_bytes"), 10) || 0,
      tx_bytes: parseInt(readIfaceFile(iface, "statistics/tx_bytes"), 10) || 0,
      dns: dnsCheap(),
    };
  }
  return { connected: false, iface, status };
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

// FAST path: fully spawn-free (sysfs + getifaddrs).
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

// SLOW path: refreshed on SLOW_MS / events, not per tick.
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
// Status shape
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

export function create(): DaemonModule {
  let cached: NetStatus | null = null;
  let fastTimer: ReturnType<typeof setInterval> | null = null;
  let slowTimer: ReturnType<typeof setInterval> | null = null;
  let lastWifiOp = ""; // last Wi-Fi operstate, to detect connect/disconnect edges
  const streamControllers = new Set<ReadableStreamDefaultController<Uint8Array>>();
  const encoder = new TextEncoder();

  // Cached popup-only detail (the only fields that cost a subprocess, via `iw`).
  // Refreshed on a Wi-Fi operstate edge + every SLOW_MS, merged by the fast tick.
  let wifiDetail: Partial<WifiStatus> = {};
  let tailscaleCache: TailscaleStatus = { installed: false };

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

  // ── SLOW refreshers (the only `iw`/tailscale spawns, for the popup) ──
  function refreshWifi() {
    const iface = findWiface();
    wifiDetail =
      iface && readIfaceFile(iface, "operstate") === "up"
        ? fetchWifiDetail(iface) // iw link/station/info
        : {};
  }
  function refreshTailscale() {
    tailscaleCache = parseTailscale();
  }

  // ── FAST tick — spawn-free, 2 Hz ──
  function tick() {
    try {
      const ts = nowSec();
      // Watch the Wi-Fi operstate (sysfs); on a connect/disconnect edge, refresh
      // the popup `iw` detail once — this is our event source, no nmcli monitor.
      const wiface = findWiface();
      const op = wiface ? readIfaceFile(wiface, "operstate") : "";
      if (op !== lastWifiOp) {
        lastWifiOp = op;
        refreshWifi();
      }
      const wifi = buildWifi(wifiDetail);
      const eiface = findEiface();
      const ethernet = eiface ? parseEthernet(eiface) : null;
      if (ethernet) ethernet.dns = dnsCheap();
      cached = {
        ts,
        gateway: parseGateway(),
        dns: dnsCheap(),
        wifi,
        ethernet,
        tailscale: tailscaleCache,
        wifi_enabled: checkWifiRadio(),
      };
      attachRates(cached.wifi, ts);
      attachRates(cached.ethernet, ts);
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

  function cleanup() {
    for (const t of [fastTimer, slowTimer]) if (t) clearInterval(t);
    fastTimer = slowTimer = null;
    closeControllers(streamControllers);
  }

  return {
    name: "net",

    init(ctx: DaemonContext) {
      refreshWifi();
      refreshTailscale();
      tick();
      fastTimer = setInterval(tick, 500);
      // Safety re-poll for popup `iw` detail (live bitrate/station stats while
      // connected) + tailscale. The 2 Hz tick's operstate-edge handles connects.
      slowTimer = setInterval(() => { refreshWifi(); refreshTailscale(); }, SLOW_MS);

      ctx.signal.addEventListener("abort", () => cleanup());
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
        refreshTailscale();
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
      cleanup();
    },
  };
}
