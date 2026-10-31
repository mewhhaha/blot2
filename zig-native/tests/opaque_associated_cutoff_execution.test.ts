import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0];
assert(executable);
const initial = "opaque type Token = U32\nopaque type Other = U32\n" +
  "const make: U32 -> Token = func value => return $Token value\n" +
  "const make_other: U32 -> Other = func value => return $Other value\n" +
  "const Token.read: Token -> U32 = func ($Token value) => return value\n" +
  "const Other.read: Other -> U32 = func ($Other value) => return @u32.add value 1\n";
const variants = [
  initial,
  "private const unrelated = 99\n" + initial,
  "private type Spare is data = $Spare U32\n" + initial,
  initial.replaceAll("value", "item"),
  initial,
];
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`associated cutoff preserves original receivers archives checkpoints and revocation (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-associated-cutoff-",
    });
    const entry = directory + "/main.blot",
      producer = directory + "/tokens.blot";
    const archive = directory + "/dependencies.blotdep";
    try {
      await Deno.writeTextFile(producer, initial);
      await Deno.writeTextFile(
        directory + "/bridge.blot",
        'import {Token, Other, make, make_other} from "./tokens"\nconst consume: U32 -> U32 = func value => return @u32.add ((make value).read) ((make_other value).read)\n',
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
              sources: { [producer]: text.replace("make: U32", "make: Bool") },
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
                        (2 * value + 1) >>> 0,
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
          for (
            const changed of [
              initial.replace(
                "const Token.read: Token -> U32 = func ($Token value) => return value",
                "const Token.read: Token -> F32 = func ($Token value) => return @u32.to_f32 value",
              ),
              initial.replace("const Token.read", "private const Token.read"),
            ]
          ) {
            const checkpoint = await retained.exportCheckpoint();
            const sources = { [producer]: changed };
            const rejected = await retained.build({ sources });
            assert(!rejected.success);
            assert(rejected.attemptStats);
            const work = rejected.attemptStats.fallback as {
              module_cutoff: { reused: number };
              entry_cutoff: { reused: number };
            };
            assert.equal(
              work.module_cutoff.reused,
              0,
              "changed relationship: module",
            );
            assert.equal(
              work.entry_cutoff.reused,
              0,
              "changed relationship: entry",
            );
            assert.deepEqual(await retained.exportCheckpoint(), checkpoint);
            const fresh = await createZigProjectCompiler(options);
            try {
              const control = await fresh.build({ sources });
              assert(!control.success);
              assert.deepEqual(rejected.diagnostics, control.diagnostics);
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

Deno.test("symbolic opaque getters retain package authority through archives restart and failed privacy edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-package-getter-" });
  const entry = directory + "/main.blot", producer = directory + "/tokens.blot";
  const archive = directory + "/dependencies.blotdep";
  try {
    await Deno.writeTextFile(producer, initial);
    await Deno.writeTextFile(
      directory + "/bridge.blot",
      'import {make, make_other} from "./tokens"\n' +
        "type Capsule = exists [a] => a\n" +
        "const capsule: Capsule = pack [U32] 0 as Capsule\n" +
        "const consume: U32 -> U32 = func value => return @u32.add ((make value).read) ((make_other value).read)\n",
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
    for (const codegenTier of ["development", "optimized"] as const) {
      for (const dependencies of [undefined, archive]) {
        const options = {
          executable,
          entry,
          dependencies,
          prelude: null,
          cacheDirectory: false as const,
          codegenTier,
          codegenWorkers: 1,
        };
        const compiler = await createZigProjectCompiler(options);
        try {
          const built = await compiler.build({});
          assert(built.success, JSON.stringify(built));
          const checkpoint = await compiler.exportCheckpoint();
          const restarted = await createZigProjectCompiler({
            ...options,
            checkpoint,
          });
          try {
            const replayed = await restarted.build({});
            assert(replayed.success, JSON.stringify(replayed));
            assert.deepEqual(replayed.bytes, built.bytes);
            for (const bytes of [built.bytes, replayed.bytes]) {
              const guest = await instantiateGuest(bytes);
              try {
                for (let value = 0; value < 100; value++) {
                  assert.equal(guest.call("answer", value), 2 * value + 1);
                }
              } finally {
                guest.dispose();
              }
            }
          } finally {
            await restarted.dispose();
          }
          const failed = await compiler.build({
            sources: {
              [producer]: initial.replace(
                "const Token.read:",
                "private const Token.read:",
              ),
            },
          });
          assert(!failed.success);
          assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          const recovered = await compiler.build({
            sources: { [producer]: initial },
          });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, built.bytes);
        } finally {
          await compiler.dispose();
        }
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
