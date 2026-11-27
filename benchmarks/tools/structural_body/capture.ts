import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { basename, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { gdevProject } from "../../../scripts/integration/gdev_project.ts";
import { createZigProjectCompiler } from "../../../host/zig_project_client.ts";

const work = resolve("build/structural-body");
const dataset = await Deno.makeTempDir({ dir: work, prefix: "capture-" });
const game = resolve(dataset, "gdev");
const compiler = resolve(
  Deno.env.get("SQUID_COMPILER") ?? "compiler-goose/build/squidc-goose-pgo",
);
const pins = {
  gdev: "cc4bbbf22d35d7b91acd02957a8bdce38bdda90b",
  ink: "77697fef9dda8caf06f5a7c92141372fa1e99cde",
  squid: "bdd1f6788418d0a5c2ee547cfa196d84028b7cb3",
};

async function snapshot(repo: keyof typeof pins, paths: string[]) {
  const destination = resolve(dataset, repo);
  await Deno.mkdir(destination);
  const archive = new Deno.Command("git", {
    args: ["-C", resolve("..", repo), "archive", pins[repo], "--", ...paths],
    stdout: "piped",
  }).spawn();
  const extract = new Deno.Command("tar", {
    args: ["-x", "-C", destination],
    stdin: "piped",
  }).spawn();
  await archive.stdout.pipeTo(extract.stdin);
  const [packed, unpacked] = await Promise.all([
    archive.status,
    extract.status,
  ]);
  assert(packed.success && unpacked.success, repo);
}

async function digest(file: string) {
  const hash = new Uint8Array(
    await crypto.subtle.digest("SHA-256", await Deno.readFile(file)),
  );
  return Array.from(hash, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

const build = JSON.parse(
  await Deno.readTextFile(resolve(work, "build-identity.json")),
);
assert.equal(await digest(resolve(work, "capture.so")), build["capture.so"]);
const compilerSha256 = await digest(compiler);
await Promise.all([
  snapshot("gdev", ["src", "pen", "devtools", "tests", "pen.json"]),
  snapshot("ink", ["lib"]),
  snapshot("squid", ["std"]),
]);
const read = (path: string) => Deno.readTextFile(resolve(game, path));
const simulation = "src/game/simulation.sq";
const render = "src/game/presentation.sq";
const events = "src/game/events.sq";
const arena = "src/world/arena.sq";
const hover = "hover.update access seconds";
function change(source: string, marker: string, replacement: string) {
  assert.equal(source.split(marker).length, 2, marker);
  return source.replace(marker, replacement);
}
const sim = await read(simulation);
const withHelper = sim +
  "\nprivate func experimental_scale (v: F32): F32 => return if v > 2.0 then v * v else v + 1.0\n";
const stageHelper = (await read(arena)) +
  "\nfunc experimental_distance (v: F32): F32 => return @f32.mul v 2.4\n";
const stage = {
  [arena]: stageHelper,
  [simulation]: change(
    sim,
    hover,
    "hover.update access (arena.experimental_distance seconds + (#run (arena.experimental_distance 2.0)))",
  ),
};
const variants: Record<string, Record<string, string>> = {
  base: {},
  timing: {
    [simulation]: change(sim, hover, "hover.update access (seconds * 0.5)"),
  },
  render: {
    [render]: change(
      await read(render),
      "render_scale = scene_scale",
      "render_scale = scene_scale * 0.75",
    ),
  },
  input: {
    [events]: change(
      await read(events),
      "if level_controls access ():",
      "if level_controls access () and context.width > 100.0:",
    ),
  },
  helper: {
    [simulation]: change(sim, hover, "hover.update access (abs seconds)"),
  },
  "edge-base": { [simulation]: withHelper },
  "edge-edit": {
    [simulation]: change(
      withHelper,
      hover,
      "hover.update access (experimental_scale seconds)",
    ),
  },
  "stage-base": stage,
  "stage-edit": {
    ...stage,
    [arena]: change(
      stageHelper,
      "@f32.mul v 2.4",
      "@f32.add (@f32.mul v 2.4) 1.0",
    ),
  },
};
const cases = [
  ["timing", "base", "timing", simulation, 275, "hover.update access"],
  ["render", "base", "render", render, 282, "frame.settings[0].render_scale ="],
  ["input", "base", "input", events, 249, "if level_controls access ()"],
  ["helper", "base", "helper", simulation, 275, "hover.update access"],
  ["edge", "edge-base", "edge-edit", simulation, 275, "hover.update access"],
  [
    "stage",
    "stage-base",
    "stage-edit",
    arena,
    92,
    "func experimental_distance",
  ],
] as const;
const trials = [];
for (const [name, base, edit, file, unit, marker] of cases) {
  for (const [from, to] of [[base, edit], [edit, base]]) {
    const text = variants[from][file] ?? await read(file);
    assert.equal(text.split(marker).length, 2);
    trials.push({
      name,
      from,
      to,
      unit,
      point:
        new TextEncoder().encode(text.slice(0, text.indexOf(marker))).length,
    });
  }
}

const packetSets: Record<string, string> = {};
for (const [name, edits] of Object.entries(variants)) {
  const directory = resolve(dataset, name);
  await Deno.mkdir(directory, { recursive: true });
  const sources = Object.fromEntries(
    Object.entries(edits).map(([path, text]) => [resolve(game, path), text]),
  );
  const quote = (text: string) => "'" + text.replaceAll("'", "'\\''") + "'";
  const wrapper = resolve(directory, "run");
  await Deno.writeTextFile(
    wrapper,
    [
      "#!/bin/sh",
      "export LD_PRELOAD=" + quote(resolve(work, "capture.so")),
      "export SQUID_CORE_PACKETS=" + quote(directory),
      "exec " + quote(compiler) + ' "$@"',
    ].join("\n") + "\n",
    { mode: 0o755 },
  );
  for (const capture of [true, false]) {
    const cfg = await gdevProject(
      game,
      resolve(dataset, "squid-lang/std"),
      "src/main.sq",
      capture ? wrapper : compiler,
    );
    const client = await createZigProjectCompiler({
      ...cfg,
      frontendWorkers: 8,
    });
    try {
      const result = await client.build({
        sources,
        signal: AbortSignal.timeout(15000),
      });
      if (!result.success) throw new Error(JSON.stringify(result.diagnostics));
      assert(WebAssembly.validate(result.bytes));
      assert.equal(result.stats.freshModules, 293);
      if (capture) {
        await Deno.writeFile(resolve(directory, "main.wasm"), result.bytes);
      } else {
        assert.deepEqual(
          result.bytes,
          await Deno.readFile(resolve(directory, "main.wasm")),
        );
      }
    } finally {
      await client.dispose();
    }
  }
  const packets = createHash("sha256");
  for (let i = 1; i <= 293; i++) {
    const bytes = await Deno.readFile(resolve(directory, i + "-2.bin"));
    assert(bytes.length > 24);
    packets.update(createHash("sha256").update(bytes).digest());
  }
  packetSets[name] = packets.digest("hex");
  await Deno.remove(wrapper);
  console.log(name);
}
assert.equal(await digest(compiler), compilerSha256);
assert.equal(await digest(resolve(work, "capture.so")), build["capture.so"]);
const manifest = {
  dataset: basename(dataset),
  pins,
  packetSets,
  captureToolSha256: await digest(fileURLToPath(import.meta.url)),
  compilerSha256,
  captureSha256: build["capture.so"],
  trials,
};
const pending = resolve(dataset, "manifest.json");
await Deno.writeTextFile(pending, JSON.stringify(manifest, null, 2) + "\n");
await Deno.rename(pending, resolve(work, "capture.json"));
