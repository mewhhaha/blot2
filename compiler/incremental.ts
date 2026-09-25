import {
  type AnalyzedArtifact,
  type AnalyzedArtifactOptions,
  type Artifact,
  type ArtifactOptions,
  type CompileOptions,
  constSteps,
  decodePipelineArtifact,
  includesAnalysis,
} from "./host.ts";
import {
  bendArray,
  bendList,
  type CheckedConstant,
  type CheckedFunction,
  type CheckedGroup,
  type CheckedModule,
  type ConstantBinding,
  type Constants,
  type EntryCode,
  type GroupInterface,
  type GroupJob,
  invoke,
  type Prepared,
  type RawModule,
  result,
  structuralKey,
} from "./pipeline.ts";
import type { SourceCompilerOptions } from "./source.ts";
import { createSourceSession } from "./source_session.ts";
import { CompilerWorkers } from "./worker_pool.ts";

export interface CompilationStats {
  readonly parsed_ms: number;
  readonly lowered_ms: number;
  readonly checked_ms: number;
  readonly constants_ms: number;
  readonly codegen_ms: number;
  readonly linked_ms: number;
  readonly total_ms: number;
  readonly declarations_lowered: number;
  readonly declarations_reused: number;
  readonly groups_checked: number;
  readonly groups_reused: number;
  readonly constants_evaluated: number;
  readonly constants_reused: number;
  readonly entries_compiled: number;
  readonly entries_reused: number;
}

export interface IncrementalCompilerOptions extends SourceCompilerOptions {
  readonly workers?: number;
}

interface Cached<T> {
  readonly key: string;
  readonly value: T;
}

interface PlannedGroup {
  readonly job: GroupJob;
  readonly owner: string;
  readonly module: RawModule;
  readonly key: string;
}

function indexed<T>(values: readonly T[], name: (value: T) => string) {
  return new Map(values.map((value, index) => [name(value), { value, index }]));
}

function select<T>(
  index: ReadonlyMap<string, { value: T; index: number }>,
  names: readonly string[],
): ReturnType<typeof bendList<T>> {
  return bendList(
    names.flatMap((name) => {
      const entry = index.get(name);
      return entry ? [entry] : [];
    }).sort((a, b) => a.index - b.index).map((entry) => entry.value),
  );
}

