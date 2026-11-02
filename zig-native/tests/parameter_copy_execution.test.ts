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

const indexedAccessFields = Array.from(
  { length: 165 },
  (_, index) => `p${index}: @u32.add input ${index}`,
).join(", ");
const indexedAccessReads = Array.from(
  { length: 165 },
  (_, index) => `alias.p${index}`,
).join(", ");
const indexedAccessSource =
  (`type IndexedRow is data = $IndexedRow {left: U32, right: U32}
type IndexedBank is data = $IndexedBank {rows: ResizeArray IndexedRow, other: ResizeArray U32}
type IndexedWorld is data = $IndexedWorld {bank: IndexedBank, stamp: U32}
const indexed_slot = func (counts: Array U32): U32 => return do:
  let slot = counts[0]
  counts[0] := @u32.add slot 1
  return slot
entry const indexed = func (input: U32): Array U32 => return do:
  let rows: ResizeArray IndexedRow = #[$IndexedRow {left: input, right: 7}, $IndexedRow {left: @u32.add input 1, right: 11}]
  let other: ResizeArray U32 = #[3, 4]
  let counts: Array U32 = #[0]
  let access = {extra: input, world: $IndexedWorld {bank: $IndexedBank {rows, other}, stamp: 23}, counts, borrowed: &other[0..2]}
  let alias = access
  access.world.bank.rows[indexed_slot access.counts].left := do:
    rows[0] := $IndexedRow {left: @u32.add input 100, right: 88}
    rows[1].right := 66
    other[0] := counts[0]
    other[1] := 44
    break @u32.add self 10
  return #[counts[0], rows[0].left, rows[0].right, rows[1].left, rows[1].right, other[0], other[1], alias.world.bank.rows[0].left, alias.world.bank.rows[0].right, alias.borrowed[0], alias.borrowed[1], alias.world.stamp, alias.extra]
entry const indexed_early = func (input: U32): Array U32 => return do:
  let rows: ResizeArray IndexedRow = #[$IndexedRow {left: input, right: 7}]
  let other: ResizeArray U32 = #[3]
  let counts: Array U32 = #[0]
  let access = {world: $IndexedWorld {bank: $IndexedBank {rows, other}, stamp: 23}, counts}
  access.world.bank.rows[indexed_slot access.counts].left := do:
    if @u32.eq input 0:
      return #[11, counts[0], rows[0].left]
    break 7
  return #[rows[0].left, counts[0], 99]
`).replace("extra: input", indexedAccessFields).replace(
    "alias.extra",
    indexedAccessReads,
  );
const indexedShrinkSource =
  `entry const indexed_shrink = func (input: U32): U32 => return do:
  let rows: ResizeArray IndexedRow = #[$IndexedRow {left: input, right: 7}]
  let other: ResizeArray U32 = #[3]
  let access = {world: $IndexedWorld {bank: $IndexedBank {rows, other}, stamp: 23}, sibling: &other[0..1]}
  access.world.bank.rows[0].left := do:
    @storage.truncate other 0
    break self
  return access.sibling[0]
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
      const positiveSource = immutableBindingsSource + indexedAccessSource;
      const addressedSource = addressedBindingsSource + indexedAccessSource;
      for (const source of [positiveSource, addressedSource, positiveSource]) {
        const built = await compiler.build({
          sources: { [entry]: source },
          signal: AbortSignal.timeout(5_000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        const addressed = source === addressedSource;
        if (addressed) {
          assert.equal(work.scoped_parameter_words_shared, 0);
          assert.equal(work.scoped_local_words_shared, 0);
          assert.equal(work.scoped_record_updates_shared, 0);
          assert.equal(work.scoped_indexed_update_roots_shared, 0);
        } else {
          assert(work.scoped_local_words_shared > 0);
          assert(work.scoped_record_updates_shared > 0);
          assert(work.scoped_indexed_update_roots_shared > 0);
        }
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const input of [0, 1, 42, 0xfffffffe, 0]) {
              const invoke = async (name: string) => {
                if (asynchronous) return await guest.callAsync(name, input);
                return guest.call(name, input);
              };
              assert.deepEqual(
                await invoke("indexed"),
                new Uint32Array([
                  1,
                  input + 10,
                  88,
                  input + 1,
                  66,
                  1,
                  44,
                  input + 10,
                  88,
                  1,
                  44,
                  23,
                  ...Array.from({ length: 165 }, (_, index) => input + index),
                ]),
              );
              let early = [7, 1, 99];
              if (input === 0) early = [11, 1, 0];
              assert.deepEqual(
                await invoke("indexed_early"),
                new Uint32Array(early),
              );
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
      const shrinking = await compiler.build({
        sources: { [entry]: indexedAccessSource + indexedShrinkSource },
        signal: AbortSignal.timeout(5_000),
      });
      assert(!shrinking.success, JSON.stringify(shrinking));
      assert(
        shrinking.diagnostics.some((diagnostic) =>
          diagnostic.code === "storage_borrow_conflict"
        ),
        JSON.stringify(shrinking),
      );
    } finally {
      await compiler?.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

const closedDiamondSource =
  `const leaf = func (value: U32): U32 => return @u32.add value 1
