/** Exercise normal process exit: API cancellation uses SIGTERM and cannot prove
 * that retained sessions, worker results and static caches are released at EOF. */
import { deepStrictEqual, equal, ok, throws } from "node:assert/strict";
import { carpExecutable } from "../carp.ts";
import { createSourceFrontend } from "../source_frontend.ts";
import { CompilerError } from "../diagnostics.ts";
import {
  decodeNativeResponse,
  nativeProtocolMagic,
  nativeProtocolVersion,
} from "../native_protocol.ts";
import { instantiateGuest } from "../guest.ts";

async function exchangeAndClose(payloads: Uint8Array[], threads: number) {
  const child = new Deno.Command(carpExecutable, {
    args: ["--threads", String(threads), "--runtime-stats"],
    clearEnv: true,
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const output = child.output();
  const writer = child.stdin.getWriter();
  const timer = setTimeout(() => {
    try {
      child.kill("SIGKILL");
    } catch { /* already exited */ }
  }, 60_000);
  try {
    for (const payload of payloads) {
      const frame = new Uint8Array(payload.byteLength + 4);
      new DataView(frame.buffer).setUint32(0, payload.byteLength / 4, true);
      frame.set(payload, 4);
      await writer.write(frame);
    }
    await writer.close();
    const { code, stdout, stderr } = await output;
    const diagnostic = new TextDecoder().decode(stderr);
    equal(code, 0, diagnostic);
    ok(
      !/ownership mismatch|AddressSanitizer|runtime error:/.test(diagnostic),
      diagnostic,
    );
    const view = new DataView(
      stdout.buffer,
      stdout.byteOffset,
      stdout.byteLength,
    );
    equal(view.getUint32(0, true), 2);
    equal(view.getUint32(4, true), nativeProtocolMagic);
    equal(view.getUint32(8, true), nativeProtocolVersion);
    const responses: Uint8Array[] = [];
    for (let offset = 12; offset < stdout.length;) {
      ok(offset + 4 <= stdout.length, "truncated response length");
      const bytes = view.getUint32(offset, true) * 4;
      offset += 4;
      ok(offset + bytes <= stdout.length, "truncated response");
      responses.push(stdout.slice(offset, offset + bytes));
      offset += bytes;
    }
    equal(responses.length, payloads.length);
    const statistics = diagnostic.split("\n").find((line) =>
      line.startsWith("runtime_stats: ")
    );
    ok(statistics, "normal shutdown did not report its statistics");
    const stats = JSON.parse(statistics.slice("runtime_stats: ".length));
    equal(stats.threads, threads);
    return { responses, stats };
  } finally {
    clearTimeout(timer);
    writer.releaseLock();
    try {
      child.kill("SIGKILL");
    } catch { /* normal EOF exit */ }
    await output.catch(() => {});
  }
}

Deno.test("Carp releases initialized caches when input closes without a request", async () => {
  for (const threads of [1, 4]) await exchangeAndClose([], threads);
});

for (const threads of [1, 4]) {
  Deno.test(`Carp clean EOF releases all request/worker ownership and recovers after errors (${threads} workers)`, async () => {
    const frontend = await createSourceFrontend({ prelude: "none" });
    try {
      const small = await frontend.prepareNative(`
const make = fn offset => fn (value: U32) => @u32.add offset value
entry const answer = fn () => (make 40) 2
`);
      const bad = await frontend.prepareNative(
        "entry const answer = missing\n",
      );
      const large = await frontend.prepareNative(
        Array.from(
          { length: 128 },
          (_, i) =>
            `entry const f${i} = fn (value: U32) => @u32.add value ${i}`,
        ).join(
          "\n",
        ) + "\nentry const answer = fn () => f40 2\n",
      );
      const valid = small.encode("emit", 10_000n);
      const invalid = bad.encode("emit", 10_000n);
      const work = large.encode("emit", 10_000n);
      const payloads = [
        valid,
        invalid,
        valid,
        work,
        valid,
        work,
        valid,
        work,
        valid,
      ];
      const { responses, stats } = await exchangeAndClose(payloads, threads);
      throws(() => decodeNativeResponse(responses[1]), CompilerError);
      const expected = new Map<number, Uint8Array>();
      for (let i = 0; i < responses.length; i++) {
        if (i === 1) continue;
        const response = decodeNativeResponse(responses[i]);
        equal(response.operation, "emit");
        if (response.operation !== "emit") {
          throw new Error("expected Wasm response");
        }
        ok(WebAssembly.validate(response.bytes));
        const kind = [3, 5, 7].includes(i) ? 1 : 0;
        if (expected.has(kind)) {
          deepStrictEqual(response.bytes, expected.get(kind));
        } else expected.set(kind, response.bytes);
        const guest = await instantiateGuest(response.bytes);
        try {
          equal(guest.call("answer", null), 42);
        } finally {
          guest.dispose();
        }
      }
      if (threads === 1) equal(stats.tasks_submitted, 0);
      else {
        ok(stats.tasks_submitted > 0);
        ok(stats.worker_tasks > 0);
      }
    } finally {
      frontend.dispose();
    }
  });
}
