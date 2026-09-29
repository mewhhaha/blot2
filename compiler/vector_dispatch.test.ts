import { deepStrictEqual as equal } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";

Deno.test("field types resolve before scalar operands select vector arithmetic", async () => {
  const source = `
type Vector is data = #Vector { x: F32 }
type Ray is data = #Ray { origin: Vector, direction: Vector }
const Vector.add = fn (a: Vector) => fn (b: Vector) => #Vector { x: a.x + b.x }
const Vector.sub = fn (a: Vector) => fn (b: Vector) => #Vector { x: a.x - b.x }
const Vector.mul = fn (a: Vector) => fn (b: F32) => #Vector { x: a.x * b }
const dot = fn (a: Vector) => fn (b: Vector) => a.x * b.x
const direction = #Vector { x: 1.0 }
const ray = #Ray { origin: #Vector { x: 40.0 }, direction }
const move = fn ray => fn weight => (ray.origin + ray.direction * weight).x
const target = fn ray => fn offset => do:
  let distance = 2.0 / max 0.001 (dot ray.direction direction)
  return ((ray.origin + ray.direction * distance) - offset).x
const interpolate = fn a => fn b => fn (weight: F32) => a + (b - a) * weight
entry const movement = fn (weight: F32) => move ray weight
entry const projected = fn () => target ray (#Vector { x: 0.0 })
entry const blended = fn weight => (interpolate (#Vector { x: 40.0 }) (#Vector { x: 44.0 }) weight).x
// One-sided inference is still available when no field can supply the type.
entry const converted = fn (value: U32) => from value / 2.0
`;
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const expected = reference.compile(source);
    equal(await native.compile(source), expected);
    const { exports } = new WebAssembly.Instance(
      new WebAssembly.Module(expected.bytes),
    );
    equal((exports.movement as CallableFunction)(2), 42);
    equal((exports.projected as CallableFunction)(), 42);
    equal((exports.blended as CallableFunction)(0.5), 42);
    equal((exports.converted as CallableFunction)(84), 42);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});
