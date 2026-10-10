import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = (seed: number) => `
const a = fn value => @u32.add value ${seed}
const b = fn value => @u32.add value 2
const c = fn value => @u32.add value 3
const d = fn value => @u32.add value 4
const even: U32 -> U32 = fn value => if @u32.eq value 0 then 42 else odd (@u32.sub value 1)
const odd: U32 -> U32 = fn value => if @u32.eq value 0 then 42 else even (@u32.sub value 1)
entry const run: U32 -> U32 = fn value => @u32.add (@u32.add (a value) (b value)) (@u32.add (c value) (d value))
entry const recursive: U32 -> U32 = fn value => even value
`;

Deno.test("private semantic workers preserve fresh retained edited restart Wasm and failed source diagnostics", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-semantic-jobs-" });
  const entry = `${directory}/main.blot`;
  try {
    const options = {
      executable,
      entry,
      prelude: null,
      cacheDirectory: false as const,
    };
    const retained: Awaited<ReturnType<typeof createZigProjectCompiler>>[] = [];
    try {
      for (const semanticWorkers of [1, 2, 4]) {
        retained.push(
          await createZigProjectCompiler({ ...options, semanticWorkers }),
        );
      }
      let original: Uint8Array<ArrayBuffer> | undefined;
      let checkpoint: Uint8Array<ArrayBuffer> | undefined;
      for (const seed of [1, 3, 1, 1]) {
        const outputs = [];
        for (const compiler of retained) {
          const result = await compiler.build({
            sources: { [entry]: source(seed) },
          });
          assert(result.success, JSON.stringify(result));
          if (original === undefined) {
            const counters = result.stats.workCounters as {
              [key: string]: number;
            };
            assert(
              counters.semantic_component_jobs >= 4,
              JSON.stringify(counters),
            );
          }
          outputs.push(result.bytes);
          const guest = await instantiateGuest(result.bytes);
          try {
            for (const value of [0, 7, 0xffff_ffff]) {
              assert.equal(
                guest.call("run", value),
                (4 * value + seed + 9) >>> 0,
              );
            }
            for (const value of [0, 1, 8]) {
              assert.equal(guest.call("recursive", value), 42);
            }
          } finally {
            guest.dispose();
          }
        }
        assert.deepEqual(outputs[0], outputs[1]);
        assert.deepEqual(outputs[0], outputs[2]);
        const fresh = await createZigProjectCompiler({
          ...options,
          semanticWorkers: 4,
        });
        try {
          const rebuilt = await fresh.build({
            sources: { [entry]: source(seed) },
          });
          assert(rebuilt.success, JSON.stringify(rebuilt));
          assert.deepEqual(rebuilt.bytes, outputs[0]);
        } finally {
          await fresh.dispose();
        }
        if (seed === 1) {
          original = outputs[0];
          checkpoint = await retained[0].exportCheckpoint();
        }
      }
      const diagnostics = [];
      for (const compiler of retained) {
        const rejected = await compiler.build({
          sources: { [entry]: source(1) + "const unused: U32 = true\n" },
        });
        assert(!rejected.success);
        diagnostics.push(rejected.diagnostics);
        const corrected = await compiler.build({
          sources: { [entry]: source(1) },
        });
        assert(corrected.success);
        assert.deepEqual(corrected.bytes, original);
      }
      assert.deepEqual(diagnostics[0], diagnostics[1]);
      assert.deepEqual(diagnostics[0], diagnostics[2]);
      const restarted = await createZigProjectCompiler({
        ...options,
        semanticWorkers: 4,
        checkpoint,
      });
      try {
        const result = await restarted.build({
          sources: { [entry]: source(1) },
        });
        assert(result.success);
        assert.deepEqual(result.bytes, original);
      } finally {
        await restarted.dispose();
      }
    } finally {
      await Promise.all(retained.map((compiler) => compiler.dispose()));
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("private semantic worker counts reject invalid options before spawning", async () => {
  for (const semanticWorkers of [0, 17, 1.5, NaN]) {
    await assert.rejects(
      createZigProjectCompiler({
        executable: "/missing-compiler",
        entry: "/main.blot",
        semanticWorkers,
      }),
      /semanticWorkers must be an integer in 1\.\.16/,
    );
  }
});

Deno.test("semantic worker profiling observes joined jobs without changing Wasm or work", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-worker-profile-" });
  const entry = `${directory}/main.blot`;
  try {
    const outputs = [];
    const counters = [];
    for (const profileBackend of [false, true]) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        semanticWorkers: 4,
        profileBackend,
      });
      try {
        const result = await compiler.build({
          sources: { [entry]: source(1) },
        });
        assert(result.success);
        outputs.push(result.bytes);
        counters.push(result.stats.workCounters);
        const timing = result.stats.backendTiming as { [key: string]: unknown };
        if (profileBackend) {
          const work = timing.work as { [key: string]: number };
          for (
            const field of [
              "semantic_coordination_us",
              "semantic_dispatch_us",
              "semantic_publication_us",
              "semantic_job_sum_us",
            ]
          ) {
            assert(Number.isInteger(work[field]) && work[field] >= 0, field);
          }
          assert(work.semantic_job_sum_us > 0);
        } else {
          assert(!("work" in timing));
        }
      } finally {
        await compiler.dispose();
      }
    }
    assert.deepEqual(outputs[0], outputs[1]);
    assert.deepEqual(counters[0], counters[1]);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
