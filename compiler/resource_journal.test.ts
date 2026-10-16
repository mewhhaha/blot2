import { strict as assert } from "node:assert";
import { ResourceJournal } from "./resource_journal.ts";

Deno.test("resource journal takes each owner before cleanup and drains LIFO after failures", () => {
  const trace: string[] = [];
  const failure = new Error("release failed");
  const journal = new ResourceJournal([{
    cleanup: (payload) => {
      trace.push(`release${payload}`);
      if (payload === 2) throw failure;
    },
    drop: (payload) => {
      trace.push(`drop${payload}`);
    },
  }]);
  journal.begin();
  const first = journal.reserve();
  journal.register(first, 0, 1, 0, 0);
  const second = journal.reserve();
  journal.register(second, 0, 2, 0, 0);
  const third = journal.reserve();
  journal.register(third, 0, 3, 0, 0);
  assert.throws(() => journal.finish(), (cause) => cause === failure);
  assert.deepEqual(trace, [
    "release3",
    "drop3",
    "release2",
    "drop2",
    "release1",
    "drop1",
  ]);
  journal.finish();
  assert.equal(trace.length, 6);
  journal.begin();
  assert.throws(() => journal.release(first), /Stale/);
  const pending = journal.reserve(); // acquisition failed before registration
  assert.throws(() => journal.release(pending), /not owned/);
  journal.finish();
  assert.equal(trace.length, 6);
});
Deno.test("resource journal preserves drop failures and never retries an explicitly released owner", () => {
  const trace: number[] = [];
  const failure = new Error("drop failed");
  const journal = new ResourceJournal([{
    cleanup: (payload) => {
      trace.push(payload);
    },
    drop: () => {
      throw failure;
    },
  }]);
  journal.begin();
  const token = journal.reserve();
  journal.register(token, 0, 7, 0, 0);
  assert.throws(() => journal.release(token), (cause) => cause === failure);
  assert.throws(() => journal.release(token), /Stale/);
  journal.finish();
  assert.deepEqual(trace, [7]);
});
Deno.test("resource journal bounds reservations before acquisition and rejects reentrant cleanup", () => {
  let attempts = 0;
  const journal = new ResourceJournal([{
    cleanup: () => {
      attempts++;
      assert.throws(() => journal.reserve(), /No active/);
      assert.throws(() => journal.begin(), /active/);
    },
    drop: () => {},
  }]);
  journal.begin();
  for (let index = 0; index < 4096; index++) {
    const token = journal.reserve();
    journal.register(token, 0, index, 0, 0);
  }
  assert.throws(() => journal.reserve(), /limit/);
  journal.finish();
  assert.equal(attempts, 4096);
});

Deno.test("resource journal bounds simultaneous scopes while reclaiming completed attempts", () => {
  let attempts = 0;
  const journal = new ResourceJournal([{
    cleanup: () => {
      attempts++;
    },
    drop: () => {},
  }]);
  journal.begin();
  let previous = 0;
  for (let index = 0; index < 10000; index++) {
    const token = journal.reserve();
    assert(token > previous);
    journal.register(token, 0, index, 0, 0);
    journal.release(token);
    assert.throws(() => journal.release(token), /Stale/);
    previous = token;
  }
  journal.finish();
  assert.equal(attempts, 10000);
});

Deno.test("resource retirement defers callbacks and drains newly retired captures at a safe point", () => {
  const trace: number[] = [];
  let captured = 0;
  const journal = new ResourceJournal([{
    cleanup: (payload) => {
      trace.push(payload);
      journal.drain(); // Safe points cannot run a nested cleanup attempt.
    },
    drop: (payload) => {
      if (payload === 1) journal.retire(captured);
    },
  }]);
  journal.begin();
  const parent = journal.reserve();
  journal.register(parent, 0, 1, 0, 0);
  captured = journal.reserve();
  journal.register(captured, 0, 2, 0, 0);
  const live = journal.reserve();
  journal.register(live, 0, 3, 0, 0);
  journal.retire(parent);
  assert.deepEqual(trace, []);
  assert.throws(() => journal.retire(parent), /not owned/);
  journal.drain();
  assert.deepEqual(trace, [1, 2]);
  assert.throws(() => journal.release(parent), /Stale/);
  journal.finish();
  assert.deepEqual(trace, [1, 2, 3]);
});

