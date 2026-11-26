// Measure the cost of forwarding a public record catalog through 16 readers.
import { strict as assert } from "node:assert";
import { join, resolve } from "node:path";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const [before, after, pairs = "12"] = Deno.args;
if (
  !before || !after || !Number.isSafeInteger(Number(pairs)) || Number(pairs) < 1
) {
  throw new Error(
    "Usage: bench_forwarded_constructors.ts BEFORE AFTER [PAIRS]",
  );
}
const directory = await Deno.makeTempDir();
const entry = join(directory, "main.blot");
try {
  await Deno.writeTextFile(
    join(directory, "bridge.blot"),
    'import { make } from "./types"\nfunc carry n => return make n\n',
  );
  const imports: string[] = [];
  let sum = "0";
  for (let i = 0; i < 16; i++) {
    await Deno.writeTextFile(
      join(directory, `reader${i}.blot`),
      'import { carry } from "./bridge"\nfunc read (n: U32): U32 => return (carry n).x\n',
    );
    imports.push(`import { read as read${i} } from "./reader${i}"`);
    sum = `@u32.add (${sum}) (read${i} n)`;
  }
  await Deno.writeTextFile(
    entry,
    [...imports, `io answer (n: U32): U32 => return ${sum}`].join(
      "\n",
    ) + "\n",
  );
  for (const width of [1, 16, 128]) {
    const types = ["type Point is data = $Point { x: U32 }"];
    for (let i = 1; i < width; i++) {
      types.push(`type Extra${i} is data = $Extra${i} { x: U32 }`);
    }
    types.push("func make (x: U32): Point => return $Point { x: x }");
    await Deno.writeTextFile(
      join(directory, "types.blot"),
      types.join("\n") + "\n",
    );
    const order = [{ mode: "before", executable: resolve(before) }, {
      mode: "after",
      executable: resolve(after),
    }];
    let reference: string | undefined;
    for (let round = 1; round <= Number(pairs); round++) {
      for (const { mode, executable } of order) {
        const client = await createZigProjectCompiler({
          entry,
          executable,
          frontendWorkers: 8,
          prelude: null,
          profileBackend: true,
        });
        try {
          const result = await client.build({
            signal: AbortSignal.timeout(9000),
          });
          if (!result.success) assert.fail(JSON.stringify(result.diagnostics));
          const profile = result.stats.phaseProfile as {
            phases: { check: { us: number } };
            checking: {
              parallel_jobs: number;
              parallel_worker_reply_bytes: number;
              type_nodes: number;
              normalization: { resolve_depth_entries: number };
            };
          };
          assert.equal(
            profile.checking.parallel_jobs,
            19,
            "benchmark requires active project workers",
          );
          const hash = new Uint8Array(
            await crypto.subtle.digest("SHA-256", result.bytes),
          ).toHex();
          if (reference === undefined) reference = hash;
          assert.equal(hash, reference);
          if (round === 1) {
            const guest = await instantiateGuest(result.bytes);
            try {
              assert.equal(guest.call("answer", 7), 112);
            } finally {
              guest.dispose();
            }
          }
          console.log(
            JSON.stringify({
              width,
              mode,
              round,
              hash,
              checkMs: profile.phases.check.us / 1000,
              workerJobs: profile.checking.parallel_jobs,
              replyBytes: profile.checking.parallel_worker_reply_bytes,
              typeNodes: profile.checking.type_nodes,
              resolveVisits:
                profile.checking.normalization.resolve_depth_entries,
            }),
          );
        } finally {
          await client.dispose();
        }
      }
      order.reverse();
    }
  }
} finally {
  await Deno.remove(directory, { recursive: true });
}
