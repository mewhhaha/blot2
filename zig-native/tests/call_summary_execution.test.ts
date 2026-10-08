import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import {
  chainGeneric,
  chainMono,
  diamond,
} from "../../scripts/bench/corpus.ts";
import { compileAndRun } from "./compile_helpers.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;

Deno.test("summary jobs preserve executed deep chains and shared diamonds", async () => {
  for (
    const [program, increment] of [
      [chainMono(1000), 1001],
      [chainGeneric(300), 301],
      [diamond(16), 65536],
    ] as const
  ) {
    await compileAndRun(program.source, (guest) => {
      assert.equal(guest.call("main", 7), 7 + increment);
      assert.equal(guest.call("main", 0xffff_ffff), increment - 1);
    });
  }
});

function chain(leaf: string, depth: number): string {
  const lines = [leaf];
  for (let i = 1; i <= depth; i++) {
    lines.push(`const f_${i} = fn value => f_${i - 1} value`);
  }
  return lines.join("\n") + "\n";
}

Deno.test("failed summary jobs retain leaf diagnostics beyond the former depth limit", async () => {
  const directory = await Deno.makeTempDir();
  const input = `${directory}/main.blot`;
  try {
    for (
      const leaf of [
        "const f_0 = fn value => value + value",
        "const f_0 = fn value => @u32.add value #True",
      ]
    ) {
      const diagnostics = [];
      for (const depth of [0, 300]) {
        await Deno.writeTextFile(
          input,
          chain(leaf, depth) +
            `entry const answer = fn () => f_${depth} ${
              leaf.includes("@u32") ? "0" : "#True"
            }\n`,
        );
        const result = await new Deno.Command(executable, {
          args: [
            "build",
            input,
            `${directory}/main.wasm`,
            "--prelude",
            prelude,
          ],
          stdout: "piped",
          stderr: "piped",
        }).output();
        assert(!result.success);
        const records = new TextDecoder().decode(result.stdout).trim().split(
          "\n",
        )
          .map((line) => JSON.parse(line));
        const errors = records.filter((record) => record.kind === "diagnostic");
        assert(errors.length > 0, new TextDecoder().decode(result.stderr));
        assert(errors.every((record) => record.code !== "constant_fuel"));
        assert.equal(
          records.find((record) => record.kind === "compilation").memory
            .live_bytes,
          0,
        );
        diagnostics.push(errors);
      }
      assert.deepEqual(diagnostics[1], diagnostics[0]);
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("summary jobs survive dependencies checkpoints edits and failed revision recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const bundle = `${directory}/library.blotdep`;
  const source = (value: string) =>
    chain(`const f_0 = fn value => @u32.add value ${value}`, 300);
  const options = { executable, entry, prelude: null };
  try {
    await Deno.writeTextFile(library, source("1"));
    await Deno.writeTextFile(
      entry,
      'import { f_300 } from "./library"\nentry const answer = fn (value: U32) => f_300 value\n',
    );
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stdout));
    const producer = await createZigProjectCompiler(options);
    let checkpoint: Uint8Array<ArrayBuffer>;
    let expected: Uint8Array<ArrayBuffer>;
    try {
      const first = await producer.build();
      assert(first.success, JSON.stringify(first));
      expected = first.bytes;
      checkpoint = await producer.exportCheckpoint();
    } finally {
      await producer.dispose();
    }
    const retained = await createZigProjectCompiler({
      ...options,
      dependencies: bundle,
      checkpoint,
    });
    try {
      const restored = await retained.build();
      assert(restored.success, JSON.stringify(restored));
      assert(restored.stats.cachedModules > 0);
      assert.deepEqual(restored.bytes, expected);
      for (const value of ["2", "#True", "1"]) {
        const sources = { [library]: source(value) };
        const current = await retained.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const reference = await fresh.build({ sources });
          assert.equal(current.success, reference.success);
          if (current.success && reference.success) {
            assert.deepEqual(current.bytes, reference.bytes);
            assert.equal(
              current.stats.nativeWorkSteps,
              reference.stats.nativeWorkSteps,
            );
            const guest = await instantiateGuest(current.bytes);
            try {
              assert.equal(guest.call("answer", 40), 40 + Number(value));
            } finally {
              guest.dispose();
            }
          } else if (!current.success && !reference.success) {
            assert.deepEqual(current.diagnostics, reference.diagnostics);
          }
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await retained.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
