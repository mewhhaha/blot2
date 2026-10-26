const root = new URL("../", import.meta.url).pathname;
function assert(ok: unknown, message = "lifecycle assertion failed"): asserts ok { if (!ok) throw new Error(message); }
async function compile(source: string, name: string) {
  const output = `build/runtime-${name}.wasm`;
  const result = await new Deno.Command(root + "build/blot", {
    cwd: root, args: ["build", source, "-o", output], stdout: "piped", stderr: "piped",
  }).output();
  assert(result.success, new TextDecoder().decode(result.stderr));
  const { instance } = await WebAssembly.instantiate(await Deno.readFile(root + output));
  assert(!("memory" in instance.exports), "scalar exports must not expose private memory");
  return instance.exports as Record<string, (...args: number[]) => number>;
}
Deno.test("K1-03/07 region and Owned release all storage across repeated source calls", async () => {
  const guest = await compile("tests/runtime_owned.blot", "owned");
  for (let i = 0; i < 1000; i++) { assert(guest.region_run() === 1); assert(guest.owned_run() === 1); }
});
Deno.test("K1-07 Owned stores a placed closure and opens it under a fresh borrow", async () => {
  const guest = await compile("tests/runtime_owned_callback.blot", "owned-callback");
  for (let i = 0; i < 1000; i++) assert(guest.invoke(i / 8) === Math.fround(Math.fround(i / 8) + 2));
});
Deno.test("K1-03/04 complete nested reserve-placement-freeze singleton executes", async () => {
  const guest = await compile("tests/runtime_singleton.blot", "singleton");
  for (let i = 0; i < 1000; i++) assert(guest.run() === 41);
});
Deno.test("K1-07/08 generic Owned root uses actual dictionary size and canonical schema", async () => {
  const guest = await compile("tests/runtime_generic_owned.blot", "generic-owned");
  for (const n of [0, 1, 0x7fffffff, 0x80000000, 0xffffffff]) assert(guest.run(n) >>> 0 === n);
  for (const n of [0, -0, 1.25, -1.25, Infinity, -Infinity]) assert(Object.is(guest.run_float(n), n));
  assert(Number.isNaN(guest.run_float(NaN)));
});
Deno.test("K1-07/08 generic seal agrees with concrete open across the ABI", async () => {
  const guest = await compile("tests/runtime_generic_owned_cross.blot", "generic-owned-cross");
  for (let i = 0; i < 1000; i++) assert(guest.run(i) === i);
  assert(guest.run(0xffffffff) >>> 0 === 0xffffffff);
});
Deno.test("K1-07/08 compound Owned payload agrees across generic and concrete schemas", async () => {
  const guest = await compile("tests/runtime_compound_owned.blot", "compound-owned");
  for (let i = 0; i < 1000; i++) assert(guest.run(i) === i);
  assert(guest.run(0xffffffff) >>> 0 === 0xffffffff);
});
Deno.test("K1-07/08 Owned generic callable crosses the concrete canonical ABI", async () => {
  const guest = await compile("tests/runtime_generic_owned_fn.blot", "generic-owned-fn");
  for (let i = 0; i < 1000; i++) assert(guest.run(i) === i);
  assert(guest.run(0xffffffff) >>> 0 === 0xffffffff);
});
Deno.test("K1-11 generic callable rejects an envelope too small for its ABI adapter", async () => {
  const source = await Deno.readTextFile(root + "tests/runtime_generic_owned_fn.blot");
  const input = "build/runtime-invalid-adapter-depth.blot";
  await Deno.writeTextFile(root + input, source.replace("resources {depth:2,frame:1024}", "resources {depth:1,frame:1024}"));
  const result = await new Deno.Command(root + "build/blot", {
    cwd: root, args: ["build", input, "-o", "build/runtime-invalid-adapter-depth.wasm"], stdout: "piped", stderr: "piped",
  }).output();
  assert(!result.success, "a one-level envelope cannot include the adapter and shared body");
  assert(new TextDecoder().decode(result.stderr).includes("4013"), "must diagnose the resource envelope");
});
Deno.test("K1-04 builder read set truncate freeze and fresh-domain slice execute", async () => {
  const guest = await compile("tests/runtime_builder.blot", "builder");
  for (let i = 0; i < 1000; i++) assert(guest.run() === 119);
});
Deno.test("K1-04 try_append returns the full builder and unused element on failure", async () => {
  const guest = await compile("tests/runtime_try_append.blot", "try-append");
  for (let i = 0; i < 1000; i++) assert(guest.run() === 99);
});
Deno.test("K1-04 disjoint destination split and checked view reads execute", async () => {
  const guest = await compile("tests/runtime_split.blot", "split");
  for (let i = 0; i < 1000; i++) assert(guest.run() === 40);
});
Deno.test("K1-03 region reset establishes a fresh epoch and restores capacity", async () => {
  const guest = await compile("tests/runtime_reset.blot", "reset");
  for (let i = 0; i < 1000; i++) assert(guest.run() === 42);
});
Deno.test("K1-05/07 graph packages preserve stored Index authority and clean early failure", async () => {
  const guest = await compile("examples/graph_demo.blot", "graph");
  for (let i = 0; i < 1000; i++) {
    assert(guest.run() === 84);
    assert(guest.late_failure() === 7);
    assert(guest.empty() === 0);
    assert(guest.zero_nodes_invalid() === 7);
  }
});
Deno.test("K1-07 Owned payload rejects an external unbound Index domain", async () => {
  const result = await new Deno.Command(root + "build/blot", {
    cwd: root, args: ["build", "tests/runtime_external_index_owned.blot", "-o", "build/runtime-external-index-owned.wasm"], stdout: "piped", stderr: "piped",
  }).output();
  assert(!result.success, "an external Index witness must be closed by the Owned package schema");
  assert(new TextDecoder().decode(result.stderr).includes("2020"), "must diagnose the unclosed Owned payload");
});
Deno.test("K1-08 generic affine identity transfers Owned and aggregate errors", async () => {
  const guest = await compile("tests/runtime_affine_generic.blot", "affine-generic");
  for (let i = 0; i < 1000; i++) { assert(guest.run() === 1); assert(guest.unit() === 1); }
  for (const n of [0, 1, 40, 0x7fffffff, 0xffffffff]) assert(guest.error(n) >>> 0 === n);
});
Deno.test("K1-04 truncate then re-extend publishes only the new initialized element", async () => {
  const guest = await compile("tests/runtime_reextend.blot", "reextend");
  for (let i = 0; i < 1000; i++) assert(guest.run() === 97);
});

