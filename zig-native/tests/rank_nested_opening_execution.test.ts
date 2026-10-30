import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("universal bodies execute nested existential openings with distinct witnesses", async () => {
  await compileAndRun(
    `type Item = exists [b] => (b, b -> U32)
const number = func value => return pack [U32] (value, func (payload: U32) => return payload) as Item
const flag = func value => return pack [Bool] (value, func payload => return if payload then 7 else 9) as Item
const read: forall [a] => a -> Item -> U32 = func ignored => return func item => return unpack item as [b] value in (@product.get value 1) (@product.get value 0)
const pair: (forall [a] => a -> Item -> U32) -> U32 = func callback => return @u32.add (callback true (number 42)) (callback 3 (flag true))
entry const answer = func () => return pair read
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
