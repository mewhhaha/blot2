/** Execute a scalar entry of an already instrumented module and pin its report. */
import { parseArgs } from "node:util";
import { resolve } from "node:path";
import {
  memoryProfileReport,
  stringifyMemoryProfile,
} from "../../compiler/memory_profile.ts";

const { values } = parseArgs({
  options: {
    wasm: { type: "string" },
    entry: { type: "string" },
    argument: { type: "string", default: "0" },
    iterations: { type: "string", default: "1" },
    output: { type: "string" },
    "expected-sha256": { type: "string" },
  },
});
if (!values.wasm || !values.entry || !values.output) {
  throw new Error(
    "Use --wasm PROFILE.wasm --entry NAME --argument NUMBER --iterations N --output REPORT.json [--expected-sha256 HASH]",
  );
}
const iterations = Number(values.iterations),
  argument = Number(values.argument);
if (
  !Number.isSafeInteger(iterations) || iterations < 1 ||
  !Number.isFinite(argument)
) throw new Error("Invalid iteration count or scalar argument");
const bytes = await Deno.readFile(values.wasm);
const started = performance.now();
const module = new WebAssembly.Module(bytes);
if (WebAssembly.Module.imports(module).length) {
  throw new Error(
    "This runner accepts import-free scalar entries; use memoryProfileReport in your application host for callbacks, owners or suspension",
  );
}
const raw = new WebAssembly.Instance(module).exports;
const call = raw[values.entry];
if (
  typeof call !== "function" ||
  typeof raw["blot:ownership_enter"] !== "function" ||
  typeof raw["blot:ownership_leave"] !== "function"
) throw new Error("Missing entry or ownership ABI");
// Verify metadata/instance identity before invoking anything.
await memoryProfileReport(bytes, raw, values["expected-sha256"]);
const instantiate_ms = performance.now() - started;
const execution = performance.now();
let result: unknown;
for (let i = 0; i < iterations; i++) {
  (raw["blot:ownership_enter"] as CallableFunction)();
  let outcome = 1;
  try {
    result = call(argument);
    outcome = 0;
  } finally {
    (raw["blot:ownership_leave"] as CallableFunction)(outcome);
  }
}
const execution_ms = performance.now() - execution;
const snapshot = await memoryProfileReport(
  bytes,
  raw,
  values["expected-sha256"],
);
const report = {
  ...snapshot,
  run: {
    wasm: resolve(values.wasm),
    entry: values.entry,
    argument,
    iterations,
    result,
    instantiate_ms,
    execution_ms,
    engine: Deno.version,
    scope:
      "Instrumented lifetime totals including initialization and ownership teardown; timings are diagnostic overhead, not release performance",
  },
};
await Deno.writeTextFile(values.output, stringifyMemoryProfile(report));
console.log(
  `${
    snapshot.complete ? "Complete" : "INCOMPLETE"
  }: ${values.output}; ${snapshot.totals.allocations} allocations, ${snapshot.totals.requested_bytes} requested bytes, ${snapshot.totals.live_bytes} live bytes, ${snapshot.totals.cycle_vertices} cycle vertices`,
);
if (!snapshot.complete) Deno.exitCode = 1;
