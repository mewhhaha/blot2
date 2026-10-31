import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const protocol = `
type Show a is contract = {const show: a -> U32}
impl Scalar : Show U32 = {const show = func value => return @u32.add value 1}
const read: a -> U32 where {Show a} = func value => return Show.show value
impl Sequence a : Show (Array a) where {Show a} = {
  const show = func values => return read values[0],
}
`;
const forward = `
import * as protocol from "./protocol"
const read: a -> U32 where {protocol.Show a} = func value => return protocol.read value
`;
const left = `
import * as protocol from "./protocol"
import * as forward from "./forward"
type Left is data = $Left U32
private impl Local : protocol.Show Left = {
  const show = func ($Left value) => return @u32.add value 10,
}
const read = func (value: U32): U32 => return forward.read ($Left value)
`;
const right = left.replaceAll("Left", "Right").replace("value 10", "value 20");
const custom = `
import * as text from "std/text"
type Meter is data = $Meter U32
impl Decimal : text.Format Meter = {
  const format = func ($Meter value) => return #[77, @u32.add 48 (@u32.rem value 10)],
}
const format = func (value: U32): Text => return text.format ($Meter value)
`;
const source = `
import * as left from "./left"
import * as right from "./right"
import * as forward from "./forward"
import * as custom from "./custom"
import * as text from "std/text"
entry const run = func (value: U32): Array U32 => return do:
  let output: GrowArray U32 = #[]
  output.push (left.read value)
  output.push (right.read value)
  output.push (left.read (value + 1))
  output.push (right.read (value + 1))
  for code in custom.format value:
    output.push code
  return @storage.freeze output
entry const boolean = func (value: U32): Array U32 => return text.format (value == 0)
entry const prerequisite = func (value: U32): Array U32 => return do:
  let output: GrowArray U32 = #[]
  let values: Array U32 = #[value]
  output.push (forward.read values)
  return @storage.freeze output
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`scoped contract methods retain caller witnesses nominal identity and prerequisite proofs (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-contract-methods-",
    });
    const entry = `${directory}/main.blot`;
    const leftPath = `${directory}/left.blot`;
    for (
      const [name, contents] of Object.entries({
        main: source,
        protocol,
        forward,
        left,
        right,
        custom,
      })
    ) await Deno.writeTextFile(`${directory}/${name}.blot`, contents);
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
      stdRoot: new URL("../../std", import.meta.url).pathname,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const initial = await compiler.build();
      assert(
        initial.success,
        !initial.success ? JSON.stringify(initial.diagnostics) : "",
      );
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(initial.bytes, { asynchronous });
        const call = (name: string, value: number) =>
          asynchronous ? guest.callAsync(name, value) : guest.call(name, value);
        try {
          for (const value of [0, 1, 7, 129, 0xffff_ffff, 0, 7]) {
            assert.deepEqual(
              await call("run", value),
              Uint32Array.from([
                value + 10,
                value + 20,
                value + 11,
                value + 21,
                77,
                48 + value % 10,
              ]),
            );
            assert.deepEqual(
              await call("boolean", value),
              Uint32Array.from(
                Array.from(
                  value === 0 ? "true" : "false",
                  (character) => character.codePointAt(0)!,
                ),
              ),
            );
            assert.deepEqual(
              await call("prerequisite", value),
              Uint32Array.from([value + 1]),
            );
          }
        } finally {
          guest.dispose();
        }
      }
      for (
        const invalid of [
          "forward.read ($left.Left 7)",
          "forward.read #[1.0]",
        ]
      ) {
        const rejected = await compiler.build({
          sources: {
            [entry]: source +
              `\nentry const invalid = func (): U32 => return ${invalid}\n`,
          },
        });
        assert(!rejected.success);
        assert.equal(rejected.diagnostics[0].code, "missing_implementation");
        assert.equal("bytes" in rejected, false);
      }
      const incompatible = await compiler.build({
        sources: { [leftPath]: left.replace("@u32.add value 10", "true") },
      });
      assert(!incompatible.success);
      assert.equal(incompatible.diagnostics[0].code, "type_mismatch");
      assert.equal("bytes" in incompatible, false);
      const recovered = await compiler.build();
      assert(
        recovered.success,
        !recovered.success ? JSON.stringify(recovered.diagnostics) : "",
      );
      assert.deepEqual(recovered.bytes, initial.bytes);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
