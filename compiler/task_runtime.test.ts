import { strict as assert } from "node:assert";
import {
  TaskAdapter,
  TaskContext,
  TaskError,
  TaskFailure,
  TaskRuntime,
} from "./task_runtime.ts";

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (cause: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}
function adapter(
  trace: string[],
  name: string,
  run: TaskAdapter["run"],
): TaskAdapter {
  return {
    run: (context, captures) => {
      trace.push(`run ${name}`);
      return run(context, captures);
    },
    dropCaptures: () => {
      trace.push(`captures ${name}`);
    },
    dropResult: () => {
      trace.push(`result ${name}`);
    },
  };
}
function code(code: TaskError["code"]) {
  return (cause: unknown) => cause instanceof TaskError && cause.code === code;
}

Deno.test("tasks: join moves a result once and close drops unused siblings in order", () => {
  const trace: string[] = [];
  const runtime = new TaskRuntime();
  const group = runtime.open();
  const left = runtime.spawn(group, adapter(trace, "left", () => 20), 1);
  runtime.spawn(group, adapter(trace, "right", () => 22), 2);
  assert.equal(runtime.join(left), 20);
  assert.throws(() => runtime.join(left), code("task_handle_consumed"));
  assert.throws(() => runtime.cancel(left), code("task_handle_consumed"));
  assert.equal(runtime.close(group), undefined);
  assert.deepEqual(trace, [
    "run left",
    "captures left",
    "run right",
    "captures right",
    "result right",
  ]);
  assert.equal(runtime.liveRecords, 0);
  assert.throws(() => runtime.poll(left), code("task_host_contract"));
  assert.throws(
    () => runtime.spawn(group, adapter([], "late", () => 0), 0),
    code("task_escape"),
  );
});

Deno.test("tasks: cancellation before start drops captures without invoking the thunk", () => {
  const trace: string[] = [];
  const runtime = new TaskRuntime();
  const group = runtime.open();
  const child = runtime.spawn(group, adapter(trace, "child", () => 42), 1);
  assert.equal(runtime.cancel(child), undefined);
  assert.equal(runtime.poll(child), "cancelled");
  runtime.close(group);
  assert.deepEqual(trace, ["captures child"]);
});

Deno.test("tasks: nested groups finish before parent cleanup and capture retirement", () => {
  const trace: string[] = [];
  const runtime = new TaskRuntime();
  const group = runtime.open();
  runtime.spawn(
    group,
    adapter(trace, "parent", (context) => {
      context.cleanup(() => {
        trace.push("cleanup parent");
      });
      const nested = context.scope();
      runtime.spawn(
        nested,
        adapter(trace, "child", (child) => {
          child.cleanup(() => {
            trace.push("cleanup child");
          });
          return 1;
        }),
        0,
      );
      return 2;
    }),
    0,
  );
  runtime.close(group);
  assert.deepEqual(trace, [
    "run parent",
    "run child",
    "cleanup child",
    "captures child",
    "result child",
    "cleanup parent",
    "captures parent",
    "result parent",
  ]);
});

Deno.test("tasks: join can resume its parent while another child remains suspended", async () => {
  const trace: string[] = [];
  const waiting = deferred<number>();
  const runtime = new TaskRuntime();
  const group = runtime.open();
  const left = runtime.spawn(group, adapter(trace, "ready", () => 42), 0);
  const right = runtime.spawn(
    group,
    adapter(trace, "waiting", () => waiting.promise),
    0,
  );
  assert.equal(runtime.join(left), 42);
  assert.equal(runtime.poll(right), "suspended");
  waiting.resolve(3);
  await runtime.close(group);
  assert.equal(runtime.liveRecords, 0);
});

