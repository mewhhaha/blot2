import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const source = (offset: string) => `
const offset = ${offset}
entry const folded: U32 where { type_rep U32 } = do:
  let local = fn value => value
  return local offset
entry const answer = fn (value: U32) => @u32.add value offset
`;

async function files(directory: string): Promise<string[]> {
  const found: string[] = [];
  for await (const item of Deno.readDir(directory)) {
    const path = `${directory}/${item.name}`;
    if (item.isDirectory) found.push(...await files(path));
    else found.push(path);
  }
  return found;
}

// Each key also keeps a `.lock` file; a `.partial` file only exists while its
// writer runs.
async function caches(directory: string): Promise<string[]> {
  const found = await files(directory);
  assert(!found.some((path) => path.endsWith(".partial")), found.join("\n"));
  return found.filter((path) => path.endsWith(".blotcache"));
}

for (const project of [false, true]) {
  Deno.test(`default ${project ? "project" : "source"} CLI restart cache validates source and replaces corrupt candidates atomically`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const cache = `${directory}/cache`;
    let serial = 0;
    const build = async (root = cache, expected = true) => {
      const output = `${directory}/result-${serial++}.wasm`;
      const result = await new Deno.Command(executable, {
        args: [
          project ? "build-project" : "build",
          entry,
          output,
          ...(project ? ["--prelude", "none"] : []),
        ],
        clearEnv: true,
        env: { BLOT_CACHE_DIR: root },
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert.equal(
        result.success,
        expected,
        new TextDecoder().decode(result.stdout),
      );
      assert.equal(
        result.stderr.length,
        0,
        new TextDecoder().decode(result.stderr),
      );
      const rows = new TextDecoder().decode(result.stdout).trim().split("\n")
        .map(
          (line) => JSON.parse(line),
        );
      const metrics = rows.find((row) => row.kind === "compilation");
      assert.equal(metrics.memory.live_bytes, 0);
      return {
        metrics: metrics.stats ?? metrics,
        bytes: expected ? await Deno.readFile(output) : null,
        errors: rows.filter((row) => row.kind === "diagnostic"),
      };
    };
    try {
      await Deno.writeTextFile(entry, source("1"));
      const fresh = await build("");
      const populated = await build();
      assert.deepEqual(populated.metrics.restart_cache, {
        loaded: false,
        saved: true,
      });
      const restarted = await build();
      assert(restarted.metrics.restart_cache.loaded);
      assert(restarted.metrics.principals.persisted_hits > 0);
      assert.deepEqual(restarted.bytes, fresh.bytes);
      const [artifact] = await caches(cache);
      assert(artifact.endsWith(".blotcache"));
      const valid = await Deno.readFile(artifact);
      await Deno.writeTextFile(artifact, "truncated checkpoint");
      const repaired = await build();
      assert.deepEqual(repaired.metrics.restart_cache, {
        loaded: false,
        saved: true,
      });
      assert.deepEqual(repaired.bytes, fresh.bytes);
      // A foreign identity is rejected even if its file is placed under this key.
      const foreign = valid.slice();
      foreign[44] ^= 1;
      await Deno.writeFile(artifact, foreign);
      assert.equal((await build()).metrics.restart_cache.loaded, false);
      for (const result of await Promise.all([build(), build()])) {
        assert.deepEqual(result.bytes, fresh.bytes);
      }
      assert.equal((await caches(cache)).length, 1);
      await Deno.writeTextFile(entry, source("2"));
      const changed = await build();
      assert.deepEqual(changed.bytes, (await build("")).bytes);
      const beforeFailure = await Deno.readFile(artifact);
      await Deno.writeTextFile(entry, source("#True"));
      const failed = await build(cache, false);
      assert.deepEqual(failed.errors, (await build("", false)).errors);
      assert.deepEqual(await Deno.readFile(artifact), beforeFailure);
      await Deno.writeTextFile(entry, source("1"));
      assert.deepEqual((await build()).bytes, fresh.bytes);
      const unavailable = `${directory}/file`;
      await Deno.writeTextFile(unavailable, "not a directory");
      assert.deepEqual((await build(unavailable)).bytes, fresh.bytes);
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}

Deno.test("project server persists committed checkpoints across disposal and graceful close", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: `${directory}/cache`,
  };
  try {
    await Deno.writeTextFile(entry, source("1"));
    const first = await createZigProjectCompiler(options);
    let original: Uint8Array<ArrayBuffer>;
    try {
      const built = await first.build();
      assert(built.success, JSON.stringify(built));
      assert.equal(built.stats.restartCacheLoaded, false);
      original = built.bytes;
    } finally {
      await first.dispose();
    }
    // Unchanged inputs publish the persisted output without compiling, and
    // export the checkpoint written with it.
    const unchanged = await createZigProjectCompiler(options);
    try {
      const built = await unchanged.build();
      assert(built.success, JSON.stringify(built));
      assert.equal(built.stats.restartCacheLoaded, true);
      assert.equal(built.stats.attemptStats.restored_output, true);
      assert.deepEqual(built.bytes, original!);
      assert((await unchanged.exportCheckpoint()).length > 0);
    } finally {
      await unchanged.dispose();
    }
    // Another output policy cannot take the output; it compiles warm from
    // the checkpoint instead.
    const retained = await createZigProjectCompiler({
      ...options,
      codegenWorkers: 1,
    });
    let expected: Uint8Array<ArrayBuffer>;
    try {
      const built = await retained.build();
      assert(built.success, JSON.stringify(built));
      assert.equal(built.stats.restartCacheLoaded, true);
      assert.equal(built.stats.attemptStats.restored_output, false);
      assert.deepEqual(built.bytes, original!);
      assert(
        (built.stats.principals as Record<string, number>).persisted_hits > 0,
      );
      const changed = await retained.build({
        sources: { [entry]: source("2") },
      });
      assert(changed.success, JSON.stringify(changed));
      expected = changed.bytes;
      const failed = await retained.build({
        sources: { [entry]: source("#True") },
      });
      assert(!failed.success);
      await retained.close();
    } finally {
      await retained.dispose();
    }
    // The closed revision read its entry from an overlay; the same bytes on
    // disk are the same input.
    await Deno.writeTextFile(entry, source("2"));
    const restored = await createZigProjectCompiler({
      ...options,
      codegenWorkers: 1,
    });
    const fresh = await createZigProjectCompiler({
      ...options,
      cacheDirectory: false,
    });
    try {
      const [current, reference] = await Promise.all([
        restored.build(),
        fresh.build(),
      ]);
      assert(current.success && reference.success);
      assert.equal(current.stats.restartCacheLoaded, true);
      assert.equal(current.stats.attemptStats.restored_output, true);
      assert.equal(reference.stats.restartCacheLoaded, false);
      assert.deepEqual(current.bytes, expected!);
      assert.deepEqual(current.bytes, reference.bytes);
      const guest = await instantiateGuest(current.bytes);
      try {
        assert.equal(guest.call("answer", 40), 42);
        assert.equal(guest.read("folded"), 2);
      } finally {
        guest.dispose();
      }
    } finally {
      await restored.dispose();
      await fresh.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

/** Waits, as an open does, until no writer holds the key's lock. */
async function settle(lock: string) {
  const file = await Deno.open(lock, { read: true });
  try {
    await file.lock(false);
    await file.unlock();
  } finally {
    file.close();
  }
}
/** The latest detached writer, which names itself in the lock file. */
async function writer(lock: string): Promise<number | undefined> {
  const text = await Deno.readTextFile(lock);
  return text ? JSON.parse(text).writer : undefined;
}
const pause = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
/** Polls until `ready` holds, at most five seconds. */
async function until(ready: () => Promise<boolean>, what: string) {
  for (let waited = 0; !(await ready()); waited += 5) {
    if (waited > 5000) throw new Error(`timed out waiting for ${what}`);
    await pause(5);
  }
}
function alive(pid: number): boolean {
  try {
    Deno.kill(pid, "SIGCONT");
    return true;
  } catch {
    return false;
  }
}
async function keyPaths(cache: string) {
  const [lock] = (await files(cache)).filter((path) => path.endsWith(".lock"));
  assert(lock);
  await settle(lock);
  const [artifact] = await caches(cache);
  assert(artifact);
  return { lock, artifact, output: artifact.replace(/\.blotcache$/, ".blotout") };
}

// A detached writer only exists where the server forks one (Linux).
const detached = Deno.build.os === "linux";

Deno.test({
  name:
    "project server cache writer killed before publishing leaves no cache, and the next open builds cold",
  ignore: !detached,
  fn: async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const cache = `${directory}/cache`;
    const options = { executable, entry, prelude: null, cacheDirectory: cache };
    try {
      await Deno.writeTextFile(entry, source("1"));
      const fresh = await createZigProjectCompiler({
        ...options,
        cacheDirectory: false,
      });
      let expected: Uint8Array<ArrayBuffer>;
      try {
        const built = await fresh.build();
        assert(built.success, JSON.stringify(built));
        expected = built.bytes;
      } finally {
        await fresh.dispose();
      }
      const first = await createZigProjectCompiler(options);
      try {
        assert((await first.build()).success);
      } finally {
        await first.dispose();
      }
      const { lock, artifact, output } = await keyPaths(cache);
      await Deno.remove(artifact);
      await Deno.remove(output);
      const previous = await writer(lock);
      assert(previous !== undefined, "a writer names itself in the lock file");
      // Holding the lock stalls the next writer before it publishes.
      const holder = await Deno.open(lock, { read: true, write: true });
      const stalled = await createZigProjectCompiler(options);
      try {
        await holder.lock(true);
        const built = await stalled.build();
        assert(built.success && !built.stats.restartCacheLoaded);
      } finally {
        await stalled.dispose();
      }
      let stuck = 0;
      await until(async () => {
        stuck = (await writer(lock)) ?? previous;
        return stuck !== previous;
      }, "the stalled writer");
      assert(alive(stuck), "the writer outlives its killed server");
      Deno.kill(stuck, "SIGKILL");
      // A killed process never runs again; wait briefly for it to be reaped.
      for (let tries = 0; tries < 200 && alive(stuck); tries++) await pause(5);
      // What a writer killed mid-write leaves behind is never read.
      await Deno.writeTextFile(`${artifact}.partial`, "truncated checkpoint");
      await holder.unlock();
      holder.close();
      const cold = await createZigProjectCompiler(options);
      try {
        const built = await cold.build();
        assert(built.success, JSON.stringify(built));
        assert.equal(built.stats.restartCacheLoaded, false);
        assert.deepEqual(built.bytes, expected!);
      } finally {
        await cold.dispose();
      }
      await settle(lock);
      assert.deepEqual(await caches(cache), [artifact]);
      const warm = await createZigProjectCompiler(options);
      try {
        const built = await warm.build();
        assert(built.success && built.stats.restartCacheLoaded);
        assert.deepEqual(built.bytes, expected!);
      } finally {
        await warm.dispose();
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  },
});

Deno.test({
  name:
    "project server opens wait for a cache write in flight and all load the published file",
  ignore: !detached,
  fn: async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const cache = `${directory}/cache`;
    const options = { executable, entry, prelude: null, cacheDirectory: cache };
    try {
      await Deno.writeTextFile(entry, source("1"));
      let expected: Uint8Array<ArrayBuffer>;
      const first = await createZigProjectCompiler(options);
      try {
        const built = await first.build();
        assert(built.success, JSON.stringify(built));
        expected = built.bytes;
      } finally {
        await first.dispose();
      }
      const { lock, artifact, output } = await keyPaths(cache);
      const published = await Deno.readFile(artifact);
      await Deno.remove(artifact);
      await Deno.remove(output);
      // This test stands in for a writer: it holds the lock, then publishes.
      const holder = await Deno.open(lock, { read: true, write: true });
      await holder.lock(true);
      const opened: boolean[] = [false, false];
      const pending = opened.map((_, index) =>
        createZigProjectCompiler(options).then((compiler) => {
          opened[index] = true;
          return compiler;
        })
      );
      await new Promise((resolve) => setTimeout(resolve, 300));
      assert.deepEqual(opened, [false, false], "opens wait for the writer");
      await Deno.writeFile(`${artifact}.test`, published);
      await Deno.rename(`${artifact}.test`, artifact);
      await holder.unlock();
      holder.close();
      const compilers = await Promise.all(pending);
      try {
        for (const built of await Promise.all(compilers.map((c) => c.build()))) {
          assert(built.success, JSON.stringify(built));
          assert.equal(built.stats.restartCacheLoaded, true);
          assert.deepEqual(built.bytes, expected!);
        }
      } finally {
        await Promise.all(compilers.map((c) => c.dispose()));
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  },
});

Deno.test("project server restores an output only for exactly its inputs and its compiler", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const cache = `${directory}/cache`;
  const options = { executable, entry, prelude: null, cacheDirectory: cache };
  const build = async (overrides = {}) => {
    const compiler = await createZigProjectCompiler({
      ...options,
      ...overrides,
    });
    try {
      const built = await compiler.build();
      assert(built.success, JSON.stringify(built));
      return built;
    } finally {
      await compiler.dispose();
    }
  };
  try {
    await Deno.writeTextFile(entry, source("1"));
    const original = (await build({ cacheDirectory: false })).bytes;
    await build();
    const [lock] = (await files(cache)).filter((path) =>
      path.endsWith(".lock")
    );
    await settle(lock);
    const [output] = (await files(cache)).filter((path) =>
      path.endsWith(".blotout")
    );
    assert(output, "the writer publishes the output part");
    const valid = await Deno.readFile(output);
    // A changed source compiles; its bytes equal a fresh build.
    await Deno.writeTextFile(entry, source("2"));
    const changed = await build();
    assert.equal(changed.stats.attemptStats.restored_output, false);
    assert.deepEqual(changed.bytes, (await build({ cacheDirectory: false })).bytes);
    await settle(lock);
    await Deno.writeTextFile(entry, source("1"));
    // Truncated, corrupt or foreign output bytes are ignored.
    const foreign = valid.slice();
    foreign[44] ^= 1;
    const corrupt = valid.slice();
    corrupt[corrupt.length - 1] ^= 1;
    for (const bytes of [valid.slice(0, valid.length >> 1), corrupt, foreign]) {
      await Deno.writeFile(output, bytes);
      const built = await build();
      assert.equal(built.stats.attemptStats.restored_output, false);
      assert.deepEqual(built.bytes, original);
      await settle(lock);
    }
    await Deno.writeFile(output, valid);
    const restored = await build();
    assert.equal(restored.stats.attemptStats.restored_output, true);
    assert.deepEqual(restored.bytes, original);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
