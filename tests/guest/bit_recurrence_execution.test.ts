import { strict as assert } from "node:assert";
import { type Guest, instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const stdRoot = new URL("../../std", import.meta.url).pathname;
function step(value: number, polynomial: number, left = false): number {
  if (left) {
    if ((value & 0x80000000) !== 0) return ((value << 1) ^ polynomial) >>> 0;
    return (value << 1) >>> 0;
  }
  if ((value & 1) !== 0) return ((value >>> 1) ^ polynomial) >>> 0;
  return value >>> 1;
}
function repeated(
  value: number,
  polynomial: number,
  count: number,
  left = false,
) {
  for (let index = 0; index < count; index++) {
    value = step(value, polynomial, left);
  }
  return value;
}
function recurrence(
  name: string,
  count: number,
  polynomial: number,
  first = 0,
) {
  return `const ${name}_shift = func (value: U32): U32 => return value >> 1
const ${name}_mix = func (value: U32): U32 => return ${name}_shift value ^ ${polynomial}
const ${name} = func (input: U32): U32 => return do:
  let state = input
  for bit in ${first} .. ${first + count}:
    if state & 1 == 0:
      state := ${name}_shift self
    else:
      state := ${name}_mix self
  return state
entry const ${name}_answer = func (input: U32): U32 => return do:
  let marker: GrowArray U32 = #[input]
  return ${name} marker[0]
`;
}
async function withGuest(
  bytes: Uint8Array<ArrayBuffer>,
  run: (guest: Guest) => void,
) {
  const guest = await instantiateGuest(bytes);
  try {
    run(guest);
  } finally {
    guest.dispose();
  }
}

Deno.test("fixed bit loops preserve polynomial count boundaries helpers shifts effects and trap recovery in both tiers", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-bit-laws-" });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        stdRoot,
        prelude: `${stdRoot}/prelude.blot`,
        cacheDirectory: false,
        codegenTier,
      });
      try {
        let source = "";
        const cases: { name: string; count: number; polynomial: number }[] = [];
        for (const polynomial of [0, 0xEDB88320, 0x12345678]) {
          for (const count of [0, 1, 2, 7, 8, 9]) {
            const name = `bits_${polynomial}_${count}`;
            cases.push({ name, count, polynomial });
            source += recurrence(name, count, polynomial, 3);
          }
        }
        source += `entry const left = func (input: U32): U32 => return do:
  let rows: GrowArray U32 = #[input]
  let state = rows[0]
  for bit in 0 .. 2:
    if state & 0x80000000 != 0:
      state := (self << 1) ^ 0xA24BAED4
    else:
      state := self << 1
  return state
entry const iterator = func (input: U32): U32 => return do:
  let rows: GrowArray U32 = #[input]
  let state = rows[0]
  for bit in 3 .. 11:
    state := (self >> 1) ^ bit
  return state
entry const multiple = func (input: U32): U32 => return do:
  let rows: GrowArray U32 = #[input]
  let state = rows[0]
  let other = 1
  for bit in 0 .. 8:
    state := self >> 1
    other := self ^ state
  return other
entry const memory = func (input: U32): U32 => return do:
  let rows: GrowArray U32 = #[input]
  let state = rows[0]
  for bit in 0 .. 8:
    rows[0] := self + 1
    state := self >> 1
  return state ^ rows[0]
entry const exits = func (input: U32): U32 => return do:
  let rows: GrowArray U32 = #[input]
  let state = rows[0]
  for bit in 0 .. 8:
    if state & 1 != 0:
      return state
    state := self >> 1
  return state
entry const breaking = func (input: U32): U32 => return do:
  let rows: GrowArray U32 = #[input]
  let state = rows[0]
  for bit in 0 .. 8:
    if state & 1 != 0:
      break
    state := self >> 1
  return state
entry const division = func (input: U32): U32 => return do:
  let rows: GrowArray U32 = #[input]
  let state = 0xFFFFFFFF
  for bit in 0 .. 8:
    state := self / rows[0]
  return state
entry const effects = func (host: U32 -> U32 ! {Foreign}): U32 ! {Foreign} => return do:
  let rows: GrowArray U32 = #[0]
  let state = rows[0]
  for bit in 0 .. 8:
    use next <- host state
    state := next
  return state
`;
        const built = await compiler.build({ sources: { [entry]: source } });
        assert(built.success, JSON.stringify(built));
        const counters = built.stats.workCounters as Record<string, number>;
        assert((counters.scoped_bit_recurrences ?? 0) >= 12);
        await withGuest(built.bytes, (guest) => {
          const inputs = [0, 1, 2, 3, 0x80000000, 0xffffffff];
          for (let bit = 0; bit < 32; bit++) inputs.push((2 ** bit) >>> 0);
          let seed = 771923;
          for (let index = 0; index < 32; index++) {
            seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
            inputs.push(seed);
          }
          for (const input of inputs) {
            for (const item of cases) {
              assert.equal(
                guest.call(`${item.name}_answer`, input),
                repeated(input, item.polynomial, item.count),
              );
            }
            assert.equal(
              guest.call("left", input),
              repeated(input, 0xA24BAED4, 2, true),
            );
            let expected = input;
            for (let bit = 3; bit < 11; bit++) {
              expected = ((expected >>> 1) ^ bit) >>> 0;
            }
            assert.equal(guest.call("iterator", input), expected);
            expected = 1;
            for (let bit = 0; bit < 8; bit++) expected ^= input >>> (bit + 1);
            assert.equal(guest.call("multiple", input), expected >>> 0);
            assert.equal(
              guest.call("memory", input),
              ((input >>> 8) ^ ((input + 8) >>> 0)) >>> 0,
            );
            expected = input;
            for (let bit = 0; bit < 8 && (expected & 1) === 0; bit++) {
              expected >>>= 1;
            }
            assert.equal(guest.call("exits", input), expected);
            assert.equal(guest.call("breaking", input), expected);
          }
          assert.throws(() => guest.call("division", 0));
          assert.equal(guest.call("division", 1), 0xffffffff);
          let calls = 0;
          const host = guest.capability({
            parameter: "U32",
            result: "U32",
            call: (value) => {
              calls++;
              return value + 1;
            },
          });
          assert.equal(guest.call("effects", host), 8);
          assert.equal(calls, 8);
        });
        const addressed = await compiler.build({
          sources: {
            [entry]:
              `entry const addressed = func (input: U32): U32 => return do:
  let rows: GrowArray U32 = #[input]
  let state = rows[0]
  let address = @storage.ref state
  for bit in 0 .. 8:
    @storage.write address (@storage.load address >> 1)
  return state
`,
          },
        });
        assert(addressed.success, JSON.stringify(addressed));
        const addressedCounters = addressed.stats.workCounters as Record<
          string,
          number
        >;
        assert.equal(addressedCounters.scoped_bit_recurrences, 0);
        await withGuest(addressed.bytes, (guest) => {
          for (const input of [0, 1, 0xffffffff]) {
            assert.equal(guest.call("addressed", input), input >>> 8);
          }
        });
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("retained bit proofs observe helper edits rejected revisions and exact reverts", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-bit-edits-" });
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0],
    entry,
    stdRoot,
    prelude: `${stdRoot}/prelude.blot`,
    cacheDirectory: false,
  });
  try {
    const original = recurrence("bits", 8, 0xEDB88320);
    const first = await compiler.build({ sources: { [entry]: original } });
    assert(first.success);
    for (const polynomial of [0x12345678, 0x80000001]) {
      const changed = await compiler.build({
        sources: { [entry]: recurrence("bits", 8, polynomial) },
      });
      assert(changed.success);
      await withGuest(
        changed.bytes,
        (guest) =>
          assert.equal(
            guest.call("bits_answer", 0xffffffff),
            repeated(0xffffffff, polynomial, 8),
          ),
      );
    }
    const rejected = await compiler.build({
      sources: {
        [entry]: original.replace("state := bits_mix self", "state := @hole"),
      },
    });
    assert.equal(rejected.success, false);
    const restored = await compiler.build({ sources: { [entry]: original } });
    assert(restored.success);
    assert.deepEqual(restored.bytes, first.bytes);
    await withGuest(
      restored.bytes,
      (guest) =>
        assert.equal(
          guest.call("bits_answer", 0xffffffff),
          repeated(0xffffffff, 0xEDB88320, 8),
        ),
    );
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
