import { deepStrictEqual, ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("structural records preserve shapes, field order and type-changing nested updates", async () => {
  await compileAndRun(
    `
type Point = { x: U32, y: F32 }
type Box a is data = $Box a
const read = func record => return record.x
const replace = func record => return do:
  record.x := true
  break record
const identity = func (point: Point) => return point
#entry const answer = func (value: U32) => return do:
  let original = { y: 2.5, x: value }
  let point = identity original
  let { y, x } = point
  let updated = replace original
  let nested = { point, retained: 40 }
  nested.point.x := 2.0
  let { point: { x: fraction } } = nested
  let $Box boxed = $Box original
  break if updated.x then @f32.add fraction (@u32.to_f32 (@u32.add nested.retained (@u32.sub (read boxed) x))) else y
#entry const reordered = func () => return read { y: true, x: 42 }
#entry const array = func () => return do:
  let values: Array { x: U32 } = #[{ x: 42 }]
  break (@array.get values 0).x
`,
    (guest) => {
      for (const value of [0, 41, 0xffffffff]) {
        equal(
          guest.call("answer", value),
          42,
        );
      }
      equal(guest.call("reordered", null), 42);
      equal(guest.call("array", null), 42);
    },
    { prelude: "none" },
  );
});

Deno.test("structural record construction evaluates fields once in source order with latent callbacks", async () => {
  await compileAndRun(
    `
const invoke = func record => return record.callback ()
#entry const answer = func (send: U32 -> U32 ! {Foreign}) => return do:
  use record <- do:
    break { z: send 1, a: send 2, callback: func () => return send 3 }
  use last <- invoke record
  break @u32.add record.z (@u32.add record.a last)
`,
    (guest) => {
      const calls: number[] = [];
      const send = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value) => {
          calls.push(value);
          return value;
        },
      });
      equal(guest.call("answer", send), 6);
      equal(calls.join(","), "1,2,3");
    },
    { prelude: "none" },
  );
});

Deno.test("structural shapes reject duplicates, absent fields and mismatched exact annotations", async () => {
  for (
    const [source, code] of [
      ["#entry const answer = ({ x: 1, x: 2 }).x\n", "duplicate_record_field"],
      ["#entry const answer = ({ x: 1 }).y\n", "missing_member"],
      [
        "const exact: { x: U32 } = { x: 1, y: 2 }\n#entry const answer = exact.x\n",
        "type_mismatch",
      ],
    ]
  ) await compileExpectedFailure(source, code, undefined, { prelude: "none" });
});

Deno.test("retired @record.merge intrinsic is rejected", async () => {
  await compileExpectedFailure(
    "#entry const answer = @record.merge { x: 1 } { y: 2 }\n",
    "unknown_intrinsic",
    undefined,
    { prelude: "none" },
  );
});
