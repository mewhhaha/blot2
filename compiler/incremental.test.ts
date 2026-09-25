import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import {
  createIncrementalCompiler,
  type IncrementalCompilerOptions,
} from "./incremental.ts";
import { createSourceCompiler } from "./source.ts";
import { createSourceSession } from "./source_session.ts";
import { SourceError } from "./syntax.ts";
import { CompilerWorkers } from "./worker_pool.ts";
import { bendArray, bendList, structuralKey } from "./pipeline.ts";
import type {
  Analysis,
  AnalyzedArtifact as Artifact,
  EffectRow,
  Type,
} from "./host.ts";

type Session = Awaited<ReturnType<typeof createIncrementalCompiler>>;
type CleanCompiler = Awaited<ReturnType<typeof createSourceCompiler>>;

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
      const row = (value: EffectRow): EffectRow => ({
        ...value,
        operations: value.operations.toSorted((a, b) =>
          a.module_name < b.module_name
            ? -1
            : a.module_name > b.module_name
            ? 1
            : a.declaration < b.declaration
            ? -1
            : a.declaration > b.declaration
            ? 1
            : 0
        ),
        tail: value.tail.$ === "ClosedRow"
          ? value.tail
          : { ...value.tail, index: index(value.tail.index) },
      });
      const type = (value: Type): Type => {
        switch (value.$) {
          case "VariableTy":
            return { ...value, index: index(value.index) };
          case "AppliedTy":
            return { ...value, arguments: value.arguments.map(type) };
          case "ProviderTy":
            return { ...value, effects: row(value.effects) };
          case "FunctionTy":
            return {
              ...value,
              parameter: type(value.parameter),
              result: type(value.result),
              effects: row(value.effects),
            };
          default:
            return value;
        }
      };
      return {
        ...signature,
        parameter: type(signature.parameter),
        result: type(signature.result),
        effect_row: row(signature.effect_row),
        variables: signature.variables.map(index).sort((a, b) =>
          a < b ? -1 : a > b ? 1 : 0
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
      "const answer = fn () => Maybe.unwrap_or 0 (Some (identity 42))\n";
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
      "const increment = fn value => @u32.add value 1\nconst answer = fn () => increment 40\n";
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
    const source = `const calculate = fn value => @u32.add value 1
const computed = calculate 40
const copied = computed
const answer = fn () => copied
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
      "const transform = fn value => @u32.add value 1\nconst answer = fn () => @u32.add (transform 41) 0\n";
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
  "incremental effect interfaces and reflected consts agree with clean compilation in workers",
  async (session, clean) => {
    const source = `effect Reader.ask: Unit -> U32
effect Clock.ask: Unit -> U32
const reader_value = fn () => 20
const clock_value = fn () => 22
const reader = @effect.provider Reader.ask reader_value
const clock = @effect.provider Clock.ask clock_value
const read = fn () => Reader.ask ()
const requirements = @effect.of read
const requirement_count = @effect.count requirements
const answer = fn () => do reader:
  use value <- do clock:
    use number <- read ()
    return number
  return value
`;
    const first = await session.compile(source);
    equivalent(first.artifact, clean.compile(source));
    equal(await answer(first.artifact), 20);
    equal(
      first.artifact.analysis.constants.find((c) =>
        c.name === "requirement_count"
      )?.value,
      { $: "U32Value", value: 1 },
    );
    const changedSource = source.replace(
      "const read = fn () => Reader.ask ()",
      `const read = fn () => do:
  use left <- Reader.ask ()
  use right <- Clock.ask ()
  return @u32.add left right`,
    );
    const changed = await session.compile(changedSource);
    equivalent(changed.artifact, clean.compile(changedSource));
    equal(await answer(changed.artifact), 42);
    equal(
      changed.artifact.analysis.constants.find((c) =>
        c.name === "requirement_count"
      )?.value,
      { $: "U32Value", value: 2 },
    );
    const repeated = await session.compile(changedSource);
    equivalent(repeated.artifact, changed.artifact);
    equal(repeated.stats.groups_checked, 0);
    equal(repeated.stats.constants_evaluated, 0);
    equal(repeated.stats.entries_compiled, 0);
    await rejects(
      () =>
        session.compile(
          changedSource.replace("Clock.ask: Unit", "Clock.ask: Bool"),
        ),
      diagnostic("type_mismatch"),
    );
    const recovered = await session.compile(changedSource);
    equivalent(recovered.artifact, changed.artifact);
    equal(await answer(recovered.artifact), 42);
  },
  { prelude: "none", workers: 2 },
);

incrementalTest(
  "incremental source identities keep unchanged lambdas and locals stable after unrelated insertion",
  async (session, clean) => {
    const source = `const capture = fn value => fn extra => do:
  let result = @u32.add value extra
  return result
const answer = fn () => capture 40 2
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
    const source = "const value = 42\nconst answer = fn () => value\n";
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
      "const answer = fn () => do:\n  let value: Bool = 1\n  return value\n";
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
    const source = "const value = 42\nconst answer = fn () => value\n";
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
      `const value = ${value}\nconst answer = fn () => value\n`;
    const options = { const_steps: 100n };
    const first = session.compile(source(40), options);
    options.const_steps = 0n;
    const second = session.compile(source(41));
    const failed = session.compile("const answer = fn () => missing\n");
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
      operations: bendList([]),
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
  const queued = session.compile("const answer = fn () => 42\n");
  const rejected = rejects(queued, /disposed/);
  await Promise.resolve();
  session.dispose();
  await rejected;
  await rejects(
    () => session.compile("const answer = fn () => 42\n"),
    /disposed/,
  );
  session.dispose();
});

incrementalTest(
  "incremental Wasm-only compiles return the cached artifact's bytes",
  async (session, clean) => {
    const source = "const answer = fn () => @u32.add 40 2\n";
    const full = await session.compile(source);
    const wasm = await session.compile(source, { analysis: false });
    equal(wasm.artifact, { bytes: full.artifact.bytes });
    ok(!("analysis" in wasm.artifact));
    equal(wasm.stats.groups_checked, 0);
    equal(clean.compile(source, { analysis: false }), wasm.artifact);
    await rejects(
      () => session.compile(source, { analysis: 1 as unknown as boolean }),
      TypeError,
    );
  },
);
