import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";
import { compileAndRun } from "./reduction_helpers.ts";
const stdRoot = new URL("../../std", import.meta.url).pathname;

Deno.test("static packed directories retain scalar leaf addresses through snapshot pressure", async () => {
  const rows = Array.from({ length: 245 }, (_, i) => `(${i},${i + 1},${i + 2})`)
    .join(",");
  await compileAndRun(
    `const saved = [${rows}]
entry const run = func count => return do:
  let cursor = @list.cursor saved
  let old = cursor
  let total = 0
  for 0..count:
    let pressure = @array.fill 8192 41
    if pressure[8191] != 41:
      @panic "pressure"
    let (x,y,z) = @cursor.value cursor
    total := self + x + y + z
    cursor := @cursor.advance self
  let (x,y,z) = @cursor.value old
  break total + x + y + z
`,
    (guest) => {
      for (const count of [0, 1, 81, 82, 244, 245]) {
        assert.equal(
          guest.call("run", count),
          3 * count * (count + 1) / 2 + 3,
        );
      }
    },
    { stdRoot },
  );
});
