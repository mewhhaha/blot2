// Controlled source-level comparison of four ways to manage N typed ECS cells.
// Run: deno run --allow-all compiler/ecs_schema_experiment.ts [samples] [counts] [threads] [compiler-root] [report-path]
import { dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { deepStrictEqual as equal } from "node:assert/strict";
import {
  matchingNativeChild,
  nativeCpuHz,
  nativeCpuMilliseconds,
  nativeCpuSample,
  nativeScheduler,
  ownedNativeChildren,
} from "./native_cpu_bench.ts";

type Variant =
  | "builder"
  | "fixed_handlers"
  | "direct_accessors"
  | "direct_record";
const variants: Variant[] = [
  "builder",
  "fixed_handlers",
  "direct_accessors",
  "direct_record",
];
const samples = Number(Deno.args[0] ?? "3");
const counts = (Deno.args[1] ?? "2,4,8,16").split(",").map(Number);
const threads = Number(Deno.args[2] ?? "1");
const compilerRoot = resolve(Deno.args[3] ?? ".");
const reportPath = Deno.args[4] ?? "build/gdev-ecs-experiment/results.json";
if (
  !Number.isInteger(samples) || samples < 1 || samples > 20 ||
  counts.length === 0 ||
  counts.some((n) => !Number.isInteger(n) || n < 1 || n > 24) ||
  !Number.isInteger(threads) || threads < 1 || threads > 8
) {
  throw new Error(
    "Usage: ecs_schema_experiment.ts [samples:1..20] [counts:1..24,...] [threads:1..8] [compiler-root] [report-path]",
  );
}

const cells = (count: number) => Array.from({ length: count }, (_, i) => i);
const common = (count: number) => `
${cells(count).map((i) => `type Cell${i} is data = #Cell${i} U32`).join("\n")}
type State a is effect = {
  get: Unit -> a
  set: a -> Unit
}
const get = fn (witness: p -> a) -> a => State.get ()
const set = fn value => State.set value
const action = fn delta => fn () => do:
${
  cells(count).map((i) =>
    `  use value${i} <- get #Cell${i}
  let #Cell${i} number${i} = value${i}
  use set (Cell${i} (number${i} + delta))`
  ).join("\n")
}
${
  cells(count).map((i) =>
    `  use updated${i} <- get #Cell${i}
  let #Cell${i} result${i} = updated${i}`
  ).join("\n")
}
  return ${cells(count).map((i) => `result${i}`).join(" + ")}
`;

function builder(count: number): string {
  return `${common(count)}
type Builder [world, scope, checkpoint, schema] is data = #Builder { initial: world, scope: world -> scope, checkpoint: checkpoint, schema: schema }
type End is data = #End
const empty = fn () => do:
  let scope = fn world => fn operation => do:
    use result <- operation ()
    return (world, result)
  return #Builder { initial: (), scope, checkpoint: fn () => (), schema: #End }
const insert_cell = fn initial => fn builder => do:
  let #Builder { initial: previous_initial, scope: previous_scope, checkpoint, schema } = builder
  let scope = fn world => fn operation => do:
    let (current, previous) = world
    use outcome <- @effect.run State.get State.set current (fn () => previous_scope previous operation)
    let (next, (previous_next, result)) = outcome
    return ((next, previous_next), result)
  return #Builder { initial: (initial, previous_initial), scope, checkpoint, schema }
const built = do:
  let builder = empty ()
${
    cells(count).map((i) => `  builder := insert_cell (#Cell${i} ${i}) self`)
      .join("\n")
  }
  return builder
const entry = fn (delta: U32) => do:
  let #Builder { initial, scope } = built
  let (world, result) = scope initial (action delta)
  return result
`;
}

const worldType = (count: number) =>
  `type World is data = #World { ${
    cells(count).map((i) => `c${i}: Cell${i}`).join(", ")
  } }`;
const worldInitial = (count: number) =>
  `#World { ${cells(count).map((i) => `c${i}: #Cell${i} ${i}`).join(", ")} }`;

