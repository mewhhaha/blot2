import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("runtime scalar exports initialize dependency order once and retain their values", async () => {
  await compileAndRun(`
entry let integer: U32 = @u32.add base 2
let base: U32 = 40
entry let floating: F32 = @f32.add 1.25 2.5
entry let enabled: Bool = #True
entry let empty: Unit = ()
entry const use_values = fn () => @u32.add integer base
const unused = @panic "unused const"
let unused_runtime = @panic "unused initializer"
`, guest => {
    for (let count = 0; count < 50; count++) {
      equal(guest.read("integer"), 42);
      equal(guest.read("floating"), 3.75);
      equal(guest.read("enabled"), true);
      equal(guest.read("empty"), null);
      equal(guest.call("use_values", null), 82);
    }
  });
  await compileExpectedFailure(`entry let values: Array U32 = #[42]\n`, "entry_let_type");
});

Deno.test("reachable runtime globals initialize in dependency order and survive arena resets", async () => {
  await compileAndRun(`
let unused = @panic "unreachable initialization"
let first = @u32.add second 1
let second = 20
let values = @array.fill 3 first
type Point is data = #Point { x: U32, y: U32 }
let point = #Point { y: second, x: first }
entry const run = fn (amount: U32) -> U32 => do:
  let changed = @array.set values 0 amount
  return @u32.add point.x (@u32.add (@array.get values 0) (@array.get changed 0))
`, guest => {
    for (let i = 0; i < 2000; i++) equal(guest.call("run", i), 42 + i);
  });
});

Deno.test("startup cycles retain original branches and metadata after all ordinary entry constants", async () => {
  await compileAndRun(`let base = 1\nconst saved = 41\nconst delay = fn ~value => value\nentry const answer = fn () => @u32.add base (@force (delay saved))\n`, guest => equal(guest.call("answer", null), 42));
  const cycle = `let first: U32 = second\nlet second = first\n`;
  await compileExpectedFailure(cycle + `entry const answer = if #True then 42 else first\n`, "initialization_cycle");
  await compileExpectedFailure(cycle + `const read: Unit -> U32 = fn () => first\nentry const answer = @effect.count (@effect.of read)\n`, "initialization_cycle");
  await compileExpectedFailure(cycle + `entry const answer: Unit -> U32 = fn () => first\nentry const bad: U32 = @panic "later"\n`, "const_panic", "later");
  await compileExpectedFailure(cycle + `let saved = 42\nentry const answer: Unit -> U32 = fn () => first\nentry const bad = saved\n`, "const_runtime_dependency");
  await compileAndRun(cycle + `entry const answer = 42\n`, guest => equal(guest.read("answer"), 42));
  await compileAndRun(`let first: U32 = @u32.add second 1\nlet second = 41\nentry const answer = if #True then 42 else first\n`, guest => equal(guest.read("answer"), 42));
});