const left = func (value: U32): U32 => return leaf value
const right = func (value: U32): U32 => return leaf value
const diamond = func (value: U32): U32 => return @u32.add (left value) (right value)
const flip = func (value: F32): F32 => return @f32.neg value
const restored = func (value: F32): F32 => return flip (flip value)
`;
const closedDiamondCaller = `import * as closed from "trial/closed"
const integer = func (value: U32): U32 => return closed.diamond value
const floating = func (value: F32): F32 => return closed.restored value
`;
const closedDiamondEntry = `import * as first from "trial/first"
import * as second from "trial/second"
import * as third from "trial/third"
entry const integer = func (input: U32): Array U32 => return do:
  let rows: ResizeArray U32 = #[input]
  return #[first.integer rows[0], second.integer rows[0], third.integer rows[0]]
entry const floating = func (input: F32): Array F32 => return do:
  let rows: ResizeArray F32 = #[input]
  return #[first.floating rows[0], second.floating rows[0], third.floating rows[0]]
`;
const contextualDispatchEntry = `import * as first from "trial/first"
import * as second from "trial/second"
entry const dispatched = func (input: U32): Array U32 => return do:
  let rows: ResizeArray U32 = #[input]
  return #[first.integer rows[0], second.integer rows[0], first.integer rows[0], second.integer rows[0]]
`;
const contextualDispatchCaller = `import * as generic from "trial/generic"
type Number is data = $Number U32
const Number.add = func (left: Number) -> (right: U32): U32 => return do:
  let $Number value = left
  return @u32.add value right
const integer = func (value: U32): U32 => return generic.combine ($Number value) 3
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`closed scalar diamonds share definitions across caller units without merging contextual dispatch (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-closed-context-",
    });
    const entry = `${directory}/main.blot`;
    let compiler:
      | Awaited<ReturnType<typeof createZigProjectCompiler>>
      | undefined;
    try {
      compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        imports: { "trial/": directory },
        prelude: null,
        cacheDirectory: false,
        codegenTier,
        startupTimeoutMs: 5_000,
      });
      const built = await compiler.build({
        sources: {
          [entry]: closedDiamondEntry,
          [`${directory}/closed.blot`]: closedDiamondSource,
          [`${directory}/first.blot`]: closedDiamondCaller,
          [`${directory}/second.blot`]: closedDiamondCaller,
          [`${directory}/third.blot`]: closedDiamondCaller,
        },
        signal: AbortSignal.timeout(5_000),
      });
      assert(built.success, JSON.stringify(built));
      const work = built.stats.workCounters as Record<string, number>;
      // Six library bodies and two wrapper bodies in each of three units.
      assert.equal(work.scoped_scalar_definitions, 12, JSON.stringify(work));
      assert(work.scoped_scalar_cache_hits > 0);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          for (
            const input of [0, 1, 42, 0x7fffffff, 0xfffffffe, 0xffffffff, 0]
          ) {
            let actual;
            if (asynchronous) actual = await guest.callAsync("integer", input);
            else actual = guest.call("integer", input);
            const expected = (input * 2 + 2) >>> 0;
            assert.deepEqual(
              actual,
              new Uint32Array([expected, expected, expected]),
            );
          }
          // Compare F32 transport bits, including both zero signs and infinities.
          for (
            const bits of [
              0,
              0x80000000,
              0x3fc00000,
              0xc0500000,
              0x7f800000,
              0xff800000,
            ]
          ) {
            const input = new Float32Array(Uint32Array.of(bits).buffer)[0];
            let actual;
            if (asynchronous) actual = await guest.callAsync("floating", input);
            else actual = guest.call("floating", input);
            const values = actual as Float32Array;
            assert.deepEqual(
              new Uint32Array(values.buffer, values.byteOffset, values.length),
              new Uint32Array([bits, bits, bits]),
            );
          }
        } finally {
          guest.dispose();
        }
      }
      const dispatched = await compiler.build({
        sources: {
          [entry]: contextualDispatchEntry,
          [`${directory}/generic.blot`]:
            'const combine = func left -> right => return @type.call "add" left right\n',
          [`${directory}/first.blot`]: contextualDispatchCaller,
          [`${directory}/second.blot`]: contextualDispatchCaller.replace(
            "@u32.add value right",
            "@u32.sub value right",
          ),
        },
        signal: AbortSignal.timeout(5_000),
      });
      assert(dispatched.success, JSON.stringify(dispatched));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(dispatched.bytes, {
          asynchronous,
        });
        try {
          for (const input of [0, 1, 42, 0xffffffff, 0]) {
            let actual;
            if (asynchronous) {
              actual = await guest.callAsync("dispatched", input);
            } else actual = guest.call("dispatched", input);
            const added = (input + 3) >>> 0;
            const subtracted = (input - 3) >>> 0;
            assert.deepEqual(
              actual,
              new Uint32Array([added, subtracted, added, subtracted]),
            );
          }
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler?.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
