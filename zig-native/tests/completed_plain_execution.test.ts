import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest, readGuestAbi } from "../../compiler/guest.ts";

const commonSource = `type IVec is data = $IVec {x: U32, y: U32}
type FVec is data = $FVec {x: F32, y: F32}
type Pose a is data = $Pose {position: a, stamp: U32}
const IVec.add = func (left: IVec) -> (right: IVec): IVec => return $IVec {x: @u32.add left.x right.x, y: @u32.add left.y right.y}
const FVec.add = func (left: FVec) -> (right: FVec): FVec => return $FVec {x: @f32.add left.x right.x, y: @f32.add left.y right.y}
const IVec.turn = func (value: IVec): IVec => return $IVec {x: value.y, y: value.x}
const FVec.turn = func (value: FVec): FVec => return $FVec {x: value.y, y: @f32.neg value.x}
const translate = func (pose: Pose IVec) -> (shift: IVec): Pose IVec => return do:
  pose.position := @type.call "add" self shift
  return pose
const rotate = func (pose: Pose IVec): Pose IVec => return do:
  pose.position := self.turn
  return pose
const translate_f = func (pose: Pose FVec) -> (shift: FVec): Pose FVec => return do:
  pose.position := @type.call "add" self shift
  return pose
const rotate_f = func (pose: Pose FVec): Pose FVec => return do:
  pose.position := self.turn
  return pose
const keep: a -> a = func value => return value
const scratch = func (value: {x: U32, y: U32}): {x: U32, y: U32} => return do:
  let words: Array U32 = #[value.x, value.y]
  value.x := @u32.add words[0] words[1]
  return value
`;

const callerSource = `import * as common from "trial/common"
const integer = func (input: U32): Array U32 => return do:
  let before = common.keep ($common.Pose {position: $common.IVec {x: input, y: @u32.add input 1}, stamp: 17})
  let after = common.rotate (common.translate before ($common.IVec {x: 3, y: 5}))
  let scratch = common.scratch {x: input, y: 9}
  return #[before.position.x, before.position.y, after.position.x, after.position.y, after.stamp, scratch.x, scratch.y]
const floating = func (bits: U32): Array U32 => return do:
  let (input, ignored_a, ignored_b, ignored_c) = @simd.u32x4.from_bits (bits,bits,bits,bits)
  let before = common.keep ($common.Pose {position: $common.FVec {x: input, y: @f32.neg input}, stamp: 23})
  let after = common.rotate_f before
  let shifted = common.translate_f before ($common.FVec {x: 1.0, y: 2.0})
  let (a,b,c,d) = @simd.f32x4.bits (before.position.x,before.position.y,after.position.x,after.position.y)
  let (e,f,g,h) = @simd.f32x4.bits (shifted.position.x,shifted.position.y,0.0,0.0)
  return #[a,b,c,d,e,f,shifted.stamp]
`;

const mainSource = `import * as left from "trial/left"
import * as right from "trial/right"
entry const integer = func (input: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[input]
  let a = left.integer marker[0]
  let b = right.integer input
  return #[a[0],a[1],a[2],a[3],a[4],a[5],a[6],b[0],b[1],b[2],b[3],b[4],b[5],b[6]]
entry const floating = func (bits: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[bits]
  let a = left.floating marker[0]
  let b = right.floating bits
  return #[a[0],a[1],a[2],a[3],a[4],a[5],a[6],b[0],b[1],b[2],b[3],b[4],b[5],b[6]]
`;

const persistentSource = `const pool: ResizeArray U32 = #[4]
const peek = func (value: {x: U32}): {x: U32} => return do:
  value.x := @u32.add self pool[0]
  return value
entry const answer = func (input: U32): Array U32 => return do:
  let a = peek {x: input}
  @storage.write (@storage.at pool 0) (@u32.add pool[0] 10)
  let b = peek {x: input}
  return #[a.x,b.x,pool[0]]
`;

