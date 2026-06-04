import { readdirSync, statSync, openSync, readSync, closeSync, existsSync, readFileSync } from "fs";
import { join, basename, dirname } from "path";
import { homedir } from "os";
import type { DaemonModule, DaemonContext } from "../types.ts";

// ---------------------------------------------------------------------------
// Claude Code token-usage tracking, per project.
//
// Claude Code already logs every assistant message — with full token usage,
// model, timestamp and cwd — to append-only JSONL transcripts under
// ~/.claude/projects/<encoded-path>/<session>.jsonl. We don't hook anything;
// we just tail those files incrementally and aggregate tokens + estimated cost
// per project per day, keeping a sliding 7-day window.
// ---------------------------------------------------------------------------

const PROJECTS_DIR = join(process.env.CLAUDE_CONFIG_DIR || `${homedir()}/.claude`, "projects");
const WINDOW_DAYS = 7;
const SCAN_INTERVAL = 30_000;

// ---------------------------------------------------------------------------
// Subscription rate-limit utilization — the numbers `/usage` shows: the 5-hour
// rolling window and the weekly (7-day) limits, overall + per-model. Pulled
// from the OAuth usage endpoint with the access token Claude Code stores (and
// keeps refreshed) in .credentials.json. We read the token fresh on every poll,
// so we always ride on Claude Code's latest refresh and never touch the refresh
// flow ourselves — an expired or missing token just yields no limits.
// ---------------------------------------------------------------------------

const CREDENTIALS_PATH = join(process.env.CLAUDE_CONFIG_DIR || `${homedir()}/.claude`, ".credentials.json");
const USAGE_ENDPOINT = "https://api.anthropic.com/api/oauth/usage";
const LIMITS_INTERVAL = 900_000; // 15 min — utilization changes slowly; no need to poll often

function readAccessToken(): string | null {
  try {
    const o = JSON.parse(readFileSync(CREDENTIALS_PATH, "utf-8"))?.claudeAiOauth;
    if (!o?.accessToken) return null;
    if (o.expiresAt && Date.now() > o.expiresAt) return null; // stale — Claude Code refreshes on next use
    return o.accessToken as string;
  } catch {
    return null;
  }
}

// One window object (five_hour / seven_day / …) -> {utilization, resetsAt} | null.
function normWindow(w: any): { utilization: number; resetsAt: string | null } | null {
  return w && typeof w.utilization === "number"
    ? { utilization: w.utilization, resetsAt: w.resets_at ?? null }
    : null;
}

// ---------------------------------------------------------------------------
// Project roots — how working directories are grouped into project buckets.
//
// A cwd at or under one of these roots collapses to that root (deepest match
// wins), so e.g. ~/nix/dotfiles/quickshell/modules/foo counts as "quickshell".
// Anything not under a listed root falls back to its git repo root, then to the
// cwd itself. So you only list the sub-apps you want carved out of their repo.
//
// The list lives in claude-usage-roots.json (gitignored, personal); a committed
// claude-usage-roots.example.json is used as a fallback template.
// ---------------------------------------------------------------------------

const ROOTS_PATH = join(import.meta.dir, "..", "claude-usage-roots.json");
const ROOTS_EXAMPLE_PATH = join(import.meta.dir, "..", "claude-usage-roots.example.json");

function expandHome(p: string): string {
  return p.startsWith("~") ? homedir() + p.slice(1) : p;
}

function loadRoots(): string[] {
  for (const path of [ROOTS_PATH, ROOTS_EXAMPLE_PATH]) {
    if (!existsSync(path)) continue;
    try {
      const parsed = JSON.parse(readFileSync(path, "utf-8"));
      const list: string[] = Array.isArray(parsed) ? parsed : parsed.roots || [];
      return list
        .map((p) => expandHome(String(p)).replace(/\/+$/, ""))
        .filter(Boolean)
        .sort((a, b) => b.length - a.length); // deepest (longest) first
    } catch (e) {
      console.error("claude-usage: roots load error:", path, e);
    }
  }
  return [];
}

const PROJECT_ROOTS = loadRoots();

