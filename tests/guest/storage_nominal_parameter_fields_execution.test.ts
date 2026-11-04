import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

function producer(reordered: boolean): string {
  let fields =
    "z_kept: Ref U32, a_omitted: Ref U32, tick: U32 -> U32 ! {}, draw: U32 -> U32 ! {}, save: U32 -> U32 ! {}, close: U32 -> U32 ! {}";
  if (reordered) {
    fields =
      "close: U32 -> U32 ! {}, a_omitted: Ref U32, draw: U32 -> U32 ! {}, save: U32 -> U32 ! {}, z_kept: Ref U32, tick: U32 -> U32 ! {}";
  }
  return `type Access is data = $Access {${fields}}
const plus = func (input: U32): U32 => return @u32.add input 1
const make = func (kept: Ref U32) -> (omitted: Ref U32): Access => return $Access {draw: plus, a_omitted: omitted, close: plus, z_kept: kept, tick: plus, save: plus}
const direct = func (access: Access): U32 => return @storage.load access.z_kept
const Access.hidden = func (access: Access): U32 => return @storage.load access.a_omitted
`;
}
const common = `import * as left from "./left"
const choose = func access => return access.z_kept
const forward = func access => return access
const hidden = func access => return access.hidden
const temporary_omitted = func (kept: Ref U32): Ref U32 => return do:
  let temporary: Array U32 = #[99]
  let access = left.make kept (@storage.at temporary 0)
  return choose access
`;
const caller = `import * as left from "./left"
import * as right from "./right"
import * as access from "./common"
type DictionaryNoise is data = $Noise {tick: F32, z_kept: Bool, close: U32, a_omitted: F32}
entry const answer = func (input: U32): Array U32 => return do:
  let first: Array U32 = #[input]
  let second: Array U32 = #[10]
  let a = left.make (@storage.at first 0) (@storage.at second 0)
  let b = right.make (@storage.at second 0) (@storage.at first 0)
  let selected_a = access.choose a
  let selected_b = access.choose b
  let selected_alias = access.choose (left.make (@storage.at first 0) (@storage.at first 0))
  let scoped = access.temporary_omitted (@storage.at first 0)
  first[0] := @u32.add input 3
  second[0] := 20
  return #[@storage.load selected_a, @storage.load selected_b, @storage.load selected_alias, @storage.load scoped, left.direct a, right.direct b]
entry const fallback = func (input: U32): Array U32 => return do:
  let first: Array U32 = #[input]
  let second: Array U32 = #[10]
  let original = left.make (@storage.at first 0) (@storage.at second 0)
  let whole = access.forward original
  let merged = whole
  merged.a_omitted := @storage.at first 0
  return #[@storage.load whole.a_omitted, @storage.load merged.a_omitted, whole.tick 4, access.hidden original]
`;
const escaped = `${common}
const invalid = func (outside: Ref U32): Ref U32 => return do:
  let temporary: Array U32 = #[7]
  return choose (left.make (@storage.at temporary 0) outside)
entry const bad = func (input: U32): U32 => return do:
  let first: Array U32 = #[input]
  return @storage.load (invalid (@storage.at first 0))
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`nominal physical fields preserve imported dictionaries aliases getters whole uses and borrow escapes (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-nominal-fields-",
    });
    const entry = `${directory}/main.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const options = {
      executable: Deno.args[0],
      entry,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
      cacheDirectory: false as const,
      codegenTier,
    };
    const compiler = await createZigProjectCompiler(options);
    try {
      const sources = {
        [entry]: caller,
        [`${directory}/left.blot`]: producer(false),
        [`${directory}/right.blot`]: producer(true),
        [`${directory}/common.blot`]: common,
      };
      const result = await compiler.build({ sources });
      assert(result.success, JSON.stringify(result));
      const counters = result.stats.workCounters as Record<string, number>;
      assert(
        counters.scoped_owned_projection_calls > 0 ||
          counters.scoped_reader_projection_calls > 0,
      );
      assert(counters.scoped_projected_parameter_fields > 0);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        try {
          for (const input of [0, 9, 0xFFFFFFFF]) {
            let actual: unknown;
            if (asynchronous) actual = await guest.callAsync("answer", input);
            else actual = guest.call("answer", input);
            assert.deepEqual(
              actual,
              new Uint32Array([
                input + 3,
                20,
                input + 3,
                input + 3,
                input + 3,
                20,
              ]),
            );
            if (asynchronous) actual = await guest.callAsync("fallback", input);
            else actual = guest.call("fallback", input);
            assert.deepEqual(actual, new Uint32Array([10, input, 5, 10]));
          }
        } finally {
          guest.dispose();
        }
      }
      const invalid = await compiler.build({
        sources: { ...sources, [entry]: escaped },
      });
      assert(
        !invalid.success,
        "a kept local borrow must not escape the callee",
      );
      assert(
        invalid.diagnostics.some((diagnostic) =>
          diagnostic.code === "storage_escape"
        ),
        JSON.stringify(invalid),
      );
      const capturedCallback = `${
        producer(false).replace(
          "tick: plus,",
          "tick: make_callback {value: 37},",
        )
      }
const make_callback = func state => return do:
  let captured = state
  return func (argument: U32): U32 => return @u32.add captured.value argument
`;
      const changed = await compiler.build({
        sources: { ...sources, [`${directory}/left.blot`]: capturedCallback },
      });
      assert(changed.success, JSON.stringify(changed));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(changed.bytes, { asynchronous });
        try {
          let value: unknown;
          if (asynchronous) value = await guest.callAsync("fallback", 9);
          else value = guest.call("fallback", 9);
          assert.deepEqual(value, new Uint32Array([10, 9, 41, 10]));
        } finally {
          guest.dispose();
        }
      }
      const restored = await compiler.build({ sources });
      assert(restored.success, JSON.stringify(restored));
      assert.deepEqual(restored.bytes, result.bytes);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
