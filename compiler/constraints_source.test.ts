import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { bendArray } from "./bend_list.ts";
import { createFrontend, type Cst, SourceError } from "./syntax.ts";
import { createSourceCompiler } from "./source.ts";

function descendants(root: Cst): Cst[] {
  const result: Cst[] = [];
  const pending = [root];
  for (let node = pending.pop(); node; node = pending.pop()) {
    result.push(node);
    pending.push(...bendArray(node.children));
  }
  return result;
}

Deno.test("contextual where, all predicate forms, open rows, and local clauses have distinct CST fields", async () => {
  const frontend = await createFrontend();
  try {
    const source = `
const where = fn where => where
const annotated: a -> a ! {Reader.ask | e} where {
  associated "add" a a a ! {| e},
  receiver "next" a Unit a,
  field "first" a U32,
  update "first" a U32 a ! {Reader.ask | e},
  operation Remote.State.get (Array a),
  type_rep (Array a),
  effect_rep ! {Reader.ask | e},
} = fn value => value
entry const answer = fn () => do:
  let local: U32 where { type_rep U32, } = 42
  return local
`;
    const nodes = descendants(frontend.parse(source).root);
    equal(nodes.filter((node) => node.kind === "where_clause").length, 2);
    equal(
      nodes.filter((node) => node.kind === "constraint_predicate").length,
      8,
    );
    const tails = nodes.filter((node) => node.field === "tail");
    equal(tails.map((node) => node.text), ["e", "e", "e", "e"]);
    ok(nodes.some((node) => node.kind === "IDENT" && node.text === "where"));
  } finally {
    frontend.dispose();
  }
});

Deno.test("where remains a name in types, values, fields, and bindings", async () => {
  const frontend = await createFrontend();
  try {
    const root = frontend.parse(`import { where as chosen } from "./other.blot"
const where = fn where => where
const field = fn box => box.where
entry const answer = fn () => do:
  let where = 42
  use where <- Reader.ask
  return where
`).root;
    ok(
      descendants(root).some((node) =>
        node.kind === "IDENT" && node.text === "where"
      ),
    );
    equal(
      descendants(root).filter((node) => node.kind === "where_clause").length,
      0,
    );
  } finally {
    frontend.dispose();
  }
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(
      `const id: where -> where where {} = fn value => value
entry const answer = fn () => id 42
`,
    );
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes)).exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("where clauses respect nested types, comments, strings, and source offsets", async () => {
  const frontend = await createFrontend();
  try {
    const source = `// 😀 where { in a comment
const id: ({ value: where // where { in a nested type
} -> where) where { associated "where" where where where } = fn value => value
const record = where { value: 42 }
`;
    const root = frontend.parse(source).root;
    equal(
      descendants(root).filter((node) => node.kind === "where_clause").length,
      1,
    );
    const clause = descendants(root).find((node) =>
      node.kind === "where_clause"
    );
    ok(clause);
    equal(Number(clause.offset), source.lastIndexOf("where { associated"));
    const spoofed = source.replace("where { associated", "wherE { associated");
    throws(() => frontend.parse(spoofed), (error) => {
      ok(error instanceof SourceError, String(error));
      equal(error.code, "reserved_clause_marker");
      equal(error.start, spoofed.indexOf("wherE { associated"));
      return true;
    });
  } finally {
    frontend.dispose();
  }
});

Deno.test("qualified local let inside a record value keeps its clause", async () => {
  const frontend = await createFrontend();
  try {
    const source = `type Box is data = #Box { value: U32 }
entry const answer = fn () => #Box { value: do:
  let number: U32 where { type_rep U32 } = 42
  return number
}
`;
    const nodes = descendants(frontend.parse(source).root);
    equal(nodes.filter((node) => node.kind === "where_clause").length, 1);
  } finally {
    frontend.dispose();
  }
});

Deno.test("destructured local annotation keeps its where clause", async () => {
  const frontend = await createFrontend();
  try {
    const source = `entry const answer = fn () => do:
  let (left, right): (U32, U32) where {} = (20, 22)
  return @u32.add left right
`;
    const nodes = descendants(frontend.parse(source).root);
    equal(nodes.filter((node) => node.kind === "where_clause").length, 1);
  } finally {
    frontend.dispose();
  }
});

Deno.test("qualified annotations constrain the final tagged result", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const source = `
#[fn value => #True] entry const answer: Bool where { type_rep Bool } = 42
`;
    const artifact = compiler.compile(source);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as WebAssembly.Global).value, 1);
  } finally {
    compiler.dispose();
  }
});

