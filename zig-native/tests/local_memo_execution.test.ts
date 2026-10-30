import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun, equal } from "./compile_helpers.ts";

const sum = `
const sum = func (count: U32) => return func ~(value: U32) => return do:
  let first = value
  let second = first
  let total = 0
  for i in 0..count:
    use current <- @demand second
    total := @u32.add self current
  break total
`;

Deno.test("local memo callee loops need no arena or thunk table", async () => {
  await compileAndRun(
    `${sum}
entry const run = func (count: U32) => return sum count 21
entry const zero = func (divisor: U32) => return sum 0 (@u32.div 1 divisor)
const ignore = func ~(value: U32) => return do:
  let alias = value
  break 42
entry const skipped = func (divisor: U32) => return ignore (@u32.div 1 divisor)
`,
    (guest, bytes) => {
      for (const count of [0, 1, 2, 1000]) {
        equal(guest.call("run", count), count * 21);
      }
      equal(guest.call("zero", 0), 0);
      equal(guest.call("skipped", 0), 42);
      const module = new WebAssembly.Module(bytes);
      assert.deepEqual(WebAssembly.Module.imports(module), []);
      assert.equal(
        WebAssembly.Module.exports(module).some((item) =>
          item.kind === "memory" || item.kind === "table"
        ),
        false,
      );
      // The ABI exports neither private arena nor thunk table. Assert the
      // corresponding sections are absent as well.
      let offset = 8;
      while (offset < bytes.length) {
        const section = bytes[offset++];
        assert.notEqual(section, 4);
        assert.notEqual(section, 5);
        let length = 0, shift = 0, next: number;
        do {
          next = bytes[offset++];
          length += (next & 127) * 2 ** shift;
          shift += 7;
        } while (next & 128);
        offset += length;
      }
    },
    { prelude: "none" },
  );
});

