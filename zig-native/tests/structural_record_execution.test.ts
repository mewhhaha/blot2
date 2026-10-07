import { deepStrictEqual, ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("structural records preserve shapes, field order and type-changing nested updates", async () => {
  await compileAndRun(
    `
type Point = { x: U32, y: F32 }
type Box a is data = #Box a
const read = fn record => record.x
const replace = fn record => do:
  record.x := #True
  return record
const identity = fn (point: Point) => point
entry const answer = fn (value: U32) => do:
  let original = { y: 2.5, x: value }
  let point = identity original
  let { y, x } = point
  let updated = replace original
  let nested = { point, retained: 40 }
  nested.point.x := 2.0
  let { point: { x: fraction } } = nested
  let #Box boxed = #Box original
  return if updated.x then @f32.add fraction (@u32.to_f32 (@u32.add nested.retained (@u32.sub (read boxed) x))) else y
entry const reordered = fn () => read { y: #True, x: 42 }
entry const array = fn () => do:
  let values: Array { x: U32 } = #[{ x: 42 }]
  return (@array.get values 0).x
`,
    (guest) => {
      for (const value of [0, 41, 0xffffffff]) {
        equal(
          guest.call("answer", value),
          42,
        );
      }
      equal(guest.call("reordered", null), 42);
      equal(guest.call("array", null), 42);
    },
    { prelude: "none" },
  );
});

Deno.test("structural record construction evaluates fields once in source order with latent callbacks", async () => {
  await compileAndRun(
    `
const invoke = fn record => record.callback ()
entry const answer = fn (send: U32 -> U32 ! {Foreign}) => do:
  use record <- do:
    return { z: send 1, a: send 2, callback: fn () => send 3 }
  use last <- invoke record
  return @u32.add record.z (@u32.add record.a last)
`,
    (guest) => {
      const calls: number[] = [];
      const send = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value) => {
          calls.push(value);
          return value;
        },
      });
      equal(guest.call("answer", send), 6);
      equal(calls.join(","), "1,2,3");
    },
    { prelude: "none" },
  );
});

Deno.test("structural shapes reject duplicates, absent fields and mismatched exact annotations", async () => {
  for (
    const [source, code] of [
      ["entry const answer = ({ x: 1, x: 2 }).x\n", "duplicate_record_field"],
      ["entry const answer = ({ x: 1 }).y\n", "missing_member"],
      [
        "const exact: { x: U32 } = { x: 1, y: 2 }\nentry const answer = exact.x\n",
        "type_mismatch",
      ],
    ]
  ) await compileExpectedFailure(source, code, undefined, { prelude: "none" });
});

Deno.test("generic record extension preserves fields and replaces their types in constants and runtime code", async () => {
  await compileAndRun(
    `
type Merge [a, b, c] is contract = { merge a b c }
const combine: a -> b -> c where { Merge [a, b, c] } = fn left => fn right => @record.merge left right
const extend = fn record => combine record { extra: 2 }
const frozen = extend { x: 40, callback: fn value => @u32.add value 1 }
entry const answer = fn (value: U32) => do:
  let original = { y: 40, x: value }
  let changed = combine original { x: 2.0, z: #True }
  let empty = combine {} (combine changed {})
  return if empty.z then @f32.add empty.x (@u32.to_f32 empty.y) else 0.0
entry const constant = fn () => @u32.add frozen.x frozen.extra
entry const callback = fn () => frozen.callback 41
entry const repeated = fn () => do:
  let point = { x: 0, y: 2 }
  for index in 0 .. 40:
    point := @record.merge point { x: @u32.add point.x 1 }
  return @u32.add point.x point.y
`,
    (guest) => {
      equal(guest.call("answer", 0xffffffff), 42);
      equal(guest.call("constant", null), 42);
      equal(guest.call("callback", null), 42);
      equal(guest.call("repeated", null), 42);
    },
    { prelude: "none" },
  );
});

