import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type Probe is data = #Probe U32
const copy = fn (value: U32) => value
const advance = fn (value: U32) => fn (delta: U32) => @u32.add (copy value) (copy delta)
const forwarded = fn (value: U32) => advance (copy value) 0
const invoke = fn callback => fn (index: U32) => callback index
const Probe.choose = fn (unused: Probe) => do:
  let copied = forwarded 0
  return fn (index: U32) => fn (delta: U32) => advance (forwarded index) (advance copied delta)
const Probe.unknown = fn (unused: Probe) => fn (index: U32) => fn callback => invoke callback index
const Probe.foreign = fn (unused: Probe) => fn (index: U32) => fn (callback: U32 -> U32 ! {Foreign}) => invoke callback index
const lookup = fn probe => fn (index: U32) => do:
  let values = #[8, 13]
  if @u32.lt index 2:
    return @array.get values ((@type.call "choose" probe index) 0)
  return 0
const lookup_unknown = fn probe => fn (index: U32) => if @u32.lt index 2 then @array.get #[8, 13] ((@type.call "unknown" probe index) (fn (value: U32) => value)) else 0
const lookup_foreign = fn probe => fn (callback: U32 -> U32 ! {Foreign}) => @array.get #[8, 13] ((@type.call "foreign" probe 1) callback)
const run = fn (index: U32) => lookup (#Probe 42) index
const run_unknown = fn (index: U32) => lookup_unknown (#Probe 42) index
const run_foreign = fn callback => lookup_foreign (#Probe 42) callback
`;
const source = `import {run, run_unknown, run_foreign} from "./logic"
entry const answer = fn (index: U32) => run index
entry const unknown = fn (index: U32) => run_unknown index
entry const effectful = fn (callback: U32 -> U32 ! {Foreign}) => run_foreign callback
`;
async function observe(bytes: Uint8Array<ArrayBuffer>, changed = false) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    const invoke = async (
      name: string,
      value: Parameters<typeof guest.call>[1],
    ) => {
      if (asynchronous) return await guest.callAsync(name, value);
      return guest.call(name, value);
    };
    try {
      let first = 8;
      if (changed) first = 13;
      assert.equal(await invoke("answer", 0), first);
      if (changed) {
        await assert.rejects(
          () => invoke("answer", 1),
          WebAssembly.RuntimeError,
        );
      } else assert.equal(await invoke("answer", 1), 13);
      for (const index of [2, 4294967295]) {
        assert.equal(await invoke("answer", index), 0);
        assert.equal(await invoke("unknown", index), 0);
      }
      assert.equal(await invoke("unknown", 0), 8);
      assert.equal(await invoke("unknown", 1), 13);
      const calls: number[] = [];
      const host = (result?: number) => {
        const call = (value: unknown) => {
          calls.push(Number(value));
          return result ?? Number(value);
        };
        if (asynchronous) {
          return guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            call: async (value) => {
              await Promise.resolve();
              return call(value);
            },
          });
        }
        return guest.capability({ parameter: "U32", result: "U32", call });
      };
      assert.equal(await invoke("effectful", host()), 13);
      assert.deepEqual(calls, [1]);
      calls.length = 0;
      await assert.rejects(
        () => invoke("effectful", host(4294967295)),
        WebAssembly.RuntimeError,
      );
      assert.deepEqual(
        calls,
        [1],
        "the unknown effect executes before its necessary bounds trap",
      );
      assert.equal(await invoke("answer", 0), first);
    } finally {
      guest.dispose();
    }
  }
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`numeric finite nested selected closures preserve exact operands unknown effects imports and restart (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/logic.blot`;
    const archive = `${directory}/logic.blotdep`;
    try {
      await Deno.writeTextFile(entry, source);
      await Deno.writeTextFile(dependency, library);
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
      let expected: Uint8Array<ArrayBuffer> | undefined;
      for (const dependencies of [undefined, archive]) {
        const options = {
          executable,
          entry,
          prelude: null,
          dependencies,
          codegenTier,
          cacheDirectory: false as const,
        };
        const compiler = await createZigProjectCompiler(options);
        try {
          const built = await compiler.build();
          assert(built.success, JSON.stringify(built));
          if (dependencies) assert(built.stats.cachedModules > 0);
          if (expected) assert.deepEqual(built.bytes, expected);
          else expected = built.bytes;
          await observe(built.bytes);
          const checkpoint = await compiler.exportCheckpoint();
          const invalid = await compiler.build({
            sources: { [entry]: source.replace("run index", "run #True") },
          });
          assert(!invalid.success);
          assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          const recovered = await compiler.build({
            sources: { [entry]: source },
          });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, built.bytes);
          const changed = library.replace(
            "let copied = forwarded 0",
            "let copied = forwarded 1",
          );
          const edited = await compiler.build({
            sources: { [dependency]: changed },
          });
          assert(edited.success, JSON.stringify(edited));
          await observe(edited.bytes, true);
          const fresh = await createZigProjectCompiler(options);
          try {
            const independent = await fresh.build({
              sources: { [dependency]: changed },
            });
            assert(independent.success, JSON.stringify(independent));
            assert.deepEqual(independent.bytes, edited.bytes);
          } finally {
            await fresh.close();
          }
          const reverted = await compiler.build({
            sources: { [dependency]: library },
          });
          assert(reverted.success, JSON.stringify(reverted));
          assert.deepEqual(reverted.bytes, built.bytes);
          const restored = await createZigProjectCompiler({
            ...options,
            checkpoint,
          });
          try {
            const replayed = await restored.build();
            assert(replayed.success, JSON.stringify(replayed));
            assert.deepEqual(replayed.bytes, built.bytes);
            await observe(replayed.bytes);
          } finally {
            await restored.close();
          }
        } finally {
          await compiler.close();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
