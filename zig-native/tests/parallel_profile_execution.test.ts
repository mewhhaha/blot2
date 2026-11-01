import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

for (const profileBackend of [false, true]) {
  Deno.test(`heap diagnostics preserve executed output and failed-edit recovery (backend profile ${profileBackend})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-heap-profile-" });
    const entry = `${directory}/main.blot`;
    const source = "entry const answer = func (value: U32): U32 => return @u32.add value 1\n";
    const options = {
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false as const,
      frontendWorkers: 4,
      startupTimeoutMs: 5000,
    };
    const ordinary = await createZigProjectCompiler(options);
    const profiled = await createZigProjectCompiler({
      ...options,
      profileBackend,
      profileTrace: true,
    });
    try {
      const reference = await ordinary.build({
        sources: { [entry]: source },
        signal: AbortSignal.timeout(5000),
      });
      assert(reference.success, JSON.stringify(reference));
      for (const text of [source, source.replace("value 1", "value 2"), source]) {
        const built = await profiled.build({
          sources: { [entry]: text },
          signal: AbortSignal.timeout(5000),
        });
        assert(built.success, JSON.stringify(built));
        if (text === source) assert.deepEqual(built.bytes, reference.bytes);
        const heap = built.stats.sessionHeap as {
          complete: boolean;
          diagnostic: {
            diagnostic: boolean;
            acquisitions: number;
            contended_acquisitions: number;
            wait_kind: string;
            wait_ns: number | null;
          };
        };
        assert(heap.complete);
        assert(heap.diagnostic.diagnostic);
        assert(heap.diagnostic.acquisitions > 0);
        assert(heap.diagnostic.contended_acquisitions <= heap.diagnostic.acquisitions);
        assert.equal(heap.diagnostic.wait_kind, "worker_sum");
        if (heap.diagnostic.wait_ns !== null) assert(heap.diagnostic.wait_ns >= 0);
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            let expected = 42;
            if (text !== source) expected = 43;
            if (asynchronous) assert.equal(await guest.callAsync("answer", 41), expected);
            else assert.equal(guest.call("answer", 41), expected);
          } finally {
            guest.dispose();
          }
        }
        const rejected = await profiled.build({
          sources: { [entry]: "entry const answer: U32 = 1.5\n" },
          signal: AbortSignal.timeout(5000),
        });
        assert(!rejected.success);
      }
    } finally {
      await ordinary.dispose();
      await profiled.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
