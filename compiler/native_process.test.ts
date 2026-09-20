import {
  deepStrictEqual as equal,
  match,
  ok,
  rejects,
} from "node:assert/strict";
import { NativeProcess } from "./native_process.ts";
import {
  decodeNativeResponse,
  encodeNativeRequest,
} from "./native_protocol.ts";
import { createSourceFrontend } from "./source_frontend.ts";

const executable = new URL("../generated/compiler/blotc", import.meta.url);
const options = { executable, threads: 1 };

function words(values: readonly number[]): Uint8Array<ArrayBuffer> {
  const bytes = new Uint8Array(values.length * 4);
  const view = new DataView(bytes.buffer);
  values.forEach((value, index) => view.setUint32(index * 4, value, true));
  return bytes;
}

const handshake = words([2, 0x424C4F54, 1]);

async function sendFraming(input: Uint8Array<ArrayBuffer>) {
  const child = new Deno.Command(executable, {
    args: ["--threads", "1"],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  let finished = false;
  let timedOut = false;
  const output = child.output().then((result) => {
    finished = true;
    return result;
  });
  const stop = () => {
    if (finished) return;
    try {
      child.kill("SIGKILL");
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  };
  const timer = setTimeout(() => {
    timedOut = true;
    stop();
  }, 10_000);
  try {
    await writer.write(input);
    await writer.close();
    const result = await output;
    ok(!timedOut, "native process did not terminate after stdin EOF");
    return result;
  } finally {
    clearTimeout(timer);
    stop();
    await Promise.allSettled([writer.abort(), output]);
    writer.releaseLock();
  }
}

Deno.test({
  name: "native process accepts its handshake and disposes idempotently",
  async fn() {
    const process = await NativeProcess.start(options);
    try {
      const first = process.dispose();
      const second = process.dispose();
      equal(first, second);
      await Promise.all([first, second]);
      await process.dispose();
      await rejects(process.request(new Uint8Array()), /disposed/);
    } finally {
      await process.dispose();
    }
  },
});

Deno.test({
  name:
    "native process snapshots concurrent queued requests and returns each matching artifact",
  async fn() {
    const frontend = await createSourceFrontend({ prelude: "none" });
    let process: NativeProcess | undefined;
    try {
      process = await NativeProcess.start(options);
      await rejects(process.request(Uint8Array.of(1)), RangeError);
      const expected = [7, 42, 0xFFFF_FFFF];
      const payloads = expected.map((answer) => {
        const prepared = frontend.prepare(
          `export fn answer () => ${answer}\n`,
        );
        return encodeNativeRequest({
          operation: "compile",
          root: prepared.root,
          prelude: prepared.prelude,
          fuel: prepared.nodeCount,
          const_steps: 100n,
        });
      });
      const pending = payloads.map((payload) => process!.request(payload));
      for (const payload of payloads) payload.fill(0);
      const responses = await Promise.all(pending);
      for (let index = 0; index < responses.length; index++) {
        const response = decodeNativeResponse(responses[index]);
        equal(response.operation, "compile");
        ok(response.operation === "compile");
        const { instance } = await WebAssembly.instantiate(
          response.artifact.bytes,
        );
        const answer = instance.exports.answer;
        ok(typeof answer === "function");
        equal(answer() >>> 0, expected[index]);
      }
    } finally {
      frontend.dispose();
      await process?.dispose();
    }
  },
});

Deno.test({
  name:
    "native process exits cleanly on frame-boundary EOF with only its handshake",
  async fn() {
    const result = await sendFraming(new Uint8Array());
    equal(result.code, 0);
    equal(result.stdout, handshake);
    equal(result.stderr.length, 0);
  },
});

for (
  const failure of [
    {
      name: "truncated frame prefix",
      input: Uint8Array.of(1, 0),
      diagnostic: /native protocol: truncated frame/,
    },
    {
      name: "truncated frame payload",
      input: Uint8Array.of(1, 0, 0, 0, 42),
      diagnostic: /native protocol: truncated frame/,
    },
    {
      name: "oversized frame",
      input: words([16_777_217]),
      diagnostic: /native protocol: frame exceeds 16777216 words/,
    },
  ]
) {
  Deno.test({
    name: `native process rejects ${failure.name} without contaminating stdout`,
    async fn() {
      const result = await sendFraming(failure.input);
      ok(result.code !== 0);
      equal(result.stdout, handshake);
      match(new TextDecoder().decode(result.stderr), failure.diagnostic);
    },
  });
}
