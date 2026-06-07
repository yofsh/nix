import { readdirSync, readFileSync } from "fs";
import type { DaemonModule, DaemonContext } from "../types.ts";
import { closeControllers } from "../util.ts";
import { exeKey } from "./procinfo.ts";
import { scanNetProcs, terminateScanner } from "./scanner.ts";

// ─── procmon ────────────────────────────────────────────────────────────────
// Always-on per-process + system monitor. Everything is sampled in the
// background (every 2s) so a popup shows a full picture instantly on open; the
// streams just relay and seed. Processes are GROUPED BY EXECUTABLE
// (/proc/<pid>/exe basename) so an app's helper procs (Firefox content/RDD/GPU,
// Chrome, Electron) collapse into one row with a count. Falls back to comm.
//
// Per-resource window (last ~60s), chosen to match what each metric means:
//   • CPU    → sliding-average % over the window (per-core; popup can normalize)
//   • Memory → sliding-average resident bytes over the window
//   • Network→ CUMULATIVE bytes transferred over the window (↓/↑) + current rate
//
//   procmon/sysprocs  {seed}=ncpu+totals+stat-history, {agg}=live system stats,
//                     {proc}=top apps by cpu/mem (window values)
//   procmon/netprocs  {procs}=top apps by traffic used in the window
//
// Cost: cpu/mem come from a cheap /proc/<pid>/stat scan on THIS thread every 2s.
// The expensive per-app NETWORK pipeline (netlink + inode→pid fd walk) runs in
// the shared scanner WORKER thread (scanner.ts) — off this event loop, no spawn —
// and this module just relays its small result. All always-on (by request).
// ─────────────────────────────────────────────────────────────────────────────

const CLK_TCK = 100;
const PAGE_SIZE = 4096;
const TICK_MS = 2000;
const WINDOW_SAMPLES = 30; // 30 × 2s ≈ 60s sliding window
const HIST_SAMPLES = 150; // 150 × 2s ≈ 5 min of system-stat history
const TOP_N = 10;
const NDJSON_HEADERS = {
  "Content-Type": "application/x-ndjson",
  "Cache-Control": "no-cache",
  "X-Accel-Buffering": "no",
};

interface Group { name: string; count: number; value: number; inst: number; swap?: number; swapInst?: number; }
interface StatPoint { u: number; s: number; mem: number; swap: number; }

const r1 = (x: number) => Math.round(x * 10) / 10;
const sum = (a: number[]) => { let s = 0; for (const v of a) s += v; return s; };

// Top-N by 1-min average UNION top-N by instant, so the popup can re-rank by
// whichever window the user selects without losing candidates either way.
function topUnion(list: Group[], n: number): Group[] {
  const byAvg = [...list].sort((a, b) => b.value - a.value).slice(0, n);
  const byInst = [...list].sort((a, b) => b.inst - a.inst).slice(0, n);
  const seen = new Set<string>();
  const out: Group[] = [];
  for (const e of byAvg) if (!seen.has(e.name)) { seen.add(e.name); out.push(e); }
  for (const e of byInst) if (!seen.has(e.name)) { seen.add(e.name); out.push(e); }
  return out;
}

function listPids(): number[] {
  const out: number[] = [];
  let names: string[];
  try { names = readdirSync("/proc"); } catch { return out; }
  for (const name of names) {
    const c = name.charCodeAt(0);
    if (c < 48 || c > 57) continue;
    const n = parseInt(name, 10);
    if (n > 0) out.push(n);
  }
  return out;
}

function readStat(pid: number): { comm: string; jiffies: number; rss: number } | null {
  let s: string;
  try { s = readFileSync(`/proc/${pid}/stat`, "utf-8"); } catch { return null; }
  const lp = s.lastIndexOf(")");
  if (lp < 0) return null;
  const comm = s.slice(s.indexOf("(") + 1, lp);
  const rest = s.slice(lp + 2).split(" ");
  const utime = parseInt(rest[11], 10) || 0; // field 14
  const stime = parseInt(rest[12], 10) || 0; // field 15
  const rssPages = parseInt(rest[21], 10) || 0; // field 24 (resident pages)
  return { comm, jiffies: utime + stime, rss: rssPages * PAGE_SIZE };
}

