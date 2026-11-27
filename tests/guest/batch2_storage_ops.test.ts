import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url);

async function buildGuest(source: string) {
  const dir = await Deno.makeTempDir({ prefix: "blot-batch2-" });
  const entry = `${dir}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude,
  });
  try {
    const built = await compiler.build({ sources: { [entry]: source } });
    assert(built.success, JSON.stringify(built));
    return {
      bytes: built.bytes,
      guest: await instantiateGuest(built.bytes),
      cleanup: async () => {
        await Deno.remove(dir, { recursive: true });
      },
    };
  } finally {
    await compiler.close();
  }
}

Deno.test("Batch 2: Array.with_capacity, Array.reserve, Array.extend and Array.extend_view", async () => {
  const source = `
io test_with_cap (n: U32): #[U32] =>
  let out: #[U32] = Array.with_capacity n
  for i in 0..n:
    out := self.push (i * 3 + 1)
  return out

io test_zero_cap (): #[U32] =>
  let out: #[U32] = Array.with_capacity 0
  out := self.push 10
  out := self.push 20
  return out

io test_reserve (n: U32): #[U32] =>
  let out: #[U32] = #[]
  out := self.reserve n
  for i in 0..n:
    out := self.push (i + 5)
  out := self.reserve 0
  return out

io test_extend (n: U32): #[U32] =>
  let chunk = @array.generate n (func i => i + 1)
  let out: #[U32] = Array.with_capacity (n * 3)
  out := self.extend chunk
  out := self.extend_view (&chunk[1..n])
  out := self.extend #[]
  return out

io test_extend_bytes (reps: U32): U32 =>
  let pat: #[U8] = #[65, 66, 67, 68]
  let out: #[U8] = Array.with_capacity (reps * 4)
  for _ in 0..reps:
    out := self.extend pat
  let sum = 0
  for b in out:
    sum := self + b.to_u32
  return sum

io test_extend_nested (): #[U32] =>
  let inner1: #[U32] = #[1, 2]
  let inner2: #[U32] = #[3, 4]
  let src: #[#[U32]] = #[inner1, inner2]
  let dst: #[#[U32]] = #[]
  dst := self.extend src
  // Mutate dst[0] to prove src[0] was deep-copied and stays independent!
  dst[0][0] := 99
  return #[src[0][0], dst[0][0], dst[1][1]]

io test_fork_rollback (): #[U32] =>
  let out: #[U32] = Array.with_capacity 4
  out := self.push 1
  out := self.push 2
  let spec = fork out:
    let more: #[U32] = #[3, 4, 5, 6, 7, 8]
    out := out.reserve 16
    out := out.extend more
    return out.length
  out := self.push spec
  return out
`;
  const { guest, cleanup } = await buildGuest(source);
  try {
    assert.deepEqual(
      Array.from(guest.call("test_with_cap", 6) as Uint32Array),
      [1, 4, 7, 10, 13, 16],
    );
    assert.deepEqual(
      Array.from(guest.call("test_zero_cap", null) as Uint32Array),
      [10, 20],
    );
    assert.deepEqual(
      Array.from(guest.call("test_reserve", 5) as Uint32Array),
      [5, 6, 7, 8, 9],
    );
    assert.deepEqual(
      Array.from(guest.call("test_extend", 4) as Uint32Array),
      [1, 2, 3, 4, 2, 3, 4],
    );
    assert.equal(guest.call("test_extend_bytes", 10), 10 * (65 + 66 + 67 + 68));
    assert.deepEqual(
      Array.from(guest.call("test_extend_nested", null) as Uint32Array),
      [1, 99, 4],
    );
    assert.deepEqual(
      Array.from(guest.call("test_fork_rollback", null) as Uint32Array),
      [1, 2, 8],
    );
  } finally {
    guest.dispose();
    await cleanup();
  }
});

Deno.test("Batch 2: direct stack-backed small local fixed arrays skip owner table and trap OOB", async () => {
  const source = `
io test_lut (x: U32): U32 =>
  let lut = #[10, 20, 30, 40, 50, 60, 70, 80]
  return lut[x & 7] + lut[0] + @array.length lut

io test_hist (n: U32): U32 =>
  let hist = @array.fill 16 0
  for i in 0..n:
    hist[i & 15] := self + 1
  let total = 0
  for i in 0..16:
    total := self + hist[i] * (i + 1)
  return total

io test_oob (idx: U32): U32 =>
  let small = #[1, 2, 3, 4]
  return small[idx]
`;
  const { guest, cleanup } = await buildGuest(source);
  try {
    assert.equal(guest.call("test_lut", 3), 40 + 10 + 8);
    assert.equal(guest.call("test_lut", 10), 30 + 10 + 8);
    // n = 32 -> every bucket 0..15 gets 2 -> sum_{i=0..15} 2*(i+1) = 2 * 136 = 272
    assert.equal(guest.call("test_hist", 32), 272);
    assert.equal(guest.call("test_oob", 2), 3);
    assert.throws(() => guest.call("test_oob", 4), WebAssembly.RuntimeError);
  } finally {
    guest.dispose();
    await cleanup();
  }
});

Deno.test("Batch 2: uniqueness rejects aliased @storage.reserve and @storage.extend", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-batch2-uniq-" });
  const entry = `${dir}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude,
  });
  try {
    const res1 = await compiler.build({
      sources: {
        [entry]: `
io bad (a: #[U32]): #[U32] =>
  let b = @storage.reserve a 10
  return #[a[0], b[0]]
`,
      },
    });
    assert(!res1.success, "expected aliased reserve to fail uniqueness");
    const res2 = await compiler.build({
      sources: {
        [entry]: `
io bad (a: #[U32]): #[U32] =>
  let b = @storage.extend a #[1, 2]
  return #[a[0], b[0]]
`,
      },
    });
    assert(!res2.success, "expected aliased extend to fail uniqueness");
  } finally {
    await compiler.close();
    await Deno.remove(dir, { recursive: true });
  }
});
