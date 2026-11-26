import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("unary associated members apply the receiver once and preserve curried results", async () => {
  await compileAndRun(`
type Box value is data = $Box { value: value }
const Box.get = func (self: Box value) => return self.value
const Box.add = func (self: Box U32) => return func (extra: U32) => return @u32.add self.value extra
const access = func self => return self.add
const read = func self => return self.get
const constant = ($Box { value: 40 }).add 2
io const staged: U32 = constant
io const unary = func (input: U32) : U32 => return read ($Box { value: input })
io const floating = func (input: F32) : F32 => return read ($Box { value: input })
io const curried = func (input: U32) : U32 => return access ($Box { value: input }) 2
io const nested = func (input: U32) : U32 => return ($Box { value: $Box { value: input } }).get.get
`, guest => {
    equal(guest.read("staged"), 42);
    equal(guest.call("unary", 40), 40);
    equal(guest.call("floating", 2.5), 2.5);
    equal(guest.call("curried", 40), 42);
    equal(guest.call("nested", 42), 42);
  });
});

Deno.test("field and method collisions remain errors through generic callers", async () => {
  for (const access of ["($Box { value: 1 }).value", "read ($Box { value: 1 })"]) {
    await compileExpectedFailure(`
type Box is data = $Box { value: U32 }
const Box.value = func self => return 99
const read = func self => return self.value
io const result: U32 = ${access}
`, "ambiguous_member");
  }
});

Deno.test("accessor functions preserve generic fields, members and nested paths", async () => {
  await compileAndRun(`
type Box value is data = $Box { value: value }
const Box.get = func (self: Box value) => return self.value
const get = .get
const read = .value
const nested = .get.value
io const integer = func (input: U32) : U32 => return get ($Box { value: input })
io const floating = func (input: F32) : F32 => return read ($Box { value: input })
io const path = func (input: U32) : U32 => return nested ($Box { value: $Box { value: input } })
io const local = func (input: U32) : U32 => return do:
  let accessor = .value
  break accessor ($Box { value: input })
io const mixed = func () : U32 => return do:
  let accessor = func box => return box.value
  let integer = accessor ($Box { value: 40 })
  let floating = accessor ($Box { value: 2.5 })
  break @u32.add integer (@f32.to_u32 floating)
`, guest => {
    equal(guest.call("integer", 42), 42);
    equal(guest.call("floating", 1.5), 1.5);
    equal(guest.call("path", 42), 42);
    equal(guest.call("local", 42), 42);
    equal(guest.call("mixed", null), 42);
  });
  await compileExpectedFailure(`
type Box value is data = $Box { value: value }
io const mixed = func () : U32 => return do:
  let accessor = .value
  let integer = accessor ($Box { value: 40 })
  let floating = accessor ($Box { value: 2.5 })
  break @u32.add integer (@f32.to_u32 floating)
`, "type_mismatch");
});

Deno.test("writable fields remain distinct from receiver methods", async () => {
  await compileAndRun(`
type Box is data = $Box { value: U32 }
const Box.value = func self => return 99
io const answer = func () : U32 => return do:
  let box = $Box { value: 1 }
  box.value := 42
  break case box of
    $Box { value } => value
`, guest => equal(guest.call("answer", null), 42));
  await compileExpectedFailure(`
type Box is data = $Box U32
const Box.method = func self => return 99
io const answer = func () : U32 => return do:
  let box = $Box 1
  box.method := 42
  break 42
`, "missing_field");
});

Deno.test("runtime generic associated operators preserve independent operand and result types", async () => {
  await compileAndRun(`
type Point is data = $Point { x: U32 }
const Point.add = func (left: Point) => return func (right: U32) => return @u32.add left.x right
const Point.eq = func (left: Point) => return func (right: Point) => return @u32.eq left.x right.x
const combine = func left => return func right => return left + right
const same = func left => return func right => return left == right
io const add = func (value: U32) : U32 => return combine ($Point { x: value }) 22
io const equal = func (value: U32) : Bool => return same ($Point { x: value }) ($Point { x: 42 })
`, guest => {
    equal(guest.call("add", 20), 42);
    equal(guest.call("add", 0xffffffff), 21);
    equal(guest.call("equal", 42), true);
    equal(guest.call("equal", 43), false);
  });
});

Deno.test("ordinary scalar method names do not alter compiler primitives", async () => {
  await compileAndRun(`
const U32.add = func (left: U32) => return func (right: U32) => return @u32.sub left right
io const dispatched = func (value: U32) : U32 => return U32.add value 2
io const primitive = func (value: U32) : U32 => return @u32.add value 2
`, guest => {
    equal(guest.call("dispatched", 44), 42);
    equal(guest.call("primitive", 40), 42);
  });
});

Deno.test("an annotated result cannot make an incompatible left-hand operator use the right implementation", async () => {
  const source = `
type Left is data = $Left U32
type Right is data = $Right U32
func Left.add (a: Left) -> (b: Left): U32 => return 1
func Right.add (a: Left) -> (b: Right): U32 => return 42
func combine a -> b => return @type.call "add" a b
`;
  for (const expr of ['@type.call "add" ($Left n) ($Right n)', 'combine ($Left n) ($Right n)']) {
    await compileExpectedFailure(source + `io answer (n: U32): U32 => return ${expr}\n`,
      "missing_associated", undefined, {prelude: "none"});
  }
  await compileAndRun(source + "io answer (n: U32): U32 => return Right.add ($Left n) ($Right n)\n",
    guest => equal(guest.call("answer", 0), 42), {prelude: "none"});
});
