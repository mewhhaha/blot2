import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { GuestError, instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const source = `
entry const answer = fn (value: U32) => @task.scope (fn group => do:
  let left = @task.spawn group (fn () => value)
  let right = @task.spawn group (fn () => 22)
  break @u32.add (@task.join left) (@task.join right))
const nested = fn () => @task.scope (fn inner => @task.join (@task.spawn inner (fn () => 42)))
entry const nesting = fn () => @task.scope (fn group => @task.join (@task.spawn group (fn () => nested ())))
entry const mixed_groups = fn () => @task.scope (fn group => do:
  let left = @task.spawn group (fn () => 20)
  let right = @task.spawn group (fn () => @task.scope (fn inner => @task.join (@task.spawn inner (fn () => 22))))
  let second = @task.join right
  break @u32.add (@task.join left) second)
entry const grow_group = fn (host: concurrent (U32 -> U32 ! {Foreign})) => @task.scope (fn group => do:
  let parent = @task.spawn group (fn () => do:
    use value <- host 1
    let child = @task.spawn group (fn () => value)
    break 9)
  break 42)
entry const grow_failure = fn (host: concurrent (U32 -> U32 ! {Foreign})) => @task.scope (fn group => do:
  let parent = @task.spawn group (fn () => do:
    use value <- host 1
    let child = @task.spawn group (fn () => @panic "descendant failed")
    break @task.join child)
  break 42)
entry const cancelled = fn () => @task.scope (fn group => do:
  let child = @task.spawn group (fn () => @panic "unstarted")
  let cancelled = @task.cancel child
  break 42)
entry const ignored = fn () => @task.scope (fn group => do:
  let child = @task.spawn group (fn () => 9)
  break 42)
entry const partition = fn (owner: unique (Array U32)) => do:
  let (owner, result) = @task.split owner ((0, 2), (2, 4)) (fn views => do:
    let (left, right) = views
    break @task.scope (fn group => do:
      let first = @task.spawn group (fn () => do:
        let written = @task.write left 0 20
        break @task.read left 0)
      let second = @task.spawn group (fn () => do:
        let written = @task.write right 0 22
        break @task.read right 0)
      break @u32.add (@task.join first) (@task.join second)))
  break result
entry const host = fn (host: concurrent (U32 -> U32 ! {Foreign})) => @task.scope (fn group => do:
  let left = @task.spawn group (fn () => host 1)
  let right = @task.spawn group (fn () => host 2)
  break @u32.add (@task.join left) (@task.join right))
entry const host_array = fn (host: concurrent (Array U32 -> Array U32 ! {Foreign})) => @task.scope (fn group => do:
  let left = @task.spawn group (fn () => host #[1])
  let right = @task.spawn group (fn () => host #[2])
  use first <- @task.join left
  use second <- @task.join right
  break @u32.add (@array.get first 0) (@array.get second 0))
entry const cancel_suspended = fn (host: concurrent (U32 -> U32 ! {Foreign})) => @task.scope (fn group => do:
  let left = @task.spawn group (fn () => host 1)
  let right = @task.spawn group (fn () => 42)
  let result = @task.join right
  use cancelled <- @task.cancel left
  break result)
entry const transfer = fn (cleanup: cleanup (unique U32 -> Unit ! {Foreign})) => do:
  use parent <- @resource.acquire (fn () => 5) cleanup
  use moved <- @resource.acquire (fn () => 9) cleanup
  break @task.scope (fn group => @task.join (@task.spawn group (fn () => @usage.borrow moved (fn loan => @usage.read loan))))
entry const returned = fn (cleanup: cleanup (unique U32 -> Unit ! {Foreign})) => do:
  use parent <- @resource.acquire (fn () => 5) cleanup
  use moved <- @resource.acquire (fn () => 9) cleanup
  let result = @task.scope (fn group => @task.join (@task.spawn group (fn () => moved)))
  break @usage.borrow result (fn loan => @usage.read loan)
entry const cancel_owner = fn (cleanup: cleanup (unique U32 -> Unit ! {Foreign})) => do:
  use parent <- @resource.acquire (fn () => 5) cleanup
  use moved <- @resource.acquire (fn () => 9) cleanup
  break @task.scope (fn group => do:
    let child = @task.spawn group (fn () => @usage.borrow moved (fn loan => @usage.read loan))
    let cancelled = @task.cancel child
    break 42)
entry const lexical_cleanup = fn (cleanup: cleanup (unique U32 -> Unit ! {Foreign})) => do:
  use moved <- @resource.acquire (fn () => 9) cleanup
  break @task.scope (fn group => @resource.scope (fn () => 5) cleanup (fn loan => do:
    let child = @task.spawn group (fn () => @usage.borrow moved (fn loan => @usage.read loan))
    break 42))
entry const read_loan = fn (owner: unique U32) => @usage.borrow owner (fn loan => @task.scope (fn group => do:
  let left = @task.spawn group (fn () => @usage.read loan)
  let right = @task.spawn group (fn () => @usage.read loan)
  break @u32.add (@task.join left) (@task.join right)))
const rows = fn (owner: unique (Array (U32, U32))) => do:
  let (owner, value) = @task.split owner ((0, 1), (1, 2)) (fn views => do:
    let (left, right) = views
    break @task.scope (fn group => do:
      let task = @task.spawn group (fn () => do:
        let written = @task.write left 0 (20, 22)
        let (a, b) = @task.read left 0
        break @u32.add a b)
      break @task.join task))
  break value
entry const packed = fn () => rows #[(1, 2), (3, 4)]
entry const returned_alias = fn (cleanup: cleanup (unique U32 -> Unit ! {Foreign})) => do:
  use moved <- @resource.acquire (fn () => 9) cleanup
  let (owner, extra) = @task.scope (fn group => @task.join (@task.spawn group (fn () => (moved, 33))))
  let alias = owner
  break @u32.add extra (@usage.borrow alias (fn loan => @usage.read loan))
entry const discard_owner = fn (cleanup: cleanup (unique U32 -> Unit ! {Foreign})) => do:
  use moved <- @resource.acquire (fn () => 9) cleanup
  break @resource.scope (fn () => 5) cleanup (fn loan => @task.scope (fn group => do:
    let child = @task.spawn group (fn () => moved)
    break 42))
const demand_child = fn ~(value: unique U32) => @task.scope (fn group => @task.join (@task.spawn group (fn () => @demand value)))
entry const demand_owner = fn (cleanup: cleanup (unique U32 -> Unit ! {Foreign})) => do:
  use owner <- @resource.acquire (fn () => 9) cleanup
  let result = demand_child owner
  break @usage.borrow result (fn loan => @usage.read loan)
entry const named_owner = fn (cleanup: cleanup (unique U32 -> Unit ! {Foreign})) => do:
  use owner <- @resource.acquire (fn () => 9) cleanup
  let result = @task.scope (fn group => do:
    let thunk: once (Unit -> unique U32) = fn () => owner
    let alias = thunk
    break @task.join (@task.spawn group alias))
  break @usage.borrow result (fn loan => @usage.read loan)
entry const late_owner = fn (host: concurrent (U32 -> U32 ! {Foreign})) => do:
  use owner <- @resource.acquire (fn () => 9) (fn owner => @panic "cancelled resource cleanup")
  break @task.scope (fn group => do:
    let left = @task.spawn group (fn () => do:
      use result <- host 1
      break owner)
    let right = @task.spawn group (fn () => host 2)
    break @task.join right)
`;
Deno.test("structured source tasks execute sync JSPI affine join cancel and nested groups", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-tasks-" });
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
    cacheDirectory: `${directory}/cache`,
  });
  try {
    const build = await compiler.build({ sources: { [entry]: source } });
    assert(build.success, JSON.stringify(build));
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(build.bytes, { asynchronous });
      try {
        assert.equal(guest.abi.taskDescriptorCount, 34);
        if (asynchronous) {
          assert.equal(await guest.callAsync("answer", 20), 42);
          assert.equal(await guest.callAsync("nesting", null), 42);
          assert.equal(await guest.callAsync("mixed_groups", null), 42);
          assert.equal(await guest.callAsync("cancelled", null), 42);
          assert.equal(await guest.callAsync("ignored", null), 42);
          assert.equal(await guest.callAsync("read_loan", 21), 42);
          assert.equal(await guest.callAsync("packed", null), 42);
          assert.equal(
            await guest.callAsync("partition", new Uint32Array([0, 0, 0, 0])),
            42,
          );
          const host = guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            concurrent: true,
            call: (value) => Promise.resolve(value * 14),
          });
          assert.equal(await guest.callAsync("host", host), 42);
        } else {
          assert.equal(guest.call("answer", 20), 42);
          assert.equal(guest.call("nesting", null), 42);
          assert.equal(guest.call("mixed_groups", null), 42);
          assert.equal(guest.call("cancelled", null), 42);
          assert.equal(guest.call("ignored", null), 42);
          assert.equal(guest.call("read_loan", 21), 42);
          assert.equal(guest.call("packed", null), 42);
          assert.equal(
            guest.call("partition", new Uint32Array([0, 0, 0, 0])),
            42,
          );
          const host = guest.capability({
            parameter: "U32",
            result: "U32",
            concurrent: true,
            call: (value) => value * 14,
          });
          assert.equal(guest.call("host", host), 42);
          const ordinary = guest.capability({
            parameter: "U32",
            result: "U32",
            call: (value) => value,
          });
          assert.throws(
            () => guest.call("host", ordinary),
            (cause) =>
              cause instanceof GuestError &&
              cause.code === "capability_signature",
          );
        }
        for (
          const name of [
            "transfer",
            "returned",
            "cancel_owner",
            "lexical_cleanup",
            "demand_owner",
            "named_owner",
          ]
        ) {
          const cleanups: number[] = [];
          const cleanup = guest.cleanupCapability({
            parameter: "U32",
            result: "Unit",
            maxSteps: 1,
            maxCalls: 8,
            call: (value) => {
              cleanups.push(value);
              return null;
            },
          });
          let result: unknown;
          if (asynchronous) result = await guest.callAsync(name, cleanup);
          else result = guest.call(name, cleanup);
          assert.equal(
            result,
            name === "transfer" || name === "returned" ||
              name === "demand_owner" || name === "named_owner"
              ? 9
              : 42,
          );
          assert.deepEqual(
            cleanups,
            name === "demand_owner" || name === "named_owner"
              ? [9]
              : name === "returned"
              ? [5, 9]
              : [9, 5],
            name,
          );
        }
        for (const failCleanup of [false, true]) {
          for (const name of ["returned_alias", "discard_owner"]) {
            const cleanups: number[] = [];
            const cleanup = guest.cleanupCapability({
              parameter: "U32",
              result: "Unit",
              maxSteps: 1,
              maxCalls: 8,
              call: (value) => {
                cleanups.push(value);
                if (failCleanup && value === 9) {
                  throw new Error("resource cleanup failed");
                }
                return null;
              },
            });
            if (asynchronous) {
              const completion = guest.callAsync(name, cleanup);
              if (failCleanup) await assert.rejects(completion);
              else assert.equal(await completion, 42);
            } else if (failCleanup) {
              assert.throws(() => guest.call(name, cleanup));
            } else assert.equal(guest.call(name, cleanup), 42);
            assert.deepEqual(cleanups, name === "discard_owner" ? [9, 5] : [9]);
          }
        }
        if (!asynchronous) {
          for (let index = 0; index < 128; index++) {
            assert.equal(guest.call("mixed_groups", null), 42);
          }
          const bytes = guest.memoryBytes();
          assert(bytes > 0);
          for (let index = 0; index < 4096; index++) {
            assert.equal(guest.call("mixed_groups", null), 42);
          }
          assert.equal(guest.memoryBytes(), bytes);
        }
        if (asynchronous) {
          const immediate = guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            concurrent: true,
            call: () => Promise.resolve(20),
          });
          assert.equal(await guest.callAsync("grow_group", immediate), 42);
          await assert.rejects(
            guest.callAsync("grow_failure", immediate),
            (cause) => {
              const failure = cause as { name: string; failures: unknown[] };
              assert.equal(failure.name, "TaskFailure");
              assert.equal(failure.failures.length, 1);
              assert(failure.failures[0] instanceof WebAssembly.RuntimeError);
              return true;
            },
          );
          const cancellation = Promise.withResolvers<number>();
          const enteredCancellation = Promise.withResolvers<void>();
          const cancellable = guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            concurrent: true,
            call: () => {
              enteredCancellation.resolve();
              return cancellation.promise;
            },
          });
          let cancelled = false;
          const cancelling = guest.callAsync("cancel_suspended", cancellable)
            .finally(() => {
              cancelled = true;
            });
          await enteredCancellation.promise;
          await new Promise((resolve) => setTimeout(resolve, 0));
          assert.equal(cancelled, false);
          cancellation.resolve(100);
          assert.equal(await cancelling, 42);
          for (const order of [[0, 1], [1, 0]]) {
            const requests = [
              Promise.withResolvers<Uint32Array>(),
              Promise.withResolvers<Uint32Array>(),
            ];
            const entered = Promise.withResolvers<void>();
            const inputs: Uint32Array[] = [];
            const callback = guest.capabilityAsync({
              parameter: "Array U32",
              result: "Array U32",
              concurrent: true,
              call: (input) => {
                inputs.push(input);
                if (inputs.length === 2) entered.resolve();
                const index = input[0] - 1;
                input[0] = 999;
                return requests[index].promise;
              },
            });
            const result = guest.callAsync("host_array", callback);
            await entered.promise;
            assert.notEqual(inputs[0].buffer, inputs[1].buffer);
            for (const index of order) {
              const reply = new Uint32Array([20 + 2 * index]);
              requests[index].resolve(reply);
              await new Promise((resolve) => setTimeout(resolve, 0));
              reply[0] = 999;
            }
            assert.equal(await result, 42);
          }
          const started = Promise.withResolvers<void>();
          const left = Promise.withResolvers<number>();
          const events: number[] = [];
          const host = guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            concurrent: true,
            call: (value) => {
              events.push(value);
              if (events.length === 2) started.resolve();
              if (value === 1) return left.promise;
              return Promise.reject(new Error("sibling failed"));
            },
          });
          let settled = false;
          const invocation = guest.callAsync("host", host).finally(() => {
            settled = true;
          });
          await started.promise;
          await new Promise((resolve) => setTimeout(resolve, 0));
          assert.equal(settled, false);
          left.resolve(99);
          await assert.rejects(invocation, { name: "TaskFailure" });
          assert.equal(await guest.callAsync("answer", 20), 42);
          const later = Promise.withResolvers<number>();
          const entered = Promise.withResolvers<void>();
          const capability = guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            concurrent: true,
            call: (value) => {
              if (value === 1) return later.promise;
              entered.resolve();
              return Promise.reject(new Error("later sibling failed"));
            },
          });
          let ended = false;
          const late = guest.callAsync("late_owner", capability).finally(() => {
            ended = true;
          });
          await entered.promise;
          await new Promise((resolve) => setTimeout(resolve, 0));
          assert.equal(ended, false);
          assert.throws(
            () => guest.dispose(),
            (cause) =>
              cause instanceof GuestError && cause.code === "reentrant_call",
          );
          later.resolve(99);
          await assert.rejects(late, (cause: unknown) => {
            const failure = cause as { name: string; failures: unknown[] };
            assert.equal(failure.name, "TaskFailure");
            assert(failure.failures[0] instanceof WebAssembly.RuntimeError);
            assert(failure.failures[1] instanceof GuestError);
            return true;
          });
          assert.equal(await guest.callAsync("answer", 20), 42);
        }
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await compiler.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("structured task archives retained edits failure rollback and restart preserve descriptors", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-task-archive-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/workers.blot`;
  const archive = `${directory}/workers.blotdep`;
  const producer = `
const sum = fn (value: U32) => @task.scope (fn group => do:
  let left = @task.spawn group (fn () => value)
  let right = @task.spawn group (fn () => 22)
  break @u32.add (@task.join left) (@task.join right))
const returned = fn (owner: unique U32) => @task.scope (fn group => @task.join (@task.spawn group (fn () => owner)))
const partition = fn (owner: unique (Array U32)) => do:
  let (owner, result) = @task.split owner ((0, 2), (2, 4)) (fn views => do:
    let (left, right) = views
    break @task.scope (fn group => do:
      let first = @task.spawn group (fn () => @task.read left 0)
      let second = @task.spawn group (fn () => @task.read right 0)
      break @u32.add (@task.join first) (@task.join second)))
  break result
const apply_quoted = fn (callback: U32 -> U32) => callback 42
type State a is effect = {get: Unit -> a, set: a -> Unit}
const hidden = fn (value: U32) => @effect.scope (fn (state: State U32) => value)
const quoted_callback = @code.quote (apply_quoted (fn (value: U32) => value))
const quoted_scope = @code.quote (hidden 42)
`;
  const consumer =
    `import {sum, returned, partition, quoted_callback, quoted_scope} from "./workers"
entry const answer = fn (value: U32) => sum value
entry const view = fn (owner: unique (Array U32)) => partition owner
entry const callback = fn () => @code.emit quoted_callback
entry const scoped = fn () => @code.emit quoted_scope
entry const transfer = fn (cleanup: cleanup (unique U32 -> Unit ! {Foreign})) => do:
  use owner <- @resource.acquire (fn () => 9) cleanup
  let result = returned owner
  break @usage.borrow result (fn loan => @usage.read loan)
`;
  try {
    await Deno.writeTextFile(entry, consumer);
    await Deno.writeTextFile(dependency, producer);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        codegenTier,
        cacheDirectory: `${directory}/cache-${codegenTier}`,
      };
      const compiler = await createZigProjectCompiler(options);
      const imported = await createZigProjectCompiler({
        ...options,
        dependencies: archive,
        cacheDirectory: false,
      });
      let firstBytes: Uint8Array;
      try {
        const first = await compiler.build();
        const archived = await imported.build();
        assert(first.success, JSON.stringify(first));
        assert(archived.success, JSON.stringify(archived));
        assert.deepEqual(archived.bytes, first.bytes);
        firstBytes = first.bytes;
        for (const bytes of [first.bytes, archived.bytes]) {
          const guest = await instantiateGuest(bytes);
          try {
            assert.equal(guest.call("answer", 20), 42);
            assert.equal(guest.call("callback", null), 42);
            assert.equal(guest.call("scoped", null), 42);
            assert.equal(
              guest.call("view", new Uint32Array([20, 0, 22, 0])),
              42,
            );
            const cleanups: number[] = [];
            const cleanup = guest.cleanupCapability({
              parameter: "U32",
              result: "Unit",
              maxSteps: 1,
              maxCalls: 1,
              call: (value) => {
                cleanups.push(value);
                return null;
              },
            });
            assert.equal(guest.call("transfer", cleanup), 9);
            assert.deepEqual(cleanups, [9]);
          } finally {
            guest.dispose();
          }
        }
        for (const bytes of [first.bytes, archived.bytes]) {
          const guest = await instantiateGuest(bytes, { asynchronous: true });
          try {
            assert.equal(await guest.callAsync("callback", null), 42);
            assert.equal(await guest.callAsync("scoped", null), 42);
          } finally {
            guest.dispose();
          }
        }
        const unchanged = await compiler.build();
        assert(unchanged.success, JSON.stringify(unchanged));
        assert.deepEqual(unchanged.bytes, first.bytes);
        const changed = await compiler.build({
          sources: {
            [dependency]: producer.replace("fn () => 22", "fn () => 23"),
          },
        });
        assert(changed.success, JSON.stringify(changed));
        const guest = await instantiateGuest(changed.bytes);
        try {
          assert.equal(guest.call("answer", 20), 43);
        } finally {
          guest.dispose();
        }
        const invalid = await compiler.build({
          sources: { [dependency]: producer.replace("(2, 4)", "(1, 4)") },
        });
        assert.equal(invalid.success, false);
        assert(
          invalid.diagnostics.some((diagnostic) =>
            diagnostic.code === "task_regions_overlap"
          ),
        );
        const repaired = await compiler.build({
          sources: { [dependency]: producer },
        });
        assert(repaired.success, JSON.stringify(repaired));
        assert.deepEqual(repaired.bytes, first.bytes);
      } finally {
        await compiler.close();
        await imported.close();
      }
      const restarted = await createZigProjectCompiler(options);
      try {
        const restored = await restarted.build();
        assert(restored.success, JSON.stringify(restored));
        assert.deepEqual(restored.bytes, firstBytes!);
        const guest = await instantiateGuest(restored.bytes, {
          asynchronous: true,
        });
        try {
          assert.equal(await guest.callAsync("answer", 20), 42);
        } finally {
          guest.dispose();
        }
      } finally {
        await restarted.close();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("quoted task groups and partitions execute only after emission with fresh lexical owners", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-quoted-tasks-" });
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
    cacheDirectory: `${directory}/cache`,
  });
  const text = `
const generated = @code.quote (fn (value: U32) => @task.scope (fn group => do:
  let first = @task.spawn group (fn () => value)
  let second = @task.spawn group (fn () => 22)
  break @u32.add (@task.join first) (@task.join second)))
const partitioned = @code.quote (fn () => do:
  let owner: unique (Array U32) = #[20, 0, 22, 0]
  let (owner, result) = @task.split owner ((0, 2), (2, 4)) (fn views => do:
    let (left, right) = views
    break @task.scope (fn group => do:
      let first = @task.spawn group (fn () => @task.read left 0)
      let second = @task.spawn group (fn () => @task.read right 0)
      break @u32.add (@task.join first) (@task.join second)))
  break result)
entry const answer = fn (value: U32) => (@code.emit generated) value
entry const views = fn () => (@code.emit partitioned) ()
`;
  try {
    const built = await compiler.build({ sources: { [entry]: text } });
    assert(built.success, JSON.stringify(built));
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(built.bytes, { asynchronous });
      try {
        if (asynchronous) {
          assert.equal(await guest.callAsync("answer", 20), 42);
          assert.equal(await guest.callAsync("views", null), 42);
        } else {
          assert.equal(guest.call("answer", 20), 42);
          assert.equal(guest.call("views", null), 42);
        }
      } finally {
        guest.dispose();
      }
    }
    for (
      const invalid of [
        "const escaped = @task.scope (fn group => @code.quote group)",
        "entry const escaped = fn () => @task.scope (fn group => @code.quote (@task.spawn group (fn () => 42)))",
      ]
    ) {
      const rejected = await compiler.build({
        sources: { [entry]: `${invalid}\nentry const answer = fn () => 42\n` },
      });
      assert.equal(rejected.success, false);
    }
    const repaired = await compiler.build({ sources: { [entry]: text } });
    assert(repaired.success, JSON.stringify(repaired));
    assert.deepEqual(repaired.bytes, built.bytes);
  } finally {
    await compiler.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("wide Source task scope and thunk execute with more than 64 direct children", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-wide-tasks-" });
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
    // This fixture checks task width; a detached restart writer can outlive
    // the server and race temporary-directory removal.
    cacheDirectory: false,
  });
  const outer = Array.from(
    { length: 96 },
    (_, index) => `  let outer_${index} = ${index}`,
  ).join("\n");
  const inner = Array.from(
    { length: 96 },
    (_, index) => `    let inner_${index} = ${index}`,
  ).join("\n");
  const text =
    `entry const answer = fn (value: U32) => @task.scope (fn group => do:
${outer}
  let child = @task.spawn group (fn () => do:
${inner}
    break @u32.add value 22)
  break @task.join child)
`;
  try {
    const built = await compiler.build({ sources: { [entry]: text } });
    assert(built.success, JSON.stringify(built));
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(built.bytes, { asynchronous });
      try {
        if (asynchronous) assert.equal(await guest.callAsync("answer", 20), 42);
        else assert.equal(guest.call("answer", 20), 42);
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await compiler.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("task named calls retain actual imported producer authority through aliases and edits", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-imported-task-calls-",
  });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/producer.blot`;
  const forwarded = `${directory}/forward.blot`;
  const main = `import { forwarded as imported } from "./forward"
const alias = imported
entry const answer = fn (value: U32) => @task.scope (fn group => @task.join (@task.spawn group (fn () => alias value)))
`;
  const forwarding = 'export { offset as forwarded } from "./producer"\n';
  const helper = "const offset = fn (value: U32) => @u32.add value 22\n";
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
    cacheDirectory: `${directory}/cache`,
  });
  async function execute(bytes: Uint8Array<ArrayBuffer>, expected: number) {
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        if (asynchronous) {
          assert.equal(await guest.callAsync("answer", 20), expected);
        } else assert.equal(guest.call("answer", 20), expected);
      } finally {
        guest.dispose();
      }
    }
  }
  try {
    const sources = {
      [entry]: main,
      [forwarded]: forwarding,
      [producer]: helper,
    };
    const built = await compiler.build({ sources });
    assert(built.success, JSON.stringify(built));
    await execute(built.bytes, 42);
    const changed = await compiler.build({
      sources: { ...sources, [producer]: helper.replace("22", "23") },
    });
    assert(changed.success, JSON.stringify(changed));
    await execute(changed.bytes, 43);
    const reverted = await compiler.build({ sources });
    assert(reverted.success, JSON.stringify(reverted));
    assert.deepEqual(reverted.bytes, built.bytes);
    await execute(reverted.bytes, 42);
  } finally {
    await compiler.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("task actual helper proof executes generic groups views loans and recursion", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-task-helpers-" });
  const entry = `${directory}/main.blot`;
  const helperSource = `
const identity = fn value => value
const owned = fn (value: unique a) => value
const read: forall [region r] => (borrow r U32) -> U32 = fn loan => @usage.read loan
const recur = fn (value: U32) -> U32 => if @u32.eq value 0 then 42 else recur (@u32.sub value 1)
const apply = fn (f: U32 -> U32) => fn (value: U32) => f value
entry const group = fn () => @task.scope (fn group => do:
  let alias = identity group
  break @task.join (@task.spawn alias (fn () => 42)))
entry const loan = fn (owner: unique U32) => @usage.borrow owner (fn loan => @task.scope (fn group => do:
  let first = @task.spawn group (fn () => read loan)
  let second = @task.spawn group (fn () => read loan)
  break @u32.add (@task.join first) (@task.join second)))
const partition = fn (owner: unique (Array U32)) => do:
  let (owner, result) = @task.split owner ((0, 1), (1, 2)) (fn views => do:
    let (left, right) = views
    let alias = owned left
    break @task.scope (fn group => @task.join (@task.spawn group (fn () => @task.read alias 0))))
  break result
entry const view = fn () => partition #[42, 22]
entry const recursive = fn () => @task.scope (fn group => @task.join (@task.spawn group (fn () => recur 3)))
const changed = fn (values: Array U32) => @array.set (@array.append values 22) 0 20
const generated = fn () => @array.generate 2 (fn (index: U32) => @u32.add index 20)
entry const collection = fn () => @task.scope (fn group => @task.join (@task.spawn group (fn () => do:
  let values = changed #[1]
  break @u32.add (@array.get values 0) (@array.get values 1))))
entry const generate = fn () => @task.scope (fn group => @task.join (@task.spawn group (fn () => @u32.add 1 (@u32.add (@array.get (generated ()) 0) (@array.get (generated ()) 1)))))
entry const concurrent_helper = fn (host: concurrent (U32 -> U32 ! {Foreign})) => @task.scope (fn group => @task.join (@task.spawn group (fn () => do:
  let alias = identity host
  use value <- alias 20
  break value)))
entry const local_function = fn () => @task.scope (fn group => do:
  let offset: U32 -> U32 = fn (value: U32) => @u32.add value 22
  break @task.join (@task.spawn group (fn () => apply offset 20)))
`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
    cacheDirectory: `${directory}/cache`,
  });
  try {
    const built = await compiler.build({ sources: { [entry]: helperSource } });
    assert(built.success, JSON.stringify(built));
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(built.bytes, { asynchronous });
      try {
        for (
          const [name, argument] of [
            ["group", null],
            ["loan", 21],
            ["view", null],
            ["recursive", null],
            ["local_function", null],
            ["collection", null],
            ["generate", null],
          ] as const
        ) {
          if (asynchronous) {
            assert.equal(await guest.callAsync(name, argument), 42);
          } else assert.equal(guest.call(name, argument), 42);
        }
        const host = guest.capability({
          parameter: "U32",
          result: "U32",
          concurrent: true,
          call: (value) => value + 22,
        });
        if (asynchronous) {
          assert.equal(await guest.callAsync("concurrent_helper", host), 42);
        } else assert.equal(guest.call("concurrent_helper", host), 42);
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await compiler.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("reconstructed higher order and scoped helper frontiers execute from Source and archive", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-task-frontiers-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/helpers.blot`;
  const archive = `${directory}/helpers.blotdep`;
  const library = `const apply = fn (callback: U32 -> U32) => callback 42
type State a is effect = {get: Unit -> a, set: a -> Unit}
const hidden = fn (value: U32) => @effect.scope (fn (state: State U32) => value)
const callback = @code.quote (apply (fn (value: U32) => value))
const scoped = @code.quote (hidden 42)
`;
  const consumer = `import {callback, scoped} from "./helpers"
entry const callback_answer = fn () => @code.emit callback
entry const scoped_answer = fn () => @code.emit scoped
`;
  try {
    await Deno.writeTextFile(entry, consumer);
    await Deno.writeTextFile(producer, library);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    const options = {
      executable,
      entry,
      prelude: null,
      cacheDirectory: false as const,
    };
    const live = await createZigProjectCompiler(options);
    const archived = await createZigProjectCompiler({
      ...options,
      dependencies: archive,
    });
    try {
      const source = await live.build();
      const frozen = await archived.build();
      assert(source.success, JSON.stringify(source));
      assert(frozen.success, JSON.stringify(frozen));
      assert.deepEqual(frozen.bytes, source.bytes);
      for (const bytes of [source.bytes, frozen.bytes]) {
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(bytes, { asynchronous });
          try {
            for (const name of ["callback_answer", "scoped_answer"]) {
              if (asynchronous) {
                assert.equal(await guest.callAsync(name, null), 42);
              } else assert.equal(guest.call(name, null), 42);
            }
          } finally {
            guest.dispose();
          }
        }
      }
    } finally {
      await live.close();
      await archived.close();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
