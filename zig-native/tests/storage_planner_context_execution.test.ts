import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const prelude = `infix 30 (==) = eq
const eq = func left -> right => return @type.call "eq" left right
const U32.eq = func (left: U32) -> (right: U32) => return @u32.eq left right
const F32.eq = func (left: F32) -> (right: F32) => return @f32.eq left right
`;
const helper = `const any = func predicate -> (values: Array item) => return do:
  for value in values:
    if predicate value:
      return true
  return false
const nested = func (rows: Array item) -> values => return
  any (func row => return any (func value => return row.value == value) values) rows
`;
const fields = Array.from({ length: 80 }, (_, i) => `a${i}: t${i}`).join(", ");
const values = Array.from({ length: 80 }, (_, i) => `a${i}: input`).join(", ");
const source = `import * as helper from "./helper"
type Meter is data = $Meter U32
const Meter.amount = func ($Meter value) => return value
const read = func (context: {${fields}, zrows: rows, zvalues: values, zmeter: meter}) => return
  if context.zmeter.amount == 0 then false else helper.nested context.zrows context.zvalues
entry const integer = func (input: U32) => return do:
  let marker: ResizeArray U32 = #[input]
  let rows: Array {value: U32} = #[{value: marker[0]}]
  return read {${values}, zrows: rows, zvalues: #[2], zmeter: $Meter 1}
entry const floating = func (input: F32) => return do:
  let marker: ResizeArray F32 = #[input]
  let rows: Array {value: F32} = #[{value: marker[0]}]
  return read {${values}, zrows: rows, zvalues: #[2.5], zmeter: $Meter 1}
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`imported planner closures retain their own field obligations (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-planner-context-",
    });
    const entry = `${directory}/main.blot`;
    const helperFile = `${directory}/helper.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      stdRoot,
      prelude: `${directory}/prelude.blot`,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      await Deno.writeTextFile(helperFile, helper);
      await Deno.writeTextFile(`${directory}/prelude.blot`, prelude);
      const result = await compiler.build({ sources: { [entry]: source } });
      assert(result.success, JSON.stringify(result));
      assert(
        (result.stats.workCounters as Record<string, number>)
          .scoped_emission_expressions > 0,
      );
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        try {
          const call = (name: string, input: number) =>
            asynchronous
              ? guest.callAsync(name, input)
              : guest.call(name, input);
          for (const input of [0, 1, 2, 100]) {
            assert.equal(await call("integer", input), input === 2);
          }
          for (const input of [-0, 1.25, 2.5, 100]) {
            assert.equal(await call("floating", input), input === 2.5);
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