Deno.test("record merge evaluates overridden fields and retains effectful callbacks", async () => {
  await compileAndRun(
    `
const combine = fn left => fn right => @record.merge left right
entry const answer = fn (send: U32 -> U32 ! {Foreign}) => do:
  use result <- do:
    return combine { x: send 1, z: send 2 } { x: send 3, callback: fn () => send 4 }
  use last <- result.callback ()
  return @u32.add result.x (@u32.add result.z last)
`,
    (guest) => {
      const calls: number[] = [];
      const send = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value) => {
          calls.push(value);
          return value;
        },
      });
      equal(guest.call("answer", send), 9);
      equal(calls.join(","), "1,2,3,4");
    },
    { prelude: "none" },
  );
});

Deno.test("record extension rejects non-records and omitted written merge requirements", async () => {
  for (
    const source of [
      "entry const answer = @record.merge 42 { x: 1 }\n",
      "type Box is data = #Box { x: U32 }\nentry const answer = @record.merge (#Box 42) {}\n",
    ]
  ) {
    await compileExpectedFailure(source, "type_mismatch", undefined, {
      prelude: "none",
    });
  }
  await compileExpectedFailure(
    "const merge: a -> b -> c where { type_rep a } = fn left => fn right => @record.merge left right\nentry const answer = 42\n",
    "missing_predicate",
    undefined,
    { prelude: "none" },
  );
});

Deno.test("structural record contracts survive imports, dependency relocation and retained failure recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/record.blot`;
  const bundle = `${directory}/records.blotdep`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
  const declaration = `
type Point = { z: U32, a: F32 }
type Merge [a, b, c] is contract = { merge a b c }
const combine: a -> b -> c where { Merge [a, b, c] } = fn left => fn right => @record.merge left right
const make = fn (value: U32) => { a: 2.0, z: value }
const frozen = combine (make 40) { z: 40 }
const read = fn (point: Point) => @f32.add (@u32.to_f32 point.z) point.a
`;
  const application = `
import { Point, combine, make, frozen, read } from "./record"
entry const answer = fn (value: U32) => do:
  let p: Point = combine { z: value } { a: 2.0 }
  let record = combine { z: #False, kept: p.a } { z: frozen.z }
  return read { a: record.kept, z: record.z }
entry const callback = fn (send: U32 -> U32 ! {Foreign}) => do:
  let record = combine { a: 2.0 } { call: fn () => send 41 }
  return record.call ()
`;
  await Deno.writeTextFile(entry, application);
  await Deno.writeTextFile(library, declaration);
  const compiler = await createZigProjectCompiler({
    entry,
    executable,
  });
  async function run(bytes: Uint8Array<ArrayBuffer>, expected: number) {
    const guest = await instantiateGuest(bytes);
    try {
      equal(guest.call("answer", 99), expected);
      const send = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value) => value + 1,
      });
      equal(guest.call("callback", send), 42);
    } finally {
      guest.dispose();
    }
  }
  try {
    const first = await compiler.build();
    ok(first.success, JSON.stringify(first));
    await run(first.bytes, 42);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    ok(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    const bundled = await createZigProjectCompiler({
      entry,
      executable,
      dependencies: bundle,
    });
    try {
      const build = await bundled.build();
      ok(build.success, JSON.stringify(build));
      deepStrictEqual(build.bytes, first.bytes);
      await run(build.bytes, 42);
    } finally {
      await bundled.dispose();
    }
    const changed = await compiler.build({
      sources: { [library]: declaration.replace("{ z: 40 }", "{ z: 41 }") },
    });
    ok(changed.success, JSON.stringify(changed));
    await run(changed.bytes, 43);
    const broken = await compiler.build({
      sources: { [library]: declaration.replace("{ z: 40 }", "{ z: #False }") },
    });
    ok(!broken.success);
    equal(broken.revision, changed.revision);
    const recovered = await compiler.build();
    ok(recovered.success, JSON.stringify(recovered));
    deepStrictEqual(recovered.bytes, first.bytes);
    const fresh = await createZigProjectCompiler({
      entry,
      executable,
    });
    try {
      const rebuilt = await fresh.build();
      ok(rebuilt.success, JSON.stringify(rebuilt));
      deepStrictEqual(rebuilt.bytes, recovered.bytes);
    } finally {
      await fresh.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
