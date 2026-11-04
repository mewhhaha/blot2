import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source = `const make = func captured => return do:
  let saved = captured
  return func argument => return {captured: saved, argument}
const left = func captured -> argument => return (make captured) argument
const right = func captured -> argument => return (make captured) argument
const twice = func captured -> argument => return do:
  let first = left captured argument
  let second = right captured argument
  return {captured: first.captured, argument: second.argument}
const outer = func captured -> argument => return do:
  let first = twice captured argument
  let second = twice captured argument
  return {argument: first.argument, captured: second.captured}
const make_scalar = func (captured: U32) => return do:
  let saved = captured
  return func (argument: U32): U32 => return @u32.add saved argument
const invoke_left = func (callback: U32 -> U32) -> (argument: U32): U32 => return callback argument
const invoke_right = func (callback: U32 -> U32) -> (argument: U32): U32 => return callback argument
const invoke_twice = func (callback: U32 -> U32) -> (argument: U32): U32 => return @u32.add (invoke_left callback argument) (invoke_right callback argument)
entry const shared_parents = func (input: U32): U32 => return do:
  let marker: GrowArray U32 = #[input]
  let first = invoke_twice (make_scalar marker[0]) 3
  let second = invoke_twice (make_scalar (@u32.add marker[0] 11)) 7
  return @u32.add first second
entry const integers = func (input: U32) => return do:
  let marker: GrowArray U32 = #[input]
  let first = outer {value: marker[0], stamp: 3} {value: @u32.add marker[0] 7, stamp: 5}
  let second = outer {stamp: 11, value: @u32.add marker[0] 13} {stamp: 17, value: @u32.add marker[0] 19}
  return #[first.captured.value, first.captured.stamp, first.argument.value, first.argument.stamp, second.captured.value, second.captured.stamp, second.argument.value, second.argument.stamp]
entry const floating = func (input: F32) => return do:
  let first = outer {value: input, stamp: 23} {value: -0.0, stamp: 29}
  let second = outer {stamp: 31, value: @f32.add input 1.5} {stamp: 37, value: input}
  return #[first.captured.value, @u32.to_f32 first.captured.stamp, first.argument.value, @u32.to_f32 first.argument.stamp, second.captured.value, @u32.to_f32 second.captured.stamp, second.argument.value, @u32.to_f32 second.argument.stamp]
type First is data = $First {value: U32}
type Second is data = $Second {value: U32}
entry const nominals = func (input: U32) => return do:
  let first = outer ($First {value: input}) ($Second {value: @u32.add input 1})
  let second = outer ($Second {value: @u32.add input 2}) ($First {value: @u32.add input 3})
  return #[first.captured.value, first.argument.value, second.captured.value, second.argument.value]
const reading = func (captured: ResizeArray U32) => return do:
  let saved = captured
  return func (argument: ResizeArray U32): U32 => return @u32.add saved[0] argument[0]
const update = func (captured: ResizeArray U32) -> (argument: ResizeArray U32) -> (amount: U32): Unit => return do:
  let value = (reading captured) argument
  argument[0] := @u32.add value amount
  return ()
entry const descriptors = func (input: U32) => return do:
  let first: ResizeArray U32 = #[input, 31]
  let second: ResizeArray U32 = #[@u32.add input 10, 37]
  update first first 1
  update first second 2
  let total: U32 = 0
  for index in 0 .. 3:
    update first second index
    total := @u32.add total ((reading second) first)
  return #[first[0], second[0], total, first[1], second[1]]
entry const snapshots = func (input: U32) => return do:
  let base = input
  let bound: U32 -> U32 = func value => return @u32.add base value
  let before = bound 1
  base := @u32.add input 99
  return #[before, bound 2, base]
type Choice is data = $Whole U32 | $Fraction F32 | $Absent
const inspect = func (choice: Choice): U32 => return case choice of
  $Whole number => number
  $Fraction number => @u32.add 100 (@f32.to_u32 number)
  $Absent => 31
entry const variants = func (input: U32) => return do:
  let marker: GrowArray U32 = #[input]
  let missing = inspect $Absent
  let whole = inspect ($Whole marker[0])
  let fraction = inspect ($Fraction 3.5)
  let again = inspect ($Whole (@u32.add marker[0] 7))
  let joined = if @u32.eq input 0 then $Absent else $Whole marker[0]
  return #[missing, whole, fraction, again, inspect joined]
`;

function descriptorExpected(input: number): Uint32Array {
  let first = input;
  let second = (input + 10) >>> 0;
  first = (first + first + 1) >>> 0;
  second = (first + second + 2) >>> 0;
  let total = 0;
  for (let index = 0; index < 3; index++) {
    second = (first + second + index) >>> 0;
    total = (total + first + second) >>> 0;
  }
  return new Uint32Array([first, second, total, 31, 37]);
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`typed closures preserve runtime captures schemas and descriptor reads (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-typed-closures-",
    });
    const entry = `${directory}/main.blot`;
    let compiler:
      | Awaited<ReturnType<typeof createZigProjectCompiler>>
      | undefined;
    try {
      compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        prelude: null,
        codegenTier,
        cacheDirectory: false,
        startupTimeoutMs: 5_000,
      });
      const built = await compiler.build({
        sources: { [entry]: source },
        signal: AbortSignal.timeout(5_000),
      });
      assert(built.success, JSON.stringify(built));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          const call = async (name: string, input: number) => {
            if (asynchronous) return await guest.callAsync(name, input);
            return guest.call(name, input);
          };
          for (const input of [0, 1, 41, 0xfffffffd, 3, 0]) {
            assert.equal(
              await call("shared_parents", input),
              (input * 4 + 42) >>> 0,
            );
            assert.deepEqual(
              await call("integers", input),
              new Uint32Array([
                input,
                3,
                input + 7,
                5,
                input + 13,
                11,
                input + 19,
                17,
              ]),
            );
            assert.deepEqual(
              await call("nominals", input),
              new Uint32Array([
                input,
                input + 1,
                input + 2,
                input + 3,
              ]),
            );
            assert.deepEqual(
              await call("descriptors", input),
              descriptorExpected(input),
            );
            assert.deepEqual(
              await call("snapshots", input),
              new Uint32Array([
                input + 1,
                input + 2,
                input + 99,
              ]),
            );
            let selected = input;
            if (input === 0) selected = 31;
            assert.deepEqual(
              await call("variants", input),
              new Uint32Array([
                31,
                input,
                103,
                input + 7,
                selected,
              ]),
            );
          }
          for (const input of [-0, 1.25, -10.5, 3, -0]) {
            assert.deepEqual(
              await call("floating", input),
              new Float32Array([
                input,
                23,
                -0,
                29,
                input + 1.5,
                31,
                input,
                37,
              ]),
            );
          }
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler?.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
