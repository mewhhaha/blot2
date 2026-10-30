import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("opened package operations keep source covariance under a Foreign callback ambient", async () => {
  await compileAndRun(
    `type Item = exists [a] => (a, a -> U32)
const make: U32 -> Item = func value => return pack [U32] (value, func number => return number) as Item
const read: Item -> U32 ! {Foreign} = func item => return unpack item as [a] body in (func (operation: a -> U32 ! {Foreign}) => return operation (@product.get body 0)) (@product.get body 1)
entry const answer: U32 -> U32 ! {Foreign} = func value => return read (make value)
`,
    (guest) => {
      equal(guest.call("answer", 42), 42);
      equal(guest.call("answer", 7), 7);
    },
    { prelude: "none" },
  );
  await compileExpectedFailure(
    `type Item = exists [a] => (a, a -> U32 ! {Foreign})
const read: Item -> U32 = func item => return unpack item as [a] body in (func (operation: a -> U32) => return operation (@product.get body 0)) (@product.get body 1)
entry const answer = 42
`,
    "effect_mismatch",
    undefined,
    { prelude: "none" },
  );
});
