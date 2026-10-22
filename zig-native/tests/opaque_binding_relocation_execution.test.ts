import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0];
assert(executable);
type Edit =
  | "initial"
  | "insert"
  | "insert_type"
  | "insert_effect"
  | "insert_contract"
  | "move"
  | "alpha"
  | "body"
  | "revert";
function library(edit: Edit) {
  const parameter = edit === "alpha" ? "payload" : "element";
  const variable = edit === "alpha" ? "item" : "a";
  const argument = edit === "alpha" ? "argument" : "value";
  const offset = `private const offset = ${edit === "body" ? 3 : 2}\n`;
  const inserted = edit !== "initial" && edit !== "revert"
    ? "private const unrelated = 99\n"
    : "";
  const privateType = edit === "insert_effect"
    ? "private type PrivateRead is effect = Unit -> U32\n"
    : edit === "insert_contract"
    ? "private type Hidden a is contract = {type_rep a}\n"
    : edit === "insert_type"
    ? "private type Spare is data = #Spare U32\n"
    : "";
  return inserted + privateType + (edit === "move" ? "" : offset) +
    `opaque type Token ${parameter} = ${parameter}\n` +
    `const make: ${variable} -> Token ${variable} = fn ${argument} => #Token ${argument}\n` +
    `const read: Token ${variable} -> ${variable} = fn (#Token ${argument}) => ${argument}\n` +
    "const adjust: U32 -> U32 = fn value => @u32.add value offset\n" +
    (edit === "move" ? offset : "");
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(
    "public effect alpha preserves typed invocation, archives and rollback (" +
      codegenTier + ")",
    async () => {
      const directory = await Deno.makeTempDir({
        prefix: "blot-effect-alpha-",
      });
      const entry = directory + "/main.blot";
      const tokens = directory + "/tokens.blot";
      const bundle = directory + "/dependencies.blotdep";
      const body = "opaque type Token = U32\n" +
        "const make: Unit -> Token = fn () => #Token 42\n" +
        "const read: Token -> Unit = fn (#Token value) => ()\n";
      const producer = (name: string) =>
        "type PublicRead " + name + " is effect = Unit -> " + name + "\n" +
        body;
      const bridge = 'import {PublicRead, make, read} from "./tokens"\n' +
        "const consume = fn () -> U32 => do (@effect.provider (PublicRead U32) (fn () => 42)):\n  read (make ())\n" +
        "  break PublicRead U32 ()\n";
      try {
        await Deno.writeTextFile(
          entry,
          'import {consume} from "./bridge"\nentry const answer = fn () => consume ()\n',
        );
        await Deno.writeTextFile(tokens, producer("element"));
        await Deno.writeTextFile(directory + "/bridge.blot", bridge);
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
            for (
              const [index, name] of ["element", "payload", "element"].entries()
            ) {
              const text = producer(name);
              const sources = { [tokens]: text };
              const built = await retained.build({ sources });
              assert(built.success, JSON.stringify(built));
              if (index !== 0) {
                const work = built.stats.attemptStats.fallback as {
                  module_cutoff: { reused: number };
                  entry_cutoff: { reused: number };
                };
                assert.equal(work.module_cutoff.reused, 1);
                assert.equal(work.entry_cutoff.reused, 1);
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
                  [tokens]: text.replace("Unit -> " + name, "Unit -> F32"),
                },
              });
              assert(!failed.success);
              assert.deepEqual(await retained.exportCheckpoint(), checkpoint);
              const corrected = await retained.build({ sources });
              assert(corrected.success, JSON.stringify(corrected));
              assert.deepEqual(corrected.bytes, built.bytes);
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
                    for (let call = 0; call < 100; call++) {
                      assert.equal(guest.call("answer", null), 42);
                    }
                    const warm = guest.memoryBytes();
                    for (let call = 0; call < 100; call++) {
                      assert.equal(guest.call("answer", null), 42);
                    }
                    assert.equal(guest.memoryBytes(), warm);
                  } finally {
                    guest.dispose();
                  }
                }
              } finally {
                await restarted.dispose();
              }
            }
          } finally {
            await retained.dispose();
          }
        }
      } finally {
        await Deno.remove(directory, { recursive: true });
      }
    },
  );
}
const bridge = `import {Token, make, read, adjust} from "./tokens"
const factories = #[make, fn value => make value]
const readers = #[read, fn value => read value]
const transform = fn (value: U32) => do:
  let token: Token U32 = (factories[@u32.rem value 2]) (adjust value)
  break (readers[@u32.rem value 2]) token
`;
const main = `import {transform} from "./bridge"
entry const answer = fn (value: U32) => transform value
`;

async function execute(bytes: Uint8Array<ArrayBuffer>, offset: number) {
  const guest = await instantiateGuest(bytes);
  try {
    for (let index = 0; index < 100; index++) {
      assert.equal(
        guest.call("answer", 40 + index % 2),
        40 + index % 2 + offset,
      );
    }
    const warmed = guest.memoryBytes();
    for (let index = 0; index < 100; index++) {
      assert.equal(
        guest.call("answer", 40 + index % 2),
        40 + index % 2 + offset,
      );
    }
    assert.equal(guest.memoryBytes(), warmed);
  } finally {
    guest.dispose();
  }
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`opaque caller relocation preserves source/archive/checkpoint and failed edits (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-opaque-relocation-",
    });
    const entry = `${directory}/main.blot`;
    const tokens = `${directory}/tokens.blot`;
    const bundle = `${directory}/dependencies.blotdep`;
    try {
      await Deno.writeTextFile(entry, main);
      await Deno.writeTextFile(`${directory}/bridge.blot`, bridge);
      await Deno.writeTextFile(tokens, library("initial"));
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
          for (
            const edit of [
              "initial",
              "insert",
              "insert_type",
              "insert_effect",
              "insert_contract",
              "move",
              "alpha",
              "body",
              "revert",
            ] as const
          ) {
            const sources = { [tokens]: library(edit) };
            const built = await retained.build({ sources });
            assert(built.success, JSON.stringify({ edit, built }));
            if (edit !== "initial") {
              const work = built.stats.attemptStats.fallback as {
                module_cutoff: { reused: number };
                entry_cutoff: { reused: number };
              };
              assert.equal(
                work.module_cutoff.reused,
                1,
                `${edit}: module reuse`,
              );
              assert.equal(work.entry_cutoff.reused, 1, `${edit}: entry reuse`);
            }
            const fresh = await createZigProjectCompiler(options);
            try {
              const control = await fresh.build({ sources });
              assert(control.success, JSON.stringify(control));
              assert.deepEqual(built.bytes, control.bytes, edit);
            } finally {
              await fresh.dispose();
            }
            await execute(built.bytes, edit === "body" ? 3 : 2);
            const checkpoint = await retained.exportCheckpoint();
            const failed = await retained.build({
              sources: {
                [tokens]: library(edit).replace("adjust: U32", "adjust: Bool"),
              },
            });
            assert(!failed.success);
            assert.deepEqual(await retained.exportCheckpoint(), checkpoint);
            const corrected = await retained.build({ sources });
            assert(corrected.success, JSON.stringify(corrected));
            assert.deepEqual(corrected.bytes, built.bytes);
            const restarted = await createZigProjectCompiler({
              ...options,
              checkpoint,
            });
            try {
              const restored = await restarted.build({ sources });
              assert(restored.success, JSON.stringify(restored));
              assert.deepEqual(restored.bytes, built.bytes);
              await execute(restored.bytes, edit === "body" ? 3 : 2);
            } finally {
              await restarted.dispose();
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
