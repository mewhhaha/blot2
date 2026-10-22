import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun } from "./compile_helpers.ts";

const hostSource = `
entry const run = fn (host: Array U32 -> Array U32 ! {Foreign}) => do:
  let captured = @array.fill 2048 41
  use reply <- host captured
  break @array.set reply 0 (@u32.add captured[1] reply[1])
entry const ready = 7
`;

function admitted(bytes: Uint8Array<ArrayBuffer>): WebAssembly.Module {
  const module = new WebAssembly.Module(bytes);
  assert.deepEqual([
    ...new Uint8Array(
      WebAssembly.Module.customSections(module, "blot:ownership")[0],
    ),
  ], [2, 2, 0]);
  return module;
}

Deno.test("counted Array host arguments and replies stay owned across JSPI settlement and rejection", async () => {
  await compileAndRun(hostSource, async (_, bytes) => {
    const module = admitted(bytes);
    let exports: WebAssembly.Exports;
    let settle: ((value: Uint32Array) => void) | undefined;
    let reject: ((reason: unknown) => void) | undefined;
    let retained: Uint32Array | undefined;
    const jspi = WebAssembly as unknown as {
      Suspending: new (
        fn: (reference: unknown, pointer: number) => Promise<number>,
      ) => WebAssembly.ImportValue;
      promising(fn: CallableFunction): (...args: unknown[]) => Promise<number>;
    };
    const Suspender = jspi.Suspending;
    const imports = {
      "blot:host/1": {
        call_array_u32_array_u32: new Suspender(
          (reference: unknown, pointer: number) => {
            assert.equal(typeof reference, "object");
            const memory = exports["blot:memory"] as WebAssembly.Memory;
            const length = new DataView(memory.buffer).getUint32(pointer, true);
            retained = new Uint32Array(memory.buffer, pointer + 4, length)
              .slice();
            return new Promise<Uint32Array>((resolve, failure) => {
              settle = resolve;
              reject = failure;
            }).then((values) => {
              const pointer = (exports["blot:allocate"] as CallableFunction)(
                (values.length + 1) * 4,
              );
              new Uint32Array(memory.buffer, pointer, values.length + 1).set([
                values.length,
                ...values,
              ]);
              return pointer;
            });
          },
        ),
      },
    };
    exports = new WebAssembly.Instance(module, imports).exports;
    const count = (name: string) =>
      Number((exports[`blot:rc_${name}`] as WebAssembly.Global).value);
    const enter = exports["blot:ownership_enter"] as CallableFunction;
    const leave = exports["blot:ownership_leave"] as CallableFunction;
    const run = jspi.promising(exports.run as CallableFunction);
    enter();
    const pending = run({});
    assert.equal(count("host_refs"), 1);
    assert(count("roots") > 0);
    assert(count("leases") > 0);
    assert.equal(retained![0], 41);
    settle!(retained!);
    const pointer = await pending as number;
    const memory = exports["blot:memory"] as WebAssembly.Memory;
    assert.equal(new DataView(memory.buffer).getUint32(pointer + 4, true), 82);
    leave(0);
    assert.equal(count("host_refs"), 0);
    assert.equal(count("roots"), 0);
    assert.equal(count("leases"), 0);
    const destroyed = count("destroyed");
    enter();
    const failed = run({});
    assert.equal(count("host_refs"), 1);
    reject!(new Error("host rejection"));
    await assert.rejects(failed, /host rejection/);
    leave(1);
    assert.equal(count("host_refs"), 0);
    assert.equal(count("roots"), 0);
    assert.equal(count("leases"), 0);
    assert(count("destroyed") > destroyed);
    leave(2);
  });
});

Deno.test("a pending JSPI invocation keeps copied packets valid and blocks reentry and disposal", async () => {
  await compileAndRun(hostSource, async (_, bytes) => {
    const module = admitted(bytes);
    const guest = await instantiateGuest(module, { asynchronous: true });
    let settle: ((value: Uint32Array) => void) | undefined;
    let packet: Uint32Array | undefined;
    const host = guest.capabilityAsync({
      parameter: "Array U32",
      result: "Array U32",
      call: (values) => {
        packet = values;
        return new Promise<Uint32Array>((resolve) => {
          settle = resolve;
        });
      },
    });
    try {
      const pending = guest.callAsync("run", host);
      assert.deepEqual(packet, new Uint32Array(2048).fill(41));
      assert.throws(
        () => guest.read("ready"),
        (error) => (error as { code: string }).code === "reentrant_call",
      );
      assert.throws(
        () => guest.dispose(),
        (error) => (error as { code: string }).code === "reentrant_call",
      );
      await assert.rejects(
        () => guest.callAsync("run", host),
        (error) => (error as { code: string }).code === "reentrant_call",
      );
      settle!(packet!);
      const result = await pending as Uint32Array;
      assert.equal(result[0], 82);
      assert.equal(packet![0], 41);
      assert.equal(guest.read("ready"), 7);
    } finally {
      guest.dispose();
    }
  });
});

