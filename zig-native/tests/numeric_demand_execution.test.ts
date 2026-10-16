import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library =
  `const both = fn (left: Bool) => fn ~(right: Bool) => if left then @demand right else #False
const either = fn (left: Bool) => fn ~(right: Bool) => if left then #True else @demand right
const below = fn left => fn right => do:
  let copied = left
  let compared = @u32.lt copied right
  return compared
const within = fn index => fn values => below index (@array.length values)
`;
const source = `import {both, either, within} from "./logic"
entry const answer = fn (index: U32) => do:
  let values = #[8, 13]
  if both (within index values) (@u32.eq index 0):
    return @array.get values index
  return 0
entry const complement = fn (index: U32) => do:
  let values = #[8, 13]
  if either (@u32.lt (@array.length values) index) (@u32.eq index (@array.length values)):
    return 0
  return @array.get values index
entry const skipped = fn () => both #False (@panic "unforced right")
entry const ordered = fn (index: U32) => both (@u32.lt index 2) (@panic "forced right")
entry const direct = fn (index: U32) => do:
  let values = #[8, 13]
  if within index values:
    return @array.get values index
  return 0
`;

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`selected demand proofs preserve traps imports edits and restart (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-demand-proof-" });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/logic.blot`;
    const archive = `${directory}/logic.blotdep`;
    const sources = { [entry]: source, [dependency]: library };
    const options = {
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: `${directory}/cache`,
    };
    const compiler = await createZigProjectCompiler(options);
    const observe = async (bytes: Uint8Array<ArrayBuffer>, changed = false) => {
      const guest = await instantiateGuest(bytes);
      try {
        assert.equal(guest.call("answer", 0), 8);
        assert.equal(guest.call("complement", 1), 13);
        assert.equal(guest.call("complement", 2), 0);
        assert.equal(guest.call("complement", 4294967295), 0);
        assert.equal(guest.call("direct", 0), 8);
        assert.equal(guest.call("direct", 1), 13);
        assert.equal(guest.call("direct", 2), 0);
        assert.equal(guest.call("direct", 4294967295), 0);
        if (changed) {
          assert.equal(guest.call("answer", 1), 13);
          assert.throws(
            () => guest.call("answer", 2),
            WebAssembly.RuntimeError,
          );
          assert.throws(
            () => guest.call("answer", 4294967295),
            WebAssembly.RuntimeError,
          );
        } else {
          assert.equal(guest.call("answer", 1), 0);
          assert.equal(guest.call("answer", 2), 0);
          assert.equal(guest.call("answer", 4294967295), 0);
          assert.equal(guest.call("skipped", null), false);
          assert.equal(guest.call("ordered", 2), false);
          assert.throws(
            () => guest.call("ordered", 0),
            WebAssembly.RuntimeError,
          );
        }
      } finally {
        guest.dispose();
      }
    };
    try {
      await Deno.writeTextFile(entry, source);
      await Deno.writeTextFile(dependency, library);
      const first = await compiler.build({ sources });
      assert(first.success, JSON.stringify(first));
      await observe(first.bytes);
      const altered = {
        ...sources,
        [dependency]: library.replace(
          "if left then @demand right else #False",
          "#True",
        ),
      };
      const changed = await compiler.build({ sources: altered });
      assert(changed.success, JSON.stringify(changed));
      await observe(changed.bytes, true);
      const fresh = await createZigProjectCompiler({
        ...options,
        cacheDirectory: false,
      });
      try {
        const independent = await fresh.build({ sources: altered });
        assert(independent.success, JSON.stringify(independent));
        assert.deepEqual(changed.bytes, independent.bytes);
      } finally {
        await fresh.dispose();
      }
      const wrappedSources = {
        ...sources,
        [dependency]: library.replace(
          "let copied = left",
          "let copied = @u32.add left 1",
        ),
      };
      const wrapped = await compiler.build({ sources: wrappedSources });
      assert(wrapped.success, JSON.stringify(wrapped));
      const wrappedGuest = await instantiateGuest(wrapped.bytes);
      try {
        assert.equal(wrappedGuest.call("direct", 0), 8);
        assert.equal(wrappedGuest.call("direct", 1), 0);
        assert.throws(
          () => wrappedGuest.call("direct", 4294967295),
          WebAssembly.RuntimeError,
        );
      } finally {
        wrappedGuest.dispose();
      }
      const freshWrapped = await createZigProjectCompiler({
        ...options,
        cacheDirectory: false,
      });
      try {
        const independent = await freshWrapped.build({
          sources: wrappedSources,
        });
        assert(independent.success, JSON.stringify(independent));
        assert.deepEqual(wrapped.bytes, independent.bytes);
      } finally {
        await freshWrapped.dispose();
      }
      const failed = await compiler.build({
        sources: {
          ...sources,
          [dependency]: library.replace("@demand right", "unknown"),
        },
      });
      assert(!failed.success);
      const recovered = await compiler.build({ sources });
      assert(recovered.success, JSON.stringify(recovered));
      assert.deepEqual(recovered.bytes, first.bytes);
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, archive, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(
        packed.success,
        new TextDecoder().decode(packed.stderr) +
          new TextDecoder().decode(packed.stdout),
      );
      for (const dependencies of [undefined, archive]) {
        const restarted = await createZigProjectCompiler({
          ...options,
          dependencies,
        });
        try {
          const result = await restarted.build({ sources });
          assert(result.success, JSON.stringify(result));
          assert.deepEqual(result.bytes, first.bytes);
          await observe(result.bytes);
        } finally {
          await restarted.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
