import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ?? new URL("../zig-out/bin/blotc", import.meta.url);
const library = `
const capture = fn (owner: once (Unit -> U32 ! {Foreign})) -> once (Unit -> U32 ! {Foreign}) => fn () => owner ()
const call = fn (callback: once (Unit -> U32 ! {Foreign})) => callback ()
`;
const entrySource = `
import {call, capture} from "./usage"
entry const answer = fn (host: Unit -> U32 ! {Foreign}) => call (capture (fn () => host ()))
`;
Deno.test("usage once contracts survive imports retained failures restart and sync JSPI execution", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-usage-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/usage.blot`;
  const options = { executable, entry, prelude: null, cacheDirectory: `${directory}/cache` };
  const retained = await createZigProjectCompiler(options);
  try {
    const sources = { [entry]: entrySource, [dependency]: library };
    const first = await retained.build({ sources });
    assert(first.success, JSON.stringify(first));
    for (const asyncHost of [false, true]) {
      const guest = await instantiateGuest(first.bytes, {asynchronous: asyncHost});
      try {
        let calls = 0;
        let callback = guest.capability({ parameter: "Unit", result: "U32", call: () => 7 });
        let answer = 0;
        if (asyncHost) {
          callback = guest.capabilityAsync({ parameter: "Unit", result: "U32", call: async () => { calls++; await Promise.resolve(); return 7; } });
          answer = Number(await guest.callAsync("answer", callback));
        } else {
          callback = guest.capability({ parameter: "Unit", result: "U32", call: () => { calls++; return 7; } });
          answer = Number(guest.call("answer", callback));
        }
        assert.equal(answer, 7);
        assert.equal(calls, 1);
      } finally { guest.dispose(); }
    }
    const bad = await retained.build({ sources: { ...sources, [dependency]: library.replace("callback ()", "@u32.add (callback ()) (callback ())") } });
    assert(!bad.success);
    assert(bad.diagnostics.some((d) => d.code === "once_reused"), JSON.stringify(bad));
    const recovered = await retained.build({ sources });
    assert(recovered.success, JSON.stringify(recovered));
    assert.deepEqual(recovered.bytes, first.bytes);
    const restarted = await createZigProjectCompiler(options);
    try {
      const resumed = await restarted.build({ sources });
      assert(resumed.success, JSON.stringify(resumed));
      assert.deepEqual(resumed.bytes, first.bytes);
    } finally { await restarted.dispose(); }
  } finally { await retained.dispose(); await Deno.remove(directory, { recursive: true }); }
});

Deno.test("usage exit and exact loop contracts execute across imports and failed retained edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-usage-control-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/usage.blot`;
  const control = `
const bounded = fn (callback: once (Unit -> U32 ! {Foreign})) => do:
  let initial = do:
    break 0
  for index in 3..4:
    use callback ()
  break 7
const stopped = fn (callback: once (Unit -> U32 ! {Foreign})) => do:
  for ever:
    use callback ()
    break
  break 7
const guarded = fn (callback: once (Unit -> Bool ! {Foreign})) => case #True of
  #True if callback () => 7
  #True => 7
  #False => 0
`;
  const main = `
import {bounded, stopped, guarded} from "./usage"
entry const bound = fn (host: Unit -> U32 ! {Foreign}) => bounded (fn () => host ())
entry const stop = fn (host: Unit -> U32 ! {Foreign}) => stopped (fn () => host ())
entry const guard = fn (host: Unit -> U32 ! {Foreign}) => guarded (fn () => @u32.eq (host ()) 7)
`;
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: `${directory}/cache`,
  };
  const retained = await createZigProjectCompiler(options);
  try {
    const sources = { [entry]: main, [dependency]: control };
    const first = await retained.build({ sources });
    assert(first.success, JSON.stringify(first));
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(first.bytes, { asynchronous });
      try {
        for (const name of ["bound", "stop", "guard"]) {
          let calls = 0;
          let capability = guest.capability({
            parameter: "Unit",
            result: "U32",
            call: () => {
              calls++;
              return 7;
            },
          });
          let answer = 0;
          if (asynchronous) {
            capability = guest.capabilityAsync({
              parameter: "Unit",
              result: "U32",
              call: async () => {
                calls++;
                await Promise.resolve();
                return 7;
              },
            });
            answer = Number(await guest.callAsync(name, capability));
          } else {
            answer = Number(guest.call(name, capability));
          }
          assert.equal(answer, 7);
          assert.equal(calls, 1);
        }
      } finally {
        guest.dispose();
      }
    }
    const rejected = await retained.build({
      sources: { ...sources, [dependency]: control.replace("3..4", "3..5") },
    });
    assert(!rejected.success);
    assert(
      rejected.diagnostics.some((diagnostic) =>
        diagnostic.code === "once_reused"
      ),
      JSON.stringify(rejected),
    );
    const recovered = await retained.build({ sources });
    assert(recovered.success, JSON.stringify(recovered));
    assert.deepEqual(recovered.bytes, first.bytes);
    const restarted = await createZigProjectCompiler(options);
    try {
      const resumed = await restarted.build({ sources });
      assert(resumed.success, JSON.stringify(resumed));
      assert.deepEqual(resumed.bytes, first.bytes);
    } finally {
      await restarted.dispose();
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("usage loan regions execute imported reads and survive failed edits restart and JSPI", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-usage-loans-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/loans.blot`;
  const loans = `
const inspect = fn (owner: unique U32) => @usage.borrow_mut owner (fn loan => @u32.add (@usage.read loan) (@usage.read loan))
const nested = fn (owner: unique U32) => @usage.borrow_mut owner (fn loan => @usage.borrow loan (fn inner => @usage.read inner))
const float = fn (owner: unique F32) => @usage.borrow owner (fn loan => @f32.add (@usage.read loan) 0.5)
`;
  const main = `
import {inspect, nested, float} from "./loans"
entry const twice = fn () => inspect 9
entry const again = fn () => nested 9
entry const half = fn () => float 1.0
entry const answer = fn (host: Unit -> U32 ! {Foreign}) => (fn (owner: unique U32) => @usage.borrow owner (fn loan => @u32.add (@usage.read loan) (host ()))) 9
`;
  const options = { executable, entry, prelude: null, cacheDirectory: `${directory}/cache` };
  const compiler = await createZigProjectCompiler(options);
  try {
    const sources = { [entry]: main, [dependency]: loans };
    const first = await compiler.build({ sources });
    assert(first.success, JSON.stringify(first));
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(first.bytes, { asynchronous });
      try {
        const invoke = async (name: string) => {
          if (asynchronous) return await guest.callAsync(name, null);
          return guest.call(name, null);
        };
        assert.equal(await invoke("twice"), 18);
        assert.equal(await invoke("again"), 9);
        assert.equal(await invoke("half"), 1.5);
        let calls = 0;
        let host = guest.capability({ parameter: "Unit", result: "U32", call: () => { calls++; return 7; } });
        let answer = 0;
        if (asynchronous) {
          host = guest.capabilityAsync({ parameter: "Unit", result: "U32", call: async () => { calls++; await Promise.resolve(); return 7; } });
          answer = Number(await guest.callAsync("answer", host));
        } else {
          answer = Number(guest.call("answer", host));
        }
        assert.equal(answer, 16);
        assert.equal(calls, 1);
      } finally { guest.dispose(); }
    }
    const bad = await compiler.build({ sources: { ...sources, [dependency]: loans.replace("@u32.add (@usage.read loan) (@usage.read loan)", "loan") } });
    assert(!bad.success);
    assert(bad.diagnostics.some((diagnostic) => diagnostic.code === "borrow_escape"), JSON.stringify(bad));
    const recovered = await compiler.build({ sources });
    assert(recovered.success, JSON.stringify(recovered));
    assert.deepEqual(recovered.bytes, first.bytes);
    const restarted = await createZigProjectCompiler(options);
    try {
      const resumed = await restarted.build({ sources });
      assert(resumed.success, JSON.stringify(resumed));
      assert.deepEqual(resumed.bytes, first.bytes);
    } finally { await restarted.dispose(); }
  } finally { await compiler.dispose(); await Deno.remove(directory, { recursive: true }); }
});
