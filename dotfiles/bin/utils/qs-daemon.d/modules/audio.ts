import type { DaemonModule, DaemonContext } from "../types.ts";
import type { Subprocess } from "bun";
import { closeControllers } from "../util.ts";

// ---------------------------------------------------------------------------
// Constants (matching Python audio-spectrum)
// ---------------------------------------------------------------------------

const RATE = 16000;
const WINDOW = 1024; // FFT size (15.6 Hz per bin)
const HOP = 512; // hop size -> ~30fps
const BANDS = 24;
const BYTES_PER_SAMPLE = 2; // s16le
const WINDOW_BYTES = WINDOW * BYTES_PER_SAMPLE;
const HOP_BYTES = HOP * BYTES_PER_SAMPLE;

// Threshold and scaling (from Python)
const THRESHOLD = 8;
const SCALE_DIVISOR = 120;

// ---------------------------------------------------------------------------
// Frequency edges: 25 logarithmically spaced from 60Hz to 800Hz
// ---------------------------------------------------------------------------

const FREQ_LO = 60;
const FREQ_HI = 800;
const EDGES: number[] = [];
for (let i = 0; i <= BANDS; i++) {
  EDGES.push(Math.floor(FREQ_LO * (FREQ_HI / FREQ_LO) ** (i / BANDS)));
}

// ---------------------------------------------------------------------------
// Band bin mapping
// ---------------------------------------------------------------------------

const BIN_W = RATE / WINDOW; // Hz per FFT bin
const BAND_RANGES: [number, number][] = [];
for (let b = 0; b < BANDS; b++) {
  let lo = Math.max(1, Math.round(EDGES[b] / BIN_W));
  let hi = Math.max(lo + 1, Math.round(EDGES[b + 1] / BIN_W));
  hi = Math.min(hi, WINDOW / 2);
  BAND_RANGES.push([lo, hi]);
}

// ---------------------------------------------------------------------------
// Precomputed Hanning window
// ---------------------------------------------------------------------------

const HANNING = new Float64Array(WINDOW);
for (let i = 0; i < WINDOW; i++) {
  HANNING[i] = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / WINDOW);
}

// ---------------------------------------------------------------------------
// Bit-reversal permutation table (precomputed for WINDOW=1024)
// ---------------------------------------------------------------------------

const BIT_REV = new Uint32Array(WINDOW);
{
  const bits = Math.log2(WINDOW); // 10 for 1024
  for (let i = 0; i < WINDOW; i++) {
    let rev = 0;
    let val = i;
    for (let b = 0; b < bits; b++) {
      rev = (rev << 1) | (val & 1);
      val >>= 1;
    }
    BIT_REV[i] = rev;
  }
}

// Precomputed twiddle factors for each FFT stage
const TWIDDLE_RE: Float64Array[] = [];
const TWIDDLE_IM: Float64Array[] = [];
{
  let size = 2;
  while (size <= WINDOW) {
    const half = size >> 1;
    const re = new Float64Array(half);
    const im = new Float64Array(half);
    for (let k = 0; k < half; k++) {
      const angle = (-2 * Math.PI * k) / size;
      re[k] = Math.cos(angle);
      im[k] = Math.sin(angle);
    }
    TWIDDLE_RE.push(re);
    TWIDDLE_IM.push(im);
    size <<= 1;
  }
}

// ---------------------------------------------------------------------------
// In-place iterative Cooley-Tukey FFT (radix-2)
// ---------------------------------------------------------------------------

function fft(re: Float64Array, im: Float64Array): void {
  const N = re.length;

  // Bit-reversal permutation
  for (let i = 0; i < N; i++) {
    const j = BIT_REV[i];
    if (i < j) {
      let tmp = re[i];
      re[i] = re[j];
      re[j] = tmp;
      tmp = im[i];
      im[i] = im[j];
      im[j] = tmp;
    }
  }

  // Butterfly stages
  let size = 2;
  let stage = 0;
  while (size <= N) {
    const half = size >> 1;
    const twRe = TWIDDLE_RE[stage];
    const twIm = TWIDDLE_IM[stage];

    for (let i = 0; i < N; i += size) {
      for (let k = 0; k < half; k++) {
        const evenIdx = i + k;
        const oddIdx = i + k + half;

        // Twiddle factor * odd element
        const tRe = twRe[k] * re[oddIdx] - twIm[k] * im[oddIdx];
        const tIm = twRe[k] * im[oddIdx] + twIm[k] * re[oddIdx];

        re[oddIdx] = re[evenIdx] - tRe;
        im[oddIdx] = im[evenIdx] - tIm;
        re[evenIdx] = re[evenIdx] + tRe;
        im[evenIdx] = im[evenIdx] + tIm;
      }
    }

    size <<= 1;
    stage++;
  }
}

