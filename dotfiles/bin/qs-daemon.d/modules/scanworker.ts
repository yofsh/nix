// Scanner worker thread — owns the daemon's two expensive jobs and runs them
// OFF the main event loop, in the SAME process (cost is honestly attributed to
// qs-daemon, no fork churn, no main-loop stalls). It returns only small results,
// so there is no large cross-thread transfer:
//   • net: the ENTIRE per-app traffic pipeline — netlink SOCK_DIAG byte counters
//          + a cached inode→pid map (/proc/*/fd) + per-socket deltas + exe
//          grouping + the 60s ring — reduced to the top-N apps.
//   • cam: executables holding a /dev/video* fd.
// See scanner.ts (client) and CLAUDE.md "Daemon is the single source".

import { readdirSync, readlinkSync } from "fs";
import { openSockDiag } from "./sockdiag.ts";
import { exeKey, commOf, procParams, type ProcEntry } from "./procinfo.ts";

declare const self: {
  onmessage: ((e: { data: any }) => void) | null;
  postMessage(d: any): void;
};

// Keep these in step with procmon.ts (independent net window vs its cpu/mem one).
const TICK_MS = 2000;
const NET_WINDOW = 30; // 30 × 2s ≈ 60s sliding window
const TOP_N = 10;
const FD_SCAN_S = 6;   // min seconds between inode→pid /proc/*/fd rescans

interface NetGroup {
  name: string; count: number;
  rx: number; tx: number; total: number; // cumulative bytes over the window
  rxr: number; txr: number;              // current (instant) bytes/sec
  rxa: number; txa: number;              // average bytes/sec over the window
}

const sum = (a: number[]) => { let s = 0; for (const v of a) s += v; return s; };

const sock = openSockDiag();

// ── per-app network traffic state (lives here, never crosses the thread) ──
const inodeToPid = new Map<number, number>();
let lastFdScan = 0;
const prevSockI = new Map<number, { tx: number; rx: number }>();
let prevNetTs = 0;
const netRing = new Map<string, { rx: number[]; tx: number[] }>();

// Rebuild inode→pid from every open socket fd across all processes.
function rebuildInodeMap(): void {
  inodeToPid.clear();
  let pids: string[];
  try { pids = readdirSync("/proc"); } catch { return; }
  for (const name of pids) {
    const c = name.charCodeAt(0);
    if (c < 48 || c > 57) continue;
    const pid = parseInt(name, 10);
    if (!(pid > 0)) continue;
    let fds: string[];
    try { fds = readdirSync(`/proc/${name}/fd`); } catch { continue; }
    for (const fd of fds) {
      try {
        const l = readlinkSync(`/proc/${name}/fd/${fd}`);
        if (l.charCodeAt(0) === 115 && l.startsWith("socket:[")) { // "socket:[12345]"
          const ino = parseInt(l.slice(8, -1), 10);
          if (ino > 0) inodeToPid.set(ino, pid);
        }
      } catch {}
    }
  }
}

