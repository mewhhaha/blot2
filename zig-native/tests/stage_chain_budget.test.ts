import { strict as assert } from "node:assert";
import {
  createZigProjectCompiler,
  type ZigProjectDiagnostic,
} from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;

// The 51-link chain reaches 974,824 inference steps. The next link exhausts
// the default budget; rejection must survive empty catalogs in export handling.
function chain(length: number): string {
  const fields = Array.from(
    { length: 64 },
    (_, index) => `f${index}: fn x => x * 2.0 + x / 3.0`,
  );
  const stages = ["const s0 = fn () => (holder ()).g"];
  for (let index = 1; index < length; index++) {
    stages.push(`const s${index} = fn () => (holder ()).g + s${index - 1} ()`);
  }
  return `const holder = fn () => #{\n  ${fields.join(",\n  ")},\n  g: 4\n}\n` +
    stages.join("\n") + `\nentry const e = fn () => s${length - 1} ()\n`;
}

function budget(issue: ZigProjectDiagnostic, entry: string, source: string) {
  assert.equal(issue.code, "inference_budget");
  assert.equal(issue.filename, entry);
  assert(issue.start >= 0 && issue.end > issue.start);
  assert(issue.end <= source.length);
  assert.match(issue.message, /budget of 1000000 steps while checking/);
}

Deno.test("CLI rejects stage chains at and beyond the inference budget without publishing output", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-stage-budget-" });
  const entry = `${directory}/main.blot`;
  const output = `${directory}/main.wasm`;
  try {
    for (const length of [52, 64]) {
      const source = chain(length);
      await Deno.writeTextFile(entry, source);
      const result = await new Deno.Command(executable, {
        args: ["build", entry, output, "--prelude", prelude],
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
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("fresh and retained stage-chain rejection agrees and the server recovers unchanged", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-stage-budget-" });
  const entry = `${directory}/main.blot`;
  const options = {
    executable,
    entry,
    prelude,
    cacheDirectory: false as const,
  };
  const retained = await createZigProjectCompiler(options);
  let original: Uint8Array<ArrayBuffer> | undefined;
  try {
    for (const length of [51, 52, 64, 51]) {
      const source = chain(length);
      const sources = { [entry]: source };
      const result = await retained.build({ sources });
      if (!result.success) {
        assert(length >= 52, JSON.stringify(result));
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
        continue;
      }
      assert.equal(length, 51);
      if (original) assert.deepEqual(result.bytes, original);
      original = result.bytes;
      const guest = await instantiateGuest(result.bytes);
      try {
        assert.equal(guest.call("e", null), 204);
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
