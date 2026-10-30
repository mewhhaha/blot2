import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
const source = `entry const list = func () => return case [].iter.next of
  #Nothing => 42
  #Some (_, _) => 0
entry const array = func () => return case #[].iter.next of
  #Nothing => 42
  #Some (_, _) => 0
`;

Deno.test("empty cursor result preserves erased source types and exact method edits in both tiers", async () => {
  const original = await Deno.readTextFile(prelude);
  const method =
    "const Cursor.next = func cursor => return\n  if @cursor.has cursor\n  then #Some (@cursor.value cursor, @cursor.advance cursor)\n  else #Nothing";
  const changed = original.replace(
    method,
    method.replace("else #Nothing", "else #Some (77, cursor)"),
  );
  const changedIter = original.replace(
    "const List.iter = func values => return @list.cursor values",
    "const List.iter = func values => return @list.cursor [77]",
  ).replace(
    "const Array.iter = func values => return @array.cursor values",
    "const Array.iter = func values => return @array.cursor #[77]",
  );
  assert.notEqual(original, changed);
  assert.notEqual(original, changedIter);
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable,
        entry,
        prelude,
        codegenTier,
        cacheDirectory: false as const,
      };
      const compiler = await createZigProjectCompiler(options);
      try {
        for (const text of [original, changed, changedIter, original]) {
          const sources = { [entry]: source, [prelude]: text };
          const actual = await compiler.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert(actual.success && expected.success, JSON.stringify(actual));
            assert.deepEqual(actual.bytes, expected.bytes);
            const module = new WebAssembly.Module(actual.bytes);
            assert.deepEqual([
              ...new Uint8Array(
                WebAssembly.Module.customSections(module, "blot:ownership")[0],
              ),
            ], [2, 2, 0]);
            const guest = await instantiateGuest(actual.bytes);
            try {
              let answer = 42;
              if (text !== original) answer = 0;
              assert.equal(guest.call("list", null), answer);
              assert.equal(guest.call("array", null), answer);
            } finally {
              guest.dispose();
            }
          } finally {
            fresh.dispose();
          }
        }
      } finally {
        compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
