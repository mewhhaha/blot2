import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

const declarations = `type Tag a is contract = { const read: Unit -> U32 }
impl Number : Tag U32 = { const read = func unit => return 42 }
type Item = exists [a] where { Tag a } => Unit
type Sealed = exists [b] => Unit -> U32
const make = func (unit: Unit) => return pack [U32] unit as Item
`;

Deno.test("closed dictionary method signatures retain their opening goal", async () => {
  for (
    const body of [
      "Tag.read",
      "func (unit: Unit) => return Tag.read unit",
      "(Tag.read, 7)",
      "pack [U32] Tag.read as Sealed",
    ]
  ) {
    await compileExpectedFailure(
      `${declarations}const escape = func (item: Item) => return unpack item as [a] value in ${body}\nentry const answer = func () => return 42\n`,
      "package_escape",
      undefined,
      { prelude: "none" },
    );
  }
});

Deno.test("closed dictionary calls and exact witness resealing execute", async () => {
  await compileAndRun(
    `${declarations}const read = func (item: Item) => return unpack item as [a] value in Tag.read ()
const keep = func (item: Item) => return unpack item as [a] value in pack [a] Tag.read as Sealed
const invoke = func (sealed: Sealed) => return unpack sealed as [b] callback in callback ()
entry const answer = func () => return @u32.add (read (make ())) (invoke (keep (make ())))
`,
    (guest) => equal(guest.call("answer", null), 84),
    { prelude: "none" },
  );
});
