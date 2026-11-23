// Sandboxed Deno child subprocess for Blot vNext `KernelPool` (§5.1).
// Runs under `--no-prompt` with zero `--allow-run` permissions so this child
// exclusively owns stdout's write end and cannot spawn grandchildren.
//
// Wire framing: 16-byte little-endian header
//   [u32 tag, u32 seq_or_flags, u32 payload_bytes, u32 inline_word]
// Control/ack frames always have `payload_bytes === 0`.

const CMD_INIT = 1;
const CMD_SET_CTX = 2;
const CMD_CLEAR_CTX = 3;
const CMD_RUN = 4;
const CMD_COPY_GRANT = 5;
const CMD_DISCARD = 6;

const TAG_INIT_OK = 1;
const TAG_INIT_FAIL = 2;
const TAG_CTX_OK = 3;
const TAG_READY = 4;
const TAG_OVERFLOW_OK = 5;
const TAG_OVERFLOW_CLEANUP_FAIL = 6;
const TAG_DISCARD_OK = 7;
const TAG_DATA_FRAME = 8;
const TAG_COMMIT_OK = 9;
const TAG_CLEANUP_FAIL = 10;
const TAG_ARENA_OOM = 11;
const TAG_RUN_TRAP = 12;

const ARENA_OOM_OFFSET = 640;
const STREAM_SLICE_BYTES = 65_536;

// Wire tag codes matching `blot:abi` / `blot:kernels`:
// 0=Unit, 1=U32, 2=Bool, 3=F32, 5=Array U32, 6=Array F32
const WIRE_U32 = 1;
const WIRE_BOOL = 2;
const WIRE_F32 = 3;

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

function readArenaOom(memory: WebAssembly.Memory | null): boolean {
  if (memory === null || memory.buffer.byteLength < ARENA_OOM_OFFSET + 4) {
    return false;
  }
  return new DataView(memory.buffer).getUint32(ARENA_OOM_OFFSET, true) !== 0;
}

function isMemoryGrowError(err: unknown): boolean {
  if (!(err instanceof Error)) return false;
  const msg = err.message.toLowerCase();
  return msg.includes("out of memory") ||
    msg.includes("memory access") === false &&
      msg.includes("grow");
}

