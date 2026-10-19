// deno run -A scripts/bench_ink_acceptance.ts [COMPILER [INK [OUTPUT]]]
// Execute the public app-hooks regression with the current local compiler/API.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createZigProjectCompiler } from "../compiler/zig_project_client.ts";
import { instantiateGuest } from "../compiler/guest.ts";

const root = fileURLToPath(new URL("..", import.meta.url));
const executable = resolve(
  Deno.args[0] ?? `${root}/zig-native/zig-out/bin/blotc`,
);
const ink = resolve(Deno.args[1] ?? `${root}/../ink`);
const output = resolve(Deno.args[2] ?? `${root}/build/bench/ink-acceptance`);
assert(Deno.args.length <= 3);
await Deno.mkdir(output, { recursive: true });
const entry = `${ink}/tests/app-hooks.blot`;
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((x) =>
    x.toString(16).padStart(2, "0")
  ).join("");
const rows = [];
for (const codegenTier of ["development", "optimized"] as const) {
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    imports: { "ink/": `${ink}/lib/` },
    stdRoot: `${root}/std/`,
    prelude: `${root}/std/prelude.blot`,
    cacheDirectory: false,
    codegenTier,
    codegenWorkers: 1,
  });
  try {
    const built = await compiler.build();
    assert(built.success, JSON.stringify(built));
    const guest = await instantiateGuest(built.bytes);
    try {
      let warmed = 0;
      for (let i = 0; i < 1000; i++) {
        assert.deepEqual(
          Array.from(guest.call("paused_frame", null) as Float32Array),
          [11, 0, 0, 0.5, 1, 2, 5, 6],
        );
        assert.deepEqual(
          Array.from(guest.call("pause_events", null) as Float32Array),
          [11, 2, 0, 0.5, 0, 1, 2, 1, 2, 1, 2, 3, 4, 4, 5, 6],
        );
        const n = i % 65;
        assert.deepEqual(
          Array.from(guest.call("schedule_workload", n) as Uint32Array),
          [n, n, n * (n + 1) / 2],
        );
        const memory = guest.memoryBytes();
        if (i === 0) warmed = memory;
        assert.equal(
          memory,
          warmed,
          "Repeated app hooks must retain bounded guest memory",
        );
      }
      rows.push({
        codegenTier,
        calls: 3000,
        guest_memory_bytes: warmed,
        wasm_sha256: await hash(built.bytes),
        stats: built.stats,
      });
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
  }
}
const head = await new Deno.Command("git", {
  args: ["-C", ink, "rev-parse", "HEAD"],
  stdout: "piped",
  stderr: "piped",
}).output();
assert(head.success);
const report = {
  compiler_sha256: await hash(await Deno.readFile(executable)),
  ink_revision: new TextDecoder().decode(head.stdout).trim(),
  entry_sha256: await hash(await Deno.readFile(entry)),
  harness_sha256: await hash(await Deno.readFile(new URL(import.meta.url))),
  rows,
};
await Deno.writeTextFile(
  `${output}/results.json`,
  JSON.stringify(report, null, 2) + "\n",
);
console.log(
  JSON.stringify({ ...report, rows: rows.map(({ stats: _, ...r }) => r) }),
);
