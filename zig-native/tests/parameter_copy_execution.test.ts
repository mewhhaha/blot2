import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const plain = `type Pair is data = $Pair {left: U32, right: U32}
const adjust = func (value: U32): U32 => return do:
  let original = value
  value := @u32.add value 1
  return @u32.add original value
const exchange = func (pair: Pair): U32 => return do:
  let saved = func () => return pair.left
  for 0 .. 3:
    let old = pair.left
    pair.left := pair.right
    pair.right := old
  return @u32.add (saved ()) (@u32.add (@u32.mul pair.left 10) pair.right)
entry const answer = func (input: U32): Array U32 => return do:
  let owned: ResizeArray U32 = #[input]
  @storage.push owned input
  let value = owned[1]
  return #[adjust value, exchange ($Pair {left: value, right: @u32.add value 1})]
`;
const addressed =
  `const observe = func (original: U32) -> (reference: Ref U32): U32 => return do:
  @storage.write reference 42
  return original
entry const answer = func (input: U32): Array U32 => return do:
  let value = input
  let original = observe value (&value)
  return #[original, value]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`parameter copies preserve rebinding captures carries and address fallback (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-parameter-copy-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      // Retained edits must recompute the inventory fact in both directions.
      const edited = plain.replace("@u32.add value 1", "@u32.add value 2");
      for (const source of [plain, addressed, edited]) {
        const built = await compiler.build({
          sources: { [entry]: source },
          signal: AbortSignal.timeout(5_000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        if (source !== addressed) {
          assert(work.scoped_parameter_words_shared > 0);
        } else assert.equal(work.scoped_parameter_words_shared, 0);
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const input of [0, 1, 17, 0xfffffffd, 0]) {
              let expected = [input, 42];
              if (source !== addressed) {
                let extra = 1;
                if (source === edited) extra = 2;
                expected = [input * 2 + extra, input * 12 + 10];
              }
              let actual;
              if (asynchronous) actual = await guest.callAsync("answer", input);
              else actual = guest.call("answer", input);
              assert.deepEqual(actual, new Uint32Array(expected));
            }
          } finally {
            guest.dispose();
          }
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

const immutableBindingsSource =
  `type Inner is data = $Inner {left: U32, right: U32}
type Box is data = $Box {inner: Inner, kept: U32}
const plus = func (saved: U32) -> (amount: U32): U32 => return @u32.add saved amount
const make = func (saved: U32) => return func (amount: U32): U32 => return @u32.add saved amount
const loop_closure = func (input: U32) => return do:
  let current = input
  for index in 0 .. 3:
    let captured = make current
    current := @u32.add current 1
    if @u32.eq index 1:
      return captured
  return make current
const loop_partial = func (input: U32) => return do:
  let current = input
  for index in 0 .. 3:
    let captured = plus current
    current := @u32.add current 1
    if @u32.eq index 1:
      return captured
  return plus current
entry const rotate = func (input: U32): Array U32 => return do:
  let trace: ResizeArray U32 = #[]
  let left = input
  let middle = @u32.add input 1
  let right = @u32.add input 2
  for index in 0 .. 6:
    let before_left = left
    let before_middle = middle
    left := middle
    middle := right
    right := before_left
    @storage.push trace before_left
    @storage.push trace before_middle
    if @u32.eq index 1:
      continue
    if @u32.eq index 3:
      break
    @storage.push trace right
  @storage.push trace left
  @storage.push trace middle
  @storage.push trace right
  return @storage.freeze trace
entry const captured = func (input: U32): Array U32 => return do:
  let marker: ResizeArray U32 = #[input]
  return #[(loop_closure marker[0]) 10, (loop_partial marker[0]) 20]
entry const updated = func (input: U32): Array U32 => return do:
  let original = $Box {inner: $Inner {left: input, right: @u32.add input 1}, kept: 7}
  let changed = original
  changed.inner.left := changed.inner.right
  changed.inner.right := @u32.add self 10
  let saved = changed
  changed.inner := $Inner {left: 0, right: 99}
  return #[original.inner.left, original.inner.right, saved.inner.left, saved.inner.right, changed.inner.left, changed.inner.right, original.kept, saved.kept]
`;

const addressedBindingsSource =
  `type Pair is data = $Pair {left: U32, right: U32}
const overwrite = func (reference: Ref U32): Unit => return @storage.write reference 42
entry const fallback = func (input: U32): Array U32 => return do:
  let value = input
  let saved = value
  let pair = $Pair {left: value, right: @u32.add input 1}
  let before = pair
  pair.left := 99
  overwrite (&value)
  return #[saved, value, before.left, pair.left]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`immutable local bindings preserve copies at control and capture boundaries (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-immutable-bindings-",
    });
    const entry = `${directory}/main.blot`;
    let compiler:
      | Awaited<ReturnType<typeof createZigProjectCompiler>>
      | undefined;
    try {
      compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
        startupTimeoutMs: 5_000,
      });
      // Restore the no-address proof after an addressed retained edit too.
      for (
        const source of [
          immutableBindingsSource,
          addressedBindingsSource,
          immutableBindingsSource,
        ]
      ) {
        const built = await compiler.build({
          sources: { [entry]: source },
          signal: AbortSignal.timeout(5_000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        const addressed = source === addressedBindingsSource;
        if (addressed) {
          assert.equal(work.scoped_parameter_words_shared, 0);
          assert.equal(work.scoped_local_words_shared, 0);
          assert.equal(work.scoped_record_updates_shared, 0);
        } else {
          assert(work.scoped_local_words_shared > 0);
          assert(work.scoped_record_updates_shared > 0);
        }
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const input of [0, 1, 42, 0xfffffffe, 0]) {
              const invoke = async (name: string) => {
                if (asynchronous) return await guest.callAsync(name, input);
                return guest.call(name, input);
              };
              if (addressed) {
                assert.deepEqual(
                  await invoke("fallback"),
                  new Uint32Array([input, 42, input, 99]),
                );
                continue;
              }
              let left = input;
              let middle = (input + 1) >>> 0;
              let right = (input + 2) >>> 0;
              const trace: number[] = [];
              for (let index = 0; index < 6; index++) {
                const beforeLeft = left;
                const beforeMiddle = middle;
                left = middle;
                middle = right;
                right = beforeLeft;
                trace.push(beforeLeft, beforeMiddle);
                if (index === 1) continue;
                if (index === 3) break;
                trace.push(right);
              }
              trace.push(left, middle, right);
              assert.deepEqual(await invoke("rotate"), new Uint32Array(trace));
              assert.deepEqual(
                await invoke("captured"),
                new Uint32Array([input + 11, input + 21]),
              );
              assert.deepEqual(
                await invoke("updated"),
                new Uint32Array([
                  input,
                  input + 1,
                  input + 1,
                  input + 11,
                  0,
                  99,
                  7,
                  7,
                ]),
              );
            }
          } finally {
            guest.dispose();
          }
        }
      }
    } finally {
      await compiler?.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
