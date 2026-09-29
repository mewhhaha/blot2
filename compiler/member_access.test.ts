import { reachedSource } from "./fixtures.ts";
import { deepStrictEqual as equal, rejects, throws } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { createIncrementalCompiler } from "./incremental.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { loadSourceProject } from "./source_project.ts";
import { instantiateGuest } from "./guest.ts";
import { SourceError } from "./syntax.ts";

Deno.test("receiver members support partial application, fields, generic wrappers, and call precedence", async () => {
  const source = `
type Count is data = #Count { value: U32 }
const Count.add = fn receiver => fn amount => #Count { value: receiver.value + amount }
const increment = fn receiver => receiver.add(2)
const make = fn value => #Count { value }
entry const folded = (#Count { value: 40 }).add(2).value
entry const run = fn () => do:
  let counter = make(40)
  let bound = counter.add
  let next = bound(2)
  return increment(make(next.value - 2)).value
entry const precedence = fn () => do:
  let sum = fn x => fn y => x + y
  let counts = [#Count { value: 40 }]
  return sum counts[0].value 2
entry const function_field = fn () => do:
  let action = #Action { run: fn x => x + 2 }
  return action.run(40)
type Action is data = #Action { run: U32 -> U32 }
`;
  const js = await createSourceCompiler();
  const native = await createNativeCompiler({ threads: 8 });
  try {
    const artifact = js.compile(source);
    equal(await native.compile(source), artifact);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.read("folded"), 42);
      for (const name of ["run", "precedence", "function_field"]) {
        equal(guest.call(name, null), 42);
      }
    } finally {
      guest.dispose();
    }
  } finally {
    js.dispose();
    await native.dispose();
  }
});

Deno.test("receiver selection follows nominal ownership across imports and lexical shadowing", async () => {
  const sources: Record<string, string> = {
    "/members/count.blot": `type Count is data = #Count { value: U32 }
const Count.add = fn receiver => fn amount => #Count { value: receiver.value + amount }
const seed = #Count { value: 40 }
`,
    "/members/main.blot": `import * as counter from "./count"
entry const run = fn () => do:
  let counter = counter.seed
  return counter.add(2).value
`,
  };
  const project = await loadSourceProject(
    new URL("file:///members/main.blot"),
    {
      readSource: (url) => Promise.resolve(sources[url.pathname]),
    },
  );
  const js = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const artifact = js.compile(project);
    equal(await native.compile(project), artifact);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.run as CallableFunction)(), 42);
  } finally {
    js.dispose();
    await native.dispose();
  }
});

Deno.test("member receivers and chained indices evaluate once in source order", async () => {
  const source = `
type Box is data = #Box { values: Array U32 }
const Box.pick = fn receiver => fn index => receiver.values[index]
const make = fn (probe: U32 -> U32 ! {Foreign}) => do:
  use probe 1
  return #Box { values: [40, 42] }
entry const run = fn (probe: U32 -> U32 ! {Foreign}) => make(probe).pick(probe(2) - 1)
`;
  const js = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const artifact = js.compile(source);
    equal(await native.compile(source), artifact);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      const calls: number[] = [];
      const probe = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value) => {
          calls.push(value);
          return value;
        },
      });
      equal(guest.call("run", probe), 42);
      equal(calls, [1, 2]);
    } finally {
      guest.dispose();
    }
  } finally {
    js.dispose();
    await native.dispose();
  }
});

Deno.test("member diagnostics reject missing members and ambiguous fields without right-side fallback", async () => {
  const js = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    for (
      const [source, code] of [
        ["const run = fn () => [1].missing", "missing_member"],
        [
          "type Box is data = #Box { value: U32 }\nconst Box.value = fn box => 0\nconst run = fn () => (#Box { value: 1 }).value",
          "ambiguous_member",
        ],
        [
          "type Left is data = #Left\ntype Right is data = #Right\nconst Right.combine = fn left => fn right => 42\nconst run = fn () => (#Left).combine(#Right)",
          "missing_member",
        ],
        [
          "type Box is data = #Box U32\nentry const run = fn () => do:\n  let box = #Box 0\n  box.value := 1\n  return box",
          "missing_field",
        ],
      ] as const
    ) {
      const matches = (error: unknown) =>
        error instanceof SourceError && error.code === code;
      throws(() => js.compile(reachedSource(source)), matches);
      await rejects(() => native.compile(reachedSource(source)), matches);
    }
  } finally {
    js.dispose();
    await native.dispose();
  }
});

Deno.test("field access tracks reordered declarations in both incremental compilers", async () => {
  const js = await createIncrementalCompiler();
  const native = await createNativeIncrementalCompiler();
  const clean = await createSourceCompiler();
  try {
    for (const session of [js, native]) {
      for (
        const fields of ["x: U32, y: U32", "y: U32, x: U32", "x: U32, y: U32"]
      ) {
        const source =
          `type Pair is data = #Pair { ${fields} }\nconst read = fn pair => pair.x\nentry const run = fn () => read (#Pair { x: 42, y: 7 })`;
        const { artifact } = await session.compile(source);
        equal(artifact, clean.compile(source));
        const { instance } = await WebAssembly.instantiate(artifact.bytes);
        equal((instance.exports.run as CallableFunction)(), 42);
      }
    }
  } finally {
    await js.dispose();
    await native.dispose();
    clean.dispose();
  }
});