// Swapped-out bytes for a pid (VmSwap in /proc/<pid>/status, readable without
// ptrace for nearly every process). 0 for kernel threads / unreadable pids.
function readSwapBytes(pid: number): number {
  let s: string;
  try { s = readFileSync(`/proc/${pid}/status`, "utf-8"); } catch { return 0; }
  const i = s.indexOf("VmSwap:");
  if (i < 0) return 0;
  return (parseInt(s.slice(i + 7), 10) || 0) * 1024; // "VmSwap:\t  123 kB" → bytes
}

function readCpuTimes(): number[] | null {
  try {
    const t = readFileSync("/proc/stat", "utf-8");
    const nl = t.indexOf("\n");
    const parts = t.slice(0, nl < 0 ? undefined : nl).trim().split(/\s+/);
    return parts.slice(1).map((x: string) => parseInt(x, 10) || 0);
  } catch { return null; }
}

function readMeminfo(): { memTotal: number; memAvail: number; swapTotal: number; swapFree: number } {
  let memTotal = 0, memAvail = 0, swapTotal = 0, swapFree = 0;
  try {
    const t = readFileSync("/proc/meminfo", "utf-8");
    for (const line of t.split("\n")) {
      const c = line.indexOf(":");
      if (c < 0) continue;
      const k = line.slice(0, c);
      const v = parseInt(line.slice(c + 1), 10) || 0;
      if (k === "MemTotal") memTotal = v;
      else if (k === "MemAvailable") memAvail = v;
      else if (k === "SwapTotal") swapTotal = v;
      else if (k === "SwapFree") swapFree = v;
    }
  } catch {}
  return { memTotal, memAvail, swapTotal, swapFree };
}

function readLoad1(): number {
  try { return parseFloat(readFileSync("/proc/loadavg", "utf-8").split(" ")[0]) || 0; } catch { return 0; }
}

