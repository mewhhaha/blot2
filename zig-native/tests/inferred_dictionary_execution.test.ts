import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

const declarations = `type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = func value => return value }
impl Flag : Render Bool = { const show = func value => return if value then 7 else 9 }
const helper = func value => return Render.show value
`;

Deno.test("inferred helper requirements receive their caller's stored dictionary", async () => {
  await compileAndRun(
    declarations +
      `const render: forall [a] where { Render a } => a -> U32 = func value => return helper value
const both: (forall [a] where { Render a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
entry const answer: Unit -> U32 = func () => return both render
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("transitive inferred helpers forward the same owned goal", async () => {
  await compileAndRun(
    declarations +
      `const middle = func value => return helper value
const render: forall [a] where { Render a } => a -> U32 = func value => return middle value
const both: (forall [a] where { Render a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
entry const answer: Unit -> U32 = func () => return both render
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("curried inferred helpers retain a dictionary during the remaining application", async () => {
  await compileAndRun(
    declarations +
      `const sum = func left => return func right => return @u32.add (helper left) (helper right)
const render: forall [a] where { Render a } => a -> a -> U32 = func left => return func right => return sum left right
const both: (forall [a] where { Render a } => a -> a -> U32) -> U32 = func callback => return @u32.add (callback 20 22) (callback true false)
entry const answer: Unit -> U32 = func () => return both render
`,
    (guest) => equal(guest.call("answer", null), 58),
    { prelude: "none" },
  );
});

Deno.test("inferred helper references retain evidence through unknown callable parameters", async () => {
  await compileAndRun(
    declarations +
      `const apply = func callback => return func value => return callback value
const render: forall [a] where { Render a } => a -> U32 = func value => return apply helper value
const both: (forall [a] where { Render a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
entry const answer: Unit -> U32 = func () => return both render
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("inferred partial helper values retain dictionaries as ordinary closure captures", async () => {
  await compileAndRun(
    declarations +
      `const apply = func callback => return func value => return callback value
const sum = func left => return func right => return @u32.add (helper left) (helper right)
const render: forall [a] where { Render a } => a -> a -> U32 = func left => return func right => return apply (sum left) right
const both: (forall [a] where { Render a } => a -> a -> U32) -> U32 = func callback => return @u32.add (callback 20 22) (callback true false)
entry const answer: Unit -> U32 = func () => return both render
`,
    (guest) => equal(guest.call("answer", null), 58),
    { prelude: "none" },
  );
});

Deno.test("inferred helper references and partial applications cannot escape opening witnesses", async () => {
  for (const body of ["func unit => return helper value", "sum value"]) {
    await compileExpectedFailure(
      declarations +
        `type Item = exists [a] where { Render a } => a
const sum = func left => return func (unit: Unit) => return helper left
const escape = func (item: Item) => return unpack item as [a] value in ${body}
entry const answer = func () => return 42
`,
      "package_escape",
      undefined,
      { prelude: "none" },
    );
  }
});

Deno.test("inferred helper dictionaries preserve abstract associated results", async () => {
  await compileAndRun(
    `type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
impl Number : Source U32 = { type Item = U32, const get = func value => return value, const show = func owner => return func value => return value }
impl Flag : Source Bool = { type Item = Bool, const get = func value => return value, const show = func owner => return func value => return if value then 7 else 9 }
const helper = func value => return Source.show value (Source.get value)
const render: forall [a] where { Source a } => a -> U32 = func value => return helper value
const both: (forall [a] where { Source a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
entry const answer: Unit -> U32 = func () => return both render
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("inferred helper dictionaries match reordered goals with distinct witness arguments", async () => {
  await compileAndRun(
    declarations +
      `const sum = func left => return func right => return @u32.add (Render.show right) (Render.show left)
const render: forall [a, b] where { Render a, Render b } => a -> b -> U32 = func left => return func right => return sum left right
const both: (forall [a, b] where { Render a, Render b } => a -> b -> U32) -> U32 = func callback => return @u32.add (callback 42 true) (callback true 42)
entry const answer: Unit -> U32 = func () => return both render
`,
    (guest) => equal(guest.call("answer", null), 98),
    { prelude: "none" },
  );
});

Deno.test("inferred helpers forward structurally instantiated contract arguments", async () => {
  await compileAndRun(
    `type Render a is contract = { const show: a -> U32 }
impl Numbers : Render (Array U32) = { const show = func values => return @array.get values 0 }
impl Flags : Render (Array Bool) = { const show = func values => return if (@array.get values 0) then 7 else 9 }
const helper = func value => return Render.show value
const render: forall [a] where { Render (Array a) } => (Array a) -> U32 = func values => return helper values
const both: (forall [a] where { Render (Array a) } => (Array a) -> U32) -> U32 = func callback => return @u32.add (callback #[42]) (callback #[true])
entry const answer: Unit -> U32 = func () => return both render
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("helper forwarding cannot choose a phantom witness from unrelated active goals", async () => {
  await compileExpectedFailure(
    `type Tag a is contract = { const read: Unit -> U32 }
impl Number : Tag U32 = { const read = func unit => return 42 }
impl Flag : Tag Bool = { const read = func unit => return 7 }
const helper: forall [a] where { Tag a } => Unit -> U32 = func unit => return Tag.read unit
const render: forall [a, b] where { Tag a, Tag b } => a -> b -> U32 = func left => return func right => return helper ()
const both: (forall [a, b] where { Tag a, Tag b } => a -> b -> U32) -> U32 = func callback => return callback 42 true
entry const answer: Unit -> U32 = func () => return both render
`,
    "ambiguous_qualified",
    undefined,
    { prelude: "none" },
  );
});
