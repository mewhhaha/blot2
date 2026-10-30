import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const extra = `
const delayed = func ~value => return value
entry const edit_source = func (size: U32) => return do:
  let saved = array.generate size (func index => return index + 1)
  let copied = array.generate saved.length (func index => return saved[index])
  saved[0] := 99
  break copied[0]
entry const edit_copy = func (size: U32) => return do:
  let saved = array.generate size (func index => return index + 1)
  let copied = array.generate saved.length (func index => return saved[index])
  copied[0] := 99
  break saved[0] + copied[0]
entry const escaped_copy = func (size: U32) => return do:
  let saved = array.generate size (func index => return index + 1)
  let copied = array.generate saved.length (func index => return saved[index])
  saved[0] := 99
  break copied
entry const captured_copy = func (size: U32) => return do:
  let saved = array.generate size (func index => return index + 1)
  let copied = array.generate saved.length (func index => return saved[index])
  let read = func () => return copied[0]
  saved[0] := 99
  break read ()
entry const suspended_copy = func (size: U32) => return do:
  let saved = array.generate size (func index => return index + 1)
  let copied = array.generate saved.length (func index => return saved[index])
  let before = delayed copied
  saved[0] := 99
  break (@force before)[0]
entry const nested_copy = func (size: U32) => return do:
  let saved = array.generate size (func index => return #[index + 1])
  let copied = array.generate saved.length (func index => return saved[index])
  saved[0][0] := 99
  copied[1][0] := 77
  break #[saved[0][0], saved[1][0], copied[0][0], copied[1][0]]
entry const copied_bits = func (values: Array F32) => return
  array.generate values.length (func index => return values[index])
entry const wrong_count = func (size: U32) => return do:
  let saved = array.generate size (func index => return index)
  let copied = array.generate (saved.length + 1) (func index => return saved[index])
  break copied.length
entry const wrong_index = func (size: U32) => return do:
  let saved = array.generate size (func index => return index)
  let copied = array.generate saved.length (func index => return saved[index + 1])
  break copied.length
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`identity arrays preserve escaping snapshots captures suspension and bits (${codegenTier})`, async () => {
    const fixture = new URL(
      "../../benchmarks/runtime-boundaries/",
      import.meta.url,
    );
    const directory = await Deno.makeTempDir({
      prefix: "blot-identity-array-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: new URL("../../std/prelude.blot", import.meta.url),
      stdRoot: new URL("../../std", import.meta.url),
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build({
        sources: {
          [entry]: await Deno.readTextFile(new URL("main.blot", fixture)) +
            extra,
          [`${directory}/rows.blot`]: await Deno.readTextFile(
            new URL("rows.blot", fixture),
          ),
        },
      });
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        for (const size of [2, 33, 512]) {
          for (
            const name of ["edit_source", "captured_copy", "suspended_copy"]
          ) assert.equal(guest.call(name, size), 1);
          assert.equal(guest.call("edit_copy", size), 100);
          assert.deepEqual(
            Array.from(guest.call("escaped_copy", size) as Uint32Array),
            Array.from({ length: size }, (_, i) => i + 1),
          );
          assert.deepEqual(
            Array.from(guest.call("nested_copy", size) as Uint32Array),
            [99, 2, 1, 77],
          );
          for (const name of ["wrong_count", "wrong_index"]) {
            assert.throws(
              () => guest.call(name, size),
              WebAssembly.RuntimeError,
            );
          }
          assert.equal(guest.call("edit_source", size), 1);
        }
        const bits = new Uint32Array([
          0,
          0x80000000,
          0x3fc00000,
          0x7f800000,
          0xff800000,
          0x7fc00123,
        ]);
        const copied = guest.call(
          "copied_bits",
          new Float32Array(bits.buffer),
        ) as Float32Array;
        assert.deepEqual(
          new Uint32Array(copied.buffer, copied.byteOffset, copied.length),
          bits,
        );
      } finally {
        guest.dispose();
      }
      const raw =
        new WebAssembly.Instance(new WebAssembly.Module(built.bytes)).exports;
      const count = (name: string) =>
        Number((raw[`blot:${name}`] as WebAssembly.Global).value) >>> 0;
      for (const steps of [0, 1, 32, 2000]) {
        const before = [
          count("rc_retains"),
          count("rc_releases"),
          count("rc_destroyed"),
        ];
        (raw["blot:ownership_enter"] as CallableFunction)();
        try {
          const expected = Array.from({ length: steps }, (_, i) => i + i % 512)
            .reduce((a, b) => a + b, 0);
          assert.equal(
            (raw.reference_scratch as CallableFunction)(steps),
            expected,
          );
        } finally {
          (raw["blot:ownership_leave"] as CallableFunction)(0);
        }
        assert.equal(count("rc_roots"), 0);
        assert.equal(count("rc_leases"), 0);
        if (codegenTier === "optimized") {
          assert.deepEqual([
            (count("rc_retains") - before[0]) >>> 0,
            (count("rc_releases") - before[1]) >>> 0,
            (count("rc_destroyed") - before[2]) >>> 0,
          ], [512, 1025, 513]);
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

Deno.test("identity array sharing rechecks imported wrapper bodies across retained edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-identity-edit-" });
  const entry = `${directory}/main.blot`, helper = `${directory}/helper.blot`;
  const main = `import {generate} from "./helper"
entry const run = func (seed: U32) => return do:
  let saved = #[seed]
  let copied = generate saved.length (func index => return saved[index])
  break copied[0]
`;
  const before =
    "const generate = func count => return func callback => return @array.generate count callback\n";
  const changed =
    "const generate = func count => return func callback => return @array.generate count (func index => return callback index + 1)\n";
  const options = {
    executable: Deno.args[0],
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url),
    stdRoot: new URL("../../std", import.meta.url),
    cacheDirectory: false as const,
    codegenTier: "optimized" as const,
  };
  const compiler = await createZigProjectCompiler(options);
  try {
    let original: Uint8Array<ArrayBuffer> | undefined;
    for (
      const [source, expected] of [[before, 42], [changed, 43], [
        before,
        42,
      ]] as const
    ) {
      const sources = { [entry]: main, [helper]: source };
      const built = await compiler.build({ sources });
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        assert.equal(guest.call("run", 42), expected);
      } finally {
        guest.dispose();
      }
      const fresh = await createZigProjectCompiler(options);
      try {
        const control = await fresh.build({ sources });
        assert(control.success, JSON.stringify(control));
        assert.deepEqual(built.bytes, control.bytes);
      } finally {
        await fresh.dispose();
      }
      if (!original) original = built.bytes;
      if (source === before) assert.deepEqual(built.bytes, original);
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
