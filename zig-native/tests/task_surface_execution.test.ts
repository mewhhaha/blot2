import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = `
const add22 = fn value => @u32.add value 22
entry const answer = fn () => tasks group:
  let left = async group:
    finish 20
  let right = async group:
    do:
      finish 22
  finish @u32.add (@task.join left) (@task.join right)
entry const branch = fn (choice: Bool) => tasks group:
  if choice:
    finish 42
  finish 5
entry const sparked = fn () => tasks group:
  let pending = *(add22 20)
  finish |pending|
`;

Deno.test("task surface blocks preserve function exits and results in both tiers", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-task-surface-" });
  const entry = `${directory}/main.blot`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      });
      try {
        const build = await compiler.build({ sources: { [entry]: source } });
        assert(build.success, JSON.stringify(build));
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(build.bytes, { asynchronous });
          try {
            if (asynchronous) {
              assert.equal(await guest.callAsync("answer", null), 42);
              assert.equal(await guest.callAsync("branch", true), 42);
              assert.equal(await guest.callAsync("branch", false), 5);
              assert.equal(await guest.callAsync("sparked", null), 42);
            } else {
              assert.equal(guest.call("answer", null), 42);
              assert.equal(guest.call("branch", true), 42);
              assert.equal(guest.call("branch", false), 5);
              assert.equal(guest.call("sparked", null), 42);
            }
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
