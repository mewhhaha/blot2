import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { loadSourceProject } from "./source_project.ts";
import { SourceError } from "./syntax.ts";

type Compiler =
  | Awaited<ReturnType<typeof createSourceCompiler>>
  | Awaited<ReturnType<typeof createNativeCompiler>>;

function resolverTest(
  name: string,
  run: (compiler: Compiler) => Promise<void>,
) {
  for (const backend of ["reference", "native"] as const) {
    Deno.test(`${backend}: ${name}`, async () => {
      const compiler = await (backend === "reference"
        ? createSourceCompiler()
        : createNativeCompiler());
      try {
        await run(compiler);
      } finally {
        await compiler.dispose();
      }
    });
  }
}

async function evaluate(compiler: Compiler, source: string, expected: number) {
  const artifact = await compiler.compile(
    source + "\nentry const expected = answer ()\n",
  );
  ok(WebAssembly.validate(artifact.bytes));
  const instance = new WebAssembly.Instance(
    new WebAssembly.Module(artifact.bytes),
  );
  const answer = instance.exports.answer;
  ok(typeof answer === "function");
  equal(answer(0), expected);
  const constant = instance.exports.expected;
  ok(constant instanceof WebAssembly.Global);
  equal(constant.value, expected);
}

resolverTest(
  "monad resolvers are ordinary aliased library values",
  async (compiler) => {
    await evaluate(
      compiler,
      `
const make = fn constructor => monad constructor
const try = identity (make (identity Maybe))
const sequence = fn resolver => fn candidate => do resolver:
  use value <- candidate
  return value
entry const answer = fn () => Maybe.unwrap_or 0 (sequence try (#Some 42))
`,
      42,
    );
  },
);

resolverTest(
  "Maybe failure skips subsequent operations and values",
  async (compiler) => {
    await evaluate(
      compiler,
      `
const fail = fn () -> Maybe U32 => #Nothing
const impossible = fn () -> Maybe U32 => @panic "continuation must not run"
const sequence = fn () => do (monad Maybe):
  use value <- fail ()
  use extra <- impossible ()
  return value + extra
entry const answer = fn () => Maybe.unwrap_or 42 (sequence ())
`,
      42,
    );
  },
);

resolverTest(
  "discard binds short-circuit inside conditional suites",
  async (compiler) => {
    await evaluate(
      compiler,
      `
const sequence = fn enabled => do monad Maybe:
  if enabled:
    use #Nothing
  return 7
entry const answer = fn () =>
  Maybe.unwrap_or 35 (sequence #True) + Maybe.unwrap_or 0 (sequence #False)
`,
      42,
    );
  },
);

resolverTest(
  "return lifts, forwarding preserves a wrapper, and fallthrough lifts Unit",
  async (compiler) => {
    await evaluate(
      compiler,
      `
const present = do monad Maybe:
  return 40
const forwarded = do monad Maybe:
  return $ #Some 2
const missing = do monad Maybe:
  return $ #Nothing
const finished = do monad Maybe:
  #Nothing
entry const answer = fn () => do:
  let #Some () = finished else:
    return 0
  if Maybe.is_some missing:
    return 0
  return Maybe.unwrap_or 0 present + Maybe.unwrap_or 0 forwarded
`,
      42,
    );
  },
);

resolverTest(
  "Result preserves errors while bind payload types change",
  async (compiler) => {
    await evaluate(
      compiler,
      `
const try = monad Result
const sequence = fn input => do try:
  use value: U32 <- input
  use converted: F32 <- #Ok (U32.to_f32 value)
  return F32.to_u32 converted + 2
entry const answer = fn () => do:
  let good = sequence (#Ok 40)
  let bad = sequence (#Err #True)
  let #Err #True = bad else:
    return 0
  return Result.unwrap_or 0 good
`,
      42,
    );
  },
);

resolverTest(
  "nested do blocks retain their own binding and return rules",
  async (compiler) => {
    await evaluate(
      compiler,
      `
const sequence = fn () => do monad Maybe:
  let wrapped = do:
    use value <- #Some 40
    return value
  use value <- wrapped
  let extra = do monad Result:
    return 2
  return value + Result.unwrap_or 0 extra
entry const answer = fn () => Maybe.unwrap_or 0 (sequence ())
`,
      42,
    );
  },
);

resolverTest(
  "source-defined monads select their own pure and bind",
  async (compiler) => {
    await evaluate(
      compiler,
      `
type Identity a is data = #Identity a
const Identity.pure = fn value => #Identity value
const Identity.bind = fn candidate => fn next => case candidate of
  #Identity value => next value
const sequence = fn () => do monad Identity:
  use value <- #Identity 40
  return value + 2
entry const answer = fn () => do:
  let #Identity value = sequence ()
  return value
`,
      42,
    );
  },
);

resolverTest(
  "monad blocks preserve unrelated effects and provider scopes",
  async (compiler) => {
    await evaluate(
      compiler,
      `
type Reader is effect = { ask: Unit -> U32 }
const reader = @effect.provider Reader.ask (fn () => 40)
const lookup = fn () => do:
  use value <- Reader.ask ()
  return #Some value
const sequence = fn () => do monad Maybe:
  use value <- lookup ()
  return value + 2
entry const answer = fn () => do reader:
  use result <- sequence ()
  return Maybe.unwrap_or 0 result
`,
      42,
    );
  },
);