const requestSource = `
type Tick is effect = { read: Array U32 -> Array U32 }
const work = @computation (fn () => do:
  use first <- Tick.read #[41, 42]
  use second <- Tick.read first
  break second
)
entry const run = fn (host: Array U32 -> Array U32 ! {Foreign}) => do:
  let saved = #[90, 91]
  for request in @requests work:
    case request of
      effect Tick.read value =>
        let before = saved
        use reply <- host value
        saved := @array.set self 0 reply[0]
        yield @array.set reply 1 before[1]
      complete value =>
        break value
`;

Deno.test("counted request payloads snapshots replies and returned children survive repeated sync and JSPI calls", async () => {
  await compileAndRun(requestSource, async (_, bytes) => {
    const module = admitted(bytes);
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(module, { asynchronous });
      const events: number[] = [];
      const definition = {
        parameter: "Array U32",
        result: "Array U32",
        call: (values: Uint32Array) => {
          events.push(values[1]);
          return values;
        },
      } as const;
      let host;
      if (asynchronous) {
        host = guest.capabilityAsync({
          ...definition,
          call: async (values) => {
            await Promise.resolve();
            return definition.call(values);
          },
        });
      } else host = guest.capability(definition);
      try {
        let warmed = 0;
        for (let index = 0; index < 2048; index++) {
          let result;
          if (asynchronous) result = await guest.callAsync("run", host);
          else result = guest.call("run", host);
          assert.deepEqual(result, Uint32Array.of(41, 91));
          if (index === 7) warmed = guest.memoryBytes();
          if (index > 7) assert.equal(guest.memoryBytes(), warmed);
        }
        assert.equal(events.length, 4096);
        for (let index = 0; index < events.length; index += 2) {
          assert.deepEqual(events.slice(index, index + 2), [42, 91]);
        }
      } finally {
        guest.dispose();
      }
    }
  });
});

Deno.test("a ready memo retains its original host closure without rebinding a revoked capability", async () => {
  await compileAndRun(
    `
type Fetch is effect = { read: Unit -> (U32 -> U32 ! {Foreign}) }
const keep = fn ~(value: U32 -> U32 ! {Foreign}) => value
const saved = keep (Fetch.read ())
entry const answer = fn (host: U32 -> U32 ! {Foreign}) => do (@effect.provider Fetch.read (fn () => host)):
  use previous <- @demand saved
  break previous 41
entry const pure = fn () => 7
`,
    async (_, bytes) => {
      const module = admitted(bytes);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(module, { asynchronous });
        let firstCalls = 0, laterCalls = 0;
        const firstDefinition = {
          parameter: "U32",
          result: "U32",
          call: (value: number) => {
            firstCalls++;
            return value + 1;
          },
        } as const;
        const laterDefinition = {
          parameter: "U32",
          result: "U32",
          call: (value: number) => {
            laterCalls++;
            return value + 100;
          },
        } as const;
        let first, later;
        if (asynchronous) {
          first = guest.capabilityAsync({
            ...firstDefinition,
            call: async (value) => firstDefinition.call(value),
          });
          later = guest.capabilityAsync({
            ...laterDefinition,
            call: async (value) => laterDefinition.call(value),
          });
        } else {
          first = guest.capability(firstDefinition);
          later = guest.capability(laterDefinition);
        }
        try {
          if (asynchronous) {
            assert.equal(
              await guest.callAsync("answer", first),
              42,
            );
          } else assert.equal(guest.call("answer", first), 42);
          for (let index = 0; index < 3; index++) {
            if (asynchronous) {
              await assert.rejects(
                () => guest.callAsync("answer", later),
                WebAssembly.RuntimeError,
              );
            } else {assert.throws(
                () => guest.call("answer", later),
                WebAssembly.RuntimeError,
              );}
            if (asynchronous) {
              assert.equal(
                await guest.callAsync("pure", null),
                7,
              );
            } else assert.equal(guest.call("pure", null), 7);
          }
          assert.equal(firstCalls, 1);
          assert.equal(laterCalls, 0);
        } finally {
          guest.dispose();
        }
      }
    },
  );
});

