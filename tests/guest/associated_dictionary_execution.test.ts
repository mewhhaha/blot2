import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

const producer =
  `type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
impl Number : Source U32 = { type Item = U32, const get = func value => return value, const show = func owner => return func value => return value }
impl Flag : Source Bool = { type Item = Bool, const get = func value => return value, const show = func owner => return func value => return if value then 7 else 9 }
impl Float : Source F32 = { type Item = F32, const get = func value => return value, const show = func owner => return func value => return @f32.to_u32 value }
impl Pair : Source (U32, U32) = { type Item = Array U32, const get = func (value: (U32, U32)) => return #[@product.get value 0, @product.get value 1], const show = func owner => return func value => return @u32.add (@array.get value 0) (@array.get value 1) }
type Package = exists [a] where { Source a } => a
const make = func (flag: Bool) => return if flag then pack [U32] 42 as Package else pack [Bool] true as Package
const reseal = func (item: Package) => return unpack item as [a] value in pack [a] value as Package
const read = func (item: Package) => return unpack item as [a] value in Source.show value (Source.get value)
`;
Deno.test("runtime associated dictionaries retain scalar Float and aggregate result carriers", async () => {
  await compileAndRun(
    producer +
      `entry const answer = func (flag: Bool) => return read (reseal (make flag))
entry const floating = func (value: F32) => return read (pack [F32] value as Package)
entry const aggregate = func (value: U32) => return read (pack [(U32, U32)] (value, 22) as Package)
entry const snapshot = func (value: U32) => return #[value]
`,
    (guest, bytes) => {
      equal(guest.call("answer", true), 42);
      equal(guest.call("answer", false), 7);
      equal(guest.call("floating", 42.5), 42);
      equal(guest.call("aggregate", 20), 42);
      const raw =
        new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
      const enter = raw["blot:ownership_enter"] as CallableFunction;
      const leave = raw["blot:ownership_leave"] as CallableFunction;
      const invoke = raw.aggregate as CallableFunction;
      const memory = raw["blot:memory"] as WebAssembly.Memory;
      let warmed = 0;
      for (let i = 0; i < 96; i++) {
        enter();
        equal(invoke(20), 42);
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
Deno.test("static associated dictionaries adapt exact evaluator member signatures", async () => {
  await compileAndRun(
    producer + `const number: Package = pack [U32] 42 as Package
const floating: Package = pack [F32] 42.5 as Package
const pair: Package = pack [(U32, U32)] (20, 22) as Package
entry const answer = func () => return @u32.add (read number) (@u32.add (read floating) (read pair))
`,
    (guest) => equal(guest.call("answer", null), 126),
    { prelude: "none" },
  );
});

Deno.test("stored universal dictionaries retain abstract associated result carriers", async () => {
  await compileAndRun(
    producer +
      `const render: forall [a] where { Source a } => a -> U32 = func value => return Source.show value (Source.get value)
const both: (forall [a] where { Source a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
entry const answer = func () => return both render
`,
    (guest) => equal(guest.call("answer", null), 49),
    { prelude: "none" },
  );
});

Deno.test("associated dictionary traps preserve later owner cleanup", async () => {
  await compileAndRun(
    producer.replace(
      "if value then 7 else 9",
      'if value then 42 else @panic "associated result trap"',
    ) +
      `entry const answer = func (flag: Bool) => return read (pack [Bool] flag as Package)
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
Deno.test("associated carriers grant no concrete or different opening authority", async () => {
  await compileExpectedFailure(
    producer +
      `const bad = func (item: Package) => return unpack item as [a] value in @u32.add (Source.get value) 1
entry const answer = func () => return bad (make true)
`,
    "type_mismatch",
    undefined,
    { prelude: "none" },
  );
  await compileExpectedFailure(
    producer +
      `const bad = func (left: Package) => return func (right: Package) => return unpack left as [a] x in unpack right as [b] y in Source.show x (Source.get y)
entry const answer = func () => return bad (make true) (make false)
`,
    "type_mismatch",
    undefined,
    { prelude: "none" },
  );
});
