// Time a fresh Gdev Main and the first edit to a widely imported module.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { gdevProject } from "../../scripts/integration/gdev_project.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const rounds = Number(Deno.args[0] ?? 6);
assert(Number.isInteger(rounds) && rounds > 0);
const root = resolve("../gdev");
const project = await gdevProject(root, resolve("std"), "src/main.blot");
const inkRoot = project.imports?.["ink/"];
assert(typeof inkRoot === "string");
const math = resolve(inkRoot, "math.blot");
const addition =
  "\nfunc invalidation_probe (value: U32): U32 => return value\n";
const cases = [];
for (
  const [label, file] of [
    ["gameLibrary", resolve(root, "src/library.blot")],
    ["inkMath", math],
    ["prelude", project.prelude],
  ]
) {
  const original = await Deno.readTextFile(file);
  assert(!original.includes("invalidation_probe"));
  cases.push({ label, sources: { [file]: original + addition } });
}
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)).toHex();
async function open(profileBackend = false) {
  return await createZigProjectCompiler({ ...project, profileBackend });
}
async function build(
  client: Awaited<ReturnType<typeof open>>,
  sources: Record<string, string>,
  start = performance.now(),
) {
  const result = await client.build({
    sources,
    signal: AbortSignal.timeout(15_000),
  });
  const ms = performance.now() - start;
  if (!result.success) throw new Error(JSON.stringify(result.diagnostics));
  return {
    ms,
    sha256: await hash(result.bytes),
    bytes: result.bytes.length,
    freshModules: result.stats.freshModules,
    cachedModules: result.stats.cachedModules,
    bodies: result.stats.frontend.body_elaborations,
    phases: result.stats.phaseProfile.phases,
  };
}
async function revision(path: string) {
  const result = await new Deno.Command("git", {
    args: ["-C", path, "rev-parse", "HEAD"],
  }).output();
  assert(result.success);
  return new TextDecoder().decode(result.stdout).trim();
}
async function freshBuild(sources: Record<string, string>) {
  const start = performance.now();
  const client = await open();
  try {
    return await build(client, sources, start);
  } finally {
    await client.dispose();
  }
}
const oracles: Record<string, string> = {};
for (const c of [{ label: "base", sources: {} }, ...cases]) {
  oracles[c.label] = (await freshBuild(c.sources)).sha256;
}
const samples = [];
// Each edit starts from a fresh build. Run separate profiled trials afterward.
for (let round = 0; round <= rounds; round++) {
  const order = cases.slice();
  if (round % 2) order.reverse();
  const profiled = round === rounds;
  for (const c of order) {
    let freshEdit;
    if (!profiled && round % 2 === 0) freshEdit = await freshBuild(c.sources);
    const start = performance.now();
    const client = await open(profiled);
    let fresh, edit;
    try {
      fresh = await build(client, {}, start);
      assert.equal(fresh.sha256, oracles.base);
      edit = await build(client, c.sources);
      assert.equal(edit.sha256, oracles[c.label]);
    } finally {
      await client.dispose();
    }
    if (!profiled && round % 2 === 1) freshEdit = await freshBuild(c.sources);
    if (freshEdit) assert.equal(freshEdit.sha256, edit.sha256);
    samples.push({
      round: round + 1,
      profiled,
      editModule: c.label,
      fresh,
      edit,
      freshEdit,
    });
  }
}
console.log(JSON.stringify(
  {
    blot: await revision("."),
    gdev: await revision(root),
    ink: await revision("../ink"),
    compilerSha256: await hash(await Deno.readFile(project.executable)),
    workers: "project default",
    method:
      "Fresh process/session open through complete Main Wasm, then one overlay edit adding an unused public function. A fresh build of the edited source is timed before or after each pair in alternating rounds. Warm filesystem. Profiled runs recorded separately. Hashes checked against fresh builds of each source.",
    oracles,
    samples,
  },
  null,
  2,
));
