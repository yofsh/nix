// Main-thread client for the shared scanner worker (scanworker.ts). One worker
// thread is lazily created and shared by every module that needs an off-loop
// /proc scan (procmon traffic, privacy camera). Request/reply is matched by seq;
// each request resolves with a fallback on timeout so a stuck worker can never
// hang a tick.

import type { ProcEntry } from "./procinfo.ts";

export interface NetProc {
  name: string; count: number;
  rx: number; tx: number; total: number;
  rxr: number; txr: number; rxa: number; txa: number;
}

const REPLY_TIMEOUT_MS = 1500;

let worker: Worker | null = null;
let seq = 0;
const pending = new Map<number, { resolve: (v: any) => void; timer: ReturnType<typeof setTimeout> }>();

function ensureWorker(): Worker {
  if (worker) return worker;
  worker = new Worker(new URL("./scanworker.ts", import.meta.url).href);
  worker.addEventListener("message", (e: any) => {
    const m = e.data;
    const p = pending.get(m.seq);
    if (!p) return;
    clearTimeout(p.timer);
    pending.delete(m.seq);
    p.resolve(m);
  });
  // On a worker error, fail open: outstanding requests resolve via their timeouts.
  worker.addEventListener("error", () => {});
  return worker;
}

function request(msg: any, fallback: any): Promise<any> {
  const w = ensureWorker();
  const s = ++seq;
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      pending.delete(s);
      resolve(fallback);
    }, REPLY_TIMEOUT_MS);
    pending.set(s, { resolve, timer });
    w.postMessage({ ...msg, seq: s });
  });
}

// Worker runs the whole traffic pipeline and returns just the top-N apps.
export function scanNetProcs(): Promise<{ procs: NetProc[] }> {
  return request({ kind: "net" }, { procs: [] }).then((m) => ({ procs: m.procs as NetProc[] }));
}

export function scanCam(): Promise<ProcEntry[]> {
  return request({ kind: "cam" }, { entries: [] }).then((m) => m.entries as ProcEntry[]);
}

export function terminateScanner(): void {
  if (worker) { try { worker.terminate(); } catch {} worker = null; }
  for (const p of pending.values()) clearTimeout(p.timer);
  pending.clear();
}
