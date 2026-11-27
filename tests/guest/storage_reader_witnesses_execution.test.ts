import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source = `const view_value = func (values: &[U32]) => return values[0]
const ref_value = func (value: Ref U32) => return @storage.load value
const link_value = func (value: Link U32) => return @storage.load value
const read = func (rows: Array U32) -> (links: Array U32) -> (index: U32) => return
  @u32.add (view_value (&rows[0..2])) (@u32.add (ref_value (@storage.at rows 1)) (link_value (@storage.link links index)))
io const answer = func (input: U32) => return do:
  let first: Array U32 = #[@u32.add input 10, @u32.add input 20, @u32.add input 30]
  let second: Array U32 = #[@u32.add input 110, @u32.add input 120, @u32.add input 130]
  let links: Array U32 = #[@u32.add input 30, @u32.add input 130]
  return @u32.add (read first links 0) (read second links 1)
`;
Deno.test(`planned borrows retain their checked View Ref and Link witnesses`, async () => {
  const directory = await Deno.makeTempDir({
    prefix: "squid-reader-witness-",
  });
  const entry = `${directory}/main.sq`;
  const stdRoot = new URL("../../std", import.meta.url).pathname;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0],
    entry,
    stdRoot,
    prelude: `${stdRoot}/prelude.sq`,
  });
  try {
    const result = await compiler.build({ sources: { [entry]: source } });
    assert(result.success, JSON.stringify(result));
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(result.bytes, { asynchronous });
      try {
        for (const input of [0, 1, 100]) {
          const actual = asynchronous
            ? await guest.callAsync("answer", input)
            : guest.call("answer", input);
          assert.equal(actual, input * 6 + 420);
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
