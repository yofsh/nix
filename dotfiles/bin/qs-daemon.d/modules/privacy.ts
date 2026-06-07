import { readFileSync } from "fs";
import type { DaemonModule, DaemonContext } from "../types.ts";
import { procParams, type ProcEntry } from "./procinfo.ts";
import { scanCam } from "./scanner.ts";

const CMD_TIMEOUT = 2000;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function spawn(cmd: string[], timeout = CMD_TIMEOUT): Promise<string> {
  try {
    const proc = Bun.spawn(cmd, { stdout: "pipe", stderr: "ignore" });
    const text = new Response(proc.stdout).text();
    const timer = new Promise<string>((_, reject) =>
      setTimeout(() => {
        proc.kill();
        reject(new Error("timeout"));
      }, timeout),
    );
    return await Promise.race([text, timer]);
  } catch {
    return "";
  }
}

function pidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Voice PID exclusion
// ---------------------------------------------------------------------------

function getVoicePids(): Set<string> {
  const pids = new Set<string>();
  const pidFiles = [
    "/tmp/voice_dictate.pid",
    "/tmp/voice_claude.pid",
    "/tmp/voice_stream.pid",
  ];
  for (const f of pidFiles) {
    try {
      const content = readFileSync(f, "utf-8").trim();
      const pid = content.split("\n")[0]?.trim();
      if (pid && pidAlive(parseInt(pid, 10))) {
        pids.add(pid);
      }
    } catch {}
  }
  return pids;
}

// ---------------------------------------------------------------------------
// Microphone check
// ---------------------------------------------------------------------------

async function checkMic(): Promise<ProcEntry[]> {
  const voicePids = getVoicePids();

  const raw = await spawn(["pactl", "-f", "json", "list", "source-outputs"]);
  if (!raw.trim()) return [];

  let outputs: any[];
  try {
    outputs = JSON.parse(raw);
  } catch {
    return [];
  }

  const out: ProcEntry[] = [];
  const seen = new Set<number>();
  for (const entry of outputs) {
    // Skip corked (paused) streams
    if (entry.corked !== false) continue;

    const props = entry.properties ?? {};

    // Skip monitor streams
    if ((props["stream.monitor"] ?? "") === "true") continue;

    // Skip voice script PIDs
    const pidStr = props["application.process.id"] ?? "";
    if (pidStr && voicePids.has(pidStr)) continue;

    const name = props["application.name"];
    if (!name) continue;
    const pid = parseInt(pidStr, 10) || 0;
    if (pid && seen.has(pid)) continue;
    if (pid) seen.add(pid);
    out.push({ name, pid, params: pid ? procParams(pid) : "" });
  }

  out.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.pid - b.pid));
  return out;
}

// Camera check is delegated to the shared scanner worker (scanCam) — it walks
// /proc/*/fd for /dev/video* holders off the main event loop, in-process.

// ---------------------------------------------------------------------------
// Screen share check
// ---------------------------------------------------------------------------

async function checkScreen(): Promise<ProcEntry[]> {
  const raw = await spawn(["pw-dump"]);
  if (!raw.trim()) return [];

  let nodes: any[];
  try {
    nodes = JSON.parse(raw);
  } catch {
    return [];
  }

  // Find portal source node IDs
  const portalIds = new Set<number>();
  for (const node of nodes) {
    const props = node.info?.props ?? {};
    if (props["media.class"] !== "Video/Source") continue;
    const nodeName: string = props["node.name"] ?? "";
    if (/xdg-desktop-portal/.test(nodeName)) {
      portalIds.add(node.id);
    }
  }

  if (portalIds.size === 0) return [];

  // Find streams targeting a portal source
  const out: ProcEntry[] = [];
  const seen = new Set<number>();
  for (const node of nodes) {
    const props = node.info?.props ?? {};
    if (props["media.class"] !== "Stream/Input/Video") continue;

    const target = props["node.target"] ?? props["node.driver-id"];
    if (target == null || !portalIds.has(target)) continue;

    const name = props["application.name"] || props["node.name"];
    if (!name) continue;
    const pid = parseInt(props["application.process.id"] ?? "", 10) || 0;
    if (pid && seen.has(pid)) continue;
    if (pid) seen.add(pid);
    out.push({ name, pid, params: pid ? procParams(pid) : "" });
  }

  out.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.pid - b.pid));
  return out;
}

// ---------------------------------------------------------------------------
// Module export — EVENT-DRIVEN
// ---------------------------------------------------------------------------
//
// Mic and screen-share state lives only in PipeWire/PulseAudio (no kernel
// signal), so instead of polling their CLIs on a timer we watch their event
// events, by what each source supports:
//   • mic    → `pactl subscribe` — instant, quiet when idle.
//   • screen → `pw-mon -a -o` filtered to Node add/remove — instant. `-a -o`
//              drop the param/prop bodies (the 38k-line "firehose" was the
//              one-time graph dump re-read in a feedback loop, not pw-mon
//              itself; idle is ~2 lines/s). We react ONLY to Node lifecycle, so
//              our own pw-dump's Client churn can't re-trigger the loop.
//   • camera → pw-mon Node events catch portal/browser camera instantly; a slow
//              POLL_MS safety scan covers direct /dev/video* (which has no event).
// The slow poll also keepalives the stream. State is pushed over `stream`.

