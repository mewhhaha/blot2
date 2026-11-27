// Cross compiler and source changes independently on the same Gdev project.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { gdevProject } from "../../scripts/integration/gdev_project.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const [previousCompiler, candidateCompiler, previousGdev, rounds = "8"] =
  Deno.args;
assert(previousCompiler && candidateCompiler && previousGdev);
const repeats = Number(rounds);
assert(Number.isInteger(repeats) && repeats > 0);
const root = resolve("../gdev");
const entry = resolve(root, "src/main.sq");
const world = resolve(root, "src/world_storage.sq");
const session = resolve(root, "src/session.sq");
const leaf = resolve(root, "src/effects/lighting_look.sq");
const project = await gdevProject(root, resolve("std"), "src/main.sq");
const decode = new TextDecoder();
async function git(...args: string[]) {
  const r = await new Deno.Command("git", { args: ["-C", root, ...args] })
    .output();
  assert(r.success, decode.decode(r.stderr));
  return decode.decode(r.stdout);
}
async function sha(bytes: Uint8Array<ArrayBuffer>) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)).toHex();
}
function edit(s: string, from: string, to: string) {
  assert.equal(s.split(from).length, 2, from);
  return s.replace(from, to);
}
const lighting = await Deno.readTextFile(leaf);
const dark = edit(
  lighting,
  "const proposed = $Look { sun: true",
  "const proposed = $Look { sun: false",
);
const oldRevision = (await git("rev-parse", previousGdev + "^{commit}")).trim();
type Edit = "base" | "rename" | "storage" | "lighting";
type Versions = Record<Edit, Record<string, string>>;
const sources: { layout: string; versions: Versions }[] = [];
for (const layout of ["original", "session"]) {
  const base: Record<string, string> = {};
  let runner = world;
  if (layout === "original") {
    base[entry] = await git("show", oldRevision + ":src/main.sq");
    base[world] = await git("show", oldRevision + ":src/world_storage.sq");
  } else {
    base[entry] = await Deno.readTextFile(entry);
    base[world] = await Deno.readTextFile(world);
    runner = session;
    base[session] = await Deno.readTextFile(session);
  }
  const signature = "-> stages -> host =>";
  let renamed: string;
  if (layout === "original") {
    renamed = edit(
      edit(base[runner], signature, "-> stages -> renamed_host =>"),
      "(owners initial) host",
      "(owners initial) renamed_host",
    );
  } else {
    renamed = edit(
      edit(base[runner], "-> host =>", "-> renamed_host =>"),
      "}) host",
      "}) renamed_host",
    );
  }
  const storage = edit(
    base[world],
    "scene_history.metadata 64 1048576",
    "scene_history.metadata 65 1048576",
  );
  sources.push({
    layout,
    versions: {
      base,
      rename: { ...base, [runner]: renamed },
      storage: { ...base, [world]: storage },
      lighting: { ...base, [leaf]: dark },
    },
  });
}
async function build(
  client: Awaited<ReturnType<typeof createZigProjectCompiler>>,
  sources: Record<string, string>,
  start = performance.now(),
) {
  const result = await client.build({
    sources,
    signal: AbortSignal.timeout(15000),
  });
  const ms = performance.now() - start;
  assert(
    result.success,
    JSON.stringify(result.success ? {} : result.diagnostics),
  );
  return {
    ms,
    freshModules: result.stats.freshModules,
    elaboratedBodies: result.stats.frontend.body_elaborations,
    loweredBodies: result.stats.frontend.body_lowerings,
    relocatedOperands: result.stats.relocatedOperands,
    modules: result.stats.freshModules + result.stats.cachedModules,
    bytes: result.bytes.length,
    sha256: await sha(result.bytes),
  };
}
const binaries = [resolve(previousCompiler), resolve(candidateCompiler)];
const open = (executable: string) =>
  createZigProjectCompiler({ ...project, executable, frontendWorkers: 8 });
const oracles = [];
for (const { versions } of sources) {
  const hashes: Record<string, string> = {};
  for (const kind of Object.keys(versions) as Edit[]) {
    const client = await open(binaries[0]);
    try {
      hashes[kind] = (await build(client, versions[kind])).sha256;
    } finally {
      await client.dispose();
    }
  }
  assert.equal(hashes.base, hashes.rename);
  assert.notEqual(hashes.base, hashes.storage);
  assert.notEqual(hashes.base, hashes.lighting);
  oracles.push(hashes);
}
const rows = [];
for (let round = 0; round < repeats; round++) {
  const sequence = [0, 1, 3, 2];
  if (round % 2) sequence.reverse();
  for (let j = 0; j < 4; j++) {
    const lane = sequence[(j + Math.floor(round / 2)) % 4];
    const layout = Math.floor(lane / 2), compiler = lane % 2;
    const { versions } = sources[layout];
    const start = performance.now(), client = await open(binaries[compiler]);
    try {
      const fresh = await build(client, versions.base, start);
      assert.equal(fresh.sha256, oracles[layout].base);
      const edits: Edit[] = ["rename", "storage", "lighting"];
      if (round % 2) edits.reverse();
      const results: Record<string, Awaited<ReturnType<typeof build>>> = {};
      for (const [i, kind] of edits.entries()) {
        if (i) {
          assert.equal(
            (await build(client, versions.base)).sha256,
            oracles[layout].base,
          );
        }
        results[kind] = await build(client, versions[kind]);
        assert.equal(results[kind].sha256, oracles[layout][kind]);
        if (layout === 1 && compiler === 1) {
          if (kind === "storage") assert.equal(results[kind].freshModules, 1);
          if (kind === "rename") assert.equal(results[kind].freshModules, 2);
        }
      }
      rows.push({
        round: round + 1,
        layout: sources[layout].layout,
        compiler: ["previous", "candidate"][compiler],
        fresh,
        ...results,
      });
    } finally {
      await client.dispose();
    }
  }
}
// A prior edit can replace a cold interface with one produced by retained checking.
const directStorageAfterFresh = [];
for (let round = 0; round < Math.min(repeats, 4); round++) {
  const layouts = [0, 1];
  if (round % 2) layouts.reverse();
  for (const layout of layouts) {
    const { versions } = sources[layout];
    const client = await open(binaries[1]);
    try {
      assert.equal(
        (await build(client, versions.base)).sha256,
        oracles[layout].base,
      );
      const storage = await build(client, versions.storage);
      assert.equal(storage.sha256, oracles[layout].storage);
      directStorageAfterFresh.push({
        round: round + 1,
        layout: sources[layout].layout,
        freshModules: storage.freshModules,
        ms: storage.ms,
        elaboratedBodies: storage.elaboratedBodies,
        relocatedOperands: storage.relocatedOperands,
      });
    } finally {
      await client.dispose();
    }
  }
}
console.log(JSON.stringify(
  {
    previousGdev: oldRevision,
    sourceFiles: await Promise.all(
      sources.map(async ({ layout, versions }) => ({
        layout,
        sha256: Object.fromEntries(
          await Promise.all(
            Object.entries(versions.base).map(async (
              [p, s],
            ) => [
              p.slice(root.length + 1),
              await sha(new TextEncoder().encode(s)),
            ]),
          ),
        ),
      })),
    ),
    candidateGdev: (await git("rev-parse", "HEAD")).trim(),
    compilerSha256: await Promise.all(
      binaries.map(async (p) => sha(await Deno.readFile(p))),
    ),
    frontendWorkers: 8,
    oracles,
    rows,
    directStorageAfterFresh,
  },
  null,
  2,
));
