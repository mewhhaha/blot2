import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
import { resultCases } from "./result_cases.ts";
import { decodeText } from "../../compiler/text.ts";

Deno.test("staged nested conversions infer their destination from the surrounding operator", async () => {
  await compileAndRun(
    `
const count = 42
entry const answer = from (ceil (sqrt (from count))) + 2
`,
    (guest) => equal(guest.read("answer"), 9),
    {
      prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
    },
  );
});

Deno.test("ordinary text values compile while intrinsic validation keeps its literal rule", async () => {
  await compileAndRun(
    `const name = "from"\nentry const answer = fn () => name\n`,
    (guest) => {
      equal(decodeText(guest.call("answer", null) as Uint32Array), "from");
    },
  );
  await compileExpectedFailure(
    `const name: String = "from"\nentry const answer = 42\n`,
    "unsupported_type",
  );
  await compileExpectedFailure(
    `const name = "from"\nentry const answer = @type.result name 42\n`,
    "literal_required",
  );
});

for (const item of resultCases) {
  if (!("expected" in item)) continue;
  Deno.test(`native expected-result dispatch preserves ${item.name}`, async () => {
    await compileAndRun(item.source, (guest) => {
      for (const [name, expected] of Object.entries(item.expected)) {
        equal(
          guest.abi.constants.some((value) => value.name === name)
            ? guest.read(name)
            : guest.call(name, null),
          expected,
        );
      }
    });
  });
}

Deno.test("native expected-result dispatch rejects selected mismatches and invalid primitive syntax", async () => {
  for (const item of resultCases) {
    if (!("error" in item)) continue;
    await compileExpectedFailure(item.source, item.error);
  }
});
