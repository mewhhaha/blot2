import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("untagged nested records execute through loop joins and tagged wrapper storage", async () => {
  await compileAndRun(
    `type Box is data = $Box {inner: {n: U32, left: U32, right: U32}, stamp: U32}
type Choice is data = $None | $Some Box
const wrap = func (n: U32) => return $Box {inner: {n: n, left: 2, right: 3}, stamp: 0}
const unpack = func (box: Box) => return case box of
  $Box {inner, stamp} => {inner, stamp}
const advance = func (state: {inner: {n: U32, left: U32, right: U32}, stamp: U32}) => return {inner: {n: @u32.add state.inner.n 1, left: state.inner.left, right: state.inner.right}, stamp: state.stamp}
entry const answer = func (count: U32): Array U32 => return do:
  let rows: GrowArray Box = #[wrap 1]
  let state = unpack rows[0]
  for index in 0 .. count:
    state := advance state
    rows[0] := $Box {inner: state.inner, stamp: state.stamp}
  let choice: Choice = if @u32.eq count 0 then $None else $Some rows[0]
  let result = case choice of
    $None => {payload: state, code: 7}
    $Some box => {payload: unpack box, code: 42}
  return #[result.payload.inner.n, result.payload.inner.left, result.payload.inner.right, result.code]
entry const scalar = func (): U32 => return do:
  let value = {nested: {answer: 42}}
  return value.nested.answer
`,
    (guest) => {
      for (
        const [count, expected] of [[0, [1, 2, 3, 7]], [3, [4, 2, 3, 42]], [1, [
          2,
          2,
          3,
          42,
        ]], [0, [1, 2, 3, 7]]] as const
      ) {
        assert.deepEqual(
          guest.call("answer", count),
          new Uint32Array(expected),
        );
      }
      assert.equal(guest.call("scalar", null), 42);
    },
  );
});
