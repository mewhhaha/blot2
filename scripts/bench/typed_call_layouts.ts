// Real Ink easing calls across constructor states; every compile is capped at 5s.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const root = resolve(new URL("../..", import.meta.url).pathname);
const { values } = parseArgs({
  args: Deno.args,
  options: {
    compiler: {
      type: "string",
      default: "zig-native/zig-out-native-dev/bin/blotc",
    },
    output: { type: "string", default: "build/bench/typed-call-layouts" },
    tier: { type: "string", default: "optimized" },
  },
});
if (values.tier !== "optimized" && values.tier !== "development") {
  throw new Error("--tier must be optimized or development");
}
const executable = resolve(root, values.compiler!);
const output = resolve(root, values.output!);
const hash = async (bytes: BufferSource) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
const compilerSha256 = await hash(await Deno.readFile(executable));
const sourceFiles = Object.fromEntries(
  await Promise.all([
    "../ink/lib/tween.blot",
    "../ink/lib/motion.blot",
    "std/prelude.blot",
    "std/array.blot",
  ].map(async (path) => {
    const absolute = resolve(root, path);
    return [absolute, await hash(await Deno.readFile(absolute))];
  })),
);
const constructors = [
  "$tween.Linear",
  "$tween.Smooth",
  "$tween.Smoother",
  "$tween.CubicIn",
  "$tween.CubicOut",
  "$tween.CubicInOut",
  "$tween.Back",
  "$tween.Hold",
  "$tween.Steps 3",
];
const midpoint = [0.5, 0.5, 0.5, 0.125, 0.875, 0.5, 1.0876975, 0, 1 / 3];
await Deno.mkdir(output, { recursive: true });
for (const count of [1, 2, 9]) {
  const entry = resolve(output, `n${count}.blot`);
  const calls = constructors.slice(0, count).map((kind) =>
    `  marker.push (apply_ease (${kind}) t)`
  ).join("\n");
  const source = `import * as tween from "ink/tween"
const apply_ease = func (ease: tween.Ease) -> (t: F32) => return tween.eased ease t
entry const main = func (t: F32) => return do:
  let marker: GrowArray F32 = #[]
${calls}
  return @storage.freeze marker
`;
  await Deno.writeTextFile(entry, source);
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    imports: { "ink/": resolve(root, "../ink/lib") },
    stdRoot: resolve(root, "std"),
    prelude: resolve(root, "std/prelude.blot"),
    cacheDirectory: false,
    profileBackend: true,
    codegenTier: values.tier,
    codegenWorkers: 1,
    startupTimeoutMs: 5000,
  });
  try {
    const begin = performance.now();
    const result = await compiler.build({ signal: AbortSignal.timeout(5000) });
    const buildMs = performance.now() - begin;
    assert(result.success, JSON.stringify(result));
    const guest = await instantiateGuest(result.bytes);
    const executions = [];
    try {
      for (const input of [0, 0.5, 1]) {
        const actual = guest.call("main", input);
        assert(actual instanceof Float32Array);
        assert.equal(actual.length, count);
        for (let at = 0; at < count; at++) {
          let expected = input;
          if (input === 0.5) expected = midpoint[at];
          assert(Math.abs(actual[at] - expected) < 0.000001);
        }
        executions.push({
          input,
          outputSha256: await hash(new Float32Array(actual)),
        });
      }
    } finally {
      guest.dispose();
    }
    await Deno.writeFile(resolve(output, `n${count}.wasm`), result.bytes);
    console.log(JSON.stringify({
      kind: "easing-constructor-states",
      count,
      compilerSha256,
      sourceFiles,
      sourceSha256: await hash(new TextEncoder().encode(source)),
      tier: values.tier,
      deadlineMs: 5000,
      buildMs,
      wasmBytes: result.bytes.length,
      wasmSha256: await hash(result.bytes),
      executions,
      stats: result.stats,
    }));
  } finally {
    await compiler.dispose();
  }
}
