// Compare whole Gdev project-session builds against independent fresh Wasm.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { gdevProject } from "../../scripts/integration/gdev_project.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const [oldPath, newPath] = Deno.args;
assert(oldPath && newPath, "expected previous and candidate compiler paths");
const root = resolve("../gdev");
const project = await gdevProject(root, resolve("std"), "src/main.blot");
const leaf = resolve(root, "src/effects/lighting_look.blot");
const world = resolve(root, "src/world_storage.blot");
const entry = resolve(root, "src/main.blot");
const entrySource = await Deno.readTextFile(entry);
const original = await Deno.readTextFile(leaf);
const worldSource = await Deno.readTextFile(world);
function edit(source: string, before: string, after: string) {
  assert.equal(source.split(before).length, 2, before);
  return source.replace(before, after);
}
const proposed = "const proposed = $Look { sun: ";
const dark = edit(original, proposed + "true", proposed + "false");
const scalar = edit(original, proposed + "true", proposed + "(61 == 1)");
const wide = edit(scalar, "(61 == 1)", "(4096 == 1)");
const stagedWorld = edit(
  worldSource,
  "let lighting_look = #[lighting_look.proposed]",
  "let lighting_look = #[if (#run lighting_look.probe_flag) then lighting_look.proposed else lighting_look.original]",
);
const flag = "\nconst probe_flag: Bool = ";
const renamed = edit(
  edit(entrySource, "(host:", "(session_probe_host:"),
  "played host",
  "played session_probe_host",
);
const sources: Record<string, Record<string, string>> = {
  base: {},
  entryRename: { [entry]: renamed },
  dependencyRename: {
    [world]: edit(
      edit(
        worldSource,
        "func run initial -> stages -> host =>",
        "func run initial -> stages -> renamed_host =>",
      ),
      "(application stages) (owners initial) host",
      "(application stages) (owners initial) renamed_host",
    ),
  },
  renamedDark: { [entry]: renamed, [leaf]: dark },
  rejectedEntry: {
    [entry]: edit(renamed, "played session_probe_host", "played missing_host"),
  },
  dark: { [leaf]: dark },
  both: {
    [leaf]: edit(
      dark,
      "fill: true, bounce: true, phase: $Nothing }\nfunc choose",
      "fill: false, bounce: true, phase: $Nothing }\nfunc choose",
    ),
  },
  rejected: {
    [leaf]: edit(dark, proposed + "false", proposed + "no_such_flag"),
  },
  scalar: { [leaf]: scalar },
  wide: { [leaf]: wide },
  stageOn: { [world]: stagedWorld, [leaf]: original + flag + "true\n" },
  stageOff: { [world]: stagedWorld, [leaf]: original + flag + "false\n" },
};
async function sha(bytes: Uint8Array<ArrayBuffer>) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)).toHex();
}
async function open(path: string, profile = false) {
  return await createZigProjectCompiler({
    ...project,
    executable: resolve(path),
    frontendWorkers: 8,
    profileBackend: profile,
  });
}
type Client = Awaited<ReturnType<typeof open>>;
async function build(c: Client, label: string, since = performance.now()) {
  const r = await c.build({
    sources: sources[label],
    signal: AbortSignal.timeout(15000),
  });
  const ms = performance.now() - since;
  if (!r.success) {
    return { ms, revision: r.revision, diagnostics: r.diagnostics };
  }
  return {
    ms,
    revision: r.revision,
    sha256: await sha(r.bytes),
    bytes: r.bytes.length,
    fresh: r.stats.freshModules,
    modules: r.stats.freshModules + r.stats.cachedModules,
    sourceLoad: r.stats.sourceLoad,
    relocatedOperands: r.stats.relocatedOperands,
    phases: r.stats.phaseProfile.phases,
  };
}
const oracle = new Map<string, Awaited<ReturnType<typeof build>>>();
for (const label of Object.keys(sources)) {
  const c = await open(oldPath);
  try {
    oracle.set(label, await build(c, label));
  } finally {
    await c.dispose();
  }
}
function verify(label: string, row: Awaited<ReturnType<typeof build>>) {
  const reference = oracle.get(label)!;
  if (reference.diagnostics) {
    assert(reference.diagnostics?.length);
    assert.deepEqual(row.diagnostics, reference.diagnostics);
  } else {
    assert(reference.sha256, label);
    assert.equal(row.sha256, reference.sha256, label);
  }
}
const transitions = [];
const candidate = await open(newPath);
try {
  let revision = 0;
  for (
    const label of [
      "base",
      "dark",
      "both",
      "rejected",
      "dark",
      "base",
      "scalar",
      "wide",
      "scalar",
      "stageOn",
      "stageOff",
      "stageOn",
      "base",
      "entryRename",
      "rejectedEntry",
      "renamedDark",
      "entryRename",
      "base",
      "dependencyRename",
      "base",
      "dark",
    ]
  ) {
    const row = await build(candidate, label);
    verify(label, row);
    if (!row.diagnostics) revision++;
    assert.equal(row.revision, revision);
    if (label === "dark" || label === "both") {
      assert.equal(row.relocatedOperands, 1);
    }
    if (["wide", "scalar", "stageOn", "stageOff"].includes(label)) {
      assert.equal(row.relocatedOperands, undefined);
    }
    transitions.push({ label, ...row });
  }
} finally {
  await candidate.dispose();
}
const pairs = [];
const entryRenames = [];
for (let pair = 0; pair < 10; pair++) {
  const order = ["previous", "candidate"];
  if (pair % 2) order.reverse();
  for (const treatment of order) {
    const start = performance.now();
    const c = await open(
      treatment === "previous" ? oldPath : newPath,
      pair >= 8,
    );
    try {
      const fresh = await build(c, "base", start);
      verify("base", fresh);
      const changed = await build(c, "dark");
      verify("dark", changed);
      if (treatment === "candidate") {
        assert.equal(changed.relocatedOperands, 1);
        assert.deepEqual(changed.sourceLoad, {
          sourceReads: changed.modules,
          reusedSyntaxModules: changed.modules! - 1,
        });
      }
      pairs.push({
        pair: pair + 1,
        profiled: pair >= 8,
        treatment,
        fresh,
        changed,
      });
    } finally {
      await c.dispose();
    }
  }
}
// Time the rename directly from the original scene in a separate session.
for (let pair = 0; pair < 10; pair++) {
  const order = ["previous", "candidate"];
  if (pair % 2) order.reverse();
  for (const treatment of order) {
    const c = await open(
      treatment === "previous" ? oldPath : newPath,
      pair >= 8,
    );
    try {
      verify("base", await build(c, "base"));
      const rename = await build(c, "entryRename");
      verify("entryRename", rename);
      if (treatment === "candidate") {
        assert.equal(rename.fresh, 1);
        assert.equal(
          rename.sourceLoad?.reusedSyntaxModules,
          rename.modules! - 1,
        );
      }
      entryRenames.push({
        pair: pair + 1,
        profiled: pair >= 8,
        treatment,
        rename,
      });
    } finally {
      await c.dispose();
    }
  }
}
console.log(JSON.stringify(
  {
    compiler: {
      previous: await sha(await Deno.readFile(oldPath)),
      candidate: await sha(await Deno.readFile(newPath)),
    },
    sources: {
      entry: await sha(await Deno.readFile(entry)),
      lighting: await sha(await Deno.readFile(leaf)),
      world: await sha(await Deno.readFile(world)),
    },
    transitions,
    pairs,
    entryRenames,
  },
  null,
  2,
));
