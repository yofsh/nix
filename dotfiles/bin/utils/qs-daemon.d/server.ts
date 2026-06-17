import { existsSync, unlinkSync } from "fs";
import { createHyprIPC } from "./hypr-ipc.ts";
import { runtimeDir } from "./util.ts";
import type { DaemonModule, DaemonContext } from "./types.ts";

import { create as createNetStatus } from "./modules/net-status.ts";
import { create as createDnsTest } from "./modules/dns-test.ts";
import { create as createPrivacy } from "./modules/privacy.ts";
import { create as createUsage } from "./modules/usage.ts";
import { create as createClaudeUsage } from "./modules/claude-usage.ts";
import { create as createClaudeSessions } from "./modules/claude-sessions.ts";
import { create as createFocus } from "./modules/focus.ts";
import { create as createCalendar } from "./modules/calendar.ts";
import { create as createAudio } from "./modules/audio.ts";
import { create as createKeybinds } from "./modules/keybinds.ts";
import { create as createBluetooth } from "./modules/bluetooth.ts";
import { create as createProcmon } from "./modules/procmon.ts";
import { create as createCups } from "./modules/cups.ts";

const SOCKET_NAME = "qs-daemon.sock";

export async function startDaemon() {
  const rtDir = runtimeDir();
  const socketPath = `${rtDir}/${SOCKET_NAME}`;

  if (existsSync(socketPath)) unlinkSync(socketPath);

  const ac = new AbortController();
  const hyprIPC = createHyprIPC();

  const ctx: DaemonContext = { hyprIPC, runtimeDir: rtDir, signal: ac.signal };

  const modules: DaemonModule[] = [
    createNetStatus(),
    createDnsTest(),
    createPrivacy(),
    createUsage(),
    createClaudeUsage(),
    createClaudeSessions(),
    createFocus(),
    createCalendar(),
    createAudio(),
    createKeybinds(),
    createBluetooth(),
    createProcmon(),
    createCups(),
  ];

  const routeTable = new Map<string, (req: Request) => Response | Promise<Response>>();
  for (const mod of modules) {
    for (const [sub, handler] of Object.entries(mod.routes)) {
      routeTable.set(`${mod.name}/${sub}`, handler);
    }
  }

  await Promise.all(modules.map((m) => m.init(ctx)));

  const server = Bun.serve({
    unix: socketPath,
    fetch(req) {
      const url = new URL(req.url);
      const path = url.pathname.replace(/^\/+/, "");

      const handler = routeTable.get(path);
      if (handler) return handler(req);

      if (path === "routes") {
        return Response.json([...routeTable.keys()].sort());
      }

      if (path === "" || path === "health") {
        return Response.json({
          ok: true,
          modules: modules.map((m) => m.name),
          uptime: process.uptime(),
        });
      }

      return new Response("not found", { status: 404 });
    },
  });

  console.error(`qs-daemon listening on ${socketPath}`);

  const shutdown = async () => {
    console.error("qs-daemon shutting down");
    ac.abort();
    for (const mod of modules) await mod.shutdown?.();
    hyprIPC.close();
    server.stop();
    if (existsSync(socketPath)) unlinkSync(socketPath);
    process.exit(0);
  };

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
  process.on("SIGHUP", () => console.error("qs-daemon: SIGHUP received"));
}
