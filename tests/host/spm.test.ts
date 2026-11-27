import { deepStrictEqual as equal } from "node:assert/strict";
import { runSpm } from "../../host/spm.ts";

Deno.test("spm initializes a project without implicit prelude and preserves an existing manifest", async () => {
  const directory = await Deno.makeTempDir();
  try {
    equal(await runSpm(["init", directory]), 0);
    const original = await Deno.readTextFile(`${directory}/squid.json`);
    equal(JSON.parse(original), { dependencies: {} });
    equal(await runSpm(["init", directory]), 1);
    equal(await Deno.readTextFile(`${directory}/squid.json`), original);
    equal(await runSpm(["install", directory]), 0);
    equal(JSON.parse(await Deno.readTextFile(`${directory}/squid.lock.json`)), {
      version: 1,
      packages: {},
    });
    equal(await runSpm(["install", directory, "--frozen"]), 0);
    equal(await runSpm(["update", "--frozen"]), 2);
    equal(await runSpm(["install", "--cache"]), 2);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
