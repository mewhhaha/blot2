import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("closed existential witnesses survive constant opening and resealing before Wasm emission", async () => {
  await compileAndRun(
    `type Item = exists [a] => a
const number = pack [U32] 42 as Item
const flag = pack [Bool] #True as Item
const resealed = unpack number as [a] first in unpack flag as [b] second in pack [b] second as Item
entry const answer = unpack resealed as [a] value in 42
`,
    (guest) => equal(guest.read("answer"), 42),
    { prelude: "none" },
  );
});
