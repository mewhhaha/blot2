/** Paired hot-path measurements, not a claim about whole-application speed.
 * Build both checkouts with the same Bend release before running:
 * deno run --allow-read --allow-write=build compiler/runtime_bench.ts /path/to/baseline
 */
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { Fifo } from "./fifo.ts";
import { instantiateGuest } from "./guest.ts";
import { parserSource } from "./parser_source.ts";
import { createSourceCompiler } from "./source.ts";
import { createFrontend, type PreparedSource } from "./syntax.ts";

const baselineRoot = Deno.args[0];
if (!baselineRoot || Deno.args.length > 1) {
  throw new Error("Usage: runtime_bench.ts /path/to/built/baseline-checkout");
}
const baselineUrl = pathToFileURL(resolve(baselineRoot) + "/");
const baselineSource = await import(
  new URL("compiler/source.ts", baselineUrl).href
) as {
  createSourceCompiler: typeof createSourceCompiler;
};
const baselineHost = await import(
  new URL("compiler/guest.ts", baselineUrl).href
) as {
  instantiateGuest: typeof instantiateGuest;
};
const source = `
entry const echo_u32 = fn (values: Array U32) => values
entry const echo_f32 = fn (values: Array F32) => values
entry const fill = fn (count: U32) => @array.fill count 0x12345678
`;
const oldCompiler = await baselineSource.createSourceCompiler({
  prelude: "none",
});
const newCompiler = await createSourceCompiler({ prelude: "none" });
const oldBytes = oldCompiler.compile(source).bytes;
const newBytes = newCompiler.compile(source).bytes;
oldCompiler.dispose();
newCompiler.dispose();
const oldGuest = await baselineHost.instantiateGuest(oldBytes);
const newGuest = await instantiateGuest(newBytes);
const oldWasm = (await WebAssembly.instantiate(oldBytes)).instance.exports;
const newWasm = (await WebAssembly.instantiate(newBytes)).instance.exports;
const rows: {
  name: string;
  iterations: number;
  baseline_ms: number[];
  candidate_ms: number[];
  baseline_median_ms: number;
  candidate_median_ms: number;
  speedup: number;
}[] = [];
let sink = 0;
function sample(fn: () => number, iterations: number) {
  const started = performance.now();
  let result = 0;
  for (let i = 0; i < iterations; i++) result = (result + fn()) >>> 0;
  const ms = (performance.now() - started) / iterations;
  sink = (sink ^ result) >>> 0;
  return ms;
}
const median = (values: number[]) =>
  [...values].sort((a, b) => a - b)[values.length >>> 1];
function paired(
  name: string,
  baseline: () => number,
  candidate: () => number,
  iterations: number,
) {
  // Match output before timing. Alternate order to reduce systematic warmup bias.
  equal(candidate(), baseline(), name);
  sample(baseline, iterations);
  sample(candidate, iterations);
  const before: number[] = [], after: number[] = [];
  for (let round = 0; round < 11; round++) {
    if (round % 2 === 0) {
      before.push(sample(baseline, iterations));
      after.push(sample(candidate, iterations));
    } else {
      after.push(sample(candidate, iterations));
      before.push(sample(baseline, iterations));
    }
  }
  const b = median(before), a = median(after);
  rows.push({
    name,
    iterations,
    baseline_ms: before,
    candidate_ms: after,
    baseline_median_ms: b,
    candidate_median_ms: a,
    speedup: b / a,
  });
  console.log(
    `${name}: ${b.toFixed(4)} -> ${a.toFixed(4)} ms (${(b / a).toFixed(2)}x)`,
  );
}

