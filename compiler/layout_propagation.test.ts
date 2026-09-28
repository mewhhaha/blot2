import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { instantiateGuest } from "./guest.ts";

const source = `
type Pair is data = Pair { x: U32, y: U32 }
entry const lexical = fn (count: U32) => do:
  let value = @u32.add count 1
  return @array.fill 8 value
entry const tupled = fn (count: U32) => do:
  let pair = (@u32.add count 1, 7)
  let (a, b) = pair
  return @array.fill 8 a
entry const indexed = fn (count: U32) => do:
  let cells = @array.fill 8 (@u32.add count 1)
  let value = @array.get cells 0
  return @array.fill 8 value
entry const matched = fn (count: U32) => case (@u32.add count 1) of
  value => @array.fill 8 value
entry const guarded = fn (count: U32) => do:
  let (a, b) = (@u32.add count 1, @u32.add count 2) else:
    return @array.fill 8 0
  return @array.fill 8 a
entry const unknown = fn (count: U32) => do:
  let value = count
  return @array.fill 8 value
entry const blocked = fn (count: U32) => do:
  let value = do:
    if @u32.eq count 0:
      return count
    return @u32.add count 1
  return @array.fill 8 value
entry const shadowed = fn (count: U32) => do:
  let value = @u32.add count 1
  let value = count
  return @array.fill 8 value
entry const pointer_tuple = fn (count: U32) => do:
  let cells = @array.fill 8 (@u32.add count 1)
  let pair = (cells, @u32.add count 2)
  let (a, b) = pair
  return @array.get a 0
entry const record = fn (count: U32) => do:
  let value = @u32.add count 1
  let pair = Pair { x: value, y: @u32.add count 2 }
  let Pair { x, y } = pair
  return @u32.add x y
`;
const loops = `
entry const captures = fn (limit: U32) => do:
  let pinned = @array.fill 32 7
  let state = (0, @array.fill 32 (fn () => @array.get pinned 0))
  for ever:
    let (turn, callbacks) = state
    if @u32.eq turn limit:
      return [turn, (@array.get callbacks 31) (), @array.get pinned 0]
    let value = @u32.add turn 1
    let cells = @array.fill 32 value
    let pair = (cells, value)
    let (live, number) = pair
    state := (number, @array.fill 32 (fn () => @array.get live 31))
entry const nested = fn (limit: U32) => do:
  let original = @array.fill 32 7
  let state = (0, @array.fill 32 original)
  for ever:
    let (turn, previous) = state
    if @u32.eq turn limit:
      return [turn, @array.get (@array.get previous 31) 31, @array.get original 0]
    let value = @u32.add turn 1
    let cells = @array.fill 32 value
    let value = cells
    state := (@u32.add turn 1, @array.fill 32 value)
`;

function flags(instance: WebAssembly.Instance): number[] {
  const memory = instance.exports["blot:memory"] as WebAssembly.Memory;
  const cursor = (instance.exports["blot:allocate"] as CallableFunction)(0);
  const view = new DataView(memory.buffer);
  const result: number[] = [];
  let position = view.getUint32(4, true);
  while (position !== 0 && position < cursor) {
    const size = view.getUint32(position, true);
    ok(size >= 16 && size <= cursor - position);
    result.push(view.getUint32(position + 8, true));
    position += size;
  }
  return result;
}

for (const backend of ["javascript", "native"] as const) {
  Deno.test(`layout propagation preserves lexical evidence and reference reachability (${backend})`, async () => {
    const compiler = backend === "javascript"
      ? await createSourceCompiler({ prelude: "none" })
      : await createNativeCompiler({ prelude: "none" });
    try {
      const artifact = await compiler.compile(source);
      const { instance } = await WebAssembly.instantiate(artifact.bytes);
      const memory = instance.exports["blot:memory"] as WebAssembly.Memory;
      for (const input of [0, 5, 65552, 0xfffffffe]) {
        for (
          const name of ["lexical", "tupled", "indexed", "matched", "guarded"]
        ) {
          const pointer = (instance.exports[name] as CallableFunction)(input);
          equal(
            new DataView(memory.buffer).getUint32(pointer - 8, true),
            2,
            name,
          );
          equal(
            new Uint32Array(memory.buffer, pointer + 4, 8),
            new Uint32Array(8).fill((input + 1) >>> 0),
          );
          if (name === "tupled") equal(flags(instance), [0, 2]);
        }
        for (const name of ["unknown", "blocked", "shadowed"]) {
          const pointer = (instance.exports[name] as CallableFunction)(input);
          equal(
            new DataView(memory.buffer).getUint32(pointer - 8, true),
            0,
            name,
          );
          const value = name === "blocked" && input !== 0
            ? (input + 1) >>> 0
            : input;
          equal(
            new Uint32Array(memory.buffer, pointer + 4, 8),
            new Uint32Array(8).fill(value),
          );
        }
        equal(
          ((instance.exports.pointer_tuple as CallableFunction)(input)) >>> 0,
          (input + 1) >>> 0,
        );
        equal(
          flags(instance),
          [2, 0],
          "tuple containing an array must trace its child",
        );
        equal(
          ((instance.exports.record as CallableFunction)(input)) >>> 0,
          (2 * input + 3) >>> 0,
        );
        equal(
          flags(instance),
          [0, 0],
          "small scalar record payload avoids the extra store; wrapper is traced",
        );
      }
      for (const count of [7, 8, 9, 16]) {
        const fields = Array(count).fill("value").join(", ");
        const names = Array.from({ length: count }, (_, i) => `v${i}`).join(
          ", ",
        );
        const probe = `
entry const inspect = fn (input: U32) => do:
  let value = @u32.add input 1
  let product = (${fields})
  let (${names}) = product
  return v${count - 1}
entry const memory_probe = fn (input: U32) => @array.fill input 0
`;
        const compiled = await compiler.compile(probe);
        const { instance: product } = await WebAssembly.instantiate(
          compiled.bytes,
        );
        equal((product.exports.inspect as CallableFunction)(65552), 65553);
        equal(flags(product), [count < 8 ? 0 : 2]);
      }
      const guest = await instantiateGuest(
        (await compiler.compile(loops)).bytes,
      );
      try {
        for (const name of ["captures", "nested"]) {
          for (const iterations of [0, 1, 10000]) {
            equal(
              guest.call(name, iterations),
              new Uint32Array([
                iterations,
                iterations === 0 ? 7 : iterations,
                7,
              ]),
            );
            ok(guest.memoryBytes() <= 256 * 1024);
          }
        }
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
    }
  });
}
