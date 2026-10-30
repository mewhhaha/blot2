import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type Probe is data = #Probe U32
const Probe.choose = func (unused: Probe) => return do:
  let copied = 0
  break func (index: U32) => return @u32.add index copied
const Probe.within = func (unused: Probe) => return do:
  let limit = 2
  break func (index: U32) => return @u32.lt index limit
const lookup = func probe => return func (index: U32) => return do:
  let values = #[8, 13]
  if @type.call "within" probe index:
    break @array.get values (@type.call "choose" probe index)
  break 0
const run = func index => return lookup (#Probe 42) index
`;
const source = `import {run} from "./logic"
entry const answer = func (index: U32) => return run index
entry const snapshot = func (value: U32) => return #[value]
`;
const remainingArgumentsLibrary = library
  .replace(
    "(index: U32) => return @u32.add",
    "(index: U32) => return func () => return @u32.add",
  )
  .replace(
    "(index: U32) => return @u32.lt",
    "(index: U32) => return func () => return @u32.lt",
  )
  .replace(
    'if @type.call "within" probe index:',
    'if (@type.call "within" probe index) ():',
  )
  .replace(
    '(@type.call "choose" probe index)',
    '((@type.call "choose" probe index) ())',
  );

const literalReceiverLibrary = `type Probe is data = #Probe U32
const Probe.choose = func (unused: Probe) => return func (index: U32) => return func (delta: U32) => return @u32.add index delta
const run = func (index: U32) => return do:
  let copied = 0
  if @u32.lt index 2:
    break @array.get #[8, 13] ((@type.call "choose" (#Probe 42) index) copied)
  break 0
`;

async function observe(bytes: Uint8Array<ArrayBuffer>, changed = false) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    const call = async (index: number) => {
      if (asynchronous) return await guest.callAsync("answer", index);
      return guest.call("answer", index);
    };
    try {
      if (changed) {
        assert.equal(await call(0), 13);
        await assert.rejects(() => call(1), WebAssembly.RuntimeError);
      } else {
        for (let repetition = 0; repetition < 32; repetition++) {
          assert.equal(await call(0), 8);
          assert.equal(await call(1), 13);
        }
      }
      assert.equal(await call(2), 0);
      assert.equal(await call(4294967295), 0);
      const warmed = guest.memoryBytes();
      for (let repetition = 0; repetition < 32; repetition++) {
        assert.equal(await call(0), 8 + Number(changed) * 5);
      }
      assert.equal(guest.memoryBytes(), warmed);
    } finally {
      guest.dispose();
    }
  }
}

for (
  const [name, librarySource] of [
    ["returned closures", library],
    ["remaining arguments", remainingArgumentsLibrary],
    ["literal receiver", literalReceiverLibrary],
  ]
) {
  for (const codegenTier of ["development", "optimized"] as const) {
    Deno.test(`curried selected proofs preserve ${name} captures traps archives and restart (${codegenTier})`, async () => {
      const directory = await Deno.makeTempDir({
        prefix: "blot-curried-proof-",
      });
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
        await Deno.writeTextFile(dependency, librarySource);
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
          const broken = source.replace("run index", "run true");
          const failed = await archive.build({ sources: { [entry]: broken } });
          assert(!failed.success);
          assert.deepEqual(await archive.exportCheckpoint(), checkpoint);
          const recovered = await archive.build({
            sources: { [entry]: source },
          });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, expected);
          const changed = librarySource.replace(
            "let copied = 0",
            "let copied = 1",
          );
          for (const current of [compiler, archive]) {
            const edited = await current.build({
              sources: { [entry]: source, [dependency]: changed },
            });
            assert(edited.success, JSON.stringify(edited));
            await observe(edited.bytes, true);
            const reverted = await current.build({
              sources: { [entry]: source, [dependency]: librarySource },
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
}
