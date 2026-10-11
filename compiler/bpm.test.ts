import { deepStrictEqual as equal } from "node:assert/strict";
import { runBpm } from "./bpm.ts";

Deno.test("bpm initializes a project without implicit prelude and preserves an existing manifest", async () => {
  const directory = await Deno.makeTempDir();
  try {
    equal(await runBpm(["init", directory]), 0);
    const original = await Deno.readTextFile(`${directory}/blot.json`);
    equal(JSON.parse(original), { dependencies: {} });
    equal(await runBpm(["init", directory]), 1);
    equal(await Deno.readTextFile(`${directory}/blot.json`), original);
    equal(await runBpm(["install", directory]), 0);
    equal(JSON.parse(await Deno.readTextFile(`${directory}/blot.lock.json`)), {
      version: 1,
      packages: {},
    });
    equal(await runBpm(["install", directory, "--frozen"]), 0);
    equal(await runBpm(["update", "--frozen"]), 2);
    equal(await runBpm(["install", "--cache"]), 2);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
