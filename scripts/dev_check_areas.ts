/** Explicit regression families. A development pass never qualifies the full tree. */
export const devCheckAreas = {
  "tasks": {
    description:
      "Task region inference, affine handles, capture transfer and portable authority.",
    native: [
      "parse.parser_tests.test.spark syntax leaves task region selection to checking",
      "parse.parser_tests.test.spark and receive lower to checked task operations with bounded syntax",
      "check.task_check_tests.test.spark and receive use the checked explicit task scope",
      "check.task_check_tests.test.spark region checking preserves exact scope owners under shadowing through OOM",
      "check.task_check_tests.test.ordinary task scope wrappers preserve fresh regions and reject escaping results through OOM",
      "check.task_check_tests.test.task collection checks stored receiver tuples and preserves tuple payloads",
      "check.task_check_tests.test.spawn wrappers validate each actual action and preserve explicit group identity",
      "check.task_check_tests.test.structured task checking rejects escaped groups and consumed handles",
      "check.task_check_tests.test.structured tasks reject children returning group scoped callbacks and packages through OOM",
      "check.task_check_tests.test.structured task checking transfers unique captures and rejects ordinary Foreign contracts",
      "check.task_backend_tests.test.structured task backend owns replay retained helpers and every failed allocation",
      "check.task_backend_tests.test.task scope wrapper authority requires its exact callback body",
      "check.task_backend_tests.test.task collect validates every result field before emission through allocation failures",
      "check.task_backend_tests.test.spawn helper partial calls retain actual capture ownership and reject forged contracts through OOM",
      "check.task_backend_tests.test.generic tuple receive preserves a complete task lifetime graph",
      "check.task_backend_tests.test.portable task capture authority encloses the destination rather than only the spawn site",
      "check.scoped_effect_backend_tests.test.task join wrapper contract requires the exact checked join body",
    ],
    guests: [
      "compiler/task_runtime.test.ts",
      "zig-native/tests/task_surface_execution.test.ts",
      "zig-native/tests/allocation_project_execution.test.ts",
      "zig-native/tests/task_execution.test.ts",
    ],
    guestFilters: {} as Record<string, string>,
  },
  "numeric-aggregates": {
    description:
      "Numeric call adapters, physical layouts, immutable snapshots and ownership.",
    native: [
      "check.core_proof_tests.test.numeric proof prepared associated bodies retain reusable code when ordinary facts already admit the check",
      "backend.numeric_rows.test.numeric row plans preserve physical paths and reject references and excessive depth",
      "backend.numeric_rows.test.numeric row cache owns positive and declined plans through every allocation failure",
      "backend.collection_tests.test.nested numeric collection rows preserve frozen evidence through emission and complete OOM",
      "backend.collection_tests.test.numeric nominal adapters preserve frozen Core and types through emission allocation failure",
      "backend.packed_layout.test.production packed arrays require complete flat scalar evidence",
      "backend.packed_layout.test.packed row plans flatten checked tuples and reject every reference representation",
      "backend.wasm_inline.test.direct callable adapter to scalar record reader exposes caller allocation to scalar replacement",
    ],
    guests: [
      "compiler/cleanup_data.test.ts",
      "zig-native/tests/structural_host_cleanup_execution.test.ts",
      "zig-native/tests/packed_rows_execution.test.ts",
      "zig-native/tests/packed_rows_revision.test.ts",
      "zig-native/tests/numeric_aggregates_execution.test.ts",
      "zig-native/tests/allocation_cost_matrix.test.ts",
      "zig-native/tests/scalar_record_reader_execution.test.ts",
      "zig-native/tests/record_payload_execution.test.ts",
    ],
    guestFilters: {} as Record<string, string>,
  },
  "static-sharing": {
    description:
      "Static aggregate sharing, retained replay, admission and fault-policy laws.",
    native: [
      "reuse.principal_input_tests.test.checked requirement observations retain transitive headers through body edits and allocation failures",
      "reuse.principal_type_graph.test.principal graph temporary buffers preserve nested aliases across stack heap boundaries and OOM",
      "reuse.principal_reuse_gate_tests.test.checked requirement interfaces reject changed producer flags requirement kinds and diagnostic positions",
      "check.effects_tests.test.row rebuilding shares immutable borrowed spans across growth rollback and allocation failures",
      "reuse.zig_project_frames_tests.test.segmented project replies preserve binary framing and reject total size before publication",
      "eval.scheme_membership.test.large scheme memberships preserve owner identity duplicates bounds and allocation failures",
      "backend.optimized_bodies_tests.test.encoded body storage caps allocated capacity as well as payload bytes",
      "backend.optimized_bodies_tests.test.encoded body reuse preserves changed physical indexes globals imports and allocation failures",
      "backend.optimized_bodies_tests.test.retained ownership verdicts require exact helper roles and fresh final bodies",
      "backend.optimized_bodies_tests.test.optimized bodies survive unrelated edits and keep immutable owned results",
      "backend.optimized_bodies_tests.test.optimizer captures above the generic query record limit remain sealed and reuse exact bodies",
      "reuse.source_value_template_tests.test.completed specialization query ordered bucket and warmed plan distinguish same-source concrete captures under every allocation failure",
      "runtime.session_heap.test.freed blocks return to their class and are reused before any new slab",
      "reuse.frontend_graph_correspondence.test.frontend relocation principal correspondence owns injective variables and budget declines",
      "reuse.frontend_graph_correspondence.test.frontend constructor correspondence accepts distinct storage sharing and rejects changed identities",
      "check.types.test.operation chains intern exactly the oldest equal operation through rollback writes and allocation failures",
      "check.types.test.operation argument shapes preserve structural equality physical edits rollback saturation and allocation failures",
      "check.types.test.closed equality visits shared certified DAG pairs without accepting open or cyclic graphs",
      "check.types.test.wide equality preserves reordered fields duplicate effect multiplicities and open arguments through OOM",
      "check.solver_worklist.test.watch frontier deduplicates shared DAGs without losing their unresolved variable",
      "check.solver_worklist.test.variable worklist coalesces writes preserves source rounds and revokes rollback watches",
      "check.solver_worklist.test.variable worklist watches future clocks physical edits and saturated generations",
      "check.solver_worklist.test.variable worklist bounds broad frontiers and recycles refreshed watch storage",
      "check.solver_worklist.test.variable worklist watches symbolic operation arguments scoped payloads and associated projections",
      "check.solver_worklist.test.variable worklist watches capability parameter and operation instance binder edges",
      "eval.semantic_evidence_import.test.private semantic evidence remaps nominal records aliases and repeated effect labels with atomic owner staging",
      "eval.semantic_evidence_import.test.private existential recipes preserve owned lexical binders through transfer and every allocation failure",
      "eval.semantic_evidence_import.test.constant semantic graph transport rejects hidden scope identities and instanced rows through OOM",
      "reuse.artifact_import_tests.test.artifact import allocation failures preserve the old capture and every earlier current success",
      "reuse.artifact_import_tests.test.artifact imports decline malformed identity fresh producers changed bodies and physical catalog movement",
      "eval.core_eval.test.lexical row scope index preserves unrelated binders and imports appended during sharing through OOM",
      "eval.core_eval.test.principal source containment owns nested closures and local reads with bounded allocation failure cleanup",
      "eval.core_eval.test.Session unit lookup preserves dense implicit sparse and duplicate first owner identities through OOM",
      "reuse.principal_reuse_gate_tests.test.call identity follows unique owned declaration names across source movement without admitting changed bodies",
      "reuse.principal_reuse_gate_tests.test.declaration projection workspace isolates declined scans generation rollover and allocation failure",
      "reuse.principal_reuse_gate_tests.test.shifted declaration origins preserve exact relative bodies and revoke changed payloads",
      "reuse.principal_reuse_gate_tests.test.relative declaration projection preserves captures and rejects inconsistent positions through OOM",
      "reuse.principal_reuse_gate_tests.test.declaration principal projection checks call arguments record destinations tags and binding metadata",
      "check.types.test.closed row certificates preserve depth history physical edits instances and saturation through OOM",
      "check.types.test.variable scratch preserves ordered answers history physical writes and heap fallback through every allocation failure",
      "check.effects_tests.test.generated row histories match sequential replacement at every cursor",
      "check.effects_tests.test.effect resolution observes one ordered clock including gaps for type writes",
      "check.effects_tests.test.effect row prefixes follow appended tails and revoke on rollback recycled IDs and saturated epochs",
      "check.types.test.operation row normalization preserves unresolved arguments histories depth rollback and saturated epochs through OOM",
      "reuse.principal_archive_tests.test.portable principal archives validate envelopes typed sections ordinals and graphs before exposure",
      "reuse.principal_archive_tests.test.implementation checkpoints reconstruct selected proofs after source owners die and equations change",
      "reuse.principal_archive_tests.test.portable principal results own inferred types and effect rows through restarts invalid inputs and allocation failures",
      "reuse.principal_archive_tests.test.portable semantic checkpoints reject source settings and malformed semantic graph candidates",
      "reuse.principal_archive_tests.test.portable semantic checkpoints outlive source owners and preserve inference through allocation failures",
      "reuse.principal_archive_tests.test.portable principal query saturation declines optional archive reuse",
      "reuse.principal_archive_tests.test.portable principal query duplicates retain oldest valid proof priority",
      "reuse.principal_input_tests.test.principal input replay owns read keys and preserves the prior capture at every allocation failure",
      "reuse.principal_input_tests.test.principal nominal replay requires exact memo inputs and publishes atomically",
      "reuse.principal_input_tests.test.principal nominal inputs retain absence negatives and final publications under allocation failures",
      "reuse.principal_input_tests.test.principal input recording bounds conflicting reads and frees every failing allocation",
      "reuse.principal_input_tests.test.principal call input recording preserves absence internal publications conflicts and allocation ownership",
      "reuse.principal_input_tests.test.principal nonempty projected rows own translated results through edits reverts and allocation failures",
      "reuse.artifact_import_tests.test.artifact import maps producer and symbol namespaces and distinct State captures after generator teardown",
      "eval.core_eval_tests.test.lexical keys distinguish pending demand creation and decline changed cached memo state",
      "eval.core_eval_tests.test.canonical selected proofs use current captures and exact equality under forced collisions",
      "reuse.principal_input_tests.test.principal anonymous module observations own their inputs and permit duplicates at the observation bound through OOM",
      "reuse.principal_input_tests.test.checked interface observations preserve principal inference while staged body edits execute current code through OOM",
      "reuse.principal_input_tests.test.principal observed sources retain memo outputs across unrelated body edits and reject consumed source edits",
      "reuse.principal_input_tests.test.principal summary replay requires exact inputs and results without publishing global certificates through OOM",
      "reuse.principal_input_tests.test.principal input certificate preserves absent scalar reads and rejects executed values",
      "reuse.principal_input_tests.test.principal input image rejects changed types collection identities and effects",
      "reuse.principal_input_tests.test.principal input image does not hide staged errors or change the last good capture",
      "reuse.principal_input_tests.test.principal input image retains inference while current staged literals change output",
      "backend.wasm.test.arena allocation collection and static roots release every failed compiler allocation",
      "reuse.principal_input_tests.test.principal input replay omits declined memo outputs while owning accepted proofs through every allocation failure",
      "reuse.principal_input_tests.test.principal input replay restores nominal and closed call publications across edits errors and recovery",
      "backend.layout.test.layout cache identity and semantic conversion preserve exact closed effect rows",
      "backend.layout.test.solved representation projection owns partial shapes without certifying open effects",
      "backend.wasm_sroa.test.scalar replacement owns scratch and output through every failed allocation",
      "backend.aggregate_constant_tests.test.retained callers replay aggregate constants with fresh-identical data through allocation failures",
      "backend.aggregate_constant_tests.test.aggregate constants with changed values aliases or nominal payloads rebuild their callers",
      "backend.aggregate_constant_tests.test.admission skips every aggregate child range of one caller and keeps the records between them",
      "reuse.retained_candidate_tests.test.direct static capture materialization preserves fresh edit revert bytes and scalar evaluated query reuse",
      "reuse.retained_candidate_tests.test.direct static capture materialization releases failed candidates without changing retained source owners",
      "reuse.artifact_backend_tests.test.artifact replay preserves codegen tiers and physical sharing without merging semantic jobs",
      "reuse.artifact_emitter_tests.test.instruction journal runs preserve owner clock and resource boundaries through OOM",
      "reuse.artifact_emitter_tests.test.owned typed emission reconstruction survives original module destruction and shifted resources",
      "reuse.artifact_emitter_tests.test.capture and replay allocations leave owners releasable on every failure",
      "reuse.artifact_operation_admission_tests.test.instruction run admission rejects invalid spans and clock overlap before publication",
      "backend.persistent_roots_tests.test.capture-free descriptor addresses relocate through retained portable replay and OOM",
      "backend.persistent_roots_tests.test.evaluated named calls preserve exact captures source reads replay checkpoint and complete OOM cleanup",
      "backend.persistent_roots_tests.test.static scalar list seeds preserve word roles through growth replay and complete OOM cleanup",
      "backend.persistent_roots_tests.test.static captured value graphs admit executable closure replay independently of principal mappings",
      "backend.persistent_roots_tests.test.evaluated named calls preserve canonical constructor captures through replay and OOM",
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
      "zig-native/tests/arena.test.ts",
      "zig-native/tests/principal_replay_execution.test.ts",
      "zig-native/tests/summary_job_principal_reuse.test.ts",
      "zig-native/tests/evaluated_calls_execution.test.ts",
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
      "parse.parser_tests.test.default dollar groups application while explicit fixities retain operator dispatch through OOM",
      "check.task_check_tests.test.dollar application preserves task scope and ownership through OOM",
      "reuse.retained_revision.test.unchanged output owns allocation explanations across teardown and OOM",
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
      "zig-native/tests/task_surface_execution.test.ts",
      "zig-native/tests/dollar_application_execution.test.ts",
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
      "check.effects_tests.test.effect row prefixes follow appended tails and revoke on rollback recycled IDs and saturated epochs",
      "check.check_contract_tests.test.ordinary effect rows preserve associated work for actual projections",
      "check.check_contract_tests.test.associated exhaustion reports its actual remaining work allowance",
      "check.check_contract_tests.test.configured associated work can exceed the legacy million step cap",
    ],
    "guests": [
      "zig-native/tests/type_identity_execution.test.ts",
      "zig-native/tests/symbolic_effect_rows.test.ts",
      "zig-native/tests/inference_budget_config.test.ts",
    ],
    "guestFilters": {} as Record<string, string>,
  },
  "body-checking": {
    "description":
      "Retained body reuse, interface invalidation, relocation and failed-revision recovery.",
    "native": [
      "reuse.dependency_interface_tests.test.text literal capability shapes agree with scalar arrays at immutable admission",
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
      "zig-native/tests/runtime_text_execution.test.ts",
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
