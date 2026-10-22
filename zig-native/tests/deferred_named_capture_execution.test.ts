import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type Maybe a is data = #Nothing | #Some a
type State a is effect = {get: Unit -> a, set: a -> Unit}
const scope_feature = fn () => @effect.scope (fn (s: State U32) => do:
  let ignored = s
  break 0
)
const generate = fn count => fn generator => @array.generate count generator
const migrate = fn (version: U32) => case version of
  1 => #Some (fn (values: Array F32) => generate (@array.length values) (fn index => if @u32.lt 0 index then (if @u32.eq (@u32.rem (@u32.sub index 1) 6) 4 then @f32.mul values[index] 2.0 else values[index]) else values[index]))
  _ => #Nothing
`;
const source = `import {migrate, Maybe, Some, Nothing} from "./library"
entry const answer = fn () => case migrate 1 of
  #Some callback => @array.get (callback #[1.0, 2.0, 3.0, 4.0, 5.0, 6.0]) 5
  #Nothing => 0.0
`;
async function execute(bytes: Uint8Array) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      for (let index = 0; index < 32; index++) {
        if (asynchronous) {
          assert.equal(await guest.callAsync("answer", null), 12);
        } else assert.equal(guest.call("answer", null), 12);
      }
    } finally {
      guest.dispose();
    }
  }
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`deferred named call construction survives source archives and recovery (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/library.blot`;
    const archive = `${directory}/library.blotdep`;
    await Deno.writeTextFile(entry, source);
    await Deno.writeTextFile(dependency, library);
    try {
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
      let bytes: Uint8Array | undefined;
      for (const dependencies of [undefined, archive]) {
        const options = {
          executable,
          entry,
          prelude: null,
          codegenTier,
          cacheDirectory: false as const,
          dependencies,
        };
        const compiler = await createZigProjectCompiler(options);
        try {
          const built = await compiler.build();
          assert(built.success, JSON.stringify(built));
          if (bytes) assert.deepEqual(built.bytes, bytes);
          else bytes = built.bytes;
          await execute(built.bytes);
          const checkpoint = await compiler.exportCheckpoint();
          const restored = await createZigProjectCompiler({
            ...options,
            checkpoint,
          });
          try {
            const replayed = await restored.build();
            assert(replayed.success, JSON.stringify(replayed));
            assert.deepEqual(replayed.bytes, built.bytes);
            await execute(replayed.bytes);
          } finally {
            await restored.close();
          }
          const changed = await compiler.build({
            sources: { [entry]: source.replace("migrate 1", "migrate 0") },
          });
          assert(changed.success, JSON.stringify(changed));
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(changed.bytes, {
              asynchronous,
            });
            try {
              if (asynchronous) {
                assert.equal(await guest.callAsync("answer", null), 0);
              } else assert.equal(guest.call("answer", null), 0);
            } finally {
              guest.dispose();
            }
          }
          const rejected = await compiler.build({
            sources: { [entry]: source.replace("migrate 1", "migrate #True") },
          });
          assert(!rejected.success);
          const recovered = await compiler.build({
            sources: { [entry]: source },
          });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, built.bytes);
          await execute(recovered.bytes);
        } finally {
          await compiler.close();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
