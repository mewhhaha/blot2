import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = `
const add22 = fn value => @u32.add value 22
const add_half = fn value => @f32.add value 0.5
const await = fn source => |source|
const await_alias = await
const scope = fn body => @task.scope body
const launch = fn group => fn action => @task.spawn group action
const launch_alias = launch
const region = scope
const relay = fn body => scope body
const wrap = fn () => fn body => scope body
const identity = fn value => value
const curried = identity (wrap ())
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
entry const shadowed_group = fn () => @task.scope (fn group => do:
  let group = 100
  let pending = *(add22 20)
  return @u32.add group (|pending|))
entry const wrapped_scope = fn () => region (fn group => do:
  let pending = *(add22 20)
  return |pending|)
entry const relayed_scope = fn () => relay (fn group => do:
  let pending = *(add22 20)
  return |pending|)
entry const curried_scope = fn () => curried (fn group => @task.join (@task.spawn group (fn () => 42)))
entry const collected = fn () => scope (fn group => do:
  let left = *(add22 20)
  let right = *(add22 0)
  let (first, second) = |(left, right)|
  return @u32.add first second)
entry const held_collection = fn () => scope (fn group => do:
  let left = *(add22 20)
  let right = *(add22 0)
  let receivers = (left, right)
  let (first, second) = |receivers|
  return @u32.add first second)
entry const helper_collection = fn () => scope (fn group => do:
  let left = *(add22 20)
  let right = *(add22 0)
  let receivers = (left, right)
  let (first, second) = await receivers
  return @u32.add first second)
entry const mixed_collection = fn () => scope (fn group => do:
  let left = *(add22 20)
  let right = *(add_half 1.0)
  let (first, second) = |(left, right)|
  return @f32.add (@u32.to_f32 first) second)
entry const tuple_payload = fn () => scope (fn group => do:
  let pending = @task.spawn group (fn () => (20, 22))
  let (first, second) = |pending|
  return @u32.add first second)
entry const spawned_helper = fn () => scope (fn group => do:
  let launch_here = launch_alias group
  let alias = launch_here
  let pending = alias (fn () => 42)
  return |pending|)
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
              assert.equal(await guest.callAsync("shadowed_group", null), 142);
              assert.equal(await guest.callAsync("wrapped_scope", null), 42);
              assert.equal(await guest.callAsync("relayed_scope", null), 42);
              assert.equal(await guest.callAsync("curried_scope", null), 42);
              assert.equal(await guest.callAsync("collected", null), 64);
              assert.equal(await guest.callAsync("held_collection", null), 64);
              assert.equal(
                await guest.callAsync("helper_collection", null),
                64,
              );
              assert.equal(
                await guest.callAsync("mixed_collection", null),
                43.5,
              );
              assert.equal(await guest.callAsync("tuple_payload", null), 42);
              assert.equal(await guest.callAsync("spawned_helper", null), 42);
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
              assert.equal(guest.call("shadowed_group", null), 142);
              assert.equal(guest.call("wrapped_scope", null), 42);
              assert.equal(guest.call("relayed_scope", null), 42);
              assert.equal(guest.call("curried_scope", null), 42);
              assert.equal(guest.call("collected", null), 64);
              assert.equal(guest.call("held_collection", null), 64);
              assert.equal(guest.call("helper_collection", null), 64);
              assert.equal(guest.call("mixed_collection", null), 43.5);
              assert.equal(guest.call("tuple_payload", null), 42);
              assert.equal(guest.call("spawned_helper", null), 42);
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
  const main =
    `import {await as original, alias as imported, scope as region, launch_alias as spawn} from "./task"
entry const answer = fn () => @task.scope (fn group => do:
  let pending = @task.spawn group (fn () => 42)
  return original pending)
entry const scoped = fn () => region (fn group => do:
  let pending = @task.spawn group (fn () => 42)
  return imported pending)
entry const collected = fn () => region (fn group => do:
  let first = @task.spawn group (fn () => 20)
  let second = @task.spawn group (fn () => 22)
  let (left, right) = imported (first, second)
  return @u32.add left right)
