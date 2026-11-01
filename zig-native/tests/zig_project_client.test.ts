import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import {
  createZigProjectCompiler,
  type ZigProjectBuildResult,
  type ZigProjectCompiler,
  type ZigProjectCompilerOptions,
} from "../../compiler/zig_project_client.ts";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

const executable = resolve(
  Deno.args[0] ??
    fileURLToPath(new URL("../zig-out/bin/blotc", import.meta.url)),
);
async function sha(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
  ).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
// Dependency provenance independently supplies the identity for
// the same executable's project server, without machine-specific proof pins.
async function verified(directory: string): Promise<string> {
  const seed = directory + "/identity";
  await Deno.mkdir(seed);
  const entry = seed + "/main.blot", bundle = seed + "/dependencies.blotdep";
  await Deno.writeTextFile(seed + "/library.blot", "const value = 42\n");
  await Deno.writeTextFile(
    entry,
    'import {value} from "./library"\nentry const answer = value\n',
  );
  const rows = await command(directory, "identity-bundle", [
    "dependencies",
    entry,
    bundle,
    "--prelude",
    "none",
  ]);
  const bytes = await Deno.readFile(bundle);
  ok(bytes.length >= 212);
  equal(new TextDecoder().decode(bytes.subarray(0, 8)), "BLOTDEP1");
  equal(new DataView(bytes.buffer).getUint32(8, true), 5);
  const identity = Array.from(
    bytes.subarray(44, 76),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  equal(
    rows.find((row) => row.kind === "cache_metrics").compiler_identity,
    identity,
  );
  return identity;
}
async function fixture(prefix: string) {
  const before = await sha(await Deno.readFile(executable));
  const directory = await Deno.makeTempDir({ prefix });
  return {
    directory,
    async cleanup() {
      equal(await sha(await Deno.readFile(executable)), before);
      await Deno.remove(directory, { recursive: true });
    },
  };
}
function success(result: ZigProjectBuildResult) {
  ok(result.success, JSON.stringify(result));
  return result;
}
async function answer(result: ZigProjectBuildResult, value: number) {
  const built = success(result);
  const module = await WebAssembly.instantiate(built.bytes);
  const export_ = module.instance.exports.answer;
  equal(
    typeof export_ === "function"
      ? export_(0)
      : (export_ as WebAssembly.Global).value,
    value,
  );
  ok(
    !Object.hasOwn(built, "const_steps") &&
      !Object.hasOwn(built, "remaining_steps"),
  );
  ok(Number.isSafeInteger(built.stats.nativeWorkSteps));
}
async function command(
  directory: string,
  label: string,
  args: string[],
  expected = true,
) {
  const argv = [executable, ...args];
  const result = await new Deno.Command(executable, {
    args,
    clearEnv: true,
    stdout: "piped",
    stderr: "piped",
  }).output();
  await Deno.writeTextFile(
    directory + "/" + label + ".argv.json",
    JSON.stringify(argv, null, 2) + "\n",
  );
  await Deno.writeFile(directory + "/" + label + ".stdout", result.stdout);
  await Deno.writeFile(directory + "/" + label + ".stderr", result.stderr);
  await Deno.writeTextFile(
    directory + "/" + label + ".exit.json",
    JSON.stringify({ exit: result.code }) + "\n",
  );
  equal(result.success, expected);
  equal(result.stderr.length, 0);
  const rows = new TextDecoder().decode(result.stdout).trim().split("\n").map(
    (line) => JSON.parse(line),
  );
  for (const row of rows) if (row.memory) equal(row.memory.live_bytes, 0);
  return rows;
}
async function fresh(
  directory: string,
  entry: string,
  result: ZigProjectBuildResult,
  label: string,
  aliases: string[] = [],
) {
  const output = directory + "/" + label + ".wasm";
  await command(directory, label, [
    "build-project",
    entry,
    output,
    "--prelude",
    "none",
    ...aliases,
  ]);
  equal(success(result).bytes, await Deno.readFile(output));
  await Deno.writeTextFile(
    directory + "/" + label + ".client.json",
    JSON.stringify(
      {
        revision: result.revision,
        success: result.success,
        stats: success(result).stats,
        wasmSha256: await sha(success(result).bytes),
      },
      null,
      2,
    ) + "\n",
  );
}
function reaped(pid: number) {
  try {
    Deno.kill(pid, 0);
    throw new Error("Owned child survived close");
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
}

Deno.test("Zig project client streams bounded profile trace through disposal", async () => {
  const item = await fixture("blot-zig-project-trace-");
  const { directory } = item;
  const entry = directory + "/main.blot";
  const readyPath = directory + "/third-ready";
  const peerSource = String.raw`
const encoder = new TextEncoder();
const readyPath = ${JSON.stringify(readyPath)};
async function readExact(length: number) {
  const bytes = new Uint8Array(length);
  let offset = 0;
  while (offset < length) {
    const count = await Deno.stdin.read(bytes.subarray(offset));
    if (count === null) Deno.exit();
    offset += count;
  }
  return bytes;
}
async function writeFrame(metadata: unknown) {
  const json = encoder.encode(JSON.stringify(metadata));
  const bytes = new Uint8Array(8 + json.length);
  const view = new DataView(bytes.buffer);
  view.setUint32(0, json.length, true);
  bytes.set(json, 8);
  let offset = 0;
  while (offset < bytes.length) offset += await Deno.stdout.write(bytes.subarray(offset));
}
async function trace(line: string) {
  const bytes = encoder.encode(line);
  await Deno.stderr.write(bytes.subarray(0, 11));
  await Deno.stderr.write(bytes.subarray(11));
}
async function record(value: Record<string, unknown>) {
  await trace("BLOT_PROFILE " + JSON.stringify({ ...value, space: value.space ?? "source" }) + "\n");
}
async function rejectBuild(metadata: Record<string, any>) {
  await writeFrame({kind:"build",id:metadata.id,epoch:"trace",revision:0,success:false,diagnostics:[{filename:"main.blot",stage:"check",code:"fixture",message:"expected",start:0,end:0,offset_encoding:"utf8_bytes"}],attemptStats:null});
}
await writeFrame({
  kind: "hello",
  protocol: "blot-zig-project",
  version: 1,
  maxFrameBytes: 67108864,
  compilerIdentity: "a".repeat(64),
  capabilities: ["project-build", "utf8_bytes", "abort-disposes-process", "source-overlays"],
});
let buildCount = 0;
let firstBuild = 0;
while (true) {
  const header = await readExact(8);
  const view = new DataView(header.buffer);
  const metadata = JSON.parse(new TextDecoder().decode(await readExact(view.getUint32(0, true))));
  await readExact(view.getUint32(4, true));
  if (metadata.kind === "open") {
    if (metadata.profileTrace !== true || metadata.profileBackend !== true) Deno.exit(42);
    await writeFrame({ kind: "open", id: metadata.id, epoch: "trace", revision: 0 });
  } else if (metadata.kind === "build") {
    buildCount++;
    if (buildCount === 1) firstBuild = metadata.id;
    if (buildCount === 1) {
      await record({kind:"module",build:metadata.id,unit:1,filename:"build-one.blot",bytes:41});
      await rejectBuild(metadata);
    } else if (buildCount === 2) {
      await record({kind:"module",build:firstBuild,unit:99,filename:"late-old.blot",bytes:999});
      await record({kind:"end",build:firstBuild,id:199,thread:1,stage:"check.module",unit:2,start:0,end:1,at_us:80,us:9000,cpu_us:9000,input_items:0,output_items:0});
      await record({kind:"module",build:metadata.id,unit:1,filename:"build-two.blot",bytes:42});
      await record({kind:"module",build:metadata.id,space:"core",unit:1,filename:"core-two.blot",bytes:0});
      await record({kind:"phases",build:metadata.id,active:"check",phase_us:Array(11).fill(7),at_us:90});
      await record({kind:"begin",build:metadata.id,id:200,thread:1,stage:"long",unit:2,start:0,end:1,at_us:91});
      await record({kind:"end",build:metadata.id,id:202,thread:1,stage:"check.module",unit:1,start:0,end:1,at_us:92,us:7,cpu_us:4,input_items:0,output_items:0});
      await record({kind:"end",build:metadata.id,id:203,thread:1,stage:"check.module",unit:1,start:0,end:1,at_us:93,us:11,cpu_us:5,input_items:0,output_items:0});
      await record({kind:"end",build:metadata.id,space:"core",id:204,thread:1,stage:"check.module",unit:1,start:0,end:1,at_us:94,us:3,cpu_us:1,input_items:0,output_items:0});
      await trace('BLOT_PROFILE {broken json}\n');
      await trace("x".repeat(70000) + "\n");
      for (let index = 0; index < 300; index++) {
        await record({kind:"detail",build:metadata.id,thread:1,stage:"body",unit:2,start:index,end:index+1,items:index,at_us:100+index});
      }
      await record({kind:"end",build:metadata.id,id:201,thread:1,stage:"lower",unit:2,start:0,end:1,at_us:500,us:12,cpu_us:null,input_items:345,output_items:123});
      await rejectBuild(metadata);
    } else {
      await record({kind:"module",build:metadata.id,unit:3,filename:"cancelled.blot",bytes:43});
      await Deno.writeTextFile(readyPath, String(metadata.id));
      await readExact(8);
    }
  } else if (metadata.kind === "close") {
    await writeFrame({ kind: "close", id: metadata.id, epoch: "trace", revision: 0 });
    break;
  }
}
`;
  const peerScript = directory + "/peer.ts";
  const executable = directory + "/peer";
  const quote = (value: string) => "'" + value.replaceAll("'", "'\\''") + "'";
  await Deno.writeTextFile(peerScript, peerSource);
  await Deno.writeTextFile(
    executable,
    `#!/bin/sh\nexec ${
      quote(Deno.execPath())
    } run --quiet --no-config --no-lock --allow-all ${
      quote(peerScript)
    } "$@"\n`,
  );
  await Deno.chmod(executable, 0o755);
  await Deno.writeTextFile(entry, "entry const answer = 1\n");
  try {
    await rejects(
      createZigProjectCompiler({
        executable,
        entry,
        profileTrace: "yes" as never,
      }),
      /profileTrace must be a boolean/,
    );
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      cacheDirectory: false,
      profileBackend: true,
      profileTrace: true,
    });
    const pid = compiler.pid;
    const queued = await Promise.all([compiler.build(), compiler.build()]);
    ok(queued.every((result) => !result.success));
    const isolated = compiler.profileProgress;
    ok(isolated);
    const controller = new AbortController();
    const cancelled = compiler.build({ signal: controller.signal });
    let buildId: string | null = null;
    for (let attempt = 0; attempt < 100; attempt++) {
      try {
        buildId = await Deno.readTextFile(readyPath);
        break;
      } catch {
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
    }
    ok(buildId !== null, "third build did not reach the trace peer");
    controller.abort();
    await rejects(
      cancelled,
      (error) => error instanceof DOMException && error.name === "AbortError",
    );
    await compiler.dispose();
    reaped(pid);
    const progress = compiler.profileProgress;
    ok(progress);
    equal(progress.events.length, 1);
    equal(progress.events[0], {
      kind: "module",
      build: Number(buildId),
      space: "source",
      unit: 3,
      filename: "cancelled.blot",
      bytes: 43,
    });
    equal(progress.modules, [{
      space: "source",
      unit: 3,
      filename: "cancelled.blot",
      bytes: 43,
    }]);
    equal(progress.phases, null);
    equal(progress.activeRegions, []);
    equal(progress.slowRegions, []);
    equal(progress.dropped, 0);

    equal(isolated.events.length, 256);
    equal(isolated.events[0].kind, "detail");
    const last = isolated.events.at(-1);
    equal(last?.kind, "end");
    if (last?.kind === "end") {
      equal(last.input_items, 345);
      equal(last.output_items, 123);
    }
    equal(isolated.dropped, 52);
    equal(isolated.modules, [{
      space: "source",
      unit: 1,
      filename: "build-two.blot",
      bytes: 42,
    }, {
      space: "core",
      unit: 1,
      filename: "core-two.blot",
      bytes: 0,
    }]);
    equal(isolated.phases?.phase_us, Array(11).fill(7));
    equal(isolated.activeRegions.map((region) => region.id), [200]);
    equal(isolated.slowRegions.map((region) => region.us), [12, 11, 7, 3]);
    equal(isolated.moduleTimings, [{
      space: "source",
      unit: 1,
      calls: 2,
      us: 18,
      cpuUs: 9,
      cpuAvailable: true,
    }, {
      space: "core",
      unit: 1,
      calls: 1,
      us: 3,
      cpuUs: 1,
      cpuAvailable: true,
    }]);
  } finally {
    await item.cleanup();
  }
});

Deno.test("Zig project client queues revisions and preserves entry edit/error/missing/correction bytes", async () => {
  const item = await fixture("blot-zig-project-entry-");
  const { directory } = item;
  const entry = directory + "/main.blot";
  let compiler: ZigProjectCompiler | undefined;
  const original = "entry const answer: Unit -> U32 = func () => return 42\n";
  try {
    await Deno.writeTextFile(entry, original);
    const identity = await verified(directory);
    compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      expectedCompilerIdentity: identity,
    });
    const pid = compiler.pid;
    equal(compiler.compilerIdentity, identity);
    const queued = await Promise.all([compiler.build(), compiler.build()]);
    equal(queued.map((result) => result.revision), [1, 2]);
    await answer(queued[0], 42);
    await answer(queued[1], 42);
    await fresh(directory, entry, queued[1], "initial");
    success(queued[0]).bytes.fill(0);
    success(queued[0]).stats.nativeWorkSteps = 999;
    await answer(queued[1], 42);
    ok(success(queued[1]).stats.nativeWorkSteps !== 999);
    await Deno.writeTextFile(entry, original.replace("42", "43"));
    const edited = await compiler.build();
    equal(edited.revision, 3);
    await answer(edited, 43);
    await fresh(directory, entry, edited, "edited");
    await Deno.writeTextFile(entry, "// 🌧\nentry const answer = missing\n");
    const rejected = await compiler.build();
    ok(!rejected.success);
    equal(rejected.revision, 3);
    equal(rejected.diagnostics[0].offset_encoding, "utf8_bytes");
    ok(rejected.attemptStats !== null);
    await Deno.writeTextFile(
      directory + "/rejected.client.json",
      JSON.stringify(rejected, null, 2) + "\n",
    );
    await Deno.remove(entry);
    const missing = await compiler.build();
    ok(!missing.success);
    equal(missing.revision, 3);
    ok(missing.attemptStats !== null);
    equal(
      (missing.attemptStats.inputs as { source_reads: number }).source_reads,
      0,
    );
    equal(
      (missing.attemptStats.fallback as { body_elaborations: number })
        .body_elaborations,
      0,
    );
    ok(
      JSON.stringify(missing.attemptStats) !==
        JSON.stringify(success(edited).stats.attemptStats),
    );
    await Deno.writeTextFile(
      directory + "/missing.client.json",
      JSON.stringify(missing, null, 2) + "\n",
    );
    await Deno.writeTextFile(entry, original);
    const restored = await compiler.build();
    equal(restored.revision, 4);
    await answer(restored, 42);
    await fresh(directory, entry, restored, "restored");
    equal(success(restored).bytes, success(queued[1]).bytes);
    await compiler.close();
    reaped(pid);
  } finally {
    try {
      await compiler?.dispose();
    } finally {
      await item.cleanup();
    }
  }
});

