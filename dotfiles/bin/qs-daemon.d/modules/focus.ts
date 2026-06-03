import { Database } from "bun:sqlite";
import { mkdirSync } from "fs";
import { execFile } from "child_process";
import type { DaemonModule, DaemonContext } from "../types.ts";
import { nowSec as now, todayStartSec as todayStart, HYPR_USAGE_DIR } from "../util.ts";

const DB_PATH = `${HYPR_USAGE_DIR}/focus.db`;
const MAX_DURATION = 12 * 3600; // sanity clamp (12h)

interface ActiveFocus {
  id: number;
  startTime: number;        // epoch seconds
  plannedSeconds: number;   // planned duration
  label: string;
  endAt: number | null;     // epoch seconds when it completes; null while paused
  paused: boolean;
  remainingWhenPaused: number;
  pausedAccum: number;      // total paused seconds accumulated
  pauseStartedAt: number | null;
}

export function create(): DaemonModule {
  let db: Database;
  let active: ActiveFocus | null = null;
  let completeTimer: ReturnType<typeof setTimeout> | null = null;

  let stmts: {
    insert: ReturnType<Database["prepare"]>;
    finish: ReturnType<Database["prepare"]>;
  };

  // -- completion timer ----------------------------------------------------

  function clearCompleteTimer() {
    if (completeTimer) {
      clearTimeout(completeTimer);
      completeTimer = null;
    }
  }

  function scheduleComplete() {
    clearCompleteTimer();
    if (!active || active.paused || active.endAt === null) return;
    const ms = Math.max(0, (active.endAt - now()) * 1000);
    completeTimer = setTimeout(() => finish("completed", true), ms);
  }

  // -- session lifecycle ---------------------------------------------------

  function finish(status: "completed" | "cancelled", notify = false) {
    if (!active) return;
    const t = now();
    let pausedAccum = active.pausedAccum;
    if (active.paused && active.pauseStartedAt !== null) {
      pausedAccum += t - active.pauseStartedAt;
    }
    stmts.finish.run(t, Math.round(pausedAccum), status, active.id);
    const label = active.label;
    active = null;
    clearCompleteTimer();
    if (notify && status === "completed") sendNotification(label);
  }

  function sendNotification(label: string) {
    const body = label ? `“${label}” is done.` : "Your focus session is done.";
    execFile(
      "notify-send",
      ["-a", "Focus", "-u", "normal", "-i", "alarm-symbolic", "Focus complete", body],
      () => {},
    );
  }

  function startSession(plannedSeconds: number, label: string) {
    if (active) finish("cancelled");
    const t = now();
    const planned = Math.max(1, Math.min(MAX_DURATION, Math.round(plannedSeconds)));
    const result = stmts.insert.run(t, planned, label);
    active = {
      id: Number(result.lastInsertRowid),
      startTime: t,
      plannedSeconds: planned,
      label,
      endAt: t + planned,
      paused: false,
      remainingWhenPaused: planned,
      pausedAccum: 0,
      pauseStartedAt: null,
    };
    scheduleComplete();
  }

  function pause() {
    if (!active || active.paused) return;
    const t = now();
    active.remainingWhenPaused = Math.max(0, (active.endAt ?? t) - t);
    active.paused = true;
    active.pauseStartedAt = t;
    active.endAt = null;
    clearCompleteTimer();
  }

  function resume() {
    if (!active || !active.paused) return;
    const t = now();
    if (active.pauseStartedAt !== null) active.pausedAccum += t - active.pauseStartedAt;
    active.paused = false;
    active.pauseStartedAt = null;
    active.endAt = t + active.remainingWhenPaused;
    scheduleComplete();
  }

  // -- serialisation -------------------------------------------------------

  function state() {
    if (!active) return { active: false };
    const t = now();
    const remaining = active.paused
      ? active.remainingWhenPaused
      : Math.max(0, (active.endAt ?? t) - t);
    return {
      active: true,
      id: active.id,
      paused: active.paused,
      label: active.label,
      startTime: active.startTime,
      plannedSeconds: active.plannedSeconds,
      endAt: active.endAt,
      remaining: Math.round(remaining),
    };
  }

  function todayBlocks() {
    const ts = todayStart();
    const t = now();
    const rows = db
      .prepare(`
        SELECT start_time, COALESCE(end_time, ?) AS end_time, status, label
        FROM focus_sessions
        WHERE end_time IS NULL OR end_time >= ?
        ORDER BY start_time ASC
      `)
      .all(t, ts) as { start_time: number; end_time: number; status: string; label: string }[];

    const blocks = rows
      .map((r) => ({
        s: Math.round(Math.max(r.start_time, ts) - ts),
        e: Math.round(Math.min(r.end_time, t) - ts),
        status: r.status,
        label: r.label,
      }))
      .filter((b) => b.e > b.s);

    return { date: new Date().toISOString().slice(0, 10), blocks };
  }

  function history(limit: number) {
    const rows = db
      .prepare(`
        SELECT id, start_time, end_time, planned_seconds, paused_seconds, label, status
        FROM focus_sessions
        ORDER BY start_time DESC
        LIMIT ?
      `)
      .all(limit) as {
        id: number; start_time: number; end_time: number | null;
        planned_seconds: number; paused_seconds: number; label: string; status: string;
      }[];

    return rows.map((r) => ({
      id: r.id,
      start: new Date(r.start_time * 1000).toISOString(),
      end: r.end_time ? new Date(r.end_time * 1000).toISOString() : null,
      plannedSeconds: Math.round(r.planned_seconds),
      activeSeconds: r.end_time
        ? Math.max(0, Math.round(r.end_time - r.start_time - r.paused_seconds))
        : 0,
      label: r.label,
      status: r.status,
    }));
  }

  // -- module export -------------------------------------------------------

  return {
    name: "focus",

    init(_ctx: DaemonContext) {
      mkdirSync(HYPR_USAGE_DIR, { recursive: true });

      db = new Database(DB_PATH);
      db.run("PRAGMA journal_mode=WAL");
      db.run(`
        CREATE TABLE IF NOT EXISTS focus_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          start_time REAL NOT NULL,
          end_time REAL,
          planned_seconds REAL NOT NULL,
          paused_seconds REAL NOT NULL DEFAULT 0,
          label TEXT NOT NULL DEFAULT '',
          status TEXT NOT NULL DEFAULT 'active'
        )
      `);
      db.run("CREATE INDEX IF NOT EXISTS idx_focus_start ON focus_sessions(start_time)");

      // Any session left 'active' from a previous daemon run was interrupted.
      db.run(`
        UPDATE focus_sessions
        SET status='interrupted',
            end_time=COALESCE(end_time, MIN(start_time + planned_seconds, ?))
        WHERE status='active'
      `, [now()]);

      stmts = {
        insert: db.prepare(
          "INSERT INTO focus_sessions(start_time,planned_seconds,label,status) VALUES(?,?,?,'active')",
        ),
        finish: db.prepare(
          "UPDATE focus_sessions SET end_time=?, paused_seconds=?, status=? WHERE id=?",
        ),
      };
    },

    routes: {
      start: (req: Request) => {
        const url = new URL(req.url);
        const duration = parseFloat(url.searchParams.get("duration") || "0");
        const label = (url.searchParams.get("label") || "").slice(0, 120);
        if (!(duration > 0)) {
          return Response.json({ error: "invalid duration" }, { status: 400 });
        }
        startSession(duration, label);
        return Response.json(state());
      },
      stop: () => {
        finish("cancelled");
        return Response.json(state());
      },
      pause: () => {
        pause();
        return Response.json(state());
      },
      resume: () => {
        resume();
        return Response.json(state());
      },
      complete: () => {
        // UI reached zero; daemon may already have fired its own timer.
        finish("completed", false);
        return Response.json(state());
      },
      state: () => Response.json(state()),
      today: () => Response.json(todayBlocks()),
      history: (req: Request) => {
        const url = new URL(req.url);
        const limit = Math.max(1, Math.min(100, parseInt(url.searchParams.get("limit") || "15", 10)));
        return Response.json({ sessions: history(limit) });
      },
    },

    shutdown() {
      // Persist an in-flight session as interrupted so records stay accurate.
      if (active) {
        const t = now();
        let pausedAccum = active.pausedAccum;
        if (active.paused && active.pauseStartedAt !== null) pausedAccum += t - active.pauseStartedAt;
        stmts.finish.run(t, Math.round(pausedAccum), "interrupted", active.id);
        active = null;
      }
      clearCompleteTimer();
      db?.close();
    },
  };
}
