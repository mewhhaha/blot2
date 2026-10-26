import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { readMemoryProfile } from "../../compiler/memory_profile.ts";

const source = `import * as array from "std/array"
entry const boxed = fn (count: U32) -> Array U32 => #[count, count + 1]
entry const copied = fn (count: U32) => do:
  let values = array.generate count (fn index => index + 1)
  let old = values
  values[0] := 99
  break old[0] + values[0] + old.length
entry const closures = fn (steps: U32) => do:
  let saved = array.generate 8 (fn index => fn offset => index + offset)
  let total = 0
  for step in 0..steps:
    let copied = array.generate saved.length (fn i => saved[i])
    total := self + copied[step % copied.length] step
  break total
entry const trapped = fn (index: U32) => do:
  let values = array.generate 8 (fn i => i + 1)
  break values[index]
`;

function instance(bytes: Uint8Array<ArrayBuffer>) {
  const module = new WebAssembly.Module(bytes);
  return { module, exports: new WebAssembly.Instance(module).exports };
}
function invoke(guest: ReturnType<typeof instance>, name: string, arg: number) {
  const e = guest.exports;
  (e["blot:ownership_enter"] as CallableFunction)();
  let outcome = 1;
  try {
    const value = (e[name] as CallableFunction)(arg) >>> 0;
    outcome = 0;
    return value;
  } finally {
    (e["blot:ownership_leave"] as CallableFunction)(outcome);
  }
}
const productionCounters = {
  retains: "rc_retains",
  releases: "rc_releases",
  retired_objects: "rc_destroyed",
  cycle_passes: "cycle_passes",
  cycle_vertices: "cycle_vertices",
  cycle_edges: "cycle_edges",
  cycle_bytes: "cycle_bytes",
} as const;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`executed memory costs reconcile after copies reuse traps and retained source edits (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-memory-profile-",
    });
    const entry = `${directory}/main.blot`;
    const options = {
      executable: resolve(Deno.args[0] ?? "zig-native/zig-out/bin/blotc"),
      entry,
      prelude: new URL("../../std/prelude.blot", import.meta.url),
      stdRoot: new URL("../../std", import.meta.url),
      cacheDirectory: false as const,
      codegenTier,
    };
    const compiler = await createZigProjectCompiler({
      ...options,
      profileMemory: true,
    });
    const control = await createZigProjectCompiler(options);
    try {
      const built = await compiler.build({ sources: { [entry]: source } });
      const plain = await control.build({ sources: { [entry]: source } });
      assert(built.success, JSON.stringify(built));
      assert(plain.success, JSON.stringify(plain));
      const guest = instance(built.bytes), baseline = instance(plain.bytes);
      assert.equal(
        WebAssembly.Module.customSections(
          baseline.module,
          "blot:memory-profile",
        ).length,
        0,
      );
      let warmLive: bigint | undefined;
      for (let pass = 0; pass < 5; pass++) {
        assert(invoke(guest, "boxed", pass) > 0);
        assert(invoke(baseline, "boxed", pass) > 0);
        assert.equal(invoke(guest, "copied", 32), 132);
        assert.equal(invoke(baseline, "copied", 32), 132);
        assert.equal(invoke(guest, "closures", 16), 176);
        assert.equal(invoke(baseline, "closures", 16), 176);
        for (const target of [guest, baseline]) {
          assert.throws(
            () => invoke(target, "trapped", 8),
            WebAssembly.RuntimeError,
          );
          assert.equal(invoke(target, "trapped", 0), 1);
        }
        const report = readMemoryProfile(guest.module, guest.exports);
        assert(report.complete);
        assert(report.totals.copy_bytes >= 32n * 4n);
        assert(report.totals.requested_bytes > report.totals.live_bytes);
        if (warmLive !== undefined) {
          assert.equal(report.totals.live_bytes, warmLive);
        }
        warmLive = report.totals.live_bytes;
        for (const [metric, counter] of Object.entries(productionCounters)) {
          const observed = Number(
            (guest.exports[`blot:${counter}`] as WebAssembly.Global).value,
          ) >>> 0;
          const expected = Number(
            (baseline.exports[`blot:${counter}`] as WebAssembly.Global).value,
          ) >>> 0;
          assert.equal(observed, expected, counter);
          assert.equal(
            report.totals[metric as keyof typeof productionCounters],
            BigInt(observed),
            metric,
          );
        }
        assert(
          report.sites.some((site) =>
            site.filename === entry && site.counts.allocations > 0n
          ),
          JSON.stringify(
            report.sites.map((
              s,
            ) => [s.filename, s.start, String(s.counts.allocations)]),
          ),
        );
      }
      const repeated = await compiler.build({ sources: { [entry]: source } });
      assert(repeated.success);
      assert.deepEqual(repeated.bytes, built.bytes);
      const shiftedSource = "// updated source locations\n" + source;
      const shifted = await compiler.build({
        sources: { [entry]: shiftedSource },
      });
      assert(shifted.success);
      const fresh = await createZigProjectCompiler({
        ...options,
        profileMemory: true,
      });
      try {
        const rebuilt = await fresh.build({
          sources: { [entry]: shiftedSource },
        });
        assert(rebuilt.success);
        assert.deepEqual(shifted.bytes, rebuilt.bytes);
      } finally {
        await fresh.dispose();
      }
      const before = readMemoryProfile(guest.module, guest.exports);
      const next = instance(shifted.bytes);
      const after = readMemoryProfile(next.module, next.exports);
      assert.throws(
        () => readMemoryProfile(guest.module, next.exports),
        /does not match the live instance/,
      );
      assert(before.compilerIdentity !== null);
      assert(before.sites.some((site) => site.inline_depth > 0));
      assert(
        before.sites.filter((site) => site.filename === entry).every((site) =>
          site.source_blake3 !== null
        ),
      );
      assert.deepEqual(
        after.sites.filter((site) => site.filename === entry).map((
          site,
        ) => [site.start, site.end]),
        before.sites.filter((site) => site.filename === entry).map((
          site,
        ) => [site.start + 28, site.end + 28]),
      );
      // An overflow is an explicit incomplete report, even when its wrapped
      // source/category sums can no longer reconcile mathematically.
      const overflow = instance(built.bytes);
      const metadata = JSON.parse(
        new TextDecoder().decode(
          WebAssembly.Module.customSections(
            overflow.module,
            "blot:memory-profile",
          )[0],
        ),
      );
      const memory = new DataView(
        (overflow.exports["blot:memory"] as WebAssembly.Memory).buffer,
      );
      const metric = metadata.metrics.indexOf("allocations");
      memory.setBigUint64(
        metadata.counters + metadata.total_row * metadata.row_bytes +
          metric * 8,
        0xffff_ffff_ffff_ffffn,
        true,
      );
      invoke(overflow, "boxed", 1);
      const failed = readMemoryProfile(overflow.module, overflow.exports);
      assert.equal(failed.complete, false);
      assert(failed.status & 4);
    } finally {
      await compiler.dispose();
      await control.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

Deno.test("memory attribution survives JSPI suspension rejection and rejected host reentry", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-memory-suspension-",
  });
  const entry = `${directory}/main.blot`;
  const source = `entry const nested = fn (seed: U32) => (#[seed, seed + 1])[1]
entry const run = fn (host: Unit -> U32 ! {Foreign}) => do:
  let before = #[10, 20]
  use seed <- host ()
  let after = #[seed, seed + 1]
  break before[0] + after[1]
`;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0],
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url),
    cacheDirectory: false,
    profileMemory: true,
  });
  try {
    const built = await compiler.build({ sources: { [entry]: source } });
    assert(built.success, JSON.stringify(built));
    const module = new WebAssembly.Module(built.bytes);
    const jspi = WebAssembly as unknown as {
      Suspending: new (
        callback: () => Promise<number>,
      ) => WebAssembly.ImportValue;
      promising(fn: CallableFunction): (...args: unknown[]) => Promise<number>;
    };
    let settle!: (value: number) => void;
    let reject!: (reason: Error) => void;
    const raw = new WebAssembly.Instance(module, {
      "blot:host/1": {
        call_unit_u32: new jspi.Suspending(() =>
          new Promise<number>((resolve, fail) => {
            settle = resolve;
            reject = fail;
          })
        ),
      },
    }).exports;
    const enter = raw["blot:ownership_enter"] as CallableFunction;
    const leave = raw["blot:ownership_leave"] as CallableFunction;
    const run = jspi.promising(raw.run as CallableFunction);
    let warmLive: bigint | undefined;
    for (let pass = 0; pass < 4; pass++) {
      enter();
      const pending = run({});
      assert(readMemoryProfile(module, raw).complete);
      // The ownership ABI forbids a second invocation while suspended.
      // Its rejection must leave both the first invocation and attribution intact.
      assert.throws(() => enter(), WebAssembly.RuntimeError);
      if (pass % 2 === 0) {
        settle(30);
        assert.equal(await pending, 41);
        leave(0);
      } else {
        reject(new Error("profile rejection"));
        await assert.rejects(pending, /profile rejection/);
        leave(1);
      }
      const report = readMemoryProfile(module, raw);
      assert(report.complete);
      if (warmLive !== undefined) {
        assert.equal(report.totals.live_bytes, warmLive);
      }
      warmLive = report.totals.live_bytes;
      assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
      assert(
        report.categories.some((row) =>
          row.name === "allocation" && row.counts.allocations > 0n
        ),
      );
      for (const [metric, counter] of Object.entries(productionCounters)) {
        assert.equal(
          report.totals[metric as keyof typeof productionCounters],
          BigInt(
            Number((raw[`blot:${counter}`] as WebAssembly.Global).value) >>> 0,
          ),
        );
      }
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("scalar-only programs publish a complete zero-source-allocation profile", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-scalar-profile-" });
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0],
    entry,
    cacheDirectory: false,
    profileMemory: true,
  });
  try {
    const built = await compiler.build({
      sources: {
        [entry]: "entry const run = fn (value: U32) => @u32.add value 1\n",
      },
    });
    assert(built.success, JSON.stringify(built));
    const guest = instance(built.bytes);
    assert.equal(invoke(guest, "run", 41), 42);
    const report = readMemoryProfile(guest.module, guest.exports);
    assert(report.complete);
    assert(report.sites.every((site) => site.counts.allocations === 0n));
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