try {
  for (const length of [0, 16, 32, 33, 1024, 65536, 1048576]) {
    const repetitions = Math.max(
      16,
      Math.min(20000, Math.floor(16777216 / Math.max(1, length))),
    );
    const fill = (exports: WebAssembly.Exports) => {
      (exports["blot:reset"] as CallableFunction)(0);
      const pointer = (exports.fill as CallableFunction)(length) >>> 0;
      const words = new Uint32Array(
        (exports["blot:memory"] as WebAssembly.Memory).buffer,
        pointer,
        length + 1,
      );
      // Consume only the last word while timing. Validate every word separately.
      return words[length];
    };
    for (const exports of [oldWasm, newWasm]) {
      (exports["blot:reset"] as CallableFunction)(0);
      const pointer = (exports.fill as CallableFunction)(length) >>> 0;
      const words = new Uint32Array(
        (exports["blot:memory"] as WebAssembly.Memory).buffer,
        pointer,
        length + 1,
      );
      equal(words[0], length);
      equal(words.subarray(1), new Uint32Array(length).fill(0x12345678));
    }
    paired(
      `Wasm fill ${length} words`,
      () => fill(oldWasm),
      () => fill(newWasm),
      repetitions,
    );
    if (length === 0 || length === 32 || length === 33) continue;
    for (
      const [name, input] of [
        [
          "echo_u32",
          new Uint32Array(length + 2).fill(0x12345678).subarray(1, length + 1),
        ],
        [
          "echo_f32",
          new Float32Array(length + 2).fill(1.25).subarray(1, length + 1),
        ],
      ] as const
    ) {
      equal(oldGuest.call(name, input), newGuest.call(name, input));
      const echo = (guest: typeof newGuest) => {
        const output = guest.call(name, input) as Uint32Array | Float32Array;
        return output.length + output[output.length - 1];
      };
      paired(
        `ABI ${name} ${length} words`,
        () => echo(oldGuest),
        () => echo(newGuest),
        repetitions,
      );
    }
  }

  // Frozen normalization algorithm from main ac59fb6. Both paths receive the
  // identical already-lexed input; lexing, typechecking and codegen are excluded.
  function previousParserSource(prepared: PreparedSource) {
    const chars = prepared.source.split("");
    for (const at of prepared.clauseMarkers) chars[at + 4] = "E";
    for (const token of prepared.tokens) {
      if (token.type === "named" && token.kind === "INTEGER") {
        chars.fill("0", token.span.start, token.span.end);
      }
    }
    return chars.join("");
  }
  const frontend = await createFrontend();
  try {
    for (const declarations of [16, 2048]) {
      const input = frontend.prepare(
        Array.from(
          { length: declarations },
          (_, i) =>
            `// Unicode 🙂\nconst n_${i}: U32 where { self < 4294967295 } = ${i}\n`,
        )
          .join(""),
      );
      equal(parserSource(input), previousParserSource(input));
      paired(
        `Parser normalization ${declarations} declarations`,
        () => previousParserSource(input).length,
        () => parserSource(input).length,
        declarations === 16 ? 500 : 40,
      );
    }
  } finally {
    frontend.dispose();
  }

  for (const size of [128, 32768]) {
    const drain = (queue: number[] | Fifo<number>) => {
      for (let i = 0; i < size; i++) queue.push(i);
      let sum = 0;
      while (queue.length) sum += queue.shift()!;
      return sum;
    };
    equal(drain(new Fifo()), (size - 1) * size / 2);
    paired(
      `FIFO enqueue + drain ${size} jobs`,
      () => drain([]),
      () => drain(new Fifo()),
      size === 128 ? 500 : 3,
    );
  }
} finally {
  oldGuest.dispose();
  newGuest.dispose();
}
await Deno.mkdir("build", { recursive: true });
const report = {
  deno: Deno.version,
  architecture: Deno.build,
  baselineRoot: resolve(baselineRoot),
  samples: 11,
  statistic: "ratio of medians; milliseconds per operation",
  caveats:
    "Microbenchmarks only. Compilation, startup and GPU/render work excluded. Shared-runner timings are noisy; no timing gate.",
  sink,
  rows,
};
await Deno.writeTextFile(
  "build/runtime-performance.json",
  JSON.stringify(report, null, 2) + "\n",
);
ok(rows.length > 0);
