import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

Deno.test("lexical summary captures preserve snapshots aliases demands and provider identity through retained edits", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const dependencies = `${directory}/library.blotdep`;
  const declarations = `type Box is data = #Box { value: U32 }
type Tick is effect = Unit -> U32
type Other is effect = Unit -> U32
const make: U32 -> (U32 -> U32 ! {}) = func amount => return func value => return @u32.add amount value
const boxes = func left => return func right => return func (value: U32) => return @u32.add value (@u32.add left.value right.value)
const nested = func callback => return func (value: U32) => return callback value
const delayed = func ~(value: U32) => return func () => return @force value
const provided: (Unit -> U32 ! {}) -> (Unit -> U32 ! {}) = func implementation => return do:
  let provider = @effect.provider Tick implementation
  break func () => return do provider:
    use result <- Tick ()
    break result
`;
  const program = (
    amount: number,
    shared: boolean,
    invalid: false | "capture" | "provider" | "body",
  ) =>
    `import * as library from "./library"
const first = library.make ${invalid === "capture" ? "true" : amount}
const other = library.make ${amount + 1}
const box = #library.Box { value: ${amount} }
const pair = library.boxes box ${
      shared ? "box" : `(#library.Box { value: ${amount + 1} })`
    }
const transformed = library.nested (library.make ${amount + 2})
const deferred = library.delayed (@u32.add ${amount} 2)
const provider = library.provided (func () => return ${
      invalid === "provider" ? "library.Other ()" : amount + 3
    })
entry const captured = func (value: U32) => return @u32.add (first value) (other value)
entry const aliases = func (value: U32) => return pair value
entry const callback = func (value: U32) => return transformed ${
      invalid === "body" ? "true" : "value"
    }
entry const demand = func () => return deferred ()
entry const handled = func () => return provider ()
entry const snapshots = func (start: U32) => return do:
  let value = start
  let before = library.make value
  value := @u32.add self 10
  let after = library.make value
  break @u32.add (before 1) (after 1)
entry const folded = captured 5
`;
  const options = { executable, entry, prelude: null };
  try {
    await Deno.writeTextFile(library, declarations);
    await Deno.writeTextFile(entry, program(1, true, false));
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, dependencies, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stdout));
    const producer = await createZigProjectCompiler(options);
    let checkpoint: Uint8Array<ArrayBuffer>;
    let initialBytes: Uint8Array<ArrayBuffer>;
    try {
      const initial = await producer.build();
      assert(initial.success, JSON.stringify(initial));
      initialBytes = initial.bytes;
      checkpoint = await producer.exportCheckpoint();
    } finally {
      await producer.dispose();
    }
    const retained = await createZigProjectCompiler({
      ...options,
      dependencies,
      checkpoint,
    });
    try {
      const restored = await retained.build();
      assert(restored.success, JSON.stringify(restored));
      assert(restored.stats.cachedModules > 0);
      assert.deepEqual(restored.bytes, initialBytes);
      for (
        const [amount, shared, invalid] of [
          [2, true, false],
          [2, false, false],
          [2, false, "capture"],
          [2, true, false],
          [2, true, "provider"],
          [3, false, false],
          [3, false, "body"],
          [1, true, false],
        ] as const
      ) {
        const sources = { [entry]: program(amount, shared, invalid) };
        const actual = await retained.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const expected = await fresh.build({ sources });
          assert.equal(actual.success, expected.success);
          assert.equal(
            actual.success,
            invalid === false,
            JSON.stringify(actual),
          );
          if (actual.success && expected.success) {
            assert.deepEqual(actual.bytes, expected.bytes);
            const guest = await instantiateGuest(actual.bytes);
            try {
              for (const value of [0, 5, 17]) {
                assert.equal(
                  guest.call("captured", value),
                  2 * value + 2 * amount + 1,
                );
                assert.equal(
                  guest.call("aliases", value),
                  value + 2 * amount + (shared ? 0 : 1),
                );
                assert.equal(guest.call("callback", value), value + amount + 2);
                assert.equal(guest.call("snapshots", value), 2 * value + 12);
              }
              for (let repeat = 0; repeat < 3; repeat++) {
                assert.equal(guest.call("demand", null), amount + 2);
                assert.equal(guest.call("handled", null), amount + 3);
              }
              assert.equal(guest.read("folded"), 10 + 2 * amount + 1);
            } finally {
              guest.dispose();
            }
          } else if (!actual.success && !expected.success) {
            assert.deepEqual(actual.diagnostics, expected.diagnostics);
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
