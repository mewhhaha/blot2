// Compare complete fresh project builds in alternating order. In edit mode
// each pair also exercises the same open-session revisions and diagnostics.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { gdevProject } from "./gdev_project.ts";

const { values } = parseArgs({
  options: {
    before: { type: "string" },
    after: { type: "string" },
    rounds: { type: "string", default: "12" },
    "frontend-workers": { type: "string" },
    edits: { type: "boolean" },
    profile: { type: "boolean" },
    wasm: { type: "string" },
    "gdev-root": { type: "string", default: "../gdev" },
  },
});
assert(values.before && values.after, "Supply both compiler executable paths");
let workers: number | undefined;
if (values["frontend-workers"] !== undefined) {
  workers = Number(values["frontend-workers"]);
  assert(Number.isInteger(workers) && workers >= 1 && workers <= 16);
}
const rounds = Number(values.rounds);
assert(Number.isSafeInteger(rounds) && rounds > 0);
const gdev = resolve(values["gdev-root"]);
const file = resolve(gdev, "src/effects/lighting_look.blot");
const original = await Deno.readTextFile(file);
const marker = "const proposed = $Look { sun: true,";
assert.equal(original.split(marker).length, 2);
type Revision = { step: string; source?: string; valid: boolean };
const revisions: Revision[] = [{ step: "fresh", valid: true }];
if (values.edits) {
  const change = (sun: string) =>
    original.replace(marker, "const proposed = $Look { sun: " + sun + ",");
  revisions.push(
    { step: "edit", source: change("false"), valid: true },
    { step: "reject", source: change("unresolved_probe"), valid: false },
    { step: "syntax", source: change(")"), valid: false },
    {
      step: "lex",
      source: original + '\nprivate const bad_probe = "\\q"\n',
      valid: false,
    },
    { step: "recover", source: original, valid: true },
  );
}
type Project = Awaited<ReturnType<typeof gdevProject>>;
const projects = new Map<string, Project>();
for (const mode of ["before", "after"] as const) {
  projects.set(
    mode,
    await gdevProject(
      gdev,
      resolve("std"),
      "src/main.blot",
      resolve(values[mode]!),
    ),
  );
}
const references = new Map<string, string>();
for (let round = 1; round <= rounds; round++) {
  const order = ["before", "after"];
  if (round % 2 === 0) order.reverse();
  for (const mode of order) {
    const open = performance.now();
    const compiler = await createZigProjectCompiler({
      ...projects.get(mode)!,
      frontendWorkers: workers,
      profileBackend: values.profile,
    });
    try {
      for (const { step, source, valid } of revisions) {
        let start = open;
        if (source !== undefined) start = performance.now();
        let sources: Record<string, string> | undefined;
        if (source !== undefined) sources = { [file]: source };
        const result = await compiler.build({
          sources,
          signal: AbortSignal.timeout(9000),
        });
        const ms = performance.now() - start;
        if (result.success) assert(valid, step);
        else assert(!valid, JSON.stringify(result.diagnostics));
        const row = { mode, round, step, ms, success: result.success };
        let fingerprint: string;
        if (result.success) {
          assert(WebAssembly.validate(result.bytes));
          fingerprint = Array.from(
            new Uint8Array(await crypto.subtle.digest("SHA-256", result.bytes)),
            (v) => v.toString(16).padStart(2, "0"),
          ).join("");
          if (step === "recover") {
            assert.equal(fingerprint, references.get("fresh"));
          }
          if (step === "edit") {
            assert.notEqual(fingerprint, references.get("fresh"));
          }
          if (
            values.wasm && round === 1 && mode === "after" && step === "fresh"
          ) {
            await Deno.writeFile(values.wasm, result.bytes);
          }
          Object.assign(row, {
            hash: fingerprint,
            bytes: result.bytes.length,
            fresh: result.stats.freshModules,
            cached: result.stats.cachedModules,
          });
          if (values.profile) {
            Object.assign(row, { profile: result.stats.phaseProfile });
          }
        } else {
          fingerprint = JSON.stringify(result.diagnostics);
          Object.assign(row, { diagnostics: result.diagnostics });
        }
        if (references.has(step)) {
          assert.equal(fingerprint, references.get(step), step);
        } else references.set(step, fingerprint);
        console.log(JSON.stringify(row));
      }
    } finally {
      await compiler.dispose();
    }
  }
}
