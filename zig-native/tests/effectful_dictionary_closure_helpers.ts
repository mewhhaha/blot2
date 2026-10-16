import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";

export const program = await Deno.readTextFile(
  new URL(
    "../fixtures/request-fixtures/effectful-dictionary-closure.blot",
    import.meta.url,
  ),
);
export function variant(helper: string) {
  return program.replace(
    "const helper = fn value => Render.show value",
    `const helper = ${helper}`,
  );
}
export async function checkGuest(
  guest: Awaited<ReturnType<typeof instantiateGuest>>,
  asynchronous: boolean,
) {
  const trace: number[] = [];
  let trap = false;
  const host = guest.capability({
    parameter: "U32",
    result: "U32",
    call: (value) => {
      const input = value as number;
      trace.push(input);
      if (trap && input === 1000) throw new Error("ordered dictionary trap");
      if (input === 42) return 10;
      if (input === 1) return 30;
      return 0;
    },
  });
  const call = async () => {
    if (asynchronous) return await guest.callAsync("answer", host);
    return guest.call("answer", host);
  };
  assert.equal(await call(), 184);
  assert.deepEqual(trace, [42, 1000, 1, 1000]);
  trace.length = 0;
  trap = true;
  await assert.rejects(call());
  assert.deepEqual(trace, [42, 1000]);
  trace.length = 0;
  trap = false;
  assert.equal(await call(), 184);
  assert.deepEqual(trace, [42, 1000, 1, 1000]);
  const warmed = guest.memoryBytes();
  for (let i = 0; i < 48; i++) assert.equal(await call(), 184);
  assert.equal(guest.memoryBytes(), warmed);
}
export async function execute(bytes: Uint8Array<ArrayBuffer>) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      await checkGuest(guest, asynchronous);
    } finally {
      guest.dispose();
    }
    const module = new WebAssembly.Module(bytes);
    assert.deepEqual(WebAssembly.Module.imports(module), [{
      module: "blot:host/1",
      name: "call_u32_u32",
      kind: "function",
    }]);
    const jspi = WebAssembly as unknown as {
      Suspending: new (
        callback: (reference: unknown, value: number) => Promise<number>,
      ) => WebAssembly.ImportValue;
      promising(fn: CallableFunction): (...args: unknown[]) => Promise<number>;
    };
    const trace: number[] = [];
    let failure = false;
    const host = (_reference: unknown, value: number) => {
      trace.push(value);
      if (failure && value === 1000) {
        throw new Error("raw ordered dictionary trap");
      }
      if (value === 42) return 10;
      if (value === 1) return 30;
      return 0;
    };
    let imported: WebAssembly.ImportValue = host;
    if (asynchronous) {
      imported = new jspi.Suspending(async (reference, value) => {
        await Promise.resolve();
        return host(reference, value);
      });
    }
    const raw = new WebAssembly.Instance(module, {
      "blot:host/1": { call_u32_u32: imported },
    }).exports;
    const enter = raw["blot:ownership_enter"] as CallableFunction;
    const leave = raw["blot:ownership_leave"] as CallableFunction;
    const invoke = async () => {
      const target = raw.answer as CallableFunction;
      if (asynchronous) return await jspi.promising(target)(null);
      return target(null);
    };
    const count = (name: string) =>
      Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
    const call = async (fails = false) => {
      trace.length = 0;
      failure = fails;
      enter();
      try {
        if (fails) {
          await assert.rejects(invoke());
          assert.deepEqual(trace, [42, 1000]);
        } else {
          assert.equal(await invoke(), 184);
          assert.deepEqual(trace, [42, 1000, 1, 1000]);
        }
      } finally {
        let outcome = 0;
        if (fails) outcome = 1;
        leave(outcome);
      }
      assert.equal(count("roots"), 0);
      assert.equal(count("leases"), 0);
    };
    await call();
    await call(true);
    await call();
    const memory = raw["blot:memory"] as WebAssembly.Memory;
    const warmed = memory.buffer.byteLength;
    for (let i = 0; i < 48; i++) await call();
    assert.equal(memory.buffer.byteLength, warmed);
    leave(2);
  }
}
