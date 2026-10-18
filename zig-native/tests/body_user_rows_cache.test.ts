import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out-dev/bin/blotc", import.meta.url).pathname;
let spine = "callback ()";
for (let index = 0; index < 16; index++) spine = `@u32.add (${spine}) 0`;
const library = `effect Read: Unit -> U32
const marker = 2
const invoke = fn (callback: Unit -> U32 ! {Read}) => @u32.add (${spine}) marker
`;
const source = (seed: string, prefix = "") =>
  `import {Read as Input, invoke} from "./logic"
${prefix}const seed = ${seed}
entry const run = fn (host: U32 -> U32 ! {Foreign}) => do (@effect.provider Input (fn () => host seed)):
  return invoke Input
`;
async function observe(bytes: Uint8Array<ArrayBuffer>, seed: number) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    const trace: number[] = [];
    const failure = new Error("user row provider failed");
    let fail = false;
    const implementation = {
      parameter: "U32" as const,
      result: "U32" as const,
      call(value: number) {
        trace.push(value);
        if (fail) throw failure;
        return value + 2;
      },
    };
    let host = guest.capability(implementation);
    if (asynchronous) host = guest.capabilityAsync(implementation);
    const call = async () => {
      if (asynchronous) return await guest.callAsync("run", host);
      return guest.call("run", host);
    };
    try {
      assert.equal(await call(), seed * 2 + 2);
      assert.deepEqual(trace, [seed]);
      fail = true;
      await assert.rejects(
        call,
        (error: unknown) => error instanceof Error && error.cause === failure,
      );
      fail = false;
      trace.length = 0;
      assert.equal(await call(), seed * 2 + 2);
      assert.deepEqual(trace, [seed]);
    } finally {
      guest.dispose();
    }
  }
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`body user operation rows preserve effects through source archive checkpoint edits (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`,
      dependency = `${directory}/logic.blot`,
      archive = `${directory}/logic.blotdep`;
    const options = {
      executable,
      entry,
      prelude: null,
      cacheDirectory: false as const,
      codegenTier,
    };
    await Deno.writeTextFile(dependency, library);
    await Deno.writeTextFile(entry, source("2"));
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
    const retained = await createZigProjectCompiler(options);
    const compiled = await createZigProjectCompiler({
      ...options,
      dependencies: archive,
    });
    let checkpoint: Uint8Array<ArrayBuffer>, expected: Uint8Array<ArrayBuffer>;
    try {
      for (
        const [seed, prefix] of [
          ["2", ""],
          ["3", "effect Earlier: Bool -> Bool\nconst earlier = 7\n"],
          ["missing", ""],
          ["3", ""],
          ["2", ""],
        ] as const
      ) {
        const fresh = await createZigProjectCompiler(options);
        try {
          const sources = {
            [entry]: source(seed),
            [dependency]: prefix +
              library.replace("const marker = 2", `const marker = ${seed}`),
          };
          const result = await fresh.build({ sources });
          assert(result.success || seed === "missing", JSON.stringify(result));
          for (const compiler of [retained, compiled]) {
            const actual = await compiler.build({ sources });
            assert.equal(actual.success, result.success);
            if (!actual.success || !result.success) {
              assert(!actual.success && !result.success);
              assert.equal(seed, "missing");
              assert.deepEqual(actual.diagnostics, result.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, result.bytes);
            if (compiler === retained && seed === "3" && prefix) {
              // Source elaboration work of the whole attempt: the project
              // check of a rebuilt seed plus the entry's consumer check.
              const work = (stats: typeof actual.stats) =>
                Number(
                  (stats.attemptStats.fallback as {
                    body_elaborations: number;
                  }).body_elaborations,
                ) +
                Number(
                  (stats.frontend as { body_elaborations: number })
                    .body_elaborations,
                );
              const actualWork = work(actual.stats);
              const freshWork = work(result.stats);
              assert(
                actualWork < freshWork,
                JSON.stringify({
                  actual: actual.stats.frontend,
                  expected: result.stats.frontend,
                  actualWork,
                  freshWork,
                  archive: compiler === compiled,
                }),
              );
              console.log(
                `BODY_USER_ROWS tier=${codegenTier} source_elaborations=${actualWork}/${freshWork}`,
              );
            }
            await observe(actual.bytes, Number(seed));
          }
          if (result.success) expected = result.bytes;
        } finally {
          await fresh.dispose();
        }
      }
      checkpoint = await compiled.exportCheckpoint();
    } finally {
      await retained.dispose();
      await compiled.dispose();
    }
    const restored = await createZigProjectCompiler({
      ...options,
      dependencies: archive,
      checkpoint: checkpoint!,
    });
    try {
      const result = await restored.build();
      assert(result.success, JSON.stringify(result));
      assert.deepEqual(result.bytes, expected!);
      await observe(result.bytes, 2);
    } finally {
      await restored.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
