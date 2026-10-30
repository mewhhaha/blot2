import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const scalar = `entry const run = func (count: U32) => return do:
  let values = @array.generate count (func i => return @u32.add i 1)
  let sum = 0
  for value in values:
    sum := @u32.add self value
  break sum
`;
const unknown = `entry const run = func (count: U32) => return do:
  let values = @array.generate count (func i => return func n => return @u32.add i n)
  break values[0] count
`;
const cyclic = `type State a is effect = {get: Unit -> a, set: a -> Unit}
type Node is data = #End | #Next (Unit -> Node ! {State.get Node})
const keep = func ~value => return func () => return @demand value
const get = func (witness: Unit -> a) : a => return State.get ()
entry const run = func (seed: U32) => return do:
  let (_, result) = @effect.run State.get State.set #End (func () => return do:
    let delayed = keep (get (func () => return #End))
    use State.set (#Next delayed)
    use first <- delayed ()
    use State.set #End
    use cached <- delayed ()
    break case cached of
      #End => @panic "memo lost its cycle"
      #Next same => do:
        use again <- same ()
        break case again of
          #End => @panic "closure lost its memo"
          #Next _ => seed
  )
  break result
`;
const certificate = (bytes: Uint8Array<ArrayBuffer>) =>
  JSON.parse(
    new TextDecoder().decode(
      WebAssembly.Module.customSections(
        new WebAssembly.Module(bytes),
        "blot:collector-contract",
      )[0],
    ),
  );
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`collector-free whole-module certificate rejects unproved neighbors and survives restart (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-collector-contract-",
    });
    const entry = `${directory}/main.blot`;
    const options = {
      executable: Deno.args[0],
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: `${directory}/cache`,
    };
    try {
      for (const restart of [false, true]) {
        const compiler = await createZigProjectCompiler({
          ...options,
          requireCollectorFree: true,
        });
        try {
          const built = await compiler.build({ sources: { [entry]: scalar } });
          assert(built.success, JSON.stringify(built));
          assert.equal(certificate(built.bytes).certificate.certified, true);
          assert.equal(certificate(built.bytes).strict, true);
          assert(certificate(built.bytes).compiler_identity !== null);
          assert(
            certificate(built.bytes).sources.some((s: { filename: string }) =>
              s.filename === entry
            ),
          );
          const raw =
            new WebAssembly.Instance(new WebAssembly.Module(built.bytes))
              .exports;
          for (let repeat = 0; repeat < 3; repeat++) {
            assert.equal((raw.run as CallableFunction)(2000), 2001000);
            for (
              const name of ["cycle_passes", "cycle_vertices", "cycle_edges"]
            ) {
              assert.equal(
                (raw[`blot:${name}`] as WebAssembly.Global).value,
                0,
              );
            }
          }
          if (!restart) {
            const shifted = await compiler.build({
              sources: { [entry]: "// source identity changes\n" + scalar },
            });
            assert(shifted.success, JSON.stringify(shifted));
            assert.notDeepEqual(
              certificate(shifted.bytes).sources,
              certificate(built.bytes).sources,
              "strict source pins follow trivia edits",
            );
            // A scalar export cannot mask an unproved export sharing its arena.
            const rejected = await compiler.build({
              sources: { [entry]: scalar.replaceAll("run", "safe") + unknown },
            });
            assert(!rejected.success);
            assert(
              JSON.stringify(rejected.diagnostics).includes(
                "collector_free_unproved",
              ),
              JSON.stringify(rejected),
            );
            const cycles = await compiler.build({
              sources: { [entry]: cyclic },
            });
            assert(!cycles.success);
            assert(
              JSON.stringify(cycles.diagnostics).includes(
                "collector_free_unproved",
              ),
              JSON.stringify(cycles),
            );
          }
        } finally {
          await compiler.dispose();
        }
      }
      const ordinary = await createZigProjectCompiler(options);
      try {
        const built = await ordinary.build({ sources: { [entry]: unknown } });
        assert(built.success, JSON.stringify(built));
        assert.equal(certificate(built.bytes).certificate.certified, false);
        assert.equal(
          (new WebAssembly.Instance(new WebAssembly.Module(built.bytes)).exports
            .run as CallableFunction)(8),
          8,
        );
        const cycles = await ordinary.build({ sources: { [entry]: cyclic } });
        assert(cycles.success, JSON.stringify(cycles));
        assert.equal(certificate(cycles.bytes).certificate.certified, false);
        const raw =
          new WebAssembly.Instance(new WebAssembly.Module(cycles.bytes))
            .exports;
        for (let pass = 0; pass < 32; pass++) {
          assert.equal((raw.run as CallableFunction)(pass), pass);
        }
        assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
        assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
      } finally {
        await ordinary.dispose();
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
