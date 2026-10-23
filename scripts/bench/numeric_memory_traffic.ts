import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import {
  numericAggregateSources,
  numericShapes,
} from "./numeric_aggregates.ts";
import { instrumentMemoryTraffic, traffic } from "./guest_copy_observer.ts";

const [before, after, outArg] = Deno.args;
assert(before && after && outArg);
const out = resolve(outArg),
  root = resolve(fileURLToPath(new URL("../..", import.meta.url)));
await Deno.mkdir(out);
const source = numericAggregateSources();
const entry = `${out}/main.blot`, library = `${out}/shapes.blot`;
const sources = { [entry]: source.main, [library]: source.shapes };
for (const [path, body] of Object.entries(sources)) {
  await Deno.writeTextFile(path, body);
}
const sha = async (bytes: Uint8Array<ArrayBuffer>) =>
  Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
const compilers = { baseline: resolve(before), candidate: resolve(after) };
const pins: Record<string, string> = {};
for (
  const p of [
    fileURLToPath(new URL(import.meta.url)),
    fileURLToPath(new URL("./guest_copy_observer.ts", import.meta.url)),
    ...Object.values(compilers),
  ]
) pins[p] = await sha(await Deno.readFile(p));
for await (const file of Deno.readDir(`${root}/std`)) {
  if (file.isFile && file.name.endsWith(".blot")) {
    const path = `${root}/std/${file.name}`;
    pins[path] = await sha(await Deno.readFile(path));
  }
}
const rows = [];
for (const tier of ["development", "optimized"] as const) {
  for (const [variant, executable] of Object.entries(compilers)) {
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      stdRoot: `${root}/std`,
      prelude: `${root}/std/prelude.blot`,
      cacheDirectory: false,
      codegenTier: tier,
      codegenWorkers: 1,
    });
    try {
      const result = await compiler.build({ sources });
      assert(result.success, JSON.stringify(result));
      await Deno.writeFile(`${out}/${tier}-${variant}.wasm`, result.bytes);
      const original =
        new WebAssembly.Instance(new WebAssembly.Module(result.bytes)).exports;
      const modified = instrumentMemoryTraffic(result.bytes);
      const observed =
        new WebAssembly.Instance(new WebAssembly.Module(modified)).exports;
      function invoke(
        exports: WebAssembly.Exports,
        name: string,
        arg: number,
        expected: number,
      ) {
        (exports["blot:ownership_enter"] as (() => void) | undefined)?.();
        try {
          assert.equal((exports[name] as (n: number) => number)(arg), expected);
        } finally {
          (exports["blot:ownership_leave"] as (() => void) | undefined)?.();
        }
      }
      for (const [shape] of numericShapes) {
        const cases = [
          ...["direct", "callback", "dynamic"].map((kind) => ({
            name: `${kind}_${shape}`,
            arg: kind === "dynamic" ? 1 : 5,
            expected: 200,
          })),
          ...[1, 32, 128, 512].map((n) => ({
            name: `array_${shape}`,
            arg: n,
            expected: 8 * n * n + 112 * n,
          })),
          { name: `snapshot_${shape}`, arg: 32, expected: 16240 },
          {
            name: `list_${shape}`,
            arg: 128,
            expected: 8 * 128 * 128 + 112 * 128 + 16120,
          },
          { name: `nested_edit_${shape}`, arg: 5, expected: 276 },
          { name: `constant_${shape}`, arg: 0, expected: 136 },
        ];
        for (const c of cases) {
          for (let i = 0; i < 20; i++) {
            invoke(original, c.name, c.arg, c.expected);
            invoke(observed, c.name, c.arg, c.expected);
          }
          const start = traffic(observed), calls = 100;
          for (let i = 0; i < calls; i++) {
            invoke(original, c.name, c.arg, c.expected);
            invoke(observed, c.name, c.arg, c.expected);
          }
          const end = traffic(observed);
          for (const name of ["blot:rc_roots", "blot:rc_leases"]) {
            assert.equal(
              (observed[name] as WebAssembly.Global | undefined)?.value ?? 0,
              0,
            );
          }
          rows.push({
            tier,
            variant,
            ...c,
            calls,
            per_call: Object.fromEntries(
              Object.keys(start).map((k) => [k, (end[k] - start[k]) / calls]),
            ),
          });
        }
      }
      console.log(
        `${tier} ${variant}: memory traffic and original/instrumented results match`,
      );
    } finally {
      await compiler.dispose();
    }
  }
}
for (const [path, hash] of Object.entries(pins)) {
  assert.equal(await sha(await Deno.readFile(path)), hash);
}
await Deno.writeTextFile(
  `${out}/report.json`,
  JSON.stringify(
    {
      pins,
      wabt: "1.0.39",
      source_sha256: await sha(
        new TextEncoder().encode(source.main + source.shapes),
      ),
      timestamp: new Date().toISOString(),
      scope:
        "Executed memory.copy and memory.fill lengths, plus scalar/vector load/store byte widths. Includes runtime ownership and allocator bookkeeping. Counts traffic, not live bytes. Instrumented modules are validated against original return values; never timed. Host memory reads, passive data initialization and instruction fetches excluded.",
      rows,
    },
    null,
    2,
  ) + "\n",
);
