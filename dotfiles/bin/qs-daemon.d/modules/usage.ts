import { Database } from "bun:sqlite";
import { readFileSync, mkdirSync, existsSync, writeFileSync } from "fs";
import { dirname, join } from "path";
import { execSync } from "child_process";
import { homedir } from "os";
import type { DaemonModule, DaemonContext } from "../types.ts";
import { todayStartSec as todayStart, nowSec, HYPR_USAGE_DIR } from "../util.ts";

const SECDAY = 86400;
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function localDateStr(sec: number): string {
  const d = new Date(sec * 1000);
  const p = (n: number) => (n < 10 ? "0" : "") + n;
  return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
}

function weekdayShort(sec: number): string {
  return WEEKDAYS[new Date(sec * 1000).getDay()];
}

function monthDay(sec: number): string {
  const d = new Date(sec * 1000);
  return MONTHS[d.getMonth()] + " " + d.getDate();
}

// Relative label for a day's local midnight: "Today" / "Yesterday" / "Thu, May 28".
function dayLabel(rangeStart: number): string {
  const diff = Math.round((todayStart() - rangeStart) / SECDAY);
  if (diff === 0) return "Today";
  if (diff === 1) return "Yesterday";
  const d = new Date(rangeStart * 1000);
  return WEEKDAYS[d.getDay()] + ", " + monthDay(rangeStart);
}

const RULES_PATH = `${process.env.XDG_CONFIG_HOME || `${homedir()}/.config`}/hypr-usage/rules.json`;
const DB_PATH = `${HYPR_USAGE_DIR}/usage.db`;
const SUMMARY_INTERVAL = 30_000;
const IDLE_TIMEOUT = 120;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface Rule {
  match: { class?: string; title?: string };
  category: string;
  subcategory: string;
}

interface Rules {
  categories: Record<string, { color: string; icon: string }>;
  rules: Rule[];
}

interface Session {
  id: number;
  windowClass: string;
  windowTitle: string;
  category: string;
  subcategory: string;
  startTime: number;
}

// ---------------------------------------------------------------------------
// Default rules
//
// The default category/rule definitions live in an external JSON file so that
// personal categorization (employer names, NSFW patterns, etc.) stays out of
// version control. `usage-rules.json` is gitignored; `usage-rules.example.json`
// is the committed template and is used as a fallback. A user override can also
// be placed at RULES_PATH (see loadRules below).
// ---------------------------------------------------------------------------

const RULES_DEFAULTS_PATH = join(import.meta.dir, "..", "usage-rules.json");
const RULES_EXAMPLE_PATH = join(import.meta.dir, "..", "usage-rules.example.json");

// Last-resort fallback if neither JSON file is present (everything -> "Other").
const FALLBACK_RULES: Rules = {
  categories: {
    Development:   { color: "#89b4fa", icon: "" },
    Communication: { color: "#a6e3a1", icon: "" },
    Entertainment: { color: "#f38ba8", icon: "" },
    Browsing:      { color: "#fab387", icon: "" },
    Productivity:  { color: "#cba6f7", icon: "" },
    System:        { color: "#94e2d5", icon: "" },
    Work:          { color: "#f9e2af", icon: "" },
    Adult:         { color: "#f2cdcd", icon: "" },
    Other:         { color: "#585b70", icon: "" },
  },
  rules: [],
};

function loadDefaultRules(): Rules {
  for (const path of [RULES_DEFAULTS_PATH, RULES_EXAMPLE_PATH]) {
    if (existsSync(path)) {
      try {
        return JSON.parse(readFileSync(path, "utf-8")) as Rules;
      } catch (e) {
        console.error("usage: default rules load error:", path, e);
      }
    }
  }
  return FALLBACK_RULES;
}

const DEFAULT_RULES: Rules = loadDefaultRules();

