import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";

// A tuple carries two versions of a data value containing nested arrays.
// Alternate acceptance/rejection while retaining shared pre-loop aliases.
const source = `
type World is data = World { rows: Array (Array F32) }
const value = fn world => do:
  let World { rows } = world
  return @array.get (@array.get rows 0) 0
const bump = fn world => do:
  let World { rows } = world
  let first = @array.get rows 0
  let changed = @array.set first 0 (@array.get first 0 + 1.0)
  return World { rows: [changed, @array.get rows 1] }
entry const run = fn (limit: U32) => do:
  let original = @array.fill 1024 7.0
  let captured = fn () => @array.get original 1023
  let initial = World { rows: [original, original] }
  let state = (initial, initial, True, 0)
  for ever:
    let (committed, candidate, accept, step) = state
    if @array.get original 0 != 7.0:
      return @panic "candidate mutated a shared pre-loop array"
    if step >= limit:
      let World { rows } = committed
      return [value committed, value candidate, @array.get (@array.get rows 1) 0, captured ()]
    let selected = case accept of
      True => candidate
      False => committed
    state := (selected, bump selected, Bool.not accept, step + 1)
const inner = fn held => do:
  let state = (held, 0)
  for ever:
    let (values, step) = state
    if step >= 7:
      return values
    state := (@array.fill 512 (@array.get held 0 + 1.0), step + 1)
entry const nested = fn (limit: U32) => do:
  let original = @array.fill 512 9.0
  let starting = inner (@array.fill 512 0.0)
  let state = (starting, 0)
  for ever:
    let (held, step) = state
    if step >= limit:
      return [@array.get held 0, @array.get original 511]
    let next = inner held
    if @array.get held 0 != (U32.to_f32 step + 1.0):
      return @panic "inner collection damaged a live outer-loop value"
    state := (next, step + 1)
`;

for (const backend of ["native", "javascript"] as const) {
  Deno.test(`persistent graph carries retain aliases and reset between entries (${backend})`, async () => {
    const compiler = backend === "native"
      ? await createNativeCompiler()
      : await createSourceCompiler();
    try {
      const artifact = await compiler.compile(source);
      const { instance } = await WebAssembly.instantiate(artifact.bytes);
      const memory = instance.exports["blot:memory"] as WebAssembly.Memory;
      const invoke = (name: string, count: number, expected: number[]) => {
        const pointer = (instance.exports[name] as CallableFunction)(count);
        // Acquire views after execution, since memory.grow detaches old views.
        equal(
          new DataView(memory.buffer).getUint32(pointer, true),
          expected.length,
        );
        equal(
          new Float32Array(memory.buffer, pointer + 4, expected.length),
          new Float32Array(expected),
        );
        ok(
          memory.buffer.byteLength <= 2 * 1024 * 1024,
          `retained ${memory.buffer.byteLength} bytes after ${count} iterations`,
        );
      };
      const run = (count: number, expected: number[]) =>
        invoke("run", count, expected);
      // Cumulative array allocations exceed 8 MiB even before object headers.
      run(2048, [1030, 1031, 7, 7]);
      // Inner collections must retain the outer loop's live array and aliases.
      // Seven initial inner backedges offset a hypothetical global cadence.
      // Each later iteration adds seven inner plus one outer backedge: a
      // global modulo-four counter would never collect at the outer boundary.
      invoke("nested", 512, [513, 9]);
      const warmed = memory.buffer.byteLength;
      run(38, [25, 26, 7, 7]);
      run(1000, [506, 507, 7, 7]);
      run(0, [7, 7, 7, 7]);
      invoke("nested", 3, [4, 9]);
      equal(memory.buffer.byteLength, warmed);
      const reset = instance.exports["blot:reset"] as CallableFunction;
      const allocate = instance.exports["blot:allocate"] as CallableFunction;
      const floor = reset(0);
      const first = allocate(128);
      equal(reset(0), floor);
      equal(allocate(128), first, "reset discards stale free-bin entries");
      run(2, [7, 8, 7, 7]);
    } finally {
      await compiler.dispose();
    }
  });
}
