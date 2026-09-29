import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { loadSourceProject } from "./source_project.ts";
import { SourceError } from "./syntax.ts";

async function compiled(source: string) {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(source);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    return instance.exports;
  } finally {
    compiler.dispose();
  }
}

function call(exports: WebAssembly.Exports, name: string, ...args: number[]) {
  const fn = exports[name];
  ok(typeof fn === "function", name);
  return fn(...args) as number;
}

Deno.test("integer operators agree at compile time and runtime, including masked shifts", async () => {
  const exports = await compiled(`
const calculate = fn value => ((value / 3) ^ (value % 3) | 7) & 0xFFFFFFFF
entry const expected = calculate 0xFFFFFFFF
entry const calculate_runtime = calculate
entry const shifted = fn value => (value >> 32) + (1 << 33)
entry const divide = fn value => 1 / value
entry const complement = fn (value: U32) => bit_not value
`);
  equal(
    call(exports, "calculate_runtime", 0xffffffff),
    (exports.expected as WebAssembly.Global).value,
  );
  equal(call(exports, "shifted", 40), 42);
  equal(call(exports, "complement", 0) >>> 0, 0xffffffff);
  throws(() => call(exports, "divide", 0), WebAssembly.RuntimeError);
  const compiler = await createSourceCompiler();
  try {
    throws(() => compiler.compile("entry const invalid = 1 % 0\n"), (error) => {
      ok(error instanceof SourceError);
      equal(error.code, "integer_divide_by_zero");
      return true;
    });
  } finally {
    compiler.dispose();
  }
});

Deno.test("selectors, type witnesses, result-directed source functions and value conditionals compose", async () => {
  const exports = await compiled(`
type Point is data = #Point { x: U32, y: U32 }
type Distance is data = #Distance U32
const Distance.from = fn value => #Distance (value + 1)
const converted = from
const increment = .add
entry const selector = fn value => #Point { x: value, y: 0 } |> .x |> increment 1
entry const normalized = fn (value: U32) => from value / 6555.0
entry const same_float = fn (value: F32) => F32.from value
entry const custom = fn value => do:
  let distance: Distance = converted value
  return case distance of
    #Distance result => result
entry const types = if :1 == :2.0 then 0 else 42
entry const same_type = if :(1 + 1) == :2 then 42 else 0
`);
  equal(call(exports, "selector", 41), 42);
  equal(call(exports, "normalized", 6555), 1);
  equal(call(exports, "same_float", 2.5), 2.5);
  equal(call(exports, "custom", 41), 42);
  equal((exports.types as WebAssembly.Global).value, 42);
  equal((exports.same_type as WebAssembly.Global).value, 42);
});

Deno.test("conditional successors flow outward, preserve captures, and respect local shadowing", async () => {
  const exports = await compiled(`
entry const update = fn enabled => do:
  let total = 1
  let old = fn () => total
  if enabled:
    total := self + 40
  else:
    total := self + 10
  return total + old ()
entry const loop = fn () => do:
  let total = 0
  for index in 0..6:
    if index % 2 == 0:
      total := self + index
  if let #Some amount = #Some 36:
    total := self + amount
  return total
entry const shadow = fn () => do:
  let value = 42
  if #True:
    let value = 0
    value := 1
  return value
`);
  equal(call(exports, "update", 1), 42);
  equal(call(exports, "update", 0), 12);
  equal(call(exports, "loop"), 42);
  equal(call(exports, "shadow"), 42);
});

Deno.test("alternative patterns share bindings and guards fall through in source order", async () => {
  const exports = await compiled(`
type Choice is data =
  | #First U32
  | #Second U32
  | #Empty
const inspect = fn value => case value of
  #First amount | #Second amount if amount > 40 => amount
  #First amount | #Second amount => amount + 2
  #Empty => 0
entry const answer = fn value => inspect (#Second value)
entry const early = fn value => do:
  let result = case #First value of
    #First amount | #Second amount if amount > 40 => do:
      return amount
    _ => 0
  return result
`);
  equal(call(exports, "answer", 40), 42);
  equal(call(exports, "answer", 42), 42);
  equal(call(exports, "early", 42), 42);
  const compiler = await createSourceCompiler();
  try {
    for (
      const source of [
        "entry const bad = fn value => case value of\n  #Some x | #Nothing => x\n",
        "entry const bad = fn value => case value of\n  #True if value => 1\n  #False => 0\n",
      ]
    ) throws(() => compiler.compile(source), SourceError);
  } finally {
    compiler.dispose();
  }
});

