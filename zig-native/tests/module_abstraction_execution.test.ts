import { compileAndRun, equal } from "./compile_helpers.ts";

const scalarSource = `
opaque type Count = U32
opaque type Floating = F32
opaque type Box a = a
const make_count: U32 -> Count = func value => return #Count value
const read_count: Count -> U32 = func (#Count value) => return value
const make_floating: F32 -> Floating = func value => return #Floating value
const read_floating: Floating -> F32 = func (#Floating value) => return value
const box = #Box
const unbox = func (#Box value) => return value
const captured = func () => return do:
  let constructor = #Floating
  break func value => return read_floating (constructor value)
entry const unsigned = func (value: U32) => return read_count (make_count value)
entry const floating = func (value: F32) => return read_floating (make_floating value)
entry const generic_unsigned = func (value: U32) => return unbox (box value)
entry const generic_floating = func (value: F32) => return unbox (box value)
entry const captured_floating = func (value: F32) => return (captured ()) value
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
const make = func value => return #Box { value: value }
const read = func (#Box value) => return value.value
const field = func value => return value.value
const wrap = #Wrapped
const unwrap = func (#Wrapped value) => return value
entry const answer = func (value: U32) => return @u32.add (read (make value)) (field (make 2))
entry const shared = func (value: U32) => return do:
  let original = #[value, 2]
  let copied = unwrap (wrap original)
  break @u32.add (@array.get original 0) (@array.get copied 1)
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
const make: U32 -> Token = func value => return #Token value
const read: Token -> U32 = func (#Token value) => return value
private entry const run = func (value: U32) => return read (make value)
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
const unwrap = func (#Callback value) => return value
entry const run = func (host: U32 -> U32 ! {Foreign}) => return do:
  let saved = wrap (func value => return host value)
  use result <- (unwrap saved) 41
  break @u32.add result 1
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
const read_first = func (#First value) => return value
const second: F32 -> Second {left:U32,right:F32} = #Second
const read_second = func (#Second value) => return value
opaque type Float = F32
const floats = #[#Float 40.0, #Float 2.5]
const read = func (#Float value) => return value
entry const tuple = func (value: F32) => return read_first (first value)
entry const record = func (value: F32) => return read_second (second value)
entry const folded = @f32.add (read (@array.get floats 0)) (read (@array.get floats 1))
`,
    (guest) => {
      equal(guest.call("tuple", 42.5), 42.5);
      equal(guest.call("record", -0), -0);
      equal(guest.read("folded"), 42.5);
    },
  );
});
