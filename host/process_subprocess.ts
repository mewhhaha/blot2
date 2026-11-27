// Sandboxed Deno child subprocess for Squid vNext `Processes` (§5.2).
// Runs under `--no-prompt` with zero `--allow-run` permissions so this child
// exclusively owns stdout's write end and cannot spawn grandchildren.
//
// Wire framing: 16-byte little-endian header
//   [u32 tag, u32 seq_or_flags, u32 payload_bytes, u32 inline_word]
// - `wire_tag == 0` (Unit): header-only COMMIT_OK_UNIT (0 B)
// - `wire_tag in {1, 2, 3}` (U32, Bool, F32 incl. 1-word FlatFixed records):
//   header-only COMMIT_OK_SCALAR (inline_word = u32 bits, 4 B logical)
// - `wire_tag in {5, 6}` (Array U32 / Array F32 / multi-word FlatFixed):
//   DATA_FRAME + streamed raw slices (if > 0) + trailing COMMIT_OK / CLEANUP_FAIL

const CMD_INIT = 1;
const CMD_STEP = 2;

const TAG_INIT_OK = 1;
const TAG_INIT_FAIL = 2;
const TAG_COMMIT_OK_UNIT = 3;
const TAG_COMMIT_OK_SCALAR = 4;
const TAG_DATA_FRAME = 5;
const TAG_COMMIT_OK = 6;
const TAG_CLEANUP_FAIL = 7;
const TAG_STEP_FAIL = 8;

const WIRE_UNIT = 0;
const WIRE_U32 = 1;
const WIRE_BOOL = 2;
const WIRE_F32 = 3;
const STREAM_SLICE_BYTES = 65_536;

const stdinReader = Deno.stdin.readable.getReader();
const stdoutWriter = Deno.stdout.writable.getWriter();

let pendingChunk: Uint8Array | null = null;
let pendingOffset = 0;

async function readExact(n: number): Promise<Uint8Array<ArrayBuffer> | null> {
  if (n === 0) return new Uint8Array(new ArrayBuffer(0));
  const out = new Uint8Array(new ArrayBuffer(n));
  let filled = 0;
  while (filled < n) {
    if (pendingChunk !== null && pendingOffset < pendingChunk.byteLength) {
      const avail = pendingChunk.byteLength - pendingOffset;
      const take = Math.min(avail, n - filled);
      out.set(
        pendingChunk.subarray(pendingOffset, pendingOffset + take),
        filled,
      );
      pendingOffset += take;
      filled += take;
      if (pendingOffset >= pendingChunk.byteLength) {
        pendingChunk = null;
        pendingOffset = 0;
      }
      continue;
    }
    const { done, value } = await stdinReader.read();
    if (done || value === undefined) {
      return filled === 0 ? null : (() => {
        throw new Error("unexpected stdin EOF");
      })();
    }
    pendingChunk = value;
    pendingOffset = 0;
  }
  return out;
}

const headerScratch = new Uint8Array(16);
const headerView = new DataView(headerScratch.buffer);
const f32Scratch = new DataView(new ArrayBuffer(4));

async function writeHeader(
  tag: number,
  seq: number,
  payloadBytes: number,
  inlineWord: number,
): Promise<void> {
  headerView.setUint32(0, tag >>> 0, true);
  headerView.setUint32(4, seq >>> 0, true);
  headerView.setUint32(8, payloadBytes >>> 0, true);
  headerView.setUint32(12, inlineWord >>> 0, true);
  await stdoutWriter.write(headerScratch.slice());
}

function f32ToBits(v: number): number {
  f32Scratch.setFloat32(0, Math.fround(v), true);
  return f32Scratch.getUint32(0, true);
}

function bitsToF32(bits: number): number {
  f32Scratch.setUint32(0, bits >>> 0, true);
  return f32Scratch.getFloat32(0, true);
}

function writePacketWords(
  memory: WebAssembly.Memory,
  allocate: (bytes: number) => number,
  reset: (arg: number) => void,
  bytes: Uint8Array,
): number {
  reset(0);
  const words = bytes.byteLength >>> 2;
  const ptr = allocate((words + 1) * 4) >>> 0;
  const buf = memory.buffer;
  if (
    ptr < 4 || (ptr & 3) !== 0 || ptr + 4 + bytes.byteLength > buf.byteLength
  ) {
    throw new Error("packet allocation out of bounds");
  }
  new DataView(buf).setUint32(ptr, words, true);
  if (bytes.byteLength > 0) {
    new Uint8Array(buf, ptr + 4, bytes.byteLength).set(bytes);
  }
  return ptr;
}

