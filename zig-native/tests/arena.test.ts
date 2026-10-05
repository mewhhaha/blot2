import { instantiateGuest } from "../../compiler/guest.ts";
const fixture = new URL("../zig-out/arena-fixture.wasm", import.meta.url);
function equal(actual: unknown, expected: unknown): void {
  if (!Object.is(actual, expected)) throw new Error(`Expected ${expected}, received ${actual}`);
}
Deno.test("linear arena grows and resets without overwriting static values", async () => {
  const bytes = await Deno.readFile(fixture);
  equal(WebAssembly.validate(bytes), true);
  const guest = await instantiateGuest(bytes);
  try {
    equal(guest.call("captured", 21), 42);
    equal(guest.call("initialized", null), 42);
    equal(guest.call("captured", 0xffffffff), 20);
    const scalar = guest.capability({ parameter: "U32", result: "U32", call: value => value * 2 });
    equal(guest.call("host_scalar", scalar), 42);
    for (let iteration = 0; iteration < 100; iteration++) {
      equal(guest.call("host_retained", scalar), 42);
      equal(guest.call("host_retained_count", null), 0);
      equal(guest.call("host_handle_cleared", 0), true);
      equal(guest.call("host_handle_cleared", 1), true);
    }
    equal(guest.call("host_retained_capacity", null), 2);
    let array_calls = 0;
    const array = guest.capability({ parameter: "Array F32", result: "Array F32", call: value => {
      equal([...value].join(","), "1.5,2.5,3.5");
      array_calls++;
      value[0] = 99;
      return Float32Array.of(4.5, 5.5);
    } });
    equal([...(guest.call("host_array", array) as Float32Array)].join(","), "4.5,5.5");
    equal([...(guest.call("host_array", array) as Float32Array)].join(","), "4.5,5.5");
    equal(array_calls, 2);
    for (const count of [0, 1, 32, 16384, 32769, 1]) {
      const input = Uint32Array.from({ length: count }, (_, i) => (i * 1234567) >>> 0);
      const result = guest.call("identity", input) as Uint32Array;
      equal(result.length, input.length);
      for (let i = 0; i < count; i++) equal(result[i], input[i]);
      const literal = guest.call("literal", null) as Uint32Array;
      equal([...literal].join(","), "1,2,3");
      if (result.length) result[0] = 99;
      equal([...guest.call("literal", null) as Uint32Array].join(","), "1,2,3");
    }
    const raw = await WebAssembly.instantiate(bytes, { "blot:host/1": {
      call_u32_u32: (capability: (value: number) => number, value: number) => capability(value),
      call_array_f32_array_f32: (_capability: number, value: number) => value,
    } });
    const retained = raw.instance.exports.host_retained as CallableFunction;
    const count = raw.instance.exports.host_retained_count as CallableFunction;
    const capacity = raw.instance.exports.host_retained_capacity as CallableFunction;
    const cleared = raw.instance.exports.host_handle_cleared as CallableFunction;
    equal(retained((value: number) => {
      equal(count(0), 2);
      equal(retained((inner: number) => inner * 2), 42);
      equal(count(0), 2);
      equal(cleared(0), 0);
      return value * 2;
    }), 42);
    equal(count(0), 0);
    equal(capacity(0), 4);
    for (let handle = 0; handle < 4; handle++) equal(cleared(handle), 1);
    const allocate = raw.instance.exports["blot:allocate"] as CallableFunction;
    let trapped = false;
    try { allocate(0xffffffff); } catch (error) { trapped = error instanceof WebAssembly.RuntimeError; }
    equal(trapped, true);
  } finally { guest.dispose(); }
});
