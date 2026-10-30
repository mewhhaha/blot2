import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = `const view_value = func (values: &[U32]) => return values[0]
const ref_value = func (value: Ref U32) => return @storage.load value
const link_value = func (value: Link U32) => return @storage.load value
const read = func (rows: ResizeArray U32) -> (links: GrowArray U32) -> (index: U32) => return
  @u32.add (view_value (&rows[0..2])) (@u32.add (ref_value (@storage.at rows 1)) (link_value (@storage.link links index)))
entry const answer = func (input: U32) => return do:
  let first: ResizeArray U32 = #[@u32.add input 10, @u32.add input 20, @u32.add input 30]
  let second: ResizeArray U32 = #[@u32.add input 110, @u32.add input 120, @u32.add input 130]
  let links: GrowArray U32 = #[@u32.add input 30, @u32.add input 130]
  return @u32.add (read first links 0) (read second links 1)
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`planned borrows retain their checked View Ref and Link witnesses (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-reader-witness-",
    });
    const entry = `${directory}/main.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
      cacheDirectory: false,
      codegenTier,
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
}
