import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = await Deno.readTextFile(
  new URL("../fixtures/provider-fixtures/lifetime-cost.blot", import.meta.url),
);

function counters(
  bytes: Uint8Array<ArrayBuffer>,
  grouped: boolean,
  allocationsPerCycle: number,
) {
  const module = new WebAssembly.Module(bytes);
  assert.deepEqual([
    ...new Uint8Array(
      WebAssembly.Module.customSections(module, "blot:ownership")[0],
    ),
  ], [2, 2, 0]);
  const imports: Record<string, Record<string, CallableFunction>> = {};
  for (const item of WebAssembly.Module.imports(module)) {
    assert.equal(item.kind, "function");
    imports[item.module] ??= {};
    imports[item.module][item.name] = () => {
      throw new Error("unexpected host call inside closed activation");
    };
  }
  const raw = new WebAssembly.Instance(module, imports).exports;
  const count = (name: string) =>
    Number((raw[`blot:${name}`] as WebAssembly.Global).value);
  const mark = (raw["blot:ownership_enter"] as CallableFunction)();
  const before = count("rc_destroyed");
  assert.equal((raw.cycles as CallableFunction)(200), 19900);
  (raw["blot:ownership_leave"] as CallableFunction)(mark);
  (raw["blot:reset"] as CallableFunction)(0);
  assert.equal(count("rc_roots"), 0);
  assert.equal(count("rc_leases"), 0);
  assert.equal(count("rc_host_refs"), 0);
  assert.equal(count("rc_destroyed") - before, 200 * allocationsPerCycle);
  if (grouped) {
    assert.equal(count("cycle_passes"), 0);
    assert.equal(count("cycle_vertices"), 0);
    assert.equal(count("cycle_edges"), 0);
    assert.equal(count("cycle_bytes"), 0);
  } else {
    assert(count("cycle_passes") > 0);
    assert(count("cycle_bytes") > 0);
  }
}

Deno.test("unique region storage rederives fresh retained portable and changed State ownership", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-cohort-" });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        stdRoot: new URL("../../std/", import.meta.url),
        cacheDirectory: false as const,
        codegenTier,
        shareMachineCode: true,
      };
      const compiler = await createZigProjectCompiler(options);
      let checkpoint: Uint8Array<ArrayBuffer>;
      let original: Uint8Array<ArrayBuffer>;
      try {
        const fresh = await compiler.build({ sources: { [entry]: source } });
        assert(fresh.success, JSON.stringify(fresh));
        original = fresh.bytes;
        // The seed-only closure keeps its scalar environment unboxed.
        let allocationsPerCycle = 3;
        if (codegenTier === "optimized") allocationsPerCycle = 1;
        counters(original, true, allocationsPerCycle);
        const retained = await compiler.build({ sources: { [entry]: source } });
        assert(retained.success, JSON.stringify(retained));
        assert.deepEqual(retained.bytes, original);
        checkpoint = await compiler.exportCheckpoint();
        const changed = source.replace(
          "    use State.set $End",
          "    use State.set ($Next delayed)",
        );
        assert.notEqual(changed, source);
        const edited = await compiler.build({ sources: { [entry]: changed } });
        assert(edited.success, JSON.stringify(edited));
        let ordinaryAllocations = 7;
        if (codegenTier === "optimized") ordinaryAllocations = 5;
        counters(edited.bytes, false, ordinaryAllocations);
        const reverted = await compiler.build({ sources: { [entry]: source } });
        assert(reverted.success, JSON.stringify(reverted));
        assert.deepEqual(reverted.bytes, original);
      } finally {
        await compiler.close();
      }
      const restarted = await createZigProjectCompiler({
        ...options,
        checkpoint,
      });
      try {
        const portable = await restarted.build({
          sources: { [entry]: source },
        });
        assert(portable.success, JSON.stringify(portable));
        assert.deepEqual(portable.bytes, original);
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(portable.bytes, {
            asynchronous,
          });
          try {
            for (const count of [0, 1, 2, 200, 20000]) {
              let actual;
              if (asynchronous) actual = await guest.callAsync("cycles", count);
              else actual = guest.call("cycles", count);
              assert.equal(actual, Math.max(0, count * (count - 1) / 2));
              assert.equal(guest.memoryBytes(), 131072);
            }
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await restarted.close();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