Deno.test("K1-11/12 scalar boundary checks numeric requirements and Bool before source execution", async () => {
  const valid: [string, number, number][] = [
    ["checked_add", 0, 1], ["checked_add", 0xfffffffe, 0xffffffff],
    ["checked_sub", 1, 0], ["checked_sub", 0xffffffff, 0xfffffffe],
    ["checked_mul", 0, 0], ["checked_mul", 0x7fffffff, 0xfffffffe],
    ["multiply_zero", 0xffffffff, 0], ["equal", 1, 1],
    ["less", 0, 1], ["less", 31, 0x80000000], ["at_most", 0, 0], ["at_most", 1, 1],
    ["complement", 1, 1], ["boolean", 0, 0], ["boolean", 1, 1],
  ];
  const invalid: [string, number][] = [
    ["checked_add", 0xffffffff], ["checked_sub", 0], ["checked_mul", 0x80000000],
    ["checked_mul", 0xffffffff], ["equal", 0], ["equal", 2],
    ["less", 32], ["less", 0xffffffff], ["at_most", 2],
    ["complement", 0], ["complement", 2], ["boolean", 2], ["boolean", 0xffffffff],
  ];
  for (const mode of ["off", "fast", "release"]) {
    const output = `build/runtime-scalar-contract-${mode}.wasm`;
    const result = await new Deno.Command(root + "build/blot", {
      cwd: root, args: ["build", "tests/runtime_scalar_contract.blot", "-o", output, `--opt=${mode}`, "--telemetry"],
      stdout: "piped", stderr: "piped",
    }).output();
    assert(result.success, new TextDecoder().decode(result.stderr));
    const module = await WebAssembly.compile(await Deno.readFile(root + output));
    const good = (await WebAssembly.instantiate(module)).exports as Record<string, (n: number) => number>;
    assert(!("memory" in good));
    for (const [name, input, expected] of valid) assert(good[name](input) >>> 0 === expected, `${mode} ${name}(${input})`);
    assert(good["blot.telemetry"](22) === valid.length);
    for (const [name, input] of invalid) {
      // Every trap gets a fresh instance. Only diagnostic counters are read
      // afterward; source execution is never resumed on a trapped instance.
      const bad = (await WebAssembly.instantiate(module)).exports as Record<string, (n: number) => number>;
      let trapped = false;
      try { bad[name](input); } catch (error) { trapped = error instanceof WebAssembly.RuntimeError; }
      assert(trapped, `${mode} must reject ${name}(${input}) at the public boundary`);
      assert(bad["blot.telemetry"](22) === 0, "invalid host input must not enter source code");
      assert(bad["blot.telemetry"](0) === 0, "invalid host input must not reserve backing");
    }
  }
});
