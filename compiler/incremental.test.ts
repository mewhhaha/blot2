import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import {
  createIncrementalCompiler,
  type IncrementalCompilerOptions,
} from "./incremental.ts";
import { createSourceCompiler } from "./source.ts";
import { createSourceSession } from "./source_session.ts";
import { SourceError } from "./syntax.ts";
import { createEcsRuntime } from "./ecs_runtime.ts";
import { CompilerWorkers } from "./worker_pool.ts";
import { bendArray, bendList, structuralKey } from "./pipeline.ts";
import type { Analysis, Type, TypeId } from "./host.ts";

type Session = Awaited<ReturnType<typeof createIncrementalCompiler>>;
type CleanCompiler = Awaited<ReturnType<typeof createSourceCompiler>>;
type Artifact = Awaited<ReturnType<Session["compile"]>>["artifact"];

function incrementalTest(
  name: string,
  test: (session: Session, clean: CleanCompiler) => Promise<void>,
  options: IncrementalCompilerOptions = { prelude: "none" },
): void {
  Deno.test(name, async () => {
    const session = await createIncrementalCompiler(options);
    let clean: CleanCompiler | undefined;
    try {
      clean = await createSourceCompiler(options);
      await test(session, clean);
    } finally {
      clean?.dispose();
      session.dispose();
    }
  });
}

function normalized(analysis: Analysis): Analysis {
  return {
    ...analysis,
    functions: analysis.functions.map((signature) => {
      const names = new Map<bigint, bigint>();
      const index = (original: bigint): bigint => {
        ok(signature.variables.includes(original));
        if (!names.has(original)) names.set(original, BigInt(names.size));
        return names.get(original)!;
      };
      const type = (value: Type): Type => {
        switch (value.$) {
          case "VariableTy":
            return { ...value, index: index(value.index) };
          case "AppliedTy":
            return { ...value, arguments: value.arguments.map(type) };
          case "FunctionTy":
            return {
              ...value,
              parameter: type(value.parameter),
              result: type(value.result),
            };
          default:
            return value;
        }
      };
      return {
        ...signature,
        parameter: type(signature.parameter),
        result: type(signature.result),
        variables: signature.variables.map(index).sort((left, right) =>
          left < right ? -1 : left > right ? 1 : 0
        ),
      };
    }),
  };
}

function equivalent(actual: Artifact, expected: Artifact): void {
  equal(actual.bytes, expected.bytes);
  equal(normalized(actual.analysis), normalized(expected.analysis));
}

async function answer(artifact: Artifact): Promise<number> {
  const { instance } = await WebAssembly.instantiate(artifact.bytes);
  const exported = instance.exports.answer;
  ok(typeof exported === "function");
  return exported(0) as number;
}

function diagnostic(code: string, start?: number) {
  return (error: unknown) => {
    ok(error instanceof SourceError, String(error));
    equal(error.code, code, error.message);
    if (start !== undefined) equal(error.start, start, error.message);
    return true;
  };
}

incrementalTest(
  "incremental no-op and trivia edits preserve prelude artifacts without rechecking",
  async (session, clean) => {
    const source =
      "export fn answer () => Maybe.unwrap_or 0 (Some (identity 42))\n";
    const first = await session.compile(source);
    equivalent(first.artifact, clean.compile(source));
    equal(await answer(first.artifact), 42);
    for (
      const revision of [source, "// Shift every source offset.\n\n" + source]
    ) {
      const next = await session.compile(revision);
      equivalent(next.artifact, clean.compile(revision));
      equal(next.stats.groups_checked, 0);
      equal(next.stats.entries_compiled, 0);
      equal(next.stats.declarations_lowered, 0);
      equal(next.stats.groups_reused, first.stats.groups_checked);
      equal(await answer(next.artifact), 42);
    }
  },
  { prelude: "default" },
);

incrementalTest(
  "incremental leaf-body edits reuse caller types and regenerate one code entry",
  async (session, clean) => {
    const source =
      "fn increment value => @u32.add value 1\nexport fn answer () => increment 40\n";
    const first = await session.compile(source);
    const revision = source.replace("value 1", "value 2");
    const next = await session.compile(revision);
    equivalent(next.artifact, clean.compile(revision));
    equal(next.stats.groups_checked, 1);
    equal(next.stats.groups_reused, 1);
    equal(next.stats.entries_compiled, 1);
    equal(next.stats.entries_reused, first.stats.entries_compiled - 1);
    equal(await answer(first.artifact), 41);
    equal(await answer(next.artifact), 42);
  },
);

