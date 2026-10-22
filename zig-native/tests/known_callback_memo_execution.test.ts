import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun, equal } from "./compile_helpers.ts";

function sections(bytes: Uint8Array): number[] {
  const result: number[] = [];
  let offset = 8;
  while (offset < bytes.length) {
    result.push(bytes[offset++]);
    let length = 0;
    let shift = 0;
    let next: number;
    do {
      next = bytes[offset++];
      length += (next & 127) * 2 ** shift;
      shift += 7;
    } while (next & 128);
    offset += length;
  }
  return result;
}

const repeat = `
const repeat = fn (count: U32) => fn ~(value: U32) => do:
  let read = fn (extra: U32) => @u32.add (@demand value) extra
  let alias = read
  let second = fn (extra: U32) => @u32.add (@demand value) extra
  let total = 0
  for i in 0..count:
    use left <- alias i
    use right <- second i
    total := @u32.add self (@u32.add left right)
  break total
`;

Deno.test("known lexical callbacks share a local memo without heap or table", async () => {
  await compileAndRun(
    `${repeat}
entry const run = fn (count: U32) => repeat count 21
entry const skipped = fn (divisor: U32) => repeat 0 (@u32.div 1 divisor)
`,
    (guest, bytes) => {
      for (const count of [0, 1, 3, 1000]) {
        equal(guest.call("run", count), 42 * count + count * (count - 1));
      }
      equal(guest.call("skipped", 0), 0);
      const module = new WebAssembly.Module(bytes);
      assert.deepEqual(WebAssembly.Module.imports(module), []);
      assert(!sections(bytes).includes(4));
      assert(!sections(bytes).includes(5));
      assert.equal(
        WebAssembly.Module.exports(module).some((item) =>
          item.kind === "memory" || item.kind === "table"
        ),
        false,
      );
    },
    { prelude: "none" },
  );
});

for (const asynchronous of [false, true]) {
  let mode = "sync";
  if (asynchronous) mode = "JSPI";
  Deno.test(`known lexical callback memos preserve first force effects (${mode})`, async () => {
    await compileAndRun(
      `${repeat}
entry const skipped = fn (host: U32 -> U32 ! {Foreign}) => repeat 0 (host 21)
entry const run = fn (host: U32 -> U32 ! {Foreign}) => repeat 3 (host 21)
`,
      async (guest) => {
        const trace: number[] = [];
        const call = (value: number) => {
          trace.push(value);
          return value;
        };
        let host;
        if (asynchronous) {
          host = guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            call: async (value) => {
              await Promise.resolve();
              return call(value);
            },
          });
        } else {
          host = guest.capability({ parameter: "U32", result: "U32", call });
        }
        const invoke = async (name: string) => {
          if (asynchronous) return await guest.callAsync(name, host);
          return guest.call(name, host);
        };
        equal(await invoke("skipped"), 0);
        assert.deepEqual(trace, []);
        equal(await invoke("run"), 132);
        assert.deepEqual(trace, [21]);
        equal(await invoke("run"), 132);
        assert.deepEqual(trace, [21, 21]);
      },
      { prelude: "none", asynchronous },
    );
  });
}

Deno.test("local callback specialization preserves polymorphism and immutable captures", async () => {
  await compileAndRun(
    `
const read = fn ~(value: U32) => do:
  let identity = fn item => item
  let offset = 2
  let first = fn item => @u32.add (@demand value) (identity item)
  let saved = fn () => @u32.add (@demand value) offset
  offset := 7
  let second = fn () => @u32.add (@demand value) offset
  use a <- first 1
  use b <- saved ()
  use c <- second ()
  break @u32.add a (@u32.add b c)
entry const run = fn (value: U32) => read value
`,
    (guest, bytes) => {
      equal(guest.call("run", 10), 40);
      equal(guest.call("run", 1), 13);
      assert(!sections(bytes).includes(4));
      assert(!sections(bytes).includes(5));
      assert.equal(
        WebAssembly.Module.exports(new WebAssembly.Module(bytes)).some((item) =>
          item.kind === "memory" || item.kind === "table"
        ),
        false,
      );
    },
    { prelude: "none" },
  );
});

