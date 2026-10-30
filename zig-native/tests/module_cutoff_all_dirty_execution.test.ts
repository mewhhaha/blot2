import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const producer = (offset: number) =>
  `opaque type Token = U32
private const offset = ${offset}
const make: U32 -> Token = func value => return #Token (@u32.add value offset)
const read: Token -> U32 = func (#Token value) => return value
`;
const bridge = `import {make, read} from "./tokens"
const transform = func (value: U32) => return read (make value)
`;
const main = `import {transform} from "./bridge"
entry const answer = func (value: U32) => return transform value
`;

async function observe(bytes: Uint8Array<ArrayBuffer>, offset: number) {
  const module = new WebAssembly.Module(bytes);
  assert.equal(
    WebAssembly.Module.exports(module).some((item) => item.kind === "memory"),
    false,
  );
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      for (const value of [0, 40, 0x7fffffff, 0xffffffff]) {
        let result;
        if (asynchronous) result = await guest.callAsync("answer", value);
        else result = guest.call("answer", value);
        assert.equal(result, (value + offset) >>> 0);
      }
    } finally {
      guest.dispose();
    }
  }
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`opaque caller cutoffs survive a wholly dirty dependency chain (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-all-dirty-" });
    const entry = `${directory}/main.blot`;
    const tokens = `${directory}/tokens.blot`;
    const bundle = `${directory}/dependencies.blotdep`;
    await Deno.writeTextFile(tokens, producer(2));
    await Deno.writeTextFile(`${directory}/bridge.blot`, bridge);
    await Deno.writeTextFile(entry, main);
    const options = {
      executable,
      entry,
      prelude: null,
      cacheDirectory: false as const,
      codegenTier,
    };
    try {
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, bundle, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(packed.success, new TextDecoder().decode(packed.stdout));
      for (const dependencies of [undefined, bundle]) {
        const retained = await createZigProjectCompiler({
          ...options,
          dependencies,
        });
        try {
          for (const [index, offset] of [2, 3, 3, 3, 2].entries()) {
            let source = producer(offset);
            if (index === 2) {
              source = source.replace(
                "func (#Token value) => return value",
                "func (#Token value) => return do:\n  let fresh_private_adjustment = @u32.add value 0\n  break fresh_private_adjustment",
              );
            }
            if (index === 3) {
              source = source.replace(
                "func value => return #Token (@u32.add value offset)",
                "func value => return do:\n  let fresh_private_adjustment = @u32.add value 0\n  break #Token (@u32.add fresh_private_adjustment offset)",
              );
            }
            const sources = { [tokens]: source };
            const result = await retained.build({ sources });
            assert(result.success, JSON.stringify(result));
            if (index !== 0) {
              const work = result.stats.attemptStats.fallback as {
                module_cutoff: { reused: number };
                entry_cutoff: { reused: number };
              };
              assert.equal(work.module_cutoff.reused, 1);
              assert.equal(work.entry_cutoff.reused, 1);
            }
            const fresh = await createZigProjectCompiler(options);
            try {
              const expected = await fresh.build({ sources });
              assert(expected.success, JSON.stringify(expected));
              assert.deepEqual(result.bytes, expected.bytes);
            } finally {
              await fresh.close();
            }
            await observe(result.bytes, offset);
            const checkpoint = await retained.exportCheckpoint();
            const invalid = await retained.build({
              sources: {
                [tokens]: producer(offset).replace(
                  "const make: U32 -> Token",
                  "const make: Bool -> Token",
                ),
              },
            });
            assert(!invalid.success);
            assert.deepEqual(await retained.exportCheckpoint(), checkpoint);
            const recovery = await retained.build({ sources });
            assert(recovery.success, JSON.stringify(recovery));
            assert.deepEqual(recovery.bytes, result.bytes);
            const restarted = await createZigProjectCompiler({
              ...options,
              checkpoint,
            });
            try {
              const restored = await restarted.build({ sources });
              assert(restored.success, JSON.stringify(restored));
              assert.deepEqual(restored.bytes, result.bytes);
              await observe(restored.bytes, offset);
            } finally {
              await restarted.close();
            }
          }
        } finally {
          await retained.close();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
