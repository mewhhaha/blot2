import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";

const source = `
export const sine_half = F32.sin 0.5
export const cosine_half = F32.cos 0.5
export const tangent_half = F32.tan 0.5
export const wrapped = F32.wrap 6.283185307 (-0.5)
export const halfway = F32.lerp_angle 6.183185307 0.1 0.5
export fn sine (angle: F32) => F32.sin angle
export fn cosine (angle: F32) => F32.cos angle
export fn tangent (angle: F32) => F32.tan angle
export fn wrap (angle: F32) => F32.wrap 6.283185307 angle
export fn halfway_angle (angle: F32) => F32.lerp_angle 6.183185307 angle 0.5
`;

function near(actual: number, expected: number, tolerance = 1e-6) {
  ok(
    Math.abs(actual - expected) <= tolerance,
    `${actual} differs from ${expected} by ${Math.abs(actual - expected)}`,
  );
}

function call(exports: WebAssembly.Exports, name: string, value: number) {
  const fn = exports[name];
  ok(typeof fn === "function", `missing scalar export ${name}`);
  return fn(value) as number;
}

Deno.test("source F32 trigonometry agrees in native/JS constants and Wasm", async () => {
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const expected = reference.compile(source);
    const actual = await native.compile(source);
    equal(actual.bytes, expected.bytes);
    equal(actual.analysis.constants, expected.analysis.constants);
    const { instance } = await WebAssembly.instantiate(actual.bytes);
    for (
      const [name, runtime] of [
        ["sine_half", "sine"],
        ["cosine_half", "cosine"],
        ["tangent_half", "tangent"],
      ]
    ) {
      const constant = instance.exports[name];
      ok(constant instanceof WebAssembly.Global);
      equal(constant.value, call(instance.exports, runtime, 0.5));
    }
    near(call(instance.exports, "sine", 0.5), Math.sin(0.5));
    near(call(instance.exports, "cosine", 0.5), Math.cos(0.5));
    near(call(instance.exports, "tangent", 0.5), Math.tan(0.5));
    near(call(instance.exports, "wrap", -0.5), 2 * Math.PI - 0.5);
    near(call(instance.exports, "halfway_angle", 0.1), 2 * Math.PI);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("source F32 trig has bounded error through quadrants and range reduction", async () => {
  const compiler = await createSourceCompiler();
  try {
    const { bytes } = compiler.compile(source);
    const { instance } = await WebAssembly.instantiate(bytes);
    const angles = [
      -8192,
      -1000,
      -2 * Math.PI,
      -Math.PI,
      -Math.PI / 2,
      -0,
      0,
      Math.PI / 2,
      Math.PI,
      2 * Math.PI,
      1000,
      8192,
    ];
    for (let sample = 0; sample <= 4096; sample++) {
      angles.push(-8192 + sample * 4);
      angles.push(-Math.PI + sample * Math.PI / 2048);
    }
    for (const angle of angles) {
      const input = Math.fround(angle);
      const sine = call(instance.exports, "sine", input);
      const cosine = call(instance.exports, "cosine", input);
      near(sine, Math.sin(input));
      near(cosine, Math.cos(input));
      near(sine * sine + cosine * cosine, 1, 2e-6);
      if (Math.abs(Math.cos(input)) >= 0.01) {
        const tangent = Math.tan(input);
        near(
          call(instance.exports, "tangent", input),
          tangent,
          1e-4 * Math.max(1, Math.abs(tangent)),
        );
      }
    }
    equal(call(instance.exports, "sine", -0), -0);
    equal(call(instance.exports, "cosine", -0), 1);
    for (const input of [8193, -8193, Infinity, -Infinity, NaN]) {
      for (const fn of ["sine", "cosine", "tangent"]) {
        ok(Number.isNaN(call(instance.exports, fn, input)));
      }
    }
    for (const input of [-100, -0.5, 0, 0.5, 100]) {
      const wrapped = call(instance.exports, "wrap", input);
      ok(wrapped >= 0 && wrapped < Math.fround(2 * Math.PI));
    }
  } finally {
    compiler.dispose();
  }
});