export function create(): DaemonModule {
  const encoder = new TextEncoder();
  const clients = new Set<ReadableStreamDefaultController<Uint8Array>>();
  let cur: { mic: ProcEntry[]; cam: ProcEntry[]; screen: ProcEntry[] } = { mic: [], cam: [], screen: [] };

  const POLL_MS = 5000; // direct-/dev/video* safety scan + stream keepalive
  let aborting = false;
  let micMon: ReturnType<typeof Bun.spawn> | null = null;
  let pwMon: ReturnType<typeof Bun.spawn> | null = null;
  let micDebounce: ReturnType<typeof setTimeout> | null = null;
  let pwDebounce: ReturnType<typeof setTimeout> | null = null;
  let pollTimer: ReturnType<typeof setInterval> | null = null;

  const same = (a: ProcEntry[], b: ProcEntry[]) =>
    a.length === b.length && a.every((e, i) => e.pid === b[i].pid && e.name === b[i].name);

  function broadcast() {
    const line = encoder.encode(JSON.stringify(cur) + "\n");
    for (const c of clients) { try { c.enqueue(line); } catch { clients.delete(c); } }
  }

  async function recheckMic() {
    const mic = await checkMic();
    if (!same(mic, cur.mic)) { cur = { ...cur, mic }; broadcast(); }
  }
  async function recheckScreen() {
    const screen = await checkScreen();
    if (!same(screen, cur.screen)) { cur = { ...cur, screen }; broadcast(); }
  }
  async function recheckCam() {
    const cam = await scanCam();
    if (!same(cam, cur.cam)) { cur = { ...cur, cam }; broadcast(); }
  }

  function startMicMonitor() {
    if (aborting) return;
    try {
      micMon = Bun.spawn(["pactl", "subscribe"], { stdout: "pipe", stderr: "ignore" });
      const dec = new TextDecoder();
      (async () => {
        try {
          for await (const chunk of micMon!.stdout as any) {
            if (dec.decode(chunk).includes("source-output")) { // a mic stream changed
              if (micDebounce) clearTimeout(micDebounce);
              micDebounce = setTimeout(recheckMic, 250);
            }
          }
        } catch {}
        if (!aborting) setTimeout(startMicMonitor, 2000); // respawn if pulse restarts
      })();
    } catch {}
  }

  // Watch the PipeWire graph for Node add/remove (a screencast or camera stream
  // is a Node). `-a -o` strip the param/prop firehose; we line-parse and react
  // only when an "added:"/"removed:" event's "type:" is a Node — so our own
  // pw-dump re-check (which connects as a Client) can't feed back.
  function startPwMonitor() {
    if (aborting) return;
    try {
      pwMon = Bun.spawn(["pw-mon", "-a", "-o"], { stdout: "pipe", stderr: "ignore" });
      const dec = new TextDecoder();
      let buf = "";
      let lifecycle = false; // saw added:/removed:, awaiting its type:
      (async () => {
        try {
          for await (const chunk of pwMon!.stdout as any) {
            buf += dec.decode(chunk, { stream: true });
            let nl: number;
            while ((nl = buf.indexOf("\n")) >= 0) {
              const t = buf.slice(0, nl).trim();
              buf = buf.slice(nl + 1);
              if (t === "added:" || t === "removed:") lifecycle = true;
              else if (lifecycle && t.startsWith("type:")) {
                if (t.includes("Interface:Node")) {
                  if (pwDebounce) clearTimeout(pwDebounce);
                  pwDebounce = setTimeout(() => { recheckScreen(); recheckCam(); }, 300);
                }
                lifecycle = false;
              }
            }
          }
        } catch {}
        if (!aborting) setTimeout(startPwMonitor, 2000); // respawn if pipewire restarts
      })();
    } catch {}
  }

  function cleanup() {
    aborting = true;
    for (const t of [micDebounce, pwDebounce]) if (t) clearTimeout(t);
    if (pollTimer) clearInterval(pollTimer);
    micDebounce = pwDebounce = pollTimer = null;
    try { micMon?.kill(); } catch {}
    try { pwMon?.kill(); } catch {}
    micMon = pwMon = null;
    for (const c of clients) { try { c.close(); } catch {} }
    clients.clear();
  }

  return {
    name: "privacy",

    init(ctx: DaemonContext) {
      recheckMic(); recheckScreen(); recheckCam(); // seed
      startMicMonitor(); // mic → pactl subscribe (instant)
      startPwMonitor();  // screen + portal-camera → pw-mon Node events (instant)
      // Only direct /dev/video* access lacks an event → slow safety scan. The
      // tick also keepalives ("\n", ignored by the client) so the push-on-change
      // stream never trips the server's idle timeout.
      pollTimer = setInterval(() => {
        if (clients.size === 0) return;
        const ka = encoder.encode("\n");
        for (const c of clients) { try { c.enqueue(ka); } catch { clients.delete(c); } }
        recheckCam();
      }, POLL_MS);
      ctx.signal.addEventListener("abort", () => cleanup());
    },

    routes: {
      // Cached snapshot — no probing (kept for compatibility / one-off reads).
      check: async (): Promise<Response> => Response.json(cur),

      // Push stream: current state on connect + on every change.
      stream: (req: Request) => {
        const stream = new ReadableStream<Uint8Array>({
          start(controller) {
            clients.add(controller);
            try { controller.enqueue(encoder.encode(JSON.stringify(cur) + "\n")); } catch {}
            req.signal.addEventListener("abort", () => {
              clients.delete(controller);
              try { controller.close(); } catch {}
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

    shutdown() { cleanup(); },
  };
}
