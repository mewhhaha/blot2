import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const prelude = `func (==) left -> right => return @type.call "eq" left right
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
io const integer = func (input: U32) => return do:
  let marker: Array U32 = #[input]
  let rows: Array {value: U32} = #[{value: marker[0]}]
  return read {${values}, zrows: rows, zvalues: #[2], zmeter: $Meter 1}
io const floating = func (input: F32) => return do:
  let marker: Array F32 = #[input]
  let rows: Array {value: F32} = #[{value: marker[0]}]
  return read {${values}, zrows: rows, zvalues: #[2.5], zmeter: $Meter 1}
`;
Deno.test(`imported planner closures retain their own field obligations`, async () => {
  const directory = await Deno.makeTempDir({
    prefix: "squid-planner-context-",
  });
  const entry = `${directory}/main.sq`;
  const helperFile = `${directory}/helper.sq`;
  const stdRoot = new URL("../../std", import.meta.url).pathname;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0],
    entry,
    stdRoot,
    prelude: `${directory}/prelude.sq`,
  });
  try {
    await Deno.writeTextFile(helperFile, helper);
    await Deno.writeTextFile(`${directory}/prelude.sq`, prelude);
    const result = await compiler.build({ sources: { [entry]: source } });
    assert(result.success, JSON.stringify(result));
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
