import { strict as assert } from "node:assert";
import { compileAndRun } from "./reduction_helpers.ts";

Deno.test("rolling streams and current summary versions bound owned callback storage", async () => {
  await compileAndRun(
    `
import * as rolling from "std/rolling"
import * as summary from "std/summary"
import * as iter from "std/iter"
type Node is data = $End | $Next (Unit -> Node)
const retained_node = func () => return do:
  let saved = $End
  break $Next (func () => return saved)
const combine = func (left: {sum: U32, node: Node}) => return func (right: {sum: U32, node: Node}) => return {sum: @u32.add left.sum right.sum, node: left.node}
const inverse = func (value: {sum: U32, node: Node}) => return {sum: @u32.sub 0 value.sum, node: value.node}
const add = func (left: U32) => return func (right: U32) => return @u32.add left right
const validate = func (node: Node) => return case node of
  $End => @panic "summary lost its callback"
  $Next delayed => case delayed () of
    $End => 0
    $Next _ => @panic "summary changed its captured node"
entry const monoid = func (count: U32) => return do:
  let node = retained_node ()
  let values = iter.map (func index => return {sum: index, node}) (iter.range 0 count)
  let total = iter.fold_left (func total => return func value => return @u32.add total value.sum) 0 (rolling.monoid combine {sum: 0, node} 31 values)
  break @u32.add total (validate node)
entry const group = func (count: U32) => return do:
  let node = retained_node ()
  let values = iter.map (func index => return {sum: index, node}) (iter.range 0 count)
  let total = iter.fold_left (func total => return func value => return @u32.add total value.sum) 0 (rolling.group combine inverse {sum: 0, node} 31 values)
  break @u32.add total (validate node)
entry const update = func (count: U32) => return do:
  let node = retained_node ()
  let initial = {sum: 0, node}
  let original = summary.build combine initial (iter.map (func index => return {sum: index, node}) (iter.range 0 31))
  let tree = original
  for index in 0..count:
    tree := summary.set combine (@u32.rem index 31) {sum: 1, node} self
  let old = summary.query combine initial 0 31 original
  let current = summary.query combine initial 0 31 tree
  break @u32.add (@u32.add old.sum current.sum) (validate current.node)
entry const memory = func () : Array U32 => return #[]
`,
    (_, bytes) => {
      const module = new WebAssembly.Module(bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      const raw = new WebAssembly.Instance(module).exports;
      const memory = raw["blot:memory"] as WebAssembly.Memory;
      for (const name of ["monoid", "group"]) {
        const run = raw[name] as CallableFunction;
        const expected = (count: number) =>
          (31 * (count - 30) * (count - 1) / 2) >>> 0;
        assert.equal(run(4096), expected(4096));
        const warm = memory.buffer.byteLength;
        assert.equal(run(65536), expected(65536));
        assert.equal(memory.buffer.byteLength, warm, `${name} stream`);
      }
      const update = raw.update as CallableFunction;
      assert.equal(update(4096), 496);
      const warm = memory.buffer.byteLength;
      assert.equal(update(65536), 496);
      assert.equal(memory.buffer.byteLength, warm, "current summary tree");
      for (const name of ["rc_roots", "rc_leases"]) {
        assert.equal(
          Number((raw[`blot:${name}`] as WebAssembly.Global).value),
          0,
        );
      }
      (raw["blot:ownership_leave"] as CallableFunction)(2);
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
});
