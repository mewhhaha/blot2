import { assert } from "./session_harness.ts";
Deno.test("CMP-02 independent compiler workers preserve admission work and canonical artifacts", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-workers-" });
  async function build(id: number) {
    const output = `${dir}/${id}.wasm`, artifact = `${dir}/${id}.bk1`;
    const result = await new Deno.Command("build/blot", {
      args: [
        "build",
        "examples/particles.blot",
        "-o",
        output,
        `--emit-core=${artifact}`,
        "--bridge-config=examples/particles.json",
        "--timings",
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(result.success, new TextDecoder().decode(result.stderr));
    const text = new TextDecoder().decode(result.stderr);
    const stats = JSON.parse(
      text.split("\n").find((line) => line.startsWith("{"))!,
    );
    return {
      stats,
      core: await Deno.readFile(artifact),
      wasm: await Deno.readFile(output),
    };
  }
  try {
    const single = await build(0);
    assert(
      single.stats.active_regions === 0 &&
        single.stats.downstream_regions === 0,
    );
    const workers = await Promise.all([1, 2, 3, 4].map(build));
    for (const result of workers) {
      for (
        const field of [
          "completed_bodies",
          "completed_declarations",
          "semantic_visits",
          "validation_visits",
          "proof_terms",
          "proof_edges",
          "proof_visits",
          "validation_proof_visits",
          "static_steps",
          "static_bytes",
          "interface_instantiations",
          "semantic_instances",
          "executable_instances",
          "adapter_count",
          "created_regions",
          "general_inference_regions_created",
          "general_inference_nodes",
          "generated_bytes",
        ]
      ) {
        assert(
          Number.isSafeInteger(single.stats[field]) &&
            single.stats[field] === result.stats[field],
          `worker-dependent ${field}`,
        );
      }
      for (const field of ["core", "wasm"] as const) {
        assert(
          result[field].length === single[field].length &&
            result[field].every((b, i) => b === single[field][i]),
          `worker-dependent ${field}`,
        );
      }
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("C13 work counters distinguish staging, generic interfaces and executable bodies", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-work-counters-" });
  const input = `${dir}/input.blot`;
  await Deno.writeTextFile(
    input,
    `static let offset: U32 = 5
let identity: forall [T: Type] => T -> T ! {} resources {depth:1,frame:1024} = fn x => return x
pub let run: U32 -> U32 ! {} requires [AddFits(arg,1)] resources {depth:3,frame:4096} = fn x => do:
  let folded = U32.wrapping_add(2,3)
  let incremented = x + 1
  let result = identity@[U32](incremented)
  return U32.wrapping_add(result,U32.wrapping_add(offset,folded))
`,
  );
  async function build(name: string, mode: string, timings: boolean) {
    const output = `${dir}/${name}.wasm`;
    const result = await new Deno.Command("build/blot", {
      args: [
        "build",
        input,
        `--package-root=${dir}`,
        "-o",
        output,
        `--opt=${mode}`,
        ...(timings ? ["--timings"] : []),
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const log = new TextDecoder().decode(result.stderr);
    assert(result.success, log);
    const bytes = await Deno.readFile(output);
    const { instance } = await WebAssembly.instantiate(bytes);
    assert((instance.exports.run as CallableFunction)(40) === 51);
    const stats = timings
      ? JSON.parse(log.split("\n").find((line) => line.startsWith("{"))!)
      : null;
    return { bytes, stats };
  }
  try {
    const plain = await build("plain", "off", false);
    const measured = await build("measured", "off", true);
    assert(
      plain.bytes.length === measured.bytes.length &&
        plain.bytes.every((b, i) => b === measured.bytes[i]),
      "attribution changed emitted program",
    );
    const s = measured.stats;
    assert(s.generated_bytes === measured.bytes.length);
    assert(s.static_steps === 2 && s.static_bytes === 4);
    assert(s.interface_instantiations === 1);
    assert(
      // Initializer and publication-anchor bodies are checked, but only the
      // initializer executes. Neither becomes a guest function.
      s.static_bodies === 2 && s.semantic_instances === 4 &&
        s.executable_instances === 2,
      JSON.stringify(s),
    );
    assert(s.proof_terms > 0 && s.proof_edges > 0 && s.proof_visits > 0);
    assert(
      s.general_inference_regions_created === 0 &&
        s.general_inference_nodes === 0 && s.downstream_regions === 0,
    );
    assert(s.rewrite_visits === 0 && s.rewrite_applications === 0);
    const optimized = await build("optimized", "fast", true);
    assert(
      optimized.stats.rewrite_visits > 0 &&
        optimized.stats.rewrite_applications > 0,
    );
    assert(optimized.stats.generated_bytes === optimized.bytes.length);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
