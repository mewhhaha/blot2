import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";
import { monadCases } from "./monad_cases.ts";

Deno.test("native monad lowering handles long flat statement sequences", async () => {
  const count = 1536;
  const source = `type Box value is data = $Box value
const Box.pure = func value => return $Box value
const sequence = func () => return do (@do.monad Box):
  let total = 0
${"  total := @u32.add self 1\n".repeat(count)}  break total
entry const answer = func () => return do:
  let $Box value = sequence ()
  break value
`;
  await compileAndRun(source, guest => equal(guest.call("answer", null), count));
});
for (const item of monadCases) {
  if (!("expected" in item)) continue;
  Deno.test(`native monad protocol preserves ${item.name}`, async () => {
    await compileAndRun(item.source, (guest) => {
      for (const [name, expected] of Object.entries(item.expected)) {
        equal(guest.abi.constants.some(value => value.name === name) ? guest.read(name) : guest.call(name, null), expected);
      }
    });
  });
}
Deno.test("native monad protocol rejects invalid owners and missing selected methods", async () => {
  for (const item of monadCases) {
    if (!("error" in item)) continue;
    await compileExpectedFailure(item.source, item.error);
  }
});
