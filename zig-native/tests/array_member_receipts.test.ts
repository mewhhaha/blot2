import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

Deno.test("shape only member calls retain method edits open elements and captured callback behavior", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-shape-member-" });
  const entry = `${directory}/main.blot`;
  const prelude = `${directory}/prelude.blot`;
  const library = await Deno.readTextFile(
    new URL("../../std/prelude.blot", import.meta.url),
  );
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude,
        codegenTier,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [sibling, extra, count] of [[1, 0, 2], [2, 0, 2], [3, 1, 3], [
            4,
            -1,
            0,
          ], [5, 0, 2]]
        ) {
          let body = "@array.length values";
          if (extra === 1) body = `@u32.add 1 (${body})`;
          if (extra === -1) body = "missing_name";
          const sources = {
            [prelude]:
              `${library}\nconst Array.measure: Array a -> U32 = func values => return ${body}\n`,
            [entry]: `
const make = func seed => return {holes: #[], callback: func value => return @u32.add seed value}
const rows = #[make 11, make 22]
const measured = do:
  let total = 0
  for index in 0..8:
    total := @u32.add total rows.measure
  break total
entry const answer = measured
entry const callback = func (value: U32) => return rows[0].callback value
entry const sibling = ${sibling}
`,
          };
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.equal(extra, -1, JSON.stringify(expected));
              assert.ok(!actual.success && !expected.success);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.notEqual(extra, -1);
            assert.deepEqual(actual.bytes, expected.bytes);
            assert.equal(
              actual.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            const guest = await instantiateGuest(actual.bytes);
            try {
              assert.equal(guest.read("answer"), count * 8);
              assert.equal(guest.call("callback", 31), 42);
              assert.equal(guest.read("sibling"), sibling);
            } finally {
              await guest.dispose();
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

Deno.test("array member receipts preserve executed sibling, method, input and failed edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-member-receipts-" });
  const entry = `${directory}/main.blot`;
  const prelude = `${directory}/prelude.blot`;
  const library = await Deno.readTextFile(
    new URL("../../std/prelude.blot", import.meta.url),
  );
  await Deno.writeTextFile(
    prelude,
    library + "\nconst Array.count = func values => return @array.length values\n",
  );
  let expression = "@array.length values";
  for (let index = 0; index < 80; index++) {
    expression = `@u32.add 0 (${expression})`;
  }
  const source = (
    sibling: string,
    body = expression,
    input = "#[]",
  ) =>
    `const Array.count = func values => return ${body}
entry const warm: U32 = #[].count
entry const result: U32 = ${input}.count
entry const sibling = ${sibling}
`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude,
  });
  try {
    for (
      const [revision, [text, answer]] of [
        [source("1"), 0],
        [source("2"), 0],
        [source("2", "@u32.add 1 (@array.length values)"), 1],
        [source("2", expression, "#[#[]]"), 1],
        [source("missing_name"), null],
        [source("2"), 0],
      ].entries()
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude,
      });
      try {
        const lines = (text as string).split("\n");
        const method = lines.shift();
        const sources = {
          [entry]: lines.join("\n"),
          [prelude]: library + "\n" + method + "\n",
        };
        const ordinary = await fresh.build({ sources });
        const retained = await compiler.build({ sources });
        assert.equal(retained.success, ordinary.success);
        if (!retained.success || !ordinary.success) {
          assert.ok(!retained.success && !ordinary.success);
          assert.deepEqual(retained.diagnostics, ordinary.diagnostics);
          if (answer !== null) console.error(ordinary.diagnostics);
          assert.equal(answer, null);
          continue;
        }
        assert.deepEqual(retained.bytes, ordinary.bytes);
        assert.equal(
          retained.stats.nativeWorkSteps,
          ordinary.stats.nativeWorkSteps,
        );
        if (revision === 1) {
          const traffic = retained.stats.selectedQueries as Record<
            string,
            number
          >;
          assert.ok(traffic.reused >= 1, JSON.stringify(traffic));
          assert.ok(traffic.collected_visits_removed >= 2);
        }
        const guest = await instantiateGuest(retained.bytes);
        try {
          assert.equal(guest.read("result"), answer);
        } finally {
          await guest.dispose();
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await compiler.close();
    await Deno.remove(directory, { recursive: true });
  }
});
