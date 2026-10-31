import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("native runtime records copy nested updates and keep aliases immutable", async () => {
  await compileAndRun(`
type Point is data = $Point { x: U32, y: U32 }
type Holder is data = $Holder { point: Point, flag: Bool }
const origin = $Point { y: 3, x: 1 }
entry const run = func (amount: U32) : U32 => return do:
  let holder = $Holder { flag: true, point: origin }
  let before = holder
  holder.point.x := @u32.add self amount
  let $Holder { point: $Point { y } } = holder
  break @u32.add (@u32.mul before.point.x 10) (@u32.add holder.point.x y)
`, guest => {
    for (let i = 0; i < 2000; i++) equal(guest.call("run", i), i + 14);
  });
});

Deno.test("native runtime generic variants preserve F32 payloads and ordered guards", async () => {
  await compileAndRun(`
type Choice a is data = $Present a | $Absent
const get = func fallback => return func candidate => return case candidate of
  $Present value => value
  $Absent => fallback
entry const floating = func (value: F32) : F32 => return get 0.0 ($Present value)
entry const integer = func (value: U32) : U32 => return get 0 ($Present value)
entry const fallback = func () : U32 => return get 7 $Absent
type Pick is data = $First U32 | $Second U32 | $Empty
const choose = func candidate => return case candidate of
  $First value | $Second value if @u32.lt 39 value => value
  $First value | $Second value => @u32.add value 2
  $Empty => 0
entry const guarded = func (value: U32) : U32 => return choose ($Second value)
`, guest => {
    equal(guest.call("floating", 1.23456789), Math.fround(1.23456789));
    equal(guest.call("integer", 0xffffffff), 0xffffffff);
    equal(guest.call("fallback", null), 7);
    for (const value of [0, 38, 39, 40, 42, 0xffffffff]) equal(guest.call("guarded", value), value > 39 ? value : value + 2);
  });
});