for (const asynchronous of [false, true]) {
  let mode = "sync";
  if (asynchronous) mode = "JSPI";
  Deno.test(`local memo nested creation scopes and aliases preserve effects (${mode})`, async () => {
    await compileAndRun(
      `${sum}
const selected = func (count: U32) => return func ~(value: U32) => return do:
  let alias = value
  let total = 0
  for i in 0..count:
    if @u32.eq i 0:
      total := 0
    else:
      use current <- @demand alias
      total := @u32.add self current
  break total
const early = func (count: U32) => return func ~(value: U32) => return do:
  let total = 0
  for i in 0..count:
    if @u32.eq i 2:
      break
    use current <- @demand value
    total := @u32.add self current
  break total
const exclusive = func (left: Bool) => return func ~(value: U32) => return do:
  if left:
    break @demand value
  else:
    break @demand value
entry const outside = func (host: U32 -> U32 ! {Foreign}) => return sum 8 (host 21)
entry const once = func (host: U32 -> U32 ! {Foreign}) => return exclusive false (host 7)
entry const inside = func (host: U32 -> U32 ! {Foreign}) => return do:
  let total = 0
  for i in 0..4:
    for j in 0..3:
      use current <- sum j (host (@u32.add (@u32.mul i 10) j))
      total := @u32.add self current
  break total
entry const conditional = func (host: U32 -> U32 ! {Foreign}) => return do:
  use skipped <- selected 1 (host 99)
  use read <- selected 4 (host 7)
  break @u32.add skipped read
entry const stopped = func (host: U32 -> U32 ! {Foreign}) => return early 100 (host 9)
entry const captured = func (host: U32 -> U32 ! {Foreign}) => return do:
  let before = 21
  use answer <- sum 2 (host before)
  before := 99
  break answer
entry const folded = sum 8 21
`,
      async (guest) => {
        const trace: number[] = [];
        let host;
        if (asynchronous) {
          host = guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            call: async (value) => {
              await Promise.resolve();
              trace.push(value);
              return value;
            },
          });
        } else {
          host = guest.capability({
            parameter: "U32",
            result: "U32",
            call: (value) => {
              trace.push(value);
              return value;
            },
          });
        }
        for (
          const [name, expected, events] of [
            ["outside", 168, [21]],
            ["once", 7, [7]],
            ["inside", 200, [1, 2, 11, 12, 21, 22, 31, 32]],
            ["conditional", 21, [7]],
            ["stopped", 18, [9]],
            ["captured", 42, [21]],
          ] as const
        ) {
          for (let invocation = 0; invocation < 3; invocation++) {
            trace.length = 0;
            let answer;
            if (asynchronous) answer = await guest.callAsync(name, host);
            else answer = guest.call(name, host);
            equal(answer, expected);
            assert.deepEqual(trace, events);
          }
        }
        equal(guest.read("folded"), 168);
      },
      { prelude: "none", asynchronous },
    );
  });

  Deno.test(`local memo List force-site cancellation and provider fallback (${mode})`, async () => {
    for (const exit of ["return 7", "break"]) {
      await compileAndRun(
        `
type Tick is effect = { read: U32 -> U32 }
const rows = @list.generate 257 (func i => return {a: i, b: i})
const walk = func (rows: List {a: U32, b: U32}) => return func ~(value: U32) => return do:
  let total = 0
  for row in rows:
    use current <- @demand value
    total := @u32.add self (@u32.add row.a current)
  break total
const work = @computation (func () => return walk rows (Tick.read 1))
const abort = func (log: U32 -> U32 ! {Foreign}) => return do:
  for request in @requests work:
    case request of
      effect Tick.read value =>
        use log value
        ${exit}
      complete value =>
        break value
  break 7
entry const aborted = func (log: U32 -> U32 ! {Foreign}) => return do:
  for i in 0..2048:
    use ignored <- abort log
  break 7
entry const resumed = func (log: U32 -> U32 ! {Foreign}) => return do:
  for request in @requests work:
    case request of
      effect Tick.read value =>
        use next <- log value
        yield next
      complete value =>
        break value
  break 0
const scoped = func ~(value: U32) => return do (@effect.provider Tick.read (func value => return 7)):
  break @u32.add (@demand value) (@demand value)
entry const provided = func (ignored: U32) => return scoped (Tick.read ignored)
`,
        async (guest) => {
          const trace: number[] = [];
          let host;
          if (asynchronous) {
            host = guest.capabilityAsync({
              parameter: "U32",
              result: "U32",
              call: async (value) => {
                await Promise.resolve();
                trace.push(value);
                return value;
              },
            });
          } else {
            host = guest.capability({
              parameter: "U32",
              result: "U32",
              call: (value) => {
                trace.push(value);
                return value;
              },
            });
          }
          const run = async (name: string) => {
            if (asynchronous) return await guest.callAsync(name, host);
            return guest.call(name, host);
          };
          equal(await run("resumed"), 33153);
          const warmed = guest.memoryBytes();
          for (let iteration = 0; iteration < 4; iteration++) {
            equal(await run("aborted"), 7);
            equal(await run("resumed"), 33153);
          }
          assert.deepEqual(trace, Array.from({ length: 8197 }, () => 1));
          assert(guest.memoryBytes() <= warmed + 65536);
          if (asynchronous) equal(await guest.callAsync("provided", 99), 14);
          else equal(guest.call("provided", 99), 14);
        },
        { prelude: "none", asynchronous },
      );
    }
  });
}

Deno.test("local memo managed results remain roots during forever-loop collection", async () => {
  await compileAndRun(
    `
const run = func (count: U32) => return func ~(value: Array U32) => return do:
  let total = 0
  let i = 0
  for ever:
    let pressure = @array.fill 1024 i
    let cached = @demand value
    total := @u32.add self (@array.get pressure 0)
    i := @u32.add self 1
    if @u32.eq i count:
      break cached
const forward = func (count: U32) => return func ~(value: Array U32) => return run count (@demand value)
entry const answer = func (count: U32) => return forward count #[21, 22, 23]
`,
    (guest) => {
      for (const count of [1, 100, 1000, 3000]) {
        assert.deepEqual(
          guest.call("answer", count),
          new Uint32Array([21, 22, 23]),
        );
      }
    },
    { prelude: "none" },
  );
});

