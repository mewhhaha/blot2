import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createNativeCompiler, type NativeCompilerOptions } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { createIncrementalFrontend } from "./incremental_frontend.ts";
import { NativeProcess } from "./native_process.ts";
import {
  decodeNativeSessionResponse,
  encodeNativeSessionRequest,
} from "./native_protocol.ts";
import { CompilerError } from "./diagnostics.ts";
import { bendArray } from "./bend_list.ts";
import { SourceError } from "./syntax.ts";
import type {
  Analysis,
  AnalyzedArtifact as Artifact,
  EffectRow,
  Expr,
  Type,
} from "./host.ts";

type Session = Awaited<ReturnType<typeof createNativeIncrementalCompiler>>;
type Clean = Awaited<ReturnType<typeof createNativeCompiler>>;

function sessionTest(
  name: string,
  test: (session: Session, clean: Clean) => Promise<void>,
  options: NativeCompilerOptions = { prelude: "none", threads: 1 },
) {
  Deno.test(name, async () => {
    const session = await createNativeIncrementalCompiler(options);
    let clean: Clean | undefined;
    try {
      clean = await createNativeCompiler(options);
      await test(session, clean);
    } finally {
      await clean?.dispose();
      await session.dispose();
    }
  });
}

sessionTest(
  "native planner invalidates an operation-only nominal catalog revision",
  async (session, clean) => {
    const source = `type Box is data = #Box U32
type Wrap is data = #Wrap U32
effect Unused : Unit -> Box
entry const answer = 7
`;
    const first = await session.compile(source);
    equivalent(first.artifact, await clean.compile(source));
    const changedSource = source.replace(
      "effect Unused : Unit -> Box",
      "effect Unused : Unit -> Wrap",
    );
    const changed = await session.compile(changedSource);
    equivalent(changed.artifact, await clean.compile(changedSource));
    // The changed operation catalog invalidates source certificates. Fresh
    // source evidence then retains this unchanged body in the final check.
    equal(changed.stats.groups_checked, 0);
    equal(
      changed.stats.groups_reused,
      first.stats.groups_checked + first.stats.groups_reused,
    );
    const recovered = await session.compile(source);
    equivalent(recovered.artifact, await clean.compile(source));
  },
);

sessionTest(
  "qualified use plans preserve native parity across concrete calls and edits",
  async (session, clean) => {
    const source =
      `const twice: a -> a where { associated "add" a a a } = fn value => value + value
const alias = twice
entry const integer = fn () => alias 21
entry const fraction = fn () => alias 1.0
`;
    const first = await session.compile(source);
    equivalent(first.artifact, await clean.compile(source));
    const exports = new WebAssembly.Instance(
      new WebAssembly.Module(first.artifact.bytes),
    ).exports;
    equal((exports.integer as CallableFunction)(), 42);
    equal((exports.fraction as CallableFunction)(), 2);

    const revised = source.replace(
      'associated "add" a a a',
      'associated "add" a a a, type_rep U32',
    );
    const edited = await session.compile(revised);
    equivalent(edited.artifact, await clean.compile(revised));
    ok(edited.stats.groups_checked > 0);

    const invalid = source.replace(
      'associated "add" a a a',
      'associated "missing" a a a',
    );
    await rejects(() => session.compile(invalid));
    await rejects(() => clean.compile(invalid));
    const restored = await session.compile(source);
    equivalent(restored.artifact, await clean.compile(source));
  },
  { prelude: "default", threads: 1 },
);

sessionTest(
  "mutual SCC carries qualified plans through aliases and predicate-only variables",
  async (session, clean) => {
    for (
      const source of [
        `const first: a -> a = fn value => do:
  let alias = second
  return alias value
const second: a -> a where { associated "add" a a a } = fn value => case #True of
  #True => value + value
  #False => first value
entry const answer = fn () => first 21
`,
        `const first: U32 -> U32 = fn value => second value
const second: U32 -> U32 where { associated "add" U32 U32 a } = fn value => case #True of
  #True => value
  #False => first value
entry const answer = fn () => first 42
`,
      ]
    ) {
      const cached = await session.compile(source);
      equivalent(cached.artifact, await clean.compile(source));
      const exports = new WebAssembly.Instance(
        new WebAssembly.Module(cached.artifact.bytes),
      ).exports;
      equal((exports.answer as CallableFunction)(), 42);
    }
  },
  { prelude: "default", threads: 1 },
);