function netProcs(): NetGroup[] {
  const now = Date.now() / 1000;
  const dt = prevNetTs > 0 ? now - prevNetTs : 0;
  // Refresh the inode→pid map on a slow cadence; a brand-new connection stays
  // unattributed until then (short bursts may be missed) — fine for "top apps
  // over ~60s" of sustained transfers, and the fd walk is the expensive part.
  if (inodeToPid.size === 0 || now - lastFdScan >= FD_SCAN_S) {
    rebuildInodeMap();
    lastFdScan = now;
  }

  const socks = sock.dump();
  const exeCache = new Map<number, string>();
  const commCache = new Map<number, string>();
  const commFor = (pid: number) => {
    const h = commCache.get(pid);
    if (h !== undefined) return h;
    const c = commOf(pid);
    commCache.set(pid, c);
    return c;
  };
  const tick = new Map<string, { rx: number; tx: number; pids: Set<number> }>();
  const cur = new Set<number>();
  for (const s of socks) {
    cur.add(s.inode);
    const pid = inodeToPid.get(s.inode);
    if (pid === undefined) continue; // unresolved until the next map refresh
    const prev = prevSockI.get(s.inode);
    if (dt > 0 && prev) {
      const dtx = Math.max(0, s.tx - prev.tx);
      const drx = Math.max(0, s.rx - prev.rx);
      if (dtx > 0 || drx > 0) {
        const name = exeKey(pid, () => commFor(pid), exeCache);
        let t = tick.get(name);
        if (!t) { t = { rx: 0, tx: 0, pids: new Set() }; tick.set(name, t); }
        t.rx += drx; t.tx += dtx; t.pids.add(pid);
      }
    }
    prevSockI.set(s.inode, { tx: s.tx, rx: s.rx });
  }
  for (const ino of prevSockI.keys()) if (!cur.has(ino)) prevSockI.delete(ino);
  prevNetTs = now;

  // push this tick's per-app delta (0 when idle) into each ring, so an app stays
  // visible — with a decaying total — for ~60s after its last traffic.
  const keys = new Set<string>([...netRing.keys(), ...tick.keys()]);
  for (const name of keys) {
    const t = tick.get(name);
    let ring = netRing.get(name);
    if (!ring) { ring = { rx: [], tx: [] }; netRing.set(name, ring); }
    ring.rx.push(t ? t.rx : 0);
    ring.tx.push(t ? t.tx : 0);
    if (ring.rx.length > NET_WINDOW) ring.rx.shift();
    if (ring.tx.length > NET_WINDOW) ring.tx.shift();
  }

  const procs: NetGroup[] = [];
  for (const [name, ring] of netRing) {
    const wrx = sum(ring.rx);
    const wtx = sum(ring.tx);
    if (wrx + wtx <= 0) { netRing.delete(name); continue; }
    const t = tick.get(name);
    const winSecs = ring.rx.length * (TICK_MS / 1000);
    procs.push({
      name,
      count: t ? t.pids.size : 0,
      rx: wrx, tx: wtx, total: wrx + wtx,
      rxr: t && dt > 0 ? t.rx / dt : 0,
      txr: t && dt > 0 ? t.tx / dt : 0,
      rxa: winSecs > 0 ? wrx / winSecs : 0,
      txa: winSecs > 0 ? wtx / winSecs : 0,
    });
  }
  procs.sort((a, b) => b.total - a.total);
  return procs.slice(0, TOP_N);
}

// Processes holding a /dev/video* fd (name + pid + params), gated on device
// existence so camera-less machines pay nothing.
function scanCamHolders(): ProcEntry[] {
  let hasVideo = false;
  try {
    for (const d of readdirSync("/dev")) if (d.startsWith("video")) { hasVideo = true; break; }
  } catch {}
  if (!hasVideo) return [];

  const out: ProcEntry[] = [];
  const exeCache = new Map<number, string>();
  let pids: string[];
  try { pids = readdirSync("/proc"); } catch { return []; }
  for (const name of pids) {
    const c = name.charCodeAt(0);
    if (c < 48 || c > 57) continue;
    let fds: string[];
    try { fds = readdirSync(`/proc/${name}/fd`); } catch { continue; }
    for (const fd of fds) {
      let holds = false;
      try { holds = readlinkSync(`/proc/${name}/fd/${fd}`).startsWith("/dev/video"); } catch {}
      if (holds) {
        const pid = parseInt(name, 10);
        out.push({ name: exeKey(pid, () => commOf(pid), exeCache), pid, params: procParams(pid) });
        break;
      }
    }
  }
  out.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.pid - b.pid));
  return out;
}

self.onmessage = (e: { data: any }) => {
  const msg = e.data;
  try {
    if (msg.kind === "net") {
      self.postMessage({ kind: "net", seq: msg.seq, procs: netProcs() });
    } else if (msg.kind === "cam") {
      self.postMessage({ kind: "cam", seq: msg.seq, entries: scanCamHolders() });
    }
  } catch {
    // never let a scan error wedge the worker — reply empty for this seq
    self.postMessage({ kind: msg.kind, seq: msg.seq, procs: [], entries: [] });
  }
};
