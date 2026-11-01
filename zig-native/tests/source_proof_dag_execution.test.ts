import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

function sourceFor(depth: number, width: number): string {
  const lines = [
    "type Row is data = $Row {first: U32, second: U32, third: U32}",
    "const read = func row => return @u32.add row.first (@u32.add row.second row.third)",
  ];
  let previous = "read";
  for (let level = 1; level <= depth; level++) {
    const stage = `stage_${level}`;
    lines.push(
      `const ${stage} = func row => return @u32.add (${previous} row) (${previous} row)`,
    );
    previous = stage;
  }
  lines.push(
    "entry const answer = func (input: U32) => return do:",
    "  let live: GrowArray U32 = #[input]",
    "  let total: U32 = 0",
  );
  for (let call = 0; call < width; call++) {
    let fields = `first: live[0], second: @u32.add input ${call + 1}, third: ${
      call + 2
    }`;
    if (call % 2 === 1) {
      fields = `third: ${call + 2}, first: live[0], second: @u32.add input ${
        call + 1
      }`;
    }
    lines.push(
      `  total := @u32.add total (${previous} ($Row {${fields}}))`,
      "  live[0] := @u32.add live[0] 3",
    );
  }
  lines.push("  return #[total, live[0]]");
  return `${lines.join("\n")}\n`;
}

for (const codegenTier of ["development", "optimized"] as const) {
  for (const depth of [6, 8, 10]) {
    for (const width of [1, 8]) {
      Deno.test(`finite nominal source proofs admit depth ${depth} width ${width} (${codegenTier})`, async () => {
        const directory = await Deno.makeTempDir({
          prefix: "blot-source-proof-",
        });
        const entry = `${directory}/main.blot`;
        const stdRoot = new URL("../../std", import.meta.url).pathname;
        let compiler:
          | Awaited<ReturnType<typeof createZigProjectCompiler>>
          | undefined;
        try {
          compiler = await createZigProjectCompiler({
            executable: Deno.args[0],
            entry,
            stdRoot,
            prelude: `${stdRoot}/prelude.blot`,
            cacheDirectory: false,
            codegenTier,
            startupTimeoutMs: 5_000,
          });
          const result = await compiler.build({
            sources: { [entry]: sourceFor(depth, width) },
            signal: AbortSignal.timeout(5_000),
          });
          if (!result.success) assert.fail(JSON.stringify(result.diagnostics));
          const counters = result.stats.workCounters as Record<string, number>;
          assert(
            counters.scoped_source_proof_instances > 0,
            JSON.stringify(counters),
          );
          assert(
            counters.scoped_source_proof_hits > 0,
            JSON.stringify(counters),
          );
          assert(
            counters.scoped_source_proof_instances < 1_000,
            JSON.stringify(counters),
          );
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(result.bytes, {
              asynchronous,
            });
            try {
              for (const input of [0, 1, 41, 0xfffffffd, 3, 0]) {
                // Summing arithmetic progressions avoids reproducing the call tree.
                const oneLevel = width * (2 * input + 3) +
                  5 * width * (width - 1) / 2;
                const expected = new Uint32Array([
                  oneLevel * 2 ** depth,
                  input + 3 * width,
                ]);
                let actual;
                if (asynchronous) {
                  actual = await guest.callAsync("answer", input);
                } else actual = guest.call("answer", input);
                assert.deepEqual(actual, expected);
              }
            } finally {
              guest.dispose();
            }
          }
        } finally {
          await compiler?.dispose();
          await Deno.remove(directory, { recursive: true });
        }
      });
    }
  }
}
