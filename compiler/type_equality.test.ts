import { deepStrictEqual as equal, rejects, throws } from "node:assert/strict";
import { instantiateGuest } from "./guest.ts";
import { createIncrementalCompiler } from "./incremental.ts";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

Deno.test("prelude type equality compares witnesses while preserving ordinary value equality", async () => {
  const source = `
type Count is data = Count U32
type Other is data = Other U32
type Cell value is data = Cell value
const Count.eq = fn left => fn right => do:
  let Count a = left
  let Count b = right
  return a == b
const Count.ne = fn left => fn right => Bool.not (Count.eq left right)
const constructor = Type Count == Type (Count 42)
const nominal = Type Count == Type Other
const generic = Type (Cell 1) == Type (Cell 1.0)
const array = Type [1, 2] == Type [42]
const product = Type (1, True) == Type (1.0, True)
const type_difference = Type (Cell 1) != Type (Cell 1.0)
const same_type = Type (Count 1) == Type (Count 2)
const same_type_difference = Type (Count 1) != Type (Count 2)
const numeric_value = 1 == 2
const numeric_difference = 1.0 != 2.0
const custom_equal = Count 2 == Count 2
const custom_value = Count 1 == Count 2
const custom_difference = Count 1 != Count 2
const run = fn () => Type (Cell 42) == Type (fn () -> Cell U32 => @panic "witness was called")
`;
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler({ threads: 8 });
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      for (
        const [name, expected] of [
          ["constructor", true],
          ["nominal", false],
          ["generic", false],
          ["array", true],
          ["product", false],
          ["type_difference", true],
          ["same_type", true],
          ["same_type_difference", false],
          ["numeric_value", false],
          ["numeric_difference", true],
          ["custom_equal", true],
          ["custom_value", false],
          ["custom_difference", true],
        ] as const
      ) {
        equal(guest.read(name), expected, name);
      }
      equal(guest.call("run", null), true);
    } finally {
      guest.dispose();
    }
    const mixed = "const run = fn () => Type 1 == 1";
    const missingEquality = (error: unknown) =>
      error instanceof SourceError && error.code === "missing_associated";
    throws(() => reference.compile(mixed), missingEquality);
    await rejects(() => native.compile(mixed), missingEquality);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("prelude type equality evaluates each witness once in order without invoking functions", async () => {
  const source = `
type Count is data = Count U32
effect Trace: U32 -> U32
const witness = fn index => do:
  use Trace index
  return fn () -> Count => @panic "witness was called"
const run = fn (probe: U32 -> U32 ! {Foreign}) => do (@effect.provider Trace probe):
  return Type (witness 1) == Type (witness 2)
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
        result: "U32",
        call: (value) => {
          observed.push(value);
          return value;
        },
      });
      equal(guest.call("run", probe), true);
      equal(observed, [1, 2]);
    } finally {
      guest.dispose();
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("prelude type equality updates after an incremental witness type changes", async () => {
  const compiler = await createIncrementalCompiler();
  try {
    for (
      const [witness, expected] of [["1", true], ["1.0", false], [
        "2",
        true,
      ]] as const
    ) {
      const { artifact } = await compiler.compile(
        `const run = fn () => Type 0 == Type ${witness}`,
      );
      const guest = await instantiateGuest(artifact.bytes);
      try {
        equal(guest.call("run", null), expected);
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await compiler.dispose();
  }
});
