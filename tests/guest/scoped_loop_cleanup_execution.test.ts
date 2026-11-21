import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const entry =
  new URL("../../compiler-goose/tests/fixtures/scoped-loop-cleanup.blot", import.meta.url).pathname;

{
  Deno.test(`loop cleanup preserves temporary owners and conditional returns`, async () => {
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      storage: {
        temporaryBytes: 1024,
        growerBytes: 256,
        persistentBytes: 256,
        transportBytes: 1024,
        ownerCapacity: 32,
      },
    });
    try {
      const built = await compiler.build();
      assert(built.success, JSON.stringify(built));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          assert.equal(guest.abi.version, 8);
          const call = async (name: string, input: number | null) => {
            if (asynchronous) return await guest.callAsync(name, input);
            return guest.call(name, input);
          };
          // The 1 KiB temporary lane cannot retain thousands of array extents.
          for (const count of [0, 1, 2, 17, 4096, 17]) {
            let scalar = 7;
            for (let index = 1; index < count; index += 2) {
              scalar += 3 * index + 3;
            }
            assert.equal(await call("scalar", count), scalar);
            assert.equal(
              await call("forever", count),
              Math.floor(count / 2) ** 2,
            );
            assert.equal(
              await call("temporary", count),
              3 * count * (count - 1) / 2 + count + 7,
            );
            let expected = [99];
            if (count !== 0) expected = [count - 1, count];
            for (const name of ["conditional", "conditional_scratch"]) {
              assert.deepEqual(
                Array.from(await call(name, count) as Uint32Array),
                expected,
              );
            }
          }
          await assert.rejects(
            () => call("bounds", 2),
            WebAssembly.RuntimeError,
          );
          assert.equal(await call("bounds", 1), 42);
          assert.equal(await call("temporary", 4096), 25163783);
          for (const value of [0, 17, 4096]) {
            assert.deepEqual(
              Array.from(await call("grow_rhs", value) as Uint32Array),
              [value + 10, value + 1],
            );
            assert.deepEqual(
              Array.from(await call("sibling_rhs", value) as Uint32Array),
              [value, value + 1],
            );
          }
          assert.equal(await call("counter_read", null), 0);
          await assert.rejects(
            () => call("checked_order", 1),
            WebAssembly.RuntimeError,
          );
          assert.equal(await call("counter_read", null), 0);
          assert.equal(await call("checked_order", 0), 42);
          assert.equal(await call("counter_read", null), 1);
        } finally {
          guest.dispose();
        }
      }
      // Ownership is checked at run time: storing into an element that the
      // right-hand side truncated away traps.
      const truncated = await compiler.build({
        sources: {
          [entry]: await Deno.readTextFile(entry) + `
const shrink_rhs = func (rows: ResizeArray U32): U32 => return do:
  @storage.truncate rows 0
  return 42
entry const invalid = func (): U32 => return do:
  let rows: ResizeArray U32 = #[1]
  let alias = rows
  rows[0] = shrink_rhs alias
  return rows[0]
`,
        },
      });
      assert(truncated.success, JSON.stringify(truncated));
      const guest = await instantiateGuest(truncated.bytes);
      try {
        assert.throws(() => guest.call("invalid", null), WebAssembly.RuntimeError);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.close();
    }
  });

  Deno.test(`method push of memory-holding values preserves caller temporary stack reclamation`, async () => {
    const source = `
type Boxed = { a: U32, b: U32, c: U32, d: U32, e: U32, view: &[U32] }
func make_row (base: &[U32]) -> (i: U32): Boxed =>
  return { a: i, b: i + 1, c: i + 2, d: i + 3, e: i + 4, view: base }
entry func main (count: U32): U32 =>
  let backing: #[U32] = #[10, 20, 30, 40]
  let view = &backing[0..backing.length]
  let out: #[+Boxed] = #[]
  for i in 0 .. count:
    out.push (make_row view i)
  let total = 0
  for row in out:
    total := self + row.a + row.view[0]
  return total
`;
    const dir = await Deno.makeTempDir();
    const path = `${dir}/main.blot`;
    await Deno.writeTextFile(path, source);
    const compiler = await createZigProjectCompiler({
      executable,
      entry: path,
      stdRoot: new URL("../../std", import.meta.url).pathname,
      prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
      storage: {
        temporaryBytes: 2048,
        growerBytes: 65536,
        persistentBytes: 256,
        transportBytes: 1024,
        ownerCapacity: 64,
      },
    });
    try {
      const built = await compiler.build();
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        // 256 iterations * boxed Boxed would overflow 2 KiB temporary stack if
        // forwarding `out.push` poisoned caller memory_stores and blocked release.
        assert.equal(guest.call("main", 256), 256 * 255 / 2 + 256 * 10);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.close();
      await Deno.remove(dir, { recursive: true });
    }
  });
}
