import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const program = (answer: number) => `
type Outer is effect = { check: U32 -> U32 }
type Inner is effect = { read: Unit -> U32 }
const make = fn action => @computation action
const inner = fn computation => do:
  for request in @requests computation:
    case request of
      effect Inner.read () =>
        use value <- Outer.check 0
        yield value
      complete value =>
        break value
const outer = fn computation => do:
  for request in @requests computation:
    case request of
      effect Outer.check value =>
        break ${answer}
      complete value =>
        break value
entry const answer = fn () => outer (@computation (fn () => do:
  use inner (make (fn () => do:
    use Inner.read ()
    break @panic "inner suffix"
  ))
  break @panic "outer suffix"
))
entry const folded = answer ()
`;
Deno.test("bottom completion slots keep complete ownership and retained cancellation in both tiers", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable,
        entry,
        codegenTier,
        cacheDirectory: false as const,
        prelude: null,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (const value of [42, 43, 42]) {
          const sources = { [entry]: program(value) };
          const result = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert(result.success && expected.success, JSON.stringify(result));
            assert.deepEqual(result.bytes, expected.bytes);
            const module = new WebAssembly.Module(result.bytes);
            const metadata = WebAssembly.Module.customSections(
              module,
              "blot:ownership",
            );
            assert.deepEqual(Array.from(new Uint8Array(metadata[0])), [
              2,
              2,
              0,
            ]);
            const guest = await instantiateGuest(result.bytes);
            try {
              for (let iteration = 0; iteration < 50; iteration++) {
                assert.equal(guest.call("answer", null), value);
              }
              assert.equal(guest.read("folded"), value);
            } finally {
              guest.dispose();
            }
          } finally {
            fresh.dispose();
          }
        }
      } finally {
        retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
