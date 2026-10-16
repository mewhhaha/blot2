import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("ordinary scheme projections keep each selected associated type beside forall", async () => {
  await compileAndRun(
    `type Source a is contract = { type Item }
impl Number : Source U32 = { type Item = U32 }
impl Flag : Source Bool = { type Item = F32 }
const identity: forall [a] => a -> a = fn value => value
const keep: a -> (Source.Item a) -> (Source.Item a) where { Source a } = fn witness => fn value => value
entry const answer = fn (value: U32) => identity (keep value value)
entry const fraction = fn (value: F32) => identity (keep #True value)
`,
    (guest) => {
      for (let value = 0; value < 96; value++) {
        equal(guest.call("answer", value), value);
        equal(guest.call("fraction", value + 0.5), value + 0.5);
      }
      const warmed = guest.memoryBytes();
      for (let value = 0; value < 96; value++) {
        equal(guest.call("answer", value), value);
      }
      equal(guest.memoryBytes(), warmed);
    },
    { prelude: "none" },
  );
});
