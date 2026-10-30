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

entry const callback_identity = func (host: U32 -> U32 ! {Foreign}) => return host (41 + ${offset})

entry const templates = func (v: U32) : U32 => return do:
  let add = func (x: U32) => return x + v + ${offset}
  let twice = func (x: U32) => return add (add x)
  let thrice = func (x: U32) => return twice (add x)
  break thrice 1

entry const cells = func (v: U32) : U32 => return do:
  let shape = #Square { side: v, label: #Circle 2 }
  let pair = (shape, v)
  let (#Square { side, label }, extra) = pair else:
    break 0
  let inner = case label of
    #Circle r => r
    #Square _ => 0
  break side + inner + extra

entry const arrays = func (v: U32) : U32 => return do:
  let items = [#Circle v, #Circle 1, #Circle 2]
  let total = 0
  for item in items:
    let #Circle r = item else:
      break 0
    total := self + r
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

entry const requested = func (v: U32) : U32 => return checked (@computation (func () => return do:
  use left <- Validate.check v
  use right <- Validate.check 2
  break left + right
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
        for (const build of [result, expected]) {
          const module = new WebAssembly.Module(build.bytes);
          assert.deepEqual([
            ...new Uint8Array(
              WebAssembly.Module.customSections(module, "blot:ownership")[0],
            ),
          ], [2, 2, 0]);
        }
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(
            guest.call(
              "callback_identity",
              guest.capability({
                parameter: "U32",
                result: "U32",
                call: (value) => value + 1,
              }),
            ),
            42 + offset,
          );
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

Deno.test("prepared machine sharing retains complete mixed ownership and sync JSPI callbacks", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const options = {
    executable,
    entry,
    prelude,
    cacheDirectory: false as const,
    shareMachineCode: true,
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
        const module = new WebAssembly.Module(result.bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        const guest = await instantiateGuest(result.bytes);
        try {
          const callback = guest.capability({
            parameter: "U32",
            result: "U32",
            call: (value) => value + 1,
          });
          assert.equal(guest.call("callback_identity", callback), 42 + offset);
          assert.equal(guest.call("templates", 5), 1 + 3 * (5 + offset));
          assert.equal(guest.call("cells", 7), 16);
          assert.equal(guest.call("arrays", 4), 7);
          assert.equal(guest.call("requested", 40), 42);
          assert.equal(guest.call("requested", 0), 0);
          assert.equal(
            await guest.callAsync("callback_identity", callback),
            42 + offset,
          );
          assert.equal(await guest.callAsync("requested", 40), 42);
        } finally {
          guest.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