export async function createIncrementalCompiler(
  options: IncrementalCompilerOptions = {},
) {
  const workers = new CompilerWorkers(options.workers ?? 1);
  let opened: Awaited<ReturnType<typeof createSourceSession>> | undefined;
  const opening = createSourceSession(options).then((session) =>
    opened = session
  );
  try {
    await Promise.all([opening, workers.ready]);
  } catch (error) {
    workers.dispose();
    await opening.then((session) => session.dispose(), () => {});
    throw error;
  }
  const frontend = opened!;
  let disposed = false;
  let queue: Promise<unknown> = Promise.resolve();
  let groups = new Map<string, Cached<CheckedGroup>>();
  let constants = new Map<string, Cached<Constants>>();
  let entries = new Map<string, Cached<EntryCode>>();
  let planning: Cached<readonly GroupJob[]> | undefined;
  let previous:
    | Cached<{ artifact: AnalyzedArtifact; stats: CompilationStats }>
    | undefined;
  let previousInput:
    | { source: string; steps: bigint }
    | undefined;

  async function build(source: string, options: CompileOptions) {
    if (disposed) throw new Error("Compiler session is disposed");
    const start = performance.now();
    const steps = constSteps(options);
    if (
      previous && previousInput?.source === source &&
      previousInput.steps === steps
    ) {
      const prior = previous.value.stats;
      const artifact = structuredClone(previous.value.artifact);
      const stats: CompilationStats = {
        parsed_ms: 0,
        lowered_ms: 0,
        checked_ms: 0,
        constants_ms: 0,
        codegen_ms: 0,
        linked_ms: 0,
        declarations_lowered: 0,
        declarations_reused: prior.declarations_lowered +
          prior.declarations_reused,
        groups_checked: 0,
        groups_reused: prior.groups_checked + prior.groups_reused,
        constants_evaluated: 0,
        constants_reused: prior.constants_evaluated + prior.constants_reused,
        entries_compiled: 0,
        entries_reused: prior.entries_compiled + prior.entries_reused,
        total_ms: performance.now() - start,
      };
      return { artifact, stats };
    }
    const preparedSource = frontend.prepare(source);
    const { module } = preparedSource;
    const stats = {
      ...preparedSource.stats,
      checked_ms: 0,
      constants_ms: 0,
      codegen_ms: 0,
      linked_ms: 0,
      total_ms: 0,
      groups_checked: 0,
      groups_reused: 0,
      constants_evaluated: 0,
      constants_reused: 0,
      entries_compiled: 0,
      entries_reused: 0,
    };
    const revisionKey = structuralKey([steps, module]);
    if (previous?.key === revisionKey) {
      const prior = previous.value.stats;
      stats.groups_reused = prior.groups_checked + prior.groups_reused;
      stats.constants_reused = prior.constants_evaluated +
        prior.constants_reused;
      stats.entries_reused = prior.entries_compiled + prior.entries_reused;
      const artifact = structuredClone(previous.value.artifact);
      previousInput = { source, steps };
      stats.total_ms = performance.now() - start;
      return { artifact, stats };
    }
    try {
      const checkStart = performance.now();
      const preparedPlan = result<unknown>("groups.prepare_plan", module);
      const planningKey = structuralKey(preparedPlan);
      const nextPlanning = planning?.key === planningKey ? planning : {
        key: planningKey,
        value: bendArray(result<ReturnType<typeof bendList<GroupJob>>>(
          "groups.finish_plan",
          preparedPlan,
        )),
      };
      const jobs = nextPlanning.value;
      const functionIndex = indexed(
        bendArray(module.functions),
        (fn) => fn.name,
      );
      const constantIndex = indexed(
        bendArray(module.constants),
        (constant) => constant.name,
      );
      const typeIndex = indexed(
        bendArray(module.data_types),
        (type) => structuralKey(type.identity),
      );
      const planned: PlannedGroup[] = jobs.map((job) => {
        const members = bendArray(job.members);
        const nominals = bendArray(job.type_dependencies).map(structuralKey);
        // Bend decides membership and transitive type dependencies. This is
        // only an indexed, source-order-preserving projection of its job.
        const subset: RawModule = {
          $: "Module",
          functions: select(functionIndex, members),
          constants: select(constantIndex, members),
          data_types: select(typeIndex, nominals),
          operations: module.operations,
        };
        return {
          job,
          owner: structuralKey(bendArray(job.members).sort()),
          module: subset,
          key: structuralKey(subset),
        };
      });
      const owners = new Map<string, PlannedGroup>();
      for (const group of planned) {
        for (const member of bendArray(group.job.members)) {
          owners.set(member, group);
        }
      }
      const pending = new Map<PlannedGroup, Promise<CheckedGroup>>();
      const nextGroups = new Map<string, Cached<CheckedGroup>>();
      const check = (group: PlannedGroup): Promise<CheckedGroup> => {
        const existing = pending.get(group);
        if (existing) return existing;
        const operation = (async () => {
          const dependencies: GroupInterface[] = [];
          for (const name of bendArray(group.job.dependencies)) {
            const owner = owners.get(name);
            if (!owner) throw new Error(`Planner omitted dependency ${name}`);
            const dependency = await check(owner);
            const signature = bendArray(dependency.interfaces).find((
              candidate,
            ) => candidate.name === name);
            if (!signature) {
              throw new Error(
                `Planner attempted to import open interface ${name}`,
              );
            }
            dependencies.push(signature);
          }
          const key = group.key + structuralKey(dependencies);
          const cached = groups.get(group.owner);
          const value = cached?.key === key
            ? (stats.groups_reused++, cached.value)
            : (stats.groups_checked++,
              await workers.run({
                kind: "check",
                module: group.module,
                dependencies: bendList(dependencies),
              }));
          nextGroups.set(group.owner, { key, value });
          return value;
        })();
        pending.set(group, operation);
        return operation;
      };
      // Wait for the whole revision before publishing or reporting failure.
      // Workers never mutate caches, and source revisions have a single writer.
      const completed = await Promise.allSettled(planned.map(check));
      const checkedFunctions = new Map<string, CheckedFunction>();
      const checkedConstants = new Map<string, CheckedConstant>();
      for (const completion of completed) {
        if (completion.status === "rejected") throw completion.reason;
        for (const fn of bendArray(completion.value.checked.functions)) {
          checkedFunctions.set(fn.function.name, fn);
        }
        for (const constant of bendArray(completion.value.checked.constants)) {
          checkedConstants.set(constant.constant.name, constant);
        }
      }
      const requireChecked = <T>(found: T | undefined, name: string): T => {
        if (found === undefined) throw new Error(`Checker omitted ${name}`);
        return found;
      };
      const checked: CheckedModule = {
        $: "CheckedModule",
        functions: bendList(
          bendArray(module.functions).map((fn) =>
            requireChecked(checkedFunctions.get(fn.name), fn.name)
          ),
        ),
        constants: bendList(
          bendArray(module.constants).map((constant) =>
            requireChecked(checkedConstants.get(constant.name), constant.name)
          ),
        ),
        data_types: module.data_types,
        operations: module.operations,
      };
      stats.checked_ms = performance.now() - checkStart;

      const constStart = performance.now();
      const context = invoke<unknown>("const_context", module, checked);
      const nextConstants = new Map<string, Cached<Constants>>();
      const bindings: ConstantBinding[] = [];
      let remaining = steps;
      // Compile-time bodies are separate from type/effect interfaces: a body
      // edit can leave callers checked while invalidating evaluated constants.
      const constDependencies = (root: PlannedGroup): string => {
        const visited = new Set<PlannedGroup>();
        const work = [root];
        while (work.length) {
          const group = work.pop()!;
          if (visited.has(group)) continue;
          visited.add(group);
          for (const name of bendArray(group.job.dependencies)) {
            work.push(requireChecked(owners.get(name), name));
          }
        }
        return structuralKey([...visited].map((group) => group.key).sort());
      };
      for (const constant of bendArray(checked.constants)) {
        const name = constant.constant.name;
        // Keying the entering budget preserves the shared, source-ordered
        // evaluation budget exactly, including cached early returns/closures.
        const key = structuralKey([
          remaining,
          constDependencies(requireChecked(owners.get(name), name)),
        ]);
        const cached = constants.get(name);
        const value = cached?.key === key
          ? (stats.constants_reused++, cached.value)
          : (stats.constants_evaluated++,
            result<Constants>(
              "const_eval.evaluate_constants",
              bendList([constant]),
              remaining,
              context,
            ));
        nextConstants.set(name, { key, value });
        bindings.push(...bendArray(value.bindings));
        remaining = value.remaining;
      }
      const analysis = {
        $: "Analysis",
        checked,
        constants: bendList(bindings),
        remaining_steps: remaining,
      };
      stats.constants_ms = performance.now() - constStart;

      const codeStart = performance.now();
      const prepared = result<Prepared>(
        "wasm.prepare",
        checked,
        analysis.constants,
      );
      const nextEntries = new Map<string, Cached<EntryCode>>();
      const generated = await Promise.allSettled(
        bendArray(prepared.jobs).map(async (job) => {
          const owner = structuralKey(job.key);
          const key = structuralKey(job);
          const cached = entries.get(owner);
          const value = cached?.key === key
            ? (stats.entries_reused++, cached.value)
            : (stats.entries_compiled++,
              await workers.run({ kind: "codegen", job }));
          nextEntries.set(owner, { key, value });
          return value;
        }),
      );
      const code = generated.map((completion) => {
        if (completion.status === "rejected") throw completion.reason;
        return completion.value;
      });
      stats.codegen_ms = performance.now() - codeStart;
      const linkStart = performance.now();
      const bytes = result<unknown>("wasm.link", prepared, bendList(code));
      const artifact = decodePipelineArtifact({ analysis, bytes });
      stats.linked_ms = performance.now() - linkStart;
      if (disposed) throw new Error("Compiler session is disposed");
      groups = nextGroups;
      constants = nextConstants;
      entries = nextEntries;
      planning = nextPlanning;
      // Own the cached artifact. Public typed arrays and analysis objects may
      // be mutated by a consumer without corrupting a later compilation.
      stats.total_ms = performance.now() - start;
      previous = {
        key: revisionKey,
        value: { artifact: structuredClone(artifact), stats: { ...stats } },
      };
      previousInput = { source, steps };
      return { artifact, stats };
    } catch (error) {
      return preparedSource.translate(error);
    }
  }

  function enqueue(source: string, options: CompileOptions) {
    const requestOptions = { ...options };
    const operation = queue.then(() => build(source, requestOptions));
    queue = operation.then(() => {}, () => {});
    return operation;
  }

  /** With `analysis: false` the artifact carries only the Wasm bytes. */
  function compile(
    source: string,
    options?: AnalyzedArtifactOptions,
  ): Promise<{ artifact: AnalyzedArtifact; stats: CompilationStats }>;
  function compile(
    source: string,
    options?: ArtifactOptions,
  ): Promise<{ artifact: Artifact; stats: CompilationStats }>;
  async function compile(
    source: string,
    options: ArtifactOptions = {},
  ): Promise<{ artifact: Artifact; stats: CompilationStats }> {
    const analysis = includesAnalysis(options);
    const { artifact, stats } = await enqueue(source, options);
    return {
      artifact: analysis
        ? { analysis: artifact.analysis, bytes: artifact.bytes }
        : { bytes: artifact.bytes },
      stats,
    };
  }
  return {
    compile,
    dispose() {
      if (disposed) return;
      disposed = true;
      workers.dispose();
      frontend.dispose();
      groups.clear();
      constants.clear();
      entries.clear();
      previous = undefined;
      previousInput = undefined;
      planning = undefined;
    },
  };
}
