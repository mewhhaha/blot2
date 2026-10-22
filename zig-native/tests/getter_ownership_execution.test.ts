import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `
const make = fn () => fn holder => holder.value
const read = make ()
const apply = fn getter => fn holder => getter holder
entry const run = fn (count: U32) => do:
  let holder = { bits: 65568, floating: -0.0, value: #[7, 42] }
  let alias = apply read holder
  holder.value := #[90, 91]
  for index in 0..count:
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      @panic "lost pressure"
  break #[alias[0], alias[1], holder.value[0]]
entry const bits = fn () => apply (fn holder => holder.bits) { bits: 65568, value: #[99] }
entry const floating = fn () => apply (fn holder => holder.floating) { floating: -0.0, value: #[99] }
entry const failed = fn (host: Array U32 -> Unit ! {Foreign}) => do:
  let holder = { value: #[7, 42] }
  let alias = apply read holder
  holder.value := #[90, 91]
  use host alias
  break alias[1]
`;

Deno.test("checked getter results survive field replacement suspension failure and producer edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-getter-" });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      for (const shareMachineCode of [false, true]) {
        const compiler = await createZigProjectCompiler({
          executable,
          entry,
          prelude: new URL("../../std/prelude.blot", import.meta.url),
          cacheDirectory: false,
          codegenTier,
          shareMachineCode,
        });
        try {
          const edited = source.replace(
            "holder => holder.value",
            "holder => @array.set holder.value 0 (holder.value[0] + 1)",
          );
          for (const [revision, text] of [source, edited, source].entries()) {
            const built = await compiler.build({ sources: { [entry]: text } });
            assert(built.success, JSON.stringify(built));
            const fresh = await createZigProjectCompiler({
              executable,
              entry,
              prelude: new URL("../../std/prelude.blot", import.meta.url),
              cacheDirectory: false,
              codegenTier,
              shareMachineCode,
            });
            try {
              const rebuilt = await fresh.build({ sources: { [entry]: text } });
              assert(rebuilt.success, JSON.stringify(rebuilt));
              assert.deepEqual(built.bytes, rebuilt.bytes);
            } finally {
              await fresh.dispose();
            }
            const module = new WebAssembly.Module(built.bytes);
            assert.deepEqual([
              ...new Uint8Array(
                WebAssembly.Module.customSections(module, "blot:ownership")[0],
              ),
            ], [2, 2, 0]);
            let first = 7;
            if (revision === 1) first = 8;
            for (const asynchronous of [false, true]) {
              const guest = await instantiateGuest(module, {
                asynchronous,
              });
              try {
                let warmed = 0;
                for (const count of [8, 200, 8]) {
                  let values;
                  if (asynchronous) {
                    values = await guest.callAsync("run", count);
                  } else values = guest.call("run", count);
                  assert.deepEqual(values, Uint32Array.of(first, 42, 90));
                  if (warmed) assert(guest.memoryBytes() <= warmed + 65536);
                  else warmed = guest.memoryBytes();
                }
                let bits, floating;
                if (asynchronous) {
                  bits = await guest.callAsync("bits", null);
                  floating = await guest.callAsync("floating", null);
                } else {
                  bits = guest.call("bits", null);
                  floating = guest.call("floating", null);
                }
                assert.equal(bits, 65568);
                assert(Object.is(floating, -0));
                const cause = new Error("suspended getter callback canceled");
                const check = (values: Uint32Array): never => {
                  assert.deepEqual(values, Uint32Array.of(first, 42));
                  throw cause;
                };
                if (asynchronous) {
                  const host = guest.capabilityAsync({
                    parameter: "Array U32",
                    result: "Unit",
                    call: async (values) => {
                      await Promise.resolve();
                      return check(values);
                    },
                  });
                  await assert.rejects(
                    guest.callAsync("failed", host),
                    (error) =>
                      error instanceof Error &&
                      (error === cause || error.cause === cause),
                  );
                  assert.deepEqual(
                    await guest.callAsync("run", 8),
                    Uint32Array.of(first, 42, 90),
                  );
                } else {
                  const host = guest.capability({
                    parameter: "Array U32",
                    result: "Unit",
                    call: (values) => check(values),
                  });
                  assert.throws(
                    () => guest.call("failed", host),
                    (error) =>
                      error instanceof Error &&
                      (error === cause || error.cause === cause),
                  );
                  assert.deepEqual(
                    guest.call("run", 8),
                    Uint32Array.of(first, 42, 90),
                  );
                }
                assert(guest.memoryBytes() <= warmed + 65536);
              } finally {
                guest.dispose();
              }
            }
          }
        } finally {
          await compiler.dispose();
        }
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
