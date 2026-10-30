import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";
import { deepStrictEqual as equal, match, ok } from "node:assert/strict";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import {
  checkGuest,
  program,
  variant,
} from "./effectful_dictionary_closure_helpers.ts";

for (const helper of ["func value => return Render.show value", "Render.show"]) {
  for (const asynchronous of [false, true]) {
    Deno.test(`effectful ${helper} preserves the first application before returned closure calls (${asynchronous})`, async () => {
      await compileAndRun(variant(helper), async (guest) => {
        await checkGuest(guest, asynchronous);
      }, { prelude: "none", asynchronous });
    });
  }
}

Deno.test("effectful dictionary closure rows cannot be erased or moved into callback parameters", async () => {
  await compileExpectedFailure(
    program.replace("(U32 -> U32) ! {Read}", "(U32 -> U32) ! {}"),
    "effect_mismatch",
    undefined,
    { prelude: "none" },
  );
  await compileExpectedFailure(
    `effect Read: Unit -> U32
const consume: (Unit -> U32 ! {}) -> U32 = func callback => return callback ()
entry const answer: Unit -> U32 ! {Read} = func unit => return consume Read
`,
    "effect_mismatch",
    undefined,
    { prelude: "none" },
  );
});

Deno.test("effectful callback mismatch names the expected and actual argument in both tiers", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const invalid = `effect Read: Unit -> U32
const consume: (Unit -> U32 ! {}) -> U32 = func callback => return callback ()
entry const answer: Unit -> U32 = func unit => return consume Read
`;
  const corrected = invalid.replace("consume Read", "consume (func () => return 42)");
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude,
        codegenTier,
      });
      try {
        const bad = await compiler.build({ sources: { [entry]: invalid } });
        ok(!bad.success);
        const diagnostic = bad.diagnostics[0];
        equal(diagnostic.code, "effect_mismatch");
        equal(diagnostic.filename, entry);
        const start = invalid.indexOf("consume Read");
        equal([diagnostic.start, diagnostic.end], [
          start,
          start + "consume Read".length,
        ]);
        equal(
          diagnostic.contexts?.map(({ kind, start, end }) => [kind, start, end]),
          [
            ["callee", start, start + "consume".length],
            ["argument", start + "consume ".length, start + "consume Read".length],
          ],
        );
        match(diagnostic.message, /expected argument: \(Unit -> U32\)/);
        match(diagnostic.message, /actual argument: \(Unit -> U32 ! \{Read/);
        const good = await compiler.build({ sources: { [entry]: corrected } });
        ok(good.success, JSON.stringify(good));
        const guest = await instantiateGuest(good.bytes);
        try {
          equal(guest.call("answer", null), 42);
        } finally {
          guest.dispose();
        }
        const again = await compiler.build({ sources: { [entry]: invalid } });
        ok(!again.success);
        equal(again.diagnostics[0].message, diagnostic.message);
        equal(again.diagnostics[0].contexts, diagnostic.contexts);
        const recovered = await compiler.build({
          sources: { [entry]: corrected },
        });
        ok(recovered.success, JSON.stringify(recovered));
        equal(recovered.bytes, good.bytes);
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
