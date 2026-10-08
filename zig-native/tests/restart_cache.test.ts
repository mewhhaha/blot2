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
      const [artifact] = await files(cache);
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
      assert.equal((await files(cache)).length, 1);
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
    try {
      const built = await first.build();
      assert(built.success, JSON.stringify(built));
      assert.equal(built.stats.restartCacheLoaded, false);
    } finally {
      await first.dispose();
    }
    const retained = await createZigProjectCompiler(options);
    let expected: Uint8Array<ArrayBuffer>;
    try {
      const built = await retained.build();
      assert(built.success, JSON.stringify(built));
      assert.equal(built.stats.restartCacheLoaded, true);
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
    await Deno.writeTextFile(entry, source("2"));
    const restored = await createZigProjectCompiler(options);
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
