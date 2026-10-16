import { strict as assert } from "node:assert";
import {
  TaskContext,
  TaskFailure,
  TaskRuntime,
} from "../../compiler/task_runtime.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const fixture = new URL(
  "../task-context-fixture.wasm",
  new URL(executable, `file://${Deno.cwd()}/`),
);
async function runtime(options: {
  asynchronous?: boolean;
  host?: (context: number) => number | Promise<number>;
  checkpoint?: (context: number) => number;
} = {}) {
  const host = options.host ?? (() => 42);
  let imported: WebAssembly.ImportValue = host;
  const integration = WebAssembly as unknown as {
    Suspending: new (callback: CallableFunction) => WebAssembly.ImportValue;
    promising: (
      exported: CallableFunction,
    ) => (value: number) => Promise<number>;
  };
  if (options.asynchronous) imported = new integration.Suspending(host);
  const instance = new WebAssembly.Instance(
    new WebAssembly.Module(await Deno.readFile(fixture)),
    {
      "tasks:fixture": {
        host: imported,
        checkpoint: options.checkpoint ?? (() => 0),
      },
    },
  );
  const exports = instance.exports;
  const memory = exports["blot:memory"] as WebAssembly.Memory;
  const call = (name: string, ...args: number[]) =>
    Number((exports[name] as CallableFunction)(...args)) >>> 0;
  const get = (name: string) =>
    Number((exports[name] as WebAssembly.Global).value) >>> 0;
  const set = (name: string, value: number) => {
    (exports[name] as WebAssembly.Global).value = value | 0;
  };
  set("root_enabled", 3);
  set("rc_enabled", 1);
  return {
    runAsync: (context: number) =>
      integration.promising(exports.run as CallableFunction)(context),
    call,
    get,
    set,
    word: (address: number) =>
      new DataView(memory.buffer).getUint32(address, true),
    put: (address: number, value: number) =>
      new DataView(memory.buffer).setUint32(address, value, true),
  };
}

Deno.test("task contexts preserve suspended parent roots while child failure drains its own frames", async () => {
  const r = await runtime();
  const parent = r.call("create", 0);
  r.call("root_enter");
  const owned = r.call("root_allocate", 4, 0);
  r.call("store_word", owned, owned, 42);
  const parentFrame = r.get("root_frame");
  r.set("cancelled", 11);
  r.call("save", parent);
  const child = r.call("create", 0);
  r.call("restore", child);
  assert.equal(r.get("root_active"), 0);
  assert.equal(r.get("cancelled"), 0);
  r.call("root_enter");
  const temporary = r.call("root_allocate", 4, 0);
  r.call("store_word", temporary, temporary, 99);
  r.set("cancelled", 22);
  assert.equal(r.get("root_count"), 2);
  r.call("root_leave", 1);
  r.call("save", child);
  r.call("restore", parent);
  assert.equal(r.get("root_count"), 1);
  assert.equal(r.get("root_frame"), parentFrame);
  assert.equal(r.get("cancelled"), 11);
  assert.equal(r.word(owned), 42);
  r.call("drop", child);
  r.call("root_leave", 0);
  assert.equal(r.get("root_count"), 0);
  r.call("save", parent);
  r.call("drop", parent);
});

Deno.test("task contexts count a parent capture while it is retained by another task", async () => {
  const r = await runtime();
  const parent = r.call("create", 0);
  r.call("root_enter");
  const owned = r.call("root_allocate", 4, 0);
  r.call("store_word", owned, owned, 42);
  r.call("save", parent);
  const child = r.call("create", 0);
  r.call("restore", child);
  r.call("root_enter");
  const captured = r.call("root_allocate", 4, 1);
  r.call("store_word", captured, captured, owned);
  assert.equal(r.get("root_count"), 2);
  r.call("save", child);
  r.call("restore", parent);
  r.call("root_leave", 0);
  assert.equal(r.get("root_count"), 1);
  assert.equal(r.word(owned), 42);
  r.call("save", parent);
  r.call("restore", child);
  assert.equal(r.word(r.word(captured)), 42);
  r.call("root_leave", 0);
  assert.equal(r.get("root_count"), 0);
  r.call("save", child);
  r.call("drop", parent);
  r.call("drop", child);
});

