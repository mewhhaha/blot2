import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const fields = 72;
const source = `const read = func row => return {${
  Array.from({ length: fields }, (_, index) => `f${index}: row.f${index}`).join(
    ", ",
  )
}}
entry const answer = func (input: U32) => return do:
  let values: Array U32 = #[input]
  values[0] := input
  let selected = read {${
  Array.from({ length: fields }, (_, index) =>
    `f${index}: @u32.add values[0] ${index}`).join(", ")
}}
  let total: U32 = 0
${
  Array.from({ length: fields }, (_, index) =>
    `  total := @u32.add total selected.f${index}\n`).join("")
}  return total
`;
Deno.test(`wide fields use scoped indexes or forward complete result words`, async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-refinement-index-",
  });
  const entry = `${directory}/main.blot`;
  const stdRoot = new URL("../../std", import.meta.url).pathname;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0],
    entry,
    stdRoot,
    prelude: `${stdRoot}/prelude.blot`,
  });
  try {
    const result = await compiler.build({ sources: { [entry]: source } });
    assert(result.success, JSON.stringify(result));
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(result.bytes, { asynchronous });
      try {
        for (const input of [0, 1, 12345, 0xffffffff]) {
          const actual = asynchronous
            ? await guest.callAsync("answer", input)
            : guest.call("answer", input);
          assert.equal(
            actual,
            (fields * input + fields * (fields - 1) / 2) >>> 0,
          );
        }
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