Deno.test("resource retirement preserves failure priority and only bounds live reservations", () => {
  const trace: number[] = [];
  const failure = new Error("first attempt");
  const journal = new ResourceJournal([{
    cleanup: (payload) => {
      trace.push(payload);
      if (payload === 2) throw failure;
    },
    drop: () => {},
  }]);
  journal.begin();
  const older = journal.reserve();
  journal.register(older, 0, 1, 0, 0);
  const newer = journal.reserve();
  journal.register(newer, 0, 2, 0, 0);
  journal.retire(older);
  journal.retire(newer);
  assert.throws(() => journal.drain(), (cause) => cause === failure);
  assert.deepEqual(trace, [2, 1]);
  journal.finish();
  journal.begin();
  let previous = journal.reserve();
  journal.register(previous, 0, 3, 0, 0);
  for (let index = 0; index < 10000; index++) {
    const next = journal.reserve();
    journal.register(next, 0, 3, 0, 0);
    journal.retire(previous);
    journal.drain();
    previous = next;
  }
  journal.finish();
  assert.equal(trace.length, 10003);
  assert.throws(() => journal.retire(previous), /No active/);
});

Deno.test("resource journal invalidates only live weak owners before cleanup and never reads retired boxes", () => {
  const trace: string[] = [];
  const journal = new ResourceJournal([{
    cleanup: (payload) => trace.push(`cleanup${payload}`),
    drop: (payload) => trace.push(`drop${payload}`),
  }], (owner, token) => trace.push(`invalidate${owner}:${token}`));
  journal.begin();
  const live = journal.reserve();
  journal.registerOwned(live, 0, 1, 0, 0, 1024);
  const retired = journal.reserve();
  journal.registerOwned(retired, 0, 2, 0, 0, 2048);
  journal.retire(retired);
  journal.drain();
  assert.deepEqual(trace, ["cleanup2", "drop2"]);
  journal.finish();
  assert.deepEqual(trace, [
    "cleanup2",
    "drop2",
    `invalidate1024:${live}`,
    "cleanup1",
    "drop1",
  ]);
  const unsupported = new ResourceJournal([]);
  unsupported.begin();
  assert.throws(
    () => unsupported.registerOwned(unsupported.reserve(), 0, 0, 0, 0, 1024),
    /Invalid/,
  );
  unsupported.finish();
});

Deno.test("persistent resource registrations survive invocation leave and release once on retirement or disposal", () => {
  const trace: number[] = [];
  const journal = new ResourceJournal([{
    cleanup: (payload) => {
      trace.push(payload);
    },
    drop: () => {},
  }], () => {});
  journal.begin();
  const retained = journal.reserve();
  journal.registerOwned(retained, 0, 7, 0, 0, 100);
  journal.promote(retained);
  const transient = journal.reserve();
  journal.register(transient, 0, 9, 0, 0);
  journal.finish();
  assert.deepEqual(trace, [9]);
  journal.begin();
  journal.promote(retained);
  journal.finish();
  assert.deepEqual(trace, [9]);
  journal.begin();
  journal.retire(retained);
  journal.drain();
  assert.deepEqual(trace, [9, 7]);
  assert.throws(() => journal.promote(retained), /Stale/);
  const next = journal.reserve();
  journal.registerOwned(next, 0, 11, 0, 0, 104);
  journal.promote(next);
  journal.finish();
  journal.begin();
  journal.dispose();
  journal.finish();
  assert.deepEqual(trace, [9, 7, 11]);
  journal.begin();
  assert.throws(() => journal.release(next), /Stale/);
  journal.finish();
});

Deno.test("persistent cleanup bindings follow each registered attempt through compaction and failures", () => {
  const trace: string[] = [];
  let current = 7;
  const journal = new ResourceJournal(
    [{
      cleanup(value) {
        trace.push(`cleanup${value}`);
        if (value === 9) throw new Error("cleanup failure");
      },
      drop(value) {
        trace.push(`drop${value}`);
      },
    }],
    () => {},
    {
      capture: () => current,
      retain(id) {
        trace.push(`retain${id}`);
      },
      release(id) {
        trace.push(`release${id}`);
      },
    },
  );
  journal.begin();
  const first = journal.reserve();
  journal.registerOwned(first, 0, 7, 0, 0, 100);
  journal.promote(first);
  current = 9;
  const other = journal.reserve();
  journal.registerOwned(other, 0, 9, 0, 0, 104);
  journal.promote(other);
  journal.finish();
  assert.deepEqual(trace, ["retain7", "retain9"]);
  journal.begin();
  journal.release(first);
  journal.finish();
  assert.deepEqual(trace.slice(2), ["cleanup7", "drop7", "release7"]);
  journal.begin();
  assert.throws(() => journal.dispose(), /cleanup failure/);
  journal.finish();
  assert.deepEqual(trace.slice(5), ["cleanup9", "drop9", "release9"]);
});
