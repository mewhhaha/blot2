// Worker counts are execution choices: every count must emit the same Wasm
// and diagnostics, fresh and after a retained edit, on a project large enough
// that lowering and assembly actually run on workers.
import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const modules = 18;
const functions = 32;
const groups = 4;

function moduleSource(module: number, bump: number): string {
  const lines = [];
  for (let f = 0; f < functions; f++) {
    lines.push(
      `const f${module}_${f} = func (value: U32) => return if @u32.lt value ${f} then @u32.add value ${
        module * 1000 + f + bump
      } else @u32.mul (@u32.add value ${f}) ${(f % 5) + 1}`,
    );
  }
  const size = functions / groups;
  for (let g = 0; g < groups; g++) {
    let sum = `(f${module}_${g * size} value)`;
    for (let f = g * size + 1; f < (g + 1) * size; f++) {
      sum = `@u32.add (${sum}) (f${module}_${f} value)`;
    }
    lines.push(`const g${module}_${g} = func (value: U32) => return ${sum}`);
  }
  return lines.join("\n") + "\n";
}

function entrySource(): string {
  const lines = [];
  let sum = "0";
  for (let m = 0; m < modules; m++) {
    const names = Array.from({ length: groups }, (_, g) => `g${m}_${g}`);
    lines.push(`import {${names.join(", ")}} from "./m${m}"`);
    for (const name of names) sum = `@u32.add (${sum}) (${name} value)`;
  }
  lines.push(`entry const run: U32 -> U32 = func value => return ${sum}`);
  return lines.join("\n") + "\n";
}

async function project(directory: string, bumps: number[]) {
  const sources: Record<string, string> = {
    [`${directory}/main.blot`]: entrySource(),
  };
  for (let m = 0; m < modules; m++) {
    sources[`${directory}/m${m}.blot`] = moduleSource(m, bumps[m]);
  }
  for (const [path, text] of Object.entries(sources)) {
    await Deno.writeTextFile(path, text);
  }
  return sources;
}

Deno.test("frontend and lowering workers emit identical Wasm and diagnostics for every worker count", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-workers-" });
  const base = {
    executable,
    entry: `${directory}/main.blot`,
    prelude: null,
  };
  try {
    const zero = Array.from({ length: modules }, () => 0);
    const original = await project(directory, zero);
    // The edit changes two dependencies, so a retained build lowers both.
    const edited = { ...original };
    edited[`${directory}/m1.blot`] = moduleSource(1, 7);
    edited[`${directory}/m4.blot`] = moduleSource(4, 9);
    const broken = { ...original };
    broken[`${directory}/m2.blot`] += "const wrong: U32 = func value => return value\n";
    broken[`${directory}/m5.blot`] += "const other: U32 = func value => return value\n";
    const results: Uint8Array[][] = [];
    const rejections: unknown[] = [];
    const counts = [[1, 1], [2, 1], [4, 1], [1, 4], [4, 4]];
    for (const [semanticWorkers, frontendWorkers] of counts) {
      const compiler = await createZigProjectCompiler({
        ...base,
        semanticWorkers,
        frontendWorkers,
        profileBackend: true,
      });
      try {
        const bytes = [];
        for (const sources of [original, edited, original]) {
          const result = await compiler.build({ sources });
          assert(result.success, JSON.stringify(result));
          if (frontendWorkers > 1 && Deno.build.os === "linux") {
            if (bytes.length === 0) {
              const { checking } = result.stats.phaseProfile as {
                checking: Record<string, number>;
              };
              assert.equal(checking.parallel_batches, 1);
              assert.equal(checking.parallel_retries, 0);
              assert(checking.parallel_jobs >= modules);
              assert(checking.parallel_worker_processes > 0);
              assert(checking.parallel_worker_processes < checking.parallel_worker_jobs);
              assert(checking.parallel_worker_reply_bytes > 0);
            } else {
              assert.equal(result.stats.freshModules, 3);
              assert.equal(result.stats.cachedModules, modules - 2);
            }
          }
          bytes.push(result.bytes);
        }
        const rejected = await compiler.build({ sources: broken });
        assert(!rejected.success);
        rejections.push(rejected.diagnostics);
        const recovered = await compiler.build({ sources: original });
        assert(recovered.success);
        assert.deepEqual(recovered.bytes, bytes[0]);
        if (frontendWorkers > 1 && Deno.build.os === "linux") {
          assert.equal(recovered.stats.freshModules, 0);
        }
        results.push(bytes);
      } finally {
        await compiler.dispose();
      }
    }
    for (const bytes of results.slice(1)) assert.deepEqual(bytes, results[0]);
    for (const issues of rejections.slice(1)) {
      assert.deepEqual(issues, rejections[0]);
    }
    assert.deepEqual(results[0][2], results[0][0]);
    assert.notDeepEqual(results[0][1], results[0][0]);
    const guest = await instantiateGuest(results[0][0]);
    try {
      assert.equal(typeof guest.call("run", 3), "number");
    } finally {
      guest.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("project workers preserve the exact associated type budget across imports", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-worker-budget-" });
  try {
    await Deno.writeTextFile(
      `${directory}/shared.blot`,
      [
        "type Identity a is contract = { type Item = a }",
        "type Read a is contract = { const read: a -> U32 }",
        "impl ReadU32 : Read U32 = { const read = func value => return @u32.add value 1 }",
        "func generic (value: a): U32 where { Read a } => return Read.read value",
        "func unwrap value => return value.number",
      ].join("\n") + "\n",
    );
    const lines = [];
    let sum = "value";
    for (let index = 0; index < 18; index++) {
      const body = [
        'import * as shared from "./shared"',
        "type Marker = shared.Identity.Item U32",
      ];
      for (let f = 0; f < 4; f++) {
        body.push(
          `func read${f} (value: U32): U32 => return shared.unwrap {number: shared.generic value}`,
        );
      }
      await Deno.writeTextFile(`${directory}/m${index}.blot`, body.join("\n") + "\n");
      lines.push(`import { read0 as value${index} } from "./m${index}"`);
      sum = `@u32.add (${sum}) (value${index} value)`;
    }
    lines.push(`entry func run (value: U32): U32 => return ${sum}`);
    const entry = `${directory}/main.blot`;
    await Deno.writeTextFile(entry, lines.join("\n") + "\n");
    for (const inferenceBudget of [16_862, 16_861]) {
      const outcomes = [];
      for (const frontendWorkers of [1, 4]) {
        const compiler = await createZigProjectCompiler({
          entry,
          executable,
          inferenceBudget,
          frontendWorkers,
          prelude: null,
          profileBackend: true,
        });
        try {
          const result = await compiler.build();
          assert.equal(result.success, inferenceBudget === 16_862);
          if (result.success) {
            if (frontendWorkers === 4 && Deno.build.os === "linux") {
              const profile = result.stats.phaseProfile as { checking: Record<string, number> };
              assert.equal(profile.checking.parallel_batches, 1);
              assert.equal(profile.checking.imported_summary_reuses, 18);
            }
            outcomes.push(result.bytes);
          } else {
            assert.equal(result.diagnostics[0].code, "associated_limit");
            outcomes.push(result.diagnostics);
          }
        } finally {
          await compiler.dispose();
        }
      }
      assert.deepEqual(outcomes[1], outcomes[0]);
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
