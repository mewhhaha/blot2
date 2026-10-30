import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("grouped curried product footprints preserve imported capability ordinals and shadowing", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-grouped-product-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/state.blot`;
  const archive = `${directory}/state.blotdep`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  const library = `type State a is effect = {get: Unit -> a, set: a -> Unit}
const pack = func first => return (func second => return (func third => return (third, (first, second), first)))
const shadow = func same => return ((func same => return (same, 42)))
`;
  const source = `import {State, pack, shadow} from "./state"
entry const answer = func (host: U32 -> U32 ! {Foreign}) => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let (selected, (first, second), repeated) = pack left right right
  use outer <- do (@effect.state left.get left.set 7):
    use inner <- do (@effect.state right.get right.set 100):
      use a <- selected.get ()
      use changed <- host a
      use selected.set changed
      use b <- first.get ()
      use c <- second.get ()
      use d <- repeated.get ()
      break @u32.add (@u32.add changed b) (@u32.add c d)
    let (state, result) = inner
    break result
  let (state, result) = outer
  break result
))
entry const lifetime = func () => return @effect.scope (func (older: State U32) => return do:
  let (retained, count) = @effect.scope (func (younger: State U32) => return shadow younger older)
  use handled <- do (@effect.state retained.get retained.set 7):
    use value <- retained.get ()
    break @u32.add value count
  let (state, result) = handled
  break result
)
`;
  const observe = async (bytes: Uint8Array<ArrayBuffer>) => {
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        const host = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => Number(value) + 2,
        });
        if (asynchronous) {
          assert.equal(await guest.callAsync("answer", host), 218);
          assert.equal(await guest.callAsync("lifetime", null), 49);
        } else {
          assert.equal(guest.call("answer", host), 218);
          assert.equal(guest.call("lifetime", null), 49);
        }
      } finally {
        guest.dispose();
      }
    }
  };
  try {
    await Deno.writeTextFile(entry, source);
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
        cacheDirectory: false,
      });
      try {
        const sources = { [entry]: source, [dependency]: library };
        const built = await compiler.build({ sources });
        assert(built.success, JSON.stringify(built));
        await observe(built.bytes);
        const failed = await compiler.build({
          sources: {
            ...sources,
            [entry]: `import {State, pack} from "./state"
entry const bad = func () => return @effect.scope (func (state: State U32) => return pack state 42 7)
`,
          },
        });
        assert(!failed.success, JSON.stringify(failed));
        assert(
          failed.diagnostics.some((issue) =>
            issue.code === "capability_escape"
          ),
          JSON.stringify(failed),
        );
        await observe(built.bytes);
        const recovered = await compiler.build({ sources });
        assert(recovered.success, JSON.stringify(recovered));
        assert.deepEqual(recovered.bytes, built.bytes);
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
