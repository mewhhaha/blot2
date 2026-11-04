// Synthetic control for wide structural access records and repeated call setup.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const { values } = parseArgs({
  options: {
    baseline: { type: "string" },
    candidate: { type: "string" },
    fields: { type: "string", default: "165" },
    calls: { type: "string", default: "300" },
    "timeout-ms": { type: "string", default: "10000" },
    output: { type: "string", default: "build/bench/wide-access" },
  },
});
assert(
  values.baseline && values.candidate,
  "Require --baseline and --candidate",
);
const fields = Number(values.fields);
const calls = Number(values.calls);
const timeoutMs = Number(values["timeout-ms"]);
assert(Number.isInteger(fields) && fields >= 3 && fields <= 1000);
assert(Number.isInteger(calls) && calls >= 1 && calls <= 2000);
assert(Number.isInteger(timeoutMs) && timeoutMs >= 100 && timeoutMs <= 30000);
const field = (index: number) => `component_${String(index).padStart(4, "0")}`;
const names = Array.from({ length: fields }, (_, index) => field(index));
const middle = field(Math.floor(fields / 2));
const last = field(fields - 1);
const source = `const plus = func (input: U32): U32 => return @u32.add input 1
const leaf = func access: U32 => return
  @u32.add (access.step access.${
  names[0]
}[0]) (@u32.add access.${middle}[0] access.${last}[0])
entry const answer = func (input: U32): Array U32 => return do:
  let rows: Array U32 = #[input]
  @storage.write (@storage.at rows 0) input
  let access = {${
  names.map((name) => `${name}: rows`).join(", ")
}, step: plus, unused_a: plus, unused_b: plus}
  let total = 0
${
  Array.from({ length: calls }, () => "  total := @u32.add total (leaf access)")
    .join("\n")
}
  return #[total]
`;
const directory = resolve(values.output!);
await Deno.mkdir(directory, { recursive: true });
const evidence = await Deno.makeTempDir({ dir: directory, prefix: "pair-" });
const entry = `${evidence}/main.blot`;
await Deno.writeTextFile(entry, source);
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
const builds = [];
for (
  const [name, path] of [["baseline", values.baseline!], [
    "candidate",
    values.candidate!,
  ]]
) {
  const executable = resolve(path);
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
    cacheDirectory: false,
    startupTimeoutMs: 5000,
    profileBackend: true,
    codegenTier: "optimized",
  });
  try {
    const start = performance.now();
    const result = await compiler.build({
      sources: { [entry]: source },
      signal: AbortSignal.timeout(timeoutMs),
    });
    const buildMs = performance.now() - start;
    assert(result.success, JSON.stringify(result));
    assert(
      Number(
        (result.stats.workCounters as Record<string, number>)
          .scoped_emission_expressions,
      ) > 0,
      "Requires owned backend",
    );
    const guest = await instantiateGuest(result.bytes);
    try {
      for (const input of [0, 7, 0xffffffff]) {
        assert.deepEqual(
          guest.call("answer", input),
          new Uint32Array([
            Math.imul(calls, (Math.imul(input, 3) + 1) >>> 0) >>> 0,
          ]),
        );
      }
    } finally {
      guest.dispose();
    }
    const build = {
      name,
      executable,
      compiler_sha256: await hash(await Deno.readFile(executable)),
      identity: compiler.compilerIdentity,
      build_ms: buildMs,
      wasm_bytes: result.bytes.length,
      wasm_sha256: await hash(result.bytes),
      stats: result.stats,
    };
    builds.push(build);
    await Deno.writeFile(`${evidence}/${name}.wasm`, result.bytes);
    console.log(JSON.stringify(build));
  } finally {
    await compiler.dispose();
  }
}
await Deno.writeTextFile(
  `${evidence}/result.json`,
  JSON.stringify(
    {
      evidence,
      workload: "synthetic_wide_structural_access",
      fields,
      calls,
      timeout_ms: timeoutMs,
      source_sha256: await hash(new TextEncoder().encode(source)),
      builds,
    },
    null,
    2,
  ) + "\n",
);
