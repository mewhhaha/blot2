import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `effect Read: Unit -> U32
const plain: code [U32, row {}] = @code.quote 42
const inner: code [U32, row {Read}] = @code.quote (Read ())
const generated = @code.quote (do:
  use first <- @code.splice inner
  break @u32.add first 2)
`;
const source = `import {Read, plain, generated} from "./producer"
entry const answer = fn (host: U32 -> U32 ! {Foreign}) => do:
  use ignored <- host 0
  let provider = @effect.provider Read (fn () => host 40)
  break do provider:
    break @code.emit generated
entry const pure = fn (host: U32 -> U32 ! {Foreign}) => do:
  use ignored <- host 0
  break @code.emit plain
entry const checked: U32 = @code.run plain
entry const snapshot = fn (value: U32) => #[value]
`;

function hostFailure(error: unknown): boolean {
  assert(error instanceof Error);
  assert(error.cause instanceof Error);
  assert.equal(error.cause.message, "host failure");
  return true;
}

async function observe(bytes: Uint8Array<ArrayBuffer>) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    const trace: number[] = [];
    const host = (value: unknown) => {
      assert.equal(typeof value, "number");
      trace.push(value as number);
      return Number(value);
    };
    let callback;
    let fault;
    if (asynchronous) {
      callback = guest.capabilityAsync({
        parameter: "U32",
        result: "U32",
        call: async (value) => {
          await Promise.resolve();
          return host(value);
        },
      });
      fault = guest.capabilityAsync({
        parameter: "U32",
        result: "U32",
        call: async () => {
          await Promise.resolve();
          throw new Error("host failure");
        },
      });
    } else {
      callback = guest.capability({
        parameter: "U32",
        result: "U32",
        call: host,
      });
      fault = guest.capability({
        parameter: "U32",
        result: "U32",
        call: () => {
          throw new Error("host failure");
        },
      });
    }
    const call = async (name: string) => {
      if (asynchronous) return await guest.callAsync(name, callback);
      return guest.call(name, callback);
    };
    try {
      assert.equal(guest.read("checked"), 42);
      for (let index = 0; index < 16; index++) {
        assert.equal(await call("answer"), 42);
        assert.equal(await call("pure"), 42);
      }
      assert.deepEqual(
        trace,
        Array.from({ length: 16 }, () => [0, 40, 0]).flat(),
      );
      const warmed = guest.memoryBytes();
      if (asynchronous) {
        await assert.rejects(
          () => guest.callAsync("answer", fault),
          hostFailure,
        );
      } else {
        assert.throws(() => guest.call("answer", fault), hostFailure);
      }
      assert.equal(await call("answer"), 42);
      assert.equal(guest.memoryBytes(), warmed);
    } finally {
      guest.dispose();
    }
  }
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`typed code adds effects to larger ambients with exact portable rows (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-staging-ambient-",
    });
    const entry = `${directory}/main.blot`;
    const producer = `${directory}/producer.blot`;
    const dependencies = `${directory}/producer.blotdep`;
    const options = {
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false as const,
    };
    try {
      await Deno.writeTextFile(entry, source);
      await Deno.writeTextFile(producer, library);
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, dependencies, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(packed.success, new TextDecoder().decode(packed.stderr));
      const fresh = await createZigProjectCompiler(options);
      const archived = await createZigProjectCompiler({
        ...options,
        dependencies,
      });
      let checkpoint: Uint8Array<ArrayBuffer>;
      let expected: Uint8Array<ArrayBuffer>;
      try {
        const initial = await fresh.build();
        const imported = await archived.build();
        assert(initial.success, JSON.stringify(initial));
        assert(imported.success, JSON.stringify(imported));
        assert(imported.stats.cachedModules > 0);
        assert.deepEqual(imported.bytes, initial.bytes);
        expected = initial.bytes;
        await observe(expected);
        checkpoint = await archived.exportCheckpoint();
        const invalid = await archived.build({
          sources: {
            [entry]: source.replace("@code.run plain", "@code.run generated"),
          },
        });
        assert(!invalid.success);
        assert(
          invalid.diagnostics.some((issue) => issue.code === "const_effect"),
        );
        assert.deepEqual(await archived.exportCheckpoint(), checkpoint);
        const repaired = await archived.build({ sources: { [entry]: source } });
        assert(repaired.success, JSON.stringify(repaired));
        assert.deepEqual(repaired.bytes, expected);
      } finally {
        await fresh.dispose();
        await archived.dispose();
      }
      const restored = await createZigProjectCompiler({
        ...options,
        dependencies,
        checkpoint: checkpoint!,
      });
      try {
        const replayed = await restored.build();
        assert(replayed.success, JSON.stringify(replayed));
        assert.deepEqual(replayed.bytes, expected!);
        await observe(replayed.bytes);
      } finally {
        await restored.dispose();
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
