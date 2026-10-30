import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `
const integer = func (index: U32) => return do:
  let shifted = @u32.add index 17
  let wrapped = @u32.mul shifted 4294967295
  break @u32.add wrapped 1
const floating = func (index: U32) => return do:
  let value = @u32.to_f32 index
  let scaled = @f32.mul value 16777216.0
  let rounded = @f32.add scaled 1.0
  break @f32.sub rounded scaled
entry const integers = func (count: U32) => return @array.generate count integer
entry const floats = func (count: U32) => return @array.generate count floating
entry const divide = func (count: U32) => return @array.generate count (func index => return do:
  let divisor = @u32.sub 4 index
  break @u32.div 12 divisor)
entry const shared = func (count: U32) => return do:
  let original = @array.generate count integer
  let saved = original
  original[0] := 99
  break #[saved[0], original[0], saved[@u32.sub count 1]]
entry const effectful = func (host: U32 -> U32 ! {Foreign}) => return do:
  let values = @array.fill 9 0
  for index in 0..9:
    use value <- host index
    let next = @u32.add value 1
    values[index] := next
  break values
`;

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`numeric helpers with private scopes keep tails, snapshots and scalar fallbacks (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-numeric-scopes-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const built = await compiler.build({ sources: { [entry]: source } });
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        for (
          const count of [0, 1, 2, 3, 4, 5, 7, 8, 9, 31, 63, 65, 257, 4099]
        ) {
          assert.deepEqual(
            guest.call("integers", count),
            Uint32Array.from(
              { length: count },
              (_, index) => (-(index + 17) + 1) >>> 0,
            ),
          );
          assert.deepEqual(
            guest.call("floats", count),
            Float32Array.from({ length: count }, (_, index) =>
              Math.fround(
                Math.fround(Math.fround(index * 16777216) + 1) -
                  Math.fround(index * 16777216),
              )),
          );
          if (count !== 0) {
            assert.deepEqual(
              guest.call("shared", count),
              Uint32Array.of((-17 + 1) >>> 0, 99, (-(count + 16) + 1) >>> 0),
            );
          }
        }
        assert.deepEqual(guest.call("divide", 4), Uint32Array.of(3, 4, 6, 12));
        assert.throws(() => guest.call("divide", 5), WebAssembly.RuntimeError);
        const seen: number[] = [];
        const host = guest.capability({
          parameter: "U32",
          result: "U32",
          call(value) {
            seen.push(value);
            return value;
          },
        });
        assert.deepEqual(
          guest.call("effectful", host),
          Uint32Array.from({ length: 9 }, (_, index) => index + 1),
        );
        assert.deepEqual(seen, Array.from({ length: 9 }, (_, index) => index));
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

Deno.test("numeric helper admission revalidates retained and checkpoint edits", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-numeric-revision-",
  });
  const entry = `${directory}/main.blot`;
  const changed = source.replace(
    "@u32.mul shifted 4294967295",
    "@u32.div 12 (@u32.sub 4 index)",
  );
  let checkpoint: Uint8Array<ArrayBuffer> | undefined;
  try {
    const retained = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      cacheDirectory: false,
    });
    try {
      for (const text of [source, changed, source]) {
        const built = await retained.build({ sources: { [entry]: text } });
        assert(built.success, JSON.stringify(built));
        const fresh = await createZigProjectCompiler({
          executable,
          entry,
          prelude: null,
          cacheDirectory: false,
        });
        try {
          const ordinary = await fresh.build({ sources: { [entry]: text } });
          assert(ordinary.success, JSON.stringify(ordinary));
          assert.deepEqual(built.bytes, ordinary.bytes);
        } finally {
          await fresh.dispose();
        }
        const guest = await instantiateGuest(built.bytes);
        try {
          if (text === changed) {
            assert.deepEqual(
              guest.call("integers", 4),
              Uint32Array.of(4, 5, 7, 13),
            );
            assert.throws(
              () => guest.call("integers", 5),
              WebAssembly.RuntimeError,
            );
          } else {
            assert.deepEqual(
              guest.call("integers", 5),
              Uint32Array.of(
                4294967280,
                4294967279,
                4294967278,
                4294967277,
                4294967276,
              ),
            );
          }
        } finally {
          guest.dispose();
        }
      }
      checkpoint = await retained.exportCheckpoint();
    } finally {
      await retained.dispose();
    }
    const restarted = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      cacheDirectory: false,
      checkpoint,
    });
    try {
      const built = await restarted.build({ sources: { [entry]: changed } });
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        assert.throws(
          () => guest.call("integers", 5),
          WebAssembly.RuntimeError,
        );
      } finally {
        guest.dispose();
      }
    } finally {
      await restarted.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
