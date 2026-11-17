import { strict as assert } from "node:assert";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
import { resultCases } from "./result_cases.ts";
import { decodeText } from "../../host/text.ts";

Deno.test("written result interfaces select the destination through aliases contracts and local templates", async () => {
  await compileAndRun(
    `
type Box a is data = $Box a
const Box.from = func value => return $Box value
type Convert (a, b) is contract = { result "from" a b }
const convert: a -> b where { result "from" a b } = func value => return @type.result "from" value
const alias: a -> b where { Convert (a, b) } = convert
entry const answer = func () => return do:
  let local: a -> b where { result "from" a b ! {} } = alias
  let $Box first: Box U32 = local 40
  let $Box second: Box F32 = local 2.5
  break @u32.add first (@f32.to_u32 second)
`,
    (guest) => equal(guest.call("answer", null), 42),
    { prelude: "none" },
  );
  await compileAndRun(
    `
const convert: a -> b where { result "from" a b } = func value => return @type.result "from" value
entry const answer = func () => return @u32.add (convert (floor 40.5)) (convert (ceil 1.5))
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
});

// Pending the traits redesign (tasks/LANGUAGE_COHERENCE.md C).
Deno.test.ignore("written result interfaces propagate selected effects and reject missing or incompatible evidence", async () => {
  const header = `
type Read is effect = Unit -> U32
type Box is data = $Box U32
const Box.from: Unit -> Box ! {Read} = func () => return do:
  use value <- Read ()
  break $Box value
const convert: a -> b ! {|e} where { result "from" a b ! {|e} } = func value => return @type.result "from" value
`;
  await compileAndRun(
    header + `
entry const answer = func () => return do (@effect.provider Read (func () => return 42)):
  use box: Box <- convert ()
  let $Box value = box
  break value
`,
    (guest) => equal(guest.call("answer", null), 42),
    { prelude: "none" },
  );
  await compileAndRun(
    `
type Tick is effect = Unit -> Unit
type Box is data = $Box U32
const Box.from = func (value: U32) => return $Box value
const convert: a -> b ! {Tick} where { result "from" a b ! {} } = func value => return do:
  use Tick ()
  break @type.result "from" value
entry const answer = func () => return do (@effect.provider Tick (func () => return ())):
  use box: Box <- convert 42
  let $Box value = box
  break value
`,
    (guest) => equal(guest.call("answer", null), 42),
    { prelude: "none" },
  );
  await compileExpectedFailure(
    `
type Source is data = $Source U32
type Target is data = $Target U32
const Source.from = func value => return $Target 42
const convert: a -> b where { result "from" a b } = func value => return @type.result "from" value
entry const answer: Target = convert ($Source 1)
`,
    "missing_associated",
    undefined,
    { prelude: "none" },
  );
  await compileExpectedFailure(
    `
type Target is data = $Target U32
const Target.from = func (value: F32) => return $Target 42
const convert: a -> b where { result "from" a b } = func value => return @type.result "from" value
entry const answer: Target = convert 1
`,
    "type_mismatch",
    undefined,
    { prelude: "none" },
  );
  await compileExpectedFailure(
    header.replace(
      'result "from" a b ! {|e}',
      'result "from" a b ! {}',
    ) + `
entry const answer = func () => return do (@effect.provider Read (func () => return 42)):
  use box: Box <- convert ()
  let $Box value = box
  break value
`,
    "effect_mismatch",
    undefined,
    { prelude: "none" },
  );
});

Deno.test("staged nested conversions infer their destination from the surrounding operator", async () => {
  await compileAndRun(
    `
const count = 42
entry const answer: U32 = from (ceil (sqrt (from count))) + 2
entry const floating: F32 = from (ceil (sqrt (from count))) + 2.5
`,
    (guest) => {
      equal(guest.read("answer"), 9);
      equal(guest.read("floating"), 9.5);
    },
    {
      prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
    },
  );
});

Deno.test("an operator supplies the expected type of a conversion on either side", async () => {
  const source = await Deno.readTextFile(new URL(
    "../../compiler-goose/tests/fixtures/result_selected_operand.blot",
    import.meta.url,
  ));
  await compileAndRun(
    source,
    (guest) => {
      equal(guest.call("normalized", 42), 21);
      equal(guest.call("matches", 21), true);
      equal(guest.call("matches", 20), false);
      equal(guest.call("scaled", 4), 171);
      equal(guest.call("caller_selects", 38), 4240);
    },
  );
});

Deno.test("a competing conversion leaves the destination open until the caller constrains it", async () => {
  const overload = `
type Other is data = $Other U32
func Other.from (value: U32): Other => return $Other value
func Other.add ($Other value) -> (right: U32): U32 => return U32.add value (U32.mul right 2)
`;
  await compileExpectedFailure(
    overload + "entry func answer (value: U32) => return from value + 2\n",
    "entry_type",
  );
  await compileAndRun(
    overload + `
entry func answer (value: U32): U32 => return do:
  let converted: Other = from value
  return converted + 2
entry func floating (value: U32) => return 2.0 + from value
`,
    (guest) => {
      equal(guest.call("answer", 38), 42);
      equal(guest.call("floating", 40), 42);
    },
  );
});

Deno.test("staged constants keep primitive calls, operators and saturating conversions", async () => {
  await compileAndRun(
    `
entry const direct = U32.add 40 2
entry const associated = @type.call "add" 40 2
entry const float_associated = @type.call "add" 1.5 2.5
entry const integer_operator = 6 * 7
entry const float_operator = 1.5 * 2.0
entry const infinite = 1.0 / 0.0
entry const saturated: U32 = from (sqrt (-1.0))
entry const divide = func (divisor: U32): U32 => return 42 / divisor
`,
    (guest) => {
      for (const name of ["direct", "associated", "integer_operator"]) {
        equal(guest.read(name), 42);
      }
      equal(guest.read("float_associated"), 4);
      equal(guest.read("float_operator"), 3);
      equal(guest.read("infinite"), Infinity);
      equal(guest.read("saturated"), 0);
      assert.throws(() => guest.call("divide", 0), WebAssembly.RuntimeError);
      equal(guest.call("divide", 7), 6);
    },
    {
      prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
    },
  );
});

// Constants run at instantiation, so a constant division by zero traps there.
Deno.test("selected primitive aliases trap on constant integer division by zero", async () => {
  await assert.rejects(
    compileAndRun(`entry const answer = @type.call "div" 42 0\n`, () => {}),
    WebAssembly.RuntimeError,
  );
});

Deno.test("ordinary text values compile while intrinsic validation keeps its literal rule", async () => {
  await compileAndRun(
    `const name = "from"\nentry const answer = func () => return name\n`,
    (guest) => {
      equal(decodeText(guest.call("answer", null) as Uint32Array), "from");
    },
  );
  await compileExpectedFailure(
    `const name: String = "from"\nentry const answer = 42\n`,
    "unsupported_type",
  );
  await compileExpectedFailure(
    `const name = "from"\nentry const answer = @type.result name 42\n`,
    "literal_required",
  );
});

for (const item of resultCases) {
  if (!("expected" in item)) continue;
  Deno.test(`native expected-result dispatch preserves ${item.name}`, async () => {
    await compileAndRun(item.source, (guest) => {
      for (const [name, expected] of Object.entries(item.expected)) {
        equal(
          guest.abi.constants.some((value) => value.name === name)
            ? guest.read(name)
            : guest.call(name, null),
          expected,
        );
      }
    });
  });
}

Deno.test("native expected-result dispatch rejects selected mismatches and invalid primitive syntax", async () => {
  for (const item of resultCases) {
    if (!("error" in item)) continue;
    // Direct backend: ambiguous_associated for a `from` with no expected type (tasks/DELETE_SCOPED.md).
    if (item.name === "ambiguous_destination") continue;
    await compileExpectedFailure(item.source, item.error);
  }
});