// Nearest ancestor (incl. self) containing a .git entry. Cached per directory.
const repoRootCache = new Map<string, string | null>();
function findRepoRoot(dir: string): string | null {
  if (repoRootCache.has(dir)) return repoRootCache.get(dir)!;
  const chain: string[] = [];
  let cur = dir;
  while (cur && cur !== "/") {
    chain.push(cur);
    if (existsSync(join(cur, ".git"))) {
      for (const d of chain) repoRootCache.set(d, cur);
      return cur;
    }
    const parent = dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  for (const d of chain) repoRootCache.set(d, null);
  return null;
}

// USD per 1M tokens. Cache reads are ~10× cheaper than fresh input; cache
// writes a bit more expensive. Keyed by model family + version tier — Anthropic
// cut Opus pricing 3× starting at Opus 4.5 ($5/$25 vs the old $15/$75), so the
// version matters, not just the family.
interface Price { in: number; out: number; cacheRead: number; write5m: number; write1h: number }
const PRICING: Record<string, Price> = {
  opusNew: { in: 5,   out: 25, cacheRead: 0.5,  write5m: 6.25,  write1h: 10 },   // Opus 4.5+
  opusOld: { in: 15,  out: 75, cacheRead: 1.5,  write5m: 18.75, write1h: 30 },   // Opus 4.1 and earlier
  sonnet:  { in: 3,   out: 15, cacheRead: 0.3,  write5m: 3.75,  write1h: 6 },
  haiku45: { in: 1,   out: 5,  cacheRead: 0.1,  write5m: 1.25,  write1h: 2 },     // Haiku 4.5
  haiku35: { in: 0.8, out: 4,  cacheRead: 0.08, write5m: 1,     write1h: 1.6 },   // Haiku 3.5
};

function priceFor(model: string): Price | null {
  if (!model) return null;
  const m = model.toLowerCase();

  if (m.includes("opus")) {
    // e.g. claude-opus-4-8, claude-opus-4-1-20250805, claude-opus-4-20250514.
    const mm = m.match(/opus-(\d+)(?:-(\d+))?/);
    let major = mm ? parseInt(mm[1], 10) : 0;
    let minor = mm && mm[2] ? parseInt(mm[2], 10) : 0;
    if (major >= 100) major = 0; // legacy "3-opus-<date>" form — date matched as major
    if (minor >= 100) minor = 0; // a date snapshot (Opus 4.0 = opus-4-20250514), not a minor
    const isNew = major > 4 || (major === 4 && minor >= 5);
    return isNew ? PRICING.opusNew : PRICING.opusOld;
  }

  if (m.includes("sonnet")) return PRICING.sonnet; // all 3.x/4.x Sonnet share $3/$15

  if (m.includes("haiku")) {
    if (m.includes("3-5-haiku")) return PRICING.haiku35; // claude-3-5-haiku-…
    return PRICING.haiku45; // Haiku 4.5 (claude-haiku-4-5-…) and newer
  }

  return null; // <synthetic> and unknowns cost nothing
}

interface Totals {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  cost: number;
  active: number;  // seconds of active agent time (summed inter-message gaps < IDLE_GAP)
  path: string;
  models: Record<string, { tokens: number; cost: number }>; // model -> tokens + cost
}

function newTotals(path: string): Totals {
  return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, active: 0, path, models: {} };
}

// model-name -> {tokens,cost} map → display list, cost-rounded, zero-usage
// (<synthetic>) dropped, sorted by cost then tokens.
function modelListFrom(m: Map<string, { tokens: number; cost: number }>) {
  return Array.from(m.entries())
    .map(([name, v]) => ({ name, tokens: v.tokens, cost: Math.round(v.cost * 100) / 100 }))
    .filter((x) => x.tokens > 0)
    .sort((a, b) => b.cost - a.cost || b.tokens - a.tokens);
}

// Gaps between consecutive messages in a session shorter than this count as
// active agent time; longer gaps are treated as idle (session left open).
const IDLE_GAP_MS = 300_000; // 5 minutes

function localDay(ts: number): string {
  const d = new Date(ts);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function windowStartDay(): string {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - (WINDOW_DAYS - 1));
  return localDay(d.getTime());
}

// Read appended bytes [offset, size) of a file, returning complete lines and
// the new offset (pointing at the start of any trailing partial line).
function readAppended(path: string, offset: number): { lines: string[]; offset: number } {
  let fd: number | null = null;
  try {
    const size = statSync(path).size;
    if (size <= offset) return { lines: [], offset };
    const len = size - offset;
    const buf = Buffer.allocUnsafe(len);
    fd = openSync(path, "r");
    readSync(fd, buf, 0, len, offset);
    const text = buf.toString("utf-8");
    const lastNL = text.lastIndexOf("\n");
    if (lastNL < 0) return { lines: [], offset }; // no complete line yet
    const complete = text.slice(0, lastNL);
    const consumed = Buffer.byteLength(complete, "utf-8") + 1; // +1 for the \n
    return { lines: complete.split("\n"), offset: offset + consumed };
  } catch {
    return { lines: [], offset };
  } finally {
    if (fd !== null) closeSync(fd);
  }
}

