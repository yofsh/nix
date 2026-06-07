// Shared process-identity helpers. Used to GROUP processes by application:
// procmon's cpu/mem rings (main thread) and the scanner worker's per-app traffic
// pipeline both label a pid the same way, so this lives in one place.

import { readFileSync, readlinkSync } from "fs";

// A detected process: display name + pid + run params (for tooltips).
export interface ProcEntry { name: string; pid: number; params: string }

// Run params of a pid — argv after argv[0] (the exe path is dropped; the name
// already conveys it), space-joined and capped at `max` chars. "" if none.
export function procParams(pid: number | string, max = 60): string {
  try {
    const args = readFileSync(`/proc/${pid}/cmdline`).toString("utf-8").split("\0").filter(Boolean);
    const params = args.slice(1).join(" ");
    return params.length > max ? params.slice(0, max - 1) + "…" : params;
  } catch { return ""; }
}

// Interpreter/runtime exe basenames whose real identity is the script they run.
// Grouping purely by exe basename collapses every bun/node/python app into one
// row (e.g. the qs-daemon and an unrelated bun server both show as "bun"); for
// these we re-key by the script's basename instead so they separate out.
export const INTERPRETERS = new Set([
  "bun", "node", "deno", "python", "python3", "python2", "ruby", "perl", "electron",
]);

export function commOf(pid: number): string {
  try { return readFileSync(`/proc/${pid}/comm`, "utf-8").trim(); } catch { return String(pid); }
}

// First bare (non-flag) cmdline arg after argv[0] is the script an interpreter
// runs; its basename is a far better label than the runtime's. "" if none.
function scriptKey(pid: number): string {
  let raw: string;
  try { raw = readFileSync(`/proc/${pid}/cmdline`, "utf-8"); } catch { return ""; }
  const args = raw.split("\0");
  for (let i = 1; i < args.length; i++) {
    const a = args[i];
    if (!a || a.startsWith("-")) continue;
    return a.slice(a.lastIndexOf("/") + 1);
  }
  return "";
}

// exe basename for a pid (re-keyed to the script for interpreters), memoised in
// `cache` for the duration of one scan. `fallback` supplies a comm when /exe
// is unreadable.
export function exeKey(pid: number, fallback: () => string, cache: Map<number, string>): string {
  const hit = cache.get(pid);
  if (hit !== undefined) return hit;
  let name = "";
  try {
    let l = readlinkSync(`/proc/${pid}/exe`);
    if (l.endsWith(" (deleted)")) l = l.slice(0, -10);
    name = l.slice(l.lastIndexOf("/") + 1);
  } catch {}
  if (!name) name = fallback() || String(pid);
  if (INTERPRETERS.has(name)) {
    const s = scriptKey(pid);
    if (s) name = s;
  }
  cache.set(pid, name);
  return name;
}
