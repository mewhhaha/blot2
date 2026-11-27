import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

Deno.test("identity array sharing rechecks imported wrapper bodies across retained edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "squid-identity-edit-" });
  const entry = `${directory}/main.sq`, helper = `${directory}/helper.sq`;
  const main = `import {generate} from "./helper"
io const run = func (seed: U32) => return do:
  let saved = #[seed]
  let copied = generate saved.length (func index => return saved[index])
  break copied[0]
`;
  const before =
    "const generate = func count => return func callback => return @array.generate count callback\n";
  const changed =
    "const generate = func count => return func callback => return @array.generate count (func index => return callback index + 1)\n";
  const options = {
    executable: Deno.args[0],
    entry,
    prelude: new URL("../../std/prelude.sq", import.meta.url),
    stdRoot: new URL("../../std", import.meta.url),
  };
  const compiler = await createZigProjectCompiler(options);
  try {
    let original: Uint8Array<ArrayBuffer> | undefined;
    for (
      const [source, expected] of [[before, 42], [changed, 43], [
        before,
        42,
      ]] as const
    ) {
      const sources = { [entry]: main, [helper]: source };
      const built = await compiler.build({ sources });
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        assert.equal(guest.call("run", 42), expected);
      } finally {
        guest.dispose();
      }
      const fresh = await createZigProjectCompiler(options);
      try {
        const control = await fresh.build({ sources });
        assert(control.success, JSON.stringify(control));
        assert.deepEqual(built.bytes, control.bytes);
      } finally {
        await fresh.dispose();
      }
      if (!original) original = built.bytes;
      if (source === before) assert.deepEqual(built.bytes, original);
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
