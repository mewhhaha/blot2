import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("type comparison preserves nominal and phantom evidence without calling witnesses", async () => {
  await compileAndRun(`
type Count is data = #Count U32
type Other is data = #Other U32
type Cell value is data = #Cell value
type Phantom value is data = #Phantom
const same = func left => return func right => return @type.same left right
entry const constructor = same #Count (#Count 42)
entry const nominal = same #Count #Other
entry const generic = same (#Cell 1) (#Cell 1.0)
entry const array = same #[1, 2] #[42]
entry const product = same (1, true) (1.0, true)
entry const run = func () => return same (#Cell 42) (func () : Cell U32 => return @panic "witness was called")
entry const phantom = func () => return same (func () : Phantom U32 => return #Phantom) (func () : Phantom F32 => return #Phantom)
entry const equal_phantom = func () => return same (func () : Phantom U32 => return #Phantom) (func () : Phantom U32 => return #Phantom)
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
  await compileExpectedFailure('entry const failure = @type.same (func () : U32 => return @panic "uncalled") (@panic "right witness")', "invalid_annotation", "Never is an internal control-flow type");
  await compileExpectedFailure("const partial = @type.same 1\nentry const run = func () => return partial 2", "call_arity");
  await compileExpectedFailure("const bare = @type.same\nentry const run = func () => return bare 1 2", "call_arity");
});

Deno.test("colon witnesses use the ordinary visible Type constructor", async () => {
  await compileAndRun(`
type Type witness is data = #Type witness
type Count is data = #Count U32
type Other is data = #Other U32
const Type.eq = func left => return func right => return case left, right of
  #Type a, #Type b => @type.same a b
entry const scalar = func () => return Type.eq (:1) (:2)
entry const nominal = func () => return Type.eq (:#Count) (:(#Count 42))
entry const different = func () => return Type.eq (:#Count) (:#Other)
`, guest => {
    equal(guest.call("scalar", null), true);
    equal(guest.call("nominal", null), true);
    equal(guest.call("different", null), false);
  });
});
