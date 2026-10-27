const root = new URL("../", import.meta.url).pathname;
function assert(ok: unknown, message = "closure assertion failed"): asserts ok { if (!ok) throw new Error(message); }
async function compile(source: string, name: string) {
  const output = `build/runtime-${name}.wasm`;
  const result = await new Deno.Command(root + "build/blot", {
    cwd: root, args: ["build", source, "-o", output], stdout: "piped", stderr: "piped",
  }).output();
  assert(result.success, new TextDecoder().decode(result.stderr));
  const module = await WebAssembly.compile(await Deno.readFile(root + output));
  return { module, instance: await WebAssembly.instantiate(module) };
}
Deno.test("K1-06 local closure captures and restores its frame", async () => {
  const { instance } = await compile("examples/closure.blot", "closure");
  const invoke = instance.exports.invoke as (n: number) => number;
  for (let i = 0; i < 1000; i++) assert(invoke(i / 8) === Math.fround(Math.fround(i / 8) + 3));
  assert(!("memory" in instance.exports), "scalar closure export must not expose memory");
});
Deno.test("K1-08 generic closure captures its dictionary with one shared body", async () => {
  const { instance, module } = await compile("tests/runtime_generic_closure.blot", "generic-closure");
  const run = instance.exports.run as (n: number) => number;
  const runFloat = instance.exports.run_float as (n: number) => number;
  for (const n of [0, 1, 0x7fffffff, 0x80000000, 0xffffffff]) assert(run(n) >>> 0 === n);
  for (const n of [0, -0, 1.5, -1.5, Infinity, -Infinity]) assert(Object.is(runFloat(n), n));
  assert(Number.isNaN(runFloat(NaN)));
  const certificates = WebAssembly.Module.customSections(module, "blot.k1.certificate"); assert(certificates.length === 1);
  const c = new DataView(certificates[0]); let at = 8 + 96 + 72 + 8;
  const word = () => { const n = c.getUint32(at, true); at += 4; return n; };
  const count = word(); let sourceFunctions = 0;
  for (let i = 0; i < count; i++) {
    word(); word(); const role = word(); word(); at += 12 + 32;
    if (role === 2) sourceFunctions++;
    const direct = word(); at += direct * 4;
    const indirect = word(); at += indirect * 8;
  }
  assert(sourceFunctions === 4, "hold, captured lambda and two entrypoints; no per-type body clones");
});
Deno.test("K1-08 instantiated callable uses an ABI adapter and one shared generic body", async () => {
  const { instance } = await compile("examples/generic_callback.blot", "generic-callback");
  const run = instance.exports.run as (n: number) => number;
  for (const n of [0, 1, 0x7fffffff, 0x80000000, 0xffffffff]) assert(run(n) >>> 0 === n);
});
Deno.test("K1-06 callback contract weakening preserves callable execution", async () => {
  const { instance } = await compile("tests/runtime_callback.blot", "callback");
  const run = instance.exports.run as (n: number) => number;
  for (const n of [0, 1, 0x7fffffff, 0x80000000, 0xffffffff]) assert(run(n) >>> 0 === n);
});
Deno.test("K1-06 nested closure forwards a grandparent capture", async () => {
  const { instance } = await compile("examples/nested_closure.blot", "nested-closure");
  const invoke = instance.exports.invoke as (n: number) => number;
  for (let i = 0; i < 100; i++) assert(invoke(i / 4) === Math.fround(Math.fround(i / 4) + 2));
});
Deno.test("K1-08 abstract callable captures its actual Type dictionary locally", async () => {
  const { instance } = await compile("examples/abstract_callback.blot", "abstract-callback");
  const run = instance.exports.run as (n: number) => number;
  for (let i = 0; i < 1000; i++) assert(run(i) === i);
  assert(run(0xffffffff) >>> 0 === 0xffffffff);
});
Deno.test("K1-08 compound Type dictionaries preserve actual tuple layouts", async () => {
  const { instance } = await compile("tests/runtime_compound_dictionary.blot", "compound-dictionary");
  const run = instance.exports.run as (n: number) => number;
  const floating = instance.exports.run_float as (n: number) => number;
  for (const n of [0, 1, 0x7fffffff, 0xffffffff]) assert(run(n) >>> 0 === n);
  for (const n of [0, -0, 1.25, -1.25, Infinity]) assert(Object.is(floating(n), n));
  assert(Number.isNaN(floating(NaN)));
});
Deno.test("K1-08 abstract callable captures the hidden Nat witness exactly", async () => {
  const { instance } = await compile("tests/runtime_nat_callback.blot", "nat-callback");
  const run = instance.exports.run as () => number;
  const zero = instance.exports.zero as () => number;
  for (let i = 0; i < 1000; i++) { assert(run() >>> 0 === 0xffffffff); assert(zero() === 0); }
});
Deno.test("K1-08 lexical forall uses one body with combined witness and capture environments", async () => {
  for (const name of ["local_generic", "local_generic_capture", "local_generic_ambient"]) {
    const { instance } = await compile(`examples/${name}.blot`, name);
    const run = instance.exports.run as (n: number) => number;
    for (const n of [0, 1, 40, 0x7fffffff, 0xffffffff]) assert(run(n) >>> 0 === n, name);
  }
});
Deno.test("K1-08 nested generic callable forwards an opened Nat witness", async () => {
  const { instance } = await compile("examples/local_generic_nat.blot", "local-generic-nat");
  const run = instance.exports.run as () => number;
  for (let i = 0; i < 1000; i++) assert(run() === 42);
});
Deno.test("K1-06 Many-to-Once weakening executes one affine callback invocation", async () => {
  const { instance } = await compile("tests/runtime_once.blot", "once");
  const run = instance.exports.run as (n: number) => number;
  for (const n of [0, 1, 40, 0x7fffffff, 0xffffffff]) assert(run(n) >>> 0 === n);
});