function fixedHandlers(count: number): string {
  const nested = cells(count).reduceRight(
    (inside, i) =>
      `@effect.run State.get State.set cell${i} (fn () => ${inside})`,
    "action ()",
  );
  const result = cells(count).reduceRight(
    (inside, i) => `(next${i}, ${inside})`,
    "result",
  );
  return `${common(count)}
${worldType(count)}
const run = fn world => fn action => do:
  let #World { ${
    cells(count).map((i) => `c${i}: cell${i}`).join(", ")
  } } = world
  use outcome <- ${nested}
  let ${result} = outcome
  return (#World { ${
    cells(count).map((i) => `c${i}: next${i}`).join(", ")
  } }, result)
const entry = fn (delta: U32) => do:
  let (world, result) = run ${worldInitial(count)} (action delta)
  return result
`;
}

function directRecord(count: number): string {
  return `${
    cells(count).map((i) => `type Cell${i} is data = #Cell${i} U32`).join("\n")
  }
${worldType(count)}
const entry = fn (delta: U32) => do:
  let initial = ${worldInitial(count)}
  let #World { ${
    cells(count).map((i) => `c${i}: cell${i}`).join(", ")
  } } = initial
${cells(count).map((i) => `  let #Cell${i} number${i} = cell${i}`).join("\n")}
  let updated = #World { ${
    cells(count).map((i) => `c${i}: Cell${i} (number${i} + delta)`).join(", ")
  } }
  let #World { ${
    cells(count).map((i) => `c${i}: updated${i}`).join(", ")
  } } = updated
${
    cells(count).map((i) => `  let #Cell${i} result${i} = updated${i}`).join(
      "\n",
    )
  }
  return ${cells(count).map((i) => `result${i}`).join(" + ")}
`;
}

function directAccessors(count: number): string {
  return `${
    cells(count).map((i) => `type Cell${i} is data = #Cell${i} U32`).join("\n")
  }
${worldType(count)}
${
    cells(count).map((i) =>
      `const get${i} = fn world => world.c${i}
const set${i} = fn value => fn world => do:
  world.c${i} := value
  return world`
    ).join("\n")
  }
const entry = fn (delta: U32) => do:
  let world0 = ${worldInitial(count)}
${
    cells(count).map((i) =>
      `  let #Cell${i} number${i} = get${i} world${i}
  let world${i + 1} = set${i} (Cell${i} (number${i} + delta)) world${i}`
    ).join("\n")
  }
${
    cells(count).map((i) =>
      `  let #Cell${i} result${i} = get${i} world${count}`
    )
      .join("\n")
  }
  return ${cells(count).map((i) => `result${i}`).join(" + ")}