Deno.test("Zig project client keeps lexical alias roots through retargeting and compiled dependency admission", async () => {
  const item = await fixture("blot-zig-project-imports-");
  const { directory } = item;
  let compiler: ZigProjectCompiler | undefined;
  try {
    const left = directory + "/left",
      right = directory + "/right",
      link = directory + "/producers";
    await Deno.mkdir(left);
    await Deno.mkdir(right);
    await Deno.writeTextFile(
      left + "/library.blot",
      "const exported_value = 40\n",
    );
    await Deno.writeTextFile(
      right + "/library.blot",
      "const exported_value = 60\n",
    );
    await Deno.symlink(left, link);
    const entry = directory + "/main.blot";
    await Deno.writeTextFile(
      entry,
      'import {exported_value} from "lib/library"\nentry const answer: Unit -> U32 = func () => return @u32.add exported_value 2\n',
    );
    const aliases = ["--alias", "lib/=" + link],
      options: ZigProjectCompilerOptions = {
        executable,
        entry,
        prelude: null,
        // This law measures explicit dependency admission, not restart reuse.
        cacheDirectory: false,
        imports: { "lib/": link },
      };
    const identity = await verified(directory);
    options.expectedCompilerIdentity = identity;
    compiler = await createZigProjectCompiler(options);
    const initial = await compiler.build();
    await answer(initial, 42);
    await fresh(directory, entry, initial, "project-initial", aliases);
    await Deno.remove(link);
    await Deno.symlink(right, link);
    const retargeted = await compiler.build();
    equal(retargeted.revision, 2);
    await answer(retargeted, 62);
    await fresh(directory, entry, retargeted, "project-retargeted", aliases);
    await Deno.remove(right + "/library.blot");
    const missing = await compiler.build();
    ok(!missing.success);
    equal(missing.revision, 2);
    await Deno.writeTextFile(
      right + "/library.blot",
      "const exported_value = 60\n",
    );
    const restored = await compiler.build();
    equal(restored.revision, 3);
    await answer(restored, 62);
    await compiler.close();
    reaped(compiler.pid);
    const bundle = directory + "/dependencies.blotdep";
    await command(directory, "bundle-create", [
      "dependencies",
      entry,
      bundle,
      "--prelude",
      "none",
      ...aliases,
    ]);
    compiler = await createZigProjectCompiler({
      ...options,
      dependencies: bundle,
    });
    const cached = await compiler.build();
    equal(cached.revision, 1);
    await answer(cached, 62);
    ok(success(cached).stats.cachedModules === 1);
    await fresh(directory, entry, cached, "project-cached", aliases);
    await Deno.writeTextFile(
      right + "/library.blot",
      "const exported_value = 61\n",
    );
    const changed = await compiler.build();
    equal(changed.revision, 2);
    await answer(changed, 63);
    await fresh(directory, entry, changed, "project-dependency-edit", aliases);
    await compiler.close();
    reaped(compiler.pid);
  } finally {
    try {
      await compiler?.dispose();
    } finally {
      await item.cleanup();
    }
  }
});

