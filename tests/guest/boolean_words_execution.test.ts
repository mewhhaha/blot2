import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("primitive boolean words preserve precedence patterns and short circuit without a prelude", async () => {
  await compileAndRun(`
entry const precedence = func () => return true or false and false
entry const conjunction = func (value: Bool) => return value and (@panic "evaluated right")
entry const disjunction = func (value: Bool) => return value or (@panic "evaluated right")
entry const classify = func (value: Bool) => return case value of
  true => 42
  false => 7
entry const scoped = func (value: Bool) => return do:
  let calls: GrowArray U32 = #[0]
  let result = value and (do:
    calls[0] := @u32.add calls[0] 1
    break true
  ) or (do:
    calls[0] := @u32.add calls[0] 10
    break false
  )
  return if result then calls[0] else @u32.add calls[0] 100
`, guest => {
    equal(guest.call("precedence", null), true);
    equal(guest.call("conjunction", false), false);
    equal(guest.call("disjunction", true), true);
    equal(guest.call("classify", true), 42);
    equal(guest.call("classify", false), 7);
    equal(guest.call("scoped", true), 1);
    equal(guest.call("scoped", false), 110);
  }, { prelude: "none" });
});

Deno.test("boolean operands remain checked on skipped branches", async () => {
  await compileExpectedFailure("entry const value = false and 42\n", "type_mismatch", undefined, { prelude: "none" });
  await compileExpectedFailure("entry const value = true or 42\n", "type_mismatch", undefined, { prelude: "none" });
});
