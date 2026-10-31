import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

// The large consumer runs repeatedly inside one invocation. Forcing a captured
// demand creates its result local inside this consumer's emission range, while
// its ready flag already belongs to the outer scope. Both must persist together.
const padding = 2000;
function sourceFor(scalar: "U32" | "F32"): string {
  return `const calculate = func (counter: Array U32) -> (input: ${scalar}): ${scalar} => return do:
  counter[0] := @u32.add counter[0] 1
  return ${scalar === "U32" ? "@u32.add input 7" : "input"}
const consume = func (destination: ResizeArray ${scalar}) -> (read: Unit -> ${scalar} ! {|e}): Unit => return do:
  let total = read ()
${
    (scalar === "U32"
      ? "  total := @u32.add total 1\n"
      : "  total := @f32.neg total\n").repeat(padding)
  }  @storage.push destination total
  return ()
const exercise = func ~(value: ${scalar}) -> (destination: ResizeArray ${scalar}): Unit => return do:
  for index in 0 .. 3:
    consume destination (func () => return @demand value)
  return ()
entry const answer = func (input: ${scalar}) => return do:
  let counter: Array U32 = #[0]
  let destination: ResizeArray ${scalar} = #[]
  exercise (calculate counter input) destination
  return #[${
    scalar === "U32" ? "counter[0]" : "@u32.to_f32 counter[0]"
  }, destination[0], destination[1], destination[2]]
`;
}

for (const scalar of ["U32", "F32"] as const) {
  for (const codegenTier of ["development", "optimized"] as const) {
    Deno.test(`machine regions retain captured ${scalar} demand state through enclosing loops (${codegenTier})`, async () => {
      const directory = await Deno.makeTempDir({
        prefix: "blot-machine-regions-",
      });
      const entry = `${directory}/main.blot`;
      const stdRoot = new URL("../../std", import.meta.url).pathname;
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        stdRoot,
        prelude: `${stdRoot}/prelude.blot`,
        cacheDirectory: false,
        codegenTier,
      });
      try {
        const result = await compiler.build({
          sources: { [entry]: sourceFor(scalar) },
        });
        assert(result.success, JSON.stringify(result));
        const counters = result.stats.workCounters as Record<string, number>;
        assert(counters.scoped_outlined_regions > 0, JSON.stringify(counters));
        assert(counters.scoped_outlined_globals > 0, JSON.stringify(counters));
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(result.bytes, { asynchronous });
          try {
            for (
              const input of scalar === "U32"
                ? [0, 9, 100, 0xffffffff]
                : [-0, 1.25, -5.5, Infinity, NaN]
            ) {
              const expected = scalar === "U32"
                ? (input + 7 + padding) >>> 0
                : input;
              const value = asynchronous
                ? await guest.callAsync("answer", input)
                : guest.call("answer", input);
              assert.deepEqual(
                value,
                scalar === "U32"
                  ? new Uint32Array([1, expected, expected, expected])
                  : new Float32Array([1, expected, expected, expected]),
              );
            }
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await compiler.dispose();
        await Deno.remove(directory, { recursive: true });
      }
    });
  }
}
