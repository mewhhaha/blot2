import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
type Storage = "u32" | "f32" | "reference" | "record" | "renamed_record";
const producer = (storage: Storage, parameter = "value") => {
  const representation = {
    u32: "U32",
    f32: "F32",
    reference: "Array U32",
    record: "{word: U32}",
    renamed_record: "{renamed: U32}",
  }[storage];
  const value = `@u32.add ${parameter} offset`;
  const payload = storage === "f32"
    ? `@u32.to_f32 (${value})`
    : storage === "reference"
    ? `#[${value}]`
    : storage === "record"
    ? `{word: ${value}}`
    : storage === "renamed_record"
    ? `{renamed: ${value}}`
    : `(${value})`;
  const observed = storage === "f32"
    ? "@f32.to_u32 value"
    : storage === "reference"
    ? "value[0]"
    : storage === "record"
    ? "value.word"
    : storage === "renamed_record"
    ? "value.renamed"
    : "value";
  return `opaque type Token = ${representation}
private const offset = 2
const make: U32 -> Token = fn ${parameter} => #Token (${payload})
const read: Token -> U32 = fn (#Token value) => ${observed}
`;
};
// Runtime selection keeps the opaque argument/result inside real closure calls.
// Guest exports themselves retain the language's scalar ABI.
const bridge = `import {make, read} from "./tokens"
const factories = #[make, fn value => make value]
const readers = #[read, fn value => read value]
const transform = fn (value: U32) => (readers[@u32.rem value 2]) ((factories[@u32.rem value 2]) value)
`;
const main = `import {transform} from "./bridge"
entry const answer = fn (value: U32) => transform value
`;
const carrier = `opaque type Envelope = Token
const pack = fn value => #Envelope (make value)
const unpack = fn (#Envelope value) => read value
const factories = #[pack, fn value => pack value]
const readers = #[unpack, fn value => unpack value]
const carry = fn (value: U32) => (readers[@u32.rem value 2]) ((factories[@u32.rem value 2]) value)
`;

// Scalar guest APIs need not expose private heap memory. Add only a telemetry
// export for raw observations; fresh/retained parity and Guest use original bytes.
function observeMemory(bytes: Uint8Array<ArrayBuffer>) {
  const name = new TextEncoder().encode("qual:storage_memory");
  const leb = (value: number) => {
    const result = [];
    do {
      const next = value & 127;
      value >>>= 7;
      result.push(next | (value ? 128 : 0));
    } while (value);
    return result;
  };
  let cursor = 8, hasMemory = false;
  const read = () => {
    let value = 0, shift = 0, byte: number;
    do {
      assert(cursor < bytes.length && shift < 35);
      byte = bytes[cursor++];
      value += (byte & 127) * 2 ** shift;
      shift += 7;
    } while (byte & 128);
    return value;
  };
  const parts: Uint8Array<ArrayBuffer>[] = [bytes.slice(0, 8)];
  while (cursor < bytes.length) {
    const start = cursor, section = bytes[cursor++], length = read();
    const end = cursor + length;
    assert(end <= bytes.length);
    if (section === 5) hasMemory = read() !== 0;
    if (section === 7 && hasMemory) {
      const count = read();
      const payload = Uint8Array.from([
        ...leb(count + 1),
        ...bytes.slice(cursor, end),
        ...leb(name.length),
        ...name,
        2,
        0,
      ]);
      parts.push(Uint8Array.from([7, ...leb(payload.length)]), payload);
    } else parts.push(bytes.slice(start, end));
    cursor = end;
  }
  const observed = new Uint8Array(
    parts.reduce((sum, part) => sum + part.length, 0),
  );
  let offset = 0;
  for (const part of parts) {
    observed.set(part, offset);
    offset += part.length;
  }
  assert(WebAssembly.validate(observed));
  return observed;
}

