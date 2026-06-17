// CUPS print-job watcher. Event-driven: listens for cupsd's D-Bus notifier
// signals on the SYSTEM bus and, on each signal (debounced), reads the queue
// with one `lpstat`. No polling on the hot path, no root, no deps.
//
// Why a hand-rolled D-Bus client: Bun has no D-Bus binding and this daemon is
// deliberately dependency-free. We only need to *detect* that a CUPS signal
// arrived (then re-query lpstat for ground truth), so the client just does SASL
// EXTERNAL auth + AddMatch and watches for the interface name in incoming
// frames — no message-body unmarshalling.
//
// cupsd only emits these signals while a `dbus://` subscription exists, so we
// create + renew one per local printer. A slow 60s reconcile is a safety net in
// case a signal is ever missed (subscription lapse, printer added). The QS
// `printjobs` widget is a pure consumer of `cups/stream`.

import type { DaemonModule, DaemonContext } from "../types.ts";
import { closeControllers } from "../util.ts";

const CUPS_IFACE = "org.cups.cupsd.Notifier";
const DBUS_SOCK =
  process.env.DBUS_SYSTEM_BUS_ADDRESS?.replace(/^unix:path=/, "") ||
  "/run/dbus/system_bus_socket";
const USER = process.env.USER || "fobos";

const LEASE_SEC = 300; // subscription lease
const RENEW_MS = 240_000; // renew before the lease lapses
const RECONCILE_MS = 60_000; // safety reconcile if a signal is ever missed
const DEBOUNCE_MS = 150; // coalesce a signal burst into one lpstat
const HEARTBEAT_MS = 8_000; // keep idle streams under Bun.serve's 10s idleTimeout

interface Job {
  id: string; // e.g. "Brother_HL_L3240CDW_series-51"
  printer: string; // id minus the trailing -N
  user: string;
  size: number; // bytes
  when: string; // submission time, as lpstat prints it
}
interface State {
  count: number;
  jobs: Job[];
}

// ---------------------------------------------------------------------------
// minimal little-endian D-Bus marshalling (only what we send)
// ---------------------------------------------------------------------------

class Writer {
  buf: number[] = [];
  pad(n: number) {
    while (this.buf.length % n) this.buf.push(0);
  }
  byte(b: number) {
    this.buf.push(b & 0xff);
  }
  u32(v: number) {
    this.pad(4);
    this.buf.push(v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff);
  }
  str(s: string) {
    const b = Buffer.from(s, "utf8");
    this.u32(b.length);
    for (const x of b) this.buf.push(x);
    this.buf.push(0);
  }
  sig(s: string) {
    const b = Buffer.from(s, "utf8");
    this.byte(b.length);
    for (const x of b) this.buf.push(x);
    this.buf.push(0);
  }
}

type Field = [code: number, typeSig: string, value: string];

function buildMsg(type: number, serial: number, fields: Field[], body?: Buffer): Buffer {
  const w = new Writer();
  w.byte(0x6c); // little-endian
  w.byte(type);
  w.byte(0); // flags
  w.byte(1); // protocol version
  w.u32(0); // body length (patched below) @4
  w.u32(serial); // @8
  const arrLenIdx = w.buf.length; // @12
  w.u32(0); // header-array byte length (patched below)
  const arrStart = w.buf.length; // @16, 8-aligned
  for (const [code, ts, val] of fields) {
    w.pad(8); // each header struct aligns to 8
    w.byte(code);
    w.sig(ts); // variant signature
    if (ts === "s" || ts === "o") w.str(val);
    else if (ts === "g") w.sig(val);
  }
  const arrLen = w.buf.length - arrStart;
  w.buf[arrLenIdx] = arrLen & 0xff;
  w.buf[arrLenIdx + 1] = (arrLen >>> 8) & 0xff;
  w.buf[arrLenIdx + 2] = (arrLen >>> 16) & 0xff;
  w.buf[arrLenIdx + 3] = (arrLen >>> 24) & 0xff;
  w.pad(8); // pad header to 8 before body
  const bodyLen = body ? body.length : 0;
  if (body) for (const x of body) w.buf.push(x);
  w.buf[4] = bodyLen & 0xff;
  w.buf[5] = (bodyLen >>> 8) & 0xff;
  w.buf[6] = (bodyLen >>> 16) & 0xff;
  w.buf[7] = (bodyLen >>> 24) & 0xff;
  return Buffer.from(w.buf);
}

const F_PATH: Field = [1, "o", "/org/freedesktop/DBus"];
const F_DEST: Field = [6, "s", "org.freedesktop.DBus"];
const F_IFACE: Field = [2, "s", "org.freedesktop.DBus"];

