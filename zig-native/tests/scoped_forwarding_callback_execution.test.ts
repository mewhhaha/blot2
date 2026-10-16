import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const helper =
  `const apply2 = fn callback => fn left => fn right => callback left right\n`;
const library = `import {apply2} from "./helper"
type State a is effect = {get: Unit -> a, set: a -> Unit}
const forward2 = fn callback => fn left => fn right => apply2 callback left right
const read2 = fn (left: State U32) => fn (right: State U32) => do:
  use x <- left.get ()
  use y <- right.get ()
  return @u32.sub x y
`;
const main = `import {State, forward2, read2} from "./library"
entry const answer = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  use outer <- do (@effect.state left.get left.set 7):
    use inner <- do (@effect.state right.get right.set 9):
      return forward2 read2 left right
    let (state, result) = inner
    return result
  let (state, result) = outer
  return result
))
`;

const completeMain = main +
  main.replace('import {State, forward2, read2} from "./library"\n', "")
    .replace(
      "entry const answer",
      "entry const reverse",
    ).replace("forward2 read2 left right", "forward2 read2 right left") +
  main.replace('import {State, forward2, read2} from "./library"\n', "")
    .replace(
      "entry const answer",
      "entry const repeated",
    ).replace("forward2 read2 left right", "forward2 read2 left left").replace(
      "right.get right.set 9",
      "left.get left.set 9",
    ) +
  main.replace('import {State, forward2, read2} from "./library"\n', "")
    .replace(
      "entry const answer",
      "entry const literal",
    ).replace(
      "forward2 read2 left right",
      "forward2 (fn (first: State U32) => fn (second: State U32) => first.get ()) left right",
    ) +
  main.replace('import {State, forward2, read2} from "./library"\n', "")
    .replace(
      "entry const answer",
      "entry const alias",
    ).replace(
      "return forward2 read2 left right",
      "let callback = read2\n      return forward2 callback left right",
    );

async function execute(bytes: Uint8Array, sum = false) {
  let sumValue = 4294967294;
  let reverseValue = 2;
  let repeatedValue = 0;
  if (sum) {
    sumValue = 16;
    reverseValue = 16;
    repeatedValue = 18;
  }
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      for (
        const [name, expected] of [
          ["answer", sumValue],
          ["reverse", reverseValue],
          ["repeated", repeatedValue],
          ["literal", 7],
          ["alias", sumValue],
        ] as const
      ) {
        if (asynchronous) {
          assert.equal(await guest.callAsync(name, null), expected);
        } else assert.equal(guest.call(name, null), expected);
      }
    } finally {
      guest.dispose();
    }
  }
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`forwarded callbacks retain exact no store and ordered scoped owners (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const helperFile = `${directory}/helper.blot`;
    const entry = `${directory}/main.blot`,
      dependency = `${directory}/library.blot`,
      archive = `${directory}/library.blotdep`;
    await Deno.writeTextFile(entry, completeMain);
    await Deno.writeTextFile(dependency, library);
    await Deno.writeTextFile(helperFile, helper);
    try {
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
          const built = await compiler.build({
            sources: {
              [entry]: completeMain,
              [helperFile]: helper,
              [dependency]: library,
            },
          });
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
            const replayed = await restored.build({
              sources: {
                [entry]: completeMain,
                [helperFile]: helper,
                [dependency]: library,
              },
            });
            assert(replayed.success, JSON.stringify(replayed));
            assert.deepEqual(replayed.bytes, built.bytes);
            await execute(replayed.bytes);
          } finally {
            await restored.dispose();
          }
          for (
            const rejected of [
              main.replace(
                "forward2 read2 left right",
                "forward2 read2 left left",
              ),
              main.replace(
                "forward2 read2 left right",
                "forward2 (fn first => fn second => fn () => first.get ()) left right",
              ),
              main.replace(
                "fn () => @effect.scope",
                "fn (host: (Unit -> U32 ! {| e}) -> U32 ! {Foreign}) => @effect.scope",
              ).replace(
                "forward2 read2 left right",
                "forward2 (fn first => fn second => host (fn () => first.get ())) left right",
              ),
            ]
          ) {
            const bad = await compiler.build({
              sources: {
                [entry]: rejected,
                [helperFile]: helper,
                [dependency]: library,
              },
            });
            assert(!bad.success, JSON.stringify(bad));
            assert(
              bad.diagnostics.some((diagnostic) =>
                diagnostic.code === "capability_escape"
              ),
              JSON.stringify(bad),
            );
            assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          }
          const recovered = await compiler.build({
            sources: {
              [entry]: completeMain,
              [helperFile]: helper,
              [dependency]: library,
            },
          });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, built.bytes);
          if (dependencies === undefined) {
            const changed = await compiler.build({
              sources: {
                [entry]: completeMain,
                [helperFile]: helper,
                [dependency]: library.replace("@u32.sub x y", "@u32.add x y"),
              },
            });
            assert(changed.success, JSON.stringify(changed));
            await execute(changed.bytes, true);
            const reverted = await compiler.build({
              sources: {
                [entry]: completeMain,
                [helperFile]: helper,
                [dependency]: library,
              },
            });
            assert(reverted.success, JSON.stringify(reverted));
            assert.deepEqual(reverted.bytes, built.bytes);
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
