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
  lines.push(`#entry const run: U32 -> U32 = func value => return ${sum}`);
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
              // Both implementations changed. Their caller sees identical interfaces.
              assert.equal(result.stats.freshModules, 2);
              assert.equal(result.stats.cachedModules, modules - 1);
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

Deno.test("parallel import discovery skips pipes and preserves the serial syntax diagnostic", async () => {
  if (Deno.build.os !== "linux") return;
  const directory = await Deno.makeTempDir({ prefix: "blot-import-discovery-" });
  try {
    const files = await project(directory, Array(modules).fill(0));
    const entry = directory + "/main.blot";
    // Neither a hidden overlay nor a FIFO named by a malformed module is an input.
    files[entry] = 'import * as ignored from "./pipe"\n' +
      'import * as hidden from "./absent"\n' + files[entry] + "func invalid => )\n";
    const pipe = await new Deno.Command("mkfifo", { args: [directory + "/pipe.blot"] }).output();
    assert(pipe.success);
    const sources = { ...files, [directory + "/absent.blot"]: null };
    let serial;
    for (const frontendWorkers of [1, 8]) {
      const compiler = await createZigProjectCompiler({ executable, entry, prelude: null, frontendWorkers });
      try {
        const result = await compiler.build({ sources, signal: AbortSignal.timeout(5000) });
        assert(!result.success);
        assert.equal(result.diagnostics[0].stage, "parse-project");
        if (frontendWorkers === 1) serial = result.diagnostics;
        else assert.deepEqual(result.diagnostics, serial);
      } finally {
        await compiler.dispose();
      }
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
        "type Identity a { item } is trait = { id: a -> item }",
        "const U32.Identity: Identity U32 { item: U32 } = { id: func value => return value }",
        "type Read a is trait = { read: a -> U32 }",
        "const U32.Read: Read U32 = { read: func value => return @u32.add value 1 }",
        "func generic (value: a): U32 where { Read a } => return Read.read value",
        "func unwrap value => return value.number",
      ].join("\n") + "\n",
    );
    const lines = [];
    let sum = "value";
    for (let index = 0; index < 18; index++) {
      const body = [
        'import * as shared from "./shared"',
        "type Marker = shared.Identity.item U32",
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
    lines.push(`#entry func run (value: U32): U32 => return ${sum}`);
    const entry = `${directory}/main.blot`;
    await Deno.writeTextFile(entry, lines.join("\n") + "\n");
    for (const inferenceBudget of [18_133, 18_132]) {
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
          assert.equal(result.success, inferenceBudget === 18_133);
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

Deno.test("staged imports use parallel workers and observe current Core after a retained edit", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-staged-workers-" });
  const entry = directory + "/main.blot";
  const provider = directory + "/math.blot";
  try {
    const imports = ['import { plus, base, spin } from "./math"'];
    for (let index = 0; index < 15; index++) {
      imports.push(`import * as side${index} from "./side${index}"`);
      await Deno.writeTextFile(`${directory}/side${index}.blot`, `const v = ${index}\n`);
    }
    const main = (expr: string) => imports.join("\n") + "\n#entry func answer (arg: U32): U32 => return " + expr + "\n";
    const source = (base: number) => `const base: Bool = ${base === 40}\nfunc plus (a: U32) -> (b: U32): U32 => return @u32.add a b\nfunc spin (n: U32): U32 => return spin n\n`;
    const staged = main("(#run (plus (if base then 40 else 41) 2))");
    await Deno.writeTextFile(entry, staged);
    await Deno.writeTextFile(provider, source(40));
    const lanes: { bytes: Uint8Array[]; diagnoses: unknown[] }[] = [];
    for (const frontendWorkers of [1, 4]) {
      const compiler = await createZigProjectCompiler({ executable, entry, prelude: null, frontendWorkers, profileBackend: true });
      const bytes: Uint8Array[] = [];
      const diagnoses = [];
      try {
        for (const base of [40, 41]) {
          const result = await compiler.build({ sources: { [entry]: staged, [provider]: source(base) } });
          if (!result.success) throw new Error(JSON.stringify(result.diagnostics));
          if (frontendWorkers > 1 && Deno.build.os === "linux") {
            if (base === 40) {
              const profile = result.stats.phaseProfile as { checking: Record<string, number> };
              assert.equal(profile.checking.parallel_worker_jobs, 17);
              assert.equal(profile.checking.parallel_retries, 0);
            } else { assert.equal(result.stats.freshModules, 1); }
          }
          const guest = await instantiateGuest(result.bytes);
          try { assert.equal(guest.call("answer", 0), base + 2); } finally { guest.dispose(); }
          bytes.push(result.bytes);
        }
        const literal = await compiler.build({ sources: { [entry]: main("43"), [provider]: source(41) } });
        assert(literal.success);
        assert.deepEqual(literal.bytes, bytes[1]);
        for (const [operand, cause] of [
          ["plus arg 2", "runtime binding"],
          ["@u32.div 1 0", "division by zero"],
          ["spin 0", "evaluation budget"],
        ]) {
          const result = await compiler.build({ sources: { [entry]: main(`(#run (${operand}))`), [provider]: source(41) } });
          assert(!result.success);
          assert(result.diagnostics.some(d => d.message.includes(cause)), JSON.stringify(result.diagnostics));
          diagnoses.push(result.diagnostics);
        }
        const recovery = await compiler.build({ sources: { [entry]: staged, [provider]: source(40) } });
        assert(recovery.success);
        assert.deepEqual(recovery.bytes, bytes[0]);
      } finally { await compiler.dispose(); }
      lanes.push({ bytes, diagnoses });
    }
    assert.deepEqual(lanes[0], lanes[1]);
  } finally { await Deno.remove(directory, { recursive: true }); }
});
