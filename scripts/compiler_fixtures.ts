export const compilerFixtures = [
  "arena-fixture",
  "shared-rc-fixture",
  "cohort-fixture",
  "list-runtime-fixture",
  "resource-retire-fixture",
  "region-owner-publication-fixture",
  "task-context-fixture",
  "data-stacks-fixture",
] as const;
export type CompilerFixture = typeof compilerFixtures[number];

export function parseCompilerFixtures(value: string): CompilerFixture[] {
  if (value === "") return [];
  const result: CompilerFixture[] = [];
  for (const name of value.split(",")) {
    if (!compilerFixtures.includes(name as CompilerFixture)) {
      throw new Error(`Unknown compiler fixture: ${name}`);
    }
    if (!result.includes(name as CompilerFixture)) {
      result.push(name as CompilerFixture);
    }
  }
  return result;
}

/** Whole directories conservatively include every fixture. */
export function fixturesForGuestFiles(
  files: readonly string[],
): CompilerFixture[] {
  const needed = new Set<CompilerFixture>();
  for (const file of files) {
    if (!file.endsWith(".test.ts")) return [...compilerFixtures];
    if (file.endsWith("/arena.test.ts")) needed.add("arena-fixture");
    if (
      file.endsWith("/shared_rc_execution.test.ts") ||
      file.endsWith("/scoped_authority_runtime.test.ts")
    ) needed.add("shared-rc-fixture");
    if (file.endsWith("/cohort_runtime_execution.test.ts")) {
      needed.add("cohort-fixture");
    }
    if (file.endsWith("/resource_retire_execution.test.ts")) {
      needed.add("resource-retire-fixture");
    }
    if (file.endsWith("/region_owner_publication_execution.test.ts")) {
      needed.add("region-owner-publication-fixture");
    }
    if (file.endsWith("/task_context_execution.test.ts")) {
      needed.add("task-context-fixture");
    }
    if (file.endsWith("/data_stacks_execution.test.ts")) {
      needed.add("data-stacks-fixture");
    }
    if (file.endsWith("/list_runtime.test.ts")) {
      needed.add("list-runtime-fixture");
    }
  }
  return compilerFixtures.filter((fixture) => needed.has(fixture));
}
