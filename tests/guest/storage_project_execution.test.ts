import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

Deno.test("imported generic access projections retain field names without concrete record types", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-storage-fields-" });
  const entry = `${directory}/main.blot`;
  try {
    await Deno.writeTextFile(
      `${directory}/access.blot`,
      `const write = func (own access) -> (value: U32) => return do:
  access.rows[0] := value
  return access
`,
    );
    await Deno.writeTextFile(
      entry,
      `import * as access from "./access"
entry const answer = func (value: U32) => return do:
  let marker: Array U32 = #[]
  let rows: Array U32 = #[0]
  let result = access.write {rows} value
  return result.rows[0]
`,
    );
    const compiler = await createZigProjectCompiler({
      executable: resolve(Deno.args[0] ?? "compiler-goose/build/blotc-goose"),
      entry,
      prelude: null,
    });
    try {
      const built = await compiler.build();
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        assert.equal(guest.call("answer", 42), 42);
        assert.equal(guest.call("answer", 7), 7);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.close();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("project service retains data-stack output across edits errors and backend changes", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-storage-project-" });
  const entry = `${directory}/main.blot`;
  const source = (value: number) =>
    `const values: Array U32 = #[${value}]
entry const answer = func () => return values[0]
`;
  try {
    await Deno.writeTextFile(entry, source(41));
    const compiler = await createZigProjectCompiler({
      executable: resolve(Deno.args[0] ?? "compiler-goose/build/blotc-goose"),
      entry,
      prelude: null,
    });
    try {
      const run = async (expected: number) => {
        const built = await compiler.build();
        assert(built.success, JSON.stringify(built));
        const guest = await instantiateGuest(built.bytes);
        try {
          assert.equal(guest.call("answer", null), expected);
        } finally {
          guest.dispose();
        }
        return built.bytes;
      };
      const first = await run(41);
      assert.deepEqual(await run(41), first);
      await Deno.writeTextFile(entry, source(42));
      const changed = await run(42);
      assert.notDeepEqual(changed, first);
      await Deno.writeTextFile(
        entry,
        source(42).replace("values[0]", "missing"),
      );
      assert.equal((await compiler.build()).success, false);
      await Deno.writeTextFile(entry, source(42));
      assert.deepEqual(await run(42), changed);
      await Deno.writeTextFile(
        entry,
        "entry const answer = func () => return 43\n",
      );
      await run(43);
      await Deno.writeTextFile(entry, source(41));
      assert.deepEqual(await run(41), first);
    } finally {
      await compiler.close();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