function helloMsg(serial: number): Buffer {
  return buildMsg(1, serial, [F_PATH, F_DEST, F_IFACE, [3, "s", "Hello"]]);
}
function addMatchMsg(serial: number, rule: string): Buffer {
  const w = new Writer();
  w.str(rule);
  return buildMsg(1, serial, [F_PATH, F_DEST, F_IFACE, [3, "s", "AddMatch"], [8, "g", "s"]], Buffer.from(w.buf));
}

// ---------------------------------------------------------------------------
// module
// ---------------------------------------------------------------------------

export function create(): DaemonModule {
  const encoder = new TextEncoder();
  const streamControllers = new Set<ReadableStreamDefaultController<Uint8Array>>();

  let state: State = { count: 0, jobs: [] };
  let lastJson = JSON.stringify(state);
  let stopped = false;

  const subs = new Map<string, number>(); // printer -> subscription id
  let dbusSocket: any = null;
  let renewTimer: any = null;
  let reconcileTimer: any = null;
  let debounceTimer: any = null;
  let heartbeatTimer: any = null;

  // --- queue read ---------------------------------------------------------

  function parseJobs(out: string): Job[] {
    const jobs: Job[] = [];
    for (const line of out.split("\n")) {
      const m = line.match(/^(\S+)\s+(\S+)\s+(\d+)\s+(.+)$/);
      if (!m) continue;
      const id = m[1];
      jobs.push({
        id,
        printer: id.replace(/-\d+$/, ""),
        user: m[2],
        size: Number(m[3]),
        when: m[4].trim(),
      });
    }
    return jobs;
  }

  async function spawnText(cmd: string[], stdin?: Buffer): Promise<string> {
    try {
      const proc = Bun.spawn(cmd, {
        stdin: stdin ?? "ignore",
        stdout: "pipe",
        stderr: "ignore",
      });
      const out = await new Response(proc.stdout).text();
      await proc.exited;
      return out;
    } catch {
      return "";
    }
  }

  function writeAll(text: string) {
    if (!streamControllers.size) return;
    const enc = encoder.encode(text);
    for (const ctrl of streamControllers) {
      try {
        ctrl.enqueue(enc);
      } catch {
        streamControllers.delete(ctrl);
      }
    }
  }
  // A bare newline keeps the socket active (resetting Bun.serve's idleTimeout)
  // and is ignored client-side by DaemonStream's SplitParser (empty token).
  const broadcast = (json: string) => writeAll(json + "\n");

  async function refresh() {
    if (stopped) return;
    const jobs = parseJobs(await spawnText(["lpstat", "-W", "not-completed", "-o"]));
    const next: State = { count: jobs.length, jobs };
    const json = JSON.stringify(next);
    if (json === lastJson) return;
    lastJson = json;
    state = next;
    broadcast(json);
  }

  function scheduleRefresh() {
    if (debounceTimer || stopped) return; // coalesce a burst
    debounceTimer = setTimeout(() => {
      debounceTimer = null;
      refresh();
    }, DEBOUNCE_MS);
  }

  // --- CUPS subscriptions (so the notifier emits) -------------------------

  async function listPrinters(): Promise<string[]> {
    const out = await spawnText(["lpstat", "-e"]);
    return out
      .split("\n")
      .map((s) => s.trim())
      .filter((s) => s && !s.includes("@")); // skip implicit @host duplicates
  }

  async function createSub(printer: string): Promise<number | null> {
    const uri = `ipp://localhost/printers/${printer}`;
    const out = await spawnText(
      ["ipptool", "-tv", uri, "/dev/stdin"],
      Buffer.from(`{
  OPERATION Create-Printer-Subscriptions
  GROUP operation-attributes-tag
  ATTR charset attributes-charset utf-8
  ATTR naturalLanguage attributes-natural-language en
  ATTR uri printer-uri ${uri}
  ATTR name requesting-user-name ${USER}
  GROUP subscription-attributes-tag
  ATTR uri notify-recipient-uri dbus://
  ATTR keyword notify-events all
  ATTR integer notify-lease-duration ${LEASE_SEC}
}`),
    );
    const m = out.match(/notify-subscription-id \(integer\) = (\d+)/);
    return m ? Number(m[1]) : null;
  }

  async function renewSub(printer: string, id: number): Promise<boolean> {
    const uri = `ipp://localhost/printers/${printer}`;
    const out = await spawnText(
      ["ipptool", "-tv", uri, "/dev/stdin"],
      Buffer.from(`{
  OPERATION Renew-Subscription
  GROUP operation-attributes-tag
  ATTR charset attributes-charset utf-8
  ATTR naturalLanguage attributes-natural-language en
  ATTR uri printer-uri ${uri}
  ATTR name requesting-user-name ${USER}
  ATTR integer notify-subscription-id ${id}
  ATTR integer notify-lease-duration ${LEASE_SEC}
}`),
    );
    return /successful-ok/.test(out);
  }

  async function ensureSubs() {
    if (stopped) return;
    const printers = await listPrinters();
    for (const p of printers) {
      const existing = subs.get(p);
      if (existing != null && (await renewSub(p, existing))) continue;
      subs.delete(p);
      const id = await createSub(p);
      if (id != null) subs.set(p, id);
    }
    for (const p of [...subs.keys()]) if (!printers.includes(p)) subs.delete(p);
  }

  // --- D-Bus listener -----------------------------------------------------

  function connectDbus() {
    if (stopped) return;
    let phase: "auth" | "run" = "auth";
    let acc = Buffer.alloc(0);
    let serial = 1;

    Bun.connect({
      unix: DBUS_SOCK,
      socket: {
        open(s: any) {
          const hexUid = Buffer.from(String(process.getuid!()), "utf8").toString("hex");
          s.write(Buffer.from([0])); // SASL nul
          s.write(`AUTH EXTERNAL ${hexUid}\r\n`);
        },
        data(s: any, data: Buffer) {
          if (phase === "auth") {
            const text = data.toString("latin1");
            if (text.includes("OK")) {
              s.write("BEGIN\r\n");
              s.write(helloMsg(serial++));
              s.write(addMatchMsg(serial++, `type='signal',interface='${CUPS_IFACE}'`));
              phase = "run";
            } else if (text.includes("REJECTED")) {
              console.error("cups: D-Bus AUTH rejected:", text.trim());
            }
            return;
          }
          acc = Buffer.concat([acc, data]);
          while (acc.length >= 16) {
            if (acc[0] !== 0x6c) {
              acc = Buffer.alloc(0); // only LE expected; resync
              break;
            }
            const bodyLen = acc.readUInt32LE(4);
            const arrLen = acc.readUInt32LE(12);
            const total = ((16 + arrLen + 7) & ~7) + bodyLen;
            if (acc.length < total) break;
            const msg = acc.subarray(0, total);
            acc = acc.subarray(total);
            // type 4 = SIGNAL; interface name only appears as a header string
            if (msg[1] === 4 && msg.includes(CUPS_IFACE)) scheduleRefresh();
          }
        },
        close() {
          dbusSocket = null;
          if (!stopped) setTimeout(connectDbus, 1000); // reconnect with backoff
        },
        error(_s: any, e: any) {
          console.error("cups: D-Bus socket error:", e?.message ?? e);
        },
      },
    })
      .then((s) => {
        dbusSocket = s;
      })
      .catch((e) => {
        console.error("cups: D-Bus connect failed:", e?.message ?? e);
        if (!stopped) setTimeout(connectDbus, 1000);
      });
  }

  // --- lifecycle ----------------------------------------------------------

  return {
    name: "cups",

    async init(ctx: DaemonContext) {
      ctx.signal.addEventListener("abort", () => {
        stopped = true;
        if (renewTimer) clearInterval(renewTimer);
        if (reconcileTimer) clearInterval(reconcileTimer);
        if (heartbeatTimer) clearInterval(heartbeatTimer);
        if (debounceTimer) clearTimeout(debounceTimer);
        try {
          dbusSocket?.end();
        } catch {}
        closeControllers(streamControllers);
      });

      connectDbus();
      await ensureSubs();
      await refresh();
      renewTimer = setInterval(ensureSubs, RENEW_MS);
      reconcileTimer = setInterval(refresh, RECONCILE_MS);
      heartbeatTimer = setInterval(() => writeAll("\n"), HEARTBEAT_MS);
    },

    routes: {
      state: () => Response.json(state),

      stream: (req: Request): Response => {
        const stream = new ReadableStream<Uint8Array>({
          start(controller) {
            streamControllers.add(controller);
            try {
              controller.enqueue(encoder.encode(JSON.stringify(state) + "\n"));
            } catch {}
            req.signal.addEventListener("abort", () => {
              streamControllers.delete(controller);
              try {
                controller.close();
              } catch {}
            });
          },
          cancel() {},
        });
        return new Response(stream, {
          headers: {
            "Content-Type": "text/plain",
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
          },
        });
      },

      // GET /cups/cancel?id=<job-id>  or  /cups/cancel?all=1
      cancel: async (req: Request): Promise<Response> => {
        const url = new URL(req.url);
        const id = url.searchParams.get("id");
        const all = url.searchParams.get("all");
        if (all) await spawnText(["cancel", "-a"]);
        else if (id) await spawnText(["cancel", id]);
        await refresh();
        return Response.json(state);
      },
    },

    shutdown() {
      stopped = true;
      if (renewTimer) clearInterval(renewTimer);
      if (reconcileTimer) clearInterval(reconcileTimer);
      if (heartbeatTimer) clearInterval(heartbeatTimer);
      if (debounceTimer) clearTimeout(debounceTimer);
      try {
        dbusSocket?.end();
      } catch {}
      closeControllers(streamControllers);
    },
  };
}
