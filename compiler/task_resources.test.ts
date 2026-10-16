import { strict as assert } from "node:assert";
import { ResourceJournal, ResourceTokens } from "./resource_journal.ts";
import { TaskFailure, TaskRuntime } from "./task_runtime.ts";

Deno.test("task resource transfer preserves one token and moves the exact cleanup obligation", () => {
  const trace: string[] = [];
  const adapters = [{
    cleanup: (payload: number) => {
      trace.push(`clean ${payload}`);
    },
    drop: (payload: number) => {
      trace.push(`drop ${payload}`);
    },
  }];
  const tokens = new ResourceTokens();
  const parent = new ResourceJournal(adapters, undefined, undefined, tokens);
  const child = new ResourceJournal(adapters, undefined, undefined, tokens);
  parent.begin();
  child.begin();
  const before = parent.reserve();
  parent.register(before, 0, 1, 0, 0);
  const moved = parent.reserve();
  parent.register(moved, 0, 2, 0, 0);
  const own = child.reserve();
  child.register(own, 0, 3, 0, 0);
  assert.notEqual(own, before);
  assert.notEqual(own, moved);
  parent.transfer(moved, child);
  assert.throws(() => parent.release(moved), /Stale/);
  child.finish();
  parent.finish();
  assert.deepEqual(trace, [
    "clean 2",
    "drop 2",
    "clean 3",
    "drop 3",
    "clean 1",
    "drop 1",
  ]);
});

Deno.test("task resource transfer does not retain or release the moved cleanup binding", () => {
  const trace: string[] = [];
  const adapters = [{ cleanup() {}, drop() {} }];
  const bindings = {
    capture: () => 7,
    retain: (id: number) => {
      trace.push(`retain ${id}`);
    },
    release: (id: number) => {
      trace.push(`release ${id}`);
    },
  };
  const invalidate = (owner: number, token: number) => {
    trace.push(`invalidate ${owner} ${token}`);
  };
  const tokens = new ResourceTokens();
  const parent = new ResourceJournal(adapters, invalidate, bindings, tokens);
  const child = new ResourceJournal(adapters, invalidate, bindings, tokens);
  parent.begin();
  child.begin();
  const token = parent.reserve();
  parent.registerOwned(token, 0, 42, 0, 0, 99);
  parent.promote(token);
  parent.transfer(token, child);
  parent.finish();
  child.finish();
  assert.deepEqual(trace, ["retain 7"]);
  child.begin();
  child.retire(token);
  child.drain();
  child.finish();
  assert.deepEqual(trace, ["retain 7", "release 7"]);
});

Deno.test("task resource admission failures preserve the original owning journal", () => {
  let cleaned = 0;
  const adapters = [{
    cleanup() {
      cleaned++;
    },
    drop() {},
  }];
  const tokens = new ResourceTokens();
  const parent = new ResourceJournal(adapters, undefined, undefined, tokens);
  const child = new ResourceJournal(adapters, undefined, undefined, tokens);
  const foreign = new ResourceJournal(adapters);
  parent.begin();
  foreign.begin();
  const token = parent.reserve();
  parent.register(token, 0, 42, 0, 0);
  assert.throws(() => parent.transfer(token, child), /ownership domain/);
  assert.throws(() => parent.transfer(token, foreign), /ownership domain/);
  assert.throws(() => parent.transfer(token, parent), /ownership domain/);
  assert.equal(cleaned, 0);
  parent.finish();
  foreign.finish();
  assert.equal(cleaned, 1);
});

Deno.test("task resource reservations share a bounded instance budget and reclaim failed acquisition", () => {
  const tokens = new ResourceTokens();
  const adapters = [{ cleanup() {}, drop() {} }];
  const parent = new ResourceJournal(adapters, undefined, undefined, tokens);
  const child = new ResourceJournal(adapters, undefined, undefined, tokens);
  parent.begin();
  child.begin();
  for (let index = 0; index < 2048; index++) {
    parent.reserve();
    child.reserve();
  }
  assert.throws(() => parent.reserve(), /limit/);
  assert.throws(() => child.reserve(), /limit/);
  parent.finish();
  for (let index = 0; index < 2048; index++) child.reserve();
  assert.throws(() => child.reserve(), /limit/);
  child.dispose();
  child.finish();
  parent.begin();
  for (let index = 0; index < 4096; index++) parent.reserve();
  parent.finish();
});

Deno.test("task resource cancellation waits for settlement then cleans children before parent", async () => {
  const trace: string[] = [];
  const adapters = [{
    cleanup: (payload: number) => {
      trace.push(`clean ${payload}`);
    },
    drop: (payload: number) => {
      trace.push(`drop ${payload}`);
    },
  }];
  const tokens = new ResourceTokens();
  const parent = new ResourceJournal(adapters, undefined, undefined, tokens);
  const child = new ResourceJournal(adapters, undefined, undefined, tokens);
  parent.begin();
  child.begin();
  const parentToken = parent.reserve();
  parent.register(parentToken, 0, 1, 0, 0);
  const transferred = parent.reserve();
  parent.register(transferred, 0, 2, 0, 0);
  parent.transfer(transferred, child);
  let settle!: (value: number) => void;
  const waiting = new Promise<number>((resolve) => {
    settle = resolve;
  });
  const tasks = new TaskRuntime();
  const group = tasks.open();
  const task = tasks.spawn(group, {
    run(context) {
      context.cleanup(() => child.finish());
      return waiting;
    },
    dropCaptures() {},
    dropResult() {},
  }, 0);
  tasks.spawn(group, {
    run() {
      throw new Error("sibling");
    },
    dropCaptures() {},
    dropResult() {},
  }, 0);
  const joining = Promise.resolve(tasks.join(task));
  assert.deepEqual(trace, []);
  settle(42);
  await assert.rejects(joining, TaskFailure);
  assert.throws(() => tasks.close(group), TaskFailure);
  parent.finish();
  assert.deepEqual(trace, ["clean 2", "drop 2", "clean 1", "drop 1"]);
});
