import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const library =
  `type Source s is contract = { type Item, const first: s -> (Source.Item s) }
impl ArraySource a : Source (Array a) = { type Item = a, const first = fn values => @array.get values 0 }
`;
const main = `import {Source} from "./library"
entry const answer = fn (value: U32) => do:
  let selected: (Array U32) -> U32 = Source.first
  break selected #[value, @u32.add value 1]
entry const floating = fn (value: F32) => do:
  let selected: (Array F32) -> F32 = Source.first
  break selected #[value, 2.5]
entry const reference = fn (value: Array U32) => do:
  let selected: (Array (Array U32)) -> Array U32 = Source.first
  break selected #[value, #[7]]
`;
const foreignLibrary =
  `type Callable f is contract = { type Run, const run: f -> (Callable.Run f) ! {Foreign} }
impl Callback a : Callable (Unit -> a ! {Foreign}) = { type Run = a, const run = fn callback => callback () }
`;
const foreignMain = `import {Callable} from "./library"
entry const answer = fn (host: Unit -> U32 ! {Foreign}) => do:
  let selected: (Unit -> U32 ! {Foreign}) -> U32 = Callable.run
  break selected host
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`selected first class callbacks retain exact associated results and current imported owners (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-selected-callback-",
    });
    const entry = `${directory}/main.blot`,
      producer = `${directory}/library.blot`;
    const options = {
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false as const,
      codegenTier,
    };
    const verify = async (bytes: Uint8Array<ArrayBuffer>, edited = false) => {
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(bytes, { asynchronous });
        const call = async (name: string, value: unknown) => {
          if (asynchronous) return await guest.callAsync(name, value);
          return guest.call(name, value);
        };
        try {
          let whole = 42;
          let fraction = 1.5;
          if (edited) {
            whole = 43;
            fraction = 2.5;
          }
          assert.equal(await call("answer", 42), whole);
          assert.equal(await call("floating", 1.5), fraction);
          let expected = new Uint32Array([20, 22]);
          if (edited) expected = new Uint32Array([7]);
          assert.deepEqual(
            await call("reference", new Uint32Array([20, 22])),
            expected,
          );
        } finally {
          guest.dispose();
        }
      }
    };
    let checkpoint: Uint8Array<ArrayBuffer>;
    let original: Uint8Array<ArrayBuffer>;
    const compiler = await createZigProjectCompiler(options);
    try {
      const sources = { [entry]: main, [producer]: library };
      const fresh = await compiler.build({ sources });
      assert(fresh.success, JSON.stringify(fresh));
      original = fresh.bytes;
      await verify(original);
      checkpoint = await compiler.exportCheckpoint();
      const edited = await compiler.build({
        sources: {
          ...sources,
          [producer]: library.replace("values 0", "values 1"),
        },
      });
      assert(edited.success, JSON.stringify(edited));
      await verify(edited.bytes, true);
      const wrongResult = library.replace("type Item = a", "type Item = Bool")
        .replace("@array.get values 0", "#True");
      const rejected = await compiler.build({
        sources: { ...sources, [producer]: wrongResult },
      });
      assert.equal(rejected.success, false, JSON.stringify(rejected));
      assert(
        rejected.diagnostics.some((diagnostic) =>
          diagnostic.code === "type_mismatch"
        ),
        JSON.stringify(rejected),
      );
      const wrongRow = await compiler.build({
        sources: { [entry]: foreignMain, [producer]: foreignLibrary },
      });
      assert.equal(wrongRow.success, false, JSON.stringify(wrongRow));
      assert(
        wrongRow.diagnostics.some((diagnostic) =>
          diagnostic.code === "effect_mismatch"
        ),
        JSON.stringify(wrongRow),
      );
      const reverted = await compiler.build({ sources });
      assert(reverted.success, JSON.stringify(reverted));
      assert.deepEqual(reverted.bytes, original);
      await verify(reverted.bytes);
    } finally {
      await compiler.close();
    }
    const restarted = await createZigProjectCompiler({
      ...options,
      checkpoint,
    });
    try {
      const portable = await restarted.build({
        sources: { [entry]: main, [producer]: library },
      });
      assert(portable.success, JSON.stringify(portable));
      assert.deepEqual(portable.bytes, original!);
      await verify(portable.bytes);
    } finally {
      await restarted.close();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