sessionTest(
  "predicate-only field and type-changing update results resolve at concrete uses",
  async (session, clean) => {
    const source = `type Box a is data = #Box { value: a }
const read: a -> b where { field "value" a b } = fn box => box.value
const replace: a -> b -> c where { update "value" a b c } = fn box => fn value => do:
  let current = box
  current.value := value
  return current
entry const field_result = fn () => read (#Box { value: 42 })
entry const changed_result = fn () => do:
  let changed = replace (#Box { value: 0 }) #True
  return case changed.value of
    #True => 42
    #False => 0
`;
    const artifact = await session.compile(source);
    equivalent(artifact.artifact, await clean.compile(source));
    const exports = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.artifact.bytes),
    ).exports;
    equal((exports.field_result as CallableFunction)(), 42);
    equal((exports.changed_result as CallableFunction)(), 42);
  },
);

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
        tail: value.tail.$ === "RowVariable" || value.tail.$ === "RowParameter"
          ? { ...value.tail, index: index(value.tail.index) }
          : value.tail,
      });
      const type = (value: Type): Type => {
        switch (value.$) {
          case "VariableTy":
            return { ...value, index: index(value.index) };
          case "AppliedTy":
            return { ...value, arguments: value.arguments.map(type) };
          case "ProductTy":
            return { ...value, elements: value.elements.map(type) };
          case "ArrayTy":
            return { ...value, element: type(value.element) };
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

function equivalent(actual: Artifact, expected: Artifact) {
  equal(actual.bytes, expected.bytes);
  equal(normalized(actual.analysis), normalized(expected.analysis));
}

async function answer(artifact: Artifact) {
  const { instance } = await WebAssembly.instantiate(artifact.bytes);
  const fn = instance.exports.answer;
  ok(typeof fn === "function");
  return fn(0) as number;
}

sessionTest(
  "native tuple-pattern edits invalidate retained closures without losing field patterns",
  async (session, clean) => {
    const source = `const choose = (fn fallback => fn pair => case pair of
  (#True, value) => value
  (#False, _) => fallback) 0
entry const answer = fn () => choose (#True, 42)
`;
    for (
      const [revision, expected] of [
        [source, 42],
        [
          source.replace("(#True, value)", "(#False, value)").replace(
            "(#False, _)",
            "(#True, _)",
          ),
          0,
        ],
        [source, 42],
      ] as const
    ) {
      const cached = await session.compile(revision);
      const fresh = await clean.compile(revision);
      equal(cached.artifact.bytes, fresh.bytes);
      equal(await answer(cached.artifact), expected);
      equal(await answer(fresh), expected);
      const saved = cached.artifact.analysis.constants.find((entry) =>
        entry.name === "choose"
      );
      ok(saved?.value.$ === "ClosureValue");
      let body = saved.value.body;
      while (body.$ === "SourceExpr") body = body.value;
      ok(body.$ === "MatchExpr");
      const pattern = body.arms[0].patterns[0];
      ok(pattern.$ === "ProductPattern");
      equal(pattern.elements[0], { $: "BoolPattern", value: expected === 42 });
      const unchanged = await session.compile(revision);
      equal(unchanged.stats.groups_checked, 0);
      equal(unchanged.stats.constants_evaluated, 0);
      equal(await answer(unchanged.artifact), expected);
    }
  },
);

function diagnostic(code: string, start?: number) {
  return (error: unknown) => {
    ok(error instanceof SourceError, String(error));
    equal(error.code, code, error.message);
    if (start !== undefined) equal(error.start, start, error.message);
    return true;
  };
}

sessionTest(
  "native session preserves product and array constants, type rows, and expression keys",
  async (session, clean) => {
    const source =
      `const select = fn (pair: (Array U32, U32)) => @array.get (@product.get pair 0) (@product.get pair 1)
const values = [40, 42]
const bundle = (values, 1)
entry const saved = (fn replacement => fn state => @array.set state 0 replacement) 99
const changed = saved values
entry const answer = fn () => select bundle
entry const edited = fn () => @array.get changed 0
`;
    const withoutSavedClosure = (artifact: Artifact): Artifact => ({
      ...artifact,
      analysis: {
        ...artifact.analysis,
        constants: artifact.analysis.constants.filter((entry) =>
          entry.name !== "saved"
        ),
      },
    });
    const withoutSource = (value: Expr): Expr => {
      let expression = value;
      while (
        expression.$ === "SourceExpr" ||
        expression.$ === "InstantiationExpr"
      ) expression = expression.value;
      return expression;
    };
    const js = await createSourceCompiler({ prelude: "none" });
    try {
      for (
        const [revision, expected] of [
          [source, 42],
          [source.replace("[40, 42]", "[40, 43]"), 43],
          [source.replace("(values, 1)", "(values, 0)"), 40],
          [
            source.replace("@array.set state 0", "@array.set state 1"),
            42,
          ],
          [source, 42],
        ] as const
      ) {
        const compiled = await session.compile(revision);
        // Cached closure identities/locals/offsets are declaration-local;
        // clean compilation uses physical source offsets. Check its body below.
        equivalent(
          withoutSavedClosure(compiled.artifact),
          withoutSavedClosure(await clean.compile(revision)),
        );
        equivalent(
          withoutSavedClosure(compiled.artifact),
          withoutSavedClosure(js.compile(revision)),
        );
        equal(await answer(compiled.artifact), expected);
        const bundle = compiled.artifact.analysis.constants.find((entry) =>
          entry.name === "bundle"
        )?.value;
        ok(
          bundle?.$ === "ProductValue" && bundle.elements[0].$ === "ArrayValue",
        );
        const saved = compiled.artifact.analysis.constants.find((entry) =>
          entry.name === "saved"
        )?.value;
        ok(saved?.$ === "ClosureValue");
        const body = withoutSource(saved.body);
        ok(body.$ === "ArraySetExpr");
        equal(withoutSource(body.array), {
          $: "LocalExpr",
          name: saved.parameter,
        });
        equal(withoutSource(body.index), {
          $: "U32Expr",
          value: revision.includes("@array.set state 1") ? 1 : 0,
        });
        const replacement = withoutSource(body.value);
        ok(replacement.$ === "LocalExpr");
        equal(
          saved.environment.find((entry) => entry.name === replacement.name)
            ?.value,
          {
            $: "U32Value",
            value: 99,
          },
        );
        const { instance } = await WebAssembly.instantiate(
          compiled.artifact.bytes,
        );
        const edited = instance.exports.edited;
        ok(typeof edited === "function");
        equal(edited(0), revision.includes("@array.set state 1") ? 40 : 99);
        const repeated = await session.compile(revision);
        equal(repeated.stats.groups_checked, 0);
        equal(repeated.stats.entries_compiled, 0);
      }
    } finally {
      js.dispose();
    }
  },
);

sessionTest(
  "native session retains prelude and reuses trivia-only revisions",
  async (session, clean) => {
    const source =
      "entry const answer = fn () => Maybe.unwrap_or 0 (#Some (identity 42))\n";
    const first = await session.compile(source);
    equivalent(first.artifact, await clean.compile(source));
    const js = await createSourceCompiler();
    try {
      equivalent(first.artifact, js.compile(source));
    } finally {
      js.dispose();
    }
    for (
      const revision of [
        source,
        "// Unicode 🙂 shifts physical offsets.\n\n" + source,
      ]
    ) {
      const next = await session.compile(revision);
      equivalent(next.artifact, await clean.compile(revision));
      equal(next.stats.declarations_lowered, 0);
      equal(next.stats.groups_checked, 0);
      equal(next.stats.entries_compiled, 0);
      equal(
        next.stats.groups_reused,
        first.stats.groups_checked + first.stats.groups_reused,
      );
      equal(next.stats.entries_reused, first.stats.entries_compiled);
      equal(await answer(next.artifact), 42);
    }
  },
  { threads: 1 },
);

sessionTest(
  "native session reuses the initial checked groups and still validates coverage",
  async (session, clean) => {
    const source = `entry const classify = fn (flag: Bool) => case flag of
  #True => 1
  #False => 0
entry const answer = fn () => classify #True
`;
    const first = await session.compile(source);
    equivalent(first.artifact, await clean.compile(source));
    ok(first.stats.groups_reused > 0);
    equal(await answer(first.artifact), 1);

    const invalid = source.replace("  #False => 0\n", "");
    await rejects(
      () => session.compile(invalid),
      diagnostic("non_exhaustive_match"),
    );
    await rejects(
      () => clean.compile(invalid),
      diagnostic("non_exhaustive_match"),
    );

    const restored = await session.compile(source);
    equivalent(restored.artifact, await clean.compile(source));
    equal(restored.stats.groups_checked, 0);
    equal(await answer(restored.artifact), 1);
  },
);

sessionTest(
  "native session leaf edits retain source evidence and regenerate one code entry",
  async (session, clean) => {
    const source =
      "entry const increment = fn value => @u32.add value 1\nentry const answer = fn () => increment 40\n";
    const first = await session.compile(source);
    const revision = source.replace("value 1", "value 2");
    const next = await session.compile(revision);
    equivalent(next.artifact, await clean.compile(revision));
    equal(next.stats.declarations_lowered, 1);
    equal(next.stats.declarations_reused, 1);
    equal(next.stats.groups_checked, 0);
    equal(next.stats.groups_reused, 2);
    equal(next.stats.entries_compiled, 1);
    equal(next.stats.entries_reused, first.stats.entries_compiled - 1);
    equal(await answer(first.artifact), 41);
    equal(await answer(next.artifact), 42);
  },
);

sessionTest(
  "native session const cache tracks transitive function bodies and entering budgets",
  async (session, clean) => {
    const source = `entry const increment = fn value => @u32.add value 1
entry const calculate = fn value => increment value
entry const first = calculate 40
entry const second = first
entry const answer = fn () => second
`;
    const first = await session.compile(source, { const_steps: 100n });
    const revision = source.replace("value 1", "value 2");
    const changed = await session.compile(revision, { const_steps: 100n });
    equivalent(
      changed.artifact,
      await clean.compile(revision, { const_steps: 100n }),
    );
    equal(changed.stats.constants_evaluated, 2);
    equal(await answer(first.artifact), 41);
    equal(await answer(changed.artifact), 42);
    await rejects(
      () => session.compile(revision, { const_steps: 0n }),
      diagnostic("const_budget"),
    );
    const recovered = await session.compile(revision, { const_steps: 100n });
    equivalent(
      recovered.artifact,
      await clean.compile(revision, { const_steps: 100n }),
    );
    equal(recovered.stats.constants_evaluated, 0);
    equal(recovered.stats.constants_reused, 2);
    equal(recovered.stats.groups_checked, 0);
    const relinkedSource = revision.replace("calculate 40", "calculate 41");
    const relinked = await session.compile(relinkedSource, {
      const_steps: 100n,
    });
    equal(relinked.stats.entries_compiled, 0);
    equal(await answer(relinked.artifact), 43);
    const shiftedBudget = "entry const unrelated = @u32.add 0 0\n" +
      relinkedSource;
    const shifted = await session.compile(shiftedBudget, { const_steps: 100n });
    equivalent(
      shifted.artifact,
      await clean.compile(shiftedBudget, { const_steps: 100n }),
    );
    equal(shifted.stats.constants_evaluated, 3);
  },
);

sessionTest(
  "native session failures do not publish type, lowering, or backend caches",
  async (session, clean) => {
    const source =
      "entry const transform = fn value => @u32.add value 1\nentry const answer = fn () => @u32.add (transform 41) 0\n";
    await session.compile(source);
    await rejects(
      () => session.compile(source.replace("@u32.add value 1", "#True")),
      diagnostic("type_mismatch"),
    );
    await rejects(
      () => session.compile(source + "const unused = fn () => missing\n"),
      diagnostic("unknown_value"),
    );
    await rejects(
      () =>
        session.compile(
          source + "const unused = fn value => @u32.add #True 1\n",
        ),
      diagnostic("type_mismatch"),
    );
    const invalid =
      "const answer = fn () => do:\n  let value: Bool = 1\n  return value\n";
    for (const revision of [invalid, "// shifted\n" + invalid]) {
      await rejects(
        () => session.compile(revision),
        diagnostic("type_mismatch", revision.indexOf("let")),
      );
    }
    await rejects(
      () =>
        session.compile(
          source +
            "entry const metadata = fn () => @effect.count (@effect.of transform)\n",
        ),
      diagnostic("backend_const_only"),
    );
    const recovered = await session.compile(source);
    equivalent(recovered.artifact, await clean.compile(source));
    equal(recovered.stats.declarations_lowered, 0);
    equal(recovered.stats.groups_checked, 0);
    equal(recovered.stats.entries_compiled, 0);
  },
);

sessionTest(
  "warm dispatch failures preserve source errors and roll back to the last success",
  async (session, clean) => {
    const source = `type Box is data = #Box { value: U32 }
entry const stable = fn () -> U32 => 1
const get = fn (box: Box) => box.value
entry const answer = fn () -> U32 => @u32.add (get (#Box { value: 41 })) (stable ())
`;
    const first = await session.compile(source);
    equivalent(first.artifact, await clean.compile(source));
    const invalid = source.replace(
      "stable = fn () -> U32 => 1",
      "stable = fn () -> U32 => #True",
    );
    for (
      const revision of [
        invalid,
        invalid + "const later = fn () -> U32 => #True\n",
        "// offset shift\n" + invalid,
      ]
    ) {
      const warmError = await session.compile(revision).then(
        () => undefined,
        (error: unknown) => error,
      );
      const cleanError = await clean.compile(revision).then(
        () => undefined,
        (error: unknown) => error,
      );
      ok(warmError instanceof SourceError);
      ok(cleanError instanceof SourceError);
      equal(
        [warmError.code, warmError.message, warmError.start],
        [cleanError.code, cleanError.message, cleanError.start],
      );
      equal(warmError.code, "type_mismatch");
    }
    const corrected = source.replace("value: 41", "value: 42");
    const recovered = await session.compile(corrected);
    equivalent(recovered.artifact, await clean.compile(corrected));
    equal(recovered.stats.result_reused, false);
    const restored = await session.compile(source);
    equivalent(restored.artifact, first.artifact);
    equal(restored.stats.result_reused, false);
  },
);

sessionTest(
  "no-dispatch success retains source evidence across failing edits and a new dispatch",
  async (session, clean) => {
    const source = `type Box is data = #Box { value: U32 }
entry const stable = fn () -> U32 => 1
entry const independent = fn () -> U32 => 2
entry const answer = fn () -> U32 => stable ()
`;
    const first = await session.compile(source);
    equivalent(first.artifact, await clean.compile(source));
    const noDispatchError = source.replace(
      "stable = fn () -> U32 => 1",
      "stable = fn () -> U32 => #True",
    );
    const dispatchError = source.replace(
      "entry const answer = fn () -> U32 => stable ()",
      "entry const answer = fn () -> U32 => (#Box { value: 41 }).missing",
    );
    for (const revision of [noDispatchError, dispatchError]) {
      const warmError = await session.compile(revision).then(
        () => undefined,
        (error: unknown) => error,
      );
      const cleanError = await clean.compile(revision).then(
        () => undefined,
        (error: unknown) => error,
      );
      ok(warmError instanceof SourceError);
      ok(cleanError instanceof SourceError);
      equal(
        [warmError.code, warmError.message, warmError.start],
        [cleanError.code, cleanError.message, cleanError.start],
      );
    }
    const corrected = source.replace(
      "independent = fn () -> U32 => 2",
      "independent = fn () -> U32 => 3",
    );
    const recovered = await session.compile(corrected);
    equivalent(recovered.artifact, await clean.compile(corrected));
    equal(recovered.stats.result_reused, false);
  },
);

sessionTest(
  "native session stable lambdas survive insertion and changed captured constants",
  async (session, clean) => {
    const source = `entry const captured = 40
const capture = fn value => fn extra => @u32.add value extra
entry const answer = fn () => capture captured 2
`;
    const first = await session.compile(source);
    const inserted = "const unrelated = fn ignored => 7\n" + source;
    const next = await session.compile(inserted);
    equivalent(next.artifact, await clean.compile(inserted));
    equal(next.stats.entries_compiled, 0);
    equal(next.stats.entries_reused, first.stats.entries_compiled);
    const changedSource = inserted.replace("captured = 40", "captured = 41");
    const changed = await session.compile(changedSource);
    equivalent(changed.artifact, await clean.compile(changedSource));
    equal(changed.stats.entries_compiled, 0);
    equal(await answer(changed.artifact), 43);
    const closureSource =
      `const capture = fn value => fn extra => @u32.add value extra
entry const closure = capture 40
entry const answer = fn () => closure 2
`;
    await session.compile(closureSource);
    const closureRevision = closureSource.replace(
      "@u32.add value extra",
      "@u32.add (@u32.add value extra) 1",
    );
    const closure = await session.compile(closureRevision);
    equal(closure.stats.constants_evaluated, 1);
    equal(closure.artifact.bytes, (await clean.compile(closureRevision)).bytes);
    equal(await answer(closure.artifact), 43);
  },
);

sessionTest(
  "native session F32 keys preserve signed zero and changed unary operators",
  async (session, clean) => {
    const source =
      "entry const offset = 0.0\nentry const answer = fn () => @f32.add offset 1.5\n";
    await session.compile(source);
    for (
      const revision of [
        source.replace("0.0", "-0.0"),
        source.replace("@f32.add offset 1.5", "@f32.neg offset"),
        source.replace("0.0", "2.5"),
      ]
    ) {
      const next = await session.compile(revision);
      equivalent(next.artifact, await clean.compile(revision));
      equal(
        await answer(next.artifact),
        await answer(await clean.compile(revision)),
      );
    }
  },
);

sessionTest(
  "native session generic effects and const descriptors follow changed call graphs",
  async (session, clean) => {
    const source = `effect Position.read: Unit -> F32
effect Velocity.read: Unit -> F32
const read_position = fn () => Position.read ()
const read_velocity = fn () => Velocity.read ()
const move = fn () => do:
  use value <- read_position ()
  return @f32.add value 1.0
entry const position_value = fn () => 1.25
entry const velocity_value = fn () => 0.25
const position = @effect.provider Position.read position_value
const velocity = @effect.provider Velocity.read velocity_value
const requirements = @effect.of move
entry const effect_count = @effect.count requirements
entry const answer = fn () => do position:
  return do velocity:
    return move ()
`;
    const first = await session.compile(source);
    equivalent(first.artifact, await clean.compile(source));
    const effect = source.replace(
      "const read_position = fn () => Position.read ()",
      `const read_position = fn () => do:
  use read_velocity ()
  return Position.read ()`,
    );
    const changed = await session.compile(effect);
    equivalent(changed.artifact, await clean.compile(effect));
    equal(
      first.artifact.analysis.constants.find((value) =>
        value.name === "effect_count"
      )?.value,
      { $: "U32Value", value: 1 },
    );
    equal(
      changed.artifact.analysis.constants.find((value) =>
        value.name === "effect_count"
      )?.value,
      { $: "U32Value", value: 2 },
    );
    const reorderedSource = effect.replace(
      "effect Position.read: Unit -> F32\neffect Velocity.read: Unit -> F32",
      "effect Velocity.read: Unit -> F32\neffect Position.read: Unit -> F32",
    );
    const reordered = await session.compile(reorderedSource);
    equivalent(reordered.artifact, await clean.compile(reorderedSource));
    equal(await answer(first.artifact), 2.25);
    equal(await answer(reordered.artifact), 2.25);
    const invalid = reorderedSource.replace(
      "return do velocity:",
      "return do position:",
    );
    await rejects(
      () => session.compile(invalid + "let initialized = answer ()\n"),
      diagnostic("initializer_effect"),
    );
    const recovered = await session.compile(reorderedSource);
    equivalent(recovered.artifact, await clean.compile(reorderedSource));
    equal(recovered.stats.groups_checked, 0);
    equal(recovered.stats.entries_compiled, 0);
  },
);

sessionTest(
  "native session queued revisions, mode changes, and public mutation cannot corrupt caches",
  async (session, clean) => {
    const source =
      "entry const value = 41\nentry const answer = fn () => value\n";
    const [first, second] = await Promise.all([
      session.compile(source),
      session.compile(source.replace("41", "42")),
    ]);
    equal(await answer(first.artifact), 41);
    equal(await answer(second.artifact), 42);
    first.artifact.bytes.fill(0);
    Object.assign(second.artifact.analysis.constants[0].value, { value: 0 });
    const analyzed = await session.analyze(source);
    equal(
      normalized(analyzed.analysis),
      normalized(await clean.analyze(source)),
    );
    const recovered = await session.compile(source);
    equivalent(recovered.artifact, await clean.compile(source));
    equal(await answer(recovered.artifact), 41);
    await session.dispose();
    await session.dispose();
    await rejects(() => session.compile(source), /disposed/);
  },
);

sessionTest(
  "native session queued failed edits retain only the last acknowledged declarations",
  async (session, clean) => {
    const source =
      "entry const increment = fn value => @u32.add value 1\nentry const answer = fn () => increment 41\n";
    const changed = source.replace("value 1", "value 2");
    const invalid = changed + "const unused = fn () => missing\n";
    const recovered = changed.replace("increment 41", "increment 40");
    const results = await Promise.allSettled([
      session.compile(source),
      session.compile(invalid),
      session.compile(recovered),
    ]);
    ok(results[0].status === "fulfilled");
    ok(results[1].status === "rejected");
    diagnostic("unknown_value")(results[1].reason);
    ok(results[2].status === "fulfilled");
    equivalent(results[2].value.artifact, await clean.compile(recovered));
    equal(await answer(results[2].value.artifact), 42);
    const repeated = await session.compile(recovered);
    equal(repeated.stats.declarations_lowered, 0);
    equal(repeated.stats.groups_checked, 0);
    equal(repeated.stats.entries_compiled, 0);
  },
);

sessionTest(
  "native session snapshots queued compile options before awaiting an earlier edit",
  async (session) => {
    const source =
      "entry const value = @u32.add 40 2\nentry const answer = fn () => value\n";
    const options = { const_steps: 100n };
    const first = session.compile(source, options);
    const second = session.compile(source, options);
    options.const_steps = 0n;
    const replies = await Promise.all([first, second]);
    equal(await answer(replies[0].artifact), 42);
    equal(await answer(replies[1].artifact), 42);
    const failure = session.compile(source, options);
    options.const_steps = 100n;
    await rejects(failure, diagnostic("const_budget"));
    const recovered = await session.compile(source, options);
    equal(recovered.stats.constants_evaluated, 0);
    equal(await answer(recovered.artifact), 42);
  },
);

sessionTest(
  "native session disposal rejects queued work before parsing or sending it",
  async (session) => {
    const first = session.compile("entry const answer = fn () => 42\n");
    const second = session.compile("fn");
    const settled = Promise.allSettled([first, second]);
    await session.dispose();
    const replies = await settled;
    for (const reply of replies) {
      ok(reply.status === "rejected");
      ok(reply.reason instanceof Error);
      ok(/disposed/.test(reply.reason.message));
    }
    await session.dispose();
  },
);

Deno.test("native declaration references reject invalid revisions and preserve the acknowledged source", async () => {
  const frontend = await createIncrementalFrontend({ prelude: "none" });
  const native = await NativeProcess.start({ threads: 1 });
  const clean = await createNativeCompiler({ prelude: "none", threads: 1 });
  try {
    const source =
      "entry const first = fn () => 1\nentry const answer = fn () => 42\n";
    const parsed = frontend.prepare(source);
    const nodes = bendArray(parsed.root.children);
    const replaced = nodes.map((node) => ({ kind: "replaced" as const, node }));
    const retained = nodes.map((node) => ({
      kind: "retained" as const,
      identity: node.offset,
    }));
    const request = {
      operation: "compile" as const,
      declarations: replaced,
      fuel: parsed.nodeCount,
      const_steps: 100n,
    };
    const send = async (
      patch: Parameters<typeof encodeNativeSessionRequest>[0],
    ) =>
      decodeNativeSessionResponse(
        await native.request(encodeNativeSessionRequest(patch)),
      );
    const failure = (code: string) => (error: unknown) => {
      ok(error instanceof CompilerError);
      equal(error.code, code, error.message);
      return true;
    };
    await rejects(() => send(request), failure("native_session"));
    equal(
      await send({
        operation: "open",
        prelude: frontend.prelude,
        fuel: frontend.preludeCount,
      }),
      { operation: "open" },
    );
    const first = await send(request);
    ok("result" in first && first.result.operation === "compile");
    equivalent(
      first.result.artifact,
      await clean.compile(source, { const_steps: request.const_steps }),
    );
    const invalid = [
      [{ kind: "retained" as const, identity: 0xFFFFFFFFFFFFn }],
      [replaced[0], {
        kind: "replaced" as const,
        node: { ...nodes[1], offset: nodes[0].offset },
      }],
      [{
        kind: "replaced" as const,
        node: { ...nodes[0], field: "not_declarations" },
      }],
    ];
    for (const declarations of invalid) {
      await rejects(
        () => send({ ...request, declarations }),
        failure("native_session"),
      );
    }
    await rejects(
      () => send({ ...request, declarations: retained, fuel: 0n }),
      failure("internal_cst"),
    );
    const analyzed = await send({
      ...request,
      operation: "analyze",
      declarations: retained,
    });
    ok("result" in analyzed);
    equal(analyzed.stats.declarations_lowered, 0);
    equal(analyzed.stats.groups_checked, 0);
    const recovered = await send({ ...request, declarations: retained });
    ok("result" in recovered);
    equal(recovered.result, first.result);
    equal(recovered.stats.declarations_lowered, 0);
    equal(recovered.stats.entries_compiled, 0);
    const reordered = await send({
      ...request,
      declarations: retained.toReversed(),
    });
    ok("result" in reordered && reordered.result.operation === "compile");
    equivalent(
      reordered.result.artifact,
      await clean.compile(
        "entry const answer = fn () => 42\nentry const first = fn () => 1\n",
        {
          const_steps: request.const_steps,
        },
      ),
    );
    equal(reordered.stats.entries_compiled, 0);
  } finally {
    frontend.dispose();
    await native.dispose();
    await clean.dispose();
  }
});

Deno.test("native session lower-fuel decreases do not bypass traversal limits after a cache hit", async () => {
  const frontend = await createIncrementalFrontend({ prelude: "none" });
  const native = await NativeProcess.start({ threads: 1 });
  try {
    const opened = decodeNativeSessionResponse(
      await native.request(
        encodeNativeSessionRequest({
          operation: "open",
          prelude: frontend.prelude,
          fuel: frontend.preludeCount,
        }),
      ),
    );
    equal(opened, { operation: "open" });
    const parsed = frontend.prepare(
      "entry const answer = fn () => @u32.add 40 2\n",
    );
    const request = {
      operation: "compile" as const,
      root: parsed.root,
      fuel: parsed.nodeCount,
      const_steps: 100n,
    };
    const first = decodeNativeSessionResponse(
      await native.request(encodeNativeSessionRequest(request)),
    );
    ok("result" in first);
    const invalid = await native.request(
      encodeNativeSessionRequest({ ...request, fuel: 0n }),
    );
    throws(() => decodeNativeSessionResponse(invalid), (error) => {
      ok(error instanceof CompilerError);
      equal(error.code, "internal_cst");
      return true;
    });
    const recovered = decodeNativeSessionResponse(
      await native.request(encodeNativeSessionRequest(request)),
    );
    ok("result" in recovered);
    equal(recovered.result, first.result);
    equal(recovered.stats.declarations_lowered, 0);
  } finally {
    frontend.dispose();
    await native.dispose();
  }
});

sessionTest(
  "native session Wasm-only compiles share compile caches and omit the analysis",
  async (session, clean) => {
    const source = `entry const captured = 40
entry const answer = fn () => @u32.add captured 2
`;
    const first = await session.compile(source);
    equivalent(first.artifact, await clean.compile(source));
    // Emit is a different operation, so it reaches the native session; the
    // session serves it from the caches the full compile filled.
    const wasm = await session.compile(source, { analysis: false });
    equal(wasm.artifact, { bytes: first.artifact.bytes });
    ok(!("analysis" in wasm.artifact));
    equal(wasm.stats.result_reused, false);
    equal(wasm.stats.declarations_lowered, 0);
    equal(wasm.stats.groups_checked, 0);
    equal(wasm.stats.entries_compiled, 0);
    equal(wasm.stats.entries_reused, first.stats.entries_compiled);
    const changedSource = source.replace("captured = 40", "captured = 41");
    const changed = await session.compile(changedSource, { analysis: false });
    const fresh = await clean.compile(changedSource);
    equal(changed.artifact, { bytes: fresh.bytes });
    equal(await answer(fresh), 43);
    const repeated = await session.compile(changedSource, { analysis: false });
    equal(repeated.stats.result_reused, true);
    equal(repeated.artifact, changed.artifact);
    await rejects(
      () => session.compile(source, { analysis: 0 as unknown as boolean }),
      TypeError,
    );
  },
);
