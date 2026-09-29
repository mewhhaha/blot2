import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { createIncrementalCompiler } from "./incremental.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { SourceError } from "./syntax.ts";
import { instantiateGuest } from "./guest.ts";
import { loadSourceProject } from "./source_project.ts";

const programs = [
  {
    name: "numeric operators specialize generic wrappers in const and Wasm",
    source: `
const twice = fn value => value + value
entry const integer = twice 21
entry const floating = twice 1.25
entry const integer_run = fn (value: U32) => twice value
entry const run = fn (value: F32) => (twice value * 3.0 - 2.0) / 2.0
entry const compare = fn (value: F32) => value >= 4.0
`,
    expected: 11,
  },
  {
    name: "associated implementations can themselves use generic operators",
    source: `
data Box = #Box F32
const Box.add = fn (left: Box) => fn (right: Box) => case (left, right) of
  (#Box a, #Box b) => #Box (a + b)
entry const run = fn (value: F32) => case #Box value + #Box 3.0 of
  #Box answer => answer
`,
    expected: 7,
  },
  {
    name:
      "right-side fallback checks both parameter types and preserves argument order",
    source: `
data Box = #Box F32
const Box.add = fn (left: F32) => fn (right: Box) => case right of
  #Box value => left - value
entry const run = fn (value: F32) => value + #Box 3.0
`,
    expected: 1,
  },
  {
    name: "left-side implementation wins when both sides accept the operands",
    source: `
data Left = #Left F32
data Right = #Right F32
const Left.add = fn (left: Left) => fn (right: Right) => 10.0
const Right.add = fn (left: Left) => fn (right: Right) => 20.0
entry const run = fn (value: F32) => #Left value + #Right value
`,
    expected: 10,
  },
  {
    name: "compile-time dispatch supports arbitrary member names",
    source: `
data Box = #Box F32
const Box.distance = fn (left: Box) => fn (right: Box) => case (left, right) of
  (#Box a, #Box b) => F32.abs (a - b)
const distance = fn left => fn right => @type.call "distance" left right
entry const run = fn (value: F32) => distance (#Box value) (#Box 9.0)
`,
    expected: 5,
  },
  {
    name:
      "specialization preserves recursion and higher-order partial applications",
    source: `
entry const sum = fn count => case count of
  0 => 0
  _ => count + sum (count - 1)
const twice = fn transform => fn value => transform (transform value)
entry const run = fn (value: F32) => twice (add value) (U32.to_f32 (sum 4))
`,
    expected: 18,
  },
  {
    name: "local function aliases and lambdas instantiate independently",
    source: `
entry const run = fn (value: F32) => do:
  let combine = add
  let twice = fn x => combine x x
  let integer = twice 3
  let floating = twice value
  return U32.to_f32 integer + floating
`,
    expected: 14,
  },
  {
    name: "constant function aliases preserve independent specializations",
    source: `
const combine = add
const twice = fn value => combine value value
entry const run = fn (value: F32) => U32.to_f32 (twice 3) + twice value
`,
    expected: 14,
  },
  {
    name:
      "associated results retain their operand constraints through local temporaries",
    source: `
entry const run = fn (value: F32) => do:
  let square = value * value
  let scaled = square * 2.0
  return scaled - square
`,
    expected: 16,
  },
  {
    name: "generic nominal implementations specialize their payload arithmetic",
    source: `
data Box value = #Box value
const Box.add = fn left => fn right => case (left, right) of
  (#Box a, #Box b) => #Box (a + b)
entry const run = fn (value: F32) => case #Box value + #Box 3.0 of
  #Box answer => answer
`,
    expected: 7,
  },
  {
    name: "associated lookup also resolves nominal prelude types",
    source: `
entry const run = fn (value: F32) => Maybe.unwrap_or 0.0 (@type.call "map" (fn x => x + 1.0) (#Some value))
`,
    expected: 5,
  },
];

for (const { name, source, expected } of programs) {
  Deno.test(name, async () => {
    const reference = await createSourceCompiler();
    const native = await createNativeCompiler();
    try {
      const artifact = reference.compile(source);
      equal(await native.compile(source), artifact);
      ok(WebAssembly.validate(artifact.bytes));
      const { instance } = await WebAssembly.instantiate(artifact.bytes);
      equal((instance.exports.run as CallableFunction)(4), expected);
      if (instance.exports.integer) {
        equal((instance.exports.integer as WebAssembly.Global).value, 42);
        equal((instance.exports.floating as WebAssembly.Global).value, 2.5);
        equal((instance.exports.integer_run as CallableFunction)(21), 42);
        equal((instance.exports.compare as CallableFunction)(3.5), 0);
        equal((instance.exports.compare as CallableFunction)(4), 1);
      }
      const specializations = artifact.analysis.functions.filter((fn) =>
        fn.name.startsWith("$mono[")
      );
      if (source.includes("const twice = fn value")) {
        ok(specializations.length > 0);
      }
    } finally {
      reference.dispose();
      await native.dispose();
    }
  });
}

