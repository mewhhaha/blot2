import { strict as assert } from "node:assert";
import {
  createZigProjectCompiler,
  type ZigProjectDiagnostic,
} from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
// Exercise unknown callback rows, rejection and recovery with the ordinary
// compiler configured to a process-local 256-step inference limit.
function chain(length: number): string {
  const fields = Array.from(
    { length: 2 },
    (_, index) => `f${index}: fn x => x`,
  );
  const stages = ["const s0 = fn () => (holder ()).g"];
  for (let index = 1; index < length; index++) {
    stages.push(
      `const s${index} = fn () => @u32.add (holder ()).g (s${index - 1} ())`,
    );
  }
  return `const holder = fn () => #{\n  ${fields.join(",\n  ")},\n  g: 4\n}\n` +
    stages.join("\n") + `\nentry const e = fn () => s${length - 1} ()\n`;
}

function budget(issue: ZigProjectDiagnostic, entry: string, source: string) {
  assert.equal(issue.code, "inference_budget");
  assert.equal(issue.filename, entry);
  assert(issue.start >= 0 && issue.end > issue.start);
  assert(issue.end <= source.length);
  assert.match(issue.message, /budget of 256 steps while checking/);
}

Deno.test("CLI rejects inference budget exhaustion without publishing output", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-stage-budget-" });
  const entry = `${directory}/main.blot`;
  const output = `${directory}/main.wasm`;
  let passed = false;
  try {
    const source = chain(32);
    await Deno.writeTextFile(entry, source);
    const result = await new Deno.Command(executable, {
      args: [
        "build",
        entry,
        output,
        "--prelude",
        "none",
        "--inference-budget",
        "256",
      ],
      env: { BLOT_CACHE_DIR: "" },
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.equal(result.code, 1, new TextDecoder().decode(result.stderr));
    const records = new TextDecoder().decode(result.stdout).trim().split("\n")
      .map((line) => JSON.parse(line));
    const issues = records.filter((record) => record.kind === "diagnostic");
    assert.equal(issues.length, 1);
    budget(issues[0], entry, source);
    const metrics = records.find((record) => record.kind === "compilation");
    assert.equal(metrics.success, false);
    assert.equal(metrics.memory.live_bytes, 0);
    await assert.rejects(() => Deno.stat(output), Deno.errors.NotFound);
    passed = true;
  } finally {
    if (passed) await Deno.remove(directory, { recursive: true });
    else console.error(`Stage-chain failure source preserved at ${entry}`);
  }
});

Deno.test("fresh and retained stage-chain rejection agrees and the server recovers unchanged", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-stage-budget-" });
  const entry = `${directory}/main.blot`;
  const options = {
    executable,
    inferenceBudget: 256,
    entry,
    prelude: null,
    cacheDirectory: false as const,
  };
  const retained = await createZigProjectCompiler(options);
  let original: Uint8Array<ArrayBuffer> | undefined;
  let passed = false;
  try {
    for (const length of [2, 32, 2]) {
      const source = chain(length);
      const sources = { [entry]: source };
      const result = await retained.build({ sources });
      if (!result.success) {
        assert.equal(length, 32, JSON.stringify(result));
        assert.equal(result.diagnostics.length, 1);
        budget(result.diagnostics[0], entry, source);
        const fresh = await createZigProjectCompiler(options);
        try {
          const reference = await fresh.build({ sources });
          assert(!reference.success);
          assert.deepEqual(result.diagnostics, reference.diagnostics);
        } finally {
          await fresh.dispose();
        }
        const production = await createZigProjectCompiler({
          ...options,
          executable,
          inferenceBudget: 1_000_000,
        });
        try {
          assert.notEqual(
            production.compilerIdentity,
            retained.compilerIdentity,
          );
          const accepted = await production.build({ sources });
          assert(accepted.success, JSON.stringify(accepted));
          const guest = await instantiateGuest(accepted.bytes);
          try {
            assert.equal(guest.call("e", null), 128);
          } finally {
            guest.dispose();
          }
        } finally {
          await production.dispose();
        }
        continue;
      }
      assert.equal(length, 2);
      if (original) assert.deepEqual(result.bytes, original);
      original = result.bytes;
      const guest = await instantiateGuest(result.bytes);
      try {
        assert.equal(guest.call("e", null), 8);
      } finally {
        guest.dispose();
      }
    }
    passed = true;
  } finally {
    await retained.dispose();
    if (passed) await Deno.remove(directory, { recursive: true });
    else console.error(`Stage-chain failure source preserved at ${entry}`);
  }
});
