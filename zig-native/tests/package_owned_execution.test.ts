import { strict as assert } from "node:assert";
import { instantiateGuest, readGuestAbi } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { ResourceJournal } from "../../compiler/resource_journal.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out-dev/bin/blotc", import.meta.url).pathname;
const source = (value: number) =>
  `type Item = exists [a] => (unique a, (unique a) -> U32)
const read: (unique U32) -> U32 = fn hidden => @usage.borrow hidden (fn loan => @usage.read loan)
const make = fn (owner: unique U32) => pack [U32] (owner, read) as Item
entry const answer = fn () => do:
  use owner <- @resource.acquire (fn () => ${value}) (fn released => ())
  break unpack (make owner) as [a] value in do:
    let (hidden, operation) = value
    break operation hidden
`;

async function observe(bytes: Uint8Array<ArrayBuffer>, value: number) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      const invoke = async () => {
        if (asynchronous) return await guest.callAsync("answer", null);
        return guest.call("answer", null);
      };
      for (let index = 0; index < 16; index++) {
        assert.equal(await invoke(), value);
      }
      const warmed = guest.memoryBytes();
      for (let index = 0; index < 128; index++) {
        assert.equal(await invoke(), value);
      }
      assert.equal(guest.memoryBytes(), warmed);
    } finally {
      guest.dispose();
    }
  }
  const module = new WebAssembly.Module(bytes);
  const abi = readGuestAbi(module);
  const raw = new WebAssembly.Instance(module, {
    "blot:resource/1": {
      reserve: () => journal.reserve(),
      register: (
        token: number,
        adapter: number,
        payload: number,
        callable: number,
        provider: number,
      ) =>
        journal.register(
          token >>> 0,
          adapter,
          payload >>> 0,
          callable >>> 0,
          provider >>> 0,
        ),
      release: (token: number) => journal.release(token >>> 0),
    },
    "blot:resource/2": {
      register_owned(
        token: number,
        adapter: number,
        payload: number,
        callable: number,
        provider: number,
        owner: number,
      ) {
        const words = new Uint32Array(memory.buffer);
        const slot = (owner >>> 0) / 4;
        assert.equal(words[slot + 1], 0);
        assert.equal(words[slot - 7], 8);
        journal.registerOwned(
          token >>> 0,
          adapter,
          payload >>> 0,
          callable >>> 0,
          provider >>> 0,
          owner >>> 0,
        );
        words[slot + 1] = token;
        words[slot - 6] |= 2048;
      },
      retire: (token: number) => journal.retire(token >>> 0),
      drain: () => journal.drain(),
    },
  }).exports;
  const memory = raw["blot:memory"] as WebAssembly.Memory;
  const trace: string[] = [];
  const journal = new ResourceJournal(
    Array.from({ length: abi.resourceAdapterCount! }, (_, index) => ({
      cleanup(payload: number, callable: number, provider: number) {
        trace.push("cleanup");
        (raw[`blot:resource_cleanup/${index}`] as CallableFunction)(
          payload,
          callable,
          provider,
        );
      },
      drop(payload: number, callable: number, provider: number) {
        trace.push("drop");
        (raw[`blot:resource_drop/${index}`] as CallableFunction)(
          payload,
          callable,
          provider,
        );
      },
    })),
    (owner, token) => {
      const words = new Uint32Array(memory.buffer);
      assert.equal(words[owner / 4 + 1], token);
      words[owner / 4 + 1] = 0;
    },
  );
  for (let index = 0; index < 16; index++) {
    trace.length = 0;
    (raw["blot:ownership_enter"] as CallableFunction)();
    journal.begin();
    assert.equal((raw.answer as CallableFunction)(0), value);
    journal.finish();
    (raw["blot:ownership_leave"] as CallableFunction)(0);
    (raw["blot:reset"] as CallableFunction)(0);
    assert.deepEqual(trace, ["cleanup", "drop"]);
    for (const name of ["roots", "leases"]) {
      assert.equal(
        Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value),
        0,
      );
    }
  }
}

Deno.test("explicit owning package interfaces preserve resource cleanup through retained checkpoint recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-package-owned-" });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false as const,
        codegenTier,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (const value of [42, 43, 42]) {
          const sources = { [entry]: source(value) };
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert(expected.success, JSON.stringify(expected));
            const actual = await retained.build({ sources });
            assert(actual.success, JSON.stringify(actual));
            assert.deepEqual(actual.bytes, expected.bytes);
            await observe(actual.bytes, value);
            const failed = await retained.build({
              sources: {
                [entry]: source(value).replace(
                  "break operation hidden",
                  "break @u32.add (operation hidden) (operation hidden)",
                ),
              },
            });
            assert(!failed.success, JSON.stringify(failed));
            await observe(actual.bytes, value);
            const recovered = await retained.build({ sources });
            assert(recovered.success, JSON.stringify(recovered));
            assert.deepEqual(recovered.bytes, expected.bytes);
            assert.equal(recovered.stats.nativeWorkSteps, 0);
            const checkpoint = await retained.exportCheckpoint();
            const restarted = await createZigProjectCompiler({
              ...options,
              checkpoint,
            });
            try {
              const replayed = await restarted.build({ sources });
              assert(replayed.success, JSON.stringify(replayed));
              assert.deepEqual(replayed.bytes, expected.bytes);
              await observe(replayed.bytes, value);
            } finally {
              await restarted.dispose();
            }
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("imported owning package operations retain their principal and cleanup in archives", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-package-owned-import-",
  });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/producer.blot`;
  const archive = `${directory}/producer.blotdep`;
  const library = `type Item = exists [a] => (unique a, (unique a) -> U32)
const read: (unique U32) -> U32 = fn hidden => @usage.borrow hidden (fn loan => @usage.read loan)
const make: (unique U32) -> Item = fn owner => pack [U32] (owner, read) as Item
const consume: Item -> U32 = fn item => unpack item as [a] value in do:
  let (hidden, operation) = value
  break operation hidden
`;
  const consumer = `import {make, consume} from "./producer"
entry const answer = fn () => do:
  use owner <- @resource.acquire (fn () => 42) (fn released => ())
  break consume (make owner)
`;
  try {
    const sources = { [entry]: consumer, [producer]: library };
    await Deno.writeTextFile(entry, consumer);
    await Deno.writeTextFile(producer, library);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false as const,
        codegenTier,
      };
      const fresh = await createZigProjectCompiler(options);
      const imported = await createZigProjectCompiler({
        ...options,
        dependencies: archive,
      });
      try {
        const expected = await fresh.build({ sources });
        const actual = await imported.build({ sources });
        assert(expected.success, JSON.stringify(expected));
        assert(actual.success, JSON.stringify(actual));
        assert(actual.stats.cachedModules > 0, JSON.stringify(actual.stats));
        assert.deepEqual(actual.bytes, expected.bytes);
        await observe(actual.bytes, 42);
        const checkpoint = await imported.exportCheckpoint();
        const restarted = await createZigProjectCompiler({
          ...options,
          dependencies: archive,
          checkpoint,
        });
        try {
          const replayed = await restarted.build({ sources });
          assert(replayed.success, JSON.stringify(replayed));
          assert.deepEqual(replayed.bytes, expected.bytes);
          await observe(replayed.bytes, 42);
        } finally {
          await restarted.dispose();
        }
      } finally {
        await fresh.dispose();
        await imported.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
