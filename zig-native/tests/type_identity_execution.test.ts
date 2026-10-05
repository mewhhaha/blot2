import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("type comparison preserves nominal and phantom evidence without calling witnesses", async () => {
  await compileAndRun(`
type Count is data = #Count U32
type Other is data = #Other U32
type Cell value is data = #Cell value
type Phantom value is data = #Phantom
const same = fn left => fn right => @type.same left right
entry const constructor = same #Count (#Count 42)
entry const nominal = same #Count #Other
entry const generic = same (#Cell 1) (#Cell 1.0)
entry const array = same #[1, 2] #[42]
entry const product = same (1, #True) (1.0, #True)
entry const run = fn () => same (#Cell 42) (fn () -> Cell U32 => @panic "witness was called")
entry const phantom = fn () => same (fn () -> Phantom U32 => #Phantom) (fn () -> Phantom F32 => #Phantom)
entry const equal_phantom = fn () => same (fn () -> Phantom U32 => #Phantom) (fn () -> Phantom U32 => #Phantom)
`, guest => {
    equal(guest.read("constructor"), true);
    equal(guest.read("nominal"), false);
    equal(guest.read("generic"), false);
    equal(guest.read("array"), true);
    equal(guest.read("product"), false);
    equal(guest.call("run", null), true);
    equal(guest.call("phantom", null), false);
    equal(guest.call("equal_phantom", null), true);
  });
});

Deno.test("type comparison selects witness types before values and requires saturation", async () => {
  await compileExpectedFailure('entry const failure = @type.same (@panic "left witness") (@panic "right witness")', "invalid_annotation", "Never is an internal control-flow type");
  await compileExpectedFailure('entry const failure = @type.same (fn () -> U32 => @panic "uncalled") (@panic "right witness")', "invalid_annotation", "Never is an internal control-flow type");
  await compileExpectedFailure("const partial = @type.same 1\nentry const run = fn () => partial 2", "call_arity");
  await compileExpectedFailure("const bare = @type.same\nentry const run = fn () => bare 1 2", "call_arity");
});

Deno.test("colon witnesses use the ordinary visible Type constructor", async () => {
  await compileAndRun(`
type Type witness is data = #Type witness
type Count is data = #Count U32
type Other is data = #Other U32
const Type.eq = fn left => fn right => case left, right of
  #Type a, #Type b => @type.same a b
entry const scalar = fn () => Type.eq (:1) (:2)
entry const nominal = fn () => Type.eq (:#Count) (:(#Count 42))
entry const different = fn () => Type.eq (:#Count) (:#Other)
`, guest => {
    equal(guest.call("scalar", null), true);
    equal(guest.call("nominal", null), true);
    equal(guest.call("different", null), false);
  });
});
