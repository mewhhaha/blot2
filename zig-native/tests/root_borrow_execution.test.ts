import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = `const scan = fn values => do:
  let original = values.iter
  let cursor = original
  let total = 0
  for unused in values:
    use step <- cursor.next
    let #Some (value, rest) = step else:
      break
    total := self + value
    cursor := rest
  break total
entry const arrays = fn (count: U32) => scan (@array.generate count identity)
entry const lists = fn (count: U32) => scan (@list.generate count identity)
`;
Deno.test("persistent cursor root borrows preserve finite traversal and normal List fallback", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-root-borrow-" });
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const entry = `${directory}/main.blot`;
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        codegenTier,
        prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
        cacheDirectory: false,
      });
      try {
        const built = await compiler.build({ sources: { [entry]: source } });
        assert(built.success, JSON.stringify(built));
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const count of [0, 1, 2, 17, 243, 244, 245, 700]) {
              for (const name of ["arrays", "lists"]) {
                let actual;
                if (asynchronous) actual = await guest.callAsync(name, count);
                else actual = guest.call(name, count);
                assert.equal(actual, (count * (count - 1) / 2) >>> 0);
              }
            }
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
