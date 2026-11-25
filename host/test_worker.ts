import { instantiateGuest } from "./guest.ts";
import type { TestCaseResult, TestMetadata } from "./test_runner.ts";

export interface TestWorkerRequest {
  bytes: Uint8Array<ArrayBuffer>;
  test:
    & Pick<TestMetadata, "kind" | "exportName">
    & Partial<Omit<TestMetadata, "kind" | "exportName">>;
}

export interface TestWorkerResponse extends
  Pick<
    TestCaseResult,
    "status" | "assertionsPassed" | "assertionsFailed" | "message"
  > {
  packet?: Uint32Array;
}

function failed(message: string, assertionsFailed = 0): TestWorkerResponse {
  return { status: "failed", assertionsPassed: 0, assertionsFailed, message };
}

async function execute(
  { bytes, test }: TestWorkerRequest,
): Promise<TestWorkerResponse> {
  const guest = await instantiateGuest(bytes);
  const passed: TestWorkerResponse = {
    status: "passed",
    assertionsPassed: 1,
    assertionsFailed: 0,
  };
  try {
    const fn = guest.abi.functions.find((entry) =>
      entry.name === test.exportName
    );
    if (!fn) {
      return failed(`Expected a function export named "${test.exportName}"`);
    }
    if (fn.parameter !== "Unit") {
      return failed(
        `Test parameter must be Unit, got ${
          typeof fn.parameter === "string" ? fn.parameter : fn.parameter.kind
        }`,
      );
    }
    const returns = fn.result;
    if (
      test.kind === "check" && returns !== "Array U32" && returns !== "Bool" &&
      returns !== "Unit"
    ) {
      return failed(
        `Unsupported test return type ${
          typeof returns === "string" ? returns : returns.kind
        }`,
      );
    }
    let value;
    try {
      value = guest.call(test.exportName, null);
    } catch (error) {
      if (test.kind === "trap" && error instanceof WebAssembly.RuntimeError) {
        return passed;
      }
      return failed(
        error instanceof Error ? error.message : String(error),
        test.kind === "check" ? 1 : 0,
      );
    }
    if (test.kind === "trap") {
      return failed("Expected test to trap, but it returned normally", 1);
    }
    if (returns === "Bool" && value !== true) {
      return failed("Expected test to return true", 1);
    }
    if (returns === "Array U32") {
      if (!(value instanceof Uint32Array)) {
        return failed("Expected an Array U32 test report");
      }
      return { ...passed, packet: value };
    }
    return passed;
  } finally {
    guest.dispose();
  }
}

export const TEST_WORKER_ARG = "--blot-internal-test-worker";
export const TEST_WORKER_URL = new URL("./test_worker.ts", import.meta.url);
const workerName = "blot-test-execution";

export function testTransport(
  reader: ReadableStreamBYOBReader,
  writer: WritableStreamDefaultWriter<Uint8Array>,
) {
  async function readExact(length: number, allowEof = false) {
    let bytes = new Uint8Array(length);
    let offset = 0;
    while (offset < length) {
      const { value, done } = await reader.read(bytes.subarray(offset));
      if (value) {
        bytes = new Uint8Array(value.buffer);
        offset += value.byteLength;
      }
      if (done) {
        if (allowEof && offset === 0) return;
        throw new Error("Truncated test worker message");
      }
    }
    return bytes;
  }
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  return {
    async write(data: unknown, payload = new Uint8Array(0)) {
      const json = encoder.encode(JSON.stringify(data));
      const header = new Uint8Array(8);
      const sizes = new DataView(header.buffer);
      sizes.setUint32(0, json.length, true);
      sizes.setUint32(4, payload.length, true);
      await writer.write(header);
      await writer.write(json);
      if (payload.length) await writer.write(payload);
    },
    async read<T>(): Promise<
      { data: T; payload: Uint8Array<ArrayBuffer> } | undefined
    > {
      const header = await readExact(8, true);
      if (!header) return;
      const sizes = new DataView(header.buffer);
      const json = await readExact(sizes.getUint32(0, true));
      const payload = await readExact(sizes.getUint32(4, true));
      return { data: JSON.parse(decoder.decode(json)), payload: payload! };
    },
  };
}

export async function serveTestWorker(): Promise<void> {
  const reader = Deno.stdin.readable.getReader({ mode: "byob" });
  const writer = Deno.stdout.writable.getWriter();
  const transport = testTransport(reader, writer);
  const worker = new Worker(TEST_WORKER_URL.href, {
    type: "module",
    name: workerName,
  });
  function receive<T>(request?: TestWorkerRequest): Promise<T> {
    return new Promise((resolve, reject) => {
      worker.onmessage = (event) => resolve(event.data);
      worker.onmessageerror = () =>
        reject(new Error("Invalid test worker message"));
      worker.onerror = (event) => {
        event.preventDefault();
        reject(new Error(event.message || "Test worker failed"));
      };
      if (request) worker.postMessage(request, [request.bytes.buffer]);
    });
  }
  try {
    await receive<"ready">();
    await transport.write("ready");
    while (true) {
      const frame = await transport.read<TestWorkerRequest["test"]>();
      if (!frame) break;
      const { packet, ...response } = await receive<TestWorkerResponse>({
        test: frame.data,
        bytes: frame.payload,
      });
      await transport.write(
        { ...response, hasPacket: packet !== undefined },
        packet &&
          new Uint8Array(
            packet.buffer as ArrayBuffer,
            packet.byteOffset,
            packet.byteLength,
          ),
      );
    }
  } finally {
    worker.terminate();
    reader.releaseLock();
    writer.releaseLock();
  }
}

if (Reflect.get(globalThis, "name") === workerName) {
  const worker = globalThis as unknown as {
    onmessage: ((event: MessageEvent<TestWorkerRequest>) => void) | null;
    postMessage(response: TestWorkerResponse | "ready"): void;
  };
  worker.onmessage = async ({ data }) => {
    try {
      worker.postMessage(await execute(data));
    } catch (error) {
      worker.postMessage(
        failed(error instanceof Error ? error.message : String(error)),
      );
    }
  };
  worker.postMessage("ready");
} else if (import.meta.main) {
  await serveTestWorker();
}
