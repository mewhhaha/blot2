import { strict as assert } from "node:assert";
import type { HostCapability } from "../../compiler/guest.ts";
import { compileAndRun } from "./reduction_helpers.ts";
import { compileExpectedFailure } from "./compile_helpers.ts";

Deno.test("rolling reductions preserve complete windows and U32 wrapping", async () => {
  await compileAndRun(
    `
import * as rolling from "std/rolling"
import * as iter from "std/iter"
const add = fn (left: U32) => fn (right: U32) => @u32.add left right
const inverse = fn (value: U32) => @u32.sub 0 value
entry const sequential = fn (input: Array U32) => iter.collect_array (rolling.fold add 0 input[0] (@array.slice input 1 (@u32.sub (@array.length input) 1)))
entry const monoid = fn (input: Array U32) => iter.collect_array (rolling.monoid add 0 input[0] (@array.slice input 1 (@u32.sub (@array.length input) 1)))
entry const group = fn (input: Array U32) => iter.collect_array (rolling.group add inverse 0 input[0] (@array.slice input 1 (@u32.sub (@array.length input) 1)))
`,
    (guest) => {
      for (const count of [0, 1, 2, 3, 31, 63, 257, 4096]) {
        const values = Uint32Array.from(
          { length: count },
          (_, i) => (i * 4294967295) >>> 0,
        );
        for (
          const width of [
            1,
            2,
            3,
            31,
            257,
            Math.max(count, 1),
            count + 1,
            4294967295,
          ]
        ) {
          const expected: number[] = [];
          for (let start = 0; start + width <= count; start++) {
            let total = 0;
            for (let offset = 0; offset < width; offset++) {
              total = (total + values[start + offset]) >>> 0;
            }
            expected.push(total);
          }
          for (const name of ["sequential", "monoid", "group"]) {
            assert.deepEqual(
              guest.call(name, Uint32Array.of(width, ...values)),
              Uint32Array.from(expected),
              `${name}:${count}:${width}`,
            );
          }
        }
      }
      for (const name of ["sequential", "monoid", "group"]) {
        assert.throws(
          () => guest.call(name, Uint32Array.of(0, 1, 2)),
          WebAssembly.RuntimeError,
        );
        assert.deepEqual(
          guest.call(name, Uint32Array.of(2, 4294967295, 2, 3)),
          Uint32Array.of(1, 5),
        );
      }
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
});

Deno.test("rolling cursors preserve forks, reference summaries and noncommutative groups", async () => {
  await compileAndRun(
    `
import * as rolling from "std/rolling"
import * as iter from "std/iter"
const add = fn (left: U32) => fn (right: U32) => @u32.add left right
const image = fn (p: {a: U32, b: U32, c: U32}) => fn (index: U32) => case index of
  0 => p.a
  1 => p.b
  _ => p.c
const combine = fn (left: {a: U32, b: U32, c: U32}) => fn (right: {a: U32, b: U32, c: U32}) => {a: image left right.a, b: image left right.b, c: image left right.c}
const inverse = fn (p: {a: U32, b: U32, c: U32}) => do:
  let a = 0
  let b = 0
  let c = 0
  for index in 0..3:
    let value = image p index
    if @u32.eq value 0:
      a := index
    if @u32.eq value 1:
      b := index
    if @u32.eq value 2:
      c := index
  break {a, b, c}
const permutation = fn (index: U32) => case @u32.rem index 6 of
  0 => {a: 0, b: 1, c: 2}
  1 => {a: 1, b: 0, c: 2}
  2 => {a: 2, b: 1, c: 0}
  3 => {a: 0, b: 2, c: 1}
  4 => {a: 1, b: 2, c: 0}
  _ => {a: 2, b: 0, c: 1}
const code = fn value => @u32.add (@u32.add (@u32.mul value.a 9) (@u32.mul value.b 3)) value.c
entry const monoid = fn (width: U32) => #[code value | value <- rolling.monoid combine {a: 0, b: 1, c: 2} width (@array.generate 257 permutation)]
entry const group = fn (width: U32) => #[code value | value <- rolling.group combine inverse {a: 0, b: 1, c: 2} width (@array.generate 257 permutation)]
entry const forks = fn (width: U32) => do:
  let original = rolling.monoid add 0 width (@array.generate 32 (fn index => index))
  use first <- original.next
  let #Some (a, rest) = first else:
    break #[]
  let saved = rest
  use second <- rest.next
  let #Some (b, next) = second else:
    break #[]
  let pressure = @array.fill 8192 99
  use repeated <- saved.next
  let #Some (again, _) = repeated else:
    break #[]
  use third <- next.next
  let #Some (c, _) = third else:
    break #[]
  break #[a, b, again, c]
entry const references = fn (count: U32) => do:
  let values = @array.generate count (fn index => #[index])
  let windows = rolling.monoid (fn (left: Array U32) => fn (right: Array U32) => @array.concat left right) #[] 3 values
  break #[@u32.add (@u32.add window[0] window[1]) window[2] | window <- windows]
`,
    (guest) => {
      const permutations = [[0, 1, 2], [1, 0, 2], [2, 1, 0], [0, 2, 1], [
        1,
        2,
        0,
      ], [2, 0, 1]];
      for (const width of [1, 2, 3, 31, 63, 257, 258]) {
        const expected: number[] = [];
        for (let start = 0; start + width <= 257; start++) {
          let value = [0, 1, 2];
          for (let offset = 0; offset < width; offset++) {
            value = permutations[(start + offset) % 6].map((index) =>
              value[index]
            );
          }
          expected.push(9 * value[0] + 3 * value[1] + value[2]);
        }
        for (const name of ["monoid", "group"]) {
          assert.deepEqual(
            guest.call(name, width),
            Uint32Array.from(expected),
            `${name}:${width}`,
          );
        }
      }
      for (const width of [1, 2, 3, 7, 29]) {
        const first = width * (width - 1) / 2;
        assert.deepEqual(
          guest.call("forks", width),
          Uint32Array.of(
            first,
            first + width,
            first + width,
            first + 2 * width,
          ),
        );
      }
      for (const count of [0, 1, 2, 3, 63, 257]) {
        assert.deepEqual(
          guest.call("references", count),
          Uint32Array.from(
            { length: Math.max(0, count - 2) },
            (_, index) => 3 * index + 3,
          ),
        );
      }
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
});

Deno.test("rolling ordered F32 windows keep scalar rounding and signed zero", async () => {
  await compileAndRun(
    `
import * as rolling from "std/rolling"
import * as iter from "std/iter"
const add = fn (left: F32) => fn (right: F32) => @f32.add left right
entry const run = fn (input: Array F32) => iter.collect_array (rolling.fold add input[1] (@f32.to_u32 input[0]) (@array.slice input 2 (@u32.sub (@array.length input) 2)))
`,
    (guest) => {
      for (
        const values of [
          Float32Array.of(16777216, 1, -16777216, 3),
          Float32Array.of(-0, 0, -0),
          Float32Array.of(Infinity, -Infinity, NaN, 1),
          Float32Array.of(1e-45, -1e-45, 2e-45),
        ]
      ) {
        for (const width of [1, 2, 3, 4, 5]) {
          const expected: number[] = [];
          for (let start = 0; start + width <= values.length; start++) {
            let total = -0;
            for (let offset = 0; offset < width; offset++) {
              total = Math.fround(
                total + values[start + offset],
              );
            }
            expected.push(total);
          }
          assert.deepEqual(
            Array.from(
              guest.call(
                "run",
                Float32Array.of(width, -0, ...values),
              ) as Float32Array,
            ),
            expected,
          );
        }
      }
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
});

Deno.test("rolling input and reducer effects keep pull order and no prefetch", async () => {
  await compileAndRun(
    `
import * as rolling from "std/rolling"
import * as iter from "std/iter"
type Input is data = #Input {index: U32, count: U32, pull: U32 -> U32 ! {Foreign}}
const Input.iter = fn (cursor: Input) => do:
  use cursor.pull 777
  break cursor
const Input.next = fn (cursor: Input) => do:
  use value <- cursor.pull cursor.index
  if @u32.eq cursor.index cursor.count:
    break #Nothing
  break #Some (value, #Input {index: @u32.add cursor.index 1, count: cursor.count, pull: cursor.pull})
const add = fn (left: U32) => fn (right: U32) => @u32.add left right
const inverse = fn (value: U32) => @u32.sub 0 value
const sequential = fn (host: U32 -> U32 ! {Foreign}) => fn (width: U32) => fn (count: U32) => fn (limit: U32) => do:
  let values = #Input {index: 0, count, pull: host}
  let step = fn total => fn value => do:
    use observed <- host (@u32.add value 100)
    break @u32.add total (@u32.sub observed 100)
  break iter.collect_array (iter.take limit (rolling.fold step 0 width values))
const monoid = fn (host: U32 -> U32 ! {Foreign}) => fn (width: U32) => fn (count: U32) => fn (limit: U32) => iter.collect_array (iter.take limit (rolling.monoid add 0 width (#Input {index: 0, count, pull: host})))
const group = fn (host: U32 -> U32 ! {Foreign}) => fn (width: U32) => fn (count: U32) => fn (limit: U32) => iter.collect_array (iter.take limit (rolling.group add inverse 0 width (#Input {index: 0, count, pull: host})))
` + ["sequential", "monoid", "group"].flatMap((name) => [
        `entry const ${name}_none = fn (host: U32 -> U32 ! {Foreign}) => ${name} host 3 9 0`,
        `entry const ${name}_short = fn (host: U32 -> U32 ! {Foreign}) => ${name} host 3 2 9`,
        `entry const ${name}_two = fn (host: U32 -> U32 ! {Foreign}) => ${name} host 3 9 2`,
        `entry const ${name}_invalid = fn (host: U32 -> U32 ! {Foreign}) => ${name} host 0 9 0`,
      ]
      ).join("\n"),
    (guest) => {
      const seen: number[] = [];
      const host = guest.capability({
        parameter: "U32",
        result: "U32",
        call(value) {
          seen.push(value);
          return value;
        },
      });
      for (const name of ["sequential", "monoid", "group"]) {
        seen.length = 0;
        assert.deepEqual(
          guest.call(`${name}_none`, host),
          new Uint32Array(),
        );
        assert.deepEqual(seen, [777]);
        seen.length = 0;
        assert.deepEqual(
          guest.call(`${name}_short`, host),
          new Uint32Array(),
        );
        assert.deepEqual(seen, [777, 0, 1, 2]);
        seen.length = 0;
        assert.deepEqual(
          guest.call(`${name}_two`, host),
          Uint32Array.of(3, 6),
        );
        let expected = [777, 0, 1, 2, 3];
        if (name === "sequential") {
          expected = [
            777,
            0,
            1,
            2,
            100,
            101,
            102,
            3,
            101,
            102,
            103,
          ];
        }
        assert.deepEqual(seen, expected);
        seen.length = 0;
        assert.throws(
          () => guest.call(`${name}_invalid`, host),
          WebAssembly.RuntimeError,
        );
        assert.deepEqual(seen, []);
      }
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
});

const foreignSource = `
import * as rolling from "std/rolling"
import * as iter from "std/iter"
type Input is data = #Input {index: U32, pull: U32 -> U32 ! {Foreign}}
const Input.iter = fn (cursor: Input) => cursor
const Input.next = fn (cursor: Input) => do:
  use value <- cursor.pull cursor.index
  break #Some (#[value], #Input {index: @u32.add cursor.index 1, pull: cursor.pull})
const combine = fn (left: Array U32) => fn (right: Array U32) => @array.concat left right
entry const run = fn (host: U32 -> U32 ! {Foreign}) => do:
  let windows = rolling.monoid combine #[] 3 (#Input {index: 0, pull: host})
  break iter.collect_array (iter.map (fn window => @u32.add (@u32.add window[0] window[1]) window[2]) (iter.take 2 windows))
`;

for (const asynchronous of [false, true]) {
  Deno.test(`rolling reference windows survive ${asynchronous} host rejection and retry`, async () => {
    await compileAndRun(foreignSource, async (guest) => {
      const seen: number[] = [];
      let failure = true;
      const call = (value: number) => {
        seen.push(value);
        if (failure && value === 3) throw new Error("rolling pull rejected");
        return value;
      };
      let host: HostCapability;
      if (asynchronous) {
        host = guest.capabilityAsync({
          parameter: "U32",
          result: "U32",
          call: async (value) => {
            await Promise.resolve();
            return call(value);
          },
        });
        await assert.rejects(
          guest.callAsync("run", host),
          (error: unknown) =>
            (error as { code: string }).code === "host_exception",
        );
      } else {
        host = guest.capability({ parameter: "U32", result: "U32", call });
        assert.throws(
          () => guest.call("run", host),
          (error: unknown) =>
            (error as { code: string }).code === "host_exception",
        );
      }
      assert.deepEqual(seen, [0, 1, 2, 3]);
      failure = false;
      seen.length = 0;
      let result;
      if (asynchronous) result = await guest.callAsync("run", host);
      else result = guest.call("run", host);
      assert.deepEqual(result, Uint32Array.of(3, 6));
      assert.deepEqual(seen, [0, 1, 2, 3]);
    }, {
      stdRoot: new URL("../../std", import.meta.url).pathname,
      asynchronous,
    });
  });
}

Deno.test("rolling fast callbacks require closed pure arrows", async () => {
  for (
    const operation of [
      "rolling.monoid (fn left => fn right => host (@u32.add left right)) 0",
      "rolling.group (fn left => fn right => host (@u32.add left right)) (fn value => @u32.sub 0 value) 0",
      "rolling.group (fn left => fn right => @u32.add left right) (fn value => host value) 0",
    ]
  ) {
    await compileExpectedFailure(
      `
import * as rolling from "std/rolling"
import * as iter from "std/iter"
entry const run = fn (host: U32 -> U32 ! {Foreign}) => iter.collect_array (${operation} 3 (iter.range 0 9))
`,
      "effect_mismatch",
      undefined,
      { stdRoot: new URL("../../std", import.meta.url).pathname },
    );
  }
});

Deno.test("rolling request cancellation releases reference buffers and leaves bounded storage", async () => {
  const definitions = `
import * as rolling from "std/rolling"
import * as iter from "std/iter"
type Tick is effect = { read: U32 -> U32 }
type Input is data = #Input U32
const Input.iter = fn cursor => cursor
const Input.next = fn (#Input index) => do:
  use value <- Tick.read index
  break #Some (#[value], #Input (@u32.add index 1))
const combine = fn (left: Array U32) => fn (right: Array U32) => @array.concat left right
const cancel = fn computation => do:
  for request in @requests computation:
    case request of
      effect Tick.read value =>
        if @u32.eq value 4:
          break 7
        yield value
      complete value =>
        break value
  break 7
entry const run = fn (count: U32) => do:
  let total = 0
  for index in 0..count:
    let work = @computation (fn () => iter.fold_left (fn sum => fn value => @u32.add sum value[0]) 0 (rolling.monoid combine #[] 3 (#Input 0)))
    total := @u32.add self (cancel work)
  break total
entry const memory = fn () -> Array U32 => #[]
`;
  await compileAndRun(definitions, (_, bytes) => {
    const module = new WebAssembly.Module(bytes);
    assert.deepEqual([
      ...new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      ),
    ], [2, 2, 0]);
    const raw = new WebAssembly.Instance(module).exports;
    const run = raw.run as CallableFunction;
    const memory = raw["blot:memory"] as WebAssembly.Memory;
    const count = (name: string) =>
      Number((raw[`blot:${name}`] as WebAssembly.Global).value);
    assert.equal(run(64), 448);
    const warm = memory.buffer.byteLength;
    assert.equal(run(2048), 14336);
    assert.equal(memory.buffer.byteLength, warm);
    assert.equal(count("rc_roots"), 0);
    assert.equal(count("rc_leases"), 0);
    (raw["blot:ownership_leave"] as CallableFunction)(2);
  }, { stdRoot: new URL("../../std", import.meta.url).pathname });
});