Deno.test("2048 nested demand cancel and settle cycles restore counted roots and externref owners", async () => {
  for (const cancellation of ["return 7", "break"]) {
    await compileAndRun(
      `
type Tick is effect = { read: U32 -> U32 }
const delay = fn ~value => value
const abort = fn log => fn computation => do:
  for request in @requests computation:
    case request of
      effect Tick.read value =>
        use log 1
        ${cancellation}
      complete value =>
        break value
  break 7
const finish = fn log => fn computation => do:
  for request in @requests computation:
    case request of
      effect Tick.read value =>
        use log 2
        yield @u32.add value 40
      complete value =>
        break value
const scenario = fn log => do:
  let payload = @array.fill 128 41
  let inner = delay (Tick.read 1)
  let pending = delay (do:
    use value <- @demand inner
    break @u32.add payload[1] value
  )
  let work = @computation (fn () => @demand pending)
  use first <- abort log work
  use second <- finish log work
  use third <- finish log work
  break @u32.add first (@u32.add second third)
entry const answer = fn (log: U32 -> U32 ! {Foreign}) => scenario log
`,
      async (_, bytes) => {
        const module = admitted(bytes);
        for (const asynchronous of [false, true]) {
          const events: number[] = [];
          const callback = (_: unknown, value: number) => {
            events.push(value);
            return value;
          };
          const jspi = WebAssembly as unknown as {
            Suspending: new (
              fn: (_: unknown, value: number) => Promise<number>,
            ) => WebAssembly.ImportValue;
            promising(
              fn: CallableFunction,
            ): (...args: unknown[]) => Promise<number>;
          };
          let imported: WebAssembly.ImportValue = callback;
          if (asynchronous) {
            imported = new jspi.Suspending(async (reference, value) => {
              await Promise.resolve();
              return callback(reference, value);
            });
          }
          const raw = new WebAssembly.Instance(module, {
            "blot:host/1": { call_u32_u32: imported },
          }).exports;
          const count = (name: string) =>
            Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
          const roots = count("roots"), leases = count("leases");
          const run = raw.answer as CallableFunction;
          const suspended = jspi.promising(run);
          const before = count("destroyed");
          for (let index = 0; index < 2048; index++) {
            if (asynchronous) assert.equal(await suspended({}), 171);
            else assert.equal(run({}), 171);
            assert.equal(count("roots"), roots);
            assert.equal(count("leases"), leases);
            assert.equal(count("host_refs"), 0);
          }
          assert.equal(events.length, 4096);
          for (let index = 0; index < events.length; index += 2) {
            assert.deepEqual(events.slice(index, index + 2), [1, 2]);
          }
          assert(
            count("destroyed") - before > 2048 * 8,
            "discarded captures and requests must actually retire",
          );
          (raw["blot:ownership_leave"] as CallableFunction)(2);
        }
      },
    );
  }
});

Deno.test("a scalar host reply borrows its Array argument from the suspended caller under allocation pressure", async () => {
  await compileAndRun(`
entry const run = fn (host: Array U32 -> U32 ! {Foreign}) => do:
  let captured = @array.fill 4096 21
  use reply <- host captured
  break @u32.add captured[2] reply
`, async (_, bytes) => {
    const module = admitted(bytes);
    let exports: WebAssembly.Exports;
    let settle: ((value: number) => void) | undefined;
    let argument = 0;
    const jspi = WebAssembly as unknown as {
      Suspending: new (fn: (reference: unknown, pointer: number) => Promise<number>) => WebAssembly.ImportValue;
      promising(fn: CallableFunction): (...args: unknown[]) => Promise<number>;
    };
    exports = new WebAssembly.Instance(module, { "blot:host/1": {
      call_array_u32_u32: new jspi.Suspending((_reference, pointer) => {
        argument = pointer;
        return new Promise<number>(resolve => { settle = resolve; });
      }),
    } }).exports;
    const enter = exports["blot:ownership_enter"] as CallableFunction;
    const leave = exports["blot:ownership_leave"] as CallableFunction;
    const count = (name: string) => Number((exports[`blot:rc_${name}`] as WebAssembly.Global).value);
    const run = jspi.promising(exports.run as CallableFunction);
    enter();
    const pending = run({});
    assert(count("roots") > 0); assert(count("leases") > 0);
    assert.equal(count("host_refs"), 1);
    for (let index = 0; index < 4; index++) (exports["blot:allocate"] as CallableFunction)(1024 * 1024);
    const view = new DataView((exports["blot:memory"] as WebAssembly.Memory).buffer);
    assert.equal(view.getUint32(argument, true), 4096);
    assert.equal(view.getUint32(argument + 12, true), 21);
    settle!(21);
    assert.equal(await pending, 42);
    leave(0);
    assert.equal(count("roots"), 0); assert.equal(count("leases"), 0);
    assert.equal(count("host_refs"), 0);
    leave(2);
  });
});