Deno.test("tasks: sibling failure waits for an unabortable suspension before reporting", async () => {
  const trace: string[] = [];
  const waiting = deferred<number>();
  const failure = new Error("sibling failed");
  const runtime = new TaskRuntime();
  const group = runtime.open();
  const left = runtime.spawn(
    group,
    adapter(trace, "waiting", (context) => {
      context.cleanup(() => {
        trace.push("cleanup waiting");
      });
      return waiting.promise;
    }),
    0,
  );
  runtime.spawn(
    group,
    adapter(trace, "failure", () => {
      throw failure;
    }),
    0,
  );
  let settled = false;
  const joining = Promise.resolve(runtime.join(left)).finally(() => {
    settled = true;
  });
  await Promise.resolve();
  assert.equal(settled, false);
  assert.equal(runtime.poll(left), "suspended");
  assert.deepEqual(trace, ["run waiting", "run failure", "captures failure"]);
  waiting.resolve(99);
  await assert.rejects(
    joining,
    (cause) => cause instanceof TaskFailure && cause.cause === failure,
  );
  assert.equal(runtime.poll(left), "cancelled");
  assert.deepEqual(trace.slice(-3), [
    "cleanup waiting",
    "captures waiting",
    "result waiting",
  ]);
  assert.throws(
    () => runtime.close(group),
    (cause) => cause instanceof TaskFailure && cause.cause === failure,
  );
  assert.equal(runtime.liveRecords, 0);
});

Deno.test("tasks: primary failure uses spawn ordinal after every suspended child settles", async () => {
  const trace: string[] = [];
  const left = deferred<number>();
  const right = deferred<number>();
  const first = new Error("ordinal 0");
  const second = new Error("ordinal 1");
  const runtime = new TaskRuntime();
  const group = runtime.open();
  runtime.spawn(group, adapter(trace, "left", () => left.promise), 0);
  runtime.spawn(group, adapter(trace, "right", () => right.promise), 0);
  const closing = Promise.resolve(runtime.close(group));
  right.reject(second);
  await Promise.resolve();
  left.reject(first);
  await assert.rejects(closing, (cause) => {
    assert(cause instanceof TaskFailure);
    assert.deepEqual(cause.failures, [first, second]);
    return true;
  });
  assert.equal(runtime.liveRecords, 0);
});

Deno.test("tasks: cleanup failures do not skip older resources or parent cleanup", () => {
  const trace: string[] = [];
  const failure = new Error("cleanup failed");
  const runtime = new TaskRuntime();
  const group = runtime.open();
  runtime.spawn(
    group,
    adapter(trace, "parent", (context) => {
      context.cleanup(() => {
        trace.push("parent cleanup");
      });
      runtime.spawn(
        context.scope(),
        adapter(trace, "child", (child) => {
          child.cleanup(() => {
            trace.push("older");
          });
          child.cleanup(() => {
            trace.push("newer");
            throw failure;
          });
          return 1;
        }),
        0,
      );
      return 2;
    }),
    0,
  );
  assert.throws(
    () => runtime.close(group),
    (cause) => cause instanceof TaskFailure && cause.cause === failure,
  );
  assert.deepEqual(trace, [
    "run parent",
    "run child",
    "newer",
    "older",
    "captures child",
    "result child",
    "parent cleanup",
    "captures parent",
    "result parent",
  ]);
  assert.equal(runtime.liveRecords, 0);
});

Deno.test("tasks: teardown requests cancellation and retains pending captures until settlement", async () => {
  const trace: string[] = [];
  const waiting = deferred<number>();
  const runtime = new TaskRuntime();
  const group = runtime.open();
  const child = runtime.spawn(
    group,
    adapter(trace, "child", () => waiting.promise),
    0,
  );
  const joining = Promise.resolve(runtime.join(child));
  const disposing = runtime.dispose();
  assert(disposing instanceof Promise);
  assert.equal(runtime.liveRecords, 2);
  assert.deepEqual(trace, ["run child"]);
  waiting.resolve(42);
  await assert.rejects(joining);
  await disposing;
  assert.deepEqual(trace, ["run child", "captures child", "result child"]);
  assert.equal(runtime.liveRecords, 0);
  assert.throws(() => runtime.open(), code("task_host_contract"));
});