// Collect every .jsonl under `dir`, recursing into subdirectories — subagent
// and workflow transcripts live in nested <session>/subagents/... folders, not
// just directly under the project dir.
function collectJsonl(dir: string, out: string[]) {
  let entries: string[];
  try { entries = readdirSync(dir); } catch { return; }
  for (const e of entries) {
    const p = join(dir, e);
    let st;
    try { st = statSync(p); } catch { continue; }
    if (st.isDirectory()) collectJsonl(p, out);
    else if (e.endsWith(".jsonl")) out.push(p);
  }
}

export function create(): DaemonModule {
  // date -> project -> totals
  const byDay = new Map<string, Map<string, Totals>>();
  const offsets = new Map<string, number>(); // filepath -> bytes consumed
  const seen = new Set<string>();             // dedup: msgId|reqId
  const fileLastTs = new Map<string, number>(); // filepath -> last message ts (ms), for active-time gaps
  let summaryCache: object | null = null;
  let timer: ReturnType<typeof setInterval> | null = null;
  let limitsCache: object | null = null;
  let limitsTimer: ReturnType<typeof setInterval> | null = null;

  // Fold the latest fetched limits into the served summary right away, without
  // waiting for the next file scan to rebuild it.
  function patchSummaryLimits() {
    if (summaryCache) (summaryCache as any).limits = limitsCache;
  }

  async function fetchLimits() {
    const token = readAccessToken();
    if (!token) { limitsCache = null; patchSummaryLimits(); return; }
    try {
      const res = await fetch(USAGE_ENDPOINT, {
        headers: { Authorization: `Bearer ${token}`, "anthropic-beta": "oauth-2025-04-20" },
      });
      if (!res.ok) {
        if (res.status === 401) limitsCache = null; // bad token; keep stale on transient errors
        patchSummaryLimits();
        return;
      }
      const d: any = await res.json();
      limitsCache = {
        fiveHour: normWindow(d.five_hour),
        sevenDay: normWindow(d.seven_day),
        sevenDayOpus: normWindow(d.seven_day_opus),
        sevenDaySonnet: normWindow(d.seven_day_sonnet),
        fetchedAt: Date.now(),
      };
    } catch {
      // network hiccup — keep the last known limits
    }
    patchSummaryLimits();
  }

  const projectCache = new Map<string, { name: string; path: string }>();
  function projectName(cwd: string | undefined, dirName: string): { name: string; path: string } {
    // Decode the dir name (path with / replaced by -) when cwd is absent.
    let path = cwd || "/" + dirName.replace(/^-/, "").replace(/-/g, "/");
    path = path.replace(/\/+$/, "");

    const cached = projectCache.get(path);
    if (cached) return cached;

    let root: string | null = null;
    // 1) deepest configured project root that contains this cwd
    for (const r of PROJECT_ROOTS) {
      if (path === r || path.startsWith(r + "/")) { root = r; break; }
    }
    // 2) else the git repo root, 3) else the cwd itself
    if (!root) root = findRepoRoot(path) || path;

    const result = { name: basename(root) || root, path: root };
    projectCache.set(path, result);
    return result;
  }

  function ingest(line: string, dirName: string, winStart: string, filePath: string) {
    if (!line || line.indexOf('"usage"') < 0) return;
    let o: any;
    try { o = JSON.parse(line); } catch { return; }
    const msg = o?.message;
    const usage = msg?.usage;
    if (!usage || o.type !== "assistant") return;

    const ts = o.timestamp ? Date.parse(o.timestamp) : NaN;
    if (!ts) return;
    const day = localDay(ts);
    if (day < winStart) return; // outside the window — ignore (offset still advances)

    // Dedup: a resumed session re-logs prior messages into the new transcript.
    const key = `${msg.id || ""}|${o.requestId || ""}`;
    if (key !== "|") {
      if (seen.has(key)) return;
      seen.add(key);
    }

    // Active agent time: the gap since the previous (deduped) message in this
    // same session file, capped so idle gaps don't count. Computed before the
    // bucket lookup so it can be attributed to this line's project/day.
    const prevTs = fileLastTs.get(filePath);
    const gap = prevTs !== undefined ? ts - prevTs : 0;
    fileLastTs.set(filePath, ts);
    const activeMs = gap > 0 && gap < IDLE_GAP_MS ? gap : 0;

    const input = usage.input_tokens || 0;
    const output = usage.output_tokens || 0;
    const cacheRead = usage.cache_read_input_tokens || 0;
    const cc = usage.cache_creation || {};
    const write5m = cc.ephemeral_5m_input_tokens ?? usage.cache_creation_input_tokens ?? 0;
    const write1h = cc.ephemeral_1h_input_tokens ?? 0;
    const cacheWrite = write5m + write1h;

    const p = priceFor(msg.model || "");
    let cost = 0;
    if (p) {
      cost = (input * p.in + output * p.out + cacheRead * p.cacheRead
            + write5m * p.write5m + write1h * p.write1h) / 1_000_000;
    }

    const { name, path } = projectName(o.cwd, dirName);
    let dayMap = byDay.get(day);
    if (!dayMap) { dayMap = new Map(); byDay.set(day, dayMap); }
    let t = dayMap.get(name);
    if (!t) { t = newTotals(path); dayMap.set(name, t); }
    t.input += input;
    t.output += output;
    t.cacheRead += cacheRead;
    t.cacheWrite += cacheWrite;
    t.cost += cost;
    t.active += activeMs / 1000;
    if (msg.model) {
      let mm = t.models[msg.model];
      if (!mm) { mm = { tokens: 0, cost: 0 }; t.models[msg.model] = mm; }
      mm.tokens += input + output + cacheRead + cacheWrite;
      mm.cost += cost;
    }
  }

  function scan() {
    if (!existsSync(PROJECTS_DIR)) return;
    const winStart = windowStartDay();
    const cutoffMs = Date.parse(winStart + "T00:00:00") - 86400_000; // 1 day slack for tz

    let dirs: string[];
    try { dirs = readdirSync(PROJECTS_DIR); } catch { return; }

    for (const dir of dirs) {
      const dirPath = join(PROJECTS_DIR, dir);
      try { if (!statSync(dirPath).isDirectory()) continue; } catch { continue; }
      const files: string[] = [];
      collectJsonl(dirPath, files); // includes nested subagent/workflow transcripts

      for (const fp of files) {
        let st;
        try { st = statSync(fp); } catch { continue; }
        // Skip files untouched before the window and never seen.
        if (st.mtimeMs < cutoffMs && !offsets.has(fp)) continue;
        const off = offsets.get(fp) || 0;
        if (st.size <= off) continue;
        const { lines, offset } = readAppended(fp, off);
        offsets.set(fp, offset);
        for (const line of lines) ingest(line, dir, winStart, fp);
      }
    }

    prune(winStart);
    buildSummary();
  }

  function prune(winStart: string) {
    for (const day of byDay.keys()) {
      if (day < winStart) byDay.delete(day);
    }
  }

  function buildSummary() {
    const today = localDay(Date.now());

    // Per-day totals + per-project & per-model breakdown (oldest -> newest), full window.
    const days: { date: string; cost: number; tokens: number; active: number; projects: any[]; models: any[] }[] = [];
    const weekProjects = new Map<string, { cost: number; tokens: number; active: number; path: string }>();
    const weekModels = new Map<string, { tokens: number; cost: number }>();
    let weekCost = 0, weekTokens = 0, weekActive = 0, maxDayCost = 0;

    for (let i = WINDOW_DAYS - 1; i >= 0; i--) {
      const d = new Date();
      d.setHours(0, 0, 0, 0);
      d.setDate(d.getDate() - i);
      const ds = localDay(d.getTime());
      const dayMap = byDay.get(ds);
      let dc = 0, dt = 0, da = 0;
      const dayProjects: { name: string; cost: number; tokens: number; active: number }[] = [];
      const dayModels = new Map<string, { tokens: number; cost: number }>();
      if (dayMap) {
        for (const [name, t] of dayMap) {
          const tok = t.input + t.output + t.cacheRead + t.cacheWrite;
          dc += t.cost; dt += tok; da += t.active;
          dayProjects.push({ name, cost: Math.round(t.cost * 100) / 100, tokens: tok, active: Math.round(t.active) });
          const wp = weekProjects.get(name) || { cost: 0, tokens: 0, active: 0, path: t.path };
          wp.cost += t.cost; wp.tokens += tok; wp.active += t.active;
          weekProjects.set(name, wp);
          for (const model in t.models) {
            const mv = t.models[model];
            const dm = dayModels.get(model) || { tokens: 0, cost: 0 };
            dm.tokens += mv.tokens; dm.cost += mv.cost; dayModels.set(model, dm);
            const wm = weekModels.get(model) || { tokens: 0, cost: 0 };
            wm.tokens += mv.tokens; wm.cost += mv.cost; weekModels.set(model, wm);
          }
        }
        dayProjects.sort((a, b) => b.cost - a.cost || b.tokens - a.tokens);
      }
      days.push({ date: ds, cost: Math.round(dc * 100) / 100, tokens: dt, active: Math.round(da), projects: dayProjects, models: modelListFrom(dayModels) });
      weekCost += dc; weekTokens += dt; weekActive += da;
      if (dc > maxDayCost) maxDayCost = dc;
    }

    // Today's per-project breakdown + per-model totals (summed across projects).
    const todayMap = byDay.get(today);
    const todayProjects: any[] = [];
    const todayModels = new Map<string, { tokens: number; cost: number }>();
    let tCost = 0, tIn = 0, tOut = 0, tCR = 0, tCW = 0, tActive = 0;
    if (todayMap) {
      for (const [name, t] of todayMap) {
        const tokens = t.input + t.output + t.cacheRead + t.cacheWrite;
        tCost += t.cost; tIn += t.input; tOut += t.output; tCR += t.cacheRead; tCW += t.cacheWrite; tActive += t.active;
        for (const model in t.models) {
          const mv = t.models[model];
          const acc = todayModels.get(model) || { tokens: 0, cost: 0 };
          acc.tokens += mv.tokens; acc.cost += mv.cost;
          todayModels.set(model, acc);
        }
        todayProjects.push({
          name, path: t.path,
          cost: Math.round(t.cost * 100) / 100,
          tokens,
          active: Math.round(t.active),
          input: t.input, output: t.output, cacheRead: t.cacheRead, cacheWrite: t.cacheWrite,
          models: Object.keys(t.models).sort((a, b) => t.models[b].tokens - t.models[a].tokens),
        });
      }
      todayProjects.sort((a, b) => b.cost - a.cost || b.tokens - a.tokens);
    }
    const todayModelList = modelListFrom(todayModels);

    summaryCache = {
      date: today,
      limits: limitsCache,
      today: {
        totalCost: Math.round(tCost * 100) / 100,
        totalTokens: tIn + tOut + tCR + tCW,
        totalActive: Math.round(tActive),
        input: tIn, output: tOut, cacheRead: tCR, cacheWrite: tCW,
        projects: todayProjects,
        models: todayModelList,
      },
      week: {
        days,
        totalCost: Math.round(weekCost * 100) / 100,
        totalTokens: weekTokens,
        totalActive: Math.round(weekActive),
        maxDayCost: Math.round(maxDayCost * 100) / 100,
        projects: Array.from(weekProjects.entries())
          .map(([name, w]) => ({ name, path: w.path, cost: Math.round(w.cost * 100) / 100, tokens: w.tokens, active: Math.round(w.active) }))
          .sort((a, b) => b.cost - a.cost || b.tokens - a.tokens),
        models: modelListFrom(weekModels),
      },
    };
  }

  return {
    name: "claude-usage",

    init(ctx: DaemonContext) {
      scan();
      fetchLimits();
      timer = setInterval(scan, SCAN_INTERVAL);
      limitsTimer = setInterval(fetchLimits, LIMITS_INTERVAL);
      ctx.signal.addEventListener("abort", () => {
        if (timer) { clearInterval(timer); timer = null; }
        if (limitsTimer) { clearInterval(limitsTimer); limitsTimer = null; }
      });
    },

    routes: {
      today: (_req: Request) => {
        if (!summaryCache) return Response.json({ error: "not ready" }, { status: 503 });
        return Response.json(summaryCache);
      },
    },

    shutdown() {
      if (timer) { clearInterval(timer); timer = null; }
      if (limitsTimer) { clearInterval(limitsTimer); limitsTimer = null; }
    },
  };
}
