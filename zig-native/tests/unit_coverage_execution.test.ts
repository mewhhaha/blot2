import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

// Sixteen unchanged SourceCompiler controls are pinned in the Unit coverage
// proof. Accepted controls must execute, including dynamic Unit arguments;
// numeric and incomplete Boolean matches must still reject.
const cases: { name: string; source: string; success: boolean; code: string }[] =
  JSON.parse(await Deno.readTextFile(new URL("../src/unit-coverage-oracle.json", import.meta.url)));

for (const item of cases) {
  Deno.test(`Unit match coverage: ${item.name}`, async () => {
    if (!item.success) {
      await compileExpectedFailure(item.source, item.code, undefined, { prelude: "none" });
      return;
    }
    await compileAndRun(item.source, guest => {
      const result = item.name === "unit_runtime_function" || item.name === "unit_function_argument"
        ? guest.call("answer", null)
        : guest.read("answer");
      equal(result, 42);
    }, { prelude: "none" });
  });
}
