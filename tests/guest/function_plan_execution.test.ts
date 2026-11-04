import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source =
  `type Access is data = $Access {rows: Array U32, audit: Array U32}
type Hooks is data = $Hooks {after: Access -> U32 -> Unit ! {}}
const Access.first = func (access: Access): U32 => return @storage.read access.rows 0
const audit_step = func (access: Access) -> (value: U32): Unit => return do:
  access.audit[0] := @u32.add (@u32.mul (@storage.read access.audit 0) 10) value
const apply_write = func (access: Access) -> (hooks: Hooks) -> (delta: U32): Unit => return do:
  access.rows[0] := @u32.add access.first delta
  hooks.after access access.first
const window = func (access: Access): &[U32] => return &access.rows[0..2]
const pair = func (access: Access): {value: U32, audit: U32} => return
  {value: access.first, audit: @storage.read access.audit 0}
const quad = func (access: Access): {a: U32, b: U32, c: U32, d: U32} => return
  {a: access.first, b: @storage.read access.rows 1, c: @storage.read access.audit 0, d: 31}
const stopped_pair = func (input: U32): {a: U32, b: U32} => return do:
  use @panic "stopped pair"
  return {a: input, b: 1}
const stopped_five = func (input: U32): {a: U32, b: U32, c: U32, d: U32, e: U32} => return do:
  use @panic "stopped five"
  return {a: input, b: 1, c: 2, d: 3, e: 4}
entry const stopped = func (input: U32): U32 => return (stopped_pair input).a
entry const stopped_buffered = func (input: U32): U32 => return (stopped_five input).a
entry const answer = func (input: U32): Array U32 => return do:
  let rows: Array U32 = #[input, 7]
  let audit: Array U32 = #[0]
  let other: Array U32 = #[@u32.add input 20, 11]
  let other_audit: Array U32 = #[0]
  let first = $Access {rows, audit}
  let second = $Access {rows: other, audit: other_audit}
  let hooks = $Hooks {after: audit_step}
  apply_write first hooks 1
  let view = window first
  rows[0] := @u32.add (@storage.read rows 0) 10
  let before = pair first
  apply_write second hooks 2
  let after = pair second
  let four = quad second
  apply_write first hooks 3
  let retained = pair first
  return #[view[0], view[1], before.value, before.audit, after.value, after.audit,
    four.a, four.b, four.c, four.d, retained.value, retained.audit,
    @storage.read audit 0, @storage.read other_audit 0]
`;

const escape = source.slice(0, source.indexOf("entry const answer")) +
  `entry const answer = func (input: U32): U32 => return do:
  let retained: ResizeArray (&[U32]) = #[]
  do:
    let rows: Array U32 = #[input, 7]
    let audit: Array U32 = #[0]
    let access = $Access {rows, audit}
    @storage.push retained (window access)
  return @storage.length retained
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`checked function plans preserve explicit interfaces and input borrows (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-function-plan-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
      startupTimeoutMs: 5000,
    });
    try {
      const result = await compiler.build({
        sources: { [entry]: source },
        signal: AbortSignal.timeout(5000),
      });
      assert(result.success, JSON.stringify(result));
      const work = result.stats.workCounters as Record<string, number>;
      assert(
        work.scoped_function_plan_definitions !== undefined,
        "candidate must expose plan coverage",
      );
      assert(
        work.scoped_function_plan_definitions >= 3,
        JSON.stringify(work),
      );
      assert(work.scoped_function_plan_hits >= 1, JSON.stringify(work));
      assert(
        work.scoped_function_plan_register_calls > 0,
        JSON.stringify(work),
      );
      assert.equal(
        work.scoped_function_plan_post_type_queries,
        0,
        JSON.stringify(work),
      );
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        try {
          assert.equal(guest.abi.version, 8);
          for (const input of [0, 1, 7, 42, 0xffffffd0, 0, 7]) {
            const u = (value: number) => value >>> 0;
            const updated = u(input + 14);
            const observed = u(11 * input + 24);
            const expected = new Uint32Array([
              updated,
              7,
              u(input + 11),
              u(input + 1),
              u(input + 22),
              u(input + 22),
              u(input + 22),
              11,
              u(input + 22),
              31,
              updated,
              observed,
              observed,
              u(input + 22),
            ]);
            let actual;
            if (asynchronous) actual = await guest.callAsync("answer", input);
            else actual = guest.call("answer", input);
            assert.deepEqual(actual, expected);
          }
          for (const name of ["stopped", "stopped_buffered"]) {
            await assert.rejects(async () => {
              if (asynchronous) return await guest.callAsync(name, 1);
              return guest.call(name, 1);
            }, WebAssembly.RuntimeError);
          }
        } finally {
          guest.dispose();
        }
      }
      const badEffect = "effect Signal: Unit -> Unit\n" +
        source.replace(
          "after: audit_step}",
          "after: func (_: Access) -> (_: U32) => return Signal ()}",
        );
      const rejectedEffect = await compiler.build({
        sources: { [entry]: badEffect },
        signal: AbortSignal.timeout(5000),
      });
      assert(
        !rejectedEffect.success,
        "an effectful callback cannot satisfy the closed Hooks interface",
      );
      assert(
        rejectedEffect.diagnostics.some((d) => d.code === "effect_mismatch"),
        JSON.stringify(rejectedEffect),
      );
      const rejectedEscape = await compiler.build({
        sources: { [entry]: escape },
        signal: AbortSignal.timeout(5000),
      });
      assert(
        !rejectedEscape.success,
        "a returned input borrow cannot escape its owner's scope",
      );
      assert(
        rejectedEscape.diagnostics.some((d) => d.code === "storage_escape"),
        JSON.stringify(rejectedEscape),
      );
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
