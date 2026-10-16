import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("inferred named member aliases retain their dictionary abstraction", async () => {
  await compileAndRun(
    `type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = fn value => value }
impl Flag : Render Bool = { const show = fn value => if value then 7 else 9 }
const helper = Render.show
const render: forall [a] where { Render a } => a -> U32 = fn value => helper value
const both: (forall [a] where { Render a } => a -> U32) -> U32 = fn callback => @u32.add (callback 42) (callback #True)
entry const answer: Unit -> U32 = fn () => both render
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("operation aliases remain values and execute only when invoked", async () => {
  await compileAndRun(
    `effect Read: Unit -> U32
const alias = Read
entry const answer = fn (host: Unit -> U32 ! {Foreign}) => do:
  let provider = @effect.provider Read host
  return do provider:
    return @u32.add (alias ()) (alias ())
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
impl Number : Render U32 = { const sum = fn left => fn right => @u32.add left right }
impl Flag : Render Bool = { const sum = fn left => fn right => if left then (if right then 14 else 16) else 18 }
const helper = Render.sum
const apply = fn callback => fn value => callback value
const render: forall [a] where { Render a } => a -> a -> U32 = fn left => fn right => apply (helper left) right
const both: (forall [a] where { Render a } => a -> a -> U32) -> U32 = fn callback => @u32.add (callback 20 22) (callback #True #False)
entry const answer: Unit -> U32 = fn () => both render
`,
    (guest) => equal(guest.call("answer", null), 58),
    { prelude: "none" },
  );
});

Deno.test("associated member aliases preserve opaque result witnesses", async () => {
  await compileAndRun(
    `type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
impl Number : Source U32 = { type Item = U32, const get = fn value => value, const show = fn owner => fn value => value }
impl Flag : Source Bool = { type Item = Bool, const get = fn value => value, const show = fn owner => fn value => if value then 7 else 9 }
const helper = Source.get
const render: forall [a] where { Source a } => a -> U32 = fn value => Source.show value (helper value)
const both: (forall [a] where { Source a } => a -> U32) -> U32 = fn callback => @u32.add (callback 42) (callback #True)
entry const answer: Unit -> U32 = fn () => both render
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("ordinary inferred helpers retain projected public result signatures", async () => {
  await compileAndRun(
    `type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
impl Number : Source U32 = { type Item = U32, const get = fn value => value, const show = fn owner => fn value => value }
impl Flag : Source Bool = { type Item = Bool, const get = fn value => value, const show = fn owner => fn value => if value then 7 else 9 }
const helper = fn value => Source.get value
const render: forall [a] where { Source a } => a -> U32 = fn value => Source.show value (helper value)
const both: (forall [a] where { Source a } => a -> U32) -> U32 = fn callback => @u32.add (callback 42) (callback #True)
entry const answer: Unit -> U32 = fn () => both render
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("member alias references and partial values cannot escape opened dictionary witnesses", async () => {
  for (const body of ["fn unit => helper value", "partial value"]) {
    await compileExpectedFailure(
      `type Render a is contract = { const show: a -> U32 }
const helper = Render.show
const partial = fn left => fn (unit: Unit) => helper left
type Item = exists [a] where { Render a } => a
const escape = fn (item: Item) => unpack item as [a] value in ${body}
entry const answer = fn () => 42
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
      source + "\nentry const answer = fn () => 42\n",
      "usage_evidence_mismatch",
      undefined,
      { prelude: "none" },
    );
  }
});
