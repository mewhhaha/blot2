import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("imported generic access projections retain field names without concrete record types", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-storage-fields-" });
  const entry = `${directory}/main.blot`;
  try {
    await Deno.writeTextFile(
      `${directory}/access.blot`,
      `const write = func access -> (value: U32) => return do:
  let rows: Array U32 = access.rows
  rows[0] := value
  return rows[0]
`,
    );
    await Deno.writeTextFile(
      entry,
      `import * as access from "./access"
entry const answer = func (value: U32) => return do:
  let marker: GrowArray U32 = #[]
  let rows: Array U32 = #[0]
  let result = access.write {rows} value
  return rows[0]
`,
    );
    const compiler = await createZigProjectCompiler({
      executable: resolve(Deno.args[0] ?? "zig-native/zig-out/bin/blotc"),
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

Deno.test("project storage budgets bound growth and cannot reuse output from a different budget", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-storage-budgets-" });
  const entry = `${directory}/main.blot`;
  try {
    await Deno.writeTextFile(
      entry,
      `entry const count = func (size: U32) => return do:
  let values: GrowArray U32 = #[]
  for i in 0 .. size:
    @storage.push values i
  return @storage.length values
`,
    );
    const outputs: Uint8Array[] = [];
    for (const growerBytes of [64, 256, 64]) {
      const compiler = await createZigProjectCompiler({
        executable: resolve(Deno.args[0] ?? "zig-native/zig-out/bin/blotc"),
        entry,
        prelude: null,
        cacheDirectory: `${directory}/cache`,
        storage: { growerBytes },
      });
      try {
        const built = await compiler.build();
        assert(built.success, JSON.stringify(built));
        outputs.push(built.bytes);
        const guest = await instantiateGuest(built.bytes);
        try {
          assert.equal(guest.call("count", 4), 4);
          if (growerBytes === 64) assert.throws(() => guest.call("count", 32));
          else assert.equal(guest.call("count", 32), 32);
          assert.equal(guest.call("count", 4), 4);
        } finally {
          guest.dispose();
        }
        const retained = await compiler.build();
        assert(retained.success, JSON.stringify(retained));
        assert.deepEqual(retained.bytes, built.bytes);
      } finally {
        await compiler.close();
      }
    }
    assert.deepEqual(outputs[0], outputs[2]);
    assert.notDeepEqual(outputs[0], outputs[1]);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("project service retains data-stack output across edits errors and backend changes", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-storage-project-" });
  const entry = `${directory}/main.blot`;
  const source = (value: number) =>
    `const values: GrowArray U32 = #[${value}]
entry const answer = func () => return values[0]
`;
  try {
    await Deno.writeTextFile(entry, source(41));
    const compiler = await createZigProjectCompiler({
      executable: resolve(Deno.args[0] ?? "zig-native/zig-out/bin/blotc"),
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
