import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0];
assert(executable);
const header =
  "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\n" +
  "impl ScalarSource : Source U32 = {\n  type Item = U32,\n  const first = func value => return @u32.add value 1,\n}\n";
const hidden =
  "private type Hidden a is contract = { type Item }\nprivate impl HiddenSource : Hidden F32 = { type Item = F32 }\n";
for (const selected of [false, true]) {
  const initial = header +
    "opaque type Token = U32\nconst make: U32 -> Token = func value => return $Token value\n" +
    `const read: Token -> U32 = func ($Token value) => return ${
      selected ? "Source.first value" : "value"
    }\n`;
  const variants = [
    initial,
    "private const unrelated = 99\n" + initial,
    hidden + initial,
    initial.replaceAll("value", "item"),
    initial.replace("@u32.add value 1", "@u32.add value 300"),
    initial,
  ];
  for (const codegenTier of ["development", "optimized"] as const) {
    Deno.test(`bounded implementation cutoff preserves ${selected ? "selected" : "unused"} catalogs archives checkpoints and revocation (${codegenTier})`, async () => {
      const directory = await Deno.makeTempDir({
        prefix: "blot-implementation-cutoff-",
      });
      const entry = directory + "/main.blot",
        producer = directory + "/tokens.blot",
        archive = directory + "/dependencies.blotdep";
      try {
        await Deno.writeTextFile(producer, initial);
        await Deno.writeTextFile(
          directory + "/bridge.blot",
          'export {Source, ScalarSource} from "./tokens"\nimport {make, read} from "./tokens"\nconst consume: U32 -> U32 = func value => return read (make value)\n',
        );
        await Deno.writeTextFile(
          entry,
          'import {consume} from "./bridge"\nentry const answer: U32 -> U32 = func value => return consume value\n',
        );
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
        const options = {
          executable,
          entry,
          prelude: null,
          cacheDirectory: false as const,
          codegenTier,
          codegenWorkers: 1,
        };
        for (const dependencies of [undefined, archive]) {
          const retained = await createZigProjectCompiler({
            ...options,
            dependencies,
          });
          try {
            for (let phase = 0; phase < variants.length; phase++) {
              const text = variants[phase], sources = { [producer]: text };
              const built = await retained.build({ sources });
              assert(built.success, JSON.stringify(built));
              if (phase !== 0) {
                const work = built.stats.attemptStats.fallback as {
                  module_cutoff: { reused: number };
                  entry_cutoff: { reused: number };
                };
                assert.equal(
                  work.module_cutoff.reused,
                  1,
                  `phase ${phase}: module`,
                );
                assert.equal(
                  work.entry_cutoff.reused,
                  1,
                  `phase ${phase}: entry`,
                );
              }
              const fresh = await createZigProjectCompiler(options);
              try {
                const control = await fresh.build({ sources });
                assert(control.success, JSON.stringify(control));
                assert.deepEqual(built.bytes, control.bytes);
              } finally {
                await fresh.dispose();
              }
              const checkpoint = await retained.exportCheckpoint();
              const failed = await retained.build({
                sources: {
                  [producer]: text.replace("make: U32", "make: Bool"),
                },
              });
              assert(!failed.success);
              assert.deepEqual(await retained.exportCheckpoint(), checkpoint);
              const recovered = await retained.build({ sources });
              assert(recovered.success, JSON.stringify(recovered));
              assert.deepEqual(recovered.bytes, built.bytes);
              const restarted = await createZigProjectCompiler({
                ...options,
                checkpoint,
              });
              try {
                const restored = await restarted.build({ sources });
                assert(restored.success, JSON.stringify(restored));
                assert.deepEqual(restored.bytes, built.bytes);
                for (const bytes of [built.bytes, restored.bytes]) {
                  const guest = await instantiateGuest(bytes);
                  try {
                    for (let call = 0; call < 50; call++) {
                      for (const value of [0, 1, 42, 0xffffffff]) {
                        assert.equal(
                          guest.call("answer", value),
                          (value + (selected ? (phase === 4 ? 300 : 1) : 0)) >>>
                            0,
                        );
                      }
                    }
                  } finally {
                    guest.dispose();
                  }
                }
              } finally {
                await restarted.dispose();
              }
            }
            const changedType = initial.replace(
              "type Item = U32",
              "type Item = F32",
            ).replace("@u32.add value 1", "@u32.to_f32 (@u32.add value 1)");
            const changedHead = initial.replace(
              "ScalarSource : Source U32",
              "ScalarSource : Source F32",
            ).replace("@u32.add value 1", "@u32.add (@f32.to_u32 value) 1");
            const addedCandidate = initial +
              "impl FloatSource : Source F32 = { type Item = F32, const first = func value => return value }\n";
            for (
              const [text, success] of [
                [changedType, !selected],
                [changedHead, !selected],
                [addedCandidate, true],
                [
                  initial.replace(
                    "impl ScalarSource",
                    "private impl ScalarSource",
                  ),
                  false,
                ],
              ] as const
            ) {
              const checkpoint = await retained.exportCheckpoint(),
                sources = { [producer]: text };
              const built = await retained.build({ sources });
              assert.equal(built.success, success, JSON.stringify(built));
              const stats = built.success
                ? built.stats.attemptStats
                : built.attemptStats;
              assert(stats);
              const work = stats.fallback as {
                module_cutoff: { reused: number };
                entry_cutoff: { reused: number };
              };
              assert.equal(
                work.module_cutoff.reused,
                0,
                "changed catalog: module",
              );
              assert.equal(
                work.entry_cutoff.reused,
                0,
                "changed catalog: entry",
              );
              if (!built.success) {
                assert.deepEqual(await retained.exportCheckpoint(), checkpoint);
              }
              const fresh = await createZigProjectCompiler(options);
              try {
                const control = await fresh.build({ sources });
                assert.equal(control.success, success);
                if (built.success && control.success) {
                  assert.deepEqual(built.bytes, control.bytes);
                } else if (!built.success && !control.success) {
                  assert.deepEqual(built.diagnostics, control.diagnostics);
                }
              } finally {
                await fresh.dispose();
              }
              const recovered = await retained.build({
                sources: { [producer]: initial },
              });
              assert(recovered.success, JSON.stringify(recovered));
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
}