incrementalTest(
  "incremental const dependencies observe same-interface body edits without caller rechecking",
  async (session, clean) => {
    const source = `fn calculate value => @u32.add value 1
const computed = calculate 40
const copied = computed
export fn answer () => copied
`;
    const first = await session.compile(source);
    const revision = source.replace("value 1", "value 2");
    const next = await session.compile(revision);
    equivalent(next.artifact, clean.compile(revision));
    equal(next.stats.groups_checked, 1);
    equal(next.stats.groups_reused, 3);
    equal(next.stats.constants_evaluated, 2);
    equal(next.artifact.analysis.constants.map((constant) => constant.value), [
      { $: "U32Value", value: 42 },
      { $: "U32Value", value: 42 },
    ]);
    equal(await answer(first.artifact), 41);
    equal(await answer(next.artifact), 42);
  },
);

incrementalTest(
  "incremental interface changes reject stale callers and failed revisions do not poison recovery",
  async (session, clean) => {
    const source =
      "fn transform value => @u32.add value 1\nexport fn answer () => @u32.add (transform 41) 0\n";
    const first = await session.compile(source);
    const invalid = source.replace("@u32.add value 1", "True");
    await rejects(() => session.compile(invalid), diagnostic("type_mismatch"));
    const recovered = await session.compile(source);
    equivalent(recovered.artifact, clean.compile(source));
    equal(recovered.stats.groups_checked, 0);
    equal(await answer(recovered.artifact), 42);
    equal(await answer(first.artifact), 42);
  },
);

incrementalTest(
  "incremental effect and constructor-layout edits agree with clean ECS execution in workers",
  async (session, clean) => {
    const source = `data Marker = Marker U32
#[component] data Position = Position U32
#[component] data Velocity = Velocity U32
fn read_position () => @ecs.get Position
fn read_velocity () => @ecs.get Velocity
export fn move () => do:
  use position <- read_position ()
  let Position value = position
  use @ecs.set (Position (@u32.add value 1))
  return ()
`;
    const identity = (declaration: string): TypeId => ({
      $: "TypeId",
      module_name: "main",
      declaration,
    });
    const first = await session.compileEcs(source);
    equivalent(first.artifact, clean.compileEcs(source));
    const runtime = await createEcsRuntime(first.artifact);
    const world = runtime.createWorld({
      entityCount: 2,
      components: [
        { identity: identity("Position"), values: [1, 2] },
        { identity: identity("Velocity"), values: [1, null] },
      ],
    });
    equal(
      runtime.readComponent(runtime.run(world), identity("Position"), 1),
      3,
    );
    const effect = source.replace(
      "fn read_position () => @ecs.get Position",
      `fn read_position () => do:
  use read_velocity ()
  use position <- @ecs.get Position
  return position`,
    );
    const changed = await session.compileEcs(effect);
    equivalent(changed.artifact, clean.compileEcs(effect));
    equal(
      changed.artifact.analysis.world.systems[0].query.map((storage) =>
        storage.identity.declaration
      ),
      ["Position", "Velocity"],
    );
    const layout = effect.replace(
      "data Marker = Marker U32",
      "data Marker = Marker U32 | EmptyMarker",
    );
    const retagged = await session.compileEcs(layout);
    const expected = clean.compileEcs(layout);
    equivalent(retagged.artifact, expected);
    equal(retagged.artifact.storage, expected.storage);
    ok(
      retagged.artifact.storage.some((slot, index) =>
        slot.tag !== changed.artifact.storage[index].tag
      ),
    );
    for (const artifact of [changed.artifact, retagged.artifact]) {
      const next = await runtime.reload(world, artifact);
      const advanced = next.runtime.run(next.world);
      equal(next.runtime.readComponent(advanced, identity("Position"), 0), 2);
      equal(next.runtime.readComponent(advanced, identity("Position"), 1), 2);
      equal(runtime.readComponent(world, identity("Position"), 0), 1);
    }
    await rejects(
      () =>
        session.compileEcs(
          "#[component] data Position = Position Bool\nexport fn move () => @ecs.set (Position True)\n",
        ),
      diagnostic("backend_ecs_layout"),
    );
  },
  { prelude: "none", workers: 2 },
);

incrementalTest(
  "incremental source identities keep unchanged lambdas and locals stable after unrelated insertion",
  async (session, clean) => {
    const source = `fn capture value => fn extra => do:
  let result = @u32.add value extra
  return result
export fn answer () => capture 40 2
`;
    const shifted = "const unrelated = 7\n" + source;
    const frontend = await createSourceSession({ prelude: "none" });
    try {
      const original = bendArray(frontend.prepare(source).module.functions);
      const inserted = bendArray(frontend.prepare(shifted).module.functions);
      equal(structuralKey(inserted), structuralKey(original));
    } finally {
      frontend.dispose();
    }
    const first = await session.compile(source);
    const next = await session.compile(shifted);
    equivalent(next.artifact, clean.compile(shifted));
    equal(next.stats.groups_reused, first.stats.groups_checked);
    equal(next.stats.entries_compiled, 0);
    equal(next.stats.entries_reused, first.stats.entries_compiled);
    equal(await answer(next.artifact), 42);
  },
);

