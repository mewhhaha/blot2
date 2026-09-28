import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { instantiateGuest } from "./guest.ts";

const layoutSource = `
entry const filled = fn (count: U32) => @array.fill count 42
entry const floats = fn (count: U32) => @array.fill count (@f32.neg 0.0)
entry const computed = fn (count: U32) => @array.fill 8 (@u32.add count 1)
entry const unknown = fn (count: U32) => @array.fill 8 count
entry const literal = fn (count: U32) => [@u32.add count 1, 7, 9]
entry const mixed = fn (count: U32) => [count, 7, 9]
entry const copied = fn (values: Array U32) => @array.set values 0 42
`;
const loopSource = `
entry const run = fn (limit: U32) => do:
  let original = @array.fill 1024 7
  let state = (0, @array.fill 1024 0)
  for ever:
    let (turn, previous) = state
    if @u32.eq turn limit:
      return [turn, @array.get previous 1000, @array.get original 0]
    state := (@u32.add turn 1, @array.fill 1024 (@u32.add turn 1))
entry const references = fn (limit: U32) => do:
  let original = @array.fill 16 7
  let state = (0, @array.fill 16 original)
  for ever:
    let (turn, previous) = state
    if @u32.eq turn limit:
      return [turn, @array.get (@array.get previous 0) 0, @array.get original 0]
    state := (@u32.add turn 1, @array.fill 16 (@array.fill 16 (@u32.add turn 1)))
`;

for (const backend of ["javascript", "native"] as const) {
  Deno.test(`scalar array layout is conservative and survives long-lived loops (${backend})`, async () => {
    const compiler = backend === "javascript"
      ? await createSourceCompiler({ prelude: "none" })
      : await createNativeCompiler({ prelude: "none" });
    try {
      const artifact = await compiler.compile(layoutSource);
      const { instance } = await WebAssembly.instantiate(artifact.bytes);
      const memory = instance.exports["blot:memory"] as WebAssembly.Memory;
      const flag = (pointer: number) =>
        new DataView(memory.buffer).getUint32(pointer - 8, true);
      for (const name of ["filled", "floats", "computed", "literal"]) {
        equal(flag((instance.exports[name] as CallableFunction)(64)), 2, name);
      }
      for (const name of ["unknown", "mixed"]) {
        equal(flag((instance.exports[name] as CallableFunction)(64)), 0, name);
      }
      const before = (instance.exports.filled as CallableFunction)(64);
      const changed = (instance.exports.copied as CallableFunction)(before);
      equal(flag(changed), 2);
      ok(changed !== before, "borrowed inputs must still be copied");
      const floats = (instance.exports.floats as CallableFunction)(64);
      equal(
        new Uint32Array(memory.buffer, floats + 4, 64),
        new Uint32Array(64).fill(0x80000000),
      );
      const loops = await compiler.compile(loopSource);
      const guest = await instantiateGuest(loops.bytes);
      try {
        for (const name of ["run", "references"]) {
          equal(guest.call(name, 10000), new Uint32Array([10000, 10000, 7]));
          ok(
            guest.memoryBytes() <= 256 * 1024,
            `${name}: ${guest.memoryBytes()}`,
          );
        }
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
    }
  });
}
