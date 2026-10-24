import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("allocation explanations retain native asset spans and identical execution across revisions", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-allocation-project-" });
  const entry = `${directory}/main.blot`;
  const asset = `${directory}/data.json`;
  const source = `import * as config from "./data.json"
entry const values = fn (replacement: U32) => do:
  let values = @array.generate (config.value).count $ fn index => index
  values[0] := replacement
  return values
`;
  try {
    await Deno.writeTextFile(entry, source);
    await Deno.writeTextFile(asset, '{"count":4}');
    let expected: Uint8Array | undefined;
    for (const explainAllocations of [false, true]) {
      const compiler = await createZigProjectCompiler({
        executable: resolve(Deno.args[0] ?? "zig-native/zig-out/bin/blotc"), entry,
        prelude: null, cacheDirectory: false, explainAllocations,
        nativeAssets: { roots: [directory], imports: [{ module: asset, path: asset, kind: "json" }] },
      });
      try {
        const first = await compiler.build();
        ok(first.success, JSON.stringify(first));
        if (expected) equal(first.bytes, expected);
        expected = first.bytes;
        const guest = await instantiateGuest(first.bytes);
        try { equal(Array.from(guest.call("values", 42) as Uint32Array), [42, 1, 2, 3]); }
        finally { guest.dispose(); }
        const repeated = await compiler.build();
        ok(repeated.success, JSON.stringify(repeated));
        equal(repeated.bytes, first.bytes);
        for (const field of ["allocationSites", "arrayCosts"] as const) {
          equal(repeated.stats[field], first.stats[field]);
          if (!explainAllocations) { equal(first.stats[field], null); continue; }
          const report = first.stats[field] as { sites: { filename: string; start: number; end: number }[]; omitted: number };
          ok(report.sites.length > 0 && report.sites.length <= 16384);
          ok(report.sites.some(site => site.filename === entry && site.end > site.start));
        }
        if (explainAllocations) {
          const shifted = await compiler.build({ sources: { [entry]: "// shift spans\n" + source } });
          ok(shifted.success, JSON.stringify(shifted));
          for (const field of ["allocationSites", "arrayCosts"] as const) {
            const before = first.stats[field] as { sites: { filename: string; start: number; end: number }[] };
            const after = shifted.stats[field] as typeof before;
            equal(after.sites.filter(site => site.filename === entry).map(site => [site.start, site.end]),
              before.sites.filter(site => site.filename === entry).map(site => [site.start + 15, site.end + 15]));
          }
        }
      } finally { await compiler.dispose(); }
    }
  } finally { await Deno.remove(directory, { recursive: true }); }
});
