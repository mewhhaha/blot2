const root = new URL("../", import.meta.url).pathname;
function assert(ok: unknown, message = "static guest assertion failed"): asserts ok { if (!ok) throw new Error(message); }
async function compile(source: string, name: string) {
  const output = `build/static-${name}.wasm`;
  const result = await new Deno.Command(root + "build/blot", { cwd: root, args: ["build", source, "-o", output], stdout: "piped", stderr: "piped" }).output();
  assert(result.success, new TextDecoder().decode(result.stderr));
  const module = await WebAssembly.compile(await Deno.readFile(root + output));
  return { module, instance: await WebAssembly.instantiate(module) };
}
Deno.test("K1-08 required static arrays use readonly relocated storage", async () => {
  const { instance } = await compile("tests/runtime_static_array.blot", "array");
  const run = instance.exports.run as () => number;
  for (let i = 0; i < 100; i++) assert(run() === 52);
  assert(!("memory" in instance.exports));
});
Deno.test("K1-08 required static products preserve complete scalar values", async () => {
  const { instance } = await compile("examples/static_pattern.blot", "pattern");
  assert((instance.exports.run as () => number)() === 42);
});
Deno.test("K1-08 required static finite calls and loops produce a published value", async () => {
  const { instance } = await compile("examples/static_loop.blot", "loop");
  assert((instance.exports.run as () => number)() === 42);
});
Deno.test("K1-08 static callable relocation uses packed runtime table indices", async () => {
  const { instance, module } = await compile("tests/runtime_static_callback.blot", "callback");
  const run = instance.exports.run as (n: number) => number;
  for (const n of [0, 1, 0x7fffffff, 0xffffffff]) assert(run(n) >>> 0 === n);
  const sections = WebAssembly.Module.customSections(module, "blot.k1.certificate"); assert(sections.length === 1);
  const bytes = new DataView(sections[0]); let at = 8 + 96 + 72 + 8;
  const word = () => { const n = bytes.getUint32(at, true); at += 4; return n; };
  const count = word(); let sourceCount = 0;
  for (let i = 0; i < count; i++) {
    word(); word(); const role = word(); word(); at += 12 + 32;
    if (role === 2) sourceCount++;
    const direct = word(); at += direct * 4; const indirect = word(); at += indirect * 8;
  }
  assert(sourceCount === 2, "static staging functions are absent from runtime code");
});
Deno.test("K1-08 static captured closure publishes an immutable environment", async () => {
  const { instance } = await compile("examples/static_closure.blot", "captured");
  const run = instance.exports.run as (n: number) => number;
  for (const n of [0, 40, 0xfffffffe, 0xffffffff]) assert(run(n) >>> 0 === (n + 2) >>> 0);
});
Deno.test("K1-08 static generic callable relocates its canonical ABI adapter", async () => {
  const { instance } = await compile("tests/runtime_static_generic.blot", "generic");
  const run = instance.exports.run as (n: number) => number;
  for (const n of [0, 1, 0xffffffff]) assert(run(n) >>> 0 === n);
});
Deno.test("K1-08 nested static closure environments preserve captured callable pointers", async () => {
  const { instance } = await compile("tests/runtime_static_nested.blot", "nested");
  const run = instance.exports.run as (n: number) => number;
  for (const n of [0, 40, 0xfffffffe, 0xffffffff]) assert(run(n) >>> 0 === (n + 2) >>> 0);
});
Deno.test("K1-08 static generic predicate retains completed captured callable resources", async () => {
  const { instance } = await compile("tests/runtime_static_predicate.blot", "predicate");
  const run = instance.exports.run as (n: number) => number;
  for (const n of [0, 1, 2]) assert(run(n) === 0);
  for (const n of [3, 40, 0xffffffff]) assert(run(n) === 1);
});
