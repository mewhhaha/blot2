import { deepStrictEqual, ok, throws } from "node:assert/strict";
import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("small collection elimination preserves eager order, unused elements, traps and early exits", async () => {
  await compileAndRun(
    `
type Trace is data = $Trace U32
const mark = func number => return do:
  use previous <- @state.get $Trace
  let $Trace before = previous
  use @state.set ($Trace (before * 10 + number))
  break number
const first = func (values: Array U32) => return do:
  for value in values:
    break value
  break 0
io const ordered = func () => return do:
  let ($Trace trace, answer) = @state.run ($Trace 0) (func () => return first #[mark 1, mark 2, mark 3])
  break trace * 10 + answer
io const trapped = func denominator => return first #[7, @u32.div 1 denominator]
io const empty = func (seed: U32) => return do:
  let result = seed
  let values: Array U32 = #[]
  for value in values:
    result := self + value
  break result
`,
    (guest) => {
      equal(guest.call("ordered", null), 1231);
      equal(guest.call("trapped", 1), 7);
      throws(() => guest.call("trapped", 0), WebAssembly.RuntimeError);
      equal(guest.call("empty", 42), 42);
    },
  );
});
