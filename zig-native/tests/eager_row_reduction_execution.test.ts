import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun } from "./reduction_helpers.ts";

const stdRoot = new URL("../../std", import.meta.url).pathname;
function program(width: number, bias: number, pressure = false) {
  const names = Array.from({ length: width }, (_, field) => `f${field}`);
  const fields = names.map((_, field) =>
    `input[2 + (index + ${field}) % (input.length - 2)] + ${bias}`
  );
  let garbage = "";
  if (pressure) garbage = "    let garbage = @array.fill 8192 index\n";
  return `entry const run_${width} = func (input: Array U32) => return do:
  let count = input[0]
  let rows = @list.generate count (func index => return (${fields.join(", ")}))
  let cursor = @list.cursor rows
  let total = input[1]
  for index in 0..count:
    let (${names.join(", ")}) = @cursor.value cursor
    total := self + ${names.join(" + ")}
${garbage}    cursor := @cursor.advance self
  break total
entry const probe_${width} = func (seed: U32) => return #[seed]
`;
}
const values = Uint32Array.of(0xffffffff, 0x80000000, 0, 1, 17, 99);
function expected(width: number, count: number, bias: number) {
  let total = 0xfffffff7;
  for (let row = 0; row < count; row++) {
    for (let field = 0; field < width; field++) {
      total =
        (total + ((values[(row + field) % values.length] + bias) >>> 0)) >>> 0;
    }
  }
  return total;
}
async function execute(
  bytes: Uint8Array<ArrayBuffer>,
  widths: number[],
  bias: number,
) {
  const guest = await instantiateGuest(bytes);
  try {
    for (const width of widths) {
      assert.equal(
        guest.call(`run_${width}`, Uint32Array.of(0, 0xfffffff7)),
        0xfffffff7,
      );
      for (const count of [1, Math.floor(244 / width) + 1, 257]) {
        assert.equal(
          guest.call(
            `run_${width}`,
            Uint32Array.of(count, 0xfffffff7, ...values),
          ),
          expected(width, count, bias),
        );
      }
      assert.throws(() => guest.call(`run_${width}`, Uint32Array.of(1, 0)));
      assert.equal(
        guest.call(`run_${width}`, Uint32Array.of(1, 0xfffffff7, ...values)),
        expected(width, 1, bias),
      );
    }
  } finally {
    guest.dispose();
  }
}
Deno.test("eager tuple reductions preserve wrapping tails traps and collection roots in both tiers", async () => {
  const widths = Array.from({ length: 15 }, (_, index) => index + 2);
  await compileAndRun(
    widths.map((width) => program(width, 0)).join("\n"),
    async (_guest, bytes) => {
      await execute(bytes, widths, 0);
    },
    { stdRoot },
  );
  await compileAndRun(program(9, 0, true), async (_guest, bytes) => {
    await execute(bytes, [9], 0);
  }, { stdRoot });
});
Deno.test("eager tuple reductions replay exact fresh retained and portable outputs after edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-eager-reduction-" });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable: Deno.args[0],
        entry,
        codegenTier,
        stdRoot,
        prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      let checkpoint;
      try {
        for (const bias of [0, 0, 1, 0]) {
          const sources = { [entry]: program(9, bias) };
          const built = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const ordinary = await fresh.build({ sources });
            assert(built.success && ordinary.success, JSON.stringify(built));
            assert.deepEqual(built.bytes, ordinary.bytes);
            await execute(built.bytes, [9], bias);
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
        const sources = { [entry]: program(9, 0) };
        const built = await resumed.build({ sources });
        const ordinary = await fresh.build({ sources });
        assert(built.success && ordinary.success, JSON.stringify(built));
        assert.deepEqual(built.bytes, ordinary.bytes);
        await execute(built.bytes, [9], 0);
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
