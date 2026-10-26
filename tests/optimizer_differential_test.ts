function assert(
  ok: unknown,
  message = "optimizer differential law failed",
): asserts ok {
  if (!ok) throw new Error(message);
}
function counter(ex: WebAssembly.Exports, id: number) {
  const read = ex["blot.telemetry"] as (word: number) => number;
  return BigInt(read(id * 2) >>> 0) | BigInt(read(id * 2 + 1) >>> 0) << 32n;
}
Deno.test("OPT-01 every enabled R01-R12 fires and preserves executed values and capability traces", async () => {
  for (let rule = 1; rule <= 12; rule++) {
    const stats = JSON.parse(
      await Deno.readTextFile(`/tmp/blot-k1-opt-${rule}-stats.json`),
    );
    assert(
      stats.rule === rule && stats.applications > 0,
      `R${rule} did not fire`,
    );
    const baseline = await WebAssembly.compile(
      await Deno.readFile(`/tmp/blot-k1-opt-${rule}-baseline.wasm`),
    );
    const candidate = await WebAssembly.compile(
      await Deno.readFile(`/tmp/blot-k1-opt-${rule}-candidate.wasm`),
    );
    for (const input of [0, 1, 4, 64, 0xffffffff]) {
      const a = await WebAssembly.instantiate(baseline),
        b = await WebAssembly.instantiate(candidate);
      const left = (a.exports.run as (x: number) => number)(input) >>> 0;
      const right = (b.exports.run as (x: number) => number)(input) >>> 0;
      const expected = rule === 6
        ? 14
        : rule === 7
        ? 16
        : rule === 8
        ? 3
        : rule === 10
        ? 1
        : rule === 11
        ? (input + 1) >>> 0
        : rule === 9
        ? input === 0xffffffff ? 77 : input < 4 ? 99 : input
        : input;
      assert(
        left === expected && right === expected,
        `R${rule}/${input}: ${left}/${right}, expected ${expected}`,
      );
      // Diagnostic copy/stack/call counters may change. These seven counters
      // describe observable reservation, failure, reset, release and live backing.
      for (let id = 0; id <= 6; id++) {
        assert(
          counter(a.exports, id) === counter(b.exports, id),
          `R${rule}/${input} changed capability counter ${id}`,
        );
      }
      assert(counter(a.exports, 5) === 0n, `R${rule} left live backing`);
      if (rule === 9) {
        assert(
          counter(a.exports, 0) === 1n,
          "reservation removed or duplicated",
        );
        assert(
          counter(a.exports, 4) === (input === 0xffffffff ? 0n : 1n),
          "failure or normal cleanup changed",
        );
      }
    }
  }
});

Deno.test("OPT-01 fired R07 F32 rules preserve exact signed zero infinity rounding and NaN copy bits", async () => {
  const expected = [
    0x80000000,
    0,
    0x7f800000,
    0x7fc00000,
    0x4b800000,
    0xffa12345,
    0x7fa12345,
    0x80000000,
  ];
  for (let sample = 1; sample <= expected.length; sample++) {
    const stats = JSON.parse(
      await Deno.readTextFile(`/tmp/blot-k1-opt-7-f32-${sample}-stats.json`),
    );
    assert(stats.rule === 7 && stats.applications > 0);
    for (const tier of ["baseline", "candidate"]) {
      const { instance } = await WebAssembly.instantiate(
        await Deno.readFile(`/tmp/blot-k1-opt-7-f32-${sample}-${tier}.wasm`),
      );
      const bits = (instance.exports.run as (x: number) => number)(0) >>> 0;
      if (sample === 4) {
        assert(
          (bits & 0x7fc00000) === 0x7fc00000,
          `${tier} arithmetic NaN is outside the quiet NaN set`,
        );
      } else {assert(
          bits === expected[sample - 1],
          `${tier}/F32 ${sample}: ${bits.toString(16)}`,
        );}
    }
  }
});
