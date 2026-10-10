import { strict as assert } from "node:assert";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;

// Every public example must decode its own checkpoint, including builtin
// nominal and effect identities and its persisted semantic owner, and reuse
// the same work as the producer.
Deno.test("public examples restart from their own portable query checkpoints", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-portable-" });
  try {
    const examples = [...Deno.readDirSync(`${repo}examples`)]
      .map((item) => item.name)
      .filter((name) => name.endsWith(".blot"))
      .sort();
    assert(examples.length > 0);
    for (const name of examples) {
      const build = async (cache: string, output: string) => {
        const result = await new Deno.Command(executable, {
          args: [
            "build-project",
            `${repo}examples/${name}`,
            output,
            "--prelude",
            `${repo}std/prelude.blot`,
            "--std-root",
            `${repo}std`,
          ],
          clearEnv: true,
          env: { BLOT_CACHE_DIR: cache },
          stdout: "piped",
          stderr: "piped",
        }).output();
        const text = new TextDecoder().decode(result.stdout);
        assert(result.success, `${name}: ${text}`);
        const metrics = text.trim().split("\n").map((line) => JSON.parse(line))
          .find((row) => row.kind === "compilation");
        assert.equal(metrics.memory.live_bytes, 0, name);
        return { metrics, bytes: await Deno.readFile(output) };
      };
      const cache = `${directory}/${name}.cache`;
      const fresh = await build("", `${directory}/${name}.fresh.wasm`);
      const populated = await build(cache, `${directory}/${name}.saved.wasm`);
      assert.deepEqual(populated.metrics.restart_cache, {
        loaded: false,
        saved: true,
      }, name);
      const restarted = await build(cache, `${directory}/${name}.loaded.wasm`);
      assert(restarted.metrics.restart_cache.loaded, name);
      assert.deepEqual(restarted.bytes, fresh.bytes, name);
      const optimizer = restarted.metrics.runtime_optimization;
      assert.equal(optimizer.reused, optimizer.functions - optimizer.shared, name);
      assert.equal(restarted.metrics.principals.persisted_declines, 0, name);
      // The persisted semantic owner replays completed selected receipts.
      const selected = restarted.metrics.selected_queries;
      if (populated.metrics.selected_queries.complete_records > 0) {
        assert(selected.reused > 0, `${name}: ${JSON.stringify(selected)}`);
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