Deno.test("task context failure makes only its evaluating demands terminal", async () => {
  const r = await runtime();
  function evaluating() {
    const demand = r.call("root_allocate", 16, 2);
    r.put(demand + 8, 1);
    r.call("root_force", demand);
    return demand;
  }
  const parent = r.call("create", 0);
  r.call("root_enter");
  const parentDemand = evaluating();
  // Keep an external counted edge so terminal state remains observable.
  r.call("retain", parentDemand);
  r.call("save", parent);
  const child = r.call("create", 0);
  r.call("restore", child);
  r.call("root_enter");
  const childDemand = evaluating();
  r.call("retain", childDemand);
  r.call("root_leave", 1);
  assert.equal(r.word(childDemand + 8), 3);
  assert.equal(r.word(parentDemand + 8), 1);
  r.call("save", child);
  r.call("restore", parent);
  r.call("root_leave", 1);
  assert.equal(r.word(parentDemand + 8), 3);
  r.call("save", parent);
  r.call("drop", child);
  r.call("drop", parent);
});

Deno.test("task context admission rejects an incomplete ownership runtime and live-frame retirement", async () => {
  const r = await runtime();
  r.set("root_enabled", 1);
  assert.throws(() => r.call("create", 0), WebAssembly.RuntimeError);
  r.set("root_enabled", 3);
  const context = r.call("create", 0);
  r.call("restore", context);
  r.call("root_enter");
  // The saved buffer is still empty: retirement must inspect the live context.
  assert.throws(() => r.call("drop", context), WebAssembly.RuntimeError);
  const frame = r.get("root_frame");
  assert.throws(() => r.call("restore", 0xFFFFFFFC), WebAssembly.RuntimeError);
  assert.equal(r.get("root_frame"), frame);
  r.call("root_leave", 1);
  r.call("save", context);
  r.call("drop", context);
  assert.throws(() => r.call("restore", context), WebAssembly.RuntimeError);
});

Deno.test("task context allocation failure preserves every previously published root", async () => {
  const r = await runtime();
  const context = r.call("create", 0);
  r.call("restore", context);
  r.call("root_enter");
  const owner = r.call("root_allocate", 4, 0);
  r.call("store_word", owner, owner, 42);
  const heap = r.get("heap");
  const frame = r.get("root_frame");
  r.set("heap", 0xFFFFFFF0);
  assert.throws(() => r.call("create", 0), WebAssembly.RuntimeError);
  assert.equal(r.get("root_frame"), frame);
  assert.equal(r.get("root_count"), 1);
  assert.equal(r.word(owner), 42);
  r.set("heap", heap);
  r.call("root_leave", 0);
  r.call("drop", context);
  assert.equal(r.get("root_count"), 0);
});

Deno.test("task context storage and suspended ownership stay bounded over repeated task groups", async () => {
  const r = await runtime();
  let baseline = 0;
  for (let iteration = 0; iteration < 10000; iteration++) {
    const context = r.call("create", 0);
    r.call("restore", context);
    r.call("root_enter");
    const temporary = r.call("root_allocate", 16, 0);
    r.call("store_word", temporary, temporary, iteration);
    r.call("root_leave", iteration % 2);
    r.call("save", context);
    r.call("drop", context);
    assert.equal(r.get("root_count"), 0);
    if (iteration === 0) baseline = r.get("heap");
  }
  assert.equal(r.get("heap"), baseline);
});

