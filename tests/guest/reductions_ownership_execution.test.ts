import { strict as assert } from "node:assert";
import { compileAndRun } from "./reduction_helpers.ts";

async function run(counts: number[]) {
  await compileAndRun(
    `
import * as rolling from "std/rolling"
import * as summary from "std/summary"
type Node is data = $End | $Next (Unit -> Node)
type Range is data = $Range { current: U32, end: U32 }
func Range.iter (r: Range) => r
func Range.next ($Range { current, end }) => if current < end then $Some (current, $Range { current: @u32.add current 1, end }) else $Nothing
type Mapped [i, f] is data = $Mapped { cursor: i, transform: f }
func Mapped.iter (m: Mapped [i, f]) => m
func Mapped.next ($Mapped { cursor, transform }) => case cursor.next of
  $Nothing => $Nothing
  $Some (value, rest) => $Some (transform value, $Mapped { cursor: rest, transform })
func fold_left step -> initial -> values =>
  let acc = initial
  let cursor = values.iter
  for ever:
    let $Some (value, rest) = cursor.next else:
      break
    acc := step acc value
    cursor := rest
  return acc
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
#entry const monoid = func (count: U32) => return do:
  let node = retained_node ()
  let values = $Mapped { cursor: $Range { current: 0, end: count }, transform: func index => return {sum: index, node} }
  let total = fold_left (func total => return func value => return @u32.add total value.sum) 0 (rolling.monoid combine {sum: 0, node} 31 values)
  break @u32.add total (validate node)
#entry const group = func (count: U32) => return do:
  let node = retained_node ()
  let values = $Mapped { cursor: $Range { current: 0, end: count }, transform: func index => return {sum: index, node} }
  let total = fold_left (func total => return func value => return @u32.add total value.sum) 0 (rolling.group combine inverse {sum: 0, node} 31 values)
  break @u32.add total (validate node)
#entry const update = func (count: U32) => return do:
  let node = retained_node ()
  let initial = {sum: 0, node}
  let original = summary.build combine initial ($Mapped { cursor: $Range { current: 0, end: 31 }, transform: func index => return {sum: index, node} })
  let tree = original
  for index in 0..count:
    tree := summary.set combine (@u32.rem index 31) {sum: 1, node} self
  let old = summary.query combine initial 0 31 original
  let current = summary.query combine initial 0 31 tree
  break @u32.add (@u32.add old.sum current.sum) (validate current.node)
#entry const memory = func () : Array U32 => return #[]
`,
    (guest) => {
      for (const count of counts) {
        for (const name of ["monoid", "group"]) {
          assert.equal(guest.call(name, count), expected(count));
        }
        assert.equal(guest.call("update", count), 496);
      }
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
}

const expected = (count: number) => (31 * (count - 30) * (count - 1) / 2) >>> 0;

Deno.test("rolling streams and current summary versions keep owned callbacks", async () => {
  await run([4096]);
});

// Direct backend gap: rolling and summary loops do not release per iteration, so 65,536 steps trap ("unreachable") (tasks/DELETE_SCOPED.md, known limits).
Deno.test.ignore("rolling streams and current summary versions bound owned callback storage", async () => {
  await run([65536]);
});
