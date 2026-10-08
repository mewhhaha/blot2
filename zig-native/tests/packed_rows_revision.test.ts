import { deepStrictEqual, ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("packed array layouts follow dependency edits and failed revision recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-packed-revision-" });
  const entry = `${directory}/main.blot`, dependency = `${directory}/rows.blot`;
  const stdRoot = new URL("../../std", import.meta.url).pathname;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    stdRoot,
    prelude: `${stdRoot}/prelude.blot`,
  };
  const main = `import { make, score, generated } from "./rows"
entry const answer = fn value => score (make value)
entry const listed = fn value => score (@array.from_list (@list.from_array (make value)))
entry const callback = fn count => (generated count)[count - 1].y
`;
  const scalar = `const saved = #[{z: 7, a: 3}]
const make = fn value => #[{a: value, z: value + 1}, ...saved]
const score = fn rows => rows[0].a + rows[0].z + rows[1].z
`;
  const cases = [
    { source: scalar, answer: 48 },
    { source: scalar.replace("z: 7", "z: 9"), answer: 50 },
    { source: "const broken = absent\n", answer: null },
    {
      source: `const make = fn value => #[{a: value, z: #[value + 2]}]
const score = fn rows => rows[0].a + rows[0].z[0]
`,
      answer: 42,
    },
    {
      source:
        `const make = fn value => #[{z: value + 2, b: value + 1, a: value}]
const score = fn rows => rows[0].a + rows[0].b + rows[0].z
`,
      answer: 63,
    },
    { source: scalar, answer: 48 },
  ];
  const retained = await createZigProjectCompiler(options);
  try {
    for (const { source, answer } of cases) {
      const sources = {
        [entry]: main,
        [dependency]: source +
          `\nconst generated = fn count => @array.generate count (fn i => {x: i, y: i + ${
            answer ?? 0
          }})\n`,
      };
      const built = await retained.build({ sources });
      if (answer === null) {
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
          deepStrictEqual(guest.call("answer", 20), answer);
          deepStrictEqual(guest.call("listed", 20), answer);
          deepStrictEqual(guest.call("callback", 3), answer + 2);
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
