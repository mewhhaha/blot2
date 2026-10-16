import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `
const keep = fn ~value => fn () => @demand value
entry const run = fn (host: U32 -> Array U32 ! {Foreign}) => do:
  let seed = 41
  let delayed = keep (host seed)
  let alias = delayed
  seed := 99
  use first <- delayed ()
  let pressure = @array.fill 8192 seed
  use second <- alias ()
  return first[0] + second[0] + pressure[0]
entry const floating = fn (host: F32 -> F32 ! {Foreign}) => do:
  let delayed = keep (host (-0.0))
  let alias = delayed
  use first <- delayed ()
  use second <- alias ()
  return second
`;

Deno.test("retained demand producer descriptors preserve memo aliases snapshots signed zero cancellation and producer edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-retained-demand-" });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
        codegenTier,
        shareMachineCode: true,
      });
      try {
        for (
          const [revision, text] of [
            source,
            source.replace("host seed", "host (seed + 1)"),
            source,
          ].entries()
        ) {
          const built = await compiler.build({ sources: { [entry]: text } });
          assert(built.success, JSON.stringify(built));
          const fresh = await createZigProjectCompiler({
            executable,
            entry,
            prelude: new URL("../../std/prelude.blot", import.meta.url),
            cacheDirectory: false,
            codegenTier,
            shareMachineCode: true,
          });
          try {
            const rebuilt = await fresh.build({ sources: { [entry]: text } });
            assert(rebuilt.success, JSON.stringify(rebuilt));
            assert.deepEqual(built.bytes, rebuilt.bytes);
          } finally {
            await fresh.dispose();
          }
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(built.bytes, { asynchronous });
            try {
              let calls = 0;
              let failed = false;
              const cause = new Error("deferred producer failed");
              let expectedSeed = 41;
              if (revision === 1) expectedSeed = 42;
              const invoke = (value: number) => {
                calls++;
                if (failed) throw cause;
                assert.equal(value, expectedSeed);
                return Uint32Array.of(value);
              };
              let host;
              if (asynchronous) {
                host = guest.capabilityAsync({
                  parameter: "U32",
                  result: "Array U32",
                  call: async (value) => {
                    await Promise.resolve();
                    return invoke(value);
                  },
                });
              } else {host = guest.capability({
                  parameter: "U32",
                  result: "Array U32",
                  call: invoke,
                });}
              const run = async () => {
                if (asynchronous) return await guest.callAsync("run", host);
                return guest.call("run", host);
              };
              assert.equal(await run(), expectedSeed * 2 + 99);
              assert.equal(calls, 1);
              failed = true;
              await assert.rejects(
                async () => await run(),
                (error) => error instanceof Error && error.cause === cause,
              );
              failed = false;
              assert.equal(await run(), expectedSeed * 2 + 99);
              assert.equal(calls, 3);
              let floatingCalls = 0;
              const negativeZero = (value: number) => {
                floatingCalls++;
                assert(Object.is(value, -0));
                return value;
              };
              let floating;
              if (asynchronous) {
                floating = guest.capabilityAsync({
                  parameter: "F32",
                  result: "F32",
                  call: async (value) => {
                    await Promise.resolve();
                    return negativeZero(value);
                  },
                });
              } else {floating = guest.capability({
                  parameter: "F32",
                  result: "F32",
                  call: negativeZero,
                });}
              let result;
              if (asynchronous) {
                result = await guest.callAsync("floating", floating);
              } else result = guest.call("floating", floating);
              assert(Object.is(result, -0));
              assert.equal(floatingCalls, 1);
            } finally {
              guest.dispose();
            }
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
