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
entry const ring: U32 -> U32 = func value => return ring_0 value
entry const callback: U32 -> U32 = func value => return left value
entry const branching: U32 -> U32 = func value => return diamond value
entry const integer: U32 -> U32 = func depth => return repeat 42 depth
entry const floating: U32 -> F32 = func depth => return repeat 1.5 depth
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

Deno.test("late selected recursive methods terminate and rejected leaves can be corrected", async () => {
  const source = `type Seed is data = #Seed
type Box a is data = #Box a
const Seed.build: a -> Seed -> Box a = func value => return func seed => return #Box value
const wrap = func value => return @type.call "build" value #Seed
const parent: U32 -> U32 = func value => return if @u32.eq value 0 then 42 else (wrap value).read
const Box.read: Box U32 -> U32 = func box => return case box of
  #Box value => parent (@u32.sub value 1)
entry const run: U32 -> U32 = func value => return parent value
`;
  for (
    const body of [
      "  #Box value => parent (@u32.sub value 1)",
      "  #Box value => do:\n    let next = @u32.sub value 1\n    break parent next",
      "  #Box value => do:\n    let next = func arg => return parent arg\n    break next (@u32.sub value 1)",
    ]
  ) {
    const selected = source.replace(
      "  #Box value => parent (@u32.sub value 1)",
      body,
    );
    await compileExpectedFailure(
      selected.replace("then 42", "then 1.5"),
      "type_mismatch",
      undefined,
      { prelude: "none" },
    );
    await compileAndRun(selected, (guest) => {
      for (const depth of [0, 1, 7, 17]) equal(guest.call("run", depth), 42);
    }, { prelude: "none" });
  }
});

Deno.test("unresolved diamonds retain invalid witness diagnostics before budget errors", async () => {
  const links = Array.from(
    { length: 12 },
    (_, index) =>
      `const f_${
        index + 1
      } = func left => return func right => return do:\n  let ignored = f_${index} left right\n  break f_${index} left right`,
  ).join("\n");
  await compileExpectedFailure(
    `const f_0 = func left => return func right => return @type.same (@panic "uncalled witness") right\n${links}\nentry const run = func (value: U32) : Bool => return f_12 value value\n`,
    "invalid_annotation",
    undefined,
    { prelude: "none" },
  );
});

Deno.test("queued associated methods preserve left dispatch priority", async () => {
  await compileAndRun(
    `type L is data = #L U32
type R is data = #R U32
type X is data = #X U32
const prime = @type.call "merge" (#X 1) (#R 2)
entry const answer: U32 = @type.call "merge" (#L 1) (#R 2)
const L.merge: L -> R -> U32 = func left => return func right => return 1
const R.merge: a -> R -> F32 = func left => return func right => return 1.0
`,
    (guest) => equal(guest.read("answer"), 1),
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
      `entry const run: U32 -> U32 = func value => return f_0 value\n${links}\nconst f_${depth}${annotation} = func value => return value\n`,
      (guest) => {
        for (const value of [0, 42, 0xFFFF_FFFF]) {
          equal(guest.call("run", value), value);
        }
      },
      { prelude: "none" },
    );
  }
});
