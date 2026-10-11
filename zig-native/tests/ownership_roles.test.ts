import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;

// Every allocation the emitter makes carries word roles from its checked
// layout, and every function it creates carries parameter roles. The lifetime
// pass never sees an allocation stored into a word whose role is scalar
// (role_conflicts), including closures capturing closure templates,
// constructor cells, records, arrays, request loops and state providers.
// Retained builds equal fresh ones through an edit.
const program = (offset: number) => `
type Shape is data = #Circle U32 | #Square { side: U32, label: Shape }
type Validate is effect = { check: U32 -> U32 }

entry const templates = fn (v: U32) -> U32 => do:
  let add = fn (x: U32) => x + v + ${offset}
  let twice = fn (x: U32) => add (add x)
  let thrice = fn (x: U32) => twice (add x)
  return thrice 1

entry const cells = fn (v: U32) -> U32 => do:
  let shape = #Square { side: v, label: #Circle 2 }
  let pair = (shape, v)
  let (#Square { side, label }, extra) = pair else:
    return 0
  let inner = case label of
    #Circle r => r
    #Square _ => 0
  return side + inner + extra

entry const arrays = fn (v: U32) -> U32 => do:
  let items = [#Circle v, #Circle 1, #Circle 2]
  let total = 0
  for item in items:
    let #Circle r = item else:
      return 0
    total := self + r
  return total

const checked = fn computation => do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        if value == 0:
          return 0
        yield value
      complete value =>
        return value

entry const requested = fn (v: U32) -> U32 => checked (@computation (fn () => do:
  use left <- Validate.check v
  use right <- Validate.check 2
  return left + right
))
`;
function counter(stats: unknown, key: string): number {
  const text = JSON.stringify(stats);
  const match = text.match(new RegExp(`"${key}":(\\d+)`));
  assert(match, `${key} missing from ${text.slice(0, 200)}`);
  return Number(match[1]);
}
Deno.test("ownership roles from checked layouts reach every allocation without conflicts", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-ownership-" });
  const entry = `${directory}/main.blot`;
  const options = { executable, entry, prelude, cacheDirectory: false as const };
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
          assert.equal(guest.call("templates", 5), 1 + 3 * (5 + offset));
          assert.equal(guest.call("cells", 7), 16);
          assert.equal(guest.call("arrays", 4), 7);
          assert.equal(guest.call("requested", 40), 42);
          assert.equal(guest.call("requested", 0), 0);
        } finally {
          guest.dispose();
        }
        for (const build of [result, expected]) {
          assert.equal(counter(build.stats, "role_conflicts"), 0);
        }
        assert(counter(expected.stats, "allocation_role_runs") > 0);
        assert(counter(expected.stats, "parameter_role_functions") > 0);
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
