import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";
const record = (omitted: string, kept: string) =>
  `{a_omitted: ${omitted},b0: 0,b1: 1,b2: 2,b3: 3,b4: 4,b5: 5,z_kept: ${kept}}`;
const source = `const choose = func access => return access.z_kept
const forward = func access => return choose access
const plus = func (value: U32): U32 ! {} => return @u32.add value 1
entry const ordinals = func (input: U32): Array U32 => return do:
  let first: ResizeArray U32 = #[input]
  let second: ResizeArray U32 = #[@u32.add input 10]
  let left = choose ${record("first", "second")}
  let right = choose ${record("second", "first")}
  let alias = choose ${record("second", "second")}
  second[0] := @u32.add input 20
  return #[left[0],right[0],alias[0]]
entry const borrowed = func (input: U32): Array U32 => return do:
  let first: ResizeArray U32 = #[input]
  let second: ResizeArray U32 = #[@u32.add input 10]
  let left = choose ${record("&first[0..1]", "&second[0..1]")}
  let right = choose ${record("&second[0..1]", "&first[0..1]")}
  second[0] := @u32.add input 20
  return #[left[0],right[0]]
entry const whole_forward = func (input: U32): U32 => return do:
  let first: ResizeArray U32 = #[99]
  let second: ResizeArray U32 = #[input]
  let picked = forward ${record("first", "second")}
  return picked[0]
entry const trimmed = func (input: U32): Array U32 => return do:
  let first: ResizeArray U32 = #[99,98]
  let second: ResizeArray U32 = #[input,@u32.add input 1]
  let picked = choose ${record("first", "second")}
  @storage.truncate picked 1
  return #[@storage.length first,@storage.length second,picked[0]]
entry const frozen = func (input: U32): Array U32 => return do:
  let first: GrowArray U32 = #[99]
  let second: GrowArray U32 = #[input]
  let picked = choose ${record("first", "second")}
  let kept = @storage.freeze picked
  @storage.push first input
  return #[@storage.length kept,@storage.length first,kept[0],first[1]]
entry const observable = func (input: U32): U32 => return do:
  let rows: ResizeArray U32 = #[input]
  let picked = choose ${
  record('if @u32.eq input 0 then @panic "unused initializer" else 7', "rows")
}
  return picked[0]
`;
const omittedRead = `type Choice is data = $A U32 | $B U32
const choose = func access => return access.z_kept
entry const answer = func (input: U32): U32 => return do:
  let omitted: ResizeArray Choice = #[$A 7]
  let kept: ResizeArray U32 = #[input]
  let total = 0
  for index in 0 .. 2:
    let picked = choose ${record("omitted", "kept")}
    total := @u32.add total picked[0]
    omitted[0] := $B 8
  return total
`;
const fullFormal =
  `const plus = func (value: U32): U32 ! {} => return @u32.add value 1
const guarded = func (access: {a_omitted: U32 -> U32 ! {},b0: U32,b1: U32,b2: U32,b3: U32,b4: U32,b5: U32,z_kept: ResizeArray U32}): ResizeArray U32 => return access.z_kept
entry const answer = func (input: U32): U32 => return do:
  let rows: ResizeArray U32 = #[input]
  let picked = guarded ${record("plus", "rows")}
  return picked[0]
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`prepared readers preserve descriptor ordinals full formals and argument evaluation (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-prepared-reader-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0] ??
        new URL("../../compiler/zig-out/bin/blotc", import.meta.url),
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const result = await compiler.build({ sources: { [entry]: source } });
      assert(result.success, JSON.stringify(result));
      const work = result.stats.workCounters as Record<string, number>;
      assert(work.scoped_owned_projection_calls > 0);
      const guest = await instantiateGuest(result.bytes);
      try {
        for (const input of [0, 7, 1000]) {
          assert.deepEqual(
            guest.call("ordinals", input),
            new Uint32Array([input + 20, input, input + 20]),
          );
          assert.deepEqual(
            guest.call("borrowed", input),
            new Uint32Array([input + 20, input]),
          );
          assert.equal(guest.call("whole_forward", input), input);
          assert.deepEqual(
            guest.call("trimmed", input),
            new Uint32Array([2, 1, input]),
          );
          assert.deepEqual(
            guest.call("frozen", input),
            new Uint32Array([1, 2, input, input]),
          );
        }
        assert.equal(guest.call("observable", 7), 7);
        assert.throws(() => guest.call("observable", 0));
      } finally {
        guest.dispose();
      }
      const checked = await compiler.build({
        sources: { [entry]: omittedRead },
      });
      assert(checked.success, JSON.stringify(checked));
      const plainRows = await instantiateGuest(checked.bytes);
      try {
        assert.equal(plainRows.call("answer", 7), 14);
      } finally {
        plainRows.dispose();
      }
      const formal = await compiler.build({ sources: { [entry]: fullFormal } });
      assert(formal.success, JSON.stringify(formal));
      const formalWork = formal.stats.workCounters as Record<string, number>;
      assert(formalWork.scoped_owned_projection_calls > 0);
      assert.equal(formalWork.scoped_function_plan_definitions, 1);
      assert.equal(formalWork.scoped_function_plan_post_type_queries, 0);
      const guarded = await instantiateGuest(formal.bytes);
      try {
        assert.equal(guarded.call("answer", 7), 7);
      } finally {
        guarded.dispose();
      }
      const invalidField = await compiler.build({
        sources: {
          [entry]: fullFormal.replace("a_omitted: plus", "a_omitted: 7"),
        },
      });
      assert(
        !invalidField.success,
        "unused fields retain their written formal types",
      );
      assert(invalidField.diagnostics.some((d) => d.stage === "check-project"));
      const effectful = "effect Signal: U32 -> U32\n" + fullFormal.replace(
        "const plus = func (value: U32): U32 ! {} => return @u32.add value 1",
        "const plus = func (value: U32): U32 => return Signal value",
      );
      const invalidEffect = await compiler.build({
        sources: { [entry]: effectful },
      });
      assert(
        !invalidEffect.success,
        "unused callbacks retain their written effect rows",
      );
      assert(
        invalidEffect.diagnostics.some((d) => d.code === "effect_mismatch"),
      );
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
