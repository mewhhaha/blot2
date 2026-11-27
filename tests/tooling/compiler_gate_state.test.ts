import { strict as assert } from "node:assert";
import { createHash } from "node:crypto";
import { resolve } from "node:path";
import {
  failedGuestFiles,
  fileDigest,
  inputDigest,
} from "../../scripts/compiler_gate_state.ts";
import { runPhase, together } from "../../scripts/compiler_phase.ts";

Deno.test("buffered identities preserve SHA-256 across chunk boundaries and same-size edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "squid-digest-" });
  try {
    const path = resolve(directory, "input");
    for (
      const length of [0, 1, 65535, 65536, 65537, 1048575, 1048576, 1048577]
    ) {
      const bytes = Uint8Array.from({ length }, (_, index) => index % 251);
      await Deno.writeFile(path, bytes);
      const expected = createHash("sha256").update(bytes).digest("hex");
      assert.equal(await fileDigest(path), expected);
      const missing = resolve(directory, "missing");
      const aggregate = createHash("sha256");
      for (const name of [path, missing].sort()) {
        aggregate.update(JSON.stringify(name));
        aggregate.update(name === path ? expected : "missing");
      }
      assert.equal(
        await inputDigest([missing, path, path]),
        aggregate.digest("hex"),
      );
    }
    const before = await inputDigest([path]);
    const stat = await Deno.stat(path);
    const changed = await Deno.readFile(path);
    changed[changed.length - 1] ^= 1;
    await Deno.writeFile(path, changed);
    await Deno.utime(path, stat.atime!, stat.mtime!);
    assert.notEqual(await inputDigest([path]), before);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("preflight remembers failed repository files from real Deno JUnit shape", () => {
  const xml = `<testsuites failures="3">
    <testsuite name="tests/guest/a.test.ts" failures="1" errors="0"><testcase><failure /></testcase></testsuite>
    <testsuite name="host/b&amp;c.test.ts" failures="0" errors="1"></testsuite>
    <testsuite name="host/passed.test.ts" failures="0" errors="0"></testsuite>
    <testsuite name="../outside.test.ts" failures="1"></testsuite>
  </testsuites>`;
  assert.deepEqual(failedGuestFiles(xml, "/repo"), [
    "host/b&c.test.ts",
    "tests/guest/a.test.ts",
  ]);
});

Deno.test("phase budget kills descendants and preserves partial logs", async () => {
  if (Deno.build.os === "windows") return;
  const directory = await Deno.makeTempDir({ prefix: "squid-gate-budget-" });
  try {
    const escaped = resolve(directory, "escaped");
    const ready = resolve(directory, "ready");
    const descendant =
      `Deno.addSignalListener('SIGTERM', () => {}); console.log('descendant started'); await Deno.writeTextFile(${
        JSON.stringify(ready)
      }, 'ready'); await new Promise(r => setTimeout(r, 1000)); await Deno.writeTextFile(${
        JSON.stringify(escaped)
      }, 'leaked process');`;
    const parent =
      `console.log('parent started'); const child = new Deno.Command(Deno.execPath(), {args: ['eval', ${
        JSON.stringify(descendant)
      }], stdout: 'inherit', stderr: 'inherit'}).spawn(); await child.status;`;
    const controller = new AbortController();
    const running = runPhase(
      "slow",
      [Deno.execPath(), "eval", parent],
      directory,
      Deno.cwd(),
      {},
      { seconds: 10, signal: controller.signal },
    );
    let phase;
    try {
      // Exercise group termination only after the SIGTERM-resistant child is
      // ready. A short startup deadline can kill its parent before it spawns.
      const deadline = performance.now() + 5000;
      while (true) {
        try {
          await Deno.stat(ready);
          break;
        } catch (error) {
          if (!(error instanceof Deno.errors.NotFound)) throw error;
        }
        assert(performance.now() < deadline, "descendant did not become ready");
        await new Promise((done) => setTimeout(done, 10));
      }
      controller.abort("budget");
      phase = await running;
    } finally {
      controller.abort();
      await running;
    }
    assert.equal(phase.code, 124);
    assert.equal(phase.stopped, "budget");
    assert.match(await Deno.readTextFile(phase.stdout), /parent started/);
    assert.match(await Deno.readTextFile(phase.stdout), /descendant started/);
    assert(phase.wall_seconds < 10);
    await new Promise((done) => setTimeout(done, 1100));
    await assert.rejects(Deno.stat(escaped), Deno.errors.NotFound);
    // Keep the real elapsed-time deadline independent of process readiness.
    const timed = await runPhase(
      "timer",
      [
        Deno.execPath(),
        "eval",
        "await new Promise(r => setTimeout(r, 10000));",
      ],
      directory,
      Deno.cwd(),
      {},
      { seconds: 0.01 },
    );
    assert.equal(timed.code, 124);
    assert.equal(timed.stopped, "budget");
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("overlapping qualification waits for cancellation after either job fails", async () => {
  const directory = await Deno.makeTempDir({ prefix: "squid-gate-overlap-" });
  try {
    const controller = new AbortController();
    let completed = false;
    await assert.rejects(
      together([
        async () => {
          await new Promise((done) => setTimeout(done, 100));
          throw new Error("release failed");
        },
        async () => {
          const phase = await runPhase(
            "native",
            [
              Deno.execPath(),
              "eval",
              "console.log('running'); await new Promise(r => setTimeout(r, 10000));",
            ],
            directory,
            Deno.cwd(),
            {},
            { signal: controller.signal },
          );
          assert.equal(phase.code, 130);
          completed = true;
        },
      ], controller),
      /release failed/,
    );
    assert(completed, "sibling process was not reaped before failure returned");
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
