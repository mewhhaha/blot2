/** Explicit regression families. A development pass never qualifies the full tree. */
export const devCheckAreas = {
  "direct": {
    description:
      "Direct code generation through the project server: executed fixtures, the wire protocol and client, frontend scheduling and allocation-fault laws.",
    native: [
      "reuse.source_input_tests.test.source lowering validates static declarations and scopes without inferring prelude expressions",
      "parse.source_operators_tests.test.source fixity uses explicit declarations and preserves frozen lowering error order",
      "parse.source_operators_tests.test.source fixity validation releases every failed allocation for successful and rejected graphs",
      "check.numeric_phase_tests.test.numeric source failures preserve actual frozen lexical declaration primitive and pattern precedence",
      "check.numeric_phase_tests.test.numeric diagnostic-only publication releases all failed allocations and static trial conversions",
      "check.package_contracts_tests.test.compile scoped source proofs reuse completed bodies without lending caller effect authority",
      "reuse.declaration_demand.test.declaration demand follows namespace named reexports and ordinary helpers through allocation failures",
      "reuse.declaration_demand.test.declaration demand preserves named aliases prelude producers and lexical shadowing",
      "reuse.declaration_demand.test.declaration demand retains operator associated and implementation roots",
      "reuse.declaration_demand.test.declaration demand omits unreachable const let and tagged initializers",
      "reuse.declaration_demand.test.declaration demand falls back for escaped namespace authority and declines compiled owners",
      "check.scheme_dependencies.test.scheme dependency watches preserve type effect future and rollback histories through OOM",
      "check.ordered_membership.test.ordered scheme membership preserves sparse IDs duplicates and append order through OOM",
      "reuse.parallel_check_tests.test.parallel module checking preserves serial Core and counters with independent solver ownership",
      "reuse.parallel_check_tests.test.immutable imported sharing summaries preserve fresh quantifiers callback rows and Core through OOM",
      "reuse.project_check.test.parallel module forwarding charges the combined project budget in serial order",
      "reuse.parallel_check_tests.test.parallel module rejection replays serial diagnostic order",
      "reuse.parallel_check_tests.test.parallel module workers release joined results and solver allocators across concurrent allocation failures",
      "reuse.semantic_query_table.test.owned query table preserves first valid order across forced collisions and allocation failures",
      "reuse.semantic_query_table.test.owned query builder cannot publish unknown observations and saturation remains bounded",
      "reuse.semantic_query_table.test.owned query capacity is measured and bounded and preparation binds one candidate",
      "reuse.body_check_cache.test.lazy closed row paths preserve sparse dense and shared certificate bytes without allocations",
      "reuse.body_check_cache.test.lazy closed row paths retain every role and certificate sorting across live and frozen sources",
      "reuse.body_check_cache.test.lazy closed row paths preserve work depth path capacity and missing-field rejection boundaries",
      "check.package_contracts_tests.test.ordinary inferred predicate schemes coexist with annotated universal bodies through OOM",
      "check.check_result_tests.test.written result requirements preserve destination input aliases contracts and local polymorphism through OOM",
      "check.check_result_tests.test.written result requirements reject missing coverage wrong members malformed arity and incompatible rows through OOM",
      "reuse.principal_type_graph.test.principal graph temporary buffers preserve nested aliases across stack heap boundaries and OOM",
      "check.effects_tests.test.row rebuilding shares immutable borrowed spans across growth rollback and allocation failures",
      "reuse.zig_project_frames_tests.test.segmented project replies preserve binary framing and reject total size before publication",
      "reuse.frontend_graph_correspondence.test.frontend relocation principal correspondence owns injective variables and budget declines",
      "reuse.frontend_graph_correspondence.test.frontend constructor correspondence accepts distinct storage sharing and rejects changed identities",
      "check.types.test.operation chains intern exactly the oldest equal operation through rollback writes and allocation failures",
      "check.types.test.operation argument shapes preserve structural equality physical edits rollback saturation and allocation failures",
      "check.types.test.closed equality visits shared certified DAG pairs without accepting open or cyclic graphs",
      "check.types.test.recursive resolution visits shared open function and product graphs once",
      "check.types.test.recursive resolution preserves open histories depth rollback recycled IDs and saturation through OOM",
      "check.types.test.known closed evidence declines revoked open and saturated certificates through OOM",
      "check.check_shared_scheme_tests.test.closed array locals bypass unrelated field generalization with old-path parity through OOM",
      "check.check_shared_scheme_tests.test.closed array locals admit all array modes and closed callbacks while open elements retain generalization",
      "check.check_shared_scheme_tests.test.closed array locals retain explicit clauses and implicit contract selection or rejection",
      "check.types.test.unchanged covariance preserves shared data graphs without creating type nodes",
      "check.types.test.covariance data sharing preserves independent callback rows history rollback and allocation failures",
      "check.check_shared_scheme_tests.test.unused generic pair helpers keep checker type graphs bounded",
      "check.types.test.wide equality preserves reordered fields duplicate effect multiplicities and open arguments through OOM",
      "check.solver_worklist.test.watch frontier deduplicates shared DAGs without losing their unresolved variable",
      "check.solver_worklist.test.variable worklist coalesces writes preserves source rounds and revokes rollback watches",
      "check.solver_worklist.test.variable worklist watches future clocks physical edits and saturated generations",
      "check.solver_worklist.test.variable worklist bounds broad frontiers and recycles refreshed watch storage",
      "check.solver_worklist.test.variable worklist watches symbolic operation arguments scoped payloads and associated projections",
      "check.solver_worklist.test.variable worklist watches capability parameter and operation instance binder edges",
      "check.package_row_facts.test.lexical row facts preserve sparse high identities collisions snapshots and saturation",
      "check.types.test.closed row certificates preserve depth history physical edits instances and saturation through OOM",
      "check.types.test.variable scratch preserves ordered answers history physical writes and heap fallback through every allocation failure",
      "check.effects_tests.test.generated row histories match sequential replacement at every cursor",
      "check.effects_tests.test.effect resolution observes one ordered clock including gaps for type writes",
      "check.effects_tests.test.effect row prefixes follow appended tails and revoke on rollback recycled IDs and saturated epochs",
      "check.types.test.operation row normalization preserves unresolved arguments histories depth rollback and saturated epochs through OOM",
      "allocation_failures.test.sampled allocation failures check bounded indices while full mode stays exhaustive",
      "allocation_failures.test.sampled allocation failures reject swallowed faults and propagate scenario failures",
      "reuse.zig_project_frames_tests.test.Zig project framing owns requests and distinguishes boundary EOF from truncation",
      "reuse.zig_project_frames_tests.test.Zig project frame limits count both payload and header before allocation",
      "reuse.zig_project_frames_tests.test.Zig project response framing carries literal binary bytes",
      "reuse.zig_project_frames_tests.test.source overlay framing owns metadata and payload and rejects truncated binary data",
      "reuse.source_overlay_tests.test.source overlays own caller bytes and release every injected allocation failure",
      "reuse.source_overlay_tests.test.source overlays normalize virtual parents symlink aliases and duplicate keys",
      "reuse.zig_project_server.test.source overlay ranges partition payload before allocating or preparing a revision",
      "reuse.zig_project_server.test.project open requires the exact public protocol version",
      "check.scalar_ops.test.U32 folding matches the guest's wrapping and shift semantics",
    ],
    guests: [
      "tests/guest/direct_backend_execution.test.ts",
      "tests/guest/entry_execution.test.ts",
      "tests/guest/array_execution.test.ts",
      "tests/guest/aggregate_execution.test.ts",
      "tests/guest/update_execution.test.ts",
      "tests/guest/loop_execution.test.ts",
      "tests/guest/collection_execution.test.ts",
      "tests/guest/cli_profile.test.ts",
      "tests/guest/compile_budget.test.ts",
      "tests/guest/worker_determinism.test.ts",
      "tests/guest/native_asset_protocol.test.ts",
      "tests/guest/zig_project_protocol.test.ts",
      "tests/guest/zig_project_client.test.ts",
    ],
    guestFilters: {
      "tests/guest/zig_project_client.test.ts":
        "Zig project client queues revisions and preserves entry edit/error/missing/correction bytes",
    } as Record<string, string>,
  },
  "project": {
    description:
      "Project loading, dependency bundles, editor completion and native assets.",
    native: [
      "assets.native_asset_readers.test.native assets infer shared records and release success and issue allocation failures",
      "assets.native_asset_readers.test.native assets preserve last-wins JSON and exact tuples and float spelling",
      "assets.native_asset_readers.test.native assets catalog suffixes indexes and text codepoints",
      "assets.native_asset_readers.test.native assets tunables round bounds preserve tiny steps and replace unsupported codepoints",
      "assets.native_asset_readers.test.native assets reject malformed numbers identifiers Unicode and catalog collisions",
      "assets.native_asset_readers.test.native assets bound JSON depth before recursive graph construction",
      "assets.native_asset_readers.test.native asset diagnostics preserve UTF-8 when bounding long field names",
      "assets.native_asset_wgsl.test.WGSL reflection folds scalar constants and resolves Parameters aliases",
      "assets.native_asset_wgsl.test.WGSL syntax validates bodies and rejects malformed reflected declarations",
      "assets.native_asset_wgsl.test.WGSL generated ownership survives every allocation failure",
      "assets.native_asset_wgsl.test.WGSL scalar and vector evaluation preserves the pinned reflector ABI",
      "assets.native_asset_wgsl.test.WGSL aliases comments attributes and structured statements remain syntax",
      "assets.native_asset_wgsl.test.WGSL limits and invalid generated identifiers reject with owned diagnostics",
      "assets.native_asset_wgsl.test.WGSL rejected ownership survives every allocation failure",
      "assets.native_asset_wgsl.test.WGSL shared constant graphs cannot multiply reflection work without bound",
      "assets.native_assets.test.native asset rejection preserves exact captured inputs and parse reuse through allocation failure",
      "assets.native_assets.test.native content media types have the same bounded wire admission as the host",
      "assets.native_assets.test.native asset names and content handles use host UTF16 lexical order",
      "reuse.module_relink_tests.test.mapped record names unify semantically across opposite physical field orders",
      "reuse.editor_completion.test.editor completion query owns answers and preserves semantic visibility through every allocation failure",
      "reuse.editor_completion.test.editor completion follows named aliases namespace boundaries fields constructors and types",
      "reuse.editor_completion.test.module abstraction completion keeps source origins without exposing constructors or fields",
      "reuse.editor_completion.test.completion metadata limits preserve one limit diagnostic with allocation-safe ownership",
      "reuse.editor_completion.test.editor lexical fallback owns only well-formed binders before the first error under allocation failure",
      "reuse.editor_completion.test.editor ignores comments and strings even when the surrounding source is malformed",
      "reuse.editor_completion.test.editor text-token queries still enforce opened project membership",
      "reuse.editor_completion.test.editor rebinding aliases retain their actual names and old types under allocation failure",
      "reuse.completion_probe.test.completion probe keeps receiver and identifier suffix while mapping later diagnostics",
      "reuse.completion_probe.test.completion probe ignores text tokens and rejects split UTF8 offsets",
      "reuse.completion_probe.test.completion probe repairs bounded argument EOF and replaces an existing hole whole",
      "reuse.completion_probe.test.completion probe repairs exactly eight EOF delimiters with allocation-safe scratch",
      "reuse.completion_fit.test.completion isolated fitting preserves live substitutions through allocation failure",
      "reuse.completion_fit.test.completion fitting preserves rigid aliases and requires enclosing evidence",
      "reuse.completion_check_tests.test.completion private expression keeps contextual types shadowing and allocation ownership",
      "reuse.completion_check_tests.test.completion private members and selectors retain receiver and expected arrow",
      "reuse.completion_check_tests.test.completion private fitting follows actual declared generic requirements",
      "reuse.completion_check_tests.test.completion private item scope exceeds the display graph and keeps the latest binder",
      "reuse.completion_check_tests.test.completion private project shares inference budget without evaluating initializers or requiring entries",
      "reuse.revision_inputs.test.restart cache: persisted input records round-trip successful observations and decline failed ones",
      "reuse.dependency_import_resolution_tests.test.cached import requests reject file symlink retarget and admit revert before fresh entry publication under every allocation failure",
      "reuse.dependency_import_resolution_tests.test.cached requests preserve nested relative directory percent decoding and alias resolution",
      "reuse.dependency_import_resolution_tests.test.cached raw requests retain duplicate edges and unit relocation independently from symbol IDs",
      "reuse.dependency_import_resolution_tests.test.cached request semantic bounds reject missing correspondence malformed bytes and false implicit prelude",
      "reuse.dependency_import_resolution_tests.test.cached implicit prelude edges remain separate from written dependency requests and bootstrap imports",
      "reuse.dependency_closure_tests.test.whole diamond closure retains producers, aliases, rows and ordered imports with dense units",
      "reuse.dependency_closure_tests.test.closure task context absence never survives a changed binding or module descriptor",
      "reuse.dependency_closure_tests.test.complete closure freeze and validation clean every failure without changing source principal facts",
      "reuse.dependency_closure_tests.test.decoded owner validation allocation failures preserve the immutable payload",
      "reuse.dependency_closure_tests.test.whole closure decode and numeric relocation publication are atomic through every failure",
      "reuse.dependency_closure_tests.test.checked unit renumbering keeps dense owners and rejects excluded or unknown producers",
      "reuse.dependency_closure_tests.test.closure keys exclude new entry bytes and reject changed dependencies paths settings and topology",
      "reuse.dependency_closure_tests.test.decoded closure rejects dependency cycles excluded entry producers and foreign binding owners",
      "reuse.dependency_closure_tests.test.prelude bootstrap imports remain directed dependencies without an implicit reverse edge",
      "reuse.dependency_closure_tests.test.unpublished named function returned across modules keeps a controlled-flow body freezable",
      "reuse.dependency_closure_tests.test.source record payload declaration order survives prior symbol identities and duplicate fields reject",
      "reuse.dependency_closure_tests.test.principal publication keeps reusable globals and Core retains later-constrained local array facts",
      "reuse.dependency_closure_tests.test.wide unordered source record uniqueness uses one bounded symbol-stamp lane and releases every failed allocation",
      "reuse.dependency_closure_tests.test.genuine global scheme quantifiers stay strict after neutral local publication",
      "reuse.dependency_closure_tests.test.entry-only project freezes an owned empty closure without treating its names as dependency source",
      "reuse.dependency_interface_tests.test.scoped public claim wire rejects unknown values after the admitted maximum",
      "reuse.dependency_interface_tests.test.capability import keeps producer graph ordinal distinct from relocated external target",
      "reuse.dependency_interface_tests.test.principal reference bounds preserve quantified row callback producers",
      "reuse.dependency_format_tests.test.dependency invocation wire keeps ordinary payloads compact and validates ordered arguments",
      "reuse.dependency_format_tests.test.dependency type wire omits transient solver certificates and owns decoded semantic fields",
      "reuse.dependency_format_tests.test.dependency header discovery owns untrusted keys and cannot replace final admission",
      "reuse.dependency_format_tests.test.dependency format preserves every frozen Core table of the unmodified standard prelude",
      "reuse.dependency_format_tests.test.dependency format rejects stale keys schema corrupt truncation and resource limits before publishing",
      "reuse.dependency_format_tests.test.dependency format exhausts encode and partial decoded allocation failures without leaking",
      "reuse.dependency_format_tests.test.dependency format validates decoded enum discriminants boolean tags counts and nested partial owners",
      "reuse.dependency_format_tests.test.dependency format integers round-trip at every width and sign through LEB128",
      "reuse.project_check_tests.test.tags on catalog declarations and fixities reject without evaluating tag expressions",
      "reuse.project_check_tests.test.diamond modules publish one principal body and independently copy imported schemes",
      "reuse.project_check_tests.test.same declaration spelling in distinct modules preserves foreign identities",
      "reuse.project_check_tests.test.imported generic constraints reject invalid uses at their own source site",
      "reuse.project_check_tests.test.aliases reject collisions and missing exports including empty namespaces",
      "reuse.project_check_tests.test.all unused module declarations are checked and dependency entries are forbidden",
      "reuse.project_check_tests.test.namespace names do not bypass lexical shadowing after a cached lookup",
      "reuse.project_check_tests.test.source cycles and malformed dependencies cannot publish interfaces",
      "reuse.project_check_tests.test.imported operator targets and product schemes retain checked producer structure",
      "reuse.project_check_tests.test.named fixity resolves lexical targets and symbolic fixity keeps its captured target",
      "reuse.project_check_tests.test.inherited symbolic fixities retain producer identity through local and imported target shadowing",
      "reuse.project_check_tests.test.local symbolic redeclaration replaces inherited capture while named fixity remains lexical",
      "reuse.project_check_tests.test.named imported targets obey aliases and local shadowing at each use",
      "reuse.project_check_tests.test.checked module type ownership survives release of every source and syntax owner",
      "reuse.project_check_tests.test.foreign scheme imports scale with distinct targets rather than uses or aliases",
      "reuse.project_check_tests.test.module interfaces and aliases release every buffer after allocation failure",
      "reuse.project_check_tests.test.imported nominal families and associated schemes preserve structured identity across aliases",
      "reuse.project_check_tests.test.generated monadic progress preserves designated prelude identity through local shadowing",
      "reuse.project_check_tests.test.module abstraction public opaque factories hide constructor and representation",
      "reuse.project_check_tests.test.module abstraction private named imports and associated declarations stay private",
      "reuse.project_check_tests.test.module abstraction selective forwarding preserves type and value producers",
      "reuse.project_check_tests.test.module abstraction public signatures cannot escape private identities",
      "reuse.project_check_tests.test.module abstraction opaque import aliases cannot construct project or coerce",
      "reuse.project_check_tests.test.module abstraction nominal identity ignores unrelated declaration insertion",
      "reuse.project_check_tests.test.module abstraction private helpers remain usable in public factory bodies",
      "reuse.project_check_tests.test.module abstraction distinct producers namespace privacy and reexports cannot bypass access",
      "reuse.project_check_tests.test.module abstraction forwarding retains data constructors effects and contracts",
      "reuse.project_check_tests.test.module abstraction public contracts cannot name private predicates",
      "reuse.project_check_tests.test.unused imported values stay absent while forwarded associated catalogs retain exact schemes",
      "reuse.project_check_tests.test.imported result and callback schemes keep owned quantified relations and numeric target identity",
      "reuse.source_input_tests.test.standalone checker rejects imports before entry semantics and owns every failure",
      "reuse.source_input_tests.test.source input retains imports without loading targets while project mode resolves them",
      "reuse.source_input_tests.test.source input bootstraps the real prelude closure and releases every allocation",
      "reuse.source_input_tests.test.entry syntax precedes prelude semantics and prelude syntax precedes reading entry",
      "reuse.source_input_tests.test.source validation publication cannot carry a typed-body owner or principal value scheme",
      "reuse.source_input_tests.test.source lowering validates static declarations and scopes without inferring prelude expressions",
      "reuse.dependency_cli_tests.test.cache options preserve arbitrary alias order with owned canonical roots and OOM cleanup",
      "reuse.dependency_cli_tests.test.CLI creation and cached consumer release owners at every allocation failure",
      "reuse.dependency_cli_tests.test.CLI declined admission preserves an existing destination and emits teardown-zero metrics",
      "reuse.dependency_publication_tests.test.creation frontend envelopes preserve earlier complete output and match ordinary public evidence",
      "reuse.dependency_publication_tests.test.owned publication code message and canonical purity details outlive all borrowed inputs with OOM",
      "reuse.revision_input_tests.test.revision input invalid resolution is owned and repeated without premature cleanup",
      "reuse.revision_input_tests.test.source validation frozen revision record moves each source owner once and survives every acquisition allocation failure",
      "reuse.revision_input_tests.test.source validation frozen inputs recheck exact bytes ordered settings and failed import observations",
      "reuse.revision_input_tests.test.trivia-only source changes keep tokens and adjacency; layout and adjacency changes do not",
      "reuse.revision_input_tests.test.revision input indexes answer exactly as list scans and survive every allocation failure",
    ],
    guests: [
      "tests/guest/aliases_execution.test.ts",
      "tests/guest/contracts_execution.test.ts",
      "tests/guest/module_abstraction_import_execution.test.ts",
      "tests/host/editor_completion.test.ts",
      "tests/host/native_asset_client.test.ts",
      "tests/host/cli_packages.test.ts",
    ],
    guestFilters: {} as Record<string, string>,
  },
  "function-syntax": {
    description:
      "Function keyword, explicit returns, curried separators and fallthrough rejection.",
    native: [
      "parse.parser_tests.test.named function declarations share curried lambda IR and preserve local entry private and tag metadata",
      "parse.parser_tests.test.named function declarations release parameter and attribute scratch through allocation failures",
      "parse.parser_tests.test.qualified named headers preserve declaration predicates and final result effects through allocation failures",
      "parse.parser_tests.test.local named functions do not consume anonymous function expression statements",
      "parse.parser_tests.test.named functions retain return parameter and identifier diagnostics and recover later declarations",
      "check.check_result_tests.test.named module functions preserve principal inference recursion and ordinary function values",
      "check.check_result_tests.test.qualified named functions and written predicates preserve ordinary value controls through OOM",
      "check.check_result_tests.test.named declaration predicates require a complete written signature and reject missing coverage",
      "check.check_result_tests.test.named function tags preserve every dispatch parameter and written result while allowing new effects through OOM",
      "parse.lexer_tests.test.flat tokens preserve longest matches and source byte spans",
      "parse.parser_tests.test.functions require explicit return and reject whitespace separated parameters",
      "check.check_result_tests.test.explicit function returns cover every path without borrowing nested function or block exits through OOM",
      "parse.parser_tests.test.multi-parameter lambda sugar lowers to a curried chain with the result on the final stage",
      "parse.parser_tests.test.long curried parameter lists release fallback storage through allocation faults",
      "parse.parser_tests.test.return exits a function while break value finishes a do and bare break exits a loop",
      "parse.parser_tests.test.dollar constructors and run staging preserve list arrays and spaced dollar application through OOM",
    ],
    guests: [
      "tests/guest/named_functions_execution.test.ts",
      "tests/host/syntax.test.ts",
      "tests/host/staged_surface.test.ts",
      "tests/guest/boolean_words_execution.test.ts",
      "tests/guest/eager_callbacks_execution.test.ts",
      "tests/guest/explicit_return_execution.test.ts",
      "tests/guest/annotation_arity_execution.test.ts",
    ],
    guestFilters: {} as Record<string, string>,
  },
  "staging-surface": {
    description:
      "Dollar constructors, forced compile-time evaluation and staging purity.",
    native: [
      "parse.parser_tests.test.dollar constructors and run staging preserve list arrays and spaced dollar application through OOM",
      "check.frozen_core_validation_tests.test.run surface validates result shape and isolated purity through allocation failures",
      "check.frozen_core_validation_tests.test.portable typed staging validates complete shapes and rejects forged operands and stage references",
      "check.frozen_core_validation_tests.test.portable typed staging rejects forged pure rows on quoted operations and invoked callbacks",
    ],
    guests: [
      "tests/host/staged_surface.test.ts",
    ],
    guestFilters: {} as Record<string, string>,
  },
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
    ],
    guests: [
      "tests/host/task_runtime.test.ts",
    ],
    guestFilters: {} as Record<string, string>,
  },
  "syntax": {
    description:
      "Lexer/parser structure, recovery, immutable trees and allocation ownership.",
    native: [
      "parse.parser_tests.test.default dollar groups application while explicit fixities retain operator dispatch through OOM",
      "check.task_check_tests.test.dollar application preserves task scope and ownership through OOM",
      "parse.lexer_tests.test.flat tokens preserve longest matches and source byte spans",
      "parse.lexer_tests.test.invalid layout, private markers, strings and Unicode report diagnostics",
      "parse.lexer_tests.test.all lexer allocation failures release tokens, trivia and scratch",
      "parse.parser_tests.test.surface syntax preserves nested blocks patterns loops and handlers",
      "parse.parser_tests.test.malformed syntax reports diagnostics and preserves later declarations",
      "parse.parser_tests.test.opaque declarations use the is kind position and reject the retired prefix",
      "parse.parser_tests.test.parser allocation failures release trees symbols and scratch stacks",
      "parse.parser_adjacent_call_tests.test.retained adjacent-call tree stays immutable across another parse and teardown",
      "parse.syntax_diagnostics_tests.test.UTF16 publication counts supplementary scalars and declines split byte boundaries",
      "parse.source_operators_tests.test.source fixity validation releases every failed allocation for successful and rejected graphs",
    ],
    guests: [
      "tests/host/syntax.test.ts",
      "tests/guest/dollar_application_execution.test.ts",
      "tests/guest/annotation_arity_execution.test.ts",
    ],
    guestFilters: {} as Record<string, string>,
  },
  "type-effects": {
    description:
      "Type identity, effect rollback, owned data and physical encoding.",
    native: [
      "check.package_contracts_tests.test.compile scoped source proofs reuse completed bodies without lending caller effect authority",
      "reuse.parallel_check_tests.test.parallel module checking preserves serial Core and counters with independent solver ownership",
      "reuse.parallel_check_tests.test.parallel worker trace diagnostics are bounded and preserve serial Core and rejection diagnostics",
      "reuse.parallel_check_tests.test.unequal independent module bodies preserve serial Core and diagnostic order under parallel dispatch",
      "reuse.parallel_check_tests.test.parallel module workers release joined results and solver allocators across concurrent allocation failures",
      "check.frozen_core_validation_tests.test.Core validation batch preserves ordinary graph source bounds and forbidden owner checks through OOM",
      "check.frozen_core_validation_tests.test.Core validation batch keeps spawn calls captures malformed wrappers and standalone fallback",
      "check.frozen_core_validation_tests.test.Core task batch recomputes exact changed entry context instead of retaining absence",
      "check.package_contracts_tests.test.validation bounds receipts retain exact context and never publish failed checks",
      "check.package_contracts_tests.test.validation bounds receipts scale past 128 owners and retain exact contexts through OOM",
      "check.package_core.test.source goal header rejection preserves epochs while failed type proofs still roll back",
      "reuse.dependency_closure_tests.test.closure task context absence never survives a changed binding or module descriptor",
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
    guests: [
      "tests/guest/completed_plain_execution.test.ts",
      "tests/guest/storage_nominal_parameter_fields_execution.test.ts",
      "tests/guest/storage_wordless_aggregate_execution.test.ts",
      "tests/guest/storage_literal_projection_execution.test.ts",
      "tests/guest/storage_inline_registers_execution.test.ts",
      "tests/guest/storage_globals_execution.test.ts",
      "tests/guest/storage_host_execution.test.ts",
      "tests/guest/typed_closure_execution.test.ts",
      "tests/guest/storage_call_graph_execution.test.ts",
      "tests/guest/scoped_loop_refinement_execution.test.ts",
      "tests/guest/symbolic_effect_rows.test.ts",
      "tests/guest/inference_budget_config.test.ts",
      "tests/guest/parallel_profile_execution.test.ts",
    ],
    guestFilters: {} as Record<string, string>,
  },
  "body-checking": {
    description:
      "Retained body reuse, interface invalidation, relocation and failed-revision recovery.",
    native: [
      "check.check_effect_tests.test.unused wide imported schemes admit no type graph or Core certificate",
      "check.check_effect_tests.test.lazy qualified and unqualified imports share one scheme and independent instantiations through OOM",
      "check.check_effect_tests.test.lazy imported shared callees retain relocated predicate evidence",
      "reuse.project_check_tests.test.unused imported values stay absent while forwarded associated catalogs retain exact schemes",
      "check.check_shared_scheme_tests.test.predicate-free schemes preserve independent types and callback rows without sharing summaries through OOM",
      "check.check_shared_scheme_tests.test.recursive frontend scheduling keeps forward chains independent of native and syntax depth",
      "check.check_shared_scheme_tests.test.recursive frontend dependency discovery preserves local and pattern shadowing",
      "check.check_shared_scheme_tests.test.recursive frontend discovery restores names after a forever suite",
      "check.check_shared_scheme_tests.test.recursive frontend scheduled allocation failures release frames and staged diagnostics",
      "check.check_shared_scheme_tests.test.recursive frontend scheduled child diagnostics keep their original reference order",
      "check.check_shared_scheme_tests.test.recursive frontend waits for the preferred left dispatch before right fallback",
      "check.check_shared_scheme_tests.test.recursive frontend retries publish only owned final scheme predicates",
      "check.check_shared_scheme_tests.test.recursive frontend queued method preserves declaration and call diagnostics",
      "check.check_shared_scheme_tests.test.late selected recursive components keep their placeholder until all schemes publish",
      "check.check_shared_scheme_tests.test.frontend recursive component transition limit bounds unresolved selected work",
      "check.check_shared_scheme_tests.test.pending effect operations wait for their types instead of rescanning",
      "check.check_shared_scheme_tests.test.pending callback selections wait for their unknown receivers",
      "check.check_shared_scheme_tests.test.a deep diamond of unannotated generic functions checks with bounded obligations",
      "check.check_shared_scheme_tests.test.a generic chain appends obligations linearly",
      "check.check_shared_scheme_tests.test.inferred operation wrappers retain their written callee latent rows",
      "check.check_shared_scheme_tests.test.left operand dispatch wins through a shared callee",
      "check.check_shared_scheme_tests.test.shared written predicates keep computed operands monomorphic and unrelated parameters fresh",
      "check.check_shared_scheme_tests.test.shared written requirements retain the local computation reference origin",
      "check.check_shared_scheme_tests.test.a conflicting operand reports the same outcome through a shared callee",
      "check.check_shared_scheme_tests.test.return type polymorphism preserves independent expected results through shared uses",
      "check.check_shared_scheme_tests.test.result directed principal diamonds keep frontend work bounded by distinct bodies",
      "check.check_shared_scheme_tests.test.mutually recursive generic functions keep flat obligations",
      "check.check_shared_scheme_tests.test.higher order callees are solved at their use",
      "check.check_shared_scheme_tests.test.allocation failures during shared use resolution release every owner",
      "check.check_shared_scheme_tests.test.a lexical closure over outer variables expands its shared callee in place",
      "phase_profile.test.project checking counters merge modules and exclude backend checker invocations",
      "reuse.body_check_cache_tests.test.body check cache copied owners survive allocation failures and unchanged revisions",
      "reuse.body_check_cache_tests.test.body check cache user operation rows reject unknown ambiguous and malformed catalog authority",
    ],
    guests: [
      "tests/guest/associated_execution.test.ts",
      "tests/host/type_diagnostics.test.ts",
    ],
    guestFilters: {} as Record<string, string>,
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
  // Deno emits filtered-out cases and cases ignored in source as <skipped/>.
  // A filtered run must pass every requested name; an unfiltered run may
  // contain ignored cases, but each file must still pass one.
  const skipped = (test: RegExpMatchArray) => /<skipped\b/.test(test[2] ?? "");
  const selected = expectedNames
    ? cases.filter((test) => expectedNames.includes(attributes(test[1]).name))
    : cases.filter((test) => !skipped(test));
  if (
    !selected.length ||
    selected.some((test) =>
      /<(?:failure|error|skipped)\b/.test(test[2] ?? "")
    ) ||
    cases.some((test) => !selected.includes(test) && !skipped(test))
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
