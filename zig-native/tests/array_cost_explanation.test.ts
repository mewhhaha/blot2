import { strict as assert } from "node:assert";
import { observeGuestAllocations } from "../../scripts/bench/guest_heap_observer.ts";

const source = `
import * as array from "std/array"
type Box is data = $Box { a: U32, b: U32 }
const boxed = func value => return $Box { a: value, b: value + 1 }
const read_box = func (row: Box) => return row.a + row.b
entry const nominal = func value => return read_box (boxed value)
const choose = func x => return if x > 0 then (func y => return y + x) else (func y => return y + 1)
entry const selected = func x => return do:
  let f = choose x
  break f 2
entry const direct = func count => return do:
  let values = array.fill count 0
  for index in 0..count:
    values := array.replace index (index + 1) values
  break values[count - 1]
entry const snapshot = func count => return do:
  let values = array.fill count 0
  let previous = values
  for index in 0..count:
    values := array.replace index (index + 1) values
  break values[count - 1] + previous[count - 1]
`;

type SourceSite = {
  filename: string;
  start: number;
  end: number;
  offset_encoding: string;
};

type ArrayCostSite = SourceSite & {
  result: string;
  reason: string;
};

type EmissionSite = SourceSite & {
  kind: string;
  requested_bytes: number | null;
  emissions: number;
};

Deno.test("allocation remarks locate array edits, nominal storage and closure capture without changing Wasm", async () => {
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
    assert.equal(
      ordinary.records.filter((record) => record.kind === "allocation_sites")
        .length,
      0,
    );
    const emissions = explained.records.filter((record) =>
      record.kind === "allocation_sites"
    );
    assert.equal(emissions.length, 1);
    const constructor = source.indexOf("$Box { a: value, b: value + 1 }");
    const nominalSites = (emissions[0].sites as EmissionSite[]).filter((site) =>
      site.filename === entry && site.start === constructor &&
      site.end === constructor + "$Box { a: value, b: value + 1 }".length
    );
    assert.deepEqual(
      nominalSites.map((
        site,
      ) => [site.kind, site.requested_bytes, site.emissions]),
      [["aggregate_storage", 8, 1], ["constructor_storage", 8, 1]],
    );
    const closure = source.indexOf("func y => return y + x");
    assert(
      (emissions[0].sites as EmissionSite[]).some((site) =>
        site.filename === entry && site.start === closure &&
        site.end === closure + "func y => return y + x".length &&
        site.kind === "closure_storage"
      ),
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
