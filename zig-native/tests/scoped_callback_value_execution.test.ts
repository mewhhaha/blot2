import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const factory = `
const encode = func (value: F32) => return #[value]
const decode = func (values: Array F32) => return values[0]
const identity = func (value: U32) => return value
const wrap = func (value: U32) => return {value}
const metadata = func (key: U32) => return {key, version: 1, encode, decode, identity, wrap}
`;
const source = `
import * as factory from "./forward"
entry const run = func (count: U32): Array F32 => return do:
  let codec = factory.metadata 23
  let output: GrowArray F32 = #[]
  output.push (U32.to_f32 codec.key)
  output.push (U32.to_f32 codec.version)
  for index in 0 .. count:
    let value = U32.to_f32 (codec.wrap (codec.identity index)).value
    output.push (codec.decode (codec.encode value))
  return @storage.freeze output
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`ordinary callback values survive imports fresh and retained builds and failed revisions (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-callback-value-",
    });
    const entry = `${directory}/main.blot`;
    const producer = `${directory}/factory.blot`;
    await Deno.writeTextFile(entry, source);
    await Deno.writeTextFile(producer, factory);
    await Deno.writeTextFile(
      `${directory}/forward.blot`,
      'import * as factory from "./factory"\nconst metadata = factory.metadata\n',
    );
    const options = {
      executable,
      entry,
      prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
      cacheDirectory: false as const,
      codegenTier,
    };
    let compiler = await createZigProjectCompiler(options);
    try {
      const initial = await compiler.build();
      assert(
        initial.success,
        !initial.success ? JSON.stringify(initial.diagnostics) : "",
      );
      await compiler.dispose();
      compiler = await createZigProjectCompiler(options);
      const replayed = await compiler.build();
      assert(
        replayed.success,
        !replayed.success ? JSON.stringify(replayed.diagnostics) : "",
      );
      assert.deepEqual(replayed.bytes, initial.bytes);
      const retained = await compiler.build();
      assert(
        retained.success,
        !retained.success ? JSON.stringify(retained.diagnostics) : "",
      );
      assert.deepEqual(retained.bytes, initial.bytes);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(replayed.bytes, { asynchronous });
        try {
          for (const count of [0, 1, 7, 32, 129]) {
            const expected = Float32Array.from([
              23,
              1,
              ...Array.from({ length: count }, (_, index) => index),
            ]);
            const result = asynchronous
              ? await guest.callAsync("run", count)
              : guest.call("run", count);
            assert.deepEqual(result, expected);
          }
        } finally {
          guest.dispose();
        }
      }
      const rejected = await compiler.build({
        sources: {
          [producer]: factory.replace("#[value]", "#[true]"),
        },
      });
      assert(!rejected.success);
      assert.equal(rejected.diagnostics[0].code, "type_mismatch");
      assert.equal("bytes" in rejected, false);
      const recovered = await compiler.build();
      assert(
        recovered.success,
        !recovered.success ? JSON.stringify(recovered.diagnostics) : "",
      );
      assert.deepEqual(recovered.bytes, initial.bytes);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
