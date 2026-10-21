/** Explicit regression families. A development pass never qualifies the full tree. */
export const devCheckAreas = {
  "static-sharing": {
    description:
      "Static aggregate sharing, retained replay, admission and fault-policy laws.",
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
  "syntax": {
    "description":
      "Lexer/parser structure, recovery, immutable trees and allocation ownership.",
    "native": [
      "parse.lexer_tests.test.flat tokens preserve longest matches and source byte spans",
      "parse.lexer_tests.test.invalid layout, private markers, strings and Unicode report diagnostics",
      "parse.lexer_tests.test.all lexer allocation failures release tokens, trivia and scratch",
      "parse.parser_tests.test.surface syntax preserves nested blocks patterns loops and handlers",
      "parse.parser_tests.test.malformed syntax reports diagnostics and preserves later declarations",
      "parse.parser_tests.test.parser allocation failures release trees symbols and scratch stacks",
      "parse.parser_adjacent_call_tests.test.retained adjacent-call tree stays immutable across another parse and teardown",
      "parse.syntax_diagnostics_tests.test.UTF16 publication counts supplementary scalars and declines split byte boundaries",
      "parse.source_operators_tests.test.source fixity validation releases every failed allocation for successful and rejected graphs",
    ],
    "guests": [
      "compiler/syntax.test.ts",
      "zig-native/tests/annotation_arity_execution.test.ts",
    ],
    "guestFilters": {} as Record<string, string>,
  },
  "type-effects": {
    "description":
      "Type identity, substitution, effect-row rollback and owned evidence.",
    "native": [
      "check.types_tests.test.principal scheme substitution creates independent uses",
      "check.types_tests.test.occurs and mismatch rollback preserve prior constraints",
      "check.types_tests.test.rejected function effect rows roll back type and row writes and shared chronology",
      "check.types_tests.test.value and effect quantifiers freshen independently without accidental numeric identity",
      "check.types_tests.test.aggregate occurs checks and rejected shapes leave the complete region unchanged",
      "check.types_tests.test.shared type substitution stays linear and releases scratch on allocation failure",
      "check.types_tests.test.selected identity terms preserve alias edges and reject independent roots transactionally through OOM",
      "check.types_tests.test.owned higher rank row binders retain alpha scope substitution and independent solving through OOM",
      "check.effect_unification_tests.test.row views retain source order and multiplicity through wide permutations failures and recovery",
    ],
    "guests": [
      "zig-native/tests/type_identity_execution.test.ts",
      "zig-native/tests/symbolic_effect_rows.test.ts",
    ],
    "guestFilters": {} as Record<string, string>,
  },
  "body-checking": {
    "description":
      "Retained body reuse, interface invalidation, relocation and failed-revision recovery.",
    "native": [
      "reuse.body_check_cache_tests.test.body check cache copied owners survive allocation failures and unchanged revisions",
      "reuse.body_check_cache_tests.test.body check cache ownership survives all allocation failures",
      "reuse.body_check_cache_tests.test.body check cache relocates generic principal binders and independently specializes consumers",
      "reuse.body_check_cache_tests.test.body check cache relocates symbolic callback effects without closing them",
      "reuse.body_check_cache_tests.test.body check cache consumes selected evidence and revokes candidate interface or presence edits",
      "reuse.body_check_cache_tests.test.body check cache static operation calls reject retargeted imported aliases through OOM",
      "reuse.body_check_cache_tests.test.body check cache opaque storage roles revoke scalar to reference consumers",
      "reuse.body_check_cache_tests.test.body check cache user operation rows reject unknown ambiguous and malformed catalog authority",
    ],
    "guests": [
      "zig-native/tests/body_check_cache.test.ts",
    ],
    "guestFilters": {
      "zig-native/tests/body_check_cache.test.ts":
        "body checker reuse relocates and follows executable edits through rejected revisions",
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
