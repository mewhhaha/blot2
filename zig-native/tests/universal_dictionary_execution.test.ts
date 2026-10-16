import { compileAndRun, equal } from "./compile_helpers.ts";

const declarations = `type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = fn value => value }
impl Flag : Render Bool = { const show = fn value => if value then 7 else 9 }
const render: forall [a] where { Render a } => a -> U32 = fn value => Render.show value
`;

Deno.test("universal predicate methods specialize closed calls", async () => {
  await compileAndRun(
    declarations +
      `entry const answer: U32 -> U32 = fn value => render value\n`,
    (guest) => equal(guest.call("answer", 42), 42),
    { prelude: "none" },
  );
});

Deno.test("stored universal dictionaries select each actual caller witness", async () => {
  await compileAndRun(
    declarations +
      `const both: (forall [a] where { Render a } => a -> U32) -> U32 = fn callback => @u32.add (callback 42) (callback #True)
entry const answer: Unit -> U32 = fn () => both render
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("universal dictionaries survive dynamic product selection", async () => {
  await compileAndRun(
    declarations +
      `const alternate: forall [a] where { Render a } => a -> U32 = fn value => @u32.add (Render.show value) 1
const choose: Bool -> (forall [a] where { Render a } => a -> U32) = fn flag => if flag then render else alternate
const both: (forall [a] where { Render a } => a -> U32) -> U32 = fn callback => @u32.add (callback 42) (callback #True)
entry const answer: Bool -> U32 = fn flag => both (choose flag)
`,
    (guest) => {
      equal(guest.call("answer", true), 49);
      equal(guest.call("answer", false), 51);
    },
    { prelude: "none" },
  );
});

Deno.test("curried universal dictionaries retain their evidence after partial application", async () => {
  await compileAndRun(
    declarations +
      `const sum: forall [a] where { Render a } => a -> a -> U32 = fn left => fn right => @u32.add (Render.show left) (Render.show right)
const both: (forall [a] where { Render a } => a -> a -> U32) -> U32 = fn callback => @u32.add (callback 20 22) (callback #True #False)
entry const answer: Unit -> U32 = fn () => both sum
`,
    (guest) => equal(guest.call("answer", null), 58),
    { prelude: "none" },
  );
});

Deno.test("anonymous universal dictionaries retain ordinary captured values", async () => {
  await compileAndRun(
    declarations +
      `const both: (forall [a] where { Render a } => a -> U32) -> U32 = fn callback => @u32.add (callback 42) (callback #True)
entry const answer: U32 -> U32 = fn offset => both (fn value => @u32.add offset (Render.show value))
`,
    (guest) => equal(guest.call("answer", 10), 69),
    { prelude: "none" },
  );
});

Deno.test("universal dictionary methods forward through a qualified helper", async () => {
  await compileAndRun(
    declarations +
      `const forward: forall [a] where { Render a } => a -> U32 = fn value => render value
const both: (forall [a] where { Render a } => a -> U32) -> U32 = fn callback => @u32.add (callback 42) (callback #True)
entry const answer: Unit -> U32 = fn () => both forward
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});
