// Archived compiler-coupled prototype; not part of the current compiler.
import { type Profiler, Session } from "node:inspector";
import { createSourceCompiler } from "./source.ts";
import { ecsWorkload } from "./ecs_workload.ts";
import { dirname } from "node:path";

const systemCount = Number(Deno.args[0] ?? 64);
const iterations = Number(Deno.args[1] ?? 3);
const destination = Deno.args[2] ?? "build/ecs.cpuprofile";
if (
  Deno.args.length > 3 || !Number.isInteger(iterations) || iterations < 1 ||
  iterations > 100
) {
  throw new Error(
    "Usage: compiler/ecs_profile.ts [systems: 1..256] [iterations: 1..100] [output.cpuprofile]",
  );
}

const source = ecsWorkload(systemCount);
const compiler = await createSourceCompiler();
const session = new Session();
session.connect();
function command(method: string, parameters: object = {}): Promise<unknown> {
  return new Promise((resolve, reject) => {
    session.post(
      method,
      parameters,
      (error, result) => error ? reject(error) : resolve(result),
    );
  });
}
try {
  for (let warmup = 0; warmup < 3; warmup++) compiler.compileEcs(source);
  await command("Profiler.enable");
  await command("Profiler.setSamplingInterval", { interval: 1000 });
  await command("Profiler.start");
  for (let index = 0; index < iterations; index++) compiler.compileEcs(source);
  const { profile } = await command("Profiler.stop") as {
    profile: Profiler.Profile;
  };
  await Deno.mkdir(dirname(destination), { recursive: true });
  await Deno.writeTextFile(destination, JSON.stringify(profile));

  const nodes = new Map(profile.nodes.map((node) => [node.id, node]));
  const parents = new Map<number, number>();
  for (const node of profile.nodes) {
    for (const child of node.children ?? []) parents.set(child, node.id);
  }
  const selfTime = new Map<string, number>();
  const inclusiveTime = new Map<string, number>();
  let total = 0;
  const nameOf = (node: Profiler.ProfileNode) =>
    node.callFrame.functionName || node.callFrame.url || "(anonymous)";
  for (let index = 0; index < (profile.samples?.length ?? 0); index++) {
    const id = profile.samples![index];
    const elapsed = profile.timeDeltas![index];
    total += elapsed;
    const leaf = nameOf(nodes.get(id)!);
    selfTime.set(leaf, (selfTime.get(leaf) ?? 0) + elapsed);
    const visited = new Set<string>();
    for (
      let cursor: number | undefined = id;
      cursor !== undefined;
      cursor = parents.get(cursor)
    ) {
      visited.add(nameOf(nodes.get(cursor)!));
    }
    for (const name of visited) {
      inclusiveTime.set(name, (inclusiveTime.get(name) ?? 0) + elapsed);
    }
  }
  for (
    const [label, timings] of [["Self", selfTime], [
      "Inclusive (recursive names counted once)",
      inclusiveTime,
    ]] as const
  ) {
    console.log(label);
    console.table(
      [...timings].sort((left, right) => right[1] - left[1]).slice(0, 20).map((
        [name, elapsed],
      ) => ({
        function: name,
        percent: Number((elapsed / total * 100).toFixed(2)),
        ms: Number((elapsed / 1000).toFixed(2)),
      })),
    );
  }
  console.log(
    `Profiled ${iterations} full ${systemCount}-system compiles after warmup; wrote ${destination}. Use the unprofiled benchmark for timings.`,
  );
} finally {
  session.disconnect();
  compiler.dispose();
}