Deno.test("task scheduler cancellation retains a native suspended child until settlement", async () => {
  const r = await runtime();
  const parent = r.call("create", 0);
  r.call("root_enter");
  const parentValue = r.call("root_allocate", 4, 0);
  r.call("store_word", parentValue, parentValue, 42);
  r.call("save", parent);
  const child = r.call("create", 0);
  let settle!: (value: number) => void;
  const waiting = new Promise<number>((resolve) => {
    settle = resolve;
  });
  const tasks = new TaskRuntime();
  const group = tasks.open();
  const task = tasks.spawn(group, {
    run(context) {
      r.call("save", parent);
      r.call("restore", child);
      r.call("root_enter");
      const owned = r.call("root_allocate", 4, 0);
      r.call("store_word", owned, owned, 99);
      context.cleanup(() => {
        r.call("save", parent);
        r.call("restore", child);
        r.call("root_leave", 1);
        r.call("save", child);
        r.call("restore", parent);
        r.call("drop", child);
      });
      r.call("save", child);
      r.call("restore", parent);
      return waiting;
    },
    dropCaptures() {},
    dropResult() {},
  }, 0);
  const joining = Promise.resolve(tasks.join(task));
  const disposing = tasks.dispose();
  assert.equal(r.get("root_count"), 2);
  assert.equal(r.word(parentValue), 42);
  settle(99);
  await assert.rejects(joining);
  await disposing;
  assert.equal(r.get("root_count"), 1);
  assert.equal(r.word(parentValue), 42);
  r.call("root_leave", 0);
  r.call("save", parent);
  r.call("drop", parent);
  assert.equal(r.get("root_count"), 0);
});

Deno.test("JSPI task resumption restores its exact frame before cancellation and nested failure cleanup", async () => {
  const contexts = new Map<number, TaskContext>();
  const completions = new Map<
    number,
    { resolve(value: number): void; reject(cause: unknown): void }
  >();
  const trace: string[] = [];
  const r = await runtime({
    asynchronous: true,
    host: (pointer) =>
      new Promise<number>((resolve, reject) => {
        completions.set(pointer >>> 0, { resolve, reject });
        trace.push(`suspended ${pointer >>> 0}`);
      }),
    checkpoint: (pointer) => {
      contexts.get(pointer >>> 0)!.checkpoint();
      return 0;
    },
  });
  const parent = r.call("create", 0);
  r.call("root_enter");
  const parentValue = r.call("root_allocate", 4, 0);
  r.call("store_word", parentValue, parentValue, 42);
  r.call("save", parent);
  const tasks = new TaskRuntime();
  const group = tasks.open();
  const pointers: number[] = [];
  const start = () =>
    tasks.spawn(group, {
      run(context) {
        const pointer = r.call("create", 0);
        pointers.push(pointer);
        contexts.set(pointer, context);
        r.call("restore", pointer);
        r.call("root_enter");
        context.cleanup(() => {
          r.call("restore", pointer);
          r.call("root_leave", 1);
          r.call("save", pointer);
          r.call("restore", parent);
          r.call("drop", pointer);
          contexts.delete(pointer);
          trace.push(`clean ${pointer}`);
        });
        const completion = r.runAsync(pointer);
        r.call("restore", parent);
        return completion.then((value) => value >>> 0);
      },
      dropCaptures() {},
      dropResult() {},
    }, 0);
  const left = start();
  start();
  const joined = Promise.resolve(tasks.join(left));
  assert.equal(pointers.length, 2);
  assert.equal(r.get("root_count"), 3);
  const failure = new Error("host rejected sibling");
  completions.get(pointers[1])!.reject(failure);
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(contexts.size, 1);
  assert.equal(r.get("root_count"), 2);
  // This successful host result must be ignored because its task was cancelled.
  completions.get(pointers[0])!.resolve(99);
  await assert.rejects(
    joined,
    (cause) => cause instanceof TaskFailure && cause.cause === failure,
  );
  assert.throws(() => tasks.close(group), TaskFailure);
  assert.equal(contexts.size, 0);
  assert.equal(r.get("root_count"), 1);
  assert.equal(r.word(parentValue), 42);
  assert.deepEqual(trace.slice(-2), [
    `clean ${pointers[1]}`,
    `clean ${pointers[0]}`,
  ]);
  r.call("root_leave", 0);
  r.call("save", parent);
  r.call("drop", parent);
  assert.equal(r.get("root_count"), 0);
});