Deno.test("generic associated helpers stay importable while unsupported calls fail", async () => {
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const genericSource =
      "const run = fn value => value + value\nentry const answer = fn () => run 21";
    const genericArtifact = reference.compile(genericSource);
    equal(await native.compile(genericSource), genericArtifact);
    equal(
      WebAssembly.Module.exports(new WebAssembly.Module(genericArtifact.bytes))
        .map((item) => item.name),
      ["answer"],
    );
    // Dispatch is selected while specializing reachable code, so these calls
    // are entries: an unreachable call is only type checked.
    for (
      const [source, code] of [
        ["entry const run = fn () => #True + #False", "missing_associated"],
        ["entry const run = fn () => 1 + 2.0", "missing_associated"],
        [
          `data Left = #Left F32
data Right = #Right F32
const Left.add = fn (left: Left) => fn (right: Right) => 10
const Right.add = fn (left: Left) => fn (right: Right) => 20.0
entry const run = fn (value: F32) => F32.add (#Left value + #Right value) 0.0`,
          "type_mismatch",
        ],
      ]
    ) {
      const expected = (error: unknown) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code);
        return true;
      };
      throws(() => reference.compile(source), expected);
      await rejects(native.compile(source), expected);
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("associated calls follow nominal type ownership across imports", async () => {
  const files: Record<string, string> = {
    "file:///dispatch/main.blot": `import { Box as Renamed } from "./box"
entry const run = fn (value: F32) => case #Renamed value + #Renamed 3.0 of
  #Renamed answer => answer`,
    "file:///dispatch/box.blot": `data Box = #Box F32
const Box.add = fn (left: Box) => fn (right: Box) => case (left, right) of
  (#Box a, #Box b) => #Box (a + b)`,
  };
  const project = await loadSourceProject(
    new URL("file:///dispatch/main.blot"),
    {
      readSource: (url) => Promise.resolve(files[url.href]),
    },
  );
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const artifact = reference.compile(project);
    equal(await native.compile(project), artifact);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.run as CallableFunction)(4), 7);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("incremental compilation replaces operand specializations after a type change", async () => {
  const reference = await createIncrementalCompiler();
  const native = await createNativeIncrementalCompiler();
  try {
    for (const literal of ["2", "2.0", "3.5"]) {
      const source = `const twice = fn value => value + value
entry const run = fn () => twice ${literal}`;
      const expected = await reference.compile(source);
      const actual = await native.compile(source);
      equal(actual.artifact, expected.artifact);
      const { instance } = await WebAssembly.instantiate(actual.artifact.bytes);
      equal((instance.exports.run as CallableFunction)(), Number(literal) * 2);
    }
  } finally {
    await reference.dispose();
    await native.dispose();
  }
});

Deno.test("incremental compilation reselects associated methods after declaration changes", async () => {
  const reference = await createIncrementalCompiler();
  const native = await createNativeIncrementalCompiler();
  try {
    for (
      const [implementation, answer] of [
        ["const Left.add = fn (left: Left) => fn (right: Right) => 10.0", 10],
        ["", 20],
        ["const Left.add = fn (left: Left) => fn (right: Left) => 30.0", 20],
        ["const Left.add = fn (left: Left) => fn (right: Right) => 40.0", 40],
      ] as const
    ) {
      const source = `data Left = #Left F32
data Right = #Right F32
${implementation}
const Right.add = fn (left: Left) => fn (right: Right) => 20.0
const combine = fn left => fn right => left + right
entry const run = fn (value: F32) => combine (#Left value) (#Right value)`;
      const expected = await reference.compile(source);
      const actual = await native.compile(source);
      equal(actual.artifact, expected.artifact);
      const { instance } = await WebAssembly.instantiate(actual.artifact.bytes);
      equal((instance.exports.run as CallableFunction)(4), answer);
    }
  } finally {
    await reference.dispose();
    await native.dispose();
  }
});

Deno.test("associated dispatch evaluates operands once before either implementation stage", async () => {
  const source = `
effect Read : U32 -> F32
data Box = #Box F32
const read = fn index => do:
  use value <- Read index
  return #Box value
const Box.add = fn (left: Box) => do:
  use first <- Read 3
  return fn (right: Box) => do:
    use second <- Read 4
    let #Box a = left
    let #Box b = right
    return a * 10.0 + b + first + second
entry const run = fn (probe: U32 -> F32 ! {Foreign}) => do (@effect.provider Read probe):
  return read 1 + read 2
`;
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      const observed: number[] = [];
      const probe = guest.capability({
        parameter: "U32",
        result: "F32",
        call: (value) => {
          observed.push(value);
          return value;
        },
      });
      equal(guest.call("run", probe), 19);
      equal(observed, [1, 2, 3, 4]);
    } finally {
      guest.dispose();
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});
