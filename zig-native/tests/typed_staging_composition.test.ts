import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

async function generationRecipeLaw(
  recipe:
    | "stateful requests"
    | "resolver continuations"
    | "resolver forwarding"
    | "resolver effects"
    | "resolver iteration",
) {
  const directory = await Deno.makeTempDir({ prefix: "blot-staging-if-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/producer.blot`;
  const archive = `${directory}/producer.blotdep`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  const source =
    `import {generated, generated_task, evaluated} from "./producer"
entry const checked: U32 = evaluated
entry const task_probe = func (value: U32) => return (@code.emit generated_task) value
entry const probe = func (value: U32) => return (@code.emit generated) value
entry const answer = func () => return do:
  let value = 100
  use first <- (@code.emit generated) 0
  use second <- (@code.emit generated) 1
  break @u32.add value (@u32.add first second)
`;
  const library = (base: number) => {
    if (recipe === "resolver iteration") {
      return `const helper = func (value: U32) => return Maybe.unwrap_or 0 (do (monad Maybe):
  let total = ${base}
  for index in 0..value:
    use item <- $Some 1
    total := @u32.add self item
  break total)
const generated = @code.quote (func (value: U32) => return helper value)
const generated_task = @code.quote (func (value: U32) => return @task.scope (func group => return @task.join (@task.spawn group (func () => return helper value))))
const evaluated: U32 = @code.run (@code.quote (helper 2))
`;
    }
    if (recipe === "stateful requests") {
      return `effect Read: U32 -> U32
const helper = func (value: U32) => return do:
  let count = ${base}
  let calculation = @computation (func () => return Read value)
  for request in @requests calculation:
    case request of
      effect Read value =>
        count := @u32.add self value
        yield value
      complete value =>
        break count
const generated = @code.quote (func (value: U32) => return helper value)
const generated_task = @code.quote (func (value: U32) => return @task.scope (func group => return @task.join (@task.spawn group (func () => return helper value))))
const evaluated: U32 = @code.run (@code.quote (helper 2))
`;
    }
    let finish = "break @u32.add number " + base;
    if (recipe === "resolver forwarding") {
      finish = "break $ $Box (@u32.add number " + base + ")";
    }
    let pure = "const Box.pure = func value => return $Box value";
    if (recipe === "resolver effects") {
      pure = `const Box.pure = func value => return do:
  use owner <- @resource.acquire (func () => return 1) (func value => return ())
  use @resource.release owner
  break $Box value`;
    }
    let generatedTask =
      "@code.quote (func (value: U32) => return @task.scope (func group => return @task.join (@task.spawn group (func () => return helper value))))";
    if (recipe === "resolver effects") generatedTask = "generated";
    let evaluated = "@code.run (@code.quote (helper 2))";
    if (recipe === "resolver effects") evaluated = String(base + 2);
    return `type Box a is data = $Box a
${pure}
const Box.bind = func candidate => return func next => return case candidate of
  $Box value => next value
const identity = func value => return value
const selected = identity (@do.monad (identity Box))
const sequence = func (value: U32) => return do selected:
  use number <- $Box value
  ${finish}
const helper = func (value: U32) => return case sequence value of
  $Box result => result
const generated = @code.quote (func (value: U32) => return helper value)
const generated_task = ${generatedTask}
const evaluated: U32 = ${evaluated}
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
          if (asynchronous) result = await guest.callAsync("task_probe", value);
          else result = guest.call("task_probe", value);
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
  let prelude: string | null = null;
  let preludeArgument = "none";
  if (recipe === "resolver iteration") {
    prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
    preludeArgument = prelude;
  }
  const measured: unknown[] = [];
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = { executable, entry, prelude, codegenTier };
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
            const invalid = sources[producer].replace("@u32.add", "@f32.add");
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
              args: [
                "dependencies",
                entry,
                archive,
                "--prelude",
                preludeArgument,
              ],
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
    "stateful requests",
    "resolver continuations",
    "resolver forwarding",
    "resolver effects",
    "resolver iteration",
  ] as const
) {
  Deno.test(
    `named ${recipe} preserve lexical owners source archive edits recovery and checkpoint restart`,
    () => generationRecipeLaw(recipe),
  );
}
