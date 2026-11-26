import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("joint recursive components preserve distinct polymorphic uses, callbacks and diamonds", async () => {
  for (const width of [8, 32, 128]) {
    const ring = Array.from(
      { length: width },
      (_, index) =>
        `const ring_${index}: U32 -> U32 = func value => return if @u32.eq value 0 then 42 else ring_${
          (index + 1) % width
        } (@u32.sub value 1)`,
    ).join("\n");
    await compileAndRun(
      `${ring}
const call = func next => return func value => return next value
const left: U32 -> U32 = func value => return if @u32.eq value 0 then 42 else call right (@u32.sub value 1)
const right: U32 -> U32 = func value => return if @u32.eq value 0 then 42 else call left (@u32.sub value 1)
const diamond: U32 -> U32 = func value => return if @u32.eq value 0 then 42 else if @u32.eq (@u32.rem value 2) 0 then arm_left (@u32.sub value 1) else arm_right (@u32.sub value 1)
const arm_left: U32 -> U32 = func value => return diamond value
const arm_right: U32 -> U32 = func value => return diamond value
const repeat = func value => return func (depth: U32) => return if @u32.eq depth 0 then value else repeat value (@u32.sub depth 1)
io const ring: U32 -> U32 = func value => return ring_0 value
io const callback: U32 -> U32 = func value => return left value
io const branching: U32 -> U32 = func value => return diamond value
io const integer: U32 -> U32 = func depth => return repeat 42 depth
io const floating: U32 -> F32 = func depth => return repeat 1.5 depth
`,
      (guest) => {
        for (const depth of [0, 1, 7, 17]) {
          for (
            const name of ["ring", "callback", "branching", "integer"]
          ) equal(guest.call(name, depth), 42);
          equal(guest.call("floating", depth), 1.5);
        }
      },
      { prelude: "none" },
    );
  }
});

Deno.test("queued associated methods select each left operand independently", async () => {
  await compileAndRun(
    `type L is data = $L U32
type R is data = $R U32
io const prime: F32 = @type.call "merge" ($R 1) ($R 2)
io const answer: U32 = @type.call "merge" ($L 1) ($R 2)
const L.merge: L -> R -> U32 = func left => return func right => return 1
const R.merge: a -> R -> F32 = func left => return func right => return 1.0
`,
    (guest) => {
      equal(guest.read("prime"), 1.0);
      equal(guest.read("answer"), 1);
    },
    { prelude: "none" },
  );
});

Deno.test("forward annotated and generic chains execute after iterative inference", async () => {
  for (
    const [depth, annotated] of [[300, true], [1000, true], [
      300,
      false,
    ]] as const
  ) {
    const annotation = annotated ? ": U32 -> U32" : "";
    const links = Array.from(
      { length: depth },
      (_, index) =>
        `const f_${index}${annotation} = func value => return f_${index + 1} value`,
    ).join("\n");
    await compileAndRun(
      `io const run: U32 -> U32 = func value => return f_0 value\n${links}\nconst f_${depth}${annotation} = func value => return value\n`,
      (guest) => {
        for (const value of [0, 42, 0xFFFF_FFFF]) {
          equal(guest.call("run", value), value);
        }
      },
      { prelude: "none" },
    );
  }
});
