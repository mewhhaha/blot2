import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("inferred named member aliases retain their dictionary abstraction", async () => {
  await compileAndRun(
    `type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = func value => return value }
impl Flag : Render Bool = { const show = func value => return if value then 7 else 9 }
const helper = Render.show
const render: forall [a] where { Render a } => a -> U32 = func value => return helper value
const both: (forall [a] where { Render a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
entry const answer: Unit -> U32 = func () => return both render
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("operation aliases remain values and execute only when invoked", async () => {
  await compileAndRun(
    `effect Read: Unit -> U32
const alias = Read
entry const answer = func (host: Unit -> U32 ! {Foreign}) => return do:
  let provider = @effect.provider Read host
  break do provider:
    break @u32.add (alias ()) (alias ())
`,
    (guest) => {
      let calls = 0;
      equal(
        guest.call(
          "answer",
          guest.capability({
            parameter: "Unit",
            result: "U32",
            call: () => ++calls,
          }),
        ),
        3,
      );
      equal(calls, 2);
    },
    { prelude: "none" },
  );
});

Deno.test("curried member aliases support partial values through unknown callables", async () => {
  await compileAndRun(
    `type Render a is contract = { const sum: a -> a -> U32 }
impl Number : Render U32 = { const sum = func left => return func right => return @u32.add left right }
impl Flag : Render Bool = { const sum = func left => return func right => return if left then (if right then 14 else 16) else 18 }
const helper = Render.sum
const apply = func callback => return func value => return callback value
const render: forall [a] where { Render a } => a -> a -> U32 = func left => return func right => return apply (helper left) right
const both: (forall [a] where { Render a } => a -> a -> U32) -> U32 = func callback => return @u32.add (callback 20 22) (callback true false)
entry const answer: Unit -> U32 = func () => return both render
`,
    (guest) => equal(guest.call("answer", null), 58),
    { prelude: "none" },
  );
});

Deno.test("associated member aliases preserve opaque result witnesses", async () => {
  await compileAndRun(
    `type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
impl Number : Source U32 = { type Item = U32, const get = func value => return value, const show = func owner => return func value => return value }
impl Flag : Source Bool = { type Item = Bool, const get = func value => return value, const show = func owner => return func value => return if value then 7 else 9 }
const helper = Source.get
const render: forall [a] where { Source a } => a -> U32 = func value => return Source.show value (helper value)
const both: (forall [a] where { Source a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
entry const answer: Unit -> U32 = func () => return both render
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("ordinary inferred helpers retain projected public result signatures", async () => {
  await compileAndRun(
    `type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
impl Number : Source U32 = { type Item = U32, const get = func value => return value, const show = func owner => return func value => return value }
impl Flag : Source Bool = { type Item = Bool, const get = func value => return value, const show = func owner => return func value => return if value then 7 else 9 }
const helper = func value => return Source.get value
const render: forall [a] where { Source a } => a -> U32 = func value => return Source.show value (helper value)
const both: (forall [a] where { Source a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
entry const answer: Unit -> U32 = func () => return both render
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("member alias references and partial values cannot escape opened dictionary witnesses", async () => {
  for (const body of ["func unit => return helper value", "partial value"]) {
    await compileExpectedFailure(
      `type Render a is contract = { const show: a -> U32 }
const helper = Render.show
const partial = func left => return func (unit: Unit) => return helper left
type Item = exists [a] where { Render a } => a
const escape = func (item: Item) => return unpack item as [a] value in ${body}
entry const answer = func () => return 42
`,
      "package_escape",
      undefined,
      { prelude: "none" },
    );
  }
});

Deno.test("associated type equations cannot erase direct or opaque shared ownership", async () => {
  for (
    const source of [
      `type Source a is contract = { type Item }
impl Number : Source U32 = { type Item = unique U32 }`,
      `opaque type Hidden = shared U32
type Source a is contract = { type Item }
impl Number : Source U32 = { type Item = Hidden }`,
      `type Hidden is data = #Hidden (shared U32)
type Source a is contract = { type Item = Hidden }`,
    ]
  ) {
    await compileExpectedFailure(
      source + "\nentry const answer = func () => return 42\n",
      "usage_evidence_mismatch",
      undefined,
      { prelude: "none" },
    );
  }
});
