import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = `
const add22 = fn value => @u32.add value 22
const add_half = fn value => @f32.add value 0.5
const await = fn source => |source|
const await_alias = await
entry const answer = fn () => @task.scope (fn group => do:
  let left = *(add22 20)
  let right = @task.spawn group (fn () => 0)
  return @u32.add (|left|) (|right|))
entry const branch = fn (choice: Bool) => do:
  if choice:
    return 42
  return 5
entry const sparked = fn () => @task.scope (fn group => do:
  let pending = *(add22 20)
  return |pending|)
entry const nested = fn () => @task.scope (fn outer => do:
  let first = *(add22 0)
  let second = @task.scope (fn inner => do:
    let pending = *(add22 20)
    return |pending|)
  return @u32.add (|first|) second)
entry const wrapped = fn () => @task.scope (fn group => do:
  let pending = *(add22 20)
  return await pending)
entry const wrapped_alias = fn () => @task.scope (fn group => do:
  let pending = *(add22 20)
  return await_alias pending)
entry const direct_f32 = fn () => @task.scope (fn group => do:
  let pending = *(add_half 1.0)
  return |pending|)
entry const wrapped_f32 = fn () => @task.scope (fn group => do:
  let pending = *(add_half 1.0)
  return await pending)
`;

Deno.test("spark and receive use explicit task scopes in both tiers", async () => {
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
              assert.equal(await guest.callAsync("nested", null), 64);
              assert.equal(await guest.callAsync("wrapped", null), 42);
              assert.equal(await guest.callAsync("wrapped_alias", null), 42);
              assert.equal(await guest.callAsync("direct_f32", null), 1.5);
              assert.equal(await guest.callAsync("wrapped_f32", null), 1.5);
            } else {
              assert.equal(guest.call("answer", null), 42);
              assert.equal(guest.call("branch", true), 42);
              assert.equal(guest.call("branch", false), 5);
              assert.equal(guest.call("sparked", null), 42);
              assert.equal(guest.call("nested", null), 64);
              assert.equal(guest.call("wrapped", null), 42);
              assert.equal(guest.call("wrapped_alias", null), 42);
              assert.equal(guest.call("direct_f32", null), 1.5);
              assert.equal(guest.call("wrapped_f32", null), 1.5);
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

Deno.test("imported and renamed task receivers preserve their checked contract", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-task-import-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/task.blot`;
  const main = `import {await as imported} from "./task"
entry const answer = fn () => @task.scope (fn group => do:
  let pending = @task.spawn group (fn () => 42)
  return imported pending)
`;
  const task = "const await = fn source => |source|\n";
  const executable = Deno.args[0] ?? new URL("../zig-out/bin/blotc", import.meta.url);
  try {
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(dependency, task);
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      });
      try {
        const build = await compiler.build({ sources: { [entry]: main, [dependency]: task } });
        assert(build.success, JSON.stringify(build));
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(build.bytes, { asynchronous });
          try {
            assert.equal(asynchronous ? await guest.callAsync("answer", null) : guest.call("answer", null), 42);
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
