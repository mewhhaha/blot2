import { strict as assert } from "node:assert";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;

// Keep the adversarial production-limit regression outside routine iteration.
Deno.test("production million-step budget rejects adversarial stage chains", async () => {
  const fields = Array.from(
    { length: 64 },
    (_, index) => `f${index}: func x => return x * 2.0 + x / 3.0`,
  );
  const stages = ["const s0 = func () => return (holder ()).g"];
  for (let index = 1; index < 101; index++) {
    stages.push(`const s${index} = func () => return (holder ()).g + s${index - 1} ()`);
  }
  const source =
    `const holder = func () => return #{\n  ${fields.join(",\n  ")},\n  g: 4\n}\n` +
    stages.join("\n") + "\nentry const e = func () => return s100 ()\n";
  const directory = await Deno.makeTempDir({ prefix: "blot-stage-stress-" });
  const entry = `${directory}/main.blot`;
  const output = `${directory}/main.wasm`;
  try {
    await Deno.writeTextFile(entry, source);
    const result = await new Deno.Command(executable, {
      args: ["build", entry, output, "--prelude", prelude],
      env: { BLOT_CACHE_DIR: "" },
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.equal(result.code, 1, new TextDecoder().decode(result.stderr));
    const records = new TextDecoder().decode(result.stdout).trim().split("\n")
      .map((line) => JSON.parse(line));
    const issues = records.filter((record) => record.kind === "diagnostic");
    assert.equal(issues.length, 1);
    assert.equal(issues[0].code, "inference_budget");
    assert.equal(issues[0].filename, entry);
    assert(issues[0].start >= 0 && issues[0].end > issues[0].start);
    assert(issues[0].end <= source.length);
    assert.match(issues[0].message, /budget of 1000000 steps while checking/);
    const metrics = records.find((record) => record.kind === "compilation");
    assert.equal(metrics.success, false);
    assert.equal(metrics.memory.live_bytes, 0);
    await assert.rejects(() => Deno.stat(output), Deno.errors.NotFound);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