// ---------------------------------------------------------------------------
// Module export
// ---------------------------------------------------------------------------

export function create(): DaemonModule {
  const encoder = new TextEncoder();
  const streamControllers = new Set<ReadableStreamDefaultController<Uint8Array>>();

  let parecProc: Subprocess | null = null;
  let processingActive = false;

  // Reusable buffers for FFT
  const fftRe = new Float64Array(WINDOW);
  const fftIm = new Float64Array(WINDOW);

  function processFrame(raw: Int16Array): string {
    // Apply Hanning window
    for (let i = 0; i < WINDOW; i++) {
      fftRe[i] = raw[i] * HANNING[i];
      fftIm[i] = 0;
    }

    // FFT
    fft(fftRe, fftIm);

    // Magnitudes for bins 1..WINDOW/2 (skip DC), averaged per band inline to
    // avoid allocating a full mags array.
    const parts: string[] = [];

    for (let b = 0; b < BANDS; b++) {
      const [lo, hi] = BAND_RANGES[b];
      let sum = 0;
      let count = 0;
      for (let k = lo; k < hi; k++) {
        const mag = Math.sqrt(fftRe[k] * fftRe[k] + fftIm[k] * fftIm[k]) / WINDOW;
        sum += mag;
        count++;
      }
      const avg = count > 0 ? sum / count : 0;
      const level =
        avg < THRESHOLD
          ? 0.0
          : Math.min(1.0, Math.sqrt((avg - THRESHOLD) / SCALE_DIVISOR));
      parts.push(level.toFixed(2));
    }

    return parts.join(" ");
  }

  async function startProcessing(): Promise<void> {
    if (processingActive) return;
    processingActive = true;

    parecProc = Bun.spawn(
      ["parec", "--format=s16le", `--rate=${RATE}`, "--channels=1", "--latency-msec=32"],
      { stdout: "pipe", stderr: "ignore" },
    );

    const stdout = parecProc.stdout;
    if (!stdout) {
      processingActive = false;
      return;
    }

    const reader = stdout.getReader();
    let buf = new Uint8Array(0);

    try {
      while (processingActive) {
        const { done, value } = await reader.read();
        if (done) break;

        // Append new data to buffer
        if (buf.length === 0) {
          buf = value;
        } else {
          const combined = new Uint8Array(buf.length + value.length);
          combined.set(buf);
          combined.set(value, buf.length);
          buf = combined;
        }

        // Process all complete frames in the buffer
        while (buf.length >= WINDOW_BYTES) {
          // Extract one window's worth of samples
          const raw = new Int16Array(
            buf.buffer,
            buf.byteOffset,
            WINDOW,
          );

          const line = processFrame(raw);

          // Advance by HOP (overlap)
          buf = buf.subarray(HOP_BYTES);

          // Broadcast to all connected clients
          if (streamControllers.size > 0) {
            const encoded = encoder.encode(line + "\n");
            for (const ctrl of streamControllers) {
              try {
                ctrl.enqueue(encoded);
              } catch {
                streamControllers.delete(ctrl);
              }
            }
          }
        }
      }
    } catch (e) {
      // Reader cancelled or process killed — expected on shutdown
      if (processingActive) {
        console.error("audio: processing loop error:", e);
      }
    } finally {
      try {
        reader.releaseLock();
      } catch {}
    }
  }

  function stopProcessing(): void {
    processingActive = false;
    if (parecProc) {
      try {
        parecProc.kill();
      } catch {}
      parecProc = null;
    }
  }

  return {
    name: "audio",

    init(ctx: DaemonContext) {
      ctx.signal.addEventListener("abort", () => {
        stopProcessing();
        closeControllers(streamControllers);
      });
    },

    routes: {
      stream: (req: Request): Response => {
        const stream = new ReadableStream<Uint8Array>({
          start(controller) {
            streamControllers.add(controller);

            // First client: start parec + processing
            if (streamControllers.size === 1) {
              startProcessing();
            }

            req.signal.addEventListener("abort", () => {
              streamControllers.delete(controller);
              try {
                controller.close();
              } catch {}

              // Last client gone: stop parec
              if (streamControllers.size === 0) {
                stopProcessing();
              }
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
    },

    shutdown() {
      stopProcessing();
      closeControllers(streamControllers);
    },
  };
}
