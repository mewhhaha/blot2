import { strict as assert } from "node:assert";
import { observeGuestAllocations } from "../../scripts/bench/guest_heap_observer.ts";

const source = `
import * as array from "std/array"
entry const direct = fn count => do:
  let values = array.fill count 0
  for index in 0..count:
    values := array.replace index (index + 1) values
  break values[count - 1]
entry const snapshot = fn count => do:
  let values = array.fill count 0
  let previous = values
  for index in 0..count:
    values := array.replace index (index + 1) values
  break values[count - 1] + previous[count - 1]
`;

type ArrayCostSite = {
  filename: string;
  start: number;
  end: number;
  offset_encoding: string;
  result: string;
  reason: string;
};

Deno.test("array cost remarks locate exclusive and retained-snapshot edits without changing Wasm", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-array-cost-" });
  const entry = `${directory}/main.blot`;
  const wasm = `${directory}/main.wasm`;
  const compiler = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  try {
    await Deno.writeTextFile(entry, source);
    const build = async (explain: boolean) => {
      const command = new Deno.Command(compiler, {
        args: [
          "build-project",
          entry,
          wasm,
          "--std-root",
          new URL("../../std", import.meta.url).pathname,
          "--prelude",
          new URL("../../std/prelude.blot", import.meta.url).pathname,
          ...(explain ? ["--explain-allocations"] : []),
        ],
        stdout: "piped",
        stderr: "piped",
      });
      const result = await command.output();
      const output = new TextDecoder().decode(result.stdout);
      assert(result.success, output + new TextDecoder().decode(result.stderr));
      return {
        records: output.trim().split("\n").map((line) => JSON.parse(line)),
        bytes: await Deno.readFile(wasm),
      };
    };
    const ordinary = await build(false);
    const explained = await build(true);
    assert.deepEqual(explained.bytes, ordinary.bytes);
    assert.equal(
      ordinary.records.filter((record) => record.kind === "array_costs").length,
      0,
    );
    const reports = explained.records.filter((record) =>
      record.kind === "array_costs"
    );
    assert.equal(reports.length, 1);
    assert.equal(reports[0].omitted, 0);
    const sites = (reports[0].sites as ArrayCostSite[]).filter((site) =>
      site.filename === entry
    );
    assert.equal(sites.length, 2);
    const edits = [
      ...source.matchAll(/array\.replace index \(index \+ 1\) values/g),
    ];
    assert.equal(edits.length, 2);
    for (const [index, site] of sites.entries()) {
      assert.equal(site.start, edits[index].index);
      assert.equal(site.end, edits[index].index + edits[index][0].length);
      assert.equal(site.offset_encoding, "utf8_bytes");
    }
    assert.deepEqual(sites.map((site) => [site.result, site.reason]), [
      ["reuse_eligible", "reused"],
      ["copy_required", "nonexclusive_predecessor"],
    ]);
    const direct = observeGuestAllocations(explained.bytes, [[
      "direct",
      128,
      128,
    ]]);
    const snapshot = observeGuestAllocations(explained.bytes, [[
      "snapshot",
      128,
      128,
    ]]);
    assert(
      snapshot.rounded_allocation_bytes > direct.rounded_allocation_bytes * 10,
    );
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
