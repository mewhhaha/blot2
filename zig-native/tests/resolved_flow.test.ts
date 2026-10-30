import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;

// Structured flow is prepared before its instructions: value and statement
// joins with rebinding merges (`if`, `if let`), guarded matches whose rows and
// guards fall through, nested loops with carries, zero iterations, `break`, `return` out
// of a loop, and request loops whose handlers yield, return or break. Each
// executes as written, retained and fresh builds agree through an edit, and
// fresh builds count every plan shape, including cleanup discharged by exits.
const program = (offset: number) => `
type Shape is data = #Circle U32 | #Square U32
type Validate is effect = { check: U32 -> U32 }

const area = func (shape: Shape) : U32 => return case shape of
  #Circle r if r > 10 => r * 3
  #Circle r => r
  #Square s => s * s

entry const joins = func (v: U32) : U32 => return do:
  let total = if v > 5 then v else 5
  let bonus = ${offset}
  if v > 20:
    bonus := self + 7
  else:
    bonus := self + 1
  let big = if v > 100 then #Some v else #Nothing
  if let #Some s = big:
    bonus := self + 2
  else:
    bonus := self + 1
  break total + bonus + area (#Circle v) + area (#Square 2)

entry const loops = func (end: U32) : U32 => return do:
  let total = 0
  let steps = 0
  for index in 0..end:
    if index == 7:
      break
    total := self + index
    for inner in 0..index:
      steps := self + 2
  break total * 1000 + steps

entry const early = func (end: U32) : U32 => return do:
  let total = 0
  for index in 0..end:
    if total > 50:
      break total + 1000
    total := self + index
  break total

const checked = func computation => return do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        if value == 0:
          break 0
        yield value
      complete value =>
        break value

const count_until_zero = func computation => return do:
  let count = 0
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        if value == 0:
          break
        count := self + 1
        yield value
      complete _ =>
        break
  break count

entry const requested = func (v: U32) : U32 => return checked (@computation (func () => return do:
  use left <- Validate.check v
  use right <- Validate.check 2
  break left + right
))

entry const counted = func (v: U32) : U32 => return count_until_zero (@computation (func () => return do:
  use Validate.check v
  use Validate.check 2
  use Validate.check 0
  break @panic "the handler broke before this statement"
))
`;
Deno.test("prepared structured flow executes and follows edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-resolved-flow-" });
  const entry = `${directory}/main.blot`;
  const options = {
    executable,
    entry,
    prelude,
    cacheDirectory: false as const,
  };
  const retained = await createZigProjectCompiler(options);
  try {
    for (const offset of [0, 10, 0]) {
      const sources = { [entry]: program(offset) };
      const result = await retained.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert(result.success && expected.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(guest.call("joins", 3), 14 + offset);
          assert.equal(guest.call("joins", 30), 132 + offset);
          assert.equal(guest.call("joins", 200), 813 + offset);
          assert.equal(guest.call("loops", 0), 0);
          assert.equal(guest.call("loops", 5), 10020);
          assert.equal(guest.call("loops", 20), 21042);
          assert.equal(guest.call("early", 0), 0);
          assert.equal(guest.call("early", 5), 10);
          assert.equal(guest.call("early", 20), 1055);
          assert.equal(guest.call("requested", 40), 42);
          assert.equal(guest.call("requested", 0), 0);
          assert.equal(guest.call("counted", 7), 2);
          assert.equal(guest.call("counted", 0), 0);
        } finally {
          guest.dispose();
        }
        const counters = expected.stats.workCounters as Record<string, number>;
        for (
          const kind of [
            "resolved_bodies",
            "resolved_plan_entries",
            "resolved_plan_reads",
            "prepared_exits",
            "prepared_exit_cleanups",
            "prepared_joins",
            "prepared_matches",
            "prepared_loops",
            "prepared_request_loops",
          ]
        ) assert(counters[kind] > 0, `${kind}: ${JSON.stringify(counters)}`);
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
