/** Explicit regression families. A development pass never qualifies the full tree. */
export const devCheckAreas = {
  "static-sharing": {
    native: [
      "backend.aggregate_constant_tests.test.retained callers replay aggregate constants with fresh-identical data through allocation failures",
      "backend.aggregate_constant_tests.test.aggregate constants with changed values aliases or nominal payloads rebuild their callers",
      "backend.aggregate_constant_tests.test.admission skips every aggregate child range of one caller and keeps the records between them",
      "reuse.artifact_backend_tests.test.artifact replay preserves codegen tiers and physical sharing without merging semantic jobs",
      "backend.persistent_roots_tests.test.capture-free descriptor addresses relocate through retained portable replay and OOM",
      "backend.persistent_roots_tests.test.static captured value graphs admit executable closure replay independently of principal mappings",
      "reuse.artifact_operation_admission_tests.test.operation admission qualifies cached and exact entry catalogs without publishing tags",
      "reuse.artifact_operation_admission_tests.test.operation admission validates exact entry catalogs in inline references and unused demands",
      "reuse.artifact_operation_admission_tests.test.executable fragment queries decline unsealed and saturated captures while preserving the live request owner",
      "reuse.artifact_operation_admission_tests.test.operation admission allocation failures preserve captures and runtime tables",
      "reuse.artifact_operation_admission_tests.test.operation admission retries failed indexing in the same owner and memoizes scope",
      "reuse.artifact_operation_admission_tests.test.startup dependency roles remap qualified owners and symbols while local ranges stay fixed",
      "reuse.artifact_operation_admission_tests.test.startup dependency role imports preserve old Core across allocation failures",
      "reuse.artifact_operation_admission_tests.test.entry operation payloads still reject a changed nominal catalog",
      "allocation_failures.test.sampled allocation failures check bounded indices while full mode stays exhaustive",
      "allocation_failures.test.sampled allocation failures reject swallowed faults and propagate scenario failures",
    ],
    guests: [
      "zig-native/tests/zig_project_protocol.test.ts",
      "zig-native/tests/zig_project_client.test.ts",
      "zig-native/tests/stage_chain_budget.test.ts",
    ],
    guestFilters: {
      "zig-native/tests/zig_project_client.test.ts":
        "Zig project client queues revisions and preserves entry edit/error/missing/correction bytes",
    } as Record<string, string>,
  },
} as const;

export type NativeTestRecord = {
  name: string;
  duration_ns: number;
  status: string;
  leaks: number;
  logged_errors: number;
  allocation_failures: string;
  sweeps: {
    full_sweeps: number;
    sampled_sweeps: number;
    discovered_allocations: number;
    fault_runs: number;
  };
};

export function nativeTestRecords(log: string): NativeTestRecord[] {
  return log.split("\n").flatMap((line) => {
    const marker = line.indexOf("BLOT_NATIVE_TEST\t");
    if (marker < 0) return [];
    return [JSON.parse(line.slice(marker + "BLOT_NATIVE_TEST\t".length))];
  });
}

export function verifyNativeSelection(
  records: NativeTestRecord[],
  expected: readonly string[],
  mode: "full" | "sampled",
) {
  const names = records.map((record) => record.name);
  if (
    new Set(names).size !== expected.length ||
    names.length !== expected.length ||
    expected.some((name) => !names.includes(name))
  ) {
    throw new Error(
      "Native results do not match the complete requested selection",
    );
  }
  for (const record of records) {
    if (
      record.status !== "passed" || record.leaks !== 0 ||
      record.logged_errors !== 0 || record.allocation_failures !== mode ||
      !Number.isFinite(record.duration_ns) || record.duration_ns < 0
    ) throw new Error(`Native test did not pass completely: ${record.name}`);
  }
}

/** A filtered Deno invocation can exit successfully after selecting zero tests. */
export function verifyGuestResults(
  xml: string,
  files: readonly string[],
  expectedNames?: string[],
) {
  const attributes = (text: string) =>
    Object.fromEntries(
      [...text.matchAll(/(\w+)="([^"]*)"/g)].map((
        match,
      ) => [match[1], match[2]]),
    );
  const cases = [
    ...xml.matchAll(/<testcase\b([^>]*?)(?:\/>|>([\s\S]*?)<\/testcase>)/g),
  ];
  // Deno emits filtered-out cases as <skipped/> too. Only explicitly unselected
  // names may be skipped; every requested name must have actually passed.
  const selected = expectedNames
    ? cases.filter((test) => expectedNames.includes(attributes(test[1]).name))
    : cases;
  if (
    !selected.length ||
    selected.some((test) =>
      /<(?:failure|error|skipped)\b/.test(test[2] ?? "")
    ) ||
    cases.some((test) =>
      !selected.includes(test) && !/<skipped\b/.test(test[2] ?? "")
    )
  ) {
    throw new Error(
      "Guest selection executed no tests or contains failed/skipped tests",
    );
  }
  const tests = selected.map((test) => attributes(test[1]));
  if (
    files.some((file) =>
      !tests.some((test) => test.classname?.replace(/^\.\//, "") === file)
    )
  ) {
    throw new Error("Guest results omit a requested test file");
  }
  if (
    expectedNames &&
    (tests.length !== expectedNames.length ||
      expectedNames.some((name) => !tests.some((test) => test.name === name)))
  ) {
    throw new Error("Guest results do not match the requested test names");
  }
  return tests.map((test) => ({ name: test.name, file: test.classname }));
}
