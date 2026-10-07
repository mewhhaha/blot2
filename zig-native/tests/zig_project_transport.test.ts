import {
  deepStrictEqual as equal,
  ok,
  rejects,
  strictEqual,
} from "node:assert/strict";
import {
  createZigProjectCompiler,
  type ZigProjectCompiler,
  type ZigProjectCompilerOptions,
} from "../../compiler/zig_project_client.ts";
import { fileURLToPath } from "node:url";
const peer = fileURLToPath(
  new URL("./fixtures/zig_project_peer.ts", import.meta.url),
);
function quote(value: string): string {
  return "'" + value.replaceAll("'", "'\\''") + "'";
}
async function fixture(mode: string) {
  const directory = await Deno.makeTempDir({
    prefix: "blot-zig-project-peer-",
  });
  const executable = directory + "/compiler", log = directory + "/log.jsonl";
  await Deno.writeTextFile(
    executable,
    `#!/bin/sh\nexec ${quote(Deno.execPath())} run --quiet --allow-all ${
      quote(peer)
    } ${quote(mode)} ${quote(log)} "$@"\n`,
  );
  await Deno.chmod(executable, 0o755);
  const options: ZigProjectCompilerOptions = {
    executable,
    entry: directory + "/entry.blot",
    prelude: null,
    expectedCompilerIdentity: "a".repeat(64),
    startupTimeoutMs: 2000,
  };
  return {
    directory,
    log,
    options,
    async cleanup() {
      try {
        const records = await logs(log);
        reaped(records[0].pid);
      } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
      }
      await Deno.remove(directory, { recursive: true });
    },
  };
}
async function logs(path: string) {
  return (await Deno.readTextFile(path)).trim().split("\n").map((line) =>
    JSON.parse(line)
  );
}
function reaped(pid: number) {
  try {
    Deno.kill(pid, 0);
    throw new Error("Owned child is still alive");
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
}
async function waiting(path: string, kind: string) {
  for (let attempt = 0; attempt < 200; attempt++) {
    try {
      if ((await logs(path)).some((row) => row.kind === kind)) return;
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  throw new Error("Peer did not receive request");
}
Deno.test("source buffers reject unsupported peers without consuming a request ID", async () => {
  const item = await fixture("fragmented");
  const compiler = await createZigProjectCompiler(item.options);
  try {
    await rejects(
      compiler.build({
        sources: { [String(item.options.entry)]: "entry const answer = 42\n" },
      }),
      /does not support source overlays/,
    );
    const result = await compiler.build();
    ok(result.success);
    equal(result.revision, 1);
    await compiler.close();
    const builds = (await logs(item.log)).filter((row) => row.kind === "build");
    equal(builds.map((row) => row.id), [2]);
  } finally {
    await compiler.dispose();
    await item.cleanup();
  }
});
for (const mode of ["fragmented", "coalesced", "reject-first"]) {
  Deno.test(`client owns framed ${mode} replies, revisions and normal close`, async () => {
    const item = await fixture(mode);
    let compiler: ZigProjectCompiler | undefined;
    try {
      compiler = await createZigProjectCompiler(item.options);
      const pid = compiler.pid;
      const first = compiler.build(),
        second = compiler.build(),
        third = compiler.build();
      const results = await Promise.all([first, second, third]);
      equal(
        results.map((result) => result.revision),
        mode === "reject-first" ? [0, 1, 2] : [1, 2, 3],
      );
      if (mode === "reject-first") {
        ok(!results[0].success);
        strictEqual(results[0].attemptStats, null);
      } else {
        ok(results[0].success);
        results[0].bytes.fill(255);
        (results[0].stats.nested as { marker: number }).marker = 999;
      }
      ok(results[1].success);
      ok(WebAssembly.validate(results[1].bytes));
      equal((results[1].stats.nested as { marker: number }).marker, 2);
      const close = compiler.close();
      strictEqual(close, compiler.close());
      await close;
      reaped(pid);
      await rejects(compiler.build(), /closed|closing/);
      const dispose = compiler.dispose();
      strictEqual(dispose, compiler.dispose());
      await dispose;
      const records = await logs(item.log);
      equal(records[0].command, "serve-project");
      equal(
        records.filter((row) => row.kind === "build").map((row) =>
          row.revision
        ),
        mode === "reject-first" ? [0, 0, 1] : [0, 1, 2],
      );
    } finally {
      await compiler?.dispose();
      await item.cleanup();
    }
  });
}
Deno.test("constructor copies paths and imports before awaiting hello and launches with clearEnv", async () => {
  const item = await fixture("delayed");
  let compiler: ZigProjectCompiler | undefined;
  const previous = Deno.env.get("BLOT_CLIENT_TEST_AMBIENT");
  Deno.env.set("BLOT_CLIENT_TEST_AMBIENT", "must-not-inherit");
  try {
    const entry = new URL("entry.blot", "file://" + item.directory + "/"),
      producer = new URL("library/", entry);
    const imports: Record<string, URL> = { "lib/": producer };
    const options = { ...item.options, entry, imports };
    const pending = createZigProjectCompiler(options);
    entry.pathname = "/changed.blot";
    producer.pathname = "/changed-library/";
    imports["other/"] = producer;
    options.prelude = "/changed-prelude.blot";
    compiler = await pending;
    await compiler.close();
    const records = await logs(item.log);
    equal(records[0].ambient, null);
    equal(records[1].entry, item.directory + "/entry.blot");
    equal(records[1].prelude, null);
    equal(records[1].imports, [{
      prefix: "lib/",
      root: item.directory + "/library",
    }]);
  } finally {
    await compiler?.dispose();
    if (previous === undefined) Deno.env.delete("BLOT_CLIENT_TEST_AMBIENT");
    else Deno.env.set("BLOT_CLIENT_TEST_AMBIENT", previous);
    await item.cleanup();
  }
});
Deno.test("queued abort rejects immediately without consuming request ID or acknowledgement", async () => {
  const item = await fixture("hold");
  let compiler: ZigProjectCompiler | undefined;
  try {
    compiler = await createZigProjectCompiler(item.options);
    const first = compiler.build();
    await waiting(item.log, "build");
    const controller = new AbortController(),
      replacement = new AbortController(),
      options = { signal: controller.signal };
    const second = compiler.build(options);
    const rejected = rejects(
      second,
      (error) => error instanceof DOMException && error.name === "AbortError",
    );
    options.signal = replacement.signal;
    controller.abort();
    await rejected;
    const third = compiler.build();
    equal((await first).revision, 1);
    equal((await third).revision, 2);
    await compiler.close();
    equal(
      (await logs(item.log)).filter((row) => row.kind === "build").map(
        (row) => [row.id, row.revision],
      ),
      [[2, 0], [3, 1]],
    );
  } finally {
    try {
      await compiler?.dispose();
    } finally {
      await item.cleanup();
    }
  }
});
Deno.test("active abort disposes the child and all queued work exactly once", async () => {
  const item = await fixture("active-stall");
  let compiler: ZigProjectCompiler | undefined;
  try {
    compiler = await createZigProjectCompiler(item.options);
    const pid = compiler.pid, controller = new AbortController();
    const first = compiler.build({ signal: controller.signal }),
      second = compiler.build();
    const checked = Promise.all([
      rejects(first, /aborted/),
      rejects(second, /aborted/),
    ]);
    await waiting(item.log, "build");
    controller.abort();
    await checked;
    const dispose = compiler.dispose();
    strictEqual(dispose, compiler.dispose());
    await dispose;
    reaped(pid);
    await rejects(compiler.build(), /aborted|disposed/);
  } finally {
    try {
      await compiler?.dispose();
    } finally {
      await item.cleanup();
    }
  }
});
for (
  const mode of [
    "cross-id",
    "wrong-kind",
    "wrong-epoch",
    "same-revision",
    "failed-revision",
    "invalid-wasm",
    "reject-payload",
    "missing-offset",
    "invalid-hole",
    "source-fuel",
    "missing-work",
    "fractional-work",
    "truncated-header",
    "truncated-metadata",
    "truncated-payload",
    "oversized",
    "oversized-metadata",
    "invalid-json",
    "invalid-utf8",
    "stderr",
  ]
) {
  Deno.test(`client terminates malformed peer: ${mode}`, async () => {
    const item = await fixture(mode);
    let compiler: ZigProjectCompiler | undefined;
    try {
      compiler = await createZigProjectCompiler(item.options);
      const pid = compiler.pid;
      await rejects(compiler.build(), (error) => {
        ok(error instanceof Error);
        if (mode === "stderr") {
          ok(error.message.includes("STDERR-TAIL"));
          ok(error.message.length < 66_000);
        }
        return true;
      });
      await compiler.dispose();
      reaped(pid);
      await rejects(compiler.build());
    } finally {
      await compiler?.dispose();
      await item.cleanup();
    }
  });
}
for (const mode of ["wrong-version", "hello-payload", "startup-stall"]) {
  Deno.test(`client reaps failed startup: ${mode}`, async () => {
    const item = await fixture(mode);
    try {
      // The peer must reach its intentional stall and write its PID before
      // timeout. A 150 ms deadline can expire during Deno startup under load.
      await rejects(createZigProjectCompiler(item.options));
      const rows = await logs(item.log);
      reaped(rows[0].pid);
    } finally {
      await item.cleanup();
    }
  });
}
Deno.test("client rejects unsupported fuel, analysis, source mode and thread options before spawn", async () => {
  const item = await fixture("fragmented");
  try {
    for (
      const key of [
        "const_steps",
        "remaining_steps",
        "analysis",
        "overlays",
        "source",
        "inputMode",
        "threads",
        "priority",
      ]
    ) await rejects(createZigProjectCompiler({ ...item.options, [key]: 1 }));
    await rejects(Deno.stat(item.log), Deno.errors.NotFound);
  } finally {
    await item.cleanup();
  }
});

Deno.test("explicit dispose rejects active and queued work and reaps without an abort signal", async () => {
  const item = await fixture("active-stall");
  let compiler: ZigProjectCompiler | undefined;
  try {
    compiler = await createZigProjectCompiler(item.options);
    const pid = compiler.pid;
    const checked = Promise.all([
      rejects(compiler.build(), /disposed/),
      rejects(compiler.build(), /disposed/),
    ]);
    await waiting(item.log, "build");
    const disposed = compiler.dispose();
    strictEqual(disposed, compiler.dispose());
    await disposed;
    await checked;
    reaped(pid);
    equal(
      (await logs(item.log)).filter((row) => row.kind === "build").length,
      1,
    );
  } finally {
    try {
      await compiler?.dispose();
    } finally {
      await item.cleanup();
    }
  }
});
Deno.test("close validates its own request ID and reaps a malformed acknowledgement", async () => {
  const item = await fixture("close-id");
  let compiler: ZigProjectCompiler | undefined;
  try {
    compiler = await createZigProjectCompiler(item.options);
    const pid = compiler.pid;
    await compiler.build();
    await rejects(compiler.close(), /request ID mismatch/);
    await compiler.dispose();
    reaped(pid);
  } finally {
    try {
      await compiler?.dispose();
    } finally {
      await item.cleanup();
    }
  }
});
Deno.test("expected compiler identity mismatch rejects startup and reaps before open", async () => {
  const item = await fixture("fragmented");
  try {
    await rejects(
      createZigProjectCompiler({
        ...item.options,
        expectedCompilerIdentity: "b".repeat(64),
      }),
      /identity mismatch/,
    );
    const rows = await logs(item.log);
    reaped(rows[0].pid);
    equal(rows.filter((row) => row.kind === "open").length, 0);
  } finally {
    await item.cleanup();
  }
});
Deno.test("already aborted and unsupported build options do not advance IDs or revisions", async () => {
  const item = await fixture("fragmented");
  let compiler: ZigProjectCompiler | undefined;
  try {
    compiler = await createZigProjectCompiler(item.options);
    const signal = AbortSignal.abort();
    await rejects(
      compiler.build({ signal }),
      (error) => error instanceof DOMException && error.name === "AbortError",
    );
    await rejects(
      compiler.build({ const_steps: 1 } as { signal?: AbortSignal }),
      /Unsupported build/,
    );
    equal((await compiler.build()).revision, 1);
    await compiler.close();
    equal(
      (await logs(item.log)).filter((row) => row.kind === "build").map(
        (row) => [row.id, row.revision],
      ),
      [[2, 0]],
    );
  } finally {
    try {
      await compiler?.dispose();
    } finally {
      await item.cleanup();
    }
  }
});
