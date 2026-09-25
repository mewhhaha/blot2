import { reachedSource } from "./fixtures.ts";
import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { createSourceFrontend } from "./source_frontend.ts";
import { loadSourceProject } from "./source_project.ts";
import { SourceError } from "./syntax.ts";
import { instantiateGuest } from "./guest.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
const api = compiled as unknown as {
  compile_source(
    root: unknown,
    prelude: unknown,
    fuel: bigint,
    steps: bigint,
  ): Result<Node>;
};

const preludeBase =
  (await Deno.readTextFile(new URL("../std/prelude.blot", import.meta.url)))
    .length + 1;

function functionNames(artifact: {
  analysis: { functions: readonly { name: string }[] };
}) {
  return artifact.analysis.functions.map((fn) => fn.name);
}

function copies(names: readonly string[], origin: string) {
  return names.filter((name) =>
    name === origin ||
    (name.startsWith("$mono[") && name.endsWith(`].${origin}`))
  ).length;
}

Deno.test("dispatch on operand types a helper already fixes compiles the helper once", async () => {
  const source = `entry const leaf = fn value => @u32.add value 1 + 0
entry const mid0 = fn value => leaf (leaf (value))
entry const mid1 = fn value => leaf (leaf (value))
entry const top0 = fn value => mid1 (mid0 (value))
entry const top1 = fn value => mid1 (mid0 (value))
entry const main = fn (value: U32) -> U32 => top1 (top0 (value))
`;
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const names = functionNames(artifact);
    equal(copies(names, "leaf"), 1);
    equal(names.filter((name) => name.startsWith("$mono[")), []);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.main as CallableFunction)(3), 11);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("a generic helper whose comparison operands are closed is not cloned", async () => {
  const source = `const leaf = fn (values: Array a) => fn (index: U32) => do:
  if index < Array.length values:
    return Some (@array.get values index)
  return Nothing
const mid0 = fn values => fn i => leaf values i
const mid1 = fn values => fn i => leaf values i
entry const pick = fn (i: U32) -> U32 => do:
  let integers = [1, 2, 3]
  let floats = [1.0, 2.0]
  let a = mid0 integers i
  let b = mid1 floats i
  return case (a, b) of
    (Some x, Some y) => x + F32.to_u32 y
    _ => 0
`;
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const names = functionNames(artifact);
    equal(copies(names, "leaf"), 1);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.pick as CallableFunction)(1), 4);
    equal((instance.exports.pick as CallableFunction)(2), 0);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("receiver members resolve once the receiver's nominal head is known", async () => {
  const source = `const count = fn (values: Array a) => values.length + 1
entry const run = fn () -> U32 => count [1, 2] + count [1.0]
`;
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const names = functionNames(artifact);
    equal(copies(names, "count"), 1);
    equal(names.filter((name) => name.startsWith("$mono[")), []);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.run as CallableFunction)(), 5);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("field accessors are shared per receiver type and field", async () => {
  const source = `type Point is data = Point { x: F32, y: F32 }
const sum = fn (p: Point) -> F32 => p.x + p.y + p.x
const other = fn (p: Point) -> F32 => p.x
const get_x = fn p => p.x
const moved = fn (p: Point) -> Point => do:
  let q = p
  q.x := self + 1.0
  q.x := self + 1.0
  return q
entry const run = fn (value: F32) -> F32 => sum (Point { x: value, y: 2.0 }) + other (Point { x: 1.0, y: value }) + get_x (moved (Point { x: 3.0, y: 0.0 }))
`;
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const accessors = functionNames(artifact)
      .filter((name) => name.startsWith("$member")).sort();
    equal(accessors, [
      "$member.set[Point].x",
      "$member[Point].x",
      "$member[Point].y",
    ]);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.run as CallableFunction)(4), 16);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("resolved members, fields and operators evaluate operands once in source order", async () => {
  const source = `
type Box is data = Box { values: Array U32 }
const Box.pick = fn receiver => fn index => receiver.values[index]
const make = fn (probe: U32 -> U32 ! {Foreign}) => do:
  use probe 1
  return Box { values: [40, 42] }
entry const run = fn (probe: U32 -> U32 ! {Foreign}) => probe(5) - probe(3) + make(probe).pick(probe(2) - 1) - 2
`;
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const artifact = reference.compile(source);
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
      equal(calls, [5, 3, 1, 2]);
    } finally {
      guest.dispose();
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

// A prelude-free operator whose implementation is a user type's member.
const localNum =
  'infixl 60 (+) = add\nconst add = fn left => fn right => @type.call "add" left right\ntype Num is data = Num U32\nconst Num.add = fn (a: Num) => fn (b: Num) => a\n';
// A receiver member that performs an effect.
const localPing =
  "effect Ping: Unit -> U32\ntype Box is data = Box { value: U32 }\nconst Box.ping = fn (box: Box) => do:\n  use value <- Ping ()\n  return value\nconst pure_only = fn (callback: Unit -> U32) => callback ()\n";
// A receiver member whose selection equates the receiver's two type arguments.
const localPair =
  "type Pair [a, b] is data = Pair (a, b)\nconst Pair.same = fn (p: Pair [a, a]) => 0\n";

// Expected values were recorded from the compiler before concrete dispatch
// resolution. `at` is the diagnostic position inside the source; the checked
// subject adds the frontend's source base (the prelude's length plus one).
const diagnostics: readonly {
  name: string;
  prelude: "none" | "default";
  source: string;
  code: string;
  at: number;
  message: string;
}[] = [
  {
    name: "closed missing member",
    prelude: "none",
    source:
      "type Box is data = Box { value: U32 }\nconst run = fn () => (Box { value: 1 }).missing\n",
    code: "missing_member",
    at: 78,
    message: "no associated member Box.missing",
  },
  {
    name: "closed field and method clash",
    prelude: "none",
    source:
      "type Box is data = Box { value: U32 }\nconst Box.value = fn box => 0\nconst run = fn () => (Box { value: 1 }).value\n",
    code: "ambiguous_member",
    at: 108,
    message: "field and associated function share the name value",
  },
  {
    name: "closed missing writable field",
    prelude: "none",
    source:
      "type Box is data = Box { value: U32 }\nconst run = fn () => do:\n  let box = Box { value: 1 }\n  box.missing := 2\n  return box.value\n",
    code: "missing_field",
    at: 97,
    message: "no writable field missing on main::Box",
  },
  {
    name: "closed operands without an implementation",
    prelude: "default",
    source: "const run = fn () => True + False\n",
    code: "missing_associated",
    at: 26,
    message:
      "no compatible add for Bool and Bool; left: unknown value $prelude.Bool.add; right: unknown value $prelude.Bool.add",
  },
  {
    name: "closed mixed operands",
    prelude: "default",
    source: "const run = fn () => 1 + 2.0\n",
    code: "missing_associated",
    at: 23,
    message:
      "no compatible add for U32 and F32; left: cannot unify U32 with F32; right: cannot unify F32 with U32",
  },
  {
    name: "closed left implementation whose result conflicts",
    prelude: "default",
    source:
      "data Left = Left F32\ndata Right = Right F32\nconst Left.add = fn (left: Left) => fn (right: Right) => 10\nconst Right.add = fn (left: Left) => fn (right: Right) => 20.0\nconst run = fn (value: F32) => F32.add (Left value + Right value) 0.0\n",
    code: "type_mismatch",
    at: 218,
    message: "cannot unify U32 with F32",
  },
  {
    name: "resolved helper result conflicts with its caller",
    prelude: "default",
    source:
      "const helper = fn (x: U32) => x + 1\nconst bad = fn () => F32.add (helper 1) 2.0\n",
    code: "type_mismatch",
    at: 32,
    message: "cannot unify U32 with F32",
  },
  {
    name: "helper argument conflicts before resolution",
    prelude: "default",
    source:
      "const helper = fn (x: U32) => x + 1\nconst bad = fn () => helper 1.0\n",
    code: "type_mismatch",
    at: 57,
    message: "cannot unify U32 with F32",
  },
  {
    name: "missing member on a resolved field result",
    prelude: "none",
    source:
      "type Inner is data = Inner { value: U32 }\ntype Outer is data = Outer { inner: Inner }\nconst run = fn () => (Outer { inner: Inner { value: 42 } }).inner.missing\n",
    code: "missing_member",
    at: 152,
    message: "no associated member Inner.missing",
  },
  {
    name: "generic receiver constrained by a monomorphic method",
    prelude: "none",
    source:
      "type Box a is data = Box a\nconst Box.get = fn (box: Box U32) => 1\nconst f = fn b => b.get\nconst g = fn () => f (Box 1.0)\n",
    code: "type_mismatch",
    at: 86,
    message: "cannot unify U32 with F32",
  },
  {
    name: "missing writable field in a generic function",
    prelude: "none",
    source:
      "type Box is data = Box { value: U32 }\nconst touch = fn box => do:\n  box.nothing := 1\n  return box\nconst run = fn () => touch (Box { value: 1 })\n",
    code: "missing_field",
    at: 71,
    message: "no writable field nothing on main::Box",
  },
  {
    name: "field and method clash through a generic caller",
    prelude: "none",
    source:
      "type Box is data = Box { value: U32 }\nconst Box.value = fn box => 0\nconst read = fn box => box.value\nconst run = fn () => read (Box { value: 1 })\n",
    code: "ambiguous_member",
    at: 95,
    message: "field and associated function share the name value",
  },
  // A local `let` generalizes what its value leaves open. Selecting a site
  // inside it binds those variables, which changes the let's scheme without
  // changing any interface, so the rewrite must be checked again and, when
  // that check fails, abandoned for specialization's diagnostic.
  {
    name: "local helper result conflicts with its caller",
    prelude: "default",
    source:
      "const run = fn () => do:\n  let helper = fn (x: U32) => x + 1\n  return F32.add (helper 1) 2.0\n",
    code: "type_mismatch",
    at: 57,
    message: "cannot unify U32 with F32",
  },
  {
    name: "local helper result conflicts with its caller in a single round",
    prelude: "none",
    source: localNum +
      "const run = fn () => do:\n  let helper = fn (x: Num) => x + Num 1\n  return @f32.add (helper (Num 1)) 2.0\n",
    code: "type_mismatch",
    at: 215,
    message: "cannot unify main::Num with F32",
  },
  {
    name: "function-valued local let conflicts with its caller",
    prelude: "none",
    source: localNum +
      "const konst = fn a => fn b => a\nconst run = fn (x: Num) => do:\n  let f = konst (x + Num 1)\n  return @f32.add (f 0) 2.0\n",
    code: "type_mismatch",
    at: 240,
    message: "cannot unify main::Num with F32",
  },
  {
    name: "local generic receiver constrained by a monomorphic method",
    prelude: "none",
    source:
      "type Box a is data = Box a\nconst Box.get = fn (box: Box U32) => 1\nconst g = fn () => do:\n  let f = fn b => (Box b).get\n  return f 1.0\n",
    code: "type_mismatch",
    at: 115,
    message: "cannot unify U32 with F32",
  },
  {
    name: "local function made effectful by its resolved member",
    prelude: "none",
    source: localPing +
      "const run = fn () => do:\n  let f = fn (b: Box) => b.ping\n  return pure_only (fn () => f (Box { value: 1 }))\n",
    code: "effect_mismatch",
    at: 251,
    message: "cannot unify effect rows and ! {main::Ping}",
  },
  // Selecting Pair.same binds the outer parameter's type variable (a group
  // variable, not generalized by the let) to the let's generalized parameter
  // type. That moves the variable out of the let, so the rewrite is checked
  // again; the let's uses conflict, and specialization reports the error.
  {
    name:
      "outer parameter tied to a local let's parameter by its resolved member",
    prelude: "none",
    source: localPair +
      "const run = fn x => do:\n  let f = fn b => @u32.add (Pair (x, b)).same 1\n  return @u32.add (f 1) (f 2.0)\nconst go = fn () -> U32 => run 1\n",
    code: "type_mismatch",
    at: 147,
    message: "cannot unify U32 with F32",
  },
];

Deno.test("dispatch diagnostics keep their code, position and message", async () => {
  const frontends = {
    none: await createSourceFrontend({ prelude: "none" }),
    default: await createSourceFrontend(),
  };
  const natives = {
    none: await createNativeCompiler({ prelude: "none" }),
    default: await createNativeCompiler(),
  };
  try {
    for (const expected of diagnostics) {
      const source = reachedSource(expected.source);
      const input = frontends[expected.prelude].prepare(source);
      const offset = (expected.prelude === "none" ? 1 : preludeBase) +
        expected.at;
      equal(
        api.compile_source(
          input.root,
          input.prelude,
          input.nodeCount,
          100_000n,
        ),
        {
          $: "Fail",
          error: {
            $: "Diagnostic",
            code: expected.code,
            subject: `offset:${offset}`,
            message: expected.message,
          },
        },
        expected.name,
      );
      await rejects(
        natives[expected.prelude].compile(source),
        (error: unknown) => {
          ok(error instanceof SourceError, expected.name);
          equal(
            [error.code, error.message, error.start],
            [expected.code, expected.message, expected.at],
            expected.name,
          );
          return true;
        },
      );
    }
  } finally {
    frontends.none.dispose();
    frontends.default.dispose();
    await natives.none.dispose();
    await natives.default.dispose();
  }
});

Deno.test("sites inside local lets resolve without changing what the let means", async () => {
  const cases: readonly {
    prelude: "none" | "default";
    source: string;
    run: string;
    expected: number;
    origin?: string;
  }[] = [
    {
      prelude: "default",
      source:
        "entry const run = fn () -> U32 => do:\n  let helper = fn (x: U32) => x + 1\n  return helper 1 + 2\n",
      run: "run",
      expected: 4,
    },
    {
      prelude: "none",
      source:
        "type Box a is data = Box a\nconst Box.get = fn (box: Box U32) => 7\nentry const g = fn () -> U32 => do:\n  let f = fn b => (Box b).get\n  return f 1\n",
      run: "g",
      expected: 7,
    },
    {
      prelude: "none",
      source: localPing +
        "entry const run = fn () => do (@effect.provider Ping (fn () => 40)):\n  let f = fn (b: Box) => b.ping\n  use value <- f (Box { value: 1 })\n  return value\n",
      run: "run",
      expected: 40,
    },
    // `square` is annotated, but its let still generalizes its latent effect
    // row. Only the fresh row variables of the selected F32.mul instance name
    // that row, so the let keeps its scheme and the generic caller still
    // compiles once.
    {
      prelude: "default",
      source:
        "const scale = fn value => do:\n  let square = fn (x: F32) -> F32 => x * x\n  return (value, square 3.0)\nentry const run = fn () -> F32 => do:\n  let (a, b) = scale 1\n  let (c, d) = scale 1.0\n  return b + d\n",
      run: "run",
      expected: 18,
      origin: "scale",
    },
    // Box.size is generic: only the fresh type and row variables of its
    // selected instance name the let's generalized parameter type and row.
    // The round is stable and is not checked again, so the rewritten let must
    // stay polymorphic: it is used at U32 and at F32.
    {
      prelude: "none",
      source:
        "type Box a is data = Box a\nconst Box.size = fn (box: Box a) => 0\nentry const run = fn () -> U32 => do:\n  let f = fn b => @u32.add (Box b).size 1\n  return @u32.add (f 1) (f 2.0)\n",
      run: "run",
      expected: 2,
      origin: "run",
    },
    // Selecting Pair.same binds the outer parameter's type variable to the
    // let's generalized parameter type. The rewrite is checked again; here the
    // let's uses agree, the check passes, and `run` compiles once.
    {
      prelude: "none",
      source: localPair +
        "entry const run = fn x => do:\n  let f = fn b => @u32.add (Pair (x, b)).same 1\n  return @u32.add (f 1) (f 2)\nentry const go = fn () -> U32 => run 1\n",
      run: "go",
      expected: 2,
      origin: "run",
    },
  ];
  const references = {
    none: await createSourceCompiler({ prelude: "none" }),
    default: await createSourceCompiler(),
  };
  const natives = {
    none: await createNativeCompiler({ prelude: "none" }),
    default: await createNativeCompiler(),
  };
  try {
    for (const expected of cases) {
      const artifact = references[expected.prelude].compile(expected.source);
      equal(await natives[expected.prelude].compile(expected.source), artifact);
      if (expected.origin !== undefined) {
        const names = functionNames(artifact);
        equal(copies(names, expected.origin), 1);
        equal(names.filter((name) => name.startsWith("$mono[")), []);
      }
      const { instance } = await WebAssembly.instantiate(artifact.bytes);
      equal(
        (instance.exports[expected.run] as CallableFunction)(),
        expected.expected,
      );
    }
  } finally {
    references.none.dispose();
    references.default.dispose();
    await natives.none.dispose();
    await natives.default.dispose();
  }
});

Deno.test("a lexical receiver still shadows a same-named namespace when resolved", async () => {
  const files: Record<string, string> = {
    "/members/count.blot":
      "type Count is data = Count { value: U32 }\nconst Count.add = fn receiver => fn amount => Count { value: receiver.value + amount }\nconst seed = Count { value: 40 }\nconst extra = 2\n",
    "/members/main.blot":
      'import * as counter from "./count"\nentry const run = fn () => do:\n  let counter = counter.seed\n  return counter.extra\n',
  };
  const project = await loadSourceProject(
    new URL("file:///members/main.blot"),
    { readSource: (url) => Promise.resolve(files[url.pathname]) },
  );
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const matches = (error: unknown) =>
      error instanceof SourceError && error.code === "missing_member" &&
      error.message ===
        "no associated member $module[count.blot].Count.extra";
    let failed = false;
    try {
      reference.compile(project);
    } catch (error) {
      failed = matches(error);
    }
    ok(failed);
    await rejects(native.compile(project), matches);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});