function memoryBytes(memory: WebAssembly.Memory | null): number {
  return memory === null ? 0 : (memory.buffer.byteLength >>> 0);
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

function decodeScalarArg(wireTag: number, bytes: Uint8Array): number {
  if (bytes.byteLength !== 4) throw new Error("expected 4-byte scalar context");
  const dv = new DataView(bytes.buffer, bytes.byteOffset, 4);
  if (wireTag === WIRE_F32) return dv.getFloat32(0, true);
  const u = dv.getUint32(0, true);
  if (wireTag === WIRE_BOOL) return u !== 0 ? 1 : 0;
  return u;
}

interface LoadedKernel {
  memory: WebAssembly.Memory;
  allocate: (bytes: number) => number;
  reset: (arg: number) => void;
  finishInvocation: (() => void) | null;
  entryFn: (ptr: number) => number;
  ctxFn: ((arg: number) => void) | null;
  clearFn: ((arg: number) => void) | null;
  variableOutput: boolean;
  ctxWireTag: number;
}

let kernel: LoadedKernel | null = null;
let heldPacketPtr = 0;
let heldPacketBytes = 0;
let hasHeldPacket = false;

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
      // payload: [u32 wasmLen, u32 metaJsonLen, wasmBytes, metaJsonUtf8]
      try {
        const dv = new DataView(
          payload.buffer,
          payload.byteOffset,
          payload.byteLength,
        );
        const wasmLen = dv.getUint32(0, true);
        const metaLen = dv.getUint32(4, true);
        const wasmBytes = payload.subarray(8, 8 + wasmLen);
        const metaText = decoder.decode(
          payload.subarray(8 + wasmLen, 8 + wasmLen + metaLen),
        );
        const meta = JSON.parse(metaText) as {
          entryName: string;
          variableOutput: boolean;
          ctxExport?: string;
          clearExport?: string;
          ctxWireTag?: number;
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
        const memory = exports["blot:memory"];
        const allocate = exports["blot:allocate"];
        const reset = exports["blot:reset"];
        const entryFn = exports[meta.entryName];
        if (
          !(memory instanceof WebAssembly.Memory) ||
          typeof allocate !== "function" ||
          typeof reset !== "function" ||
          typeof entryFn !== "function"
        ) {
          await writeHeader(TAG_INIT_FAIL, seq, 0, 0);
          continue;
        }
        const finishRaw = exports["blot:finish_invocation"];
        const ctxRaw = meta.ctxExport !== undefined
          ? exports[meta.ctxExport]
          : undefined;
        const clearRaw = meta.clearExport !== undefined
          ? exports[meta.clearExport]
          : undefined;
        kernel = {
          memory,
          allocate: allocate as (bytes: number) => number,
          reset: reset as (arg: number) => void,
          finishInvocation: typeof finishRaw === "function"
            ? (finishRaw as () => void)
            : null,
          entryFn: entryFn as (ptr: number) => number,
          ctxFn: typeof ctxRaw === "function"
            ? (ctxRaw as (arg: number) => void)
            : null,
          clearFn: typeof clearRaw === "function"
            ? (clearRaw as (arg: number) => void)
            : null,
          variableOutput: meta.variableOutput,
          ctxWireTag: meta.ctxWireTag ?? 5,
        };
        hasHeldPacket = false;
        heldPacketPtr = 0;
        heldPacketBytes = 0;
        await writeHeader(TAG_INIT_OK, seq, 0, memoryBytes(memory));
      } catch (err) {
        const oom = isMemoryGrowError(err) ? 1 : 0;
        await writeHeader(TAG_INIT_FAIL, seq, 0, oom);
      }
      continue;
    }

    if (kernel === null) {
      await writeHeader(TAG_RUN_TRAP, seq, 0, 0);
      continue;
    }

    if (cmd === CMD_CLEAR_CTX) {
      if (kernel.clearFn === null) {
        await writeHeader(TAG_CTX_OK, seq, 0, memoryBytes(kernel.memory));
        continue;
      }
      try {
        kernel.reset(0);
        kernel.clearFn(0);
        if (kernel.finishInvocation !== null) kernel.finishInvocation();
        kernel.reset(0);
        await writeHeader(TAG_CTX_OK, seq, 0, memoryBytes(kernel.memory));
      } catch (err) {
        if (readArenaOom(kernel.memory) || isMemoryGrowError(err)) {
          await writeHeader(TAG_ARENA_OOM, seq, 0, 0);
        } else {
          await writeHeader(TAG_CLEANUP_FAIL, seq, 0, 0);
        }
      }
      continue;
    }

    if (cmd === CMD_SET_CTX) {
      if (kernel.ctxFn === null) {
        await writeHeader(TAG_RUN_TRAP, seq, 0, 0);
        continue;
      }
      try {
        let arg: number;
        if (
          kernel.ctxWireTag === WIRE_U32 ||
          kernel.ctxWireTag === WIRE_BOOL ||
          kernel.ctxWireTag === WIRE_F32
        ) {
          kernel.reset(0);
          arg = decodeScalarArg(kernel.ctxWireTag, payload);
        } else {
          arg = writePacketWords(
            kernel.memory,
            kernel.allocate,
            kernel.reset,
            payload,
          );
        }
        kernel.ctxFn(arg);
        if (kernel.finishInvocation !== null) kernel.finishInvocation();
        kernel.reset(0);
        await writeHeader(TAG_CTX_OK, seq, 0, memoryBytes(kernel.memory));
      } catch (err) {
        if (readArenaOom(kernel.memory) || isMemoryGrowError(err)) {
          await writeHeader(TAG_ARENA_OOM, seq, 0, 0);
        } else {
          await writeHeader(TAG_RUN_TRAP, seq, 0, 0);
        }
      }
      continue;
    }

    if (cmd === CMD_RUN) {
      hasHeldPacket = false;
      heldPacketPtr = 0;
      heldPacketBytes = 0;
      let ptr = 0;
      try {
        const inPtr = writePacketWords(
          kernel.memory,
          kernel.allocate,
          kernel.reset,
          payload,
        );
        ptr = kernel.entryFn(inPtr) >>> 0;
      } catch (err) {
        if (readArenaOom(kernel.memory) || isMemoryGrowError(err)) {
          await writeHeader(TAG_ARENA_OOM, seq, 0, 0);
          continue;
        }
        let cleanupOk = 1;
        try {
          if (kernel.finishInvocation !== null) kernel.finishInvocation();
          kernel.reset(0);
          if (readArenaOom(kernel.memory)) cleanupOk = 0;
        } catch {
          cleanupOk = 0;
        }
        await writeHeader(TAG_RUN_TRAP, seq, 0, cleanupOk);
        continue;
      }

      // Inspect output header directly in Wasm linear memory (0 JS copy bytes).
      const buf = kernel.memory.buffer;
      if (ptr < 4 || (ptr & 3) !== 0 || ptr + 4 > buf.byteLength) {
        await writeHeader(TAG_RUN_TRAP, seq, 0, 0);
        continue;
      }
      const lenWords = new DataView(buf).getUint32(ptr, true);
      if (kernel.variableOutput && lenWords === 0xffff_ffff) {
        // Unified [0xffffffff] overflow transition: run cleanup FIRST.
        let cleanupOk = true;
        try {
          if (kernel.finishInvocation !== null) kernel.finishInvocation();
          kernel.reset(0);
          if (readArenaOom(kernel.memory)) cleanupOk = false;
        } catch {
          cleanupOk = false;
        }
        if (cleanupOk) {
          await writeHeader(
            TAG_OVERFLOW_OK,
            seq,
            0,
            memoryBytes(kernel.memory),
          );
        } else {
          await writeHeader(TAG_OVERFLOW_CLEANUP_FAIL, seq, 0, 0);
        }
        continue;
      }

      const resultBytes = lenWords * 4;
      if (ptr + 4 + resultBytes > buf.byteLength) {
        await writeHeader(TAG_RUN_TRAP, seq, 0, 0);
        continue;
      }
      heldPacketPtr = ptr;
      heldPacketBytes = resultBytes;
      hasHeldPacket = true;
      await writeHeader(TAG_READY, seq, 0, resultBytes);
      continue;
    }

    if (cmd === CMD_COPY_GRANT) {
      if (!hasHeldPacket || heldPacketBytes !== inlineWord) {
        await writeHeader(TAG_CLEANUP_FAIL, seq, 0, heldPacketBytes);
        continue;
      }
      const bytesToStream = heldPacketBytes;
      const ptr = heldPacketPtr;
      hasHeldPacket = false;
      heldPacketPtr = 0;
      heldPacketBytes = 0;
      if (bytesToStream > 0) {
        await writeHeader(TAG_DATA_FRAME, seq, bytesToStream, 0);
        // Stream directly from Wasm linear memory in bounded <= 64 KiB slices.
        let offset = 0;
        while (offset < bytesToStream) {
          const take = Math.min(STREAM_SLICE_BYTES, bytesToStream - offset);
          const slice = new Uint8Array(
            kernel.memory.buffer,
            ptr + 4 + offset,
            take,
          );
          await stdoutWriter.write(slice);
          offset += take;
        }
      }
      // Execute mandatory post-copy cleanup BEFORE emitting COMMIT_OK.
      let cleanupOk = true;
      try {
        if (kernel.finishInvocation !== null) kernel.finishInvocation();
        kernel.reset(0);
        if (readArenaOom(kernel.memory)) cleanupOk = false;
      } catch {
        cleanupOk = false;
      }
      if (cleanupOk) {
        await writeHeader(TAG_COMMIT_OK, seq, 0, memoryBytes(kernel.memory));
      } else {
        await writeHeader(TAG_CLEANUP_FAIL, seq, 0, bytesToStream);
      }
      continue;
    }

    if (cmd === CMD_DISCARD) {
      const resultBytes = heldPacketBytes;
      hasHeldPacket = false;
      heldPacketPtr = 0;
      heldPacketBytes = 0;
      let cleanupOk = true;
      try {
        if (kernel.finishInvocation !== null) kernel.finishInvocation();
        kernel.reset(0);
        if (readArenaOom(kernel.memory)) cleanupOk = false;
      } catch {
        cleanupOk = false;
      }
      if (cleanupOk) {
        await writeHeader(TAG_DISCARD_OK, seq, 0, memoryBytes(kernel.memory));
      } else {
        await writeHeader(TAG_CLEANUP_FAIL, seq, 0, resultBytes);
      }
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
