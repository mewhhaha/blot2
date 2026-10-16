import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

async function generationRecipeLaw(
  recipe:
    | "statement if"
    | "Boolean case"
    | "scalar case"
    | "product case"
    | "loop carries"
    | "scope providers"
    | "row principals"
    | "provider callbacks",
) {
  const directory = await Deno.makeTempDir({ prefix: "blot-staging-if-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/producer.blot`;
  const archive = `${directory}/producer.blotdep`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  const source = `import {generated, evaluated} from "./producer"
entry const checked: U32 = evaluated
entry const probe = fn (value: U32) => (@code.emit generated) value
entry const answer = fn () => do:
  let value = 100
  let first = (@code.emit generated) 0
  let second = (@code.emit generated) 1
  return @u32.add value (@u32.add first second)
`;
  const library = (base: number) => {
    if (recipe === "provider callbacks") {
      return `effect Read: Unit -> U32
const callback = fn () => ${base}
const helper = fn (value: U32) => do (@effect.provider Read callback):
  use initial <- Read ()
  return @u32.add initial value
const generated = @code.quote (fn (value: U32) => helper value)
const evaluated: U32 = @code.run (@code.quote (helper 2))
`;
    }
    if (recipe === "row principals") {
      return `effect Read: Unit -> U32
const apply: (Unit -> U32 ! {| e}) -> U32 ! {| e} = fn callback => callback ()
const helper = fn (value: U32) => do (@effect.provider Read (fn () => @u32.add value ${base})):
  return apply (fn () => Read ())
const generated = @code.quote (fn (value: U32) => helper value)
const evaluated: U32 = @code.run (@code.quote (helper 2))
`;
    }
    if (recipe === "scope providers") {
      return `type State a is effect = {get: Unit -> a, set: a -> Unit}
const helper = fn (value: U32) => @effect.scope (fn (state: State U32) => do:
  let read = fn () => state.get ()
  let pair = do (@effect.state state.get state.set ${base}):
    use previous <- read ()
    use state.set (@u32.add previous value)
    return read ()
  let (final, result) = pair
  return result)
const generated = @code.quote (fn (value: U32) => helper value)
const evaluated: U32 = @code.run (@code.quote (helper 2))
`;
    }
    if (recipe === "loop carries") {
      return `const helper = fn (value: U32) => do:
  let total = ${base}
  for part in #[value, 0]:
    if @u32.eq part 0:
      break
    if @u32.eq part 1:
      total := @u32.add total part
    else:
      total := @u32.add part total
  return total
const generated = @code.quote (fn (value: U32) => helper value)
const evaluated: U32 = @code.run (@code.quote (helper 2))
`;
    }
    if (recipe === "scalar case") {
      return `const helper = fn (value: U32) => case value of
  0 => ${base}
  value => @u32.add value ${base}
const generated = @code.quote (fn (value: U32) => helper value)
const evaluated: U32 = @code.run (@code.quote (helper 2))
`;
    }
    if (recipe === "product case") {
      return `const combine = fn (pair: (U32, U32)) => case pair of
  (left, right) => @u32.add left right
const helper = fn (value: U32) => combine (value, ${base})
const generated = @code.quote (fn (value: U32) => helper value)
const evaluated: U32 = @code.run (@code.quote (helper 2))
`;
    }
    if (recipe === "Boolean case") {
      return `const helper = fn (flag: Bool) => fn (value: U32) => case flag of
  #True => do:
    let flag = value
    return @u32.add flag ${base}
  #False => do:
    let value = @u32.add value ${base}
    return value
const generated = @code.quote (fn (value: U32) => helper (@u32.eq value 0) value)
const evaluated: U32 = @code.run (@code.quote (helper #False 2))
`;
    }
    return `const helper = fn (value: U32) => do:
  let kept = @u32.add value ${base}
  if @u32.eq value 0:
    let value = kept
    return value
  if @u32.eq value 1:
    if @u32.eq value 1:
      return kept
    else:
      return 0
  return @u32.add value ${base}
const generated = @code.quote (fn (value: U32) => helper value)
const evaluated: U32 = @code.run (@code.quote (helper 2))
`;
  };
  const observe = async (bytes: Uint8Array<ArrayBuffer>, base: number) => {
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        assert.equal(guest.read("checked"), base + 2);
        for (const value of [0, 1, 2]) {
          let result;
          if (asynchronous) result = await guest.callAsync("probe", value);
          else result = guest.call("probe", value);
          assert.equal(result, base + value);
        }
        let result;
        if (asynchronous) result = await guest.callAsync("answer", null);
        else result = guest.call("answer", null);
        assert.equal(result, 101 + base * 2);
      } finally {
        guest.dispose();
      }
    }
  };
  const measured: unknown[] = [];
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = { executable, entry, prelude: null, codegenTier };
      const cached = {
        ...options,
        cacheDirectory: `${directory}/cache-${codegenTier}`,
      };
      const retained = await createZigProjectCompiler(cached);
      try {
        for (const base of [40, 45, 40]) {
          const sources = { [entry]: source, [producer]: library(base) };
          await Deno.writeTextFile(entry, source);
          await Deno.writeTextFile(producer, sources[producer]);
          const fresh = await createZigProjectCompiler({
            ...options,
            cacheDirectory: false,
          });
          try {
            const expected = await fresh.build({ sources });
            assert(expected.success, JSON.stringify(expected));
            const built = await retained.build({ sources });
            assert(built.success, JSON.stringify(built));
            assert.deepEqual(built.bytes, expected.bytes);
            assert.equal(
              built.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            await observe(built.bytes, base);
            const unchanged = await retained.build({ sources });
            assert(unchanged.success, JSON.stringify(unchanged));
            assert.deepEqual(unchanged.bytes, expected.bytes);
            assert.equal(unchanged.stats.nativeWorkSteps, 0);
            let invalid = sources[producer].replace(
              `@u32.add value ${base}`,
              "#True",
            );
            if (recipe === "loop carries") {
              invalid = sources[producer].replace(
                "@u32.add total part",
                "#True",
              );
            }
            if (recipe === "scope providers") {
              invalid = sources[producer].replace(
                "@u32.add previous value",
                "#True",
              );
            }
            if (recipe === "provider callbacks") {
              invalid = sources[producer].replace(
                `fn () => ${base}`,
                "fn () => #True",
              );
            }
            if (recipe === "product case") {
              invalid = sources[producer].replace(
                "@u32.add left right",
                "#True",
              );
            }
            const failed = await retained.build({
              sources: {
                ...sources,
                [producer]: invalid,
              },
            });
            assert(!failed.success, JSON.stringify(failed));
            await observe(built.bytes, base);
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
              const replay of [
                cached,
                {
                  ...options,
                  cacheDirectory: false as const,
                  dependencies: archive,
                },
                { ...options, cacheDirectory: false as const, checkpoint },
              ]
            ) {
              const restarted = await createZigProjectCompiler(replay);
              try {
                const resumed = await restarted.build({ sources });
                assert(resumed.success, JSON.stringify(resumed));
                assert.deepEqual(resumed.bytes, expected.bytes);
                await observe(resumed.bytes, base);
                restartSteps.push(resumed.stats.nativeWorkSteps);
              } finally {
                await restarted.dispose();
              }
            }
            measured.push({
              recipe,
              codegenTier,
              base,
              fresh: expected.stats.nativeWorkSteps,
              retained: built.stats.nativeWorkSteps,
              unchanged: unchanged.stats.nativeWorkSteps,
              recovery: restored.stats.nativeWorkSteps,
              restart: restartSteps,
            });
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
    console.log(JSON.stringify(measured));
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

for (
  const recipe of [
    "statement if",
    "Boolean case",
    "scalar case",
    "product case",
    "loop carries",
    "scope providers",
    "row principals",
    "provider callbacks",
  ] as const
) {
  Deno.test(
    `staged ${recipe} helpers preserve branch hygiene source archive edits recovery and checkpoint restart`,
    () => generationRecipeLaw(recipe),
  );
}
