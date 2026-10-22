import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const reader = `import {value} from "./changed"
const identity: forall [a] => a -> a = fn item => item
const consume = fn (item: unique U32) => @usage.borrow item (fn loan => @usage.read loan)
const checked = fn (item: U32) => do:
  let witness = @proof.lt 0 item
  break item
const read: Unit -> U32 = fn () => identity value
`;
Deno.test("shared dependency validation owns actual foreign rank usage and proof inputs across archives edits rollback and restart", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-dependency-owners-",
  });
  const entry = `${directory}/main.blot`;
  const left = `${directory}/left.blot`;
  const changed = `${directory}/changed.blot`;
  const right = `${directory}/right.blot`;
  const dependencies = `${directory}/deps.blotdep`;
  const main = (seed = "2") =>
    `import {read} from "./left"
import {fixed} from "./right"
entry const answer = fn () => @u32.add (read ()) fixed
entry const sibling = ${seed}
`;
  const sources = (seed = "2", value = "41", fixed = "1") => ({
    [entry]: main(seed),
    [left]: reader,
    [changed]: `const value: U32 = ${value}\n`,
    [right]: `const fixed: U32 = ${fixed}\n`,
  });
  async function run(bytes: Uint8Array<ArrayBuffer>, answer: number) {
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        if (asynchronous) {
          assert.equal(await guest.callAsync("answer", null), answer);
        } else assert.equal(guest.call("answer", null), answer);
      } finally {
        guest.dispose();
      }
    }
  }
  try {
    for (const [path, text] of Object.entries(sources())) {
      await Deno.writeTextFile(path, text);
    }
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, dependencies, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      } as const;
      const retained = await createZigProjectCompiler(options);
      const archived = await createZigProjectCompiler({
        ...options,
        dependencies,
      });
      let checkpoint: Uint8Array<ArrayBuffer> | undefined;
      let finalBytes: Uint8Array<ArrayBuffer> | undefined;
      try {
        const first = await retained.build();
        const frozen = await archived.build();
        assert.ok(first.success, JSON.stringify(first));
        assert.ok(frozen.success, JSON.stringify(frozen));
        assert.deepEqual(frozen.bytes, first.bytes);
        for (const compiler of [retained, archived]) {
          const actual = await compiler.build({
            sources: sources("3", "41", "2"),
          });
          assert.ok(actual.success, JSON.stringify(actual));
          const storage = (actual.stats.attemptStats.fallback as {
            dependency_storage: { core_reused: number; core_checked: number };
          }).dependency_storage;
          assert.equal(storage.core_reused, 2, JSON.stringify(storage));
          assert.equal(storage.core_checked, 1, JSON.stringify(storage));
          await run(actual.bytes, 43);
        }
        const revisions = [
          ["4", "43", "2"],
          ["missing", "43", "2"],
          ["4", "missing", "2"],
          ["5", "43", "2"],
          ["2", "41", "1"],
          ["3", "41", "1"],
        ] as const;
        for (const compiler of [retained, archived]) {
          checkpoint = await compiler.exportCheckpoint();
          for (const [seed, value, fixed] of revisions) {
            const fresh = await createZigProjectCompiler(options);
            try {
              const revision = sources(seed, value, fixed);
              const expected = await fresh.build({ sources: revision });
              const actual = await compiler.build({ sources: revision });
              assert.equal(actual.success, expected.success);
              if (!actual.success || !expected.success) {
                assert.ok(!actual.success && !expected.success);
                assert.ok(seed === "missing" || value === "missing");
                assert.deepEqual(actual.diagnostics, expected.diagnostics);
                assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
                continue;
              }
              assert.deepEqual(actual.bytes, expected.bytes);
              assert.equal(
                actual.stats.nativeWorkSteps,
                expected.stats.nativeWorkSteps,
              );
              if (seed === "4") {
                const storage = (actual.stats.attemptStats.fallback as {
                  dependency_storage: { core_reused: number };
                }).dependency_storage;
                assert.equal(storage.core_reused, 1, JSON.stringify(storage));
              }
              await run(actual.bytes, Number(value) + Number(fixed));
              checkpoint = await compiler.exportCheckpoint();
              finalBytes = actual.bytes;
            } finally {
              await fresh.dispose();
            }
          }
        }
      } finally {
        await retained.dispose();
        await archived.dispose();
      }
      assert.ok(checkpoint && finalBytes);
      const restarted = await createZigProjectCompiler({
        ...options,
        checkpoint,
      });
      try {
        const actual = await restarted.build({ sources: sources("3") });
        assert.ok(actual.success, JSON.stringify(actual));
        assert.deepEqual(actual.bytes, finalBytes);
        await run(actual.bytes, 42);
      } finally {
        await restarted.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