const hostSource =
  `const invoke = func (host: U32 -> U32 ! {Foreign}) -> (value: {x: U32}): U32 ! {Foreign} => return do:
  value.x := @u32.add self 1
  use reply <- host value.x
  return @u32.add reply value.x
entry const answer = func (host: U32 -> U32 ! {Foreign}): U32 ! {Foreign} => return do:
  let marker: GrowArray U32 = #[7]
  use reply <- invoke host {x: marker[0]}
  return reply
`;

const escapeSource = `const bad = func (input: U32): Ref U32 => return do:
  let words: Array U32 = #[input]
  return @storage.at words 0
entry const answer = func (input: U32): U32 => return @storage.load (bad input)
`;

const floatBytes = new DataView(new ArrayBuffer(4));
function fromBits(bits: number): number {
  floatBytes.setUint32(0, bits);
  return floatBytes.getFloat32(0);
}
function toBits(value: number): number {
  floatBytes.setFloat32(0, value);
  return floatBytes.getUint32(0);
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`completed plain plans preserve nominal updates and typed bits across modules (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-plain-plans-" });
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
          [entry]: mainSource,
          [`${directory}/common.blot`]: commonSource,
          [`${directory}/left.blot`]: callerSource,
          [`${directory}/right.blot`]: callerSource,
        },
      });
      assert(built.success, JSON.stringify(built));
      assert(WebAssembly.validate(built.bytes));
      assert.equal(
        readGuestAbi(new WebAssembly.Module(built.bytes)).version,
        8,
      );
      const work = built.stats.workCounters as Record<string, number>;
      assert.equal(work.scoped_plain_plan_definitions, 5, JSON.stringify(work));
      assert.equal(work.scoped_owner_graph_definitions, 0);
      assert.equal(work.scoped_owner_graph_inputs, 0);
      assert(work.scoped_writer_cache_hits >= 5);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          for (const input of [0, 1, 17, 0xfffffffd, 0]) {
            let actual;
            if (asynchronous) actual = await guest.callAsync("integer", input);
            else actual = guest.call("integer", input);
            const values = [
              input,
              input + 1,
              input + 6,
              input + 3,
              17,
              input + 9,
              9,
            ];
            assert.deepEqual(actual, new Uint32Array([...values, ...values]));
          }
          for (
            const bits of [
              0,
              0x80000000,
              0x3fc00000,
              0xc0e80000,
              0x7f800000,
              0xff800000,
              1,
              0,
            ]
          ) {
            let actual;
            if (asynchronous) actual = await guest.callAsync("floating", bits);
            else actual = guest.call("floating", bits);
            const input = fromBits(bits);
            const negated = (bits ^ 0x80000000) >>> 0;
            const values = [
              bits,
              negated,
              negated,
              negated,
              toBits(input + 1),
              toBits(-input + 2),
              23,
            ];
            assert.deepEqual(actual, new Uint32Array([...values, ...values]));
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
  Deno.test(`completed plain plans keep hidden pools host effects and fresh borrows outside sharing (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-plain-fallback-",
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
      const persistent = await compiler.build({
        sources: { [entry]: persistentSource },
      });
      assert(persistent.success, JSON.stringify(persistent));
      const work = persistent.stats.workCounters as Record<string, number>;
      assert.equal(work.scoped_plain_plan_definitions, 0);
      assert.equal(work.scoped_completed_plan_rollbacks, 1);
      assert(work.scoped_completed_plan_discarded_expressions > 0);
      assert(WebAssembly.validate(persistent.bytes));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(persistent.bytes, {
          asynchronous,
        });
        try {
          let pool = 4;
          for (const input of [0, 7, 0xfffffffd, 0]) {
            let actual;
            if (asynchronous) actual = await guest.callAsync("answer", input);
            else actual = guest.call("answer", input);
            assert.deepEqual(
              actual,
              new Uint32Array([input + pool, input + pool + 10, pool + 10]),
            );
            pool += 10;
          }
        } finally {
          guest.dispose();
        }
      }
      const hostBuilt = await compiler.build({
        sources: { [entry]: hostSource },
      });
      assert(hostBuilt.success, JSON.stringify(hostBuilt));
      const hostWork = hostBuilt.stats.workCounters as Record<string, number>;
      assert.equal(hostWork.scoped_plain_plan_definitions, 0);
      assert.equal(hostWork.scoped_completed_plan_attempts, 0);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(hostBuilt.bytes, { asynchronous });
        try {
          const calls: number[] = [];
          const host = guest.capability({
            parameter: "U32",
            result: "U32",
            call: (value) => {
              assert.equal(typeof value, "number");
              calls.push(value as number);
              return (value as number) * 3;
            },
          });
          for (let round = 0; round < 2; round++) {
            let actual;
            if (asynchronous) actual = await guest.callAsync("answer", host);
            else actual = guest.call("answer", host);
            assert.equal(actual, 32);
          }
          assert.deepEqual(calls, [8, 8]);
        } finally {
          guest.dispose();
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

const boundarySource =
  `type Choice is data = $Count U32 | $Pair {x: U32, y: U32}
const floating = func (input: F32): F32 => return do:
  let row = {value: input}
  row.value := @f32.neg self
  return row.value
const unit = func (): Unit => return do:
  let values: Array U32 = #[1]
  values[0] := 2
  return ()
const aggregate = func (): {x: U32, y: U32} => return do:
  let row = {x: 2, y: 3}
  row.x := @u32.add self 5
  return row
const choose = func (flag: Bool) -> (input: U32): Choice => return do:
  let row = {value: input}
  row.value := @u32.add self 1
  if flag:
    return $Count row.value
  return $Pair {x: row.value, y: 17}
const total = func (input: U32): U32 => return do:
  let values: Array U32 = #[input, @u32.add input 1]
  return @u32.add values[0] values[1]
const local_ref = func (input: U32): U32 => return do:
  let value = input
  @storage.write (&value) (@u32.add input 5)
  return value
entry const answer = func (bits: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[bits]
  let (input,a,b,c) = @simd.u32x4.from_bits (bits,bits,bits,bits)
  let result = floating input
  let (output,d,e,f) = @simd.f32x4.bits (result,result,result,result)
  unit ()
  unit ()
  let record = aggregate ()
  let again = aggregate ()
  let first = total marker[0]
  let second = total (@u32.add marker[0] 1)
  let local = local_ref marker[0]
  let choice = choose (@u32.eq (@u32.rem bits 2) 0) bits
  let selected = case choice of
    $Count value => value
    $Pair {x,y} => @u32.add x y
  return #[output,record.x,record.y,again.x,again.y,first,second,local,marker[0],selected]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`completed plain word ABI preserves scalar floats nullary results variants scratch and references (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-plain-boundaries-",
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
        sources: { [entry]: boundarySource },
      });
      assert(built.success, JSON.stringify(built));
      assert(WebAssembly.validate(built.bytes));
      const work = built.stats.workCounters as Record<string, number>;
      assert.equal(work.scoped_plain_plan_definitions, 6);
      assert(work.scoped_plain_plan_hits >= 3);
      assert.equal(work.scoped_owner_graph_inputs, 0);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          for (
            const bits of [
              0,
              1,
              0x80000000,
              0x3fc00000,
              0x7fc01234,
              0xffffffff,
              0,
            ]
          ) {
            let actual;
            if (asynchronous) actual = await guest.callAsync("answer", bits);
            else actual = guest.call("answer", bits);
            let selected = bits + 1;
            if (bits % 2 !== 0) selected += 17;
            assert.deepEqual(
              actual,
              new Uint32Array([
                (bits ^ 0x80000000) >>> 0,
                7,
                3,
                7,
                3,
                bits * 2 + 1,
                bits * 2 + 3,
                bits + 5,
                bits,
                selected,
              ]),
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
