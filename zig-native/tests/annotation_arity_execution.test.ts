import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("annotation constructor saturation keeps primitive array curried and shaped types distinct", async () => {
  await compileAndRun(`type Curried a => type b is data = #Curried (a,b)
type Shaped [a,b] is data = #Shaped (a,b)
const curried: Curried U32 F32 = #Curried (20,1.5)
const shaped: Shaped [U32,F32] = #Shaped (22,2.5)
entry const answer = fn () => do:
  let #Curried (left,_) = curried
  let #Shaped (right,_) = shaped
  return @u32.add left right
entry const folded = answer ()
entry const scalar = fn (values: Array U32) => @array.get values 0
entry const floating = fn (values: Array F32) => @array.get values 0
`, guest => {
    equal(guest.read("folded"), 42);
    for (let index = 0; index < 100; index++) {
      equal(guest.call("answer", null), 42);
      equal(guest.call("scalar", new Uint32Array([index])), index);
      equal(guest.call("floating", new Float32Array([index + 0.5])), index + 0.5);
    }
  }, { prelude: "none" });
});

Deno.test("annotation saturation diagnostics preserve reference categories and messages", async () => {
  for (const [source, message] of [
    ["const values: Array = #[]\n", "Array requires one element type"],
    ["const values: Array U32 Bool = #[]\n", "type does not accept another argument; currying must be explicit in its declaration"],
    ["const values: Array Array = #[]\n", "Array requires one element type"],
    ["type Maybe a is data = #Some a | #Nothing\nconst value: Maybe = #Nothing\n", "partially applied type constructor requires another argument"],
    ["type Maybe a is data = #Some a | #Nothing\nconst value: Maybe Array Bool = #Nothing\n", "Array requires one element type"],
  ]) await compileExpectedFailure(source, "type_arity", message, { prelude: "none" });
});

Deno.test("unknown annotation argument precedes overapplication of a concrete type", async () => {
  await compileExpectedFailure("const values: Array U32 Missing = #[]\n", "unsupported_type", undefined, { prelude: "none" });
});
