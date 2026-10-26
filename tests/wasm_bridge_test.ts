Deno.test("M12 copy bridge status lifecycle and isolation", async () => {
  const binary = await Deno.readFile("/tmp/blot-k1-bridge.wasm");
  const map = JSON.parse(await Deno.readTextFile("/tmp/blot-k1-bridge-map.json"));
  function assert(value: unknown, message = "bridge assertion failed"): asserts value {
    if (!value) throw new Error(message);
  }
  const { instance } = await WebAssembly.instantiate(binary);
  const memory = instance.exports.memory as WebAssembly.Memory;
  const call = instance.exports.blot_call as (id: number, input: number, output: number) => number;
  const words = new Uint32Array(memory.buffer), bytes = new Uint8Array(memory.buffer);
  const input = map.ingress / 4, output = map.egress / 4;
  function setup(id = 1, values = [10, 20, 30]) {
    words.fill(0, input, input + 8);
    words[input] = 0x4b310001; words[input + 1] = id;
    words[input + 3] = 8 + values.length * 4;
    words[input + 8] = values.length; words[input + 9] = 8;
    words.set(values, input + 10);
    return 40 + values.length * 4;
  }
  function clean() {
    assert(words[map.control / 4] === 0, "guard is released");
    assert(bytes.slice(map.bitmap, map.bitmap + map.bitmapBytes).every(v => v === 0), "private region is released");
  }
  assert(call(1, setup(), 20) === 0);
  assert(words[output + 2] === 0 && words[output + 3] === 20 && words[output + 4] === 20 && words[output + 5] === 3);
  assert(words[output + 8] === 3 && words[output + 9] === 8);
  assert(words.slice(output + 10, output + 13).join() === "10,20,30");
  clean();
  const copied = words.slice(output + 10, output + 13);
  assert(call(1, setup(1, [77]), 12) === 0);
  assert(copied.join() === "10,20,30", "host copy survives subsequent invocation");
  clean();
  assert(call(1, setup(), 19) === 2);
  assert(words[output + 3] === 0 && words[output + 4] === 20, "too small exposes only exact requirement");
  clean();
  assert(call(2, setup(2), 20) === 6);
  assert(words[output + 3] === 0 && words[output + 4] === 0 && words[output + 6] === 0);
  clean();
  assert(call(1, setup(1, []), 8) === 0 && words[output + 3] === 8 && words[output + 8] === 0);
  clean();

  for (const corrupt of ["abi", "count", "offset", "unaligned", "payload", "reserved", "item-count", "too-short", "output-window"]) {
    let size = setup(); let capacity = 20;
    if (corrupt === "abi") words[input] ^= 1;
    if (corrupt === "count") words[input + 8] = 0xffffffff;
    if (corrupt === "offset") words[input + 9] = 0;
    if (corrupt === "unaligned") words[input + 9] = 9;
    if (corrupt === "payload") words[input + 3]++;
    if (corrupt === "reserved") words[input + 7] = 1;
    if (corrupt === "item-count") words[input + 5] = 1;
    if (corrupt === "too-short") size = 31;
    if (corrupt === "output-window") capacity = 65505;
    assert(call(1, size, capacity) === 1, `${corrupt} must fail before source execution`);
    assert(words[output + 3] === 0 && words[output + 4] === 0);
    clean();
  }
  setup(); words[map.control / 4] = 1;
  const busySnapshot = bytes.slice();
  assert(call(1, 52, 20) === 4);
  assert(bytes.every((v, i) => v === busySnapshot[i]), "Busy must not write any memory");
  words[map.control / 4] = 0;
  setup(); words[map.control / 4 + 1] = map.frameBytes - 100;
  assert(call(1, 52, 20) === 5);
  assert(words[map.control / 4 + 1] === map.frameBytes - 100, "frame preflight restores incoming frontier");
  words[map.control / 4 + 1] = 0;
  clean();
  setup(); bytes.fill(255, map.bitmap, map.bitmap + map.bitmapBytes);
  assert(call(1, 52, 20) === 3 && words[output + 6] === 2);
  assert(words[output + 3] === 0 && words[output + 4] === 0);
  assert(bytes.slice(map.bitmap, map.bitmap + map.bitmapBytes).every(v => v === 255), "failed reserve leaves bitmap unchanged");
  bytes.fill(0, map.bitmap, map.bitmap + map.bitmapBytes);
  clean();
  setup(); assert(call(999, 52, 20) === 1 && words[output + 1] === 999);
  clean();
});

