import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const fields = Array.from(
  { length: 165 },
  (_, i) => `p${i}: @u32.add input ${i}`,
).join(", ");
const reads = Array.from({ length: 165 }, (_, i) => `world.p${i}`).join(", ");
const source = `type Bank is data = $Bank {rows: Array U32, other: Array U32}
entry const run = func (input: U32): Array U32 => return do:
  let rows: Array U32 = #[input, @u32.add input 1]
  let others: Array U32 = #[2, 3]
  let world = {bank: $Bank {rows: rows, other: others}, stamp: 7, ${fields}}
  let original = world
  let first = input
  let second = @u32.add input 10
  for index in 0 .. 4:
    let prior = first
    first := second
    second := prior
    if @u32.eq (@u32.rem index 2) 0:
      world.bank.rows[0] := @u32.add self 1
    else:
      world.bank.other[1] := @u32.add self 2
    if @u32.eq index 1:
      continue
    for slot in 0 .. 2:
      world.bank.rows[slot] := @u32.add self (@u32.add index slot)
    if @u32.eq index 2:
      break
  return #[rows[0], rows[1], others[1], world.bank.rows[0], original.bank.rows[1], world.stamp, first, second, ${reads}]
entry const shadow = func (input: U32): Array U32 => return do:
  let rows: Array U32 = #[input]
  let world = {rows: rows, stamp: 7}
  let other = {rows: rows, stamp: 99}
  for index in 0 .. 3:
    world.rows[0] := @u32.add self 1
    if @u32.eq index 1:
      let world = other
      break
  return #[world.rows[0], world.stamp]
entry const fields = func (input: U32): Array U32 => return do:
  let rows: Array U32 = #[input]
  let world = {rows: rows, stamp: 7}
  let original = world
  for index in 0 .. 3:
    world.rows[0] := @u32.add self 1
    world.stamp := @u32.add self index
  return #[world.rows[0], world.stamp, original.stamp]
`;
const extra =
  `entry const field_break = func (input: U32): Array U32 => return do:
  let rows: Array U32 = #[input]
  let world = {rows: rows, stamp: 7}
  for index in 0 .. 3:
    world.rows[0] := @u32.add self 1
    world.stamp := @u32.add self index
    if @u32.eq index 1:
      break
  return #[world.rows[0], world.stamp]
entry const exits = func (input: U32): Array U32 => return do:
  let rows: Array U32 = #[input]
  let world = {rows: rows, stamp: 7}
  for index in 0 .. 3:
    if @u32.eq input 0:
      world.rows[0] := @u32.add self 1
      return #[world.rows[0], world.stamp]
    else:
      world.rows[0] := @u32.add self 2
      return #[world.rows[0], world.stamp]
  return #[99, 99]
entry const targets = func (input: U32): Array U32 => return do:
  let rows: Array U32 = #[input]
  let world = {rows: rows, stamp: 7}
  for outer in 0 .. 3:
    for inner in 0 .. 3:
      world.rows[0] := @u32.add self 1
      if @u32.eq inner 1:
        world.stamp := @u32.add self 10
        break
    if @u32.eq outer 1:
      break
  return #[world.rows[0], world.stamp]
`;
const addressed = `const unused = func (): U32 => return do:
  let value = 1
  let pointer = &value
  @storage.write pointer 2
  return value
`;
for (const tier of ["development", "optimized"] as const) {
  Deno.test(`whole-root SSA transport preserves indexed heap effects and changing carries (${tier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-ssa-transport-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier: tier,
    });
    try {
      for (const localRef of [false, true]) {
        const built = await compiler.build({
          sources: { [entry]: source + extra + (localRef ? addressed : "") },
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        if (localRef) assert.equal(work.scoped_transport_words_avoided, 0);
        else assert(work.scoped_transport_words_avoided > 0);
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const input of [0, 1, 17, 0xfffffffc, 0]) {
              const call = async (name: string) => {
                if (asynchronous) return await guest.callAsync(name, input);
                return guest.call(name, input);
              };
              const run = await call("run");
              assert.deepEqual(
                run,
                new Uint32Array([
                  input + 4,
                  input + 5,
                  5,
                  input + 4,
                  input + 5,
                  7,
                  input + 10,
                  input,
                  ...Array.from({ length: 165 }, (_, i) => input + i),
                ]),
              );
              const shadow = await call("shadow");
              assert.deepEqual(shadow, new Uint32Array([input + 2, 99]));
              assert.deepEqual(
                await call("fields"),
                new Uint32Array([input + 3, 10, 7]),
              );
              assert.deepEqual(
                await call("field_break"),
                new Uint32Array([input + 2, 8]),
              );
              let increment = 2;
              if (input === 0) increment = 1;
              assert.deepEqual(
                await call("exits"),
                new Uint32Array([input + increment, 7]),
              );
              assert.deepEqual(
                await call("targets"),
                new Uint32Array([input + 4, 27]),
              );
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