entry const spawned = fn () => region (fn group => do:
  let here = spawn group
  let pending = here (fn () => 42)
  return imported pending)
`;
  const task =
    "const await = fn source => |source|\nconst alias = await\nconst scope = fn body => @task.scope body\nconst launch = fn group => fn action => @task.spawn group action\nconst launch_alias = launch\n";
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
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
        let initial: Uint8Array | undefined;
        for (
          const [round, edited] of [main, main.replaceAll("42", "43"), main]
            .entries()
        ) {
          const build = await compiler.build({
            sources: { [entry]: edited, [dependency]: task },
          });
          assert(build.success, JSON.stringify({ codegenTier, round, build }));
          if (round === 0) initial = build.bytes.slice();
          if (round === 2) assert.deepEqual(build.bytes, initial);
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(build.bytes, { asynchronous });
            try {
              for (const name of ["answer", "scoped", "collected", "spawned"]) {
                assert.equal(
                  asynchronous
                    ? await guest.callAsync(name, null)
                    : guest.call(name, null),
                  round === 1 && name !== "collected" ? 43 : 42,
                );
              }
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

Deno.test("spawn helper presence follows imported revisions and restart in both tiers", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-spawn-revision-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/helper.blot`;
  const ordinary = "const value = fn () => 41\n";
  const helper = ordinary +
    "const launch = fn group => fn action => @task.spawn group action\nconst alias = launch\n";
  const plain = `import * as helper from "./helper"
entry const answer = fn () => @u32.add (helper.value ()) 1
`;
  const spawned = `import {alias as launch, value} from "./helper"
entry const answer = fn () => @task.scope (fn group => do:
  let here = launch group
  let pending = here (fn () => @u32.add (value ()) 2)
  return |pending|)
`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
  const execute = async (bytes: Uint8Array<ArrayBuffer>, expected: number) => {
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        assert.equal(
          asynchronous
            ? await guest.callAsync("answer", null)
            : guest.call("answer", null),
          expected,
        );
      } finally {
        guest.dispose();
      }
    }
  };
  try {
    await Deno.writeTextFile(entry, plain);
    await Deno.writeTextFile(dependency, ordinary);
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false as const,
        codegenTier,
      };
      const compiler = await createZigProjectCompiler(options);
      let checkpoint: Uint8Array<ArrayBuffer>;
      const outputs = new Map<string, Uint8Array<ArrayBuffer>>();
      try {
        for (
          const [main, library, expected] of [
            [plain, ordinary, 42],
            [spawned, helper, 43],
            [plain, ordinary, 42],
            [spawned, helper, 43],
          ] as const
        ) {
          const sources = { [entry]: main, [dependency]: library };
          const build = await compiler.build({ sources });
          assert(build.success, JSON.stringify(build));
          await execute(build.bytes, expected);
          const previous = outputs.get(main);
          if (previous) assert.deepEqual(build.bytes, previous);
          else outputs.set(main, build.bytes.slice());
          const fresh = await createZigProjectCompiler(options);
          try {
            const control = await fresh.build({ sources });
            assert(control.success, JSON.stringify(control));
            assert.deepEqual(build.bytes, control.bytes);
          } finally {
            await fresh.dispose();
          }
        }
        checkpoint = await compiler.exportCheckpoint();
      } finally {
        await compiler.dispose();
      }
      const restored = await createZigProjectCompiler({
        ...options,
        checkpoint,
      });
      try {
        for (
          const [main, library, expected] of [[spawned, helper, 43], [
            plain,
            ordinary,
            42,
          ]] as const
        ) {
          const build = await restored.build({
            sources: { [entry]: main, [dependency]: library },
          });
          assert(build.success, JSON.stringify(build));
          assert.deepEqual(build.bytes, outputs.get(main));
          await execute(build.bytes, expected);
        }
      } finally {
        await restored.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("tuple collection drains failures and transfers owning results once", async () => {
  const text = `
const launch = fn group => fn action => @task.spawn group action
entry const collect = fn (host: concurrent (U32 -> U32 ! {Foreign})) => @task.scope (fn group => do:
  let first = @task.spawn group (fn () => host 1)
  let second = @task.spawn group (fn () => host 2)
  use received <- |(first, second)|
  let (left, right) = received
  break @u32.add left right)
entry const owners = fn (cleanup: cleanup (unique U32 -> Unit ! {Foreign})) => do:
  use first <- @resource.acquire (fn () => 20) cleanup
  use second <- @resource.acquire (fn () => 22) cleanup
  let (left, right) = @task.scope (fn group => do:
    let first_task = launch group (fn () => first)
    let second_task = launch group (fn () => second)
    break |(first_task, second_task)|)
  break @usage.borrow left (fn left_loan => @usage.borrow right (fn right_loan => @u32.add (@usage.read left_loan) (@usage.read right_loan)))
entry const failed_owner = fn (cleanup: cleanup (unique U32 -> Unit ! {Foreign})) => do:
  use owner <- @resource.acquire (fn () => 20) cleanup
  break @task.scope (fn group => do:
    let first = @task.spawn group (fn () => owner)
    let second = @task.spawn group (fn () -> U32 => @panic "failed child")
    let (left, right) = |(first, second)|
    break @usage.borrow left (fn loan => @u32.add (@usage.read loan) right))
`;
  const directory = await Deno.makeTempDir({ prefix: "blot-task-collect-" });
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
        const build = await compiler.build({ sources: { [entry]: text } });
        assert(build.success, JSON.stringify(build));
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(build.bytes, { asynchronous });
          try {
            const retired: number[] = [];
            const cleanup = guest.cleanupCapability({
              parameter: "U32",
              result: "Unit",
              maxSteps: 1,
              maxCalls: 8,
              call: (value) => {
                retired.push(value);
                return null;
              },
            });
            assert.equal(
              asynchronous
                ? await guest.callAsync("owners", cleanup)
                : guest.call("owners", cleanup),
              42,
            );
            assert.deepEqual(retired, [22, 20]);
            retired.length = 0;
            if (asynchronous) {
              await assert.rejects(guest.callAsync("failed_owner", cleanup));
            } else assert.throws(() => guest.call("failed_owner", cleanup));
            assert.deepEqual(retired, [20]);
            if (!asynchronous) continue;
            for (const order of [[1, 0], [0, 1]]) {
              const requests = [
                Promise.withResolvers<number>(),
                Promise.withResolvers<number>(),
              ];
              const entered = Promise.withResolvers<void>();
              const calls: number[] = [];
              const host = guest.capabilityAsync({
                parameter: "U32",
                result: "U32",
                concurrent: true,
                call: (value) => {
                  calls.push(value);
                  if (calls.length === 2) entered.resolve();
                  return requests[value - 1].promise;
                },
              });
              let settled = false;
              const result = guest.callAsync("collect", host).finally(() => {
                settled = true;
              });
              await entered.promise;
              assert.deepEqual(calls, [1, 2]);
              requests[order[0]].resolve(order[0] === 0 ? 20 : 22);
              await new Promise((resolve) => setTimeout(resolve, 0));
              assert.equal(settled, false);
              requests[order[1]].resolve(order[1] === 0 ? 20 : 22);
              assert.equal(await result, 42);
            }
            const waiting = Promise.withResolvers<number>();
            const failure = Promise.withResolvers<number>();
            const entered = Promise.withResolvers<void>();
            let calls = 0;
            const cause = new Error("failed second task");
            const host = guest.capabilityAsync({
              parameter: "U32",
              result: "U32",
              concurrent: true,
              call: (value) => {
                if (++calls === 2) entered.resolve();
                return value === 1 ? waiting.promise : failure.promise;
              },
            });
            let settled = false;
            const result = guest.callAsync("collect", host).finally(() => {
              settled = true;
            });
            const rejected = assert.rejects(result, (error: unknown) => {
              assert.equal((error as { name: string }).name, "TaskFailure");
              return true;
            });
            await entered.promise;
            failure.reject(cause);
            await new Promise((resolve) => setTimeout(resolve, 0));
            assert.equal(settled, false);
            waiting.resolve(20);
            await rejected;
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
