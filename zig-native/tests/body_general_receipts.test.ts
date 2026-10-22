import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = (seed: string, delta: number, prefix = "") =>
  `infixl 60 (%%) = both
infixl 60 (??) = ignore
${prefix}const seed = ${seed}
type Number is data = #Number U32
const Number.next = fn (#Number value) => @u32.add value ${delta}
const both = fn ~(left: U32) => fn ~(right: U32) => @u32.add (@u32.add (@force left) (@force left)) (@force right)
const ignore = fn ~(left: U32) => fn ~(right: U32) => 7
const operate = fn (host: U32 -> U32 ! {Foreign}) => @u32.add ((host seed) %% (host (@u32.add seed 1))) ((host 999) ?? (host 998))
const describe = fn (value: U32) => do:
  let record = {value, values: #[value, seed]}
  record.value := @u32.add self 1
  break @record.merge record {next: (#Number value).next}
`;
const main = `import {operate, describe} from "./logic"
entry const run = fn (host: U32 -> U32 ! {Foreign}) => operate host
entry const method = fn (value: U32) => do:
  let record = describe value
  break @u32.add record.value record.next
entry const owned = fn (value: U32) => (describe value).values
`;
async function observe(
  bytes: Uint8Array<ArrayBuffer>,
  seed: number,
  delta: number,
) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    const trace: number[] = [];
    let fail = false;
    const failure = new Error("binary demand host failed");
    const implementation = {
      parameter: "U32" as const,
      result: "U32" as const,
      call(value: number) {
        trace.push(value);
        if (fail) throw failure;
        return value + 10;
      },
    };
    let host = guest.capability(implementation);
    if (asynchronous) host = guest.capabilityAsync(implementation);
    const call = async () => {
      if (asynchronous) return await guest.callAsync("run", host);
      return guest.call("run", host);
    };
    try {
      assert.equal(await call(), 3 * seed + 38);
      assert.deepEqual(trace, [seed, seed + 1]);
      fail = true;
      await assert.rejects(
        call,
        (error: unknown) => error instanceof Error && error.cause === failure,
      );
      fail = false;
      trace.length = 0;
      assert.equal(await call(), 3 * seed + 38);
      assert.deepEqual(trace, [seed, seed + 1]);
      for (let value = 0; value < 16; value++) {
        let method;
        let owned;
        if (asynchronous) {
          method = await guest.callAsync("method", value);
          owned = await guest.callAsync("owned", value);
        } else {
          method = guest.call("method", value);
          owned = guest.call("owned", value);
        }
        assert.equal(method, 2 * value + 1 + delta);
        assert.deepEqual(owned, Uint32Array.of(value, seed));
      }
    } finally {
      guest.dispose();
    }
  }
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`general body receipts preserve binary demand effects method edits and owning records (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-general-bodies-",
    });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/logic.blot`;
    const archive = `${directory}/logic.blotdep`;
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(dependency, library("2", 1));
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stdout));
    const options = {
      executable,
      entry,
      prelude: null,
      cacheDirectory: false as const,
      codegenTier,
    };
    const retained = await createZigProjectCompiler(options);
    const compiled = await createZigProjectCompiler({
      ...options,
      dependencies: archive,
    });
    const prefix = "const earlier = fn (value: F32) => @f32.add value 1.0\n";
    try {
      for (
        const [seed, delta, inserted] of [
          ["2", 1, ""],
          ["3", 1, prefix],
          ["3", 2, prefix],
          ["missing_name", 2, prefix],
          ["2", 1, ""],
        ] as const
      ) {
        const fresh = await createZigProjectCompiler(options);
        try {
          const sources = {
            [entry]: main,
            [dependency]: library(seed, delta, inserted),
          };
          const expected = await fresh.build({ sources });
          for (const compiler of [retained, compiled]) {
            let checkpoint: Uint8Array<ArrayBuffer> | undefined;
            if (seed === "missing_name") {
              checkpoint = await compiler.exportCheckpoint();
            }
            const actual = await compiler.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert(!actual.success && !expected.success);
              assert.equal(
                seed,
                "missing_name",
                JSON.stringify(actual.diagnostics),
              );
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            assert.equal(
              actual.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            await observe(actual.bytes, Number(seed), delta);
          }
        } finally {
          await fresh.close();
        }
      }
    } finally {
      await retained.close();
      await compiled.close();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
