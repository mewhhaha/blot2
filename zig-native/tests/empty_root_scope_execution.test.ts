import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = `let rows = @list.generate 700 (fn index => {value: index})
entry const pure = fn (limit: U32) => do:
  let total = 0
  for row in rows:
    if row.value == limit:
      break
    total := self + row.value
  return total
entry const trap = fn (divisor: U32) => do:
  let total = 0
  for row in rows:
    total := self + row.value / divisor
  return total
entry const effects = fn (host: U32 -> U32 ! {Foreign}) => do:
  let owner = #[40, 2]
  let total = 0
  for row in rows:
    use value <- host row.value
    let pressure = @array.fill 4096 value
    total := self + pressure[4095]
  return total + owner[0] + owner[1]
`;

Deno.test("empty lexical frames preserve packed folds traps foreign allocation and suspension fallback", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-empty-scopes-" });
  const entry = `${directory}/main.blot`;
  const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        prelude,
        codegenTier,
        cacheDirectory: false,
      });
      try {
        const built = await compiler.build({ sources: { [entry]: source } });
        assert(built.success, JSON.stringify(built));
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          const invoke = async (name: string, argument: unknown) => {
            if (asynchronous) return await guest.callAsync(name, argument);
            return guest.call(name, argument);
          };
          try {
            for (const count of [0, 1, 243, 244, 245, 699, 700, 701]) {
              const size = Math.min(count, 700);
              assert.equal(
                await invoke("pure", count),
                (size * (size - 1) / 2) >>> 0,
              );
            }
            await assert.rejects(invoke("trap", 0));
            assert.equal(await invoke("trap", 1), 700 * 699 / 2);
            const trace: number[] = [];
            let stop = false;
            const observe = (value: number) => {
              trace.push(value);
              if (stop && value === 17) throw new Error("stop");
              return value + 1;
            };
            let host;
            if (asynchronous) {
              host = guest.capabilityAsync({
                parameter: "U32",
                result: "U32",
                call: async (value) => {
                  await Promise.resolve();
                  return observe(value);
                },
              });
            } else {
              host = guest.capability({
                parameter: "U32",
                result: "U32",
                call: observe,
              });
            }
            const expected = 700 * 701 / 2 + 42;
            assert.equal(await invoke("effects", host), expected);
            assert.deepEqual(trace, Array.from({ length: 700 }, (_, i) => i));
            trace.length = 0;
            stop = true;
            await assert.rejects(invoke("effects", host));
            assert.deepEqual(trace, Array.from({ length: 18 }, (_, i) => i));
            trace.length = 0;
            stop = false;
            assert.equal(await invoke("effects", host), expected);
            assert.deepEqual(trace, Array.from({ length: 700 }, (_, i) => i));
            assert.equal(await invoke("pure", 700), 700 * 699 / 2);
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
