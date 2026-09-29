import { ok } from "node:assert/strict";
import { dirname } from "node:path";
import compiled from "../generated/compiler/compiler.js";
import { toBendCst } from "./bend_abi.ts";
import { bendArray, type BendList } from "./bend_list.ts";
import { benchmarkWorkloads } from "./benchmark_workloads.ts";
import { createSourceFrontend } from "./source_frontend.ts";

type Node = { readonly $: string; readonly [key: string]: unknown };
const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const report = Deno.args[0] ?? "build/handoff/eligibility.json";
if (Deno.args.length > 1) {
  throw new Error("Usage: checked_handoff_census.ts [report.json]");
}
const workloads: {
  name: string;
  source: string;
  prelude: "none" | "default";
}[] = benchmarkWorkloads.filter((workload) =>
  ["lexical_256", "balanced_64", "reader_64", "chain_64", "nominal_256"]
    .includes(workload.name)
).map((workload) => ({ ...workload, prelude: "none" }));
for (const name of ["generic_effects", "ecs"]) {
  workloads.push({
    name: `example_${name}`,
    source: await Deno.readTextFile(`examples/${name}.blot`),
    prelude: "default",
  });
}
const rows = [];
for (const workload of workloads) {
  const frontend = await createSourceFrontend({ prelude: workload.prelude });
  try {
    const parsed = frontend.prepare(workload.source);
    const result = api["source_modules.source_module_core"](
      false,
      toBendCst(parsed.root),
      toBendCst(parsed.prelude),
      parsed.nodeCount,
    ) as Node;
    ok(result.$ === "Done", `${workload.name}: ${Deno.inspect(result)}`);
    const prepared = api["source_modules.sourced_prepared"](result.value);
    const certificates = api["checked_core.prepared_certificates"](
      prepared,
    ) as BendList<unknown>;
    const row = {
      workload: workload.name,
      checked_handoff: api["checked_core.prepared_is_checked"](prepared),
      retained_group_certificates: bendArray(certificates).length,
    };
    rows.push(row);
    console.log(JSON.stringify(row));
  } finally {
    frontend.dispose();
  }
}
await Deno.mkdir(dirname(report), { recursive: true });
await Deno.writeTextFile(
  report,
  JSON.stringify({ note: "Eligibility only, not a timing result", rows }, null, 2) +
    "\n",
);