async function observe(bytes: Uint8Array<ArrayBuffer>, reference: boolean) {
  const module = new WebAssembly.Module(bytes);
  const original = new WebAssembly.Instance(module).exports;
  assert.equal((original.answer as CallableFunction)(40), 42);
  const raw =
    new WebAssembly.Instance(new WebAssembly.Module(observeMemory(bytes)))
      .exports;
  const enter = raw["blot:ownership_enter"] as (() => void) | undefined;
  const leave = raw["blot:ownership_leave"] as
    | ((n: number) => void)
    | undefined;
  if (reference) {
    assert.equal(typeof enter, "function");
    assert.equal(typeof leave, "function");
  }
  const call = (value: number) => {
    enter?.();
    try {
      assert.equal((raw.answer as CallableFunction)(value), value + 2);
    } finally {
      leave?.(0);
    }
  };
  call(40);
  const memory = raw["qual:storage_memory"];
  if (reference) assert(memory instanceof WebAssembly.Memory);
  const privateWarm = memory instanceof WebAssembly.Memory
    ? memory.buffer.byteLength
    : 0;
  if (reference) assert(privateWarm > 0);
  for (let index = 0; index < 1000; index++) call(40 + index % 2);
  assert.equal(
    memory instanceof WebAssembly.Memory ? memory.buffer.byteLength : 0,
    privateWarm,
  );
  for (const name of ["blot:rc_roots", "blot:rc_leases"]) {
    const counter = raw[name];
    if (reference) assert(counter instanceof WebAssembly.Global);
    if (counter instanceof WebAssembly.Global) assert.equal(counter.value, 0);
  }
  const guest = await instantiateGuest(module);
  try {
    for (const value of [0, 1, 40, 41, 0x00fffffd]) {
      assert.equal(guest.call("answer", value), value + 2);
    }
    const warm = guest.memoryBytes();
    for (let call = 0; call < 1000; call++) {
      const value = 40 + call % 2;
      assert.equal(guest.call("answer", value), value + 2);
    }
    assert.equal(guest.memoryBytes(), warm);
  } finally {
    guest.dispose();
  }
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`opaque ABI changes reuse semantic callers and rebuild executable readers (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-opaque-storage-",
    });
    const entry = `${directory}/main.blot`, tokens = `${directory}/tokens.blot`;
    const bundle = `${directory}/dependencies.blotdep`;
    try {
      await Deno.writeTextFile(entry, main);
      await Deno.writeTextFile(`${directory}/bridge.blot`, bridge);
      await Deno.writeTextFile(tokens, producer("u32"));
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, bundle, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(
        packed.success,
        new TextDecoder().decode(packed.stdout) +
          new TextDecoder().decode(packed.stderr),
      );
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false as const,
        codegenTier,
      };
      for (const dependencies of [undefined, bundle]) {
        const retained = await createZigProjectCompiler({
          ...options,
          dependencies,
        });
        try {
          for (
            const [index, storage] of ([
              "u32",
              "f32",
              "reference",
              "record",
              "renamed_record",
              "alpha",
              "u32",
            ] as const).entries()
          ) {
            const text = storage === "alpha"
              ? producer("u32", "argument")
              : producer(storage);
            const sources = { [tokens]: text };
            const built = await retained.build({ sources });
            assert(built.success, JSON.stringify(built));
            if (index > 0) {
              const work = built.stats.attemptStats.fallback as {
                module_cutoff: { reused: number };
                entry_cutoff: { reused: number };
              };
              assert.equal(work.module_cutoff.reused, 1);
              assert.equal(work.entry_cutoff.reused, 1);
            }
            const fresh = await createZigProjectCompiler(options);
            try {
              const control = await fresh.build({ sources });
              assert(control.success, JSON.stringify(control));
              assert.deepEqual(built.bytes, control.bytes);
            } finally {
              await fresh.dispose();
            }
            const reference = storage === "reference" || storage === "record" ||
              storage === "renamed_record";
            await observe(built.bytes, reference);
            const checkpoint = await retained.exportCheckpoint();
            const failed = await retained.build({
              sources: {
                [tokens]: text.replace("make: U32", "make: Bool"),
              },
            });
            assert(!failed.success);
            assert.deepEqual(await retained.exportCheckpoint(), checkpoint);
            const corrected = await retained.build({ sources });
            assert(corrected.success, JSON.stringify(corrected));
            assert.deepEqual(corrected.bytes, built.bytes);
            const restarted = await createZigProjectCompiler({
              ...options,
              checkpoint,
            });
            try {
              const restored = await restarted.build({ sources });
              assert(restored.success, JSON.stringify(restored));
              assert.deepEqual(restored.bytes, built.bytes);
              await observe(restored.bytes, reference);
            } finally {
              await restarted.dispose();
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

  Deno.test(`derived opaque storage refreshes producers and retains unrelated semantic callers (${codegenTier})`, async () => {
    for (
      const scenario of [
        "module",
        "entry",
        "unrelated",
        "unrelated_entry",
      ] as const
    ) {
      const directory = await Deno.makeTempDir({
        prefix: "blot-derived-storage-",
      });
      const entry = `${directory}/main.blot`,
        tokens = `${directory}/tokens.blot`;
      const bundle = `${directory}/dependencies.blotdep`;
      try {
        const bridgeSource = scenario === "module"
          ? `import {Token, make, read} from "./tokens"\n${carrier}const transform = carry\n`
          : bridge +
            (scenario === "unrelated" ? "opaque type Unrelated = U32\n" : "");
        const entrySource = scenario === "entry"
          ? `import {transform} from "./bridge"\nimport {Token, make, read} from "./tokens"\n${carrier}entry const answer = carry\n`
          : main +
            (scenario === "unrelated_entry"
              ? "opaque type Unrelated = U32\nopaque type Nested = Unrelated\n"
              : "");
        await Deno.writeTextFile(entry, entrySource);
        await Deno.writeTextFile(`${directory}/bridge.blot`, bridgeSource);
        await Deno.writeTextFile(tokens, producer("u32"));
        const packed = await new Deno.Command(executable, {
          args: ["dependencies", entry, bundle, "--prelude", "none"],
          stdout: "piped",
          stderr: "piped",
        }).output();
        assert(
          packed.success,
          new TextDecoder().decode(packed.stdout) +
            new TextDecoder().decode(packed.stderr),
        );
        const options = {
          executable,
          entry,
          prelude: null,
          cacheDirectory: false as const,
          codegenTier,
        };
        for (const dependencies of [undefined, bundle]) {
          const retained = await createZigProjectCompiler({
            ...options,
            dependencies,
          });
          try {
            for (
              const [index, storage]
                of (["u32", "f32", "reference", "record", "u32"] as const)
                  .entries()
            ) {
              const text = producer(storage), sources = { [tokens]: text };
              const built = await retained.build({ sources });
              assert(built.success, JSON.stringify(built));
              if (index > 0) {
                const physicalChange = index !== 3;
                const work = built.stats.attemptStats.fallback as {
                  module_cutoff: { reused: number; storage_rechecks: number };
                  entry_cutoff: { reused: number; storage_rechecks: number };
                };
                const moduleRefresh = scenario === "module" && physicalChange;
                const entryRefresh = scenario === "entry" && physicalChange;
                assert.equal(work.module_cutoff.reused, moduleRefresh ? 0 : 1);
                assert.equal(work.entry_cutoff.reused, entryRefresh ? 0 : 1);
                assert.equal(
                  work.module_cutoff.storage_rechecks,
                  moduleRefresh ? 1 : 0,
                );
                assert.equal(
                  work.entry_cutoff.storage_rechecks,
                  entryRefresh ? 1 : 0,
                );
              }
              const fresh = await createZigProjectCompiler(options);
              try {
                const control = await fresh.build({ sources });
                assert(control.success, JSON.stringify(control));
                assert.deepEqual(built.bytes, control.bytes);
              } finally {
                await fresh.dispose();
              }
              await observe(
                built.bytes,
                storage === "reference" || storage === "record",
              );
              const checkpoint = await retained.exportCheckpoint();
              const failed = await retained.build({
                sources: { [tokens]: text.replace("make: U32", "make: Bool") },
              });
              assert(!failed.success);
              assert.deepEqual(await retained.exportCheckpoint(), checkpoint);
              const corrected = await retained.build({ sources });
              assert(corrected.success, JSON.stringify(corrected));
              assert.deepEqual(corrected.bytes, built.bytes);
              const restarted = await createZigProjectCompiler({
                ...options,
                checkpoint,
              });
              try {
                const restored = await restarted.build({ sources });
                assert(restored.success, JSON.stringify(restored));
                assert.deepEqual(restored.bytes, built.bytes);
                await observe(
                  restored.bytes,
                  storage === "reference" || storage === "record",
                );
              } finally {
                await restarted.dispose();
              }
            }
          } finally {
            await retained.dispose();
          }
        }
      } finally {
        await Deno.remove(directory, { recursive: true });
      }
    }
  });
}
