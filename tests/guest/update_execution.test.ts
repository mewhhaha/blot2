import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
import { updateCases } from "./update_cases.ts";

for (const item of updateCases) {
  if (!("expected" in item)) continue;
  Deno.test(`native indexed updates preserve ${item.name}`, async () => {
    await compileAndRun(item.source, (guest) => {
      for (const [name, expected] of Object.entries(item.expected)) {
        const argument = "arguments" in item
          ? (item.arguments as Record<string, number>)[name]
          : undefined;
        equal(
          guest.abi.constants.some((value) => value.name === name)
            ? guest.read(name)
            : guest.call(name, argument ?? null),
          expected,
        );
      }
    });
  });
}

Deno.test("native indexed updates preserve outer-index, old-leaf and RHS failure order", async () => {
  for (const item of updateCases) {
    if (!("error" in item)) continue;
    await compileExpectedFailure(
      item.source,
      item.error,
      item.error === "const_panic"
        ? "rhs executes after selecting leaf"
        : undefined,
    );
  }
});
