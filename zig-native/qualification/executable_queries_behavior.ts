import assert from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const base = "/workspace/blot2/build/bench/cloud-principal-graphs";
const out = `${base}/executable-queries-behavior`;
const hash = async (bytes: Uint8Array) =>
  Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
    ),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
const variants = [
  { name: "baseline", executable: `${base}/candidate-source-validation/blotc` },
  { name: "default", executable: `${base}/candidate-executable-queries/blotc` },
  {
    name: "development",
    executable: `${base}/candidate-executable-queries/blotc`,
    codegenTier: "development" as const,
  },
  {
    name: "shared",
    executable: `${base}/candidate-executable-queries/blotc`,
    shareMachineCode: true,
  },
  {
    name: "workers-4",
    executable: `${base}/candidate-executable-queries/blotc`,
    codegenWorkers: 4,
    semanticWorkers: 4,
  },
];
const pins = Object.fromEntries(
  await Promise.all(
    variants.map(
      async (v) => [v.name, await hash(await Deno.readFile(v.executable))],
    ),
  ),
);
await Deno.mkdir(out, { recursive: true });
const entry = `${out}/main.blot`, dep = `${out}/dep.blot`;
const main =
  `import * as dep from "./dep"\nconst changed = 1\nentry const run = fn (value: U32) -> U32 => @u32.add (dep.helper value) changed\n`;
const library =
  `const helper = fn (value: U32) -> U32 => do:\n  let total = value\n${
    "  total := @u32.add total 1\n".repeat(32)
  }  return total\n`;
const changedMain = main.replace("const changed = 1", "const changed = 3");
const changedBody = library.replace("@u32.add total 1", "@u32.add total 2");
const samples: unknown[] = [];
let guests = 0, calls = 0;
let positiveFragments = 0, positiveOptimizer = 0;
for (const variant of variants) {
  const { name, ...policy } = variant;
  const options = {
    ...policy,
    entry,
    prelude: null,
    cacheDirectory: false as const,
  };
  const compiler = await createZigProjectCompiler(options);
  try {
    for (let round = 0; round < 3; round++) {
      for (
        const [phase, source, body, delta] of [
          ["population", main, library, 33],
          ["entry-edit", changedMain, library, 35],
          ["same-signature-callee-edit", main, changedBody, 34],
          ["revert", main, library, 33],
          ["noop", main, library, 33],
        ] as const
      ) {
        const sources = { [entry]: source, [dep]: body };
        const result = await compiler.build({ sources });
        assert(result.success, JSON.stringify({ name, phase, result }));
        const fresh = await createZigProjectCompiler(options);
        try {
          const rebuilt = await fresh.build({ sources });
          assert(rebuilt.success);
          assert.deepEqual(result.bytes, rebuilt.bytes);
        } finally {
          await fresh.dispose();
        }
        const guest = await instantiateGuest(result.bytes);
        try {
          for (const value of [0, 7, 4294967295]) {
            assert.equal(guest.call("run", value), (value + delta) >>> 0);
            calls++;
          }
          guests++;
        } finally {
          guest.dispose();
        }
        const backend = result.stats.backend as Record<string, number>;
        const optimizer = result.stats.runtimeOptimization as Record<
          string,
          number
        >;
        if (name === "default" && phase === "entry-edit") {
          positiveFragments += backend.reused_named + backend.reused_closures;
          positiveOptimizer += optimizer.reused;
        }
        samples.push({
          name,
          round,
          phase,
          wasm: await hash(result.bytes),
          stats: result.stats,
        });
      }
    }
    const bad = await compiler.build({
      sources: {
        [entry]: main,
        [dep]: library + "const unused_error: U32 = true\n",
      },
    });
    assert(!bad.success);
    const restored = await compiler.build({
      sources: { [entry]: main, [dep]: library },
    });
    assert(restored.success);
    const checkpoint = await compiler.exportCheckpoint();
    const restarted = await createZigProjectCompiler({
      ...options,
      checkpoint,
    });
    try {
      const result = await restarted.build({
        sources: { [entry]: main, [dep]: library },
      });
      assert(result.success);
      assert.deepEqual(result.bytes, restored.bytes);
      samples.push({
        name,
        phase: "restart",
        wasm: await hash(result.bytes),
        stats: result.stats,
      });
    } finally {
      await restarted.dispose();
    }
  } finally {
    await compiler.dispose();
  }
  console.log(
    `${name}: same-signature body edits, fresh bytes, execution, recovery and restart matched`,
  );
}
assert(positiveFragments > 0, "no positive fragment reuse");
assert(positiveOptimizer > 0, "no positive optimizer reuse");
for (const v of variants) {
  assert.equal(await hash(await Deno.readFile(v.executable)), pins[v.name]);
}
await Deno.writeTextFile(
  `${out}/report.json`,
  JSON.stringify(
    {
      pins,
      main: await hash(new TextEncoder().encode(main)),
      library: await hash(new TextEncoder().encode(library)),
      samples,
      guests,
      calls,
      positiveFragments,
      positiveOptimizer,
      successful: true,
    },
    null,
    2,
  ) + "\n",
);
console.log(
  `${samples.length} samples; ${guests} guests; ${calls} calls; ${positiveFragments} fragment hits; ${positiveOptimizer} optimizer hits`,
);
