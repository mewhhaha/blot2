import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { instantiateGuest } from "./guest.ts";
import { SourceError } from "./syntax.ts";

const typedBuilder = `
type Builder [world, scope] is data = #Builder { initial: world, scope: scope }
data Counter = #Counter U32
const new = fn () => #Builder { initial: (), scope: fn world => fn action => (world, action ()) }
const insert_resource = fn initial => fn builder => do:
  let #Builder { initial: previous_initial, scope: previous_scope } = builder
  let scope = fn world => fn action => do:
    let (current, previous) = world
    use outcome <- @state.run current (fn () => previous_scope previous action)
    let (next, (previous_next, result)) = outcome
    return ((next, previous_next), result)
  return #Builder { initial: (initial, previous_initial), scope }
const scoped = fn builder => fn world => fn action => do:
  let #Builder { scope } = builder
  return scope world action
const create = fn builder => fn action => do:
  let #Builder { initial } = builder
  return scoped builder initial action
const application = insert_resource (#Counter 40) (new ())
entry const run = fn () => do:
  let (initial, _) = create application (fn () => ())
  let (next, integer) = scoped application initial (fn () => do:
    use counter <- @state.get #Counter
    let #Counter value = counter
    use @state.set (#Counter (value + 2))
    return value)
  let (_, floating) = scoped application next (fn () => do:
    use counter <- @state.get #Counter
    let #Counter value = counter
    return U32.to_f32 value + 0.5)
  return U32.to_f32 integer + floating
entry const folded = run ()
`;

const sharedBuilder =
  typedBuilder.replace("scope: scope", "scope: world -> scope") + `
entry const callback = fn (probe: Unit -> F32 ! {Foreign}) => do:
  use outcome <- create application probe
  let (_, result) = outcome
  return result
`;

Deno.test("const builders share resolved schemas across callback types and effects", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(sharedBuilder);
    equal(
      artifact.analysis.constants.filter(({ value }) =>
        value.$ === "DataValue" && value.constructor === "Builder"
      ).map(({ name }) => name),
      ["application"],
      "the composed builder must be evaluated and stored only once",
    );
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("run", null), 82.5);
      equal(guest.read("folded"), 82.5);
      let calls = 0;
      const probe = guest.capability({
        parameter: "Unit",
        result: "F32",
        call: () => {
          calls++;
          return 1.5;
        },
      });
      equal(guest.call("callback", probe), 1.5);
      equal(calls, 1);
    } finally {
      guest.dispose();
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("const callable fields defer dispatch that requires each caller's type", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
data Box action = #Box action
const doubled = #Box (fn value => value + value)
const double = fn value => do:
  let #Box apply = doubled
  return apply value
entry const run = fn () => U32.to_f32 (double 20) + double 1.25
`);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("run", null), 42.5);
    } finally {
      guest.dispose();
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("const callable fields retain shared dependency values", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
data Scope action = #Scope action
const wrapped = do:
  let #Scope invoke = scope
  return #Scope (fn action => invoke action)
const scope = #Scope (fn action => (40 + 2, action ()))
const invoke = fn action => do:
  let #Scope apply = wrapped
  return apply action
entry const run = fn () => do:
  let (_, ignored) = invoke (fn () => ())
  let (count, result) = invoke (fn () => 1.5)
  return U32.to_f32 count + result
`);
    equal(
      artifact.analysis.constants.filter(({ value }) =>
        value.$ === "DataValue" && value.constructor === "Scope"
      ).map(({ name }) => name).sort(),
      ["scope", "wrapped"],
    );
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("run", null), 43.5);
    } finally {
      guest.dispose();
    }
  } finally {
    compiler.dispose();
  }
});

// Only initializers an entry reaches are specialized and evaluated.
Deno.test("const callable fields validate reached resolved initializers", async () => {
  const compiler = await createSourceCompiler();
  try {
    for (
      const [body, code] of [
        [
          `do:
  if 1 + 1 == 2:
    return @panic "invalid builder"
  return #Scope (fn action => (40 + 2, action ()))`,
          "const_panic",
        ],
        [
          "#Scope (fn action => (#True + #False, action ()))",
          "missing_associated",
        ],
      ]
    ) {
      throws(
        () =>
          compiler.compile(
            `data Scope action = #Scope action\nconst invalid = ${body}\nentry const probe = fn () => do:\n  let kept = invalid\n  return 0\n`,
          ),
        (error: unknown) => {
          ok(error instanceof SourceError);
          equal(error.code, code);
          return true;
        },
      );
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("const builders specialize callback results while retaining compile-time values", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(typedBuilder);
    ok(
      artifact.analysis.constants.some(({ value }) =>
        value.$ === "DataValue" && value.constructor === "Builder"
      ),
      "builder composition must remain a compile-time value",
    );
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("run", null), 82.5);
      equal(guest.call("run", null), 82.5);
      equal(guest.read("folded"), 82.5);
    } finally {
      guest.dispose();
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("const callable fields preserve independent generic results with ordinary operators", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
data Scope action = #Scope action
const scope = #Scope (fn action => (40 + 2, action ()))
const invoke = fn action => do:
  let #Scope call = scope
  return call action
entry const run = fn () => do:
  let (_, ignored) = invoke (fn () => ())
  let (count, result) = invoke (fn () => 1.5)
  return U32.to_f32 count + result
`);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("run", null), 43.5);
    } finally {
      guest.dispose();
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("const callable specialization preserves foreign callback effects", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
data Scope action = #Scope action
const scope = #Scope (fn action => do:
  use result <- action ()
  return (40 + 2, result))
const invoke = fn action => do:
  let #Scope call = scope
  use result <- call action
  return result
entry const run = fn (probe: Unit -> F32 ! {Foreign}) => do:
  use first <- invoke (fn () => ())
  use second <- invoke probe
  let (count, result) = second
  return U32.to_f32 count + result
`);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      let calls = 0;
      const probe = guest.capability({
        parameter: "Unit",
        result: "F32",
        call: () => {
          calls++;
          return 1.5;
        },
      });
      equal(guest.call("run", probe), 43.5);
      equal(calls, 1);
    } finally {
      guest.dispose();
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("const specialization retains exact native compiler parity", async () => {
  const js = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    equal(await native.compile(typedBuilder), js.compile(typedBuilder));
    equal(await native.compile(sharedBuilder), js.compile(sharedBuilder));
  } finally {
    js.dispose();
    await native.dispose();
  }
});