function decodeScalarParam(wireTag: number, inlineWord: number): number {
  if (wireTag === WIRE_UNIT) return 0;
  if (wireTag === WIRE_BOOL) return inlineWord !== 0 ? 1 : 0;
  if (wireTag === WIRE_F32) return bitsToF32(inlineWord);
  return inlineWord >>> 0;
}

interface LoadedProcess {
  memory: WebAssembly.Memory | null;
  allocate: ((bytes: number) => number) | null;
  reset: ((arg: number) => void) | null;
  finishInvocation: (() => void) | null;
  initFn: (arg: number) => void;
  stepFn: (arg: number) => number;
  configWireTag: number;
  cmdWireTag: number;
  replyWireTag: number;
  replyFixedBytes: number | null;
  maxReplyBytes: number;
}

let proc: LoadedProcess | null = null;

function runCleanup(p: LoadedProcess): boolean {
  try {
    if (p.finishInvocation !== null) p.finishInvocation();
    if (p.reset !== null) p.reset(0);
    return true;
  } catch {
    return false;
  }
}

async function main(): Promise<void> {
  const decoder = new TextDecoder();
  for (;;) {
    const hdrBytes = await readExact(16);
    if (hdrBytes === null) break;
    const hdr = new DataView(
      hdrBytes.buffer,
      hdrBytes.byteOffset,
      hdrBytes.byteLength,
    );
    const cmd = hdr.getUint32(0, true);
    const seq = hdr.getUint32(4, true);
    const payloadLen = hdr.getUint32(8, true);
    const inlineWord = hdr.getUint32(12, true);
    const payload = payloadLen > 0
      ? await readExact(payloadLen)
      : new Uint8Array(new ArrayBuffer(0));
    if (payload === null) break;

    if (cmd === CMD_INIT) {
      // payload: [u32 wasmLen, u32 metaLen, u32 configLen, wasmBytes, metaJson, configBytes]
      try {
        const dv = new DataView(
          payload.buffer,
          payload.byteOffset,
          payload.byteLength,
        );
        const wasmLen = dv.getUint32(0, true);
        const metaLen = dv.getUint32(4, true);
        const configLen = dv.getUint32(8, true);
        const wasmBytes = payload.subarray(12, 12 + wasmLen);
        const metaText = decoder.decode(
          payload.subarray(12 + wasmLen, 12 + wasmLen + metaLen),
        );
        const configBytes = payload.subarray(
          12 + wasmLen + metaLen,
          12 + wasmLen + metaLen + configLen,
        );
        const meta = JSON.parse(metaText) as {
          initExport: string;
          stepExport: string;
          configWireTag: number;
          cmdWireTag: number;
          replyWireTag: number;
          replyFixedBytes: number | null;
          maxReplyBytes: number;
        };
        const module = new WebAssembly.Module(wasmBytes);
        const stubImports: Record<
          string,
          Record<string, WebAssembly.ImportValue>
        > = {};
        for (const imp of WebAssembly.Module.imports(module)) {
          if (imp.kind === "function") {
            (stubImports[imp.module] ??= {})[imp.name] = () => {
              throw new Error(
                `unexpected host import ${imp.module}/${imp.name}`,
              );
            };
          }
        }
        const instance = new WebAssembly.Instance(module, stubImports);
        const exports = instance.exports;
        const memRaw = exports["squid:memory"];
        const allocRaw = exports["squid:allocate"];
        const resetRaw = exports["squid:reset"];
        const finishRaw = exports["squid:finish_invocation"];
        const initRaw = exports[meta.initExport];
        const stepRaw = exports[meta.stepExport];
        if (typeof initRaw !== "function" || typeof stepRaw !== "function") {
          await writeHeader(TAG_INIT_FAIL, seq, 0, 0);
          break;
        }
        const hasArena = memRaw instanceof WebAssembly.Memory &&
          typeof allocRaw === "function" && typeof resetRaw === "function";
        const loaded: LoadedProcess = {
          memory: hasArena ? memRaw : null,
          allocate: hasArena ? (allocRaw as (bytes: number) => number) : null,
          reset: hasArena ? (resetRaw as (arg: number) => void) : null,
          finishInvocation: typeof finishRaw === "function"
            ? (finishRaw as () => void)
            : null,
          initFn: initRaw as (arg: number) => void,
          stepFn: stepRaw as (arg: number) => number,
          configWireTag: meta.configWireTag,
          cmdWireTag: meta.cmdWireTag,
          replyWireTag: meta.replyWireTag,
          replyFixedBytes: meta.replyFixedBytes,
          maxReplyBytes: meta.maxReplyBytes,
        };

        let initArg: number;
        if (loaded.configWireTag === 5 || loaded.configWireTag === 6) {
          if (
            loaded.memory === null || loaded.allocate === null ||
            loaded.reset === null
          ) {
            await writeHeader(TAG_INIT_FAIL, seq, 0, 0);
            break;
          }
          initArg = writePacketWords(
            loaded.memory,
            loaded.allocate,
            loaded.reset,
            configBytes,
          );
        } else {
          if (loaded.reset !== null) loaded.reset(0);
          initArg = decodeScalarParam(loaded.configWireTag, inlineWord);
        }
        loaded.initFn(initArg);
        if (!runCleanup(loaded)) {
          await writeHeader(TAG_INIT_FAIL, seq, 0, 0);
          break;
        }
        proc = loaded;
        await writeHeader(TAG_INIT_OK, seq, 0, 0);
      } catch {
        await writeHeader(TAG_INIT_FAIL, seq, 0, 0);
        break;
      }
      continue;
    }

    if (cmd === CMD_STEP) {
      if (proc === null) {
        await writeHeader(TAG_STEP_FAIL, seq, 0, 0);
        break;
      }
      let rawResult = 0;
      try {
        let cmdArg: number;
        if (proc.cmdWireTag === 5 || proc.cmdWireTag === 6) {
          if (
            proc.memory === null || proc.allocate === null ||
            proc.reset === null
          ) {
            await writeHeader(TAG_STEP_FAIL, seq, 0, 0);
            break;
          }
          cmdArg = writePacketWords(
            proc.memory,
            proc.allocate,
            proc.reset,
            payload,
          );
        } else {
          if (proc.reset !== null) proc.reset(0);
          cmdArg = decodeScalarParam(proc.cmdWireTag, inlineWord);
        }
        rawResult = proc.stepFn(cmdArg);
      } catch {
        // Process store is never reused after a step trap; skip cleanup.
        await writeHeader(TAG_STEP_FAIL, seq, 0, 0);
        break;
      }

      if (proc.replyWireTag === WIRE_UNIT) {
        if (!runCleanup(proc)) {
          await writeHeader(TAG_CLEANUP_FAIL, seq, 0, 0);
          break;
        }
        await writeHeader(TAG_COMMIT_OK_UNIT, seq, 0, 0);
        continue;
      }

      if (
        proc.replyWireTag === WIRE_U32 ||
        proc.replyWireTag === WIRE_BOOL ||
        proc.replyWireTag === WIRE_F32
      ) {
        let word = 0;
        if (proc.replyWireTag === WIRE_U32) {
          word = rawResult >>> 0;
        } else if (proc.replyWireTag === WIRE_BOOL) {
          if (rawResult !== 0 && rawResult !== 1) {
            await writeHeader(TAG_STEP_FAIL, seq, 0, 0);
            break;
          }
          word = rawResult;
        } else {
          word = f32ToBits(rawResult);
        }
        if (!runCleanup(proc)) {
          await writeHeader(TAG_CLEANUP_FAIL, seq, 0, 0);
          break;
        }
        await writeHeader(TAG_COMMIT_OK_SCALAR, seq, 0, word);
        continue;
      }

      // wire_tag in {5, 6}: array or multi-word FlatFixed reply.
      if (proc.memory === null) {
        await writeHeader(TAG_STEP_FAIL, seq, 0, 0);
        break;
      }
      const ptr = rawResult >>> 0;
      const buf = proc.memory.buffer;
      if (ptr < 4 || (ptr & 3) !== 0 || ptr + 4 > buf.byteLength) {
        await writeHeader(TAG_STEP_FAIL, seq, 0, 0);
        break;
      }
      const lenWords = new DataView(buf).getUint32(ptr, true);
      const replyBytes = lenWords * 4;
      if (
        ptr + 4 + replyBytes > buf.byteLength ||
        replyBytes > proc.maxReplyBytes ||
        (proc.replyFixedBytes !== null && replyBytes !== proc.replyFixedBytes)
      ) {
        await writeHeader(TAG_STEP_FAIL, seq, 0, 0);
        break;
      }

      // Write DATA_FRAME + stream raw linear-memory slices (0 slices if 0 bytes).
      await writeHeader(TAG_DATA_FRAME, seq, replyBytes, 0);
      let offset = 0;
      while (offset < replyBytes) {
        const take = Math.min(STREAM_SLICE_BYTES, replyBytes - offset);
        const slice = new Uint8Array(
          proc.memory.buffer,
          ptr + 4 + offset,
          take,
        );
        await stdoutWriter.write(slice);
        offset += take;
      }

      // Mandatory post-stream cleanup BEFORE emitting trailing COMMIT_OK.
      if (!runCleanup(proc)) {
        await writeHeader(TAG_CLEANUP_FAIL, seq, 0, 0);
        break;
      }
      await writeHeader(TAG_COMMIT_OK, seq, 0, 0);
      continue;
    }
  }
}

try {
  await main();
} finally {
  try {
    await stdoutWriter.close();
  } catch { /* ignore */ }
}
