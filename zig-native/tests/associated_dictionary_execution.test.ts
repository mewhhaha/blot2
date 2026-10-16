import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

const producer =
  `type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
impl Number : Source U32 = { type Item = U32, const get = fn value => value, const show = fn owner => fn value => value }
impl Flag : Source Bool = { type Item = Bool, const get = fn value => value, const show = fn owner => fn value => if value then 7 else 9 }
impl Float : Source F32 = { type Item = F32, const get = fn value => value, const show = fn owner => fn value => @f32.to_u32 value }
impl Pair : Source (U32, U32) = { type Item = Array U32, const get = fn (value: (U32, U32)) => #[@product.get value 0, @product.get value 1], const show = fn owner => fn value => @u32.add (@array.get value 0) (@array.get value 1) }
type Package = exists [a] where { Source a } => a
const make = fn (flag: Bool) => if flag then pack [U32] 42 as Package else pack [Bool] #True as Package
const reseal = fn (item: Package) => unpack item as [a] value in pack [a] value as Package
const read = fn (item: Package) => unpack item as [a] value in Source.show value (Source.get value)
`;
Deno.test("runtime associated dictionaries retain scalar Float and aggregate result carriers", async () => {
  await compileAndRun(
    producer +
      `entry const answer = fn (flag: Bool) => read (reseal (make flag))
entry const floating = fn (value: F32) => read (pack [F32] value as Package)
entry const aggregate = fn (value: U32) => read (pack [(U32, U32)] (value, 22) as Package)
entry const snapshot = fn (value: U32) => #[value]
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
entry const answer = fn () => @u32.add (read number) (@u32.add (read floating) (read pair))
`,
    (guest) => equal(guest.call("answer", null), 126),
    { prelude: "none" },
  );
});

Deno.test("stored universal dictionaries retain abstract associated result carriers", async () => {
  await compileAndRun(
    producer +
      `const render: forall [a] where { Source a } => a -> U32 = fn value => Source.show value (Source.get value)
const both: (forall [a] where { Source a } => a -> U32) -> U32 = fn callback => @u32.add (callback 42) (callback #True)
entry const answer = fn () => both render
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
      `entry const answer = fn (flag: Bool) => read (pack [Bool] flag as Package)
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
      `const bad = fn (item: Package) => unpack item as [a] value in @u32.add (Source.get value) 1
entry const answer = fn () => bad (make #True)
`,
    "type_mismatch",
    undefined,
    { prelude: "none" },
  );
  await compileExpectedFailure(
    producer +
      `const bad = fn (left: Package) => fn (right: Package) => unpack left as [a] x in unpack right as [b] y in Source.show x (Source.get y)
entry const answer = fn () => bad (make #True) (make #False)
`,
    "type_mismatch",
    undefined,
    { prelude: "none" },
  );
});
