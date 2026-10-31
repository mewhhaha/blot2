import { strict as assert } from "node:assert";
import { createFrontend } from "./syntax.ts";
import { formatSource } from "./format.ts";

Deno.test("constructor and run surface preserves formatting and spaced dollar application", async () => {
  const source = `type Choice is data = $Some U32 | $None
const run = func x => return x
const answer = #run run 42
const selected = $Some answer
const flag = true
const apply = func f -> x => return f $ x
const values = #[1,2]
const linked = [1,2]
const block = #do:
  let value = 40
  break value + 2
const qualified = $run.Some 42
const legacy_qualified = $run.Some 42
`;
  const frontend = await createFrontend();
  try {
    frontend.parse(source);
    const formatted = await formatSource(source);
    assert(formatted.includes("$Some"));
    assert(formatted.includes("true"));
    assert(formatted.includes("#run"));
    assert(formatted.includes("#do:"));
    assert(formatted.includes("f $ x"));
    assert.equal(await formatSource(formatted), formatted);
    frontend.parse(formatted);
  } finally {
    frontend.dispose();
  }
});
