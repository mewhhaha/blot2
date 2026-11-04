import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("predicate package methods follow each runtime witness", async () => {
  await compileAndRun(
    `type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = func value => return value }
impl Flag : Render Bool = { const show = func value => return if value then 7 else 9 }
type Item = exists [a] where { Render a } => a
const make: Bool -> Item = func flag => return if flag then pack [U32] 42 as Item else pack [Bool] true as Item
const read = func (item: Item) => return unpack item as [a] value in Render.show value
const both = func (left: Item) => return func (right: Item) => return unpack left as [a] x in unpack right as [b] y in @u32.add (Render.show x) (Render.show y)
entry const answer = func (flag: Bool) => return read (make flag)
entry const combined = func (flag: Bool) => return both (make flag) (make false)
entry const collection = func (flag: Bool) => return do:
  let items = #[make flag, make false]
  break @u32.add (read (@array.get items 0)) (read (@array.get items 1))
entry const snapshot = func (value: U32) => return #[value]
`,
    (guest, bytes) => {
      equal(guest.call("answer", true), 42);
      equal(guest.call("answer", false), 7);
      equal(guest.call("combined", true), 49);
      equal(guest.call("combined", false), 14);
      equal(guest.call("collection", true), 49);
      equal(guest.call("collection", false), 14);
      const exports = new WebAssembly.Instance(new WebAssembly.Module(bytes))
        .exports;
      const enter = exports["blot:ownership_enter"] as CallableFunction;
      const leave = exports["blot:ownership_leave"] as CallableFunction;
      const invoke = exports.collection as CallableFunction;
      const memory = exports["blot:memory"] as WebAssembly.Memory;
      const counter = (name: string) =>
        Number((exports[`blot:rc_${name}`] as WebAssembly.Global).value);
      let warmed = 0;
      for (let repetition = 0; repetition < 96; repetition++) {
        enter();
        equal(invoke(repetition % 2), 14 + (repetition % 2) * 35);
        leave(0);
        equal(counter("roots"), 0);
        equal(counter("leases"), 0);
        if (repetition === 8) warmed = memory.buffer.byteLength;
        if (repetition > 8) equal(memory.buffer.byteLength, warmed);
      }
    },
    { prelude: "none" },
  );
});

Deno.test("stored dictionary traps preserve later invocations", async () => {
  await compileAndRun(
    `type Render a is contract = { const show: a -> U32 }
impl Flag : Render Bool = { const show = func value => return if value then 42 else @panic "dictionary failure" }
type Item = exists [a] where { Render a } => a
const make: Bool -> Item = func flag => return pack [Bool] flag as Item
const read = func (item: Item) => return unpack item as [a] value in Render.show value
entry const answer = func (flag: Bool) => return read (make flag)
`,
    (guest) => {
      equal(guest.call("answer", true), 42);
      let trapped = false;
      try {
        guest.call("answer", false);
      } catch {
        trapped = true;
      }
      equal(trapped, true);
      equal(guest.call("answer", true), 42);
    },
    { prelude: "none" },
  );
});

Deno.test("stored dictionary goals retain compound witness types", async () => {
  await compileAndRun(
    `type Render a is contract = { const show: a -> U32 }
impl Numbers : Render (Array U32) = { const show = func values => return @array.get values 0 }
impl Flags : Render (Array Bool) = { const show = func values => return if @array.get values 0 then 7 else 9 }
type Item = exists [a] where { Render (Array a) } => Array a
const make: Bool -> Item = func flag => return if flag then pack [U32] #[42, 9] as Item else pack [Bool] #[true, false] as Item
const read = func (item: Item) => return unpack item as [a] values in Render.show values
entry const answer = func (flag: Bool) => return read (make flag)
`,
    (guest) => {
      equal(guest.call("answer", true), 42);
      equal(guest.call("answer", false), 7);
    },
    { prelude: "none" },
  );
});