`;
}

const source = (variant: Variant, count: number) =>
  variant === "builder"
    ? builder(count)
    : variant === "fixed_handlers"
    ? fixedHandlers(count)
    : variant === "direct_accessors"
    ? directAccessors(count)
    : directRecord(count);

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", bytes.slice().buffer as ArrayBuffer),
  );
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

const nativeModule = await import(
  pathToFileURL(resolve(compilerRoot, "compiler/native.ts")).href
);
const executable = pathToFileURL(
  resolve(compilerRoot, "generated/compiler/blotc"),
);
const executableSha256 = await sha256(await Deno.readFile(executable));
const rows: unknown[] = [];
await Deno.mkdir("build/gdev-ecs-experiment", { recursive: true });
for (const count of counts) {
  const programs = new Map(
    variants.map((variant) => [variant, source(variant, count)]),
  );
  await Promise.all(
    variants.map((variant) =>
      Deno.writeTextFile(
        `build/gdev-ecs-experiment/${count}-${variant}.blot`,
        programs.get(variant)!,
      )
    ),
  );
  const compilers = new Map<
    Variant,
    Awaited<ReturnType<typeof nativeModule.createNativeCompiler>>
  >();
  const nativePids = new Map<Variant, number | undefined>();
  const nativePolicies = new Map<Variant, ReturnType<typeof nativeScheduler>>();
  try {
    for (const variant of variants) {
      const before = await ownedNativeChildren();
      compilers.set(
        variant,
        await nativeModule.createNativeCompiler({ executable, threads }),
      );
      const pid = await matchingNativeChild(executable, before);
      nativePids.set(variant, pid);
      nativePolicies.set(variant, nativeScheduler(await nativeCpuSample(pid)));
    }
    const times = new Map<Variant, number[]>(
      variants.map((variant) => [variant, []]),
    );
    const cpuTimes = new Map<Variant, number[]>(
      variants.map((variant) => [variant, []]),
    );
    const byteLengths = new Map<Variant, number>();
    const wasmHashes = new Map<Variant, string>();
    for (let round = 0; round < samples + 1; round++) {
      const order = round % 2 === 0 ? variants : [...variants].reverse();
      for (const variant of order) {
        const cpuBefore = await nativeCpuSample(nativePids.get(variant));
        const start = performance.now();
        const artifact = await compilers.get(variant)!.compile(
          programs.get(variant)!,
          { const_steps: 100_000n },
        );
        const elapsed = performance.now() - start;
        const cpuAfter = await nativeCpuSample(nativePids.get(variant));
        const cpuMs = nativeCpuMilliseconds(cpuBefore, cpuAfter);
        const module = await WebAssembly.compile(artifact.bytes);
        equal(WebAssembly.Module.imports(module), []);
        const instance = await WebAssembly.instantiate(module);
        const exports = instance.exports as Record<
          string,
          WebAssembly.ExportValue
        >;
        const functionName = Object.keys(exports).find((name) =>
          name === "entry"
        ) ??
          Object.keys(exports).find((name) => name.startsWith("entry_"));
        if (!functionName || typeof exports[functionName] !== "function") {
          throw new Error(
            `Missing entry export: ${Object.keys(exports).join(", ")}`,
          );
        }
        for (const delta of [0, 1, 17]) {
          const actual: number =
            (exports[functionName] as (arg: number) => number)(delta);
          const expected = count * (count - 1) / 2 + count * delta;
          equal(actual, expected);
        }
        byteLengths.set(variant, artifact.bytes.length);
        wasmHashes.set(variant, await sha256(artifact.bytes));
        if (round > 0) {
          times.get(variant)!.push(elapsed);
          if (cpuMs !== null) cpuTimes.get(variant)!.push(cpuMs);
        }
      }
    }
    for (const variant of variants) {
      const samplesMs = times.get(variant)!;
      const sorted = [...samplesMs].sort((a, b) => a - b);
      const cpuSamplesMs = cpuTimes.get(variant)!;
      const sortedCpu = [...cpuSamplesMs].sort((a, b) => a - b);
      const row = {
        variant,
        cells: count,
        source_chars: programs.get(variant)!.length,
        source_sha256: await sha256(
          new TextEncoder().encode(programs.get(variant)!),
        ),
        wasm_bytes: byteLengths.get(variant),
        wasm_sha256: wasmHashes.get(variant),
        samples_ms: samplesMs,
        median_ms: sorted[Math.floor(sorted.length / 2)],
        native_cpu_samples_ms: cpuSamplesMs,
        median_native_cpu_ms: sortedCpu.length
          ? sortedCpu[Math.floor(sortedCpu.length / 2)]
          : null,
        native_pid: nativePids.get(variant) ?? null,
        native_scheduler: nativePolicies.get(variant) ?? null,
        expected_for_delta_1: count * (count + 1) / 2,
      };
      rows.push(row);
      console.log(JSON.stringify(row));
    }
  } finally {
    await Promise.all(
      [...compilers.values()].map((compiler) => compiler.dispose()),
    );
  }
}
await Deno.mkdir(dirname(reportPath), { recursive: true });
await Deno.writeTextFile(
  reportPath,
  JSON.stringify(
    {
      compilerRoot,
      executable,
      executable_sha256: executableSha256,
      threads,
      samples,
      native_cpu_ticks_per_second: nativeCpuHz ?? null,
      rows,
    },
    null,
    2,
  ),
);
