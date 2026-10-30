import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
import { loopCases } from "./loop_cases.ts";
import { strict as assert } from "node:assert";

// These source cases and outputs are also run against the unchanged compiler
// in build/zig-native-core-eval/loop_oracle.ts. No hand-constructed IR bypasses
// the native parser, checker, retained bodies, evaluator or Wasm emitter.
for (const item of loopCases) {
  if (!("expected" in item)) continue;
  Deno.test(`native loops preserve ${item.name}`, async () => {
    await compileAndRun(item.source, (guest) => {
      for (const [name, expected] of Object.entries(item.expected)) {
        const argument = "arguments" in item
          ? (item.arguments as Record<string, number>)[name]
          : undefined;
        equal(
          guest.abi.constants.some((value) => value.name === name)
            ? guest.read(name)
            : guest.call(name, argument ?? null),
          expected,
        );
      }
    });
  });
}

Deno.test("native loops reject invalid bounds, refutable iterators and escaped control scopes", async () => {
  for (const item of loopCases) {
    if (!("error" in item)) continue;
    const nativeCode = item.error;
    await compileExpectedFailure(item.source, nativeCode);
  }
});

Deno.test("native range iteration uses constant stack on large runtime bounds", async () => {
  await compileAndRun(
    `
entry const run = func (limit: U32) : U32 => return do:
  let total = 0
  for index in 0..limit:
    total := @u32.add self index
  break total
`,
    (guest) => {
      equal(guest.call("run", 0), 0);
      equal(guest.call("run", 100000), 704982704);
      equal(guest.call("run", 100001), 705082704);
    },
  );
});

Deno.test("continue works in a loop local to a request callback", async () => {
  await compileAndRun(`
type Tick is effect = { read: Unit -> U32 }
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      effect Tick.read () =>
        let total = 0
        for index in 0..4:
          if @u32.eq index 2:
            continue
          total := @u32.add self index
        yield total
      complete value =>
        break value
entry const answer = func () => return handled (@computation (func () => return Tick.read ()))
`, guest => equal(guest.call("answer", null), 4));
});

Deno.test("continue cannot cross a request callback boundary", async () => {
  const source = `
type Tick is effect = { read: Unit -> U32 }
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      effect Tick.read () =>
        continue
      complete value =>
        break value
entry const answer = func () => return handled (@computation (func () => return Tick.read ()))
`;
  await compileExpectedFailure(source, "invalid_return");
});

Deno.test("continue and a guarded body perform the same effects", async () => {
  await compileAndRun(`
entry const skipped = func (record: U32 -> U32 ! {Foreign}) => return do:
  let total = 0
  for index in 0..5:
    if @u32.eq index 2:
      continue
    use record index
    total := @u32.add self index
  break total
entry const guarded = func (record: U32 -> U32 ! {Foreign}) => return do:
  let total = 0
  for index in 0..5:
    if @u32.eq index 2:
      use ()
    else:
      use record index
      total := @u32.add self index
  break total
`, guest => {
    const skipped: number[] = [];
    const guarded: number[] = [];
    const first = guest.capability({ parameter: "U32", result: "U32", call: (value: number) => { skipped.push(value); return value; } });
    const second = guest.capability({ parameter: "U32", result: "U32", call: (value: number) => { guarded.push(value); return value; } });
    equal(guest.call("skipped", first), 8);
    equal(guest.call("guarded", second), 8);
    equal(skipped.join(","), "0,1,3,4");
    equal(guarded.join(","), skipped.join(","));
  });
});

Deno.test("continue retires skipped iteration arrays and restores ownership roots", async () => {
  await compileAndRun(`
entry const run = func (count: U32) => return do:
  let checksum = 0
  for index in 0..count:
    let discarded = @array.fill 8192 index
    checksum := @u32.add self discarded[8191]
    continue
  break checksum
`, (_, bytes) => {
    const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
    const enter = raw["blot:ownership_enter"] as CallableFunction;
    const leave = raw["blot:ownership_leave"] as CallableFunction;
    const count = (name: string) => Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
    for (const iterations of [8, 40, 8]) {
      enter();
      const destroyed = count("destroyed");
      assert.equal((raw.run as CallableFunction)(iterations), iterations * (iterations - 1) / 2);
      assert(count("destroyed") - destroyed >= iterations);
      leave(0);
      assert.equal(count("roots"), 0);
      assert.equal(count("leases"), 0);
    }
  });
});

Deno.test("continue advances packed array and list rows across leaf boundaries", async () => {
  await compileAndRun(`
entry const run = func (count: U32) => return do:
  let rows = @array.generate count (func index => return {value: index, extra: @u32.add index 1})
  let listed = @list.from_array rows
  let total = 0
  for row in rows:
    if @u32.eq (@u32.rem row.value 2) 0:
      continue
    total := @u32.add self row.value
  for row in listed:
    if @u32.eq (@u32.rem row.value 2) 0:
      continue
    total := @u32.add self row.value
  break total
`, guest => {
    for (const count of [0, 1, 2, 83, 244, 245, 1000, 1025]) {
      assert.equal(guest.call("run", count), 2 * Math.floor(count / 2) ** 2);
    }
  });
});
