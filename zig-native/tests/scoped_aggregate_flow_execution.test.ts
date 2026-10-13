import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type State a is effect = {get: Unit -> a, set: a -> Unit}
const pack = fn first => fn second => fn third => (third, (first, second), first)
const keep = fn unused => fn retained => (retained, 42)
const shadow = fn same => fn same => (same, 1)
`;
const main = `import {State, pack, keep, shadow} from "./state"
entry const answer = fn (host: U32 -> U32 ! {Foreign}) => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let (selected, (first, second), repeated) = pack left right right
  use outer <- do (@effect.state left.get left.set 7):
    use inner <- do (@effect.state right.get right.set 100):
      use a <- selected.get ()
      use changed <- host a
      use selected.set changed
      use b <- first.get ()
      use c <- second.get ()
      use d <- repeated.get ()
      return @u32.add (@u32.add changed b) (@u32.add c d)
    let (state, result) = inner
    return result
  let (state, result) = outer
  return result
))
entry const mixed = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State F32) => do:
  let (selected, (first, second), repeated) = pack left right right
  use outer <- do (@effect.state left.get left.set 7):
    use inner <- do (@effect.state right.get right.set 1.5):
      use value <- selected.get ()
      use ignored <- first.get ()
      return @f32.add value 1.0
    let (state, result) = inner
    return result
  let (state, result) = outer
  return result
))
entry const lifetime = fn () => @effect.scope (fn (older: State U32) => do:
  let (borrowed, count) = @effect.scope (fn (younger: State U32) => keep younger older)
  use handled <- do (@effect.state borrowed.get borrowed.set 7):
    use value <- borrowed.get ()
    return @u32.add value count
  let (state, result) = handled
  return result
)
entry const shadowed = fn () => @effect.scope (fn (older: State U32) => do:
  let (borrowed, count) = @effect.scope (fn (younger: State U32) => shadow younger older)
  use handled <- do (@effect.state borrowed.get borrowed.set 7):
    use value <- borrowed.get ()
    return @u32.add value count
  let (state, result) = handled
  return result
)
`;
const escaping = `import {State, pack} from "./state"
entry const bad = fn () => @effect.scope (fn (state: State U32) => pack state 42 7)
`;
const variants = [{
  shape: "product",
  library,
  main,
  body: "(third, (first, second), first)",
  changedBody: "(third, (second, first), second)",
  lostBody:
    "do:\n  let saved = first\n  return (third, (saved, second), first)",
}, {
  shape: "record",
  library: library.replace(
    "(third, (first, second), first)",
    "{selected: third, nested: {first, second}, repeated: first}",
  ).replace("(retained, 42)", "{retained, count: 42}").replace(
    "(same, 1)",
    "{retained: same, count: 1}",
  ),
  main: main.replaceAll(
    "let (selected, (first, second), repeated)",
    "let {selected, nested: {first, second}, repeated}",
  ).replaceAll("let (borrowed, count)", "let {retained: borrowed, count}"),
  body: "{selected: third, nested: {first, second}, repeated: first}",
  changedBody:
    "{selected: third, nested: {first: second, second: first}, repeated: second}",
  lostBody:
    "do:\n  let saved = first\n  return {selected: third, nested: {first: saved, second}, repeated: first}",
}];
const cases = variants.flatMap((variant) =>
  (["optimized", "development"] as const).map((codegenTier) => ({
    ...variant,
    codegenTier,
  }))
);
for (
  const { shape, library, main, body, changedBody, lostBody, codegenTier }
    of cases
) {
  Deno.test(`owned parameter ${shape} footprints preserve imported capabilities and lifetimes (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-scoped-product-",
    });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/state.blot`;
    const archive = `${directory}/state.blotdep`;
    try {
      await Deno.writeTextFile(entry, main);
      await Deno.writeTextFile(dependency, library);
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
      for (const dependencies of [undefined, archive]) {
        const compiler = await createZigProjectCompiler({
          executable,
          entry,
          prelude: null,
          dependencies,
          codegenTier,
          cacheDirectory: false,
        });
        try {
          const sources = { [entry]: main, [dependency]: library };
          const built = await compiler.build({ sources });
          assert(built.success, JSON.stringify(built));
          const sync = await instantiateGuest(built.bytes);
          try {
            const host = sync.capability({
              parameter: "U32",
              result: "U32",
              call: (value) => Number(value) + 2,
            });
            assert.equal(sync.call("answer", host), 218);
            assert.equal(sync.call("mixed", null), 2.5);
            assert.equal(sync.call("lifetime", null), 49);
            assert.equal(sync.call("shadowed", null), 8);
          } finally {
            sync.dispose();
          }
          const asyncGuest = await instantiateGuest(built.bytes, {
            asynchronous: true,
          });
          try {
            const host = asyncGuest.capabilityAsync({
              parameter: "U32",
              result: "U32",
              call: async (value) => {
                await Promise.resolve();
                return Number(value) + 2;
              },
            });
            assert.equal(await asyncGuest.callAsync("answer", host), 218);
            const rejected = asyncGuest.capabilityAsync({
              parameter: "U32",
              result: "U32",
              call: () => Promise.reject(new Error("product rejected")),
            });
            await assert.rejects(
              asyncGuest.callAsync("answer", rejected),
              (error) => {
                assert.equal(
                  (error as { code: string }).code,
                  "host_exception",
                );
                return true;
              },
            );
            assert.equal(await asyncGuest.callAsync("answer", host), 218);
          } finally {
            asyncGuest.dispose();
          }
          const changed = await compiler.build({
            sources: {
              ...sources,
              [dependency]: library.replace(body, changedBody),
            },
          });
          assert(changed.success, JSON.stringify(changed));
          const edited = await instantiateGuest(changed.bytes);
          try {
            const host = edited.capability({
              parameter: "U32",
              result: "U32",
              call: (value) => Number(value) + 2,
            });
            assert.equal(edited.call("answer", host), 313);
          } finally {
            edited.dispose();
          }
          const recovery = await compiler.build({ sources });
          assert(recovery.success, JSON.stringify(recovery));
          assert.deepEqual(recovery.bytes, built.bytes);
          const checkpoint = await compiler.exportCheckpoint();
          const bad = await compiler.build({
            sources: { ...sources, [entry]: escaping },
          });
          assert(!bad.success);
          assert.equal(bad.diagnostics[0].code, "capability_escape");
          assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          const lost = await compiler.build({
            sources: {
              ...sources,
              [dependency]: library.replace(body, lostBody),
            },
          });
          assert(!lost.success);
          assert.equal(lost.diagnostics[0].code, "capability_escape");
          assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          const reverted = await compiler.build({ sources });
          assert(reverted.success, JSON.stringify(reverted));
          assert.deepEqual(reverted.bytes, built.bytes);
          const restored = await createZigProjectCompiler({
            executable,
            entry,
            prelude: null,
            dependencies,
            codegenTier,
            cacheDirectory: false,
            checkpoint,
          });
          try {
            const result = await restored.build({ sources });
            assert(result.success, JSON.stringify(result));
            assert.deepEqual(result.bytes, built.bytes);
          } finally {
            await restored.dispose();
          }
        } finally {
          await compiler.dispose();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
