import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("universal bodies execute nested existential openings with distinct witnesses", async () => {
  await compileAndRun(
    `type Item = exists [b] => (b, b -> U32)
const number = fn value => pack [U32] (value, fn (payload: U32) => payload) as Item
const flag = fn value => pack [Bool] (value, fn payload => if payload then 7 else 9) as Item
const read: forall [a] => a -> Item -> U32 = fn ignored => fn item => unpack item as [b] value in (@product.get value 1) (@product.get value 0)
const pair: (forall [a] => a -> Item -> U32) -> U32 = fn callback => @u32.add (callback #True (number 42)) (callback 3 (flag #True))
entry const answer = fn () => pair read
`,
    (guest) => {
      for (let index = 0; index < 96; index++) {
        equal(guest.call("answer", null), 49);
      }
      const warmed = guest.memoryBytes();
      for (let index = 0; index < 96; index++) {
        equal(guest.call("answer", null), 49);
      }
      equal(guest.memoryBytes(), warmed);
    },
    { prelude: "none" },
  );
});
