import { connect, type Socket } from "net";
import { runtimeDir } from "./util.ts";
import type { HyprIPCBus } from "./types.ts";

type Handler = (data: string) => void;

class HyprIPC implements HyprIPCBus {
  private listeners = new Map<string, Set<Handler>>();
  private sock: Socket | null = null;
  private buf = "";
  private stopped = false;

  on(event: string, handler: Handler) {
    if (!this.listeners.has(event)) this.listeners.set(event, new Set());
    this.listeners.get(event)!.add(handler);
  }

  off(event: string, handler: Handler) {
    this.listeners.get(event)?.delete(handler);
  }

  once(event: string, handler: Handler) {
    const wrapped: Handler = (data) => {
      this.off(event, wrapped);
      handler(data);
    };
    this.on(event, wrapped);
  }

  private emit(event: string, data: string) {
    for (const h of this.listeners.get(event) || []) h(data);
    for (const h of this.listeners.get("*") || []) h(`${event}>>${data}`);
  }

  private dispatch(line: string) {
    const sep = line.indexOf(">>");
    if (sep < 0) return;
    this.emit(line.slice(0, sep), line.slice(sep + 2));
  }

  connect() {
    const sig = process.env.HYPRLAND_INSTANCE_SIGNATURE;
    if (!sig) {
      console.error("hypr-ipc: HYPRLAND_INSTANCE_SIGNATURE not set");
      return;
    }
    const sockPath = `${runtimeDir()}/hypr/${sig}/.socket2.sock`;

    const sock: Socket = connect({ path: sockPath });
    this.sock = sock;

    sock.on("data", (chunk: Buffer) => {
      this.buf += chunk.toString("utf-8");
      let nl: number;
      while ((nl = this.buf.indexOf("\n")) >= 0) {
        const line = this.buf.slice(0, nl).trim();
        this.buf = this.buf.slice(nl + 1);
        if (line) this.dispatch(line);
      }
    });

    sock.on("error", (err: Error) => console.error("hypr-ipc:", err.message));

    sock.on("close", () => {
      this.sock = null;
      if (!this.stopped) setTimeout(() => this.connect(), 2000);
    });
  }

  close() {
    this.stopped = true;
    this.sock?.destroy();
    this.sock = null;
  }
}

export function createHyprIPC(): HyprIPC {
  const ipc = new HyprIPC();
  ipc.connect();
  return ipc;
}
