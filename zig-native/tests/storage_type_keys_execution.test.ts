import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const fields = Array.from({ length: 166 }, (_, i) => `f${i}: Array U32`);
const parameters = Array.from({ length: 13 }, (_, i) => `callback_${i}`).join(
  " -> ",
);
const callbacks = Array(13).fill("inspect").join(" ");
const wide = `type Wide = {${fields.join(",")}}
const inspect = func (value: Wide): U32 ! {} => return 0
const policy = func ${parameters} -> (value: U32): U32 => return @u32.add value 1
entry const answer = func () => return do:
  let kept: Array U32 = #[41]
  return policy ${callbacks} kept[0]
`;
const captured =
  `const capture = func value => return func (ignored: Unit) => return value
const invoke = func callback => return callback ()
entry const answer = func () => return do:
  let kept: Array U32 = #[0]
  let whole = invoke (capture 40)
  let fraction = invoke (capture 1.25)
  return @u32.add (@u32.add whole (@f32.to_u32 fraction)) (@storage.length kept)
`;
for (const codegenTier of ["development", "optimized"] as const) {
  for (
    const [name, source] of [["wide policy", wide], [
      "captured types",
      captured,
    ]]
  ) {
    Deno.test(`owned selected type keys execute ${name} (${codegenTier})`, async () => {
      const directory = await Deno.makeTempDir({ prefix: "blot-type-key-" });
      const entry = `${directory}/main.blot`;
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(result.bytes, { asynchronous });
          try {
            assert.equal(
              asynchronous
                ? await guest.callAsync("answer", null)
                : guest.call("answer", null),
              42,
            );
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await compiler.dispose();
        await Deno.remove(directory, { recursive: true });
      }
    });
  }
}
