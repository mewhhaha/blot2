import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

Deno.test("array member receipts preserve executed sibling, method, input and failed edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-member-receipts-" });
  const entry = `${directory}/main.blot`;
  const prelude = `${directory}/prelude.blot`;
  const library = await Deno.readTextFile(
    new URL("../../std/prelude.blot", import.meta.url),
  );
  await Deno.writeTextFile(
    prelude,
    library + "\nconst Array.count = fn values => @array.length values\n",
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
    `const Array.count = fn values => ${body}
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
