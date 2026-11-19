// Measure the compiler's type-checking work independently of the size of Main.
import assert from "node:assert/strict";
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
const executable = resolve(Deno.args[0] ?? "compiler-goose/build/blotc-goose");
const directory = await Deno.makeTempDir();
const entry = resolve(directory, "main.blot");
function source(kind: string, size: number) {
  const lines = [];
  if (kind === "composition") {
    lines.push("func layer0 x => return (x, x)");
    for (let i = 1; i < size; i++) {
      lines.push(`func layer${i} x => return layer${i - 1} (layer${i - 1} x)`);
    }
  } else if (kind === "pair" || kind === "namedPair") {
    let constructor = "";
    if (kind === "namedPair") {
      lines.push("type Pair a is data = $Pair (a, a)");
      constructor = "$Pair ";
    }
    lines.push("func layer0 x => return x");
    for (let i = 1; i < size; i++) {
      lines.push(
        `func layer${i} x => return ${constructor}(layer${i - 1} x, layer${
          i - 1
        } x)`,
      );
    }
  } else {
    for (let i = 0; i < size; i++) {
      if (kind === "fields") lines.push(`func field${i} x => return x.value`);
      else if (kind === "annotated") {
        lines.push(`func field${i} (x: {value: U32}): U32 => return x.value`);
      } else lines.push(`func id${i} x => return x`);
    }
  }
  lines.push("entry const answer = 42");
  return lines.join("\n") + "\n";
}
try {
  // Isolate type inference so later passes cannot hide its scaling curve.
  for (const kind of ["pair", "namedPair", "composition"]) {
    let limit = 13;
    if (kind === "composition") limit = 11;
    for (let size = 1; size <= limit; size++) {
      await Deno.writeTextFile(entry, source(kind, size));
      const result = await new Deno.Command(executable, {
        args: ["check-project", entry, "--prelude", "none"],
        signal: AbortSignal.timeout(3000),
      }).output();
      const records = new TextDecoder().decode(result.stdout).trim().split("\n")
        .map((line) => JSON.parse(line));
      const check = records.find((row) => row.kind === "compilation");
      assert(check && check.success === result.success);
      const diagnostics = records.filter((row) => row.kind === "diagnostic")
        .map((row) => row.code);
      console.log(
        JSON.stringify({
          mode: "check",
          kind,
          size,
          success: check.success,
          diagnostics,
          nodes: check.type_nodes,
          checkUs: check.check_us,
        }),
      );
      if (!check.success) break;
    }
  }
  for (const kind of ["identity", "fields", "annotated", "composition"]) {
    let sizes = [32, 64, 128, 256, 512, 1024, 2048, 4096];
    if (kind === "composition") {
      sizes = Array.from({ length: 11 }, (_, index) => index + 1);
    }
    for (const size of sizes) {
      const body = source(kind, size);
      await Deno.writeTextFile(entry, body);
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        frontendWorkers: 1,
        profileBackend: true,
      });
      try {
        const start = performance.now();
        const result = await compiler.build({
          signal: AbortSignal.timeout(3000),
        });
        const ms = performance.now() - start;
        if (!result.success) {
          console.log(
            JSON.stringify({
              mode: "build",
              kind,
              size,
              ms,
              diagnostic: result.diagnostics.map((d) => d.code),
            }),
          );
          break;
        }
        const instance = await WebAssembly.instantiate(result.bytes);
        assert.equal(
          (instance.instance.exports.answer as WebAssembly.Global).value,
          42,
        );
        const profile = result.stats.phaseProfile;
        const check = profile.checking as Record<string, number>;
        const phases = profile.phases as Record<string, { us: number }>;
        console.log(JSON.stringify({
          mode: "build",
          kind,
          size,
          ms,
          bytes: body.length,
          checkUs: phases.check.us,
          bodies: result.stats.frontend.body_elaborations,
          scans: check.candidate_scans,
          candidates: check.candidates,
          nodes: check.type_nodes,
          schemeCalls: check.scheme_calls,
          wasm: new Uint8Array(
            await crypto.subtle.digest("SHA-256", result.bytes),
          ).toHex(),
        }));
      } catch (error) {
        if (
          !(error instanceof DOMException &&
            ["TimeoutError", "AbortError"].includes(error.name))
        ) throw error;
        console.log(
          JSON.stringify({ mode: "build", kind, size, timeoutMs: 3000 }),
        );
        break;
      } finally {
        await compiler.dispose();
      }
    }
  }
} finally {
  await Deno.remove(directory, { recursive: true });
}
