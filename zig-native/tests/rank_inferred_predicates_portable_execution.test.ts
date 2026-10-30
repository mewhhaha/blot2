import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const producer = `type Source a is contract = { type Item }
impl Number : Source U32 = { type Item = U32 }
const keep: a -> (Source.Item a) -> (Source.Item a) where { Source a } = func witness => return func value => return value
type Identity = forall [a] => a -> a
const identity: Identity = func value => return value
type Point is data = #Point { x: U32 }
const Point.add = func (left: Point) => return func (right: U32) => return @u32.add left.x right
const combine = func left => return func right => return @type.call "add" left right
const represented: a -> a where { type_rep a } = func value => return value
const field = func value => return value.x
const forward = func value => return combine value 22
const calculate = func (value: U32) => return keep value (forward (#Point {x: represented (field {x: value})}))
`;
const consumer = `import {identity, calculate} from "./identity"
entry const answer = func (value: U32) => return identity (calculate value)
`;
async function run(bytes: Uint8Array<ArrayBuffer>) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(new WebAssembly.Module(bytes), {
      asynchronous,
    });
    try {
      for (let value = 0; value < 96; value++) {
        let actual;
        if (asynchronous) actual = await guest.callAsync("answer", value);
        else actual = guest.call("answer", value);
        assert.equal(actual, value + 22);
      }
      const warmed = guest.memoryBytes();
      for (let value = 0; value < 96; value++) {
        let actual;
        if (asynchronous) actual = await guest.callAsync("answer", value);
        else actual = guest.call("answer", value);
        assert.equal(actual, value + 22);
      }
      assert.equal(guest.memoryBytes(), warmed);
    } finally {
      guest.dispose();
    }
  }
}
Deno.test("ordinary inferred predicate schemes retain exact publication through archives checkpoints and restart", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-rank-structural-" });
  const entry = `${directory}/main.blot`;
  const identity = `${directory}/identity.blot`;
  const dependencies = `${directory}/identity.blotdep`;
  try {
    await Deno.writeTextFile(entry, consumer);
    await Deno.writeTextFile(identity, producer);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, dependencies, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false as const,
        codegenTier,
      };
      const source = await createZigProjectCompiler(options);
      const archive = await createZigProjectCompiler({
        ...options,
        dependencies,
      });
      let checkpoint: Uint8Array<ArrayBuffer>;
      let expected: Uint8Array<ArrayBuffer>;
      try {
        const actual = await source.build();
        const frozen = await archive.build();
        assert(actual.success, JSON.stringify(actual));
        assert(frozen.success, JSON.stringify(frozen));
        assert(frozen.stats.cachedModules > 0);
        assert.deepEqual(frozen.bytes, actual.bytes);
        await run(actual.bytes);
        await run(frozen.bytes);
        expected = actual.bytes;
        checkpoint = await archive.exportCheckpoint();
        for (
          const failed of [
            consumer.replace("calculate value", "calculate true"),
            consumer.replace(
              "calculate value",
              "calculate (func value => return value)",
            ),
          ]
        ) {
          const live = await source.build({ sources: { [entry]: failed } });
          const frozenFailure = await archive.build({
            sources: { [entry]: failed },
          });
          assert(!live.success && !frozenFailure.success);
          assert.deepEqual(frozenFailure.diagnostics, live.diagnostics);
          assert.deepEqual(await archive.exportCheckpoint(), checkpoint);
        }
        const recovered = await archive.build({
          sources: { [entry]: consumer },
        });
        assert(recovered.success, JSON.stringify(recovered));
        assert.deepEqual(recovered.bytes, expected);
      } finally {
        await source.dispose();
        await archive.dispose();
      }
      await run(expected!);
      const restored = await createZigProjectCompiler({
        ...options,
        dependencies,
        checkpoint: checkpoint!,
      });
      try {
        const replayed = await restored.build();
        assert(replayed.success, JSON.stringify(replayed));
        assert.deepEqual(replayed.bytes, expected!);
        assert(
          (replayed.stats.runtimeOptimization as Record<string, number>)
            .reused >
            0,
          JSON.stringify(replayed.stats.runtimeOptimization),
        );
        await run(replayed.bytes);
      } finally {
        await restored.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
