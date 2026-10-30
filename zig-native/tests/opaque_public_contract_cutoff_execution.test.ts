import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0];
assert(executable);
const header = "type Public a is contract = {type_rep a}\n";
for (const usedContract of [false, true]) {
  const body = "opaque type Token = U32\n" +
    (usedContract
      ? "const keep: a -> a where {Public a} = func value => return value\n"
      : "") +
    (usedContract
      ? "const make: U32 -> Token = func value => return #Token (keep value)\n"
      : "const make: U32 -> Token = func value => return #Token value\n") +
    "const read: Token -> U32 = func (#Token value) => return value\n";
  const initial = header + body;
  const variants = [
    initial,
    header + "private const unrelated = 99\n" + body,
    "private type Hidden a is contract = {type_rep a}\n" + initial,
    "type Public item is contract = {type_rep item}\n" + body,
    initial,
  ];
  for (const codegenTier of ["development", "optimized"] as const) {
    Deno.test(`${usedContract ? "used" : "unused"} public contract cutoff preserves forwarding archives checkpoints and revocation (${codegenTier})`, async () => {
      const directory = await Deno.makeTempDir({
        prefix: "blot-public-contract-cutoff-",
      });
      const entry = directory + "/main.blot",
        producer = directory + "/tokens.blot";
      const bundle = directory + "/dependencies.blotdep";
      try {
        await Deno.writeTextFile(producer, initial);
        await Deno.writeTextFile(
          directory + "/bridge.blot",
          'import {make, read} from "./tokens"\nexport {Public} from "./tokens"\nconst consume: U32 -> U32 = func value => return read (make value)\n',
        );
        await Deno.writeTextFile(
          entry,
          'import {Public, consume} from "./bridge"\nentry const answer: U32 -> U32 = func value => return consume value\n',
        );
        const packed = await new Deno.Command(executable, {
          args: ["dependencies", entry, bundle, "--prelude", "none"],
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
        };
        for (const dependencies of [undefined, bundle]) {
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
                        assert.equal(guest.call("answer", value), value);
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
            const changed = initial.replace("type_rep a", "type_rep U32");
            const sources = { [producer]: changed };
            const invalidated = await retained.build({ sources });
            assert(invalidated.success, JSON.stringify(invalidated));
            const work = invalidated.stats.attemptStats.fallback as {
              module_cutoff: { reused: number };
              entry_cutoff: { reused: number };
            };
            assert.equal(
              work.module_cutoff.reused,
              0,
              "changed public predicate: module",
            );
            assert.equal(
              work.entry_cutoff.reused,
              0,
              "changed public predicate: entry",
            );
            const fresh = await createZigProjectCompiler(options);
            try {
              const control = await fresh.build({ sources });
              assert(control.success, JSON.stringify(control));
              assert.deepEqual(invalidated.bytes, control.bytes);
            } finally {
              await fresh.dispose();
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
