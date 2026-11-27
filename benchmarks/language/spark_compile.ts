// deno run -A benchmarks/language/spark_compile.ts [gdev checkout] [squidc]
import assert from "node:assert/strict";
import { resolve } from "node:path";
import { instantiateGuest } from "../../host/guest.ts";
import { Processes } from "../../host/processes.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { gdevProject } from "../../scripts/integration/gdev_project.ts";

const root = resolve(Deno.args[0] ?? "../gdev");
const executable = resolve(Deno.args[1] ?? "compiler-goose/build/squidc-goose");
const fixtures = [
  {
    name: "spark_routes",
    from: "=> return seed\n",
    to: "=> return @u32.add seed 1\n",
    entry: "route_planner",
  },
  {
    name: "spark_spawn",
    from: "@u32.mul x 2 |",
    to: "@u32.mul x 3 |",
    entry: "twice",
  },
];
const digest = async (bytes: Uint8Array<ArrayBuffer>) =>
  new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)).toHex();
const records = [];
for (const fixture of fixtures) {
  const source = await Deno.readTextFile(
    new URL(`./${fixture.name}.sq`, import.meta.url),
  );
  assert.equal(source.split(fixture.from).length, 2);
  const edit = source.replace(fixture.from, fixture.to);
  const project = await gdevProject(
    root,
    resolve("std"),
    `performance/modernize/${fixture.name}.sq`,
    executable,
  );
  const hashes = new Map<string, string>();
  for (let pair = 0; pair < 6; pair++) {
    // Reverse which version is compiled fresh so both retained edits have fresh controls.
    let versions = [source, edit];
    if (pair % 2) versions = [edit, source];
    let start = performance.now();
    const client = await createZigProjectCompiler({
      ...project,
      frontendWorkers: 8,
    });
    try {
      for (const [index, version] of versions.entries()) {
        const result = await client.build({
          sources: { [project.entry]: version },
          signal: AbortSignal.timeout(8000),
        });
        const ms = performance.now() - start;
        if (!result.success) throw Error(JSON.stringify(result.diagnostics));
        const hash = await digest(result.bytes);
        if (hashes.has(version)) assert.equal(hashes.get(version), hash);
        hashes.set(version, hash);
        if (fixture.entry === "twice") {
          const guest = await instantiateGuest(result.bytes);
          try {
            let expected = 14;
            if (version === edit) expected = 21;
            assert.deepEqual(
              guest.call(fixture.entry, Uint32Array.of(7)),
              Uint32Array.of(expected),
            );
          } finally {
            guest.dispose();
          }
        } else {
          const procs = new Processes(result.bytes, [{
            name: "route_planner",
            initWork: 1,
            stepWork: 1,
            mailbox: 1,
            mailboxBytes: 64,
            maxReplyBytes: 4,
          }]);
          try {
            const h = procs.admit("route_planner", 7);
            assert(h !== null);
            await procs.advance(1);
            const t = procs.send(h, 0);
            assert.equal(typeof t, "number");
            await procs.advance(1);
            const ev = procs.poll(h);
            assert(ev?.status === "done");
          } finally {
            await procs.restore();
          }
        }
        records.push({
          fixture: fixture.name,
          pair,
          session: ["fresh", "retained"][index],
          editedSource: version === edit,
          ms,
          freshModules: result.stats.freshModules,
          cachedModules: result.stats.cachedModules,
          wasmSha256: hash,
        });
        start = performance.now();
      }
    } finally {
      await client.dispose();
    }
  }
  assert.equal(new Set(hashes.values()).size, 2);
}
console.log(
  JSON.stringify(
    {
      compilerSha256: await digest(await Deno.readFile(executable)),
      frontendWorkers: 8,
      records,
    },
    null,
    2,
  ),
);
