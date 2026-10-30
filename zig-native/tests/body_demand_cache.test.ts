import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
let spine = "@force value";
for (let index = 0; index < 16; index++) spine = `@u32.add (${spine}) 0`;
const argumentSpine = spine.replaceAll("@force value", "marker");
const library = `const marker = 2
const twice = func ~(value: U32) => return @u32.add (${spine}) (@force value)
const ignore = func ~(value: U32) => return do:
  let unused = func () => return @force value
  break 7
const keep = func ~(values: Array U32) => return do:
  let first = @force values
  let second = @force values
  break #[@array.get first 0, @array.get second 1]
const apply = func (host: U32 -> U32 ! {Foreign}) => return @u32.add (twice (host (${argumentSpine}))) (ignore (host 999))
`;
const source = (seed: string, prefix = "") =>
  `import {apply, keep} from "./logic"
${prefix}const seed = ${seed}
entry const run = func (host: U32 -> U32 ! {Foreign}) => return apply host
entry const owned = func (value: U32) => return keep #[value, seed]
`;

async function observe(
  bytes: Uint8Array<ArrayBuffer>,
  seed: number,
  eager = false,
) {
  const expectedTrace = [seed];
  if (eager) expectedTrace.push(999);
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    const trace: number[] = [];
    let fail = false;
    const failure = new Error("delayed host failed");
    const implementation = {
      parameter: "U32" as const,
      result: "U32" as const,
      call(value: number) {
        trace.push(value);
        if (fail) throw failure;
        return value + 1;
      },
    };
    let host = guest.capability(implementation);
    if (asynchronous) host = guest.capabilityAsync(implementation);
    const call = async () => {
      if (asynchronous) return await guest.callAsync("run", host);
      return guest.call("run", host);
    };
    try {
      assert.equal(await call(), (seed + 1) * 2 + 7);
      assert.deepEqual(trace, expectedTrace);
      fail = true;
      await assert.rejects(
        call,
        (error: unknown) => error instanceof Error && error.cause === failure,
      );
      fail = false;
      trace.length = 0;
      assert.equal(await call(), (seed + 1) * 2 + 7);
      assert.deepEqual(trace, expectedTrace);
      for (let value = 0; value < 32; value++) {
        let result;
        if (asynchronous) result = await guest.callAsync("owned", value);
        else result = guest.call("owned", value);
        assert.deepEqual(result, Uint32Array.of(value, seed));
      }
      const warmed = guest.memoryBytes();
      for (let index = 0; index < 32; index++) await call();
      assert.equal(guest.memoryBytes(), warmed);
    } finally {
      guest.dispose();
    }
  }
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`body demand receipts preserve lazy effects owning results and recovery (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/logic.blot`;
    const archive = `${directory}/logic.blotdep`;
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
    assert(packed.success, new TextDecoder().decode(packed.stdout));
    const retained = await createZigProjectCompiler(options);
    const compiled = await createZigProjectCompiler({
      ...options,
      dependencies: archive,
    });
    let checkpoint: Uint8Array<ArrayBuffer>;
    let expected: Uint8Array<ArrayBuffer>;
    try {
      const inserted =
        "const earlier = func (value: F32) => return @f32.add value 1.0\n";
      for (
        const [text, seed, eager] of [
          [source("2"), 2, false],
          [source("3", inserted), 3, false],
          [source("3", inserted), 3, true],
          [source("missing"), null, false],
          [source("3", inserted), 3, false],
          [source("2"), 2, false],
        ] as const
      ) {
        const fresh = await createZigProjectCompiler(options);
        try {
          let dependencySource = library.replace(
            "const marker = 2",
            `const marker = ${seed ?? 2}`,
          );
          if (eager) {
            dependencySource = dependencySource.replace(
              "const ignore = func ~(value: U32)",
              "const ignore = func (value: U32)",
            )
              .replace(
                "let unused = func () => return @force value",
                "let unused = func () => return value",
              );
          }
          const sources = { [entry]: text, [dependency]: dependencySource };
          const result = await fresh.build({ sources });
          for (const compiler of [retained, compiled]) {
            const actual = await compiler.build({ sources });
            assert.equal(actual.success, result.success);
            if (!actual.success || !result.success) {
              assert(!actual.success && !result.success);
              if (seed !== null) console.error(actual.diagnostics);
              assert.equal(seed, null);
              assert.deepEqual(actual.diagnostics, result.diagnostics);
              continue;
            }
            assert.notEqual(seed, null);
            assert.deepEqual(actual.bytes, result.bytes);
            await observe(actual.bytes, seed!, eager);
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