Deno.test("Zig project client rejects an incompatible dependency schema during open without fallback", async () => {
  const item = await fixture("blot-zig-project-decline-");
  const { directory } = item, entry = directory + "/main.blot";
  try {
    await Deno.writeTextFile(entry, "entry const answer = 42\n");
    const identity = await verified(directory);
    const valid = await Deno.readFile(
      directory + "/identity/dependencies.blotdep",
    );
    const incompatible = valid.slice();
    // The fixed schema digest starts after magic and version.
    // Preserve provenance, payload and checksum; invalidate only this schema.
    incompatible[12] ^= 1;
    equal(incompatible.subarray(0, 12), valid.subarray(0, 12));
    equal(incompatible.subarray(13), valid.subarray(13));
    const bundle = directory + "/incompatible.blotdep";
    await Deno.writeFile(bundle, incompatible);
    await rejects(
      createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        dependencies: bundle,
        expectedCompilerIdentity: identity,
      }),
      /SchemaMismatch/,
    );
    equal(await Deno.readFile(bundle), incompatible);
    equal(await Deno.readTextFile(entry), "entry const answer = 42\n");
  } finally {
    await item.cleanup();
  }
});

Deno.test("chunk runtime and static chains survive dependency bundles and retained entry edits", async () => {
  const item = await fixture("blot-zig-project-collections-");
  const { directory } = item, entry = directory + "/main.blot";
  let compiler: ZigProjectCompiler | undefined;
  const source = (offset: number) =>
    `import * as lists from "./lists"
entry const answer = func () => return @u32.add (lists.read 40) ${offset}
`;
  try {
    await Deno.writeTextFile(
      directory + "/lists.blot",
      `
const frozen = @list.generate 513 (func index => return index)
const first = func values => return (@array.from_list values)[0]
const read = func (seed: U32) => return do:
  let values = @array.from_list [seed, ...[2, 3], 4]
  values[1] := (@array.from_list frozen)[512]
  let array = @array.from_list [value | value <- values, @u32.lt 0 value]
  break first (@list.from_array array)
`,
    );
    await Deno.writeTextFile(entry, source(2));
    const identity = await verified(directory);
    const bundle = directory + "/collections.blotdep";
    await command(directory, "collection-bundle", [
      "dependencies",
      entry,
      bundle,
      "--prelude",
      "none",
    ]);
    for (const dependencies of [undefined, bundle]) {
      const label = dependencies ? "cached" : "source";
      await Deno.writeTextFile(entry, source(2));
      compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        dependencies,
        expectedCompilerIdentity: identity,
      });
      for (const offset of [2, 3, 2]) {
        await Deno.writeTextFile(entry, source(offset));
        const result = await compiler.build();
        await answer(result, 40 + offset);
        await fresh(directory, entry, result, `${label}-${result.revision}`);
      }
      await Deno.writeTextFile(entry, "entry const broken: Array U32 = [1]\n");
      ok(!(await compiler.build()).success);
      await Deno.writeTextFile(entry, source(2));
      await answer(await compiler.build(), 42);
      await compiler.close();
    }
  } finally {
    try {
      await compiler?.dispose();
    } finally {
      await item.cleanup();
    }
  }
});