Deno.test("captured Array demands survive callback loops and real retirement", async () => {
  await compileAndRun(
    `
const repeat = fn (count: U32) => fn ~(value: Array U32) => do:
  let snapshot = #[17, 18]
  let read = fn (index: U32) => @u32.add (@array.get (@demand value) index) snapshot[0]
  let alias = read
  let second = fn (index: U32) => @array.get (@demand value) index
  let total = 0
  for i in 0..count:
    let pressure = @array.fill 1024 i
    let churn = @array.fill (@u32.add (@u32.rem i 2) 2) i
    use a <- alias (@u32.rem i 3)
    use b <- second (@u32.rem i 3)
    total := @u32.add self (@u32.add (@u32.add a b) (@u32.add pressure[0] churn[0]))
  break total
entry const run = fn (count: U32) => repeat count #[21, 22, 23]
`,
    (guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      const raw = new WebAssembly.Instance(module).exports;
      const counter = (name: string) =>
        Number((raw["blot:rc_" + name] as WebAssembly.Global).value);
      for (const count of [0, 1, 5000, 5000]) {
        let expected = 0;
        for (let i = 0; i < count; i++) expected += 59 + 2 * (i % 3) + 2 * i;
        const before = counter("destroyed");
        equal((raw.run as CallableFunction)(count), expected);
        equal(counter("roots"), 0);
        equal(counter("leases"), 0);
        assert(counter("destroyed") - before >= 2 * count);
        equal(guest.call("run", count), expected);
      }
    },
    { prelude: "none" },
  );
});

Deno.test("returned and stored callbacks retain one shared fallback cell", async () => {
  await compileAndRun(
    `
const keep = fn ~(value: U32) => { first: fn () => @demand value, second: fn () => @demand value }
entry const run = fn (host: U32 -> U32 ! {Foreign}) => do:
  let callbacks = keep (host 21)
  use first <- callbacks.first ()
  use second <- callbacks.second ()
  break @u32.add first second
`,
    (guest, bytes) => {
      assert(sections(bytes).includes(5));
      let calls = 0;
      const host = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value) => {
          calls++;
          return value;
        },
      });
      for (let i = 1; i <= 32; i++) {
        equal(guest.call("run", host), 42);
        equal(calls, i);
      }
    },
    { prelude: "none" },
  );
});

Deno.test("local callback imports, stable-type edits and checkpoints match fresh output", async () => {
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  const directory = await Deno.makeTempDir();
  const entry = directory + "/main.blot";
  const library = directory + "/library.blot";
  const dependencies = directory + "/library.blotdep";
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: false as const,
  };
  try {
    await Deno.writeTextFile(
      entry,
      'import { repeat } from "./library"\nentry const run = fn (count: U32) => repeat count 21\n',
    );
    await Deno.writeTextFile(library, repeat);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, dependencies, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stdout));
    const retained = await createZigProjectCompiler(options);
    try {
      for (const edited of [false, true, false]) {
        let body = repeat;
        if (edited) {
          body = body.replace(
            "@u32.add (@demand value) extra",
            "@u32.add (@demand value) (@u32.add extra 1)",
          );
        }
        const sources = { [library]: body };
        const current = await retained.build({ sources });
        assert(current.success, JSON.stringify(current));
        const checkpoint = await retained.exportCheckpoint();
        for (
          const imported of [{}, { checkpoint }, { dependencies, checkpoint }]
        ) {
          const fresh = await createZigProjectCompiler({
            ...options,
            ...imported,
          });
          try {
            const result = await fresh.build({ sources });
            assert(result.success, JSON.stringify(result));
            assert.deepEqual(result.bytes, current.bytes);
            const guest = await instantiateGuest(result.bytes);
            try {
              for (const count of [0, 1, 7]) {
                let expected = 42 * count + count * (count - 1);
                if (edited) expected += count;
                equal(guest.call("run", count), expected);
              }
            } finally {
              guest.dispose();
            }
          } finally {
            await fresh.dispose();
          }
        }
        const failed = await retained.build({
          sources: { [library]: body.replace("@demand value", "@demand 42") },
        });
        assert.equal(failed.success, false);
      }
    } finally {
      await retained.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("known callbacks can call bounded ordinary helpers without demand cells", async () => {
  await compileAndRun(
    `
const add = fn (value: U32) => @u32.add value 1
const read = fn ~(value: U32) => do:
  let callback = fn () => add (@demand value)
  use first <- callback ()
  use second <- callback ()
  break @u32.add first second
entry const run = fn (value: U32) => read value
`,
    (guest, bytes) => {
      equal(guest.call("run", 20), 42);
      assert(!sections(bytes).includes(4));
      assert(!sections(bytes).includes(5));
    },
    { prelude: "none" },
  );
});

Deno.test("generic callback captures preserve scalar machine types", async () => {
  await compileAndRun(
    `
const read = fn ~value => do:
  let identity = fn item => item
  let callback = fn () => identity (@demand value)
  use first <- callback ()
  use callback ()
  break first
entry const integer = fn (value: U32) => read value
entry const floating = fn (value: F32) => read value
`,
    (guest, bytes) => {
      for (const value of [0, 21, 0xffffffff]) {
        equal(
          guest.call("integer", value),
          value,
        );
      }
      for (const value of [0, 1.5, -21.5]) {
        equal(
          guest.call("floating", value),
          value,
        );
      }
      assert(!sections(bytes).includes(4));
      assert(!sections(bytes).includes(5));
    },
    { prelude: "none" },
  );
});
