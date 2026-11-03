import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

for (const width of [8, 600]) {
  let first = "f0";
  let last = `f${width - 1}`;
  let fields = Array.from(
    { length: width },
    (_, index) => `f${index}: @u32.add input ${index},`,
  ).join("");
  let returned =
    `if @u32.eq flag 0 then row else @record.merge row {${last}: @u32.add row.f0 1000}`;
  if (width === 600) {
    returned = "row";
    first = "g0.f0";
    last = "g7.f74";
    fields = Array.from({ length: 8 }, (_, group) => {
      const children = Array.from(
        { length: 75 },
        (_, index) => `f${index}: @u32.add input ${group * 75 + index},`,
      ).join("");
      return `g${group}: {${children}},`;
    }).join("");
  }
  const source =
    `const carry = func row -> (flag: U32) -> (effects: Array U32) => return do:
  effects[0] := @u32.add self 1
  return ${returned}
entry const answer = func (input: U32): Array U32 => return do:
  let effects: Array U32 = #[0]
  let original = {${fields}}
  let first = carry original 0 effects
  let second = carry original 1 effects
  let current = original
  for step in 0 .. 3:
    current := carry current (@u32.rem input 2) effects
  return #[first.${first}, first.${last}, second.${last}, current.${last}, effects[0]]
`;
  for (const codegenTier of ["development", "optimized"] as const) {
    Deno.test(`result input aliases preserve ${width} word calls effects and loop snapshots (${codegenTier})`, async () => {
      const directory = await Deno.makeTempDir({
        prefix: "blot-result-alias-",
      });
      const entry = `${directory}/main.blot`;
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      });
      try {
        const built = await compiler.build({
          sources: { [entry]: source },
          signal: AbortSignal.timeout(10_000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        assert(
          work.scoped_result_store_words_avoided >= width - 1,
          JSON.stringify(work),
        );
        assert(
          work.scoped_result_load_words_avoided >= width - 1,
          JSON.stringify(work),
        );
        assert(work.scoped_function_plan_hits > 0);
        if (width === 600) assert(work.scoped_owned_packed_calls > 0);
        else assert(work.scoped_owned_word_calls > 0);
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const input of [0, 1, 8, 17, 0xffff_fffe, 0xffff_ffff, 0]) {
              let final = input + width - 1;
              if (width === 8 && input % 2 !== 0) final = input + 1000;
              let changed = input + width - 1;
              if (width === 8) changed = input + 1000;
              const expected = new Uint32Array([
                input,
                input + width - 1,
                changed,
                final,
                5,
              ]);
              let actual: unknown;
              if (asynchronous) actual = await guest.callAsync("answer", input);
              else actual = guest.call("answer", input);
              assert.deepEqual(actual, expected);
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
