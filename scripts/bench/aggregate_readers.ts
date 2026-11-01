// Actual Ink aggregate-return readers and wide-row updates, bounded to five seconds.
// deno run -A scripts/bench/aggregate_readers.ts --compiler PATH
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const repo = resolve(new URL("../../", import.meta.url).pathname);
const out = resolve(repo, "build/bench/aggregate-producer");
await Deno.mkdir(out, { recursive: true });
let executable = resolve(repo, "zig-native/zig-out-native-dev/bin/blotc");
if (Deno.args.length !== 0) {
  if (Deno.args.length !== 2 || Deno.args[0] !== "--compiler") {
    throw new Error("Expected --compiler PATH");
  }
  executable = resolve(repo, Deno.args[1]);
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
      source_files,
      source_sha256: await hash(new TextEncoder().encode(source)),
      deadline_ms: 5000,
      wall_ms: performance.now() - start,
      ...report,
    }));
  }
}
