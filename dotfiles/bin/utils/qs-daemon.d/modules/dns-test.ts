import { resolve4 } from "node:dns/promises";
import { createSocket } from "node:dgram";
import type { DaemonModule } from "../types.ts";

const TARGETS = ["google.com", "cloudflare.com", "github.com"];
const EXTERNAL = "1.1.1.1";
const TIMEOUT = 3000;

interface TestResult {
  domain: string;
  ok: boolean;
  ip: string;
  time_ms: number;
  error: string;
}

// ── System resolver (libc / nsswitch / resolv.conf) ─────────────────────────

async function resolveSystem(domain: string): Promise<TestResult> {
  const start = performance.now();
  try {
    const ips = await resolve4(domain);
    const elapsed = Math.round(performance.now() - start);
    const ip = ips.length > 0 ? ips[0] : "";
    return {
      domain,
      ok: ips.length > 0,
      ip,
      time_ms: elapsed,
      error: ips.length > 0 ? "" : "no answer",
    };
  } catch (e: any) {
    return {
      domain,
      ok: false,
      ip: "",
      time_ms: Math.round(performance.now() - start),
      error: e.message || "resolve error",
    };
  }
}

// ── Raw DNS-over-UDP ────────────────────────────────────────────────────────

function buildQuery(domain: string, tid: number): Buffer {
  // Header: 12 bytes
  const header = Buffer.alloc(12);
  header.writeUInt16BE(tid, 0);         // Transaction ID
  header.writeUInt16BE(0x0100, 2);      // Flags: standard query, recursion desired
  header.writeUInt16BE(1, 4);           // QDCOUNT
  header.writeUInt16BE(0, 6);           // ANCOUNT
  header.writeUInt16BE(0, 8);           // NSCOUNT
  header.writeUInt16BE(0, 10);          // ARCOUNT

  // QNAME: length-prefixed labels + null terminator
  const labels = domain.split(".");
  const qnameParts: Buffer[] = [];
  for (const label of labels) {
    const len = Buffer.alloc(1);
    len.writeUInt8(label.length, 0);
    qnameParts.push(len, Buffer.from(label, "ascii"));
  }
  qnameParts.push(Buffer.from([0x00])); // null terminator
  const qname = Buffer.concat(qnameParts);

  // QTYPE=A (1), QCLASS=IN (1)
  const qfooter = Buffer.alloc(4);
  qfooter.writeUInt16BE(1, 0);  // QTYPE
  qfooter.writeUInt16BE(1, 2);  // QCLASS

  return Buffer.concat([header, qname, qfooter]);
}

function skipName(data: Buffer, pos: number): number {
  while (pos < data.length) {
    const b = data[pos];
    if (b === 0) return pos + 1;               // end of name
    if ((b & 0xc0) === 0xc0) return pos + 2;   // compression pointer
    pos += b + 1;                               // skip label
  }
  return pos;
}

function parseFirstA(
  data: Buffer,
  expectedTid: number,
): { ip: string; error: string } {
  if (data.length < 12) return { ip: "", error: "short response" };

  const tid = data.readUInt16BE(0);
  const flags = data.readUInt16BE(2);
  // const qdcount = data.readUInt16BE(4);
  const ancount = data.readUInt16BE(6);

  if (tid !== expectedTid) return { ip: "", error: "tid mismatch" };

  const rcode = flags & 0xf;
  if (rcode !== 0) return { ip: "", error: `rcode ${rcode}` };
  if (ancount === 0) return { ip: "", error: "no answer" };

  // Skip question section
  let pos = 12;
  pos = skipName(data, pos);  // skip QNAME
  pos += 4;                   // skip QTYPE + QCLASS

  // Iterate answer records
  for (let i = 0; i < ancount; i++) {
    if (pos >= data.length) break;
    pos = skipName(data, pos); // skip NAME
    if (pos + 10 > data.length) break;

    const atype = data.readUInt16BE(pos);
    // aclass at pos+2
    // ttl at pos+4 (4 bytes)
    const rdlen = data.readUInt16BE(pos + 8);
    pos += 10;

    if (atype === 1 && rdlen === 4 && pos + 4 <= data.length) {
      const ip = `${data[pos]}.${data[pos + 1]}.${data[pos + 2]}.${data[pos + 3]}`;
      return { ip, error: "" };
    }
    pos += rdlen;
  }

  return { ip: "", error: "no A record" };
}

function resolveRaw(domain: string, server: string): Promise<TestResult> {
  return new Promise((resolve) => {
    const tid = (Math.random() * 0xffff) | 0;
    const packet = buildQuery(domain, tid);
    const sock = createSocket("udp4");
    const start = performance.now();
    let settled = false;

    const finish = (result: TestResult) => {
      if (settled) return;
      settled = true;
      try { sock.close(); } catch {}
      resolve(result);
    };

    const timer = setTimeout(() => {
      finish({ domain, ok: false, ip: "", time_ms: TIMEOUT, error: "timeout" });
    }, TIMEOUT);

    sock.on("error", (err) => {
      clearTimeout(timer);
      finish({
        domain,
        ok: false,
        ip: "",
        time_ms: Math.round(performance.now() - start),
        error: err.message || "udp error",
      });
    });

    sock.on("message", (msg) => {
      clearTimeout(timer);
      const elapsed = Math.round(performance.now() - start);
      const buf = Buffer.from(msg);
      const { ip, error } = parseFirstA(buf, tid);
      finish({ domain, ok: !!ip, ip, time_ms: elapsed, error });
    });

    sock.send(packet, 53, server, (err) => {
      if (err) {
        clearTimeout(timer);
        finish({
          domain,
          ok: false,
          ip: "",
          time_ms: Math.round(performance.now() - start),
          error: err.message || "send error",
        });
      }
    });
  });
}

// ── Module ──────────────────────────────────────────────────────────────────

export function create(): DaemonModule {
  return {
    name: "dns",

    init() {},

    routes: {
      test: async (req: Request): Promise<Response> => {
        const url = new URL(req.url);
        const upstream = url.searchParams.get("upstream") || "";

        // Build work list
        const work: Array<{ method: string; server: string }> = [
          { method: "system", server: "system" },
        ];
        if (upstream) {
          work.push({ method: "upstream", server: upstream });
        }
        work.push({ method: "external", server: EXTERNAL });

        // Run all methods in parallel; each method runs all targets in parallel
        const results = await Promise.all(
          work.map(async ({ method, server }) => {
            const tests =
              method === "system"
                ? await Promise.all(TARGETS.map((d) => resolveSystem(d)))
                : await Promise.all(TARGETS.map((d) => resolveRaw(d, server)));
            return { method, server, tests };
          }),
        );

        const methods: Record<string, { server: string; tests: TestResult[] }> = {};
        for (const { method, server, tests } of results) {
          methods[method] = { server, tests };
        }

        return Response.json({ ts: Date.now() / 1000, methods });
      },
    },
  };
}
