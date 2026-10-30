// End-to-end asset reply experiment. Compiler RSS excludes the Deno client;
// process CPU includes all compiler threads. Every payload has an independent
// byte hash oracle and every guest is executed before its sample is accepted.
import { parseArgs } from "node:util";
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { fileDigest } from "../compiler_gate_state.ts";

const { values } = parseArgs({
  options: {
    baseline: { type: "string" },
    candidate: { type: "string" },
    out: { type: "string" },
    runs: { type: "string", default: "5" },
    "asset-mib": { type: "string", default: "8" },
  },
});
if (!values.baseline || !values.candidate || !values.out) {
  throw new Error("Require --baseline --candidate --out");
}
const runs = Number(values.runs), mib = Number(values["asset-mib"]);
if (
  !Number.isInteger(runs) || runs < 1 || runs > 30 || !Number.isInteger(mib) ||
  mib < 1 || mib > 16
) {
  throw new Error("Require 1..30 runs and 1..16 MiB per asset");
}
const out = resolve(values.out);
await Deno.mkdir(out); // Never overwrite an earlier experiment.
const directory = await Deno.makeTempDir({ prefix: "blot-assets-" });
const entry = directory + "/main.blot";
const source =
  'import * as a from "./a.bin"\nimport * as b from "./b.bin"\nentry const answer = func () => return do:\n  let #a.Content handle = a.content\n  break @u32.add handle 1\n';
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
const payloads = [
  new Uint8Array(mib * 1024 * 1024).fill(41),
  new Uint8Array(mib * 1024 * 1024).fill(173),
];
const expected = await Promise.all(payloads.map(hash));
const binaries = {
  baseline: resolve(values.baseline),
  candidate: resolve(values.candidate),
};
const pins = {
  baseline: await fileDigest(binaries.baseline),
  candidate: await fileDigest(binaries.candidate),
  runs,
  asset_mib: mib,
  asset_sha256: expected,
  source_sha256: await hash(new TextEncoder().encode(source)),
};
await Deno.writeTextFile(
  `${out}/pins.json`,
  JSON.stringify(pins, null, 2) + "\n",
);
const ticks = await new Deno.Command("getconf", {
  args: ["CLK_TCK"],
  stdout: "piped",
}).output();
if (!ticks.success) throw new Error("getconf CLK_TCK failed");
const ticksPerSecond = Number(new TextDecoder().decode(ticks.stdout).trim());
if (!(ticksPerSecond > 0)) throw new Error("Invalid CPU clock tick rate");
async function processStats(pid: number) {
  const [stat, status] = await Promise.all([
    Deno.readTextFile(`/proc/${pid}/stat`),
    Deno.readTextFile(`/proc/${pid}/status`),
  ]);
  const fields = stat.slice(stat.lastIndexOf(") ") + 2).trim().split(/\s+/);
  const kib = (name: string) =>
    Number(status.match(new RegExp(`^${name}:\\s+(\\d+)`, "m"))?.[1] ?? 0);
  return {
    ticks: Number(fields[11]) + Number(fields[12]),
    rss_kib: kib("VmRSS"),
    peak_rss_kib: kib("VmHWM"),
    swap_kib: kib("VmSwap"),
  };
}
const wasm = new Map<string, string>();
const samples: unknown[] = [];
try {
  await Deno.writeTextFile(entry, source);
  for (const [i, name] of ["a", "b"].entries()) {
    await Deno.writeFile(`${directory}/${name}.bin`, payloads[i]);
  }
  for (let run = 0; run < runs; run++) {
    const order = run % 2
      ? ["candidate", "baseline"] as const
      : ["baseline", "candidate"] as const;
    for (const variant of order) {
      const compiler = await createZigProjectCompiler({
        executable: binaries[variant],
        entry,
        prelude: null,
        cacheDirectory: false,
        nativeAssets: {
          imports: ["a", "b"].map((name) => ({
            module: `./${name}.bin`,
            path: `./${name}.bin`,
            kind: "reference",
            type: "Content",
            export: "content",
          })),
        },
      });
      try {
        for (
          const phase of ["fresh", "noop", "source-edit", "revert"] as const
        ) {
          const before = await processStats(compiler.pid);
          const start = performance.now();
          const result = await compiler.build({
            sources: {
              [entry]: phase === "source-edit"
                ? source.replace("handle 1", "handle 2")
                : source,
            },
          });
          const wall_ms = performance.now() - start;
          const after = await processStats(compiler.pid);
          if (!result.success) {
            throw new Error(JSON.stringify(result.diagnostics));
          }
          if (result.assets?.length !== 2) {
            throw new Error("Asset inventory mismatch");
          }
          for (let i = 0; i < 2; i++) {
            if (
              result.assets[i].id !== i + 1 ||
              await hash(result.assets[i].bytes) !== expected[i]
            ) throw new Error("Asset payload mismatch");
          }
          const digest = await hash(result.bytes);
          const key = phase === "source-edit" ? "edited" : "original";
          if (wasm.has(key) && wasm.get(key) !== digest) {
            throw new Error("Wasm mismatch across binaries/revisions");
          }
          wasm.set(key, digest);
          const { instance } = await WebAssembly.instantiate(result.bytes);
          if (
            (instance.exports.answer as CallableFunction)() !==
              (phase === "source-edit" ? 3 : 2)
          ) throw new Error("Guest result mismatch");
          const sample = {
            run,
            variant,
            phase,
            wall_ms,
            cpu_ms: (after.ticks - before.ticks) * 1000 / ticksPerSecond,
            before,
            after,
            wasm_sha256: digest,
            wasm_bytes: result.bytes.length,
            asset_bytes: payloads.reduce((n, p) => n + p.length, 0),
          };
          samples.push(sample);
          await Deno.writeTextFile(
            `${out}/samples.jsonl`,
            JSON.stringify(sample) + "\n",
            { append: true },
          );
          console.log(
            `${run} ${variant} ${phase}: ${
              wall_ms.toFixed(1)
            } ms, ${after.peak_rss_kib} KiB compiler HWM`,
          );
        }
      } finally {
        await compiler.dispose();
      }
    }
  }
  for (const variant of ["baseline", "candidate"] as const) {
    if (await fileDigest(binaries[variant]) !== pins[variant]) {
      throw new Error("Compiler changed during experiment");
    }
  }
  await Deno.writeTextFile(
    `${out}/results.json`,
    JSON.stringify(
      {
        success: true,
        pins,
        samples: samples.length,
        scope:
          "Client build latency and compiler process CPU/RSS; excludes client RSS and process startup. Asset hashes and guest results verified on every request.",
      },
      null,
      2,
    ) + "\n",
  );
} finally {
  await Deno.remove(directory, { recursive: true });
}