Deno.test("M12 numeric entry predicates and compact Unit arrays", async () => {
  const map = JSON.parse(await Deno.readTextFile("/tmp/blot-k1-bridge-map.json"));
  for (const [fixture, count, expected, payload] of [
    ["guard", 2, 0, 16], ["guard", 3, 1, 20], ["repeated", 3, 1, 20], ["repeated", 4, 0, 24], ["unit", 0xffffffff, 0, 8],
  ] as const) {
    const { instance } = await WebAssembly.instantiate(await Deno.readFile(`/tmp/blot-k1-bridge-${fixture}.wasm`));
    const memory = instance.exports.memory as WebAssembly.Memory;
    const words = new Uint32Array(memory.buffer); const input = map.ingress / 4, output = map.egress / 4;
    words[input] = 0x4b310001; words[input + 1] = 1; words[input + 3] = payload;
    words[input + 8] = count; words[input + 9] = 8;
    if (fixture !== "unit") words.set([1, 2, 3, 4], input + 10);
    const status = (instance.exports.blot_call as CallableFunction)(1, 32 + payload, 32);
    if (status !== expected) throw new Error(`${fixture}/${count}: expected ${expected}, got ${status}`);
    if (fixture === "unit" && (words[output + 8] !== count || words[output + 3] !== 8)) throw new Error("Unit arrays must keep logical count without payload allocation");
    if (words[map.control / 4] !== 0 || words[map.control / 4 + 1] !== 0) throw new Error("entry predicate path leaked frame or invocation guard");
  }
});

Deno.test("M12 Plain wire validation rejects Bool tags and inactive sum padding", async () => {
  const root = new URL("../", import.meta.url).pathname;
  const built = await new Deno.Command(root + "build/blot", {
    cwd: root, args: ["build", "tests/runtime_wire.blot", "-o", "build/runtime-wire.wasm", "--bridge-config=tests/runtime_wire.json", "--telemetry"], stdout: "piped", stderr: "piped",
  }).output();
  function assert(ok: unknown, message = "wire validity assertion failed"): asserts ok { if (!ok) throw new Error(message); }
  assert(built.success, new TextDecoder().decode(built.stderr));
  const module = await WebAssembly.compile(await Deno.readFile(root + "build/runtime-wire.wasm"));
  const manifest = JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(module, "blot.k1.manifest")[0]));
  const instance = await WebAssembly.instantiate(module), ex = instance.exports;
  const memory = ex.memory as WebAssembly.Memory, data = new DataView(memory.buffer);
  const call = ex.blot_call as (id: number, bytes: number, capacity: number) => number;
  const trace = ex["blot.telemetry"] as (word: number) => number;
  const entry = manifest.exports[0], input = manifest.memory.ingress, output = manifest.memory.egress;
  const wire = entry.fields[0].type, flag = wire.fields.find((f: { name: string }) => f.name === "flag"), choice = wire.fields.find((f: { name: string }) => f.name === "choice");
  const small = choice.type.fields.findIndex((f: { name: string }) => f.name === "Small");
  assert(small >= 0 && wire.size === 16);
  const row = input + 32 + entry.fixed_bytes;
  function setup() {
    for (let i = 0; i < 32 + entry.fixed_bytes + wire.size; i += 4) data.setUint32(input + i, 0, true);
    data.setUint32(input, 0x4b310001, true); data.setUint32(input + 4, entry.id, true);
    data.setUint32(input + 12, entry.fixed_bytes + wire.size, true);
    data.setUint32(input + 32, 1, true); data.setUint32(input + 36, entry.fixed_bytes, true);
    data.setUint32(row + flag.offset, 1, true); data.setUint32(row + choice.offset, small, true);
    data.setUint32(row + choice.offset + 4, 42, true);
  }
  setup(); assert(call(entry.id, 32 + entry.fixed_bytes + wire.size, 8 + wire.size) === 0);
  assert(data.getUint32(output + 40 + choice.offset + 4, true) === 42);
  const calls = trace(22), reservations = trace(0);
  for (const bad of ["bool", "tag", "padding", "overflow"]) {
    setup();
    if (bad === "bool") data.setUint32(row + flag.offset, 2, true);
    if (bad === "tag") data.setUint32(row + choice.offset, choice.type.fields.length, true);
    if (bad === "padding") data.setUint32(row + choice.offset + 8, 1, true);
    if (bad === "overflow") data.setUint32(input + 36, 0xfffffffc, true);
    assert(call(entry.id, 32 + entry.fixed_bytes + wire.size, 8 + wire.size) === 1, bad);
    assert(trace(22) === calls && trace(0) === reservations, "invalid wire must fail before source or reservation");
    assert(data.getUint32(output + 12, true) === 0 && data.getUint32(output + 16, true) === 0);
  }
});
