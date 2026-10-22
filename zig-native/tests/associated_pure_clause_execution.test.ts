import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = (offset: number, effect = "") =>
  `const identity: forall [a] => a -> a = fn value => value
type Number is data = #Number U32
const Number.add = fn (#Number left) => fn (#Number right) => do:
${effect}  break #Number (@u32.add (@u32.add left right) ${offset})
const twice: a -> a where {associated "add" a a a} = fn value => @type.call "add" value value
const alias = twice
const generic = fn value => alias value
const answer = fn () => case generic (#Number 21) of
  #Number value => identity value
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`pure associated clauses retain their invocation equation (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-pure-clause-" });
    const entry = `${directory}/main.blot`;
    const producer = `${directory}/logic.blot`;
    const archive = `${directory}/logic.blotdep`;
    const main =
      'import {answer} from "./logic"\nentry const probe = fn () => answer ()\n';
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(producer, library(0));
    const options = {
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false as const,
    };
    try {
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, archive, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(
        packed.success,
        new TextDecoder().decode(packed.stdout) +
          new TextDecoder().decode(packed.stderr),
      );
      for (const mode of [options, { ...options, dependencies: archive }]) {
        const retained = await createZigProjectCompiler(mode);
        try {
          for (const offset of [0, 1, 0]) {
            const sources = { [entry]: main, [producer]: library(offset) };
            const fresh = await createZigProjectCompiler(options);
            try {
              const expected = await fresh.build({ sources });
              const built = await retained.build({ sources });
              assert(expected.success, JSON.stringify(expected));
              assert(built.success, JSON.stringify(built));
              assert.deepEqual(built.bytes, expected.bytes);
              assert.equal(
                built.stats.nativeWorkSteps,
                expected.stats.nativeWorkSteps,
              );
              for (const asynchronous of [false, true]) {
                const guest = await instantiateGuest(built.bytes, {
                  asynchronous,
                });
                try {
                  let result;
                  if (asynchronous) {
                    result = await guest.callAsync("probe", null);
                  } else result = guest.call("probe", null);
                  assert.equal(result, 42 + offset);
                } finally {
                  guest.dispose();
                }
              }
              const checkpoint = await retained.exportCheckpoint();
              const failed = await retained.build({
                sources: {
                  ...sources,
                  [producer]: library(
                    offset,
                    "  use owner <- @resource.acquire (fn () => ()) (fn value => ())\n  use @resource.release owner\n",
                  ),
                },
              });
              assert(!failed.success, JSON.stringify(failed));
              assert(
                failed.diagnostics.some((diagnostic) =>
                  diagnostic.code === "effect_mismatch"
                ),
              );
              assert.deepEqual(await retained.exportCheckpoint(), checkpoint);
              const recovered = await retained.build({ sources });
              assert(recovered.success, JSON.stringify(recovered));
              assert.deepEqual(recovered.bytes, expected.bytes);
              assert.equal(recovered.stats.nativeWorkSteps, 0);
              const restarted = await createZigProjectCompiler({
                ...options,
                checkpoint,
              });
              try {
                const replay = await restarted.build({ sources });
                assert(replay.success, JSON.stringify(replay));
                assert.deepEqual(replay.bytes, expected.bytes);
              } finally {
                await restarted.dispose();
              }
            } finally {
              await fresh.dispose();
            }
          }
        } finally {
          await retained.dispose();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
