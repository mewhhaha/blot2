/** Verify that compiler batches execute on workers, not just accept --threads. */
import { deepStrictEqual, equal, ok } from "node:assert/strict";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { carpExecutable } from "../carp.ts";
import { createSourceFrontend } from "../source_frontend.ts";
import {
  decodeNativeResponse,
  nativeProtocolMagic,
  nativeProtocolVersion,
} from "../native_protocol.ts";

if (Deno.args.length > 1) {
  throw new Error("Usage: worker_probe.ts [executable]");
}
const executable = Deno.args[0]
  ? pathToFileURL(resolve(Deno.args[0]))
  : carpExecutable;
const source = Array.from(
  { length: 128 },
  (_, i) => `entry const f${i} = fn (value: U32) => @u32.add value ${i}`,
).join("\n") + "\n";
const frontend = await createSourceFrontend({ prelude: "none" });
try {
  const prepared = await frontend.prepareNative(source);
  const payload = prepared.encode("emit", 10_000n);
  const input = new Uint8Array(4 + payload.byteLength);
  new DataView(input.buffer).setUint32(0, payload.byteLength / 4, true);
  input.set(payload, 4);
  let expected: Uint8Array<ArrayBuffer> | undefined;
  for (const threads of [1, 4]) {
    const child = new Deno.Command(executable, {
      args: ["--threads", String(threads), "--runtime-stats"],
      clearEnv: true,
      stdin: "piped",
      stdout: "piped",
      stderr: "piped",
    }).spawn();
    const result = child.output();
    const writer = child.stdin.getWriter();
    await writer.write(input);
    await writer.close();
    const { code, stdout, stderr } = await result;
    equal(code, 0, new TextDecoder().decode(stderr));
    const view = new DataView(
      stdout.buffer,
      stdout.byteOffset,
      stdout.byteLength,
    );
    equal(view.getUint32(0, true), 2);
    equal(view.getUint32(4, true), nativeProtocolMagic);
    equal(view.getUint32(8, true), nativeProtocolVersion);
    equal(stdout.byteLength, 16 + view.getUint32(12, true) * 4);
    const response = decodeNativeResponse(stdout.slice(16));
    equal(response.operation, "emit");
    if (response.operation !== "emit") throw new Error("expected Wasm");
    ok(WebAssembly.validate(response.bytes));
    if (expected) deepStrictEqual(response.bytes, expected);
    else expected = response.bytes;
    const line = new TextDecoder().decode(stderr).split("\n").find((line) =>
      line.startsWith("runtime_stats: ")
    );
    ok(line);
    const stats = JSON.parse(line.slice("runtime_stats: ".length));
    equal(stats.threads, threads);
    if (threads === 1) {
      equal(stats.tasks_submitted, 0);
      equal(stats.worker_tasks, 0);
    } else {
      ok(stats.tasks_submitted > 0, "no compiler batch was submitted");
      ok(stats.worker_tasks > 0, "compiler work never reached a worker");
    }
    console.log(JSON.stringify(stats));
  }
  console.log(
    "Worker probe: actual compiler work executed on workers; Wasm remained identical.",
  );
} finally {
  frontend.dispose();
}
