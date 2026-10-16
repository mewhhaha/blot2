import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const main = `import * as library from "./library"
entry const run = fn (seed: U32) => do:
  let callable = library.make seed
  let alias = callable
  let published = {callback: callable}
  let pressure = @array.fill 8192 0
  return library.read (alias ()) + library.read (published.callback ()) + pressure[8191]
`;
const record = `const make = fn (seed: U32) => fn () => {saved: seed}
const read = fn value => value.saved
`;
const array = `const make = fn (seed: U32) => fn () => #[seed + 1]
const read = fn value => value[0]
`;
Deno.test("returned callable endpoints retain owners through graph publication and producer type edits with identical ABI", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-callable-endpoint-",
  });
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  try {
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(library, record);
    for (const codegenTier of ["development", "optimized"] as const) {
      for (const shareMachineCode of [false, true]) {
        const options = {
          executable,
          entry,
          codegenTier,
          shareMachineCode,
          cacheDirectory: false as const,
          prelude: new URL("../../std/prelude.blot", import.meta.url),
        };
        const compiler = await createZigProjectCompiler(options);
        try {
          for (
            const [text, expected] of [[record, 82], [array, 84], [
              array.replace("seed + 1", "seed + 2"),
              86,
            ], [record, 82]] as const
          ) {
            const sources = { [entry]: main, [library]: text };
            const built = await compiler.build({ sources });
            assert(built.success, JSON.stringify(built));
            const fresh = await createZigProjectCompiler(options);
            try {
              const rebuilt = await fresh.build({ sources });
              assert(rebuilt.success, JSON.stringify(rebuilt));
              assert.deepEqual(built.bytes, rebuilt.bytes);
            } finally {
              await fresh.dispose();
            }
            for (const asynchronous of [false, true]) {
              const guest = await instantiateGuest(built.bytes, {
                asynchronous,
              });
              try {
                let value;
                if (asynchronous) value = await guest.callAsync("run", 41);
                else value = guest.call("run", 41);
                assert.equal(value, expected);
              } finally {
                guest.dispose();
              }
            }
          }
        } finally {
          await compiler.dispose();
        }
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
