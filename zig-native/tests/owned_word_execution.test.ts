import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const borrowed =
  `type Row is data = $Row {target: Ref U32, window: &[U32], cursor: Link U32}
type Choice is data = $Direct (Ref U32) | $Window (&[U32]) | $Cursor (Link U32)
const target = func (rows: Array Row): Ref U32 => return rows[0].target
const window = func (rows: Array Row): &[U32] => return rows[0].window
const cursor = func (rows: Array Row): Link U32 => return rows[0].cursor
const choose = func (rows: Array Row) -> (kind: U32): Choice => return
  if @u32.eq kind 0 then $Direct rows[0].target else
  if @u32.eq kind 1 then $Window rows[0].window else $Cursor rows[0].cursor
const touch_ref = func (value: Ref U32): U32 => return do:
  @storage.write value (@storage.load value)
  return @storage.load value
const touch_link = func (value: Link U32): U32 => return do:
  @storage.write value (@storage.load value)
  return @storage.load value
const observe = func (choice: Choice): U32 => return case choice of
  $Direct value => touch_ref value
  $Window value => value[0]
  $Cursor value => touch_link value
entry const answer = func (input: U32): Array U32 => return do:
  let a: Array U32 = #[input, @u32.add input 1]
  let b: Array U32 = #[@u32.add input 10, @u32.add input 11]
  let links_a: GrowArray U32 = #[@u32.add input 20]
  let links_b: GrowArray U32 = #[@u32.add input 30]
  let first: Array Row = #[$Row {target: @storage.at a 0, window: &a[0..2], cursor: @storage.link links_a 0}]
  let second: Array Row = #[$Row {target: @storage.at b 0, window: &b[0..2], cursor: @storage.link links_b 0}]
  let joined = if @u32.eq (@u32.rem input 2) 0 then first else second
  let ref = target joined
  let view = window joined
  let link = cursor joined
  let choice = choose joined (@u32.rem input 3)
  @storage.write ref (@u32.add (@storage.load ref) 2)
  @storage.write link (@u32.add (@storage.load link) 3)
  let again = target second
  return #[a[0], b[0], links_a[0], links_b[0], @storage.load ref, view[0], view[1], @storage.load link, observe choice, @storage.load again]
`;
const cycle = `type Node is data = $End | $Next (Ref Node)
const walk = func (start: Ref Node): U32 => return case @storage.load start of
  $End => 0
  $Next first => case @storage.load first of
    $End => 0
    $Next second => case @storage.load second of
      $End => 0
      $Next last => 3
entry const answer = func (input: U32): Array U32 => return do:
  let first: Array Node = #[$End]
  let second: Array Node = #[$End]
  first[0] := $Next (@storage.at second 0)
  second[0] := $Next (@storage.at first 0)
  let a = walk (@storage.at first 0)
  let b = walk (@storage.at second 0)
  first[0] := $End
  let c = walk (@storage.at second 0)
  return #[a, b, c, input]
`;
const floating = `const flip = func (rows: Array F32): F32 => return do:
  rows[0] := @f32.neg self
  return @storage.read rows 0
entry const answer = func (input: U32): Array U32 => return do:
  let (value, unused_a, unused_b, unused_c) = @simd.u32x4.from_bits (input,input,input,input)
  let rows: Array F32 = #[value]
  let first = flip rows
  let second = flip rows
  let (a,b,c,d) = @simd.f32x4.bits (first,second,rows[0],value)
  return #[a,b,c,d]
`;
function boundary(fields: number, scalar: boolean): string {
  const members = Array.from(
    { length: fields },
    (_, i) => `p${i}: @u32.add input ${i}`,
  ).join(", ");
  let resultType = "Ref U32";
  let resultValue = "@storage.at owner 0";
  let invocation = "@storage.load (read access)";
  if (scalar) {
    resultType = "U32";
    resultValue = "@storage.read owner 0";
    invocation = "read access";
  }
  let write = "";
  if (scalar) write = "owner[0] := @u32.add self alias.p0";
  return `const read = func access: ${resultType} => return do:
  let alias = access
  let owner: Array U32 = alias.owner
  ${write}
  return ${resultValue}
entry const answer = func (input: U32): Array U32 => return do:
  let owner: Array U32 = #[input]
  let access = {owner, ${members}}
  return #[${invocation}, ${invocation}]
`;
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`owned words retain graph descriptors and bounded signatures (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-owned-words-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      for (
        const fixture of [
          {
            name: "floating",
            source: floating,
            expected: (
              input: number,
            ) => [(input ^ 0x80000000) >>> 0, input, input, input],
            packed: false,
          },
          {
            name: "borrowed",
            source: borrowed,
            expected: (input: number) => {
              const selected = input % 2;
              const rows = [input, input + 10, input + 20, input + 30];
              rows[selected] += 2;
              rows[selected + 2] += 3;
              let choice = rows[selected + 2];
              if (input % 3 !== 2) choice = rows[selected];
              return [
                ...rows,
                rows[selected],
                rows[selected],
                input + selected * 10 + 1,
                rows[selected + 2],
                choice,
                rows[1],
              ];
            },
            packed: false,
          },
          {
            name: "cycles",
            source: cycle,
            expected: (input: number) => [3, 3, 0, input],
            packed: false,
          },
          {
            name: "borrowed512",
            source: boundary(507, false),
            expected: (input: number) => [input, input],
            packed: false,
          },
          {
            name: "borrowed513",
            source: boundary(508, false),
            expected: (input: number) => [input, input],
            packed: true,
          },
          {
            name: "scalar512",
            source: boundary(508, true),
            expected: (input: number) => [input * 2, input * 3],
            packed: false,
          },
          {
            name: "scalar513",
            source: boundary(509, true),
            expected: (input: number) => [input * 2, input * 3],
            packed: true,
          },
        ]
      ) {
        const built = await compiler.build({
          sources: { [entry]: fixture.source },
        });
        assert(built.success, fixture.name + ":" + JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        if (fixture.packed) {
          assert.equal(work.scoped_owned_word_calls, 0, fixture.name);
          assert(
            work.scoped_owned_packed_calls >= 1,
            fixture.name + JSON.stringify(work),
          );
        } else {assert(
            work.scoped_owned_word_calls >= 1,
            fixture.name + JSON.stringify(work),
          );}
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (
              const input of [
                0,
                1,
                2,
                17,
                0x80000000,
                0x3fc00000,
                0x7f800000,
                0xff800000,
                0x7fa12345,
                0xfffffffe,
                0,
              ]
            ) {
              let actual;
              if (asynchronous) actual = await guest.callAsync("answer", input);
              else actual = guest.call("answer", input);
              assert.deepEqual(
                actual,
                new Uint32Array(fixture.expected(input)),
                fixture.name,
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
