import { readdirSync, readFileSync, statSync, unlinkSync, watch, readlinkSync, openSync, readSync, closeSync } from "fs";
import { join, basename } from "path";
import type { DaemonModule, DaemonContext } from "../types.ts";
import { run, nowSec, closeControllers } from "../util.ts";

// ─── claude-sessions ─────────────────────────────────────────────────────────
// Tracks every running Claude Code session for the bar widget: which are still
// working vs stopped/waiting, and the Hyprland window each one lives in so a
// click can focus it.
//
// Three sources, merged:
//   • hook state files — $XDG_RUNTIME_DIR/claude-sessions/<id>.json, written by
//     cc-session-hook on SessionStart/UserPromptSubmit/Stop/Notification/
//     SessionEnd. Authoritative state (working / idle / attention).
//   • live `claude` processes — /proc scan gives the roster + liveness, and each
//     proc's environ carries ZELLIJ_SESSION_NAME/ZELLIJ_PANE_ID, the key that
//     joins a process to its hook file and to its window.
//   • foot window titles — `hyprctl clients -j`. Each cc session runs in a foot
//     window whose title is "<zellij-session> | <glyph> <task>". The zellij name
//     maps a session to a focusable window address (+ workspace); the leading
//     glyph (✳ = idle, braille spinner = working) gives a state fallback for
//     sessions started before hooks were installed.
//
// Cost: no per-tick spawn. Window scan (the only spawn) runs on debounced
// Hyprland window events + a slow safety timer; the proc/file merge is cheap
// sysfs/procfs and runs on a short timer + a watch on the state dir.
// ─────────────────────────────────────────────────────────────────────────────

const STATE_INTERVAL_MS = 3000; // proc + file merge (spawn-free)
const WINDOW_SAFETY_MS = 15000; // hyprctl clients backstop for missed events
const WINDOW_DEBOUNCE_MS = 300; // coalesce a burst of window events (title spinner)
const STATE_DEBOUNCE_MS = 100; // hook writes are atomic — react fast, no coalesce needed
const STALE_FILE_SEC = 30 * 60; // reap hook files with no live proc after this

const STAR = 0x2733; // ✳  Claude's idle/waiting title marker
const CLK_TCK = 100; // jiffies/sec — used to turn proc starttime into wall clock

// System boot time (epoch seconds), to convert a proc's starttime (ticks since
// boot) into a real "running since" timestamp. Constant per boot; read once.
function readBootTime(): number {
  try {
    const m = readFileSync("/proc/stat", "utf-8").match(/^btime (\d+)/m);
    return m ? parseInt(m[1], 10) : 0;
  } catch {
    return 0;
  }
}

interface SessionFile {
  sessionId: string;
  cwd: string;
  transcript: string;
  zellij: string;
  pane: string;
  state: string;
  message: string;
  ts: number;
  startTs: number;
  mtime: number;
}

interface Proc {
  pid: number;
  zellij: string;
  pane: string;
  cwd: string;
  started: number; // /proc/<pid>/stat field 22 (ticks since boot) — stable sort key
}

interface WinInfo {
  address: string;
  title: string;
  task: string;
  glyph: string | null; // "working" | "idle" from the title glyph, or null
  workspace: number;
  workspaceName: string;
}

interface Session {
  id: string;
  pid: number | null;
  project: string;
  cwd: string;
  zellij: string;
  state: string; // working | idle | attention
  message: string;
  task: string;
  address: string | null;
  workspace: number | null;
  workspaceName: string;
  startTs: number | null;
  ts: number | null;
  started: number; // proc start time — bar/popup render in this stable order
  startedAt: number; // epoch s the session's process started (uptime source)
  focused: boolean; // its window is the currently-focused Hyprland window
  branch: string; // git branch of the session's cwd
  tokens: number; // cumulative tokens for the session (from its transcript)
  model: string; // last model used in the session
  hooked: boolean;
}

// Title glyph → coarse state. The spinner cycles through braille frames
// (U+2800–U+28FF) while working; ✳ shows when idle/waiting for input.
function glyphState(firstChar: string): string | null {
  if (!firstChar) return null;
  const cp = firstChar.codePointAt(0)!;
  if (cp === STAR) return "idle";
  if (cp >= 0x2800 && cp <= 0x28ff) return "working";
  return null;
}

