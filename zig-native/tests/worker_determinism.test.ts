// Worker counts are execution choices: every count must emit the same Wasm
// and diagnostics, fresh and after a retained edit, on a project large enough
// that lowering and assembly actually run on workers.
import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const modules = 6;
const functions = 96;
const groups = 8;

function moduleSource(module: number, bump: number): string {
  const lines = [];
  for (let f = 0; f < functions; f++) {
    lines.push(
      `const f${module}_${f} = fn (value: U32) => if @u32.lt value ${f} then @u32.add value ${
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
    lines.push(`const g${module}_${g} = fn (value: U32) => ${sum}`);
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
  lines.push(`entry const run: U32 -> U32 = fn value => ${sum}`);
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

Deno.test("frontend lowering and codegen workers emit identical Wasm and diagnostics for every worker count", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-workers-" });
  const base = {
    executable,
    entry: `${directory}/main.blot`,
    prelude: null,
    cacheDirectory: false as const,
  };
  try {
    const zero = Array.from({ length: modules }, () => 0);
    const original = await project(directory, zero);
    // The edit changes two dependencies, so a retained build lowers both.
    const edited = { ...original };
    edited[`${directory}/m1.blot`] = moduleSource(1, 7);
    edited[`${directory}/m4.blot`] = moduleSource(4, 9);
    const broken = { ...original };
    broken[`${directory}/m2.blot`] += "const wrong: U32 = fn value => value\n";
    broken[`${directory}/m5.blot`] += "const other: U32 = fn value => value\n";
    const results: Uint8Array[][] = [];
    const rejections: unknown[] = [];
    const counts = [[1, 1, 1], [2, 1, 1], [4, 1, 1], [1, 4, 1], [4, 4, 1], [
      1,
      1,
      4,
    ], [4, 4, 4]];
    for (const [semanticWorkers, codegenWorkers, frontendWorkers] of counts) {
      const compiler = await createZigProjectCompiler({
        ...base,
        semanticWorkers,
        codegenWorkers,
        frontendWorkers,
        profileBackend: true,
      });
      try {
        const bytes = [];
        for (const sources of [original, edited, original]) {
          const result = await compiler.build({ sources });
          assert(result.success, JSON.stringify(result));
          if (bytes.length === 0 && frontendWorkers > 1) {
            const profile = result.stats.phaseProfile as {
              checking: Record<string, number>;
            };
            assert(profile.checking.parallel_jobs >= modules);
            assert.equal(profile.checking.parallel_retries, 0);
          }
          bytes.push(result.bytes);
        }
        const rejected = await compiler.build({ sources: broken });
        assert(!rejected.success);
        rejections.push(rejected.diagnostics);
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
