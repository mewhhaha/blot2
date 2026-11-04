import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source = `type Row is data = $Row {left: Ref U32, right: Ref U32}
const bump = func (rows: Array Row): Unit => return do:
  for row in rows:
    @storage.write row.left (@u32.add (@storage.load row.left) 1)
    @storage.write row.right (@u32.add (@storage.load row.right) 10)
const fetch = func (rows: Array Row): Row => return @storage.read rows 0
entry const answer = func (input: U32): Array U32 => return do:
  let a: Array U32 = #[input]
  let b: Array U32 = #[input]
  let c: Array U32 = #[input]
  let d: Array U32 = #[input]
  let e: Array U32 = #[input]
  let aliased: Array Row = #[$Row {left: @storage.at a 0, right: @storage.at a 0}]
  let first: Array Row = #[$Row {left: @storage.at b 0, right: @storage.at c 0}]
  let second: Array Row = #[$Row {left: @storage.at d 0, right: @storage.at e 0}]
  bump aliased
  bump first
  bump second
  let joined = if @u32.eq (@u32.rem input 2) 0 then first else second
  bump joined
  let observed_first = fetch first
  let observed_second = fetch second
  let observed_joined = fetch joined
  return #[a[0], b[0], c[0], d[0], e[0],
    @storage.load observed_first.left, @storage.load observed_second.right,
    @storage.load observed_joined.left, @storage.load observed_joined.right]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`symbolic owner graphs preserve aliases and returned descriptors (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-owner-graph-" });
    const entry = `${directory}/main.blot`;
    let compiler:
      | Awaited<ReturnType<typeof createZigProjectCompiler>>
      | undefined;
    try {
      compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
        startupTimeoutMs: 5_000,
      });
      const built = await compiler.build({
        sources: { [entry]: source },
        signal: AbortSignal.timeout(5_000),
      });
      assert(built.success, JSON.stringify(built));
      const work = built.stats.workCounters as Record<string, number>;
      assert(work.scoped_owner_graph_definitions >= 5, JSON.stringify(work));
      assert(work.scoped_function_plan_hits >= 2, JSON.stringify(work));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          for (const input of [0, 1, 7, 42, 0xfffffffd, 0]) {
            const rows = [
              input + 11,
              input + 1,
              input + 10,
              input + 1,
              input + 10,
            ];
            let selected = 1;
            if (input % 2 !== 0) selected = 3;
            rows[selected] += 1;
            rows[selected + 1] += 10;
            const expected = new Uint32Array([
              ...rows,
              rows[1],
              rows[4],
              rows[selected],
              rows[selected + 1],
            ]);
            let actual;
            if (asynchronous) actual = await guest.callAsync("answer", input);
            else actual = guest.call("answer", input);
            assert.deepEqual(actual, expected);
          }
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler?.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

const plainWriterSource = `type Span is data = $Span {start: U32, count: U32}
const append = func (output: ResizeArray U32) -> (input: &[U32]): Span => return do:
  let start = @storage.length output
  let count = @storage.length input
  for value in input:
    @storage.push output value
  return $Span {start, count}
entry const answer = func (input: U32): Array U32 => return do:
  let source: Array U32 = #[input, 7]
  let first: ResizeArray U32 = #[11]
  let second: ResizeArray U32 = #[13]
  let a = append first (&source[0..2])
  let b = append second (&source[0..2])
  let c = append first (&first[0..3])
  return #[a.start, a.count, b.start, b.count, c.start, c.count,
    first[0], first[1], first[2], first[3], first[4], first[5],
    second[0], second[1], second[2]]
`;

const projectedWriterSource = `type Point is data = $Point {x: U32}
type Pose is data = $Pose {position: Point}
const advance = func (point: Point): Point => return $Point {x: @u32.add point.x 1}
const amend = func (rows: ResizeArray U32) -> (pose: Pose): Pose => return do:
  pose.position := advance self
  @storage.push rows pose.position.x
  return pose
entry const answer = func (input: U32): Array U32 => return do:
  let first: ResizeArray U32 = #[input]
  let second: ResizeArray U32 = #[input]
  let a = amend first ($Pose {position: $Point {x: input}})
  let b = amend second ($Pose {position: $Point {x: @u32.add input 10}})
  return #[a.position.x, first[1], b.position.x, second[1]]
`;
const writerFixtures = [
  {
    name: "return plain spans",
    source: plainWriterSource,
    definitions: 2,
    expected: (input: number) => [
      1,
      2,
      1,
      2,
      3,
      3,
      11,
      input,
      7,
      11,
      input,
      7,
      13,
      input,
      7,
    ],
  },
  {
    name: "bind projected update self to its nominal payload",
    source: projectedWriterSource,
    definitions: 1,
    expected: (input: number) => [input + 1, input + 1, input + 11, input + 11],
  },
];

for (const codegenTier of ["development", "optimized"] as const) {
  for (const fixture of writerFixtures) {
    Deno.test(`symbolic owner graph writers ${fixture.name} (${codegenTier})`, async () => {
      const directory = await Deno.makeTempDir({
        prefix: "blot-owner-graph-span-",
      });
      const entry = `${directory}/main.blot`;
      let compiler:
        | Awaited<ReturnType<typeof createZigProjectCompiler>>
        | undefined;
      try {
        compiler = await createZigProjectCompiler({
          executable: Deno.args[0],
          entry,
          prelude: null,
          cacheDirectory: false,
          codegenTier,
          startupTimeoutMs: 5_000,
        });
        const built = await compiler.build({
          sources: { [entry]: fixture.source },
          signal: AbortSignal.timeout(5_000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        assert.equal(work.scoped_owner_graph_definitions, fixture.definitions);
        assert(work.scoped_function_plan_hits >= 1, JSON.stringify(work));
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const input of [0, 1, 42, 0xffffffff, 0]) {
              const expected = new Uint32Array(fixture.expected(input));
              let actual;
              if (asynchronous) actual = await guest.callAsync("answer", input);
              else actual = guest.call("answer", input);
              assert.deepEqual(actual, expected);
            }
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await compiler?.dispose();
        await Deno.remove(directory, { recursive: true });
      }
    });
  }
}
