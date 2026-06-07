// In-process netlink SOCK_DIAG TCP dump — the spawn-free replacement for
// `ss -tinHOp`. Talks NETLINK_SOCK_DIAG via bun:ffi (libc socket/sendto/recv)
// and returns per-socket cumulative byte counters (tcp_info bytes_acked/
// bytes_received) keyed by socket inode. Mapping inode→pid is the caller's job
// (it scans /proc/*/fd, cached) — see procmon.ts. Falls back gracefully: if the
// FFI/socket can't be set up, `available` is false and the caller keeps `ss`.
//
// Why this exists: per-socket cumulative bytes live ONLY in the kernel's
// INET_DIAG netlink interface (procfs has no such counter), so avoiding the
// `ss` fork means speaking the protocol ourselves. See the spawn-free principle
// in dotfiles/quickshell/CLAUDE.md "Daemon is the single source".

import { dlopen, FFIType } from "bun:ffi";

const AF_NETLINK = 16, AF_INET = 2, AF_INET6 = 10;
const SOCK_RAW = 3, NETLINK_SOCK_DIAG = 4;
const SOCK_DIAG_BY_FAMILY = 20, NLMSG_ERROR = 2, NLMSG_DONE = 3;
const NLM_F_REQUEST = 1, NLM_F_DUMP = 0x300;
const IPPROTO_TCP = 6, INET_DIAG_INFO = 2;
const SOL_SOCKET = 1, SO_RCVTIMEO = 20;

// Data-transfer states only (skip LISTEN, TIME_WAIT, SYN_*, CLOSE — they add
// parse cost without contributing live deltas):
//   ESTABLISHED|FIN_WAIT1|FIN_WAIT2|CLOSE_WAIT|LAST_ACK|CLOSING
const STATES =
  (1 << 1) | (1 << 4) | (1 << 5) | (1 << 8) | (1 << 9) | (1 << 11);

// tcp_info field offsets (stable; later fields are only appended):
const TCPI_BYTES_ACKED = 120;     // __u64 ≈ bytes sent (acked)
const TCPI_BYTES_RECEIVED = 128;  // __u64

export interface SockBytes { inode: number; tx: number; rx: number; }

export interface SockDiag {
  available: boolean;
  dump(): SockBytes[];
  close(): void;
}

export function openSockDiag(): SockDiag {
  let libc: any;
  try {
    libc = dlopen("libc.so.6", {
      socket: { args: [FFIType.i32, FFIType.i32, FFIType.i32], returns: FFIType.i32 },
      setsockopt: { args: [FFIType.i32, FFIType.i32, FFIType.i32, FFIType.ptr, FFIType.u32], returns: FFIType.i32 },
      sendto: { args: [FFIType.i32, FFIType.ptr, FFIType.u64, FFIType.i32, FFIType.ptr, FFIType.u32], returns: FFIType.i64 },
      recv: { args: [FFIType.i32, FFIType.ptr, FFIType.u64, FFIType.i32], returns: FFIType.i64 },
      close: { args: [FFIType.i32], returns: FFIType.i32 },
    }).symbols;
  } catch {
    return unavailable();
  }

  const fd = libc.socket(AF_NETLINK, SOCK_RAW, NETLINK_SOCK_DIAG);
  if (fd < 0) return unavailable();

  // 2s recv timeout so a misbehaving kernel can never hang the daemon.
  const tv = new Uint8Array(16);
  new DataView(tv.buffer).setBigInt64(0, 2n, true); // tv_sec = 2
  libc.setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, tv, tv.length);

  // sockaddr_nl pointing at the kernel (pid 0)
  const sa = new Uint8Array(12);
  new DataView(sa.buffer).setUint16(0, AF_NETLINK, true);

  const rbuf = new Uint8Array(256 * 1024);
  let seq = 0;

  function buildReq(family: number): Uint8Array {
    const buf = new Uint8Array(72);
    const dv = new DataView(buf.buffer);
    dv.setUint32(0, 72, true);                          // nlmsg_len
    dv.setUint16(4, SOCK_DIAG_BY_FAMILY, true);         // nlmsg_type
    dv.setUint16(6, NLM_F_REQUEST | NLM_F_DUMP, true);  // nlmsg_flags
    dv.setUint32(8, ++seq, true);                       // nlmsg_seq
    dv.setUint32(12, 0, true);                          // nlmsg_pid
    dv.setUint8(16, family);                            // sdiag_family
    dv.setUint8(17, IPPROTO_TCP);                       // sdiag_protocol
    dv.setUint8(18, 1 << (INET_DIAG_INFO - 1));         // idiag_ext → tcp_info
    dv.setUint8(19, 0);
    dv.setUint32(20, STATES, true);                     // idiag_states
    return buf;
  }

  function dumpFamily(family: number, out: SockBytes[]): void {
    const req = buildReq(family);
    if (Number(libc.sendto(fd, req, BigInt(req.length), 0, sa, sa.length)) < 0) return;
    let done = false;
    while (!done) {
      const n = Number(libc.recv(fd, rbuf, BigInt(rbuf.length), 0));
      if (n <= 0) break; // 0/EAGAIN (timeout) — stop
      const dv = new DataView(rbuf.buffer, 0, n);
      let o = 0;
      while (o + 16 <= n) {
        const len = dv.getUint32(o, true);
        const type = dv.getUint16(o + 4, true);
        if (len < 16 || o + len > n) break;
        if (type === NLMSG_DONE) { done = true; break; }
        if (type === NLMSG_ERROR) { done = true; break; }
        if (type === SOCK_DIAG_BY_FAMILY) {
          const m = o + 16;                       // inet_diag_msg
          const inode = dv.getUint32(m + 68, true);
          let tx = 0, rx = 0;
          let a = m + 72;                         // rtattr list
          while (a + 4 <= o + len) {
            const rtaLen = dv.getUint16(a, true);
            const rtaType = dv.getUint16(a + 2, true);
            if (rtaLen < 4 || a + rtaLen > o + len) break;
            if (rtaType === INET_DIAG_INFO) {
              const ti = a + 4;                   // struct tcp_info
              if (ti + TCPI_BYTES_RECEIVED + 8 <= o + len) {
                tx = Number(dv.getBigUint64(ti + TCPI_BYTES_ACKED, true));
                rx = Number(dv.getBigUint64(ti + TCPI_BYTES_RECEIVED, true));
              }
            }
            a += (rtaLen + 3) & ~3;
          }
          if (inode > 0 && tx + rx > 0) out.push({ inode, tx, rx });
        }
        o += (len + 3) & ~3;
      }
    }
  }

  return {
    available: true,
    dump(): SockBytes[] {
      const out: SockBytes[] = [];
      try {
        dumpFamily(AF_INET, out);
        dumpFamily(AF_INET6, out);
      } catch {
        // a parse/FFI hiccup shouldn't kill the tick
      }
      return out;
    },
    close() {
      try { libc.close(fd); } catch {}
    },
  };
}

function unavailable(): SockDiag {
  return { available: false, dump: () => [], close: () => {} };
}
