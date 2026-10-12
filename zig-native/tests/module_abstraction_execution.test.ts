import { compileAndRun, equal } from "./compile_helpers.ts";

const scalarSource = `
opaque type Count = U32
opaque type Floating = F32
opaque type Box a = a
const make_count: U32 -> Count = fn value => #Count value
const read_count: Count -> U32 = fn (#Count value) => value
const make_floating: F32 -> Floating = fn value => #Floating value
const read_floating: Floating -> F32 = fn (#Floating value) => value
const box = #Box
const unbox = fn (#Box value) => value
const captured = fn () => do:
  let constructor = #Floating
  return fn value => read_floating (constructor value)
entry const unsigned = fn (value: U32) => read_count (make_count value)
entry const floating = fn (value: F32) => read_floating (make_floating value)
entry const generic_unsigned = fn (value: U32) => unbox (box value)
entry const generic_floating = fn (value: F32) => unbox (box value)
entry const captured_floating = fn (value: F32) => (captured ()) value
entry const folded = read_floating (#Floating 42.5)
`;

for (const asynchronous of [false, true]) {
  Deno.test(`opaque scalar storage erases constructors and preserves bits (${String(asynchronous)})`, async () => {
    await compileAndRun(scalarSource, async (guest) => {
      equal(guest.read("folded"), 42.5);
      for (let iteration = 0; iteration < 50; iteration++) {
        for (const value of [0, 7, 42, 0x80000000, 0xffffffff]) {
          for (const name of ["unsigned", "generic_unsigned"]) {
            let actual: unknown;
            if (asynchronous) actual = await guest.callAsync(name, value);
            else actual = guest.call(name, value);
            equal(actual, value);
          }
        }
        for (const value of [0, -0, 2.5, 42.5, Infinity, NaN]) {
          for (
            const name of ["floating", "generic_floating", "captured_floating"]
          ) {
            let actual: unknown;
            if (asynchronous) actual = await guest.callAsync(name, value);
            else actual = guest.call(name, value);
            equal(actual, value);
          }
        }
      }
    }, { asynchronous });
  });
}

Deno.test("opaque reference storage keeps representation aliases and projections", async () => {
  await compileAndRun(
    `
opaque type Box a = { value: a }
opaque type Wrapped a = Array a
const make = fn value => #Box { value: value }
const read = fn (#Box value) => value.value
const field = fn value => value.value
const wrap = #Wrapped
const unwrap = fn (#Wrapped value) => value
entry const answer = fn (value: U32) => @u32.add (read (make value)) (field (make 2))
entry const shared = fn (value: U32) => do:
  let original = #[value, 2]
  let copied = unwrap (wrap original)
  return @u32.add (@array.get original 0) (@array.get copied 1)
`,
    (guest) => {
      for (let iteration = 0; iteration < 1000; iteration++) {
        equal(guest.call("answer", 40), 42);
        equal(guest.call("shared", 40), 42);
      }
    },
  );
});

Deno.test("opaque callback captures preserve effects and scalar wrapping adds no guest heap", async () => {
  await compileAndRun(
    `
opaque type Token = U32
const make: U32 -> Token = fn value => #Token value
const read: Token -> U32 = fn (#Token value) => value
private entry const run = fn (value: U32) => read (make value)
`,
    (guest, bytes) => {
      equal(guest.call("run", 42), 42);
      const module = new WebAssembly.Module(bytes);
      equal(
        WebAssembly.Module.exports(module).some((item) =>
          item.kind === "memory"
        ),
        false,
      );
    },
    { prelude: "none" },
  );
  await compileAndRun(
    `
opaque type Callback a = a
const wrap = #Callback
const unwrap = fn (#Callback value) => value
entry const run = fn (host: U32 -> U32 ! {Foreign}) => do:
  let saved = wrap (fn value => host value)
  use result <- (unwrap saved) 41
  return @u32.add result 1
`,
    (guest) => {
      const seen: number[] = [];
      const host = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value: number) => {
          seen.push(value);
          return value;
        },
      });
      equal(guest.call("run", host), 42);
      equal(JSON.stringify(seen), "[41]");
    },
  );
});

Deno.test("opaque structured generic parameters and staged aggregate words preserve F32 storage", async () => {
  await compileAndRun(
    `
opaque type First [left, right] = left
opaque type Second {left, right} = right
const first: F32 -> First [F32,U32] = #First
const read_first = fn (#First value) => value
const second: F32 -> Second {left:U32,right:F32} = #Second
const read_second = fn (#Second value) => value
opaque type Float = F32
const floats = #[#Float 40.0, #Float 2.5]
const read = fn (#Float value) => value
entry const tuple = fn (value: F32) => read_first (first value)
entry const record = fn (value: F32) => read_second (second value)
entry const folded = @f32.add (read (@array.get floats 0)) (read (@array.get floats 1))
`,
    (guest) => {
      equal(guest.call("tuple", 42.5), 42.5);
      equal(guest.call("record", -0), -0);
      equal(guest.read("folded"), 42.5);
    },
  );
});
