import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun, equal } from "./compile_helpers.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;

function sections(bytes: Uint8Array): Set<number> {
  const result = new Set<number>();
  let at = 8;
  while (at < bytes.length) {
    result.add(bytes[at++]);
    let size = 0, shift = 0, word: number;
    do {
      word = bytes[at++];
      size += (word & 127) * 2 ** shift;
      shift += 7;
    } while (word & 128);
    at += size;
  }
  return result;
}

const forwardedSource = `
const twice = fn ~(value: U32) => @u32.add (@demand value) (@demand value)
const forward = fn ~(value: U32) => twice (@demand value)
const many = fn ~(value: U32) => @u32.add (forward (@demand value)) (twice (@demand value))
const ignore = fn ~(value: U32) => 42
const discard = fn ~(value: U32) => ignore (@demand value)
const choose = fn (skip: Bool) => fn ~(value: U32) => if skip then 9 else @demand value
const guarded = fn (skip: Bool) => fn ~(value: U32) => choose skip (@demand value)
entry const run = fn (value: U32) => many value
entry const skip = fn (value: U32) => discard (@u32.div 1 value)
entry const guard = fn (value: U32) => guarded (@u32.eq value 0) (@u32.div 100 value)
`;

Deno.test("local demand forwarding uses control flow and locals without heap cells", async () => {
  await compileAndRun(forwardedSource, (guest, bytes) => {
    for (const value of [0, 1, 2, 21, 100, 0xFFFFFFFF]) {
      equal(guest.call("run", value), (value * 4) >>> 0);
      equal(guest.call("skip", value), 42);
      equal(
        guest.call("guard", value),
        value === 0 ? 9 : Math.floor(100 / value),
      );
    }
    const emitted = sections(bytes);
    assert.equal(emitted.has(4), false, "forwarding created a function table");
    assert.equal(emitted.has(5), false, "forwarding created demand storage");
  });
});

for (const asynchronous of [false, true]) {
  Deno.test(`forwarded demand effects run once at the first use (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(
      `${forwardedSource}
entry const effectful = fn (host: U32 -> U32 ! {Foreign}) => many (host 21)
entry const ignored = fn (host: U32 -> U32 ! {Foreign}) => discard (host 0)
`,
      async (guest) => {
        const calls: number[] = [];
        const host = asynchronous
          ? guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            call: async (value) => {
              await Promise.resolve();
              calls.push(value);
              return value;
            },
          })
          : guest.capability({
            parameter: "U32",
            result: "U32",
            call: (value) => {
              calls.push(value);
              return value;
            },
          });
        equal(
          asynchronous
            ? await guest.callAsync("ignored", host)
            : guest.call("ignored", host),
          42,
        );
        assert.deepEqual(calls, []);
        for (let iteration = 0; iteration < 5; iteration++) {
          equal(
            asynchronous
              ? await guest.callAsync("effectful", host)
              : guest.call("effectful", host),
            84,
          );
        }
        assert.deepEqual(calls, [21, 21, 21, 21, 21]);
      },
      { asynchronous },
    );
  });
}

Deno.test("indirect demand forwarding retains the shared cell fallback", async () => {
  await compileAndRun(
    `
const twice = fn ~(value: U32) => @u32.add (@demand value) (@demand value)
const forward = fn (next: ~U32 -> U32) => fn ~(value: U32) => next (@demand value)
entry const run = fn (value: U32) => forward twice value
`,
    (guest, bytes) => {
      for (const value of [0, 21, 0xFFFFFFFF]) {
        equal(
          guest.call("run", value),
          (value * 2) >>> 0,
        );
      }
      assert(sections(bytes).has(5));
    },
  );
});

function librarySource(factor: number): string {
  const demand = "(@demand value)";
  const expression = factor === 0
    ? "#True"
    : factor === 2
    ? `@u32.add ${demand} ${demand}`
    : `@u32.add (@u32.add ${demand} ${demand}) ${demand}`;
  return `const twice = fn ~(value: U32) => ${expression}\nconst forward = fn ~(value: U32) => twice (@demand value)\n`;
}

Deno.test("forwarding dependencies follow helper edits through checkpoints and failed revisions", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const dependencies = `${directory}/library.blotdep`;
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: false as const,
  };
  try {
    await Deno.writeTextFile(
      entry,
      'import { forward } from "./library"\nentry const run = fn (value: U32) -> U32 => forward value\n',
    );
    await Deno.writeTextFile(library, librarySource(2));
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, dependencies, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stdout));
    const first = await createZigProjectCompiler(options);
    let checkpoint: Uint8Array<ArrayBuffer>;
    try {
      const initial = await first.build();
      assert(initial.success, JSON.stringify(initial));
      checkpoint = await first.exportCheckpoint();
    } finally {
      await first.dispose();
    }
    const retained = await createZigProjectCompiler({
      ...options,
      dependencies,
      checkpoint,
    });
    try {
      for (const factor of [2, 3, 0, 2]) {
        const sources = { [library]: librarySource(factor) };
        const current = await retained.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const reference = await fresh.build({ sources });
          assert.equal(current.success, factor !== 0, JSON.stringify(current));
          assert.equal(current.success, reference.success);
          if (current.success && reference.success) {
            assert.deepEqual(current.bytes, reference.bytes);
            assert(!sections(current.bytes).has(5));
            const guest = await instantiateGuest(current.bytes);
            try {
              equal(guest.call("run", 21), 21 * factor);
            } finally {
              guest.dispose();
            }
          } else if (!current.success && !reference.success) {
            assert.deepEqual(current.diagnostics, reference.diagnostics);
          }
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await retained.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