resolverTest(
  "guarded bindings return from their monad block",
  async (compiler) => {
    await evaluate(
      compiler,
      `
const sequence = fn candidate => do monad Maybe:
  let #Some value = candidate else:
    return $ #Nothing
  return value + 2
entry const answer = fn () =>
  Maybe.unwrap_or 0 (sequence (#Some 40)) + Maybe.unwrap_or 0 (sequence #Nothing)
`,
      42,
    );
  },
);

resolverTest(
  "loop binds skip later iterations and the block suffix",
  async (compiler) => {
    await evaluate(
      compiler,
      `
const next = fn index => do:
  if index == 2:
    return #Nothing
  if index > 2:
    return @panic "later iteration must not run"
  return #Some index
const sequence = fn () => do monad Maybe:
  for index in 0 .. 5:
    use next index
  return @panic "suffix must not run"
entry const answer = fn () => Maybe.unwrap_or 42 (sequence ())
`,
      42,
    );
  },
);

resolverTest(
  "monad loops carry successor bindings and allow early returns",
  async (compiler) => {
    await evaluate(
      compiler,
      `
const sequence = fn () => do monad Maybe:
  let total = 0
  for index in 0 .. 4:
    use value <- #Some index
    total := self + value
  for ever:
    use value <- #Some 36
    return total + value
entry const answer = fn () => Maybe.unwrap_or 0 (sequence ())
`,
      42,
    );
  },
);

resolverTest(
  "a source bind controls how often its continuation executes",
  async (compiler) => {
    await evaluate(
      compiler,
      `
type Twice a is data = #Twice a
const Twice.pure = fn value => #Twice value
const Twice.bind = fn candidate => fn next => case candidate of
  #Twice value => do:
    use ignored <- next value
    return next value
type Counter is effect = { read: Unit -> U32, write: U32 -> Unit }
const sequence = fn () => do monad Twice:
  use ignored <- #Twice ()
  let value = do:
    return 1
  return do:
    use current <- Counter.read ()
    use Counter.write (current + value)
    return current
entry const answer = fn () => do:
  let (state, #Twice result) = do (@effect.state Counter.read Counter.write 20):
    return sequence ()
  return state + result
`,
      43,
    );
  },
);

resolverTest(
  "resolver expressions execute once before their block",
  async (compiler) => {
    await evaluate(
      compiler,
      `
type Counter is effect = { read: Unit -> U32, write: U32 -> Unit }
const construct = fn () => do:
  use value <- Counter.read ()
  use Counter.write (value + 1)
  return monad Maybe
entry const answer = fn () => do:
  let (count, result) = do (@effect.state Counter.read Counter.write 0):
    return do (construct ()):
      use first <- #Some 40
      use second <- #Some 2
      return first + second
  return count + Maybe.unwrap_or 0 result
`,
      43,
    );
  },
);

resolverTest(
  "imported type constructors retain their nominal method owner",
  async (compiler) => {
    const sources: Record<string, string> = {
      "/main.blot": `import * as boxes from "./box"
import { Box as Wrapped } from "./box"
const try = monad Wrapped
const sequence = fn () => do try:
  use value <- #boxes.Box 40
  return value + 2
entry const answer = fn () => do:
  let #boxes.Box value = sequence ()
  return value
entry const expected = answer ()
`,
      "/box.blot": `type Box a is data = #Box a
const Box.pure = fn value => #Box value
const Box.bind = fn candidate => fn next => case candidate of
  #Box value => next value
`,
    };
    const project = await loadSourceProject(new URL("file:///main.blot"), {
      readSource: (url) => Promise.resolve(sources[url.pathname]),
    });
    const artifact = await compiler.compile(project);
    const instance = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.bytes),
    );
    equal((instance.exports.answer as CallableFunction)(0), 42);
    equal((instance.exports.expected as WebAssembly.Global).value, 42);
  },
);

resolverTest(
  "monad can be shadowed without changing do syntax",
  async (compiler) => {
    await evaluate(
      compiler,
      `
type Reader is effect = { ask: Unit -> U32 }
const monad = fn ignored => @effect.provider Reader.ask (fn () => 42)
entry const answer = fn () => do (monad Maybe):
  use value <- Reader.ask ()
  return value
`,
      42,
    );
  },
);

resolverTest(
  "existing effect providers retain iterative loops",
  async (compiler) => {
    const artifact = await compiler.compile(`
type Reader is effect = { ask: Unit -> U32 }
const reader = @effect.provider Reader.ask (fn () => 42)
entry const answer = fn () => do reader:
  let total = 0
  for index in 0 .. 100000:
    use value <- Reader.ask ()
    total := self + value
  return total
`);
    const instance = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.bytes),
    );
    equal((instance.exports.answer as CallableFunction)(0), 4200000);
  },
);

resolverTest(
  "invalid resolver inputs and forwarding boundaries are rejected",
  async (compiler) => {
    for (
      const [source, code] of [
        ["entry const answer = monad 42", "type_constructor_required"],
        ["entry const answer = do 42:\n  return 1", "invalid_provider"],
        ["entry const answer = do:\n  return $ #Some 1", "resolver_required"],
        [
          "entry const answer = do monad Maybe:\n  return $ 42",
          "type_mismatch",
        ],
        [
          "entry const answer = do monad Maybe:\n  return do:\n    return $ #Some 1",
          "resolver_required",
        ],
        [
          "type R is effect = { read: Unit -> U32 }\nentry const answer = do (@effect.provider R.read (fn () => 1)):\n  return $ #Some 1",
          "resolver_required",
        ],
      ]
    ) {
      await rejects(async () => await compiler.compile(source), (error) => {
        ok(error instanceof SourceError);
        equal(error.code, code, error.message);
        return true;
      });
    }
  },
);
