function assert(
  ok: unknown,
  message = "release inline differential law failed",
): asserts ok {
  if (!ok) throw new Error(message);
}
function counter(ex: WebAssembly.Exports, id: number): bigint {
  const read = ex["blot.telemetry"] as (word: number) => number;
  return BigInt(read(id * 2) >>> 0) | BigInt(read(id * 2 + 1) >>> 0) << 32n;
}
async function pair(name: string) {
  const stats = JSON.parse(
    await Deno.readTextFile(`/tmp/blot-k1-inline-${name}-stats.json`),
  );
  assert(
    stats.sites > 0 && stats.growth <= 64 && stats.max_callee <= 32 &&
      stats.max_depth <= 2,
  );
  const modules = await Promise.all(
    ["baseline", "candidate"].map(async (tier) =>
      WebAssembly.compile(
        await Deno.readFile(`/tmp/blot-k1-inline-${name}-${tier}.wasm`),
      )
    ),
  );
  return Promise.all(
    modules.map(async (module) =>
      (await WebAssembly.instantiate(module)).exports
    ),
  );
}
Deno.test("INLINE release scalar transport preserves U32 and separately rounded F32 operations", async () => {
  const guests = await pair("scalar");
  for (const n of [0, 1, 40, 0x7fffffff, 0x80000000, 0xffffffff]) {
    for (const ex of guests) {
      assert(
        (ex.run as (n: number) => number)(n) >>> 0 === Math.imul(n, 4) >>> 0,
      );
      assert(
        (ex.run_early as (n: number) => number)(n) >>> 0 ===
          Math.imul(n, 2) >>> 0,
      );
    }
  }
  for (const n of [0, -0, 1.25, -1.25, Infinity, -Infinity, NaN]) {
    for (const ex of guests) {
      assert(
        Object.is((ex.run_negate as (n: number) => number)(n), -Math.fround(n)),
        "inlined negation changed signed zero or F32 bits",
      );
    }
  }
  const scale = Math.fround(1.0000001192092896), add = Math.fround(0.137);
  for (
    const n of [
      0,
      -0,
      1,
      -1,
      0.1,
      -0.1,
      16777216,
      -16777216,
      Infinity,
      -Infinity,
      NaN,
    ]
  ) {
    const expected = Math.fround(Math.fround(Math.fround(n) * scale) + add);
    for (const ex of guests) {
      const actual = (ex.run_float as (n: number) => number)(n);
      assert(
        Object.is(actual, expected),
        `separate F32 multiply/add changed for ${n}`,
      );
    }
  }
  for (const ex of guests) {
    for (let id = 0; id <= 6; id++) assert(counter(ex, id) === 0n);
  }
});
Deno.test("INLINE release argument transport evaluates reservation and release exactly once", async () => {
  const guests = await pair("effect");
  for (let repeat = 0; repeat < 32; repeat++) {
    for (const ex of guests) assert((ex.run as () => number)() === 42);
    for (let id = 0; id <= 6; id++) {
      assert(
        counter(guests[0], id) === counter(guests[1], id),
        `capability counter ${id} differs`,
      );
    }
    for (const ex of guests) {
      assert(
        counter(ex, 0) === BigInt(repeat + 1),
        "argument reservation repeated or erased",
      );
      assert(
        counter(ex, 4) === BigInt(repeat + 1) && counter(ex, 5) === 0n,
        "argument release repeated or erased",
      );
    }
  }
});
