import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("plain name templates and one-use destructured functions execute independently", async () => {
  await compileAndRun(`
const selected: U32 -> U32 where {type_rep U32} = fn value => value
entry const answer = fn () => do:
  let identity = fn value => value
  let (field, extracted) = (0.5, fn value => value)
  let (_, qualified) = ((), selected)
  let integer = identity (qualified (extracted 41))
  return @f32.add (@u32.to_f32 integer) (@f32.add field (identity 1.0))
`, guest => equal(guest.call("answer", null), 42.5));
});

Deno.test("destructured callable aliases cannot select two argument types", async () => {
  for (const binding of [
    "let (x, identity) = (0, fn value => value)",
    "let pair = (0, fn value => value)\n  let (x, identity) = pair",
    "let original = fn value => value\n  let (x, identity) = (0, original)",
    "let (identity, ()) = (fn value => value, ())",
    "let (_, identity) = (0, fn value => value)",
  ]) await compileExpectedFailure(`entry const answer = fn () => do:
  ${binding}
  let first = identity 41
  return @f32.add (@u32.to_f32 first) (identity 1.5)
`, "type_mismatch");
});
