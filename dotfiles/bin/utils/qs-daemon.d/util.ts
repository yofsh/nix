import { homedir } from "os";

export function runtimeDir(): string {
  return process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid!()}`;
}

export function run(cmd: string[], timeout = 2000): string {
  try {
    return Bun.spawnSync(cmd, { timeout }).stdout.toString();
  } catch {
    return "";
  }
}

export function nowSec(): number {
  return Date.now() / 1000;
}

export function todayStartSec(): number {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.getTime() / 1000;
}

// Shared on-disk state dir for the focus + usage trackers.
export const HYPR_USAGE_DIR =
  `${process.env.XDG_DATA_HOME || `${homedir()}/.local/share`}/hypr-usage`;

export function closeControllers(
  controllers: Set<ReadableStreamDefaultController<Uint8Array>>,
): void {
  for (const ctrl of controllers) {
    try {
      ctrl.close();
    } catch {}
  }
  controllers.clear();
}
