import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const common = `type Vec3 a is data = $Vec3 {x: a, y: a, z: a}
type First is data = $First U32
type Second is data = $Second U32
const keep: a -> a = func value => return value
const load: (Array a) -> a = func values => return values[0]
`;
const caller = `import * as common from "trial/common"
const integer = func (input: U32): Array U32 => return do:
  let row = common.keep {x: input, y: @u32.add input 1}
  let vector = common.keep ($common.Vec3 {x: row.x, y: row.y, z: @u32.add input 2})
  let rows: Array (common.Vec3 U32) = #[vector]
  let selected = common.load rows
  let $common.First first = common.keep ($common.First input)
  let $common.Second second = common.keep ($common.Second (@u32.add input 3))
  return #[selected.x, selected.y, selected.z, first, second]
const floating = func (input: F32): Array F32 => return do:
  let row = common.keep {x: input, y: @f32.neg input}
  let vector = common.keep ($common.Vec3 {x: row.x, y: row.y, z: @f32.neg row.y})
  let rows: Array (common.Vec3 F32) = #[vector]
  let selected = common.load rows
  return #[selected.x, selected.y, selected.z]
`;
const main = `import * as left from "trial/left"
import * as right from "trial/right"
entry const integer = func (input: U32): Array U32 => return do:
  let owner: Array U32 = #[input]
  let a = left.integer (@storage.read owner 0)
  let b = right.integer input
  return #[a[0],a[1],a[2],a[3],a[4],b[0],b[1],b[2],b[3],b[4]]
entry const floating = func (input: F32): Array F32 => return do:
  let owner: Array F32 = #[input]
  let a = left.floating (@storage.read owner 0)
  let b = right.floating input
  return #[a[0],a[1],a[2],b[0],b[1],b[2]]
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`completed contexts share generic aggregate plans while separating types (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-completed-context-positive-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      imports: { "trial/": directory },
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build({
        sources: {
          [entry]: main,
          [`${directory}/common.blot`]: common,
          [`${directory}/left.blot`]: caller,
          [`${directory}/right.blot`]: caller,
        },
      });
      assert(built.success, JSON.stringify(built));
      const work = built.stats?.workCounters as
        | Record<string, number>
        | undefined;
      assert.equal(work?.scoped_function_plan_definitions, 8);
      assert.equal(work?.scoped_context_sensitive_definitions ?? 0, 0);
      assert.equal(work?.scoped_context_free_definitions, 8);

      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          for (const input of [0, 1, 17, 0xfffffffe, 0]) {
            let actual;
            if (asynchronous) actual = await guest.callAsync("integer", input);
            else actual = guest.call("integer", input);
            const expected = [input, input + 1, input + 2, input, input + 3];
            assert.deepEqual(
              actual,
              new Uint32Array([...expected, ...expected]),
            );
          }
          for (const input of [0, -0, 1.5, -7.25, Infinity, -Infinity, 0]) {
            let actual;
            if (asynchronous) actual = await guest.callAsync("floating", input);
            else actual = guest.call("floating", input);
            assert(actual instanceof Float32Array);
            const expected = new Float32Array([
              input,
              -input,
              input,
              input,
              -input,
              input,
            ]);
            assert.deepEqual(
              new Uint32Array(actual.buffer, actual.byteOffset, actual.length),
              new Uint32Array(expected.buffer),
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

const sensitiveProtocol = `type Read a is contract = {const read: a -> U32}
type Row is data = $Row {target: Ref U32}
impl Rows : Read (Array Row) = {
  const read = func (rows: Array Row): U32 => return @storage.load (rows[0].target),
}
const read: a -> U32 where {Read a} = func value => return Read.read value
`;
const sensitiveHelpers = `import * as protocol from "trial/protocol"
const inner: a -> U32 where {protocol.Read a} = func value => return protocol.read value
const outer: a -> U32 where {protocol.Read a} = func value => return inner value
const apply = func operation -> value => return operation value
`;
const sensitiveCaller = `import * as protocol from "trial/protocol"
import * as helpers from "trial/helpers"
const read = func (rows: Array protocol.Row) => return {warm: helpers.inner rows, result: helpers.outer rows}
`;
const sensitiveEntry = `import * as protocol from "trial/protocol"
import * as left from "trial/left"
import * as right from "trial/right"
entry const answer = func (input: U32): Array U32 => return do:
  let a: Array U32 = #[input]
  let b: Array U32 = #[@u32.add input 10]
  let first: Array protocol.Row = #[$protocol.Row {target: @storage.at a 0}]
  let second: Array protocol.Row = #[$protocol.Row {target: @storage.at b 0}]
  let x = left.read first
  let y = right.read second
  let z = left.read second
  return #[x.warm, x.result, y.warm, y.result, z.warm, z.result]
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`completed contexts retain sensitivity from cached generic contract children (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-completed-context-sensitive-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      imports: { "trial/": directory },
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      for (const callback of [false, true]) {
        let helperSource = sensitiveHelpers;
        if (callback) {
          helperSource = sensitiveHelpers.replace(
            "return inner value",
            "return apply inner value",
          );
        }
        const built = await compiler.build({
          sources: {
            [entry]: sensitiveEntry,
            [`${directory}/protocol.blot`]: sensitiveProtocol,
            [`${directory}/helpers.blot`]: helperSource,
            [`${directory}/left.blot`]: sensitiveCaller,
            [`${directory}/right.blot`]: sensitiveCaller,
          },
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats?.workCounters as
          | Record<string, number>
          | undefined;
        assert((work?.scoped_context_sensitive_definitions ?? 0) >= 10);
        assert((work?.scoped_context_sensitive_calls ?? 0) >= 13);
        assert.equal(work?.scoped_context_queries, 2);

        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const input of [0, 1, 17, 0xfffffffe, 0]) {
              let actual;
              if (asynchronous) actual = await guest.callAsync("answer", input);
              else actual = guest.call("answer", input);
              assert.deepEqual(
                actual,
                new Uint32Array([
                  input,
                  input,
                  input + 10,
                  input + 10,
                  input + 10,
                  input + 10,
                ]),
              );
            }
          } finally {
            guest.dispose();
          }
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