Deno.test("collection helpers preserve order, empty arrays and tuple columns", async () => {
  const library = await Deno.readTextFile(
    new URL("../std/array.blot", import.meta.url),
  );
  const project = await loadSourceProject(
    new URL("readability.blot", import.meta.url),
    {
      readSource: (url) =>
        Promise.resolve(
          url.pathname.endsWith("array.blot") ? library : `
import * as array from "./array"
const numbers = [1, 2, 3, 4, 5]
const even = fn value => value % 2 == 0
const choose = fn value => if even value then #Some (value * 10) else #Nothing
entry const answer = fn () => do:
  let selected = array.filter even numbers
  let mapped = array.filter_map choose numbers
  let flat = array.flatten [[], selected, [], [6]]
  let (left, right) = array.unzip (array.zip flat mapped)
  return left[0] + right[1]
entry const empties = array.length (array.flatten [[], []])
entry const last = array.fold_left add 0 (array.push 6 (array.slice 1 2 numbers))
`,
        ),
    },
  );
  const compiler = await createSourceCompiler();
  try {
    const { bytes } = compiler.compile(project);
    const { instance } = await WebAssembly.instantiate(bytes);
    equal(call(instance.exports, "answer"), 42);
    equal((instance.exports.empties as WebAssembly.Global).value, 0);
    equal((instance.exports.last as WebAssembly.Global).value, 11);
  } finally {
    compiler.dispose();
  }
});

Deno.test("vector members and generic math compose with conversions and selectors", async () => {
  const library = await Deno.readTextFile(
    new URL("../std/vector.blot", import.meta.url),
  );
  const source = `
import { Vec2, Vec3 } from "./vector"
entry const length = fn () => (#Vec2 { x: 3.0, y: 4.0 }).length
entry const normal = fn () => (#Vec3 { x: 0.0, y: 0.0, z: 4.0 }).normalized.z
entry const zero = fn () => (#Vec3 { x: 0.0, y: 0.0, z: 0.0 }).normalized.length
entry const dot = fn () => (#Vec3 { x: 2.0, y: 3.0, z: 4.0 } * 2.0).dot (#Vec3 { x: 1.0, y: 2.0, z: 3.0 })
entry const cross = fn () => ((#Vec3 { x: 1.0, y: 0.0, z: 0.0 }).cross (#Vec3 { x: 0.0, y: 1.0, z: 0.0 })).z
entry const math = fn () => do:
  let (sine, cosine) = sin_cos 0.0
  let amount = smoothstep 0.0 1.0 0.5
  return sine + cosine + amount + saturate 2.0
entry const integer_math = clamp 0 10 (square 12)
`;
  const project = await loadSourceProject(
    new URL("vectors.blot", import.meta.url),
    {
      readSource: (url) =>
        Promise.resolve(
          url.pathname.endsWith("vector.blot") ? library : source,
        ),
    },
  );
  const compiler = await createSourceCompiler();
  try {
    const { instance } = await WebAssembly.instantiate(
      compiler.compile(project).bytes,
    );
    equal(call(instance.exports, "length"), 5);
    equal(call(instance.exports, "normal"), 1);
    equal(call(instance.exports, "zero"), 0);
    equal(call(instance.exports, "dot"), 40);
    equal(call(instance.exports, "cross"), 1);
    equal(call(instance.exports, "math"), 2.5);
    equal((instance.exports.integer_math as WebAssembly.Global).value, 10);
  } finally {
    compiler.dispose();
  }
});

Deno.test("pattern guards evaluate scrutinees once and preserve effect order", async () => {
  const exports = await compiled(`
effect Count.read: Unit -> U32
effect Count.write: U32 -> Unit
const step = fn () => do:
  use count <- Count.read ()
  use Count.write (count + 1)
  return #Some count
const probe = fn () => do:
  let (count, result) = do (@effect.state Count.read Count.write 1):
    return case step () of
      #Some value if value > 1 => 0
      #Some value if value == 1 => value + 40
      _ => 0
  return count + result
entry const expected = probe ()
entry const run = fn () => probe ()
`);
  equal(call(exports, "run"), 43);
  equal((exports.expected as WebAssembly.Global).value, 43);
});
