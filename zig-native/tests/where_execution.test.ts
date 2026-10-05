import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
const compiler = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;

Deno.test("qualified aliases and local templates instantiate separate concrete evidence", async () => {
  await compileAndRun(
    `
const twice: a -> a where { associated "add" a a a } = fn value => value + value
const alias = twice
entry const answer = fn () => do:
  let local = alias
  let integer = local 20
  let choose: a -> a where { type_rep a } = fn value => value
  return @u32.add (choose integer) (@f32.to_u32 (local (choose 1.0)))
`,
    (guest) => equal(guest.call("answer", null), 42),
    { prelude },
  );
});

Deno.test("qualified fields receivers and updates prove physical and selected members", async () => {
  await compileAndRun(
    `
type Box a is data = #Box { value: a }
const Box.plus = fn (box: Box U32) => fn (amount: U32) => @u32.add box.value amount
const first: a -> b where { field "value" a b } = fn box => box.value
const bind: a -> (U32 -> U32) where { receiver "plus" a Unit (U32 -> U32) } = fn box => box.plus
const replace: a -> b -> c where { update "value" a b c } = fn box => fn value => do:
  let current = box
  current.value := value
  return current
entry const answer = fn () => @u32.add (first (#Box { value: 20 })) ((bind (#Box { value: 20 })) 2)
entry const changed = fn () => do:
  let #Box { value } = replace (#Box { value: 20 }) 42.0
  return value
`,
    (guest) => {
      equal(guest.call("answer", null), 42);
      equal(guest.call("changed", null), 42);
    },
  );
});

