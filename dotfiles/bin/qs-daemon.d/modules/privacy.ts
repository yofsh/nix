import { readFileSync } from "fs";
import { basename } from "path";
import type { DaemonModule } from "../types.ts";

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

function readCmdline(pid: string): string {
  try {
    const raw = readFileSync(`/proc/${pid}/cmdline`);
    // cmdline is null-separated; first element is the executable
    const first = raw.toString("utf-8").split("\0")[0];
    return first ? basename(first) : "";
  } catch {
    return "";
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

async function checkMic(): Promise<string[]> {
  const voicePids = getVoicePids();

  const raw = await spawn(["pactl", "-f", "json", "list", "source-outputs"]);
  if (!raw.trim()) return [];

  let outputs: any[];
  try {
    outputs = JSON.parse(raw);
  } catch {
    return [];
  }

  const names = new Set<string>();
  for (const entry of outputs) {
    // Skip corked (paused) streams
    if (entry.corked !== false) continue;

    const props = entry.properties ?? {};

    // Skip monitor streams
    if ((props["stream.monitor"] ?? "") === "true") continue;

    // Skip voice script PIDs
    const pid = props["application.process.id"] ?? "";
    if (pid && voicePids.has(pid)) continue;

    const name = props["application.name"];
    if (name) names.add(name);
  }

  return [...names].sort();
}

// ---------------------------------------------------------------------------
// Camera check
// ---------------------------------------------------------------------------

async function checkCam(): Promise<string[]> {
  // fuser on common /dev/video devices
  const raw = await spawn([
    "fuser",
    "/dev/video0",
    "/dev/video1",
    "/dev/video2",
    "/dev/video3",
  ]);
  if (!raw.trim()) return [];

  // fuser outputs PIDs separated by spaces
  const pids = raw
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((s) => s.replace(/[^0-9]/g, ""))
    .filter(Boolean);

  const uniquePids = [...new Set(pids)];

  const names = new Set<string>();
  for (const pid of uniquePids) {
    const name = readCmdline(pid);
    if (name) names.add(name);
  }

  return [...names].sort();
}

// ---------------------------------------------------------------------------
// Screen share check
// ---------------------------------------------------------------------------

async function checkScreen(): Promise<string[]> {
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
  const names = new Set<string>();
  for (const node of nodes) {
    const props = node.info?.props ?? {};
    if (props["media.class"] !== "Stream/Input/Video") continue;

    const target = props["node.target"] ?? props["node.driver-id"];
    if (target != null && portalIds.has(target)) {
      const name = props["node.name"];
      if (name) names.add(name);
    }
  }

  return [...names].sort();
}

// ---------------------------------------------------------------------------
// Module export
// ---------------------------------------------------------------------------

export function create(): DaemonModule {
  return {
    name: "privacy",

    init() {},

    routes: {
      check: async (_req: Request): Promise<Response> => {
        const [mic, cam, screen] = await Promise.all([
          checkMic(),
          checkCam(),
          checkScreen(),
        ]);
        return Response.json({ mic, cam, screen });
      },
    },
  };
}
