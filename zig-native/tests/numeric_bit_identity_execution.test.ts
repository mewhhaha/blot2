import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `const identity = func (index: U32) => return do:
  let multiplied = @u32.mul 1 index
  let masked = @u32.bit_and multiplied 0xffffffff
  let shifted = @u32.shl masked 32
  let zero = @u32.bit_xor index index
  break @u32.div (@u32.bit_or shifted zero) 1
const lookup = func (index: U32) => return if @u32.lt index 2 then @array.get #[8, 13] (identity index) else 0
const guarded = func (index: U32) => return if @u32.lt index 2 then @array.get #[8, 13] (@u32.div index 0) else 0
`;
const source = `import {identity, lookup, guarded} from "./logic"
entry const echo = func (index: U32) => return identity index
entry const answer = func (index: U32) => return lookup index
entry const trap = func (index: U32) => return guarded index
entry const snapshot = func (value: U32) => return #[value]
`;

async function observe(bytes: Uint8Array<ArrayBuffer>, changed = false) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    const call = async (name: string, value: number) => {
      if (asynchronous) return await guest.callAsync(name, value);
      return guest.call(name, value);
    };
    try {
      for (const value of [0, 1, 31, 32, 0x7fffffff, 0x80000000, 0xffffffff]) {
        let expected = value;
        if (changed) expected = (value << 1) >>> 0;
        assert.equal(await call("echo", value), expected);
      }
      assert.equal(await call("answer", 0), 8);
      if (changed) {
        await assert.rejects(() => call("answer", 1), WebAssembly.RuntimeError);
      } else assert.equal(await call("answer", 1), 13);
      assert.equal(await call("answer", 2), 0);
      await assert.rejects(() => call("trap", 0), WebAssembly.RuntimeError);
      assert.equal(await call("trap", 2), 0);
      const memory = guest.memoryBytes();
      for (let index = 0; index < 32; index++) {
        assert.equal(await call("answer", 0), 8);
      }
      assert.equal(guest.memoryBytes(), memory);
    } finally {
      guest.dispose();
    }
  }
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`U32 identity proofs preserve bits traps edits and portable ownership (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-bit-proof-" });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/logic.blot`;
    const dependencies = `${directory}/logic.blotdep`;
    const options = {
      executable,
      entry,
      prelude: null,
      cacheDirectory: false as const,
      codegenTier,
    };
    try {
      await Deno.writeTextFile(entry, source);
      await Deno.writeTextFile(dependency, library);
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, dependencies, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(packed.success, new TextDecoder().decode(packed.stderr));
      const compiler = await createZigProjectCompiler(options);
      const archive = await createZigProjectCompiler({
        ...options,
        dependencies,
      });
      let checkpoint: Uint8Array<ArrayBuffer>;
      let expected: Uint8Array<ArrayBuffer>;
      try {
        const first = await compiler.build();
        const frozen = await archive.build();
        assert(first.success, JSON.stringify(first));
        assert(frozen.success, JSON.stringify(frozen));
        assert(frozen.stats.cachedModules > 0);
        assert.deepEqual(frozen.bytes, first.bytes);
        expected = first.bytes;
        await observe(expected);
        checkpoint = await archive.exportCheckpoint();
        const invalid = await archive.build({
          sources: { [entry]: source.replace("lookup index", "lookup true") },
        });
        assert(!invalid.success);
        assert.deepEqual(await archive.exportCheckpoint(), checkpoint);
        const changed = library.replace(
          "@u32.shl masked 32",
          "@u32.shl masked 33",
        );
        for (const current of [compiler, archive]) {
          const edited = await current.build({
            sources: { [entry]: source, [dependency]: changed },
          });
          assert(edited.success, JSON.stringify(edited));
          await observe(edited.bytes, true);
          const reverted = await current.build({
            sources: { [entry]: source, [dependency]: library },
          });
          assert(reverted.success, JSON.stringify(reverted));
          assert.deepEqual(reverted.bytes, expected);
        }
      } finally {
        await compiler.dispose();
        await archive.dispose();
      }
      const restored = await createZigProjectCompiler({
        ...options,
        dependencies,
        checkpoint: checkpoint!,
      });
      try {
        const replayed = await restored.build();
        assert(replayed.success, JSON.stringify(replayed));
        assert.deepEqual(replayed.bytes, expected!);
        await observe(replayed.bytes);
      } finally {
        await restored.dispose();
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