Deno.test("qualified operation arguments share written open row identities", async () => {
  await compileAndRun(
    `
type Signal a is effect = { get: Unit -> a }
const read: Unit -> a ! {| e} where { operation Signal.get a } = fn () => Signal.get a ()
const invoke: (Unit -> a ! {| e}) -> a ! {| e} where { type_rep a, effect_rep ! {| e} } = fn callback => callback ()
entry const answer = fn () -> U32 => do (@effect.provider (Signal.get U32) (fn () => 42)):
  return invoke (fn () => read ())
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
});

Deno.test("predicate-only variables and closed extra clauses narrow reached schemes", async () => {
  await compileAndRun(
    `
const identity: U32 -> U32 where { associated "add" U32 U32 a } = fn value => value
const unused: a -> a where { associated "missing" a a a } = fn value => value
entry const answer = fn () => do:
  let increment: U32 -> U32 where { associated "add" F32 F32 F32 ! {} } = fn value => value + 1
  return identity (increment 41)
entry const number: U32 where { type_rep U32 } = 42
entry let runtime: U32 where { effect_rep ! {} } = 7
`,
    (guest) => {
      equal(guest.call("answer", null), 42);
      equal(guest.read("number"), 42);
      equal(guest.read("runtime"), 7);
    },
    { prelude },
  );
});

Deno.test("written clauses reject malformed shapes missing body coverage and parameter clauses", async () => {
  for (
    const [source, code] of [
      [
        "entry const answer: U32 where { mystery U32 } = 42\n",
        "invalid_constraint",
      ],
      [
        'entry const answer: U32 where { associated "add" U32 U32 } = 42\n',
        "invalid_constraint",
      ],
      [
        'entry const answer: U32 where { field "x" U32 U32 ! {} } = 42\n',
        "invalid_constraint",
      ],
      [
        "entry const answer = fn (callback: U32 -> U32 where {}) => 42\n",
        "higher_rank_constraint",
      ],
      [
        "const twice: a -> a where {} = fn value => value + value\nentry const answer = 42\n",
        "missing_predicate",
      ],
      [
        "const identity: e -> e where { effect_rep ! {| e} } = fn value => value\nentry const answer = 42\n",
        "annotation_kind_mismatch",
      ],
      [
        "type Signal a is effect = {get: Unit -> a}\nentry const answer: U32 where {operation Signal.get} = 42\n",
        "effect_arity",
      ],
    ]
  ) await compileExpectedFailure(source, code);
});

Deno.test("reached extra clauses require exact concrete type and effect evidence", async () => {
  for (
    const source of [
      'entry const answer: U32 where { associated "missing" Bool Bool Bool } = 42\n',
      'entry const answer: Unit -> U32 where { associated "missing" Bool Bool Bool } = fn () => 42\n',
      'entry let answer: U32 where { associated "missing" Bool Bool Bool } = 42\n',
    ]
  ) await compileExpectedFailure(source, "missing_associated");
  await compileExpectedFailure(
    `
const identity: a -> a where { effect_rep ! {| e} } = fn value => value
entry const answer = fn () => identity 42
`,
    "ambiguous_qualified",
  );
  await compileExpectedFailure(
    `
type Tick is effect = Unit -> Unit
const identity: a -> a where { associated "add" U32 U32 U32 ! {Tick} } = fn value => value
const alias = identity
entry const answer = fn () => alias 42
`,
    "effect_mismatch",
    undefined,
    { prelude },
  );
});

Deno.test("qualified computed values retain one evidence instance", async () => {
  const header =
    'const twice: a -> a where { associated "add" a a a } = fn value => value + value\n';
  const selected = `entry const answer = fn () => do:
  let selected = case #True of
    #True => twice
    #False => twice
`;
  await compileAndRun(
    header + selected + "  return selected 21\n",
    (guest) => equal(guest.call("answer", null), 42),
    { prelude },
  );
  await compileExpectedFailure(
    header + selected +
      "  return @f32.add (@u32.to_f32 (selected 21)) (selected 1.5)\n",
    "type_mismatch",
    undefined,
    { prelude },
  );
});

Deno.test("qualified imports preserve representation predicates and callback row sharing", async () => {
  const directory = await Deno.makeTempDir({
    dir: new URL("../../build", import.meta.url).pathname,
    prefix: "zig-native-where-import-",
  });
  try {
    const library = `${directory}/library.blot`;
    await Deno.writeTextFile(
      library,
      "const invoke: (Unit -> a ! {| e}) -> a ! {| e} where { type_rep a, effect_rep ! {} } = fn callback => callback ()\n",
    );
    const main = `${directory}/main.blot`;
    const output = `${directory}/program.wasm`;
    await Deno.writeTextFile(
      main,
      `import { invoke } from "./library"
type Read is effect = Unit -> U32
const pure_callback: Unit -> U32 = fn () => 37
const read_callback: Unit -> U32 ! {Read} = fn () => Read ()
entry const pure = fn () => invoke pure_callback
entry const answer = fn () => do (@effect.provider Read (fn () => 42)):
  return invoke read_callback
`,
    );
    const result = await new Deno.Command(compiler, {
      args: ["build-project", main, output],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const text = new TextDecoder().decode(result.stdout);
    if (!result.success) {
      throw new Error(text + new TextDecoder().decode(result.stderr));
    }
    equal(JSON.parse(text.trim().split("\n").at(-1)!).memory.live_bytes, 0);
    const bytes = await Deno.readFile(output);
    equal(WebAssembly.validate(bytes), true);
    const guest = await instantiateGuest(bytes);
    try {
      equal(guest.call("pure", null), 37);
      equal(guest.call("answer", null), 42);
    } finally {
      guest.dispose();
    }
    await Deno.writeTextFile(
      library,
      "const invoke: (Unit -> a ! {| e}) -> a ! {| e} where { type_rep a, effect_rep ! {| e} } = fn callback => callback ()\n",
    );
    await Deno.writeTextFile(
      main,
      `import {invoke} from "./library"
entry const answer = fn () => invoke (fn () => 42)
`,
    );
    const rejected = await new Deno.Command(compiler, {
      args: ["build-project", main, `${directory}/rejected.wasm`],
      stdout: "piped",
      stderr: "piped",
    }).output();
    equal(rejected.success, false);
    const records = new TextDecoder().decode(rejected.stdout).trim().split("\n")
      .map((line) => JSON.parse(line));
    equal(
      records.find((record) => record.kind === "diagnostic").code,
      "ambiguous_qualified",
    );
    equal(records.at(-1).memory.live_bytes, 0);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
