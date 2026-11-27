import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

for (const profileBackend of [false, true]) {
  Deno.test(`profiled sessions preserve executed output and failed-edit recovery (backend profile ${profileBackend})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "squid-heap-profile-" });
    const entry = `${directory}/main.sq`;
    const source = "io const answer = func (value: U32): U32 => return @u32.add value 1\n";
    const options = {
      executable: Deno.args[0],
      entry,
      prelude: null,
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
          sources: { [entry]: "io const answer: U32 = 1.5\n" },
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
