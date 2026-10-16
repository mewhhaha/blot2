import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("repacked dictionaries follow exact runtime witnesses", async () => {
  await compileAndRun(
    `type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = fn value => value }
impl Flag : Render Bool = { const show = fn value => if value then 7 else 9 }
type Item = exists [a] where { Render a } => a
const make = fn (flag: Bool) => if flag then pack [U32] 42 as Item else pack [Bool] #True as Item
const reseal = fn (item: Item) => unpack item as [a] value in pack [a] value as Item
const choose = fn (left: Item) => fn (right: Item) => unpack left as [a] x in unpack right as [b] y in pack [b] y as Item
const read = fn (item: Item) => unpack item as [a] value in Render.show value
entry const answer = fn (flag: Bool) => @u32.add (read (reseal (make flag))) (read (reseal (make flag)))
entry const selected = fn (flag: Bool) => read (choose (make flag) (make #False))
entry const snapshot = fn (value: U32) => #[value]
`,
    (guest, bytes) => {
      equal(guest.call("answer", true), 84);
      equal(guest.call("answer", false), 14);
      equal(guest.call("selected", true), 7);
      equal(guest.call("selected", false), 7);
      const raw =
        new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
      const enter = raw["blot:ownership_enter"] as CallableFunction;
      const leave = raw["blot:ownership_leave"] as CallableFunction;
      const invoke = raw.answer as CallableFunction;
      const memory = raw["blot:memory"] as WebAssembly.Memory;
      let warmed = 0;
      for (let i = 0; i < 96; i++) {
        enter();
        equal(invoke(i % 2), 14 + (i % 2) * 70);
        leave(0);
        for (const name of ["roots", "leases"]) {
          equal(
            Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value),
            0,
          );
        }
        if (i === 8) warmed = memory.buffer.byteLength;
        if (i > 8) equal(memory.buffer.byteLength, warmed);
      }
    },
    { prelude: "none" },
  );
});

Deno.test("universal givens can seal existential dictionaries", async () => {
  await compileAndRun(
    `type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = fn value => value }
impl Flag : Render Bool = { const show = fn value => if value then 7 else 9 }
type Item = exists [a] where { Render a } => a
const seal: forall [a] where { Render a } => a -> Item = fn value => pack [a] value as Item
const read = fn (item: Item) => unpack item as [a] value in Render.show value
entry const answer = fn () => @u32.add (read (seal 42)) (read (seal #True))
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("dictionary resealing rejects changed witnesses and unsealed method captures", async () => {
  const source = `type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = fn value => value }
type Item = exists [a] where { Render a } => a
const make = fn (value: U32) => pack [U32] value as Item
const bad = fn (item: Item) => unpack item as [a] value in pack [U32] value as Item
entry const answer = fn () => bad (make 42)
`;
  await compileExpectedFailure(source, "type_mismatch", undefined, {
    prelude: "none",
  });
  await compileExpectedFailure(
    source.replace("pack [U32] value as Item\nentry", "Render.show\nentry"),
    "package_escape",
    undefined,
    { prelude: "none" },
  );
});
