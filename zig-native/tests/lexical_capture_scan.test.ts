import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;

// Every closure added to an inference region asks for a lexical capture key.
// The key reads interfaces only for values reachable from that closure's
// captures, so selecting them projects those scopes, never every scope the
// region holds. Wide closure tables stay linear instead of quadratic.
const table = (count: number, shared: boolean) => {
  const items = Array.from(
    { length: count },
    (_, index) => {
      if (shared) return `make shared ${index}`;
      return `make ${index}`;
    },
  ).join(", ");
  let make =
    "const make = fn (captured: U32) => fn (value: U32) => @u32.add captured value";
  let capture = "";
  if (shared) {
    make =
      "const make = fn (base: Array U32) => fn (captured: U32) => fn (value: U32) => @u32.add base[0] (@u32.add captured value)";
    capture = "  let shared = #[1, 2]\n";
  }
  return `${make}
entry const answer: U32 = do:
${capture}  let table = #[${items}]
  return table.capture_count
`;
};
Deno.test("lexical capture keys project only reachable scopes in wide closure tables", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-lexical-scan-" });
  const entry = `${directory}/main.blot`;
  // Keep ordinary member inference active: exact generic length bodies can
  // now prove that they need no element or lexical capture interfaces.
  const library = await Deno.readTextFile(prelude) +
    "\nconst Array.capture_count = fn values => @u32.add 0 (@array.length values)\n";
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude,
    cacheDirectory: false,
  });
  try {
    for (const shared of [false, true]) {
      for (const count of [8, 32, 96]) {
        const result = await compiler.build({
          sources: { [entry]: table(count, shared), [prelude]: library },
        });
        assert(result.success, JSON.stringify(result));
        const counters = result.stats.workCounters as Record<string, number>;
        const projections = counters.lexical_interface_projections;
        // A shared aggregate is reachable from every closure; scalars are not
        // scopes. The quadratic scan projected count * (count + 1) / 2.
        if (shared) assert(projections > 0, `${count}: ${projections}`);
        assert(projections <= 4 * count, `${count}: ${projections}`);
      }
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
