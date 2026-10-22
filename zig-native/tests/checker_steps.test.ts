import { strict as assert } from "node:assert";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;

interface Checker {
  obligations_appended: number;
  inference_steps: number;
}
async function check(source: string): Promise<Checker> {
  const directory = await Deno.makeTempDir({ prefix: "blot-checker-steps-" });
  try {
    const input = `${directory}/main.blot`;
    await Deno.writeTextFile(input, source);
    const result = await new Deno.Command(executable, {
      args: ["check", input, "--prelude", prelude],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const record = JSON.parse(
      new TextDecoder().decode(result.stdout).split("\n")[0],
    );
    assert(result.success && record.success, JSON.stringify(record));
    return record.checker as Checker;
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

// Operator uses whose operand types are fixed only at the end of a body wait
// on their instance types once the operator is settled. Quadrupling the uses
// adds steps proportional to the added obligations, where retrying every open
// use on every pass added hundreds of steps per obligation.
Deno.test("open operator uses wait for their operand types", async () => {
  const late = (count: number) => {
    const indices = Array.from({ length: count }, (_, index) => index);
    return `const late = ${indices.map((i) => `fn p${i} => `).join("")}do:
${indices.map((i) => `  let same_${i} = p${i} == p${i}`).join("\n")}
${indices.map((i) => `  let used_${i} = p${i} + 1`).join("\n")}
  break 0
`;
  };
  const small = await check(late(32));
  const large = await check(late(128));
  const steps = large.inference_steps - small.inference_steps;
  const obligations = large.obligations_appended - small.obligations_appended;
  assert(obligations > 0);
  assert(steps <= 16 * obligations, JSON.stringify({ small, large }));
});

// A global record of closures with an unhandled effect operation puts one
// pending operation check per closure into each helper that uses it. Those
// checks sleep until their types change: about one step per obligation.
Deno.test("pending effect operations wait for their types", async () => {
  const record = (count: number) => {
    const indices = Array.from({ length: count }, (_, index) => index);
    return `type Probe a is effect = { ask: Unit -> a }
const app = { ${indices.map((i) => `f${i}: fn () => Probe.ask ()`).join(", ")} }
${
      indices.map((i) =>
        `const use_${i} = fn () => do:\n  let handlers = app\n  use value <- handlers.f${i} ()\n  break value`
      ).join("\n")
    }
`;
  };
  const small = await check(record(8));
  const checker = await check(record(64));
  assert(checker.obligations_appended >= 64 * 64);
  const addedObligations = checker.obligations_appended -
    small.obligations_appended;
  const addedSteps = checker.inference_steps - small.inference_steps;
  assert(addedObligations > 0);
  assert(
    addedSteps <= 2 * addedObligations,
    JSON.stringify({ small, checker }),
  );
});
