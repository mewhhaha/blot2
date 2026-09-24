// Retained-project memory and correctness stress. The source edit is an in-memory
// overlay; this script never writes to the gdev tree. Run after building blotc:
// deno run --allow-read --allow-write --allow-run --allow-env compiler/gdev_project_memory_bench.ts \
//   50 1 . build/gdev-application-baseline build/gdev-project-memory/results.json
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { dirname, join, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";
import {
  decodeFrame,
  encodeFrame,
  parseCatalog,
  validateSchema,
  validateState,
} from "../../gdev/boundary.ts";
import { type Guest, instantiateGuest } from "./guest.ts";
import type { Artifact } from "./host.ts";

const edits = Number(Deno.args[0] ?? "50");
const threads = Number(Deno.args[1] ?? "1");
const compilerRoot = resolve(Deno.args[2] ?? ".");
const applicationRoot = resolve(Deno.args[3] ?? "../gdev");
const reportPath = resolve(
  Deno.args[4] ?? "build/gdev-project-memory/results.json",
);
if (
  Deno.build.os !== "linux" || !Number.isInteger(edits) || edits < 1 ||
  edits > 200 || !Number.isInteger(threads) || threads < 1 || threads > 64 ||
  Deno.args.length > 5
) {
  throw new Error(
    "Usage (Linux): gdev_project_memory_bench.ts [edits:1..200] [threads:1..64] [compiler-root] [gdev-root] [report-path]",
  );
}

const compilerUrl = pathToFileURL(compilerRoot + sep);
const { createNativeCompiler }: typeof import("./native.ts") = await import(
  new URL("compiler/native.ts", compilerUrl).href
);
const { createNativeProjectCompiler }: typeof import("./native_project.ts") =
  await import(new URL("compiler/native_project.ts", compilerUrl).href);
const { loadSourceProject }: typeof import("./source_project.ts") =
  await import(
    new URL("compiler/source_project.ts", compilerUrl).href
  );

const executable = pathToFileURL(
  join(compilerRoot, "generated/compiler/blotc"),
);
const entry = pathToFileURL(join(applicationRoot, "src/main.blot"));
const motionPath = join(applicationRoot, "src/motion.blot");
const catalog = parseCatalog(
  JSON.parse(
    await Deno.readTextFile(join(applicationRoot, "src/assets/catalog.json")),
  ),
);
const original = await Deno.readTextFile(motionPath);
const axis = "y: 1.0";
ok(original.split(axis).length === 2, "Expected one motion axis to edit");
const edited = original.replace(axis, "y: 0.9");
type Variant = "original" | "edited";
let variant: Variant = "original";
const readSource = (url: URL) =>
  fileURLToPath(url) === motionPath
    ? Promise.resolve(variant === "original" ? original : edited)
    : Deno.readTextFile(url);
const imports = {
  "std/": pathToFileURL(join(compilerRoot, "std") + sep),
};

async function digest(bytes: Uint8Array): Promise<string> {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes.slice().buffer)),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

function observeGame(guest: Guest) {
  const schema = guest.read("state_schema");
  validateSchema(schema);
  const created = guest.call("create", null);
  validateState(created);
  const cleaned = guest.call("clean", created.slice());
  validateState(cleaned);
  const packet = guest.call(
    "frame",
    encodeFrame(
      { timestamp: 0, viewport: { width: 1280n, height: 720n }, events: [] },
      1 / 60,
      cleaned.slice(),
    ),
  );
  decodeFrame(packet, schema, catalog);
  return { abi: guest.abi, schema, created, cleaned, packet };
}

async function execute(artifact: Artifact) {
  const guest = await instantiateGuest(artifact.bytes);
  try {
    return observeGame(guest);
  } finally {
    guest.dispose();
  }
}

async function children(): Promise<Set<number>> {
  const found = new Set<number>();
  // A runtime helper thread may spawn the process; inspect every task's
  // children rather than assuming the main thread owns it.
  for await (const task of Deno.readDir("/proc/self/task")) {
    if (!task.isDirectory) continue;
    let value: string;
    try {
      value = await Deno.readTextFile(
        `/proc/self/task/${task.name}/children`,
      );
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) continue;
      throw error;
    }
    for (const part of value.trim().split(/\s+/).filter(Boolean)) {
      found.add(Number(part));
    }
  }
  return found;
}