Deno.test("tasks: admission failure preserves the caller's captures and existing children", () => {
  const trace: string[] = [];
  const runtime = new TaskRuntime(2);
  const group = runtime.open();
  const child = runtime.spawn(group, adapter(trace, "first", () => 42), 1);
  assert.throws(
    () => runtime.spawn(group, adapter(trace, "rejected", () => 0), 2),
    code("task_budget"),
  );
  assert.deepEqual(trace, []);
  assert.equal(runtime.join(child), 42);
  runtime.close(group);
  assert.equal(runtime.liveRecords, 0);
});

Deno.test("tasks: repeated scopes retain no closed groups or consumed results", () => {
  const runtime = new TaskRuntime(4);
  let captures = 0;
  let results = 0;
  const task: TaskAdapter = {
    run: () => 1,
    dropCaptures: () => {
      captures++;
    },
    dropResult: () => {
      results++;
    },
  };
  for (let index = 0; index < 10000; index++) {
    const group = runtime.open();
    runtime.spawn(group, task, 0);
    runtime.close(group);
    assert.equal(runtime.liveRecords, 0);
  }
  assert.equal(captures, 10000);
  assert.equal(results, 10000);
});

Deno.test("tasks: a saved task context cannot introduce work after terminal cleanup", () => {
  let saved!: TaskContext;
  const runtime = new TaskRuntime();
  const group = runtime.open();
  runtime.spawn(group, {
    run(context) {
      saved = context;
      return 1;
    },
    dropCaptures() {},
    dropResult() {},
  }, 0);
  runtime.close(group);
  assert.throws(() => saved.scope(), code("task_escape"));
  assert.throws(() => saved.cleanup(() => {}), code("task_escape"));
  assert.throws(() => saved.checkpoint(), code("task_host_contract"));
});

Deno.test("tasks: failed pre-handle publication returns captures without running or cleanup", () => {
  const trace: string[] = [];
  const runtime = new TaskRuntime();
  const group = runtime.open();
  const first = runtime.spawn(
    group,
    adapter(trace, "unpublished", () => 7),
    41,
  );
  runtime.rollbackSpawn(first);
  assert.throws(
    () => runtime.poll(first),
    (cause) =>
      cause instanceof TaskError && cause.code === "task_host_contract",
  );
  assert.deepEqual(trace, []);
  const second = runtime.spawn(
    group,
    adapter(trace, "published", () => 42),
    41,
  );
  assert(second > first);
  assert.equal(runtime.join(second), 42);
  assert.throws(
    () => runtime.rollbackSpawn(second),
    (cause) =>
      cause instanceof TaskError && cause.code === "task_host_contract",
  );
  runtime.close(group);
  assert.equal(runtime.liveRecords, 0);
});

Deno.test("tasks: closing groups drain newly published descendants and failure waits exclude their caller", async () => {
  for (const fail of [false, true]) {
    const runtime = new TaskRuntime();
    const trace: string[] = [];
    const group = runtime.open();
    const failure = new Error("descendant failed");
    runtime.spawn(
      group,
      adapter(trace, "parent", async (context) => {
        await Promise.resolve();
        const child = runtime.spawn(
          group,
          adapter(trace, "descendant", () => {
            if (fail) throw failure;
            return 42;
          }),
          1,
          context.id,
        );
        if (fail) return runtime.join(child, context.id);
        return 7;
      }),
      0,
    );
    const completion = runtime.close(group);
    if (fail) {
      await assert.rejects(Promise.resolve(completion), (cause) => {
        assert(cause instanceof TaskFailure);
        assert.deepEqual(cause.failures, [failure]);
        return true;
      });
    } else await completion;
    assert(trace.includes("run descendant"));
    assert(trace.includes("captures descendant"));
    assert.equal(runtime.liveRecords, 0);
  }
});
