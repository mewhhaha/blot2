import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createIncrementalCompiler } from "./incremental.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { loadSourceProject } from "./source_project.ts";
import { SourceError } from "./syntax.ts";

const source = `
type Cell a is effect = {
  get: Unit -> a
  set: a -> Unit
}
type Box a is data = Box a

const get = fn (witness: p -> a) -> a => Cell.get ()
const set = fn value => Cell.set value
const run = fn initial => fn action => @effect.run Cell.get Cell.set initial action

const advance = fn () => do:
  use integer <- get (fn () => Box 0)
  let Box count = integer
  use fraction <- get (fn () => Box 0.0)
  let Box amount = fraction
  use set (Box (@u32.add count 1))
  use set (Box (@f32.add amount 0.5))
  return count

const answer = fn () => do:
  let (Box count, (Box amount, previous)) = run (Box 40) (fn () =>
    run (Box 1.0) advance)
  return @f32.add (@f32.add (@u32.to_f32 count) amount) (@u32.to_f32 previous)

const custom_reader = fn () => @effect.reader Cell.get (fn () => Box 0) (fn () => Box 7) (fn () => do:
  use boxed <- get (fn () => Box 0)
  let Box value = boxed
  return value)

const custom_writer = fn () => do:
  let (Box written, answer) = run (Box 0) (fn () =>
    @effect.writer Cell.set (fn () => Box 0) (fn value => set value) (fn () => do:
      use set (Box 42)
      return 42))
  return @u32.add answer written

const constant_answer = answer ()
`;

Deno.test("generic effect operations infer state arguments from ordinary wrappers", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    ok(WebAssembly.validate(artifact.bytes));
    const exports = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.bytes),
    ).exports;
    equal((exports.answer as CallableFunction)(0), 82.5);
    equal((exports.custom_reader as CallableFunction)(0), 7);
    equal((exports.custom_writer as CallableFunction)(0), 84);
    equal((exports.constant_answer as WebAssembly.Global).value, 82.5);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("generic effect bridge rejects invalid families and unhandled access", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    for (
      const [invalid, code] of [
        [
          `type Pair [a, b] is effect = Unit -> a
const answer = fn () => @effect.get Pair 1`,
          "unknown_intrinsic",
        ],
        [
          `type Left a is effect = {
  get: Unit -> a
  set: a -> Unit
}
type Right a is effect = {
  get: Unit -> a
  set: a -> Unit
}
const answer = fn () => @effect.run Left.get Right.set 1 (fn () => 2)`,
          "effect_family",
        ],
        [
          `type Wrong a is effect = {
  get: a -> a
  set: a -> Unit
}
const answer = fn () => @effect.run Wrong.get Wrong.set 1 (fn () => Wrong.get 1)`,
          "type_mismatch",
        ],
        [
          `type Cell a is effect = Unit -> a
const answer: Unit -> U32 = fn () => Cell ()`,
          "effect_mismatch",
        ],
      ] as const
    ) {
      let expected: SourceError | undefined;
      throws(() => reference.compile(invalid), (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code);
        expected = error;
        return true;
      });
      await rejects(() => native.compile(invalid), (error) => {
        ok(error instanceof SourceError, String(error));
        ok(expected);
        equal(
          [error.code, error.message, error.start, error.end],
          [expected.code, expected.message, expected.start, expected.end],
        );
        return true;
      });
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("generic effect bridge preserves imported operation identity", async () => {
  const sources: Readonly<Record<string, string>> = {
    "file:///generic-family/main.blot":
      `import { Cell as LocalCell } from "./cell"
const get = fn (witness: a) -> a => LocalCell.get ()
const run = fn initial => fn action => @effect.run LocalCell.get LocalCell.set initial action
const answer = fn () => do:
  let (next, previous) = run 41 (fn () => get 0)
  return @u32.add next previous
`,
    "file:///generic-family/cell.blot": `type Cell a is effect = {
  get: Unit -> a
  set: a -> Unit
}
`,
  };
  const project = await loadSourceProject(
    new URL("file:///generic-family/main.blot"),
    {
      readSource(url) {
        const source = sources[url.href];
        if (source === undefined) {
          throw new Error(`Missing module: ${url.href}`);
        }
        return Promise.resolve(source);
      },
    },
  );
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const artifact = reference.compile(project);
    equal(await native.compile(project), artifact);
    ok(
      artifact.analysis.functions.some((fn) =>
        fn.effect_row.operations.some((operation) =>
          operation.module_name === "cell.blot" &&
          operation.declaration === "Cell.get<1:i>"
        )
      ),
    );
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(0), 82);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("hot reload invalidates edited generic effect signatures", async () => {
  const valid = `type Cell a is effect = {
  get: Unit -> a
  set: a -> Unit
}
const get = fn (witness: a) -> a => Cell.get ()
const answer = fn () => do:
  let (next, previous) = @effect.run Cell.get Cell.set 41 (fn () => get 0)
  return @u32.add next previous
`;
  const invalid = valid.replace("get: Unit -> a", "get: a -> a");
  const javascript = await createIncrementalCompiler({ prelude: "none" });
  const native = await createNativeIncrementalCompiler({
    prelude: "none",
  });
  const reference = await createSourceCompiler({ prelude: "none" });
  try {
    const first = await javascript.compile(valid);
    equal(first.artifact, reference.compile(valid));
    equal((await native.compile(valid)).artifact, first.artifact);
    for (const incremental of [javascript, native]) {
      await rejects(() => incremental.compile(invalid), (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, "type_mismatch");
        return true;
      });
    }
    const restored = await javascript.compile(valid);
    equal(restored.artifact, first.artifact);
    equal((await native.compile(valid)).artifact, restored.artifact);
    const exports = new WebAssembly.Instance(
      new WebAssembly.Module(restored.artifact.bytes),
    ).exports;
    equal((exports.answer as CallableFunction)(0), 82);
  } finally {
    await javascript.dispose();
    await native.dispose();
    reference.dispose();
  }
});
