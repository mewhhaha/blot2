import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun } from "./compile_helpers.ts";

const source = `
const choose = func (values: Array U32) => return func (branch: U32) => return do:
  if branch == 0:
    break values
  if branch == 1:
    if values[0] == 41:
      break values
    break @array.set values 0 77
  break @array.fill 64 branch
entry const run = func (branch: U32) => return do:
  let values = @array.fill 64 41
  let selected = choose values branch
  for index in 0..200:
    let discarded = @array.fill 8192 index
    if discarded[8191] != index:
      @panic "pressure"
  break selected
entry const suspend = func (host: Array U32 -> Array U32 ! {Foreign}) => return do:
  let selected = choose (@array.fill 64 41) 1
  use reply <- host selected
  break #[selected[0], reply[0]]
entry const trap = func (branch: U32) => return do:
  let selected = choose (@array.fill 64 41) branch
  if selected[0] == 41:
    @panic "selected trap"
  break selected[0]
`;

Deno.test("conditional borrowed returns survive nested exits pressure suspension and exceptional cleanup", async () => {
  await compileAndRun(source, async (_, bytes) => {
    const module = new WebAssembly.Module(bytes);
    assert.deepEqual([
      ...new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      ),
    ], [2, 2, 0]);
    const raw = new WebAssembly.Instance(module, {
      "blot:host/1": {
        call_array_u32_array_u32: () => {
          throw new Error("unused host");
        },
      },
    }).exports;
    const enter = raw["blot:ownership_enter"] as CallableFunction;
    const leave = raw["blot:ownership_leave"] as CallableFunction;
    const count = (name: string) =>
      Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
    const memory = raw["blot:memory"] as WebAssembly.Memory;
    let warmed = 0;
    for (const branch of [0, 1, 2, 0, 1, 2]) {
      enter();
      const before = count("destroyed");
      const pointer = (raw.run as CallableFunction)(branch);
      const expected = branch < 2 ? 41 : branch;
      assert.deepEqual(
        new Uint32Array(memory.buffer, pointer + 4, 64),
        new Uint32Array(64).fill(expected),
      );
      assert(
        count("destroyed") > before + 100,
        "discarded arrays must retire during the invocation",
      );
      if (warmed !== 0) assert.equal(memory.buffer.byteLength, warmed);
      warmed = memory.buffer.byteLength;
      leave(0);
      assert.equal(count("roots"), 0);
      assert.equal(count("leases"), 0);
    }
    enter();
    assert.throws(
      () => (raw.trap as CallableFunction)(0),
      WebAssembly.RuntimeError,
    );
    leave(1);
    assert.equal(count("roots"), 0);
    assert.equal(count("leases"), 0);
    leave(2);
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(module, { asynchronous });
      const definition = {
        parameter: "Array U32",
        result: "Array U32",
        call: (values: Uint32Array) => values,
      } as const;
      let host;
      let failure;
      if (asynchronous) {
        host = guest.capabilityAsync({
          ...definition,
          call: async (values) => {
            await Promise.resolve();
            return values;
          },
        });
        failure = guest.capabilityAsync({
          ...definition,
          call: async () => {
            throw new Error("selected rejection");
          },
        });
      } else {
        host = guest.capability(definition);
        failure = guest.capability({
          ...definition,
          call: () => {
            throw new Error("selected rejection");
          },
        });
      }
      try {
        if (asynchronous) {
          assert.deepEqual(
            await guest.callAsync("suspend", host),
            Uint32Array.of(41, 41),
          );
          await assert.rejects(
            () => guest.callAsync("suspend", failure),
            (error) => (error as { code: string }).code === "host_exception",
          );
          assert.deepEqual(
            await guest.callAsync("suspend", host),
            Uint32Array.of(41, 41),
          );
        } else {
          assert.deepEqual(guest.call("suspend", host), Uint32Array.of(41, 41));
          assert.throws(
            () => guest.call("suspend", failure),
            (error) => (error as { code: string }).code === "host_exception",
          );
          assert.deepEqual(guest.call("suspend", host), Uint32Array.of(41, 41));
        }
      } finally {
        guest.dispose();
      }
    }
  });
});
