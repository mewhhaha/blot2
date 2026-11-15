import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;

// Named calls, closures called through their table entry and typed by the
// callee (including a closure held by a constant), and operator methods that
// return a closure each execute as written, retained and fresh builds agree,
// and an edit to one callee updates its callers.
const program = (offset: number) => `
type Vec is data = $Vec U32
const Vec.add = func (left: Vec) => return do:
  let $Vec x = left
  break func (right: Vec) : Vec => return do:
    let $Vec y = right
    break $Vec (x + y + ${offset})
const adder = func (x: U32) => return do:
  break func (y: U32) : U32 => return x + y + ${offset}
const twice = func (f: U32 -> U32) => return func (x: U32) : U32 => return f (f x)
const shift = (func (k: U32) => return func (y: U32) : U32 => return y + k) ${offset + 3}
entry const named_over = func (v: U32) : U32 => return adder v 2
entry const indirect = func (v: U32) : U32 => return twice (func (y: U32) => return y + 3) v
entry const closure_constant = func (v: U32) : U32 => return twice shift v
entry const operator = func (v: U32) : U32 => return do:
  let $Vec total = $Vec v + $Vec 5
  break total
entry const captured = func (v: U32) : U32 => return do:
  let step = func (y: U32) => return y * 2
  let apply = func (g: U32 -> U32) => return g v
  break apply step + adder 1 1
`;
Deno.test("calls of every shape execute and follow edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-resolved-calls-" });
  const entry = `${directory}/main.blot`;
  const options = {
    executable,
    entry,
    prelude,
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
          assert.equal(guest.call("named_over", 40), 42 + offset);
          assert.equal(guest.call("indirect", 10), 16);
          assert.equal(guest.call("operator", 37), 42 + offset);
          assert.equal(guest.call("captured", 20), 42 + offset);
          assert.equal(guest.call("closure_constant", 30), 36 + 2 * offset);
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
