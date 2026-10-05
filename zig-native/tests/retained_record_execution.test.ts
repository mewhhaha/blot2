import { strict as assert } from "node:assert";
import { createCompiler, instantiateGuest } from "../../mod.ts";
import { compileAndRun, equal } from "./compile_helpers.ts";

const declarations = `
type Pack [unused, selected] is data = #Pack { unused: unused, selected: selected }
const identity = fn value => value
const packed = #Pack { unused: identity, selected: fn (value: U32) => value + 1 }
const invoke = fn callback => callback 1
const sum = fn packed => fn (left: U32) => fn (right: U32) => do:
  let #Pack { selected } = packed
  return selected (left + right)
const run = fn packed => fn (value: U32) => do:
  let #Pack { selected } = packed
  return selected value
const capture = fn packed => fn (value: U32) => invoke (fn extra => do:
  let #Pack { selected } = packed
  return selected (value + extra))
`;

Deno.test("constant records retain unused generic fields across calls and mixed static/dynamic captures", async () => {
  await compileAndRun(
    declarations + `
entry const answer = fn (value: U32) => run packed value
entry const captured = fn (value: U32) => capture packed value
entry const partial = fn (value: U32) => invoke (run packed)
entry const partial_pair = fn (value: U32) => invoke (sum packed value)
entry const partial_chain = fn (value: U32) => do:
  let callback = sum packed
  return invoke (callback value)
entry const effectful = fn (host: U32 -> U32 ! {Foreign}) => capture packed (host 40)
`,
    (guest) => {
      for (let i = 0; i < 100; i++) {
        equal(guest.call("answer", 41), 42);
        equal(guest.call("captured", 40), 42);
        equal(guest.call("partial", 0), 2);
        equal(guest.call("partial_pair", 40), 42);
        equal(guest.call("partial_chain", 40), 42);
      }
      const calls: number[] = [];
      const host = guest.capability({
        parameter: "U32",
        result: "U32",
        call(value) {
          calls.push(value as number);
          return value;
        },
      });
      equal(guest.call("effectful", host), 42);
      assert.deepEqual(calls, [40]);
    },
  );
});

Deno.test("stored curried callbacks close their own effect rows and still use the caller's provider", async () => {
  await compileAndRun(
    `
type Clock is effect = { tick: Unit -> U32 }
type Pack callback is data = #Pack { callback: callback, marker: U32 }
const prepare = fn (amount: U32) => fn (value: U32) => do:
  use current <- Clock.tick ()
  return current + value + amount
const packed = #Pack { callback: prepare, marker: 42 }
const read = fn pack => do:
  let #Pack { marker } = pack
  return marker
const invoke = fn pack => do:
  let #Pack { callback } = pack
  return callback 1 2
entry const marker = fn () => read packed
entry const answer = fn (value: U32) => do:
  let clock = @effect.provider Clock.tick (fn () => value)
  return do clock:
    return invoke packed
`,
    (guest) => {
      equal(guest.call("marker", null), 42);
      equal(guest.call("answer", 39), 42);
      equal(guest.call("answer", 7), 10);
    },
  );
});

Deno.test("constant collections infer concrete callbacks in variants the consumer does not call", async () => {
  await compileAndRun(
    `
type Action value is data = #Ignored (value -> Unit) | #Chosen (Unit -> U32)
const unused = fn value => do:
  let next = value * 0.25
  return ()
const actions = #[#Ignored unused, #Chosen (fn () => 42)]
entry const answer = fn () => do:
  let total = 0
  for action in actions:
    total := total + (case action of
      #Ignored _ => 0
      #Chosen run => run ())
  return total
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
});

Deno.test("retained generic records invalidate constant values and inlined bodies after edits and recover after errors", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`, library = `${directory}/lib.blot`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
  const options = { entry, executable };
  const compiler = await createCompiler(options);
  const main = `import * as lib from "./lib"
entry const answer = fn (value: U32) => lib.capture lib.packed value
`;
  let original: Uint8Array | undefined;
  try {
    for (
      const [source, answer] of [
        [declarations, 42],
        [declarations.replace("value + 1", "value + 2"), 43],
        [declarations.replace("callback 1", "callback 3"), 44],
        [declarations.replace("value + 1", "missing"), null],
        [declarations, 42],
      ] as const
    ) {
      const sources = { [entry]: main, [library]: source };
      const result = await compiler.build({ sources });
      if (answer === null) {
        assert.equal(result.success, false);
        continue;
      }
      assert(result.success, JSON.stringify(result));
      const guest = await instantiateGuest(result.bytes);
      try {
        equal(guest.call("answer", 40), answer);
      } finally {
        guest.dispose();
      }
      if (source === declarations) {
        if (original) assert.deepEqual(result.bytes, original);
        else original = result.bytes;
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
