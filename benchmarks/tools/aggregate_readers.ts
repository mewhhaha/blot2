// Actual Ink aggregate-return readers and wide-row updates, bounded to five seconds.
// deno run -A benchmarks/tools/aggregate_readers.ts --compiler PATH
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";
const repo = resolve(new URL("../../", import.meta.url).pathname);
const out = resolve(repo, "build/bench/aggregate-producer");
await Deno.mkdir(out, { recursive: true });
let executable = resolve(repo, "compiler/zig-out-native-dev/bin/blotc");
let codegenTier: "development" | "optimized" = "optimized";
let codegenWorkers = 1;
for (let at = 0; at < Deno.args.length; at += 2) {
  const flag = Deno.args[at];
  const value = Deno.args[at + 1];
  if (value === undefined) throw new Error(`Missing value for ${flag}`);
  if (flag === "--compiler") executable = resolve(repo, value);
  else if (
    flag === "--tier" && (value === "development" || value === "optimized")
  ) {
    codegenTier = value;
  } else if (flag === "--workers" && /^(?:[1-9]|1[0-6])$/.test(value)) {
    codegenWorkers = Number(value);
  } else throw new Error(`Unsupported option: ${flag} ${value}`);
}
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((b) =>
    b.toString(16).padStart(2, "0")
  ).join("");
const compiler_sha256 = await hash(await Deno.readFile(executable));
const source_files = Object.fromEntries(
  await Promise.all([
    resolve(repo, "../ink/lib/transform.blot"),
    resolve(repo, "../ink/lib/math.blot"),
    resolve(repo, "../ink/lib/render.blot"),
    resolve(repo, "std/prelude.blot"),
  ].map(async (path) => [path, await hash(await Deno.readFile(path))])),
);
const names = "xx xy xz xw yx yy yz yw zx zy zz zw wx wy wz ww".split(" ");
for (const kind of ["matrix", "settings"]) {
  let sizes = [1, 4, 8];
  if (kind === "matrix") sizes = [2, 4, 6];
  for (const size of sizes) {
    const entry = `${out}/${kind}-${size}.blot`;
    const lines: string[] = [];
    if (kind === "matrix") {
      lines.push(
        'import * as transform from "ink/transform"',
        'import * as math from "ink/math"',
        "const leaf = func (rows: GrowArray transform.Pose3) -> (at: U32) => return transform.matrix rows[at]",
      );
      let previous = "leaf";
      for (let n = 1; n <= size; n++) {
        const next = `layer_${n}`;
        lines.push(
          `const ${next} = func (rows: GrowArray transform.Pose3) -> (at: U32) => return do:`,
          `  let left = ${previous} rows at`,
          `  let right = ${previous} rows at`,
          `  return $math.Mat4 { ${
            names.map((name) => `${name}: @f32.add left.${name} right.${name}`)
              .join(", ")
          } }`,
        );
        previous = next;
      }
      lines.push(
        "entry const answer = func (input: F32): F32 => return do:",
        "  let pose = $transform.Pose3 {position: math.zero3, rotation: math.identity_quat, scale: math.vec3 input 1.0 1.0}",
        "  let rows: GrowArray transform.Pose3 = #[pose]",
        `  let result = ${previous} rows 0`,
        "  return result.xx",
      );
    } else {
      lines.push(
        'import * as render from "ink/render"',
        "entry const answer = func (input: F32): F32 => return do:",
        "  let rows: Array render.Settings = #[render.defaults]",
      );
      for (let n = 0; n < size; n++) {
        lines.push("  rows[0].blur := @f32.add rows[0].blur input");
      }
      lines.push("  return rows[0].blur");
    }
    const source = lines.join("\n") + "\n";
    await Deno.writeTextFile(entry, source);
    let compiler;
    let guest;
    const start = performance.now();
    let report: Record<string, unknown>;
    try {
      compiler = await createZigProjectCompiler({
        executable,
        entry,
        stdRoot: `${repo}/std`,
        prelude: `${repo}/std/prelude.blot`,
        imports: { "ink/": resolve(repo, "../ink/lib") },
        cacheDirectory: false,
        codegenTier,
        codegenWorkers,
        profileBackend: true,
        startupTimeoutMs: 5000,
      });
      const begin = performance.now();
      const result = await compiler.build({
        sources: { [entry]: source },
        signal: AbortSignal.timeout(5000),
      });
      const build_ms = performance.now() - begin;
      if (!result.success) {
        report = {
          status: "failed",
          build_ms,
          diagnostics: result.diagnostics,
        };
        Deno.exitCode = 1;
      } else {
        guest = await instantiateGuest(result.bytes);
        for (const input of [0, 1, 3.5, -2, 0.125]) {
          const actual = guest.call("answer", input);
          let expected = 0;
          if (kind === "matrix") expected = Math.fround(input * 2 ** size);
          else {for (let n = 0; n < size; n++) {
              expected = Math.fround(expected + input);
            }}
          if (actual !== expected) {
            throw new Error(
              `${kind}/${size} ${input}: ${actual} != ${expected}`,
            );
          }
        }
        await Deno.writeFile(`${out}/${kind}-${size}.wasm`, result.bytes);
        report = {
          status: "complete",
          build_ms,
          wasm_bytes: result.bytes.length,
          wasm_sha256: await hash(result.bytes),
          stats: result.stats,
          executed: true,
        };
      }
    } catch (e) {
      report = { status: "failed_or_timeout", error: String(e) };
      Deno.exitCode = 1;
    } finally {
      guest?.dispose();
      await compiler?.dispose();
    }
    console.log(JSON.stringify({
      diagnostic_only: true,
      kind,
      size,
      compiler_sha256,
      codegen_tier: codegenTier,
      codegen_workers: codegenWorkers,
      source_files,
      source_sha256: await hash(new TextEncoder().encode(source)),
      deadline_ms: 5000,
      wall_ms: performance.now() - start,
      ...report,
    }));
  }
}