export function create(): DaemonModule {
  let stateDir = "";
  const windows = new Map<string, WinInfo>(); // zellij session name → window
  let activeAddr = ""; // normalized address of the focused Hyprland window
  const norm = (a: string) => (a || "").replace(/^0x/i, "").toLowerCase();
  const bootTime = readBootTime(); // epoch s of boot, for proc-starttime → wall clock
  let snapshot: { sessions: Session[]; counts: Record<string, number> } = {
    sessions: [],
    counts: { total: 0, working: 0, idle: 0, attention: 0 },
  };

  // Push the snapshot to stream subscribers, but only when it actually changed —
  // working sessions animate their title glyph (many windowtitle events/sec), and
  // the 3s liveness timer rebuilds unconditionally; dedupe keeps those no-ops off
  // the wire so the bar only re-renders on a real state/roster change.
  const streamControllers = new Set<ReadableStreamDefaultController<Uint8Array>>();
  const encoder = new TextEncoder();
  let lastSent = "";
  function broadcast(): void {
    const json = JSON.stringify(snapshot);
    if (json === lastSent) return;
    lastSent = json;
    const line = encoder.encode(json + "\n");
    for (const ctrl of streamControllers) {
      try {
        ctrl.enqueue(line);
      } catch {
        streamControllers.delete(ctrl);
      }
    }
  }

  // ── sources ───────────────────────────────────────────────────────────────

  function readFiles(): SessionFile[] {
    let names: string[];
    try {
      names = readdirSync(stateDir);
    } catch {
      return [];
    }
    const out: SessionFile[] = [];
    for (const name of names) {
      if (!name.endsWith(".json")) continue;
      const path = join(stateDir, name);
      try {
        const d = JSON.parse(readFileSync(path, "utf-8"));
        const mtime = statSync(path).mtimeMs / 1000;
        out.push({
          sessionId: d.sessionId || name.replace(/\.json$/, ""),
          cwd: d.cwd || "",
          transcript: d.transcript || "",
          zellij: d.zellij || "",
          pane: String(d.pane ?? ""),
          state: d.state || "idle",
          message: d.message || "",
          ts: d.ts || mtime,
          startTs: d.startTs || d.ts || mtime,
          mtime,
        });
      } catch {}
    }
    return out;
  }

  function scanProcs(): Proc[] {
    let pids: string[];
    try {
      pids = readdirSync("/proc");
    } catch {
      return [];
    }
    const out: Proc[] = [];
    for (const name of pids) {
      const c = name.charCodeAt(0);
      if (c < 48 || c > 57) continue;
      let cmd: string;
      try {
        cmd = readFileSync(`/proc/${name}/cmdline`, "utf-8");
      } catch {
        continue;
      }
      // exec -a "claude" sets argv0 to "claude"; the wrapped binary is
      // .claude-wrapped. Match either so we catch every Claude Code process.
      const argv0 = cmd.split("\0")[0] || "";
      if (basename(argv0) !== "claude" && !cmd.includes(".claude-wrapped")) continue;

      let zellij = "";
      let pane = "";
      try {
        const env = readFileSync(`/proc/${name}/environ`, "utf-8");
        for (const kv of env.split("\0")) {
          if (kv.startsWith("ZELLIJ_SESSION_NAME=")) zellij = kv.slice(20);
          else if (kv.startsWith("ZELLIJ_PANE_ID=")) pane = kv.slice(15);
        }
      } catch {}
      let cwd = "";
      try {
        cwd = readlinkSync(`/proc/${name}/cwd`);
      } catch {}
      let started = 0;
      try {
        const st = readFileSync(`/proc/${name}/stat`, "utf-8");
        const lp = st.lastIndexOf(")");
        if (lp >= 0) started = parseInt(st.slice(lp + 2).split(" ")[19], 10) || 0; // field 22
      } catch {}
      out.push({ pid: parseInt(name, 10), zellij, pane, cwd, started });
    }
    return out;
  }

  function refreshWindows(): void {
    const raw = run(["hyprctl", "clients", "-j"], 1500);
    if (!raw) return;
    let clients: any[];
    try {
      clients = JSON.parse(raw);
    } catch {
      return;
    }
    windows.clear();
    for (const cl of clients) {
      const title: string = cl.title || "";
      const idx = title.indexOf(" | ");
      if (idx < 0) continue; // not a "<zellij> | <task>" title
      const zellij = title.slice(0, idx).trim();
      if (!zellij) continue;
      const rest = title.slice(idx + 3).trim();
      const first = rest ? String.fromCodePoint(rest.codePointAt(0)!) : "";
      const gs = glyphState(first);
      // Drop the leading status glyph from the displayed task text.
      const task = gs ? rest.slice(first.length).trim() : rest;
      windows.set(zellij, {
        address: cl.address || "",
        title,
        task,
        glyph: gs,
        workspace: cl.workspace?.id ?? -1,
        workspaceName: cl.workspace?.name ?? "",
      });
    }
    build();
  }

  // ── merge ───────────────────────────────────────────────────────────────────

  function build(): void {
    const files = readFiles();
    const procs = scanProcs();
    const now = nowSec();

    const filesByZellij = new Map<string, SessionFile[]>();
    for (const f of files) {
      const key = f.zellij || `cwd:${f.cwd}`;
      if (!filesByZellij.has(key)) filesByZellij.set(key, []);
      filesByZellij.get(key)!.push(f);
    }

    const used = new Set<string>();
    const sessions: Session[] = [];

    for (const p of procs) {
      const key = p.zellij || `cwd:${p.cwd}`;
      const candidates = filesByZellij.get(key) || [];
      // Prefer an exact pane match (two sessions can share one zellij session).
      let file =
        candidates.find((f) => f.pane && p.pane && f.pane === p.pane) ||
        candidates.find((f) => !used.has(f.sessionId)) ||
        null;
      if (file) used.add(file.sessionId);

      const win = p.zellij ? windows.get(p.zellij) || null : null;
      // File state (hook) is authoritative for idle-vs-attention, but the live
      // title spinner is real-time proof Claude is generating, so it overrides a
      // stale file — e.g. a "needs permission/input" notification the user has
      // since answered (no hook fires on a permission grant) and Claude resumed.
      // Override only TOWARD working (never downgrade a hooked "working" on a
      // momentary ✳ between tools).
      // The hook decides idle vs attention (timing-based: only a mid-turn block
      // is needs-input, not the idle nudge). Safety net for files written before
      // that rule (and the known idle-nudge wording): "waiting for your input" is
      // just stopped/done, never a block.
      let state = file ? file.state : win?.glyph || "idle";
      if (state === "attention" && /waiting for your input/i.test(file?.message || "")) state = "idle";
      // The live title glyph is real-time truth about whether Claude is
      // generating: a spinner overrides a stale file toward working (e.g. a
      // permission the user granted — no hook fires on a grant); a steady ✳
      // overrides a stale "working" back to stopped (e.g. the user interrupted
      // with ESC — no Stop hook fires either). Only when there's no visible glyph
      // (glyph === null: background zellij tab) do we trust the file's "working".
      // Never let the glyph touch "attention" — that's the hook's call.
      if (win?.glyph === "working") state = "working";
      else if (win?.glyph === "idle" && state === "working") state = "idle";
      const cwd = file?.cwd || p.cwd;

      sessions.push({
        id: file?.sessionId || `proc:${p.pid}`,
        pid: p.pid,
        project: basename(cwd) || cwd || "claude",
        cwd,
        zellij: p.zellij,
        state,
        message: file?.message || "",
        task: win?.task || "",
        address: win?.address || null,
        workspace: win?.workspace ?? null,
        workspaceName: win?.workspaceName || "",
        startTs: file?.startTs ?? null,
        ts: file?.ts ?? null,
        started: p.started,
        startedAt: bootTime && p.started ? Math.round(bootTime + p.started / CLK_TCK) : 0,
        focused: !!win?.address && norm(win.address) === activeAddr,
        branch: gitBranch(cwd),
        tokens: file ? tokenCache.get(file.transcript)?.tokens ?? 0 : 0,
        model: file ? tokenCache.get(file.transcript)?.model ?? "" : "",
        hooked: !!file,
      });
    }

    // Reap stale hook files whose process is gone (crash without SessionEnd).
    for (const f of files) {
      if (used.has(f.sessionId)) continue;
      if (now - f.mtime > STALE_FILE_SEC) {
        try {
          unlinkSync(join(stateDir, `${f.sessionId}.json`));
        } catch {}
      }
    }

    // Strict, stable order by process start time: existing sessions never
    // reshuffle when one changes state, and a newly-started session always
    // appends to the end. (Tie-break by pid for procs started in the same tick.)
    sessions.sort((a, b) => (a.started - b.started) || ((a.pid ?? 0) - (b.pid ?? 0)));

    const counts = { total: sessions.length, working: 0, idle: 0, attention: 0 };
    for (const s of sessions) {
      if (s.state === "working") counts.working++;
      else if (s.state === "attention") counts.attention++;
      else counts.idle++;
    }

    snapshot = { sessions, counts };
    broadcast();
  }

  // ── debounced window refresh on Hyprland events ─────────────────────────────
  let winTimer: ReturnType<typeof setTimeout> | null = null;
  function scheduleWindows(): void {
    if (winTimer) return;
    winTimer = setTimeout(() => {
      winTimer = null;
      refreshWindows();
    }, WINDOW_DEBOUNCE_MS);
  }

  // Focus a window by address. The hyprland config is Lua, so `hyprctl dispatch
  // <x>` is eval'd as `hl.dispatch(<x>)`; a bare `focuswindow address:…` is a Lua
  // syntax error. focuswindow has no hl.dsp wrapper — hl.dsp.focus({ window = … })
  // is the working form.
  function focusWindow(addr: string): boolean {
    if (!/^0x[0-9a-fA-F]+$/.test(addr)) return false;
    run(["hyprctl", "dispatch", `hl.dsp.focus({ window = "address:${addr}" })`], 1500);
    return true;
  }

  // Git branch of a cwd — stat-gated cache (tiny .git/HEAD read only on change).
  const branchCache = new Map<string, { branch: string; mtime: number }>();
  function gitBranch(cwd: string): string {
    if (!cwd) return "";
    const head = `${cwd}/.git/HEAD`;
    let st;
    try {
      st = statSync(head);
    } catch {
      return "";
    }
    const c = branchCache.get(cwd);
    if (c && c.mtime === st.mtimeMs) return c.branch;
    let branch = "";
    try {
      const h = readFileSync(head, "utf-8").trim();
      const m = h.match(/^ref: refs\/heads\/(.+)$/);
      branch = m ? m[1] : h.slice(0, 7); // detached HEAD → short sha
    } catch {}
    branchCache.set(cwd, { branch, mtime: st.mtimeMs });
    return branch;
  }

  // Cumulative tokens + last model per transcript, tailed INCREMENTALLY (reads
  // only the appended bytes). Refreshed on a slow timer, never in the hot build
  // path, so it costs ~nothing at idle and a few KB read while a session streams.
  const tokenCache = new Map<string, { offset: number; tokens: number; model: string }>();
  function tailTokens(path: string): void {
    if (!path) return;
    let st;
    try {
      st = statSync(path);
    } catch {
      return;
    }
    const c = tokenCache.get(path) || { offset: 0, tokens: 0, model: "" };
    if (st.size === c.offset) return; // nothing new appended
    if (st.size < c.offset) { c.offset = 0; c.tokens = 0; } // rotated/truncated
    let text = "";
    try {
      const fd = openSync(path, "r");
      const len = st.size - c.offset;
      const buf = Buffer.allocUnsafe(len);
      const n = readSync(fd, buf, 0, len, c.offset);
      closeSync(fd);
      text = buf.toString("utf-8", 0, n);
    } catch {
      return;
    }
    const lines = text.split("\n");
    let consumed = Buffer.byteLength(text, "utf-8");
    if (!text.endsWith("\n")) consumed -= Buffer.byteLength(lines.pop() || "", "utf-8"); // keep partial line
    for (const line of lines) {
      if (!line || line.indexOf('"usage"') < 0) continue;
      try {
        const o = JSON.parse(line);
        const msg = o.message;
        const u = msg?.usage;
        if (!u || o.type !== "assistant") continue;
        const cc = u.cache_creation || {};
        const w5 = cc.ephemeral_5m_input_tokens ?? u.cache_creation_input_tokens ?? 0;
        const w1 = cc.ephemeral_1h_input_tokens ?? 0;
        c.tokens += (u.input_tokens || 0) + (u.output_tokens || 0) + (u.cache_read_input_tokens || 0) + w5 + w1;
        if (msg.model) c.model = msg.model;
      } catch {}
    }
    c.offset += consumed;
    tokenCache.set(path, c);
  }
  function refreshTokens(): void {
    for (const f of readFiles()) tailTokens(f.transcript);
    build();
  }

  return {
    name: "claude-sessions",

    init(ctx: DaemonContext) {
      stateDir = `${ctx.runtimeDir}/claude-sessions`;

      // Seed the currently-focused window so the "selected" chip is right on start.
      try {
        const aw = JSON.parse(run(["hyprctl", "activewindow", "-j"], 1500) || "{}");
        activeAddr = norm(aw.address || "");
      } catch {}

      refreshWindows();
      build();

      const onWin = () => scheduleWindows();
      for (const ev of ["openwindow", "closewindow", "windowtitle", "windowtitlev2", "movewindowv2"]) {
        ctx.hyprIPC.on(ev, onWin);
      }

      // Track focus changes so the widget can mark the selected session live.
      ctx.hyprIPC.on("activewindowv2", (data: string) => {
        const a = norm(data.trim());
        if (a === activeAddr) return;
        activeAddr = a;
        build();
      });

      const stateTimer = setInterval(build, STATE_INTERVAL_MS);
      const winSafety = setInterval(refreshWindows, WINDOW_SAFETY_MS);
      refreshTokens(); // seed token tallies + git branches
      const tokenTimer = setInterval(refreshTokens, 10000); // slow, incremental

      // Refresh promptly when a hook writes/removes a session file.
      let fsTimer: ReturnType<typeof setTimeout> | null = null;
      try {
        watch(stateDir, () => {
          if (fsTimer) return;
          fsTimer = setTimeout(() => {
            fsTimer = null;
            build();
          }, STATE_DEBOUNCE_MS);
        });
      } catch {}

      ctx.signal.addEventListener("abort", () => {
        clearInterval(stateTimer);
        clearInterval(winSafety);
        clearInterval(tokenTimer);
      });
    },

    shutdown() {
      closeControllers(streamControllers);
    },

    routes: {
      // Always-on push: emits the snapshot on connect, then again on every real
      // change (deduped in broadcast()). Bar widget + popup are pure consumers.
      stream: (req: Request) => {
        const rs = new ReadableStream<Uint8Array>({
          start(controller) {
            streamControllers.add(controller);
            controller.enqueue(encoder.encode(JSON.stringify(snapshot) + "\n"));
            req.signal.addEventListener("abort", () => {
              streamControllers.delete(controller);
              try {
                controller.close();
              } catch {}
            });
          },
          cancel() {},
        });
        return new Response(rs, {
          headers: {
            "Content-Type": "application/x-ndjson",
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
          },
        });
      },

      list: () => Response.json(snapshot),

      focus: (req: Request) => {
        const url = new URL(req.url);
        let addr = url.searchParams.get("addr") || "";
        const sid = url.searchParams.get("session") || "";
        if (!addr && sid) addr = snapshot.sessions.find((x) => x.id === sid)?.address || "";
        if (!focusWindow(addr)) return Response.json({ ok: false, error: "no window" }, { status: 404 });
        return Response.json({ ok: true });
      },

      // Cycle focus through running sessions in bar order. dir=next|prev. Starts
      // from whichever session window is focused now (or the ends if none is).
      cycle: (req: Request) => {
        const dir = new URL(req.url).searchParams.get("dir") === "prev" ? -1 : 1;
        const list = snapshot.sessions.filter((s) => s.address);
        if (list.length === 0) return Response.json({ ok: false, error: "no sessions" }, { status: 404 });
        let cur = -1;
        try {
          const aw = JSON.parse(run(["hyprctl", "activewindow", "-j"], 1500) || "{}");
          cur = list.findIndex((s) => s.address === aw.address);
        } catch {}
        const i = cur < 0 ? (dir > 0 ? 0 : list.length - 1) : (cur + dir + list.length) % list.length;
        focusWindow(list[i].address!);
        return Response.json({ ok: true, focused: list[i].id });
      },
    },
  };
}
