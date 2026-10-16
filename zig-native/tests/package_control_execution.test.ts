import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const fixture = await Deno.readTextFile(
  new URL("../fixtures/package/ordinary-control.blot", import.meta.url),
);
const source = `${fixture}
entry const control = fn (seed: U32) => @u32.add (choose (loop seed)) (update seed)
entry const requested = fn (host: U32 -> U32 ! {Foreign}) => request host
entry const delayed = fn (host: U32 -> U32 ! {Foreign}) => demand (host 2)
`;
Deno.test("portable ordinary control executes request carries patterns updates and demand once after checkpoint restart", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  await Deno.writeTextFile(entry, source);
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable,
        entry,
        codegenTier,
        cacheDirectory: false as const,
        prelude: null,
      };
      const compiler = await createZigProjectCompiler(options);
      try {
        const first = await compiler.build({ sources: { [entry]: source } });
        assert(first.success, JSON.stringify(first));
        const checkpoint = await compiler.exportCheckpoint();
        const restored = await createZigProjectCompiler({
          ...options,
          checkpoint,
        });
        try {
          const replayed = await restored.build({
            sources: { [entry]: source },
          });
          assert(replayed.success, JSON.stringify(replayed));
          assert.deepEqual(replayed.bytes, first.bytes);
          for (const bytes of [first.bytes, replayed.bytes]) {
            for (const asynchronous of [false, true]) {
              const guest = await instantiateGuest(bytes, { asynchronous });
              const trace: number[] = [];
              const implementation = {
                parameter: "U32" as const,
                result: "U32" as const,
                call(value: number) {
                  trace.push(value);
                  return value + 10;
                },
              };
              let host = guest.capability(implementation);
              if (asynchronous) host = guest.capabilityAsync(implementation);
              try {
                if (asynchronous) {
                  assert.equal(await guest.callAsync("control", 4), 13);
                  assert.equal(await guest.callAsync("requested", host), 13);
                  assert.equal(await guest.callAsync("delayed", host), 24);
                } else {
                  assert.equal(guest.call("control", 4), 13);
                  assert.equal(guest.call("requested", host), 13);
                  assert.equal(guest.call("delayed", host), 24);
                }
                assert.deepEqual(trace, [2, 2]);
              } finally {
                guest.dispose();
              }
            }
          }
        } finally {
          await restored.dispose();
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
