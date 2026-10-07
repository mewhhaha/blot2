//! Handwritten HM checker. Source bodies produce principal schemes; uses get
//! fresh type variables and their own numeric obligations. Every declaration is
//! checked, including declarations not reachable from an entrypoint.
const std = @import("std");
const ast = @import("ast.zig");
const symbols = @import("symbols.zig");
const T = @import("types.zig");
const P = @import("parameter_patterns.zig");
const loop_targets = @import("loop_targets.zig");
const source_operators = @import("source_operators.zig");
const Allocator = std.mem.Allocator;
const F = @import("frozen_types.zig");
const PI = @import("principal_interface.zig");
pub const BindingId = u32;
/// Symbolic imports retain their producer; named targets resolve lexically.
pub const ImportedFixity = struct { operator: symbols.Symbol, target: symbols.Symbol, named: bool, external: ?ExternalTarget = null, origin: ast.Id = 0 };
pub const ModuleOrigins = struct {
    context: ?*const anyopaque = null,
    lookup: ?*const fn (?*const anyopaque, Allocator, u32) T.Error![]u8 = null,
    pub fn name(self: ModuleOrigins, allocator: Allocator, unit: u32, current_unit: u32) @import("purity_type_key.zig").OriginError![]u8 {
        if (self.lookup) |lookup| return lookup(self.context, allocator, unit);
        if (unit != current_unit) return error.SourceIdentityUnavailable;
        return allocator.dupe(u8, "main");
    }
};
pub const ModuleOptions = struct { purity_origins: ModuleOrigins = .{}, builtin_catalog: bool = false, prelude_unit: u32 = 0, inherited_fixities: []const ImportedFixity = &.{} };
/// Private differential control. This changes execution, never semantic module
/// options or any retained-artifact key. Ordinary public entrypoints leave it off.
pub const AliasGlobalStats = struct { attempts: usize = 0, admitted: usize = 0, declined: usize = 0, frames: usize = 0, peak_frames: usize = 0 };
pub const GlobalTrace = struct {
    kind: enum { begun, finished },
    binding: BindingId,
    counter: u32,
    index: u32,
    low: u32,
    active: usize,
    current: BindingId,
    owner: ast.Id,
    ambient: T.Effects.Id,
    pending_start: usize,
    type_nodes: usize,
    type_versions: usize,
    row_versions: usize,
    type_env: usize,
    row_env: usize,
    computation_annotations: usize,
};
pub const PrivateExecution = struct {
    alias_globals: bool = false,
    stats: ?*AliasGlobalStats = null,
    context: ?*anyopaque = null,
    observe: ?*const fn (?*anyopaque, GlobalTrace) void = null,
};
pub const Identity = T.NominalIdentity;
pub const Nominal = PI.Nominal;
pub const Contract = PI.Contract;
pub const Constructor = PI.Constructor;
pub const Associated = PI.Associated;
pub const EffectFamily = PI.EffectFamily;
pub const EffectTemplate = PI.EffectTemplate;
pub const ReflectionKind = enum(u32) { of, descriptor, count, has, same };
pub const Reflection = struct { node: ast.Id, kind: ReflectionKind, left: ast.Id = 0, right: ast.Id = 0, binding: BindingId = 0, row: T.Effects.Id = 0, label: T.Effects.Label = 0 };
pub const OperationUse = struct { node: ast.Id, template: u32, arguments: T.List, signature: T.Id, call: enum { value, state_read, state_write } = .value, operand: ast.Id = 0 };
const AssociatedKey = struct { identity: Identity, operator: T.Operator };
const AssociatedMember = struct { identity: Identity, member: symbols.Symbol };
const EffectMember = struct { family: u32, member: symbols.Symbol };
pub const Rebinding = struct { root: BindingId = 0, self_binding: BindingId = 0, path: T.List = .{} };
pub const Projection = struct { nominal: Identity, field: symbols.Symbol, variants: T.List };
pub const ImportedCatalog = struct {
    producer: ?*const Checked = null,
    frozen: ?*const PI.Interface = null,
    namespace: symbols.Symbol = 0,
    name: symbols.Symbol = 0,
    kind: enum { catalog, nominal, constructor, effect_family, contract },
    index: u32,
    origin: ast.Id,

    pub fn catalog(self: ImportedCatalog) DeclarationCatalog {
        if (self.frozen) |owner| return .{ .types = .{ .frozen = &owner.graph }, .parameter_patterns = .{ .frozen = &owner.patterns }, .nominals = owner.nominals, .constructors = owner.constructors, .effect_families = owner.effect_families, .effect_templates = owner.effect_templates, .associated = owner.associated, .unit = owner.unit, .contracts = owner.contracts, .contract_predicates = owner.contract_predicates };
        return declarationCatalog(self.producer.?);
    }
    pub fn bindingCount(self: ImportedCatalog) usize {
        return if (self.frozen) |owner| owner.bindings.len else self.producer.?.bindings.len;
    }
    pub fn declaration(self: ImportedCatalog, id: BindingId) SourceDeclaration {
        if (self.frozen) |owner| {
            const value = owner.bindings[id];
            return .{ .name = value.name, .declaration = 0, .kind = value.kind, .named_function = value.named_function, .external = value.external };
        }
        return sourceDeclaration(self.producer.?.bindings[id]);
    }
    pub fn interface(self: ImportedCatalog, id: BindingId) SchemeInterface {
        if (self.frozen) |owner| {
            const value = owner.bindings[id];
            return .{ .types = .{ .frozen = &owner.graph }, .scheme = value.scheme, .named_function = value.named_function, .obligations = owner.obligations };
        }
        const owner = self.producer.?;
        const value = owner.bindings[id];
        return .{ .types = .{ .store = &owner.types }, .scheme = value.scheme, .named_function = value.named_function, .obligations = owner.obligations };
    }
};
/// Static imports cannot carry principal source-body interfaces.
pub const SourceCatalog = struct { producer: DeclarationCatalog, declarations: []const SourceDeclaration, namespace: symbols.Symbol = 0, name: symbols.Symbol = 0, kind: @FieldType(ImportedCatalog, "kind"), index: u32, origin: ast.Id };
pub const Kind = PI.Kind;
pub const ExternalTarget = PI.ExternalTarget;
pub const Binding = struct { name: symbols.Symbol, declaration: ast.Id, owner: ast.Id, kind: Kind, named_function: bool = false, ty: T.Id, scheme: T.Scheme = .{}, external: ?ExternalTarget = null, predecessor: BindingId = 0 };
/// An immutable interface borrows only semantic tables, never a source body.
pub const SchemeInterface = struct { named_function: bool = false, types: F.Source, scheme: T.Scheme, obligations: []const T.Obligation };
pub const ImportedBinding = struct {
    name: symbols.Symbol = 0,
    namespace: symbols.Symbol = 0,
    member: symbols.Symbol = 0,
    target: ExternalTarget,
    interface: SchemeInterface,
    origin: ast.Id,
    expose: bool = true,
};
/// Declaration facts admitted only by the owned source-validation API.
pub const SourceHeader = struct { name: symbols.Symbol = 0, namespace: symbols.Symbol = 0, member: symbols.Symbol = 0, target: ExternalTarget, named_function: bool = false, origin: ast.Id, expose: bool = true };
pub const SourceDeclaration = struct { name: symbols.Symbol, declaration: ast.Id, kind: Kind, named_function: bool, external: ?ExternalTarget };
pub fn sourceDeclaration(binding: Binding) SourceDeclaration {
    return .{ .name = binding.name, .declaration = binding.declaration, .kind = binding.kind, .named_function = binding.named_function, .external = binding.external };
}
/// Shared borrowed declaration payloads. No value schemes, obligations or bodies.
pub const DeclarationCatalog = struct { types: F.Source, parameter_patterns: F.Patterns, nominals: []const Nominal, constructors: []const Constructor, effect_families: []const EffectFamily, effect_templates: []const EffectTemplate, associated: []const Associated, unit: u32, contracts: []const Contract = &.{}, contract_predicates: []const T.Obligation = &.{} };
pub fn declarationCatalog(producer: anytype) DeclarationCatalog {
    return .{ .types = .{ .store = &producer.types }, .parameter_patterns = .{ .store = &producer.parameter_patterns }, .nominals = producer.nominals, .constructors = producer.constructors, .effect_families = producer.effect_families, .effect_templates = producer.effect_templates, .associated = producer.associated, .unit = producer.unit, .contracts = producer.contracts, .contract_predicates = producer.contract_predicates };
}
pub const ResolverKind = enum { monad, pure, bind, forward, iterate };
pub const ResolverBlock = struct { node: ast.Id, resolver: BindingId, result: T.Id, fallthrough: u32 = 0 };
pub const ProviderBlock = struct { node: ast.Id, provider: ast.Id, body_result: T.Id, result: T.Id, body_effects: T.Effects.Id, outer_effects: T.Effects.Id };
pub const EffectRunnerKind = enum { run, reader, writer };
/// Selector operands are source declarations, not runtime expressions. The
/// remaining operands retain written evaluation order before installation.
pub const EffectRunner = struct { node: ast.Id, kind: EffectRunnerKind, read_token: T.Id = 0, write_token: T.Id = 0, initial: ast.Id = 0, witness: ast.Id = 0, implementation: ast.Id = 0, action: ast.Id, state_type: T.Id, body_result: T.Id, result: T.Id, implementation_type: T.Id = 0, action_type: T.Id, body_effects: T.Effects.Id, outer_effects: T.Effects.Id };
/// Catalog references are 1-based; zero means absent. completed_types records
/// actual prelude Done result types from the inner value outward. A forward
/// return uses completion instead, preserving the selected source bind call.
pub const ResolverOp = struct { node: ast.Id, kind: ResolverKind, member: symbols.Symbol = 0, resolver: BindingId = 0, method: BindingId = 0, method_type: T.Id = 0, payload: T.Id = 0, result: T.Id = 0, continuation_parameter: BindingId = 0, completed_types: T.List = .{}, done_constructor: u32 = 0, completion: u32 = 0 };
pub const ResolverJoin = struct { node: ast.Id, parameter: BindingId, ty: T.Id, result: T.Id };
pub const ResolverCompletion = struct { node: ast.Id, bind: u32, pure: u32, completed_types: T.List, done_constructor: u32 };
/// The step, suffix and iterate outputs stay distinct: ordinary source methods
/// may change the wrapped payload type. cursor is (U32, carried-state), with
/// Unit for an empty carried-state; bound and array handles are captured once.
pub const ResolverLoop = struct { node: ast.Id, cursor_parameter: BindingId, first_binding: BindingId, end_binding: BindingId, cursor: T.Id, step_result: T.Id, suffix_result: T.Id, iterate: u32, continued: u32, finish: u32, continue_constructor: u32, done_constructor: u32 };
pub const LoopCarry = struct { node: ast.Id, incoming: BindingId, iteration: BindingId, backedge: BindingId, outgoing: BindingId };
pub const LoopExit = struct { node: ast.Id, loop: ast.Id, bindings: T.List };
pub const ClosedRow = struct { owner: BindingId, variable: u32 };
pub const Merge = struct { node: ast.Id, result: BindingId, then_binding: BindingId, else_binding: BindingId };
pub const Code = enum { unbound_alias_row, recursive_contract, contract_arity, recursive_type_alias, typed_hole, effect_member, integer_range, float_range, float_literal, module_loader_required, intrinsic_arity, requests_scope, yield_scope, request_loop_scope, request_loop_body, request_loop_range, request_binding, request_completion, request_clause_fallthrough, request_completion_fallthrough, duplicate_request_handler, request_case_scope, unknown_value, syntax, duplicate_name, unknown_name, type_mismatch, infinite_type, effect_mismatch, infinite_effect, const_effect, initializer_effect, let_effect, sealed_effect, effect_arity, effect_family, unknown_effect, invalid_effect_annotation, invalid_constraint, higher_rank_constraint, missing_predicate, ambiguous_qualified, annotation_kind_mismatch, unsupported_polymorphic_effect_label, operation_signature, type_arity, operation_target, invalid_state_provider, unsupported, unsupported_attribute, recursive_tag, function_target, open_effect_descriptor, unsupported_expression, unsupported_type, ambiguous_operator, ambiguous_associated, missing_associated, ambiguous_member, missing_member, type_constructor_required, invalid_provider, resolver_required, literal_required, call_arity, break_scope, invalid_return, unreachable_statement, invalid_operator, return_outside_block, unknown_rebinding, nesting_limit, unknown_constructor, constructor_marker, type_parameter, type_argument, duplicate_type_parameter, duplicate_type_field, unknown_field, duplicate_field, missing_field, non_exhaustive_match, refutable_pattern, constructor_arity, unknown_product_shape, product_index, product_index_literal, pattern_arity, pattern_bindings, value_pattern_type, non_exiting_fallback, unknown_operator, operator_associativity, operator_header_order, operator_precedence, duplicate_operator, unsupported_prefix, unknown_intrinsic, alternative_bindings, duplicate_pattern_binding, duplicate_record_field, unknown_record_field, record_constructor, missing_record_field, unknown_modifier, guard_fallthrough, product_arity };
pub const PurityWitness = @import("purity_diagnostics.zig").Witness;
pub const Diagnostic = struct {
    pub const TypeApplication = enum { missing_array, missing_nominal, extra };
    pub const Terminator = source_operators.Terminator;
    code: Code,
    span: ast.Span,
    node: ast.Id,
    type_application: ?TypeApplication = null,
    symbol: symbols.Symbol = 0,
    implicit_type_witness: bool = false,
    source_terminator: Terminator = .none,
    numeric_literal: ?ast.NumericFault = null,
    purity: ?PurityWitness = null,
    /// Owned diagnostic-only text. Never intern scratch allocations in the
    /// borrowed source pool; project/source validation can have another owner.
    detail: ?[]const u8 = null,
    hole: ?@import("hole_diagnostics.zig").Snapshot = null,
    pub fn message(self: Diagnostic) []const u8 {
        if (self.detail) |detail| return detail;
        if (self.type_application) |application| return switch (application) {
            .missing_array => "Array requires one element type",
            .missing_nominal => "partially applied type constructor requires another argument",
            .extra => "type does not accept another argument; currying must be explicit in its declaration",
        };
        return switch (self.code) {
            .unbound_alias_row => "A data or effect declaration must carry an open alias row in an explicit type parameter",
            .recursive_contract => "Contracts cannot include themselves recursively",
            .contract_arity => "A contract requires its declared type argument shapes",
            .recursive_type_alias => "Type aliases cannot refer to themselves recursively",
            .typed_hole => "Unfilled expression; expected",
            .effect_member => "effect family requires an operation member",
            .integer_range => "integer literal exceeds U32 (4294967295)",
            .float_range => "floating-point literal exceeds finite F32 range",
            .float_literal => "invalid F32 literal",
            .duplicate_type_parameter => "Duplicate type parameter",
            .duplicate_type_field => if (self.symbol != 0) "duplicate type argument field" else "Duplicate type argument field",
            .type_parameter => "A type parameter pattern binds lowercase names",
            .type_argument => "A type argument must match its parameter pattern",
            .intrinsic_arity => "Invalid request intrinsic arity",
            .requests_scope => "@requests is only available as a request loop input",
            .yield_scope => "yield requires an operation clause in a request loop",
            .request_loop_scope => "A request loop requires an enclosing do block",
            .request_loop_body => "A request loop requires one effect/complete case",
            .request_loop_range => "A request loop cannot have a range endpoint",
            .request_binding => "The request case must match the loop binding",
            .request_completion => "A request loop requires exactly one complete clause",
            .request_clause_fallthrough => "An operation clause must reply or exit on each path",
            .request_completion_fallthrough => "A completion clause must return or break",
            .duplicate_request_handler => "An operation can have only one request clause",
            .request_case_scope => "Request cases require a request loop",
            .record_constructor => "named fields require a declared record constructor",
            .missing_record_field => "missing record field",
            .unknown_modifier => "only `entry` may precede `const` or `let`",
            .guard_fallthrough => "let-else fallback must exit its enclosing do block",
            .product_arity => "cannot unify products with different element counts",
            .unknown_value => if (self.implicit_type_witness) "unknown value: Type" else "unknown value",
            .unknown_operator => "operator has no source fixity declaration",
            .operator_associativity => "operators at equal precedence need compatible associativity or explicit parentheses",
            .operator_header_order => "operator declarations must precede values and data declarations",
            .operator_precedence => "operator precedence must be between 0 and 255",
            .duplicate_operator => "duplicate operator fixity declaration",
            .unsupported_prefix => "only F32 prefix negation (-) is supported",
            .unknown_intrinsic => "unknown compiler intrinsic",
            .product_index_literal => "product projection requires a literal zero-based index",
            .syntax => "Invalid syntax prevents semantic checking",
            .duplicate_name => "duplicate value or constructor declaration",
            .unknown_name => "Unknown value name",
            .type_mismatch => "Types do not match",
            .infinite_type => "A type contains itself",
            .effect_mismatch => "Effect rows do not match",
            .infinite_effect => "An effect row contains itself",
            .const_effect => "A constant initializer must be pure",
            .initializer_effect => "A runtime initializer must be pure",
            .let_effect => "A let or rebinding initializer must be pure",
            .sealed_effect => "Foreign is a compiler effect label, not a callable or providable operation",
            .effect_arity => "An effect operation has the wrong number of type arguments",
            .effect_family => "Read and write operations must belong to the same declared effect family",
            .unknown_effect => "Effect rows require Foreign or a declared effect operation or family",
            .invalid_effect_annotation => "A latent effect row annotates a function arrow",
            .invalid_constraint => "A where predicate has the wrong kind or argument shape",
            .higher_rank_constraint => "Parameter annotations cannot contain where clauses",
            .missing_predicate => "inferred requirement is absent from the explicit where clause",
            .ambiguous_qualified => "Qualified evidence still has unconstrained type or effect variables",
            .annotation_kind_mismatch => "One annotation name cannot be both a type and an effect-row variable",
            .unsupported_polymorphic_effect_label => "Open rows currently require concrete effect operation labels",
            .operation_signature => "An operation declaration specifies a unary parameter and result without an outer effect row",
            .type_arity => "A type application has the wrong number of arguments",
            .operation_target => "Expected the name of a declared effect operation",
            .invalid_state_provider => "State read and write must be distinct operations",
            .module_loader_required => "compile a source project to resolve file imports",
            .unsupported => "This semantic form is not implemented in the native compiler",
            .unsupported_attribute => "Tags are allowed only on const and let declarations",
            .function_target => "Effect reflection requires a statically named top-level function",
            .open_effect_descriptor => "Effect reflection requires a closed checked effect row",
            .recursive_tag => "A tagged declaration cannot refer to its own bound name",
            .unsupported_expression => "This expression is not implemented in the executable core",
            .unsupported_type => "This annotation type is not implemented in the native compiler",
            .ambiguous_operator => "Numeric operation has no admitted U32 or F32 evidence",
            .ambiguous_associated => "The expected result type does not identify an associated implementation",
            .missing_associated => "No compatible associated implementation exists",
            .ambiguous_member => "A field and associated function share this name",
            .missing_member => "This receiver has no associated member with this name",
            .type_constructor_required => "Monad requires a nominal type constructor value",
            .invalid_provider => "Do requires an effect provider or monad resolver",
            .resolver_required => "Return $ requires a monad resolver",
            .literal_required => "This compiler primitive requires a literal string argument",
            .call_arity => "This compiler primitive requires its exact literal and operand arguments",
            .break_scope => "Break requires an enclosing loop in this function",
            .invalid_return => "Loop control cannot escape a suspended argument",
            .unreachable_statement => switch (self.source_terminator) {
                .return_, .break_, .yield_ => "statement after return in the same suite",
                .none => "A statement follows an unconditional return or break",
            },
            .invalid_operator => "This operator is not declared or supported",
            .return_outside_block => "Return requires an enclosing do block in this function",
            .unknown_rebinding => if (self.symbol != 0) ":= requires an existing local binding" else "Rebinding requires an existing lexical name",
            .nesting_limit => "Semantic nesting exceeds the compiler limit",
            .constructor_marker => "Record constructors require # before the name",
            .unknown_constructor => if (self.symbol != 0) "unknown record constructor" else "Unknown data constructor",
            .unknown_field => "This value has no such named field",
            .duplicate_field => "A field was supplied more than once",
            .missing_field => "A required record field is missing",
            .non_exhaustive_match => "Case patterns do not cover every possible value",
            .refutable_pattern => "A refutable let pattern requires an exiting else branch",
            .constructor_arity => "Constructor payload does not match its declared arity",
            .unknown_product_shape => "projection requires a known product arity; annotate the parameter with a product type",
            .product_index => "product projection index is outside its fixed arity",
            .pattern_arity => "Pattern shape does not match the scrutinee shape",
            .alternative_bindings => "alternative patterns must bind the same names",
            .duplicate_pattern_binding => "a pattern cannot bind the same name more than once",
            .duplicate_record_field => "record field is supplied more than once",
            .unknown_record_field => "record has no field named",
            .pattern_bindings => "Pattern alternatives must bind the same names",
            .value_pattern_type => "Value patterns require U32 or Bool",
            .non_exiting_fallback => "A refutable let failure branch must exit",
        };
    }
};
/// Source intervals owned by tag expressions. The wrapped initializer is outside
/// these intervals and retains its original diagnostic location.
pub const TagOrigin = struct { span: ast.Span, attribute: ast.Id };
fn tagOrigin(origins: []const TagOrigin, span: ast.Span) ast.Id {
    var low: usize = 0;
    var high = origins.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (origins[middle].span.start <= span.start) low = middle + 1 else high = middle;
    }
    if (low == 0) return 0;
    const candidate = origins[low - 1];
    return if (span.end <= candidate.span.end) candidate.attribute else 0;
}
pub const Computation = struct { node: ast.Id, action: ast.Id, ty: T.Id, action_type: T.Id };
pub const RequestArm = struct { node: ast.Id, loop: ast.Id, operation: T.Effects.Label, parameter_type: T.Id, reply_type: T.Id, signature: T.Id, pattern: ast.Id, suite: ast.Id, state_bindings: T.List };
pub const RequestLoop = struct { node: ast.Id, computation: ast.Id, value_type: T.Id, result_type: T.Id, state_type: T.Id, action_type: T.Id, arms: T.List, completion: ast.Id, complete_pattern: ast.Id, complete_suite: ast.Id, complete_state_bindings: T.List, carried: T.List, return_scope: ast.Id };
pub const RequestControl = struct { node: ast.Id, loop: ast.Id, kind: enum { reply, cancel, break_ }, value_type: T.Id, bindings: T.List = .{}, target_scope: ast.Id };
pub const Checked = struct {
    iterator_bodies: []ast.Id = &.{},
    initializer_rejected: bool = false,
    computations: []Computation = &.{},
    request_loops: []RequestLoop = &.{},
    request_arms: []RequestArm = &.{},
    request_controls: []RequestControl = &.{},
    reflections: []Reflection = &.{},
    tag_origins: []TagOrigin = &.{},
    effect_runners: []EffectRunner = &.{},
    effect_runner_ids: []u32 = &.{},
    provider_blocks: []ProviderBlock = &.{},
    provider_block_ids: []u32 = &.{},
    body_closed_rows: []ClosedRow = &.{},
    lambda_closed_rows: []T.List = &.{},
    dispatch_signatures: []T.Id = &.{},
    effect_families: []EffectFamily = &.{},
    effect_templates: []EffectTemplate = &.{},
    operation_uses: []OperationUse = &.{},
    operation_refs: []u32 = &.{},
    types: T.Store,
    parameter_patterns: P.Store = .{},
    expr_types: []T.Id,
    resolved: []BindingId,
    bindings: []Binding,
    merges: []Merge,
    obligations: []T.Obligation,
    diagnostics: []Diagnostic,
    body_elaborations: usize,
    imported_schemes: usize = 0,
    unit: u32 = 1,
    associated: []Associated = &.{},
    nominals: []Nominal = &.{},
    contracts: []Contract = &.{},
    contract_predicates: []T.Obligation = &.{},
    constructors: []Constructor = &.{},
    constructor_resolved: []u32 = &.{},
    projections: []u32 = &.{},
    access_paths: []T.List = &.{},
    access_nodes: []T.List = &.{},
    access_types: []T.List = &.{},
    projection_resolved: []u32 = &.{},
    projection_catalog: []Projection = &.{},
    rebindings: []Rebinding = &.{},
    resolver_blocks: []ResolverBlock = &.{},
    resolver_ops: []ResolverOp = &.{},
    resolver_joins: []ResolverJoin = &.{},
    resolver_completions: []ResolverCompletion = &.{},
    resolver_loops: []ResolverLoop = &.{},
    resolver_block_ids: []u32 = &.{},
    resolver_op_ids: []u32 = &.{},
    resolver_join_ids: []u32 = &.{},
    resolver_loop_ids: []u32 = &.{},
    loop_carries: []LoopCarry = &.{},
    loop_ranges: []T.List = &.{},
    demand_calls: []bool = &.{},
    demand_types: []T.Id = &.{},
    demand_binary_left_types: []T.Id = &.{},
    demand_binary_left: []bool = &.{},
    loop_exits: []LoopExit = &.{},
    pub fn reflection(self: *const Checked, id: ast.Id) ?Reflection {
        var low: usize = 0;
        var high = self.reflections.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.reflections[middle].node < id) low = middle + 1 else high = middle;
        }
        return if (low < self.reflections.len and self.reflections[low].node == id) self.reflections[low] else null;
    }
    pub fn diagnosticSpan(self: *const Checked, tree: *const ast.Tree, source: ast.Id) ast.Span {
        const span = tree.span(source);
        const origin = tagOrigin(self.tag_origins, span);
        return if (origin == 0) span else tree.span(origin);
    }
    pub fn deinit(self: *Checked, allocator: Allocator) void {
        allocator.free(self.iterator_bodies);
        allocator.free(self.computations);
        allocator.free(self.request_loops);
        allocator.free(self.request_arms);
        allocator.free(self.request_controls);
        allocator.free(self.reflections);
        allocator.free(self.tag_origins);
        allocator.free(self.effect_runners);
        allocator.free(self.effect_runner_ids);
        allocator.free(self.provider_blocks);
        allocator.free(self.provider_block_ids);
        allocator.free(self.body_closed_rows);
        allocator.free(self.lambda_closed_rows);
        allocator.free(self.dispatch_signatures);
        allocator.free(self.effect_families);
        allocator.free(self.effect_templates);
        allocator.free(self.operation_uses);
        allocator.free(self.operation_refs);
        self.types.deinit();
        self.parameter_patterns.deinit(allocator);
        allocator.free(self.expr_types);
        allocator.free(self.resolved);
        allocator.free(self.bindings);
        allocator.free(self.merges);
        allocator.free(self.obligations);
        deinitDiagnosticPayloads(allocator, self.diagnostics);
        allocator.free(self.diagnostics);
        allocator.free(self.nominals);
        allocator.free(self.contracts);
        allocator.free(self.contract_predicates);
        allocator.free(self.constructors);
        allocator.free(self.constructor_resolved);
        allocator.free(self.projections);
        allocator.free(self.access_paths);
        allocator.free(self.access_nodes);
        allocator.free(self.access_types);
        allocator.free(self.projection_resolved);
        allocator.free(self.projection_catalog);
        allocator.free(self.rebindings);
        allocator.free(self.associated);
        allocator.free(self.resolver_blocks);
        allocator.free(self.resolver_ops);
        allocator.free(self.resolver_joins);
        allocator.free(self.resolver_completions);
        allocator.free(self.resolver_loops);
        allocator.free(self.resolver_block_ids);
        allocator.free(self.resolver_op_ids);
        allocator.free(self.resolver_join_ids);
        allocator.free(self.resolver_loop_ids);
        allocator.free(self.loop_carries);
        allocator.free(self.loop_ranges);
        allocator.free(self.demand_calls);
        allocator.free(self.demand_types);
        allocator.free(self.demand_binary_left_types);
        allocator.free(self.demand_binary_left);
        allocator.free(self.loop_exits);
        self.* = undefined;
    }
};
const Entry = struct { name: symbols.Symbol, binding: BindingId };
const State = enum { pending, active, complete };
const Global = struct { state: State = .pending, index: u32 = 0, low: u32 = 0, on_stack: bool = false };
const PendingObligation = struct { metadata: u32 = 0, value: T.Obligation, owner: BindingId, scope: ast.Id = 0, origin: u32 = 0, declared: bool = false, covered: bool = false, local_scheme: bool = false, direct: bool = false, method_member: bool = false, suspended: bool = false, solved: bool = false };
const Qualification = struct { scope: ast.Id, owner: BindingId, clauses: T.List, value: ast.Id, checked: bool = false };
const QualificationUse = struct { scope: ast.Id, owner: BindingId, target: BindingId, source: ast.Id };
const LoopFrame = struct { node: ast.Id, carries: []const Entry, iterations: []const BindingId, resolver_block: ast.Id = 0, exits: usize = 0 };
const ResolverScope = struct { block: ast.Id = 0, resolver: BindingId = 0, owner_type: T.Id = 0, result: T.Id = 0, progress_depth: u32 = 0 };
const RequestScope = struct { loop: ast.Id = 0, reply: T.Id = 0, target: T.Id = 0, completion: bool = false, return_scope: ast.Id = 0, arm: u32 = 0, state_bindings: T.List = .{}, invalid_outer_return: bool = false };
const Flow = struct { ty: T.Id = T.unit, exits: bool = false, returns: bool = false, breaks: bool = false };
const Qualified = struct { namespace: symbols.Symbol, member: symbols.Symbol };
const QualifiedResolution = struct { namespace: symbols.Symbol, binding: BindingId };
const OperatorOverride = struct { target: symbols.Symbol, named: bool, external: ?ExternalTarget = null };
const Engine = struct {
    active_aliases: std.AutoHashMapUnmanaged(u32, void) = .empty,
    holes: std.ArrayList(struct { node: ast.Id, scope: T.List, owner: BindingId }) = .empty,
    execution: PrivateExecution = .{},
    computations: std.ArrayList(Computation) = .empty,
    request_loops: std.ArrayList(RequestLoop) = .empty,
    request_arms: std.ArrayList(RequestArm) = .empty,
    request_controls: std.ArrayList(RequestControl) = .empty,
    reflections: std.ArrayList(Reflection) = .empty,
    case_pattern_source: ast.Id = 0,
    let_pattern_source: ast.Id = 0,
    tag_origins: []TagOrigin = &.{},
    effect_runners: std.ArrayList(EffectRunner) = .empty,
    effect_runner_ids: []u32 = &.{},
    provider_blocks: std.ArrayList(ProviderBlock) = .empty,
    provider_block_ids: []u32 = &.{},
    body_closed_rows: std.ArrayList(ClosedRow) = .empty,
    closed_row_keys: std.AutoHashMapUnmanaged(ClosedRow, void) = .empty,
    row_sources: std.AutoHashMapUnmanaged(u32, ast.Id) = .empty,
    purity_origins: ModuleOrigins = .{},
    initializer_rejected: bool = false,
    lambda_closed_rows: []T.List = &.{},
    dispatch_signatures: []T.Id = &.{},
    effect_families: std.ArrayList(EffectFamily) = .empty,
    effect_templates: std.ArrayList(EffectTemplate) = .empty,
    operation_uses: std.ArrayList(OperationUse) = .empty,
    operation_refs: []u32 = &.{},
    effect_family_names: std.AutoHashMapUnmanaged(Qualified, u32) = .empty,
    effect_family_identities: std.AutoHashMapUnmanaged(Identity, u32) = .empty,
    effect_members: std.AutoHashMapUnmanaged(EffectMember, u32) = .empty,
    effect_operation_names: std.AutoHashMapUnmanaged(Qualified, u32) = .empty,
    effect_template_identities: std.AutoHashMapUnmanaged(Identity, u32) = .empty,
    allocator: Allocator,
    tree: *const ast.Tree,
    pool: *symbols.Pool,
    types: T.Store,
    parameter_patterns: P.Store = .{},
    expr_types: []T.Id,
    resolved: []BindingId,
    bindings: std.ArrayList(Binding) = .empty,
    merges: std.ArrayList(Merge) = .empty,
    obligations: std.ArrayList(T.Obligation) = .empty,
    pending: std.ArrayList(PendingObligation) = .empty,
    qualification_scope: ast.Id = 0,
    request_scope: RequestScope = .{},
    local_qualification_scope: ast.Id = 0,
    local_requirements_start: usize = 0,
    qualifications: std.ArrayList(Qualification) = .empty,
    qualification_uses: std.ArrayList(QualificationUse) = .empty,
    declared_obligations: std.ArrayList(T.Obligation) = .empty,
    predicate_origins: std.ArrayList(ast.Span) = .empty,
    computed_variables: std.ArrayList(T.Id) = .empty,
    computed_rows: std.ArrayList(u32) = .empty,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    globals: std.AutoHashMapUnmanaged(symbols.Symbol, BindingId) = .empty,
    global_states: std.AutoHashMapUnmanaged(BindingId, Global) = .empty,
    active: std.ArrayList(BindingId) = .empty,
    env: std.ArrayList(Entry) = .empty,
    current: BindingId = 0,
    pending_start: usize = 0,
    owner: ast.Id = 0,
    return_target: T.Id = 0,
    ambient: T.Effects.Id = 0,
    suspended_loop_escape: bool = false,
    resolver_scope: ResolverScope = .{},
    counter: u32 = 0,
    depth: usize = 0,
    permitted_intrinsic: ast.Id = 0,
    closed_type_variables: bool = false,
    implicit_row_parameters: bool = false,
    body_elaborations: usize = 0,
    self_name: symbols.Symbol,
    overrides: std.AutoHashMapUnmanaged(symbols.Symbol, OperatorOverride) = .empty,
    qualified: std.AutoHashMapUnmanaged(Qualified, BindingId) = .empty,
    qualified_symbols: std.AutoHashMapUnmanaged(symbols.Symbol, QualifiedResolution) = .empty,
    external_targets: std.AutoHashMapUnmanaged(ExternalTarget, BindingId) = .empty,
    unit: u32 = 1,
    builtin_catalog: bool = false,
    source_validation: bool = false,
    source_annotation_failed: bool = false,
    source_header_diagnostics: []Diagnostic = &.{},
    prelude_unit: u32 = 0,
    nominals: std.ArrayList(Nominal) = .empty,
    contracts: std.ArrayList(Contract) = .empty,
    contract_predicates: std.ArrayList(T.Obligation) = .empty,
    contract_names: std.AutoHashMapUnmanaged(Qualified, u32) = .empty,
    contract_identities: std.AutoHashMapUnmanaged(Identity, u32) = .empty,
    contract_states: std.AutoHashMapUnmanaged(u32, enum { visiting, ready }) = .empty,
    contract_depth: usize = 0,
    constructors: std.ArrayList(Constructor) = .empty,
    nominal_identities: std.AutoHashMapUnmanaged(Identity, u32) = .empty,
    constructor_identities: std.AutoHashMapUnmanaged(Identity, u32) = .empty,
    nominal_names: std.AutoHashMapUnmanaged(Qualified, u32) = .empty,
    constructor_names: std.AutoHashMapUnmanaged(Qualified, u32) = .empty,
    type_env: std.ArrayList(struct { name: symbols.Symbol, ty: T.Id }) = .empty,
    row_env: std.ArrayList(struct { name: symbols.Symbol, row: T.Effects.Id }) = .empty,
    // @computation supplies a source-site annotation. Its result and row
    // remain shared in local schemes until an explicit RHS scope restores
    // the enclosing annotations. Numeric type IDs avoid synthetic names.
    computation_annotations: std.ArrayList(T.Id) = .empty,
    annotation_binding: ast.Id = 0,
    inherited_types: usize = 0,
    inherited_rows: usize = 0,
    constructor_resolved: []u32 = &.{},
    projections: []u32 = &.{},
    access_paths: []T.List = &.{},
    access_nodes: []T.List = &.{},
    access_types: []T.List = &.{},
    projection_resolved: []u32 = &.{},
    projection_catalog: std.ArrayList(Projection) = .empty,
    rebindings: []Rebinding = &.{},
    resolver_blocks: std.ArrayList(ResolverBlock) = .empty,
    resolver_ops: std.ArrayList(ResolverOp) = .empty,
    resolver_joins: std.ArrayList(ResolverJoin) = .empty,
    resolver_completions: std.ArrayList(ResolverCompletion) = .empty,
    resolver_loops: std.ArrayList(ResolverLoop) = .empty,
    resolver_block_ids: []u32 = &.{},
    resolver_op_ids: []u32 = &.{},
    resolver_join_ids: []u32 = &.{},
    resolver_loop_ids: []u32 = &.{},
    loop_carries: std.ArrayList(LoopCarry) = .empty,
    iterator_bodies: []ast.Id = &.{},
    loop_ranges: []T.List = &.{},
    demand_calls: []bool = &.{},
    demand_types: []T.Id = &.{},
    demand_binary_left_types: []T.Id = &.{},
    demand_binary_left: []bool = &.{},
    loop_exits: std.ArrayList(LoopExit) = .empty,
    loop_stack: std.ArrayList(LoopFrame) = .empty,
    cases: std.ArrayList(ast.Id) = .empty,
    associated: std.ArrayList(Associated) = .empty,
    associated_ops: std.AutoHashMapUnmanaged(AssociatedKey, u32) = .empty,
    associated_members: std.AutoHashMapUnmanaged(AssociatedMember, u32) = .empty,

    fn qualifiedKey(self: *const Engine, name: symbols.Symbol) ?Qualified {
        const text = self.pool.get(name);
        const separator = std.mem.indexOfScalar(u8, text, '.') orelse return null;
        return .{ .namespace = self.pool.lookup(text[0..separator]) orelse return null, .member = self.pool.lookup(text[separator + 1 ..]) orelse return null };
    }
    fn qualifiedBinding(self: *Engine, name: symbols.Symbol) Allocator.Error!?BindingId {
        if (self.qualified_symbols.get(name)) |found| return found.binding;
        const key = self.qualifiedKey(name) orelse return null;
        const binding = self.qualified.get(key) orelse return null;
        try self.qualified_symbols.put(self.allocator, name, .{ .namespace = key.namespace, .binding = binding });
        return binding;
    }
    fn globalBinding(self: *Engine, name: symbols.Symbol) Allocator.Error!?BindingId {
        // Resolve source value paths through the lexical root first. Fixity
        // declarations use the separate immutable global catalog below.
        const text = self.pool.get(name);
        if (std.mem.indexOfScalar(u8, text, '.')) |separator| {
            if (self.pool.lookup(text[0..separator])) |root|
                if (self.lookup(root) != null) return null;
        }
        return self.catalogBinding(name);
    }
    fn catalogBinding(self: *Engine, name: symbols.Symbol) Allocator.Error!?BindingId {
        if (self.globals.get(name)) |binding| return binding;
        return self.qualifiedBinding(name);
    }
    pub fn sourceDuplicateName(self: *const Engine) ?ast.Id {
        if (self.source_validation) {
            // Constructor and value declarations share a source namespace.
            // Collection fails before any expression is lowered.
            for (self.constructors.items[1..]) |constructor| if (constructor.identity.unit == self.unit) {
                if (self.globals.get(constructor.name)) |binding| {
                    const declaration = self.bindings.items[binding].declaration;
                    return if (self.tree.span(declaration).start < self.tree.span(constructor.identity.decl).start) declaration else constructor.identity.decl;
                }
            };
        }
        const diagnostics = if (self.source_validation) self.source_header_diagnostics else self.diagnostics.items;
        for (diagnostics) |issue| if (issue.code == .duplicate_name and self.tree.node(issue.node).tag == .value_decl) {
            const name = self.tree.valueDecl(issue.node).name;
            if (self.globals.get(name)) |binding| return self.bindings.items[binding].declaration;
        };
        return null;
    }
    pub fn sourceTypeApplication(self: *const Engine, symbol: symbols.Symbol) bool {
        if (self.nominal_names.get(self.catalogKey(symbol))) |nominal| return self.nominals.items[nominal].patterns.len != 0;
        if (self.catalogOperationTemplate(symbol)) |template| {
            const family = self.effect_templates.items[template].family;
            return self.effect_families.items[family].patterns.len != 0;
        }
        return false;
    }
    pub fn sourceNonCallableEffect(self: *const Engine, symbol: symbols.Symbol) bool {
        if (self.effect_family_names.get(self.catalogKey(symbol))) |family| return !self.effect_families.items[family].callable;
        if (self.globals.contains(symbol) or self.qualified.contains(self.catalogKey(symbol)) or self.catalogOperationTemplate(symbol) != null) return false;
        const text = self.pool.get(symbol);
        var prefix_end = text.len;
        while (std.mem.lastIndexOfScalar(u8, text[0..prefix_end], '.')) |separator| {
            prefix_end = separator;
            const prefix = text[0..prefix_end];
            const key: Qualified = if (std.mem.indexOfScalar(u8, prefix, '.')) |dot| .{ .namespace = self.pool.lookup(prefix[0..dot]) orelse continue, .member = self.pool.lookup(prefix[dot + 1 ..]) orelse continue } else .{ .namespace = 0, .member = self.pool.lookup(prefix) orelse continue };
            if (self.effect_family_names.get(key)) |family| return !self.effect_families.items[family].callable;
        }
        return false;
    }
    fn sourceParameterMatches(self: *Engine, param_pattern: P.Id, argument: ast.Id) T.Error!bool {
        // Source admission is a fallible conversion/match, not an inferred
        // expression. Its trial types and diagnostics never become catalogs.
        const point = self.types.mark();
        const diagnostic_count = self.diagnostics.items.len;
        const type_names = self.type_env.items.len;
        const row_names = self.row_env.items.len;
        defer {
            self.types.rollback(point);
            self.diagnostics.shrinkRetainingCapacity(diagnostic_count);
            self.type_env.shrinkRetainingCapacity(type_names);
            self.row_env.shrinkRetainingCapacity(row_names);
        }
        _ = try self.parameterArgument(param_pattern, argument, false, 0);
        return self.diagnostics.items.len == diagnostic_count;
    }
    pub fn sourceArgumentIsType(self: *Engine, original: ast.Id, argument: ast.Id) T.Error!bool {
        var head = original;
        var consumed: usize = 0;
        while (true) {
            const node = self.tree.node(head);
            if (node.tag == .group) head = node.a else if (node.tag == .apply) {
                consumed += 1;
                head = node.a;
            } else break;
        }
        const node = self.tree.node(head);
        if (node.tag != .name) return false;
        // A nominal type token is an ordinary value. Only parameterized
        // operations consume explicit type arguments during source lowering.
        const template = self.catalogOperationTemplate(node.a) orelse return false;
        const patterns = self.effect_families.items[self.effect_templates.items[template].family].patterns;
        if (consumed >= patterns.len) return false;
        const param_pattern = self.parameter_patterns.list(patterns)[consumed];
        return try self.possibleParameterArgument(param_pattern, argument, true, 0) and try self.sourceParameterMatches(param_pattern, argument);
    }
    pub fn sourceConstructorExists(self: *const Engine, symbol: symbols.Symbol) bool {
        return self.constructor_names.contains(self.catalogKey(symbol));
    }
    pub fn sourceRecordFieldExists(self: *const Engine, symbol: symbols.Symbol, field: symbols.Symbol) ?bool {
        const constructor = self.constructor_names.get(self.catalogKey(symbol)) orelse return null;
        const payload = self.constructors.items[constructor].payload;
        if (!self.constructors.items[constructor].declared_record) return null;
        if (payload == 0) return false;
        const record = self.types.node(payload);
        if (record.tag != .record) return null;
        for (0..record.b) |index| if (self.types.recordField(record, index).name == field) return true;
        return false;
    }
    pub fn sourceRecordTarget(self: *Engine, symbol: symbols.Symbol) T.Error!enum { missing, record, other } {
        if (self.constructor_names.get(self.catalogKey(symbol))) |constructor|
            return if (self.constructors.items[constructor].declared_record) .record else .other;
        const value = try self.catalogBinding(symbol) != null or self.catalogOperationTemplate(symbol) != null or self.effect_family_names.contains(self.catalogKey(symbol));
        return if (value) .other else .missing;
    }
    pub fn sourceMissingRecordField(self: *const Engine, symbol: symbols.Symbol, fields: []const ast.Id) ?symbols.Symbol {
        const constructor = self.constructor_names.get(self.catalogKey(symbol)) orelse return null;
        const payload = self.constructors.items[constructor].payload;
        if (payload == 0) return null;
        const record = self.types.node(payload);
        if (record.tag != .record) return null;
        for (0..record.b) |index| {
            const field = self.types.recordField(record, index).name;
            var supplied = false;
            for (fields) |id| if (self.tree.node(id).a == field) {
                supplied = true;
                break;
            };
            if (!supplied) return field;
        }
        return null;
    }
    pub fn sourceIntrinsicArity(self: *const Engine, symbol: symbols.Symbol) ?usize {
        const text = self.pool.get(symbol);
        if (std.mem.eql(u8, text, "@requests") or std.mem.eql(u8, text, "@computation")) return 1;
        return intrinsicArity(text);
    }
    pub fn sourceIntrinsicKnown(self: *const Engine, symbol: symbols.Symbol) bool {
        const text = self.pool.get(symbol);
        return intrinsicArity(text) != null or std.mem.eql(u8, text, "@requests") or std.mem.eql(u8, text, "@computation");
    }
    pub fn sourceSymbolicDeclared(self: *const Engine, symbol: symbols.Symbol) bool {
        const fixity = self.overrides.get(symbol) orelse return false;
        return !fixity.named;
    }
    pub fn sourceOperatorTargetExists(self: *Engine, name: symbols.Symbol) Allocator.Error!bool {
        if (try self.catalogBinding(name) != null) return true;
        const key = self.catalogKey(name);
        return self.constructor_names.contains(key) or self.catalogOperationTemplate(name) != null;
    }
    pub fn sourceQualifiedExists(self: *const Engine, namespace: symbols.Symbol, member: symbols.Symbol) bool {
        const key: Qualified = .{ .namespace = namespace, .member = member };
        return self.qualified.contains(key) or self.nominal_names.contains(key) or self.effect_family_names.contains(key) or self.effect_operation_names.contains(key);
    }
    pub fn sourceValueExists(self: *Engine, name: symbols.Symbol) Allocator.Error!bool {
        if (try self.sourceOperatorTargetExists(name)) return true;
        const key = self.catalogKey(name);
        if (self.nominal_names.contains(key) or self.effect_family_names.contains(key)) return true;
        const text = self.pool.get(name);
        const root = if (std.mem.indexOfScalar(u8, text, '.')) |separator| self.pool.lookup(text[0..separator]) orelse return false else name;
        if (root != name and try self.sourceOperatorTargetExists(root)) return true;
        if (self.nominal_names.contains(.{ .namespace = 0, .member = root }) or self.effect_family_names.contains(.{ .namespace = 0, .member = root })) return true;
        return false;
    }

    pub const SourceAnnotationScope = struct {
        types: usize,
        rows: usize,
        computations: usize,
        binding: ast.Id,
        inherited_types: usize,
        inherited_rows: usize,
    };
    pub fn sourceLiteralPoint(self: *const Engine, id: ast.Id) u32 {
        const span = self.tree.span(id);
        const attribute = tagOrigin(self.tag_origins, span);
        return if (attribute == 0) span.start else self.tree.span(attribute).start;
    }
    pub fn sourceAnnotationsStopped(self: *const Engine) bool {
        return self.source_annotation_failed;
    }
    pub fn sourceControlValidation(self: *const Engine) bool {
        return self.source_validation;
    }
    pub fn sourceDeclarationHeader(self: *Engine, id: ast.Id) Allocator.Error!void {
        if (!self.source_validation or self.source_annotation_failed) return;
        const span = self.tree.span(id);
        for (self.source_header_diagnostics) |diagnostic_| {
            const node_span = self.tree.span(diagnostic_.node);
            if (node_span.start < span.start or node_span.end > span.end) continue;
            try self.diagnostics.append(self.allocator, diagnostic_);
            self.source_annotation_failed = true;
            return;
        }
    }
    pub fn sourceBindingStart(self: *Engine, id: ast.Id) T.Error!SourceAnnotationScope {
        const saved: SourceAnnotationScope = .{ .types = self.type_env.items.len, .rows = self.row_env.items.len, .computations = self.computation_annotations.items.len, .binding = self.annotation_binding, .inherited_types = self.inherited_types, .inherited_rows = self.inherited_rows };
        if (!self.source_validation) return saved;
        const before = self.diagnostics.items.len;
        self.annotation_binding = if (self.tree.node(id).tag == .let_stmt) id else 0;
        self.inherited_types = saved.types;
        self.inherited_rows = saved.rows;
        if (self.tree.node(id).tag == .value_decl) {
            const declaration = self.tree.valueDecl(id);
            try self.collectAnnotationNames(declaration.annotation, 0);
            try self.collectAnnotationNames(declaration.where_node, 0);
            try self.collectAnnotationNames(declaration.body, 0);
            for (self.tree.list(declaration.attributes)) |attribute| try self.collectAnnotationNames(self.tree.node(attribute).a, 0);
        } else {
            const binding = self.tree.binding(id);
            try self.collectAnnotationNames(binding.annotation, 0);
            try self.collectAnnotationNames(binding.where_node, 0);
            try self.collectAnnotationNames(binding.value, 0);
            try self.collectAnnotationNames(binding.fallback, 0);
        }
        self.source_annotation_failed = self.source_annotation_failed or self.diagnostics.items.len != before;
        return saved;
    }
    pub fn sourceBindingAnnotation(self: *Engine, id: ast.Id) T.Error!void {
        if (!self.source_validation or self.source_annotation_failed) return;
        const before = self.diagnostics.items.len;
        const annotation_ = if (self.tree.node(id).tag == .value_decl) self.tree.valueDecl(id).annotation else self.tree.binding(id).annotation;
        if (annotation_ != 0) _ = try self.annotation(annotation_);
        self.source_annotation_failed = self.diagnostics.items.len != before;
    }
    pub fn sourceBindingFinish(self: *Engine, id: ast.Id) T.Error!void {
        if (!self.source_validation or self.source_annotation_failed) return;
        const before = self.diagnostics.items.len;
        if (self.tree.node(id).tag == .value_decl) {
            const declaration = self.tree.valueDecl(id);
            try self.beginQualification(id, declaration.where_node, declaration.annotation, declaration.body);
        } else {
            const binding = self.tree.binding(id);
            try self.beginQualification(id, binding.where_node, binding.annotation, binding.value);
        }
        self.source_annotation_failed = self.diagnostics.items.len != before;
    }
    pub fn sourceBindingEnd(self: *Engine, saved: SourceAnnotationScope) void {
        if (!self.source_validation) return;
        self.type_env.shrinkRetainingCapacity(saved.types);
        self.row_env.shrinkRetainingCapacity(saved.rows);
        self.computation_annotations.shrinkRetainingCapacity(saved.computations);
        self.annotation_binding = saved.binding;
        self.inherited_types = saved.inherited_types;
        self.inherited_rows = saved.inherited_rows;
    }
    pub fn sourceExpressionAnnotations(self: *Engine, id: ast.Id) T.Error!void {
        if (!self.source_validation or self.source_annotation_failed) return;
        const before = self.diagnostics.items.len;
        const node = self.tree.node(id);
        if (node.tag == .lambda) {
            const parameter = self.tree.parameter(node.a);
            if (parameter.where_node != 0) try self.diagnostic(.higher_rank_constraint, parameter.where_node);
            if (parameter.annotation != 0) _ = try self.annotation(parameter.annotation);
            if (node.c != 0) _ = try self.annotation(node.c);
        } else if (node.tag == .use_stmt and node.c != 0) {
            _ = try self.annotation(node.c);
        }
        self.source_annotation_failed = self.diagnostics.items.len != before;
    }
    fn importHeader(self: *Engine, imported: SourceHeader) T.Error!void {
        std.debug.assert(self.source_validation);
        const key: Qualified = .{ .namespace = imported.namespace, .member = imported.member };
        if (imported.expose and ((imported.namespace == 0 and self.globals.contains(imported.name)) or (imported.namespace != 0 and self.qualified.contains(key)))) {
            try self.diagnostic(.duplicate_name, imported.origin);
            return;
        }
        const binding = self.external_targets.get(imported.target) orelse fresh: {
            const fresh = try self.addBinding(.{ .name = if (imported.namespace == 0) imported.name else imported.member, .declaration = imported.origin, .owner = imported.origin, .kind = .external, .ty = try self.types.fresh(), .named_function = imported.named_function, .external = imported.target });
            try self.external_targets.put(self.allocator, imported.target, fresh);
            break :fresh fresh;
        };
        if (!imported.expose) return;
        if (imported.namespace == 0) try self.globals.put(self.allocator, imported.name, binding) else try self.qualified.put(self.allocator, key, binding);
    }
    fn importBinding(self: *Engine, imported: ImportedBinding) T.Error!void {
        const key: Qualified = .{ .namespace = imported.namespace, .member = imported.member };
        if (imported.expose and ((imported.namespace == 0 and self.globals.contains(imported.name)) or
            (imported.namespace != 0 and self.qualified.contains(key))))
        {
            try self.diagnostic(.duplicate_name, imported.origin);
            return;
        }
        var binding = self.external_targets.get(imported.target);
        if (binding == null) {
            const interface = imported.interface;
            var copier: SchemeCopier = .{ .allocator = self.allocator, .source = interface.types, .destination = &self.types };
            defer copier.deinit();
            var variables: std.ArrayList(T.Id) = .empty;
            defer variables.deinit(self.allocator);
            for (copier.source.list(interface.scheme.variables)) |old| {
                const fresh = try self.types.fresh();
                try copier.mapping.put(self.allocator, copier.source.head(old, 0), fresh);
                try variables.append(self.allocator, fresh);
            }
            const row_variables = try copier.quantifiedRows(interface.scheme.row_variables);
            const closed_rows = try copier.quantifiedRows(interface.scheme.closed_rows);
            const root = try copier.copy(interface.scheme.root, 0);
            const start: u32 = @intCast(self.obligations.items.len);
            const range = interface.scheme.obligations;
            for (interface.obligations[range.start..][0..range.len]) |constraint| {
                try self.obligations.append(self.allocator, .{ .ty = try copier.copy(constraint.ty, 0), .kind = constraint.kind, .source = imported.origin, .name = constraint.name, .result = if (constraint.result == 0) 0 else try copier.copy(constraint.result, 0), .other = if (constraint.other == 0) 0 else try copier.copy(constraint.other, 0), .signature = if (constraint.signature == 0) 0 else try copier.copy(constraint.signature, 0), .operator = constraint.operator, .identity = constraint.identity, .explicit = constraint.explicit, .qualification_span = constraint.qualification_span, .qualification_unit = constraint.qualification_unit });
            }
            const principal: T.Scheme = .{ .root = root, .variables = try self.types.saveList(variables.items), .row_variables = row_variables, .closed_rows = closed_rows, .obligations = .{ .start = start, .len = @intCast(self.obligations.items.len - start) } };
            binding = try self.addBinding(.{ .name = if (imported.namespace == 0) imported.name else imported.member, .declaration = imported.origin, .owner = imported.origin, .kind = .external, .ty = root, .scheme = principal, .named_function = interface.named_function, .external = imported.target });
            try self.external_targets.put(self.allocator, imported.target, binding.?);
        }
        if (!imported.expose) return;
        if (imported.namespace == 0) try self.globals.put(self.allocator, imported.name, binding.?) else try self.qualified.put(self.allocator, key, binding.?);
    }

    fn appendPending(self: *Engine, item: PendingObligation) Allocator.Error!void {
        var value = item;
        value.scope = self.qualification_scope;
        value.method_member = value.method_member or (value.value.kind == .receiver and !value.value.explicit);
        try self.pending.append(self.allocator, value);
    }
    fn diagnostic(self: *Engine, code: Code, id: ast.Id) Allocator.Error!void {
        const origin = tagOrigin(self.tag_origins, self.tree.span(id));
        const source = if (origin == 0) id else origin;
        var span = self.tree.span(source);
        if (origin == 0 and self.tree.node(id).tag == .binary and (code == .type_mismatch or code == .effect_mismatch or code == .infinite_type or code == .infinite_effect)) {
            const point = source_operators.origin(self.tree, id);
            span = .{ .start = point, .end = point };
        }
        try self.diagnostics.append(self.allocator, .{ .code = code, .span = span, .node = source });
    }
    fn constrain(self: *Engine, a: T.Id, b: T.Id, id: ast.Id) T.Error!void {
        self.types.unify(a, b) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.InfiniteType => try self.diagnostic(.infinite_type, id),
            error.TypeMismatch => try self.diagnostic(.type_mismatch, id),
            error.InfiniteEffect => try self.diagnostic(.infinite_effect, id),
            error.EffectMismatch => try self.diagnostic(.effect_mismatch, id),
            error.TypeLimit => try self.diagnostic(.nesting_limit, id),
        };
    }
    fn constrainEffects(self: *Engine, left: T.Effects.Id, right: T.Effects.Id, source: ast.Id) T.Error!void {
        self.types.unifyEffects(left, right) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.EffectMismatch => try self.diagnostic(.effect_mismatch, source),
            error.InfiniteEffect => try self.diagnostic(.infinite_effect, source),
            else => return err,
        };
    }
    fn invocation(self: *Engine, parameter: T.Id, result: T.Id) T.Error!T.Id {
        return self.types.functionWithEffects(parameter, result, self.ambient);
    }
    fn invocationBinary(self: *Engine, left: T.Id, right: T.Id, result: T.Id) T.Error!T.Id {
        return self.invocation(left, try self.invocation(right, result));
    }
    fn pureExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        const saved = self.ambient;
        self.ambient = try self.types.freshEffects();
        defer self.ambient = saved;
        const result = try self.expression(id);
        self.types.unifyEffects(self.ambient, 0) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.EffectMismatch => try self.diagnostic(.let_effect, id),
            error.InfiniteEffect => try self.diagnostic(.infinite_effect, id),
            else => return err,
        };
        return result;
    }
    fn recordClosedRows(self: *Engine, owner: BindingId, rows: T.List) T.Error!void {
        for (self.types.list(rows)) |variable| {
            const key: ClosedRow = .{ .owner = owner, .variable = variable };
            const entry = try self.closed_row_keys.getOrPut(self.allocator, key);
            if (!entry.found_existing) try self.body_closed_rows.append(self.allocator, key);
        }
    }
    fn certifyLambda(self: *Engine, source: ast.Id, raw_type: T.Id, parent_row: T.Effects.Id) T.Error!void {
        const function = self.types.node(try self.types.resolve(raw_type, 0));
        const tail = self.types.row(function.c).tail;
        if (tail != .variable) return;
        var protected: std.ArrayList(u32) = .empty;
        defer protected.deinit(self.allocator);
        const environment = try self.environmentRows();
        defer self.allocator.free(environment);
        try protected.appendSlice(self.allocator, environment);
        const parent = self.types.effects.freeVariables(parent_row) catch |err| return T.effectError(err);
        defer self.allocator.free(parent);
        for (parent) |variable| if (!inList(protected.items, variable)) try protected.append(self.allocator, variable);
        for (self.pending.items[self.pending_start..]) |pending| if (!pending.solved and pending.owner == self.current) {
            for ([_]T.Id{ pending.value.ty, pending.value.other, pending.value.result, pending.value.signature }) |part| {
                if (part == 0) continue;
                const free = try self.types.freeRowVariables(part);
                defer self.allocator.free(free);
                for (free) |variable| if (!inList(protected.items, variable)) try protected.append(self.allocator, variable);
            }
        };
        const decision = try self.types.closeCovariantCertified(try self.types.resolve(raw_type, 0), &.{tail.variable}, protected.items);
        if (decision.closed_rows.len == 0) return;
        try self.row_sources.put(self.allocator, tail.variable, source);
        try self.recordClosedRows(self.current, decision.closed_rows);
    }
    fn addBinding(self: *Engine, value: Binding) Allocator.Error!BindingId {
        const id: BindingId = @intCast(self.bindings.items.len);
        try self.bindings.append(self.allocator, value);
        return id;
    }
    fn lookup(self: *const Engine, name: symbols.Symbol) ?BindingId {
        var i = self.env.items.len;
        while (i != 0) {
            i -= 1;
            if (self.env.items[i].name == name) return self.env.items[i].binding;
        }
        return null;
    }
    fn inList(values: []const T.Id, wanted: T.Id) bool {
        for (values) |value| if (value == wanted) return true;
        return false;
    }
    fn catalogKey(self: *const Engine, name: symbols.Symbol) Qualified {
        return self.qualifiedKey(name) orelse .{ .namespace = 0, .member = name };
    }
    fn memberOperator(name: []const u8) T.Operator {
        const members = [_]struct { []const u8, T.Operator }{ .{ "add", .add }, .{ "sub", .sub }, .{ "mul", .mul }, .{ "div", .div }, .{ "rem", .rem }, .{ "eq", .equal }, .{ "ne", .not_equal }, .{ "lt", .less }, .{ "le", .less_equal }, .{ "gt", .greater }, .{ "ge", .greater_equal }, .{ "bit_and", .bit_and }, .{ "bit_or", .bit_or }, .{ "bit_xor", .bit_xor }, .{ "shl", .shift_left }, .{ "shr", .shift_right } };
        for (members) |member| if (std.mem.eql(u8, name, member[0])) return member[1];
        return .none;
    }
    fn symbolOperator(name: []const u8) T.Operator {
        const operators = [_]struct { []const u8, T.Operator }{ .{ "+", .add }, .{ "-", .sub }, .{ "*", .mul }, .{ "/", .div }, .{ "%", .rem }, .{ "==", .equal }, .{ "!=", .not_equal }, .{ "<", .less }, .{ "<=", .less_equal }, .{ ">", .greater }, .{ ">=", .greater_equal }, .{ "&", .bit_and }, .{ "|", .bit_or }, .{ "^", .bit_xor }, .{ "<<", .shift_left }, .{ ">>", .shift_right } };
        for (operators) |operator| if (std.mem.eql(u8, name, operator[0])) return operator[1];
        return .none;
    }
    fn identityOf(self: *const Engine, ty: T.Id) ?Identity {
        const n = self.types.node(self.types.head(ty, 0));
        return switch (n.tag) {
            .nominal => .{ .unit = n.a, .decl = n.b },
            .u32 => .{ .unit = 0, .decl = T.u32_type },
            .f32 => .{ .unit = 0, .decl = T.f32_type },
            .boolean => .{ .unit = 0, .decl = T.boolean },
            .unit => .{ .unit = 0, .decl = T.unit },
            .array => .{ .unit = 0, .decl = std.math.maxInt(u32) },
            .list => .{ .unit = 0, .decl = std.math.maxInt(u32) - 1 },
            .cursor => .{ .unit = 0, .decl = std.math.maxInt(u32) - 2 },
            else => null,
        };
    }
    fn indexAssociated(self: *Engine) T.Error!void {
        var globals = self.globals.iterator();
        while (globals.next()) |entry| {
            const text = self.pool.get(entry.key_ptr.*);
            const dot = std.mem.lastIndexOfScalar(u8, text, '.') orelse continue;
            const head = text[0..dot];
            const member = self.pool.lookup(text[dot + 1 ..]) orelse continue;
            var identity: ?Identity = null;
            if (self.pool.lookup(head)) |name| if (self.nominal_names.get(.{ .namespace = 0, .member = name })) |index| {
                // Alias-qualified values remain ordinary namespace bindings;
                // aliases introduce no nominal owner for associated dispatch.
                if (self.nominals.items[index].alias == 0) identity = self.nominals.items[index].identity;
            };
            if (identity == null and self.builtin_catalog) {
                if (std.mem.eql(u8, head, "U32")) identity = .{ .unit = 0, .decl = T.u32_type } else if (std.mem.eql(u8, head, "F32")) identity = .{ .unit = 0, .decl = T.f32_type } else if (std.mem.eql(u8, head, "Bool")) identity = .{ .unit = 0, .decl = T.boolean } else if (std.mem.eql(u8, head, "Unit")) identity = .{ .unit = 0, .decl = T.unit } else if (std.mem.eql(u8, head, "Array")) identity = .{ .unit = 0, .decl = std.math.maxInt(u32) } else if (std.mem.eql(u8, head, "List")) identity = .{ .unit = 0, .decl = std.math.maxInt(u32) - 1 } else if (std.mem.eql(u8, head, "Cursor")) identity = .{ .unit = 0, .decl = std.math.maxInt(u32) - 2 };
            }
            if (identity) |owner| {
                if (owner.unit != 0 and owner.unit != self.unit) continue;
                const operator = memberOperator(text[dot + 1 ..]);
                const index: u32 = @intCast(self.associated.items.len);
                try self.associated.append(self.allocator, .{ .identity = owner, .member = member, .operator = operator, .binding = entry.value_ptr.* });
                try self.associated_members.put(self.allocator, .{ .identity = owner, .member = member }, index);
                if (operator != .none) try self.associated_ops.put(self.allocator, .{ .identity = owner, .operator = operator }, index);
            }
        }
    }
    fn tryAssociated(self: *Engine, identity: Identity, member: symbols.Symbol, operator: T.Operator, left: T.Id, right: T.Id, source: ast.Id) T.Error!?struct { ty: T.Id, binding: BindingId } {
        const index = (if (member == 0) self.associated_ops.get(.{ .identity = identity, .operator = operator }) else self.associated_members.get(.{ .identity = identity, .member = member })) orelse return null;
        const binding = self.associated.items[index].binding;
        try self.prepareGlobal(binding);
        const point = self.types.mark();
        const pending = self.pending.items.len;
        const function = try self.instantiate(binding, source);
        const result = try self.types.fresh();
        const expected = try self.invocationBinary(left, right, result);
        self.types.unify(function, expected) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.TypeMismatch, error.InfiniteType, error.EffectMismatch, error.InfiniteEffect => {
                self.types.rollback(point);
                self.pending.shrinkRetainingCapacity(pending);
                return null;
            },
            error.TypeLimit => return err,
        };
        self.dispatch_signatures[source] = expected;
        return .{ .ty = result, .binding = binding };
    }
    fn dispatch(self: *Engine, left: T.Id, right: T.Id, member: symbols.Symbol, operator: T.Operator, source: ast.Id, direct: bool) T.Error!?T.Id {
        const a = try self.types.resolve(left, 0);
        const b = try self.types.resolve(right, 0);
        const an = self.types.node(a);
        const bn = self.types.node(b);
        if (an.tag == .variable or bn.tag == .variable) return null;
        if (self.identityOf(a)) |identity| if (try self.tryAssociated(identity, member, operator, a, b, source)) |choice| {
            if (direct) self.resolved[source] = choice.binding;
            return choice.ty;
        };
        const scalar_a = an.tag == .u32 or an.tag == .f32 or an.tag == .boolean;
        const scalar_b = bn.tag == .u32 or bn.tag == .f32 or bn.tag == .boolean;
        if (member == 0 and scalar_a and scalar_b and an.tag == bn.tag) {
            const comparison = operator == .equal or operator == .not_equal or operator == .less or operator == .less_equal or operator == .greater or operator == .greater_equal;
            const equality = operator == .equal or operator == .not_equal;
            const integer = operator == .rem or operator == .bit_and or operator == .bit_or or operator == .bit_xor or operator == .shift_left or operator == .shift_right;
            if (an.tag == .boolean and !equality or an.tag == .f32 and integer) {
                try self.diagnostic(.ambiguous_operator, source);
                return try self.types.fresh();
            }
            return if (comparison) T.boolean else a;
        }
        if (self.identityOf(b)) |identity| if (try self.tryAssociated(identity, member, operator, a, b, source)) |choice| {
            if (direct) self.resolved[source] = choice.binding;
            return choice.ty;
        };
        if (member != 0) return null;
        try self.diagnostic(.ambiguous_operator, source);
        return try self.types.fresh();
    }
    fn resultDispatch(self: *Engine, input: T.Id, expected: T.Id, member: symbols.Symbol, source: ast.Id, direct: bool) T.Error!?T.Id {
        const destination = try self.types.resolve(expected, 0);
        const identity = self.identityOf(destination) orelse return null;
        const index = self.associated_members.get(.{ .identity = identity, .member = member }) orelse return null;
        const binding = self.associated.items[index].binding;
        try self.prepareGlobal(binding);
        const function = try self.instantiate(binding, source);
        // Destination lookup selects exactly one ordinary unary member. Unlike
        // binary dispatch, an incompatible selected signature has no fallback.
        const expected_function = try self.invocation(input, destination);
        try self.constrain(function, expected_function, source);
        self.dispatch_signatures[source] = expected_function;
        if (direct) self.resolved[source] = binding;
        return destination;
    }
    fn resolverDispatch(self: *Engine, pending: PendingObligation) T.Error!bool {
        const constraint = pending.value;
        const owner = self.types.node(try self.types.resolve(constraint.ty, 0));
        if (owner.tag == .variable) return false;
        if (owner.tag != .resolver) {
            try self.diagnostic(.invalid_provider, constraint.source);
            return true;
        }
        const token = self.types.node(try self.types.resolve(owner.a, 0));
        if (token.tag == .variable) return false;
        if (token.tag != .type_constructor) {
            try self.diagnostic(.type_constructor_required, constraint.source);
            return true;
        }
        const selected = self.associated_members.get(.{ .identity = .{ .unit = token.a, .decl = token.b }, .member = constraint.name }) orelse return false;
        const binding = self.associated.items[selected].binding;
        try self.prepareGlobal(binding);
        // The protocol's selected ordinary method determines every input,
        // continuation and output type. No wrapper shape or fallback is implied.
        const function = try self.instantiate(binding, constraint.source);
        try self.constrain(function, constraint.other, constraint.source);
        if (pending.metadata != 0) self.resolver_ops.items[pending.metadata - 1].method = binding;
        return true;
    }
    fn typeVariable(self: *Engine, name: symbols.Symbol, source: ast.Id) T.Error!T.Id {
        for (self.row_env.items, 0..) |entry, index| if (entry.name == name) {
            try self.diagnostic(.annotation_kind_mismatch, if (index < self.inherited_rows) self.annotation_binding else source);
            return self.types.fresh();
        };
        var i = self.type_env.items.len;
        while (i != 0) {
            i -= 1;
            if (self.type_env.items[i].name == name) return self.type_env.items[i].ty;
        }
        const ty = try self.types.fresh();
        if (self.closed_type_variables) {
            try self.diagnostic(.unsupported_type, source);
            return ty;
        }
        try self.type_env.append(self.allocator, .{ .name = name, .ty = ty });
        return ty;
    }
    fn rowVariable(self: *Engine, name: symbols.Symbol, source: ast.Id) T.Error!T.Effects.Id {
        for (self.type_env.items, 0..) |entry, index| if (entry.name == name) {
            try self.diagnostic(.annotation_kind_mismatch, if (index < self.inherited_types) self.annotation_binding else source);
            return self.types.freshEffects();
        };
        var i = self.row_env.items.len;
        while (i != 0) {
            i -= 1;
            if (self.row_env.items[i].name == name) return self.row_env.items[i].row;
        }
        const row = try self.types.freshEffects();
        if (self.closed_type_variables and !self.implicit_row_parameters) {
            try self.diagnostic(.invalid_effect_annotation, source);
            return row;
        }
        try self.row_env.append(self.allocator, .{ .name = name, .row = row });
        return row;
    }
    // A binding owns all of its written annotation names before any body is
    // checked. Nested lets collect their own names against that inherited scope.
    fn collectAnnotationNames(self: *Engine, id: ast.Id, depth: usize) T.Error!void {
        if (id == 0) return;
        if (depth >= 1024) return error.TypeLimit;
        const node = self.tree.node(id);
        switch (node.tag) {
            .let_stmt => if (self.source_validation) {
                // Source annotation_scope collects written free annotation
                // names across the whole declaration before lowering bodies.
                // Inference instead creates a fresh scope at each local let.
                const binding = self.tree.binding(id);
                try self.collectAnnotationNames(binding.annotation, depth + 1);
                try self.collectAnnotationNames(binding.where_node, depth + 1);
                try self.collectAnnotationNames(binding.value, depth + 1);
                try self.collectAnnotationNames(binding.fallback, depth + 1);
            },
            .type_name => {
                const name = self.pool.get(node.a);
                if (name.len != 0 and (std.ascii.isLower(name[0]) or name[0] == '_') and std.mem.indexOfScalar(u8, name, '.') == null) _ = try self.typeVariable(node.a, id);
            },
            .effect_row => {
                if (node.c != 0) _ = try self.rowVariable(self.tree.node(node.c).a, node.c);
                for (self.tree.list(.{ .start = node.a, .len = node.b })) |label| try self.collectEffectArgumentNames(label, depth + 1);
            },
            .where_clause => {
                for (self.tree.list(.{ .start = node.a, .len = node.b })) |child| try self.collectAnnotationNames(child, depth + 1);
            },
            .constraint => {
                const details = self.tree.extra.items[node.c..][0..3];
                const arguments = self.tree.list(.{ .start = details[0], .len = details[1] });
                const skip: usize = if (std.mem.eql(u8, self.pool.get(node.a), "operation") and arguments.len != 0) 1 else 0;
                for (arguments[skip..]) |child| try self.collectAnnotationNames(child, depth + 1);
                try self.collectAnnotationNames(details[2], depth + 1);
            },
            .lambda => {
                try self.collectAnnotationNames(self.tree.parameter(node.a).annotation, depth + 1);
                try self.collectAnnotationNames(node.c, depth + 1);
                try self.collectAnnotationNames(node.b, depth + 1);
            },
            .group, .type_demand, .type_witness, .field_access, .return_stmt, .yield_stmt, .forever_stmt => try self.collectAnnotationNames(node.a, depth + 1),
            .field, .unary, .operator_tail => try self.collectAnnotationNames(node.b, depth + 1),
            .type_field => {
                if (node.b == 0) _ = try self.typeVariable(node.a, id) else try self.collectAnnotationNames(node.b, depth + 1);
            },
            .apply, .index_access, .rebind_stmt, .type_apply, .type_effect => {
                try self.collectAnnotationNames(node.a, depth + 1);
                try self.collectAnnotationNames(node.b, depth + 1);
            },
            .binary => {
                try self.collectAnnotationNames(node.b, depth + 1);
                try self.collectAnnotationNames(node.c, depth + 1);
            },
            .type_function, .if_expr, .if_stmt, .range_stmt => {
                try self.collectAnnotationNames(node.a, depth + 1);
                try self.collectAnnotationNames(node.b, depth + 1);
                try self.collectAnnotationNames(node.c, depth + 1);
            },
            .use_stmt, .iterator_bind => {
                try self.collectAnnotationNames(node.c, depth + 1);
                try self.collectAnnotationNames(node.b, depth + 1);
            },
            .product, .array, .record, .type_product, .type_array, .type_record => {
                for (self.tree.children(id)) |child| try self.collectAnnotationNames(child, depth + 1);
            },
            .block => {
                try self.collectAnnotationNames(node.c, depth + 1);
                for (self.tree.children(id)) |child| try self.collectAnnotationNames(child, depth + 1);
            },
            .infix_chain => {
                try self.collectAnnotationNames(node.a, depth + 1);
                for (self.tree.list(.{ .start = node.b, .len = node.c })) |child| try self.collectAnnotationNames(child, depth + 1);
            },
            .if_let_stmt, .for_stmt => {
                try self.collectAnnotationNames(node.b, depth + 1);
                const metadata = self.tree.extra.items[node.c..];
                try self.collectAnnotationNames(metadata[0], depth + 1);
                try self.collectAnnotationNames(metadata[1], depth + 1);
            },
            .case_expr, .request_case => {
                const inputs = self.tree.extra.items[node.a..][0..2];
                for (self.tree.list(.{ .start = inputs[0], .len = inputs[1] })) |child| try self.collectAnnotationNames(child, depth + 1);
                for (self.tree.list(.{ .start = node.b, .len = node.c })) |child| try self.collectAnnotationNames(child, depth + 1);
            },
            .case_arm => {
                const metadata = self.tree.extra.items[node.c..][0..2];
                try self.collectAnnotationNames(metadata[0], depth + 1);
                try self.collectAnnotationNames(metadata[1], depth + 1);
            },
            .request_arm => {
                try self.collectAnnotationNames(node.a, depth + 1);
                try self.collectAnnotationNames(node.c, depth + 1);
            },
            else => {},
        }
    }
    fn collectEffectArgumentNames(self: *Engine, id: ast.Id, depth: usize) T.Error!void {
        if (depth >= 1024) return error.TypeLimit;
        const node = self.tree.node(id);
        if (node.tag == .type_apply) {
            try self.collectEffectArgumentNames(node.a, depth + 1);
            try self.collectAnnotationNames(node.b, depth + 1);
        }
    }
    fn nominalIndex(self: *const Engine, identity: Identity) ?u32 {
        return self.nominal_identities.get(identity);
    }
    fn copyNominal(self: *Engine, producer: DeclarationCatalog, source_index: u32) T.Error!u32 {
        const source = producer.nominals[source_index];
        if (self.nominalIndex(source.identity)) |index| return index;
        var copier: SchemeCopier = .{ .allocator = self.allocator, .source = producer.types, .destination = &self.types };
        defer copier.deinit();
        var variables: std.ArrayList(T.Id) = .empty;
        defer variables.deinit(self.allocator);
        for (producer.types.list(source.variables)) |old| {
            const fresh = try self.types.fresh();
            try copier.mapping.put(self.allocator, producer.types.head(old, 0), fresh);
            try variables.append(self.allocator, fresh);
        }
        var parameters: std.ArrayList(T.Id) = .empty;
        defer parameters.deinit(self.allocator);
        for (producer.types.list(source.parameters)) |old| try parameters.append(self.allocator, try copier.copy(old, 0));
        const index: u32 = @intCast(self.nominals.items.len);
        const quantified = try self.types.saveList(variables.items);
        const names = try self.types.saveList(producer.types.list(source.parameter_names));
        const patterns = try self.copyParameterPatterns(producer.parameter_patterns, source.patterns, &copier);
        const alias_rows = try copier.quantifiedRows(source.alias_rows);
        try self.nominals.append(self.allocator, .{ .identity = source.identity, .name = source.name, .variables = quantified, .parameters = try self.types.saveList(parameters.items), .patterns = patterns, .parameter_names = names, .alias_rows = alias_rows, .alias = if (source.alias == 0) 0 else try copier.copy(source.alias, 0) });
        try self.nominal_identities.put(self.allocator, source.identity, index);
        var constructors: std.ArrayList(T.Id) = .empty;
        defer constructors.deinit(self.allocator);
        for (producer.types.list(source.constructors)) |old| {
            const ctor = producer.constructors[old];
            const own: u32 = @intCast(self.constructors.items.len);
            try self.constructors.append(self.allocator, .{ .identity = ctor.identity, .nominal = index, .tag = ctor.tag, .name = ctor.name, .scheme = .{ .root = try copier.copy(ctor.scheme.root, 0), .variables = quantified }, .payload = if (ctor.payload == 0) 0 else try copier.copy(ctor.payload, 0), .declared_record = ctor.declared_record });
            try self.constructor_identities.put(self.allocator, ctor.identity, own);
            try constructors.append(self.allocator, own);
        }
        self.nominals.items[index].constructors = try self.types.saveList(constructors.items);
        return index;
    }
    fn copyEffectFamily(self: *Engine, producer: DeclarationCatalog, source_index: u32) T.Error!u32 {
        const source = producer.effect_families[source_index];
        if (self.effect_family_identities.get(source.identity)) |known| return known;
        var copier: SchemeCopier = .{ .allocator = self.allocator, .source = producer.types, .destination = &self.types };
        defer copier.deinit();
        var variables: std.ArrayList(T.Id) = .empty;
        defer variables.deinit(self.allocator);
        for (producer.types.list(source.variables)) |old| {
            const fresh = try self.types.fresh();
            try copier.mapping.put(self.allocator, producer.types.head(old, 0), fresh);
            try variables.append(self.allocator, fresh);
        }
        var parameters: std.ArrayList(T.Id) = .empty;
        defer parameters.deinit(self.allocator);
        for (producer.types.list(source.parameters)) |old| try parameters.append(self.allocator, try copier.copy(old, 0));
        if (self.effect_families.items.len == std.math.maxInt(u32)) return error.TypeLimit;
        const family: u32 = @intCast(self.effect_families.items.len);
        const patterns = try self.copyParameterPatterns(producer.parameter_patterns, source.patterns, &copier);
        try self.effect_families.append(self.allocator, .{ .identity = source.identity, .name = source.name, .callable = source.callable, .variables = try self.types.saveList(variables.items), .parameters = try self.types.saveList(parameters.items), .patterns = patterns, .parameter_names = try self.types.saveList(producer.types.list(source.parameter_names)) });
        try self.effect_family_identities.put(self.allocator, source.identity, family);
        var operations: std.ArrayList(T.Id) = .empty;
        defer operations.deinit(self.allocator);
        for (producer.types.list(source.operations)) |old| {
            const template = producer.effect_templates[old];
            if (self.effect_templates.items.len == std.math.maxInt(u32)) return error.TypeLimit;
            const index: u32 = @intCast(self.effect_templates.items.len);
            try self.effect_templates.append(self.allocator, .{ .identity = template.identity, .family = family, .name = template.name, .parameter = try copier.copy(template.parameter, 0), .result = try copier.copy(template.result, 0) });
            try self.effect_members.put(self.allocator, .{ .family = family, .member = template.name }, index);
            try self.effect_template_identities.put(self.allocator, template.identity, index);
            try operations.append(self.allocator, index);
        }
        self.effect_families.items[family].operations = try self.types.saveList(operations.items);
        return family;
    }
    fn importCatalog(self: *Engine, imported: anytype) T.Error!void {
        const producer = if (@TypeOf(imported) == SourceCatalog) imported.producer else imported.catalog();
        if (imported.kind == .catalog) {
            for (1..producer.nominals.len) |index| _ = try self.copyNominal(producer, @intCast(index));
            for (1..producer.effect_families.len) |index| _ = try self.copyEffectFamily(producer, @intCast(index));
            for (0..producer.contracts.len) |index| _ = try self.copyContract(producer, @intCast(index));
            for (producer.associated) |method| {
                const definition = if (@TypeOf(imported) == SourceCatalog) imported.declarations[method.binding] else imported.declaration(method.binding);
                const target = definition.external orelse ExternalTarget{ .unit = producer.unit, .binding = method.binding };
                if (@TypeOf(imported) == SourceCatalog) try self.importHeader(.{ .target = target, .named_function = definition.named_function, .origin = imported.origin, .expose = false }) else if (self.source_validation) try self.importHeader(.{ .target = target, .named_function = definition.named_function, .origin = imported.origin, .expose = false }) else try self.importBinding(.{ .target = target, .interface = imported.interface(method.binding), .origin = imported.origin, .expose = false });
                const binding = self.external_targets.get(target).?;
                var present = false;
                for (self.associated.items) |prior| if (prior.identity.unit == method.identity.unit and prior.identity.decl == method.identity.decl and prior.member == method.member and prior.binding == binding) {
                    present = true;
                    break;
                };
                if (!present) {
                    const index: u32 = @intCast(self.associated.items.len);
                    try self.associated.append(self.allocator, .{ .identity = method.identity, .member = method.member, .operator = method.operator, .binding = binding });
                    try self.associated_members.put(self.allocator, .{ .identity = method.identity, .member = method.member }, index);
                    if (method.operator != .none) try self.associated_ops.put(self.allocator, .{ .identity = method.identity, .operator = method.operator }, index);
                }
            }
            return;
        }
        if (imported.kind == .effect_family) {
            const family = try self.copyEffectFamily(producer, imported.index);
            const effect_key: Qualified = .{ .namespace = imported.namespace, .member = imported.name };
            if (self.effect_family_names.contains(effect_key) or self.nominal_names.contains(effect_key)) try self.diagnostic(.duplicate_name, imported.origin) else try self.effect_family_names.put(self.allocator, effect_key, family);
            if (self.effect_families.items[family].callable) {
                const operations = self.types.list(self.effect_families.items[family].operations);
                if (operations.len != 1) return error.TypeLimit;
                try self.effect_operation_names.put(self.allocator, effect_key, operations[0]);
            }
            return;
        }
        const key: Qualified = .{ .namespace = imported.namespace, .member = imported.name };
        if (imported.kind == .contract) {
            const index = try self.copyContract(producer, imported.index);
            if (self.contract_names.contains(key) or self.nominal_names.contains(key)) try self.diagnostic(.duplicate_name, imported.origin) else try self.contract_names.put(self.allocator, key, index);
            return;
        }
        if (imported.kind == .nominal) {
            const index = try self.copyNominal(producer, imported.index);
            if (self.nominal_names.contains(key)) try self.diagnostic(.duplicate_name, imported.origin) else try self.nominal_names.put(self.allocator, key, index);
        } else {
            const source = producer.constructors[imported.index];
            _ = try self.copyNominal(producer, source.nominal);
            const index = self.constructor_identities.get(source.identity).?;
            if (self.constructor_names.contains(key)) try self.diagnostic(.duplicate_name, imported.origin) else try self.constructor_names.put(self.allocator, key, index);
        }
    }
    fn constructorType(self: *Engine, index: u32) T.Error!T.Id {
        return self.constructorUse(index, false);
    }
    fn copyContract(self: *Engine, producer: DeclarationCatalog, source_index: u32) T.Error!u32 {
        const source = producer.contracts[source_index];
        if (self.contract_identities.get(source.identity)) |known| return known;
        var copier: SchemeCopier = .{ .allocator = self.allocator, .source = producer.types, .destination = &self.types };
        defer copier.deinit();
        var variables: std.ArrayList(T.Id) = .empty;
        defer variables.deinit(self.allocator);
        for (producer.types.list(source.variables)) |old| {
            const fresh = try self.types.fresh();
            try copier.mapping.put(self.allocator, producer.types.head(old, 0), fresh);
            try variables.append(self.allocator, fresh);
        }
        const rows = try copier.quantifiedRows(source.row_variables);
        var parameters: std.ArrayList(T.Id) = .empty;
        defer parameters.deinit(self.allocator);
        for (producer.types.list(source.parameters)) |old| try parameters.append(self.allocator, try copier.copy(old, 0));
        const start: u32 = @intCast(self.contract_predicates.items.len);
        for (producer.contract_predicates[source.predicates.start..][0..source.predicates.len]) |old| {
            var predicate = old;
            inline for (.{ "ty", "other", "result", "signature" }) |field| @field(predicate, field) = try copier.copy(@field(old, field), 0);
            predicate.source = 0;
            try self.contract_predicates.append(self.allocator, predicate);
        }
        const index: u32 = @intCast(self.contracts.items.len);
        const patterns = try self.copyParameterPatterns(producer.parameter_patterns, source.patterns, &copier);
        try self.contracts.append(self.allocator, .{ .identity = source.identity, .name = source.name, .variables = try self.types.saveList(variables.items), .parameters = try self.types.saveList(parameters.items), .patterns = patterns, .parameter_names = try self.types.saveList(producer.types.list(source.parameter_names)), .row_variables = rows, .predicates = .{ .start = start, .len = source.predicates.len } });
        try self.contract_identities.put(self.allocator, source.identity, index);
        return index;
    }
    fn contractHeaders(self: *Engine) T.Error!void {
        for (self.tree.roots.items) |id| {
            const node = self.tree.node(id);
            if (node.tag != .contract_decl) continue;
            const key: Qualified = .{ .namespace = 0, .member = node.a };
            if (self.contract_names.contains(key) or self.nominal_names.contains(key)) {
                try self.diagnostic(.duplicate_name, id);
                continue;
            }
            const meta = self.tree.extra.items[node.c..][0..4];
            if (meta[3] != 0) try self.diagnostic(.unsupported_attribute, id);
            self.type_env.clearRetainingCapacity();
            self.row_env.clearRetainingCapacity();
            var parameters: std.ArrayList(T.Id) = .empty;
            defer parameters.deinit(self.allocator);
            var patterns: std.ArrayList(P.Id) = .empty;
            defer patterns.deinit(self.allocator);
            for (self.tree.list(.{ .start = meta[0], .len = meta[1] })) |parameter| {
                const parsed = try self.parameterAnnotation(parameter, 0);
                try parameters.append(self.allocator, parsed.ty);
                try patterns.append(self.allocator, parsed.pattern);
            }
            var names: std.ArrayList(T.Id) = .empty;
            defer names.deinit(self.allocator);
            var variables: std.ArrayList(T.Id) = .empty;
            defer variables.deinit(self.allocator);
            for (self.type_env.items) |entry| {
                try names.append(self.allocator, entry.name);
                try variables.append(self.allocator, entry.ty);
            }
            const index: u32 = @intCast(self.contracts.items.len);
            const identity: Identity = .{ .unit = self.unit, .decl = id };
            try self.contracts.append(self.allocator, .{ .identity = identity, .name = node.a, .parameters = try self.types.saveList(parameters.items), .patterns = try self.parameter_patterns.saveList(self.allocator, patterns.items), .variables = try self.types.saveList(variables.items), .parameter_names = try self.types.saveList(names.items) });
            try self.contract_names.put(self.allocator, key, index);
            try self.contract_identities.put(self.allocator, identity, index);
        }
        self.type_env.clearRetainingCapacity();
        self.row_env.clearRetainingCapacity();
    }
    fn resolveContract(self: *Engine, index: u32) T.Error!void {
        const contract = self.contracts.items[index];
        if (contract.identity.unit != self.unit) return;
        if (self.contract_states.get(index)) |state| {
            if (state == .visiting) try self.diagnostic(.recursive_contract, contract.identity.decl);
            return;
        }
        if (self.contract_depth >= 256) return error.TypeLimit;
        self.contract_depth += 1;
        defer self.contract_depth -= 1;
        try self.contract_states.put(self.allocator, index, .visiting);
        const saved_types = self.type_env;
        const saved_rows = self.row_env;
        const saved_closed = self.closed_type_variables;
        const saved_alias_rows = self.implicit_row_parameters;
        self.type_env = .empty;
        self.row_env = .empty;
        self.closed_type_variables = true;
        self.implicit_row_parameters = true;
        defer {
            self.type_env.deinit(self.allocator);
            self.row_env.deinit(self.allocator);
            self.type_env = saved_types;
            self.row_env = saved_rows;
            self.closed_type_variables = saved_closed;
            self.implicit_row_parameters = saved_alias_rows;
        }
        for (0..contract.variables.len) |parameter| try self.type_env.append(self.allocator, .{ .name = self.types.list(contract.parameter_names)[parameter], .ty = self.types.list(contract.variables)[parameter] });
        const body = self.tree.node(contract.identity.decl).b;
        var predicates: std.ArrayList(T.Obligation) = .empty;
        defer predicates.deinit(self.allocator);
        const node = self.tree.node(body);
        for (self.tree.list(.{ .start = node.a, .len = node.b })) |child| try self.lowerPredicates(child, body, &predicates);
        var roots: std.ArrayList(T.Id) = .empty;
        defer roots.deinit(self.allocator);
        for (predicates.items) |*predicate| inline for (.{ "ty", "other", "result", "signature" }) |field| {
            const root = @field(predicate, field);
            if (root != 0) {
                @field(predicate, field) = try self.types.resolve(root, 0);
                try roots.append(self.allocator, @field(predicate, field));
            }
        };
        const row_variables = try self.types.freeRowVariables(try self.types.product(roots.items));
        defer self.allocator.free(row_variables);
        const start: u32 = @intCast(self.contract_predicates.items.len);
        try self.contract_predicates.appendSlice(self.allocator, predicates.items);
        self.contracts.items[index].predicates = .{ .start = start, .len = @intCast(predicates.items.len) };
        self.contracts.items[index].row_variables = try self.types.saveList(row_variables);
        try self.contract_states.put(self.allocator, index, .ready);
    }
    fn constructorStorageType(self: *Engine, index: u32) T.Error!T.Id {
        return self.constructorUse(index, true);
    }
    fn canonicalRecordType(self: *Engine, record: T.Node) T.Error!T.Id {
        if (record.b == 1) return self.types.recordField(record, 0).ty;
        var fields: std.ArrayList(T.Id) = .empty;
        defer fields.deinit(self.allocator);
        for (0..record.b) |index| try fields.append(self.allocator, self.types.recordField(record, index).ty);
        return self.types.product(fields.items);
    }
    fn constructorUse(self: *Engine, index: u32, storage: bool) T.Error!T.Id {
        const metadata = self.constructors.items[index];
        const principal = metadata.scheme;
        const root = if (storage and metadata.payload != 0 and self.types.node(metadata.payload).tag == .record) try self.types.function(metadata.payload, self.types.node(principal.root).b) else principal.root;
        const old = try self.allocator.dupe(T.Id, self.types.list(principal.variables));
        defer self.allocator.free(old);
        const fresh = try self.allocator.alloc(T.Id, old.len);
        defer self.allocator.free(fresh);
        for (fresh) |*id| id.* = try self.types.fresh();
        return self.types.substitute(root, old, fresh);
    }
    fn dataHeaders(self: *Engine) T.Error!void {
        for (self.tree.roots.items) |id| {
            const n = self.tree.node(id);
            if (n.tag != .data_decl and n.tag != .type_alias_decl) continue;
            const key: Qualified = .{ .namespace = 0, .member = n.a };
            if (self.nominal_names.contains(key)) {
                try self.diagnostic(.duplicate_name, id);
                continue;
            }
            const index: u32 = @intCast(self.nominals.items.len);
            try self.nominals.append(self.allocator, .{ .identity = .{ .unit = self.unit, .decl = id }, .name = n.a, .parameters = .{}, .variables = .{} });
            try self.nominal_identities.put(self.allocator, .{ .unit = self.unit, .decl = id }, index);
            try self.nominal_names.put(self.allocator, key, index);
        }
        for (self.nominals.items[1..], 1..) |nominal_, index| {
            if (nominal_.identity.unit != self.unit) continue;
            const n = self.tree.node(nominal_.identity.decl);
            const meta = self.tree.extra.items[n.c..][0..4];
            if (meta[3] != 0) try self.diagnostic(.unsupported_attribute, nominal_.identity.decl);
            self.type_env.clearRetainingCapacity();
            self.row_env.clearRetainingCapacity();
            var parameters: std.ArrayList(T.Id) = .empty;
            defer parameters.deinit(self.allocator);
            var patterns: std.ArrayList(P.Id) = .empty;
            defer patterns.deinit(self.allocator);
            for (self.tree.list(.{ .start = meta[0], .len = meta[1] })) |param| {
                const parsed = try self.parameterAnnotation(param, 0);
                try parameters.append(self.allocator, parsed.ty);
                try patterns.append(self.allocator, parsed.pattern);
            }
            var names: std.ArrayList(T.Id) = .empty;
            defer names.deinit(self.allocator);
            var variables: std.ArrayList(T.Id) = .empty;
            defer variables.deinit(self.allocator);
            for (self.type_env.items) |entry| {
                try names.append(self.allocator, entry.name);
                try variables.append(self.allocator, entry.ty);
            }
            self.nominals.items[index].parameters = try self.types.saveList(parameters.items);
            self.nominals.items[index].patterns = try self.parameter_patterns.saveList(self.allocator, patterns.items);
            self.nominals.items[index].variables = try self.types.saveList(variables.items);
            self.nominals.items[index].parameter_names = try self.types.saveList(names.items);
        }
        self.type_env.clearRetainingCapacity();
        self.row_env.clearRetainingCapacity();
    }
    fn resolveAlias(self: *Engine, index: u32) T.Error!T.Id {
        const nominal_ = self.nominals.items[index];
        if (nominal_.alias != 0) return nominal_.alias;
        if (nominal_.identity.unit != self.unit or self.tree.node(nominal_.identity.decl).tag != .type_alias_decl) return 0;
        if (self.active_aliases.contains(index)) {
            try self.diagnostic(.recursive_type_alias, nominal_.identity.decl);
            return self.types.fresh();
        }
        if (self.active_aliases.count() >= 256) return error.TypeLimit;
        try self.active_aliases.put(self.allocator, index, {});
        defer _ = self.active_aliases.remove(index);
        const saved_types = self.type_env;
        const saved_rows = self.row_env;
        const saved_closed = self.closed_type_variables;
        const saved_alias_rows = self.implicit_row_parameters;
        self.type_env = .empty;
        self.row_env = .empty;
        self.closed_type_variables = true;
        self.implicit_row_parameters = true;
        defer {
            self.type_env.deinit(self.allocator);
            self.row_env.deinit(self.allocator);
            self.type_env = saved_types;
            self.row_env = saved_rows;
            self.closed_type_variables = saved_closed;
            self.implicit_row_parameters = saved_alias_rows;
        }
        for (0..nominal_.variables.len) |parameter| {
            try self.type_env.append(self.allocator, .{ .name = self.types.list(nominal_.parameter_names)[parameter], .ty = self.types.list(nominal_.variables)[parameter] });
        }
        const target = try self.annotation(self.tree.node(nominal_.identity.decl).b);
        const rows = try self.types.freeRowVariables(target);
        defer self.allocator.free(rows);
        self.nominals.items[index].alias_rows = try self.types.saveList(rows);
        self.nominals.items[index].alias = target;
        return target;
    }
    fn aliasInstance(self: *Engine, index: u32, old: []const T.Id, fresh: []const T.Id, source: ast.Id) T.Error!?T.Id {
        const alias = try self.resolveAlias(index);
        if (alias == 0) return null;
        // Data/effect declarations cannot hide an unbound effect row in a
        // payload. Such a row must travel in an explicit type parameter;
        // otherwise values with different latent effects would share one type.
        if (self.closed_type_variables and !self.implicit_row_parameters and self.nominals.items[index].alias_rows.len != 0) {
            try self.diagnostic(.unbound_alias_row, source);
            return try self.types.fresh();
        }
        const rows = try self.allocator.dupe(u32, self.types.list(self.nominals.items[index].alias_rows));
        defer self.allocator.free(rows);
        const fresh_rows = try self.allocator.alloc(T.Effects.Id, rows.len);
        defer self.allocator.free(fresh_rows);
        for (fresh_rows) |*row| row.* = try self.types.freshEffects();
        return try self.types.substituteWithRows(alias, old, fresh, rows, fresh_rows);
    }
    fn dataBodies(self: *Engine) T.Error!void {
        self.closed_type_variables = true;
        defer self.closed_type_variables = false;
        var index: usize = 1;
        while (index < self.nominals.items.len) : (index += 1) {
            const nominal_ = self.nominals.items[index];
            if (nominal_.identity.unit != self.unit) continue;
            if (self.tree.node(nominal_.identity.decl).tag == .type_alias_decl) {
                _ = try self.resolveAlias(@intCast(index));
                continue;
            }
            self.type_env.clearRetainingCapacity();
            self.row_env.clearRetainingCapacity();
            const names = try self.allocator.dupe(T.Id, self.types.list(nominal_.parameter_names));
            defer self.allocator.free(names);
            const variables = try self.allocator.dupe(T.Id, self.types.list(nominal_.variables));
            defer self.allocator.free(variables);
            for (names, variables) |name, ty| try self.type_env.append(self.allocator, .{ .name = name, .ty = ty });
            const args = try self.allocator.dupe(T.Id, self.types.list(nominal_.parameters));
            defer self.allocator.free(args);
            const result = try self.types.nominal(nominal_.identity, args);
            var constructors: std.ArrayList(T.Id) = .empty;
            defer constructors.deinit(self.allocator);
            const declaration = self.tree.node(nominal_.identity.decl);
            for (self.tree.children(declaration.b), 0..) |id, tag| {
                const n = self.tree.node(id);
                const key = self.catalogKey(n.a);
                if (self.constructor_names.contains(key)) {
                    try self.diagnostic(.duplicate_name, id);
                    continue;
                }
                var payload = if (n.b == 0) 0 else try self.constructorPayloadAnnotation(n.b);
                if (payload != 0) {
                    const shape = self.types.node(payload);
                    if (shape.tag == .record and shape.b == 0) payload = 0;
                }
                const storage = self.types.node(payload);
                const parameter = if (payload != 0 and storage.tag == .record) try self.canonicalRecordType(storage) else payload;
                const ty = if (payload == 0) result else try self.types.function(parameter, result);
                const constructor: u32 = @intCast(self.constructors.items.len);
                try self.constructors.append(self.allocator, .{ .identity = .{ .unit = self.unit, .decl = id }, .nominal = @intCast(index), .tag = @intCast(tag), .name = n.a, .payload = payload, .declared_record = n.b != 0 and self.tree.node(n.b).tag == .type_record and self.tree.typeConversionOrigin(n.b) == self.tree.span(n.b).start, .scheme = .{ .root = ty, .variables = nominal_.variables } });
                try self.constructor_identities.put(self.allocator, .{ .unit = self.unit, .decl = id }, constructor);
                try self.constructor_names.put(self.allocator, key, constructor);
                try constructors.append(self.allocator, constructor);
                self.constructor_resolved[id] = constructor;
            }
            self.nominals.items[index].constructors = try self.types.saveList(constructors.items);
        }
        self.type_env.clearRetainingCapacity();
        self.row_env.clearRetainingCapacity();
    }
    fn effectHeaders(self: *Engine) T.Error!void {
        for (self.tree.roots.items) |id| {
            const n = self.tree.node(id);
            if (n.tag != .effect_decl and n.tag != .effect_type_decl) continue;
            const attributes = self.tree.extra.items[n.c..];
            if (attributes[if (n.tag == .effect_decl) @as(usize, 1) else 3] != 0) try self.diagnostic(.unsupported_attribute, id);
            if (std.mem.eql(u8, self.pool.get(n.a), "Foreign")) {
                try self.diagnostic(.sealed_effect, id);
                continue;
            }
            const key = self.catalogKey(n.a);
            if (self.effect_family_names.contains(key) or self.nominal_names.contains(key) or self.globals.contains(n.a)) {
                try self.diagnostic(.duplicate_name, id);
                continue;
            }
            self.type_env.clearRetainingCapacity();
            self.row_env.clearRetainingCapacity();
            var parameters: std.ArrayList(T.Id) = .empty;
            defer parameters.deinit(self.allocator);
            var patterns: std.ArrayList(P.Id) = .empty;
            defer patterns.deinit(self.allocator);
            if (n.tag == .effect_type_decl) {
                const meta = self.tree.extra.items[n.c..][0..4];
                for (self.tree.list(.{ .start = meta[0], .len = meta[1] })) |parameter| {
                    const parsed = try self.parameterAnnotation(parameter, 0);
                    try parameters.append(self.allocator, parsed.ty);
                    try patterns.append(self.allocator, parsed.pattern);
                }
            }
            var names: std.ArrayList(T.Id) = .empty;
            defer names.deinit(self.allocator);
            var variables: std.ArrayList(T.Id) = .empty;
            defer variables.deinit(self.allocator);
            for (self.type_env.items) |entry| {
                try names.append(self.allocator, entry.name);
                try variables.append(self.allocator, entry.ty);
            }
            if (self.effect_families.items.len == std.math.maxInt(u32)) return error.TypeLimit;
            const family: u32 = @intCast(self.effect_families.items.len);
            try self.effect_families.append(self.allocator, .{ .identity = .{ .unit = self.unit, .decl = id }, .name = n.a, .callable = self.tree.node(n.b).tag != .effect_operations, .patterns = try self.parameter_patterns.saveList(self.allocator, patterns.items), .parameters = try self.types.saveList(parameters.items), .variables = try self.types.saveList(variables.items), .parameter_names = try self.types.saveList(names.items) });
            try self.effect_family_names.put(self.allocator, key, family);
            try self.effect_family_identities.put(self.allocator, .{ .unit = self.unit, .decl = id }, family);
            var operations: std.ArrayList(T.Id) = .empty;
            defer operations.deinit(self.allocator);
            if (self.tree.node(n.b).tag == .effect_operations) {
                for (self.tree.children(n.b)) |member| {
                    const operation_ = self.tree.node(member);
                    if (self.effect_members.contains(.{ .family = family, .member = operation_.a })) {
                        try self.diagnostic(.duplicate_name, member);
                        continue;
                    }
                    const template = try self.effectSignature(family, member, operation_.a, operation_.b);
                    try self.effect_members.put(self.allocator, .{ .family = family, .member = operation_.a }, template);
                    try operations.append(self.allocator, template);
                }
            } else {
                const template = try self.effectSignature(family, id, n.a, n.b);
                try self.effect_operation_names.put(self.allocator, key, template);
                try operations.append(self.allocator, template);
            }
            self.effect_families.items[family].operations = try self.types.saveList(operations.items);
        }
        self.type_env.clearRetainingCapacity();
        self.row_env.clearRetainingCapacity();
    }
    fn effectSignature(self: *Engine, family: u32, identity: ast.Id, name: symbols.Symbol, annotation_id: ast.Id) T.Error!u32 {
        const old_closed = self.closed_type_variables;
        self.closed_type_variables = true;
        defer self.closed_type_variables = old_closed;
        const syntax = self.tree.node(annotation_id);
        const signature = if (syntax.tag == .type_function and syntax.c != 0) invalid: {
            try self.diagnostic(.operation_signature, annotation_id);
            break :invalid try self.types.function(try self.annotation(syntax.a), try self.annotation(syntax.b));
        } else try self.annotation(annotation_id);
        const function = self.types.node(signature);
        if (function.tag != .function) try self.diagnostic(if (self.source_validation) .operation_signature else .unsupported_type, if (self.source_validation) identity else annotation_id);
        if (self.effect_templates.items.len == std.math.maxInt(u32)) return error.TypeLimit;
        const index: u32 = @intCast(self.effect_templates.items.len);
        try self.effect_templates.append(self.allocator, .{ .identity = .{ .unit = self.unit, .decl = identity }, .family = family, .name = name, .parameter = if (function.tag == .function) function.a else T.unit, .result = if (function.tag == .function) function.b else signature });
        try self.effect_template_identities.put(self.allocator, .{ .unit = self.unit, .decl = identity }, index);
        return index;
    }
    fn textCatalogKey(self: *const Engine, text: []const u8) ?Qualified {
        const separator = std.mem.indexOfScalar(u8, text, '.') orelse
            return .{ .namespace = 0, .member = self.pool.lookup(text) orelse return null };
        return .{ .namespace = self.pool.lookup(text[0..separator]) orelse return null, .member = self.pool.lookup(text[separator + 1 ..]) orelse return null };
    }
    fn operationTemplate(self: *Engine, name: symbols.Symbol) T.Error!?u32 {
        if (self.lookup(name) != null or try self.globalBinding(name) != null) return null;
        const text = self.pool.get(name);
        const root_end = std.mem.indexOfScalar(u8, text, '.') orelse text.len;
        if (self.pool.lookup(text[0..root_end])) |root| if (self.lookup(root) != null or self.globals.contains(root)) return null;
        return self.catalogOperationTemplate(name);
    }
    fn catalogOperationTemplate(self: *const Engine, name: symbols.Symbol) ?u32 {
        const text = self.pool.get(name);
        if (self.effect_operation_names.get(self.catalogKey(name))) |single| return single;
        const separator = std.mem.lastIndexOfScalar(u8, text, '.') orelse return null;
        const family_key = self.textCatalogKey(text[0..separator]) orelse return null;
        const family = self.effect_family_names.get(family_key) orelse return null;
        const member = self.pool.lookup(text[separator + 1 ..]) orelse return null;
        return self.effect_members.get(.{ .family = family, .member = member });
    }
    fn operationValue(self: *Engine, source: ast.Id, template_index: u32, explicit_arguments: ?[]const ast.Id) T.Error!T.Id {
        const template = self.effect_templates.items[template_index];
        const family = self.effect_families.items[template.family];
        const old = try self.allocator.dupe(T.Id, self.types.list(family.variables));
        defer self.allocator.free(old);
        const fresh = try self.allocator.alloc(T.Id, old.len);
        defer self.allocator.free(fresh);
        for (fresh) |*variable| variable.* = try self.types.fresh();
        const shapes = try self.allocator.dupe(T.Id, self.types.list(family.parameters));
        defer self.allocator.free(shapes);
        var arguments: std.ArrayList(T.Id) = .empty;
        defer arguments.deinit(self.allocator);
        if (explicit_arguments) |syntax| {
            if (syntax.len != shapes.len) {
                try self.diagnostic(.effect_arity, source);
                return self.types.fresh();
            }
            for (syntax, shapes, self.parameter_patterns.list(family.patterns)) |argument, shape, param_pattern| {
                const actual = try self.parameterArgument(param_pattern, argument, false, 0);
                const selected = try self.types.substitute(shape, old, fresh);
                try self.constrain(selected, actual, argument);
                try arguments.append(self.allocator, try self.types.resolve(selected, 0));
            }
        } else {
            for (shapes) |shape| try arguments.append(self.allocator, try self.types.substitute(shape, old, fresh));
        }
        const parameter = try self.types.substitute(template.parameter, old, fresh);
        const result = try self.types.substitute(template.result, old, fresh);
        const latent = try self.types.freshEffects();
        var row = latent;
        var concrete = shapes.len == 0 or explicit_arguments != null;
        for (arguments.items) |*argument| {
            argument.* = try self.types.resolve(argument.*, 0);
            concrete = concrete and try self.types.equalClosed(argument.*, argument.*);
        }
        if (concrete) {
            const label = try self.types.internOperation(template.identity, arguments.items);
            row = self.types.effects.row(&.{label}, self.types.row(latent).tail) catch |err| return T.effectError(err);
        }
        const signature = try self.types.functionWithEffects(parameter, result, row);
        if (self.operation_uses.items.len == std.math.maxInt(u32)) return error.TypeLimit;
        try self.operation_uses.append(self.allocator, .{ .node = source, .template = template_index, .arguments = try self.types.saveList(arguments.items), .signature = signature });
        self.operation_refs[source] = @intCast(self.operation_uses.items.len);
        if (!concrete) {
            // Inferred generic operations remain principal predicates even
            // after an ordinary expected result makes their arguments concrete.
            // Reflection precedes demanded evidence selection in the oracle.
            try self.appendPending(.{ .owner = self.current, .direct = true, .value = .{ .kind = .effect_operation, .ty = signature, .signature = signature, .other = try self.types.product(arguments.items), .identity = template.identity, .source = source } });
        }
        return signature;
    }
    fn builtinStateTemplate(self: *Engine, read: bool) T.Error!u32 {
        const identity = if (read) T.builtin_state_read else T.builtin_state_write;
        if (self.effect_template_identities.get(identity)) |existing| return existing;
        if (self.effect_templates.items.len == std.math.maxInt(u32)) return error.TypeLimit;
        const state = try self.types.fresh();
        const index: u32 = @intCast(self.effect_templates.items.len);
        try self.effect_templates.append(self.allocator, .{ .identity = identity, .family = 0, .name = 0, .parameter = if (read) T.unit else state, .result = if (read) state else T.unit });
        try self.effect_template_identities.put(self.allocator, identity, index);
        return index;
    }
    fn witnessResult(self: *Engine, original: T.Id) T.Error!T.Id {
        var result = original;
        for (0..1024) |_| {
            const node = self.types.node(try self.types.resolve(result, 0));
            if (node.tag != .function) return result;
            result = node.b;
        }
        return error.TypeLimit;
    }
    fn witnessType(self: *Engine, operand: T.Id, source: ast.Id) T.Error!T.Id {
        const known = try self.witnessResult(operand);
        if (self.types.node(try self.types.resolve(known, 0)).tag != .variable) return known;
        const result = try self.types.fresh();
        try self.appendPending(.{ .owner = self.current, .direct = true, .value = .{ .kind = .type_head, .ty = operand, .result = result, .source = source } });
        return result;
    }
    fn builtinStateApplication(self: *Engine, id: ast.Id) T.Error!?T.Id {
        const syntax = self.tree.node(id);
        if (self.tree.node(syntax.a).tag != .intrinsic) return null;
        const name = self.pool.get(self.tree.node(syntax.a).a);
        const read = std.mem.eql(u8, name, "@state.get");
        if (!read and !std.mem.eql(u8, name, "@state.set")) return null;
        const operand = try self.expression(syntax.b);
        const state = if (read) try self.witnessType(operand, id) else operand;
        const template = try self.builtinStateTemplate(read);
        const identity = self.effect_templates.items[template].identity;
        const latent = try self.types.freshEffects();
        var row = latent;
        const concrete = try self.types.equalClosed(state, state);
        if (concrete) {
            const label = try self.types.internOperation(identity, &.{state});
            row = self.types.effects.row(&.{label}, self.types.row(latent).tail) catch |err| return T.effectError(err);
        }
        const result = if (read) state else T.unit;
        const signature = try self.types.functionWithEffects(if (read) T.unit else state, result, row);
        if (self.operation_uses.items.len == std.math.maxInt(u32)) return error.TypeLimit;
        try self.operation_uses.append(self.allocator, .{ .node = id, .template = template, .arguments = try self.types.saveList(&.{state}), .signature = signature, .call = if (read) .state_read else .state_write, .operand = syntax.b });
        self.operation_refs[id] = @intCast(self.operation_uses.items.len);
        if (!concrete) try self.appendPending(.{ .owner = self.current, .direct = true, .value = .{ .kind = .effect_operation, .ty = signature, .signature = signature, .other = try self.types.product(&.{state}), .identity = identity, .source = id } });
        try self.constrainEffects(row, self.ambient, id);
        return result;
    }
    fn reflectionType(self: *Engine, descriptor: bool) T.Error!T.Id {
        return self.types.nominal(if (descriptor) T.effect_descriptor_identity else T.effect_set_identity, &.{});
    }
    fn reflectionOperation(self: *Engine, original: ast.Id, required: bool) T.Error!?T.Effects.Label {
        var id = original;
        while (self.tree.node(id).tag == .group) id = self.tree.node(id).a;
        const node = self.tree.node(id);
        if (node.tag == .name and std.mem.eql(u8, self.pool.get(node.a), "Foreign")) return T.foreign_operation;
        _ = try self.expression(original);
        const selected = self.operation_refs[id];
        if (selected == 0) {
            if (required) try self.diagnostic(.operation_target, original);
            return null;
        }
        const use = self.operation_uses.items[selected - 1];
        const arguments = try self.allocator.dupe(T.Id, self.types.list(use.arguments));
        defer self.allocator.free(arguments);
        for (arguments) |argument| {
            const closed = try self.types.resolve(argument, 0);
            if (!try self.types.equalClosed(closed, closed)) {
                try self.diagnostic(.open_effect_descriptor, original);
                return null;
            }
        }
        return try self.types.internOperation(self.effect_templates.items[use.template].identity, arguments);
    }
    fn reflectDescriptor(self: *Engine, original: ast.Id, label: T.Effects.Label) T.Error!T.Id {
        var id = original;
        while (self.tree.node(id).tag == .group) id = self.tree.node(id).a;
        try self.reflections.append(self.allocator, .{ .node = id, .kind = .descriptor, .label = label });
        const ty = try self.reflectionType(true);
        self.expr_types[id] = ty;
        self.expr_types[original] = ty;
        return ty;
    }
    fn reflectionApplication(self: *Engine, id: ast.Id) T.Error!?T.Id {
        var head = id;
        while (self.tree.node(head).tag == .apply) head = self.tree.node(head).a;
        const syntax = self.tree.node(head);
        if (syntax.tag != .intrinsic) return null;
        const name = self.pool.get(syntax.a);
        const kind: ReflectionKind = if (std.mem.eql(u8, name, "@effect.of")) .of else if (std.mem.eql(u8, name, "@effect.descriptor")) .descriptor else if (std.mem.eql(u8, name, "@effect.count")) .count else if (std.mem.eql(u8, name, "@effect.has")) .has else if (std.mem.eql(u8, name, "@effect.same")) .same else return null;
        const arity: usize = if (kind == .has or kind == .same) 2 else 1;
        var application_scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var application_scratch: std.heap.BufferFirstAllocator = .init(&application_scratch_buffer, self.allocator);
        const argument_allocator = application_scratch.allocator();
        var arguments: std.ArrayList(ast.Id) = .empty;
        defer arguments.deinit(argument_allocator);
        try arguments.ensureTotalCapacityPrecise(argument_allocator, 16);
        var application_probe = id;
        while (self.tree.node(application_probe).tag == .apply) {
            try arguments.append(argument_allocator, self.tree.node(application_probe).b);
            application_probe = self.tree.node(application_probe).a;
        }
        if (arguments.items.len != arity) {
            try self.diagnostic(.call_arity, id);
            return try self.types.fresh();
        }
        std.mem.reverse(ast.Id, arguments.items);
        const left = arguments.items[0];
        if (kind == .descriptor) {
            const label = (try self.reflectionOperation(left, true)) orelse return try self.types.fresh();
            return try self.reflectDescriptor(id, label);
        }
        if (kind == .of) {
            const argument = self.tree.node(left);
            var binding: ?BindingId = null;
            if (argument.tag == .name and self.lookup(argument.a) == null) binding = try self.globalBinding(argument.a);
            if (argument.tag == .field_access and self.tree.node(argument.a).tag == .name and self.lookup(self.tree.node(argument.a).a) == null) binding = self.qualified.get(.{ .namespace = self.tree.node(argument.a).a, .member = argument.b });
            const selected = binding orelse {
                try self.diagnostic(.function_target, left);
                return try self.types.fresh();
            };
            if (!self.bindings.items[selected].named_function) {
                try self.diagnostic(.function_target, left);
                return try self.types.fresh();
            }
            try self.prepareGlobal(selected);
            try self.reflections.append(self.allocator, .{ .node = id, .kind = .of, .binding = selected });
            return try self.reflectionType(false);
        }
        try self.constrain(try self.expression(left), try self.reflectionType(kind == .same), left);
        const right = if (arity == 2) arguments.items[1] else 0;
        if (right != 0) {
            const ty = if (kind == .has) blk: {
                if (try self.reflectionOperation(right, false)) |label| break :blk try self.reflectDescriptor(right, label);
                break :blk self.expr_types[right];
            } else try self.expression(right);
            try self.constrain(ty, try self.reflectionType(true), right);
        }
        try self.reflections.append(self.allocator, .{ .node = id, .kind = kind, .left = left, .right = right });
        return if (kind == .count) T.u32_type else T.boolean;
    }
    fn finishReflection(self: *Engine) T.Error!void {
        for (self.reflections.items) |*reflection| {
            if (reflection.kind != .of) continue;
            const binding = self.bindings.items[reflection.binding];
            const signature = self.types.node(try self.types.resolve(binding.scheme.root, 0));
            if (signature.tag != .function) {
                try self.diagnostic(.function_target, reflection.node);
                continue;
            }
            const row = try self.types.resolveEffects(signature.c, 0);
            if (self.types.row(row).tail != .closed) {
                try self.diagnostic(.open_effect_descriptor, reflection.node);
                continue;
            }
            reflection.row = row;
        }
        std.mem.sortUnstable(Reflection, self.reflections.items, {}, struct {
            fn less(_: void, left: Reflection, right: Reflection) bool {
                return left.node < right.node;
            }
        }.less);
    }
    fn copyParameterPatterns(self: *Engine, source: F.Patterns, span: P.List, copier: *SchemeCopier) T.Error!P.List {
        var result: std.ArrayList(P.Id) = .empty;
        defer result.deinit(self.allocator);
        for (source.list(span)) |param_pattern| try result.append(self.allocator, try self.copyParameterPattern(source, param_pattern, copier, 0));
        return self.parameter_patterns.saveList(self.allocator, result.items);
    }
    fn copyParameterPattern(self: *Engine, source: F.Patterns, id: P.Id, copier: *SchemeCopier, depth: usize) T.Error!P.Id {
        if (depth >= 1024) return error.TypeLimit;
        const node = source.node(id);
        if (node.kind == .binding) return self.parameter_patterns.add(self.allocator, .{ .kind = .binding, .a = try copier.copy(node.a, depth + 1) });
        if (node.kind == .record) {
            var fields: std.ArrayList(P.Field) = .empty;
            defer fields.deinit(self.allocator);
            for (0..node.b) |index| {
                const field = source.field(node, index);
                try fields.append(self.allocator, .{ .name = field.name, .pattern = try self.copyParameterPattern(source, field.pattern, copier, depth + 1) });
            }
            return self.parameter_patterns.record(self.allocator, fields.items);
        }
        var children: std.ArrayList(P.Id) = .empty;
        defer children.deinit(self.allocator);
        for (source.list(.{ .start = node.a, .len = node.b })) |child| try children.append(self.allocator, try self.copyParameterPattern(source, child, copier, depth + 1));
        return self.parameter_patterns.sequence(self.allocator, node.kind, children.items);
    }
    const ParameterAnnotation = struct { ty: T.Id, pattern: P.Id };
    fn parameterAnnotation(self: *Engine, id: ast.Id, depth: usize) T.Error!ParameterAnnotation {
        if (depth >= 1024) return error.TypeLimit;
        const node = self.tree.node(id);
        if (node.tag == .group) return self.parameterAnnotation(node.a, depth + 1);
        if (node.tag == .type_product or node.tag == .type_array) {
            const children = self.tree.children(id);
            if (node.tag == .type_product and children.len == 1) return self.parameterAnnotation(children[0], depth + 1);
            var types: std.ArrayList(T.Id) = .empty;
            defer types.deinit(self.allocator);
            var patterns: std.ArrayList(P.Id) = .empty;
            defer patterns.deinit(self.allocator);
            for (children) |child| {
                const parsed = try self.parameterAnnotation(child, depth + 1);
                try types.append(self.allocator, parsed.ty);
                try patterns.append(self.allocator, parsed.pattern);
            }
            return .{ .ty = if (types.items.len == 0) T.unit else try self.types.product(types.items), .pattern = try self.parameter_patterns.sequence(self.allocator, if (node.tag == .type_array) .array else .tuple, patterns.items) };
        }
        if (node.tag == .type_record) {
            var types: std.ArrayList(T.Field) = .empty;
            defer types.deinit(self.allocator);
            var fields: std.ArrayList(P.Field) = .empty;
            defer fields.deinit(self.allocator);
            for (self.tree.children(id)) |child| {
                const field = self.tree.node(child);
                for (fields.items) |prior| if (prior.name == field.a) try self.diagnostic(.duplicate_type_field, id);
                const parsed = if (field.b == 0) try self.parameterBinding(field.a, child) else try self.parameterAnnotation(field.b, depth + 1);
                try types.append(self.allocator, .{ .name = field.a, .ty = parsed.ty });
                try fields.append(self.allocator, .{ .name = field.a, .pattern = parsed.pattern });
            }
            return .{ .ty = try self.types.record(types.items), .pattern = try self.parameter_patterns.record(self.allocator, fields.items) };
        }
        const text = if (node.tag == .type_name) self.pool.get(node.a) else "";
        if (text.len == 0 or (!std.ascii.isLower(text[0]) and text[0] != '_') or std.mem.indexOfScalar(u8, text, '.') != null) {
            try self.diagnostic(.type_parameter, id);
            const ty = try self.types.fresh();
            return .{ .ty = ty, .pattern = try self.parameter_patterns.add(self.allocator, .{ .kind = .binding, .a = ty }) };
        }
        return self.parameterBinding(node.a, id);
    }
    fn parameterBinding(self: *Engine, name: symbols.Symbol, source: ast.Id) T.Error!ParameterAnnotation {
        for (self.type_env.items) |prior| if (prior.name == name) {
            try self.diagnostic(.duplicate_type_parameter, source);
            break;
        };
        const ty = try self.typeVariable(name, source);
        return .{ .ty = ty, .pattern = try self.parameter_patterns.add(self.allocator, .{ .kind = .binding, .a = ty }) };
    }
    fn scalarArgumentPossible(self: *Engine, source: ast.Id, allow_unit: bool, depth: usize) T.Error!bool {
        if (depth >= 1024) return error.TypeLimit;
        const node = self.tree.node(source);
        if (node.tag == .group) return self.scalarArgumentPossible(node.a, allow_unit, depth + 1);
        if (node.tag == .array) return false;
        if (node.tag == .product) {
            for (self.tree.children(source)) |child| if (!try self.scalarArgumentPossible(child, true, depth + 1)) return false;
            return true;
        }
        return self.possibleOperationType(source, allow_unit, depth + 1);
    }
    fn possibleParameterArgument(self: *Engine, param_pattern: P.Id, source: ast.Id, allow_unit: bool, depth: usize) T.Error!bool {
        if (depth >= 1024) return error.TypeLimit;
        const node = self.parameter_patterns.node(param_pattern);
        if (node.kind == .binding) return self.scalarArgumentPossible(source, allow_unit, depth + 1);
        return self.possibleOperationType(source, allow_unit or (node.kind == .tuple and node.b == 0), depth + 1);
    }
    fn scalarTypeArgument(self: *Engine, source: ast.Id, annotation_: bool, depth: usize) T.Error!T.Id {
        if (depth >= 1024) return error.TypeLimit;
        const node = self.tree.node(source);
        if (node.tag == .group) return self.scalarTypeArgument(node.a, annotation_, depth + 1);
        if (node.tag == .array or node.tag == .type_array) {
            try self.diagnostic(.type_argument, source);
            return self.types.fresh();
        }
        if (node.tag == .product or node.tag == .type_product) {
            var fields: std.ArrayList(T.Id) = .empty;
            defer fields.deinit(self.allocator);
            for (self.tree.children(source)) |child| try fields.append(self.allocator, try self.scalarTypeArgument(child, annotation_, depth + 1));
            return switch (fields.items.len) {
                0 => T.unit,
                1 => fields.items[0],
                else => self.types.product(fields.items),
            };
        }
        return if (annotation_) self.annotation(source) else self.operationTypeArgument(source, depth + 1);
    }
    fn parameterArgument(self: *Engine, param_pattern: P.Id, source: ast.Id, annotation_: bool, depth: usize) T.Error!T.Id {
        if (depth >= 1024) return error.TypeLimit;
        const node = self.tree.node(source);
        if (node.tag == .group) return self.parameterArgument(param_pattern, node.a, annotation_, depth + 1);
        const formal = self.parameter_patterns.node(param_pattern);
        if (formal.kind == .binding) return self.scalarTypeArgument(source, annotation_, depth + 1);
        if (formal.kind == .record and (node.tag == .record or node.tag == .type_record)) {
            const children = self.tree.children(source);
            for (children, 0..) |child, index| for (children[0..index]) |prior| if (self.tree.node(prior).a == self.tree.node(child).a) try self.diagnostic(.duplicate_type_field, source);
            if (children.len != formal.b) {
                try self.diagnostic(.type_argument, source);
                return self.types.fresh();
            }
            var fields: std.ArrayList(T.Field) = .empty;
            defer fields.deinit(self.allocator);
            for (0..formal.b) |index| {
                const expected = self.parameter_patterns.field(formal, index);
                var match: ast.Id = 0;
                for (children) |child| if (self.tree.node(child).a == expected.name) {
                    match = child;
                    break;
                };
                if (match == 0) {
                    try self.diagnostic(.type_argument, source);
                    return self.types.fresh();
                }
                const actual = self.tree.node(match);
                const ty = if (actual.b == 0) try self.typeVariable(actual.a, match) else try self.parameterArgument(expected.pattern, actual.b, annotation_, depth + 1);
                try fields.append(self.allocator, .{ .name = expected.name, .ty = ty });
            }
            return self.types.record(fields.items);
        }
        const tuple = node.tag == .product or node.tag == .type_product or node.tag == .unit;
        const array = (node.tag == .array and node.c == 1) or node.tag == .type_array;
        if ((formal.kind == .tuple and tuple) or (formal.kind == .array and array)) {
            const children: []const ast.Id = if (node.tag == .unit) &.{} else self.tree.children(source);
            if (children.len != formal.b) {
                try self.diagnostic(.type_argument, source);
                return self.types.fresh();
            }
            var fields: std.ArrayList(T.Id) = .empty;
            defer fields.deinit(self.allocator);
            for (self.parameter_patterns.list(.{ .start = formal.a, .len = formal.b }), children) |child_pattern, child| try fields.append(self.allocator, try self.parameterArgument(child_pattern, child, annotation_, depth + 1));
            return if (fields.items.len == 0) T.unit else self.types.product(fields.items);
        }
        try self.diagnostic(.type_argument, source);
        return self.types.fresh();
    }
    fn possibleOperationType(self: *Engine, original: ast.Id, allow_unit: bool, depth: usize) T.Error!bool {
        if (depth >= 1024) return error.TypeLimit;
        const n = self.tree.node(original);
        switch (n.tag) {
            .group => return self.possibleOperationType(n.a, allow_unit, depth + 1),
            .unit => return allow_unit,
            .name => {
                if (self.lookup(n.a) != null or try self.globalBinding(n.a) != null) return false;
                const text = self.pool.get(n.a);
                if (std.mem.eql(u8, text, "Unit") or std.mem.eql(u8, text, "Bool") or std.mem.eql(u8, text, "U32") or std.mem.eql(u8, text, "F32") or std.mem.eql(u8, text, "Array") or std.mem.eql(u8, text, "List") or std.mem.eql(u8, text, "Cursor")) return true;
                for (self.type_env.items) |entry| if (entry.name == n.a) return true;
                return self.nominal_names.contains(self.catalogKey(n.a));
            },
            .apply => return (try self.possibleOperationType(n.a, false, depth + 1)) and (try self.possibleOperationType(n.b, true, depth + 1)),
            .product, .array => {
                if (n.tag == .array and n.c == 0) return false;
                for (self.tree.children(original)) |child| if (!try self.possibleOperationType(child, true, depth + 1)) return false;
                return true;
            },
            .record => {
                if (n.a != 0) return false;
                for (self.tree.children(original)) |child| {
                    const field = self.tree.node(child);
                    if (field.b == 0) {
                        var known = false;
                        for (self.type_env.items) |entry| known = known or entry.name == field.a;
                        if (!known) return false;
                    } else if (!try self.possibleOperationType(field.b, true, depth + 1)) return false;
                }
                return true;
            },
            else => return false,
        }
    }
    fn operationTypeArgument(self: *Engine, id: ast.Id, depth: usize) T.Error!T.Id {
        if (depth >= 1024) return error.TypeLimit;
        const n = self.tree.node(id);
        switch (n.tag) {
            .unit => return T.unit,
            .group => return self.operationTypeArgument(n.a, depth + 1),
            .name => {
                const text = self.pool.get(n.a);
                if (std.mem.eql(u8, text, "Unit")) return T.unit;
                if (std.mem.eql(u8, text, "Bool")) return T.boolean;
                if (std.mem.eql(u8, text, "U32")) return T.u32_type;
                if (std.mem.eql(u8, text, "F32")) return T.f32_type;
                for (self.type_env.items) |entry| if (entry.name == n.a) return entry.ty;
                if (self.nominal_names.get(self.catalogKey(n.a))) |index| {
                    if (self.nominals.items[index].parameters.len != 0) {
                        try self.diagnostic(.type_arity, id);
                        return self.types.fresh();
                    }
                    if (try self.aliasInstance(index, &.{}, &.{}, id)) |alias| return alias;
                    return self.types.nominal(self.nominals.items[index].identity, &.{});
                }
            },
            .apply => {
                var reverse: std.ArrayList(ast.Id) = .empty;
                defer reverse.deinit(self.allocator);
                var head = id;
                while (true) {
                    const syntax = self.tree.node(head);
                    if (syntax.tag == .group) {
                        head = syntax.a;
                        continue;
                    }
                    if (syntax.tag != .apply) break;
                    try reverse.append(self.allocator, syntax.b);
                    head = syntax.a;
                }
                std.mem.reverse(ast.Id, reverse.items);
                if (self.tree.node(head).tag != .name) return error.TypeLimit;
                const symbol = self.tree.node(head).a;
                if ((std.mem.eql(u8, self.pool.get(symbol), "Array") or std.mem.eql(u8, self.pool.get(symbol), "List") or std.mem.eql(u8, self.pool.get(symbol), "Cursor")) and reverse.items.len == 1) return self.types.sequence(if (std.mem.eql(u8, self.pool.get(symbol), "Cursor")) .cursor else if (std.mem.eql(u8, self.pool.get(symbol), "List")) .list else .array, try self.operationTypeArgument(reverse.items[0], depth + 1));
                const index = self.nominal_names.get(self.catalogKey(symbol)) orelse return error.TypeLimit;
                const nominal_ = self.nominals.items[index];
                const shapes = try self.allocator.dupe(T.Id, self.types.list(nominal_.parameters));
                defer self.allocator.free(shapes);
                if (reverse.items.len != shapes.len) {
                    try self.diagnostic(.type_arity, id);
                    return self.types.fresh();
                }
                const old = try self.allocator.dupe(T.Id, self.types.list(nominal_.variables));
                defer self.allocator.free(old);
                const fresh = try self.allocator.alloc(T.Id, old.len);
                defer self.allocator.free(fresh);
                for (fresh) |*variable| variable.* = try self.types.fresh();
                var arguments: std.ArrayList(T.Id) = .empty;
                defer arguments.deinit(self.allocator);
                for (reverse.items, shapes, self.parameter_patterns.list(nominal_.patterns)) |syntax, shape, param_pattern| {
                    const argument = try self.parameterArgument(param_pattern, syntax, false, depth + 1);
                    const selected = try self.types.substitute(shape, old, fresh);
                    try self.constrain(selected, argument, syntax);
                    try arguments.append(self.allocator, try self.types.resolve(selected, 0));
                }
                if (try self.aliasInstance(index, old, fresh, id)) |alias| return alias;
                return self.types.nominal(nominal_.identity, arguments.items);
            },
            .product, .array => {
                if (n.tag == .array and n.c == 0) {
                    try self.diagnostic(.type_argument, id);
                    return self.types.fresh();
                }
                var parts: std.ArrayList(T.Id) = .empty;
                defer parts.deinit(self.allocator);
                for (self.tree.children(id)) |child| try parts.append(self.allocator, try self.operationTypeArgument(child, depth + 1));
                return self.types.product(parts.items);
            },
            .record => {
                var fields: std.ArrayList(T.Field) = .empty;
                defer fields.deinit(self.allocator);
                for (self.tree.children(id)) |child| {
                    const field = self.tree.node(child);
                    const ty = if (field.b == 0) try self.typeVariable(field.a, child) else try self.operationTypeArgument(field.b, depth + 1);
                    for (fields.items) |known| if (known.name == field.a) try self.diagnostic(.duplicate_field, child);
                    try fields.append(self.allocator, .{ .name = field.a, .ty = ty });
                }
                return self.types.record(fields.items);
            },
            else => {},
        }
        try self.diagnostic(.unsupported_type, id);
        return self.types.fresh();
    }
    fn operationApplication(self: *Engine, id: ast.Id) T.Error!?T.Id {
        var head = id;
        while (true) {
            const syntax = self.tree.node(head);
            if (syntax.tag == .group) {
                head = syntax.a;
                continue;
            }
            if (syntax.tag != .apply) break;
            head = syntax.a;
        }
        if (self.tree.node(head).tag != .name) return null;
        const template = (try self.operationTemplate(self.tree.node(head).a)) orelse return null;
        const family = self.effect_families.items[self.effect_templates.items[template].family];
        const count: usize = family.parameters.len;
        if (count == 0) return null;
        var application_scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var application_scratch: std.heap.BufferFirstAllocator = .init(&application_scratch_buffer, self.allocator);
        const argument_allocator = application_scratch.allocator();
        var reverse: std.ArrayList(ast.Id) = .empty;
        defer reverse.deinit(argument_allocator);
        try reverse.ensureTotalCapacityPrecise(argument_allocator, 16);
        var application_probe = id;
        while (true) {
            const syntax = self.tree.node(application_probe);
            if (syntax.tag == .group) {
                application_probe = syntax.a;
                continue;
            }
            if (syntax.tag != .apply) break;
            try reverse.append(argument_allocator, application_probe);
            application_probe = syntax.a;
        }
        if (reverse.items.len < count) return null;
        std.mem.reverse(ast.Id, reverse.items);
        var arguments: std.ArrayList(ast.Id) = .empty;
        defer arguments.deinit(self.allocator);
        const has_runtime = reverse.items.len >= count * 2;
        for (reverse.items[0..count], self.parameter_patterns.list(family.patterns)) |application, param_pattern| {
            const syntax = self.tree.node(application).b;
            if (!try self.possibleParameterArgument(param_pattern, syntax, has_runtime, 0)) return null;
            try arguments.append(self.allocator, syntax);
        }
        if (reverse.items.len > count and try self.possibleOperationType(self.tree.node(reverse.items[count]).b, false, 0)) {
            try self.diagnostic(.type_arity, id);
            return try self.types.fresh();
        }
        const specialized = reverse.items[count - 1];
        var ty = try self.operationValue(specialized, template, arguments.items);
        self.expr_types[specialized] = ty;
        for (reverse.items[count..]) |application| {
            const syntax = self.tree.node(application);
            const function = self.types.node(try self.types.resolve(ty, 0));
            const lazy = function.tag == .function and self.types.node(self.types.head(function.a, 0)).tag == .demand;
            const argument = try self.checkArgument(syntax.b, lazy);
            self.demand_calls[application] = lazy;
            if (lazy) self.demand_types[application] = function.a;
            const result = try self.types.fresh();
            try self.constrain(ty, try self.invocation(argument, result), application);
            ty = result;
            self.expr_types[application] = ty;
        }
        return ty;
    }
    const OperationTarget = struct { token: T.Id, signature: T.Id, label: T.Effects.Label };
    fn operationTarget(self: *Engine, original: ast.Id) T.Error!?OperationTarget {
        var source = original;
        while (self.tree.node(source).tag == .group) source = self.tree.node(source).a;
        const syntax = self.tree.node(source);
        if (syntax.tag == .name and std.mem.eql(u8, self.pool.get(syntax.a), "Foreign")) {
            try self.diagnostic(.sealed_effect, source);
            return null;
        }
        const signature = try self.expression(original);
        const index = self.operation_refs[source];
        if (index == 0) {
            try self.diagnostic(.operation_target, source);
            return null;
        }
        const use = self.operation_uses.items[index - 1];
        const function = self.types.node(try self.types.resolve(signature, 0));
        const labels = self.types.rowLabels(function.c);
        if (labels.len != 1) {
            try self.diagnostic(.operation_target, source);
            return null;
        }
        const identity = self.effect_templates.items[use.template].identity;
        const arguments = try self.allocator.dupe(T.Id, self.types.list(use.arguments));
        defer self.allocator.free(arguments);
        const token = try self.types.nominal(identity, arguments);
        return .{ .token = token, .signature = signature, .label = labels[0] };
    }
    fn providerApplication(self: *Engine, id: ast.Id) T.Error!?T.Id {
        var head = id;
        while (self.tree.node(head).tag == .apply) head = self.tree.node(head).a;
        const syntax = self.tree.node(head);
        if (syntax.tag != .intrinsic) return null;
        const name = self.pool.get(syntax.a);
        const ordinary = std.mem.eql(u8, name, "@effect.provider");
        const state = std.mem.eql(u8, name, "@effect.state");
        if (!ordinary and !state) return null;
        var application_scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var application_scratch: std.heap.BufferFirstAllocator = .init(&application_scratch_buffer, self.allocator);
        const argument_allocator = application_scratch.allocator();
        var reverse: std.ArrayList(ast.Id) = .empty;
        defer reverse.deinit(argument_allocator);
        try reverse.ensureTotalCapacityPrecise(argument_allocator, 16);
        var application_probe = id;
        while (self.tree.node(application_probe).tag == .apply) {
            try reverse.append(argument_allocator, self.tree.node(application_probe).b);
            application_probe = self.tree.node(application_probe).a;
        }
        std.mem.reverse(ast.Id, reverse.items);
        const arguments = reverse.items;
        if (arguments.len != @as(usize, if (ordinary) 2 else 3)) {
            try self.diagnostic(.call_arity, id);
            return try self.types.fresh();
        }
        const read = (try self.operationTarget(arguments[0])) orelse return try self.types.fresh();
        const reader = self.types.node(try self.types.resolve(read.signature, 0));
        if (ordinary) {
            const implementation = try self.expression(arguments[1]);
            const row = try self.types.freshEffects();
            try self.constrain(implementation, try self.types.functionWithEffects(reader.a, reader.b, row), arguments[1]);
            return try self.types.provider(read.token, row);
        }
        const write = (try self.operationTarget(arguments[1])) orelse return try self.types.fresh();
        if (read.label == write.label) {
            try self.diagnostic(.invalid_state_provider, id);
            return try self.types.fresh();
        }
        const writer = self.types.node(try self.types.resolve(write.signature, 0));
        const initial = try self.expression(arguments[2]);
        try self.constrain(reader.a, T.unit, arguments[0]);
        try self.constrain(writer.b, T.unit, arguments[1]);
        try self.constrain(reader.b, writer.a, id);
        try self.constrain(initial, reader.b, arguments[2]);
        return try self.types.stateProvider(read.token, write.token, reader.b);
    }
    fn runnerTemplate(self: *Engine, original: ast.Id) T.Error!?u32 {
        var source = original;
        while (self.tree.node(source).tag == .group) source = self.tree.node(source).a;
        const syntax = self.tree.node(source);
        if (syntax.tag != .name) {
            try self.diagnostic(.operation_target, original);
            return null;
        }
        const index = (try self.operationTemplate(syntax.a)) orelse {
            try self.diagnostic(.operation_target, original);
            return null;
        };
        const family = self.effect_families.items[self.effect_templates.items[index].family];
        if (family.parameters.len == 0) {
            try self.diagnostic(.operation_target, original);
            return null;
        }
        if (family.parameters.len != 1 or self.types.node(self.types.list(family.parameters)[0]).tag != .variable) {
            try self.diagnostic(.type_arity, original);
            return null;
        }
        return index;
    }
    const RunnerOperation = struct { token: T.Id, parameter: T.Id, result: T.Id };
    fn runnerOperation(self: *Engine, index: u32, state: T.Id) T.Error!RunnerOperation {
        const template = self.effect_templates.items[index];
        const family = self.effect_families.items[template.family];
        const old = try self.allocator.dupe(T.Id, self.types.list(family.variables));
        defer self.allocator.free(old);
        if (old.len != 1) return error.TypeLimit;
        const parameter = try self.types.substitute(template.parameter, old, &.{state});
        const result = try self.types.substitute(template.result, old, &.{state});
        return .{ .token = try self.types.nominal(template.identity, &.{state}), .parameter = parameter, .result = result };
    }
    /// A handler removes one occurrence, retaining all residual labels and
    /// their tail. The token's arguments may become closed only at a use site.
    fn handlerEquation(self: *Engine, token_type: T.Id, extended: T.Effects.Id, residual: T.Effects.Id, source: ast.Id) T.Error!bool {
        const token = self.types.node(try self.types.resolve(token_type, 0));
        if (token.tag != .nominal) return error.TypeLimit;
        const arguments = try self.allocator.dupe(T.Id, self.types.nominalArguments(token));
        defer self.allocator.free(arguments);
        for (arguments) |*argument| {
            argument.* = try self.types.resolve(argument.*, 0);
            if (!try self.types.equalClosed(argument.*, argument.*)) return false;
        }
        const label = try self.types.internOperation(.{ .unit = token.a, .decl = token.b }, arguments);
        const tail = try self.types.resolveEffects(residual, 0);
        var labels: std.ArrayList(T.Effects.Label) = .empty;
        defer labels.deinit(self.allocator);
        try labels.append(self.allocator, label);
        try labels.appendSlice(self.allocator, self.types.rowLabels(tail));
        const row = self.types.effects.rowAt(labels.items, self.types.row(tail).tail, self.types.row(tail).cursor) catch |err| return T.effectError(err);
        try self.constrainEffects(extended, row, source);
        return true;
    }
    fn runnerHandler(self: *Engine, source: ast.Id, token: T.Id, extended: T.Effects.Id, residual: T.Effects.Id) T.Error!void {
        if (try self.handlerEquation(token, extended, residual, source)) return;
        const signature = try self.types.functionWithEffects(T.unit, T.unit, extended);
        const remainder = try self.types.functionWithEffects(T.unit, T.unit, residual);
        try self.appendPending(.{ .owner = self.current, .direct = true, .value = .{ .kind = .effect_handler, .ty = token, .signature = signature, .other = remainder, .source = source } });
    }
    fn effectRunnerApplication(self: *Engine, id: ast.Id) T.Error!?T.Id {
        var head = id;
        while (self.tree.node(head).tag == .apply) head = self.tree.node(head).a;
        const syntax = self.tree.node(head);
        if (syntax.tag != .intrinsic) return null;
        const name = self.pool.get(syntax.a);
        const builtin = std.mem.startsWith(u8, name, "@state.");
        const kind: EffectRunnerKind = if (std.mem.eql(u8, name, "@effect.run") or std.mem.eql(u8, name, "@state.run")) .run else if (std.mem.eql(u8, name, "@effect.reader") or std.mem.eql(u8, name, "@state.reader")) .reader else if (std.mem.eql(u8, name, "@effect.writer") or std.mem.eql(u8, name, "@state.writer")) .writer else return null;
        const arity: usize = if (builtin) if (kind == .run) 2 else 3 else 4;
        var application_scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var application_scratch: std.heap.BufferFirstAllocator = .init(&application_scratch_buffer, self.allocator);
        const argument_allocator = application_scratch.allocator();
        var reverse: std.ArrayList(ast.Id) = .empty;
        defer reverse.deinit(argument_allocator);
        try reverse.ensureTotalCapacityPrecise(argument_allocator, 16);
        var application_probe = id;
        while (self.tree.node(application_probe).tag == .apply) {
            try reverse.append(argument_allocator, self.tree.node(application_probe).b);
            application_probe = self.tree.node(application_probe).a;
        }
        if (reverse.items.len != arity) {
            try self.diagnostic(.call_arity, id);
            return try self.types.fresh();
        }
        std.mem.reverse(ast.Id, reverse.items);
        const arguments = reverse.items;
        const first = if (builtin) try self.builtinStateTemplate(kind != .writer) else (try self.runnerTemplate(arguments[0])) orelse return try self.types.fresh();
        const second = if (kind == .run) if (builtin) try self.builtinStateTemplate(false) else (try self.runnerTemplate(arguments[1])) orelse return try self.types.fresh() else 0;
        if (!builtin and kind == .run and self.effect_templates.items[first].family != self.effect_templates.items[second].family) {
            try self.diagnostic(.effect_family, id);
            return try self.types.fresh();
        }
        const state_operand: usize = if (builtin) 0 else if (kind == .run) 2 else 1;
        const implementation_operand: usize = if (builtin) 1 else 2;
        const action_operand = arguments.len - 1;
        const initial_or_witness = try self.expression(arguments[state_operand]);
        const state = if (kind == .run) initial_or_witness else try self.witnessType(initial_or_witness, arguments[state_operand]);
        const operation: RunnerOperation = if (builtin) .{ .token = try self.types.nominal(self.effect_templates.items[first].identity, &.{state}), .parameter = if (kind != .writer) T.unit else state, .result = if (kind != .writer) state else T.unit } else try self.runnerOperation(first, state);
        const body_result = try self.types.fresh();
        const body_row = try self.types.freshEffects();
        const action_type = try self.types.functionWithEffects(T.unit, body_result, body_row);
        var metadata: EffectRunner = .{ .node = id, .kind = kind, .action = arguments[action_operand], .state_type = state, .body_result = body_result, .result = body_result, .action_type = action_type, .body_effects = body_row, .outer_effects = self.ambient };
        if (kind == .run) {
            const writer: RunnerOperation = if (builtin) .{ .token = try self.types.nominal(self.effect_templates.items[second].identity, &.{state}), .parameter = state, .result = T.unit } else try self.runnerOperation(second, state);
            const read_identity = self.types.node(operation.token);
            const write_identity = self.types.node(writer.token);
            if (read_identity.a == write_identity.a and read_identity.b == write_identity.b) {
                try self.diagnostic(.invalid_state_provider, id);
                return try self.types.fresh();
            }
            try self.constrain(operation.parameter, T.unit, arguments[0]);
            try self.constrain(operation.result, state, arguments[0]);
            try self.constrain(writer.parameter, state, arguments[1]);
            try self.constrain(writer.result, T.unit, arguments[1]);
            const intermediate = try self.types.freshEffects();
            try self.runnerHandler(id, operation.token, body_row, intermediate);
            try self.runnerHandler(id, writer.token, intermediate, self.ambient);
            metadata.read_token = operation.token;
            metadata.write_token = writer.token;
            metadata.initial = arguments[state_operand];
            metadata.result = try self.types.product(&.{ state, body_result });
        } else {
            const parameter = if (kind == .reader) T.unit else state;
            const result = if (kind == .reader) state else T.unit;
            try self.constrain(operation.parameter, parameter, arguments[0]);
            try self.constrain(operation.result, result, arguments[0]);
            const implementation = try self.expression(arguments[implementation_operand]);
            const implementation_type = try self.types.functionWithEffects(parameter, result, self.ambient);
            try self.constrain(implementation, implementation_type, arguments[implementation_operand]);
            try self.runnerHandler(id, operation.token, body_row, self.ambient);
            metadata.witness = arguments[state_operand];
            metadata.implementation = arguments[implementation_operand];
            metadata.implementation_type = implementation_type;
            if (kind == .reader) metadata.read_token = operation.token else metadata.write_token = operation.token;
        }
        try self.constrain(try self.expression(arguments[action_operand]), action_type, arguments[action_operand]);
        if (self.effect_runners.items.len == std.math.maxInt(u32)) return error.TypeLimit;
        try self.effect_runners.append(self.allocator, metadata);
        self.effect_runner_ids[id] = @intCast(self.effect_runners.items.len);
        return metadata.result;
    }
    fn providerBlock(self: *Engine, id: ast.Id, provider_type: T.Id) T.Error!T.Id {
        const syntax = self.tree.node(id);
        const provider_ = self.types.node(try self.types.resolve(provider_type, 0));
        const scope = self.env.items.len;
        const old_target = self.return_target;
        const old_owner = self.owner;
        const old_resolver = self.resolver_scope;
        const old_ambient = self.ambient;
        defer {
            self.env.shrinkRetainingCapacity(scope);
            self.return_target = old_target;
            self.owner = old_owner;
            self.resolver_scope = old_resolver;
            self.ambient = old_ambient;
        }
        if (provider_.tag == .provider) try self.constrainEffects(provider_.c, old_ambient, syntax.c);
        var labels: std.ArrayList(T.Effects.Label) = .empty;
        defer labels.deinit(self.allocator);
        for ([_]T.Id{ provider_.a, if (provider_.tag == .state_provider) provider_.b else 0 }) |token| {
            if (token == 0) continue;
            const nominal_ = self.types.node(try self.types.resolve(token, 0));
            if (nominal_.tag != .nominal) return error.TypeLimit;
            const arguments = try self.allocator.dupe(T.Id, self.types.nominalArguments(nominal_));
            defer self.allocator.free(arguments);
            for (arguments) |*argument| argument.* = try self.types.resolve(argument.*, 0);
            try labels.append(self.allocator, try self.types.internOperation(.{ .unit = nominal_.a, .decl = nominal_.b }, arguments));
        }
        const outer = try self.types.resolveEffects(old_ambient, 0);
        try labels.appendSlice(self.allocator, self.types.rowLabels(outer));
        const body_row = self.types.effects.rowAt(labels.items, self.types.row(outer).tail, self.types.row(outer).cursor) catch |err| return T.effectError(err);
        self.ambient = body_row;
        self.resolver_scope = .{};
        self.owner = id;
        var body_result = try self.types.fresh();
        self.return_target = body_result;
        const flow = try self.suite(id);
        if (!flow.exits) try self.constrain(body_result, T.unit, id);
        if (flow.exits and flow.breaks and !flow.returns) body_result = T.never;
        const result = if (provider_.tag == .state_provider and body_result != T.never) try self.types.product(&.{ provider_.c, body_result }) else body_result;
        if (self.provider_blocks.items.len == std.math.maxInt(u32)) return error.TypeLimit;
        try self.provider_blocks.append(self.allocator, .{ .node = id, .provider = syntax.c, .body_result = body_result, .result = result, .body_effects = body_row, .outer_effects = old_ambient });
        self.provider_block_ids[id] = @intCast(self.provider_blocks.items.len);
        return result;
    }
    fn typeArity(self: *Engine, source: ast.Id, application: Diagnostic.TypeApplication) Allocator.Error!void {
        const point = if (application == .extra) self.tree.span(source).start else self.tree.typeConversionOrigin(source);
        try self.diagnostics.append(self.allocator, .{ .code = .type_arity, .span = .{ .start = point, .end = point }, .node = source, .type_application = application });
    }
    // Source type values resolve their written names before application. A
    // constructor name here can still be unsaturated; conversion to a runtime
    // type happens at the enclosing application's formal parameter.
    fn argumentTypeNames(self: *Engine, source: ast.Id, depth: usize) T.Error!void {
        if (depth >= 1024) return error.TypeLimit;
        const node = self.tree.node(source);
        switch (node.tag) {
            .type_name => {
                const name = self.pool.get(node.a);
                if (name.len != 0 and (std.ascii.isLower(name[0]) or name[0] == '_') and std.mem.indexOfScalar(u8, name, '.') == null) return;
                for ([_][]const u8{ "Unit", "Bool", "U32", "F32", "Array", "List", "Cursor", "EffectSet", "EffectDescriptor" }) |builtin| if (std.mem.eql(u8, name, builtin)) return;
                if (!self.nominal_names.contains(self.catalogKey(node.a))) {
                    try self.diagnostic(.unsupported_type, source);
                    self.diagnostics.items[self.diagnostics.items.len - 1].span.end = self.tree.span(source).start;
                }
            },
            .group, .type_demand => try self.argumentTypeNames(node.a, depth + 1),
            .type_apply, .type_function => {
                try self.argumentTypeNames(node.a, depth + 1);
                try self.argumentTypeNames(node.b, depth + 1);
            },
            .type_product, .type_array => for (self.tree.children(source)) |child| try self.argumentTypeNames(child, depth + 1),
            .type_record => for (self.tree.children(source)) |child| {
                const field = self.tree.node(child);
                if (field.b != 0) try self.argumentTypeNames(field.b, depth + 1);
            },
            else => {},
        }
    }
    fn applicationDiagnosticOrigin(self: *Engine, before: usize, source: ast.Id) void {
        for (self.diagnostics.items[before..]) |*diagnostic_| if (diagnostic_.type_application) |application| {
            if (application == .extra) continue;
            const point = self.tree.typeConversionOrigin(source);
            diagnostic_.span = .{ .start = point, .end = point };
            diagnostic_.node = source;
        };
    }
    fn nominalAnnotation(self: *Engine, head: ast.Id, arguments: []const ast.Id, source: ast.Id) T.Error!T.Id {
        const name = self.tree.node(head).a;
        if (std.mem.eql(u8, self.pool.get(name), "Array") or std.mem.eql(u8, self.pool.get(name), "List") or std.mem.eql(u8, self.pool.get(name), "Cursor")) {
            if (arguments.len == 0) {
                try self.typeArity(source, .missing_array);
                return self.types.fresh();
            }
            const before = self.diagnostics.items.len;
            if (arguments.len > 1) for (arguments) |argument| try self.argumentTypeNames(argument, 0);
            if (self.diagnostics.items.len != before) return self.types.fresh();
            const element = try self.annotation(arguments[0]);
            self.applicationDiagnosticOrigin(before, source);
            if (self.diagnostics.items.len != before) return self.types.fresh();
            if (arguments.len > 1) {
                try self.typeArity(source, .extra);
                return self.types.fresh();
            }
            return self.types.sequence(if (std.mem.eql(u8, self.pool.get(name), "Cursor")) .cursor else if (std.mem.eql(u8, self.pool.get(name), "List")) .list else .array, element);
        }
        for ([_][]const u8{ "Unit", "Bool", "U32", "F32", "EffectSet", "EffectDescriptor" }) |builtin| if (std.mem.eql(u8, self.pool.get(name), builtin)) {
            const before = self.diagnostics.items.len;
            for (arguments) |argument| try self.argumentTypeNames(argument, 0);
            if (self.diagnostics.items.len == before) try self.typeArity(source, .extra);
            return self.types.fresh();
        };
        const index = self.nominal_names.get(self.catalogKey(name)) orelse {
            try self.diagnostic(.unsupported_type, source);
            return self.types.fresh();
        };
        const nominal_ = self.nominals.items[index];
        const before = self.diagnostics.items.len;
        if (arguments.len != nominal_.parameters.len) for (arguments) |argument| try self.argumentTypeNames(argument, 0);
        if (self.diagnostics.items.len != before) return self.types.fresh();
        const old = try self.allocator.dupe(T.Id, self.types.list(nominal_.variables));
        defer self.allocator.free(old);
        const fresh = try self.allocator.alloc(T.Id, old.len);
        defer self.allocator.free(fresh);
        for (fresh) |*id| id.* = try self.types.fresh();
        const shapes = try self.allocator.dupe(T.Id, self.types.list(nominal_.parameters));
        defer self.allocator.free(shapes);
        var args: std.ArrayList(T.Id) = .empty;
        defer args.deinit(self.allocator);
        const count = @min(arguments.len, shapes.len);
        for (arguments[0..count], shapes[0..count], self.parameter_patterns.list(nominal_.patterns)[0..count]) |arg, shape, param_pattern| {
            const actual = try self.parameterArgument(param_pattern, arg, true, 0);
            const selected = try self.types.substitute(shape, old, fresh);
            try self.constrain(selected, actual, arg);
            try args.append(self.allocator, try self.types.resolve(selected, 0));
        }
        self.applicationDiagnosticOrigin(before, source);
        if (arguments.len != shapes.len) {
            if (self.diagnostics.items.len == before) try self.typeArity(source, if (arguments.len < shapes.len) .missing_nominal else .extra);
            return self.types.fresh();
        }
        if (try self.aliasInstance(index, old, fresh, source)) |alias| return alias;
        return self.types.nominal(nominal_.identity, args.items);
    }
    fn projectionOrigin(self: *Engine, source: ast.Id, name: symbols.Symbol, read: bool) Allocator.Error!u32 {
        if (self.qualifications.items.len == 0) return 0;
        for (self.tree.operator_origins.items) |origin| if (origin.node == source and origin.member == name) {
            const span: ast.Span = if (read) .{ .start = origin.span.end, .end = origin.span.end } else origin.span;
            try self.predicate_origins.append(self.allocator, span);
            return @intCast(self.predicate_origins.items.len);
        };
        return 0;
    }
    fn memberUseOrigin(self: *Engine, requirement: T.Obligation, source: ast.Id) Allocator.Error!u32 {
        if (requirement.explicit or requirement.kind != .receiver or self.types.node(self.types.head(requirement.other, 0)).tag != .unit) return 0;
        const point = self.tree.span(source).start;
        try self.predicate_origins.append(self.allocator, .{ .start = point, .end = point });
        return @intCast(self.predicate_origins.items.len);
    }
    fn projectField(self: *Engine, original: T.Id, name: symbols.Symbol, source: ast.Id, writable: bool, request: ?PendingObligation) T.Error!struct { ty: T.Id, projection: u32 } {
        const ty = try self.types.resolve(original, 0);
        const n = self.types.node(ty);
        if (n.tag == .variable) {
            const result = try self.types.fresh();
            try self.appendPending(.{ .owner = self.current, .origin = try self.projectionOrigin(source, name, !writable), .value = .{ .ty = ty, .kind = if (writable) .writable_field else .field, .name = name, .result = result, .signature = if (writable) 0 else try self.invocation(ty, result), .source = source } });
            const projection: u32 = @intCast(self.projection_catalog.items.len);
            try self.projection_catalog.append(self.allocator, .{ .nominal = .{ .unit = 0, .decl = 0 }, .field = name, .variants = .{} });
            return .{ .ty = result, .projection = projection };
        }
        var variants: std.ArrayList(T.Id) = .empty;
        defer variants.deinit(self.allocator);
        var result: T.Id = 0;
        var identity: Identity = .{ .unit = 0, .decl = 0 };
        if (n.tag == .record) {
            for (0..n.b) |i| {
                const f = self.types.recordField(n, i);
                if (f.name == name) {
                    result = f.ty;
                    try variants.appendSlice(self.allocator, &.{ 0, @intCast(i) });
                    break;
                }
            }
        } else if (n.tag == .nominal) {
            identity = .{ .unit = n.a, .decl = n.b };
            const index = self.nominalIndex(identity) orelse {
                try self.diagnostic(.unknown_field, source);
                return .{ .ty = try self.types.fresh(), .projection = 0 };
            };
            const ctors = try self.allocator.dupe(T.Id, self.types.list(self.nominals.items[index].constructors));
            defer self.allocator.free(ctors);
            for (ctors) |ctor| {
                const definition = self.constructors.items[ctor];
                const use = try self.constructorStorageType(ctor);
                const function = self.types.node(use);
                if (function.tag != .function) {
                    result = 0;
                    break;
                }
                try self.constrain(function.b, ty, source);
                const payload = self.types.node(try self.types.resolve(function.a, 0));
                if (payload.tag != .record) {
                    result = 0;
                    break;
                }
                var found: T.Id = 0;
                for (0..payload.b) |i| {
                    const f = self.types.recordField(payload, i);
                    if (f.name == name) {
                        found = f.ty;
                        try variants.appendSlice(self.allocator, &.{ definition.tag, @intCast(i) });
                        break;
                    }
                }
                if (found == 0) {
                    result = 0;
                    break;
                }
                if (result == 0) result = found else try self.constrain(result, found, source);
            }
        }
        const method = if (!writable) (if (self.identityOf(ty)) |receiver| self.associated_members.get(.{ .identity = receiver, .member = name }) else null) else null;
        if (method) |index| {
            if (result != 0) {
                try self.diagnostic(.ambiguous_member, source);
            } else {
                const binding = self.associated.items[index].binding;
                // An unfinished member has no independently completed body
                // interface yet. Preserve its requirement for the demanded
                // Core instance instead of constraining that unfinished body
                // through an unused returned closure. Other members retain
                // normal source inference so their invocation rows and result
                // requirements remain visible to callers and entry checks.
                const active_member = if (self.global_states.get(binding)) |state| state.state == .active else false;
                var open_self_member = false;
                if (!active_member) if (request) |pending| {
                    if (pending.owner == binding and self.bindings.items[binding].scheme.root == 0) if (self.global_states.get(binding)) |state| {
                        if (state.state == .complete) {
                            // SCC bodies finish before their schemes publish.
                            // Its own open result cannot prove this projection;
                            // a concrete result still admits ordinary recursion.
                            var requirement = pending.value;
                            requirement.kind = .receiver;
                            requirement.other = T.unit;
                            open_self_member = try self.requirementOpen(requirement);
                        }
                    };
                };
                if (!active_member and !open_self_member) try self.prepareGlobal(binding);
                const retained_self_member = !active_member and self.retainsSelfMember(binding, self.associated.items[index]);
                if (active_member or open_self_member or retained_self_member) {
                    result = try self.types.fresh();
                    const expected_function = try self.invocation(ty, result);
                    self.dispatch_signatures[source] = expected_function;
                    var deferred = request orelse PendingObligation{
                        .owner = if (request) |pending| pending.owner else self.current,
                        .scope = if (request) |pending| pending.scope else self.qualification_scope,
                        .value = .{ .ty = ty, .kind = .receiver, .name = name, .other = T.unit, .result = result, .signature = expected_function, .source = source },
                    };
                    // Keep source provenance when a delayed field becomes a
                    // method requirement. The original request belongs to its
                    // qualification boundary, even during nested inference.
                    deferred.value.ty = ty;
                    deferred.value.kind = .receiver;
                    deferred.value.name = name;
                    deferred.value.other = T.unit;
                    deferred.value.result = result;
                    deferred.value.signature = expected_function;
                    deferred.value.source = source;
                    deferred.method_member = true;
                    if (deferred.origin == 0) deferred.origin = try self.projectionOrigin(source, name, true);
                    try self.pending.append(self.allocator, deferred);
                } else {
                    const start = self.pending.items.len;
                    const function = try self.instantiate(binding, source);
                    var projected_origin: ?u32 = null;
                    for (self.pending.items[start..]) |*pending| if (!pending.value.explicit and pending.value.kind == .receiver and self.types.node(self.types.head(pending.value.other, 0)).tag == .unit) {
                        if (projected_origin == null) projected_origin = if (request) |pending_request| if (pending_request.origin != 0) pending_request.origin else try self.projectionOrigin(source, name, true) else try self.projectionOrigin(source, name, true);
                        if (projected_origin.? != 0) pending.origin = projected_origin.?;
                    };
                    result = try self.types.fresh();
                    const expected_function = try self.invocation(ty, result);
                    try self.constrain(function, expected_function, source);
                    self.dispatch_signatures[source] = expected_function;
                }
                variants.clearRetainingCapacity();
            }
        } else if (result == 0) {
            try self.diagnostic(if (writable) .missing_field else .missing_member, source);
            return .{ .ty = try self.types.fresh(), .projection = 0 };
        }
        const projection: u32 = @intCast(self.projection_catalog.items.len);
        try self.projection_catalog.append(self.allocator, .{ .nominal = identity, .field = name, .variants = try self.types.saveList(variants.items) });
        return .{ .ty = result, .projection = projection };
    }
    fn retainsSelfMember(self: *const Engine, binding: BindingId, member: Associated) bool {
        // Finishing the source SCC does not solve a suspended self projection.
        // Its declaration row/result remain requirements of the selected Core
        // instance, not a completed method proof to constrain an unused caller.
        const declaration = self.bindings.items[binding].declaration;
        const state = self.global_states.get(binding) orelse return false;
        if (state.state != .complete) return false;
        // A written qualification deliberately omits inferred predicates from
        // its public scheme. Its suspended body request still belongs to this
        // exact source declaration and must not be mistaken for solved evidence.
        for (self.pending.items) |pending| {
            if (pending.owner != binding or pending.scope != declaration or !pending.method_member or !pending.suspended or pending.solved or pending.covered or pending.declared) continue;
            const requirement = pending.value;
            if (requirement.explicit or requirement.kind != .receiver or requirement.name != member.member or self.types.node(self.types.head(requirement.other, 0)).tag != .unit) continue;
            const receiver = self.identityOf(requirement.ty) orelse continue;
            if (std.meta.eql(receiver, member.identity)) return true;
        }
        return false;
    }
    fn qualifiedValue(self: *Engine, id: ast.Id, name: symbols.Symbol) T.Error!?T.Id {
        const text = self.pool.get(name);
        var parts = std.mem.splitScalar(u8, text, '.');
        const first = parts.next().?;
        if (parts.peek() == null) return null;
        const root = self.pool.lookup(first) orelse return null;
        var binding = self.lookup(root) orelse self.globals.get(root);
        if (binding == null) {
            const member = parts.next().?;
            if (self.pool.lookup(member)) |symbol| binding = self.qualified.get(.{ .namespace = root, .member = symbol });
        }
        const target = binding orelse return null;
        var ty = if (self.bindings.items[target].kind == .global or self.bindings.items[target].kind == .external) try self.globalReference(target, id) else try self.instantiate(target, id);
        self.resolved[id] = target;
        var path: std.ArrayList(T.Id) = .empty;
        defer path.deinit(self.allocator);
        var types_: std.ArrayList(T.Id) = .empty;
        defer types_.deinit(self.allocator);
        try types_.append(self.allocator, ty);
        while (parts.next()) |part| {
            const symbol = self.pool.lookup(part) orelse {
                try self.diagnostic(.unknown_field, id);
                return try self.types.fresh();
            };
            const projected = try self.projectField(ty, symbol, id, false, null);
            ty = projected.ty;
            try path.append(self.allocator, projected.projection);
            try types_.append(self.allocator, ty);
        }
        self.access_paths[id] = try self.types.saveList(path.items);
        self.access_types[id] = try self.types.saveList(types_.items);
        return ty;
    }
    fn selectorFunction(self: *Engine, id: ast.Id) T.Error!T.Id {
        const saved_ambient = self.ambient;
        self.ambient = try self.types.freshEffects();
        const latent = self.ambient;
        try self.row_sources.put(self.allocator, self.types.row(latent).tail.variable, id);
        defer self.ambient = saved_ambient;
        const input = try self.types.fresh();
        const binding = try self.addBinding(.{ .name = 0, .declaration = id, .owner = self.owner, .kind = .parameter, .ty = input });
        self.resolved[id] = binding;
        var path: std.ArrayList(T.Id) = .empty;
        defer path.deinit(self.allocator);
        var types_: std.ArrayList(T.Id) = .empty;
        defer types_.deinit(self.allocator);
        try types_.append(self.allocator, input);
        var current = input;
        var names = std.mem.splitScalar(u8, self.pool.get(self.tree.node(id).a), '.');
        while (names.next()) |part| {
            const name = self.pool.lookup(part) orelse return error.TypeLimit;
            const projected = try self.projectField(current, name, id, false, null);
            try path.append(self.allocator, projected.projection);
            try types_.append(self.allocator, projected.ty);
            current = projected.ty;
        }
        self.access_paths[id] = try self.types.saveList(path.items);
        self.access_types[id] = try self.types.saveList(types_.items);
        return self.types.functionWithEffects(input, current, latent);
    }
    fn recordValue(self: *Engine, id: ast.Id) T.Error!T.Id {
        const n = self.tree.node(id);
        if (n.a == 0) {
            var fields: std.ArrayList(T.Field) = .empty;
            defer fields.deinit(self.allocator);
            var diverges = false;
            for (self.tree.children(id), 0..) |child, index| {
                const field = self.tree.node(child);
                for (fields.items) |prior| if (prior.name == field.a) try self.diagnostic(.duplicate_field, child);
                const value = if (field.b == 0) try self.shorthand(child, field.a) else try self.expression(field.b);
                diverges = diverges or try self.types.resolve(value, 0) == T.never;
                self.expr_types[child] = value;
                self.projections[child] = @intCast(index);
                try fields.append(self.allocator, .{ .name = field.a, .ty = value });
            }
            return if (diverges) T.never else self.types.record(fields.items);
        }
        const constructor = self.constructor_names.get(self.catalogKey(n.a)) orelse {
            try self.diagnostic(.unknown_constructor, id);
            return self.types.fresh();
        };
        self.constructor_resolved[id] = constructor;
        const use = try self.constructorStorageType(constructor);
        const function = self.types.node(use);
        if (function.tag != .function) {
            if (self.constructors.items[constructor].payload == 0 and self.tree.children(id).len == 0) return use;
            try self.diagnostic(.type_mismatch, id);
            return use;
        }
        const payload = self.types.node(function.a);
        if (payload.tag != .record) {
            try self.diagnostic(.type_mismatch, id);
            return function.b;
        }
        const supplied = try self.allocator.alloc(bool, payload.b);
        defer self.allocator.free(supplied);
        @memset(supplied, false);
        var diverges = false;
        for (self.tree.children(id)) |child| {
            const f = self.tree.node(child);
            const value = if (f.b == 0) try self.shorthand(child, f.a) else try self.expression(f.b);
            diverges = diverges or try self.types.resolve(value, 0) == T.never;
            self.expr_types[child] = value;
            var found = false;
            for (0..payload.b) |i| {
                const declared = self.types.recordField(payload, i);
                if (declared.name == f.a) {
                    found = true;
                    if (supplied[i]) try self.diagnostic(.duplicate_field, child);
                    supplied[i] = true;
                    self.projections[child] = @intCast(i);
                    try self.constrain(value, declared.ty, child);
                    break;
                }
            }
            if (!found) try self.diagnostic(.unknown_field, child);
        }
        for (supplied) |present| if (!present) {
            try self.diagnostic(.missing_field, id);
            break;
        };
        return if (diverges) T.never else function.b;
    }
    fn typeConstructorValue(self: *Engine, key: Qualified) T.Error!?T.Id {
        if (key.namespace != 0 and self.lookup(key.namespace) != null) return null;
        const catalog = self.nominal_names.get(key) orelse return null;
        if (try self.resolveAlias(catalog) != 0) return null;
        return try self.types.typeConstructor(self.nominals.items[catalog].identity);
    }
    fn shorthand(self: *Engine, id: ast.Id, name: symbols.Symbol) T.Error!T.Id {
        return self.shorthandBefore(id, name, self.env.items.len);
    }
    fn shorthandBefore(self: *Engine, id: ast.Id, name: symbols.Symbol, limit: usize) T.Error!T.Id {
        const binding_ = for (0..limit) |offset| {
            const entry = self.env.items[limit - offset - 1];
            if (entry.name == name) break entry.binding;
        } else null;
        if (binding_) |binding| {
            self.resolved[id] = binding;
            return self.instantiate(binding, id);
        }
        if (try self.globalBinding(name)) |binding| return self.globalReference(binding, id);
        try self.diagnostic(.unknown_name, id);
        return self.types.fresh();
    }
    fn associatedApplication(self: *Engine, id: ast.Id) T.Error!?T.Id {
        const outer = self.tree.node(id);
        if (self.tree.node(outer.a).tag != .apply) return null;
        const middle = self.tree.node(outer.a);
        if (self.tree.node(middle.a).tag != .apply) return null;
        const inner = self.tree.node(middle.a);
        const head = self.tree.node(inner.a);
        if (head.tag != .intrinsic or !std.mem.eql(u8, self.pool.get(head.a), "@type.call")) return null;
        const literal = self.tree.node(inner.b);
        if (literal.tag != .string) {
            try self.diagnostic(.call_arity, inner.b);
            return try self.types.fresh();
        }
        const left = try self.expression(middle.b);
        const right = try self.expression(outer.b);
        const operation = memberOperator(self.pool.get(literal.a));
        if (try self.dispatch(left, right, literal.a, operation, id, true)) |result| return result;
        const result = try self.types.fresh();
        try self.appendPending(.{ .owner = self.current, .direct = true, .value = .{ .ty = left, .other = right, .result = result, .signature = try self.invocationBinary(left, right, result), .kind = .dispatch, .operator = operation, .name = literal.a, .source = id } });
        return result;
    }
    fn resultApplication(self: *Engine, id: ast.Id) T.Error!?T.Id {
        const outer = self.tree.node(id);
        const inner = self.tree.node(outer.a);
        if (inner.tag != .apply) return null;
        const head = self.tree.node(inner.a);
        if (head.tag != .intrinsic or !std.mem.eql(u8, self.pool.get(head.a), "@type.result")) return null;
        var member = inner.b;
        while (self.tree.node(member).tag == .group) member = self.tree.node(member).a;
        const literal = self.tree.node(member);
        if (literal.tag != .string) {
            try self.diagnostic(.literal_required, member);
            return try self.types.fresh();
        }
        const input = try self.expression(outer.b);
        const result = try self.types.fresh();
        try self.appendPending(.{ .owner = self.current, .direct = true, .value = .{ .ty = input, .result = result, .signature = try self.invocation(input, result), .kind = .result_dispatch, .name = literal.a, .source = id } });
        return result;
    }
    fn productProjection(self: *Engine, id: ast.Id) T.Error!?T.Id {
        const n = self.tree.node(id);
        if (self.tree.node(n.a).tag != .apply) return null;
        const inner = self.tree.node(n.a);
        if (self.tree.node(inner.a).tag != .intrinsic) return null;
        if (!std.mem.eql(u8, self.pool.get(self.tree.node(inner.a).a), "@product.get")) return null;
        const index = self.tree.node(n.b);
        // Source validation owns literal/index ordering before type inference.
        // This defensive check also covers callers of the direct checker API.
        if (index.tag != .integer) {
            try self.diagnostic(.product_index_literal, n.b);
            self.diagnostics.items[self.diagnostics.items.len - 1].span.end = self.diagnostics.items[self.diagnostics.items.len - 1].span.start;
            return try self.types.fresh();
        }
        const ty = try self.expression(inner.b);
        const product = self.types.node(try self.types.resolve(ty, 0));
        self.expr_types[n.b] = T.u32_type;
        switch (product.tag) {
            .never => return T.never,
            .product => if (index.a < product.b) {
                self.projections[id] = index.a;
                return self.types.extra.items[product.a + index.a];
            },
            else => {},
        }
        try self.diagnostic(switch (product.tag) {
            .variable => .unknown_product_shape,
            .product => .product_index,
            else => .type_mismatch,
        }, id);
        self.diagnostics.items[self.diagnostics.items.len - 1].span.end = self.diagnostics.items[self.diagnostics.items.len - 1].span.start;
        return try self.types.fresh();
    }
    fn patternConstrain(self: *Engine, left: T.Id, right: T.Id, source: ast.Id) T.Error!void {
        const before = self.diagnostics.items.len;
        try self.constrain(left, right, source);
        if (self.let_pattern_source != 0) for (self.diagnostics.items[before..]) |*diagnostic_| {
            if (diagnostic_.node != source) continue;
            const point = self.tree.span(self.let_pattern_source).start;
            diagnostic_.node = self.let_pattern_source;
            diagnostic_.span = .{ .start = point, .end = point };
        };
    }
    fn pattern(self: *Engine, id: ast.Id, ty: T.Id, scope: usize, reuse: []const Entry, generalize: bool) T.Error!bool {
        if (id == 0) return true;
        if (self.depth >= 1024) return error.TypeLimit;
        self.depth += 1;
        defer self.depth -= 1;
        const n = self.tree.node(id);
        self.expr_types[id] = ty;
        switch (n.tag) {
            .pattern_name, .pattern_field => {
                if (std.mem.eql(u8, self.pool.get(n.a), "_")) return true;
                for (self.env.items[scope..]) |prior| if (prior.name == n.a) {
                    try self.diagnostic(.duplicate_name, id);
                    return true;
                };
                var selected: ?BindingId = null;
                for (reuse) |prior| if (prior.name == n.a) {
                    selected = prior.binding;
                    try self.patternConstrain(self.bindings.items[prior.binding].ty, ty, id);
                    break;
                };
                const binding = selected orelse if (generalize) try self.local(n.a, ty, id) else try self.addBinding(.{ .name = n.a, .declaration = id, .owner = self.owner, .kind = .local, .ty = ty, .scheme = .{ .root = ty } });
                if (selected != null or !generalize) try self.env.append(self.allocator, .{ .name = n.a, .binding = binding });
                self.resolved[id] = binding;
                return true;
            },
            .pattern_integer => {
                try self.patternConstrain(ty, T.u32_type, id);
                return false;
            },
            .pattern_boolean => {
                try self.patternConstrain(ty, T.boolean, id);
                return false;
            },
            .pattern_value => {
                // Value references belong to the environment before this
                // pattern, independently of sibling binder traversal order.
                const value = try self.shorthandBefore(id, n.a, scope);
                try self.patternConstrain(ty, value, id);
                const tag = self.types.node(try self.types.resolve(value, 0)).tag;
                if (tag != .u32 and tag != .boolean) try self.diagnostic(.value_pattern_type, if (self.case_pattern_source == 0) id else self.case_pattern_source);
                return false;
            },
            .pattern_constructor => {
                const ctor = self.constructor_names.get(self.catalogKey(n.a)) orelse {
                    try self.diagnostic(.unknown_constructor, id);
                    return false;
                };
                self.constructor_resolved[id] = ctor;
                const use = try self.constructorStorageType(ctor);
                const cn = self.types.node(use);
                var payload: T.Id = 0;
                var result = use;
                if (cn.tag == .function) {
                    payload = cn.a;
                    result = cn.b;
                }
                try self.patternConstrain(ty, result, id);
                const definition = self.constructors.items[ctor];
                const unique = self.nominals.items[definition.nominal].constructors.len == 1;
                if (payload == 0) {
                    if (n.b != 0 and !(self.tree.node(n.b).tag == .pattern_record and self.tree.children(n.b).len == 0)) try self.diagnostic(.constructor_arity, id);
                    return unique;
                }
                if (n.b == 0) {
                    try self.diagnostic(.constructor_arity, id);
                    return false;
                }
                const shape = self.types.node(try self.types.resolve(payload, 0));
                // A whole record constructor payload exposes its canonical
                // field values; named record patterns retain the record view.
                if (self.types.node(definition.payload).tag == .record and shape.tag == .record and self.tree.node(n.b).tag != .pattern_record) {
                    payload = try self.canonicalRecordType(shape);
                }
                return (try self.pattern(n.b, payload, scope, reuse, generalize)) and unique;
            },
            .pattern_product => {
                const children = self.tree.children(id);
                if (children.len == 0) {
                    try self.patternConstrain(ty, T.unit, id);
                    return true;
                }
                var fields: std.ArrayList(T.Id) = .empty;
                defer fields.deinit(self.allocator);
                for (children) |_| try fields.append(self.allocator, try self.types.fresh());
                const actual = self.types.node(try self.types.resolve(ty, 0));
                if (actual.tag == .product and actual.b != children.len) {
                    const source = if (self.let_pattern_source != 0) self.let_pattern_source else id;
                    try self.diagnostic(.product_arity, source);
                    self.diagnostics.items[self.diagnostics.items.len - 1].span.end = self.diagnostics.items[self.diagnostics.items.len - 1].span.start;
                } else try self.patternConstrain(ty, try self.types.product(fields.items), id);
                var total = true;
                for (children, fields.items) |child, field_ty| total = (try self.pattern(child, field_ty, scope, reuse, generalize)) and total;
                return total;
            },
            .pattern_record => {
                const record = self.types.node(try self.types.resolve(ty, 0));
                if (record.tag != .record) {
                    try self.diagnostic(.type_mismatch, id);
                    return false;
                }
                const seen = try self.allocator.alloc(bool, record.b);
                defer self.allocator.free(seen);
                @memset(seen, false);
                var total = true;
                for (self.tree.children(id)) |child| {
                    const f = self.tree.node(child);
                    var found = false;
                    for (0..record.b) |i| {
                        const field_ = self.types.recordField(record, i);
                        if (field_.name == f.a) {
                            found = true;
                            if (seen[i]) try self.diagnostic(.duplicate_field, child);
                            seen[i] = true;
                            self.projections[child] = @intCast(i);
                            self.expr_types[child] = field_.ty;
                            total = (try self.pattern(if (f.b == 0) child else f.b, field_.ty, scope, reuse, generalize)) and total;
                            break;
                        }
                    }
                    if (!found) try self.diagnostic(.unknown_field, child);
                }
                return total;
            },
            else => {
                try self.diagnostic(.unsupported, id);
                return false;
            },
        }
    }
    fn caseExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        const n = self.tree.node(id);
        const inputs = self.tree.extra.items[n.a..][0..2];
        var types_: std.ArrayList(T.Id) = .empty;
        defer types_.deinit(self.allocator);
        var diverges = false;
        for (self.tree.list(.{ .start = inputs[0], .len = inputs[1] })) |input| {
            const value = try self.expression(input);
            try types_.append(self.allocator, value);
            diverges = diverges or try self.types.resolve(value, 0) == T.never;
        }
        const scope = self.env.items.len;
        defer self.env.shrinkRetainingCapacity(scope);
        const result = try self.types.fresh();
        for (self.tree.list(.{ .start = n.b, .len = n.c })) |arm_id| {
            const arm = self.tree.node(arm_id);
            const meta = self.tree.extra.items[arm.c..][0..2];
            var first: []Entry = &.{};
            defer self.allocator.free(first);
            for (self.tree.list(.{ .start = arm.a, .len = arm.b }), 0..) |row, row_index| {
                self.env.shrinkRetainingCapacity(scope);
                const patterns = self.tree.children(row);
                if (patterns.len != types_.items.len) {
                    try self.diagnostic(.pattern_arity, row);
                    continue;
                }
                {
                    const saved_pattern_source = self.case_pattern_source;
                    self.case_pattern_source = id;
                    defer self.case_pattern_source = saved_pattern_source;
                    for (patterns, types_.items) |pat, ty| _ = try self.pattern(pat, ty, scope, first, false);
                }

                if (row_index == 0) first = try self.allocator.dupe(Entry, self.env.items[scope..]) else {
                    if (self.env.items.len - scope != first.len) try self.diagnostic(.pattern_bindings, row);
                    for (self.env.items[scope..]) |entry| {
                        var found = false;
                        for (first) |prior| if (entry.name == prior.name) {
                            found = true;
                            break;
                        };
                        if (!found) try self.diagnostic(.pattern_bindings, row);
                    }
                }
            }
            self.env.shrinkRetainingCapacity(scope);
            try self.env.appendSlice(self.allocator, first);
            if (meta[0] != 0) try self.constrain(try self.expression(meta[0]), T.boolean, meta[0]);
            try self.constrain(result, try self.expression(meta[1]), arm_id);
        }
        try self.cases.append(self.allocator, id);
        return if (diverges) T.never else result;
    }
    fn annotationEffects(self: *Engine, id: ast.Id) T.Error!T.Effects.Id {
        const row = self.tree.node(id);
        if (row.tag != .effect_row) return error.TypeLimit;
        const tail: T.Effects.Tail = if (row.c == 0) .closed else self.types.row(try self.rowVariable(self.tree.node(row.c).a, row.c)).tail;
        var labels: std.ArrayList(T.Effects.Label) = .empty;
        defer labels.deinit(self.allocator);
        for (self.tree.list(.{ .start = row.a, .len = row.b })) |label_source| {
            var reverse: std.ArrayList(ast.Id) = .empty;
            defer reverse.deinit(self.allocator);
            var head = label_source;
            while (self.tree.node(head).tag == .type_apply) {
                try reverse.append(self.allocator, self.tree.node(head).b);
                head = self.tree.node(head).a;
            }
            const name = self.tree.node(head);
            if (name.tag != .type_name) {
                try self.diagnostic(.unknown_effect, label_source);
                continue;
            }
            if (std.mem.eql(u8, self.pool.get(name.a), "Foreign")) {
                if (reverse.items.len != 0) try self.diagnostic(.type_arity, label_source) else try labels.append(self.allocator, T.foreign_operation);
                continue;
            }
            var family_index: ?u32 = null;
            var member: ?u32 = null;
            if (self.effect_family_names.get(self.catalogKey(name.a))) |family| {
                family_index = family;
            } else if (self.effect_operation_names.get(self.catalogKey(name.a))) |template| {
                member = template;
                family_index = self.effect_templates.items[template].family;
            } else {
                const text = self.pool.get(name.a);
                if (std.mem.lastIndexOfScalar(u8, text, '.')) |separator| {
                    if (self.textCatalogKey(text[0..separator])) |key| if (self.effect_family_names.get(key)) |family| {
                        if (self.pool.lookup(text[separator + 1 ..])) |symbol| if (self.effect_members.get(.{ .family = family, .member = symbol })) |template| {
                            family_index = family;
                            member = template;
                        };
                    };
                }
            }
            const index = family_index orelse {
                try self.diagnostic(.unknown_effect, label_source);
                continue;
            };
            const family = self.effect_families.items[index];
            const shapes = try self.allocator.dupe(T.Id, self.types.list(family.parameters));
            defer self.allocator.free(shapes);
            if (reverse.items.len != shapes.len) {
                try self.diagnostic(.type_arity, label_source);
                continue;
            }
            std.mem.reverse(ast.Id, reverse.items);
            const old = try self.allocator.dupe(T.Id, self.types.list(family.variables));
            defer self.allocator.free(old);
            const fresh = try self.allocator.alloc(T.Id, old.len);
            defer self.allocator.free(fresh);
            for (fresh) |*variable| variable.* = try self.types.fresh();
            var arguments: std.ArrayList(T.Id) = .empty;
            defer arguments.deinit(self.allocator);
            var closed = true;
            for (reverse.items, shapes, self.parameter_patterns.list(family.patterns)) |syntax, shape, param_pattern| {
                const argument = try self.parameterArgument(param_pattern, syntax, true, 0);
                const selected = try self.types.substitute(shape, old, fresh);
                try self.constrain(argument, selected, syntax);
                const resolved = try self.types.resolve(selected, 0);
                closed = closed and try self.types.equalClosed(resolved, resolved);
                try arguments.append(self.allocator, resolved);
            }
            if (!closed) {
                try self.diagnostic(if (row.c != 0) .unsupported_polymorphic_effect_label else .unsupported_type, if (row.c != 0) id else label_source);
                continue;
            }
            const operations = try self.allocator.dupe(T.Id, if (member) |template| &.{template} else self.types.list(family.operations));
            defer self.allocator.free(operations);
            for (operations) |template| try labels.append(self.allocator, try self.types.internOperation(self.effect_templates.items[template].identity, arguments.items));
        }
        return self.types.effects.row(labels.items, tail) catch |err| return T.effectError(err);
    }
    fn constructorPayloadAnnotation(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        if (node.tag != .type_record) return self.annotation(id);
        const fields_syntax = self.tree.children(id);
        if (self.tree.typeConversionOrigin(id) != self.tree.span(id).start)
            for (fields_syntax, 0..) |field, index| for (fields_syntax[0..index]) |earlier| if (self.tree.node(field).a == self.tree.node(earlier).a) {
                try self.diagnostic(.duplicate_type_field, id);
                const diagnostic_ = &self.diagnostics.items[self.diagnostics.items.len - 1];
                diagnostic_.span.end = diagnostic_.span.start;
                diagnostic_.symbol = self.tree.node(field).a;
                return self.types.fresh();
            };
        if (self.tree.typeConversionOrigin(id) != self.tree.span(id).start) {
            try self.diagnostic(.type_argument, id);
            const point = self.tree.typeConversionOrigin(id);
            self.diagnostics.items[self.diagnostics.items.len - 1].span = .{ .start = point, .end = point };
            return self.types.fresh();
        }
        return self.recordAnnotation(id);
    }
    fn recordAnnotation(self: *Engine, id: ast.Id) T.Error!T.Id {
        var fields: std.ArrayList(T.Field) = .empty;
        defer fields.deinit(self.allocator);
        for (self.tree.children(id)) |child| {
            const field = self.tree.node(child);
            for (fields.items) |prior| if (prior.name == field.a) {
                try self.diagnostic(.duplicate_field, child);
            };
            try fields.append(self.allocator, .{ .name = field.a, .ty = if (field.b == 0) try self.typeVariable(field.a, child) else try self.annotation(field.b) });
        }
        return self.types.record(fields.items);
    }
    fn annotation(self: *Engine, id: ast.Id) T.Error!T.Id {
        if (id == 0) return self.types.fresh();
        if (self.depth >= 1024) return error.TypeLimit;
        self.depth += 1;
        defer self.depth -= 1;
        const node = self.tree.node(id);
        switch (node.tag) {
            .type_name => {
                const name = self.pool.get(node.a);
                if (std.mem.eql(u8, name, "EffectSet")) return self.reflectionType(false);
                if (std.mem.eql(u8, name, "EffectDescriptor")) return self.reflectionType(true);
                if (std.mem.eql(u8, name, "Unit")) return T.unit;
                if (std.mem.eql(u8, name, "Bool")) return T.boolean;
                if (std.mem.eql(u8, name, "U32")) return T.u32_type;
                if (std.mem.eql(u8, name, "F32")) return T.f32_type;
                if (name.len != 0 and (std.ascii.isLower(name[0]) or name[0] == '_') and std.mem.indexOfScalar(u8, name, '.') == null) return self.typeVariable(node.a, id);
                return self.nominalAnnotation(id, &.{}, id);
            },
            .type_demand => return self.types.demand(try self.annotation(node.a)),
            .type_function => {
                const parameter = try self.annotation(node.a);
                const result = try self.annotation(node.b);
                const row = if (node.c == 0) 0 else try self.annotationEffects(node.c);
                return self.types.functionWithEffects(parameter, result, row);
            },
            .type_effect => {
                try self.diagnostic(.invalid_effect_annotation, id);
                return self.annotation(node.a);
            },
            .type_product => {
                var fields: std.ArrayList(T.Id) = .empty;
                defer fields.deinit(self.allocator);
                for (self.tree.children(id)) |child| try fields.append(self.allocator, try self.annotation(child));
                return if (fields.items.len == 0) T.unit else self.types.product(fields.items);
            },
            .type_record => return self.recordAnnotation(id),
            .type_array => {
                try self.diagnostic(.type_argument, id);
                return self.types.fresh();
            },
            .type_apply => {
                var reverse: std.ArrayList(ast.Id) = .empty;
                defer reverse.deinit(self.allocator);
                var head = id;
                while (true) {
                    const n = self.tree.node(head);
                    if (n.tag == .group) {
                        head = n.a;
                        continue;
                    }
                    if (n.tag != .type_apply) break;
                    try reverse.append(self.allocator, n.b);
                    head = n.a;
                }
                std.mem.reverse(ast.Id, reverse.items);
                if (self.tree.node(head).tag != .type_name) {
                    try self.diagnostic(.unsupported_type, id);
                    return self.types.fresh();
                }
                return self.nominalAnnotation(head, reverse.items, id);
            },
            .group => {
                const before = self.diagnostics.items.len;
                const result = try self.annotation(node.a);
                self.applicationDiagnosticOrigin(before, id);
                return result;
            },
            else => {},
        }
        try self.diagnostic(.unsupported_type, id);
        return self.types.fresh();
    }
    fn obligation(self: *Engine, ty: T.Id, kind: T.ObligationKind, id: ast.Id) Allocator.Error!void {
        try self.appendPending(.{ .value = .{ .ty = ty, .kind = kind, .source = id }, .owner = self.current });
    }
    fn lowerPredicates(self: *Engine, id: ast.Id, where_node: ast.Id, output: *std.ArrayList(T.Obligation)) T.Error!void {
        const node = self.tree.node(id);
        const index = self.contract_names.get(self.catalogKey(node.a)) orelse {
            if (try self.lowerPredicate(id, where_node)) |predicate| {
                if (output.items.len >= 65_536) return error.TypeLimit;
                try output.append(self.allocator, predicate);
            }
            return;
        };
        try self.resolveContract(index);
        const contract = self.contracts.items[index];
        const details = self.tree.extra.items[node.c..][0..3];
        const syntax = self.tree.list(.{ .start = details[0], .len = details[1] });
        if (node.b != 0 or details[2] != 0 or syntax.len != contract.parameters.len) {
            try self.diagnostic(.contract_arity, id);
            return;
        }
        const old = try self.allocator.dupe(T.Id, self.types.list(contract.variables));
        defer self.allocator.free(old);
        const fresh = try self.allocator.alloc(T.Id, old.len);
        defer self.allocator.free(fresh);
        for (fresh) |*variable| variable.* = try self.types.fresh();
        const shapes = try self.allocator.dupe(T.Id, self.types.list(contract.parameters));
        defer self.allocator.free(shapes);
        for (shapes, self.parameter_patterns.list(contract.patterns), syntax) |shape, parameter_pattern, origin| {
            const actual = try self.parameterArgument(parameter_pattern, origin, true, 0);
            try self.constrain(try self.types.substitute(shape, old, fresh), actual, origin);
        }
        const rows = try self.allocator.dupe(u32, self.types.list(contract.row_variables));
        defer self.allocator.free(rows);
        const fresh_rows = try self.allocator.alloc(T.Effects.Id, rows.len);
        defer self.allocator.free(fresh_rows);
        for (fresh_rows) |*row| row.* = try self.types.freshEffects();
        if (contract.predicates.len > 65_536 - output.items.len) return error.TypeLimit;
        for (self.contract_predicates.items[contract.predicates.start..][0..contract.predicates.len]) |old_predicate| {
            var predicate = old_predicate;
            inline for (.{ "ty", "other", "result", "signature" }) |field| {
                const root = @field(old_predicate, field);
                @field(predicate, field) = if (root == 0) 0 else try self.types.substituteWithRows(root, old, fresh, rows, fresh_rows);
            }
            predicate.source = id;
            predicate.qualification_unit = self.unit;
            predicate.qualification_span = self.tree.span(where_node);
            try output.append(self.allocator, predicate);
        }
    }
    fn lowerPredicate(self: *Engine, id: ast.Id, where_node: ast.Id) T.Error!?T.Obligation {
        const node = self.tree.node(id);
        const details = self.tree.extra.items[node.c..][0..3];
        const syntax = self.tree.list(.{ .start = details[0], .len = details[1] });
        const name = self.pool.get(node.a);
        const kind: T.ObligationKind = if (std.mem.eql(u8, name, "associated")) .dispatch else if (std.mem.eql(u8, name, "receiver")) .receiver else if (std.mem.eql(u8, name, "merge")) .record_merge else if (std.mem.eql(u8, name, "field")) .field else if (std.mem.eql(u8, name, "update")) .update else if (std.mem.eql(u8, name, "operation")) .effect_operation else if (std.mem.eql(u8, name, "type_rep")) .type_rep else if (std.mem.eql(u8, name, "effect_rep")) .effect_rep else {
            try self.diagnostic(.invalid_constraint, id);
            return null;
        };
        const named = kind == .dispatch or kind == .receiver or kind == .field or kind == .update;
        const expected: usize = switch (kind) {
            .dispatch, .receiver, .update, .record_merge => 3,
            .field => 2,
            .type_rep => 1,
            .effect_rep => 0,
            else => syntax.len,
        };
        const has_invocation = kind == .dispatch or kind == .receiver or kind == .update;
        if ((named and node.b == 0) or (!named and node.b != 0) or syntax.len != expected or
            (kind == .effect_rep and details[2] == 0) or (!has_invocation and kind != .effect_rep and details[2] != 0) or
            (kind == .effect_operation and syntax.len == 0))
        {
            try self.diagnostic(.invalid_constraint, id);
            return null;
        }
        var arguments: std.ArrayList(T.Id) = .empty;
        defer arguments.deinit(self.allocator);
        const skip: usize = if (kind == .effect_operation) 1 else 0;
        if (kind != .effect_operation) for (syntax[skip..]) |argument| try arguments.append(self.allocator, try self.annotation(argument));
        var result: T.Obligation = .{ .ty = T.unit, .kind = kind, .source = id, .name = node.b, .explicit = true, .qualification_span = self.tree.span(where_node), .qualification_unit = self.unit };
        if (kind == .type_rep) {
            result.ty = arguments.items[0];
        } else if (kind == .effect_operation) {
            const head = self.tree.node(syntax[0]);
            const template_index = if (head.tag == .type_name) self.catalogOperationTemplate(head.a) else null;
            const template = self.effect_templates.items[
                template_index orelse {
                    try self.diagnostic(.invalid_constraint, id);
                    return null;
                }
            ];
            const family = self.effect_families.items[template.family];
            if (family.callable or family.parameters.len == 0) {
                try self.diagnostic(.invalid_constraint, id);
                return null;
            }
            if (syntax.len - 1 != family.parameters.len) {
                try self.diagnostic(.effect_arity, where_node);
                return null;
            }
            const old = try self.allocator.dupe(T.Id, self.types.list(family.variables));
            defer self.allocator.free(old);
            const fresh = try self.allocator.alloc(T.Id, old.len);
            defer self.allocator.free(fresh);
            for (fresh) |*variable| variable.* = try self.types.fresh();
            const shapes = try self.allocator.dupe(T.Id, self.types.list(family.parameters));
            defer self.allocator.free(shapes);
            for (shapes, self.parameter_patterns.list(family.patterns), syntax[1..]) |shape, param_pattern, origin| {
                const argument = try self.parameterArgument(param_pattern, origin, true, 0);
                const selected = try self.types.substitute(shape, old, fresh);
                try self.constrain(selected, argument, origin);
                try arguments.append(self.allocator, try self.types.resolve(selected, 0));
            }
            const parameter = try self.types.substitute(template.parameter, old, fresh);
            const output = try self.types.substitute(template.result, old, fresh);
            result.ty = try self.types.functionWithEffects(parameter, output, try self.types.freshEffects());
            result.signature = result.ty;
            result.other = try self.types.product(arguments.items);
            result.identity = template.identity;
        } else if (kind != .effect_rep) {
            result.ty = arguments.items[0];
            if (kind == .field) result.result = arguments.items[1] else {
                result.other = arguments.items[1];
                result.result = arguments.items[2];
                if (kind == .dispatch) result.operator = memberOperator(self.pool.get(node.b));
            }
        }
        if (has_invocation or kind == .effect_rep) {
            const previous_diagnostics = self.diagnostics.items.len;
            const row = if (details[2] == 0) try self.types.freshEffects() else try self.annotationEffects(details[2]);
            for (self.diagnostics.items[previous_diagnostics..]) |*diagnostic_| {
                if (diagnostic_.code == .unsupported_polymorphic_effect_label or diagnostic_.code == .unsupported_type) diagnostic_.code = .unsupported_polymorphic_effect_label;
                if (diagnostic_.code == .unsupported_polymorphic_effect_label or diagnostic_.code == .unknown_effect) {
                    diagnostic_.node = id;
                    diagnostic_.span = self.tree.span(id);
                }
            }
            result.signature = try self.types.functionWithEffects(T.unit, T.unit, row);
        }
        return result;
    }
    fn beginQualification(self: *Engine, scope: ast.Id, where_node: ast.Id, annotation_node: ast.Id, value: ast.Id) T.Error!void {
        if (where_node == 0) return;
        if (annotation_node == 0) try self.diagnostic(.invalid_constraint, where_node);
        const node = self.tree.node(where_node);
        const start: u32 = @intCast(self.declared_obligations.items.len);
        var predicates: std.ArrayList(T.Obligation) = .empty;
        defer predicates.deinit(self.allocator);
        for (self.tree.list(.{ .start = node.a, .len = node.b })) |syntax| try self.lowerPredicates(syntax, where_node, &predicates);
        for (predicates.items) |constraint| {
            try self.declared_obligations.append(self.allocator, constraint);
            try self.appendPending(.{ .owner = self.current, .value = constraint, .declared = true, .suspended = true });
        }
        try self.qualifications.append(self.allocator, .{ .scope = scope, .owner = self.current, .clauses = .{ .start = start, .len = @intCast(self.declared_obligations.items.len - start) }, .value = value });
    }
    fn requirementOpen(self: *Engine, constraint: T.Obligation) T.Error!bool {
        const include_signature = constraint.kind != .dispatch and constraint.kind != .receiver and constraint.kind != .update;
        for ([_]T.Id{ constraint.ty, constraint.other, constraint.result, if (include_signature) constraint.signature else 0 }) |part| {
            if (part == 0) continue;
            const values = try self.types.freeVariables(part);
            defer self.allocator.free(values);
            if (values.len != 0) return true;
            const rows = try self.types.freeRowVariables(part);
            defer self.allocator.free(rows);
            if (rows.len != 0) return true;
        }
        return false;
    }
    fn sourceRequirement(kind: T.ObligationKind) bool {
        return kind == .record_merge or kind == .dispatch or kind == .field or kind == .writable_field or kind == .receiver or kind == .update or kind == .effect_operation or kind == .type_rep or kind == .effect_rep;
    }
    fn requirementHead(self: *const Engine, wanted: T.Obligation, declared: T.Obligation) bool {
        if (wanted.kind == .dispatch and declared.kind == .dispatch) return if (wanted.name != 0) wanted.name == declared.name else wanted.operator != .none and wanted.operator == declared.operator;
        if (wanted.kind == .field and (declared.kind == .field or declared.kind == .receiver)) return wanted.name == declared.name and (declared.kind == .field or self.types.node(self.types.head(declared.other, 0)).tag == .unit);
        if (wanted.kind == .writable_field and declared.kind == .update) return wanted.name == declared.name;
        if (wanted.kind != declared.kind) return false;
        if (wanted.kind == .effect_operation) return wanted.identity.unit == declared.identity.unit and wanted.identity.decl == declared.identity.decl;
        return wanted.name == declared.name;
    }
    fn unifyRequirement(self: *Engine, wanted: T.Obligation, declared: T.Obligation) T.Error!bool {
        if (!self.requirementHead(wanted, declared)) return false;
        const point = self.types.mark();
        const matched = blk: {
            self.types.unify(wanted.ty, declared.ty) catch |err| switch (err) {
                error.OutOfMemory, error.TypeLimit => return err,
                else => break :blk false,
            };
            if (wanted.kind == .writable_field and declared.kind == .update) {
                self.types.unify(wanted.result, declared.other) catch |err| switch (err) {
                    error.OutOfMemory, error.TypeLimit => return err,
                    else => break :blk false,
                };
                self.types.unify(wanted.ty, declared.result) catch |err| switch (err) {
                    error.OutOfMemory, error.TypeLimit => return err,
                    else => break :blk false,
                };
            } else {
                if (wanted.other != 0 and declared.other != 0 and wanted.kind != .field) self.types.unify(wanted.other, declared.other) catch |err| switch (err) {
                    error.OutOfMemory, error.TypeLimit => return err,
                    else => break :blk false,
                };
                if (wanted.result != 0 and declared.result != 0) self.types.unify(wanted.result, declared.result) catch |err| switch (err) {
                    error.OutOfMemory, error.TypeLimit => return err,
                    else => break :blk false,
                };
            }
            if (wanted.signature != 0 and declared.signature != 0) {
                if (wanted.kind == .effect_operation) {
                    self.types.unify(wanted.signature, declared.signature) catch |err| switch (err) {
                        error.OutOfMemory, error.TypeLimit => return err,
                        else => break :blk false,
                    };
                } else {
                    const a_ = self.types.node(try self.types.resolve(wanted.signature, 0));
                    const b_ = self.types.node(try self.types.resolve(declared.signature, 0));
                    if (a_.tag != .function or b_.tag != .function) break :blk false;
                    // Coverage relates source operands/results. Dispatch
                    // signatures here carry the surrounding ambient
                    // row; the retained explicit clause checks the selected
                    // implementation's actual row independently.
                    const ambient_signature = wanted.kind == .dispatch;
                    if (!ambient_signature) self.types.unifyEffects(a_.c, b_.c) catch |err| switch (err) {
                        error.OutOfMemory => return err,
                        else => break :blk false,
                    };
                }
            }
            break :blk true;
        };
        if (!matched) self.types.rollback(point);
        return matched;
    }
    fn checkQualification(self: *Engine, index: usize) T.Error!void {
        const boundary = self.qualifications.items[index];
        if (boundary.checked) return;
        for (self.qualification_uses.items) |use| if (use.scope == boundary.scope) {
            const state = self.global_states.get(use.target).?;
            if (state.on_stack) return;
        };
        var i: usize = 0;
        while (i < self.pending.items.len) : (i += 1) {
            const pending = self.pending.items[i];
            if (pending.scope != boundary.scope or pending.declared or pending.covered or pending.solved or pending.local_scheme) continue;
            if (!sourceRequirement(pending.value.kind)) continue;
            if (!try self.requirementOpen(pending.value)) {
                // This boundary publishes no inferred source predicates.
                // A closed self projection is still deferred evidence, not
                // an open requirement that needs an explicit clause. Keep
                // its signature for demanded Core checking; do not claim an
                // unused nested callable has already selected a valid result.
                if (pending.method_member and !pending.value.explicit and pending.value.kind == .receiver and self.types.node(self.types.head(pending.value.other, 0)).tag == .unit and pending.owner != 0 and pending.scope == self.bindings.items[pending.owner].declaration and self.bindings.items[pending.owner].scheme.root == 0) {
                    if (self.global_states.get(pending.owner)) |state| {
                        if (state.state == .complete) if (self.identityOf(pending.value.ty)) |receiver| {
                            if (self.associated_members.get(.{ .identity = receiver, .member = pending.value.name })) |member| {
                                if (self.associated.items[member].binding == pending.owner) self.pending.items[i].suspended = true;
                            }
                        };
                    }
                }
                continue;
            }
            // This implicit receiver is the retained proof of a source field
            // projection. Written field and Unit receiver clauses both cover
            // that projection; its selected semantic proof remains a receiver.
            var coverage = pending.value;
            if (pending.method_member and !coverage.explicit and coverage.kind == .receiver and self.types.node(self.types.head(coverage.other, 0)).tag == .unit) {
                coverage.kind = .field;
                coverage.other = 0;
            }
            var matched_requirement = false;
            var clause: u32 = 0;
            while (clause < boundary.clauses.len) : (clause += 1) {
                const declared = self.declared_obligations.items[boundary.clauses.start + clause];
                if (try self.unifyRequirement(coverage, declared)) {
                    matched_requirement = true;
                    break;
                }
            }
            if (!matched_requirement) {
                try self.diagnostic(.missing_predicate, pending.value.source);
                if (pending.origin != 0) self.diagnostics.items[self.diagnostics.items.len - 1].span = self.predicate_origins.items[pending.origin - 1] else for (self.tree.operator_origins.items) |origin| if (origin.node == pending.value.source and self.tree.node(origin.node).tag == .binary) {
                    self.diagnostics.items[self.diagnostics.items.len - 1].span = origin.span;
                    break;
                };
            } else {
                self.pending.items[i].covered = true;
                self.pending.items[i].suspended = true;
            }
        }
        self.qualifications.items[index].checked = true;
    }
    fn targetRequirements(self: *Engine, target: BindingId, limit: usize, visited: *std.ArrayList(BindingId), output: *std.ArrayList(T.Obligation), depth: usize) T.Error!void {
        if (depth >= 1024) return error.TypeLimit;
        if (inList(visited.items, target)) return;
        try visited.append(self.allocator, target);
        const scope = self.bindings.items[target].declaration;
        for (self.qualifications.items) |boundary| if (boundary.scope == scope) {
            try output.appendSlice(self.allocator, self.declared_obligations.items[boundary.clauses.start..][0..boundary.clauses.len]);
            return;
        };
        for (self.pending.items[0..limit]) |pending| if (pending.scope == scope and !pending.solved and !pending.declared and !pending.covered and !pending.local_scheme) try output.append(self.allocator, pending.value);
        for (self.qualification_uses.items) |use| if (use.scope == scope) try self.targetRequirements(use.target, limit, visited, output, depth + 1);
    }
    fn expandQualificationUses(self: *Engine, group: []const BindingId) T.Error!void {
        var qualified = false;
        for (self.qualifications.items) |boundary| if (inList(group, boundary.owner)) {
            qualified = true;
            break;
        };
        if (!qualified) return;
        const limit = self.pending.items.len;
        const saved_scope = self.qualification_scope;
        defer self.qualification_scope = saved_scope;
        for (self.qualification_uses.items) |use| {
            if (!inList(group, use.target)) continue;
            var visited: std.ArrayList(BindingId) = .empty;
            defer visited.deinit(self.allocator);
            var requirements: std.ArrayList(T.Obligation) = .empty;
            defer requirements.deinit(self.allocator);
            try self.targetRequirements(use.target, limit, &visited, &requirements, 0);
            self.qualification_scope = use.scope;
            for (requirements.items) |constraint| {
                var value = constraint;
                value.source = use.source;
                // A forwarded implicit method projection is required at this
                // reference occurrence, rather than at the member's body.
                try self.appendPending(.{ .owner = use.owner, .origin = try self.memberUseOrigin(value, use.source), .suspended = value.explicit and value.kind != .record_merge, .value = value });
            }
        }
    }
    fn scheme(self: *Engine, root: T.Id, excluded: []const T.Id, group: []const BindingId, capture_concrete: bool, certificate_owner: BindingId, qualification_scope: ast.Id) T.Error!T.Scheme {
        try self.solveFields();
        const resolved = try self.types.resolve(root, 0);
        const free = try self.types.freeVariables(resolved);
        defer self.allocator.free(free);
        const Candidate = struct { index: usize, variables: []T.Id, rows: []u32, retained: bool = false };
        var candidates: std.ArrayList(Candidate) = .empty;
        defer {
            for (candidates.items) |candidate| {
                self.allocator.free(candidate.variables);
                self.allocator.free(candidate.rows);
            }
            candidates.deinit(self.allocator);
        }
        for (self.pending.items, 0..) |pending, index| {
            if (pending.solved or pending.covered or pending.local_scheme or !inList(group, pending.owner) or (pending.declared and pending.scope != qualification_scope)) continue;
            if (!capture_concrete and pending.value.explicit and index < self.local_requirements_start) continue;
            var qualified = false;
            for (self.qualifications.items) |boundary| if (boundary.scope == qualification_scope) {
                qualified = true;
                break;
            };
            if (qualified and !pending.declared and pending.scope == qualification_scope and sourceRequirement(pending.value.kind)) continue;
            var predicate_free: std.ArrayList(T.Id) = .empty;
            defer predicate_free.deinit(self.allocator);
            for ([_]T.Id{ pending.value.ty, pending.value.other, pending.value.result, pending.value.signature }) |part| {
                if (part == 0) continue;
                const vars = try self.types.freeVariables(part);
                defer self.allocator.free(vars);
                for (vars) |variable| if (!inList(predicate_free.items, variable)) try predicate_free.append(self.allocator, variable);
            }
            var predicate_rows: std.ArrayList(u32) = .empty;
            defer predicate_rows.deinit(self.allocator);
            for ([_]T.Id{ pending.value.ty, pending.value.other, pending.value.result, pending.value.signature }) |part| {
                if (part == 0) continue;
                const rows = try self.types.freeRowVariables(part);
                defer self.allocator.free(rows);
                for (rows) |row| if (!inList(predicate_rows.items, row)) try predicate_rows.append(self.allocator, row);
            }
            const owned = try predicate_free.toOwnedSlice(self.allocator);
            errdefer self.allocator.free(owned);
            const owned_rows = try predicate_rows.toOwnedSlice(self.allocator);
            errdefer self.allocator.free(owned_rows);
            try candidates.append(self.allocator, .{ .index = index, .variables = owned, .rows = owned_rows });
        }
        // A latent result depending on an outer variable is itself monomorphic.
        // This closure prevents a local binding from generalizing p.x while p
        // still belongs to an enclosing function's inference region.
        var outer: std.ArrayList(T.Id) = .empty;
        defer outer.deinit(self.allocator);
        try outer.appendSlice(self.allocator, excluded);
        var outer_rows: std.ArrayList(u32) = .empty;
        defer outer_rows.deinit(self.allocator);
        const ambient_free = self.types.effects.freeVariables(self.ambient) catch |err| return T.effectError(err);
        defer self.allocator.free(ambient_free);
        try outer_rows.appendSlice(self.allocator, ambient_free);
        if (!capture_concrete) {
            for (self.computation_annotations.items) |annotation_type| {
                const annotation_free = try self.types.freeVariables(annotation_type);
                defer self.allocator.free(annotation_free);
                try outer.appendSlice(self.allocator, annotation_free);
                const annotation_rows = try self.types.freeRowVariables(annotation_type);
                defer self.allocator.free(annotation_rows);
                try outer_rows.appendSlice(self.allocator, annotation_rows);
            }
            try outer.appendSlice(self.allocator, self.computed_variables.items);
            try outer_rows.appendSlice(self.allocator, self.computed_rows.items);
            const rows = try self.environmentRows();
            defer self.allocator.free(rows);
            try outer_rows.appendSlice(self.allocator, rows);
        }
        var progress = true;
        while (progress) {
            progress = false;
            for (candidates.items) |candidate| {
                var connected = false;
                for (candidate.variables) |variable| if (inList(outer.items, variable)) {
                    connected = true;
                    break;
                };
                for (candidate.rows) |row| if (inList(outer_rows.items, row)) {
                    connected = true;
                    break;
                };
                if (!connected) continue;
                for (candidate.rows) |row| if (!inList(outer_rows.items, row)) {
                    try outer_rows.append(self.allocator, row);
                    progress = true;
                };
                for (candidate.variables) |variable| if (!inList(outer.items, variable)) {
                    try outer.append(self.allocator, variable);
                    progress = true;
                };
            }
        }
        var variables: std.ArrayList(T.Id) = .empty;
        defer variables.deinit(self.allocator);
        for (free) |id| if (!inList(outer.items, id)) try variables.append(self.allocator, id);
        var row_variables: std.ArrayList(u32) = .empty;
        defer row_variables.deinit(self.allocator);
        const free_rows = try self.types.freeRowVariables(resolved);
        defer self.allocator.free(free_rows);
        for (free_rows) |row| if (!inList(outer_rows.items, row)) try row_variables.append(self.allocator, row);
        // Quantifiers cover the entire retained predicate graph, including
        // intermediate dispatch results absent from the visible signature.
        // Each use freshens these private variables with the public ones.
        progress = true;
        while (progress) {
            progress = false;
            for (candidates.items) |*candidate| {
                const pending = self.pending.items[candidate.index];
                var retained = candidate.retained or pending.method_member or pending.value.explicit or (capture_concrete and (pending.value.kind == .dispatch or pending.value.kind == .result_dispatch or pending.value.kind == .monad_factory or pending.value.kind == .resolver_dispatch or pending.value.kind == .resolver_shape or pending.value.kind == .effect_operation or pending.value.kind == .effect_handler or pending.value.kind == .type_head) and !pending.suspended);
                if (!retained) for (candidate.variables) |variable| if (inList(variables.items, variable)) {
                    retained = true;
                    break;
                };
                if (!retained) for (candidate.rows) |row| if (inList(row_variables.items, row)) {
                    retained = true;
                    break;
                };
                if (!retained) continue;
                if (!candidate.retained) {
                    candidate.retained = true;
                    progress = true;
                }
                for (candidate.rows) |row| if (!inList(outer_rows.items, row) and !inList(row_variables.items, row)) {
                    try row_variables.append(self.allocator, row);
                    progress = true;
                };
                for (candidate.variables) |variable| if (!inList(outer.items, variable) and !inList(variables.items, variable)) {
                    try variables.append(self.allocator, variable);
                    progress = true;
                };
            }
        }
        var protected_rows: std.ArrayList(u32) = .empty;
        defer protected_rows.deinit(self.allocator);
        for (candidates.items) |candidate| if (candidate.retained) {
            for (candidate.rows) |row| if (!inList(protected_rows.items, row)) try protected_rows.append(self.allocator, row);
        };
        const closed = try self.types.closeCovariantCertified(resolved, row_variables.items, protected_rows.items);
        try self.recordClosedRows(certificate_owner, closed.closed_rows);
        // Closing a positive tail removes it from the public quantifier set.
        // The raw body certificate retains its identity independently.
        const remaining_rows = try self.types.freeRowVariables(closed.root);
        defer self.allocator.free(remaining_rows);
        var kept: usize = 0;
        for (row_variables.items) |variable| if (inList(remaining_rows, variable) or inList(protected_rows.items, variable)) {
            row_variables.items[kept] = variable;
            kept += 1;
        };
        row_variables.shrinkRetainingCapacity(kept);
        const span = try self.types.saveList(variables.items);
        const start: u32 = @intCast(self.obligations.items.len);
        for (candidates.items) |candidate| {
            if (!candidate.retained) continue;
            const pending = self.pending.items[candidate.index];
            try self.obligations.append(self.allocator, .{ .ty = try self.types.resolve(pending.value.ty, 0), .kind = pending.value.kind, .source = pending.value.source, .name = pending.value.name, .result = if (pending.value.result == 0) 0 else try self.types.resolve(pending.value.result, 0), .other = if (pending.value.other == 0) 0 else try self.types.resolve(pending.value.other, 0), .signature = if (pending.value.signature == 0) 0 else try self.types.resolve(pending.value.signature, 0), .operator = pending.value.operator, .identity = pending.value.identity, .explicit = pending.value.explicit, .qualification_span = pending.value.qualification_span, .qualification_unit = pending.value.qualification_unit });
            self.pending.items[candidate.index].suspended = true;
            if (!capture_concrete and pending.value.explicit) self.pending.items[candidate.index].local_scheme = true;
        }
        return .{ .root = closed.root, .variables = span, .row_variables = try self.types.saveList(row_variables.items), .closed_rows = closed.closed_rows, .obligations = .{ .start = start, .len = @intCast(self.obligations.items.len - start) } };
    }
    fn instantiate(self: *Engine, binding: BindingId, source: ast.Id) T.Error!T.Id {
        const principal = self.bindings.items[binding].scheme;
        if (principal.root == 0) return self.types.openCovariant(try self.types.resolve(self.bindings.items[binding].ty, 0));
        var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const temporary = scratch.allocator();
        const old = try temporary.dupe(T.Id, self.types.list(principal.variables));
        defer temporary.free(old);
        const fresh_ids = try temporary.alloc(T.Id, old.len);
        defer temporary.free(fresh_ids);
        for (fresh_ids) |*id| id.* = try self.types.fresh();
        const old_rows = try temporary.dupe(u32, self.types.list(principal.row_variables));
        defer temporary.free(old_rows);
        const fresh_rows = try temporary.alloc(T.Effects.Id, old_rows.len);
        defer temporary.free(fresh_rows);
        for (fresh_rows) |*row| row.* = try self.types.freshEffects();
        const value = try self.types.substituteWithRows(principal.root, old, fresh_ids, old_rows, fresh_rows);
        for (self.obligations.items[principal.obligations.start..][0..principal.obligations.len]) |constraint| {
            const ty = try self.types.substituteWithRows(constraint.ty, old, fresh_ids, old_rows, fresh_rows);
            try self.appendPending(.{ .owner = self.current, .origin = try self.memberUseOrigin(constraint, source), .suspended = constraint.explicit and constraint.kind != .record_merge, .method_member = constraint.kind == .receiver and !constraint.explicit, .value = .{ .ty = ty, .kind = constraint.kind, .source = source, .name = constraint.name, .result = if (constraint.result == 0) 0 else try self.types.substituteWithRows(constraint.result, old, fresh_ids, old_rows, fresh_rows), .other = if (constraint.other == 0) 0 else try self.types.substituteWithRows(constraint.other, old, fresh_ids, old_rows, fresh_rows), .signature = if (constraint.signature == 0) 0 else try self.types.substituteWithRows(constraint.signature, old, fresh_ids, old_rows, fresh_rows), .operator = constraint.operator, .identity = constraint.identity, .explicit = constraint.explicit, .qualification_span = constraint.qualification_span, .qualification_unit = constraint.qualification_unit } });
        }
        return self.types.openCovariant(value);
    }
    fn purityIdentity(context: *anyopaque, allocator: Allocator, identity: Identity, kind: @import("purity_type_key.zig").Kind) @import("purity_type_key.zig").OriginError!@import("purity_type_key.zig").Identity {
        const self: *Engine = @ptrCast(@alignCast(context));
        const module_name = try self.purity_origins.name(allocator, identity.unit, self.unit);
        errdefer allocator.free(module_name);
        const declaration = switch (kind) {
            .nominal => blk: {
                const index = self.nominal_identities.get(identity) orelse return error.SourceIdentityUnavailable;
                break :blk try allocator.dupe(u8, self.pool.get(self.nominals.items[index].name));
            },
            .operation => blk: {
                const index = self.effect_template_identities.get(identity) orelse return error.SourceIdentityUnavailable;
                const template = self.effect_templates.items[index];
                if (template.family == 0) return error.SourceIdentityUnavailable;
                const family = self.effect_families.items[template.family];
                break :blk if (family.callable) try allocator.dupe(u8, self.pool.get(family.name)) else try allocator.print("{s}.{s}", .{ self.pool.get(family.name), self.pool.get(template.name) });
            },
        };
        return .{ .module = module_name, .declaration = declaration };
    }
    fn purityArguments(context: *anyopaque, allocator: Allocator, identity: Identity, kind: @import("purity_type_key.zig").Kind, actual: []const T.Id) @import("purity_type_key.zig").OriginError![]T.Id {
        const self: *Engine = @ptrCast(@alignCast(context));
        const Formal = struct { patterns: P.List, variables: T.List };
        const formal: Formal = switch (kind) {
            .nominal => blk: {
                const nominal = self.nominals.items[self.nominal_identities.get(identity) orelse return error.SourceIdentityUnavailable];
                break :blk .{ .patterns = nominal.patterns, .variables = nominal.variables };
            },
            .operation => blk: {
                const template = self.effect_templates.items[self.effect_template_identities.get(identity) orelse return error.SourceIdentityUnavailable];
                if (template.family == 0) return error.SourceIdentityUnavailable;
                const family = self.effect_families.items[template.family];
                break :blk .{ .patterns = family.patterns, .variables = family.variables };
            },
        };
        const patterns = self.parameter_patterns.list(formal.patterns);
        if (patterns.len != actual.len) return error.TypeLimit;
        // Frozen lowering specializes logical binder order, not argument-shape
        // containers. Preserve imported pattern IDs and original declaration.
        const variables = try allocator.dupe(T.Id, self.types.list(formal.variables));
        defer allocator.free(variables);
        const result = try allocator.alloc(T.Id, variables.len);
        errdefer allocator.free(result);
        @memset(result, 0);
        const Item = struct { pattern: P.Id, actual: T.Id };
        var pending: std.ArrayList(Item) = .empty;
        defer pending.deinit(allocator);
        for (patterns, actual) |formal_pattern, ty| try pending.append(allocator, .{ .pattern = formal_pattern, .actual = ty });
        while (pending.pop()) |item| {
            const formal_pattern = self.parameter_patterns.node(item.pattern);
            const resolved = try self.types.resolve(item.actual, 0);
            if (formal_pattern.kind == .binding) {
                var found = false;
                for (variables, result) |variable, *slot| if (variable == formal_pattern.a) {
                    slot.* = resolved;
                    found = true;
                    break;
                };
                if (!found) return error.TypeLimit;
                continue;
            }
            const shape = self.types.node(resolved);
            if (formal_pattern.kind == .record) {
                if (shape.tag != .record or shape.b != formal_pattern.b) return error.TypeLimit;
                for (0..formal_pattern.b) |index| {
                    const field = self.parameter_patterns.field(formal_pattern, index);
                    var child: T.Id = 0;
                    for (0..shape.b) |actual_index| {
                        const actual_field = self.types.recordField(shape, actual_index);
                        if (actual_field.name == field.name) {
                            child = actual_field.ty;
                            break;
                        }
                    }
                    if (child == 0) return error.TypeLimit;
                    try pending.append(allocator, .{ .pattern = field.pattern, .actual = child });
                }
            } else {
                if (formal_pattern.b == 0 and shape.tag == .unit) continue;
                if (shape.tag != .product or shape.b != formal_pattern.b) return error.TypeLimit;
                for (self.parameter_patterns.list(.{ .start = formal_pattern.a, .len = formal_pattern.b }), 0..) |child, index| try pending.append(allocator, .{ .pattern = child, .actual = self.types.extra.items[shape.a + index] });
            }
        }
        for (result) |ty| if (ty == 0) return error.TypeLimit;
        return result;
    }
    fn initializerPurity(self: *Engine, declaration: ast.Id) T.Error!void {
        const resolved = try self.types.resolveEffects(self.ambient, 0);
        const labels = self.types.rowLabels(resolved);
        if (labels.len == 0) return self.types.unifyEffects(resolved, 0);
        const operation = self.types.operation(labels[0]);
        var witness: PurityWitness = .{ .identity = operation.identity, .foreign = labels[0] == T.foreign_operation, .specialized = operation.arguments.len != 0 };
        if (self.effect_template_identities.get(operation.identity)) |index| {
            const template = self.effect_templates.items[index];
            if (template.family != 0) {
                const family = self.effect_families.items[template.family];
                witness.family = family.name;
                witness.member = template.name;
                witness.compound = !family.callable;
            }
        }
        const key_context: @import("purity_type_key.zig").Context = .{ .allocator = self.allocator, .types = &self.types, .source = self, .origin = purityIdentity, .arguments = purityArguments };
        const identity: ?@import("purity_type_key.zig").Identity = key_context.operation(labels[0], 65536) catch |err| switch (err) {
            error.SourceIdentityUnavailable => null,
            error.AmbiguousTypeKey, error.SpecializationLimit => return error.TypeLimit,
            else => |failure| return failure,
        };
        if (identity) |owned_identity| {
            defer owned_identity.deinit(self.allocator);
            witness.operation_name = try self.allocator.print("{s}::{s}", .{ owned_identity.module, owned_identity.declaration });
        } else witness.origin_unavailable = true;
        errdefer witness.deinit(self.allocator);
        const point = self.tree.valueNamePoint(declaration) orelse return error.TypeLimit;
        try self.diagnostics.append(self.allocator, .{ .code = if (self.tree.valueDecl(declaration).runtime) .initializer_effect else .const_effect, .span = .{ .start = point, .end = point }, .node = declaration, .purity = witness });
        self.initializer_rejected = true;
    }
    const GlobalContext = struct {
        current: BindingId,
        pending_start: usize,
        owner: ast.Id,
        qualification_scope: ast.Id,
        target: T.Id,
        loops: std.ArrayList(LoopFrame),
        escape: bool,
        resolver: ResolverScope,
        ambient: T.Effects.Id,
        annotation_binding: ast.Id,
        inherited_types: usize,
        inherited_rows: usize,
        type_env: ?@TypeOf(@as(Engine, undefined).type_env.items) = null,
        row_env: ?@TypeOf(@as(Engine, undefined).row_env.items) = null,
        computation_annotations: ?[]T.Id = null,
        env: ?[]Entry = null,
        loops_changed: bool = false,
        annotations_changed: bool = false,
        env_changed: bool = false,
        fn restore(self: *GlobalContext, engine: *Engine) void {
            if (self.env_changed) {
                engine.env.clearRetainingCapacity();
                engine.env.appendSliceAssumeCapacity(self.env.?);
                engine.current = self.current;
                engine.owner = self.owner;
                engine.return_target = self.target;
            }
            if (self.env) |items| engine.allocator.free(items);
            if (self.annotations_changed) {
                engine.annotation_binding = self.annotation_binding;
                engine.inherited_types = self.inherited_types;
                engine.inherited_rows = self.inherited_rows;
            }
            if (self.computation_annotations) |items| {
                engine.computation_annotations.deinit(engine.allocator);
                engine.computation_annotations = std.ArrayList(T.Id).fromOwnedSlice(items);
            }
            if (self.row_env) |items| {
                engine.row_env.deinit(engine.allocator);
                engine.row_env = @FieldType(Engine, "row_env").fromOwnedSlice(items);
            }
            if (self.type_env) |items| {
                engine.type_env.deinit(engine.allocator);
                engine.type_env = @FieldType(Engine, "type_env").fromOwnedSlice(items);
            }
            if (self.loops_changed) {
                engine.loop_stack.deinit(engine.allocator);
                engine.loop_stack = self.loops;
                engine.suspended_loop_escape = self.escape;
            }
            engine.resolver_scope = self.resolver;
            engine.ambient = self.ambient;
            engine.qualification_scope = self.qualification_scope;
            engine.pending_start = self.pending_start;
            self.* = undefined;
        }
    };
    const GlobalFrame = struct {
        binding: BindingId,
        id: ast.Id,
        required: T.Id,
        initializer_diagnostics: usize,
        context: GlobalContext,
        plan_index: usize = 0,
        before: ?Global = null,
    };
    fn traceGlobal(self: *Engine, kind: @FieldType(GlobalTrace, "kind"), binding: BindingId) void {
        const observe = self.execution.observe orelse return;
        const state = self.global_states.get(binding).?;
        observe(self.execution.context, .{
            .kind = kind,
            .binding = binding,
            .counter = self.counter,
            .index = state.index,
            .low = state.low,
            .active = self.active.items.len,
            .current = self.current,
            .owner = self.owner,
            .ambient = self.ambient,
            .pending_start = self.pending_start,
            .type_nodes = self.types.nodes.items.len,
            .type_versions = self.types.versions.items.len,
            .row_versions = self.types.effects.versions.items.len,
            .type_env = self.type_env.items.len,
            .row_env = self.row_env.items.len,
            .computation_annotations = self.computation_annotations.items.len,
        });
    }
    // Both execution engines use this exact prefix, including every fallible
    // operation's original position. Frames only replace native call ownership.
    fn beginGlobal(self: *Engine, binding: BindingId) T.Error!GlobalFrame {
        self.counter += 1;
        try self.global_states.put(self.allocator, binding, .{ .state = .active, .index = self.counter, .low = self.counter, .on_stack = true });
        try self.active.append(self.allocator, binding);
        var context: GlobalContext = .{
            .current = self.current,
            .pending_start = self.pending_start,
            .owner = self.owner,
            .qualification_scope = self.qualification_scope,
            .target = self.return_target,
            .loops = self.loop_stack,
            .escape = self.suspended_loop_escape,
            .resolver = self.resolver_scope,
            .ambient = self.ambient,
            .annotation_binding = self.annotation_binding,
            .inherited_types = self.inherited_types,
            .inherited_rows = self.inherited_rows,
        };
        errdefer context.restore(self);
        self.pending_start = self.pending.items.len;
        self.ambient = try self.types.freshEffects();
        self.resolver_scope = .{};
        self.loop_stack = .empty;
        self.suspended_loop_escape = false;
        context.loops_changed = true;
        const type_env = try self.type_env.toOwnedSlice(self.allocator);
        context.type_env = type_env;
        const row_env = try self.row_env.toOwnedSlice(self.allocator);
        context.row_env = row_env;
        const annotations = try self.computation_annotations.toOwnedSlice(self.allocator);
        context.computation_annotations = annotations;
        self.annotation_binding = 0;
        self.inherited_types = 0;
        self.inherited_rows = 0;
        context.annotations_changed = true;
        const env = try self.allocator.dupe(Entry, self.env.items);
        context.env = env;
        self.env.clearRetainingCapacity();
        self.current = binding;
        self.owner = self.bindings.items[binding].declaration;
        self.return_target = 0;
        context.env_changed = true;
        const id = self.bindings.items[binding].declaration;
        self.qualification_scope = id;
        const declaration = self.tree.valueDecl(id);
        try self.collectAnnotationNames(declaration.annotation, 0);
        try self.collectAnnotationNames(declaration.where_node, 0);
        try self.collectAnnotationNames(declaration.body, 0);
        for (self.tree.list(declaration.attributes)) |attribute| try self.collectAnnotationNames(self.tree.node(attribute).a, 0);
        const initializer_diagnostics = self.diagnostics.items.len;
        const required = if (declaration.annotation != 0) try self.annotation(declaration.annotation) else 0;
        try self.beginQualification(id, declaration.where_node, declaration.annotation, declaration.body);
        self.body_elaborations += 1;
        self.traceGlobal(.begun, binding);
        return .{ .binding = binding, .id = id, .required = required, .initializer_diagnostics = initializer_diagnostics, .context = context };
    }
    fn finishGlobal(self: *Engine, frame: *const GlobalFrame, value: T.Id) T.Error!void {
        const binding = frame.binding;
        const id = frame.id;
        const required = frame.required;
        const initializer_diagnostics = frame.initializer_diagnostics;
        const declaration = self.tree.valueDecl(id);
        if (required != 0) try self.constrain(self.bindings.items[binding].ty, required, if (declaration.attributes.len == 0) id else declaration.annotation);
        try self.constrain(self.bindings.items[binding].ty, value, if (declaration.attributes.len != 0 and required != 0) declaration.annotation else id);
        if (self.diagnostics.items.len == initializer_diagnostics) {
            self.initializerPurity(id) catch |err| switch (err) {
                error.OutOfMemory => return err,
                error.InfiniteEffect => try self.diagnostic(.infinite_effect, id),
                else => return err,
            };
        }
        const now = self.global_states.get(binding).?;
        if (now.low == now.index) {
            var group: std.ArrayList(BindingId) = .empty;
            defer group.deinit(self.allocator);
            while (self.active.pop()) |member| {
                var state = self.global_states.get(member).?;
                state.state = .complete;
                state.on_stack = false;
                try self.global_states.put(self.allocator, member, state);
                try group.append(self.allocator, member);
                if (member == binding) break;
            }
            try self.expandQualificationUses(group.items);
            try self.solveFields();
            var qualification: usize = 0;
            while (qualification < self.qualifications.items.len) : (qualification += 1) if (inList(group.items, self.qualifications.items[qualification].owner)) try self.checkQualification(qualification);
            for (group.items) |member| {
                const principal = try self.scheme(self.bindings.items[member].ty, &.{}, group.items, true, member, self.bindings.items[member].declaration);
                self.bindings.items[member].scheme = principal;
            }
        }
        self.traceGlobal(.finished, binding);
    }
    fn inferGlobal(self: *Engine, binding: BindingId) T.Error!void {
        if (self.global_states.get(binding).?.state != .pending) return;
        if (self.execution.alias_globals and self.aliasEntryContext()) {
            if (self.execution.stats) |stats| stats.attempts += 1;
            var plan = try self.aliasPlan(binding);
            defer plan.deinit(self.allocator);
            if (plan.items.len != 0) {
                if (self.execution.stats) |stats| stats.admitted += 1;
                return self.inferAliasPlan(plan.items);
            }
            if (self.execution.stats) |stats| stats.declined += 1;
        }
        var frame = try self.beginGlobal(binding);
        defer frame.context.restore(self);
        const declaration = self.tree.valueDecl(frame.id);
        const value = try self.taggedExpression(self.tree.list(declaration.attributes), declaration.body, 0);
        try self.finishGlobal(&frame, value);
    }
    const AliasStep = struct { binding: BindingId, body: ast.Id, target: BindingId = 0, next: usize = 0 };
    fn aliasEntryContext(self: *const Engine) bool {
        // Never reset syntax depth while an ordinary expression remains live.
        return self.current == 0 and self.depth == 0 and self.active.items.len == 0 and self.pending.items.len == 0 and
            self.env.items.len == 0 and self.type_env.items.len == 0 and self.row_env.items.len == 0 and
            self.computation_annotations.items.len == 0 and self.loop_stack.items.len == 0 and
            std.meta.eql(self.request_scope, RequestScope{}) and std.meta.eql(self.resolver_scope, ResolverScope{}) and
            self.return_target == 0 and self.owner == 0 and self.qualification_scope == 0 and
            !self.suspended_loop_escape and self.annotation_binding == 0 and self.inherited_types == 0 and
            self.inherited_rows == 0 and self.local_qualification_scope == 0 and
            self.local_requirements_start == 0 and self.diagnostics.items.len == 0;
    }
    fn aliasPlan(self: *const Engine, initial: BindingId) T.Error!std.ArrayList(AliasStep) {
        var result: std.ArrayList(AliasStep) = .empty;
        errdefer result.deinit(self.allocator);
        var visited: std.AutoHashMapUnmanaged(BindingId, usize) = .empty;
        defer visited.deinit(self.allocator);
        var binding = initial;
        while (true) {
            if (visited.get(binding)) |index| {
                result.items[result.items.len - 1].next = index;
                return result;
            }
            const info = self.bindings.items[binding];
            if (info.kind != .global or info.external != null or info.declaration == 0 or info.named_function) break;
            if (self.tree.node(info.declaration).tag != .value_decl) break;
            if (std.mem.findScalar(u8, self.pool.get(info.name), '.') != null) break;
            const declaration = self.tree.valueDecl(info.declaration);
            if (declaration.where_node != 0 or declaration.attributes.len != 0 or declaration.body == 0) break;
            if (declaration.annotation != 0) {
                const annotation_node = self.tree.node(declaration.annotation);
                if (annotation_node.tag != .type_name) break;
                const name = self.pool.get(annotation_node.a);
                if (!std.mem.eql(u8, name, "Unit") and !std.mem.eql(u8, name, "Bool") and !std.mem.eql(u8, name, "U32") and !std.mem.eql(u8, name, "F32")) break;
            }
            const node = self.tree.node(declaration.body);
            const target: BindingId = switch (node.tag) {
                .unit, .boolean, .integer, .float => 0,
                .name => blk: {
                    if (std.mem.findScalar(u8, self.pool.get(node.a), '.') != null) break;
                    break :blk self.globals.get(node.a) orelse break;
                },
                else => break,
            };
            try visited.put(self.allocator, binding, result.items.len);
            try result.append(self.allocator, .{ .binding = binding, .body = declaration.body, .target = target, .next = result.items.len + 1 });
            if (target == 0) return result;
            binding = target;
        }
        // Unsupported anywhere in the component declines before beginGlobal.
        result.clearRetainingCapacity();
        return result;
    }
    fn inferAliasPlan(self: *Engine, plan: []const AliasStep) T.Error!void {
        var frames: std.ArrayList(GlobalFrame) = .empty;
        defer {
            while (frames.pop()) |value| {
                var frame = value;
                frame.context.restore(self);
            }
            frames.deinit(self.allocator);
        }
        // Reserve complete ownership before replay. There is no late fallback.
        try frames.ensureTotalCapacity(self.allocator, plan.len);
        frames.appendAssumeCapacity(try self.beginGlobal(plan[0].binding));
        while (frames.items.len != 0) {
            const index = frames.items.len - 1;
            const step = plan[frames.items[index].plan_index];
            if (self.execution.stats) |stats| stats.peak_frames = @max(stats.peak_frames, frames.items.len);
            if (step.target != 0 and frames.items[index].before == null) {
                const before = self.global_states.get(step.target).?;
                frames.items[index].before = before;
                if (before.state == .pending) {
                    var child = try self.beginGlobal(step.target);
                    child.plan_index = step.next;
                    frames.appendAssumeCapacity(child);
                    continue;
                }
            }
            const value = if (step.target == 0) try self.expression(step.body) else blk: {
                // The suspended name has one syntax head. Dependency frames do
                // not live on the native expression stack or increment its depth.
                std.debug.assert(self.depth == 0);
                self.depth += 1;
                defer self.depth -= 1;
                try self.finishPreparedGlobal(step.target, frames.items[index].before.?);
                const result = try self.preparedGlobalReference(step.target, step.body);
                break :blk self.finishExpression(step.body, result);
            };
            try self.finishGlobal(&frames.items[index], value);
            var finished = frames.pop().?;
            finished.context.restore(self);
            if (self.execution.stats) |stats| stats.frames += 1;
        }
    }
    fn prepareGlobal(self: *Engine, binding: BindingId) T.Error!void {
        if (self.bindings.items[binding].kind == .external) return;
        const before = self.global_states.get(binding).?;
        if (before.state == .pending) try self.inferGlobal(binding);
        try self.finishPreparedGlobal(binding, before);
    }
    fn finishPreparedGlobal(self: *Engine, binding: BindingId, before: Global) T.Error!void {
        const after = self.global_states.get(binding).?;
        if (self.current != 0 and after.on_stack) {
            var current = self.global_states.get(self.current).?;
            current.low = @min(current.low, if (before.state == .pending) after.low else after.index);
            try self.global_states.put(self.allocator, self.current, current);
        }
    }
    fn globalReference(self: *Engine, binding: BindingId, id: ast.Id) T.Error!T.Id {
        if (binding == self.current and self.bindings.items[binding].kind == .global) {
            const attributes = self.tree.list(self.tree.valueDecl(self.bindings.items[binding].declaration).attributes);
            if (attributes.len != 0) {
                try self.diagnostic(.recursive_tag, attributes[0]);
                self.resolved[id] = binding;
                return self.types.fresh();
            }
        }
        try self.prepareGlobal(binding);
        return self.preparedGlobalReference(binding, id);
    }
    fn preparedGlobalReference(self: *Engine, binding: BindingId, id: ast.Id) T.Error!T.Id {
        if (self.bindings.items[binding].kind == .global and self.bindings.items[binding].scheme.root == 0) try self.qualification_uses.append(self.allocator, .{ .scope = self.qualification_scope, .owner = self.current, .target = binding, .source = id });
        self.resolved[id] = binding;
        return self.instantiate(binding, id);
    }
    fn intrinsicArity(name: []const u8) ?usize {
        if (@import("simd_intrinsics.zig").lookup(name)) |op| return op.arity;
        if (std.mem.eql(u8, name, "@hole")) return 0;
        if (std.mem.eql(u8, name, "@record.merge")) return 2;
        if (@import("collection_ops.zig").lookup(name)) |op| return op.arity;
        if (std.mem.eql(u8, name, "@state.get") or std.mem.eql(u8, name, "@state.set")) return 1;
        if (std.mem.eql(u8, name, "@effect.of") or std.mem.eql(u8, name, "@effect.descriptor") or std.mem.eql(u8, name, "@effect.count")) return 1;
        if (std.mem.eql(u8, name, "@effect.has") or std.mem.eql(u8, name, "@effect.same")) return 2;
        if (std.mem.eql(u8, name, "@state.run")) return 2;
        if (std.mem.eql(u8, name, "@state.reader") or std.mem.eql(u8, name, "@state.writer")) return 3;
        if (std.mem.eql(u8, name, "@effect.provider")) return 2;
        if (std.mem.eql(u8, name, "@effect.state")) return 3;
        if (std.mem.eql(u8, name, "@effect.run") or std.mem.eql(u8, name, "@effect.reader") or std.mem.eql(u8, name, "@effect.writer")) return 4;
        if (std.mem.eql(u8, name, "@type.same") or std.mem.eql(u8, name, "@type.result")) return 2;
        const binary_primitives = [_][]const u8{ "@u32.add", "@u32.sub", "@u32.mul", "@u32.div", "@u32.rem", "@u32.bit_and", "@u32.bit_or", "@u32.bit_xor", "@u32.shl", "@u32.shr", "@u32.eq", "@u32.lt", "@f32.add", "@f32.sub", "@f32.mul", "@f32.div", "@f32.eq", "@f32.ne", "@f32.lt", "@f32.le", "@f32.gt", "@f32.ge", "@array.get", "@array.fill", "@array.generate", "@product.get" };
        for (binary_primitives) |member| if (std.mem.eql(u8, name, member)) return 2;
        const unary = [_][]const u8{ "@u32.to_f32", "@f32.to_u32", "@f32.neg", "@f32.abs", "@f32.sqrt", "@f32.floor", "@f32.ceil", "@f32.trunc", "@array.length", "@panic", "@force", "@demand", "@do.monad" };
        for (unary) |member| if (std.mem.eql(u8, name, member)) return 1;
        if (std.mem.eql(u8, name, "@array.set") or std.mem.eql(u8, name, "@type.call")) return 3;
        return null;
    }
    fn constrainCollection(self: *Engine, owner: T.Id, element: T.Id, source: ast.Id) T.Error!void {
        const tag = self.types.node(self.types.head(owner, 0)).tag;
        if (tag == .variable) {
            try self.appendPending(.{ .owner = self.current, .value = .{ .kind = .collection, .ty = owner, .result = element, .source = source } });
        } else try self.constrain(owner, try self.types.sequence(if (tag == .list) .list else .array, element), source);
    }
    fn intrinsic(self: *Engine, id: ast.Id, name: symbols.Symbol) T.Error!T.Id {
        const text = self.pool.get(name);
        if (@import("simd_intrinsics.zig").lookup(text)) |op| {
            const element = if (op.floating) T.f32_type else T.u32_type;
            const input = try self.types.product(&.{ element, element, element, element });
            const output = if (op.conversion) blk: {
                const result = if (op.floating) T.u32_type else T.f32_type;
                break :blk try self.types.product(&.{ result, result, result, result });
            } else input;
            return self.types.function(input, if (op.arity == 1) output else try self.types.function(input, output));
        }
        if (std.mem.eql(u8, text, "@hole")) {
            // Nearest visible bindings first; the 33rd entry only signals
            // truncation. Avoid copying or repeatedly searching a large scope.
            var scope: [33]u32 = undefined;
            var count: usize = 0;
            var index = self.env.items.len;
            while (index != 0 and count != scope.len) {
                index -= 1;
                const entry = self.env.items[index];
                var shadowed = false;
                for (scope[0..count]) |binding| if (self.bindings.items[binding].name == entry.name) {
                    shadowed = true;
                    break;
                };
                if (!shadowed) {
                    scope[count] = entry.binding;
                    count += 1;
                }
            }
            try self.holes.append(self.allocator, .{ .node = id, .scope = try self.types.saveList(scope[0..count]), .owner = self.current });
            return self.types.fresh();
        }
        if (std.mem.eql(u8, text, "@requests") or std.mem.eql(u8, text, "@computation")) {
            try self.diagnostic(if (std.mem.eql(u8, text, "@requests")) .requests_scope else .intrinsic_arity, id);
            return self.types.fresh();
        }
        if (intrinsicArity(text) != null and self.permitted_intrinsic != id) {
            try self.diagnostic(.call_arity, id);
            return self.types.fresh();
        }
        if ((std.mem.eql(u8, text, "@force") or std.mem.eql(u8, text, "@demand"))) {
            const element = try self.types.fresh();
            return self.types.function(try self.types.demand(element), element);
        }
        if (std.mem.eql(u8, text, "@record.merge")) {
            const left = try self.types.fresh();
            const right = try self.types.fresh();
            const result = try self.types.fresh();
            try self.appendPending(.{ .owner = self.current, .value = .{ .kind = .record_merge, .ty = left, .other = right, .result = result, .source = id } });
            return self.types.function(left, try self.types.function(right, result));
        }
        if (std.mem.eql(u8, text, "@type.same")) return self.types.function(try self.types.fresh(), try self.types.function(try self.types.fresh(), T.boolean));
        const scalar = if (std.mem.startsWith(u8, text, "@u32.")) T.u32_type else if (std.mem.startsWith(u8, text, "@f32.")) T.f32_type else 0;
        if (scalar != 0) {
            const member = text[5..];
            const binary_members = [_][]const u8{ "add", "sub", "mul", "div" };
            const integer_members = [_][]const u8{ "rem", "bit_and", "bit_or", "bit_xor", "shl", "shr" };
            const comparisons = [_][]const u8{ "eq", "ne", "lt", "le", "gt", "ge" };
            for (binary_members) |candidate| if (std.mem.eql(u8, member, candidate)) return self.types.function(scalar, try self.types.function(scalar, scalar));
            if (scalar == T.u32_type) for (integer_members) |candidate| if (std.mem.eql(u8, member, candidate)) return self.types.function(scalar, try self.types.function(scalar, scalar));
            for (comparisons) |candidate| if (std.mem.eql(u8, member, candidate) and (scalar == T.f32_type or std.mem.eql(u8, member, "eq") or std.mem.eql(u8, member, "lt"))) return self.types.function(scalar, try self.types.function(scalar, T.boolean));
            const unary_members = [_][]const u8{ "neg", "abs", "sqrt", "floor", "ceil", "trunc" };
            if (scalar == T.f32_type) for (unary_members) |candidate| if (std.mem.eql(u8, member, candidate)) return self.types.function(scalar, scalar);
            if (scalar == T.u32_type and std.mem.eql(u8, member, "to_f32")) return self.types.function(T.u32_type, T.f32_type);
            if (scalar == T.f32_type and std.mem.eql(u8, member, "to_u32")) return self.types.function(T.f32_type, T.u32_type);
        }
        if (@import("collection_ops.zig").lookup(text)) |primitive| {
            const element = try self.types.fresh();
            if (primitive.op == .cursor_has or primitive.op == .cursor_value or primitive.op == .cursor_advance) {
                const collection = try self.types.fresh();
                try self.constrainCollection(collection, element, id);
                const cursor = try self.types.sequence(.cursor, collection);
                return self.types.function(cursor, switch (primitive.op) {
                    .cursor_has => T.boolean,
                    .cursor_value => element,
                    else => cursor,
                });
            }
            const sequence = try self.types.sequence(if (primitive.is_list) .list else .array, element);
            return switch (primitive.op) {
                .length => self.types.function(sequence, T.u32_type),
                .get => self.types.function(sequence, try self.types.function(T.u32_type, element)),
                .set => self.types.function(sequence, try self.types.function(T.u32_type, try self.types.function(element, sequence))),
                .fill => self.types.function(T.u32_type, try self.types.function(element, sequence)),
                .generate => self.types.function(T.u32_type, try self.types.function(try self.types.function(T.u32_type, element), sequence)),
                .append, .prepend => self.types.function(sequence, try self.types.function(element, sequence)),
                .identity => self.types.function(sequence, sequence),
                .convert => self.types.function(try self.types.sequence(if (primitive.is_list) .array else .list, element), sequence),
                .cursor => self.types.function(sequence, try self.types.sequence(.cursor, sequence)),
                .concat => self.types.function(sequence, try self.types.function(sequence, sequence)),
                .slice => self.types.function(sequence, try self.types.function(T.u32_type, try self.types.function(T.u32_type, sequence))),
                .cursor_has, .cursor_value, .cursor_advance => unreachable,
            };
        }
        try self.diagnostic(.unsupported, id);
        return self.types.fresh();
    }
    fn expression(self: *Engine, id: ast.Id) T.Error!T.Id {
        if (id == 0) return T.unit;
        if (self.depth == 1024) {
            try self.diagnostic(.nesting_limit, id);
            return T.absent;
        }
        self.depth += 1;
        defer self.depth -= 1;
        const node = self.tree.node(id);
        const value: T.Id = switch (node.tag) {
            .unit => T.unit,
            .boolean => T.boolean,
            .integer => T.u32_type,
            .float => T.f32_type,
            .string => try self.types.fresh(),
            .group => try self.expression(node.a),
            .name => blk: {
                if (self.lookup(node.a)) |binding| {
                    self.resolved[id] = binding;
                    break :blk try self.instantiate(binding, id);
                }
                if (try self.globalBinding(node.a)) |binding| break :blk try self.globalReference(binding, id);
                if (try self.qualifiedValue(id, node.a)) |ty| break :blk ty;
                if (try self.operationTemplate(node.a)) |template| break :blk try self.operationValue(id, template, null);
                if (try self.typeConstructorValue(self.catalogKey(node.a))) |ty| break :blk ty;
                try self.diagnostic(.unknown_name, id);
                break :blk try self.types.fresh();
            },
            .selector => try self.selectorFunction(id),
            .field_access => blk: {
                var parent = node.a;
                while (self.tree.node(parent).tag == .group) parent = self.tree.node(parent).a;
                const base = self.tree.node(parent);
                if (base.tag == .name and self.lookup(base.a) == null) {
                    if (self.qualified.get(.{ .namespace = base.a, .member = node.b })) |binding|
                        break :blk try self.globalReference(binding, id);
                    if (try self.typeConstructorValue(.{ .namespace = base.a, .member = node.b })) |ty| break :blk ty;
                }
                const projected = try self.projectField(try self.expression(node.a), node.b, id, false, null);
                self.projection_resolved[id] = projected.projection;
                break :blk projected.ty;
            },
            .constructor_ref => blk: {
                const ctor = self.constructor_names.get(self.catalogKey(node.a)) orelse {
                    try self.diagnostic(.unknown_constructor, id);
                    break :blk try self.types.fresh();
                };
                self.constructor_resolved[id] = ctor;
                break :blk try self.types.openCovariant(try self.constructorType(ctor));
            },
            .type_witness => blk: {
                const value = try self.expression(node.a);
                const name = self.pool.lookup("Type") orelse {
                    try self.diagnostic(.unknown_constructor, id);
                    break :blk try self.types.fresh();
                };
                const ctor = self.constructor_names.get(self.catalogKey(name)) orelse {
                    try self.diagnostic(.unknown_constructor, id);
                    break :blk try self.types.fresh();
                };
                self.constructor_resolved[id] = ctor;
                const result = try self.types.fresh();
                try self.constrain(try self.constructorType(ctor), try self.types.function(value, result), id);
                break :blk result;
            },
            .record => try self.recordValue(id),
            .index_access => blk: {
                const owner = try self.expression(node.a);
                const index = try self.expression(node.b);
                const element = try self.types.fresh();
                try self.constrain(owner, try self.types.sequence(.array, element), id);
                try self.constrain(index, T.u32_type, node.b);
                break :blk element;
            },
            .array => blk: {
                const element = try self.types.fresh();
                var diverges = false;
                for (self.tree.children(id)) |child| {
                    const value = try self.expression(child);
                    try self.constrain(element, value, child);
                    diverges = diverges or try self.types.resolve(value, 0) == T.never;
                }
                break :blk if (diverges) T.never else try self.types.sequence(if (node.c == 1) .list else .array, element);
            },
            .intrinsic => try self.types.openCovariant(try self.intrinsic(id, node.a)),
            .lambda => blk: {
                const parameter = self.tree.parameter(node.a);
                if (parameter.where_node != 0) try self.diagnostic(.higher_rank_constraint, parameter.where_node);
                const element_ty = if (parameter.is_unit) T.unit else try self.types.fresh();
                if (parameter.annotation != 0) try self.constrain(element_ty, try self.annotation(parameter.annotation), node.a);
                const required = if (node.c != 0) try self.annotation(node.c) else 0;
                const parameter_ty = if (parameter.demanded) try self.types.demandWithEffects(element_ty, try self.types.freshEffects()) else element_ty;
                const saved_ambient = self.ambient;
                self.ambient = try self.types.freshEffects();
                const latent = self.ambient;
                try self.row_sources.put(self.allocator, self.types.row(latent).tail.variable, id);
                defer self.ambient = saved_ambient;
                const scope = self.env.items.len;
                const saved_owner = self.owner;
                const saved_target = self.return_target;
                const saved_loops = self.loop_stack;
                const saved_escape = self.suspended_loop_escape;
                const saved_resolver = self.resolver_scope;
                const saved_requests = self.request_scope;
                self.request_scope = .{};
                defer self.request_scope = saved_requests;
                self.resolver_scope = .{};
                defer self.resolver_scope = saved_resolver;
                self.loop_stack = .empty;
                self.suspended_loop_escape = false;
                defer {
                    self.loop_stack.deinit(self.allocator);
                    self.loop_stack = saved_loops;
                    self.suspended_loop_escape = saved_escape;
                }
                self.owner = id;
                self.return_target = 0;
                defer {
                    self.env.shrinkRetainingCapacity(scope);
                    self.owner = saved_owner;
                    self.return_target = saved_target;
                }
                if (parameter.name != 0) {
                    const binding = try self.addBinding(.{ .name = parameter.name, .declaration = node.a, .owner = id, .kind = .parameter, .ty = parameter_ty });
                    self.resolved[node.a] = binding;
                    try self.env.append(self.allocator, .{ .name = parameter.name, .binding = binding });
                }
                self.expr_types[node.a] = parameter_ty;
                var result = try self.expression(node.b);
                if (required != 0) {
                    try self.constrain(result, required, id);
                    result = required;
                } else if (try self.types.resolve(result, 0) == T.never) {
                    // A lambda's result is a fresh inference variable. Bottom
                    // satisfies it without fixing the callable's result type.
                    result = try self.types.fresh();
                }
                const raw_function = try self.types.functionWithEffects(parameter_ty, result, latent);
                try self.certifyLambda(id, raw_function, saved_ambient);
                break :blk raw_function;
            },
            .apply => blk: {
                if (try self.requestCapture(id)) |ty| break :blk ty;
                if (try self.operationApplication(id)) |ty| break :blk ty;
                var leaf = node.a;
                var arity: usize = 1;
                while (self.tree.node(leaf).tag == .apply) {
                    arity += 1;
                    leaf = self.tree.node(leaf).a;
                }
                const saved_intrinsic = self.permitted_intrinsic;
                defer self.permitted_intrinsic = saved_intrinsic;
                if (self.tree.node(leaf).tag == .intrinsic) {
                    if (intrinsicArity(self.pool.get(self.tree.node(leaf).a))) |expected| {
                        if (self.permitted_intrinsic != leaf and arity != expected) {
                            try self.diagnostic(.call_arity, id);
                            break :blk try self.types.fresh();
                        }
                        self.permitted_intrinsic = leaf;
                    }
                }
                if (try self.reflectionApplication(id)) |ty| break :blk ty;
                if (try self.builtinStateApplication(id)) |ty| break :blk ty;
                if (try self.effectRunnerApplication(id)) |ty| break :blk ty;
                if (try self.providerApplication(id)) |ty| break :blk ty;
                const head = self.tree.node(node.a);
                if (head.tag == .intrinsic and std.mem.eql(u8, self.pool.get(head.a), "@do.monad")) {
                    const token = try self.expression(node.b);
                    const result = try self.types.resolver(token);
                    const op = try self.addResolverOp(.{ .node = id, .kind = .monad, .payload = token, .result = result, .method_type = try self.types.function(token, result) }, true);
                    try self.appendPending(.{ .owner = self.current, .metadata = op, .value = .{ .kind = .monad_factory, .ty = token, .result = result, .source = id } });
                    break :blk result;
                }
                if (head.tag == .intrinsic and (std.mem.eql(u8, self.pool.get(head.a), "@force") or std.mem.eql(u8, self.pool.get(head.a), "@demand"))) {
                    const suspended = try self.expression(node.b);
                    const result = try self.types.fresh();
                    try self.constrain(suspended, try self.types.demandWithEffects(result, self.ambient), id);
                    break :blk result;
                }
                if (head.tag == .intrinsic and std.mem.eql(u8, self.pool.get(head.a), "@panic")) {
                    var argument = node.b;
                    while (self.tree.node(argument).tag == .group) argument = self.tree.node(argument).a;
                    if (self.tree.node(argument).tag != .string) try self.diagnostic(.call_arity, argument);
                    break :blk T.never;
                }
                if (try self.productProjection(id)) |ty| break :blk ty;
                if (try self.associatedApplication(id)) |ty| break :blk ty;
                if (try self.resultApplication(id)) |ty| break :blk ty;
                const function_ty = try self.types.openCovariant(try self.types.resolve(try self.expression(node.a), 0));
                const function = self.types.node(try self.types.resolve(function_ty, 0));
                const lazy = function.tag == .function and self.types.node(self.types.head(function.a, 0)).tag == .demand;
                const argument = try self.checkArgument(node.b, lazy);
                const parameter = argument;
                self.demand_calls[id] = lazy;
                if (lazy) self.demand_types[id] = function.a;
                const result = try self.types.fresh();
                try self.constrain(function_ty, try self.invocation(parameter, result), id);
                break :blk try self.applicationFlow(id, function_ty, argument, result);
            },
            .product => blk: {
                var fields: std.ArrayList(T.Id) = .empty;
                defer fields.deinit(self.allocator);
                var diverges = false;
                for (self.tree.children(id)) |child| {
                    const value = try self.expression(child);
                    try fields.append(self.allocator, value);
                    diverges = diverges or try self.types.resolve(value, 0) == T.never;
                }
                break :blk if (diverges) T.never else try self.types.product(fields.items);
            },
            .unary => blk: {
                const operand = try self.expression(node.b);
                const operator = self.pool.get(node.a);
                if (std.mem.eql(u8, operator, "-")) {
                    try self.constrain(operand, T.f32_type, id);
                    break :blk T.f32_type;
                }
                try self.diagnostic(.invalid_operator, id);
                break :blk try self.types.fresh();
            },
            .binary => try self.binary(id),
            .case_expr => try self.caseExpression(id),
            .request_case => blk: {
                try self.diagnostic(.request_case_scope, id);
                break :blk try self.types.fresh();
            },
            .if_expr => blk: {
                const condition = try self.expression(node.a);
                try self.constrain(condition, T.boolean, node.a);
                const left = try self.expression(node.b);
                const right = try self.expression(node.c);
                try self.constrain(left, right, id);
                break :blk if (left == T.never) right else left;
            },
            .block => blk: {
                const resolver_type = if (node.c == 0) 0 else try self.expression(node.c);
                if (resolver_type != 0) {
                    const resolver = self.types.node(try self.types.resolve(resolver_type, 0));
                    if (resolver.tag == .provider or resolver.tag == .state_provider) break :blk try self.providerBlock(id, resolver_type);
                }
                const scope = self.env.items.len;
                const old_target = self.return_target;
                const old_owner = self.owner;
                const old_resolver = self.resolver_scope;
                const result = try self.types.fresh();
                self.resolver_scope = .{};
                var block_index: u32 = 0;
                if (resolver_type != 0) {
                    const tag = self.types.node(try self.types.resolve(resolver_type, 0)).tag;
                    if (tag != .variable and tag != .resolver) try self.diagnostic(.invalid_provider, node.c);
                    const binding = try self.addBinding(.{ .name = 0, .declaration = id, .owner = id, .kind = .local, .ty = resolver_type, .scheme = .{ .root = resolver_type } });
                    self.resolver_scope = .{ .block = id, .resolver = binding, .owner_type = resolver_type, .result = result };
                    if (self.resolver_blocks.items.len >= std.math.maxInt(u32)) return error.TypeLimit;
                    try self.resolver_blocks.append(self.allocator, .{ .node = id, .resolver = binding, .result = result });
                    block_index = @intCast(self.resolver_blocks.items.len);
                    self.resolver_block_ids[id] = block_index;
                    try self.resolverShape(id, result);
                }
                self.return_target = result;
                self.owner = id;
                defer {
                    self.env.shrinkRetainingCapacity(scope);
                    self.return_target = old_target;
                    self.owner = old_owner;
                    self.resolver_scope = old_resolver;
                }
                const flow = try self.suite(id);
                if (!flow.exits) {
                    if (block_index == 0) try self.constrain(result, T.unit, id) else {
                        const op = try self.resolverMethod(id, .pure, T.unit, self.resolver_scope.result, 0, false);
                        self.resolver_blocks.items[block_index - 1].fallthrough = op;
                    }
                }
                break :blk if (flow.exits and flow.breaks and !flow.returns) T.never else result;
            },
            else => blk: {
                try self.diagnostic(.unsupported, id);
                break :blk try self.types.fresh();
            },
        };
        return self.finishExpression(id, value);
    }
    fn finishExpression(self: *Engine, id: ast.Id, value: T.Id) T.Id {
        self.expr_types[id] = value;
        return value;
    }
    fn taggedExpression(self: *Engine, attributes: []const ast.Id, body: ast.Id, depth: usize) T.Error!T.Id {
        if (depth >= 1024) return error.TypeLimit;
        if (attributes.len == 0) return self.expression(body);
        const attribute = attributes[0];
        const function_ty = try self.expression(self.tree.node(attribute).a);
        const argument = try self.taggedExpression(attributes[1..], body, depth + 1);
        const result = try self.types.fresh();
        try self.constrain(function_ty, try self.invocation(argument, result), attribute);
        self.expr_types[attribute] = result;
        return result;
    }
    fn applicationFlow(self: *Engine, id: ast.Id, callee: T.Id, argument: T.Id, result: T.Id) T.Error!T.Id {
        var head = id;
        var count: usize = 0;
        var diverges = false;
        while (self.tree.node(head).tag == .apply) {
            const node = self.tree.node(head);
            diverges = diverges or try self.types.resolve(self.expr_types[node.b], 0) == T.never;
            count += 1;
            head = node.a;
        }
        if (self.tree.node(head).tag == .intrinsic) {
            // Source primitives lower as one operation. Keep each formal
            // parameter available until every operand has been checked.
            if (intrinsicArity(self.pool.get(self.tree.node(head).a))) |arity| {
                if (count < arity) return result;
                if (count == arity) return if (diverges) T.never else result;
            }
        }
        const function = self.types.node(try self.types.resolve(callee, 0));
        const never_result = function.tag == .function and try self.types.resolve(function.b, 0) == T.never;
        return if (function.tag == .never or never_result or try self.types.resolve(argument, 0) == T.never) T.never else result;
    }
    fn checkArgument(self: *Engine, id: ast.Id, lazy: bool) T.Error!T.Id {
        if (!lazy) return self.expression(id);
        const saved_ambient = self.ambient;
        self.ambient = try self.types.freshEffects();
        defer self.ambient = saved_ambient;
        const saved_loops = self.loop_stack;
        const saved_escape = self.suspended_loop_escape;
        self.loop_stack = .empty;
        self.suspended_loop_escape = saved_escape or saved_loops.items.len != 0;
        defer {
            self.loop_stack.deinit(self.allocator);
            self.loop_stack = saved_loops;
            self.suspended_loop_escape = saved_escape;
        }
        return self.types.demandWithEffects(try self.expression(id), self.ambient);
    }
    fn demandCallee(self: *Engine, ty: T.Id) T.Error!bool {
        const node = self.types.node(try self.types.resolve(ty, 0));
        return node.tag == .function and self.types.node(self.types.head(node.a, 0)).tag == .demand;
    }
    fn binary(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        const operator = self.pool.get(node.a);
        const declared = self.overrides.get(node.a);
        // A named operator is an ordinary qualified name between backticks.
        // It has source precedence 80 without a declaration. Its fixity sets
        // precedence/association; the value still resolves at every use.
        const named = if (declared) |override| override.named else operator.len != 0 and
            (std.ascii.isAlphabetic(operator[0]) or operator[0] == '_');
        if (declared != null or named) {
            const target = if (declared) |override| override.target else node.a;
            var function_ty: ?T.Id = null;
            if (named) {
                if (self.lookup(target)) |binding| {
                    self.resolved[id] = binding;
                    function_ty = try self.instantiate(binding, id);
                } else if (try self.globalBinding(target)) |binding|
                    function_ty = try self.globalReference(binding, id);
            } else if (declared.?.external) |external| {
                if (self.external_targets.get(external)) |binding| function_ty = try self.globalReference(binding, id);
            } else if (try self.catalogBinding(target)) |binding|
                function_ty = try self.globalReference(binding, id);
            if (function_ty) |ty| {
                self.dispatch_signatures[id] = ty;
                const lazy_left = try self.demandCallee(ty);
                if (lazy_left) self.demand_binary_left_types[id] = self.types.node(try self.types.resolve(ty, 0)).a;
                const left = try self.checkArgument(node.b, lazy_left);
                const after_left = try self.types.fresh();
                try self.constrain(ty, try self.invocation(left, after_left), id);
                const lazy_right = try self.demandCallee(after_left);
                if (lazy_right) self.demand_types[id] = self.types.node(try self.types.resolve(after_left, 0)).a;
                const right = try self.checkArgument(node.c, lazy_right);
                const result = try self.types.fresh();
                try self.constrain(after_left, try self.invocation(right, result), id);
                self.demand_binary_left[id] = lazy_left;
                self.demand_calls[id] = lazy_right;
                return result;
            }
            _ = try self.expression(node.b);
            _ = try self.expression(node.c);
            try self.diagnostic(.unknown_name, id);
            return self.types.fresh();
        }
        const point = source_operators.origin(self.tree, id);
        try self.diagnostics.append(self.allocator, .{ .code = .unknown_operator, .node = id, .span = .{ .start = point, .end = point }, .symbol = node.a });
        return self.types.fresh();
    }
    fn environmentRows(self: *Engine) T.Error![]u32 {
        var free: std.ArrayList(u32) = .empty;
        errdefer free.deinit(self.allocator);
        for (self.env.items) |entry| {
            const binding = self.bindings.items[entry.binding];
            const variables = try self.types.freeRowVariables(if (binding.scheme.root != 0) binding.scheme.root else binding.ty);
            defer self.allocator.free(variables);
            for (variables) |variable| if (!inList(self.types.list(binding.scheme.row_variables), variable) and !inList(free.items, variable)) try free.append(self.allocator, variable);
        }
        for (self.active.items) |binding| {
            const variables = try self.types.freeRowVariables(self.bindings.items[binding].ty);
            defer self.allocator.free(variables);
            for (variables) |variable| if (!inList(free.items, variable)) try free.append(self.allocator, variable);
        }
        return free.toOwnedSlice(self.allocator);
    }
    fn environmentFree(self: *Engine) T.Error![]T.Id {
        var free: std.ArrayList(T.Id) = .empty;
        errdefer free.deinit(self.allocator);
        for (self.env.items) |entry| {
            const binding = self.bindings.items[entry.binding];
            const root = if (binding.scheme.root != 0) binding.scheme.root else binding.ty;
            const variables = try self.types.freeVariables(root);
            defer self.allocator.free(variables);
            for (variables) |variable| if (!inList(self.types.list(binding.scheme.variables), variable) and !inList(free.items, variable)) try free.append(self.allocator, variable);
        }
        // Active recursive globals are monomorphic in a local let boundary.
        for (self.active.items) |id| {
            const variables = try self.types.freeVariables(self.bindings.items[id].ty);
            defer self.allocator.free(variables);
            for (variables) |variable| if (!inList(free.items, variable)) try free.append(self.allocator, variable);
        }
        return free.toOwnedSlice(self.allocator);
    }
    fn local(self: *Engine, name: symbols.Symbol, value: T.Id, declaration: ast.Id) T.Error!BindingId {
        try self.solveFields();
        const resolved = try self.types.resolve(value, 0);
        const tag = self.types.node(resolved).tag;
        var qualified = false;
        for (self.qualifications.items) |boundary| if (boundary.scope == self.local_qualification_scope) {
            qualified = true;
            break;
        };
        if (!qualified and (tag == .unit or tag == .boolean or tag == .u32 or tag == .f32 or tag == .never)) {
            // Ground scalars cannot capture any inference variable. Walking
            // every earlier lexical binding here makes N scalar lets quadratic.
            const binding = try self.addBinding(.{ .name = name, .declaration = declaration, .owner = self.owner, .kind = .local, .ty = resolved, .scheme = .{ .root = resolved } });
            try self.env.append(self.allocator, .{ .name = name, .binding = binding });
            return binding;
        }
        const excluded = try self.environmentFree();
        defer self.allocator.free(excluded);
        const principal = try self.scheme(value, excluded, &.{self.current}, false, self.current, self.local_qualification_scope);
        const binding = try self.addBinding(.{ .name = name, .declaration = declaration, .owner = self.owner, .kind = .local, .ty = value, .scheme = principal });
        try self.env.append(self.allocator, .{ .name = name, .binding = binding });
        return binding;
    }
    fn templateValue(self: *const Engine, id: ast.Id) bool {
        const node = self.tree.node(id);
        return switch (node.tag) {
            .lambda, .constructor_ref => true,
            .group => self.templateValue(node.a),
            .name, .field_access => blk: {
                const binding = self.resolved[id];
                if (binding == 0) break :blk self.operation_refs[id] != 0;
                const kind = self.bindings.items[binding].kind;
                break :blk kind == .global or kind == .external;
            },
            else => self.operation_refs[id] != 0,
        };
    }
    fn blockComputedRequirements(self: *Engine, start: usize, qualified: bool) T.Error!void {
        var explicit = false;
        for (self.pending.items[start..]) |pending| if (pending.owner == self.current and pending.scope == self.qualification_scope and !pending.solved and !pending.covered and pending.value.explicit) {
            explicit = true;
            break;
        };
        if (!explicit) return;
        for (self.pending.items[start..]) |pending| {
            if (pending.owner != self.current or pending.scope != self.qualification_scope or pending.solved or pending.covered or !sourceRequirement(pending.value.kind) or (qualified and !pending.declared)) continue;
            for ([_]T.Id{ pending.value.ty, pending.value.other, pending.value.result, pending.value.signature }) |part| {
                if (part == 0) continue;
                const values = try self.types.freeVariables(part);
                defer self.allocator.free(values);
                for (values) |variable| if (!inList(self.computed_variables.items, variable)) try self.computed_variables.append(self.allocator, variable);
                const rows = try self.types.freeRowVariables(part);
                defer self.allocator.free(rows);
                for (rows) |row| if (!inList(self.computed_rows.items, row)) try self.computed_rows.append(self.allocator, row);
            }
        }
    }
    fn addResolverOp(self: *Engine, value: ResolverOp, explicit: bool) T.Error!u32 {
        if (self.resolver_ops.items.len >= std.math.maxInt(u32)) return error.TypeLimit;
        try self.resolver_ops.append(self.allocator, value);
        const index: u32 = @intCast(self.resolver_ops.items.len);
        if (explicit) self.resolver_op_ids[value.node] = index;
        return index;
    }
    fn resolverShape(self: *Engine, source: ast.Id, result: T.Id) T.Error!void {
        try self.appendPending(.{ .owner = self.current, .value = .{ .kind = .resolver_shape, .ty = self.resolver_scope.owner_type, .result = result, .source = source } });
    }
    fn progressConstructor(self: *Engine, name: []const u8, source: ast.Id) T.Error!?u32 {
        if (self.prelude_unit != 0) for (self.constructors.items[1..], 1..) |constructor, index| {
            if (constructor.identity.unit == self.prelude_unit and std.mem.eql(u8, self.pool.get(constructor.name), name)) return @intCast(index);
        };
        // Compiler-generated progress uses the actual prelude identity. A
        // same-spelled user constructor cannot provide this protocol.
        try self.diagnostic(.unknown_constructor, source);
        return null;
    }
    fn progressValue(self: *Engine, constructor: u32, payload: T.Id, source: ast.Id) T.Error!T.Id {
        const result = try self.types.fresh();
        try self.constrain(try self.constructorType(constructor), try self.types.function(payload, result), source);
        return result;
    }
    fn completedTypes(self: *Engine, source: ast.Id, payload: T.Id, depth: u32, constructor: u32) T.Error!T.List {
        var types_: std.ArrayList(T.Id) = .empty;
        defer types_.deinit(self.allocator);
        var current = payload;
        for (0..depth) |_| {
            current = try self.progressValue(constructor, current, source);
            try types_.append(self.allocator, current);
        }
        return self.types.saveList(types_.items);
    }
    fn resolverBind(self: *Engine, source: ast.Id, candidate: T.Id, payload: T.Id, suffix: T.Id, result: T.Id, parameter: BindingId, explicit: bool) T.Error!u32 {
        const continuation = try self.invocation(payload, suffix);
        const function = try self.invocation(candidate, try self.invocation(continuation, result));
        try self.resolverShape(source, result);
        const member = self.pool.lookup("bind") orelse 0;
        const op = try self.addResolverOp(.{ .node = source, .kind = .bind, .member = member, .resolver = self.resolver_scope.resolver, .payload = payload, .result = result, .method_type = function, .continuation_parameter = parameter }, explicit);
        try self.appendPending(.{ .owner = self.current, .metadata = op, .value = .{ .kind = .resolver_dispatch, .ty = self.resolver_scope.owner_type, .other = function, .result = result, .name = member, .source = source } });
        return op;
    }
    fn resolverComplete(self: *Engine, source: ast.Id, value: T.Id, result: T.Id, depth: u32, constructor: u32) T.Error!u32 {
        const payload = try self.types.fresh();
        const parameter = try self.addBinding(.{ .name = 0, .declaration = source, .owner = self.owner, .kind = .local, .ty = payload, .scheme = .{ .root = payload } });
        const completed = try self.completedTypes(source, payload, depth, constructor);
        const input = self.types.list(completed)[completed.len - 1];
        const pure_result = try self.types.fresh();
        const pure = try self.resolverMethod(source, .pure, input, pure_result, 0, false);
        const bind = try self.resolverBind(source, value, payload, pure_result, result, parameter, false);
        if (self.resolver_completions.items.len >= std.math.maxInt(u32)) return error.TypeLimit;
        try self.resolver_completions.append(self.allocator, .{ .node = source, .bind = bind, .pure = pure, .completed_types = completed, .done_constructor = constructor });
        return @intCast(self.resolver_completions.items.len);
    }
    fn resolverMethod(self: *Engine, source: ast.Id, kind: ResolverKind, input: T.Id, result: T.Id, parameter: BindingId, explicit: bool) T.Error!u32 {
        const member = self.pool.lookup(switch (kind) {
            .pure => "pure",
            .bind => "bind",
            .iterate => "iterate",
            else => unreachable,
        }) orelse 0;
        const function = try self.invocation(input, result);
        try self.resolverShape(source, result);
        const op = try self.addResolverOp(.{ .node = source, .kind = kind, .member = member, .resolver = self.resolver_scope.resolver, .payload = input, .result = result, .method_type = function, .continuation_parameter = parameter }, explicit);
        try self.appendPending(.{ .owner = self.current, .metadata = op, .value = .{ .kind = .resolver_dispatch, .ty = self.resolver_scope.owner_type, .other = function, .result = result, .source = source, .name = member } });
        return op;
    }
    fn definitelyPanic(self: *const Engine, id: ast.Id, depth: usize) bool {
        if (id == 0 or depth >= 1024) return false;
        const node = self.tree.node(id);
        return switch (node.tag) {
            .group => self.definitelyPanic(node.a, depth + 1),
            .apply => self.tree.node(node.a).tag == .intrinsic and std.mem.eql(u8, self.pool.get(self.tree.node(node.a).a), "@panic"),
            .if_expr => self.definitelyPanic(node.a, depth + 1) or (self.definitelyPanic(node.b, depth + 1) and self.definitelyPanic(node.c, depth + 1)),
            .case_expr => blk: {
                const inputs = self.tree.extra.items[node.a..][0..2];
                for (self.tree.list(.{ .start = inputs[0], .len = inputs[1] })) |input| if (self.definitelyPanic(input, depth + 1)) break :blk true;
                for (self.tree.list(.{ .start = node.b, .len = node.c })) |arm| {
                    const metadata = self.tree.extra.items[self.tree.node(arm).c..][0..2];
                    if (!self.definitelyPanic(metadata[1], depth + 1)) break :blk false;
                }
                break :blk true;
            },
            else => false,
        };
    }
    fn statement(self: *Engine, id: ast.Id) T.Error!Flow {
        const node = self.tree.node(id);
        switch (node.tag) {
            .let_stmt => {
                const value_ = self.tree.binding(id);
                const computation_annotation_scope = self.computation_annotations.items.len;
                const type_scope = self.type_env.items.len;
                defer self.type_env.shrinkRetainingCapacity(type_scope);
                const row_scope = self.row_env.items.len;
                defer self.row_env.shrinkRetainingCapacity(row_scope);
                const saved_annotation_binding = self.annotation_binding;
                const saved_inherited_types = self.inherited_types;
                const saved_inherited_rows = self.inherited_rows;
                const saved_qualification_scope = self.qualification_scope;
                defer self.qualification_scope = saved_qualification_scope;
                if (value_.where_node != 0) self.qualification_scope = id;
                self.annotation_binding = id;
                self.inherited_types = type_scope;
                self.inherited_rows = row_scope;
                defer {
                    self.annotation_binding = saved_annotation_binding;
                    self.inherited_types = saved_inherited_types;
                    self.inherited_rows = saved_inherited_rows;
                }
                try self.collectAnnotationNames(value_.annotation, 0);
                try self.collectAnnotationNames(value_.where_node, 0);
                try self.collectAnnotationNames(value_.value, 0);
                try self.collectAnnotationNames(value_.fallback, 0);
                const required = if (value_.annotation != 0) try self.annotation(value_.annotation) else 0;
                const qualification_index = self.qualifications.items.len;
                const requirement_start = self.pending.items.len;
                try self.beginQualification(id, value_.where_node, value_.annotation, value_.value);
                const value = try self.pureExpression(value_.value);
                if (required != 0) try self.constrain(value, required, id);
                if (value_.where_node != 0) try self.checkQualification(qualification_index);
                // Frozen inference restores explicit RHS annotation names
                // before generalization. Plain lets retain generated facts.
                if (value_.annotation != 0 or value_.where_node != 0)
                    self.computation_annotations.shrinkRetainingCapacity(computation_annotation_scope);
                const computed_values = self.computed_variables.items.len;
                const computed_effects = self.computed_rows.items.len;
                defer self.computed_variables.shrinkRetainingCapacity(computed_values);
                defer self.computed_rows.shrinkRetainingCapacity(computed_effects);
                if (!self.templateValue(value_.value)) try self.blockComputedRequirements(requirement_start, value_.where_node != 0);
                const exits = self.types.node(try self.types.resolve(value, 0)).tag == .never;
                const scope = self.env.items.len;
                const saved_local_qualification = self.local_qualification_scope;
                const saved_local_requirements = self.local_requirements_start;
                self.local_qualification_scope = if (value_.where_node != 0) id else 0;
                self.local_requirements_start = requirement_start;
                defer {
                    self.local_qualification_scope = saved_local_qualification;
                    self.local_requirements_start = saved_local_requirements;
                }
                // Guard typing checks the value pattern before the failure
                // branch, whose lexical scope excludes successful binders.
                const generalize = value_.fallback == 0 and self.tree.node(value_.pattern).tag == .pattern_name;
                const saved_pattern_source = self.let_pattern_source;
                self.let_pattern_source = id;
                const total = self.pattern(value_.pattern, value, scope, &.{}, generalize) catch |err| {
                    self.let_pattern_source = saved_pattern_source;
                    return err;
                };
                self.let_pattern_source = saved_pattern_source;
                if (value_.fallback != 0) {
                    const success_environment = try self.allocator.dupe(Entry, self.env.items);
                    defer self.allocator.free(success_environment);
                    self.env.shrinkRetainingCapacity(scope);
                    const saved_result = self.resolver_scope.result;
                    const flow = try self.suite(value_.fallback);
                    self.resolver_scope.result = saved_result;
                    if (!flow.exits) {
                        try self.diagnostic(.guard_fallthrough, id);
                        self.diagnostics.items[self.diagnostics.items.len - 1].span.end = self.diagnostics.items[self.diagnostics.items.len - 1].span.start;
                    }
                    self.env.clearRetainingCapacity();
                    try self.env.appendSlice(self.allocator, success_environment);
                }
                if (!total and value_.fallback == 0) {
                    try self.diagnostic(.non_exhaustive_match, id);
                    self.diagnostics.items[self.diagnostics.items.len - 1].span.end = self.diagnostics.items[self.diagnostics.items.len - 1].span.start;
                }
                self.resolved[id] = self.resolved[value_.pattern];
                self.expr_types[id] = if (exits) T.never else T.unit;
                return .{ .exits = exits, .breaks = exits };
            },
            .rebind_stmt => {
                if (self.tree.node(node.a).tag != .name) return self.rebindFields(id);
                const name = self.tree.node(node.a).a;
                const previous = self.lookup(name) orelse {
                    try self.diagnostic(.unknown_rebinding, id);
                    return .{};
                };
                const scope = self.env.items.len;
                try self.env.append(self.allocator, .{ .name = self.self_name, .binding = previous });
                const value = try self.pureExpression(node.b);
                self.env.shrinkRetainingCapacity(scope);
                const binding = try self.local(name, value, id);
                self.bindings.items[binding].predecessor = previous;
                self.resolved[id] = binding;
                self.resolved[node.a] = previous;
                self.expr_types[node.a] = self.bindings.items[previous].ty;
                const exits = try self.types.resolve(value, 0) == T.never;
                self.expr_types[id] = if (exits) T.never else T.unit;
                return .{ .exits = exits, .breaks = exits };
            },
            .return_stmt => {
                if (self.request_scope.invalid_outer_return and self.owner == self.request_scope.return_scope) {
                    try self.diagnostic(.invalid_return, id);
                    return .{ .exits = true, .returns = true };
                }
                const value = try self.expression(node.a);
                if (self.request_scope.loop != 0 and self.owner == self.request_scope.return_scope) try self.request_controls.append(self.allocator, .{ .node = id, .loop = self.request_scope.loop, .kind = .cancel, .value_type = value, .target_scope = self.request_scope.return_scope });
                if (self.resolver_scope.block != 0) {
                    if (self.definitelyPanic(node.a, 0)) {
                        // The source rewrite leaves a panicking suffix intact;
                        // neither pure nor progress completion is invoked.
                        _ = try self.addResolverOp(.{ .node = id, .kind = .forward, .resolver = self.resolver_scope.resolver, .payload = value, .result = self.resolver_scope.result }, true);
                        self.expr_types[id] = T.never;
                        return .{ .ty = T.never, .exits = true, .returns = true };
                    }
                    if (node.b != 0) {
                        try self.resolverShape(id, value);
                        var completion: u32 = 0;
                        if (self.resolver_scope.progress_depth != 0) {
                            if (try self.progressConstructor("Done", id)) |constructor| completion = try self.resolverComplete(id, value, self.resolver_scope.result, self.resolver_scope.progress_depth, constructor);
                        } else try self.constrain(self.resolver_scope.result, value, id);
                        _ = try self.addResolverOp(.{ .node = id, .kind = .forward, .resolver = self.resolver_scope.resolver, .payload = value, .result = self.resolver_scope.result, .completion = completion }, true);
                    } else {
                        var completed: T.List = .{};
                        var done_constructor: u32 = 0;
                        var input = value;
                        if (self.resolver_scope.progress_depth != 0) if (try self.progressConstructor("Done", id)) |constructor| {
                            done_constructor = constructor;
                            completed = try self.completedTypes(id, value, self.resolver_scope.progress_depth, constructor);
                            input = self.types.list(completed)[completed.len - 1];
                        };
                        const op = try self.resolverMethod(id, .pure, input, self.resolver_scope.result, 0, true);
                        self.resolver_ops.items[op - 1].completed_types = completed;
                        self.resolver_ops.items[op - 1].done_constructor = done_constructor;
                    }
                } else {
                    if (node.b != 0) try self.diagnostic(.resolver_required, id);
                    if (self.return_target == 0) try self.diagnostic(.return_outside_block, id) else try self.constrain(self.return_target, value, id);
                }
                self.expr_types[id] = T.never;
                return .{ .ty = T.never, .exits = true, .returns = true };
            },
            .use_stmt, .iterator_bind => {
                const value = try self.expression(node.b);
                if (node.tag == .use_stmt and self.resolver_scope.block != 0) {
                    const payload = try self.types.fresh();
                    if (node.c != 0) try self.constrain(payload, try self.annotation(node.c), id);
                    const binding = try self.addBinding(.{ .name = node.a, .declaration = id, .owner = self.owner, .kind = .local, .ty = payload, .scheme = .{ .root = payload } });
                    if (node.a != 0) try self.env.append(self.allocator, .{ .name = node.a, .binding = binding });
                    self.resolved[id] = binding;
                    const suffix = try self.types.fresh();
                    _ = try self.resolverBind(id, value, payload, suffix, self.resolver_scope.result, binding, true);
                    self.resolver_scope.result = suffix;
                    self.expr_types[id] = T.unit;
                    return .{};
                }
                if (node.c != 0) try self.constrain(value, try self.annotation(node.c), id);
                if (node.a != 0) {
                    const binding = try self.addBinding(.{ .name = node.a, .declaration = id, .owner = self.owner, .kind = .local, .ty = value, .scheme = .{ .root = value } });
                    try self.env.append(self.allocator, .{ .name = node.a, .binding = binding });
                    self.resolved[id] = binding;
                }
                self.expr_types[id] = T.unit;
                return .{};
            },
            .forever_stmt, .range_stmt, .for_stmt => return self.loopStatement(id),
            .break_stmt => return self.breakStatement(id),
            .yield_stmt => return self.requestReply(id),
            .if_stmt, .if_let_stmt => return self.conditional(id),
            else => {
                const ty = try self.expression(id);
                const exits = self.types.node(try self.types.resolve(ty, 0)).tag == .never;
                return .{ .exits = exits, .breaks = exits };
            },
        }
    }
    fn suite(self: *Engine, id: ast.Id) T.Error!Flow {
        var result: Flow = .{};
        var direct_exit = false;
        for (self.tree.children(id)) |child| {
            if (direct_exit) try self.diagnostic(.unreachable_statement, child);
            const flow = try self.statement(child);
            // Type every suffix, but only reachable exits contribute to the
            // enclosing block's return/break target evidence.
            if (!result.exits) {
                result.returns = result.returns or flow.returns;
                result.breaks = result.breaks or flow.breaks;
            }
            result.exits = result.exits or flow.exits;
            const tag = self.tree.node(child).tag;
            direct_exit = direct_exit or tag == .return_stmt or tag == .break_stmt or tag == .yield_stmt;
        }
        self.expr_types[id] = if (result.exits) T.never else T.unit;
        return result;
    }
    fn flowsFrom(self: *const Engine, initial: BindingId, original: BindingId) bool {
        var binding = initial;
        var steps: usize = 0;
        while (binding != 0 and steps < self.bindings.items.len) : (steps += 1) {
            if (binding == original) return true;
            binding = self.bindings.items[binding].predecessor;
        }
        return false;
    }
    fn latestSuccessor(self: *const Engine, original: BindingId) BindingId {
        const name = self.bindings.items[original].name;
        var index = self.env.items.len;
        while (index != 0) {
            index -= 1;
            const entry = self.env.items[index];
            if (entry.name == name and self.flowsFrom(entry.binding, original)) return entry.binding;
        }
        return original;
    }
    fn requestCapture(self: *Engine, id: ast.Id) T.Error!?T.Id {
        var head = id;
        var argument: ast.Id = 0;
        var count: usize = 0;
        while (true) {
            const node = self.tree.node(head);
            if (node.tag == .group) {
                head = node.a;
                continue;
            }
            if (node.tag != .apply) break;
            argument = node.b;
            count += 1;
            head = node.a;
        }
        const intrinsic_ = self.tree.node(head);
        if (intrinsic_.tag != .intrinsic) return null;
        const name = self.pool.get(intrinsic_.a);
        if (std.mem.eql(u8, name, "@requests")) {
            try self.diagnostic(.requests_scope, head);
            return try self.types.fresh();
        }
        if (!std.mem.eql(u8, name, "@computation")) return null;
        if (count != 1) {
            try self.diagnostic(.intrinsic_arity, head);
            return try self.types.fresh();
        }
        const value = try self.expression(argument);
        const action = try self.types.functionWithEffects(T.unit, try self.types.fresh(), try self.types.freshEffects());
        try self.constrain(value, action, id);
        try self.computation_annotations.append(self.allocator, action);
        const result = try self.types.nominal(.{ .unit = std.math.maxInt(u32), .decl = 5 }, &.{action});
        try self.computations.append(self.allocator, .{ .node = id, .action = argument, .ty = result, .action_type = action });
        return result;
    }
    const RequestInput = struct { argument: ast.Id = 0, count: usize = 0 };
    fn requestInput(self: *const Engine, id: ast.Id) ?RequestInput {
        var head = id;
        var input: RequestInput = .{};
        var steps: usize = 0;
        while (steps < 1024) : (steps += 1) {
            const node = self.tree.node(head);
            if (node.tag == .group) {
                head = node.a;
                continue;
            }
            if (node.tag == .apply) {
                input.argument = node.b;
                input.count += 1;
                head = node.a;
                continue;
            }
            if (node.tag == .intrinsic and std.mem.eql(u8, self.pool.get(node.a), "@requests")) return input;
            return null;
        }
        return null;
    }
    fn requestReply(self: *Engine, id: ast.Id) T.Error!Flow {
        const scope = self.request_scope;
        if (scope.loop == 0 or scope.completion) {
            try self.diagnostic(.yield_scope, id);
            return .{ .exits = true, .breaks = true };
        }
        const value = try self.expression(self.tree.node(id).a);
        try self.constrain(value, scope.reply, scope.loop);
        var frame: ?LoopFrame = null;
        for (self.loop_stack.items) |candidate| if (candidate.node == scope.loop) {
            frame = candidate;
            break;
        };
        var snapshot: std.ArrayList(BindingId) = .empty;
        defer snapshot.deinit(self.allocator);
        if (frame) |request| for (request.carries, self.types.list(scope.state_bindings)) |carry, iteration| {
            const current = self.lookup(carry.name) orelse iteration;
            try self.constrain(self.bindings.items[iteration].ty, self.bindings.items[current].ty, scope.loop);
            try snapshot.append(self.allocator, current);
        };
        try self.request_controls.append(self.allocator, .{ .node = id, .loop = scope.loop, .kind = .reply, .value_type = value, .bindings = try self.types.saveList(snapshot.items), .target_scope = self.request_arms.items[scope.arm - 1].node });
        self.expr_types[id] = T.never;
        return .{ .exits = true, .breaks = true };
    }
    const RequestSyntax = struct { arms: []const ast.Id, completion: ast.Id };
    fn requestSyntaxHeader(self: *Engine, id: ast.Id) Allocator.Error!?RequestSyntax {
        const node = self.tree.node(id);
        const metadata = self.tree.extra.items[node.c..][0..3];
        const body = metadata[1];
        if (metadata[0] != 0) {
            try self.diagnostic(.request_loop_range, id);
            return null;
        }
        const statements = self.tree.children(body);
        if (statements.len != 1) {
            try self.diagnostic(.request_loop_body, body);
            return null;
        }
        const dispatch_id = statements[0];
        const request_case = self.tree.node(dispatch_id);
        if (request_case.tag != .request_case) {
            try self.diagnostic(.request_loop_body, dispatch_id);
            return null;
        }
        const inputs = self.tree.extra.items[request_case.a..][0..2];
        const subjects = self.tree.list(.{ .start = inputs[0], .len = inputs[1] });
        if (self.tree.node(node.a).tag != .pattern_name or subjects.len != 1 or self.tree.node(subjects[0]).tag != .name or self.tree.node(subjects[0]).a != self.tree.node(node.a).a) {
            try self.diagnostic(.request_binding, dispatch_id);
            return null;
        }
        const arms = self.tree.list(.{ .start = request_case.b, .len = request_case.c });
        var completion: ast.Id = 0;
        for (arms) |arm_id| if (self.tree.node(arm_id).a == 0) {
            if (completion != 0) {
                try self.diagnostic(.request_completion, arm_id);
                return null;
            }
            completion = arm_id;
        };
        if (completion == 0) {
            try self.diagnostic(.request_completion, id);
            self.diagnostics.items[self.diagnostics.items.len - 1].span = .{ .start = 0, .end = 0 };
            return null;
        }
        return .{ .arms = arms, .completion = completion };
    }
    pub fn sourceRequestHeader(self: *Engine, id: ast.Id) Allocator.Error!void {
        if (!self.source_validation or self.source_annotation_failed) return;
        const before = self.diagnostics.items.len;
        _ = try self.requestSyntaxHeader(id);
        self.source_annotation_failed = self.diagnostics.items.len != before;
    }
    fn requestLoop(self: *Engine, id: ast.Id) T.Error!?Flow {
        const node = self.tree.node(id);
        const input = self.requestInput(node.b) orelse return null;
        const diagnostic_mark = self.diagnostics.items.len;
        const saved_target = self.return_target;
        const saved_resolver = self.resolver_scope;
        const monadic = saved_resolver.block != 0;
        const protocol_result = if (monadic) try self.types.fresh() else saved_target;
        defer {
            self.return_target = saved_target;
            self.resolver_scope = saved_resolver;
        }
        const metadata = self.tree.extra.items[node.c..][0..3];
        const body = metadata[1];
        if (metadata[0] != 0) {
            try self.diagnostic(.request_loop_range, id);
            return .{};
        }
        if (input.count != 1) {
            try self.diagnostic(.intrinsic_arity, id);
            return .{};
        }
        if (self.return_target == 0) {
            try self.diagnostic(.request_loop_scope, id);
            return .{};
        }
        const header = (try self.requestSyntaxHeader(id)) orelse return .{};
        const arms = header.arms;
        const completion = header.completion;
        var labels: std.ArrayList(T.Effects.Label) = .empty;
        defer labels.deinit(self.allocator);
        var signatures: std.ArrayList(T.Id) = .empty;
        defer signatures.deinit(self.allocator);
        for (arms) |arm_id| {
            const arm = self.tree.node(arm_id);
            if (arm.a == 0) continue;
            const diagnostic_start = self.diagnostics.items.len;
            const target = (try self.operationTarget(arm.a)) orelse {
                for (self.diagnostics.items[diagnostic_start..]) |*diagnostic_| if (diagnostic_.code == .unknown_name or diagnostic_.code == .sealed_effect) {
                    diagnostic_.code = .unknown_value;
                };
                return .{};
            };
            if (inList(labels.items, target.label)) {
                try self.diagnostic(.duplicate_request_handler, arm.a);
                const operation = self.types.operation(target.label);
                if (operation.identity.unit == self.unit) {
                    self.diagnostics.items[self.diagnostics.items.len - 1].span = self.tree.span(operation.identity.decl);
                    if (self.tree.node(operation.identity.decl).tag == .effect_type_decl) self.diagnostics.items[self.diagnostics.items.len - 1].span.start += 5 else if (self.tree.node(operation.identity.decl).tag == .effect_decl) self.diagnostics.items[self.diagnostics.items.len - 1].span.start += 7 else self.diagnostics.items[self.diagnostics.items.len - 1].span = .{ .start = 0, .end = 0 };
                }
                return .{};
            }
            try labels.append(self.allocator, target.label);
            try signatures.append(self.allocator, target.signature);
        }
        const handled = try self.types.saveList(labels.items);
        const captured = try self.expression(input.argument);
        const value = try self.types.fresh();
        const outer_row = try self.types.resolveEffects(self.ambient, 0);
        try labels.appendSlice(self.allocator, self.types.rowLabels(outer_row));
        const action_row = self.types.effects.row(labels.items, self.types.row(outer_row).tail) catch |err| return T.effectError(err);
        const action = try self.types.functionWithEffects(T.unit, value, action_row);
        const computation = try self.types.nominal(.{ .unit = std.math.maxInt(u32), .decl = 5 }, &.{action});
        try self.constrain(captured, computation, id);
        const targets = loop_targets.collect(self.allocator, self.tree, self.pool, node.a, body) catch |err| return switch (err) {
            error.TargetLimit => error.TypeLimit,
            error.OutOfMemory => error.OutOfMemory,
        };
        defer self.allocator.free(targets);
        var carries: std.ArrayList(Entry) = .empty;
        defer carries.deinit(self.allocator);
        for (targets) |name| if (self.lookup(name)) |binding| try carries.append(self.allocator, .{ .name = name, .binding = binding });
        const base = try self.allocator.dupe(Entry, self.env.items);
        defer self.allocator.free(base);
        const iterations = try self.allocator.alloc(BindingId, carries.items.len);
        defer self.allocator.free(iterations);
        for (carries.items, iterations) |incoming, *iteration| {
            const ty = self.bindings.items[incoming.binding].ty;
            iteration.* = try self.addBinding(.{ .name = incoming.name, .declaration = id, .owner = self.owner, .kind = .local, .ty = ty, .scheme = .{ .root = ty }, .predecessor = incoming.binding });
        }
        const stack_mark = self.loop_stack.items.len;
        try self.loop_stack.append(self.allocator, .{ .node = id, .carries = carries.items, .iterations = iterations });
        defer self.loop_stack.shrinkRetainingCapacity(stack_mark);
        const saved_requests = self.request_scope;
        defer self.request_scope = saved_requests;
        var state_types: std.ArrayList(T.Id) = .empty;
        defer state_types.deinit(self.allocator);
        for (iterations) |iteration| try state_types.append(self.allocator, self.bindings.items[iteration].ty);
        const state_type = if (state_types.items.len == 0) T.unit else if (state_types.items.len == 1) state_types.items[0] else try self.types.product(state_types.items);
        var published_arms: std.ArrayList(u32) = .empty;
        defer published_arms.deinit(self.allocator);
        var complete_state_bindings: T.List = .{};
        var signature_index: usize = 0;
        var returns = false;
        for (arms) |arm_id| {
            self.env.clearRetainingCapacity();
            try self.env.appendSlice(self.allocator, base);
            var arm_state: std.ArrayList(BindingId) = .empty;
            defer arm_state.deinit(self.allocator);
            for (carries.items, iterations) |carry, iteration| {
                const ty = self.bindings.items[iteration].ty;
                const arm_binding = try self.addBinding(.{ .name = carry.name, .declaration = arm_id, .owner = arm_id, .kind = .parameter, .ty = ty, .scheme = .{ .root = ty }, .predecessor = carry.binding });
                try arm_state.append(self.allocator, arm_binding);
                try self.env.append(self.allocator, .{ .name = carry.name, .binding = arm_binding });
            }
            const state_bindings = try self.types.saveList(arm_state.items);
            const arm = self.tree.node(arm_id);
            const complete = arm_id == completion;
            const function = if (complete) T.Node{ .tag = .absent } else self.types.node(try self.types.resolve(signatures.items[signature_index], 0));
            if (!complete) signature_index += 1;
            var arm_index: u32 = 0;
            if (complete) complete_state_bindings = state_bindings else {
                const decision = try self.types.nominal(.{ .unit = std.math.maxInt(u32), .decl = 6 }, &.{ function.b, state_type, protocol_result });
                const signature = try self.types.functionWithEffects(try self.types.product(&.{ function.a, state_type }), decision, self.ambient);
                arm_index = @intCast(self.request_arms.items.len + 1);
                try self.request_arms.append(self.allocator, .{ .node = arm_id, .loop = id, .operation = self.types.list(handled)[signature_index - 1], .parameter_type = function.a, .reply_type = function.b, .signature = signature, .pattern = arm.b, .suite = arm.c, .state_bindings = state_bindings });
                try published_arms.append(self.allocator, arm_index - 1);
            }
            self.return_target = protocol_result;
            self.resolver_scope = .{};
            self.request_scope = .{ .loop = id, .reply = if (complete) 0 else function.b, .target = protocol_result, .completion = complete, .return_scope = self.owner, .arm = arm_index, .state_bindings = state_bindings, .invalid_outer_return = monadic and complete };
            const pattern_diagnostics = self.diagnostics.items.len;
            if (!try self.pattern(arm.b, if (complete) value else function.a, self.env.items.len, &.{}, false)) try self.diagnostic(.non_exhaustive_match, id);
            const pattern_origin = tagOrigin(self.tag_origins, self.tree.span(id));
            const pattern_source = if (pattern_origin == 0) id else pattern_origin;
            for (self.diagnostics.items[pattern_diagnostics..]) |*diagnostic_| {
                diagnostic_.span = self.tree.span(pattern_source);
                diagnostic_.node = pattern_source;
            }
            const flow = try self.suite(arm.c);
            returns = returns or flow.returns;
            if (!flow.exits) try self.diagnostic(if (complete) .request_completion_fallthrough else .request_clause_fallthrough, id);
        }
        if (monadic and self.diagnostics.items.len == diagnostic_mark) try self.diagnostic(.invalid_return, id);
        const breaks = self.loop_stack.items[stack_mark].exits;
        self.env.clearRetainingCapacity();
        try self.env.appendSlice(self.allocator, base);
        const start = self.loop_carries.items.len;
        for (carries.items, iterations) |incoming, iteration| {
            const ty = self.bindings.items[incoming.binding].ty;
            const outgoing = try self.addBinding(.{ .name = incoming.name, .declaration = id, .owner = self.owner, .kind = .local, .ty = ty, .scheme = .{ .root = ty }, .predecessor = incoming.binding });
            try self.env.append(self.allocator, .{ .name = incoming.name, .binding = outgoing });
            try self.loop_carries.append(self.allocator, .{ .node = id, .incoming = incoming.binding, .iteration = iteration, .backedge = iteration, .outgoing = outgoing });
        }
        self.loop_ranges[id] = .{ .start = @intCast(start), .len = @intCast(carries.items.len) };
        try self.request_loops.append(self.allocator, .{ .node = id, .computation = input.argument, .value_type = value, .result_type = self.return_target, .state_type = state_type, .action_type = action, .arms = try self.types.saveList(published_arms.items), .completion = completion, .complete_pattern = self.tree.node(completion).b, .complete_suite = self.tree.node(completion).c, .complete_state_bindings = complete_state_bindings, .carried = self.loop_ranges[id], .return_scope = self.owner });
        self.expr_types[id] = T.unit;
        return .{ .exits = breaks == 0, .returns = returns };
    }
    fn iteratorStatement(self: *Engine, id: ast.Id) T.Error!Flow {
        const expansion = self.tree.extra.items[self.tree.node(id).c + 3];
        const base = try self.allocator.dupe(Entry, self.env.items);
        defer self.allocator.free(base);
        self.iterator_bodies[id] = expansion;
        const flow = try self.suite(expansion);
        // Publish outer rebindings, but keep generated cursor locals scoped to
        // this one for statement. The nested loop already owns its carries.
        for (base) |*entry| entry.binding = self.latestSuccessor(entry.binding);
        self.env.clearRetainingCapacity();
        try self.env.appendSlice(self.allocator, base);
        self.expr_types[id] = if (flow.exits) T.never else T.unit;
        return flow;
    }
    fn loopStatement(self: *Engine, id: ast.Id) T.Error!Flow {
        if (self.depth >= 1024) return error.TypeLimit;
        self.depth += 1;
        defer self.depth -= 1;
        const node = self.tree.node(id);
        if (node.tag == .for_stmt) if (try self.requestLoop(id)) |flow| return flow;
        var pattern_id: ast.Id = 0;
        var body: ast.Id = node.a;
        var element: T.Id = T.u32_type;
        var first_type: T.Id = T.u32_type;
        if (node.tag == .range_stmt) {
            try self.constrain(try self.expression(node.a), T.u32_type, node.a);
            try self.constrain(try self.expression(node.b), T.u32_type, node.b);
            body = node.c;
        } else if (node.tag == .for_stmt) {
            const parts = self.tree.extra.items[node.c..][0..3];
            pattern_id = node.a;
            body = parts[1];
            const value = try self.expression(node.b);
            first_type = value;
            if (parts[0] != 0) {
                try self.constrain(value, T.u32_type, node.b);
                try self.constrain(try self.expression(parts[0]), T.u32_type, parts[0]);
            } else {
                const source_tag = self.types.node(try self.types.resolve(value, 0)).tag;
                if (source_tag != .array and source_tag != .list)
                    return self.iteratorStatement(id);
                element = try self.types.fresh();
                try self.constrainCollection(value, element, node.b);
            }
        }
        const targets = loop_targets.collect(self.allocator, self.tree, self.pool, pattern_id, body) catch |err| return switch (err) {
            error.TargetLimit => error.TypeLimit,
            error.OutOfMemory => error.OutOfMemory,
        };
        defer self.allocator.free(targets);
        var carries: std.ArrayList(Entry) = .empty;
        defer carries.deinit(self.allocator);
        for (targets) |name| if (self.lookup(name)) |binding| {
            try carries.append(self.allocator, .{ .name = name, .binding = binding });
        };
        // The source resolver protocol exposes the state tuple to ordinary
        // iterate implementations. Canonical loop targets are prepended.
        if (self.resolver_scope.block != 0) std.mem.reverse(Entry, carries.items);
        const base = try self.allocator.dupe(Entry, self.env.items);
        defer self.allocator.free(base);
        // Body bindings are private. Only typed carry successors are published.
        var published = false;
        defer if (!published) {
            self.env.clearRetainingCapacity();
            self.env.appendSliceAssumeCapacity(base);
        };
        const iterations = try self.allocator.alloc(BindingId, carries.items.len);
        defer self.allocator.free(iterations);
        for (carries.items, iterations) |incoming, *iteration| {
            const ty = self.bindings.items[incoming.binding].ty;
            iteration.* = try self.addBinding(.{ .name = incoming.name, .declaration = id, .owner = self.owner, .kind = .local, .ty = ty, .scheme = .{ .root = ty }, .predecessor = incoming.binding });
            try self.env.append(self.allocator, .{ .name = incoming.name, .binding = iteration.* });
        }
        const stack_mark = self.loop_stack.items.len;
        try self.loop_stack.append(self.allocator, .{ .node = id, .carries = carries.items, .iterations = iterations, .resolver_block = self.resolver_scope.block });
        defer self.loop_stack.shrinkRetainingCapacity(stack_mark);
        var resolver_loop: ?ResolverLoop = null;
        const resolver_outer = self.resolver_scope;
        var resolver_restored = false;
        defer {
            if (!resolver_restored) self.resolver_scope = resolver_outer;
        }
        if (self.resolver_scope.block != 0) {
            const continue_constructor = try self.progressConstructor("Continue", id);
            const done_constructor = try self.progressConstructor("Done", id);
            if (continue_constructor != null and done_constructor != null) {
                if (self.constructors.items[continue_constructor.?].nominal != self.constructors.items[done_constructor.?].nominal) return error.TypeLimit;
                var carry_types: std.ArrayList(T.Id) = .empty;
                defer carry_types.deinit(self.allocator);
                for (iterations) |iteration| try carry_types.append(self.allocator, self.bindings.items[iteration].ty);
                const state_type = if (carry_types.items.len == 0) T.unit else try self.types.product(carry_types.items);
                const cursor = try self.types.product(&.{ T.u32_type, state_type });
                const cursor_parameter = try self.addBinding(.{ .name = 0, .declaration = id, .owner = self.owner, .kind = .local, .ty = cursor, .scheme = .{ .root = cursor } });
                const first_binding = try self.addBinding(.{ .name = 0, .declaration = id, .owner = self.owner, .kind = .local, .ty = first_type, .scheme = .{ .root = first_type } });
                const end_binding = try self.addBinding(.{ .name = 0, .declaration = id, .owner = self.owner, .kind = .local, .ty = T.u32_type, .scheme = .{ .root = T.u32_type } });
                const step_result = try self.types.fresh();
                const suffix_result = try self.types.fresh();
                const step = try self.invocation(cursor, step_result);
                const method = try self.invocation(cursor, try self.invocation(step, resolver_outer.result));
                try self.resolverShape(id, resolver_outer.result);
                const member = self.pool.lookup("iterate") orelse 0;
                const iterate = try self.addResolverOp(.{ .node = id, .kind = .iterate, .member = member, .resolver = self.resolver_scope.resolver, .method_type = method, .payload = cursor, .result = resolver_outer.result, .continuation_parameter = cursor_parameter }, true);
                try self.appendPending(.{ .owner = self.current, .metadata = iterate, .value = .{ .kind = .resolver_dispatch, .ty = self.resolver_scope.owner_type, .other = method, .result = resolver_outer.result, .name = member, .source = id } });
                const completion = try self.resolverComplete(id, suffix_result, step_result, 1, done_constructor.?);
                resolver_loop = .{ .node = id, .cursor_parameter = cursor_parameter, .first_binding = first_binding, .end_binding = end_binding, .cursor = cursor, .step_result = step_result, .suffix_result = suffix_result, .iterate = iterate, .continued = 0, .finish = completion, .continue_constructor = continue_constructor.?, .done_constructor = done_constructor.? };
                self.resolver_scope.result = step_result;
                if (self.resolver_scope.progress_depth == std.math.maxInt(u32)) return error.TypeLimit;
                self.resolver_scope.progress_depth += 1;
            }
        }
        if (pattern_id != 0 and !try self.pattern(pattern_id, element, self.env.items.len, &.{}, false)) try self.diagnostic(.non_exhaustive_match, pattern_id);
        const flow = try self.suite(body);
        if (resolver_loop) |*monad_loop| {
            const continued = try self.progressValue(monad_loop.continue_constructor, monad_loop.cursor, id);
            monad_loop.continued = try self.resolverMethod(id, .pure, continued, self.resolver_scope.result, 0, false);
            self.resolver_scope = resolver_outer;
            self.resolver_scope.result = monad_loop.suffix_result;
            if (self.resolver_loops.items.len >= std.math.maxInt(u32)) return error.TypeLimit;
            try self.resolver_loops.append(self.allocator, monad_loop.*);
            self.resolver_loop_ids[id] = @intCast(self.resolver_loops.items.len);
        } else self.resolver_scope = resolver_outer;
        resolver_restored = true;
        const breaks = self.loop_stack.items[stack_mark].exits;
        const backedges = try self.allocator.alloc(BindingId, carries.items.len);
        defer self.allocator.free(backedges);
        for (iterations, backedges) |iteration, *backedge| {
            backedge.* = self.latestSuccessor(iteration);
            try self.constrain(self.bindings.items[iteration].ty, self.bindings.items[backedge.*].ty, id);
        }
        self.env.clearRetainingCapacity();
        self.env.appendSliceAssumeCapacity(base);
        const start = self.loop_carries.items.len;
        for (carries.items, iterations, backedges) |incoming, iteration, backedge| {
            const ty = self.bindings.items[incoming.binding].ty;
            const outgoing = try self.addBinding(.{ .name = incoming.name, .declaration = id, .owner = self.owner, .kind = .local, .ty = ty, .scheme = .{ .root = ty }, .predecessor = incoming.binding });
            try self.env.append(self.allocator, .{ .name = incoming.name, .binding = outgoing });
            try self.loop_carries.append(self.allocator, .{ .node = id, .incoming = incoming.binding, .iteration = iteration, .backedge = backedge, .outgoing = outgoing });
        }
        if (start > std.math.maxInt(u32) or carries.items.len > std.math.maxInt(u32)) return error.TypeLimit;
        self.loop_ranges[id] = .{ .start = @intCast(start), .len = @intCast(carries.items.len) };
        self.expr_types[id] = T.unit;
        published = true;
        return .{ .exits = node.tag == .forever_stmt and breaks == 0, .returns = flow.returns };
    }
    fn breakStatement(self: *Engine, id: ast.Id) T.Error!Flow {
        self.expr_types[id] = T.never;
        if (self.loop_stack.items.len == 0) {
            try self.diagnostic(if (self.suspended_loop_escape) .invalid_return else .break_scope, id);
            return .{ .exits = true, .breaks = true };
        }
        const frame_index = self.loop_stack.items.len - 1;
        const frame = self.loop_stack.items[frame_index];
        if (frame.resolver_block != 0 and self.resolver_scope.block == 0) {
            // An ordinary do cannot complete the enclosing resolver's loop
            // progress protocol. Its own return boundary must remain intact.
            try self.diagnostic(.invalid_return, id);
            return .{ .exits = true, .breaks = true };
        }
        const current = try self.allocator.alloc(BindingId, frame.carries.len);
        defer self.allocator.free(current);
        for (frame.carries, frame.iterations, current) |carry, iteration, *binding| {
            // A break captures the currently visible lexical binding, including
            // a same-name let. Normal backedges instead follow predecessor flow.
            binding.* = self.lookup(carry.name) orelse iteration;
            try self.constrain(self.bindings.items[iteration].ty, self.bindings.items[binding.*].ty, if (self.request_scope.loop == frame.node) frame.node else id);
        }
        const nested_resolver = self.resolver_scope.block != 0 and self.resolver_scope.block != frame.resolver_block;
        // Canonical loop_targets prepends source targets. Ordinary loop
        // metadata follows our forward catalog; the exposed nested-resolver
        // snapshot uses the canonical reverse source-write order.
        if (nested_resolver and frame.resolver_block == 0) std.mem.reverse(BindingId, current);
        const bindings = try self.types.saveList(current);
        if (self.request_scope.loop == frame.node) try self.request_controls.append(self.allocator, .{ .node = id, .loop = frame.node, .kind = .break_, .value_type = T.unit, .bindings = bindings, .target_scope = frame.node });
        try self.loop_exits.append(self.allocator, .{ .node = id, .loop = frame.node, .bindings = bindings });
        if (nested_resolver) {
            // A nested resolver completes with the lexical loop state. The
            // enclosing loop still advances normally after that value returns.
            var payload: std.ArrayList(T.Id) = .empty;
            defer payload.deinit(self.allocator);
            for (current) |binding| try payload.append(self.allocator, self.bindings.items[binding].ty);
            const state = if (payload.items.len == 0) T.unit else try self.types.product(payload.items);
            _ = try self.resolverMethod(id, .pure, state, self.resolver_scope.result, 0, true);
            return .{ .exits = true, .returns = true };
        }
        self.loop_stack.items[frame_index].exits += 1;
        return .{ .exits = true, .breaks = true };
    }
    fn updatedFieldType(self: *Engine, original: T.Id, name: symbols.Symbol, assigned: T.Id, source: ast.Id) T.Error!?T.Id {
        const owner = try self.types.resolve(original, 0);
        const node = self.types.node(owner);
        if (node.tag == .variable) return null;
        if (node.tag == .record) {
            var fields: std.ArrayList(T.Field) = .empty;
            defer fields.deinit(self.allocator);
            var found = false;
            for (0..node.b) |index| {
                var field = self.types.recordField(node, index);
                if (field.name == name) {
                    field.ty = assigned;
                    found = true;
                }
                try fields.append(self.allocator, field);
            }
            if (found) return try self.types.record(fields.items);
        } else if (node.tag == .nominal) {
            const nominal = self.nominalIndex(.{ .unit = node.a, .decl = node.b }) orelse {
                try self.diagnostic(.missing_field, source);
                return try self.types.fresh();
            };
            const constructors = try self.allocator.dupe(T.Id, self.types.list(self.nominals.items[nominal].constructors));
            defer self.allocator.free(constructors);
            var result: T.Id = 0;
            for (constructors) |constructor| {
                const input = self.types.node(try self.constructorStorageType(constructor));
                const output = self.types.node(try self.constructorStorageType(constructor));
                if (input.tag != .function or output.tag != .function) break;
                try self.constrain(input.b, owner, source);
                const input_payload = self.types.node(try self.types.resolve(input.a, 0));
                const output_payload = self.types.node(try self.types.resolve(output.a, 0));
                if (input_payload.tag != .record or output_payload.tag != .record or input_payload.b != output_payload.b) break;
                var found = false;
                for (0..input_payload.b) |index| {
                    const before = self.types.recordField(input_payload, index);
                    const after = self.types.recordField(output_payload, index);
                    if (before.name != after.name) return error.TypeLimit;
                    if (before.name == name) {
                        try self.constrain(after.ty, assigned, source);
                        found = true;
                    } else try self.constrain(before.ty, after.ty, source);
                }
                if (!found) break;
                if (result == 0) result = output.b else try self.constrain(result, output.b, source);
            } else {
                if (result != 0) return result;
            }
        }
        try self.diagnostic(.missing_field, source);
        return try self.types.fresh();
    }
    fn rebindFields(self: *Engine, id: ast.Id) T.Error!Flow {
        const saved_ambient = self.ambient;
        self.ambient = try self.types.freshEffects();
        defer self.ambient = saved_ambient;
        const statement_ = self.tree.node(id);
        var reverse: std.ArrayList(ast.Id) = .empty;
        defer reverse.deinit(self.allocator);
        var root = statement_.a;
        while (self.tree.node(root).tag == .field_access or self.tree.node(root).tag == .index_access) {
            if (reverse.items.len >= 1024) return error.TypeLimit;
            try reverse.append(self.allocator, root);
            root = self.tree.node(root).a;
        }
        const root_node = self.tree.node(root);
        if (root_node.tag != .name) {
            try self.diagnostic(.unsupported, id);
            return .{};
        }
        const previous = self.lookup(root_node.a) orelse {
            try self.diagnostic(.unknown_rebinding, id);
            return .{};
        };
        std.mem.reverse(ast.Id, reverse.items);
        var ty = self.bindings.items[previous].ty;
        var path: std.ArrayList(T.Id) = .empty;
        defer path.deinit(self.allocator);
        var types_: std.ArrayList(T.Id) = .empty;
        defer types_.deinit(self.allocator);
        try types_.append(self.allocator, ty);
        const scope = self.env.items.len;
        errdefer self.env.shrinkRetainingCapacity(scope);
        // Selector expressions see the original root; the RHS sees the old
        // final leaf. Each selector is checked once in written path order.
        try self.env.append(self.allocator, .{ .name = self.self_name, .binding = previous });
        for (reverse.items) |access| {
            const selector = self.tree.node(access);
            var projection: u32 = 0;
            if (selector.tag == .index_access) {
                const element = try self.types.fresh();
                try self.constrain(ty, try self.types.sequence(.array, element), access);
                try self.constrain(try self.expression(selector.b), T.u32_type, selector.b);
                ty = element;
            } else {
                const pending_start = self.pending.items.len;
                const projected = try self.projectField(ty, selector.b, access, true, null);
                // The updater proves this physical selector. Its old leaf is
                // available to `self`, independently of the replacement type.
                for (self.pending.items[pending_start..]) |*pending| if (pending.value.kind == .writable_field and pending.value.source == access) {
                    pending.covered = true;
                    pending.suspended = true;
                };
                ty = projected.ty;
                projection = projected.projection;
            }
            self.expr_types[access] = ty;
            self.projection_resolved[access] = projection;
            try path.append(self.allocator, projection);
            try types_.append(self.allocator, ty);
        }
        self.env.shrinkRetainingCapacity(scope);
        self.resolved[root] = previous;
        self.expr_types[root] = self.bindings.items[previous].ty;
        const self_binding = try self.addBinding(.{ .name = self.self_name, .declaration = id, .owner = self.owner, .kind = .local, .ty = ty, .scheme = .{ .root = ty } });
        try self.env.append(self.allocator, .{ .name = self.self_name, .binding = self_binding });
        const value = try self.expression(statement_.b);
        self.env.shrinkRetainingCapacity(scope);
        var updated = value;
        var remaining = reverse.items.len;
        while (remaining != 0) {
            remaining -= 1;
            const selector = self.tree.node(reverse.items[remaining]);
            const owner = types_.items[remaining];
            if (selector.tag == .index_access) {
                try self.constrain(types_.items[remaining + 1], updated, id);
                updated = owner;
            } else if (try self.updatedFieldType(owner, selector.b, updated, reverse.items[remaining])) |result| {
                updated = result;
            } else {
                const result = try self.types.fresh();
                try self.appendPending(.{ .owner = self.current, .origin = try self.projectionOrigin(reverse.items[remaining], selector.b, false), .value = .{ .kind = .update, .ty = owner, .other = updated, .result = result, .name = selector.b, .signature = try self.types.functionWithEffects(T.unit, T.unit, 0), .source = reverse.items[remaining] } });
                updated = result;
            }
        }
        const successor = try self.local(root_node.a, updated, id);
        self.bindings.items[successor].predecessor = previous;
        self.resolved[id] = successor;
        self.expr_types[id] = T.unit;
        const range = try self.types.saveList(path.items);
        self.rebindings[id] = .{ .root = previous, .self_binding = self_binding, .path = range };
        self.access_types[id] = try self.types.saveList(types_.items);
        self.access_nodes[id] = try self.types.saveList(reverse.items);
        self.types.unifyEffects(self.ambient, 0) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.EffectMismatch => try self.diagnostic(.let_effect, id),
            error.InfiniteEffect => try self.diagnostic(.infinite_effect, id),
            else => return err,
        };
        return .{};
    }
    fn conditional(self: *Engine, id: ast.Id) T.Error!Flow {
        const node = self.tree.node(id);
        const pattern_conditional = node.tag == .if_let_stmt;
        const subject = if (pattern_conditional) try self.expression(node.b) else try self.expression(node.a);
        if (!pattern_conditional) try self.constrain(subject, T.boolean, node.a);
        const bodies = if (pattern_conditional) self.tree.extra.items[node.c..][0..2] else &[_]u32{ node.b, node.c };
        const base = try self.allocator.dupe(Entry, self.env.items);
        defer self.allocator.free(base);
        const left = try self.allocator.alloc(BindingId, base.len);
        defer self.allocator.free(left);
        const resolver_head = self.resolver_scope.result;
        const monadic = self.resolver_scope.block != 0;
        const resolver_suffix = if (monadic) try self.types.fresh() else 0;
        if (pattern_conditional) _ = try self.pattern(node.a, subject, base.len, &.{}, false);
        const then_flow = try self.suite(bodies[0]);
        if (monadic and !then_flow.exits) try self.constrain(self.resolver_scope.result, resolver_suffix, id);
        for (base, left) |entry, *binding| {
            binding.* = self.latestSuccessor(entry.binding);
        }
        self.env.clearRetainingCapacity();
        try self.env.appendSlice(self.allocator, base);
        if (monadic) self.resolver_scope.result = resolver_head;
        const else_flow: Flow = if (bodies[1] != 0) try self.suite(bodies[1]) else .{};
        if (monadic and !else_flow.exits) try self.constrain(self.resolver_scope.result, resolver_suffix, id);
        const right = try self.allocator.alloc(BindingId, base.len);
        defer self.allocator.free(right);
        for (base, right) |entry, *binding| {
            binding.* = self.latestSuccessor(entry.binding);
        }
        self.env.clearRetainingCapacity();
        try self.env.appendSlice(self.allocator, base);
        var join_types: std.ArrayList(T.Id) = .empty;
        defer join_types.deinit(self.allocator);
        for (base, left, right, 0..) |entry, a, b, i| {
            var shadowed = false;
            for (base[i + 1 ..]) |later| if (later.name == entry.name) {
                shadowed = true;
                break;
            };
            if (shadowed) continue;
            if (a == entry.binding and b == entry.binding) continue;
            if (then_flow.exits and else_flow.exits) continue;
            if (then_flow.exits and !monadic) {
                try self.env.append(self.allocator, .{ .name = entry.name, .binding = b });
                continue;
            }
            if (else_flow.exits and !monadic) {
                try self.env.append(self.allocator, .{ .name = entry.name, .binding = a });
                continue;
            }
            if (!then_flow.exits and !else_flow.exits) try self.constrain(self.bindings.items[a].ty, self.bindings.items[b].ty, id);
            const merged_type = self.bindings.items[if (then_flow.exits) b else a].ty;
            const merged = try self.addBinding(.{ .name = entry.name, .declaration = id, .owner = self.owner, .kind = .local, .ty = merged_type, .predecessor = entry.binding });
            try self.env.append(self.allocator, .{ .name = entry.name, .binding = merged });
            try self.merges.append(self.allocator, .{ .node = id, .result = merged, .then_binding = a, .else_binding = b });
            if (monadic) try join_types.append(self.allocator, merged_type);
        }
        if (monadic) {
            const join_type = if (join_types.items.len == 0) T.unit else try self.types.product(join_types.items);
            const parameter = if (join_types.items.len == 0) 0 else try self.addBinding(.{ .name = 0, .declaration = id, .owner = self.owner, .kind = .local, .ty = join_type, .scheme = .{ .root = join_type } });
            if (self.resolver_joins.items.len >= std.math.maxInt(u32)) return error.TypeLimit;
            try self.resolver_joins.append(self.allocator, .{ .node = id, .parameter = parameter, .ty = join_type, .result = resolver_suffix });
            self.resolver_join_ids[id] = @intCast(self.resolver_joins.items.len);
            self.resolver_scope.result = resolver_suffix;
        }
        self.expr_types[id] = T.unit;
        return .{ .exits = then_flow.exits and else_flow.exits, .returns = then_flow.returns or else_flow.returns, .breaks = then_flow.breaks or else_flow.breaks };
    }
    fn solveFields(self: *Engine) T.Error!void {
        var progress = true;
        while (progress) {
            progress = false;
            var i: usize = 0;
            while (i < self.pending.items.len) : (i += 1) {
                const pending = self.pending.items[i];
                if (pending.solved or pending.suspended) continue;
                const constraint = pending.value;
                if (constraint.kind == .record_merge) {
                    const result = self.types.mergeRecords(constraint.ty, constraint.other) catch |err| switch (err) {
                        error.TypeMismatch => {
                            try self.diagnostic(.type_mismatch, constraint.source);
                            self.pending.items[i].solved = true;
                            progress = true;
                            continue;
                        },
                        else => return err,
                    };
                    if (result) |ty| {
                        try self.constrain(ty, constraint.result, constraint.source);
                        self.pending.items[i].solved = true;
                        progress = true;
                    }
                    continue;
                }
                if (constraint.kind == .collection) {
                    const owner = self.types.node(try self.types.resolve(constraint.ty, 0));
                    if (owner.tag == .variable) continue;
                    if (owner.tag == .array or owner.tag == .list) {
                        try self.constrain(owner.a, constraint.result, constraint.source);
                    } else try self.diagnostic(.type_mismatch, constraint.source);
                    self.pending.items[i].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .monad_factory) {
                    const token = self.types.node(try self.types.resolve(constraint.ty, 0));
                    if (token.tag == .variable) continue;
                    if (token.tag != .type_constructor) try self.diagnostic(.type_constructor_required, constraint.source);
                    self.pending.items[i].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .resolver_dispatch) {
                    self.pending.items[i].suspended = true;
                    const selected = try self.resolverDispatch(pending);
                    self.pending.items[i].suspended = false;
                    if (selected) {
                        self.pending.items[i].solved = true;
                        progress = true;
                    }
                    continue;
                }
                if (constraint.kind == .type_head) {
                    const head = try self.witnessResult(constraint.ty);
                    if (self.types.node(try self.types.resolve(head, 0)).tag == .variable) continue;
                    try self.constrain(head, constraint.result, constraint.source);
                    self.pending.items[i].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .effect_handler) {
                    const extended = self.types.node(try self.types.resolve(constraint.signature, 0));
                    const residual = self.types.node(try self.types.resolve(constraint.other, 0));
                    if (extended.tag != .function or residual.tag != .function) return error.TypeLimit;
                    if (try self.handlerEquation(constraint.ty, extended.c, residual.c, constraint.source)) {
                        self.pending.items[i].solved = true;
                        progress = true;
                    }
                    continue;
                }
                if (constraint.kind == .effect_operation) {
                    const arguments = try self.types.resolve(constraint.other, 0);
                    if (!try self.types.equalClosed(arguments, arguments)) continue;
                    const pack = self.types.node(arguments);
                    if (pack.tag != .product) return error.TypeLimit;
                    const owned_arguments = try self.allocator.dupe(T.Id, self.types.list(.{ .start = pack.a, .len = pack.b }));
                    defer self.allocator.free(owned_arguments);
                    const signature = self.types.node(try self.types.resolve(constraint.signature, 0));
                    if (signature.tag != .function) return error.TypeLimit;
                    const label = try self.types.internOperation(constraint.identity, owned_arguments);
                    // A handler or explicit type context has already supplied
                    // this exact label. Discharge only that established fact;
                    // inferred generic operations never insert their own label.
                    for (self.types.rowLabels(signature.c)) |known| if (known == label) {
                        self.pending.items[i].solved = true;
                        progress = true;
                        break;
                    };
                    continue;
                }
                if (constraint.kind == .resolver_shape) {
                    const owner = self.types.node(try self.types.resolve(constraint.ty, 0));
                    if (owner.tag == .variable) continue;
                    if (owner.tag != .resolver) {
                        try self.diagnostic(.invalid_provider, constraint.source);
                    } else {
                        const token = self.types.node(try self.types.resolve(owner.a, 0));
                        if (token.tag == .variable) continue;
                        if (token.tag != .type_constructor) {
                            try self.diagnostic(.type_constructor_required, constraint.source);
                        } else {
                            const identity: Identity = .{ .unit = token.a, .decl = token.b };
                            const nominal_ = self.nominalIndex(identity) orelse return error.TypeLimit;
                            // A shaped parameter such as Result [value,error]
                            // occupies one applied slot, despite two leaf vars.
                            const arguments = try self.allocator.alloc(T.Id, self.nominals.items[nominal_].parameters.len);
                            defer self.allocator.free(arguments);
                            for (arguments) |*argument| argument.* = try self.types.fresh();
                            try self.constrain(constraint.result, try self.types.nominal(identity, arguments), constraint.source);
                        }
                    }
                    self.pending.items[i].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .update) {
                    if (try self.updatedFieldType(constraint.ty, constraint.name, constraint.other, constraint.source)) |updated| {
                        try self.constrain(constraint.result, updated, constraint.source);
                        self.pending.items[i].solved = true;
                        progress = true;
                    }
                    continue;
                }
                if (constraint.kind != .field and constraint.kind != .writable_field and constraint.kind != .dispatch and constraint.kind != .result_dispatch) continue;
                const saved_ambient = self.ambient;
                if (constraint.signature != 0) self.ambient = self.types.node(try self.types.resolve(constraint.signature, 0)).c;
                defer self.ambient = saved_ambient;
                const owner = try self.types.resolve(if (constraint.kind == .result_dispatch) constraint.result else constraint.ty, 0);
                if (self.types.node(owner).tag == .variable) continue;
                // A candidate can demand another source body, whose scheme
                // construction recursively enters this solver. Hide only this
                // in-flight obligation, keeping all other chronological work.
                self.pending.items[i].suspended = true;
                const selected: ?T.Id = if (constraint.kind == .field or constraint.kind == .writable_field)
                    (try self.projectField(owner, constraint.name, constraint.source, constraint.kind == .writable_field, pending)).ty
                else if (constraint.kind == .result_dispatch)
                    try self.resultDispatch(constraint.ty, owner, constraint.name, constraint.source, pending.direct)
                else
                    try self.dispatch(owner, constraint.other, constraint.name, constraint.operator, constraint.source, pending.direct);
                self.pending.items[i].suspended = false;
                if (selected) |result| {
                    try self.constrain(constraint.result, result, constraint.source);
                    self.pending.items[i].solved = true;
                    progress = true;
                }
            }
        }
    }
    fn finishHoles(self: *Engine) T.Error!void {
        const display = @import("type_display.zig");
        for (self.holes.items) |hole| {
            var bytes: std.ArrayList(u8) = .empty;
            defer bytes.deinit(self.allocator);
            try display.text(self, &bytes, "Unfilled expression; expected: ");
            try display.append(self, &bytes, self.expr_types[hole.node]);
            if (hole.scope.len != 0) try display.text(self, &bytes, "; in scope: ");
            for (0..hole.scope.len) |index| {
                const binding = self.types.list(hole.scope)[index];
                if (index == 32) {
                    try display.text(self, &bytes, ", ...");
                    break;
                }
                if (index != 0) try display.text(self, &bytes, ", ");
                try display.text(self, &bytes, self.pool.get(self.bindings.items[binding].name));
                try display.text(self, &bytes, ": ");
                try display.append(self, &bytes, self.bindings.items[binding].ty);
            }
            try self.diagnostic(.typed_hole, hole.node);
            self.diagnostics.items[self.diagnostics.items.len - 1].detail = try bytes.toOwnedSlice(self.allocator);
            self.diagnostics.items[self.diagnostics.items.len - 1].hole = try @import("hole_diagnostics.zig").build(self, hole.node, hole.scope, hole.owner);
        }
    }
    fn finish(self: *Engine) T.Error!void {
        try self.solveFields();
        // Each latent lambda row has one source owner. Only a decision about
        // that exact raw variable may become an anonymous closure certificate.
        var lambda_rows: std.AutoHashMapUnmanaged(ast.Id, std.ArrayList(u32)) = .empty;
        defer {
            var lists = lambda_rows.valueIterator();
            while (lists.next()) |list| list.deinit(self.allocator);
            lambda_rows.deinit(self.allocator);
        }
        for (self.body_closed_rows.items) |decision| if (self.row_sources.get(decision.variable)) |source| {
            const entry = try lambda_rows.getOrPut(self.allocator, source);
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            if (!inList(entry.value_ptr.items, decision.variable)) try entry.value_ptr.append(self.allocator, decision.variable);
        };
        var lists = lambda_rows.iterator();
        while (lists.next()) |entry| self.lambda_closed_rows[entry.key_ptr.*] = try self.types.saveList(entry.value_ptr.items);
        var quantified: std.ArrayList(T.Id) = .empty;
        defer quantified.deinit(self.allocator);
        for (self.bindings.items[1..]) |binding| try quantified.appendSlice(self.allocator, self.types.list(binding.scheme.variables));
        for (self.pending.items) |pending| {
            if (pending.solved or pending.suspended) continue;
            const resolved = try self.types.resolve(pending.value.ty, 0);
            const tag = self.types.node(resolved).tag;
            if (tag == .variable and inList(quantified.items, resolved)) continue;
            if (pending.value.kind == .monad_factory) {
                try self.diagnostic(.type_constructor_required, pending.value.source);
                continue;
            }
            if (pending.value.kind == .resolver_dispatch) {
                try self.diagnostic(.missing_member, pending.value.source);
                continue;
            }
            if (pending.value.kind == .effect_operation or pending.value.kind == .effect_handler or pending.value.kind == .type_head or pending.value.kind == .record_merge) continue;
            if (pending.value.kind == .resolver_shape) {
                try self.diagnostic(.invalid_provider, pending.value.source);
                continue;
            }
            if (pending.value.kind == .field or pending.value.kind == .writable_field) {
                try self.diagnostic(if (pending.value.kind == .writable_field) .missing_field else .missing_member, pending.value.source);
                continue;
            }
            if (pending.value.kind == .result_dispatch) {
                const destination = try self.types.resolve(pending.value.result, 0);
                try self.diagnostic(if (self.types.node(destination).tag == .variable) .ambiguous_associated else .missing_associated, pending.value.source);
                continue;
            }
            if (pending.value.kind == .dispatch) {
                try self.diagnostic(if (pending.value.name == 0) .ambiguous_operator else .missing_associated, pending.value.source);
                continue;
            }
            if (tag == .u32 or (tag == .f32 and pending.value.kind != .integer) or (tag == .boolean and pending.value.kind == .equality)) continue;
            try self.diagnostic(.ambiguous_operator, pending.value.source);
        }
        if (self.diagnostics.items.len == 0) {
            for (self.tree.nodes.items, 0..) |node, index| {
                // Intrinsic literal arguments are consumed as syntax; only a
                // string visited as an ordinary expression is unsupported.
                if (node.tag == .string and self.expr_types[index] != 0) try self.diagnostic(.unsupported_expression, @intCast(index));
            }
        }
        for (self.expr_types) |*id| if (id.* != 0) {
            id.* = try self.types.resolve(id.*, 0);
        };
        for (self.demand_types) |*id| if (id.* != 0) {
            id.* = try self.types.resolve(id.*, 0);
        };
        for (self.demand_binary_left_types) |*id| if (id.* != 0) {
            id.* = try self.types.resolve(id.*, 0);
        };
        for (self.dispatch_signatures) |*id| if (id.* != 0) {
            id.* = try self.types.resolve(id.*, 0);
        };
        for (self.bindings.items[1..]) |*binding| {
            binding.ty = try self.types.resolve(binding.ty, 0);
            if (binding.scheme.root != 0) binding.scheme.root = try self.types.resolve(binding.scheme.root, 0);
        }
        for (self.resolver_blocks.items) |*block| block.result = try self.types.resolve(block.result, 0);
        for (self.resolver_ops.items) |*op| {
            if (op.method_type != 0) op.method_type = try self.types.resolve(op.method_type, 0);
            if (op.payload != 0) op.payload = try self.types.resolve(op.payload, 0);
            if (op.result != 0) op.result = try self.types.resolve(op.result, 0);
            try self.normalizeList(op.completed_types);
        }
        for (self.resolver_joins.items) |*join| {
            join.ty = try self.types.resolve(join.ty, 0);
            join.result = try self.types.resolve(join.result, 0);
        }
        for (self.resolver_completions.items) |completion| try self.normalizeList(completion.completed_types);
        for (self.resolver_loops.items) |*loop| {
            loop.cursor = try self.types.resolve(loop.cursor, 0);
            loop.step_result = try self.types.resolve(loop.step_result, 0);
            loop.suffix_result = try self.types.resolve(loop.suffix_result, 0);
        }
        for (self.access_types) |list| try self.normalizeList(list);
        for (self.nominals.items[1..]) |nominal_| {
            try self.normalizeList(nominal_.parameters);
            try self.normalizeList(nominal_.variables);
        }
        for (self.constructors.items[1..]) |*constructor| {
            constructor.scheme.root = try self.types.resolve(constructor.scheme.root, 0);
            constructor.payload = try self.types.resolve(constructor.payload, 0);
            try self.normalizeList(constructor.scheme.variables);
        }
        for (self.effect_families.items[1..]) |family| {
            try self.normalizeList(family.parameters);
            try self.normalizeList(family.variables);
        }
        for (self.effect_templates.items[1..]) |*template| {
            template.parameter = try self.types.resolve(template.parameter, 0);
            template.result = try self.types.resolve(template.result, 0);
        }
        for (self.operation_uses.items) |*use| {
            try self.normalizeList(use.arguments);
            use.signature = try self.types.resolve(use.signature, 0);
        }

        for (self.provider_blocks.items) |*block| {
            block.body_result = try self.types.resolve(block.body_result, 0);
            block.result = try self.types.resolve(block.result, 0);
            block.body_effects = try self.types.resolveEffects(block.body_effects, 0);
            block.outer_effects = try self.types.resolveEffects(block.outer_effects, 0);
        }
        for (self.effect_runners.items) |*runner| {
            if (runner.read_token != 0) runner.read_token = try self.types.resolve(runner.read_token, 0);
            if (runner.write_token != 0) runner.write_token = try self.types.resolve(runner.write_token, 0);
            runner.state_type = try self.types.resolve(runner.state_type, 0);
            runner.body_result = try self.types.resolve(runner.body_result, 0);
            runner.result = try self.types.resolve(runner.result, 0);
            if (runner.implementation_type != 0) runner.implementation_type = try self.types.resolve(runner.implementation_type, 0);
            runner.action_type = try self.types.resolve(runner.action_type, 0);
            runner.body_effects = try self.types.resolveEffects(runner.body_effects, 0);
            runner.outer_effects = try self.types.resolveEffects(runner.outer_effects, 0);
        }
        for (self.obligations.items) |*predicate| {
            predicate.ty = try self.types.resolve(predicate.ty, 0);
            if (predicate.result != 0) predicate.result = try self.types.resolve(predicate.result, 0);
            if (predicate.other != 0) predicate.other = try self.types.resolve(predicate.other, 0);
            if (predicate.signature != 0) predicate.signature = try self.types.resolve(predicate.signature, 0);
        }
        if (self.diagnostics.items.len == 0) for (self.cases.items) |id| try self.checkCoverage(id);
    }
    fn normalizeList(self: *Engine, list: T.List) T.Error!void {
        if (list.len == 0) return;
        const copy = try self.allocator.dupe(T.Id, self.types.list(list));
        defer self.allocator.free(copy);
        for (copy, 0..) |old, i| self.types.replaceListItem(list, i, try self.types.resolve(old, 0));
    }
    fn wildcard(self: *const Engine, id: ast.Id) bool {
        if (id == 0) return true;
        return switch (self.tree.node(id).tag) {
            .pattern_name, .pattern_field => true,
            else => false,
        };
    }
    fn checkCoverage(self: *Engine, id: ast.Id) T.Error!void {
        const n = self.tree.node(id);
        const input = self.tree.extra.items[n.a..][0..2];
        var types_: std.ArrayList(T.Id) = .empty;
        defer types_.deinit(self.allocator);
        for (self.tree.list(.{ .start = input[0], .len = input[1] })) |child| {
            const ty = self.expr_types[child];
            // A diverging scrutinee produces no pattern row to cover. All
            // pattern and arm expressions were still checked during inference.
            if (try self.types.resolve(ty, 0) == T.never) return;
            try types_.append(self.allocator, ty);
        }
        var rows: std.ArrayList([]const ast.Id) = .empty;
        defer rows.deinit(self.allocator);
        for (self.tree.list(.{ .start = n.b, .len = n.c })) |arm_id| {
            const arm = self.tree.node(arm_id);
            const guard = self.tree.extra.items[arm.c];
            if (guard != 0) continue;
            for (self.tree.list(.{ .start = arm.a, .len = arm.b })) |row| try rows.append(self.allocator, self.tree.children(row));
        }
        var budget: usize = 100_000;
        if (!try self.covered(rows.items, types_.items, 0, &budget)) try self.diagnostic(.non_exhaustive_match, id);
    }
    fn covered(self: *Engine, rows: []const []const ast.Id, types_: []const T.Id, depth: usize, budget: *usize) T.Error!bool {
        if (budget.* == 0 or depth >= 1024) return error.TypeLimit;
        budget.* -= 1;
        if (rows.len == 0) return false;
        if (types_.len == 0) return true;
        for (rows) |row| {
            var all = true;
            for (row) |pat| all = all and self.wildcard(pat);
            if (all) return true;
        }
        const ty = try self.types.resolve(types_[0], 0);
        const n = self.types.node(ty);
        var variants: std.ArrayList(T.Id) = .empty;
        defer variants.deinit(self.allocator);
        switch (n.tag) {
            .boolean => try variants.appendSlice(self.allocator, &.{ 0, 1 }),
            .nominal => {
                const index = self.nominalIndex(.{ .unit = n.a, .decl = n.b }) orelse return false;
                try variants.appendSlice(self.allocator, self.types.list(self.nominals.items[index].constructors));
            },
            .unit, .record, .product => try variants.append(self.allocator, 0),
            else => {
                var defaults: std.ArrayList([]const ast.Id) = .empty;
                defer defaults.deinit(self.allocator);
                for (rows) |row| if (self.wildcard(row[0])) {
                    try defaults.append(self.allocator, row[1..]);
                };
                return self.covered(defaults.items, types_[1..], depth + 1, budget);
            },
        }
        for (variants.items) |variant| {
            var children: std.ArrayList(T.Id) = .empty;
            defer children.deinit(self.allocator);
            var record_payload: ?T.Node = null;
            switch (n.tag) {
                .nominal => {
                    const use = self.types.node(try self.constructorStorageType(variant));
                    if (use.tag == .function) {
                        try self.constrain(use.b, ty, 0);
                        const payload = try self.types.resolve(use.a, 0);
                        const shape = self.types.node(payload);
                        if (shape.tag == .record) {
                            record_payload = shape;
                            for (0..shape.b) |index| try children.append(self.allocator, self.types.recordField(shape, index).ty);
                        } else try children.append(self.allocator, payload);
                    }
                },
                .product => try children.appendSlice(self.allocator, self.types.list(.{ .start = n.a, .len = n.b })),
                .record => for (0..n.b) |i| {
                    try children.append(self.allocator, self.types.recordField(n, i).ty);
                },
                else => {},
            }
            const arity = children.items.len;
            try children.appendSlice(self.allocator, types_[1..]);
            var words: std.ArrayList(ast.Id) = .empty;
            defer words.deinit(self.allocator);
            var ranges: std.ArrayList(T.List) = .empty;
            defer ranges.deinit(self.allocator);
            for (rows) |row| {
                const pat = row[0];
                const wildcard_ = self.wildcard(pat);
                const p = if (pat == 0) ast.Node{ .tag = .pattern_name } else self.tree.node(pat);
                if (!wildcard_) {
                    const matches = switch (n.tag) {
                        .boolean => p.tag == .pattern_boolean and p.a == variant,
                        .unit => p.tag == .pattern_product and self.tree.children(pat).len == 0,
                        .nominal => p.tag == .pattern_constructor and self.constructor_resolved[pat] == variant,
                        .product => p.tag == .pattern_product,
                        .record => p.tag == .pattern_record,
                        else => false,
                    };
                    if (!matches) continue;
                }
                const start: u32 = @intCast(words.items.len);
                try words.appendNTimes(self.allocator, 0, arity);
                if (!wildcard_) switch (n.tag) {
                    .nominal => if (arity != 0) {
                        if (record_payload) |record| {
                            const payload = self.tree.node(p.b);
                            if (payload.tag == .pattern_record) {
                                for (self.tree.children(p.b)) |field| {
                                    const slot = self.projections[field];
                                    if (slot < arity) words.items[start + slot] = self.tree.node(field).b;
                                }
                            } else if (record.b == 1) {
                                words.items[start] = p.b;
                            } else if (payload.tag == .pattern_product) {
                                const fields = self.tree.children(p.b);
                                if (fields.len != arity) continue;
                                @memcpy(words.items[start..][0..arity], fields);
                            }
                        } else words.items[start] = p.b;
                    },
                    .product => {
                        const fields = self.tree.children(pat);
                        if (fields.len != arity) continue;
                        @memcpy(words.items[start..][0..arity], fields);
                    },
                    .record => for (self.tree.children(pat)) |field_| {
                        const f = self.tree.node(field_);
                        const slot = self.projections[field_];
                        if (slot < arity) words.items[start + slot] = f.b;
                    },
                    else => {},
                };
                try words.appendSlice(self.allocator, row[1..]);
                try ranges.append(self.allocator, .{ .start = start, .len = @intCast(arity + row.len - 1) });
            }
            var specialized: std.ArrayList([]const ast.Id) = .empty;
            defer specialized.deinit(self.allocator);
            for (ranges.items) |range| try specialized.append(self.allocator, words.items[range.start..][0..range.len]);
            if (!try self.covered(specialized.items, children.items, depth + 1, budget)) return false;
        }
        return true;
    }
};

const SchemeCopier = struct {
    allocator: Allocator,
    source: F.Source,
    destination: *T.Store,
    mapping: std.AutoHashMapUnmanaged(T.Id, T.Id) = .empty,
    row_variables: std.AutoHashMapUnmanaged(u32, T.Effects.Id) = .empty,
    rows: std.AutoHashMapUnmanaged(T.Effects.Id, T.Effects.Id) = .empty,
    labels: std.AutoHashMapUnmanaged(T.Effects.Label, T.Effects.Label) = .empty,
    fn deinit(self: *SchemeCopier) void {
        self.mapping.deinit(self.allocator);
        self.row_variables.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.labels.deinit(self.allocator);
    }
    fn quantifiedRows(self: *SchemeCopier, span: T.List) T.Error!T.List {
        var variables: std.ArrayList(u32) = .empty;
        defer variables.deinit(self.allocator);
        for (self.source.list(span)) |index| {
            const fresh = try self.destination.freshEffects();
            try self.row_variables.put(self.allocator, index, fresh);
            try variables.append(self.allocator, self.destination.effects.node(fresh).tail.variable);
        }
        return self.destination.saveList(variables.items);
    }
    fn copyLabel(self: *SchemeCopier, label: T.Effects.Label, depth: usize) T.Error!T.Effects.Label {
        if (depth >= 1024 or label == 0 or label >= self.source.operationCount()) return error.TypeLimit;
        if (self.labels.get(label)) |known| return known;
        const operation = self.source.operation(label);
        var args: std.ArrayList(T.Id) = .empty;
        defer args.deinit(self.allocator);
        for (self.source.list(operation.arguments)) |arg| try args.append(self.allocator, try self.copy(arg, depth + 1));
        const result = try self.destination.internOperation(operation.identity, args.items);
        try self.labels.put(self.allocator, label, result);
        return result;
    }
    fn copyRow(self: *SchemeCopier, source_row: T.Effects.Id, depth: usize) T.Error!T.Effects.Id {
        if (depth >= 1024) return error.TypeLimit;
        if (source_row == 0) return 0;
        if (self.rows.get(source_row)) |known| return known;
        const row = self.source.row(source_row);
        var labels: std.ArrayList(T.Effects.Label) = .empty;
        defer labels.deinit(self.allocator);
        for (self.source.rowLabels(row.labels)) |label| try labels.append(self.allocator, try self.copyLabel(label, depth + 1));
        const tail: T.Effects.Tail = switch (row.tail) {
            .closed => .closed,
            .parameter => |index| .{ .parameter = index },
            .variable => |index| self.destination.effects.node(self.row_variables.get(index) orelse return error.TypeLimit).tail,
        };
        const result = self.destination.effects.row(labels.items, tail) catch |err| return T.effectError(err);
        try self.rows.put(self.allocator, source_row, result);
        return result;
    }

    fn copy(self: *SchemeCopier, source_id: T.Id, depth: usize) T.Error!T.Id {
        if (depth >= 1024) return error.TypeLimit;
        const id = self.source.head(source_id, 0);
        if (self.mapping.get(id)) |known| return known;
        const node = self.source.node(id);
        const result = switch (node.tag) {
            .absent, .unit, .boolean, .u32, .f32, .never => id,
            .array, .list, .cursor => try self.destination.sequence(node.tag, try self.copy(node.a, depth + 1)),
            .demand => try self.destination.demandWithEffects(try self.copy(node.a, depth + 1), try self.copyRow(node.c, depth + 1)),
            .provider => try self.destination.provider(try self.copy(node.a, depth + 1), try self.copyRow(node.c, depth + 1)),
            .state_provider => try self.destination.stateProvider(try self.copy(node.a, depth + 1), try self.copy(node.b, depth + 1), try self.copy(node.c, depth + 1)),
            .resolver => try self.destination.resolver(try self.copy(node.a, depth + 1)),
            .type_constructor => try self.destination.typeConstructor(.{ .unit = node.a, .decl = node.b }),
            .record => blk: {
                var fields: std.ArrayList(T.Field) = .empty;
                defer fields.deinit(self.allocator);
                for (0..node.b) |i| {
                    const f = self.source.recordField(node, i);
                    try fields.append(self.allocator, .{ .name = f.name, .ty = try self.copy(f.ty, depth + 1) });
                }
                break :blk try self.destination.record(fields.items);
            },
            .nominal => blk: {
                var args: std.ArrayList(T.Id) = .empty;
                defer args.deinit(self.allocator);
                for (self.source.nominalArguments(node)) |arg| try args.append(self.allocator, try self.copy(arg, depth + 1));
                break :blk try self.destination.nominal(.{ .unit = node.a, .decl = node.b }, args.items);
            },
            // Every external variable must have been quantified in the
            // producer's principal scheme. No caller solver state is imported.
            .variable => return error.TypeLimit,
            .function => try self.destination.functionWithEffects(try self.copy(node.a, depth + 1), try self.copy(node.b, depth + 1), try self.copyRow(node.c, depth + 1)),
            .product => blk: {
                var fields: std.ArrayList(T.Id) = .empty;
                defer fields.deinit(self.allocator);
                for (self.source.list(.{ .start = node.a, .len = node.b })) |child|
                    try fields.append(self.allocator, try self.copy(child, depth + 1));
                break :blk try self.destination.product(fields.items);
            },
        };
        try self.mapping.put(self.allocator, id, result);
        return result;
    }
};

/// Standalone source has parsed imports but no resolved module interface.
/// Keep the native import origin; callers may explicitly project UTF-16.
pub fn sourceImportDiagnostic(tree: *const ast.Tree) ?Diagnostic {
    if (tree.diagnostics.items.len != 0) return null;
    for (tree.roots.items) |id| if (tree.node(id).tag == .import_decl) {
        const origin = tree.span(id).start;
        return .{ .code = .module_loader_required, .node = id, .span = .{ .start = origin, .end = origin } };
    };
    return null;
}

pub fn hasNumericFailure(tree: *const ast.Tree) bool {
    for (tree.nodes.items) |node| if (node.tag == .numeric_error) return true;
    return false;
}
fn deinitDiagnosticPayloads(allocator: Allocator, diagnostics: []const Diagnostic) void {
    for (diagnostics) |diagnostic| {
        if (diagnostic.purity) |witness| witness.deinit(allocator);
        if (diagnostic.detail) |detail| allocator.free(detail);
        if (diagnostic.hole) |hole| hole.deinit(allocator);
    }
}
fn cloneDiagnostics(allocator: Allocator, diagnostics: []const Diagnostic) ![]Diagnostic {
    const result = try allocator.alloc(Diagnostic, diagnostics.len);
    var initialized: usize = 0;
    errdefer {
        deinitDiagnosticPayloads(allocator, result[0..initialized]);
        allocator.free(result);
    }
    for (diagnostics, result) |diagnostic, *target| {
        target.* = diagnostic;
        target.detail = null;
        target.purity = null;
        target.hole = null;
        initialized += 1;
        if (diagnostic.purity) |witness| target.purity = try witness.clone(allocator);
        if (diagnostic.detail) |detail| target.detail = try allocator.dupe(u8, detail);
        if (diagnostic.hole) |hole| target.hole = try hole.clone(allocator);
    }
    return result;
}
fn rejectedSource(allocator: Allocator, diagnostics: []const Diagnostic) !Checked {
    var types = try T.Store.init(allocator);
    errdefer types.deinit();
    const bindings = try allocator.dupe(Binding, &.{.{ .name = 0, .declaration = 0, .owner = 0, .kind = .local, .ty = 0 }});
    errdefer allocator.free(bindings);
    const owned = try cloneDiagnostics(allocator, diagnostics);
    return .{ .types = types, .expr_types = &.{}, .resolved = &.{}, .bindings = bindings, .merges = &.{}, .obligations = &.{}, .diagnostics = owned, .body_elaborations = 0 };
}
fn rejectNumericSource(allocator: Allocator, tree: *const ast.Tree, pool: *symbols.Pool, imports: []const ImportedBinding, catalogs: []const ImportedCatalog, unit: u32, options: ModuleOptions) !Checked {
    var headers: std.ArrayList(SourceHeader) = .empty;
    defer headers.deinit(allocator);
    for (imports) |imported| try headers.append(allocator, .{ .name = imported.name, .namespace = imported.namespace, .member = imported.member, .target = imported.target, .named_function = imported.interface.named_function, .origin = imported.origin, .expose = imported.expose });
    var owned_declarations: std.ArrayList([]SourceDeclaration) = .empty;
    defer {
        for (owned_declarations.items) |declarations| allocator.free(declarations);
        owned_declarations.deinit(allocator);
    }
    var source_catalogs: std.ArrayList(SourceCatalog) = .empty;
    defer source_catalogs.deinit(allocator);
    for (catalogs) |imported| {
        const declarations = try allocator.alloc(SourceDeclaration, imported.bindingCount());
        owned_declarations.append(allocator, declarations) catch |err| {
            allocator.free(declarations);
            return err;
        };
        for (declarations, 0..) |*declaration, index| declaration.* = imported.declaration(@intCast(index));
        try source_catalogs.append(allocator, .{ .producer = imported.catalog(), .declarations = declarations, .namespace = imported.namespace, .name = imported.name, .kind = imported.kind, .index = imported.index, .origin = imported.origin });
    }
    var validation = try validateModuleSource(allocator, tree, pool, headers.items, source_catalogs.items, unit, options);
    defer validation.deinit(allocator);
    if (validation.diagnostics.len == 0) return error.NumericValidationIncomplete;
    return rejectedSource(allocator, validation.diagnostics);
}

pub fn check(allocator: Allocator, tree: *const ast.Tree, pool: *symbols.Pool) !Checked {
    if (sourceImportDiagnostic(tree)) |item| return rejectedSource(allocator, &.{item});
    return checkInternal(allocator, tree, pool, &.{}, &.{}, &.{}, &.{}, 1, false, .{}, false);
}

/// Isolated proof entrypoint; the public checker/project/CLI remain default off.
pub fn checkPrivateExecution(allocator: Allocator, tree: *const ast.Tree, pool: *symbols.Pool, execution: PrivateExecution) !Checked {
    if (sourceImportDiagnostic(tree)) |item| return rejectedSource(allocator, &.{item});
    return checkInternalExecution(allocator, tree, pool, &.{}, &.{}, &.{}, &.{}, 1, false, .{}, false, execution);
}

pub fn checkWithImports(allocator: Allocator, tree: *const ast.Tree, pool: *symbols.Pool, imports: []const ImportedBinding) !Checked {
    return checkInternal(allocator, tree, pool, imports, &.{}, &.{}, &.{}, 1, true, .{}, false);
}

pub fn checkModule(allocator: Allocator, tree: *const ast.Tree, pool: *symbols.Pool, imports: []const ImportedBinding, catalogs: []const ImportedCatalog, unit: u32) !Checked {
    return checkModuleWithOptions(allocator, tree, pool, imports, catalogs, unit, .{});
}

pub fn checkModuleWithOptions(allocator: Allocator, tree: *const ast.Tree, pool: *symbols.Pool, imports: []const ImportedBinding, catalogs: []const ImportedCatalog, unit: u32, options: ModuleOptions) !Checked {
    return checkModuleWithPrivateExecution(allocator, tree, pool, imports, catalogs, unit, options, .{});
}

/// PRIVATE project proof forwarding. Execution is separate from semantic
/// ModuleOptions; the unchanged worker admits only its original whole component.
pub fn checkModuleWithPrivateExecution(allocator: Allocator, tree: *const ast.Tree, pool: *symbols.Pool, imports: []const ImportedBinding, catalogs: []const ImportedCatalog, unit: u32, options: ModuleOptions, execution: PrivateExecution) !Checked {
    if (unit == 0) return error.InvalidUnit;
    return checkInternalExecution(allocator, tree, pool, imports, &.{}, catalogs, &.{}, unit, true, options, false, execution);
}

/// An owned source-lowering region. Its declaration tables support subsequent
/// prelude lowering; it has no principal interface or executable typed body.
/// Project validation destroys every such region before returning diagnostics.
pub const SourceValidation = struct {
    types: T.Store,
    parameter_patterns: P.Store,
    declarations: []SourceDeclaration,
    resolved: []BindingId,
    nominals: []Nominal,
    contracts: []Contract,
    contract_predicates: []T.Obligation,
    constructors: []Constructor,
    effect_families: []EffectFamily,
    effect_templates: []EffectTemplate,
    associated: []Associated,
    diagnostics: []Diagnostic,
    unit: u32,
    pub fn deinit(self: *SourceValidation, allocator: Allocator) void {
        self.types.deinit();
        self.parameter_patterns.deinit(allocator);
        allocator.free(self.declarations);
        allocator.free(self.resolved);
        allocator.free(self.nominals);
        allocator.free(self.contracts);
        allocator.free(self.contract_predicates);
        allocator.free(self.constructors);
        allocator.free(self.effect_families);
        allocator.free(self.effect_templates);
        allocator.free(self.associated);
        deinitDiagnosticPayloads(allocator, self.diagnostics);
        allocator.free(self.diagnostics);
        self.* = undefined;
    }
};

pub fn validateModuleSource(allocator: Allocator, tree: *const ast.Tree, pool: *symbols.Pool, headers: []const SourceHeader, catalogs: []const SourceCatalog, unit: u32, options: ModuleOptions) (T.Error || error{ InvalidUnit, NumericValidationIncomplete })!SourceValidation {
    if (unit == 0) return error.InvalidUnit;
    var checked = try checkInternal(allocator, tree, pool, &.{}, headers, &.{}, catalogs, unit, true, options, true);
    defer checked.deinit(allocator);
    const declarations = try allocator.alloc(SourceDeclaration, checked.bindings.len);
    for (checked.bindings, declarations) |binding, *declaration| declaration.* = sourceDeclaration(binding);
    const result: SourceValidation = .{
        .types = checked.types,
        .parameter_patterns = checked.parameter_patterns,
        .declarations = declarations,
        .resolved = checked.resolved,
        .nominals = checked.nominals,
        .contracts = checked.contracts,
        .contract_predicates = checked.contract_predicates,
        .constructors = checked.constructors,
        .effect_families = checked.effect_families,
        .effect_templates = checked.effect_templates,
        .associated = checked.associated,
        .diagnostics = checked.diagnostics,
        .unit = checked.unit,
    };
    // Detach only static owners. The private intermediate checker destroys its
    // expression/body arrays, value schemes and obligations before publication.
    checked.types = .{ .allocator = allocator, .effects = .{ .allocator = allocator } };
    checked.parameter_patterns = .{};
    checked.resolved = &.{};
    checked.nominals = &.{};
    checked.contracts = &.{};
    checked.contract_predicates = &.{};
    checked.constructors = &.{};
    checked.effect_families = &.{};
    checked.effect_templates = &.{};
    checked.associated = &.{};
    checked.diagnostics = &.{};
    return result;
}

fn checkInternal(allocator: Allocator, tree: *const ast.Tree, pool: *symbols.Pool, imports: []const ImportedBinding, headers: []const SourceHeader, catalogs: []const ImportedCatalog, source_catalogs: []const SourceCatalog, unit: u32, allow_imports: bool, options: ModuleOptions, source_validation: bool) !Checked {
    return checkInternalExecution(allocator, tree, pool, imports, headers, catalogs, source_catalogs, unit, allow_imports, options, source_validation, .{});
}
fn checkInternalExecution(allocator: Allocator, tree: *const ast.Tree, pool: *symbols.Pool, imports: []const ImportedBinding, headers: []const SourceHeader, catalogs: []const ImportedCatalog, source_catalogs: []const SourceCatalog, unit: u32, allow_imports: bool, options: ModuleOptions, source_validation: bool, execution: PrivateExecution) !Checked {
    if (!source_validation and hasNumericFailure(tree)) return rejectNumericSource(allocator, tree, pool, imports, catalogs, unit, options);
    var engine: Engine = .{
        .execution = execution,
        .allocator = allocator,
        .tree = tree,
        .pool = pool,
        .types = try T.Store.initWithOptions(allocator, .{ .closed_graphs = true }),
        .expr_types = &.{},
        .resolved = &.{},
        .self_name = 0,
        .unit = unit,
        .builtin_catalog = options.builtin_catalog,
        .purity_origins = options.purity_origins,
        .source_validation = source_validation,
        .prelude_unit = options.prelude_unit,
    };
    errdefer engine.types.deinit();
    defer engine.holes.deinit(allocator);
    defer engine.active_aliases.deinit(allocator);
    defer {
        deinitDiagnosticPayloads(allocator, engine.source_header_diagnostics);
        allocator.free(engine.source_header_diagnostics);
    }
    errdefer engine.parameter_patterns.deinit(allocator);
    var tag_count: usize = 0;
    for (tree.nodes.items) |node| {
        if (node.tag == .attribute) tag_count += 1;
    }
    if (tag_count != 0) {
        engine.tag_origins = try allocator.alloc(TagOrigin, tag_count);
        var index: usize = 0;
        for (tree.nodes.items, 0..) |node, id| if (node.tag == .attribute) {
            engine.tag_origins[index] = .{ .span = tree.span(node.a), .attribute = @intCast(id) };
            index += 1;
        };
    }
    errdefer engine.reflections.deinit(allocator);
    defer engine.computations.deinit(allocator);
    defer engine.request_loops.deinit(allocator);
    defer engine.request_arms.deinit(allocator);
    defer engine.request_controls.deinit(allocator);
    errdefer allocator.free(engine.tag_origins);

    engine.provider_block_ids = try allocator.alloc(u32, tree.nodes.items.len);
    errdefer allocator.free(engine.provider_block_ids);
    @memset(engine.provider_block_ids, 0);
    engine.effect_runner_ids = try allocator.alloc(u32, tree.nodes.items.len);
    errdefer allocator.free(engine.effect_runner_ids);
    @memset(engine.effect_runner_ids, 0);
    errdefer engine.effect_runners.deinit(allocator);
    errdefer engine.provider_blocks.deinit(allocator);
    engine.operation_refs = try allocator.alloc(u32, tree.nodes.items.len);
    errdefer allocator.free(engine.operation_refs);
    @memset(engine.operation_refs, 0);
    errdefer engine.effect_families.deinit(allocator);
    errdefer engine.effect_templates.deinit(allocator);
    errdefer engine.operation_uses.deinit(allocator);
    errdefer engine.body_closed_rows.deinit(allocator);
    defer engine.closed_row_keys.deinit(allocator);
    defer engine.row_sources.deinit(allocator);
    engine.lambda_closed_rows = try allocator.alloc(T.List, tree.nodes.items.len);
    errdefer allocator.free(engine.lambda_closed_rows);
    @memset(engine.lambda_closed_rows, .{});
    engine.dispatch_signatures = try allocator.alloc(T.Id, tree.nodes.items.len);
    errdefer allocator.free(engine.dispatch_signatures);
    @memset(engine.dispatch_signatures, 0);
    try engine.effect_families.append(allocator, .{ .identity = .{ .unit = 0, .decl = 0 }, .name = 0 });
    try engine.effect_templates.append(allocator, .{ .identity = .{ .unit = 0, .decl = 0 }, .family = 0, .name = 0, .parameter = 0, .result = 0 });
    engine.expr_types = try allocator.alloc(T.Id, tree.nodes.items.len);
    errdefer allocator.free(engine.expr_types);
    engine.resolved = try allocator.alloc(BindingId, tree.nodes.items.len);
    errdefer allocator.free(engine.resolved);
    engine.constructor_resolved = try allocator.alloc(u32, tree.nodes.items.len);
    errdefer allocator.free(engine.constructor_resolved);
    @memset(engine.constructor_resolved, 0);
    engine.projections = try allocator.alloc(u32, tree.nodes.items.len);
    errdefer allocator.free(engine.projections);
    @memset(engine.projections, std.math.maxInt(u32));
    engine.projection_resolved = try allocator.alloc(u32, tree.nodes.items.len);
    errdefer allocator.free(engine.projection_resolved);
    @memset(engine.projection_resolved, 0);
    engine.access_paths = try allocator.alloc(T.List, tree.nodes.items.len);
    errdefer allocator.free(engine.access_paths);
    @memset(engine.access_paths, .{});
    engine.access_nodes = try allocator.alloc(T.List, tree.nodes.items.len);
    errdefer allocator.free(engine.access_nodes);
    @memset(engine.access_nodes, .{});
    engine.access_types = try allocator.alloc(T.List, tree.nodes.items.len);
    errdefer allocator.free(engine.access_types);
    @memset(engine.access_types, .{});
    engine.rebindings = try allocator.alloc(Rebinding, tree.nodes.items.len);
    errdefer allocator.free(engine.rebindings);
    @memset(engine.rebindings, .{});
    engine.loop_ranges = try allocator.alloc(T.List, tree.nodes.items.len);
    errdefer allocator.free(engine.loop_ranges);
    @memset(engine.loop_ranges, .{});
    engine.iterator_bodies = try allocator.alloc(ast.Id, tree.nodes.items.len);
    errdefer allocator.free(engine.iterator_bodies);
    @memset(engine.iterator_bodies, 0);
    engine.demand_calls = try allocator.alloc(bool, tree.nodes.items.len);
    errdefer allocator.free(engine.demand_calls);
    @memset(engine.demand_calls, false);
    engine.demand_types = try allocator.alloc(T.Id, tree.nodes.items.len);
    errdefer allocator.free(engine.demand_types);
    @memset(engine.demand_types, 0);
    engine.demand_binary_left_types = try allocator.alloc(T.Id, tree.nodes.items.len);
    errdefer allocator.free(engine.demand_binary_left_types);
    @memset(engine.demand_binary_left_types, 0);
    engine.demand_binary_left = try allocator.alloc(bool, tree.nodes.items.len);
    errdefer allocator.free(engine.demand_binary_left);
    @memset(engine.demand_binary_left, false);
    engine.resolver_block_ids = try allocator.alloc(u32, tree.nodes.items.len);
    errdefer allocator.free(engine.resolver_block_ids);
    @memset(engine.resolver_block_ids, 0);
    engine.resolver_op_ids = try allocator.alloc(u32, tree.nodes.items.len);
    errdefer allocator.free(engine.resolver_op_ids);
    @memset(engine.resolver_op_ids, 0);
    engine.resolver_join_ids = try allocator.alloc(u32, tree.nodes.items.len);
    errdefer allocator.free(engine.resolver_join_ids);
    @memset(engine.resolver_join_ids, 0);
    engine.resolver_loop_ids = try allocator.alloc(u32, tree.nodes.items.len);
    errdefer allocator.free(engine.resolver_loop_ids);
    @memset(engine.resolver_loop_ids, 0);
    errdefer engine.resolver_blocks.deinit(allocator);
    errdefer engine.resolver_ops.deinit(allocator);
    errdefer engine.resolver_joins.deinit(allocator);
    errdefer engine.resolver_completions.deinit(allocator);
    errdefer engine.resolver_loops.deinit(allocator);
    errdefer engine.loop_carries.deinit(allocator);
    errdefer engine.loop_exits.deinit(allocator);
    defer engine.loop_stack.deinit(allocator);
    defer engine.effect_family_names.deinit(allocator);
    defer engine.effect_family_identities.deinit(allocator);
    defer engine.effect_members.deinit(allocator);
    defer engine.effect_operation_names.deinit(allocator);
    defer engine.effect_template_identities.deinit(allocator);
    defer engine.nominal_identities.deinit(allocator);
    defer engine.constructor_identities.deinit(allocator);
    defer engine.nominal_names.deinit(allocator);
    defer engine.constructor_names.deinit(allocator);
    defer engine.type_env.deinit(allocator);
    defer engine.row_env.deinit(allocator);
    defer engine.computation_annotations.deinit(allocator);
    defer engine.cases.deinit(allocator);
    defer engine.associated_ops.deinit(allocator);
    defer engine.associated_members.deinit(allocator);
    errdefer engine.associated.deinit(allocator);
    errdefer engine.nominals.deinit(allocator);
    errdefer engine.contracts.deinit(allocator);
    errdefer engine.contract_predicates.deinit(allocator);
    defer engine.contract_names.deinit(allocator);
    defer engine.contract_identities.deinit(allocator);
    defer engine.contract_states.deinit(allocator);
    errdefer engine.constructors.deinit(allocator);
    errdefer engine.projection_catalog.deinit(allocator);
    try engine.nominals.append(allocator, .{ .identity = .{ .unit = 0, .decl = 0 }, .name = 0, .parameters = .{}, .variables = .{} });
    try engine.constructors.append(allocator, .{ .identity = .{ .unit = 0, .decl = 0 }, .nominal = 0, .tag = 0, .name = 0 });
    try engine.projection_catalog.append(allocator, .{ .nominal = .{ .unit = 0, .decl = 0 }, .field = 0, .variants = .{} });
    // Semantic checking borrows the source pool. It must not grow a caller's
    // pool using a potentially different scratch allocator.
    for (0..pool.entries.items.len) |index| {
        const symbol: symbols.Symbol = @intCast(index + 1);
        if (std.mem.eql(u8, pool.get(symbol), "self")) {
            engine.self_name = symbol;
            break;
        }
    }
    @memset(engine.expr_types, 0);
    @memset(engine.resolved, 0);
    defer engine.globals.deinit(allocator);
    defer engine.global_states.deinit(allocator);
    defer engine.active.deinit(allocator);
    defer engine.env.deinit(allocator);
    defer engine.pending.deinit(allocator);
    defer engine.qualifications.deinit(allocator);
    defer engine.qualification_uses.deinit(allocator);
    defer engine.declared_obligations.deinit(allocator);
    defer engine.predicate_origins.deinit(allocator);
    defer engine.computed_variables.deinit(allocator);
    defer engine.computed_rows.deinit(allocator);
    defer engine.overrides.deinit(allocator);
    defer engine.qualified.deinit(allocator);
    defer engine.qualified_symbols.deinit(allocator);
    defer engine.external_targets.deinit(allocator);
    errdefer engine.bindings.deinit(allocator);
    errdefer {
        deinitDiagnosticPayloads(allocator, engine.diagnostics.items);
        engine.diagnostics.deinit(allocator);
    }
    errdefer engine.obligations.deinit(allocator);
    errdefer engine.merges.deinit(allocator);
    _ = try engine.addBinding(.{ .name = 0, .declaration = 0, .owner = 0, .kind = .local, .ty = 0 });
    for (tree.diagnostics.items) |diagnostic| try engine.diagnostics.append(allocator, .{ .code = .syntax, .span = .{ .start = diagnostic.start, .end = diagnostic.end }, .node = 0 });
    try engine.dataHeaders();
    try engine.contractHeaders();
    var local_fixities: std.AutoHashMapUnmanaged(symbols.Symbol, void) = .empty;
    defer local_fixities.deinit(allocator);
    for (options.inherited_fixities) |fixity| try engine.overrides.put(allocator, fixity.operator, .{ .target = fixity.target, .named = fixity.named, .external = fixity.external });
    for (tree.roots.items) |id| {
        if (tree.node(id).tag == .data_decl or tree.node(id).tag == .type_alias_decl or tree.node(id).tag == .contract_decl or tree.node(id).tag == .effect_decl or tree.node(id).tag == .effect_type_decl) continue;
        if (allow_imports and tree.node(id).tag == .import_decl) continue;
        if (tree.node(id).tag == .fixity_decl) {
            const fixity = tree.fixity(id);
            if (fixity.attributes.len != 0) try engine.diagnostic(.unsupported_attribute, id);
            if (local_fixities.contains(fixity.operator)) try engine.diagnostic(.duplicate_name, id) else {
                try local_fixities.put(allocator, fixity.operator, {});
                try engine.overrides.put(allocator, fixity.operator, .{ .target = fixity.target, .named = fixity.named });
            }
            continue;
        }
        if (tree.node(id).tag != .value_decl) {
            try engine.diagnostic(.unsupported, id);
            continue;
        }
        const declaration = tree.valueDecl(id);
        if (engine.globals.contains(declaration.name)) {
            try engine.diagnostic(.duplicate_name, id);
            continue;
        }
        const binding = try engine.addBinding(.{ .name = declaration.name, .declaration = id, .owner = id, .kind = .global, .named_function = tree.node(declaration.body).tag == .lambda and declaration.attributes.len == 0, .ty = try engine.types.fresh() });
        try engine.globals.put(allocator, declaration.name, binding);
        try engine.global_states.put(allocator, binding, .{});
        engine.resolved[id] = binding;
    }
    for (catalogs) |imported| try engine.importCatalog(imported);
    for (source_catalogs) |imported| try engine.importCatalog(imported);
    for (imports) |imported| {
        if (engine.source_validation) try engine.importHeader(.{ .name = imported.name, .namespace = imported.namespace, .member = imported.member, .target = imported.target, .named_function = imported.interface.named_function, .origin = imported.origin, .expose = imported.expose }) else try engine.importBinding(imported);
    }
    for (headers) |imported| try engine.importHeader(imported);
    try engine.effectHeaders();
    try engine.dataBodies();
    for (0..engine.contracts.items.len) |index| try engine.resolveContract(@intCast(index));
    try engine.indexAssociated();
    for (options.inherited_fixities) |fixity| {
        if (local_fixities.contains(fixity.operator)) continue;
        const binding = if (fixity.external) |external| engine.external_targets.get(external) else try engine.catalogBinding(fixity.target);
        if (binding == null) try engine.diagnostic(.unknown_name, fixity.origin);
    }
    // A source declaration named namespace.member cannot silently hide an
    // imported declaration whose identity is the same numeric pair.
    for (tree.roots.items) |id| if (tree.node(id).tag == .value_decl) {
        if (engine.qualifiedKey(tree.valueDecl(id).name)) |key|
            if (engine.qualified.contains(key)) try engine.diagnostic(.duplicate_name, id);
    };
    if (engine.source_validation) engine.source_header_diagnostics = try engine.diagnostics.toOwnedSlice(allocator);
    const source_issue = if (tree.diagnostics.items.len == 0) try source_operators.validate(allocator, tree, pool, &engine) else null;
    if (source_issue) |issue| {
        // Source lowering fails before inference. Do not publish unrelated
        // provisional type failures collected while building declaration tables.
        deinitDiagnosticPayloads(allocator, engine.diagnostics.items);
        engine.diagnostics.clearRetainingCapacity();
        try engine.diagnostics.append(allocator, .{ .code = switch (issue.code) {
            .effect_member => .effect_member,
            .constructor_marker => .constructor_marker,
            .integer_range => .integer_range,
            .float_range => .float_range,
            .float_literal => .float_literal,
            .duplicate_name => .duplicate_name,
            .alternative_bindings => .alternative_bindings,
            .duplicate_pattern_binding => .duplicate_pattern_binding,
            .duplicate_record_field => .duplicate_record_field,
            .unknown_record_field => .unknown_record_field,
            .record_constructor => .record_constructor,
            .missing_record_field => .missing_record_field,
            .unknown_modifier => .unknown_modifier,
            .unknown_operator => .unknown_operator,
            .unknown_value => .unknown_value,
            .unknown_rebinding => .unknown_rebinding,
            .unreachable_statement => .unreachable_statement,
            .operator_associativity => .operator_associativity,
            .operator_header_order => .operator_header_order,
            .operator_precedence => .operator_precedence,
            .duplicate_operator => .duplicate_operator,
            .unsupported_prefix => .unsupported_prefix,
            .unknown_intrinsic => .unknown_intrinsic,
            .unsupported_expression => .unsupported_expression,
            .unknown_constructor => .unknown_constructor,
            .sealed_effect => .sealed_effect,
            .call_arity => .call_arity,
            .requests_scope => .requests_scope,
            .yield_scope => .yield_scope,
            .break_scope => .break_scope,
            .literal_required => .literal_required,
            .product_index_literal => .product_index_literal,
            .nesting_limit => .nesting_limit,
        }, .node = issue.node, .span = .{ .start = issue.point, .end = issue.point }, .symbol = issue.symbol, .implicit_type_witness = issue.implicit_type_witness, .source_terminator = issue.terminator, .numeric_literal = issue.numeric_literal });
    }
    if (tree.diagnostics.items.len == 0 and source_issue == null and !engine.source_annotation_failed) {
        for (tree.roots.items) |id| if (tree.node(id).tag == .fixity_decl) {
            if (try engine.catalogBinding(tree.fixity(id).target)) |binding| engine.resolved[id] = binding else try engine.diagnostic(.unknown_name, id);
        };
    }
    if (!engine.source_validation and tree.diagnostics.items.len == 0 and source_issue == null) {
        for (tree.roots.items) |id| if (tree.node(id).tag == .value_decl and engine.resolved[id] != 0) try engine.inferGlobal(engine.resolved[id]);
        // A known entry resolver cannot omit a source protocol method. Do not
        // instantiate unrelated latent closure predicates here: their exact
        // operand evidence belongs to the demanded retained body instance.
        for (tree.roots.items) |id| if (tree.node(id).tag == .value_decl and tree.valueDecl(id).exported and engine.resolved[id] != 0) {
            const principal = engine.bindings.items[engine.resolved[id]].scheme;
            for (engine.obligations.items[principal.obligations.start..][0..principal.obligations.len]) |constraint| {
                if (constraint.kind != .resolver_dispatch) continue;
                const owner = engine.types.node(try engine.types.resolve(constraint.ty, 0));
                if (owner.tag != .resolver) continue;
                const token = engine.types.node(try engine.types.resolve(owner.a, 0));
                if (token.tag != .type_constructor) continue;
                if (!engine.associated_members.contains(.{ .identity = .{ .unit = token.a, .decl = token.b }, .member = constraint.name })) try engine.diagnostic(.missing_member, constraint.source);
            }
        };
        try engine.finish();
        try engine.finishReflection();
        try engine.finishHoles();
    }
    const computations = try engine.computations.toOwnedSlice(allocator);
    errdefer allocator.free(computations);
    const request_loops = try engine.request_loops.toOwnedSlice(allocator);
    errdefer allocator.free(request_loops);
    const request_arms = try engine.request_arms.toOwnedSlice(allocator);
    errdefer allocator.free(request_arms);
    const request_controls = try engine.request_controls.toOwnedSlice(allocator);
    errdefer allocator.free(request_controls);
    const reflections = try engine.reflections.toOwnedSlice(allocator);
    errdefer allocator.free(reflections);
    const bindings = try engine.bindings.toOwnedSlice(allocator);
    errdefer allocator.free(bindings);
    const diagnostics = try engine.diagnostics.toOwnedSlice(allocator);
    errdefer {
        deinitDiagnosticPayloads(allocator, diagnostics);
        allocator.free(diagnostics);
    }
    const obligations = try engine.obligations.toOwnedSlice(allocator);
    errdefer allocator.free(obligations);
    const nominals = try engine.nominals.toOwnedSlice(allocator);
    errdefer allocator.free(nominals);
    const contracts = try engine.contracts.toOwnedSlice(allocator);
    errdefer allocator.free(contracts);
    const contract_predicates = try engine.contract_predicates.toOwnedSlice(allocator);
    errdefer allocator.free(contract_predicates);
    const constructors = try engine.constructors.toOwnedSlice(allocator);
    errdefer allocator.free(constructors);
    const projection_catalog = try engine.projection_catalog.toOwnedSlice(allocator);
    errdefer allocator.free(projection_catalog);
    const associated = try engine.associated.toOwnedSlice(allocator);
    errdefer allocator.free(associated);
    const loop_carries = try engine.loop_carries.toOwnedSlice(allocator);
    errdefer allocator.free(loop_carries);
    const loop_exits = try engine.loop_exits.toOwnedSlice(allocator);
    errdefer allocator.free(loop_exits);
    const resolver_blocks = try engine.resolver_blocks.toOwnedSlice(allocator);
    errdefer allocator.free(resolver_blocks);
    const resolver_ops = try engine.resolver_ops.toOwnedSlice(allocator);
    errdefer allocator.free(resolver_ops);
    const resolver_joins = try engine.resolver_joins.toOwnedSlice(allocator);
    errdefer allocator.free(resolver_joins);
    const resolver_completions = try engine.resolver_completions.toOwnedSlice(allocator);
    errdefer allocator.free(resolver_completions);
    const resolver_loops = try engine.resolver_loops.toOwnedSlice(allocator);
    errdefer allocator.free(resolver_loops);
    const effect_families = try engine.effect_families.toOwnedSlice(allocator);
    errdefer allocator.free(effect_families);
    const effect_templates = try engine.effect_templates.toOwnedSlice(allocator);
    errdefer allocator.free(effect_templates);
    const operation_uses = try engine.operation_uses.toOwnedSlice(allocator);
    errdefer allocator.free(operation_uses);
    const effect_runners = try engine.effect_runners.toOwnedSlice(allocator);
    errdefer allocator.free(effect_runners);
    const provider_blocks = try engine.provider_blocks.toOwnedSlice(allocator);
    errdefer allocator.free(provider_blocks);
    const body_closed_rows = try engine.body_closed_rows.toOwnedSlice(allocator);
    errdefer allocator.free(body_closed_rows);
    const merges = try engine.merges.toOwnedSlice(allocator);
    errdefer allocator.free(merges);
    var checked: Checked = .{ .iterator_bodies = engine.iterator_bodies, .computations = computations, .request_loops = request_loops, .request_arms = request_arms, .request_controls = request_controls, .reflections = reflections, .tag_origins = engine.tag_origins, .effect_runners = effect_runners, .effect_runner_ids = engine.effect_runner_ids, .provider_blocks = provider_blocks, .provider_block_ids = engine.provider_block_ids, .body_closed_rows = body_closed_rows, .lambda_closed_rows = engine.lambda_closed_rows, .dispatch_signatures = engine.dispatch_signatures, .effect_families = effect_families, .effect_templates = effect_templates, .operation_uses = operation_uses, .operation_refs = engine.operation_refs, .resolver_completions = resolver_completions, .resolver_loops = resolver_loops, .resolver_loop_ids = engine.resolver_loop_ids, .resolver_blocks = resolver_blocks, .resolver_ops = resolver_ops, .resolver_joins = resolver_joins, .resolver_block_ids = engine.resolver_block_ids, .resolver_op_ids = engine.resolver_op_ids, .resolver_join_ids = engine.resolver_join_ids, .demand_calls = engine.demand_calls, .demand_types = engine.demand_types, .demand_binary_left_types = engine.demand_binary_left_types, .demand_binary_left = engine.demand_binary_left, .loop_carries = loop_carries, .loop_ranges = engine.loop_ranges, .loop_exits = loop_exits, .unit = unit, .associated = associated, .nominals = nominals, .contracts = contracts, .contract_predicates = contract_predicates, .constructors = constructors, .constructor_resolved = engine.constructor_resolved, .projections = engine.projections, .access_paths = engine.access_paths, .access_nodes = engine.access_nodes, .access_types = engine.access_types, .projection_resolved = engine.projection_resolved, .projection_catalog = projection_catalog, .rebindings = engine.rebindings, .types = engine.types, .parameter_patterns = engine.parameter_patterns, .expr_types = engine.expr_types, .resolved = engine.resolved, .bindings = bindings, .merges = merges, .obligations = obligations, .diagnostics = diagnostics, .body_elaborations = engine.body_elaborations, .imported_schemes = if (source_validation) 0 else engine.external_targets.count() };
    if (!source_validation and engine.initializer_rejected) {
        var rejected = try rejectedSource(allocator, checked.diagnostics);
        rejected.initializer_rejected = true;
        rejected.unit = unit;
        checked.deinit(allocator);
        return rejected;
    }
    return checked;
}
