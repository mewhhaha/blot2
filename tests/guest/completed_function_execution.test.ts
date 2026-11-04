import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const truncateSource = `type Row is data = $Row {target: Ref U32}
const bump = func (rows: ResizeArray Row): Unit => return do:
  for row in rows:
    @storage.write row.target (@u32.add (@storage.load row.target) 1)
const change = func (rows: ResizeArray Row): U32 => return do:
  bump rows
  @storage.truncate rows 1
  return @storage.length rows
entry const answer = func (input: U32): Array U32 => return do:
  let left: Array U32 = #[input]
  let right: Array U32 = #[@u32.add input 10]
  let rows: ResizeArray Row = #[$Row {target: @storage.at left 0}, $Row {target: @storage.at right 0}]
  let count = change rows
  return #[left[0], right[0], count]
`;

const reserveSource = `type Row is data = $Row {target: Ref U32}
const bump = func (rows: ResizeArray Row): Unit => return do:
  for row in rows:
    @storage.write row.target (@u32.add (@storage.load row.target) 1)
const change = func (rows: ResizeArray Row): U32 => return do:
  bump rows
  @storage.reserve rows 4
  @storage.push rows (@storage.read rows 0)
  return @storage.length rows
entry const answer = func (input: U32): Array U32 => return do:
  let left: Array U32 = #[input]
  let right: Array U32 = #[@u32.add input 10]
  let rows: ResizeArray Row = #[$Row {target: @storage.at left 0}, $Row {target: @storage.at right 0}]
  let count = change rows
  return #[left[0], right[0], count]
`;

const freezeSource = `type Row is data = $Row {target: Ref U32}
const bump = func (rows: ResizeArray Row): Unit => return do:
  for row in rows:
    @storage.write row.target (@u32.add (@storage.load row.target) 1)
const change = func (rows: ResizeArray Row): U32 => return do:
  bump rows
  let frozen = @storage.freeze rows
  return @storage.length frozen
entry const answer = func (input: U32): Array U32 => return do:
  let left: Array U32 = #[input]
  let right: Array U32 = #[@u32.add input 10]
  let rows: ResizeArray Row = #[$Row {target: @storage.at left 0}, $Row {target: @storage.at right 0}]
  let count = change rows
  return #[left[0], right[0], count]
`;

const simdSource =
  `const target = func (words: Array U32): Ref U32 => return @storage.at words 0
const change = func (words: Array U32): Ref U32 => return do:
  let place = target words
  let changed = @simd.store words 0 (9,8,7,6)
  return place
entry const answer = func (input: U32): Array U32 => return do:
  let first: Array U32 = #[input,2,3,4]
  let second: Array U32 = #[5,6,7,input]
  let a = change first
  let b = change second
  return #[@storage.load a, first[1], first[2], first[3], @storage.load b, second[1], second[2], second[3]]
`;

const borrowSource = `type Row is data = $Row {target: Ref U32}
const target = func (rows: Array Row): Ref U32 => return (@storage.read rows 0).target
entry const answer = func (input: U32): Array U32 => return do:
  let first: Array U32 = #[input]
  let second: Array U32 = #[@u32.add input 10]
  let a: Array Row = #[$Row {target: @storage.at first 0}]
  let b: Array Row = #[$Row {target: @storage.at second 0}]
  let left = target a
  let right = target b
  @storage.write left (@u32.add (@storage.load left) 1)
  @storage.write right (@u32.add (@storage.load right) 2)
  return #[first[0],second[0],@storage.load left,@storage.load right]
`;

const escapeSource = `type Row is data = $Row {target: Ref U32}
const target = func (rows: Array Row): Ref U32 => return (@storage.read rows 0).target
const escape = func (): Ref U32 => return do:
  let values: Array U32 = #[7]
  let rows: Array Row = #[$Row {target: @storage.at values 0}]
  return target rows
entry const answer = func (): U32 => return @storage.load (escape ())
`;

const fixtures = [
  {
    name: "truncate",
    source: truncateSource,
    expected: (input: number) => [(input + 1) >>> 0, (input + 11) >>> 0, 1],
  },
  {
    name: "reserve",
    source: reserveSource,
    expected: (input: number) => [(input + 1) >>> 0, (input + 11) >>> 0, 3],
  },
  {
    name: "freeze",
    source: freezeSource,
    expected: (input: number) => [(input + 1) >>> 0, (input + 11) >>> 0, 2],
  },
  {
    name: "simd",
    source: simdSource,
    expected: (_input: number) => [9, 8, 7, 6, 9, 8, 7, 6],
  },
  {
    name: "borrow",
    source: borrowSource,
    expected: (
      input: number,
    ) => [
      (input + 1) >>> 0,
      (input + 12) >>> 0,
      (input + 1) >>> 0,
      (input + 12) >>> 0,
    ],
  },
];

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`completed function trials roll back effects and retain caller borrows (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-completed-function-",
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
      for (const fixture of fixtures) {
        const built = await compiler.build({
          sources: { [entry]: fixture.source },
        });
        assert(built.success, `${fixture.name}: ${JSON.stringify(built)}`);
        assert(WebAssembly.validate(built.bytes), fixture.name);
        const counters = built.stats.workCounters as Record<string, number>;
        let definitions = 1;
        if (fixture.name === "simd") definitions = 2;
        assert.equal(
          counters.scoped_completed_plan_definitions,
          definitions,
          fixture.name,
        );
        assert.equal(
          counters.scoped_owner_graph_definitions,
          definitions,
          fixture.name,
        );
        if (fixture.name === "borrow" || fixture.name === "simd") {
          assert.equal(counters.scoped_completed_plan_rollbacks, 0);
          assert(counters.scoped_function_plan_hits >= 1);
        } else {
          assert.equal(
            counters.scoped_completed_plan_rollbacks,
            1,
            fixture.name,
          );
          assert(
            counters.scoped_completed_plan_discarded_expressions > 0,
            fixture.name,
          );
        }
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const input of [0, 7, 0xfffffffd, 0]) {
              let actual;
              if (asynchronous) actual = await guest.callAsync("answer", input);
              else actual = guest.call("answer", input);
              assert(actual instanceof Uint32Array);
              assert.deepEqual(
                Array.from(actual),
                fixture.expected(input),
                fixture.name,
              );
            }
          } finally {
            guest.dispose();
          }
        }
      }
      const rejected = await compiler.build({
        sources: { [entry]: escapeSource },
      });
      assert(!rejected.success);
      assert(
        rejected.diagnostics.some((diagnostic) =>
          diagnostic.code === "storage_escape"
        ),
      );
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
