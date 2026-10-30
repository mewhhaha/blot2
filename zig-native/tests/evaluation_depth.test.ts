import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;

// Compile-time recursion is bounded by nested calls (4096), on a compile
// thread whose stack fits that bound. A recursive walk over a registration
// table thousands long evaluates, and runaway recursion fails at the call that
// started it, in retained and fresh builds alike.
const registry = (size: number, wanted: number) => {
  const items = Array.from({ length: size }, (_, index) => index).join(", ");
  return `const registry = #[${items}]
const contains = func (index: U32) => return func (wanted: U32) : Bool => return if index == registry.length then false else if registry[index] == wanted then true else contains (index + 1) wanted
const present: Bool = contains 0 ${wanted}
entry const found = func () : Bool => return present
`;
};
const runaway = `const forever = func (n: U32) : U32 => return forever (n + 1)
const value: U32 = forever 0
entry const found = func () : U32 => return value
`;
Deno.test("compile-time recursion walks long tables and bounds runaway calls", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-depth-" });
  const entry = `${directory}/main.blot`;
  const options = { executable, entry, prelude, cacheDirectory: false as const };
  // [source, expected guest result, or null for the recursion diagnostic]
  const revisions: [string, number | null][] = [
    [registry(600, 599), 1],
    [registry(3000, 2999), 1],
    [registry(3000, 3000), 0],
    [runaway, null],
    [registry(600, 599), 1],
  ];
  const retained = await createZigProjectCompiler(options);
  try {
    for (const [index, [text, expected]] of revisions.entries()) {
      const sources = { [entry]: text };
      const result = await retained.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const reference = await fresh.build({ sources });
        assert.equal(result.success, reference.success, `revision ${index}`);
        if (!result.success && !reference.success) {
          assert.deepEqual(result.diagnostics, reference.diagnostics);
          assert.equal(expected, null, JSON.stringify(result.diagnostics));
          const [issue] = result.diagnostics;
          assert.equal(issue.code, "constant_recursion");
          const call = text.indexOf("forever 0");
          assert.equal(issue.start, call, JSON.stringify(issue));
          assert.equal(issue.end, call + "forever 0".length);
          continue;
        }
        assert(result.success && reference.success, `revision ${index}`);
        assert.deepEqual(result.bytes, reference.bytes);
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(Number(guest.call("found", null)), expected);
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
