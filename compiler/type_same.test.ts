import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { createIncrementalCompiler } from "./incremental.ts";
import { instantiateGuest } from "./guest.ts";
import { loadSourceProject } from "./source_project.ts";
import { SourceError } from "./syntax.ts";

const identityProgram = `
data Count = #Count U32
data Other = #Other U32
data Cell value = #Cell value
const same = fn left => fn right => @type.same left right
entry const constructor = same #Count (#Count 42)
entry const nominal = same #Count #Other
entry const generic = same (#Cell 1) (#Cell 1.0)
entry const array = same [1, 2] [42]
entry const product = same (1, #True) (1.0, #True)
entry const run = fn () => same (#Cell 42) (fn () -> Cell U32 => @panic "witness was called")
`;

Deno.test("type comparison specializes concrete nominal, generic and structural witnesses", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(identityProgram);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      for (
        const [name, expected] of [
          ["constructor", true],
          ["nominal", false],
          ["generic", false],
          ["array", true],
          ["product", false],
        ] as const
      ) {
        equal(guest.read(name), expected);
      }
      equal(guest.call("run", null), true);
    } finally {
      guest.dispose();
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("type comparison evaluates witness expressions once in order without invoking them", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
data Count = #Count U32
effect Trace: U32 -> U32
const witness = fn index => do:
  use Trace index
  return fn () -> Count => @panic "witness was called"
entry const run = fn (probe: U32 -> U32 ! {Foreign}) => do (@effect.provider Trace probe):
  return @type.same (witness 1) (witness 2)
`);
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
    compiler.dispose();
  }
});

Deno.test("type comparison preserves nominal module ownership", async () => {
  const files: Record<string, string> = {
    "file:///types/main.blot": `import { Box as Left } from "./left"
import { Box as Right } from "./right"
entry const run = fn () => @type.same #Left #Right`,
    "file:///types/left.blot": "data Box = #Box U32",
    "file:///types/right.blot": "data Box = #Box U32",
  };
  const project = await loadSourceProject(new URL("file:///types/main.blot"), {
    readSource: (url) => Promise.resolve(files[url.href]),
  });
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(project);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("run", null), false);
    } finally {
      guest.dispose();
    }
  } finally {
    compiler.dispose();
  }
});

const schemaProgram = `
data End = #End
type Entry { head, tail } is data = #Entry { head, tail }
data Builder schema = #Builder { schema: schema }
data Count = #Count U32
data Clock = #Clock U32
data Cell value = #Cell value
const End.contains = fn entries => fn witness => #False
const Entry.contains = fn entries => fn witness => do:
  let #Entry { head, tail } = entries
  if @type.same head witness:
    return #True
  return tail.contains(witness)
const register = fn initial => fn builder => do:
  let #Builder { schema } = builder
  if schema.contains(initial):
    return @panic "duplicate resource type"
  return #Builder { schema: #Entry { head: initial, tail: schema } }
const empty = #Builder { schema: #End }
const registered = do:
  let builder = empty
  builder := register (#Count 1) self
  builder := register (#Clock 2) self
  builder := register (#Cell 3) self
  builder := register (#Cell 4.0) self
  return builder
entry const run = fn () => do:
  let #Builder { schema } = registered
  return schema.contains(#Count)
`;

Deno.test("value schemas reject duplicate resource types during const composition", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(schemaProgram);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("run", null), true);
    } finally {
      guest.dispose();
    }
    throws(
      () =>
        compiler.compile(
          schemaProgram +
            "\nconst duplicate = register (#Count 9) registered" +
            "\nentry const probe = fn () => @array.length [duplicate]",
        ),
      (error: unknown) => {
        ok(error instanceof SourceError);
        equal(error.code, "const_panic");
        ok(error.message.includes("duplicate resource type"));
        return true;
      },
    );
    // A generic comparison is library code: only the entry is exported.
    const generic = compiler.compile(
      "const compare = fn value => @type.same value 1\nentry const same = fn () => compare 2",
    );
    equal(
      WebAssembly.Module.exports(new WebAssembly.Module(generic.bytes))
        .map((item) => item.name),
      ["same"],
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("type comparison updates incremental specialization after a witness changes", async () => {
  const compiler = await createIncrementalCompiler();
  try {
    for (
      const [witness, expected] of [["1", true], ["1.0", false], [
        "2",
        true,
      ]] as const
    ) {
      const { artifact } = await compiler.compile(
        `entry const run = fn () => @type.same 0 ${witness}`,
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

Deno.test("type comparison has exact native compiler parity", async () => {
  const js = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    for (const source of [identityProgram, schemaProgram]) {
      equal(await native.compile(source), js.compile(source));
    }
  } finally {
    js.dispose();
    await native.dispose();
  }
});