async function nativePid(before: Set<number>): Promise<number> {
  const spawned = [...await children()].filter((pid) => !before.has(pid));
  ok(
    spawned.length === 1,
    `Expected one native compiler child, found ${spawned.join(", ")}`,
  );
  return spawned[0];
}

async function rss(pid: number) {
  const status = await Deno.readTextFile(`/proc/${pid}/status`);
  const number = (label: string) =>
    Number(new RegExp(`^${label}:\\s+(\\d+)`, "m").exec(status)?.[1] ?? 0);
  return { rss_kib: number("VmRSS"), high_water_kib: number("VmHWM") };
}

// Clean oracles are built and their child is disposed before the retained
// process starts, so /proc child discovery cannot confuse the two compilers.
const clean = await createNativeCompiler({ executable, threads });
const oracles = {} as Record<
  Variant,
  {
    artifact: Artifact;
    wasm_sha256: string;
    result: Awaited<ReturnType<typeof execute>>;
  }
>;
try {
  for (const selected of ["original", "edited"] as const) {
    variant = selected;
    const project = await loadSourceProject(entry, { imports, readSource });
    const artifact = await clean.compile(project, { const_steps: 100_000n });
    oracles[selected] = {
      artifact,
      wasm_sha256: await digest(artifact.bytes),
      result: await execute(artifact),
    };
  }
} finally {
  await clean.dispose();
}

const before = await children();
const session = await createNativeProjectCompiler({
  executable,
  threads,
  imports,
  readSource,
});
try {
  const initialPid = await nativePid(before);
  let previousPid = initialPid;
  let generation = 0;
  const rows: Array<Record<string, unknown>> = [];
  const initialRss = await rss(initialPid);
  async function compile(
    selected: Variant,
    phase: "first" | "body_edit" | "unchanged",
    edit: number,
  ) {
    variant = selected;
    const started = performance.now();
    const { artifact, stats } = await session.compile(entry, {
      const_steps: 100_000n,
    });
    const compileMs = performance.now() - started;
    equal(await execute(artifact), oracles[selected].result);
    const wasmSha256 = await digest(artifact.bytes);
    const pid = await nativePid(before);
    if (pid !== previousPid) {
      generation++;
      previousPid = pid;
    }
    const memory = await rss(pid);
    if (phase === "body_edit") {
      ok(!stats.result_reused && stats.declarations_sent >= 1);
    } else if (phase === "unchanged") {
      ok(stats.result_reused && stats.declarations_sent === 0);
    }
    rows.push({
      edit,
      phase,
      variant: selected,
      compile_ms: compileMs,
      native_pid: pid,
      generation,
      wasm_sha256: wasmSha256,
      wasm_equal: wasmSha256 === oracles[selected].wasm_sha256,
      analysis_equal: isDeepStrictEqual(
        artifact.analysis,
        oracles[selected].artifact.analysis,
      ),
      ...memory,
      cache_stats: stats,
    });
    if (edit % 10 === 0 && phase !== "unchanged") {
      console.log(
        `${edit}/${edits} edits, native RSS ${
          (memory.rss_kib / 1024).toFixed(1)
        } MiB`,
      );
    }
  }

  await compile("original", "first", 0);
  for (let edit = 1; edit <= edits; edit++) {
    const selected: Variant = edit % 2 === 1 ? "edited" : "original";
    await compile(selected, "body_edit", edit);
    await compile(selected, "unchanged", edit);
  }
  const report = {
    date: new Date().toISOString(),
    compiler_root: compilerRoot,
    application_root: applicationRoot,
    executable: fileURLToPath(executable),
    executable_sha256: await digest(await Deno.readFile(executable)),
    motion_sha256: {
      original: await digest(new TextEncoder().encode(original)),
      edited: await digest(new TextEncoder().encode(edited)),
    },
    oracle_wasm_sha256: {
      original: oracles.original.wasm_sha256,
      edited: oracles.edited.wasm_sha256,
    },
    edits,
    threads,
    native_pid: initialPid,
    generations: generation + 1,
    restarts: rows.filter((row) =>
      (row.cache_stats as { session_restarted?: boolean }).session_restarted
    ).length,
    initial_rss: initialRss,
    rows,
    final_rss: await rss(previousPid),
    behavior_parity: true,
  };
  await Deno.mkdir(dirname(reportPath), { recursive: true });
  await Deno.writeTextFile(reportPath, JSON.stringify(report, null, 2) + "\n");
  console.log(`Report: ${reportPath}`);
} finally {
  await session.dispose();
}