Deno.test("a local qualified let carries associated evidence into both concrete uses", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
entry const answer = fn () => do:
  let twice: a -> a where { associated "add" a a a } = fn value => value + value
  return @u32.add (twice 20) (twice 1)
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("binding-local qualified variables instantiate at U32 and F32 uses", async () => {
  const compiler = await createSourceCompiler();
  try {
    const represented = compiler.compile(`
entry const answer = fn () => do:
  let choose: a -> a where { type_rep a } = fn value => value
  let integer = choose 40
  return @u32.add integer (@f32.to_u32 (choose 2.0))
`);
    const representedExports = new WebAssembly.Instance(
      new WebAssembly.Module(represented.bytes),
    ).exports;
    equal((representedExports.answer as CallableFunction)(), 42);

    const associated = compiler.compile(`
entry const answer = fn () => do:
  let twice: a -> a where { associated "add" a a a } = fn value => value + value
  let integer = twice 20
  return @u32.add integer (@f32.to_u32 (twice 1.0))
`);
    const associatedExports = new WebAssembly.Instance(
      new WebAssembly.Module(associated.bytes),
    ).exports;
    equal((associatedExports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("an ordinary annotated local instantiates at U32 and F32 uses", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
entry const answer = fn () => do:
  let choose: a -> a = fn value => value
  let integer = choose 40
  return @u32.add integer (@f32.to_u32 (choose 2.0))
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("a nested qualified let retains an enclosing fixed annotation", async () => {
  const compiler = await createSourceCompiler();
  try {
    throws(
      () =>
        compiler.compile(`
const outer = fn (value: a) => do:
  let choose: b -> b where { type_rep b } = fn value => value
  return (fn (w: a) => w) 42
entry const answer = fn () => outer 1.0
`),
      (error) => error instanceof SourceError && error.code === "type_mismatch",
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("a synthetic rebinding let retains its enclosing annotation", async () => {
  const compiler = await createSourceCompiler();
  try {
    throws(
      () =>
        compiler.compile(`
entry const answer = fn () => do:
  let x = 0.0
  x := (fn (z: a) => z) 1.0
  return (fn (w: a) => @u32.add w 1) 41
`),
      (error) => error instanceof SourceError && error.code === "type_mismatch",
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("a closed body call leaves unrelated qualified clauses independent", async () => {
  const compiler = await createSourceCompiler();
  try {
    const matched = compiler.compile(`
entry const answer = fn () => do:
  let increment: U32 -> U32 where { associated "add" U32 U32 U32 } = fn value => value + 1
  return increment 41
`);
    const matchedExports =
      new WebAssembly.Instance(new WebAssembly.Module(matched.bytes)).exports;
    equal((matchedExports.answer as CallableFunction)(), 42);

    const extra = compiler.compile(`
entry const answer = fn () => do:
  let increment: U32 -> U32 where { associated "add" F32 F32 F32 ! {} } = fn value => value + 1
  return increment 41
`);
    const extraExports =
      new WebAssembly.Instance(new WebAssembly.Module(extra.bytes)).exports;
    equal((extraExports.answer as CallableFunction)(), 42);

    const unrelated = compiler.compile(`
entry const answer = fn () => do:
  let increment: U32 -> U32 where { type_rep U32 } = fn value => value + 1
  return increment 41
`);
    const unrelatedExports =
      new WebAssembly.Instance(new WebAssembly.Module(unrelated.bytes)).exports;
    equal((unrelatedExports.answer as CallableFunction)(), 42);

    throws(
      () =>
        compiler.compile(`
entry const answer = fn () => do:
  let increment: U32 -> U32 where { associated "add" a a a ! {} } = fn value => value + 1
  return increment 41
`),
      (error) =>
        error instanceof SourceError && error.code === "ambiguous_qualified",
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("selected implementation evidence keeps exact effects inside a handler", async () => {
  const compiler = await createSourceCompiler();
  try {
    const pure = compiler.compile(`
type Tick is effect = Unit -> Unit
entry const answer = fn () => do (@effect.provider Tick (fn () => ())):
  use Tick ()
  return 20 + 22
`);
    const pureExports =
      new WebAssembly.Instance(new WebAssembly.Module(pure.bytes)).exports;
    equal((pureExports.answer as CallableFunction)(), 42);

    const effectful = compiler.compile(`
type Tick is effect = Unit -> Unit
type Box is data = #Box U32
const Box.add = fn (left: Box) => fn (right: Box) => do:
  use Tick ()
  let #Box a = left
  let #Box b = right
  return #Box (@u32.add a b)
entry const answer = fn () => do (@effect.provider Tick (fn () => ())):
  use boxed <- #Box 20 + #Box 22
  let #Box result = boxed
  return result
`);
    const effectfulExports =
      new WebAssembly.Instance(new WebAssembly.Module(effectful.bytes))
        .exports;
    equal((effectfulExports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("a generic qualified call distinguishes invocation effects from its ambient row", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
type Tick is effect = Unit -> Unit
const twice: a -> a ! {Tick} where { associated "add" a a a ! {} } = fn value => do:
  use Tick ()
  return value + value
entry const answer = fn () => do (@effect.provider Tick (fn () => ())):
  return twice 21
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("an explicit Tick invocation cannot select a pure add", async () => {
  const compiler = await createSourceCompiler();
  try {
    throws(
      () =>
        compiler.compile(`
type Tick is effect = Unit -> Unit
const twice: U32 -> U32 where { associated "add" U32 U32 U32 ! {Tick} } = fn value => value + value
entry const answer = fn () => twice 21
`),
      (error) =>
        error instanceof SourceError && error.code === "effect_mismatch",
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("an entry qualifier must select its declared Tick invocation", async () => {
  const compiler = await createSourceCompiler();
  try {
    throws(
      () =>
        compiler.compile(`
type Tick is effect = Unit -> Unit
entry const answer: Unit -> U32 where { associated "add" U32 U32 U32 ! {Tick} } = fn () => 20 + 22
`),
      (error) =>
        error instanceof SourceError && error.code === "effect_mismatch",
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("reached qualifiers check independent clauses through aliases and local lets", async () => {
  const compiler = await createSourceCompiler();
  try {
    for (
      const source of [
        `
type Tick is effect = Unit -> Unit
const twice: a -> a where { associated "add" U32 U32 U32 ! {Tick} } = fn value => value
const alias = twice
entry const answer = fn () => alias 21
`,
        `
type Tick is effect = Unit -> Unit
entry const answer = fn () => do:
  let local: U32 -> U32 where { associated "add" U32 U32 U32 ! {Tick} } = fn value => value
  return local 21
`,
      ]
    ) {
      throws(
        () => compiler.compile(source),
        (error) =>
          error instanceof SourceError && error.code === "effect_mismatch",
      );
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("an unused generic qualifier does not select an invalid extra clause", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
type Tick is effect = Unit -> Unit
const unused: a -> a where { associated "add" U32 U32 U32 ! {Tick} } = fn value => value
entry const answer = fn () => 42
`);
    const exports = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.bytes),
    ).exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("concrete qualified clones select separate pure and Tick effects", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
type Tick is effect = Unit -> Unit
type Box is data = #Box U32
const Box.add: Box -> (Box -> Box ! {Tick}) = fn (left: Box) => fn (right: Box) => do:
  use Tick ()
  return #Box 42
const twice: a -> a ! {| e} where { associated "add" a a a ! {| e} } = fn value => value + value
entry const integer = fn () => twice 21
entry const boxed = fn () => do (@effect.provider Tick (fn () => ())):
  use result <- twice (#Box 21)
  let #Box value = result
  return value
`);
    const exports = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.bytes),
    ).exports;
    equal((exports.integer as CallableFunction)(), 42);
    equal((exports.boxed as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("ordinary arithmetic closes invocation from the selected numeric choice", async () => {
  const compiler = await createSourceCompiler();
  try {
    const pure = compiler.compile(`entry const answer = fn () => 20 + 22`);
    const pureExports = new WebAssembly.Instance(
      new WebAssembly.Module(pure.bytes),
    ).exports;
    equal((pureExports.answer as CallableFunction)(), 42);

    const effectful = compiler.compile(`
type Tick is effect = Unit -> Unit
type Box is data = #Box U32
const Box.add: Box -> (Box -> Box ! {Tick}) = fn (left: Box) => fn (right: Box) => do:
  use Tick ()
  return #Box 42
entry const answer = fn () => do (@effect.provider Tick (fn () => ())):
  use boxed <- #Box 20 + #Box 22
  let #Box result = boxed
  return result
`);
    const effectfulExports = new WebAssembly.Instance(
      new WebAssembly.Module(effectful.bytes),
    ).exports;
    equal((effectfulExports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("a curried selected add retains pure outer and Tick inner rows", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
type Tick is effect = Unit -> Unit
type Box is data = #Box U32
const Box.add = fn (left: Box) => fn (right: Box) => do:
  use Tick ()
  return #Box 42
const twice: Box -> Box ! {Tick} where { associated "add" Box Box Box ! {Tick} } = fn value => value + value
entry const answer = fn () => do (@effect.provider Tick (fn () => ())):
  use boxed <- twice (#Box 21)
  let #Box result = boxed
  return result
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("qualified invocation rows preserve duplicate Tick effects", async () => {
  const compiler = await createSourceCompiler();
  try {
    const header = `
type Tick is effect = Unit -> Unit
type Box is data = #Box U32
const Box.add: Box -> (Box -> Box ! {Tick, Tick}) = fn (left: Box) => fn (right: Box) => do:
  use Tick ()
  use Tick ()
  return #Box 42
`;
    const body = `
entry const answer = fn () => do (@effect.provider Tick (fn () => ())):
  return do (@effect.provider Tick (fn () => ())):
    use boxed <- twice (#Box 21)
    let #Box result = boxed
    return result
`;
    const artifact = compiler.compile(
      header +
        'const twice: Box -> Box ! {Tick, Tick} where { associated "add" Box Box Box ! {Tick, Tick} } = fn value => value + value\n' +
        body,
    );
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(), 42);

    throws(
      () =>
        compiler.compile(
          header +
            'const twice: Box -> Box ! {Tick, Tick} where { associated "add" Box Box Box ! {Tick} } = fn value => value + value\n' +
            body,
        ),
      (error) =>
        error instanceof SourceError && error.code === "effect_mismatch",
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("top-level and local aliases instantiate qualified functions at each use", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
const twice: a -> a where { associated "add" a a a } = fn value => value + value
const alias = twice
entry const integer = fn () => alias 21
entry const fraction = fn () => alias 1.0
entry const local = fn () => do:
  let renamed = twice
  return @u32.add (renamed 20) (@f32.to_u32 (renamed 1.0))
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.integer as CallableFunction)(), 42);
    equal((exports.fraction as CallableFunction)(), 2);
    equal((exports.local as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("a bound member retained as a callable resolves receiver evidence", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(`
type Box is data = #Box { value: U32 }
const Box.plus = fn box => fn delta => @u32.add box.value delta
const invoke: a -> U32 where { receiver "plus" a Unit (U32 -> U32) } = fn box => do:
  let bound = box.plus
  return bound 1
entry const answer = fn () => invoke (#Box { value: 41 })
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("a bound member cannot claim a pure returned closure when its selected body uses Tick", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    throws(
      () =>
        compiler.compile(`
type Tick is effect = Unit -> Unit
type Box is data = #Box { value: U32 }
const Box.plus = fn box => fn delta => do:
  use Tick ()
  return @u32.add box.value delta
const bind: a -> (U32 -> U32 ! {}) where { receiver "plus" a Unit (U32 -> U32 ! {}) } = fn box => box.plus
entry const answer = fn () => do:
  let bound = bind (#Box { value: 41 })
  return bound 1
`),
      (error) =>
        error instanceof SourceError && error.code === "effect_mismatch",
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("a qualified constructor value instantiates at two concrete types", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(`
type Box a is data = #Box a
const make: a -> Box a where { type_rep a } = #Box
entry const integer = fn () => case make 42 of
  #Box value => value
entry const fraction = fn () => case make 1.0 of
  #Box value => value
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.integer as CallableFunction)(), 42);
    equal((exports.fraction as CallableFunction)(), 1);
  } finally {
    compiler.dispose();
  }
});

Deno.test("closed arithmetic constants remain usable as value patterns", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(`
const token = @u32.add 1 2
entry const answer = fn value => case value of
  ^token => 42
  _ => 0
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(3), 42);
    equal((exports.answer as CallableFunction)(4), 0);
  } finally {
    compiler.dispose();
  }
});

Deno.test("a concrete selector can infer a predicate-only result variable", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
const identity: U32 -> U32 where { associated "add" U32 U32 a } = fn value => value
entry const answer = fn () => identity 42
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("mutual SCC aliases carry transitive qualified requirements at creation", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
const first: a -> a = fn value => do:
  let alias = second
  return alias value
const second: a -> a where { associated "add" a a a } = fn value => case #True of
  #True => value + value
  #False => first value
entry const answer = fn () => first 21
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("mutual SCC propagates an inferred peer requirement", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
const first: a -> a = fn value => second value
const second: a -> a = fn value => case #True of
  #True => value + value
  #False => first value
entry const answer = fn () => first 21
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("mutual SCC preserves a variable mentioned only by a predicate", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
const first: U32 -> U32 = fn value => second value
const second: U32 -> U32 where { associated "add" U32 U32 a } = fn value => case #True of
  #True => value
  #False => first value
entry const answer = fn () => first 42
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("local where clauses recheck transitive SCC peers at their own boundary", async () => {
  const compiler = await createSourceCompiler();
  try {
    const source = (clause: string) => `
const first: a -> a = fn value => do:
  let alias: a -> a where { ${clause} } = second
  return alias value
const second: a -> a = fn value => third value
const third: a -> a = fn value => case #True of
  #True => value + value
  #False => first value
entry const answer = fn () => first 21
`;
    throws(() => compiler.compile(source("")), (error) => {
      ok(error instanceof SourceError, String(error));
      equal(error.code, "missing_predicate");
      equal(error.start, source("").indexOf("second\n"));
      return true;
    });
    const artifact = compiler.compile(
      source('associated "add" a a a'),
    );
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("an inner SCC clause cannot borrow its outer clause's predicate", async () => {
  const compiler = await createSourceCompiler();
  try {
    const source = (inner: string, outer: string) => `
const first: a -> a = fn value => do:
  let alias: a -> a where { ${outer} } = do:
    let inner: a -> a where { ${inner} } = second
    return inner
  return alias value
const second: a -> a where { associated "add" a a a } = fn value => case #True of
  #True => value + value
  #False => first value
entry const answer = fn () => first 21
`;
    throws(
      () => compiler.compile(source("", 'associated "add" a a a')),
      (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, "missing_predicate");
        return true;
      },
    );
    throws(
      () => compiler.compile(source('associated "add" a a a', "")),
      (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, "missing_predicate");
        return true;
      },
    );
    const artifact = compiler.compile(
      source('associated "add" a a a', 'associated "add" a a a'),
    );
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("a reached qualified entry checks its explicit extra predicate", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    for (
      const source of [
        'entry const run: () -> U32 where { associated "missing" Bool Bool Bool } = fn () => 42\n',
        'entry const value: U32 where { associated "missing" Bool Bool Bool } = 42\n',
        '#[fn value => value] entry const tagged: () -> U32 where { associated "missing" Bool Bool Bool } = fn () => 42\n',
        'entry let runtime: U32 where { associated "missing" Bool Bool Bool } = 42\n',
      ]
    ) {
      throws(
        () => compiler.compile(source),
        (error) =>
          error instanceof SourceError && error.code === "missing_associated",
      );
    }
    const valid = compiler.compile(`
entry const number: U32 where { type_rep U32 } = 42
entry let runtime: U32 where { effect_rep ! {} } = 7
`);
    const validExports =
      new WebAssembly.Instance(new WebAssembly.Module(valid.bytes)).exports;
    equal((validExports.number as WebAssembly.Global).value, 42);
    equal((validExports.runtime as WebAssembly.Global).value, 7);
    const artifact = compiler.compile(`
const unused: a -> a where { associated "missing" a a a } = fn value => value
entry const answer = fn () => 42
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
        .exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("row/type name collision and higher-rank clauses have source diagnostics", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    for (
      const [source, code, marker] of [
        [
          "const bad: e -> U32 ! {| e} = fn value => 1\nentry const answer = 42\n",
          "annotation_kind_mismatch",
          "e}",
        ],
        [
          "entry const bad = fn (callback: U32 -> U32 where { type_rep U32 }) => 42\n",
          "higher_rank_constraint",
          "where",
        ],
        [
          "type Box is data = #Box { value: U32 }\nentry const bad = #Box { value: fn (callback: U32 -> U32 where { type_rep U32 }) => 42 }\n",
          "higher_rank_constraint",
          "where",
        ],
        [
          "entry const bad: U32 where { mystery U32 } = 42\n",
          "invalid_constraint",
          "mystery",
        ],
        [
          'type State a is effect = Unit -> a\nentry const bad: U32 -> U32 where { associated "add" U32 U32 U32 ! {State a | e} } = fn value => value\n',
          "unsupported_polymorphic_effect_label",
          "associated",
        ],
      ] as const
    ) {
      throws(() => compiler.compile(source), (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code);
        equal(error.start, source.indexOf(marker));
        return true;
      });
    }
  } finally {
    compiler.dispose();
  }
});
