import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun } from "./reduction_helpers.ts";
const stdRoot = new URL("../../std", import.meta.url).pathname;

Deno.test("cursor directories preserve snapshots pressure and changed producer replay in both tiers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-cursor-directory-",
  });
  const entry = `${directory}/main.blot`;
  const helper = `${directory}/rows.blot`;
  const program = `import * as rows from "./rows"
entry const run = fn count => do:
  let values = rows.make count
  let warm = 0
  for row in values:
    warm := self + row.x + row.y + row.z
  let cursor = @list.cursor values
  let old = cursor
  if count != 0:
    values := [@record.merge (@cursor.value (@list.cursor self)) {x: 777, y: 778, z: 779}, ...self]
  let total = 0
  for 0..count:
    let pressure = @array.fill 8192 41
    if pressure[8191] != 41:
      @panic "pressure"
    let row = @cursor.value cursor
    total := self + row.x + row.y + row.z
    cursor := @cursor.advance self
  if count == 0:
    break #[warm, total, 0, 0]
  break #[warm, total, (@cursor.value old).x, (@cursor.value (@list.cursor values)).x]
`;
  const producer = (sliced: boolean, wide = false) => {
    let row = "{x: i, y: i + 1, z: i + 2}";
    if (wide) row = "{x: i, y: i + 1, z: i + 2, w: i + 3}";
    if (sliced) {
      return `const make = fn count => @list.slice (@list.generate (count + 2) (fn i => ${row})) 1 count\n`;
    }
    return `const make = fn count => @list.generate count (fn i => ${row})\n`;
  };
  const execute = async (bytes: Uint8Array<ArrayBuffer>, sliced: boolean) => {
    const guest = await instantiateGuest(bytes);
    try {
      for (const count of [0, 1, 80, 81, 82, 244, 245, 1000]) {
        let total = 3 * count * (count + 1) / 2;
        let first = 0;
        let changed = 0;
        if (sliced) total += 3 * count;
        if (count !== 0) {
          if (sliced) first = 1;
          changed = 777;
        }
        assert.deepEqual(
          guest.call("run", count),
          Uint32Array.of(total, total, first, changed),
        );
      }
    } finally {
      guest.dispose();
    }
  };
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable: Deno.args[0],
        entry,
        codegenTier,
        prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
        stdRoot,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      let checkpoint;
      try {
        for (
          const [sliced, wide] of [
            [false, false],
            [false, false],
            [true, false],
            [true, true],
            [false, false],
          ]
        ) {
          const sources = {
            [entry]: program,
            [helper]: producer(sliced, wide),
          };
          const built = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const ordinary = await fresh.build({ sources });
            assert(built.success && ordinary.success, JSON.stringify(built));
            assert.deepEqual(built.bytes, ordinary.bytes);
            await execute(built.bytes, sliced);
          } finally {
            await fresh.dispose();
          }
        }
        checkpoint = await retained.exportCheckpoint();
      } finally {
        await retained.dispose();
      }
      const resumed = await createZigProjectCompiler({
        ...options,
        checkpoint,
      });
      const fresh = await createZigProjectCompiler(options);
      try {
        const sources = { [entry]: program, [helper]: producer(true, true) };
        const built = await resumed.build({ sources });
        const ordinary = await fresh.build({ sources });
        assert(built.success && ordinary.success, JSON.stringify(built));
        assert.deepEqual(built.bytes, ordinary.bytes);
        await execute(built.bytes, true);
        if (codegenTier === "optimized") {
          const optimization = built.stats.runtimeOptimization as Record<
            string,
            number
          >;
          assert(optimization.reused > 0, JSON.stringify(optimization));
        }
      } finally {
        await resumed.dispose();
        await fresh.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("static packed directories retain scalar leaf addresses through snapshot pressure", async () => {
  const rows = Array.from({ length: 245 }, (_, i) => `(${i},${i + 1},${i + 2})`)
    .join(",");
  await compileAndRun(
    `const saved = [${rows}]
entry const run = fn count => do:
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
