import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler/zig-out/bin/blotc", import.meta.url).pathname;

Deno.test("discarded Arrays inside nested collecting loops keep the checksum", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url),
    cacheDirectory: false,
  });
  try {
    const result = await compiler.build({
      sources: {
        [entry]: `
entry const run = func (count: U32) => return do:
  let rows = @array.generate 90 (func index => return #[index, index + 1])
  let checksum = 0
  for row in rows:
    let round = 0
    for ever:
      if round == count:
        break
      let discarded = @array.fill 8192 round
      checksum := self + discarded[8191]
      round := self + 1
    checksum := self + row[0] + row[1]
  break #[checksum, rows[89][0], rows[89][1]]
`,
      },
    });
    assert(result.success, JSON.stringify(result));
    const guest = await instantiateGuest(result.bytes);
    try {
      for (const count of [8, 8, 40, 200, 8, 200]) {
        assert.deepEqual(
          guest.call("run", count),
          Uint32Array.of(90 * count * (count - 1) / 2 + 8100, 89, 90),
        );
      }
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("unchanged variants preserve erased payload descriptors and aliases", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url),
    cacheDirectory: false,
  });
  try {
    const result = await compiler.build({
      sources: {
        [entry]: `
const change = func (candidate: Result [U32, Array U32]) : Result [U32, Array U32] => return Result.map (func value => return value + 1) candidate
entry const scalar = func (value: U32) => return Result.unwrap_or 42 (change ($Ok value))
entry const alias = func (value: U32) => return do:
  let child = #[value, value + 1]
  let candidate = $Err child
  let mapped = change candidate
  for index in 0..200:
    let pressure = @array.fill 8192 index
    if pressure[0] != index:
      @panic "lost pressure"
  break case mapped of
    $Ok _ => @panic "changed the variant"
    $Err same => #[same[0], child[1]]
`,
      },
    });
    assert(result.success, JSON.stringify(result));
    const guest = await instantiateGuest(result.bytes);
    try {
      for (const value of [0, 8192, 0xffff_fffe]) {
        assert.equal(guest.call("scalar", value), (value + 1) >>> 0);
        assert.deepEqual(
          guest.call("alias", value),
          Uint32Array.of(value, (value + 1) >>> 0),
        );
      }
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("borrowed reference returns preserve field aliases when their parent replaces the owning edge", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url),
    cacheDirectory: false,
  });
  try {
    const result = await compiler.build({
      sources: {
        [entry]: `
const identity = func value => return value
entry const run = func (count: U32) => return do:
  let fresh = #[7, 42]
  let direct = identity fresh
  let rows = @array.generate 2 (func index => return #[index, index + 1])
  let field = identity rows[0]
  rows := @array.set rows 0 #[90, 91]
  for index in 0..count:
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      @panic "lost pressure"
  break #[direct[1], field[0], field[1], rows[0][0], fresh[0]]
`,
      },
    });
    assert(result.success, JSON.stringify(result));
    const guest = await instantiateGuest(result.bytes);
    try {
      for (const count of [8, 200, 8, 200]) {
        assert.deepEqual(guest.call("run", count), Uint32Array.of(42, 0, 1, 90, 7));
      }
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("checked field updates preserve variant layouts aliases captures and retained edits in both tiers", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable,
        entry,
        codegenTier,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (const offset of [0, 10, 0]) {
          const sources = {
            [entry]: `
type Shape is data = $Small {child: Array U32, value: U32} | $Large {alpha: F32, child: Array U32, value: U32, tail: U32}
const replace = func (shape: Shape) => return do:
  shape.child := #[self[0] + 1 + ${offset}]
  shape.value := self + 2
  break shape
entry const run = func (mode: U32) => return do:
  let original = if mode == 0 then $Small {child: #[40], value: 7} else $Large {alpha: -0.0, child: #[40], value: 7, tail: 3}
  let captured = func () => return original.child[0]
  let changed = replace original
  for index in 0..32:
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      break #[0]
  break #[original.child[0], changed.child[0], captured (), original.value, changed.value]
entry const packed = func (value: U32) => return do:
  let rows = [{x: value, y: value + 1}]
  let original = rows
  rows := [{x: value + 40, y: value + 1}, ...self]
  let items = @array.from_list rows
  let before = items
  items[0] := {x: self.x + 1, y: self.y + 2}
  break #[(@array.from_list original)[0].x, (@array.from_list rows)[0].x, before[0].x, items[0].x, items[0].y]
entry const floating = func (value: F32) => return do:
  let original = $Large {alpha: value, child: #[40], value: 7, tail: 3}
  let changed = replace original
  let $Large {alpha, child: _, value: _, tail: _} = changed else:
    break 0.0
  break alpha
`,
          };
          const result = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert(result.success && expected.success, JSON.stringify(result));
            assert.deepEqual(result.bytes, expected.bytes);
            const guest = await instantiateGuest(result.bytes);
            try {
              for (const mode of [0, 1, 0, 1]) {
                assert.deepEqual(
                  Array.from(guest.call("run", mode) as Uint32Array),
                  [40, 41 + offset, 40, 7, 9],
                );
              }
              // `before` aliases `items`, so it sees the write (tasks/LANGUAGE_COHERENCE.md A7).
              assert.deepEqual(
                Array.from(guest.call("packed", 1) as Uint32Array),
                [1, 41, 42, 42, 4],
              );
              for (const value of [-0, 0, 1.25, -1.5]) {
                assert(Object.is(guest.call("floating", value), value));
              }
            } finally {
              guest.dispose();
            }
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("allocating loops compute their totals with ordinary and shared machine bodies", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    for (const shareMachineCode of [false, true]) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        shareMachineCode,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
      });
      try {
        const result = await compiler.build({
          sources: {
            [entry]: `
entry const run = func (count: U32) => return do:
  let kept = #[7, 11]
  let total = 0
  for index in 0..count:
    let pressure = @array.fill 8192 index
    total := self + pressure[8191]
  break total + kept[0] + kept[1]
entry const memory = func (value: U32) => return #[value]
`,
          },
        });
        assert(result.success, JSON.stringify(result));
        const guest = await instantiateGuest(result.bytes);
        try {
          for (let round = 0; round < 10; round++) {
            assert.equal(guest.call("run", 32), 514);
          }
        } finally {
          guest.dispose();
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
