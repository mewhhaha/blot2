import { strict as assert } from "node:assert";
import { createCompiler, instantiateGuest } from "../../mod.ts";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

function sections(bytes: Uint8Array): Set<number> {
  const result = new Set<number>();
  let offset = 8;
  while (offset < bytes.length) {
    result.add(bytes[offset++]);
    let length = 0, shift = 0, next: number;
    do {
      next = bytes[offset++];
      length += (next & 127) * 2 ** shift;
      shift += 7;
    } while (next & 128);
    offset += length;
  }
  return result;
}

Deno.test("known demand combinators compile to control flow without heap or thunk helpers", async () => {
  for (
    const [declarations, expression, expected] of [
      ["", "(x < 100) && (x % 2 == 0)", (x: number) => x < 100 && x % 2 === 0],
      [
        "const alias = and",
        "alias (x < 100) (x % 2 == 0)",
        (x: number) => x < 100 && x % 2 === 0,
      ],
      ["", "(x < 100) || (x % 2 == 0)", (x: number) => x < 100 || x % 2 === 0],
      [
        "const choose = fn (a: Bool) => fn ~(b: Bool) => if a then @demand b else #False",
        "choose (x < 100) (x % 2 == 0)",
        (x: number) => x < 100 && x % 2 === 0,
      ],
      [
        "const twice = fn ~(value: U32) => @u32.add (@demand value) (@demand value)",
        "twice x",
        (x: number) => (x * 2) >>> 0,
      ],
    ] as const
  ) {
    await compileAndRun(
      `${declarations}\nentry const run = fn (x: U32) => ${expression}\n`,
      (guest, bytes) => {
        for (const x of [0, 1, 2, 3, 98, 99, 100, 101, 200, 0xFFFFFFFF]) {
          equal(guest.call("run", x), expected(x));
        }
        // Scalar-only examples need neither an arena nor a table of thunks.
        const emitted = sections(bytes);
        assert.equal(emitted.has(4), false, "Unexpected function table");
        assert.equal(emitted.has(5), false, "Unexpected linear memory");
      },
    );
  }
});

Deno.test("local demand sharing preserves effect order, branches, lexical versions and repeated calls", async () => {
  await compileAndRun(
    `
const twice = fn ~(value: U32) => @u32.add (@demand value) (@demand value)
const conditional = fn (condition: Bool) => fn ~(value: U32) =>
  @u32.add (if condition then @demand value else 0) (@demand value)
const choose = fn (first: U32) => fn ~(second: U32) => fn (last: U32) =>
  @u32.add (@u32.add first last) (@demand second)
const ignore = fn ~(value: U32) => 42
entry const skipped = fn (x: U32) => ignore (1 / x)
entry const guarded = fn (x: U32) => (x != 0) && (100 / x == 10)
entry const order = fn (host: U32 -> U32 ! {Foreign}) => choose (host 1) (host 2) (host 3)
entry const mixed = fn (host: U32 -> U32 ! {Foreign}) => do:
  use first <- conditional #False (host 20)
  use second <- conditional #True (host 1)
  return first + second
entry const repeated = fn (host: U32 -> U32 ! {Foreign}) => do:
  let total = 0
  for i in 0..20:
    use value <- twice (host i)
    total := total + value
  return total
entry const captured = fn (x: U32) => do:
  let before = x
  let value = twice before
  before := 99
  return value
`,
    (guest) => {
      equal(guest.call("skipped", 0), 42);
      equal(guest.call("guarded", 0), false);
      equal(guest.call("guarded", 10), true);
      equal(guest.call("captured", 21), 42);
      const calls: number[] = [];
      const host = guest.capability({
        parameter: "U32",
        result: "U32",
        call(value) {
          calls.push(value as number);
          return value;
        },
      });
      equal(guest.call("order", host), 6);
      assert.deepEqual(calls, [1, 3, 2]);
      calls.length = 0;
      equal(guest.call("mixed", host), 22);
      assert.deepEqual(calls, [20, 1]);
      calls.length = 0;
      equal(guest.call("repeated", host), 380);
      assert.deepEqual(calls, Array.from({ length: 20 }, (_, i) => i));
    },
  );
});

Deno.test("demand spelling retains force compatibility and demand-only typing", async () => {
  await compileAndRun(
    `
const twice = fn ~(value: U32) => @u32.add (@force value) (@demand value)
entry const constant = twice 21
entry const run = fn (x: U32) => twice x
`,
    (guest) => {
      equal(guest.read("constant"), 42);
      equal(guest.call("run", 21), 42);
    },
  );
  await compileExpectedFailure(
    "entry const wrong = @demand 42\n",
    "type_mismatch",
  );
  await compileExpectedFailure(
    "const demand = @demand\nentry const answer = 42\n",
    "call_arity",
  );
  await compileExpectedFailure(
    "const ignore = fn ~(value: U32) => 42\nentry const wrong = ignore #True\n",
    "type_mismatch",
  );
});

Deno.test("retained code tracks inlined demand bodies through edits, reuse, failures and recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`, library = `${directory}/lib.blot`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
  const options = { entry, executable };
  const compiler = await createCompiler(options);
  const declaration =
    "const choose = fn (a: Bool) => fn ~(b: Bool) => if a then @demand b else #False\nconst wrapped = fn (x: U32) => choose (x < 100) (x % 2 == 0)\n";
  const main =
    'import * as lib from "./lib"\nentry const run = fn (x: U32) => lib.wrapped (x + OFFSET)\n';
  try {
    for (
      const [source, offset, answer] of [
        [declaration, 0, false],
        [declaration, 1, true],
        [declaration, 2, false],
        [
          declaration.replace("@demand b else #False", "#True else @demand b"),
          0,
          true,
        ],
        [declaration.replace("@demand b", "missing"), 0, null],
        [declaration, 0, false],
      ] as const
    ) {
      const sources = {
        [entry]: main.replace("OFFSET", String(offset)),
        [library]: source,
      };
      const result = await compiler.build({ sources });
      if (answer === null) {
        assert.equal(result.success, false);
        continue;
      }
      assert(result.success, JSON.stringify(result));
      const guest = await instantiateGuest(result.bytes);
      try {
        equal(guest.call("run", 3), answer);
      } finally {
        guest.dispose();
      }
      const fresh = await createCompiler(options);
      try {
        const rebuilt = await fresh.build({ sources });
        assert(rebuilt.success, JSON.stringify(rebuilt));
        assert.deepEqual(result.bytes, rebuilt.bytes);
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
