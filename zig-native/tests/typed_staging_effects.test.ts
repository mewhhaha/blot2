import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

for (const declared of ["observed", "superset", "unused"] as const) {
  Deno.test(`imported quoted named operations retain effects through edits and restart (${declared})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-staging-effects-",
    });
    const entry = `${directory}/main.blot`;
    const producer = `${directory}/producer.blot`;
    const operations = `${directory}/operations.blot`;
    const archive = `${directory}/producer.blotdep`;
    const executable = Deno.args[0] ??
      new URL("../zig-out-dev/bin/blotc", import.meta.url).pathname;
    let source = `import {generated} from "./producer"
import {Read, Write} from "./operations"
const provider = @effect.provider Read (fn () => 40)
const write = @effect.provider Write (fn () => ())
entry const answer = fn () => do provider:
  use first <- @code.emit generated
  use second <- @code.emit generated
  return @u32.add first second
`;
    if (declared === "superset") {
      source = source.replace(
        "  use first <-",
        "  return do write:\n    use first <-",
      ).replace("  use second <-", "    use second <-").replace(
        "  return @u32.add",
        "    return @u32.add",
      );
    }
    let operationSource = `effect Read: Unit -> U32
effect Write: Unit -> Unit
const identity = fn value => value
const invoke = fn () => identity (Read ())
`;
    let observed = 40;
    if (declared === "superset") {
      operationSource = operationSource.replace(
        "const invoke =",
        "const invoke: Unit -> U32 ! {Read, Write} =",
      );
    }
    if (declared === "unused") {
      operationSource = operationSource.replace(
        "const invoke = fn () => identity (Read ())",
        "const invoke: Unit -> U32 ! {Read} = fn () => 42",
      );
      observed = 42;
    }
    const library = (step: number) =>
      `import {invoke} from "./operations"
const helper = fn () => @u32.add (invoke ()) ${step}
const generated = @code.quote (helper ())
`;
    const observe = async (
      bytes: Uint8Array<ArrayBuffer>,
      expected: number,
    ) => {
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(bytes, { asynchronous });
        try {
          let answer;
          if (asynchronous) answer = await guest.callAsync("answer", null);
          else answer = guest.call("answer", null);
          assert.equal(answer, expected);
        } finally {
          guest.dispose();
        }
      }
    };
    try {
      for (const codegenTier of ["optimized", "development"] as const) {
        const options = { executable, entry, prelude: null, codegenTier };
        const cached = {
          ...options,
          cacheDirectory: `${directory}/cache-${codegenTier}`,
        };
        const retained = await createZigProjectCompiler(cached);
        try {
          for (const step of [2, 3, 2]) {
            const sources = {
              [entry]: source,
              [producer]: library(step),
              [operations]: operationSource,
            };
            await Deno.writeTextFile(entry, source);
            await Deno.writeTextFile(producer, sources[producer]);
            await Deno.writeTextFile(operations, operationSource);
            const fresh = await createZigProjectCompiler({
              ...options,
              cacheDirectory: false,
            });
            try {
              const expected = await fresh.build({ sources });
              assert(expected.success, JSON.stringify(expected));
              const result = await retained.build({ sources });
              assert(result.success, JSON.stringify(result));
              assert.deepEqual(result.bytes, expected.bytes);
              assert.equal(
                result.stats.nativeWorkSteps,
                expected.stats.nativeWorkSteps,
              );
              await observe(result.bytes, (observed + step) * 2);
              const unchanged = await retained.build({ sources });
              assert(unchanged.success, JSON.stringify(unchanged));
              assert.deepEqual(unchanged.bytes, expected.bytes);
              assert.equal(unchanged.stats.nativeWorkSteps, 0);
              const failed = await retained.build({
                sources: {
                  ...sources,
                  [entry]: source +
                    "const forbidden: U32 = @code.run generated\n",
                },
              });
              assert(!failed.success, JSON.stringify(failed));
              await observe(result.bytes, (observed + step) * 2);
              const restored = await retained.build({ sources });
              assert(restored.success, JSON.stringify(restored));
              assert.deepEqual(restored.bytes, expected.bytes);
              assert.equal(restored.stats.nativeWorkSteps, 0);
              const checkpoint = await retained.exportCheckpoint();
              const packed = await new Deno.Command(executable, {
                args: ["dependencies", entry, archive, "--prelude", "none"],
                stdout: "piped",
                stderr: "piped",
              }).output();
              assert(packed.success, new TextDecoder().decode(packed.stderr));
              const restartSteps: number[] = [];
              for (
                const settings of [cached, {
                  ...options,
                  cacheDirectory: false as const,
                  dependencies: archive,
                }, { ...options, cacheDirectory: false as const, checkpoint }]
              ) {
                const restarted = await createZigProjectCompiler(settings);
                try {
                  const resumed = await restarted.build({ sources });
                  assert(resumed.success, JSON.stringify(resumed));
                  assert.deepEqual(resumed.bytes, expected.bytes);
                  await observe(resumed.bytes, (observed + step) * 2);
                  restartSteps.push(resumed.stats.nativeWorkSteps);
                } finally {
                  await restarted.dispose();
                }
              }
              console.log(JSON.stringify({
                kind: "staging_effectful_named_work",
                declared,
                codegenTier,
                step,
                fresh: expected.stats.nativeWorkSteps,
                edit: result.stats.nativeWorkSteps,
                unchanged: unchanged.stats.nativeWorkSteps,
                recovery: restored.stats.nativeWorkSteps,
                restart: restartSteps,
              }));
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
}
