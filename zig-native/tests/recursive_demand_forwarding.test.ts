import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

for (const annotation of ["", ": U32 -> ~U32 -> U32"]) {
  Deno.test(`recursive demand forwarding terminates through curried calls ${annotation}`, async () => {
    await compileAndRun(
      `
const recursive${annotation} = func (count: U32) => return func ~(value: U32) => return
  if @u32.eq count 0 then @demand value
  else recursive (@u32.sub count 1) (@demand value)
entry const run = func (count: U32) => return recursive count 42
`,
      (guest) => {
        for (const count of [0, 1, 2, 9, 32]) {
          equal(guest.call("run", count), 42);
        }
      },
    );
  });
  Deno.test(`mutual demand forwarding keeps one shared argument ${annotation}`, async () => {
    await compileAndRun(
      `
const even${annotation} = func (count: U32) => return func ~(value: U32) => return
  if @u32.eq count 0 then @u32.add (@demand value) (@demand value)
  else odd (@u32.sub count 1) (@demand value)
const odd${annotation} = func (count: U32) => return func ~(value: U32) => return
  if @u32.eq count 0 then @u32.add (@demand value) (@demand value)
  else even (@u32.sub count 1) (@demand value)
entry const run = func (count: U32) => return even count 21
`,
      (guest) => {
        for (const count of [0, 1, 2, 9, 32]) {
          equal(guest.call("run", count), 42);
        }
      },
    );
  });
}

Deno.test("recursive demand mode remains checked in unused ill-typed bodies", async () => {
  await compileExpectedFailure(
    `
const wrong: ~U32 -> U32 = func ~(value: U32) => return
  if true then wrong (@demand value) else false
entry const unused = 42
`,
    "type_mismatch",
  );
});

Deno.test("recursive demand forwarding preserves retained edits rejection and recovery", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-recursive-demand-",
  });
  const entry = `${directory}/main.blot`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
    cacheDirectory: false as const,
  };
  const source = (value: number) => `
const recursive = func (count: U32) => return func ~value => return
  if @u32.eq count 0 then @demand value
  else recursive (@u32.sub count 1) (@demand value)
entry const run = func (count: U32) => return recursive count ${value}
`;
  const retained = await createZigProjectCompiler(options);
  try {
    let revision = 0;
    for (const value of [42, 43, 42]) {
      const sources = { [entry]: source(value) };
      const result = await retained.build({ sources });
      assert(result.success, JSON.stringify(result));
      assert.equal(result.revision, ++revision);
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert(expected.success, JSON.stringify(expected));
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        try {
          for (const count of [0, 1, 9, 32]) {
            equal(guest.call("run", count), value);
          }
        } finally {
          guest.dispose();
        }
      } finally {
        await fresh.dispose();
      }
      const rejected = await retained.build({
        sources: { [entry]: source(value) + "\nconst wrong: U32 = false\n" },
      });
      assert(!rejected.success);
      assert.equal(rejected.revision, revision);
      assert.equal(rejected.diagnostics[0].code, "type_mismatch");
      const recovered = await retained.build({ sources });
      assert(recovered.success);
      assert.equal(recovered.revision, ++revision);
      assert.deepEqual(recovered.bytes, result.bytes);
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