export function create(): DaemonModule {
  const encoder = new TextEncoder();
  const sysClients = new Set<ReadableStreamDefaultController<Uint8Array>>();
  const netClients = new Set<ReadableStreamDefaultController<Uint8Array>>();

  let ncpu = 1;
  try {
    ncpu = readFileSync("/proc/cpuinfo", "utf-8").split("\n")
      .filter((l: string) => l.startsWith("processor")).length || 1;
  } catch {}

  function broadcast(clients: Set<ReadableStreamDefaultController<Uint8Array>>, payload: string) {
    if (clients.size === 0) return;
    const buf = encoder.encode(payload);
    for (const ctrl of clients) {
      try { ctrl.enqueue(buf); } catch { clients.delete(ctrl); }
    }
  }

  // ── aggregate system stats + history (always-on) ──
  let prevCpu: number[] | null = null;
  const statHistory: StatPoint[] = [];
  let memTotalKB = 0, swapTotalKB = 0;
  let lastAgg: any = null;

  function aggTick() {
    const cpu = readCpuTimes();
    let u = 0, s = 0;
    if (cpu) {
      if (prevCpu) {
        let tot = 0;
        for (let i = 0; i < cpu.length; i++) tot += cpu[i] - (prevCpu[i] || 0);
        if (tot > 0) {
          const du = cpu[0] - prevCpu[0] + (cpu[1] - (prevCpu[1] || 0));
          const ds = cpu[2] - prevCpu[2] + (cpu[5] || 0) - (prevCpu[5] || 0)
            + (cpu[6] || 0) - (prevCpu[6] || 0) + (cpu[7] || 0) - (prevCpu[7] || 0);
          u = Math.max(0, (du / tot) * 100);
          s = Math.max(0, (ds / tot) * 100);
        }
      }
      prevCpu = cpu;
    }
    const mi = readMeminfo();
    const memPct = mi.memTotal > 0 ? (1 - mi.memAvail / mi.memTotal) * 100 : 0;
    const swapPct = mi.swapTotal > 0 ? (1 - mi.swapFree / mi.swapTotal) * 100 : 0;
    memTotalKB = mi.memTotal;
    swapTotalKB = mi.swapTotal;

    const pt: StatPoint = { u: r1(u), s: r1(s), mem: r1(memPct), swap: r1(swapPct) };
    statHistory.push(pt);
    if (statHistory.length > HIST_SAMPLES) statHistory.shift();

    lastAgg = {
      agg: 1, u: pt.u, s: pt.s, mem: pt.mem, swap: pt.swap,
      load: r1(readLoad1()),
      memUsedKB: mi.memTotal - mi.memAvail,
      swapUsedKB: mi.swapTotal - mi.swapFree,
    };
    broadcast(sysClients, JSON.stringify(lastAgg) + "\n");
  }

  function seedPayload(): string {
    return JSON.stringify({
      seed: 1, ncpu, memTotalKB, swapTotalKB,
      hist: statHistory.map((p) => [p.u, p.s, p.mem, p.swap]),
    }) + "\n";
  }

  // ── per-process cpu+mem (always-on); sliding-window averages per app ──
  let prevJiffies = new Map<number, number>();
  let prevProcTs = 0;
  const cpuRing = new Map<string, number[]>(); // exe → per-tick total CPU% (per-core)
  const memRing = new Map<string, number[]>(); // exe → per-tick total RSS bytes
  const swapRing = new Map<string, number[]>(); // exe → per-tick total swap bytes
  let lastProcPayload: string | null = null;

  function procTick() {
    const now = Date.now() / 1000;
    const dt = prevProcTs > 0 ? now - prevProcTs : 0;
    const nextJiffies = new Map<number, number>();
    const exeCache = new Map<number, string>();
    const groups = new Map<string, { cpu: number; rss: number; swap: number; count: number }>();

    for (const pid of listPids()) {
      const st = readStat(pid);
      if (!st) continue;
      nextJiffies.set(pid, st.jiffies);
      const key = exeKey(pid, () => st.comm, exeCache);
      let g = groups.get(key);
      if (!g) { g = { cpu: 0, rss: 0, swap: 0, count: 0 }; groups.set(key, g); }
      g.rss += st.rss;
      g.count++;
      if (swapTotalKB > 0) g.swap += readSwapBytes(pid);
      if (dt > 0) {
        const prev = prevJiffies.get(pid);
        if (prev !== undefined) {
          const dj = st.jiffies - prev;
          if (dj > 0) g.cpu += (dj / CLK_TCK / dt) * 100;
        }
      }
    }
    prevJiffies = nextJiffies;
    prevProcTs = now;

    for (const [key, g] of groups) {
      let mr = memRing.get(key);
      if (!mr) { mr = []; memRing.set(key, mr); }
      mr.push(g.rss);
      if (mr.length > WINDOW_SAMPLES) mr.shift();

      let sr = swapRing.get(key);
      if (!sr) { sr = []; swapRing.set(key, sr); }
      sr.push(g.swap);
      if (sr.length > WINDOW_SAMPLES) sr.shift();

      if (dt > 0) {
        let cr = cpuRing.get(key);
        if (!cr) { cr = []; cpuRing.set(key, cr); }
        cr.push(g.cpu);
        if (cr.length > WINDOW_SAMPLES) cr.shift();
      }
    }
    // drop rings for executables no longer running
    for (const key of cpuRing.keys()) if (!groups.has(key)) cpuRing.delete(key);
    for (const key of memRing.keys()) if (!groups.has(key)) memRing.delete(key);
    for (const key of swapRing.keys()) if (!groups.has(key)) swapRing.delete(key);

    const cpuList: Group[] = [];
    for (const [name, r] of cpuRing) {
      if (r.length === 0) continue;
      const g = groups.get(name);
      cpuList.push({ name, count: g ? g.count : 0, value: sum(r) / r.length, inst: r[r.length - 1] });
    }

    const memList: Group[] = [];
    for (const [name, r] of memRing) {
      if (r.length === 0) continue;
      const avg = sum(r) / r.length;
      if (avg <= 0) continue;
      const g = groups.get(name);
      const sr = swapRing.get(name);
      const swapAvg = sr && sr.length ? sum(sr) / sr.length : 0;
      const swapInst = sr && sr.length ? sr[sr.length - 1] : 0;
      memList.push({ name, count: g ? g.count : 0, value: avg, inst: r[r.length - 1], swap: swapAvg, swapInst });
    }

    lastProcPayload = JSON.stringify({
      proc: 1, cpu: topUnion(cpuList, TOP_N), mem: topUnion(memList, TOP_N),
    }) + "\n";
    broadcast(sysClients, lastProcPayload);
  }

  // ── per-process network (always-on) ──
  // The ENTIRE per-app traffic pipeline (netlink SOCK_DIAG byte counters, the
  // inode→pid /proc/*/fd map, per-socket deltas, exe grouping, and the 60s ring)
  // runs in the shared scanner WORKER thread — off this event loop, in-process
  // (honest CPU, no fork). Main only relays the worker's small final result, so
  // there's no big cross-thread transfer. See scanworker.ts + CLAUDE.md.
  let lastNetPayload: string | null = null;

  async function netTick() {
    const { procs } = await scanNetProcs();
    lastNetPayload = JSON.stringify({ procs }) + "\n";
    broadcast(netClients, lastNetPayload);
  }

  let aggTimer: ReturnType<typeof setInterval> | null = null;
  let procTimer: ReturnType<typeof setInterval> | null = null;
  let netTimer: ReturnType<typeof setInterval> | null = null;

  return {
    name: "procmon",

    init(ctx: DaemonContext) {
      aggTick(); procTick(); netTick();
      aggTimer = setInterval(aggTick, TICK_MS);
      procTimer = setInterval(procTick, TICK_MS);
      netTimer = setInterval(netTick, TICK_MS);
      ctx.signal.addEventListener("abort", () => {
        for (const t of [aggTimer, procTimer, netTimer]) if (t) clearInterval(t);
        aggTimer = procTimer = netTimer = null;
        terminateScanner();
        closeControllers(sysClients);
        closeControllers(netClients);
      });
    },

    routes: {
      sysprocs: (req: Request) => {
        const stream = new ReadableStream<Uint8Array>({
          start(controller) {
            sysClients.add(controller);
            try {
              controller.enqueue(encoder.encode(seedPayload()));
              if (lastAgg) controller.enqueue(encoder.encode(JSON.stringify(lastAgg) + "\n"));
              if (lastProcPayload) controller.enqueue(encoder.encode(lastProcPayload));
            } catch {}
            req.signal.addEventListener("abort", () => {
              sysClients.delete(controller);
              try { controller.close(); } catch {}
            });
          },
          cancel() {},
        });
        return new Response(stream, { headers: NDJSON_HEADERS });
      },

      netprocs: (req: Request) => {
        const stream = new ReadableStream<Uint8Array>({
          start(controller) {
            netClients.add(controller);
            if (lastNetPayload) {
              try { controller.enqueue(encoder.encode(lastNetPayload)); } catch {}
            }
            req.signal.addEventListener("abort", () => {
              netClients.delete(controller);
              try { controller.close(); } catch {}
            });
          },
          cancel() {},
        });
        return new Response(stream, { headers: NDJSON_HEADERS });
      },
    },

    shutdown() {
      for (const t of [aggTimer, procTimer, netTimer]) if (t) clearInterval(t);
      aggTimer = procTimer = netTimer = null;
      terminateScanner();
      closeControllers(sysClients);
      closeControllers(netClients);
    },
  };
}
