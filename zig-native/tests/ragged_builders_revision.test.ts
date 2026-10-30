import { deepStrictEqual, ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("ragged retained bounds filters captures payload and primitive wrapper edits match fresh recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-ragged-revision-" });
  const entry = `${directory}/main.blot`;
  const prelude = `${directory}/prelude.blot`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude,
    stdRoot: new URL("../../std", import.meta.url).pathname,
  };
  const wrappers = `infix 30 (>) = gt
infix 30 (<) = lt
infixl 70 (*) = mul
const gt = func left => return func right => return @type.call "gt" left right
const lt = func left => return func right => return @type.call "lt" left right
const mul = func left => return func right => return @type.call "mul" left right
const U32.lt = func left => return func right => return @u32.lt left right
const U32.gt = func left => return func right => return U32.lt right left
const U32.mul = func left => return func right => return @u32.mul left right
`;
  const main = `entry const run = func seed => return do:
  let values = #[0,1,2,3,4]
  let bound = seed
  break #[x * x | x <- values, x > bound, x < 4]
entry const triangle = func count => return do:
  let values: List U32 = []
  for x in 0..count:
    for y in 0..x:
      values := @list.append self (@u32.add (@u32.mul x 10) y)
  break @array.from_list values
`;
  const cases = [
    { main, wrappers, selected: [4, 9], triangle: [10, 20, 21] },
    { main, wrappers, selected: [4, 9], triangle: [10, 20, 21] },
    {
      main: main.replace("bound = seed", "bound = @u32.add seed 1"),
      wrappers,
      selected: [9],
      triangle: [10, 20, 21],
    },
    {
      main: main.replace("x < 4", "x < 3"),
      wrappers,
      selected: [4],
      triangle: [10, 20, 21],
    },
    {
      main: main.replace("#[x * x |", "#[@u32.add (x * x) 1 |"),
      wrappers,
      selected: [5, 10],
      triangle: [10, 20, 21],
    },
    {
      main: main.replace("y in 0..x", "y in 0..@u32.add x 1"),
      wrappers,
      selected: [4, 9],
      triangle: [0, 10, 11, 20, 21, 22],
    },
    {
      main,
      wrappers: wrappers.replace("U32.lt right left", "U32.lt left right"),
      selected: [0],
      triangle: [10, 20, 21],
    },
    {
      main: "entry const broken = absent\n",
      wrappers,
      selected: null,
      triangle: null,
    },
    { main, wrappers, selected: [4, 9], triangle: [10, 20, 21] },
  ];
  const retained = await createZigProjectCompiler(options);
  try {
    for (const revision of cases) {
      const sources = { [entry]: revision.main, [prelude]: revision.wrappers };
      const built = await retained.build({ sources });
      if (revision.selected === null) {
        ok(!built.success);
        continue;
      }
      ok(built.success, JSON.stringify(built));
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        ok(expected.success, JSON.stringify(expected));
        deepStrictEqual(built.bytes, expected.bytes);
        const guest = await instantiateGuest(built.bytes);
        try {
          deepStrictEqual(
            guest.call("run", 1),
            Uint32Array.from(revision.selected),
          );
          deepStrictEqual(
            guest.call("triangle", 3),
            Uint32Array.from(revision.triangle!),
          );
        } finally {
          guest.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("ragged imported controls preserve qualified identity through staging and retained edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-ragged-import-" });
  const entry = `${directory}/main.blot`;
  const prelude = `${directory}/prelude.blot`;
  const library = `${directory}/limits.blot`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude,
    stdRoot: new URL("../../std", import.meta.url).pathname,
  };
  const main = `import { limit } from "./limits"
entry const run = func () => return do:
  let result: List U32 = []
  for x in 0..3:
    if @u32.lt x limit:
      result := [...self, x]
  break @array.from_list result
const folded = run ()
entry const staged = func () => return folded
`;
  const padding = Array.from(
    { length: 6 },
    (_, index) => `const padding${index}: U32 = 4\n`,
  ).join("");
  const retained = await createZigProjectCompiler(options);
  try {
    for (const limit of [4, 1, 0, 4]) {
      const sources = {
        [entry]: main,
        [prelude]: "",
        [library]: `${padding}const limit: U32 = ${limit}\n`,
      };
      const built = await retained.build({ sources });
      ok(built.success, JSON.stringify(built));
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        ok(expected.success, JSON.stringify(expected));
        deepStrictEqual(built.bytes, expected.bytes);
        const guest = await instantiateGuest(built.bytes);
        try {
          const values = Uint32Array.from([0, 1, 2].filter((x) => x < limit));
          deepStrictEqual(guest.call("run", null), values);
          deepStrictEqual(guest.call("staged", null), values);
        } finally {
          guest.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
