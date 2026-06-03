import { readdirSync, readFileSync, statSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import type { DaemonModule } from "../types.ts";

const CAL_ROOT = join(homedir(), ".calendars");

const KHAL_FIELDS = [
  "title", "start", "end", "calendar", "description",
  "location", "all-day", "uid",
];

const LINK_PATTERNS = [
  /https:\/\/meet\.google\.com\/[A-Za-z0-9_\-?=&]+/,
  /https:\/\/[A-Za-z0-9.\-]*zoom\.us\/[A-Za-z0-9_\-?=&\/.]+/,
  /https:\/\/teams\.(?:microsoft|live)\.com\/[^\s"<>]+/,
  /https:\/\/[A-Za-z0-9.\-]*webex\.com\/[^\s"<>]+/,
];

const BOILERPLATE_PREFIXES = [
  "-::", "join with google meet", "or dial:", "more phone numbers:",
  "learn more about meet", "please do not edit",
];

const PLACEHOLDER_ORGANIZERS = new Set([
  "unknownorganizer@calendar.google.com",
]);

const STATUS_PRIORITY: Record<string, number> = {
  ACCEPTED: 3,
  DECLINED: 2,
  TENTATIVE: 1,
  "NEEDS-ACTION": 0,
};

const ZERO_ATTENDEES = {
  accepted: 0, declined: 0, tentative: 0, needsAction: 0, total: 0,
};

// ── Helpers ──────────────────────────────────────────────────────────────────

function extractMeetingLink(desc: string): string {
  if (!desc) return "";
  for (const p of LINK_PATTERNS) {
    const m = desc.match(p);
    if (m) return m[0];
  }
  return "";
}

function cleanDescription(desc: string, limit = 240): string {
  if (!desc) return "";
  const out: string[] = [];
  for (const line of desc.split(/\r?\n/)) {
    const s = line.trim();
    if (!s) continue;
    const low = s.toLowerCase();
    if (BOILERPLATE_PREFIXES.some((p) => low.startsWith(p))) continue;
    if (low.includes("meet.google.com")) continue;
    if (low.includes("google.com/a/users")) continue;
    out.push(s);
  }
  let text = out.join(" ");
  if (text.length > limit) {
    text = text.slice(0, limit - 1).trimEnd() + "…";
  }
  return text;
}

/** Join RFC 5545 continuation lines (lines starting with space or tab). */
function unfold(text: string): string[] {
  const out: string[] = [];
  for (const line of text.split(/\r?\n/)) {
    if ((line.startsWith(" ") || line.startsWith("\t")) && out.length > 0) {
      out[out.length - 1] += line.slice(1);
    } else {
      out.push(line);
    }
  }
  return out;
}

// ── ICS reading ──────────────────────────────────────────────────────────────

/** Per-request cache: cleared at the start of each handler call. */
let icsCache = new Map<string, string[]>();

function isDir(p: string): boolean {
  try { return statSync(p).isDirectory(); } catch { return false; }
}

/**
 * Return every ICS text under `calendar` whose base UID matches `uid`.
 * Google-synced recurring events split master and RECURRENCE-ID overrides
 * into separate .ics files; we union them.
 */
function readIcsAll(calendar: string, uid: string): string[] {
  const cacheKey = `${calendar}\0${uid}`;
  const cached = icsCache.get(cacheKey);
  if (cached) return cached;

  const base = uid.split("_R", 1)[0];
  if (!base) { icsCache.set(cacheKey, []); return []; }

  const needle = `UID:${base}`;
  const matches: string[] = [];

  let accounts: string[];
  try { accounts = readdirSync(CAL_ROOT); } catch { accounts = []; }

  for (const account of accounts) {
    const accountPath = join(CAL_ROOT, account);
    if (!isDir(accountPath)) continue;
    const calDir = join(accountPath, calendar);
    if (!isDir(calDir)) continue;

    let entries: string[];
    try { entries = readdirSync(calDir); } catch { continue; }

    for (const entry of entries) {
      if (!entry.endsWith(".ics")) continue;
      const icsPath = join(calDir, entry);
      let text: string;
      try { text = readFileSync(icsPath, "utf-8"); } catch { continue; }
      if (text.includes(needle)) {
        matches.push(text);
      }
    }
  }

  icsCache.set(cacheKey, matches);
  return matches;
}

// ── VEVENT parsing ───────────────────────────────────────────────────────────

interface VEvent {
  recurrenceId: string;
  isOverride: boolean;
  organizer: string;
  attendees: string[];
}

function attendeeEmail(line: string): string {
  const m = line.match(/mailto:([^\s,;]+)/i);
  return m ? m[1].toLowerCase() : "";
}

function attendeeStatus(line: string): string {
  const m = line.match(/PARTSTAT=([A-Z\-]+)/);
  return m ? m[1].toUpperCase() : "NEEDS-ACTION";
}

function collectVevents(icsTexts: string[]): VEvent[] {
  const out: VEvent[] = [];
  for (const ics of icsTexts) {
    const lines = unfold(ics);
    let cur: VEvent | null = null;
    for (const ln of lines) {
      if (ln === "BEGIN:VEVENT") {
        cur = {
          recurrenceId: "",
          isOverride: false,
          organizer: "",
          attendees: [],
        };
      } else if (ln === "END:VEVENT") {
        if (cur) { out.push(cur); cur = null; }
      } else if (cur) {
        if (ln.startsWith("ATTENDEE")) {
          cur.attendees.push(ln);
        } else if (ln.startsWith("ORGANIZER") && !cur.organizer) {
          const m = ln.match(/mailto:([^\s,;]+)/i);
          if (m) cur.organizer = m[1].toLowerCase();
        } else if (ln.startsWith("RECURRENCE-ID")) {
          cur.isOverride = true;
          const m = ln.match(/:([0-9T]+)$/);
          if (m) cur.recurrenceId = m[1];
        }
      }
    }
  }
  return out;
}

/**
 * Compute attendee counts for a (possibly recurring) event.
 *
 * Roster = attendees of the latest RECURRENCE-ID override, else master VEVENT.
 * Status = strongest RSVP that person ever gave across the series.
 * Organizer is always counted as implicit ACCEPTED.
 */
function parseAttendees(icsTexts: string[]): typeof ZERO_ATTENDEES {
  if (icsTexts.length === 0) return { ...ZERO_ATTENDEES };

  const vevents = collectVevents(icsTexts);
  if (vevents.length === 0) return { ...ZERO_ATTENDEES };

  // Roster source: latest override by recurrenceId, else master
  const overrides = vevents.filter((v) => v.isOverride);
  let rosterSrc: VEvent;
  if (overrides.length > 0) {
    overrides.sort((a, b) => (b.recurrenceId > a.recurrenceId ? 1 : -1));
    rosterSrc = overrides[0];
  } else {
    rosterSrc = vevents.find((v) => !v.isOverride) ?? vevents[0];
  }

  const roster: string[] = [];
  const seen = new Set<string>();
  for (const ln of rosterSrc.attendees) {
    const email = attendeeEmail(ln);
    if (email && !seen.has(email)) {
      seen.add(email);
      roster.push(email);
    }
  }

  let organizerEmail = rosterSrc.organizer
    || vevents.find((v) => v.organizer)?.organizer
    || "";
  if (PLACEHOLDER_ORGANIZERS.has(organizerEmail)) organizerEmail = "";
  if (organizerEmail && !seen.has(organizerEmail)) {
    seen.add(organizerEmail);
    roster.push(organizerEmail);
  }

  // Strongest status ever seen across every VEVENT
  const best = new Map<string, string>();
  for (const v of vevents) {
    for (const ln of v.attendees) {
      const email = attendeeEmail(ln);
      if (!seen.has(email)) continue;
      const status = attendeeStatus(ln);
      const prev = best.get(email);
      if (prev === undefined || STATUS_PRIORITY[status] > STATUS_PRIORITY[prev]) {
        best.set(email, status);
      }
    }
  }

  if (organizerEmail) best.set(organizerEmail, "ACCEPTED");

  const counts = { accepted: 0, declined: 0, tentative: 0, needsAction: 0 };
  for (const email of roster) {
    const status = best.get(email) ?? "NEEDS-ACTION";
    if (status === "ACCEPTED") counts.accepted++;
    else if (status === "DECLINED") counts.declined++;
    else if (status === "TENTATIVE") counts.tentative++;
    else counts.needsAction++;
  }

  return { ...counts, total: roster.length };
}

// ── khal runner ──────────────────────────────────────────────────────────────

function runKhal(span: string): Record<string, unknown>[] {
  const cmd = ["khal", "list"];
  for (const f of KHAL_FIELDS) {
    cmd.push("--json", f);
  }
  cmd.push("today", span);

  const proc = Bun.spawnSync(cmd, { stdout: "pipe", stderr: "pipe" });
  const stdout = proc.stdout.toString();

  const events: Record<string, unknown>[] = [];
  for (const rawLine of stdout.split("\n")) {
    const line = rawLine.trim();
    if (!line || line === "[]") continue;
    try {
      const parsed = JSON.parse(line);
      if (Array.isArray(parsed)) events.push(...parsed);
    } catch {
      continue;
    }
  }
  return events;
}

// ── Pipeline ─────────────────────────────────────────────────────────────────

interface EnrichedEvent {
  title: string;
  start: string;
  end: string;
  calendar: string;
  location: string;
  allDay: boolean;
  uid: string;
  description: string;
  meetingLink: string;
  attendees: typeof ZERO_ATTENDEES;
}

function enrich(e: Record<string, unknown>): EnrichedEvent {
  const calendar = (e.calendar as string) ?? "";
  const uid = (e.uid as string) ?? "";
  const icsTexts = readIcsAll(calendar, uid);
  const descRaw = (e.description as string) ?? "";
  return {
    title: ((e.title as string) ?? "").trim(),
    start: (e.start as string) ?? "",
    end: (e.end as string) ?? "",
    calendar,
    location: (e.location as string) ?? "",
    allDay: e["all-day"] === "True",
    uid,
    description: cleanDescription(descRaw),
    meetingLink: extractMeetingLink(descRaw),
    attendees: parseAttendees(icsTexts),
  };
}

function dedupeByUid(events: Record<string, unknown>[]): Record<string, unknown>[] {
  const seen = new Set<string>();
  const out: Record<string, unknown>[] = [];
  for (const e of events) {
    const uid = (e.uid as string) ?? "";
    if (!uid) { out.push(e); continue; }
    const key = `${uid}\0${(e.start as string) ?? ""}\0${(e.end as string) ?? ""}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(e);
  }
  return out;
}

// ── Module ───────────────────────────────────────────────────────────────────

export function create(): DaemonModule {
  return {
    name: "calendar",

    init() {},

    routes: {
      agenda: async (req: Request): Promise<Response> => {
        const url = new URL(req.url);
        const span = url.searchParams.get("span") || "14d";

        // Clear per-request ICS cache
        icsCache = new Map();

        try {
          const raw = runKhal(span);
          const deduped = dedupeByUid(raw);
          const events = deduped.map(enrich);
          return Response.json(events);
        } catch (e: any) {
          return Response.json(
            { error: e.message || "unknown error", events: [] },
            { status: 500 },
          );
        }
      },
    },
  };
}