Deno.test("local memo loop traps publish no result and later creations remain independent", async () => {
  await compileAndRun(
    `${sum}
const floating = func (count: U32) => return func ~(value: F32) => return do:
  let total = 0.0
  for i in 0..count:
    total := @f32.add self (@demand value)
  break total
entry const divide = func (count: U32) => return sum count (@u32.div 100 0)
entry const failed = func (host: U32 -> U32 ! {Foreign}) => return sum 4 (host 21)
entry const floats = func (count: U32) => return floating count 1.5
const drop = func (divisor: U32) => return func ~(_: U32) => return do:
  use @u32.div 100 divisor
  break 42
entry const discarded = func (divisor: U32) => return drop divisor (@u32.div 1 0)
`,
    (guest) => {
      equal(guest.call("divide", 0), 0);
      equal(guest.call("discarded", 1), 42);
      assert.throws(() => guest.call("discarded", 0));
      assert.throws(() => guest.call("divide", 1));
      equal(guest.call("divide", 0), 0);
      let calls = 0;
      const fault = guest.capability({
        parameter: "U32",
        result: "U32",
        call: () => {
          calls++;
          throw new Error("first demand failed");
        },
      });
      const good = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value) => {
          calls++;
          return value;
        },
      });
      assert.throws(() => guest.call("failed", fault));
      equal(guest.call("failed", good), 84);
      equal(calls, 2);
      for (const count of [0, 1, 2, 1000]) {
        equal(
          guest.call("floats", count),
          count * 1.5,
        );
      }
    },
    { prelude: "none" },
  );
});

Deno.test("local memo retained callee edits preserve stable types and failure recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`, library = `${directory}/library.blot`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  const options = {
    entry,
    executable,
    prelude: null,
    cacheDirectory: false as const,
  };
  try {
    await Deno.writeTextFile(
      entry,
      'import { sum } from "./library"\nentry const run = func (count: U32) => return sum count 21\n',
    );
    await Deno.writeTextFile(library, sum);
    const retained = await createZigProjectCompiler(options);
    try {
      for (const doubled of [false, true, true, false]) {
        let body = sum;
        let factor = 21;
        if (doubled) {
          body = sum.replace(
            "@u32.add self current",
            "@u32.add self (@u32.add current (@demand first))",
          );
          factor = 42;
        }
        const sources = { [library]: body };
        const current = await retained.build({ sources });
        assert(current.success, JSON.stringify(current));
        const fresh = await createZigProjectCompiler(options);
        try {
          const rebuilt = await fresh.build({ sources });
          assert(rebuilt.success, JSON.stringify(rebuilt));
          assert.deepEqual(current.bytes, rebuilt.bytes);
          const guest = await instantiateGuest(current.bytes);
          try {
            for (const count of [0, 1, 7]) {
              equal(guest.call("run", count), count * factor);
            }
          } finally {
            guest.dispose();
          }
        } finally {
          await fresh.dispose();
        }
        const failed = await retained.build({
          sources: { [library]: body.replace("@demand second", "@demand 42") },
        });
        assert.equal(failed.success, false);
      }
    } finally {
      await retained.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("counted local Array memos survive callee iteration retirement and recycled allocation pressure", async () => {
  await compileAndRun(
    `
const run = func (count: U32) => return func ~(value: Array U32) => return do:
  let total = 0
  let index = 0
  for ever:
    let cached = @demand value
    let pressure = @array.fill 1024 index
    let churn = @array.fill (@u32.add (@u32.rem index 2) 2) index
    total := @u32.add self (@u32.add pressure[0] churn[0])
    index := @u32.add self 1
    if @u32.eq index count:
      if @u32.eq total (@u32.mul count (@u32.sub count 1)):
        break cached
      break @panic "the pressure loop lost its values"
const forward = func (count: U32) => return func ~(value: Array U32) => return run count (@demand value)
entry const answer = func (count: U32) => return forward count #[21, 22, 23]
`,
    (guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      const raw = new WebAssembly.Instance(module).exports;
      const count = (name: string) =>
        Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
      const memory = raw["blot:memory"] as WebAssembly.Memory;
      for (const iterations of [1, 5000, 5000]) {
        const before = count("destroyed");
        const value = (raw.answer as CallableFunction)(iterations);
        assert.deepEqual([...new Uint32Array(memory.buffer, value + 4, 3)], [
          21,
          22,
          23,
        ]);
        (raw["blot:reset"] as CallableFunction)();
        assert.equal(count("roots"), 0);
        assert.equal(count("leases"), 0);
        assert(
          count("destroyed") - before >= iterations * 2,
          "iteration graphs must retire rather than stay tracer-only",
        );
      }
      for (const iterations of [1, 5000, 5000]) {
        assert.deepEqual(
          guest.call("answer", iterations),
          Uint32Array.of(21, 22, 23),
        );
      }
    },
    { prelude: "none" },
  );
});