const SUB_ICONS: Record<string, string> = {
  Terminal: "", Editor: "", "Code Review": "", Documentation: "", AI: "󰧑",
  Chat: "󰍡", Email: "󰇰",
  Video: "󰕧", Social: "󰋕", Media: "󰎈", Music: "󰎆", Gaming: "󰊗",
  Web: "󰖟",
  Documents: "󰈙", Files: "󰉋", Office: "󰏗", Notes: "󱓧", Creative: "󰏘", Tools: "󰔨",
  Settings: "󰒓", Desktop: "󰍹",
  General: "󰦑",
  NSFW: "󰈈",
  Uncategorized: "",
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function loadRules(): Rules {
  if (existsSync(RULES_PATH)) {
    try {
      const user = JSON.parse(readFileSync(RULES_PATH, "utf-8"));
      const merged = structuredClone(DEFAULT_RULES);
      if (user.categories) Object.assign(merged.categories, user.categories);
      if (user.rules) merged.rules = user.rules;
      return merged;
    } catch (e) {
      console.error("usage: rules load error:", e);
    }
  }
  return structuredClone(DEFAULT_RULES);
}

function categorize(wclass: string, wtitle: string, rules: Rules): [string, string] {
  for (const rule of rules.rules) {
    const { class: cpat, title: tpat } = rule.match;
    if (cpat && !new RegExp(cpat, "i").test(wclass)) continue;
    if (tpat && !new RegExp(tpat, "i").test(wtitle)) continue;
    return [rule.category, rule.subcategory];
  }
  return ["Other", "Uncategorized"];
}

export function create(): DaemonModule {
  let db: Database;
  let rules: Rules;
  let activeAddr = "";
  let current: Session | null = null;
  let summaryCache: object | null = null;
  let summaryTimer: ReturnType<typeof setInterval> | null = null;

  let isIdle = false;

  let stmts: {
    insert: ReturnType<Database["prepare"]>;
    close: ReturnType<Database["prepare"]>;
    updateTitle: ReturnType<Database["prepare"]>;
  };

  // -- session management --------------------------------------------------

  function closeCurrent() {
    if (!current) return;
    stmts.close.run(Date.now() / 1000, current.id);
    current = null;
  }

  function startSession(wcls: string, wtitle: string) {
    closeCurrent(); // never leave a previous session open (e.g. seed() after resume)
    const now = Date.now() / 1000;
    const [cat, sub] = categorize(wcls, wtitle, rules);
    const result = stmts.insert.run(now, wcls, wtitle, cat, sub);
    current = {
      id: Number(result.lastInsertRowid),
      windowClass: wcls,
      windowTitle: wtitle,
      category: cat,
      subcategory: sub,
      startTime: now,
    };
  }

  function seed() {
    try {
      const out = execSync("hyprctl activewindow -j", { timeout: 2000, encoding: "utf-8" });
      if (!out.trim()) return;
      const win = JSON.parse(out);
      activeAddr = win.address || "";
      if (win.class) startSession(win.class, win.title || "");
    } catch {}
  }

  function cleanup(days = 90) {
    const cutoff = Date.now() / 1000 - days * 86400;
    db.run("DELETE FROM sessions WHERE end_time IS NOT NULL AND end_time < ?", [cutoff]);
  }

  // -- IPC handlers --------------------------------------------------------

  function onActiveWindowV2(payload: string) {
    activeAddr = payload.trim();
  }

  function onActiveWindow(payload: string) {
    // While idle (on a break) Hyprland still emits focus events (notifications,
    // focus-steals). Ignore them so they don't create phantom sessions that
    // fill the idle gap and hide the break. onResume re-seeds the real window.
    if (isIdle) return;
    const idx = payload.indexOf(",");
    const wcls = idx >= 0 ? payload.slice(0, idx) : payload;
    const wtitle = idx >= 0 ? payload.slice(idx + 1) : "";
    if (current && wcls === current.windowClass && wtitle === current.windowTitle) return;
    closeCurrent();
    if (wcls) startSession(wcls, wtitle);
    buildSummary();
  }

  function onTitleChange(payload: string) {
    if (isIdle) return;
    const idx = payload.indexOf(",");
    const addr = idx >= 0 ? payload.slice(0, idx) : payload;
    const title = idx >= 0 ? payload.slice(idx + 1) : "";
    if (addr !== activeAddr || !current || title === current.windowTitle) return;

    const [newCat, newSub] = categorize(current.windowClass, title, rules);
    if (newCat !== current.category || newSub !== current.subcategory) {
      const wcls = current.windowClass;
      closeCurrent();
      startSession(wcls, title);
      buildSummary();
    } else {
      current.windowTitle = title;
      stmts.updateTitle.run(title, current.id);
    }
  }

  function onCloseWindow(payload: string) {
    if (payload.trim() === activeAddr) {
      closeCurrent();
      activeAddr = "";
      buildSummary();
    }
  }

  function onIdle() {
    if (isIdle) return;
    isIdle = true;
    if (!current) return;
    const idleStart = Date.now() / 1000 - IDLE_TIMEOUT;
    const endTime = Math.max(current.startTime + 1, idleStart);
    stmts.close.run(endTime, current.id);
    current = null;
    buildSummary();
  }

  function onResume() {
    if (!isIdle) return;
    isIdle = false;
    seed();
    buildSummary();
  }

  function onLock() {
    isIdle = true;
    closeCurrent();
    buildSummary();
  }

  function onUnlock() {
    isIdle = false;
    seed();
    buildSummary();
  }

  // -- summary builder -----------------------------------------------------

  // Build a usage summary for an arbitrary day range. `live` means the range
  // ends "now" (the current day): only then do we report the open window, the
  // in-progress break, and the now-marker. Historical days are treated as
  // closed — clamped to rangeEnd, no current window, no ongoing break.
  function computeSummary(rangeStart: number, rangeEnd: number, live: boolean): object {
    rules = loadRules();

    const now = live ? nowSec() : rangeEnd;
    const ts = rangeStart;
    const liveCurrent = live ? current : null;

    const rows = db
      .prepare(`
        SELECT category, subcategory, window_class, start_time,
               COALESCE(end_time, ?) AS end_time
        FROM sessions
        WHERE start_time < ? AND COALESCE(end_time, ?) > ?
      `)
      .all(now, now, now, ts) as { category: string; subcategory: string; window_class: string; start_time: number; end_time: number }[];

    const catData: Record<string, { s: number; subs: Record<string, number> }> = {};
    const appData: Record<string, { s: number; cat: string }> = {};
    let total = 0;

    for (const row of rows) {
      const secs = Math.max(0, Math.min(row.end_time, now) - Math.max(row.start_time, ts));
      total += secs;

      const cd = (catData[row.category] ??= { s: 0, subs: {} });
      cd.s += secs;
      cd.subs[row.subcategory] = (cd.subs[row.subcategory] || 0) + secs;

      const ad = (appData[row.window_class] ??= { s: 0, cat: row.category });
      ad.s += secs;
    }

    const categories = Object.entries(catData)
      .sort((a, b) => b[1].s - a[1].s)
      .map(([name, d]) => {
        const meta = rules.categories[name] || { color: "#585b70", icon: "" };
        const subcategories = Object.entries(d.subs)
          .sort((a, b) => b[1] - a[1])
          .map(([sn, ss]) => ({
            name: sn,
            icon: SUB_ICONS[sn] || "",
            seconds: Math.round(ss),
            percent: d.s > 0 ? Math.round((1000 * ss) / d.s) / 10 : 0,
          }));
        return {
          name,
          icon: meta.icon,
          color: meta.color,
          seconds: Math.round(d.s),
          percent: total > 0 ? Math.round((1000 * d.s) / total) / 10 : 0,
          subcategories,
        };
      });

    const topApps = Object.entries(appData)
      .sort((a, b) => b[1].s - a[1].s)
      .slice(0, 10)
      .map(([cls, d]) => ({ class: cls, seconds: Math.round(d.s), category: d.cat }));

    let currentWindow = null;
    if (liveCurrent) {
      currentWindow = {
        class: liveCurrent.windowClass,
        title: liveCurrent.windowTitle,
        category: liveCurrent.category,
        subcategory: liveCurrent.subcategory,
        since: new Date(liveCurrent.startTime * 1000).toISOString(),
      };
    }

    const sorted = [...rows].sort((a, b) => a.start_time - b.start_time);
    const merged: { s: number; e: number; cat: string; col: string }[] = [];
    let prev: { s: number; e: number; cat: string; col: string } | null = null;
    for (const row of sorted) {
      const s = Math.round(Math.max(row.start_time, ts) - ts);
      const e = Math.round(Math.min(row.end_time, now) - ts);
      if (e - s < 3) continue;
      const col = rules.categories[row.category]?.color || "#585b70";
      if (prev && prev.cat === row.category && (s - prev.e) < 120) {
        prev.e = e;
      } else {
        if (prev) merged.push(prev);
        prev = { s, e, cat: row.category, col };
      }
    }
    if (prev) merged.push(prev);
    const blocks = merged.map(b => ({ s: b.s, e: b.e, col: b.col }));

    // Fine-grained segments (merged by subcategory) for timeline hover detail.
    type Seg = { s: number; e: number; cat: string; sub: string; cls: string; col: string };
    const segments: Seg[] = [];
    let pseg: Seg | null = null;
    for (const row of sorted) {
      const s = Math.round(Math.max(row.start_time, ts) - ts);
      const e = Math.round(Math.min(row.end_time, now) - ts);
      if (e - s < 2) continue;
      const col = rules.categories[row.category]?.color || "#585b70";
      if (pseg && pseg.cat === row.category && pseg.sub === row.subcategory && (s - pseg.e) < 60) {
        pseg.e = e;
      } else {
        if (pseg) segments.push(pseg);
        pseg = { s, e, cat: row.category, sub: row.subcategory, cls: row.window_class, col };
      }
    }
    if (pseg) segments.push(pseg);

    const tlStart = blocks.length > 0 ? Math.floor(blocks[0].s / 3600) * 3600 : 0;
    const tlSpan = Math.round(now - ts) - tlStart;

    // -- continuous-usage streak ("time without break") -------------------
    // A break is BREAK_GAP seconds of no usage between activity intervals.
    // We accumulate *active* time since the most recent break — idle gaps
    // shorter than a break don't inflate the streak (and a trivial blip
    // before a near-break gap can't make a fresh sit-down look long).
    const BREAK_GAP = 300; // 5 minutes
    let streakActive = 0;
    let streakStart: number | null = null;
    let lastEnd: number | null = null;
    // Each gap >= BREAK_GAP between activity intervals is a break.
    const breaks: { start: number; end: number }[] = [];
    for (const row of sorted) {
      const s = Math.max(row.start_time, ts);
      const e = Math.min(row.end_time, now);
      if (e <= s) continue;
      if (lastEnd !== null && s - lastEnd >= BREAK_GAP) {
        breaks.push({ start: lastEnd, end: s });
      }
      if (lastEnd === null || s - lastEnd >= BREAK_GAP) {
        streakActive = 0;
        streakStart = s;
      }
      streakActive += e - s;
      lastEnd = Math.max(lastEnd ?? e, e);
    }

    let streakSeconds = 0;
    let onBreak = false;
    let streakSince: string | null = null;
    if (streakStart !== null && lastEnd !== null) {
      if (live && !liveCurrent && now - lastEnd >= BREAK_GAP) {
        // No active window and the last activity was over a break ago.
        onBreak = true;
      } else {
        streakSeconds = Math.round(streakActive);
        streakSince = new Date(streakStart * 1000).toISOString();
      }
    }

    // The current idle gap is itself an (in-progress) break (live day only).
    if (onBreak && lastEnd !== null) breaks.push({ start: lastEnd, end: now });

    const latest = breaks.length > 0 ? breaks[breaks.length - 1] : null;
    const lastBreak = latest
      ? {
          since: new Date(latest.start * 1000).toISOString(),
          seconds: Math.round(latest.end - latest.start),
          ongoing: onBreak, // the in-progress break is always pushed last
        }
      : null;

    return {
      date: localDateStr(ts),
      dateLabel: dayLabel(ts),
      live,
      totalSeconds: Math.round(total),
      streakSeconds: Math.round(streakSeconds),
      streakSince,
      onBreak,
      breakCount: breaks.length,
      lastBreak,
      categories,
      topApps,
      current: currentWindow,
      timeline: { start: tlStart, span: tlSpan, blocks, segments },
    };
  }

  // Refresh the cached live summary for the current day (widget + today route).
  function buildSummary() {
    summaryCache = computeSummary(todayStart(), nowSec(), true);
  }

  // Aggregate categories / top apps / per-day totals over a rolling 7-day window.
  // offset 0 = the 7 days ending today; each step back is the previous 7 days.
  function computeWeek(offset: number): object {
    const t0 = todayStart();
    const lastDayStart = t0 - offset * 7 * SECDAY;
    const firstDayStart = lastDayStart - 6 * SECDAY;
    const live = offset === 0;
    const rangeEnd = live ? nowSec() : lastDayStart + SECDAY;

    const agg = computeSummary(firstDayStart, rangeEnd, false) as {
      totalSeconds: number; categories: unknown; topApps: unknown;
    };

    // Per-day buckets for the bar chart, split by category so each bar can be
    // rendered as a colour-segmented stack.
    const rows = db
      .prepare(`
        SELECT category, start_time, COALESCE(end_time, ?) AS end_time
        FROM sessions
        WHERE start_time < ? AND COALESCE(end_time, ?) > ?
      `)
      .all(rangeEnd, rangeEnd, rangeEnd, firstDayStart) as { category: string; start_time: number; end_time: number }[];

    const days = [];
    for (let i = 0; i < 7; i++) {
      const ds = firstDayStart + i * SECDAY;
      const de = Math.min(ds + SECDAY, rangeEnd);
      const catSec: Record<string, number> = {};
      let sec = 0;
      for (const r of rows) {
        const overlap = Math.max(0, Math.min(r.end_time, de) - Math.max(r.start_time, ds));
        if (overlap <= 0) continue;
        sec += overlap;
        catSec[r.category] = (catSec[r.category] || 0) + overlap;
      }
      // Largest category last → it anchors the bottom of the stacked bar.
      const cats = Object.entries(catSec)
        .sort((x, y) => x[1] - y[1])
        .map(([name, s]) => ({
          color: rules.categories[name]?.color || "#585b70",
          seconds: Math.round(s),
        }));
      days.push({
        date: localDateStr(ds),
        label: weekdayShort(ds),
        seconds: Math.round(sec),
        today: ds === t0,
        cats,
      });
    }

    const a = firstDayStart;
    const b = lastDayStart;
    const rangeLabel = new Date(a * 1000).getMonth() === new Date(b * 1000).getMonth()
      ? MONTHS[new Date(a * 1000).getMonth()] + " " + new Date(a * 1000).getDate() + " – " + new Date(b * 1000).getDate()
      : monthDay(a) + " – " + monthDay(b);

    return {
      mode: "week",
      live,
      rangeStart: firstDayStart,
      rangeEnd,
      rangeLabel,
      totalSeconds: agg.totalSeconds,
      avgSeconds: Math.round(agg.totalSeconds / 7),
      categories: agg.categories,
      topApps: agg.topApps,
      days,
    };
  }

  // -- module export -------------------------------------------------------

  return {
    name: "usage",

    init(ctx: DaemonContext) {
      mkdirSync(HYPR_USAGE_DIR, { recursive: true });

      if (!existsSync(RULES_PATH)) {
        mkdirSync(dirname(RULES_PATH), { recursive: true });
        writeFileSync(RULES_PATH, JSON.stringify(DEFAULT_RULES, null, 2));
      }

      db = new Database(DB_PATH);
      db.run("PRAGMA journal_mode=WAL");
      db.run(`
        CREATE TABLE IF NOT EXISTS sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          start_time REAL NOT NULL,
          end_time REAL,
          window_class TEXT NOT NULL DEFAULT '',
          window_title TEXT NOT NULL DEFAULT '',
          category TEXT NOT NULL DEFAULT 'Other',
          subcategory TEXT NOT NULL DEFAULT 'Uncategorized'
        )
      `);
      db.run("CREATE INDEX IF NOT EXISTS idx_start ON sessions(start_time)");

      stmts = {
        insert: db.prepare("INSERT INTO sessions(start_time,window_class,window_title,category,subcategory) VALUES(?,?,?,?,?)"),
        close: db.prepare("UPDATE sessions SET end_time=? WHERE id=?"),
        updateTitle: db.prepare("UPDATE sessions SET window_title=? WHERE id=?"),
      };

      rules = loadRules();

      // Close any sessions left open from a previous daemon run
      db.run("UPDATE sessions SET end_time = start_time + 300 WHERE end_time IS NULL");

      seed();
      cleanup();
      buildSummary();

      summaryTimer = setInterval(() => buildSummary(), SUMMARY_INTERVAL);

      ctx.signal.addEventListener("abort", () => {
        if (summaryTimer) {
          clearInterval(summaryTimer);
          summaryTimer = null;
        }
      });

      // Subscribe to HyprIPC events
      ctx.hyprIPC.on("activewindowv2", onActiveWindowV2);
      ctx.hyprIPC.on("activewindow", onActiveWindow);
      ctx.hyprIPC.on("windowtitlev2", onTitleChange);
      ctx.hyprIPC.on("closewindow", onCloseWindow);
      ctx.hyprIPC.on("lockscreen", (data: string) => {
        if (data === "1") onLock();
        else if (data === "0") onUnlock();
      });
    },

    routes: {
      today: (_req: Request) => {
        if (!summaryCache) {
          return Response.json({ error: "not ready" }, { status: 503 });
        }
        return Response.json(summaryCache);
      },
      // Single day, `offset` days back (0 = today, served from the live cache).
      day: (req: Request) => {
        const offset = Math.max(0, parseInt(new URL(req.url).searchParams.get("offset") || "0", 10) || 0);
        if (offset === 0) {
          if (!summaryCache) return Response.json({ error: "not ready" }, { status: 503 });
          return Response.json(summaryCache);
        }
        const dayStart = todayStart() - offset * SECDAY;
        return Response.json(computeSummary(dayStart, dayStart + SECDAY, false));
      },
      // Rolling 7-day window, `offset` weeks back (0 = last 7 days).
      week: (req: Request) => {
        const offset = Math.max(0, parseInt(new URL(req.url).searchParams.get("offset") || "0", 10) || 0);
        return Response.json(computeWeek(offset));
      },
      idle: (_req: Request) => {
        onIdle();
        return new Response("ok");
      },
      resume: (_req: Request) => {
        onResume();
        return new Response("ok");
      },
    },

    shutdown() {
      if (summaryTimer) {
        clearInterval(summaryTimer);
        summaryTimer = null;
      }
      closeCurrent();
      buildSummary();
      db?.close();
    },
  };
}
