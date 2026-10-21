import { strict as assert } from "node:assert";
import { createHash } from "node:crypto";
import { resolve } from "node:path";
import {
  failedGuestFiles,
  fileDigest,
  inputDigest,
  nativeInputs,
  NativeJournal,
} from "./compiler_gate_state.ts";
import { runPhase, together } from "./compiler_phase.ts";

Deno.test("buffered identities preserve SHA-256 across chunk boundaries and same-size edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-digest-" });
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

Deno.test("resume requires completed laws and exact binary, logs and input identity", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-gate-resume-" });
  try {
    const binary = resolve(directory, "binary");
    const source = resolve(directory, "source");
    const path = resolve(directory, "success.json");
    await Deno.writeTextFile(binary, "executable");
    await Deno.writeTextFile(source, "input");
    const key = await inputDigest([source]);
    const journal = new NativeJournal(path);
    await journal.load();
    const result = await runPhase("native-run", [
      Deno.execPath(),
      "eval",
      "console.log('law passed')",
    ], directory);
    await journal.record(key, result, [binary]);
    await journal.invalidate("native-run");
    await journal.record(key, { ...result, cache: "hit" }, [binary]);
    assert.equal(await journal.reuse("native-run", key), undefined);
    await journal.record(key, result, [binary]);
    const accepted = await Deno.readTextFile(path);
    const legacy = JSON.parse(accepted);
    legacy.entries["native-run"].phase.cache = "hit";
    await Deno.writeTextFile(path, JSON.stringify(legacy));
    const legacyJournal = new NativeJournal(path);
    await legacyJournal.load();
    assert.equal(await legacyJournal.reuse("native-run", key), undefined);
    await Deno.writeTextFile(path, accepted);
    const loaded = new NativeJournal(path);
    await loaded.load();
    assert.equal((await loaded.reuse("native-run", key))?.cache, "resumed");
    assert.equal(
      await loaded.reuse("native-run", key + "different command/toolchain"),
      undefined,
    );
    await Deno.writeTextFile(source, "same path, new content");
    assert.equal(
      await loaded.reuse("native-run", await inputDigest([source])),
      undefined,
    );
    await Deno.writeTextFile(binary, "different executable");
    assert.equal(await loaded.reuse("native-run", key), undefined);
    await Deno.writeTextFile(binary, "executable");
    await Deno.writeTextFile(result.stdout, "truncated evidence");
    assert.equal(await loaded.reuse("native-run", key), undefined);
    await Deno.writeTextFile(result.stdout, "law passed\n");
    assert(await loaded.reuse("native-run", key));
    await loaded.invalidate("native-run");
    await loaded.record(key, { ...result, code: 1 }, [binary]);
    await loaded.record(key, { ...result, stopped: "budget" }, [binary]);
    assert.equal(await loaded.reuse("native-run", key), undefined);
    await Deno.remove(binary);
    assert.equal(await journal.reuse("native-run", key), undefined);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("native resume observes native inputs and runtime fixtures but survives notes and guest repairs", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-gate-inputs-" });
  const root = resolve(directory, "blot");
  try {
    await Deno.mkdir(root);
    const init = await new Deno.Command("git", {
      args: ["init", "--quiet", root],
    }).output();
    assert.equal(init.code, 0);
    await Deno.mkdir(resolve(root, "zig-native/src/check"), {
      recursive: true,
    });
    await Deno.mkdir(resolve(root, "zig-native/tests"), { recursive: true });
    const source = resolve(root, "zig-native/src/check/check.zig");
    const guest = resolve(root, "zig-native/tests/repaired.test.ts");
    await Deno.writeTextFile(source, "native law");
    await Deno.writeTextFile(guest, "broken guest assertion");
    const ignored = resolve(root, "zig-native/src/ignored.zig");
    await Deno.writeTextFile(
      resolve(root, ".gitignore"),
      "zig-native/src/ignored.zig\n",
    );
    await Deno.writeTextFile(ignored, "ignored source still compiles");
    const sibling = resolve(directory, "gdev/src");
    await Deno.mkdir(sibling, { recursive: true });
    const corpus = resolve(sibling, "corpus.blot");
    await Deno.writeTextFile(corpus, "entry const answer = 42");
    const guide = resolve(root, "compiler/guide.md");
    await Deno.mkdir(resolve(root, "compiler"));
    await Deno.writeTextFile(guide, "native parser corpus");
    const fixtures = resolve(root, "zig-native/fixtures");
    await Deno.mkdir(fixtures);
    const fixture = resolve(fixtures, "input.blot");
    await Deno.writeTextFile(fixture, "original embedded Source");
    const before = await inputDigest(await nativeInputs(root));
    await Deno.writeTextFile(guest, "repaired guest assertion");
    assert.equal(await inputDigest(await nativeInputs(root)), before);
    await Deno.writeTextFile(
      resolve(root, "CONTINUE.md"),
      "qualified native laws",
    );
    await Deno.mkdir(resolve(root, "tasks"));
    await Deno.writeTextFile(
      resolve(root, "tasks/001.md"),
      "recorded evidence",
    );
    assert.equal(await inputDigest(await nativeInputs(root)), before);
    await Deno.writeTextFile(guide, "changed parser corpus");
    assert.notEqual(await inputDigest(await nativeInputs(root)), before);
    await Deno.writeTextFile(guide, "native parser corpus");
    const build = resolve(root, "zig-native/build.zig");
    await Deno.writeTextFile(build, "new compiler configuration");
    assert.notEqual(await inputDigest(await nativeInputs(root)), before);
    await Deno.remove(build);
    assert.equal(await inputDigest(await nativeInputs(root)), before);
    await Deno.writeTextFile(corpus, "changed external corpus");
    assert.notEqual(await inputDigest(await nativeInputs(root)), before);
    await Deno.writeTextFile(corpus, "entry const answer = 42");
    await Deno.writeTextFile(ignored, "changed ignored native source");
    assert.notEqual(await inputDigest(await nativeInputs(root)), before);
    await Deno.writeTextFile(ignored, "ignored source still compiles");
    await Deno.writeTextFile(
      resolve(root, "zig-native/src/new.zig"),
      "new native law",
    );
    assert.notEqual(await inputDigest(await nativeInputs(root)), before);
    await Deno.remove(resolve(root, "zig-native/src/new.zig"));
    assert.equal(await inputDigest(await nativeInputs(root)), before);
    await Deno.writeTextFile(fixture, "changed embedded Source");
    assert.notEqual(await inputDigest(await nativeInputs(root)), before);
    await Deno.writeTextFile(fixture, "original embedded Source");
    const data = resolve(fixtures, "input.json");
    await Deno.writeTextFile(data, '{"value":42}');
    assert.notEqual(await inputDigest(await nativeInputs(root)), before);
    await Deno.remove(data);
    assert.equal(await inputDigest(await nativeInputs(root)), before);
    await Deno.remove(fixture);
    assert.notEqual(await inputDigest(await nativeInputs(root)), before);
    await Deno.writeTextFile(fixture, "original embedded Source");
    assert.equal(await inputDigest(await nativeInputs(root)), before);
    await Deno.writeTextFile(source, "repaired native law");
    assert.notEqual(await inputDigest(await nativeInputs(root)), before);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("preflight remembers failed repository files from real Deno JUnit shape", () => {
  const xml = `<testsuites failures="3">
    <testsuite name="zig-native/tests/a.test.ts" failures="1" errors="0"><testcase><failure /></testcase></testsuite>
    <testsuite name="compiler/b&amp;c.test.ts" failures="0" errors="1"></testsuite>
    <testsuite name="compiler/passed.test.ts" failures="0" errors="0"></testsuite>
    <testsuite name="../outside.test.ts" failures="1"></testsuite>
  </testsuites>`;
  assert.deepEqual(failedGuestFiles(xml, "/repo"), [
    "compiler/b&c.test.ts",
    "zig-native/tests/a.test.ts",
  ]);
});

Deno.test("phase budget kills descendants and preserves partial logs", async () => {
  if (Deno.build.os === "windows") return;
  const directory = await Deno.makeTempDir({ prefix: "blot-gate-budget-" });
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
  const directory = await Deno.makeTempDir({ prefix: "blot-gate-overlap-" });
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

Deno.test("full runner resumes native qualification after a guest repair and invalidates a native edit", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-gate-end-to-end-" });
  const quote = (text: string) => "'" + text.replaceAll("'", "'\\''") + "'";
  try {
    for (
      const directory of [
        "bin",
        "lib",
        "scripts",
        "zig-native/src/check",
        "zig-native/tests",
        "compiler",
        "build",
      ]
    ) {
      await Deno.mkdir(resolve(root, directory), { recursive: true });
    }
    assert.equal(
      (await new Deno.Command("git", { args: ["init", "--quiet", root] })
        .output()).code,
      0,
    );
    await Deno.writeTextFile(
      resolve(root, ".gitignore"),
      "build/\nzig-native/zig-out*/\ngenerated/\n",
    );
    for (
      const file of [
        "test_compiler.ts",
        "compiler_phase.ts",
        "compiler_gate_state.ts",
        "compiler_lease.ts",
        "run_native_tests.ts",
        "dev_check_areas.ts",
        "compiler_fixtures.ts",
        "build_compiler.ts",
      ]
    ) {
      await Deno.copyFile(
        new URL(file, import.meta.url),
        resolve(root, "scripts", file),
      );
    }
    // Real runner, process controls, journals and Deno reporting; fake only the
    // expensive compiler and compiler-specific assertions inside this fixture.
    for (
      const file of [
        "test_compiler",
        "bench_compile",
        "compiler_gate_state",
        "compiler_fingerprint",
        "compiler_fixtures",
        "build_compiler",
        "native_test_runner",
        "run_native_tests",
        "check_dev",
        "lint_zig",
      ]
    ) {
      await Deno.writeTextFile(
        resolve(root, "scripts", `${file}.test.ts`),
        'Deno.test("harness prerequisite", () => {});\n',
      );
    }
    for (
      const file of [
        "zig_project_protocol",
        "zig_project_client",
        "stage_chain_budget",
      ]
    ) {
      await Deno.writeTextFile(
        resolve(root, "zig-native/tests", `${file}.test.ts`),
        'Deno.test("smoke prerequisite", () => {});\n',
      );
    }
    await Deno.writeTextFile(
      resolve(root, "scripts/pack_native.ts"),
      "// Package fixture.\n",
    );
    const source = resolve(root, "zig-native/src/check/check.zig");
    const guest = resolve(root, "compiler/repair.test.ts");
    await Deno.writeTextFile(source, "native source before edit");
    await Deno.writeTextFile(
      guest,
      'Deno.test("guest regression", () => { throw new Error("repair me"); });\n',
    );
    const calls = resolve(root, "build/native-calls");
    const nativeFixture = resolve(root, "bin/native-fixture");
    await Deno.writeTextFile(
      nativeFixture,
      `#!/bin/sh
if [ "$1" = --list ]; then printf 'first\\nsecond\\n'; exit 0; fi
printf 'test\\n' >> ${quote(calls)}
shard=0
for argument in "$@"; do
  case "$argument" in --shard=*) shard=\${argument#--shard=};; esac
done
name=first
if [ "$shard" = 1 ]; then name=second; fi
printf 'BLOT_NATIVE_TEST\\t{"name":"%s","duration_ns":1,"status":"passed","leaks":0,"logged_errors":0,"allocation_failures":"full","sweeps":{"full_sweeps":0,"sampled_sweeps":0,"discovered_allocations":0,"fault_runs":0}}\\n' "$name" >&2
printf 'BLOT_NATIVE_SHARD\\t{"shard":%s,"shards":2,"selected":1,"start_ns":1,"end_ns":2}\\n' "$shard" >&2
`,
    );
    await Deno.chmod(nativeFixture, 0o755);
    const releaseStarted = resolve(root, "build/release-started");
    const zig = resolve(root, "bin/zig");
    const environment = `.{ .zig_exe = ${JSON.stringify(zig)}, .lib_dir = ${
      JSON.stringify(resolve(root, "lib"))
    } }`;
    await Deno.writeTextFile(
      zig,
      `#!/bin/sh
if [ "$1" = version ]; then printf '0.17.0\\n'; exit 0; fi
if [ "$1" = env ]; then printf '%s\\n' ${quote(environment)}; exit 0; fi
for argument in "$@"; do
  if [ "$argument" = -Doptimize=fast ]; then
    printf 'release started\\n' > ${quote(releaseStarted)}
  fi
done
if [ "$2" = test-compile ]; then
  attempts=0
  while [ ! -f ${quote(releaseStarted)} ]; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 200 ]; then exit 91; fi
    /bin/sleep 0.01
  done
fi
if [ "$2" = test-compile ] || [ "$2" = test ]; then
  /bin/mkdir -p zig-out-native-dev/bin
  /bin/cp ${quote(nativeFixture)} zig-out-native-dev/bin/blot-tests
  printf '%s\\n' "$2" >> ${quote(calls)}
fi
`,
    );
    await Deno.chmod(zig, 0o755);
    // This fixture exercises recovery, including cold Deno startup and checks
    // of its synthetic modules. The short deadline and descendant-kill laws
    // above test timer behavior independently.
    const run = async () => {
      try {
        await Deno.remove(releaseStarted);
      } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
      }
      const result = await new Deno.Command(Deno.execPath(), {
        cwd: root,
        args: [
          "run",
          "--allow-read",
          "--allow-write",
          "--allow-run",
          "--allow-env",
          "scripts/test_compiler.ts",
          "--resume",
          "--budget-seconds",
          "120",
        ],
        env: { PATH: `${resolve(root, "bin")}:${Deno.env.get("PATH")}` },
        stdout: "piped",
        stderr: "piped",
      }).output();
      const report = JSON.parse(
        await Deno.readTextFile(
          resolve(root, "build/bench/iteration/timings.json"),
        ),
      );
      return { result, report };
    };
    const failed = await run();
    assert.notEqual(failed.result.code, 0);
    assert.equal(
      failed.report.phases.at(-1).name,
      "guests",
      new TextDecoder().decode(failed.result.stderr),
    );
    assert.equal(await Deno.readTextFile(calls), "test-compile\ntest\ntest\n");
    await Deno.writeTextFile(
      guest,
      'Deno.test("guest regression", () => {});\n',
    );
    const repaired = await run();
    assert.equal(
      repaired.result.code,
      0,
      new TextDecoder().decode(repaired.result.stderr),
    );
    assert.equal(repaired.report.success, true);
    assert.equal(repaired.report.phases[1].name, "preflight-regressions");
    for (const name of ["native-compile", "native-run"]) {
      assert.equal(
        repaired.report.phases.find((phase: { name: string }) =>
          phase.name === name
        ).cache,
        "resumed",
      );
    }
    assert.equal(await Deno.readTextFile(calls), "test-compile\ntest\ntest\n");
    await Deno.writeTextFile(source, "native source after edit");
    const changed = await run();
    assert.equal(
      changed.result.code,
      0,
      new TextDecoder().decode(changed.result.stderr),
    );
    assert.equal(
      await Deno.readTextFile(calls),
      "test-compile\ntest\ntest\ntest-compile\ntest\ntest\n",
    );
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});