incrementalTest(
  "incremental budgets and diagnostic offsets survive trivia and failed revisions",
  async (session, clean) => {
    const source = "const value = 42\nexport fn answer () => value\n";
    const options = { const_steps: 100n };
    const first = await session.compile(source, options);
    await rejects(
      () => session.compile(source, { const_steps: 0n }),
      diagnostic("const_budget"),
    );
    const shifted = "// New location.\n\n" + source;
    const next = await session.compile(shifted, options);
    equivalent(next.artifact, clean.compile(shifted, options));
    equal(
      next.artifact.analysis.remaining_steps,
      first.artifact.analysis.remaining_steps,
    );
    const invalid =
      "export fn answer () => do:\n  let value: Bool = 1\n  return value\n";
    for (const revision of [invalid, "// Diagnostic shifts.\n" + invalid]) {
      await rejects(
        () => session.compile(revision),
        diagnostic("type_mismatch", revision.indexOf("let")),
      );
    }
    equivalent(
      (await session.compile(source, options)).artifact,
      clean.compile(source, options),
    );
  },
);

incrementalTest(
  "incremental public artifact and stats mutations cannot change cached results",
  async (session, clean) => {
    const source = "const value = 42\nexport fn answer () => value\n";
    const first = await session.compile(source);
    const counts = { ...first.stats };
    first.artifact.bytes.fill(0);
    Object.assign(first.artifact.analysis.functions[0], { name: "corrupt" });
    Object.assign(first.artifact.analysis.constants[0].value, { value: 0 });
    Object.assign(first.stats, {
      groups_checked: 12345,
      groups_reused: 0,
      entries_compiled: 54321,
    });
    for (const revision of [source, "// Trivia cache path.\n" + source]) {
      const next = await session.compile(revision);
      equivalent(next.artifact, clean.compile(revision));
      equal(next.stats.groups_reused, counts.groups_checked);
      equal(next.stats.entries_reused, counts.entries_compiled);
      equal(await answer(next.artifact), 42);
      next.artifact.bytes.fill(0);
      Object.assign(next.stats, { groups_checked: 9999, entries_reused: 9999 });
    }
  },
);

incrementalTest(
  "incremental queued requests snapshot options and recover in source order",
  async (session, clean) => {
    const source = (value: number) =>
      `const value = ${value}\nexport fn answer () => value\n`;
    const options = { const_steps: 100n };
    const first = session.compile(source(40), options);
    options.const_steps = 0n;
    const second = session.compile(source(41));
    const failed = session.compile("export fn answer () => missing\n");
    const final = session.compile(source(42));
    const results = await Promise.allSettled([first, second, failed, final]);
    equal(results.map((result) => result.status), [
      "fulfilled",
      "fulfilled",
      "rejected",
      "fulfilled",
    ]);
    for (const [index, value] of [[0, 40], [1, 41], [3, 42]]) {
      const completed = results[index];
      ok(completed.status === "fulfilled");
      equivalent(
        completed.value.artifact,
        clean.compile(source(value), index === 0 ? { const_steps: 100n } : {}),
      );
      equal(await answer(completed.value.artifact), value);
    }
    const last = await session.compile(source(42));
    equal(last.stats.groups_checked, 0);
    equal(await answer(last.artifact), 42);
  },
  { prelude: "none", workers: 2 },
);

Deno.test("incremental disposal rejects startup jobs, queued revisions and later requests", async () => {
  const workers = new CompilerWorkers(2);
  const job = workers.run({
    kind: "check",
    module: {
      $: "Module",
      functions: bendList([]),
      constants: bendList([]),
      data_types: bendList([]),
      descriptors: bendList([]),
    },
    dependencies: bendList([]),
  });
  const stopped = Promise.all([
    rejects(workers.ready, /disposed/),
    rejects(job, /disposed/),
  ]);
  workers.dispose();
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    await Promise.race([
      stopped,
      new Promise<never>((_, reject) => {
        timeout = setTimeout(
          () =>
            reject(
              new Error("Disposed worker startup promises did not settle"),
            ),
          1000,
        );
      }),
    ]);
  } finally {
    clearTimeout(timeout);
    workers.dispose();
  }
  const session = await createIncrementalCompiler({
    prelude: "none",
    workers: 2,
  });
  const queued = session.compile("export fn answer () => 42\n");
  const rejected = rejects(queued, /disposed/);
  await Promise.resolve();
  session.dispose();
  await rejected;
  await rejects(
    () => session.compile("export fn answer () => 42\n"),
    /disposed/,
  );
  session.dispose();
});
