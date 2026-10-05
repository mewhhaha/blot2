import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("unary associated members apply the receiver once and preserve curried results", async () => {
  await compileAndRun(`
type Box value is data = #Box { value: value }
const Box.get = fn (self: Box value) => self.value
const Box.add = fn (self: Box U32) => fn (extra: U32) => @u32.add self.value extra
const access = fn self => self.add
const read = fn self => self.get
const constant = (#Box { value: 40 }).add 2
entry const staged: U32 = constant
entry const unary = fn (input: U32) -> U32 => read (#Box { value: input })
entry const floating = fn (input: F32) -> F32 => read (#Box { value: input })
entry const curried = fn (input: U32) -> U32 => access (#Box { value: input }) 2
entry const nested = fn (input: U32) -> U32 => (#Box { value: #Box { value: input } }).get.get
`, guest => {
    equal(guest.read("staged"), 42);
    equal(guest.call("unary", 40), 40);
    equal(guest.call("floating", 2.5), 2.5);
    equal(guest.call("curried", 40), 42);
    equal(guest.call("nested", 42), 42);
  });
});

Deno.test("field and method collisions remain errors through generic callers", async () => {
  for (const access of ["(#Box { value: 1 }).value", "read (#Box { value: 1 })"]) {
    await compileExpectedFailure(`
type Box is data = #Box { value: U32 }
const Box.value = fn self => 99
const read = fn self => self.value
entry const result: U32 = ${access}
`, "ambiguous_member");
  }
});

Deno.test("accessor functions preserve generic fields, members and nested paths", async () => {
  await compileAndRun(`
type Box value is data = #Box { value: value }
const Box.get = fn (self: Box value) => self.value
const get = .get
const read = .value
const nested = .get.value
entry const integer = fn (input: U32) -> U32 => get (#Box { value: input })
entry const floating = fn (input: F32) -> F32 => read (#Box { value: input })
entry const path = fn (input: U32) -> U32 => nested (#Box { value: #Box { value: input } })
entry const local = fn (input: U32) -> U32 => do:
  let accessor = .value
  return accessor (#Box { value: input })
entry const mixed = fn () -> U32 => do:
  let accessor = .value
  let integer = accessor (#Box { value: 40 })
  let floating = accessor (#Box { value: 2.5 })
  return @u32.add integer (@f32.to_u32 floating)
`, guest => {
    equal(guest.call("integer", 42), 42);
    equal(guest.call("floating", 1.5), 1.5);
    equal(guest.call("path", 42), 42);
    equal(guest.call("local", 42), 42);
    equal(guest.call("mixed", null), 42);
  });
});

Deno.test("writable fields remain distinct from receiver methods", async () => {
  await compileAndRun(`
type Box is data = #Box { value: U32 }
const Box.value = fn self => 99
entry const answer = fn () -> U32 => do:
  let box = #Box { value: 1 }
  box.value := 42
  return case box of
    #Box { value } => value
`, guest => equal(guest.call("answer", null), 42));
  await compileExpectedFailure(`
type Box is data = #Box U32
const Box.method = fn self => 99
entry const answer = fn () -> U32 => do:
  let box = #Box 1
  box.method := 42
  return 42
`, "missing_field");
});

Deno.test("runtime generic associated operators preserve independent operand and result types", async () => {
  await compileAndRun(`
infixl 60 (+) = associated_add
infix 50 (==) = associated_eq
type Point is data = #Point { x: U32 }
const associated_add = fn left => fn right => @type.call "add" left right
const associated_eq = fn left => fn right => @type.call "eq" left right
const Point.add = fn (left: Point) => fn (right: U32) => @u32.add left.x right
const Point.eq = fn (left: Point) => fn (right: Point) => @u32.eq left.x right.x
const combine = fn left => fn right => left + right
const same = fn left => fn right => left == right
entry const add = fn (value: U32) -> U32 => combine (#Point { x: value }) 22
entry const equal = fn (value: U32) -> Bool => same (#Point { x: value }) (#Point { x: 42 })
`, guest => {
    equal(guest.call("add", 20), 42);
    equal(guest.call("add", 0xffffffff), 21);
    equal(guest.call("equal", 42), true);
    equal(guest.call("equal", 43), false);
  });
});

Deno.test("runtime associated dispatch retries the right owner without swapping operands", async () => {
  await compileAndRun(`
infixl 60 (+) = associated_add
type Left is data = #Left U32
type Right is data = #Right U32
const associated_add = fn left => fn right => @type.call "add" left right
const Left.add = fn (left: Left) => fn (right: U32) => right
const Right.add = fn (left: Left) => fn (right: Right) => do:
  let #Left first = left
  let #Right second = right
  return @u32.sub first second
const combine = fn left => fn right => left + right
entry const run = fn (value: U32) -> U32 => combine (#Left value) (#Right 2)
`, guest => {
    equal(guest.call("run", 44), 42);
    equal(guest.call("run", 2), 0);
  });
});

Deno.test("ordinary scalar method names do not alter compiler primitives", async () => {
  await compileAndRun(`
const U32.add = fn (left: U32) => fn (right: U32) => @u32.sub left right
entry const dispatched = fn (value: U32) -> U32 => U32.add value 2
entry const primitive = fn (value: U32) -> U32 => @u32.add value 2
`, guest => {
    equal(guest.call("dispatched", 44), 42);
    equal(guest.call("primitive", 40), 42);
  });
});
