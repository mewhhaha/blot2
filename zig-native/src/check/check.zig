//! Handwritten HM checker. Source bodies produce principal schemes; uses get
//! fresh type variables and their own numeric obligations. Every declaration is
//! checked, including declarations not reachable from an entrypoint.
const std = @import("std");
const region_arena = @import("../eval/region_arena.zig");
const ast = @import("../parse/ast.zig");
const symbols = @import("../parse/symbols.zig");
const T = @import("types.zig");
const dispatch_explanation = @import("../reuse/dispatch_explanation.zig");
const P = @import("parameter_patterns.zig");
const loop_targets = @import("../backend/loop_targets.zig");
const source_operators = @import("../parse/source_operators.zig");
const global_references = @import("../reuse/global_references.zig");
const proof_headers = @import("numeric_proof_headers.zig");
const proof_terms = @import("numeric_proof_terms.zig");
const proof_bodies = @import("numeric_proof_bodies.zig");
const staging = @import("typed_staging.zig");
const Allocator = std.mem.Allocator;
const F = @import("frozen_types.zig");
const PI = @import("../reuse/principal_interface.zig");
pub const BindingId = u32;
pub const ProofContract = struct {
    binding: BindingId,
    header: proof_headers.Owned,
    parameters: []BindingId,
    fn deinit(self: *ProofContract, allocator: Allocator) void {
        self.header.deinit(allocator);
        allocator.free(self.parameters);
        self.* = undefined;
    }
};
/// Symbolic imports retain their producer; named targets resolve lexically.
pub const ImportedFixity = struct { operator: symbols.Symbol, target: symbols.Symbol, named: bool, external: ?ExternalTarget = null, origin: ast.Id = 0 };
pub const ModuleOrigins = struct {
    context: ?*const anyopaque = null,
    lookup: ?*const fn (?*const anyopaque, Allocator, u32) T.Error![]u8 = null,
    source_available: ?*const fn (?*const anyopaque, u32) bool = null,
    pub fn name(self: ModuleOrigins, allocator: Allocator, unit: u32, current_unit: u32) @import("../eval/purity_type_key.zig").OriginError![]u8 {
        if (self.lookup) |lookup| return lookup(self.context, allocator, unit);
        if (unit != current_unit) return error.SourceIdentityUnavailable;
        return allocator.dupe(u8, "main");
    }
};
/// A request-local cursor marker. Numeric facts in EditorCapture are owned by
/// the returned Checked region; callers must never publish them as artifacts.
pub const EditorMarker = struct { span: ast.Span, kind: @import("../reuse/completion_probe.zig").Kind, prefix: []const u8 = "" };
pub const EditorName = struct {
    name: symbols.Symbol,
    kind: enum { value, function, type_, constructor, field, member, module },
    scheme: T.Scheme = .{},
    distance: u32 = 0,
    identity: Identity = .{ .unit = 0, .decl = 0 },
    external: ?ExternalTarget = null,
    ambiguous: bool = false,
    receiver: bool = false,
};
pub const EditorCapture = struct {
    names: []EditorName = &.{},
    kind: @import("../reuse/completion_probe.zig").Kind,
    node: ast.Id,
    scope: T.List,
    visible: T.List = .{},
    visible_names: T.List = .{},
    scope_names: T.List = .{},
    type_scope: T.List = .{},
    truncated: bool = false,
    owner: BindingId,
    receiver: T.Id = 0,
    namespace: symbols.Symbol = 0,
    context: ?@import("../reuse/hole_diagnostics.zig").Snapshot = null,
};
const default_inference_budget = if (@hasDecl(@import("root"), "compiler_defaults")) @import("root").compiler_defaults.inference_budget else 1_000_000;
fn inferenceBudget(options: ModuleOptions) usize {
    if (options.max_inference_transitions) |limit| return limit;
    if (@hasDecl(@import("root"), "inferenceBudget")) return @import("root").inferenceBudget();
    return default_inference_budget;
}
pub const ModuleOptions = struct { editor: ?EditorMarker = null, purity_origins: ModuleOrigins = .{}, builtin_catalog: bool = false, prelude_unit: u32 = 0, inherited_fixities: []const ImportedFixity = &.{}, max_inference_transitions: ?usize = null, associated_remaining: ?*usize = null, body_source: []const u8 = &.{}, retained_bodies: ?*@import("../reuse/body_check_cache.zig").Cache = null, previous_bodies: ?*const @import("../reuse/body_check_cache.zig").Cache = null, body_external_names: ?@import("../reuse/body_check_cache.zig").ExternalNames = null, producer_capabilities: ?ProducerCapabilities = null, producer_storage: ?ProducerStorage = null };
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
    schedule_globals: bool = true,
    stats: ?*AliasGlobalStats = null,
    context: ?*anyopaque = null,
    observe: ?*const fn (?*anyopaque, GlobalTrace) void = null,
};
pub const Identity = T.NominalIdentity;
pub const Nominal = PI.Nominal;
pub const Contract = PI.Contract;
pub const ContractMember = PI.ContractMember;
pub const Implementation = PI.Implementation;
pub const ImplementationMember = PI.ImplementationMember;
const implementation_patterns = @import("../eval/implementation_patterns.zig");
pub const Constructor = PI.Constructor;
pub const Associated = PI.Associated;
pub const EffectFamily = PI.EffectFamily;
pub const EffectTemplate = PI.EffectTemplate;
pub const ReflectionKind = enum(u32) { of, descriptor, count, has, same };
pub const Reflection = struct { node: ast.Id, kind: ReflectionKind, left: ast.Id = 0, right: ast.Id = 0, binding: BindingId = 0, row: T.Effects.Id = 0, label: T.Effects.Label = 0 };
pub const OperationUse = struct { node: ast.Id, template: u32, arguments: T.List, signature: T.Id, instance: Identity = .{ .unit = 0, .decl = 0 }, capability: ast.Id = 0, capability_binding: BindingId = 0, call: enum { value, state_read, state_write } = .value, operand: ast.Id = 0 };
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
    kind: enum { catalog, nominal, constructor, effect_family, contract, implementation },
    index: u32,
    origin: ast.Id,

    pub fn catalog(self: ImportedCatalog) DeclarationCatalog {
        if (self.frozen) |owner| return .{ .types = .{ .frozen = &owner.graph }, .parameter_patterns = .{ .frozen = &owner.patterns }, .nominals = owner.nominals, .constructors = owner.constructors, .effect_families = owner.effect_families, .effect_templates = owner.effect_templates, .associated = owner.associated, .unit = owner.unit, .contracts = owner.contracts, .contract_predicates = owner.contract_predicates, .contract_members = owner.contract_members, .implementations = owner.implementations, .implementation_predicates = owner.implementation_predicates, .implementation_members = owner.implementation_members };
        return declarationCatalog(self.producer.?);
    }
    pub fn bindingCount(self: ImportedCatalog) usize {
        return if (self.frozen) |owner| owner.bindings.len else self.producer.?.bindings.len;
    }
    pub fn declaration(self: ImportedCatalog, id: BindingId) SourceDeclaration {
        if (self.frozen) |owner| {
            const value = owner.bindings[id];
            return .{ .private = value.private, .name = value.name, .declaration = 0, .kind = value.kind, .capability_flow = value.capability_flow, .capability_parameters = value.capability_parameters, .named_function = value.named_function, .external = value.external };
        }
        return sourceDeclaration(self.producer.?.bindings[id]);
    }
    pub fn interface(self: ImportedCatalog, id: BindingId) SchemeInterface {
        if (self.frozen) |owner| {
            const value = owner.bindings[id];
            return .{ .producer_binding = id, .proof_contract = proof_headers.find(owner.proof_contracts, id), .types = .{ .frozen = &owner.graph }, .scheme = value.scheme, .capability_flow = value.capability_flow, .capability_parameters = value.capability_parameters, .named_function = value.named_function, .obligations = owner.obligations, .callees = .{ .frozen = owner } };
        }
        const owner = self.producer.?;
        const value = owner.bindings[id];
        return .{ .producer_binding = id, .proof_contract = checkedProofContract(owner, id), .types = .{ .store = &owner.types }, .scheme = value.scheme, .capability_flow = value.capability_flow, .capability_parameters = value.capability_parameters, .named_function = value.named_function, .obligations = owner.obligations, .callees = .{ .live = owner } };
    }
};
/// Static imports cannot carry principal source-body interfaces.
pub const SourceCatalog = struct { producer: DeclarationCatalog, declarations: []const SourceDeclaration, namespace: symbols.Symbol = 0, name: symbols.Symbol = 0, kind: @FieldType(ImportedCatalog, "kind"), index: u32, origin: ast.Id };
pub const Kind = PI.Kind;
pub const ExternalTarget = PI.ExternalTarget;
/// A completed global's scheme may reference other completed schemes by
/// reference (`callee_use` obligations) instead of repeating their
/// obligations. `summary` records what a use needs to share such a scheme.
pub const SchemeSummary = struct {
    /// Saturating count of the flat obligations this scheme stands for.
    flat_size: u32 = 0,
    /// Quantified variables and rows reachable from the root: the part of an
    /// instantiation that callers observe. Everything else is private.
    public_variables: T.List = .{},
    public_rows: T.List = .{},
    /// One flag per public variable: it occurs in a parameter type.
    public_inputs: T.List = .{},
    public_outputs: T.List = .{},
    only_result_selected: bool = false,
    /// Predicate-connected public slots retain the computed-value restriction
    /// even when the predicates themselves are behind shared references.
    requirement_variables: T.List = .{},
    requirement_rows: T.List = .{},
    has_explicit: bool = false,
    /// Only schemes made of position-independent obligations are shared.
    shareable: bool = false,
};
pub const CapabilityFlow = @import("capability_flow.zig").Contract;
pub const Binding = struct { read: bool = false, capability_flow: CapabilityFlow = .unknown, capability_parameters: @import("capability_flow.zig").Parameters = .{}, operation_ref: u32 = 0, private: bool = false, name: symbols.Symbol, declaration: ast.Id, owner: ast.Id, kind: Kind, named_function: bool = false, ty: T.Id, scheme: T.Scheme = .{}, external: ?ExternalTarget = null, predecessor: BindingId = 0, summary: SchemeSummary = .{} };
/// An immutable interface borrows only semantic tables, never a source body.
pub const SchemeInterface = struct {
    /// Binding ordinal in the owner of `callees`, before external relocation.
    producer_binding: BindingId = 0,
    proof_contract: ?*const proof_headers.Owned = null,
    capability_flow: CapabilityFlow = .unknown,
    capability_parameters: @import("capability_flow.zig").Parameters = .{},
    named_function: bool = false,
    types: F.Source,
    scheme: T.Scheme,
    obligations: []const T.Obligation,
    /// Where the schemes shared by this scheme's `callee_use` obligations live.
    callees: Callees = .none,
    /// The producer's recipe, when it differs from `callees`/`producer_binding`.
    capability_source: ?CapabilitySource = null,
};
/// The producer tables that resolve a scheme's shared callees by binding.
pub const Callees = union(enum) {
    none,
    live: *const Checked,
    frozen: *const PI.Interface,

    pub fn capabilityContract(self: Callees, binding: u32, arity: u32) ?@import("capability_contracts.zig").Recipe {
        return switch (self) {
            .none => null,
            .live => |owner| owner.capability_contracts.header(binding, arity),
            .frozen => |owner| owner.capability_contracts.header(binding, arity),
        };
    }
    pub fn interface(self: Callees, binding: u32) ?SchemeInterface {
        switch (self) {
            .none => return null,
            .live => |owner| {
                if (binding == 0 or binding >= owner.bindings.len) return null;
                const value = owner.bindings[binding];
                return .{ .producer_binding = binding, .proof_contract = checkedProofContract(owner, binding), .types = .{ .store = &owner.types }, .scheme = value.scheme, .capability_flow = value.capability_flow, .capability_parameters = value.capability_parameters, .named_function = value.named_function, .obligations = owner.obligations, .callees = self };
            },
            .frozen => |owner| {
                if (binding == 0 or binding >= owner.bindings.len) return null;
                const value = owner.bindings[binding];
                return .{ .producer_binding = binding, .proof_contract = proof_headers.find(owner.proof_contracts, binding), .types = .{ .frozen = &owner.graph }, .scheme = value.scheme, .capability_flow = value.capability_flow, .capability_parameters = value.capability_parameters, .named_function = value.named_function, .obligations = owner.obligations, .callees = self };
            },
        }
    }
};
pub fn checkedProofContract(owner: *const Checked, binding: u32) ?*const proof_headers.Owned {
    for (owner.proof_contracts) |*value| if (value.binding == binding) return &value.header;
    return null;
}
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
pub const SourceHeader = struct { capability_flow: CapabilityFlow = .unknown, capability_parameters: @import("capability_flow.zig").Parameters = .{}, name: symbols.Symbol = 0, namespace: symbols.Symbol = 0, member: symbols.Symbol = 0, target: ExternalTarget, named_function: bool = false, origin: ast.Id, expose: bool = true };
pub const SourceDeclaration = struct { capability_flow: CapabilityFlow = .unknown, capability_parameters: @import("capability_flow.zig").Parameters = .{}, private: bool = false, name: symbols.Symbol, declaration: ast.Id, kind: Kind, named_function: bool, external: ?ExternalTarget };
/// The capability facts an imported binding's own producer published. A
/// member imported through another module's catalog arrives as that module's
/// alias, and a frozen interface keeps no capability facts for aliases; taking
/// them from the producer gives a live and a frozen-interface check the same
/// imports.
pub const ProducerCapability = struct {
    flow: CapabilityFlow = .unknown,
    parameters: @import("capability_flow.zig").Parameters = .{},
    /// Where the producer's published recipe lives, when it has one.
    recipe: ?CapabilitySource = null,
};
pub const CapabilitySource = struct { callees: Callees, binding: BindingId };
pub const ProducerCapabilities = struct {
    context: *const anyopaque,
    lookup: *const fn (context: *const anyopaque, target: ExternalTarget) ?ProducerCapability,
};
/// Opaque recipes come from the current original producer. A semantically
/// reusable forwarding catalog may still carry its previous physical recipe.
pub const ProducerStorage = struct {
    context: *const anyopaque,
    lookup: *const fn (context: *const anyopaque, identity: Identity) ?@import("../backend/opaque_storage.zig").Storage,
};
pub fn sourceDeclaration(binding: Binding) SourceDeclaration {
    return .{ .private = binding.private, .name = binding.name, .declaration = binding.declaration, .kind = binding.kind, .capability_flow = binding.capability_flow, .capability_parameters = binding.capability_parameters, .named_function = binding.named_function, .external = binding.external };
}
/// Shared borrowed declaration payloads. No value schemes, obligations or bodies.
pub const DeclarationCatalog = struct { types: F.Source, parameter_patterns: F.Patterns, nominals: []const Nominal, constructors: []const Constructor, effect_families: []const EffectFamily, effect_templates: []const EffectTemplate, associated: []const Associated, unit: u32, contracts: []const Contract = &.{}, contract_predicates: []const T.Obligation = &.{}, contract_members: []const ContractMember = &.{}, implementations: []const Implementation = &.{}, implementation_predicates: []const T.Obligation = &.{}, implementation_members: []const ImplementationMember = &.{} };
pub fn declarationCatalog(producer: anytype) DeclarationCatalog {
    return .{ .types = .{ .store = &producer.types }, .parameter_patterns = .{ .store = &producer.parameter_patterns }, .nominals = producer.nominals, .constructors = producer.constructors, .effect_families = producer.effect_families, .effect_templates = producer.effect_templates, .associated = producer.associated, .unit = producer.unit, .contracts = producer.contracts, .contract_predicates = producer.contract_predicates, .contract_members = producer.contract_members, .implementations = producer.implementations, .implementation_predicates = producer.implementation_predicates, .implementation_members = producer.implementation_members };
}
pub const ResolverKind = enum { monad, pure, bind, forward, iterate };
pub const ResolverBlock = struct { node: ast.Id, resolver: BindingId, result: T.Id, body_effects: T.Effects.Id = 0, fallthrough: u32 = 0 };
pub const EffectScope = struct { node: ast.Id, callback: ast.Id, parameter: ast.Id, capability: T.Id, result: T.Id, body_effects: T.Effects.Id };
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
/// A do: arm of a statement case whose rebinding carries out of the case.
/// Core lowers its statements as that arm's suite, as for an if branch.
pub const StatementArm = struct { node: ast.Id };
pub const ClosedRow = struct { owner: BindingId, variable: u32 };
pub const Merge = struct { node: ast.Id, result: BindingId, then_binding: BindingId, else_binding: BindingId };
pub const Code = enum { task_escape, task_handle_consumed, task_capture_transfer, task_capability_shared, task_demand_shared, task_regions_overlap, task_host_contract, task_budget, invalid_proof_operand, proof_scope_escape, proof_runtime_use, proof_mismatch, contradictory_proof, proof_analysis_limit, effect_identity_scope, capability_escape, capability_analysis_limit, undetermined_implementation, orphan_implementation, overlapping_implementation, incompatible_implementation, recursive_evidence, missing_type_member, associated_arity, recursive_associated_type, associated_limit, missing_implementation, private_access, private_identity_escape, unbound_alias_row, recursive_contract, contract_arity, recursive_type_alias, typed_hole, effect_member, integer_range, float_range, float_literal, module_loader_required, intrinsic_arity, requests_scope, yield_scope, request_loop_scope, request_loop_body, request_loop_range, request_binding, request_completion, request_clause_fallthrough, request_completion_fallthrough, duplicate_request_handler, request_case_scope, unknown_value, syntax, duplicate_name, unknown_name, type_mismatch, infinite_type, effect_mismatch, infinite_effect, const_effect, initializer_effect, let_effect, sealed_effect, effect_arity, effect_family, unknown_effect, invalid_effect_annotation, invalid_constraint, higher_rank_constraint, missing_predicate, ambiguous_qualified, annotation_kind_mismatch, unsupported_polymorphic_effect_label, operation_signature, type_arity, operation_target, invalid_state_provider, unsupported, unsupported_attribute, recursive_tag, function_target, open_effect_descriptor, unsupported_expression, unsupported_type, ambiguous_operator, ambiguous_associated, missing_associated, ambiguous_member, missing_member, type_constructor_required, invalid_provider, resolver_required, literal_required, call_arity, break_scope, continue_scope, invalid_return, unreachable_statement, invalid_operator, return_outside_block, return_outside_function, return_across_continuation, unknown_rebinding, dead_rebinding, case_arm_return, nesting_limit, unknown_constructor, constructor_marker, type_parameter, type_argument, duplicate_type_parameter, duplicate_type_field, unknown_field, duplicate_field, missing_field, non_exhaustive_match, refutable_pattern, constructor_arity, unknown_product_shape, product_index, product_index_literal, pattern_arity, pattern_bindings, value_pattern_type, non_exiting_fallback, unknown_operator, operator_associativity, operator_header_order, operator_precedence, duplicate_operator, unsupported_prefix, unknown_intrinsic, alternative_bindings, duplicate_pattern_binding, duplicate_record_field, unknown_record_field, record_constructor, missing_record_field, unknown_modifier, guard_fallthrough, product_arity, inference_budget, skolem_escape, rank_mismatch, package_expected, package_witness_mismatch, package_escape, abstract_representation_access, use_after_move, duplicate_owner, borrow_conflict, borrow_escape, once_reused, multiplicity_unknown, cleanup_not_safe, usage_evidence_mismatch, usage_analysis_limit, code_shape_mismatch, stage_unavailable, cross_stage_authority, descriptor_private, generated_binding_escape, staging_budget };
pub const PurityWitness = @import("../reuse/purity_diagnostics.zig").Witness;
pub const Diagnostic = struct {
    pub const TypeApplication = enum { missing_array, missing_nominal, extra };
    pub const Terminator = source_operators.Terminator;
    pub const Context = struct {
        kind: enum { callee, argument, left_operand, right_operand },
        span: ast.Span,
    };
    origin_unit: u32 = 0,
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
    hole: ?@import("../reuse/hole_diagnostics.zig").Snapshot = null,
    /// Owned candidates of a failed operator or associated dispatch.
    explanation: ?dispatch_explanation.Explanation = null,
    /// At most two source expressions that explain a type/effect/dispatch
    /// mismatch at an application or binary operator.
    contexts: [2]Context = .{
        .{ .kind = .callee, .span = .{ .start = 0, .end = 0 } },
        .{ .kind = .argument, .span = .{ .start = 0, .end = 0 } },
    },
    context_len: u8 = 0,
    pub fn message(self: Diagnostic) []const u8 {
        if (self.detail) |detail| return detail;
        if (self.type_application) |application| return switch (application) {
            .missing_array => "Array requires one element type",
            .missing_nominal => "partially applied type constructor requires another argument",
            .extra => "type does not accept another argument; currying must be explicit in its declaration",
        };
        return switch (self.code) {
            .task_escape => "A task handle, group or loan outlives its task scope",
            .task_handle_consumed => "The task handle was already joined, cancelled or moved",
            .task_capture_transfer => "Task captures require an owning transfer or checked immutable sharing",
            .task_capability_shared => "A task capture shares a writable or scoped capability",
            .task_demand_shared => "A pending demand can move to one task but cannot be shared between tasks",
            .task_regions_overlap => "Task regions need one owner version and proved disjoint ranges",
            .task_host_contract => "Task host execution requires an explicit concurrent capability contract",
            .task_budget => "Task analysis exceeds its bounded state budget",
            .invalid_proof_operand => "A proof operand must name a preceding value of the required kind",
            .proof_scope_escape => "The proof refers to a value outside its complete contract",
            .proof_runtime_use => "An erased proof cannot be used as an ordinary runtime value",
            .proof_mismatch => "The witness does not establish this exact value proposition",
            .contradictory_proof => "The required proof contract contains contradictory facts",
            .proof_analysis_limit => "The required proof contract exceeds the analysis limit",
            .skolem_escape => "A rigid type escapes its quantified scope",
            .rank_mismatch => "The value does not satisfy the quantified annotation",
            .use_after_move => "This owning binding version was already moved",
            .duplicate_owner => "An affine owner cannot be copied",
            .borrow_conflict => "This owner has a conflicting live loan",
            .borrow_escape => "This loan outlives its owner scope",
            .once_reused => "This once callable may already have been invoked or moved",
            .multiplicity_unknown => "This callable has no checked affine invocation contract",
            .cleanup_not_safe => "Cleanup needs a finite non-suspending adapter contract",
            .usage_evidence_mismatch => "Usage evidence does not match the checked value",
            .usage_analysis_limit => "Usage analysis exceeds its bounded state budget",
            .package_expected => "An explicit existential package type is required",
            .package_witness_mismatch => "Package witnesses and opened binders must match the existential declaration",
            .package_escape => "An opened package identity escapes its lexical scope",
            .abstract_representation_access => "Reflection cannot inspect an abstract type witness",
            .code_shape_mismatch => "The value does not have the required typed code or descriptor shape",
            .stage_unavailable => "The value is unavailable at this stage; use explicit lift or splice",
            .cross_stage_authority => "The value carries authority that cannot cross a stage boundary",
            .descriptor_private => "The descriptor cannot expose this abstract or private shape",
            .generated_binding_escape => "A generated binding escapes its checked scope",
            .staging_budget => "Typed staging exceeds the analysis budget",
            .unbound_alias_row => "A data or effect declaration must carry an open alias row in an explicit type parameter",
            .undetermined_implementation => "The implementation head does not determine every declared parameter",
            .orphan_implementation => "The implementation producer owns neither the contract nor its anchor nominal",
            .overlapping_implementation => "Visible implementation heads have a common instantiation",
            .incompatible_implementation => "The matching implementation cannot satisfy its prerequisites",
            .recursive_evidence => "Implementation prerequisites repeat an active application",
            .missing_type_member => "The contract has no associated type member with this name",
            .associated_arity => "An associated projection requires the contract's complete argument shapes",
            .recursive_associated_type => "Associated type equations cannot recurse",
            .associated_limit => "Associated type normalization exceeded its work or depth limit",
            .missing_implementation => "This contract application requires an explicit implementation",
            .recursive_contract => "Contracts cannot include themselves recursively",
            .contract_arity => "A contract requires its declared type argument shapes",
            .recursive_type_alias => "Type aliases cannot refer to themselves recursively",
            .typed_hole => "Unfilled expression; expected",
            .effect_identity_scope => "A scoped effect requires a direct callback with one family annotation",
            .capability_escape => "A scoped capability or unknown authority footprint cannot cross its owner boundary",
            .capability_analysis_limit => "Scoped capability analysis exceeded its bound",
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
            .resolver_required => "Break $ requires a monad resolver",
            .literal_required => "This compiler primitive requires a literal string argument",
            .call_arity => "This compiler primitive requires its exact literal and operand arguments",
            .break_scope => "Break requires an enclosing loop in this function",
            .continue_scope => "Continue requires an enclosing loop in this function",
            .invalid_return => "Loop control cannot escape a suspended argument",
            .unreachable_statement => switch (self.source_terminator) {
                .return_, .break_, .yield_ => "statement after return in the same suite",
                .none => "A statement follows an unconditional return or break",
            },
            .invalid_operator => "This operator is not declared or supported",
            .return_outside_block => "Break with a value requires an enclosing do block in this function",
            .return_outside_function => "Return requires an enclosing function; use break with a value to finish a do block",
            .return_across_continuation => "Return cannot cross a monadic continuation or a nested request callback; finish that do block with break value instead",
            .unknown_rebinding => if (self.symbol != 0) ":= requires an existing local binding" else "Rebinding requires an existing lexical name",
            .dead_rebinding => "This := inside a nested do: block is never read and leaves the enclosing binding unchanged; rebind it with if/else or a statement case, or assign a case expression",
            .case_arm_return => "This break would leave only its case arm and skip the rebinding the arm carries out; break directly in the arm's do: block or restructure with if/else",
            .nesting_limit => "Semantic nesting exceeds the compiler limit",
            .inference_budget => "Type inference exceeded this module's work budget",
            .constructor_marker => "Record constructors require # before the name",
            .private_access => "Private declaration or opaque representation is unavailable here",
            .private_identity_escape => "Public signature exposes a private declaration",
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
pub const RequestArm = struct { node: ast.Id, loop: ast.Id, operation_source: ast.Id = 0, operation: T.Effects.Label, parameter_type: T.Id, reply_type: T.Id, signature: T.Id, pattern: ast.Id, suite: ast.Id, state_bindings: T.List };
pub const RequestLoop = struct { node: ast.Id, computation: ast.Id, value_type: T.Id, result_type: T.Id, state_type: T.Id, action_type: T.Id, arms: T.List, completion: ast.Id, complete_pattern: ast.Id, complete_suite: ast.Id, complete_state_bindings: T.List, carried: T.List, return_scope: ast.Id };
pub const RequestControl = struct { node: ast.Id, loop: ast.Id, kind: enum { reply, cancel, break_ }, value_type: T.Id, bindings: T.List = .{}, target_scope: ast.Id };
pub const UsageLoan = struct { source: ast.Id, callback: ast.Id, parameter: ast.Id, region: T.Id, mutable: bool, acquire: ast.Id = 0, release: ast.Id = 0 };
pub const DictionaryUse = struct { source: ast.Id, opening: BindingId, introduction: ast.Id = 0, quantifier: T.Id, goal: u32, member: u32 };
pub const DictionaryGiven = struct { opening: BindingId, introduction: ast.Id = 0, quantifier: T.Id, goal: u32, arguments: T.List, member_types: T.List };
pub const DictionaryProof = union(enum) { selected: u32, given: DictionaryGiven };
pub const DictionarySelection = struct { source: ast.Id, quantifier: T.Id, goal: u32, proof: DictionaryProof };
pub const RankImplementation = struct { scope: u32, quantified: T.Id, node: ast.Id = 0 };
/// A source requirement proven by a written clause of its own scope.
/// Coverage can solve clause-local parts, such as a method row closed by an
/// empty ambient, so body replay covers the same requirement again.
pub const CoveredRequirement = struct { scope: ast.Id, value: T.Obligation };
pub const Checked = struct {
    function_exit_lambdas: []ast.Id = &.{},
    usage_loans: []UsageLoan = &.{},
    proof_contracts: []ProofContract = &.{},
    proof_bodies: proof_bodies.Owned = .{},
    rank_implementations: []RankImplementation = &.{},
    generative_bindings: []@import("generative_schemes.zig").Binder = &.{},
    dictionary_selections: []DictionarySelection = &.{},
    dictionary_uses: []DictionaryUse = &.{},
    capability_contracts: @import("capability_contracts.zig").Collection = .{},
    editor: ?EditorCapture = null,
    iterator_bodies: []ast.Id = &.{},
    initializer_rejected: bool = false,
    computations: []Computation = &.{},
    request_loops: []RequestLoop = &.{},
    request_arms: []RequestArm = &.{},
    request_controls: []RequestControl = &.{},
    reflections: []Reflection = &.{},
    tag_origins: []TagOrigin = &.{},
    effect_scopes: []EffectScope = &.{},
    effect_scope_ids: []u32 = &.{},
    effect_runners: []EffectRunner = &.{},
    effect_runner_ids: []u32 = &.{},
    provider_blocks: []ProviderBlock = &.{},
    provider_block_ids: []u32 = &.{},
    body_closed_rows: []ClosedRow = &.{},
    lambda_closed_rows: []T.List = &.{},
    dispatch_signatures: []T.Id = &.{},
    covered_requirements: []CoveredRequirement = &.{},
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
    counters: Counters = .{},
    unit: u32 = 1,
    associated: []Associated = &.{},
    nominals: []Nominal = &.{},
    contracts: []Contract = &.{},
    contract_predicates: []T.Obligation = &.{},
    contract_members: []ContractMember = &.{},
    implementations: []Implementation = &.{},
    implementation_predicates: []T.Obligation = &.{},
    implementation_members: []ImplementationMember = &.{},
    member_templates: []PI.MemberTemplate = &.{},
    selected_proofs: []PI.SelectedProof = &.{},
    selected_members: []ImplementationMember = &.{},
    selected_edges: []u32 = &.{},
    selected_uses: []PI.SelectedUse = &.{},
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
    demand_once: []bool = &.{},
    demand_types: []T.Id = &.{},
    demand_binary_left_types: []T.Id = &.{},
    demand_binary_left: []bool = &.{},
    loop_exits: []LoopExit = &.{},
    statement_arms: []StatementArm = &.{},
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
        allocator.free(self.function_exit_lambdas);
        self.capability_contracts.deinit(allocator);
        if (self.editor) |editor| {
            allocator.free(editor.names);
            if (editor.context) |context| context.deinit(allocator);
        }
        allocator.free(self.iterator_bodies);
        allocator.free(self.computations);
        allocator.free(self.request_loops);
        allocator.free(self.request_arms);
        allocator.free(self.request_controls);
        allocator.free(self.reflections);
        allocator.free(self.tag_origins);
        allocator.free(self.effect_scopes);
        allocator.free(self.effect_scope_ids);
        allocator.free(self.effect_runners);
        allocator.free(self.effect_runner_ids);
        allocator.free(self.provider_blocks);
        allocator.free(self.provider_block_ids);
        allocator.free(self.body_closed_rows);
        allocator.free(self.rank_implementations);
        allocator.free(self.generative_bindings);
        allocator.free(self.dictionary_selections);
        allocator.free(self.dictionary_uses);
        allocator.free(self.usage_loans);
        allocator.free(self.lambda_closed_rows);
        allocator.free(self.dispatch_signatures);
        allocator.free(self.covered_requirements);
        allocator.free(self.effect_families);
        allocator.free(self.effect_templates);
        allocator.free(self.operation_uses);
        allocator.free(self.operation_refs);
        for (self.proof_contracts) |*contract| contract.deinit(allocator);
        allocator.free(self.proof_contracts);
        self.proof_bodies.deinit(allocator);
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
        allocator.free(self.contract_members);
        allocator.free(self.implementations);
        allocator.free(self.implementation_predicates);
        allocator.free(self.implementation_members);
        allocator.free(self.member_templates);
        allocator.free(self.selected_proofs);
        allocator.free(self.selected_members);
        allocator.free(self.selected_edges);
        allocator.free(self.selected_uses);
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
        allocator.free(self.demand_once);
        allocator.free(self.demand_types);
        allocator.free(self.demand_binary_left_types);
        allocator.free(self.demand_binary_left);
        allocator.free(self.loop_exits);
        allocator.free(self.statement_arms);
        self.* = undefined;
    }
};
const Entry = struct { name: symbols.Symbol, binding: BindingId };
/// Checker work counters, reported through the stats JSON.
pub const Counters = struct {
    obligations_appended: u64 = 0,
    pending_peak: u64 = 0,
    instantiations: u64 = 0,
    shared_uses: u64 = 0,
    use_expansions: u64 = 0,
    memo_hits: u64 = 0,
    memo_misses: u64 = 0,
    memo_declined: u64 = 0,
    /// Budgeted inference steps (`ModuleOptions.max_inference_transitions`).
    inference_steps: u64 = 0,
    associated_steps: u64 = 0,
    projection_memo_hits: u64 = 0,

    pub fn add(self: *Counters, other: Counters) void {
        inline for (@typeInfo(Counters).@"struct".field_names) |name| {
            if (comptime std.mem.eql(u8, name, "pending_peak")) @field(self, name) = @max(@field(self, name), @field(other, name)) else @field(self, name) += @field(other, name);
        }
    }
};
const CalleeOutcome = struct { types: []T.Id, rows: []T.Effects.Id };
const unchanged_output = std.math.maxInt(u32);
const State = enum { pending, active, complete };
const Global = struct { state: State = .pending, index: u32 = 0, low: u32 = 0, on_stack: bool = false };
const PendingObligation = struct { metadata: u32 = 0, value: T.Obligation, owner: BindingId, scope: ast.Id = 0, origin: u32 = 0, wait_target: BindingId = 0, declared: bool = false, covered: bool = false, local_scheme: bool = false, direct: bool = false, method_member: bool = false, suspended: bool = false, solved: bool = false, expansion: u32 = 0 };
const Qualification = struct { scope: ast.Id, owner: BindingId, clauses: T.List, value: ast.Id, checked: bool = false };
const QualificationUse = struct { scope: ast.Id, owner: BindingId, target: BindingId, source: ast.Id };
const ForwardedRequirement = struct { use: usize, value: T.Obligation };
const SelectedGlobal = struct { binding: BindingId, owner: BindingId, diagnostic_at: usize };
const LoopFrame = struct { node: ast.Id, carries: []const Entry, iterations: []const BindingId, resolver_block: ast.Id = 0, exits: usize = 0 };
const ResolverScope = struct { block: ast.Id = 0, resolver: BindingId = 0, owner_type: T.Id = 0, result: T.Id = 0, progress_depth: u32 = 0 };
const RequestScope = struct { loop: ast.Id = 0, reply: T.Id = 0, target: T.Id = 0, completion: bool = false, return_scope: ast.Id = 0, arm: u32 = 0, state_bindings: T.List = .{}, invalid_outer_return: bool = false };
const Flow = struct { ty: T.Id = T.unit, exits: bool = false, returns: bool = false, breaks: bool = false };
const Qualified = struct { namespace: symbols.Symbol, member: symbols.Symbol };
const QualifiedResolution = struct { namespace: symbols.Symbol, binding: BindingId };
const OperatorOverride = struct { target: symbols.Symbol, named: bool, external: ?ExternalTarget = null };
// These lookup indices borrow published catalog identities. They own only
// mutable indexing storage and are retired before Checked publication.
const CatalogIndex = struct {
    effect_family_names: std.AutoHashMapUnmanaged(Qualified, u32) = .empty,
    effect_family_identities: std.AutoHashMapUnmanaged(Identity, u32) = .empty,
    effect_members: std.AutoHashMapUnmanaged(EffectMember, u32) = .empty,
    effect_operation_names: std.AutoHashMapUnmanaged(Qualified, u32) = .empty,
    effect_template_identities: std.AutoHashMapUnmanaged(Identity, u32) = .empty,
    qualified_symbols: std.AutoHashMapUnmanaged(symbols.Symbol, QualifiedResolution) = .empty,
    contract_names: std.AutoHashMapUnmanaged(Qualified, u32) = .empty,
    implementation_names: std.AutoHashMapUnmanaged(Qualified, u32) = .empty,
    contract_identities: std.AutoHashMapUnmanaged(Identity, u32) = .empty,
    nominal_identities: std.AutoHashMapUnmanaged(Identity, u32) = .empty,
    constructor_identities: std.AutoHashMapUnmanaged(Identity, u32) = .empty,
    nominal_names: std.AutoHashMapUnmanaged(Qualified, u32) = .empty,
    constructor_names: std.AutoHashMapUnmanaged(Qualified, u32) = .empty,
    associated_ops: std.AutoHashMapUnmanaged(AssociatedKey, u32) = .empty,
    associated_members: std.AutoHashMapUnmanaged(AssociatedMember, u32) = .empty,
    qualified: std.AutoHashMapUnmanaged(Qualified, BindingId) = .empty,
    external_targets: std.AutoHashMapUnmanaged(ExternalTarget, BindingId) = .empty,
    globals: std.AutoHashMapUnmanaged(symbols.Symbol, BindingId) = .empty,
    overrides: std.AutoHashMapUnmanaged(symbols.Symbol, OperatorOverride) = .empty,
    fn deinit(self: *CatalogIndex, allocator: Allocator) void {
        inline for (@typeInfo(CatalogIndex).@"struct".field_names) |field| @field(self, field).deinit(allocator);
    }
};

/// The versions of enclosing locals a statement case arm block leaves, read
/// before its scope closes. `carrying` is set when one of them is a successor.
const ArmCapture = struct { block: ast.Id, versions: []BindingId, carrying: bool = false };

const Engine = struct {
    catalogs: CatalogIndex = .{},
    associated_usage_work: @import("usage_check.zig").Work = .{},
    usage_loans: std.ArrayList(UsageLoan) = .empty,
    staging_depth: u32 = 0,
    staging_bindings: std.AutoHashMapUnmanaged(BindingId, u32) = .empty,
    proof_contracts: std.ArrayList(ProofContract) = .empty,
    proof_body: proof_bodies.Builder = .{},
    proof_visits: usize = 0,
    proof_header_active: bool = false,
    body_external_names: ?@import("../reuse/body_check_cache.zig").ExternalNames = null,
    body_source: []const u8 = &.{},
    retained_bodies: ?*@import("../reuse/body_check_cache.zig").Cache = null,
    previous_bodies: ?*const @import("../reuse/body_check_cache.zig").Cache = null,
    editor_marker: ?EditorMarker = null,
    editor_capture: ?EditorCapture = null,
    scratch_pool: region_arena.Pool,
    pending_arena: ?*region_arena.Arena = null,
    active_aliases: std.AutoHashMapUnmanaged(u32, void) = .empty,
    holes: std.ArrayList(struct { node: ast.Id, scope: T.List, owner: BindingId }) = .empty,
    execution: PrivateExecution = .{},
    inference_limit: usize = 1_000_000,
    inference_transitions: usize = 0,
    /// Where the module's inference budget ran out. The engine is discarded
    /// with its error; this record outlives it to position the diagnostic.
    budget_exhaustion: ?*BudgetExhaustion = null,
    /// The top-level declaration whose inference is under way.
    root_global: BindingId = 0,
    /// Body checking may finish before late selected dependencies stabilize.
    /// These members retain their recursive placeholders until publication.
    finishing_group: []const BindingId = &.{},
    dependency_owner: ?BindingId = null,
    /// Evidence heads use the ordinary value type before covariant row widening.
    exact_argument_types: bool = false,
    implementation_trace: @import("../eval/implementation_trace.zig").Record = .{},
    proved_predicate_target: ExternalTarget = .{ .unit = 0, .binding = 0 },
    proved_predicate_prerequisites: T.List = .{},
    active_predicates: std.ArrayList(struct { binding: BindingId, value: T.Obligation }) = .empty,
    computations: std.ArrayList(Computation) = .empty,
    request_loops: std.ArrayList(RequestLoop) = .empty,
    request_arms: std.ArrayList(RequestArm) = .empty,
    request_controls: std.ArrayList(RequestControl) = .empty,
    reflections: std.ArrayList(Reflection) = .empty,
    case_pattern_source: ast.Id = 0,
    let_pattern_source: ast.Id = 0,
    tag_origins: []TagOrigin = &.{},
    effect_scopes: std.ArrayList(EffectScope) = .empty,
    effect_scope_ids: []u32 = &.{},
    scoped_parameter: ast.Id = 0,
    scoped_parameter_type: T.Id = 0,
    active_effect_scopes: usize = 0,
    has_tasks: bool = false,
    expected_lambda_source: ast.Id = 0,
    expected_lambda_type: T.Id = 0,
    scope_lifetimes: std.ArrayList(T.Id) = .empty,
    capability_store: @import("capability_contracts.zig").Store = .{},
    generative_owner: ast.Id = 0,
    generative_bindings: std.ArrayList(@import("generative_schemes.zig").Binder) = .empty,
    has_input_invocations: bool = false,
    capability_roots: std.ArrayList(@import("capability_contracts.zig").Binding) = .empty,
    storage_frames: std.ArrayList(struct { read: T.Effects.Label, write: T.Effects.Label = 0, depth: usize }) = .empty,
    effect_runners: std.ArrayList(EffectRunner) = .empty,
    effect_runner_ids: []u32 = &.{},
    provider_blocks: std.ArrayList(ProviderBlock) = .empty,
    provider_block_ids: []u32 = &.{},
    body_closed_rows: std.ArrayList(ClosedRow) = .empty,
    covered_requirements: std.ArrayList(CoveredRequirement) = .empty,
    rank_implementations: std.ArrayList(RankImplementation) = .empty,
    dictionary_selections: std.ArrayList(DictionarySelection) = .empty,
    dictionary_uses: std.ArrayList(DictionaryUse) = .empty,
    dictionary_givens: std.ArrayList(struct { opening: BindingId, introduction: ast.Id = 0, quantifier: T.Id, goal: u32, predicate: T.Obligation }) = .empty,
    annotation_givens: std.ArrayList(T.Obligation) = .empty,
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
    /// Ready bits and type watches for `pending`, by the same index.
    pending_queue: @import("solver_worklist.zig").Queue = .{},
    counters: Counters = .{},
    /// Closed outcomes of shared scheme uses, keyed by callee and the closed
    /// projection of the use's instantiation. Values are owned slices.
    callee_memo: std.StringHashMapUnmanaged(CalleeOutcome) = .empty,
    mark_depth: u32 = 0,
    /// The candidate the latest successful `dispatch` selected.
    dispatch_side: dispatch_explanation.Side = .left,
    expansion_serial: u32 = 0,
    expansion_depth: u32 = 0,
    qualification_scope: ast.Id = 0,
    request_scope: RequestScope = .{},
    local_qualification_scope: ast.Id = 0,
    local_requirements_start: usize = 0,
    qualifications: std.ArrayList(Qualification) = .empty,
    qualification_uses: std.ArrayList(QualificationUse) = .empty,
    forwarded_requirements: std.AutoHashMapUnmanaged(ForwardedRequirement, void) = .empty,
    staged_global_diagnostics: std.AutoHashMapUnmanaged(BindingId, []Diagnostic) = .empty,
    selected_globals: std.ArrayList(SelectedGlobal) = .empty,
    global_driver: bool = false,
    declared_obligations: std.ArrayList(T.Obligation) = .empty,
    predicate_origins: std.ArrayList(ast.Span) = .empty,
    computed_variables: std.ArrayList(T.Id) = .empty,
    computed_rows: std.ArrayList(u32) = .empty,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    global_states: std.AutoHashMapUnmanaged(BindingId, Global) = .empty,
    active: std.ArrayList(BindingId) = .empty,
    env: std.ArrayList(Entry) = .empty,
    /// The block that is a lambda's own body, as opposed to a nested do:.
    function_body: ast.Id = 0,
    function_exit_allowed: bool = false,
    function_exit_target: T.Id = 0,
    function_exit_lambdas: std.ArrayList(ast.Id) = .empty,
    /// The case being checked as a statement, whose value is discarded.
    statement_case: ast.Id = 0,
    /// The statement case arm block awaiting its carried versions.
    arm_capture: ?*ArmCapture = null,
    /// The arm block being checked, and its first return nested below it.
    arm_block: ast.Id = 0,
    arm_nested_return: ast.Id = 0,
    current: BindingId = 0,
    pending_start: usize = 0,
    owner: ast.Id = 0,
    // A do/provider block changes return ownership, but keeps proof scope.
    proof_owner: ast.Id = 0,
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
    unit: u32 = 1,
    builtin_catalog: bool = false,
    source_validation: bool = false,
    producer_capabilities: ?ProducerCapabilities = null,
    producer_storage: ?ProducerStorage = null,
    source_annotation_failed: bool = false,
    source_header_diagnostics: []Diagnostic = &.{},
    prelude_unit: u32 = 0,
    nominals: std.ArrayList(Nominal) = .empty,
    contracts: std.ArrayList(Contract) = .empty,
    contract_predicates: std.ArrayList(T.Obligation) = .empty,
    contract_members: std.ArrayList(ContractMember) = .empty,
    implementations: std.ArrayList(Implementation) = .empty,
    implementation_predicates: std.ArrayList(T.Obligation) = .empty,
    implementation_members: std.ArrayList(ImplementationMember) = .empty,
    member_templates: std.ArrayList(PI.MemberTemplate) = .empty,
    selected_proofs: std.ArrayList(PI.SelectedProof) = .empty,
    selected_members: std.ArrayList(ImplementationMember) = .empty,
    selected_edges: std.ArrayList(u32) = .empty,
    selected_uses: std.ArrayList(PI.SelectedUse) = .empty,
    checking_implementation: ?u32 = null,
    implementation_bindings: std.AutoHashMapUnmanaged(BindingId, u32) = .empty,
    implementation_member_sources: std.AutoHashMapUnmanaged(u32, ast.Id) = .empty,
    implementation_member_states: std.AutoHashMapUnmanaged(u32, enum { visiting, ready }) = .empty,
    active_evidence: std.ArrayList(struct { contract: Identity, arguments: T.List }) = .empty,
    implementation_order: std.ArrayList(u32) = .empty,
    provisional_equations: std.ArrayList(struct { declaration: u32, arguments: T.List, variables: []const T.Id, rows: []const T.Effects.Id }) = .empty,
    member_sources: std.AutoHashMapUnmanaged(u32, ast.Id) = .empty,
    member_states: std.AutoHashMapUnmanaged(u32, enum { visiting, ready }) = .empty,

    associated_depth: usize = 0,
    defer_associated: bool = false,
    has_associated_types: bool = false,
    contract_states: std.AutoHashMapUnmanaged(u32, enum { visiting, ready }) = .empty,
    contract_depth: usize = 0,
    constructors: std.ArrayList(Constructor) = .empty,
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
    demand_once: []bool = &.{},
    demand_types: []T.Id = &.{},
    demand_binary_left_types: []T.Id = &.{},
    demand_binary_left: []bool = &.{},
    loop_exits: std.ArrayList(LoopExit) = .empty,
    statement_arms: std.ArrayList(StatementArm) = .empty,
    loop_stack: std.ArrayList(LoopFrame) = .empty,
    cases: std.ArrayList(ast.Id) = .empty,
    associated: std.ArrayList(Associated) = .empty,

    fn collectModuleHeaders(self: *Engine, imports: []const ImportedBinding, headers: []const SourceHeader, catalogs: []const ImportedCatalog, source_catalogs: []const SourceCatalog, allow_imports: bool, inherited_fixities: []const ImportedFixity) T.Error!void {
        const allocator = self.allocator;
        const tree = self.tree;
        const pool = self.pool;
        const unit = self.unit;
        try self.dataHeaders();
        try self.contractHeaders();
        var local_fixities: std.AutoHashMapUnmanaged(symbols.Symbol, void) = .empty;
        defer local_fixities.deinit(allocator);
        for (inherited_fixities) |fixity| try self.catalogs.overrides.put(allocator, fixity.operator, .{ .target = fixity.target, .named = fixity.named, .external = fixity.external });
        for (tree.roots.items) |id| {
            if (tree.node(id).tag == .data_decl or tree.node(id).tag == .type_alias_decl or tree.node(id).tag == .contract_decl or tree.node(id).tag == .implementation_decl or tree.node(id).tag == .effect_decl or tree.node(id).tag == .effect_type_decl) continue;
            if (allow_imports and (tree.node(id).tag == .import_decl or tree.node(id).tag == .export_decl)) continue;
            if (tree.node(id).tag == .fixity_decl) {
                const fixity = tree.fixity(id);
                if (fixity.attributes.len != 0) try self.diagnostic(.unsupported_attribute, id);
                if (local_fixities.contains(fixity.operator)) try self.diagnostic(.duplicate_name, id) else {
                    try local_fixities.put(allocator, fixity.operator, {});
                    try self.catalogs.overrides.put(allocator, fixity.operator, .{ .target = fixity.target, .named = fixity.named });
                }
                continue;
            }
            if (tree.node(id).tag != .value_decl) {
                try self.diagnostic(.unsupported, id);
                continue;
            }
            const declaration = tree.valueDecl(id);
            if (self.catalogs.globals.contains(declaration.name)) {
                try self.diagnostic(.duplicate_name, id);
                continue;
            }
            const binding = try self.addBinding(.{ .private = tree.declarationTraits(id).private, .name = declaration.name, .declaration = id, .owner = id, .kind = .global, .capability_flow = if (tree.node(declaration.body).tag == .lambda and declaration.attributes.len == 0) @import("capability_flow.zig").source(tree, declaration.body) else .unknown, .named_function = tree.node(declaration.body).tag == .lambda and declaration.attributes.len == 0, .ty = try self.types.fresh() });
            try self.catalogs.globals.put(allocator, declaration.name, binding);
            try self.global_states.put(allocator, binding, .{});
            self.resolved[id] = binding;
        }
        for (catalogs) |imported| try self.importCatalog(imported);
        for (source_catalogs) |imported| try self.importCatalog(imported);
        for (imports) |imported| {
            if (self.source_validation) try self.importHeader(.{ .name = imported.name, .namespace = imported.namespace, .member = imported.member, .target = imported.target, .capability_flow = imported.interface.capability_flow, .capability_parameters = imported.interface.capability_parameters, .named_function = imported.interface.named_function, .origin = imported.origin, .expose = imported.expose }) else try self.importBinding(imported);
        }
        for (headers) |imported| try self.importHeader(imported);
        try self.effectHeaders();
        for (self.bindings.items) |*binding| if (binding.kind == .global and binding.named_function) {
            binding.capability_flow = self.capabilityFlowContract(tree.valueDecl(binding.declaration).body, tree.valueDecl(binding.declaration).annotation);
            const parameters = self.capabilityParameters(tree.valueDecl(binding.declaration).body, tree.valueDecl(binding.declaration).annotation);
            if (binding.capability_flow == .unknown or parameters.kind == .product) binding.capability_parameters = parameters;
            if (binding.capability_parameters.inputInvokes()) self.has_input_invocations = true;
        };
        for (self.bindings.items, 0..) |binding, index| {
            if (binding.kind != .global or !binding.named_function or !binding.capability_parameters.present()) continue;
            const root = @import("capability_contract_source.zig").derive(allocator, &self.capability_store, tree, pool, tree.valueDecl(binding.declaration).body, binding.capability_parameters) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.CapabilityAnalysisLimit, error.InvalidCapabilityContract => continue,
            };
            if (root) |value| try self.capability_roots.append(allocator, .{ .binding = @intCast(index), .root = value });
        }
        try self.dataBodies();
        self.prepareOpaqueStorage();
        for (0..self.contracts.items.len) |index| try self.resolveContract(@intCast(index));
        for (self.contract_members.items, 0..) |member, index| {
            if (member.contract.unit != unit or member.root == 0) continue;
            const source = self.member_sources.get(@intCast(index)).?;
            const normalized = try self.normalizeAssociated(member.root, source, false);
            try self.validateMemberRequirements(@intCast(index));
            if (member.kind == .value) {
                if (self.types.node(self.types.head(normalized, 0)).tag != .function) {
                    try self.diagnostic(.annotation_kind_mismatch, source);
                } else self.contract_members.items[index].root = normalized;
            }
        }
        for (tree.roots.items) |id| if (tree.node(id).tag == .value_decl) {
            const name = tree.valueDecl(id).name;
            const text = pool.get(name);
            const dot = std.mem.findScalarLast(u8, text, '.') orelse continue;
            const path = self.textCatalogKey(text[0..dot]) orelse continue;
            const contract_index = self.catalogs.contract_names.get(path) orelse continue;
            const member_name = pool.lookup(text[dot + 1 ..]) orelse continue;
            if (self.memberIndex(self.contracts.items[contract_index], member_name) != null) try self.diagnostic(.duplicate_name, id);
        };
        try self.implementationHeaders();
        try self.implementationCoherence();
        try self.implementationBodies();
        try self.memberTemplates();
        try self.indexAssociated();
        for (inherited_fixities) |fixity| {
            if (local_fixities.contains(fixity.operator)) continue;
            const binding = if (fixity.external) |external| self.catalogs.external_targets.get(external) else try self.catalogBinding(fixity.target);
            if (binding == null) try self.diagnostic(.unknown_name, fixity.origin);
        }
        // A source declaration named namespace.member cannot silently hide an
        // imported declaration whose identity is the same numeric pair.
        for (tree.roots.items) |id| if (tree.node(id).tag == .value_decl) {
            if (self.qualifiedKey(tree.valueDecl(id).name)) |key|
                if (self.catalogs.qualified.contains(key)) try self.diagnostic(.duplicate_name, id);
        };
    }
    fn validateModuleBodies(self: *Engine) T.Error!void {
        const allocator = self.allocator;
        const tree = self.tree;
        const pool = self.pool;
        const unit = self.unit;
        if (self.source_validation) self.source_header_diagnostics = try self.diagnostics.toOwnedSlice(allocator);
        const source_issue = if (tree.diagnostics.items.len == 0) try source_operators.validate(allocator, tree, pool, self) else null;
        if (source_issue) |issue| {
            // Source lowering fails before inference. Do not publish unrelated
            // provisional type failures collected while building declaration tables.
            deinitDiagnosticPayloads(allocator, self.diagnostics.items);
            self.diagnostics.clearRetainingCapacity();
            try self.diagnostics.append(allocator, .{ .code = switch (issue.code) {
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
                .private_access => .private_access,
                .unknown_constructor => .unknown_constructor,
                .sealed_effect => .sealed_effect,
                .call_arity => .call_arity,
                .requests_scope => .requests_scope,
                .yield_scope => .yield_scope,
                .break_scope => .break_scope,
                .continue_scope => .continue_scope,
                .literal_required => .literal_required,
                .product_index_literal => .product_index_literal,
                .nesting_limit => .nesting_limit,
            }, .node = issue.node, .span = .{ .start = issue.point, .end = issue.point }, .symbol = issue.symbol, .implicit_type_witness = issue.implicit_type_witness, .source_terminator = issue.terminator, .numeric_literal = issue.numeric_literal });
        }
        if (tree.diagnostics.items.len == 0 and source_issue == null and !self.source_annotation_failed) {
            for (tree.roots.items) |id| if (tree.node(id).tag == .fixity_decl) {
                if (try self.catalogBinding(tree.fixity(id).target)) |binding| self.resolved[id] = binding else try self.diagnostic(.unknown_name, id);
            };
        }
        if (!self.source_validation and tree.diagnostics.items.len == 0 and source_issue == null) {
            for (tree.roots.items) |id| if (tree.node(id).tag == .value_decl and self.resolved[id] != 0) {
                self.root_global = self.resolved[id];
                try self.inferGlobal(self.resolved[id]);
            };
            for (self.implementations.items) |declaration| {
                if (declaration.identity.unit != unit) continue;
                for (self.implementation_members.items[declaration.members.start..][0..declaration.members.len]) |member| {
                    if (member.kind != .value) continue;
                    self.root_global = member.target.binding;
                    try self.inferGlobal(member.target.binding);
                }
            }
            self.root_global = 0;
            // A known entry resolver cannot omit a source protocol method. Do not
            // instantiate unrelated latent closure predicates here: their exact
            // operand evidence belongs to the demanded retained body instance.
            for (tree.roots.items) |id| if (tree.node(id).tag == .value_decl and tree.valueDecl(id).exported and self.resolved[id] != 0) {
                const principal = self.bindings.items[self.resolved[id]].scheme;
                for (self.obligations.items[principal.obligations.start..][0..principal.obligations.len]) |constraint| {
                    if (constraint.kind != .resolver_dispatch) continue;
                    const owner = self.types.node(try self.types.resolve(constraint.ty, 0));
                    if (owner.tag != .resolver) continue;
                    const token = self.types.node(try self.types.resolve(owner.a, 0));
                    if (token.tag != .type_constructor) continue;
                    if (!self.catalogs.associated_members.contains(.{ .identity = .{ .unit = token.a, .decl = token.b }, .member = constraint.name })) try self.diagnostic(.missing_member, constraint.source);
                }
            };
            try self.finish();
            try self.finishSelectedUses();
            try self.finishReflection();
            try self.finishHoles();
            // Typed producer bodies publish callback no-store authority even when
            // the producer itself never invokes them. Imported calls cannot infer
            // this proof from a callable type or a result mask.
            var scoped_types = false;
            for (self.types.nodes.items) |node| if (node.tag == .scoped) {
                scoped_types = true;
                break;
            };
            if (scoped_types and self.diagnostics.items.len == 0) {
                for (0..self.bindings.items.len) |index| {
                    const binding = self.bindings.items[index];
                    if (binding.kind != .global or !binding.named_function or binding.capability_flow != .unknown or binding.declaration == 0 or (binding.capability_parameters.present() and binding.capability_parameters.kind != .product)) continue;
                    // Contract member headers have no implementation body. Their
                    // selected implementations publish their own callback proof.
                    if (tree.node(binding.declaration).tag != .value_decl) continue;
                    const declaration = tree.valueDecl(binding.declaration);
                    const arity = @import("capability_flow.zig").parameterArity(tree, declaration.body, declaration.annotation);
                    if (arity != 0) _ = try self.publishInputFunction(@intCast(index), arity);
                }
            }
            if (self.types.has_usage_types and self.diagnostics.items.len == 0) try @import("usage_check.zig").validate(self);
            if (self.diagnostics.items.len == 0) try self.validateVisibility();
        }
    }
    fn qualifiedKey(self: *const Engine, name: symbols.Symbol) ?Qualified {
        const text = self.pool.get(name);
        const separator = std.mem.findScalar(u8, text, '.') orelse return null;
        return .{ .namespace = self.pool.lookup(text[0..separator]) orelse return null, .member = self.pool.lookup(text[separator + 1 ..]) orelse return null };
    }
    fn qualifiedBinding(self: *Engine, name: symbols.Symbol) Allocator.Error!?BindingId {
        if (self.catalogs.qualified_symbols.get(name)) |found| return found.binding;
        const key = self.qualifiedKey(name) orelse return null;
        const binding = self.catalogs.qualified.get(key) orelse return null;
        try self.catalogs.qualified_symbols.put(self.allocator, name, .{ .namespace = key.namespace, .binding = binding });
        return binding;
    }
    fn globalBinding(self: *Engine, name: symbols.Symbol) Allocator.Error!?BindingId {
        // Resolve source value paths through the lexical root first. Fixity
        // declarations use the separate immutable global catalog below.
        const text = self.pool.get(name);
        if (std.mem.findScalar(u8, text, '.')) |separator| {
            if (self.pool.lookup(text[0..separator])) |root|
                if (self.lookup(root) != null) return null;
        }
        return self.catalogBinding(name);
    }
    fn catalogBinding(self: *Engine, name: symbols.Symbol) Allocator.Error!?BindingId {
        if (self.catalogs.globals.get(name)) |binding| return binding;
        return self.qualifiedBinding(name);
    }
    pub fn sourceDuplicateName(self: *const Engine) ?ast.Id {
        if (self.source_validation) {
            // Constructor and value declarations share a source namespace.
            // Collection fails before any expression is lowered.
            for (self.constructors.items[1..]) |constructor| if (constructor.identity.unit == self.unit) {
                if (self.catalogs.globals.get(constructor.name)) |binding| {
                    const declaration = self.bindings.items[binding].declaration;
                    return if (self.tree.span(declaration).start < self.tree.span(constructor.identity.decl).start) declaration else constructor.identity.decl;
                }
            };
        }
        const diagnostics = if (self.source_validation) self.source_header_diagnostics else self.diagnostics.items;
        for (diagnostics) |issue| if (issue.code == .duplicate_name and self.tree.node(issue.node).tag == .value_decl) {
            const name = self.tree.valueDecl(issue.node).name;
            if (self.catalogs.globals.get(name)) |binding| return self.bindings.items[binding].declaration;
        };
        return null;
    }
    pub fn sourceTypeApplication(self: *const Engine, symbol: symbols.Symbol) bool {
        if (self.catalogs.nominal_names.get(self.catalogKey(symbol))) |nominal| return self.nominals.items[nominal].patterns.len != 0;
        if (self.catalogOperationTemplate(symbol)) |template| {
            const family = self.effect_templates.items[template].family;
            return self.effect_families.items[family].patterns.len != 0;
        }
        return false;
    }
    pub fn sourceNonCallableEffect(self: *const Engine, symbol: symbols.Symbol) bool {
        if (self.catalogs.effect_family_names.get(self.catalogKey(symbol))) |family| return !self.effect_families.items[family].callable;
        if (self.catalogs.globals.contains(symbol) or self.catalogs.qualified.contains(self.catalogKey(symbol)) or self.catalogOperationTemplate(symbol) != null) return false;
        const text = self.pool.get(symbol);
        var prefix_end = text.len;
        while (std.mem.findScalarLast(u8, text[0..prefix_end], '.')) |separator| {
            prefix_end = separator;
            const prefix = text[0..prefix_end];
            const key: Qualified = if (std.mem.findScalar(u8, prefix, '.')) |dot| .{ .namespace = self.pool.lookup(prefix[0..dot]) orelse continue, .member = self.pool.lookup(prefix[dot + 1 ..]) orelse continue } else .{ .namespace = 0, .member = self.pool.lookup(prefix) orelse continue };
            if (self.catalogs.effect_family_names.get(key)) |family| return !self.effect_families.items[family].callable;
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
        self.mark_depth += 1;
        defer {
            self.mark_depth -= 1;
            self.types.rollback(point);
            deinitDiagnosticPayloads(self.allocator, self.diagnostics.items[diagnostic_count..]);
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
    pub fn sourcePrivateConstructor(self: *const Engine, symbol: symbols.Symbol) bool {
        const nominal = self.catalogs.nominal_names.get(self.catalogKey(symbol)) orelse return false;
        return self.nominals.items[nominal].is_opaque and self.nominals.items[nominal].identity.unit != self.unit;
    }
    pub fn sourceConstructorExists(self: *const Engine, symbol: symbols.Symbol) bool {
        return self.catalogs.constructor_names.contains(self.catalogKey(symbol));
    }
    pub fn sourceRecordFieldExists(self: *const Engine, symbol: symbols.Symbol, field: symbols.Symbol) ?bool {
        const constructor = self.catalogs.constructor_names.get(self.catalogKey(symbol)) orelse return null;
        const payload = self.constructors.items[constructor].payload;
        if (!self.constructors.items[constructor].declared_record) return null;
        if (payload == 0) return false;
        const record = self.types.node(payload);
        if (record.tag != .record) return null;
        for (0..record.b) |index| if (self.types.recordField(record, index).name == field) return true;
        return false;
    }
    pub fn sourceRecordTarget(self: *Engine, symbol: symbols.Symbol) T.Error!enum { missing, record, other } {
        if (self.catalogs.constructor_names.get(self.catalogKey(symbol))) |constructor| {
            const definition = self.constructors.items[constructor];
            if (definition.declared_record or (self.nominals.items[definition.nominal].is_opaque and self.types.node(definition.payload).tag == .record)) return .record;
            return .other;
        }
        const value = try self.catalogBinding(symbol) != null or self.catalogOperationTemplate(symbol) != null or self.catalogs.effect_family_names.contains(self.catalogKey(symbol));
        return if (value) .other else .missing;
    }
    pub fn sourceMissingRecordField(self: *const Engine, symbol: symbols.Symbol, fields: []const ast.Id) ?symbols.Symbol {
        const constructor = self.catalogs.constructor_names.get(self.catalogKey(symbol)) orelse return null;
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
        const fixity = self.catalogs.overrides.get(symbol) orelse return false;
        return !fixity.named;
    }
    pub fn sourceOperatorTargetExists(self: *Engine, name: symbols.Symbol) Allocator.Error!bool {
        if (try self.catalogBinding(name) != null) return true;
        const key = self.catalogKey(name);
        return self.catalogs.constructor_names.contains(key) or self.catalogOperationTemplate(name) != null;
    }
    pub fn sourceQualifiedExists(self: *const Engine, namespace: symbols.Symbol, member: symbols.Symbol) bool {
        const key: Qualified = .{ .namespace = namespace, .member = member };
        return self.catalogs.qualified.contains(key) or self.catalogs.nominal_names.contains(key) or self.catalogs.effect_family_names.contains(key) or self.catalogs.effect_operation_names.contains(key);
    }
    pub fn sourceValueExists(self: *Engine, name: symbols.Symbol) Allocator.Error!bool {
        if (try self.sourceOperatorTargetExists(name)) return true;
        const key = self.catalogKey(name);
        if (self.catalogs.nominal_names.contains(key) or self.catalogs.effect_family_names.contains(key)) return true;
        const text = self.pool.get(name);
        const root = if (std.mem.findScalar(u8, text, '.')) |separator| self.pool.lookup(text[0..separator]) orelse return false else name;
        if (root != name) {
            const suffix = text[self.pool.get(root).len + 1 ..];
            const end = std.mem.findScalar(u8, suffix, '.') orelse suffix.len;
            if (self.pool.lookup(suffix[0..end])) |member|
                if (self.catalogs.qualified.contains(.{ .namespace = root, .member = member })) return true;
        }
        if (root != name and try self.sourceOperatorTargetExists(root)) return true;
        if (self.catalogs.nominal_names.contains(.{ .namespace = 0, .member = root }) or self.catalogs.effect_family_names.contains(.{ .namespace = 0, .member = root })) return true;
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
    const SourceImplementationScope = struct { implementation: ?u32, closed: bool, implicit_rows: bool };
    pub fn sourceImplementationStart(self: *Engine, id: ast.Id) T.Error!SourceImplementationScope {
        const saved: SourceImplementationScope = .{ .implementation = self.checking_implementation, .closed = self.closed_type_variables, .implicit_rows = self.implicit_row_parameters };
        if (!self.source_validation) return saved;
        const index = self.catalogs.implementation_names.get(.{ .namespace = 0, .member = self.tree.node(id).a }) orelse return saved;
        try self.implementationScope(self.implementations.items[index]);
        self.checking_implementation = index;
        self.closed_type_variables = true;
        self.implicit_row_parameters = false;
        return saved;
    }
    pub fn sourceImplementationEnd(self: *Engine, saved: SourceImplementationScope) void {
        if (!self.source_validation) return;
        self.type_env.clearRetainingCapacity();
        self.row_env.clearRetainingCapacity();
        self.checking_implementation = saved.implementation;
        self.closed_type_variables = saved.closed;
        self.implicit_row_parameters = saved.implicit_rows;
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
    fn producerCapability(self: *const Engine, target: ExternalTarget) ?ProducerCapability {
        const resolver = self.producer_capabilities orelse return null;
        return resolver.lookup(resolver.context, target);
    }
    fn importHeader(self: *Engine, imported: SourceHeader) T.Error!void {
        std.debug.assert(self.source_validation);
        const key: Qualified = .{ .namespace = imported.namespace, .member = imported.member };
        if (imported.expose and ((imported.namespace == 0 and self.catalogs.globals.contains(imported.name)) or (imported.namespace != 0 and self.catalogs.qualified.contains(key)))) {
            try self.diagnostic(.duplicate_name, imported.origin);
            return;
        }
        const binding = self.catalogs.external_targets.get(imported.target) orelse fresh: {
            const fresh = try self.addBinding(.{ .name = if (imported.namespace == 0) imported.name else imported.member, .declaration = imported.origin, .owner = imported.origin, .kind = .external, .ty = try self.types.fresh(), .capability_flow = imported.capability_flow, .capability_parameters = imported.capability_parameters, .named_function = imported.named_function, .external = imported.target });
            try self.catalogs.external_targets.put(self.allocator, imported.target, fresh);
            break :fresh fresh;
        };
        if (!imported.expose) return;
        if (imported.namespace == 0) try self.catalogs.globals.put(self.allocator, imported.name, binding) else try self.catalogs.qualified.put(self.allocator, key, binding);
    }
    fn importBinding(self: *Engine, imported: ImportedBinding) T.Error!void {
        const key: Qualified = .{ .namespace = imported.namespace, .member = imported.member };
        if (imported.expose and ((imported.namespace == 0 and self.catalogs.globals.contains(imported.name)) or
            (imported.namespace != 0 and self.catalogs.qualified.contains(key))))
        {
            try self.diagnostic(.duplicate_name, imported.origin);
            return;
        }
        var binding = self.catalogs.external_targets.get(imported.target);
        if (binding == null) {
            binding = try self.importScheme(imported.interface, imported.target, if (imported.namespace == 0) imported.name else imported.member, imported.origin, 0);
            if (binding == null) return;
        }
        if (!imported.expose) return;
        if (imported.namespace == 0) try self.catalogs.globals.put(self.allocator, imported.name, binding.?) else try self.catalogs.qualified.put(self.allocator, key, binding.?);
    }
    /// Copies one producer scheme. Schemes it shares are imported first, as
    /// bindings of their own, so shared uses keep pointing at shared schemes.
    fn importScheme(self: *Engine, interface: SchemeInterface, target: ExternalTarget, name: symbols.Symbol, origin: ast.Id, depth: usize) T.Error!?BindingId {
        if (self.catalogs.external_targets.get(target)) |existing| return existing;
        const range = interface.scheme.obligations;
        const constraints = interface.obligations[range.start..][0..range.len];
        var callees: std.ArrayList(BindingId) = .empty;
        defer callees.deinit(self.allocator);
        for (constraints) |constraint| if (constraint.kind == .callee_use) {
            const callee_interface = interface.callees.interface(constraint.identity.decl);
            if (callee_interface == null or depth >= 256) {
                try self.diagnostic(.nesting_limit, origin);
                return null;
            }
            const callee = try self.importScheme(callee_interface.?, .{ .unit = target.unit, .binding = constraint.identity.decl }, 0, origin, depth + 1) orelse return null;
            try callees.append(self.allocator, callee);
        };
        const copier_arena = try self.scratch_pool.take(self.allocator);
        defer self.scratch_pool.give(copier_arena);
        var copier_buffer: [4096]u8 align(@alignOf(usize)) = undefined;
        var copier_scratch: std.heap.BufferFirstAllocator = .init(&copier_buffer, copier_arena.allocator());
        var copier: SchemeCopier = .{ .allocator = copier_scratch.allocator(), .source = interface.types, .destination = &self.types };
        defer copier.deinit();
        var variables: std.ArrayList(T.Id) = .empty;
        defer variables.deinit(self.allocator);
        for (copier.source.list(interface.scheme.variables)) |old| {
            const fresh = try self.types.fresh();
            try copier.mapping.put(copier.allocator, copier.source.head(old, 0), fresh);
            try variables.append(self.allocator, fresh);
        }
        const row_variables = try copier.quantifiedRows(interface.scheme.row_variables);
        const closed_rows = try copier.quantifiedRows(interface.scheme.closed_rows);
        const root = try copier.copy(interface.scheme.root, 0);
        const start: u32 = @intCast(self.obligations.items.len);
        var shared: usize = 0;
        for (constraints) |constraint| {
            var identity = constraint.identity;
            if (constraint.kind == .callee_use) {
                identity = .{ .unit = self.unit, .decl = callees.items[shared] };
                shared += 1;
            }
            try self.obligations.append(self.allocator, .{ .ty = try copier.copy(constraint.ty, 0), .kind = constraint.kind, .source = origin, .name = constraint.name, .result = if (constraint.result == 0) 0 else try copier.copy(constraint.result, 0), .other = if (constraint.other == 0) 0 else try copier.copy(constraint.other, 0), .signature = if (constraint.signature == 0) 0 else try copier.copy(constraint.signature, 0), .operator = constraint.operator, .identity = identity, .explicit = constraint.explicit, .qualification_span = constraint.qualification_span, .qualification_unit = constraint.qualification_unit });
        }
        const principal: T.Scheme = .{ .root = root, .variables = try self.types.saveList(variables.items), .row_variables = row_variables, .closed_rows = closed_rows, .generative = try copier.copyGenerative(interface.scheme.generative), .obligations = .{ .start = start, .len = @intCast(self.obligations.items.len - start) } };
        const binding = try self.addBinding(.{ .name = name, .declaration = origin, .owner = origin, .kind = .external, .ty = root, .scheme = principal, .capability_flow = interface.capability_flow, .capability_parameters = interface.capability_parameters, .named_function = interface.named_function, .external = target });
        if (interface.proof_contract) |source_header| {
            source_header.signature().validate(self.allocator, self.proof_body.values.limits) catch |err| {
                _ = try self.proofHeaderFailure(err, origin);
                return null;
            };
            var header = try source_header.clone(self.allocator);
            errdefer header.deinit(self.allocator);
            try self.proof_contracts.append(self.allocator, .{ .binding = binding, .header = header, .parameters = &.{} });
        }
        const recipe_source = interface.capability_source orelse CapabilitySource{ .callees = interface.callees, .binding = interface.producer_binding };
        if (recipe_source.callees.capabilityContract(recipe_source.binding, interface.capability_parameters.arity())) |header| contract: {
            const checkpoint = self.capability_store.mark();
            var committed = false;
            defer if (!committed) self.capability_store.rollback(checkpoint);
            var arguments: [16]u32 = undefined;
            for (0..header.arity) |index| arguments[index] = self.capability_store.append(self.allocator, .{ .tag = .parameter, .a = @intCast(index) }) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.CapabilityAnalysisLimit => break :contract,
                else => return error.TypeLimit,
            };
            const capability_root = self.capability_store.instantiate(self.allocator, header, arguments[0..header.arity]) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.CapabilityAnalysisLimit => break :contract,
                else => return error.TypeLimit,
            };
            self.capability_store.view().validate(capability_root, header.arity, true) catch break :contract;
            try self.capability_roots.append(self.allocator, .{ .binding = binding, .root = capability_root });
            committed = true;
        }
        self.bindings.items[binding].summary = try self.summarize(principal);
        try self.catalogs.external_targets.put(self.allocator, target, binding);
        return binding;
    }

    fn pendingAllocator(self: *Engine) Allocator.Error!Allocator {
        if (self.pending_arena == null) self.pending_arena = try self.scratch_pool.take(self.allocator);
        return self.pending_arena.?.allocator();
    }
    fn appendPending(self: *Engine, item: PendingObligation) Allocator.Error!void {
        var value = item;
        value.scope = self.qualification_scope;
        value.method_member = value.method_member or (value.value.kind == .receiver and !value.value.explicit);
        try self.pending.append(try self.pendingAllocator(), value);
        self.counters.obligations_appended += 1;
        self.counters.pending_peak = @max(self.counters.pending_peak, self.pending.items.len);
    }
    pub fn usageConflict(self: *Engine, code: Code, id: ast.Id, first: ast.Id, declaration: ast.Id) Allocator.Error!void {
        try self.diagnostic(code, id);
        const index = self.diagnostics.items.len - 1;
        const message = self.diagnostics.items[index].message();
        self.diagnostics.items[index].detail = try self.allocator.print("{s}; first conflicting use at byte {d}, owner declared at byte {d}", .{ message, self.tree.span(first).start, self.tree.span(declaration).start });
    }
    pub fn usageLoanFootprint(self: *Engine, source: ast.Id, region: T.Id) T.Error!bool {
        var remaining: usize = 65_536;
        return try self.valueFootprint(source, .{ .loan = region }, &.{}, &remaining, 0) orelse try self.scopeFootprintDepth(self.expr_types[source], 0, &remaining, &.{}, .{ .loan = region });
    }
    pub fn usageDiagnostic(self: *Engine, code: Code, id: ast.Id) Allocator.Error!void {
        try self.diagnostic(code, id);
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
        if (origin == 0 and (code == .type_mismatch or code == .effect_mismatch or code == .missing_associated)) {
            const issue = &self.diagnostics.items[self.diagnostics.items.len - 1];
            const node = self.tree.node(id);
            switch (node.tag) {
                .apply => {
                    issue.contexts = .{
                        .{ .kind = .callee, .span = self.tree.span(node.a) },
                        .{ .kind = .argument, .span = self.tree.span(node.b) },
                    };
                    issue.context_len = 2;
                },
                .binary => {
                    issue.contexts = .{
                        .{ .kind = .left_operand, .span = self.tree.span(node.b) },
                        .{ .kind = .right_operand, .span = self.tree.span(node.c) },
                    };
                    issue.context_len = 2;
                },
                else => {},
            }
        }
        switch (code) {
            .missing_implementation, .incompatible_implementation, .recursive_evidence, .recursive_associated_type, .associated_limit, .overlapping_implementation, .ambiguous_qualified => try self.explainImplementation(id),
            else => {},
        }
    }
    fn spellStable(self: *Engine, builder: *dispatch_explanation.Builder, root: T.Id) Allocator.Error![]u8 {
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(self.allocator);
        @import("../reuse/type_display.zig").appendStable(self, &bytes, root) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                builder.truncated = true;
            },
        };
        return builder.own(&bytes);
    }
    fn explainImplementation(self: *Engine, source: ast.Id) Allocator.Error!void {
        const trace = self.implementation_trace;
        if (trace.contract.unit == 0 or trace.request != source) return;
        var builder: dispatch_explanation.Builder = .{ .allocator = self.allocator, .truncated = trace.truncated };
        defer builder.deinit();
        for (trace.candidates[0..trace.len]) |candidate| {
            const declaration = for (self.implementations.items) |known| {
                if (std.meta.eql(known.identity, candidate.identity)) break known;
            } else continue;
            const path = self.purity_origins.name(self.allocator, declaration.identity.unit, self.unit) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => null,
            };
            defer if (path) |bytes| self.allocator.free(bytes);
            var span = declaration.origin_span;
            if (self.purity_origins.source_available) |available| {
                if (!available(self.purity_origins.context, declaration.identity.unit)) span = null;
            } else if (declaration.identity.unit != self.unit) {
                span = null;
            }
            const origin = try builder.makeOrigin(self.pool.get(declaration.name), path, span);
            builder.addOrigin(null, candidate.outcome, origin);
        }
        for (trace.steps[0..trace.step_len]) |step| {
            var member: ?[]const u8 = null;
            if (step.member != 0) member = self.pool.get(step.member);
            try builder.addStep(member, try self.spellStable(&builder, step.ty), step.outcome);
        }
        const contract = self.contracts.items[self.catalogs.contract_identities.get(trace.contract) orelse return];
        const result = try builder.finish(null, self.pool.get(contract.name));
        const issue = &self.diagnostics.items[self.diagnostics.items.len - 1];
        if (issue.explanation) |old| old.deinit(self.allocator);
        issue.explanation = result;
    }
    fn constrain(self: *Engine, a: T.Id, b: T.Id, id: ast.Id) T.Error!void {
        var left = a;
        var right = b;
        if (self.implementations.items.len != 0) {
            left = try self.normalizeAssociated(left, id, false);
            right = try self.normalizeAssociated(right, id, false);
        }
        if (self.has_associated_types and self.qualifications.items.len != 0) {
            left = try self.rewriteGiven(left, 0);
            right = try self.rewriteGiven(right, 0);
        }
        try self.constrainRaw(left, right, id);
    }
    fn constrainRaw(self: *Engine, left: T.Id, right: T.Id, id: ast.Id) T.Error!void {
        self.constrainEquationRoot(left, right, id) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.InfiniteType => try self.diagnostic(.infinite_type, id),
            error.TypeMismatch => try self.diagnostic(.type_mismatch, id),
            error.InfiniteEffect => try self.diagnostic(.infinite_effect, id),
            error.EffectMismatch => {
                try self.diagnostic(.effect_mismatch, id);
                const display = @import("../reuse/type_display.zig");
                const application = self.tree.node(id).tag == .apply;
                const first = self.types.node(self.types.head(left, 0));
                const second = self.types.node(self.types.head(right, 0));
                var expected: std.ArrayList(u8) = .empty;
                defer expected.deinit(self.allocator);
                var actual: std.ArrayList(u8) = .empty;
                defer actual.deinit(self.allocator);
                var arguments = application and first.tag == .function and second.tag == .function;
                if (arguments) {
                    try display.append(self, &expected, first.a);
                    try display.append(self, &actual, second.a);
                    // A call can also fail in its result or own effect row.
                    // Only blame the argument when the rendered pair differs.
                    if (std.mem.eql(u8, expected.items, actual.items)) arguments = false;
                }
                if (!arguments) {
                    expected.clearRetainingCapacity();
                    actual.clearRetainingCapacity();
                    try display.append(self, &expected, left);
                    try display.append(self, &actual, right);
                }
                var detail: std.ArrayList(u8) = .empty;
                defer detail.deinit(self.allocator);
                try display.text(self, &detail, if (arguments) "Effect rows do not match; expected argument: " else "Effect rows do not match; one side: ");
                try display.text(self, &detail, expected.items);
                try display.text(self, &detail, if (arguments) "; actual argument: " else "; other side: ");
                try display.text(self, &detail, actual.items);
                self.diagnostics.items[self.diagnostics.items.len - 1].detail = try detail.toOwnedSlice(self.allocator);
            },
            error.TypeLimit => try self.diagnostic(.nesting_limit, id),
        };
    }
    fn constrainEquationRoot(self: *Engine, left: T.Id, right: T.Id, source: ast.Id) T.Error!void {
        if (self.implementations.items.len == 0 or !self.types.has_projections) return self.types.unify(left, right);
        var pairs: std.AutoHashMapUnmanaged(u64, void) = .empty;
        defer pairs.deinit(self.allocator);
        return self.constrainEquation(left, right, source, 0, &pairs);
    }
    fn constrainEquation(self: *Engine, left: T.Id, right: T.Id, source: ast.Id, depth: usize, pairs: *std.AutoHashMapUnmanaged(u64, void)) T.Error!void {
        const first = self.types.head(left, 0);
        const second = self.types.head(right, 0);
        if (first == second) return;
        const key = (@as(u64, first) << 32) | second;
        if (pairs.contains(key)) return;
        try self.constrainEquationPair(left, right, source, depth, pairs);
        try pairs.put(self.allocator, key, {});
    }
    fn constrainEquationPair(self: *Engine, left: T.Id, right: T.Id, source: ast.Id, depth: usize, pairs: *std.AutoHashMapUnmanaged(u64, void)) T.Error!void {
        if (self.implementations.items.len == 0 or !self.types.has_projections) return self.types.unify(left, right);
        if (depth >= 256 or !try self.associatedStep(source)) return error.TypeLimit;
        const first = self.types.node(self.types.head(left, 0));
        const second = self.types.node(self.types.head(right, 0));
        if (first.tag == .function and second.tag == .function) {
            try self.constrainEquation(first.a, second.a, source, depth + 1, pairs);
            try self.constrainEquation(first.b, second.b, source, depth + 1, pairs);
            return self.types.unifyEffects(first.c, second.c);
        }
        if (first.tag == second.tag) switch (first.tag) {
            .array, .list, .cursor => return self.constrainEquation(first.a, second.a, source, depth + 1, pairs),
            .product => {
                if (first.b != second.b) return error.TypeMismatch;
                const old = try self.allocator.dupe(T.Id, self.types.list(.{ .start = first.a, .len = first.b }));
                defer self.allocator.free(old);
                const actuals = try self.allocator.dupe(T.Id, self.types.list(.{ .start = second.a, .len = second.b }));
                defer self.allocator.free(actuals);
                for (old, actuals) |before, after| try self.constrainEquation(before, after, source, depth + 1, pairs);
                return;
            },
            else => {},
        };
        var before = try self.normalizeAssociated(left, source, false);
        var after = try self.normalizeAssociated(right, source, false);
        if (self.qualifications.items.len != 0) {
            before = try self.rewriteGiven(before, 0);
            after = try self.rewriteGiven(after, 0);
        }
        return self.types.unify(before, after);
    }
    fn rewriteGiven(self: *Engine, root: T.Id, depth: usize) T.Error!T.Id {
        if (depth >= 256) return error.TypeLimit;
        const Given = @import("../eval/given_equations.zig");
        var equations: std.ArrayList(Given.Equation) = .empty;
        defer equations.deinit(self.allocator);
        for (self.qualifications.items) |boundary| {
            if (boundary.owner != self.current) continue;
            for (self.declared_obligations.items[boundary.clauses.start..][0..boundary.clauses.len]) |equation| {
                if (equation.kind != .type_eq) continue;
                try self.types.chargeProjection();
                try equations.append(self.allocator, .{ .left = equation.ty, .right = equation.result });
            }
        }
        var rewrite: Given.Rewrite = .{ .store = &self.types, .equations = equations.items };
        return rewrite.normalize(root);
    }
    fn constrainEffects(self: *Engine, left: T.Effects.Id, right: T.Effects.Id, source: ast.Id) T.Error!void {
        self.types.unifyEffects(left, right) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.EffectMismatch => try self.diagnostic(.effect_mismatch, source),
            error.InfiniteEffect => try self.diagnostic(.infinite_effect, source),
            else => return err,
        };
    }
    fn stagingEffects(self: *Engine, row: T.Effects.Id, source: ast.Id) T.Error!void {
        // The code value keeps its exact latent row. This execution may occur
        // in a surrounding computation with additional effects.
        const arrow = try self.types.functionWithEffects(T.unit, T.unit, row);
        const use = self.types.node(try self.types.openCovariant(arrow));
        try self.constrainEffects(use.c, self.ambient, source);
    }
    fn invocation(self: *Engine, parameter: T.Id, result: T.Id) T.Error!T.Id {
        return self.types.functionWithEffects(parameter, result, self.ambient);
    }
    fn invocationBinary(self: *Engine, left: T.Id, right: T.Id, result: T.Id) T.Error!T.Id {
        return self.invocation(left, try self.invocation(right, result));
    }
    fn pureExpression(self: *Engine, id: ast.Id, required: T.Id) T.Error!T.Id {
        const saved = self.ambient;
        self.ambient = try self.types.freshEffects();
        defer self.ambient = saved;
        var result: T.Id = undefined;
        if (required != 0) result = try self.contextualLambda(id, required) else result = try self.expression(id);
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
        _ = try self.certifiedLambdaType(source, raw_type, parent_row);
    }
    fn certifiedLambdaType(self: *Engine, source: ast.Id, raw_type: T.Id, parent_row: T.Effects.Id) T.Error!T.Id {
        const function = self.types.node(try self.types.resolve(raw_type, 0));
        const tail = self.types.row(function.c).tail;
        if (tail != .variable) return raw_type;
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
        if (decision.closed_rows.len == 0) return decision.root;
        try self.row_sources.put(self.allocator, tail.variable, source);
        try self.recordClosedRows(self.current, decision.closed_rows);
        return decision.root;
    }
    fn addBinding(self: *Engine, value: Binding) Allocator.Error!BindingId {
        if (value.capability_parameters.inputInvokes()) self.has_input_invocations = true;
        const id: BindingId = @intCast(self.bindings.items.len);
        try self.bindings.append(self.allocator, value);
        if (self.tree.has_typed_staging and (value.kind == .local or value.kind == .parameter)) try self.staging_bindings.put(self.allocator, id, self.staging_depth);
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
        var globals = self.catalogs.globals.iterator();
        while (globals.next()) |entry| {
            const text = self.pool.get(entry.key_ptr.*);
            const dot = std.mem.findScalarLast(u8, text, '.') orelse continue;
            const head = text[0..dot];
            const member = self.pool.lookup(text[dot + 1 ..]) orelse continue;
            var identity: ?Identity = null;
            if (self.pool.lookup(head)) |name| if (self.catalogs.nominal_names.get(.{ .namespace = 0, .member = name })) |index| {
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
                try self.catalogs.associated_members.put(self.allocator, .{ .identity = owner, .member = member }, index);
                if (operator != .none) try self.catalogs.associated_ops.put(self.allocator, .{ .identity = owner, .operator = operator }, index);
            }
        }
    }
    const AssociatedChoice = union(enum) { absent, waiting, selected: struct { ty: T.Id, binding: BindingId } };
    fn tryAssociated(self: *Engine, identity: Identity, member: symbols.Symbol, operator: T.Operator, left: T.Id, right: T.Id, source: ast.Id) T.Error!AssociatedChoice {
        const index = (if (member == 0) self.catalogs.associated_ops.get(.{ .identity = identity, .operator = operator }) else self.catalogs.associated_members.get(.{ .identity = identity, .member = member })) orelse return .absent;
        const binding = self.associated.items[index].binding;
        if (!try self.prepareSelectedGlobal(binding)) return .waiting;
        const point = self.types.mark();
        const pending = self.pending.items.len;
        self.mark_depth += 1;
        defer self.mark_depth -= 1;
        const function = try self.instantiate(binding, source);
        const result = try self.types.fresh();
        const expected = try self.invocationBinary(left, right, result);
        self.types.unify(function, expected) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.TypeMismatch, error.InfiniteType, error.EffectMismatch, error.InfiniteEffect => {
                self.types.rollback(point);
                self.pending.shrinkRetainingCapacity(pending);
                return .absent;
            },
            error.TypeLimit => return err,
        };
        self.dispatch_signatures[source] = expected;
        return .{ .selected = .{ .ty = result, .binding = binding } };
    }
    fn dispatch(self: *Engine, left: T.Id, right: T.Id, member: symbols.Symbol, operator: T.Operator, source: ast.Id, direct: bool) T.Error!?T.Id {
        const a = try self.types.resolve(left, 0);
        const b = try self.types.resolve(right, 0);
        const an = self.types.node(a);
        const bn = self.types.node(b);
        if (an.tag == .variable or bn.tag == .variable) return null;
        if (self.identityOf(a)) |identity| switch (try self.tryAssociated(identity, member, operator, a, b, source)) {
            .absent => {},
            .waiting => return null,
            .selected => |choice| {
                if (direct) self.resolved[source] = choice.binding;
                self.dispatch_side = .left;
                return choice.ty;
            },
        };
        const scalar_a = an.tag == .u32 or an.tag == .f32 or an.tag == .boolean;
        const scalar_b = bn.tag == .u32 or bn.tag == .f32 or bn.tag == .boolean;
        if (member == 0 and scalar_a and scalar_b and an.tag == bn.tag) {
            const comparison = operator == .equal or operator == .not_equal or operator == .less or operator == .less_equal or operator == .greater or operator == .greater_equal;
            const equality = operator == .equal or operator == .not_equal;
            const integer = operator == .rem or operator == .bit_and or operator == .bit_or or operator == .bit_xor or operator == .shift_left or operator == .shift_right;
            if (an.tag == .boolean and !equality or an.tag == .f32 and integer) {
                try self.diagnostic(.ambiguous_operator, source);
                try self.explainDispatch(a, b, member, operator, true);
                return try self.types.fresh();
            }
            self.dispatch_side = .builtin;
            return if (comparison) T.boolean else a;
        }
        if (self.identityOf(b)) |identity| switch (try self.tryAssociated(identity, member, operator, a, b, source)) {
            .absent => {},
            .waiting => return null,
            .selected => |choice| {
                if (direct) self.resolved[source] = choice.binding;
                self.dispatch_side = .right;
                return choice.ty;
            },
        };
        if (member != 0) return null;
        try self.diagnostic(.ambiguous_operator, source);
        try self.explainDispatch(a, b, member, operator, false);
        return try self.types.fresh();
    }
    /// Explains the dispatch whose diagnostic was just appended, from the
    /// member tables and operand types alone. Dispatch tried the left
    /// operand's owner, then (for an operator without a member name) the
    /// built-in scalar operation, then a different right owner.
    fn explainDispatch(self: *Engine, left: T.Id, right: T.Id, member: symbols.Symbol, operator: T.Operator, scalar_rejected: bool) T.Error!void {
        var builder: dispatch_explanation.Builder = .{ .allocator = self.allocator };
        defer builder.deinit();
        try self.explainOperand(&builder, .left, left, member, operator);
        if (scalar_rejected) {
            builder.add(.builtin, null, .unsupported_scalar);
        } else if (!try self.sameOwner(left, right)) try self.explainOperand(&builder, .right, right, member, operator);
        try self.attachExplanation(&builder, member, operator);
    }
    /// Explains a selected binary member whose result just conflicted with
    /// its use. Candidates before the selected one are listed as rejected.
    fn explainSelected(self: *Engine, left: T.Id, right: T.Id, member: symbols.Symbol, operator: T.Operator, side: dispatch_explanation.Side) T.Error!void {
        var builder: dispatch_explanation.Builder = .{ .allocator = self.allocator };
        defer builder.deinit();
        if (side == .right) try self.explainOperand(&builder, .left, left, member, operator);
        builder.add(side, try self.spellType(&builder, if (side == .right) right else left), .result_mismatch);
        try self.attachExplanation(&builder, member, operator);
    }
    fn explainResult(self: *Engine, destination: T.Id, member: symbols.Symbol) T.Error!void {
        var builder: dispatch_explanation.Builder = .{ .allocator = self.allocator };
        defer builder.deinit();
        try self.explainOperand(&builder, .destination, destination, member, .none);
        try self.attachExplanation(&builder, member, .none);
    }
    /// Member access searches its receiver's owner only.
    fn explainReceiver(self: *Engine, receiver: T.Id, member: symbols.Symbol) T.Error!void {
        var builder: dispatch_explanation.Builder = .{ .allocator = self.allocator };
        defer builder.deinit();
        builder.add(.receiver, try self.spellType(&builder, receiver), .no_member);
        try self.attachExplanation(&builder, member, .none);
    }
    fn attachExplanation(self: *Engine, builder: *dispatch_explanation.Builder, member: symbols.Symbol, operator: T.Operator) T.Error!void {
        const spelled = if (member != 0) self.pool.get(member) else dispatch_explanation.operatorMember(operator);
        const explanation = try builder.finish(dispatch_explanation.operatorSymbol(operator), spelled);
        const issue = &self.diagnostics.items[self.diagnostics.items.len - 1];
        if (issue.explanation) |old| old.deinit(self.allocator);
        issue.explanation = explanation;
    }
    fn sameOwner(self: *Engine, left: T.Id, right: T.Id) T.Error!bool {
        const a = self.identityOf(try self.types.resolve(left, 0)) orelse return false;
        const b = self.identityOf(try self.types.resolve(right, 0)) orelse return false;
        return std.meta.eql(a, b);
    }
    fn spellType(self: *Engine, builder: *dispatch_explanation.Builder, ty: T.Id) T.Error![]u8 {
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(self.allocator);
        try @import("../reuse/type_display.zig").append(self, &bytes, try self.types.resolve(ty, 0));
        return builder.own(&bytes);
    }
    fn explainOperand(self: *Engine, builder: *dispatch_explanation.Builder, side: dispatch_explanation.Side, ty: T.Id, member: symbols.Symbol, operator: T.Operator) T.Error!void {
        const resolved = try self.types.resolve(ty, 0);
        const outcome: dispatch_explanation.Outcome = if (self.types.node(resolved).tag == .variable)
            .unknown_operand
        else if (self.identityOf(resolved)) |identity| (if ((if (member == 0) self.catalogs.associated_ops.get(.{ .identity = identity, .operator = operator }) else self.catalogs.associated_members.get(.{ .identity = identity, .member = member })) != null) .incompatible else .no_member) else .no_member;
        builder.add(side, try self.spellType(builder, resolved), outcome);
    }
    fn resultDispatch(self: *Engine, input: T.Id, expected: T.Id, member: symbols.Symbol, source: ast.Id, direct: bool) T.Error!?T.Id {
        const destination = try self.types.resolve(expected, 0);
        const identity = self.identityOf(destination) orelse return null;
        const index = self.catalogs.associated_members.get(.{ .identity = identity, .member = member }) orelse return null;
        const binding = self.associated.items[index].binding;
        if (!try self.prepareSelectedGlobal(binding)) return null;
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
        const selected = self.catalogs.associated_members.get(.{ .identity = .{ .unit = token.a, .decl = token.b }, .member = constraint.name }) orelse return false;
        const binding = self.associated.items[selected].binding;
        if (!try self.prepareSelectedGlobal(binding)) return false;
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
        var type_index = self.type_env.items.len;
        while (type_index != 0) {
            type_index -= 1;
            const entry = self.type_env.items[type_index];
            if (entry.name != name) continue;
            const leaf = self.types.node(self.types.head(entry.ty, 0));
            if ((leaf.tag == .bound and leaf.b == 1) or (leaf.tag == .rigid and leaf.c == 1)) break;
            try self.diagnostic(.annotation_kind_mismatch, if (type_index < self.inherited_types) self.annotation_binding else source);
            return self.types.freshEffects();
        }
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
                if (name.len != 0 and (std.ascii.isLower(name[0]) or name[0] == '_') and std.mem.findScalar(u8, name, '.') == null) _ = try self.typeVariable(node.a, id);
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
            .type_usage => try self.collectAnnotationNames(node.b, depth + 1),
            .type_field, .type_binder => {
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
        return self.catalogs.nominal_identities.get(identity);
    }
    fn copyNominal(self: *Engine, producer: DeclarationCatalog, source_index: u32) T.Error!u32 {
        var source = producer.nominals[source_index];
        if (source.is_opaque) if (self.producer_storage) |resolver| {
            if (resolver.lookup(resolver.context, source.identity)) |storage| source.storage = storage;
        };
        if (self.nominalIndex(source.identity)) |index| return index;
        const copier_arena = try self.scratch_pool.take(self.allocator);
        defer self.scratch_pool.give(copier_arena);
        var copier_buffer: [4096]u8 align(@alignOf(usize)) = undefined;
        var copier_scratch: std.heap.BufferFirstAllocator = .init(&copier_buffer, copier_arena.allocator());
        var copier: SchemeCopier = .{ .allocator = copier_scratch.allocator(), .source = producer.types, .destination = &self.types };
        defer copier.deinit();
        var variables: std.ArrayList(T.Id) = .empty;
        defer variables.deinit(self.allocator);
        for (producer.types.list(source.variables)) |old| {
            const fresh = try self.types.fresh();
            try copier.mapping.put(copier.allocator, producer.types.head(old, 0), fresh);
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
        try self.nominals.append(self.allocator, .{ .affine = source.affine, .has_usage = source.has_usage, .closed_storage = source.closed_storage, .private = source.private, .is_opaque = source.is_opaque, .storage = source.storage, .identity = source.identity, .name = source.name, .variables = quantified, .parameters = try self.types.saveList(parameters.items), .patterns = patterns, .parameter_names = names, .alias_rows = alias_rows, .alias = if (source.alias == 0) 0 else try copier.copy(source.alias, 0) });
        if (source.has_usage) self.types.has_usage_types = true;
        try self.catalogs.nominal_identities.put(self.allocator, source.identity, index);
        var constructors: std.ArrayList(T.Id) = .empty;
        defer constructors.deinit(self.allocator);
        for (producer.types.list(source.constructors)) |old| {
            if (source.is_opaque) continue;
            const ctor = producer.constructors[old];
            const own: u32 = @intCast(self.constructors.items.len);
            try self.constructors.append(self.allocator, .{ .identity = ctor.identity, .nominal = index, .tag = ctor.tag, .name = ctor.name, .scheme = .{ .root = try copier.copy(ctor.scheme.root, 0), .variables = quantified }, .payload = if (ctor.payload == 0) 0 else try copier.copy(ctor.payload, 0), .declared_record = ctor.declared_record });
            try self.catalogs.constructor_identities.put(self.allocator, ctor.identity, own);
            try constructors.append(self.allocator, own);
        }
        self.nominals.items[index].constructors = try self.types.saveList(constructors.items);
        return index;
    }
    fn copyEffectFamily(self: *Engine, producer: DeclarationCatalog, source_index: u32) T.Error!u32 {
        const source = producer.effect_families[source_index];
        if (self.catalogs.effect_family_identities.get(source.identity)) |known| return known;
        const copier_arena = try self.scratch_pool.take(self.allocator);
        defer self.scratch_pool.give(copier_arena);
        var copier_buffer: [4096]u8 align(@alignOf(usize)) = undefined;
        var copier_scratch: std.heap.BufferFirstAllocator = .init(&copier_buffer, copier_arena.allocator());
        var copier: SchemeCopier = .{ .allocator = copier_scratch.allocator(), .source = producer.types, .destination = &self.types };
        defer copier.deinit();
        var variables: std.ArrayList(T.Id) = .empty;
        defer variables.deinit(self.allocator);
        for (producer.types.list(source.variables)) |old| {
            const fresh = try self.types.fresh();
            try copier.mapping.put(copier.allocator, producer.types.head(old, 0), fresh);
            try variables.append(self.allocator, fresh);
        }
        var parameters: std.ArrayList(T.Id) = .empty;
        defer parameters.deinit(self.allocator);
        for (producer.types.list(source.parameters)) |old| try parameters.append(self.allocator, try copier.copy(old, 0));
        if (self.effect_families.items.len == std.math.maxInt(u32)) return error.TypeLimit;
        const family: u32 = @intCast(self.effect_families.items.len);
        const patterns = try self.copyParameterPatterns(producer.parameter_patterns, source.patterns, &copier);
        try self.effect_families.append(self.allocator, .{ .private = source.private, .identity = source.identity, .name = source.name, .callable = source.callable, .variables = try self.types.saveList(variables.items), .parameters = try self.types.saveList(parameters.items), .patterns = patterns, .parameter_names = try self.types.saveList(producer.types.list(source.parameter_names)) });
        try self.catalogs.effect_family_identities.put(self.allocator, source.identity, family);
        var operations: std.ArrayList(T.Id) = .empty;
        defer operations.deinit(self.allocator);
        for (producer.types.list(source.operations)) |old| {
            const template = producer.effect_templates[old];
            if (self.effect_templates.items.len == std.math.maxInt(u32)) return error.TypeLimit;
            const index: u32 = @intCast(self.effect_templates.items.len);
            try self.effect_templates.append(self.allocator, .{ .identity = template.identity, .family = family, .name = template.name, .parameter = try copier.copy(template.parameter, 0), .result = try copier.copy(template.result, 0) });
            try self.catalogs.effect_members.put(self.allocator, .{ .family = family, .member = template.name }, index);
            try self.catalogs.effect_template_identities.put(self.allocator, template.identity, index);
            try operations.append(self.allocator, index);
        }
        self.effect_families.items[family].operations = try self.types.saveList(operations.items);
        return family;
    }
    fn importCatalog(self: *Engine, imported: anytype) T.Error!void {
        const producer = if (@TypeOf(imported) == SourceCatalog) imported.producer else imported.catalog();
        if (imported.kind == .catalog) {
            for (1..producer.nominals.len) |index| {
                if (producer.nominals[index].private) continue;
                _ = try self.copyNominal(producer, @intCast(index));
            }
            for (1..producer.effect_families.len) |index| {
                if (producer.effect_families[index].private) continue;
                _ = try self.copyEffectFamily(producer, @intCast(index));
            }
            for (0..producer.contracts.len) |index| {
                if (producer.contracts[index].private) continue;
                _ = try self.copyContract(producer, @intCast(index));
            }
            for (producer.implementations, 0..) |implementation, index| {
                if (implementation.private) continue;
                _ = try self.copyImplementation(producer, @intCast(index));
            }
            for (producer.associated) |method| {
                const definition = if (@TypeOf(imported) == SourceCatalog) imported.declarations[method.binding] else imported.declaration(method.binding);
                if (definition.private) continue;
                const target = definition.external orelse ExternalTarget{ .unit = producer.unit, .binding = method.binding };
                // A member the catalog's module itself imported keeps its
                // producer's capability facts, never the alias's copy.
                const owned: ?ProducerCapability = if (definition.external != null) self.producerCapability(target) else null;
                if (@TypeOf(imported) == SourceCatalog or self.source_validation) {
                    const flow = if (owned) |facts| facts.flow else definition.capability_flow;
                    const parameters = if (owned) |facts| facts.parameters else definition.capability_parameters;
                    try self.importHeader(.{ .target = target, .capability_flow = flow, .capability_parameters = parameters, .named_function = definition.named_function, .origin = imported.origin, .expose = false });
                } else {
                    var interface = imported.interface(method.binding);
                    if (owned) |facts| {
                        interface.capability_flow = facts.flow;
                        interface.capability_parameters = facts.parameters;
                        interface.capability_source = facts.recipe orelse CapabilitySource{ .callees = .none, .binding = 0 };
                    }
                    try self.importBinding(.{ .target = target, .interface = interface, .origin = imported.origin, .expose = false });
                }
                const binding = self.catalogs.external_targets.get(target).?;
                var present = false;
                for (self.associated.items) |prior| if (prior.identity.unit == method.identity.unit and prior.identity.decl == method.identity.decl and prior.member == method.member and prior.binding == binding) {
                    present = true;
                    break;
                };
                if (!present) {
                    const index: u32 = @intCast(self.associated.items.len);
                    try self.associated.append(self.allocator, .{ .identity = method.identity, .member = method.member, .operator = method.operator, .binding = binding });
                    try self.catalogs.associated_members.put(self.allocator, .{ .identity = method.identity, .member = method.member }, index);
                    if (method.operator != .none) try self.catalogs.associated_ops.put(self.allocator, .{ .identity = method.identity, .operator = method.operator }, index);
                }
            }
            return;
        }
        if (imported.kind == .effect_family) {
            const family = try self.copyEffectFamily(producer, imported.index);
            const effect_key: Qualified = .{ .namespace = imported.namespace, .member = imported.name };
            if (self.catalogs.effect_family_names.contains(effect_key) or self.catalogs.nominal_names.contains(effect_key)) try self.diagnostic(.duplicate_name, imported.origin) else try self.catalogs.effect_family_names.put(self.allocator, effect_key, family);
            if (self.effect_families.items[family].callable) {
                const operations = self.types.list(self.effect_families.items[family].operations);
                if (operations.len != 1) return error.TypeLimit;
                try self.catalogs.effect_operation_names.put(self.allocator, effect_key, operations[0]);
            }
            return;
        }
        const key: Qualified = .{ .namespace = imported.namespace, .member = imported.name };
        if (imported.kind == .contract) {
            const index = try self.copyContract(producer, imported.index);
            if (self.catalogs.contract_names.contains(key) or self.catalogs.nominal_names.contains(key)) try self.diagnostic(.duplicate_name, imported.origin) else try self.catalogs.contract_names.put(self.allocator, key, index);
            return;
        }
        if (imported.kind == .implementation) {
            const index = try self.copyImplementation(producer, imported.index);
            if (self.catalogs.implementation_names.contains(key)) try self.diagnostic(.duplicate_name, imported.origin) else try self.catalogs.implementation_names.put(self.allocator, key, index);
            return;
        }
        if (imported.kind == .nominal) {
            const index = try self.copyNominal(producer, imported.index);
            if (self.catalogs.nominal_names.contains(key)) try self.diagnostic(.duplicate_name, imported.origin) else try self.catalogs.nominal_names.put(self.allocator, key, index);
        } else {
            const source = producer.constructors[imported.index];
            _ = try self.copyNominal(producer, source.nominal);
            const index = self.catalogs.constructor_identities.get(source.identity).?;
            if (self.catalogs.constructor_names.contains(key)) try self.diagnostic(.duplicate_name, imported.origin) else try self.catalogs.constructor_names.put(self.allocator, key, index);
        }
    }
    fn prepareOpaqueStorage(self: *Engine) void {
        var remaining: usize = 1_000_000;
        for (self.nominals.items, 0..) |nominal, index| {
            if (!nominal.is_opaque or nominal.identity.unit != self.unit) continue;
            self.nominals.items[index].storage = @import("../backend/opaque_storage.zig").infer(.{ .store = &self.types }, self.nominals.items, self.constructors.items, @intCast(index), &remaining);
        }
    }
    fn validateVisibility(self: *Engine) T.Error!void {
        var private = false;
        for (self.bindings.items) |binding| private = private or binding.private;
        for (self.nominals.items) |nominal| private = private or nominal.private;
        for (self.effect_families.items) |family| private = private or family.private;
        for (self.contracts.items) |contract| private = private or contract.private;
        if (!private) return;
        const visibility = @import("../reuse/module_visibility.zig");
        var scan = try visibility.Scan.init(self.allocator, .{ .store = &self.types }, self.nominals.items, self.effect_families.items, self.effect_templates.items);
        defer scan.deinit();
        for (self.contracts.items) |contract| if (contract.private) try scan.blocked.put(self.allocator, contract.identity, {});
        for (self.bindings.items) |binding| {
            if (binding.kind != .global or binding.private) continue;
            var allowed = try scan.allowed(binding.scheme.root);
            if (self.tree.node(binding.declaration).tag != .value_decl) continue;
            for (self.tree.list(self.tree.valueDecl(binding.declaration).where)) |predicate| {
                const name = self.tree.node(predicate).a;
                if (self.catalogs.contract_names.get(self.catalogKey(name))) |index| if (self.contracts.items[index].private) {
                    allowed = false;
                };
            }
            for (self.obligations.items[binding.scheme.obligations.start..][0..binding.scheme.obligations.len]) |requirement| {
                if (requirement.kind == .callee_use and requirement.identity.decl < self.bindings.items.len and self.bindings.items[requirement.identity.decl].private) allowed = false;
                inline for (.{ "ty", "result", "other", "signature" }) |field| {
                    if (!try scan.allowed(@field(requirement, field))) allowed = false;
                }
            }
            if (!allowed) try self.diagnostic(.private_identity_escape, binding.declaration);
        }
        for (self.nominals.items) |nominal| {
            if (nominal.identity.unit != self.unit or nominal.private) continue;
            var allowed = try scan.allowed(nominal.alias);
            for (self.types.list(nominal.parameters)) |parameter| if (!try scan.allowed(parameter)) {
                allowed = false;
            };
            if (nominal.is_opaque) {
                if (!allowed) try self.diagnostic(.private_identity_escape, nominal.declaration);
                continue;
            }
            for (self.types.list(nominal.constructors)) |index| if (!try scan.allowed(self.constructors.items[index].payload)) {
                allowed = false;
            };
            if (!allowed) try self.diagnostic(.private_identity_escape, nominal.declaration);
        }
        for (self.contracts.items) |contract| {
            if (contract.identity.unit != self.unit or contract.private) continue;
            var allowed = true;
            for (self.contract_predicates.items[contract.predicates.start..][0..contract.predicates.len]) |requirement| {
                inline for (.{ "ty", "result", "other", "signature" }) |field| {
                    if (!try scan.allowed(@field(requirement, field))) allowed = false;
                }
            }
            for (self.contract_members.items[contract.members.start..][0..contract.members.len]) |member| if (!try scan.allowed(member.root)) {
                allowed = false;
            };
            const body = self.tree.node(self.tree.node(contract.declaration).b);
            for (self.tree.list(.{ .start = body.a, .len = body.b })) |predicate| {
                if (self.catalogs.contract_names.get(self.catalogKey(self.tree.node(predicate).a))) |index| if (self.contracts.items[index].private) {
                    allowed = false;
                };
            }
            if (!allowed) try self.diagnostic(.private_identity_escape, contract.declaration);
        }
        for (self.implementations.items) |implementation| {
            if (implementation.identity.unit != self.unit or implementation.private) continue;
            var allowed = !scan.blocked.contains(implementation.contract);
            for (self.types.list(implementation.head)) |root| if (!try scan.allowed(root)) {
                allowed = false;
            };
            for (self.implementation_members.items[implementation.members.start..][0..implementation.members.len]) |member| if (!try scan.allowed(member.root)) {
                allowed = false;
            };
            for (self.implementation_predicates.items[implementation.predicates.start..][0..implementation.predicates.len]) |predicate| {
                if (scan.blocked.contains(predicate.identity)) allowed = false;
                inline for (.{ "ty", "other", "result", "signature" }) |field| if (!try scan.allowed(@field(predicate, field))) {
                    allowed = false;
                };
            }
            if (!allowed) try self.diagnostic(.private_identity_escape, implementation.declaration);
        }
        for (self.effect_families.items) |family| {
            if (family.identity.unit != self.unit or family.private) continue;
            var allowed = true;
            for (self.types.list(family.operations)) |index| {
                const operation = self.effect_templates.items[index];
                if (!try scan.allowed(operation.parameter) or !try scan.allowed(operation.result)) allowed = false;
            }
            if (!allowed) try self.diagnostic(.private_identity_escape, family.identity.decl);
        }
    }
    fn constructorDiagnostic(self: *Engine, symbol: symbols.Symbol, source: ast.Id) Allocator.Error!void {
        if (self.catalogs.nominal_names.get(self.catalogKey(symbol))) |index| {
            if (self.nominals.items[index].is_opaque and self.nominals.items[index].identity.unit != self.unit) return self.diagnostic(.private_access, source);
        }
        try self.diagnostic(.unknown_constructor, source);
    }
    fn constructorType(self: *Engine, index: u32) T.Error!T.Id {
        return self.constructorUse(index, false);
    }
    fn copyContract(self: *Engine, producer: DeclarationCatalog, source_index: u32) T.Error!u32 {
        const source = producer.contracts[source_index];
        self.has_associated_types = self.has_associated_types or source.members.len != 0;
        if (self.catalogs.contract_identities.get(source.identity)) |known| return known;
        const copier_arena = try self.scratch_pool.take(self.allocator);
        defer self.scratch_pool.give(copier_arena);
        var copier_buffer: [4096]u8 align(@alignOf(usize)) = undefined;
        var copier_scratch: std.heap.BufferFirstAllocator = .init(&copier_buffer, copier_arena.allocator());
        var copier: SchemeCopier = .{ .allocator = copier_scratch.allocator(), .source = producer.types, .destination = &self.types, .associated = source.members.len != 0 };
        defer copier.deinit();
        var variables: std.ArrayList(T.Id) = .empty;
        defer variables.deinit(self.allocator);
        for (producer.types.list(source.variables)) |old| {
            const fresh = try self.types.fresh();
            try copier.mapping.put(copier.allocator, producer.types.head(old, 0), fresh);
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
        var row_parameters: std.ArrayList(T.Id) = .empty;
        defer row_parameters.deinit(self.allocator);
        for (producer.types.list(source.row_parameters)) |old| try row_parameters.append(self.allocator, try copier.copyRow(old, 0));
        const member_start: u32 = @intCast(self.contract_members.items.len);
        for (producer.contract_members[source.members.start..][0..source.members.len]) |old| {
            var member = old;
            member.root = try copier.copy(old.root, 0);
            try self.contract_members.append(self.allocator, member);
        }
        const index: u32 = @intCast(self.contracts.items.len);
        const patterns = try self.copyParameterPatterns(producer.parameter_patterns, source.patterns, &copier);
        try self.contracts.append(self.allocator, .{ .private = source.private, .identity = source.identity, .name = source.name, .variables = try self.types.saveList(variables.items), .parameters = try self.types.saveList(parameters.items), .patterns = patterns, .parameter_names = try self.types.saveList(producer.types.list(source.parameter_names)), .row_variables = rows, .predicates = .{ .start = start, .len = source.predicates.len }, .members = .{ .start = member_start, .len = source.members.len }, .requires_implementation = source.requires_implementation, .row_parameter_names = try self.types.saveList(producer.types.list(source.row_parameter_names)), .row_parameters = try self.types.saveList(row_parameters.items) });
        try self.catalogs.contract_identities.put(self.allocator, source.identity, index);
        return index;
    }
    fn copyImplementation(self: *Engine, producer: DeclarationCatalog, source_index: u32) T.Error!u32 {
        const source = producer.implementations[source_index];
        for (self.implementations.items, 0..) |prior, index| if (std.meta.eql(prior.identity, source.identity)) return @intCast(index);
        if (self.implementations.items.len >= 4096) return error.TypeLimit;
        for (producer.contracts, 0..) |contract, index| if (std.meta.eql(contract.identity, source.contract)) {
            _ = try self.copyContract(producer, @intCast(index));
            break;
        };
        var copier: SchemeCopier = .{ .allocator = self.allocator, .source = producer.types, .destination = &self.types, .associated = true };
        defer copier.deinit();
        var variables: std.ArrayList(T.Id) = .empty;
        defer variables.deinit(self.allocator);
        for (producer.types.list(source.variables)) |old| {
            const fresh = try self.types.fresh();
            try copier.mapping.put(copier.allocator, producer.types.head(old, 0), fresh);
            try variables.append(self.allocator, fresh);
        }
        const rows = try copier.quantifiedRows(source.row_variables);
        var head: std.ArrayList(T.Id) = .empty;
        defer head.deinit(self.allocator);
        for (producer.types.list(source.head)) |root| try head.append(self.allocator, try copier.copy(root, 0));
        var row_parameters: std.ArrayList(T.Id) = .empty;
        defer row_parameters.deinit(self.allocator);
        for (producer.types.list(source.row_parameters)) |row| try row_parameters.append(self.allocator, try copier.copyRow(row, 0));
        const predicate_start: u32 = @intCast(self.implementation_predicates.items.len);
        for (producer.implementation_predicates[source.predicates.start..][0..source.predicates.len]) |old| {
            var value = old;
            inline for (.{ "ty", "other", "result", "signature" }) |field| @field(value, field) = try copier.copy(@field(old, field), 0);
            value.source = 0;
            try self.implementation_predicates.append(self.allocator, value);
        }
        const member_start: u32 = @intCast(self.implementation_members.items.len);
        for (producer.implementation_members[source.members.start..][0..source.members.len]) |old| {
            var value = old;
            value.root = try copier.copy(old.root, 0);
            try self.implementation_members.append(self.allocator, value);
        }
        const index: u32 = @intCast(self.implementations.items.len);
        try self.implementations.append(self.allocator, .{ .origin_span = source.origin_span, .private = source.private, .identity = source.identity, .name = source.name, .contract = source.contract, .head = try self.types.saveList(head.items), .variables = try self.types.saveList(variables.items), .parameter_names = try self.types.saveList(producer.types.list(source.parameter_names)), .row_variables = rows, .row_parameters = try self.types.saveList(row_parameters.items), .row_parameter_names = try self.types.saveList(producer.types.list(source.row_parameter_names)), .predicates = .{ .start = predicate_start, .len = source.predicates.len }, .members = .{ .start = member_start, .len = source.members.len } });
        return index;
    }
    fn implementationRowNames(self: *Engine, id: ast.Id, names: *std.ArrayList(u32), depth: usize) T.Error!void {
        if (id == 0) return;
        if (depth >= 256) return error.TypeLimit;
        if (!try self.associatedStep(id)) return;
        const node = self.tree.node(id);
        switch (node.tag) {
            .type_function, .type_effect => {
                try self.implementationRowNames(node.a, names, depth + 1);
                try self.implementationRowNames(node.b, names, depth + 1);
                if (node.tag == .type_function) try self.implementationRowNames(node.c, names, depth + 1);
            },
            .type_apply => {
                try self.implementationRowNames(node.a, names, depth + 1);
                try self.implementationRowNames(node.b, names, depth + 1);
            },
            .group, .type_demand => try self.implementationRowNames(node.a, names, depth + 1),
            .type_product, .type_array, .type_record => for (self.tree.children(id)) |child| try self.implementationRowNames(child, names, depth + 1),
            .type_field => try self.implementationRowNames(node.b, names, depth + 1),
            .effect_row => {
                if (node.c != 0) {
                    const name = self.tree.node(node.c).a;
                    if (!inList(names.items, name)) try names.append(self.allocator, name);
                }
                for (self.tree.list(.{ .start = node.a, .len = node.b })) |label| try self.implementationRowNames(label, names, depth + 1);
            },
            else => {},
        }
    }
    fn implementationScope(self: *Engine, declaration: Implementation) T.Error!void {
        for (self.types.list(declaration.parameter_names), self.types.list(declaration.variables)) |name, variable| try self.type_env.append(self.allocator, .{ .name = name, .ty = variable });
        for (self.types.list(declaration.row_parameter_names), self.types.list(declaration.row_parameters)) |name, row| try self.row_env.append(self.allocator, .{ .name = name, .row = row });
    }
    fn implementationHeaders(self: *Engine) T.Error!void {
        const headers_defer = self.defer_associated;
        self.defer_associated = true;
        defer self.defer_associated = headers_defer;
        for (self.tree.roots.items) |id| {
            if (self.tree.node(id).tag != .implementation_decl) continue;
            if (!try self.associatedStep(id)) return;
            if (self.implementations.items.len >= 4096) {
                try self.diagnostic(.associated_limit, id);
                return;
            }
            const syntax = self.tree.implementation(id);
            var duplicate = self.catalogs.globals.contains(syntax.name) or self.catalogs.nominal_names.contains(.{ .namespace = 0, .member = syntax.name }) or self.catalogs.contract_names.contains(.{ .namespace = 0, .member = syntax.name }) or self.catalogs.implementation_names.contains(.{ .namespace = 0, .member = syntax.name });
            for (self.implementations.items) |prior| {
                if (prior.identity.unit == self.unit and prior.name == syntax.name) duplicate = true;
            }
            if (duplicate) {
                try self.diagnostic(.duplicate_name, id);
                continue;
            }
            const predicate = self.tree.node(syntax.head);
            const contract_index = self.catalogs.contract_names.get(self.catalogKey(predicate.a)) orelse {
                try self.diagnostic(.unknown_name, syntax.head);
                continue;
            };
            const contract = self.contracts.items[contract_index];
            if (!contract.requires_implementation) {
                try self.diagnostic(.invalid_constraint, id);
                continue;
            }
            self.type_env.clearRetainingCapacity();
            self.row_env.clearRetainingCapacity();
            for (self.tree.list(syntax.parameters)) |parameter| _ = try self.parameterAnnotation(parameter, 0);
            const details = self.tree.extra.items[predicate.c..][0..3];
            const arguments = self.tree.list(.{ .start = details[0], .len = details[1] });
            if (predicate.b != 0 or details[2] != 0 or arguments.len != contract.parameters.len) {
                try self.diagnostic(.associated_arity, syntax.head);
                continue;
            }
            var row_names: std.ArrayList(u32) = .empty;
            defer row_names.deinit(self.allocator);
            for (arguments) |argument| try self.implementationRowNames(argument, &row_names, 0);
            var at: usize = 0;
            while (at < self.type_env.items.len) {
                const entry = self.type_env.items[at];
                if (!inList(row_names.items, entry.name)) {
                    at += 1;
                    continue;
                }
                _ = self.type_env.orderedRemove(at);
                try self.row_env.append(self.allocator, .{ .name = entry.name, .row = try self.types.freshEffects() });
            }
            var variables: std.ArrayList(T.Id) = .empty;
            defer variables.deinit(self.allocator);
            var names: std.ArrayList(u32) = .empty;
            defer names.deinit(self.allocator);
            var row_parameters: std.ArrayList(u32) = .empty;
            defer row_parameters.deinit(self.allocator);
            var declared_row_names: std.ArrayList(u32) = .empty;
            defer declared_row_names.deinit(self.allocator);
            for (self.type_env.items) |entry| {
                try variables.append(self.allocator, entry.ty);
                try names.append(self.allocator, entry.name);
            }
            for (self.row_env.items) |entry| {
                try row_parameters.append(self.allocator, entry.row);
                try declared_row_names.append(self.allocator, entry.name);
            }
            const saved_closed = self.closed_type_variables;
            const saved_implicit = self.implicit_row_parameters;
            const saved_defer = self.defer_associated;
            self.closed_type_variables = true;
            self.implicit_row_parameters = false;
            self.defer_associated = true;
            defer {
                self.closed_type_variables = saved_closed;
                self.implicit_row_parameters = saved_implicit;
                self.defer_associated = saved_defer;
            }
            var head: std.ArrayList(T.Id) = .empty;
            defer head.deinit(self.allocator);
            const contract_old = try self.allocator.dupe(T.Id, self.types.list(contract.variables));
            defer self.allocator.free(contract_old);
            const contract_fresh = try self.allocator.alloc(T.Id, contract_old.len);
            defer self.allocator.free(contract_fresh);
            for (contract_fresh) |*variable| variable.* = try self.types.fresh();
            const old_rows = try self.allocator.dupe(u32, self.types.list(contract.row_variables));
            defer self.allocator.free(old_rows);
            const new_rows = try self.allocator.alloc(T.Effects.Id, old_rows.len);
            defer self.allocator.free(new_rows);
            for (new_rows) |*row| row.* = try self.types.freshEffects();
            for (arguments, 0..) |argument, ordinal| {
                const actual = try self.parameterArgument(self.parameter_patterns.list(contract.patterns)[ordinal], argument, true, 0);
                if (try self.types.containsProjection(actual)) try self.diagnostic(.invalid_constraint, argument);
                try self.constrainRaw(try self.types.substituteWithRows(self.types.list(contract.parameters)[ordinal], contract_old, contract_fresh, old_rows, new_rows), actual, argument);
                try head.append(self.allocator, actual);
            }
            const product = try self.types.product(head.items);
            const free = try self.types.freeVariables(product);
            defer self.allocator.free(free);
            const rows = try self.types.freeRowVariables(product);
            defer self.allocator.free(rows);
            for (variables.items) |*variable| {
                variable.* = self.types.head(variable.*, 0);
                if (!inList(free, variable.*)) try self.diagnostic(.undetermined_implementation, id);
            }
            for (row_parameters.items) |row| {
                const tail = self.types.row(row).tail;
                if (tail != .variable or !inList(rows, tail.variable)) try self.diagnostic(.undetermined_implementation, id);
            }
            const member_start: u32 = @intCast(self.implementation_members.items.len);
            const index: u32 = @intCast(self.implementations.items.len);
            for (self.tree.list(syntax.members)) |child| {
                const item = self.tree.node(child);
                const member_index = self.memberIndex(contract, item.a) orelse {
                    try self.diagnostic(.missing_type_member, child);
                    continue;
                };
                const required = self.contract_members.items[member_index];
                if (required.kind == .defined_type) {
                    try self.diagnostic(.duplicate_name, child);
                    continue;
                }
                const is_type = item.tag == .contract_type_member;
                if (is_type != (required.kind == .abstract_type)) {
                    try self.diagnostic(.type_mismatch, child);
                    continue;
                }
                var repeated = false;
                for (self.implementation_members.items[member_start..]) |prior| {
                    if (prior.name == item.a) repeated = true;
                }
                if (repeated) {
                    try self.diagnostic(.duplicate_name, child);
                    continue;
                }
                const owned: u32 = @intCast(self.implementation_members.items.len);
                var member: ImplementationMember = .{ .name = item.a, .kind = .type_ };
                if (!is_type) {
                    member.kind = .value;
                    const text = try self.allocator.print("{s}.{s}", .{ self.pool.get(syntax.name), self.pool.get(item.a) });
                    defer self.allocator.free(text);
                    const name = self.pool.intern(self.allocator, text) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        error.SymbolLimit => return error.TypeLimit,
                    };
                    const binding = try self.addBinding(.{ .private = true, .name = name, .declaration = child, .owner = child, .kind = .global, .named_function = true, .ty = try self.types.fresh() });
                    self.resolved[child] = binding;
                    try self.implementation_bindings.put(self.allocator, binding, index);
                    try self.global_states.put(self.allocator, binding, .{});
                    member.target = .{ .unit = self.unit, .binding = binding };
                }
                try self.implementation_members.append(self.allocator, member);
                try self.implementation_member_sources.put(self.allocator, owned, child);
            }
            const members: T.List = .{ .start = member_start, .len = @intCast(self.implementation_members.items.len - member_start) };
            for (self.contract_members.items[contract.members.start..][0..contract.members.len]) |required| {
                if (required.kind == .defined_type) continue;
                const present = for (self.implementation_members.items[members.start..][0..members.len]) |member| {
                    if (member.name == required.name) break true;
                } else false;
                if (!present) {
                    var code: Code = .missing_type_member;
                    if (required.kind == .value) code = .missing_member;
                    try self.diagnostic(code, id);
                }
            }
            try self.implementations.append(self.allocator, .{ .origin_span = self.tree.span(id), .declaration = id, .private = self.tree.declarationTraits(id).private, .identity = .{ .unit = self.unit, .decl = T.opaque_name_bit | syntax.name }, .name = syntax.name, .contract = contract.identity, .head = try self.types.saveList(head.items), .variables = try self.types.saveList(variables.items), .parameter_names = try self.types.saveList(names.items), .row_variables = try self.types.saveList(rows), .row_parameter_names = try self.types.saveList(declared_row_names.items), .row_parameters = try self.types.saveList(row_parameters.items), .members = members });
            try self.catalogs.implementation_names.put(self.allocator, .{ .namespace = 0, .member = syntax.name }, index);
            // The anchor is the first public type binder, never a nested owner.
            var owner = contract.identity.unit == self.unit;
            if (!owner and contract_old.len != 0) {
                const anchor = self.types.node(try self.types.resolve(contract_fresh[0], 0));
                owner = anchor.tag == .nominal and anchor.a == self.unit;
            }
            if (!owner) try self.diagnostic(.orphan_implementation, id);
            var predicates: std.ArrayList(T.Obligation) = .empty;
            defer predicates.deinit(self.allocator);
            for (self.tree.list(syntax.where)) |predicate_source| try self.lowerPredicates(predicate_source, syntax.where_node, &predicates);
            // Contract prerequisites are obligations of the implementation too.
            for (self.contract_predicates.items[contract.predicates.start..][0..contract.predicates.len]) |old| {
                var requirement = old;
                inline for (.{ "ty", "other", "result", "signature" }) |field| requirement = updatePredicateField(requirement, field, try self.types.substituteWithRows(@field(old, field), contract_old, contract_fresh, old_rows, new_rows));
                requirement.source = id;
                try predicates.append(self.allocator, requirement);
            }
            const predicate_start: u32 = @intCast(self.implementation_predicates.items.len);
            try self.implementation_predicates.appendSlice(self.allocator, predicates.items);
            self.implementations.items[index].predicates = .{ .start = predicate_start, .len = @intCast(predicates.items.len) };
        }
        self.type_env.clearRetainingCapacity();
        self.row_env.clearRetainingCapacity();
    }
    fn updatePredicateField(value: T.Obligation, comptime field: []const u8, root: T.Id) T.Obligation {
        var result = value;
        @field(result, field) = root;
        return result;
    }
    fn implementationOrder(self: *Engine) T.Error!void {
        const OrderEntry = struct { index: u32, path: ?[]u8 = null };
        const entries = try self.allocator.alloc(OrderEntry, self.implementations.items.len);
        defer self.allocator.free(entries);
        for (entries, 0..) |*entry, index| entry.* = .{ .index = @intCast(index) };
        defer for (entries) |entry| if (entry.path) |path| self.allocator.free(path);
        for (entries) |*entry| {
            if (!try self.associatedStep(0)) return;
            entry.path = self.purity_origins.name(self.allocator, self.implementations.items[entry.index].identity.unit, self.unit) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => null,
            };
        }
        const Context = struct {
            engine: *Engine,
            failure: *?T.Error,
            fn less(self_: @This(), left: OrderEntry, right: OrderEntry) bool {
                self_.engine.types.chargeProjection() catch |err| {
                    self_.failure.* = err;
                    return left.index < right.index;
                };
                const first = self_.engine.implementations.items[left.index];
                const second = self_.engine.implementations.items[right.index];
                if (left.path) |before| if (right.path) |after| {
                    const order = std.mem.order(u8, before, after);
                    if (order != .eq) return order == .lt;
                };
                if (first.identity.unit != second.identity.unit) return first.identity.unit < second.identity.unit;
                if (first.origin_span) |before| if (second.origin_span) |after| {
                    if (before.start != after.start) return before.start < after.start;
                };
                return std.mem.lessThan(u8, self_.engine.pool.get(first.name), self_.engine.pool.get(second.name));
            }
        };
        var failure: ?T.Error = null;
        std.mem.sortUnstable(OrderEntry, entries, Context{ .engine = self, .failure = &failure }, Context.less);
        if (failure) |err| {
            if (err == error.OutOfMemory) return err;
            try self.diagnostic(.associated_limit, 0);
            return;
        }
        for (entries) |entry| try self.implementation_order.append(self.allocator, entry.index);
    }
    fn implementationCoherence(self: *Engine) T.Error!void {
        try self.implementationOrder();
        for (self.implementation_order.items, 0..) |later_index, ordinal| {
            const later = self.implementations.items[later_index];
            for (self.implementation_order.items[0..ordinal]) |earlier_index| {
                const earlier = self.implementations.items[earlier_index];
                if (later.private and earlier.private and later.identity.unit != earlier.identity.unit) continue;
                if (try implementation_patterns.overlap(&self.types, earlier, later)) {
                    var origin = later.declaration;
                    if (later.identity.unit != self.unit) origin = 0;
                    self.implementation_trace = .{ .context = self.unit, .request = origin, .contract = later.contract };
                    self.implementation_trace.candidate(earlier.identity, .overlap);
                    self.implementation_trace.candidate(later.identity, .overlap);
                    try self.diagnostic(.overlapping_implementation, origin);
                    if (later.identity.unit != self.unit) {
                        const issue = &self.diagnostics.items[self.diagnostics.items.len - 1];
                        issue.origin_unit = later.identity.unit;
                        if (self.purity_origins.source_available) |available| {
                            if (available(self.purity_origins.context, later.identity.unit)) if (later.origin_span) |span| {
                                issue.span = span;
                            };
                        }
                    }
                    return;
                }
            }
        }
    }
    fn implementationIndexForMember(self: *const Engine, member: u32) ?u32 {
        for (self.implementations.items, 0..) |declaration, index| {
            if (member >= declaration.members.start and member - declaration.members.start < declaration.members.len) return @intCast(index);
        }
        return null;
    }
    fn implementationMemberIndex(self: *const Engine, declaration: Implementation, name: u32) ?u32 {
        for (declaration.members.start..declaration.members.start + declaration.members.len) |ordinal| {
            if (self.implementation_members.items[ordinal].name == name) return @intCast(ordinal);
        }
        return null;
    }
    fn activeImplementation(self: *const Engine) ?u32 {
        if (self.checking_implementation) |index| return index;
        return self.implementation_bindings.get(self.current);
    }
    fn implementationEquation(self: *Engine, contract: Identity, name: u32, arguments: []const T.Id) T.Error!?T.Id {
        const index = self.activeImplementation() orelse return null;
        const declaration = self.implementations.items[index];
        if (!std.meta.eql(contract, declaration.contract) or arguments.len != declaration.head.len) return null;
        const member = self.implementationMemberIndex(declaration, name) orelse return null;
        if (self.implementation_members.items[member].kind != .type_) return null;
        var same = true;
        for (0..arguments.len) |ordinal| {
            if (!try self.types.equalSymbolic(arguments[ordinal], self.types.list(declaration.head)[ordinal])) same = false;
        }
        if (!same) {
            if (self.implementation_member_states.get(member) == .visiting and try implementation_patterns.matchesRigid(&self.types, declaration, arguments)) {
                try self.diagnostic(.recursive_associated_type, self.implementation_member_sources.get(member).?);
                return try self.types.fresh();
            }
            return null;
        }
        return try self.resolveImplementationMember(member);
    }
    fn unrestrictedAssociatedType(self: *Engine, root: T.Id, source: ast.Id) T.Error!void {
        if (try @import("usage_check.zig").containsNominalWork(&self.types, self.nominals.items, root, &self.associated_usage_work)) try self.diagnostic(.usage_evidence_mismatch, source);
    }
    fn resolveImplementationMember(self: *Engine, ordinal: u32) T.Error!T.Id {
        const member = self.implementation_members.items[ordinal];
        if (member.root != 0) return member.root;
        const index = self.implementationIndexForMember(ordinal).?;
        const declaration = self.implementations.items[index];
        const source = self.implementation_member_sources.get(ordinal) orelse return 0;
        if (self.implementation_member_states.get(ordinal)) |state| {
            if (state == .visiting) try self.diagnostic(.recursive_associated_type, source);
            return self.types.fresh();
        }
        try self.implementation_member_states.put(self.allocator, ordinal, .visiting);
        const saved_types = self.type_env;
        const saved_rows = self.row_env;
        const saved_closed = self.closed_type_variables;
        const saved_implicit = self.implicit_row_parameters;
        const saved_defer = self.defer_associated;
        const saved_implementation = self.checking_implementation;
        self.type_env = .empty;
        self.row_env = .empty;
        self.closed_type_variables = true;
        self.implicit_row_parameters = false;
        self.defer_associated = false;
        self.checking_implementation = index;
        defer {
            self.type_env.deinit(self.allocator);
            self.row_env.deinit(self.allocator);
            self.type_env = saved_types;
            self.row_env = saved_rows;
            self.closed_type_variables = saved_closed;
            self.implicit_row_parameters = saved_implicit;
            self.defer_associated = saved_defer;
            self.checking_implementation = saved_implementation;
        }
        try self.implementationScope(declaration);
        var root: T.Id = 0;
        if (member.kind == .type_) {
            root = try self.annotation(self.tree.node(source).b);
            try self.unrestrictedAssociatedType(root, source);
        } else {
            const contract = self.contracts.items[self.catalogs.contract_identities.get(declaration.contract).?];
            const descriptor = self.contract_members.items[self.memberIndex(contract, member.name).?];
            const old = try self.allocator.dupe(T.Id, self.types.list(contract.variables));
            defer self.allocator.free(old);
            const fresh = try self.allocator.alloc(T.Id, old.len);
            defer self.allocator.free(fresh);
            for (fresh) |*variable| variable.* = try self.types.fresh();
            const old_rows = try self.allocator.dupe(u32, self.types.list(contract.row_variables));
            defer self.allocator.free(old_rows);
            const new_rows = try self.allocator.alloc(T.Effects.Id, old_rows.len);
            defer self.allocator.free(new_rows);
            for (new_rows) |*row| row.* = try self.types.freshEffects();
            for (0..declaration.head.len) |parameter| try self.types.unify(try self.types.substituteWithRows(self.types.list(contract.parameters)[parameter], old, fresh, old_rows, new_rows), self.types.list(declaration.head)[parameter]);
            root = try self.normalizeAssociated(try self.types.substituteWithRows(descriptor.root, old, fresh, old_rows, new_rows), source, false);
            const annotation_ = self.tree.valueDecl(source).annotation;
            if (annotation_ != 0) try self.constrain(root, try self.annotation(annotation_), annotation_);
            self.bindings.items[member.target.binding].ty = root;
        }
        self.implementation_members.items[ordinal].root = root;
        try self.implementation_member_states.put(self.allocator, ordinal, .ready);
        return root;
    }
    fn provisionalEquation(self: *Engine, contract: Identity, name: u32, arguments: []const T.Id) T.Error!?T.Id {
        var ordinal = self.provisional_equations.items.len;
        while (ordinal != 0) {
            ordinal -= 1;
            const frame = self.provisional_equations.items[ordinal];
            const declaration = self.implementations.items[frame.declaration];
            if (!std.meta.eql(declaration.contract, contract) or frame.arguments.len != arguments.len) continue;
            var same = true;
            for (self.types.list(frame.arguments), arguments) |before, after| {
                if (!try self.types.equalSymbolic(before, after)) {
                    same = false;
                    break;
                }
            }
            if (!same) continue;
            const member_index = self.implementationMemberIndex(declaration, name) orelse return null;
            const member = self.implementation_members.items[member_index];
            if (member.kind != .type_) return null;
            const old = try implementation_patterns.typeBinders(&self.types, declaration);
            defer self.allocator.free(old);
            const old_rows = try implementation_patterns.rowBinders(&self.types, declaration);
            defer self.allocator.free(old_rows);
            return try self.types.substituteWithRows(member.root, old, frame.variables, old_rows, frame.rows);
        }
        return null;
    }
    fn implementationBodies(self: *Engine) T.Error!void {
        for (self.implementations.items) |declaration| {
            if (declaration.identity.unit != self.unit) continue;
            for (declaration.members.start..declaration.members.start + declaration.members.len) |member| _ = try self.resolveImplementationMember(@intCast(member));
        }
    }
    fn implementationMethodScope(self: *Engine, index: u32) T.Error!void {
        const declaration = self.implementations.items[index];
        try self.implementationScope(declaration);
        for (self.implementation_members.items[declaration.members.start..][0..declaration.members.len]) |member| {
            if (member.kind == .value) try self.env.append(self.allocator, .{ .name = member.name, .binding = member.target.binding });
        }
    }
    fn implementationArgumentPack(self: *Engine, span: T.List) T.Error!T.Id {
        const roots = try self.allocator.dupe(T.Id, self.types.list(span));
        defer self.allocator.free(roots);
        return self.types.product(roots);
    }
    fn beginImplementationQualification(self: *Engine, index: u32, scope: ast.Id, value: ast.Id) T.Error!void {
        const declaration = self.implementations.items[index];
        const start: u32 = @intCast(self.declared_obligations.items.len);
        for (self.implementation_predicates.items[declaration.predicates.start..][0..declaration.predicates.len]) |predicate| {
            try self.declared_obligations.append(self.allocator, predicate);
            try self.appendPending(.{ .owner = self.current, .value = predicate, .declared = true, .suspended = true });
        }
        const self_proof: T.Obligation = .{ .kind = .contract, .identity = declaration.contract, .ty = try self.implementationArgumentPack(declaration.head), .source = scope, .explicit = true };
        try self.declared_obligations.append(self.allocator, self_proof);
        try self.appendPending(.{ .owner = self.current, .value = self_proof, .declared = true, .suspended = true });
        try self.qualifications.append(self.allocator, .{ .scope = scope, .owner = self.current, .clauses = .{ .start = start, .len = @intCast(self.declared_obligations.items.len - start) }, .value = value });
    }
    fn validateImplementationBinders(self: *Engine, index: u32, source: ast.Id) T.Error!void {
        const declaration = self.implementations.items[index];
        for (0..declaration.variables.len) |ordinal| {
            const variable = self.types.list(declaration.variables)[ordinal];
            const resolved = self.types.head(variable, 0);
            if (self.types.node(resolved).tag != .variable) try self.diagnostic(.type_mismatch, source);
            for (0..ordinal) |prior| {
                if (self.types.head(self.types.list(declaration.variables)[prior], 0) == resolved) try self.diagnostic(.type_mismatch, source);
            }
        }
        for (self.types.list(declaration.row_parameters), 0..) |row, ordinal| {
            const resolved = self.types.row(try self.types.resolveEffects(row, 0));
            if (resolved.labels.len != 0 or resolved.tail != .variable) {
                try self.diagnostic(.effect_mismatch, source);
                continue;
            }
            for (self.types.list(declaration.row_parameters)[0..ordinal]) |prior| {
                const previous = self.types.row(try self.types.resolveEffects(prior, 0));
                if (previous.tail == .variable and previous.tail.variable == resolved.tail.variable) try self.diagnostic(.effect_mismatch, source);
            }
        }
    }
    fn contractGiven(self: *Engine, contract: Identity, arguments: []const T.Id) T.Error!bool {
        for (self.annotation_givens.items) |given| {
            try self.inferenceTransition();
            if (given.kind != .contract or !std.meta.eql(given.identity, contract)) continue;
            const tuple = self.types.node(self.types.head(given.ty, 0));
            if (tuple.tag != .product or tuple.b != arguments.len) continue;
            const expected = try self.allocator.dupe(T.Id, self.types.list(.{ .start = tuple.a, .len = tuple.b }));
            defer self.allocator.free(expected);
            var same = true;
            for (expected, arguments) |left, right| {
                if (!try self.types.equalSymbolic(try self.types.resolve(left, 0), try self.types.resolve(right, 0))) same = false;
            }
            if (same) return true;
        }
        for (self.dictionary_givens.items) |lexical| {
            const given = lexical.predicate;
            if (given.kind != .contract or !std.meta.eql(given.identity, contract)) continue;
            const application = self.types.node(self.types.head(given.ty, 0));
            if (application.tag != .product or application.b != arguments.len) continue;
            var same = true;
            for (self.types.list(.{ .start = application.a, .len = application.b }), arguments) |expected, actual| {
                if (!try self.types.equalSymbolic(try self.types.resolve(expected, 0), try self.types.resolve(actual, 0))) same = false;
            }
            if (same) return true;
        }

        for (self.qualifications.items) |boundary| {
            if (boundary.owner != self.current) continue;
            for (self.declared_obligations.items[boundary.clauses.start..][0..boundary.clauses.len]) |given| {
                if (given.kind != .contract or !std.meta.eql(given.identity, contract)) continue;
                const node = self.types.node(self.types.head(given.ty, 0));
                if (node.tag != .product or node.b != arguments.len) continue;
                var same = true;
                for (0..arguments.len) |ordinal| {
                    if (!try self.types.equalSymbolic(self.types.list(.{ .start = node.a, .len = node.b })[ordinal], arguments[ordinal])) same = false;
                }
                if (same) return true;
            }
        }
        if (self.checking_implementation) |index| {
            const declaration = self.implementations.items[index];
            if (std.meta.eql(declaration.contract, contract) and declaration.head.len == arguments.len) {
                var same = true;
                for (0..arguments.len) |ordinal| {
                    if (!try self.types.equalSymbolic(self.types.list(declaration.head)[ordinal], arguments[ordinal])) same = false;
                }
                if (same) return true;
            }
            for (self.implementation_predicates.items[declaration.predicates.start..][0..declaration.predicates.len]) |given| {
                if (given.kind != .contract or !std.meta.eql(given.identity, contract)) continue;
                const node = self.types.node(self.types.head(given.ty, 0));
                if (node.tag != .product or node.b != arguments.len) continue;
                var same = true;
                for (0..arguments.len) |ordinal| {
                    if (!try self.types.equalSymbolic(self.types.list(.{ .start = node.a, .len = node.b })[ordinal], arguments[ordinal])) same = false;
                }
                if (same) return true;
            }
        }
        return false;
    }
    fn privateImplementationAllowed(self: *const Engine, source: ast.Id) bool {
        const span = self.tree.span(source);
        for (self.tree.roots.items) |root| {
            const enclosing = self.tree.span(root);
            if (span.start < enclosing.start or span.end > enclosing.end) continue;
            if (self.tree.declarationTraits(root).private) return true;
            if (self.tree.node(root).tag == .implementation_decl) {
                const declaration = self.tree.implementation(root);
                for (self.tree.list(declaration.members)) |member| {
                    if (self.tree.node(member).tag != .value_decl) continue;
                    if (source == member and self.implementation_bindings.contains(self.current)) return true;
                    const body = self.tree.span(self.tree.valueDecl(member).body);
                    if (span.start >= body.start and span.end <= body.end) return true;
                }
                return false;
            }
            if (self.tree.node(root).tag != .value_decl) return false;
            const value = self.tree.valueDecl(root);
            for ([_]ast.Id{ value.annotation, value.where_node }) |header| {
                if (header == 0) continue;
                const boundary = self.tree.span(header);
                if (span.start >= boundary.start and span.end <= boundary.end) return false;
            }
            return true;
        }
        return self.current != 0;
    }
    fn selectedMember(self: *const Engine, proof: u32, name: u32) ?ImplementationMember {
        const declaration = self.selected_proofs.items[proof];
        for (self.selected_members.items[declaration.members.start..][0..declaration.members.len]) |member| if (member.name == name) return member;
        return null;
    }
    const LegacyProof = struct {
        engine: *Engine,
        evidence: *@import("../eval/type_evidence.zig").Store,
        source: ast.Id,
        remaining: usize,
        observed: usize,
        fn sync(self: *LegacyProof) T.Error!void {
            const spent = self.observed - self.remaining;
            if (spent > self.engine.types.projection_limit - self.engine.types.projection_steps) return error.TypeLimit;
            self.engine.types.projection_steps += spent;
            self.observed = self.remaining;
        }
        fn refresh(self: *LegacyProof) void {
            self.remaining = self.engine.types.projection_limit - self.engine.types.projection_steps;
            self.observed = self.remaining;
        }
        fn resolve(raw: *anyopaque, identity: Identity, member: u32, arguments: []const @import("../eval/type_evidence.zig").Id) @import("../eval/type_evidence.zig").Error!@import("../eval/type_evidence.zig").Id {
            const self: *LegacyProof = @ptrCast(@alignCast(raw));
            self.sync() catch |err| return convert(err);
            var copy: @import("../eval/closed_evidence_import.zig").Importer = .{ .allocator = self.engine.allocator, .source = self.evidence.view(), .destination = &self.engine.types };
            defer copy.deinit();
            var roots: std.ArrayList(T.Id) = .empty;
            defer roots.deinit(self.engine.allocator);
            for (arguments) |argument| try roots.append(self.engine.allocator, copy.ty(argument, 0) catch |err| return convert(err));
            const projection = self.engine.types.projection(identity, member, roots.items) catch |err| return convert(err);
            const result = self.engine.normalizeAssociated(projection, self.source, true) catch |err| return convert(err);
            self.refresh();
            return self.evidence.projectWithBudget(&self.engine.types, result, &.{}, &.{}, &self.remaining);
        }
        fn convert(err: T.Error) @import("../eval/type_evidence.zig").Error {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            if (err == error.TypeLimit) return error.EvidenceLimit;
            return error.TypeMismatch;
        }
        fn resolver(self: *LegacyProof) @import("../eval/type_evidence.zig").ProjectionResolver {
            return .{ .context = self, .remaining = &self.remaining, .resolve = resolve };
        }
    };
    fn proveLegacy(self: *Engine, predicate: *T.Obligation, source: ast.Id) T.Error!bool {
        const E = @import("../eval/type_evidence.zig");
        var evidence = E.Store.init(self.allocator) catch |err| return legacyError(err);
        defer evidence.deinit();
        var state: LegacyProof = .{ .engine = self, .evidence = &evidence, .source = source, .remaining = self.types.projection_limit - self.types.projection_steps, .observed = self.types.projection_limit - self.types.projection_steps };
        errdefer state.sync() catch {};
        const result = try self.proveLegacyState(&state, predicate, source);
        try state.sync();
        return result;
    }
    fn proveLegacyState(self: *Engine, state: *LegacyProof, predicate: *T.Obligation, source: ast.Id) T.Error!bool {
        const E = @import("../eval/type_evidence.zig");
        const evidence = state.evidence;
        var operands: [4]E.Id = @splat(0);
        for ([_]T.Id{ predicate.ty, predicate.other, predicate.result, predicate.signature }, &operands, 0..) |root, *operand, ordinal| {
            if (root == 0) continue;
            const normalized = try self.normalizeAssociated(root, source, true);
            state.refresh();
            operand.* = evidence.projectWithBudget(&self.types, normalized, &.{}, &.{}, &state.remaining) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnresolvedType => {
                    const node = self.types.node(self.types.head(root, 0));
                    if (ordinal == 3 and node.tag == .function and node.a == T.unit and node.b == T.unit and self.types.rowLabels(node.c).len == 0 and self.types.row(node.c).tail == .variable) continue;
                    return false;
                },
                else => return legacyError(err),
            };
            try state.sync();
        }
        if (predicate.kind == .field or predicate.kind == .writable_field) {
            const record = evidence.node(operands[0]);
            if (record.tag == .record) {
                const fields = evidence.children(operands[0]);
                var at: usize = 0;
                while (at < fields.len) : (at += 2) if (fields[at] == predicate.name) return fields[at + 1] == operands[2];
            }
            if (record.tag == .nominal) {
                const identity: Identity = .{ .unit = record.a, .decl = record.b };
                const index = self.nominalIndex(identity) orelse return false;
                const definition = self.nominals.items[index];
                if (!definition.is_opaque or definition.identity.unit == self.unit) {
                    const constructors = try self.allocator.dupe(T.Id, self.types.list(definition.constructors));
                    defer self.allocator.free(constructors);
                    var found = constructors.len != 0;
                    var compatible = true;
                    for (constructors) |constructor| {
                        if (!try self.associatedStep(source)) return false;
                        const signature = self.types.node(try self.constructorStorageType(constructor));
                        if (signature.tag != .function) {
                            found = false;
                            break;
                        }
                        self.types.unify(signature.b, predicate.ty) catch |err| switch (err) {
                            error.OutOfMemory, error.TypeLimit => return err,
                            else => {
                                found = false;
                                break;
                            },
                        };
                        const payload = self.types.node(try self.types.resolve(signature.a, 0));
                        if (payload.tag != .record) {
                            found = false;
                            break;
                        }
                        var field_type: T.Id = 0;
                        for (0..payload.b) |field| {
                            if (!try self.associatedStep(source)) return false;
                            const value = self.types.recordField(payload, field);
                            if (value.name == predicate.name) {
                                field_type = value.ty;
                                break;
                            }
                        }
                        if (field_type == 0) {
                            found = false;
                            break;
                        }
                        if (!try self.types.equalSymbolic(try self.types.resolve(field_type, 0), try self.types.resolve(predicate.result, 0))) compatible = false;
                    }
                    if (found) {
                        if (predicate.kind == .field and self.catalogs.associated_members.contains(.{ .identity = identity, .member = predicate.name })) return false;
                        return compatible;
                    }
                }
            }
            if (predicate.kind == .writable_field) return false;
        }
        var candidates: [2]?BindingId = @splat(null);
        var selection_owner = predicate.ty;
        var selected_identity: ?Identity = null;
        if (predicate.kind == .result_dispatch) selection_owner = predicate.result;
        if (predicate.kind == .resolver_dispatch) {
            const resolver = self.types.node(try self.types.resolve(predicate.ty, 0));
            if (resolver.tag != .resolver) return false;
            const constructor = self.types.node(try self.types.resolve(resolver.a, 0));
            if (constructor.tag != .type_constructor) return false;
            selected_identity = .{ .unit = constructor.a, .decl = constructor.b };
        } else {
            selected_identity = self.identityOf(selection_owner);
        }
        if (selected_identity) |identity| {
            const descriptor = if (predicate.name == 0) self.catalogs.associated_ops.get(.{ .identity = identity, .operator = predicate.operator }) else self.catalogs.associated_members.get(.{ .identity = identity, .member = predicate.name });
            if (descriptor) |ordinal| candidates[0] = self.associated.items[ordinal].binding;
        }
        if (predicate.kind == .dispatch) if (self.identityOf(predicate.other)) |identity| {
            const descriptor = if (predicate.name == 0) self.catalogs.associated_ops.get(.{ .identity = identity, .operator = predicate.operator }) else self.catalogs.associated_members.get(.{ .identity = identity, .member = predicate.name });
            if (descriptor) |ordinal| candidates[1] = self.associated.items[ordinal].binding;
        };
        for (candidates, 0..) |candidate, side| {
            if (side == 1 and predicate.kind == .dispatch and predicate.name == 0) {
                if (@import("../eval/implementation_predicates.zig").primitiveResult(evidence, predicate.operator, operands[0], operands[1])) |result| {
                    if (result != operands[2]) return false;
                    var carrier = operands[3];
                    if (carrier == 0) carrier = evidence.intern(.function, T.unit, T.unit, &.{}) catch |err| return legacyError(err);
                    try state.sync();
                    var copy: @import("../eval/closed_evidence_import.zig").Importer = .{ .allocator = self.allocator, .source = evidence.view(), .destination = &self.types };
                    defer copy.deinit();
                    predicate.signature = try copy.ty(carrier, 0);
                    return true;
                }
            }
            const binding = candidate orelse continue;
            if (!try self.prepareSelectedGlobal(binding)) continue;
            const principal = self.bindings.items[binding].scheme;
            state.refresh();
            var mappings: std.ArrayList(E.Mapping) = .empty;
            defer mappings.deinit(self.allocator);
            var rows: std.ArrayList(E.RowMapping) = .empty;
            defer rows.deinit(self.allocator);
            var arity: usize = 2;
            if (predicate.kind == .field or predicate.kind == .writable_field or predicate.kind == .result_dispatch) arity = 1;
            var carrier: E.Id = 0;
            if (predicate.kind == .resolver_dispatch) {
                const matched = evidence.matchLegacySignature(&self.types, principal.root, operands[1], &mappings, &rows, state.resolver()) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.TypeMismatch, error.UnresolvedType => return false,
                    else => return legacyError(err),
                };
                if (!matched) continue;
            } else {
                carrier = evidence.matchPrerequisite(&self.types, principal.root, operands, arity, &mappings, &rows, state.resolver()) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.TypeMismatch, error.UnresolvedType => return false,
                    else => return legacyError(err),
                } orelse continue;
            }
            for (mappings.items) |mapping| if (!inList(self.types.list(principal.variables), mapping.variable)) return false;
            var certificates: std.ArrayList(u32) = .empty;
            defer certificates.deinit(self.allocator);
            try certificates.appendSlice(self.allocator, self.types.list(principal.closed_rows));
            for (self.body_closed_rows.items) |certificate| if (certificate.owner == binding) try certificates.append(self.allocator, certificate.variable);
            const local_clauses = try self.allocator.dupe(T.Obligation, self.obligations.items[principal.obligations.start..][0..principal.obligations.len]);
            defer self.allocator.free(local_clauses);
            for (local_clauses) |*clause| {
                inline for (.{ "ty", "other", "result", "signature" }) |field| @field(clause, field) = try self.types.resolve(@field(clause, field), 0);
            }
            @import("../eval/implementation_rows.zig").reconstruct(evidence, @as(*const T.Store, &self.types), local_clauses, certificates.items, self.types.list(principal.variables), &mappings, &rows, state.resolver()) catch |err| switch (err) {
                error.TypeMismatch, error.UnresolvedType => return false,
                else => return legacyError(err),
            };
            for (rows.items) |mapping| if (!inList(self.types.list(principal.row_variables), mapping.variable)) return false;
            try state.sync();
            var copy: @import("../eval/closed_evidence_import.zig").Importer = .{ .allocator = self.allocator, .source = evidence.view(), .destination = &self.types };
            defer copy.deinit();
            if (predicate.kind != .resolver_dispatch) predicate.signature = try copy.ty(carrier, 0);
            if (self.active_evidence.items.len >= 256 or self.active_predicates.items.len >= 256 - self.active_evidence.items.len) {
                try self.diagnostic(.associated_limit, source);
                return false;
            }
            for (self.active_predicates.items) |active| {
                if (!try self.associatedStep(source)) return false;
                if (active.binding != binding or active.value.kind != predicate.kind) continue;
                var same = true;
                inline for (.{ "ty", "other", "result", "signature" }) |field| {
                    if (!try self.types.equalSymbolic(@field(active.value, field), @field(predicate.*, field))) same = false;
                }
                if (same) {
                    try self.diagnostic(.recursive_evidence, source);
                    return false;
                }
            }
            try self.active_predicates.append(self.allocator, .{ .binding = binding, .value = predicate.* });
            defer _ = self.active_predicates.pop();
            const clauses = try self.allocator.dupe(T.Obligation, local_clauses);
            defer self.allocator.free(clauses);
            var old_variables: std.ArrayList(T.Id) = .empty;
            defer old_variables.deinit(self.allocator);
            var new_variables: std.ArrayList(T.Id) = .empty;
            defer new_variables.deinit(self.allocator);
            for (mappings.items) |mapping| {
                try old_variables.append(self.allocator, mapping.variable);
                try new_variables.append(self.allocator, try copy.ty(mapping.evidence, 0));
            }
            var old_rows: std.ArrayList(u32) = .empty;
            defer old_rows.deinit(self.allocator);
            var new_rows: std.ArrayList(T.Effects.Id) = .empty;
            defer new_rows.deinit(self.allocator);
            for (rows.items) |mapping| {
                try old_rows.append(self.allocator, mapping.variable);
                try new_rows.append(self.allocator, try copy.row(mapping.evidence, 0));
            }
            var edges: std.ArrayList(u32) = .empty;
            defer edges.deinit(self.allocator);
            for (clauses) |before| {
                if (!try self.associatedStep(source)) return false;
                var clause = before;
                inline for (.{ "ty", "other", "result", "signature" }) |field| @field(clause, field) = try self.types.substituteWithRows(@field(before, field), old_variables.items, new_variables.items, old_rows.items, new_rows.items);
                clause.source = source;
                const child = try self.proveAndSavePredicate(&clause, source) orelse return false;
                try edges.append(self.allocator, child);
            }
            const edge_start: u32 = @intCast(self.selected_edges.items.len);
            try self.selected_edges.appendSlice(self.allocator, edges.items);
            self.proved_predicate_prerequisites = .{ .start = edge_start, .len = @intCast(edges.items.len) };
            self.proved_predicate_target = self.bindings.items[binding].external orelse .{ .unit = self.unit, .binding = binding };
            return true;
        }
        return false;
    }
    fn legacyError(err: @import("../eval/type_evidence.zig").Error) T.Error {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        if (err == error.EvidenceLimit) return error.TypeLimit;
        return error.TypeMismatch;
    }
    fn proveImplementationPredicate(self: *Engine, predicate: *T.Obligation, source: ast.Id) T.Error!bool {
        self.proved_predicate_target = .{ .unit = 0, .binding = 0 };
        self.proved_predicate_prerequisites = .{};
        if (predicate.kind == .callee_use) return self.proveCalleePredicate(predicate, source);
        if (predicate.kind == .dispatch or predicate.kind == .receiver or predicate.kind == .field or predicate.kind == .writable_field or predicate.kind == .result_dispatch or predicate.kind == .resolver_dispatch) return self.proveLegacy(predicate, source);
        if (predicate.kind == .effect_operation) {
            const arguments = try self.types.resolve(predicate.other, 0);
            if (!try self.types.equalClosed(arguments, arguments)) return false;
            const pack = self.types.node(arguments);
            if (pack.tag != .product) return false;
            const actuals = try self.allocator.dupe(T.Id, self.types.list(.{ .start = pack.a, .len = pack.b }));
            defer self.allocator.free(actuals);
            const label = try self.types.internOperation(predicate.identity, actuals);
            const carrier = self.types.node(try self.types.resolve(predicate.signature, 0));
            if (carrier.tag != .function) return false;
            const row = self.types.row(carrier.c);
            for (self.types.rowLabels(carrier.c)) |known| if (known == label) return true;
            if (row.tail != .variable) return false;
            // The existing demanded operation rule supplies a typed label to
            // this predicate's own row. It never changes executable ambient.
            var labels: std.ArrayList(T.Effects.Label) = .empty;
            defer labels.deinit(self.allocator);
            try labels.appendSlice(self.allocator, self.types.rowLabels(carrier.c));
            try labels.append(self.allocator, label);
            const established = self.types.effects.row(labels.items, .closed) catch |err| return T.effectError(err);
            try self.types.unifyEffects(carrier.c, established);
            predicate.ty = try self.types.resolve(predicate.ty, 0);
            predicate.signature = try self.types.resolve(predicate.signature, 0);
            return true;
        }
        if (predicate.kind != .type_eq and try self.requirementOpen(predicate.*)) return false;
        const tag = self.types.node(self.types.head(predicate.ty, 0)).tag;
        if (predicate.kind == .update and predicate.signature != 0) {
            const carrier = self.types.node(self.types.head(predicate.signature, 0));
            if (carrier.tag != .function) return false;
            const row = self.types.row(try self.types.resolveEffects(carrier.c, 0));
            if (row.labels.len == 0 and row.tail == .variable) predicate.signature = try self.types.functionWithEffects(T.unit, T.unit, 0);
        }
        switch (predicate.kind) {
            .arithmetic, .ordered => return tag == .u32 or tag == .f32,
            .equality => return tag == .u32 or tag == .f32 or tag == .boolean,
            .integer => return tag == .u32,
            .type_rep, .effect_rep => return true,
            .type_eq => {
                const left = try self.normalizeAssociated(predicate.ty, source, true);
                const right = try self.normalizeAssociated(predicate.result, source, true);
                predicate.ty = left;
                predicate.result = right;
                return self.types.equalSymbolic(left, right);
            },
            else => {},
        }
        // An invocation prerequisite constrains its own row carrier. Merely
        // normalizing a projection must not acquire the executable ambient.
        const saved_ambient = self.ambient;
        defer self.ambient = saved_ambient;
        if (predicate.signature == 0) {
            self.ambient = try self.types.freshEffects();
        } else {
            const carrier = self.types.node(self.types.head(predicate.signature, 0));
            if (carrier.tag != .function) return false;
            self.ambient = carrier.c;
        }
        const start = self.diagnostics.items.len;
        const index = self.pending.items.len;
        try self.appendPending(.{ .owner = self.current, .value = predicate.* });
        _ = try self.attemptPending(index, self.pending.items[index]);
        const solved = self.pending.items[index].solved and self.diagnostics.items.len == start;
        self.pending.items[index].solved = true;
        if (self.diagnostics.items.len != start) {
            deinitDiagnosticPayloads(self.allocator, self.diagnostics.items[start..]);
            self.diagnostics.shrinkRetainingCapacity(start);
        }
        return solved;
    }
    fn proveCalleePredicate(self: *Engine, predicate: *T.Obligation, source: ast.Id) T.Error!bool {
        const binding = predicate.identity.decl;
        if (!try self.prepareSelectedGlobal(binding)) return false;
        const principal = self.bindings.items[binding].scheme;
        const summary = self.bindings.items[binding].summary;
        const pack = self.types.node(try self.types.resolve(predicate.ty, 0));
        if (pack.tag != .product or pack.b != summary.public_variables.len + summary.public_rows.len) return false;
        if (self.active_evidence.items.len >= 256 or self.active_predicates.items.len >= 256 - self.active_evidence.items.len) {
            try self.diagnostic(.associated_limit, source);
            return false;
        }
        for (self.active_predicates.items) |active| {
            if (!try self.associatedStep(source)) return false;
            if (active.binding == binding and active.value.kind == .callee_use and try self.types.equalSymbolic(try self.types.resolve(active.value.ty, 0), try self.types.resolve(predicate.ty, 0))) {
                try self.diagnostic(.recursive_evidence, source);
                return false;
            }
        }
        try self.active_predicates.append(self.allocator, .{ .binding = binding, .value = predicate.* });
        defer _ = self.active_predicates.pop();
        const parts = try self.allocator.dupe(T.Id, self.types.list(.{ .start = pack.a, .len = pack.b }));
        defer self.allocator.free(parts);
        const old = try self.allocator.dupe(T.Id, self.types.list(summary.public_variables));
        defer self.allocator.free(old);
        const old_rows = try self.allocator.dupe(u32, self.types.list(summary.public_rows));
        defer self.allocator.free(old_rows);
        const new_rows = try self.allocator.alloc(T.Effects.Id, old_rows.len);
        defer self.allocator.free(new_rows);
        for (parts[old.len..], new_rows) |carrier, *row| {
            const node = self.types.node(self.types.head(carrier, 0));
            if (node.tag != .function or node.a != T.unit or node.b != T.unit) return false;
            row.* = node.c;
        }
        const clauses = try self.allocator.dupe(T.Obligation, self.obligations.items[principal.obligations.start..][0..principal.obligations.len]);
        defer self.allocator.free(clauses);
        var edges: std.ArrayList(u32) = .empty;
        defer edges.deinit(self.allocator);
        for (clauses) |before| {
            if (!try self.associatedStep(source)) return false;
            var clause = before;
            inline for (.{ "ty", "other", "result", "signature" }) |field| @field(clause, field) = try self.types.substituteWithRows(@field(before, field), old, parts[0..old.len], old_rows, new_rows);
            clause.source = source;
            try edges.append(self.allocator, try self.proveAndSavePredicate(&clause, source) orelse return false);
        }
        const start: u32 = @intCast(self.selected_edges.items.len);
        try self.selected_edges.appendSlice(self.allocator, edges.items);
        self.proved_predicate_prerequisites = .{ .start = start, .len = @intCast(edges.items.len) };
        self.proved_predicate_target = self.bindings.items[binding].external orelse .{ .unit = self.unit, .binding = binding };
        return true;
    }
    fn proveAndSavePredicate(self: *Engine, predicate: *T.Obligation, source: ast.Id) T.Error!?u32 {
        if (predicate.kind == .contract) {
            const application = self.types.node(self.types.head(predicate.ty, 0));
            if (application.tag != .product) return null;
            return self.selectImplementation(predicate.identity, self.types.list(.{ .start = application.a, .len = application.b }), source);
        }
        if (!try self.proveImplementationPredicate(predicate, source)) return null;
        const child: u32 = @intCast(self.selected_proofs.items.len);
        try self.selected_proofs.append(self.allocator, .{ .context = self.unit, .kind = .predicate, .predicate_target = self.proved_predicate_target, .predicate = predicate.*, .implementation = .{ .unit = 0, .decl = 0 }, .contract = .{ .unit = 0, .decl = 0 }, .arguments = .{}, .members = .{}, .prerequisites = self.proved_predicate_prerequisites });
        return child;
    }
    fn selectImplementation(self: *Engine, contract: Identity, input: []const T.Id, source: ast.Id) T.Error!?u32 {
        if (self.active_evidence.items.len == 0) self.implementation_trace = .{ .context = self.unit, .request = source, .contract = contract };
        const arguments = try self.allocator.dupe(T.Id, input);
        defer self.allocator.free(arguments);
        for (arguments) |*argument| argument.* = try self.types.resolve(argument.*, 0);
        if (try self.contractGiven(contract, arguments)) return null;
        for (arguments) |argument| if (!try self.types.equalClosed(argument, argument)) return null;
        if (self.active_evidence.items.len >= 256 or self.active_predicates.items.len >= 256 - self.active_evidence.items.len) {
            try self.diagnostic(.associated_limit, source);
            return null;
        }
        for (self.active_evidence.items) |active| {
            if (!try self.associatedStep(source)) return null;
            if (!std.meta.eql(active.contract, contract) or active.arguments.len != arguments.len) continue;
            var same = true;
            for (0..arguments.len) |ordinal| {
                if (!try self.types.equalSymbolic(arguments[ordinal], self.types.list(active.arguments)[ordinal])) same = false;
            }
            if (same) {
                try self.diagnostic(.recursive_evidence, source);
                return null;
            }
        }
        for (self.selected_proofs.items, 0..) |proof, ordinal| {
            if (!try self.associatedStep(source)) return null;
            if (proof.kind != .implementation or !std.meta.eql(proof.contract, contract) or proof.arguments.len != arguments.len) continue;
            var same = true;
            for (0..arguments.len) |argument| {
                if (!try self.types.equalSymbolic(arguments[argument], self.types.list(proof.arguments)[argument])) same = false;
            }
            if (same) {
                for (self.implementations.items) |declaration| {
                    if (!std.meta.eql(declaration.identity, proof.implementation)) continue;
                    if (declaration.private and !self.privateImplementationAllowed(source)) {
                        try self.diagnostic(.private_identity_escape, source);
                        return null;
                    }
                    break;
                }
                try self.selected_uses.append(self.allocator, .{ .source = source, .proof = @intCast(ordinal) });
                return @intCast(ordinal);
            }
        }
        const saved_arguments = try self.types.saveList(arguments);
        try self.active_evidence.append(self.allocator, .{ .contract = contract, .arguments = saved_arguments });
        defer _ = self.active_evidence.pop();
        var selected: ?u32 = null;
        for (self.implementation_order.items) |ordinal| {
            const declaration = self.implementations.items[ordinal];
            if (!try self.associatedStep(source)) return null;
            if (!std.meta.eql(declaration.contract, contract)) continue;
            if (declaration.private and declaration.identity.unit != self.unit) continue;
            if (!declaration.private or self.privateImplementationAllowed(source)) self.implementation_trace.candidate(declaration.identity, .head_mismatch);
            if (!try implementation_patterns.matches(&self.types, declaration, arguments)) continue;
            if (!declaration.private or self.privateImplementationAllowed(source)) self.implementation_trace.candidate(declaration.identity, .selected);
            if (selected != null) {
                try self.diagnostic(.overlapping_implementation, source);
                return null;
            }
            selected = @intCast(ordinal);
        }
        const index = selected orelse {
            try self.diagnostic(.missing_implementation, source);
            return null;
        };
        const declaration = self.implementations.items[index];
        if (declaration.private and !self.privateImplementationAllowed(source)) {
            try self.diagnostic(.private_identity_escape, source);
            return null;
        }
        for (declaration.members.start..declaration.members.start + declaration.members.len) |member| {
            if (self.implementation_members.items[member].root == 0) _ = try self.resolveImplementationMember(@intCast(member));
        }
        const instance = try implementation_patterns.instantiate(&self.types, declaration);
        defer instance.deinit(self.allocator);
        for (0..arguments.len) |ordinal| try self.types.unify(self.types.list(instance.head)[ordinal], arguments[ordinal]);
        const old = try implementation_patterns.typeBinders(&self.types, declaration);
        defer self.allocator.free(old);
        const old_rows = try implementation_patterns.rowBinders(&self.types, declaration);
        defer self.allocator.free(old_rows);
        // Equations belong to the selected head. They can normalize its
        // prerequisites, but the proof is published only after every edge.
        try self.provisional_equations.append(self.allocator, .{ .declaration = index, .arguments = saved_arguments, .variables = instance.variables, .rows = instance.rows });
        defer _ = self.provisional_equations.pop();
        var edges: std.ArrayList(u32) = .empty;
        defer edges.deinit(self.allocator);
        const prerequisites = try self.allocator.dupe(T.Obligation, self.implementation_predicates.items[declaration.predicates.start..][0..declaration.predicates.len]);
        defer self.allocator.free(prerequisites);
        for (prerequisites) |before| {
            if (!try self.associatedStep(source)) return null;
            var predicate = before;
            inline for (.{ "ty", "other", "result", "signature" }) |field| @field(predicate, field) = try self.types.substituteWithRows(try self.types.resolve(@field(before, field), 0), old, instance.variables, old_rows, instance.rows);
            predicate.source = source;
            const trace_step = self.implementation_trace.step(predicate.ty, predicate.name, .requires_evidence);
            const child = try self.proveAndSavePredicate(&predicate, source);
            if (child == null) {
                self.implementation_trace.candidate(declaration.identity, .requires_evidence);
                self.implementation_trace.setOutcome(trace_step, @import("../eval/implementation_predicates.zig").failureOutcome(predicate.kind));
                if (trace_step) |step| self.implementation_trace.steps[step].ty = predicate.ty;
                try self.diagnostic(.incompatible_implementation, source);
                return null;
            }
            self.implementation_trace.setOutcome(trace_step, .selected);
            try edges.append(self.allocator, child.?);
        }
        var selected_members: std.ArrayList(ImplementationMember) = .empty;
        defer selected_members.deinit(self.allocator);
        const before_members = try self.allocator.dupe(ImplementationMember, self.implementation_members.items[declaration.members.start..][0..declaration.members.len]);
        defer self.allocator.free(before_members);
        for (before_members) |before| {
            var member = before;
            const root = try self.types.substituteWithRows(try self.types.resolve(before.root, 0), old, instance.variables, old_rows, instance.rows);
            member.root = try self.normalizeAssociated(root, source, true);
            if (member.kind == .type_) try self.unrestrictedAssociatedType(member.root, source);
            if (!try self.types.equalClosed(member.root, member.root)) {
                try self.diagnostic(.incompatible_implementation, source);
                return null;
            }
            try selected_members.append(self.allocator, member);
        }
        const member_start: u32 = @intCast(self.selected_members.items.len);
        try self.selected_members.appendSlice(self.allocator, selected_members.items);
        const edge_start: u32 = @intCast(self.selected_edges.items.len);
        try self.selected_edges.appendSlice(self.allocator, edges.items);
        const proof: u32 = @intCast(self.selected_proofs.items.len);
        try self.selected_proofs.append(self.allocator, .{ .context = self.unit, .implementation = declaration.identity, .contract = contract, .arguments = saved_arguments, .members = .{ .start = member_start, .len = declaration.members.len }, .prerequisites = .{ .start = edge_start, .len = @intCast(edges.items.len) } });
        try self.selected_uses.append(self.allocator, .{ .source = source, .proof = proof });
        return proof;
    }
    fn memberTemplates(self: *Engine) T.Error!void {
        var names = self.catalogs.contract_names.iterator();
        while (names.next()) |entry| {
            const contract = self.contracts.items[entry.value_ptr.*];
            for (self.contract_members.items[contract.members.start..][0..contract.members.len]) |member| {
                if (member.kind != .value) continue;
                if (!try self.associatedStep(0)) return;
                const key = entry.key_ptr.*;
                var text: []u8 = undefined;
                if (key.namespace == 0) {
                    text = try self.allocator.print("{s}.{s}", .{ self.pool.get(key.member), self.pool.get(member.name) });
                } else {
                    text = try self.allocator.print("{s}.{s}.{s}", .{ self.pool.get(key.namespace), self.pool.get(key.member), self.pool.get(member.name) });
                }
                defer self.allocator.free(text);
                const name = self.pool.intern(self.allocator, text) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.SymbolLimit => return error.TypeLimit,
                };
                if (self.catalogs.globals.contains(name)) continue;
                const start: u32 = @intCast(self.obligations.items.len);
                for (self.contract_predicates.items[contract.predicates.start..][0..contract.predicates.len]) |predicate| try self.obligations.append(self.allocator, predicate);
                const source = self.member_sources.get(self.memberIndex(contract, member.name).?) orelse 0;
                try self.obligations.append(self.allocator, .{ .kind = .contract, .ty = try self.implementationArgumentPack(contract.parameters), .identity = contract.identity, .source = source, .explicit = true });
                const principal: T.Scheme = .{ .root = member.root, .variables = contract.variables, .row_variables = contract.row_variables, .obligations = .{ .start = start, .len = @intCast(self.obligations.items.len - start) } };
                const binding = try self.addBinding(.{ .private = contract.private, .name = name, .declaration = source, .owner = source, .kind = .global, .named_function = true, .ty = member.root, .scheme = principal, .summary = try self.summarize(principal) });
                try self.global_states.put(self.allocator, binding, .{ .state = .complete });
                try self.catalogs.globals.put(self.allocator, name, binding);
                try self.member_templates.append(self.allocator, .{ .binding = binding, .contract = contract.identity, .name = member.name, .arguments = contract.parameters });
            }
        }
    }
    fn selectedReference(self: *Engine, source: ast.Id, template: PI.MemberTemplate, proof: PI.SelectedProof) T.Error!bool {
        return self.selectedReferenceWithGoal(source, template, proof, false);
    }
    fn selectedReferenceWithGoal(self: *Engine, source: ast.Id, template: PI.MemberTemplate, proof: PI.SelectedProof, lexical: bool) T.Error!bool {
        if (!std.meta.eql(template.contract, proof.contract)) return false;
        const actual_root = try self.types.resolve(self.expr_types[source], 0);
        if (actual_root == 0 or self.types.node(actual_root).tag != .function) return false;
        const contract = self.contracts.items[self.catalogs.contract_identities.get(template.contract).?];
        const member = self.contract_members.items[self.memberIndex(contract, template.name).?];
        const old = try self.allocator.dupe(T.Id, self.types.list(contract.variables));
        defer self.allocator.free(old);
        const old_rows = try self.allocator.dupe(u32, self.types.list(contract.row_variables));
        defer self.allocator.free(old_rows);
        const point = self.types.mark();
        defer self.types.rollback(point);
        const fresh = try self.allocator.alloc(T.Id, old.len);
        defer self.allocator.free(fresh);
        for (fresh) |*variable| variable.* = try self.types.fresh();
        const rows = try self.allocator.alloc(T.Effects.Id, old_rows.len);
        defer self.allocator.free(rows);
        for (rows) |*row| row.* = try self.types.freshEffects();
        var expected = try self.types.substituteWithRows(member.root, old, fresh, old_rows, rows);
        var actual = actual_root;
        while (self.types.node(self.types.head(expected, 0)).tag == .function and self.types.node(actual).tag == .function) {
            const left = self.types.node(self.types.head(expected, 0));
            const right = self.types.node(actual);
            // Only ordinary argument positions determine head binders. Wanted
            // associated outputs cannot choose an implementation or its input.
            self.types.unifyPattern(left.a, right.a) catch |err| switch (err) {
                error.OutOfMemory, error.TypeLimit => return err,
                else => return false,
            };
            expected = left.b;
            actual = right.b;
        }
        if (contract.parameters.len != proof.arguments.len) return false;
        for (0..contract.parameters.len) |ordinal| {
            const input = try self.types.resolve(try self.types.substituteWithRows(self.types.list(contract.parameters)[ordinal], old, fresh, old_rows, rows), 0);
            const argument = self.types.list(proof.arguments)[ordinal];
            if (lexical) self.types.unifyPattern(input, argument) catch |err| switch (err) {
                error.OutOfMemory, error.TypeLimit => return err,
                else => return false,
            };
            if (!lexical and !try self.types.equalClosed(input, input)) return false;
            if (!try self.types.equalSymbolic(try self.types.resolve(input, 0), try self.types.resolve(argument, 0))) return false;
        }
        return true;
    }
    fn lexicalDictionaryGoal(self: *Engine, wanted: T.Obligation) T.Error!bool {
        if (wanted.kind != .contract or wanted.source == 0) return false;
        const occurrence = self.tree.span(wanted.source);
        for (self.rank_implementations.items) |implementation| {
            try self.inferenceTransition();
            if (implementation.node == 0 or implementation.scope == 0) continue;
            var body = implementation.node;
            const syntax = self.tree.node(body);
            if (syntax.tag == .package_unpack) body = self.tree.extra.items[syntax.c + 2];
            const boundary = self.tree.span(body);
            if (occurrence.start < boundary.start or occurrence.end > boundary.end) continue;
            const owner = self.types.node(implementation.quantified);
            if ((owner.tag != .forall and owner.tag != .existential) or owner.c > 128) continue;
            const binders = try self.allocator.dupe(T.Id, self.types.list(.{ .start = owner.b, .len = owner.c }));
            defer self.allocator.free(binders);
            var replacements: [128]T.Id = undefined;
            for (binders, replacements[0..owner.c]) |binder, *replacement| {
                const leaf = self.types.node(binder);
                replacement.* = try self.types.rigid(implementation.scope, leaf.a, leaf.b);
            }
            const goals = try self.allocator.dupe(T.Obligation, self.types.quantifierGoals(implementation.quantified));
            defer self.allocator.free(goals);
            for (goals) |goal| {
                try self.inferenceTransition();
                if (goal.kind != wanted.kind or !std.meta.eql(goal.identity, wanted.identity)) continue;
                const given = try self.types.substituteGoal(goal, binders, replacements[0..owner.c]);
                if (try self.types.equalSymbolic(try self.types.resolve(given.ty, 0), try self.types.resolve(wanted.ty, 0))) return true;
            }
        }
        return false;
    }
    fn finishDictionaryGoals(self: *Engine, body: ast.Id) T.Error!void {
        const boundary = self.tree.span(body);
        for (0..self.pending.items.len) |ordinal| {
            const pending = self.pending.items[ordinal];
            if (pending.solved or pending.value.kind != .contract or pending.value.source == 0) continue;
            const span = self.tree.span(pending.value.source);
            if (span.start < boundary.start or span.end > boundary.end) continue;
            const arguments = self.types.node(self.types.head(pending.value.ty, 0));
            if (arguments.tag != .product) continue;
            if (try self.contractGiven(pending.value.identity, self.types.list(.{ .start = arguments.a, .len = arguments.b }))) self.pending.items[ordinal].solved = true;
        }
    }
    fn finishDictionaryUses(self: *Engine, body: ast.Id) T.Error!void {
        if (self.dictionary_givens.items.len == 0) return;
        const boundary = self.tree.span(body);
        for (self.tree.nodes.items, 0..) |syntax, ordinal| {
            try self.inferenceTransition();
            if (syntax.tag != .name and syntax.tag != .field_access) continue;
            const source: ast.Id = @intCast(ordinal);
            const span = self.tree.span(source);
            if (span.start < boundary.start or span.end > boundary.end) continue;
            const target = self.resolved[source];
            const template = for (self.member_templates.items) |candidate| {
                try self.inferenceTransition();
                if (candidate.binding == target) break candidate;
            } else continue;
            var already = false;
            for (self.dictionary_uses.items) |use| {
                try self.inferenceTransition();
                if (use.source != source) continue;
                already = true;
                break;
            }
            if (already) continue;
            var selected: ?DictionaryUse = null;
            for (self.dictionary_givens.items) |given| {
                try self.inferenceTransition();
                const goal = given.predicate;
                if (goal.kind != .contract or !std.meta.eql(goal.identity, template.contract)) continue;
                const application = self.types.node(self.types.head(goal.ty, 0));
                if (application.tag != .product) return error.TypeMismatch;
                const proof: PI.SelectedProof = .{ .implementation = .{ .unit = 0, .decl = 0 }, .contract = goal.identity, .arguments = .{ .start = application.a, .len = application.b }, .members = .{}, .prerequisites = .{} };
                if (!try self.selectedReferenceWithGoal(source, template, proof, true)) continue;
                const contract = self.contracts.items[self.catalogs.contract_identities.get(goal.identity).?];
                const member = self.memberIndex(contract, template.name) orelse return error.TypeMismatch;
                if (selected != null) {
                    try self.diagnostic(.ambiguous_qualified, source);
                    break;
                }
                selected = .{ .source = source, .opening = given.opening, .introduction = given.introduction, .quantifier = given.quantifier, .goal = given.goal, .member = member - contract.members.start };
            }
            if (selected) |use| {
                try self.dictionary_uses.append(self.allocator, use);
                for (self.pending.items) |*pending| {
                    try self.inferenceTransition();
                    if (pending.value.source != source or pending.value.kind != .contract) continue;
                    if (!std.meta.eql(pending.value.identity, template.contract)) continue;
                    pending.solved = true;
                }
            }
        }
    }
    fn finishSelectedUses(self: *Engine) T.Error!void {
        if (self.selected_uses.items.len == 0) return;
        var uses: std.ArrayList(PI.SelectedUse) = .empty;
        defer uses.deinit(self.allocator);
        var seen: std.AutoHashMapUnmanaged(PI.SelectedUse, void) = .empty;
        defer seen.deinit(self.allocator);
        for (self.tree.nodes.items, 0..) |node, ordinal| {
            if (!try self.associatedStep(@intCast(ordinal))) return;
            if (node.tag != .name and node.tag != .field_access) continue;
            const binding = self.resolved[ordinal];
            const template = for (self.member_templates.items) |candidate| {
                if (candidate.binding == binding) break candidate;
            } else continue;
            const span = self.tree.span(@intCast(ordinal));
            for (self.selected_uses.items) |use| {
                if (!try self.associatedStep(@intCast(ordinal))) return;
                const enclosing = self.tree.span(use.source);
                if (span.start < enclosing.start or span.end > enclosing.end) continue;
                if (!try self.selectedReference(@intCast(ordinal), template, self.selected_proofs.items[use.proof])) continue;
                const precise: PI.SelectedUse = .{ .source = @intCast(ordinal), .proof = use.proof };
                const entry = try seen.getOrPut(self.allocator, precise);
                if (!entry.found_existing) try uses.append(self.allocator, precise);
            }
        }
        std.mem.swap(std.ArrayList(PI.SelectedUse), &self.selected_uses, &uses);
    }
    fn contractHeaders(self: *Engine) T.Error!void {
        for (self.tree.roots.items) |id| {
            const node = self.tree.node(id);
            if (node.tag != .contract_decl) continue;
            const key: Qualified = .{ .namespace = 0, .member = node.a };
            if (self.catalogs.contract_names.contains(key) or self.catalogs.nominal_names.contains(key)) {
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
            const identity: Identity = .{ .unit = self.unit, .decl = T.opaque_name_bit | node.a };
            var row_names: std.ArrayList(T.Id) = .empty;
            defer row_names.deinit(self.allocator);
            var row_parameters: std.ArrayList(T.Id) = .empty;
            defer row_parameters.deinit(self.allocator);
            for (self.row_env.items) |entry| {
                try row_names.append(self.allocator, entry.name);
                try row_parameters.append(self.allocator, entry.row);
            }
            const header_rows = try self.types.freeRowVariables(try self.types.product(parameters.items));
            defer self.allocator.free(header_rows);
            const body = self.tree.node(node.b);
            const member_start: u32 = @intCast(self.contract_members.items.len);
            var requires_implementation = false;
            for (self.tree.list(.{ .start = body.a, .len = body.b })) |child| {
                const item = self.tree.node(child);
                if (item.tag != .contract_type_member and item.tag != .contract_value_member) continue;
                if (!try self.associatedStep(child)) continue;
                var duplicate = false;
                for (self.contract_members.items[member_start..]) |member| if (member.name == item.a) {
                    duplicate = true;
                };
                if (duplicate) {
                    try self.diagnostic(.duplicate_name, child);
                    continue;
                }
                const kind: @FieldType(ContractMember, "kind") = if (item.tag == .contract_value_member) .value else if (item.b == 0) .abstract_type else .defined_type;
                requires_implementation = requires_implementation or kind != .defined_type;
                const member_index: u32 = @intCast(self.contract_members.items.len);
                try self.contract_members.append(self.allocator, .{ .contract = identity, .name = item.a, .kind = kind });
                try self.member_sources.put(self.allocator, member_index, child);
            }
            const members: T.List = .{ .start = member_start, .len = @intCast(self.contract_members.items.len - member_start) };
            self.has_associated_types = self.has_associated_types or members.len != 0;
            try self.contracts.append(self.allocator, .{ .declaration = id, .private = self.tree.declarationTraits(id).private, .identity = identity, .name = node.a, .parameters = try self.types.saveList(parameters.items), .patterns = try self.parameter_patterns.saveList(self.allocator, patterns.items), .variables = try self.types.saveList(variables.items), .parameter_names = try self.types.saveList(names.items), .members = members, .requires_implementation = requires_implementation, .row_variables = try self.types.saveList(header_rows), .row_parameter_names = try self.types.saveList(row_names.items), .row_parameters = try self.types.saveList(row_parameters.items) });
            try self.catalogs.contract_names.put(self.allocator, key, index);
            try self.catalogs.contract_identities.put(self.allocator, identity, index);
        }
        self.type_env.clearRetainingCapacity();
        self.row_env.clearRetainingCapacity();
    }
    fn resolveContract(self: *Engine, index: u32) T.Error!void {
        const contract = self.contracts.items[index];
        if (contract.identity.unit != self.unit) return;
        if (self.contract_states.get(index)) |state| {
            if (state == .visiting) try self.diagnostic(.recursive_contract, contract.declaration);
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
        for (self.types.list(contract.row_parameter_names), self.types.list(contract.row_parameters)) |name, row| try self.row_env.append(self.allocator, .{ .name = name, .row = row });
        const body = self.tree.node(contract.declaration).b;
        var predicates: std.ArrayList(T.Obligation) = .empty;
        defer predicates.deinit(self.allocator);
        const node = self.tree.node(body);
        for (self.tree.list(.{ .start = node.a, .len = node.b })) |child| {
            if (self.tree.node(child).tag == .constraint) try self.lowerPredicates(child, body, &predicates);
        }
        for (contract.members.start..contract.members.start + contract.members.len) |member| try self.resolveMember(@intCast(member));
        var roots: std.ArrayList(T.Id) = .empty;
        defer roots.deinit(self.allocator);
        for (predicates.items) |*predicate| inline for (.{ "ty", "other", "result", "signature" }) |field| {
            const root = @field(predicate, field);
            if (root != 0) {
                @field(predicate, field) = try self.types.resolve(root, 0);
                try roots.append(self.allocator, @field(predicate, field));
            }
        };
        try roots.appendSlice(self.allocator, self.types.list(contract.parameters));
        const row_variables = try self.types.freeRowVariables(try self.types.product(roots.items));
        defer self.allocator.free(row_variables);
        const start: u32 = @intCast(self.contract_predicates.items.len);
        try self.contract_predicates.appendSlice(self.allocator, predicates.items);
        self.contracts.items[index].predicates = .{ .start = start, .len = @intCast(predicates.items.len) };
        self.contracts.items[index].row_variables = try self.types.saveList(row_variables);
        try self.contract_states.put(self.allocator, index, .ready);
    }
    fn associatedStep(self: *Engine, source: ast.Id) T.Error!bool {
        if (self.inference_transitions + self.types.projection_steps >= self.inference_limit) {
            try self.diagnostic(.associated_limit, source);
            return false;
        }
        self.types.chargeProjection() catch |err| switch (err) {
            error.TypeLimit => {
                try self.diagnostic(.associated_limit, source);
                return false;
            },
            else => return err,
        };
        return true;
    }

    fn memberIndex(self: *const Engine, contract: Contract, name: u32) ?u32 {
        for (contract.members.start..contract.members.start + contract.members.len) |index| if (self.contract_members.items[index].name == name) return @intCast(index);
        return null;
    }
    fn resolveMember(self: *Engine, index: u32) T.Error!void {
        const member = self.contract_members.items[index];
        if (member.contract.unit != self.unit or member.kind == .abstract_type) return;
        if (self.member_states.contains(index)) return;
        try self.member_states.put(self.allocator, index, .visiting);
        const contract = self.contracts.items[self.catalogs.contract_identities.get(member.contract).?];
        const source = self.member_sources.get(index).?;
        const saved_types = self.type_env;
        const saved_rows = self.row_env;
        const saved_closed = self.closed_type_variables;
        const saved_implicit = self.implicit_row_parameters;
        const saved_defer = self.defer_associated;
        self.type_env = .empty;
        self.row_env = .empty;
        self.closed_type_variables = true;
        self.implicit_row_parameters = false;
        self.defer_associated = true;
        defer {
            self.type_env.deinit(self.allocator);
            self.row_env.deinit(self.allocator);
            self.type_env = saved_types;
            self.row_env = saved_rows;
            self.closed_type_variables = saved_closed;
            self.implicit_row_parameters = saved_implicit;
            self.defer_associated = saved_defer;
        }
        for (self.types.list(contract.parameter_names), self.types.list(contract.variables)) |name, variable| try self.type_env.append(self.allocator, .{ .name = name, .ty = variable });
        for (self.types.list(contract.row_parameter_names), self.types.list(contract.row_parameters)) |name, row| try self.row_env.append(self.allocator, .{ .name = name, .row = row });
        const root = try self.annotation(self.tree.node(source).b);
        if (member.kind == .defined_type) try self.unrestrictedAssociatedType(root, source);
        self.contract_members.items[index].root = root;
        try self.member_states.put(self.allocator, index, .ready);
    }
    fn projectionAnnotation(self: *Engine, symbol: u32, syntax: []const ast.Id, source: ast.Id) T.Error!?T.Id {
        const name = self.pool.get(symbol);
        const separator = std.mem.findScalarLast(u8, name, '.') orelse return null;
        const path = name[0..separator];
        const first_separator = std.mem.findScalar(u8, path, '.');
        const first_name = self.pool.lookup(if (first_separator) |at| path[0..at] else path) orelse return null;
        for (self.type_env.items) |entry| if (entry.name == first_name) {
            try self.diagnostic(.unsupported_type, source);
            return try self.types.fresh();
        };
        var key: Qualified = .{ .namespace = 0, .member = first_name };
        if (first_separator) |at| key = .{ .namespace = first_name, .member = self.pool.lookup(path[at + 1 ..]) orelse return null };
        const index = self.catalogs.contract_names.get(key) orelse return null;
        const contract = self.contracts.items[index];
        if (contract.private) {
            const span = self.tree.span(source);
            for (self.tree.roots.items) |declaration| {
                const enclosing = self.tree.span(declaration);
                if (span.start < enclosing.start or span.end > enclosing.end or self.tree.declarationTraits(declaration).private) continue;
                if (self.tree.node(declaration).tag == .value_decl) {
                    const binding = self.tree.valueDecl(declaration);
                    const annotation_span = self.tree.span(binding.annotation);
                    const where_span = self.tree.span(binding.where_node);
                    if ((binding.annotation != 0 and span.start >= annotation_span.start and span.end <= annotation_span.end) or (binding.where_node != 0 and span.start >= where_span.start and span.end <= where_span.end)) try self.diagnostic(.private_identity_escape, source);
                } else try self.diagnostic(.private_identity_escape, source);
            }
        }
        const member_name = self.pool.lookup(name[separator + 1 ..]) orelse 0;
        const member_index = self.memberIndex(contract, member_name) orelse {
            try self.diagnostic(.missing_type_member, source);
            return try self.types.fresh();
        };
        if (self.contract_members.items[member_index].kind == .value) {
            try self.diagnostic(.missing_type_member, source);
            return try self.types.fresh();
        }
        if (syntax.len != contract.parameters.len) {
            try self.diagnostic(.associated_arity, source);
            return try self.types.fresh();
        }
        const old = try self.allocator.dupe(T.Id, self.types.list(contract.variables));
        defer self.allocator.free(old);
        const fresh = try self.allocator.alloc(T.Id, old.len);
        defer self.allocator.free(fresh);
        for (fresh) |*variable| variable.* = try self.types.fresh();
        const old_rows = try self.allocator.dupe(u32, self.types.list(contract.row_variables));
        defer self.allocator.free(old_rows);
        const fresh_rows = try self.allocator.alloc(T.Effects.Id, old_rows.len);
        defer self.allocator.free(fresh_rows);
        for (fresh_rows) |*row| row.* = try self.types.freshEffects();
        const shapes = try self.allocator.dupe(T.Id, self.types.list(contract.parameters));
        defer self.allocator.free(shapes);
        var arguments: std.ArrayList(T.Id) = .empty;
        defer arguments.deinit(self.allocator);
        for (shapes, self.parameter_patterns.list(contract.patterns), syntax) |shape, pattern_, origin| {
            const actual = try self.parameterArgument(pattern_, origin, true, 0);
            try self.constrain(try self.types.substituteWithRows(shape, old, fresh, old_rows, fresh_rows), actual, origin);
            try arguments.append(self.allocator, actual);
        }
        const projection = try self.types.projection(contract.identity, member_name, arguments.items);
        if (self.defer_associated) return projection;
        return try self.normalizeAssociated(projection, source, true);
    }
    const PackEquations = struct { source: ast.Id, quantifier: T.Id, selections: T.List, binders: []const T.Id, witnesses: []const T.Id };
    const AssociatedMemo = struct {
        package_probe: bool = false,
        usage: ?@import("usage_check.zig").Memo = null,
        package: ?PackEquations = null,
        rows: std.AutoHashMapUnmanaged(T.Effects.Id, T.Effects.Id) = .empty,
        types: std.AutoHashMapUnmanaged(T.Id, T.Id) = .empty,
        projections: std.ArrayList(struct { member: u32, arguments: T.List, result: T.Id }) = .empty,
        fn deinit(self: *AssociatedMemo, allocator: Allocator) void {
            self.types.deinit(allocator);
            self.rows.deinit(allocator);
            self.projections.deinit(allocator);
            if (self.usage) |*usage| usage.deinit();
        }
    };
    fn normalizeAssociated(self: *Engine, root: T.Id, source: ast.Id, requirements: bool) T.Error!T.Id {
        var memo: AssociatedMemo = .{};
        defer memo.deinit(self.allocator);
        var active: std.ArrayList(u32) = .empty;
        defer active.deinit(self.allocator);
        return self.normalizeAssociatedNode(root, source, requirements, &memo, &active, 0);
    }
    fn normalizeAssociatedNode(self: *Engine, root: T.Id, source: ast.Id, requirements: bool, memo: *AssociatedMemo, active: *std.ArrayList(u32), depth: usize) T.Error!T.Id {
        const id = self.types.head(root, 0);
        const n = self.types.node(id);
        if (id <= T.never or n.tag == .variable or n.tag == .type_constructor) return id;
        if (memo.types.get(id)) |known| return known;
        if (depth >= 256 or !try self.associatedStep(source)) {
            if (depth >= 256) try self.diagnostic(.associated_limit, source);
            return id;
        }
        if (n.tag == .projection and memo.package_probe) {
            const result = try self.types.fresh();
            try memo.types.put(self.allocator, id, result);
            return result;
        }
        const result = switch (n.tag) {
            .projection, .nominal => blk: {
                const prior = try self.allocator.dupe(T.Id, self.types.nominalArguments(n));
                defer self.allocator.free(prior);
                var arguments: std.ArrayList(T.Id) = .empty;
                defer arguments.deinit(self.allocator);
                var changed = false;
                for (prior) |child| {
                    const next = try self.normalizeAssociatedNode(child, source, requirements, memo, active, depth + 1);
                    changed = changed or next != child;
                    try arguments.append(self.allocator, next);
                }
                if (n.tag == .nominal) {
                    if (!changed) break :blk id;
                    break :blk try self.types.nominal(.{ .unit = n.a, .decl = n.b }, arguments.items);
                }
                if (memo.package) |equations| break :blk try self.packageProjection(id, arguments.items, equations, source);
                const identity: Identity = .{ .unit = n.a, .decl = n.b };
                const contract_index = self.catalogs.contract_identities.get(identity) orelse {
                    try self.diagnostic(.missing_type_member, source);
                    break :blk id;
                };
                const contract = self.contracts.items[contract_index];
                const member_name = self.types.projectionMember(n);
                const member_index = self.memberIndex(contract, member_name) orelse {
                    try self.diagnostic(.missing_type_member, source);
                    break :blk id;
                };
                if (inList(active.items, member_index)) {
                    try self.diagnostic(.recursive_associated_type, source);
                    break :blk id;
                }
                for (memo.projections.items) |cached| {
                    if (!try self.associatedStep(source)) break :blk id;
                    if (cached.member != member_index or cached.arguments.len != arguments.items.len) continue;
                    var same = true;
                    for (self.types.list(cached.arguments), arguments.items) |before, after| if (!try self.types.equalSymbolic(before, after)) {
                        same = false;
                        break;
                    };
                    if (same) {
                        self.counters.projection_memo_hits += 1;
                        break :blk cached.result;
                    }
                }
                try self.resolveMember(member_index);
                const member = self.contract_members.items[member_index];
                const old = try self.allocator.dupe(T.Id, self.types.list(contract.variables));
                defer self.allocator.free(old);
                const fresh = try self.allocator.alloc(T.Id, old.len);
                defer self.allocator.free(fresh);
                for (fresh) |*variable| variable.* = try self.types.fresh();
                const old_rows = try self.allocator.dupe(u32, self.types.list(contract.row_variables));
                defer self.allocator.free(old_rows);
                const fresh_rows = try self.allocator.alloc(T.Effects.Id, old_rows.len);
                defer self.allocator.free(fresh_rows);
                for (fresh_rows) |*row| row.* = try self.types.freshEffects();
                const shapes = try self.allocator.dupe(T.Id, self.types.list(contract.parameters));
                defer self.allocator.free(shapes);
                for (shapes, arguments.items) |shape, actual| try self.constrain(try self.types.substituteWithRows(shape, old, fresh, old_rows, fresh_rows), actual, source);
                if (try self.implementationEquation(identity, member_name, arguments.items)) |equation| break :blk equation;
                if (try self.provisionalEquation(identity, member_name, arguments.items)) |equation| {
                    try active.append(self.allocator, member_index);
                    defer _ = active.pop();
                    break :blk try self.normalizeAssociatedNode(equation, source, requirements, memo, active, depth + 1);
                }
                const lexical = try self.contractGiven(identity, arguments.items);
                var selected_proof: ?u32 = null;
                if (contract.requires_implementation and !lexical) selected_proof = try self.selectImplementation(identity, arguments.items, source);
                if (selected_proof) |proof| {
                    if (member.kind != .defined_type) {
                        if (self.selectedMember(proof, member_name)) |selected| break :blk selected.root;
                    }
                }
                if (requirements) {
                    try self.resolveContract(contract_index);
                    const resolved_contract = self.contracts.items[contract_index];
                    for (self.contract_predicates.items[resolved_contract.predicates.start..][0..resolved_contract.predicates.len]) |predicate| {
                        var instantiated = predicate;
                        inline for (.{ "ty", "other", "result", "signature" }) |field| @field(instantiated, field) = try self.types.substituteWithRows(@field(predicate, field), old, fresh, old_rows, fresh_rows);
                        instantiated.source = source;
                        instantiated.explicit = true;
                        instantiated.qualification_unit = self.unit;
                        instantiated.qualification_span = self.tree.span(source);
                        if (instantiated.kind == .type_eq and try self.types.equalSymbolic(instantiated.ty, instantiated.result)) continue;
                        if (self.closed_type_variables and !self.implicit_row_parameters and self.current == 0 and try self.requirementOpen(instantiated)) try self.diagnostic(.missing_predicate, source);
                        try self.appendPending(.{ .owner = self.current, .value = instantiated, .suspended = true });
                    }
                    if (contract.requires_implementation and selected_proof == null and !lexical) {
                        const requirement: T.Obligation = .{ .kind = .contract, .identity = identity, .ty = try self.types.product(arguments.items), .source = source, .explicit = true };
                        if (self.closed_type_variables and !self.implicit_row_parameters and self.current == 0 and self.checking_implementation == null) {
                            var code: Code = .missing_implementation;
                            if (try self.requirementOpen(requirement)) code = .missing_predicate;
                            try self.diagnostic(code, source);
                        }
                        try self.appendPending(.{ .owner = self.current, .value = requirement, .suspended = true });
                    }
                }
                if (member.kind != .defined_type) {
                    if (!changed) break :blk id;
                    break :blk try self.types.projection(identity, member_name, arguments.items);
                }
                try active.append(self.allocator, member_index);
                defer _ = active.pop();
                const expanded = try self.types.substituteWithRows(member.root, old, fresh, old_rows, fresh_rows);
                const normalized = try self.normalizeAssociatedNode(expanded, source, requirements, memo, active, depth + 1);
                if (memo.usage == null) memo.usage = .{ .allocator = self.allocator };
                if (try @import("usage_check.zig").containsNominalMemoWork(&self.types, self.nominals.items, normalized, &self.associated_usage_work, &memo.usage.?)) try self.diagnostic(.usage_evidence_mismatch, source);
                const argument_span = try self.types.saveList(arguments.items);
                try memo.projections.append(self.allocator, .{ .member = member_index, .arguments = argument_span, .result = normalized });
                break :blk normalized;
            },
            .function => blk: {
                const a = try self.normalizeAssociatedNode(n.a, source, requirements, memo, active, depth + 1);
                const b = try self.normalizeAssociatedNode(n.b, source, requirements, memo, active, depth + 1);
                const row = try self.normalizeAssociatedRow(n.c, source, requirements, memo, active, depth + 1);
                if (a == n.a and b == n.b and row == n.c) break :blk id;
                break :blk try self.types.functionWithEffects(a, b, row);
            },
            .product => blk: {
                const prior = try self.allocator.dupe(T.Id, self.types.list(.{ .start = n.a, .len = n.b }));
                defer self.allocator.free(prior);
                var fields: std.ArrayList(T.Id) = .empty;
                defer fields.deinit(self.allocator);
                var changed = false;
                for (prior) |child| {
                    const next = try self.normalizeAssociatedNode(child, source, requirements, memo, active, depth + 1);
                    changed = changed or next != child;
                    try fields.append(self.allocator, next);
                }
                if (!changed) break :blk id;
                break :blk try self.types.product(fields.items);
            },
            .record => blk: {
                var fields: std.ArrayList(T.Field) = .empty;
                defer fields.deinit(self.allocator);
                var changed = false;
                for (0..n.b) |at| {
                    const field = self.types.recordField(n, at);
                    const next = try self.normalizeAssociatedNode(field.ty, source, requirements, memo, active, depth + 1);
                    changed = changed or next != field.ty;
                    try fields.append(self.allocator, .{ .name = field.name, .ty = next });
                }
                if (!changed) break :blk id;
                break :blk try self.types.record(fields.items);
            },
            .array, .list, .cursor, .resolver, .demand, .provider => blk: {
                const child = try self.normalizeAssociatedNode(n.a, source, requirements, memo, active, depth + 1);
                const row = if (n.tag == .demand or n.tag == .provider) try self.normalizeAssociatedRow(n.c, source, requirements, memo, active, depth + 1) else n.c;
                if (child == n.a and row == n.c) break :blk id;
                break :blk switch (n.tag) {
                    .resolver => try self.types.resolver(child),
                    .demand => try self.types.demandWithEffects(child, row),
                    .provider => try self.types.provider(child, row),
                    else => try self.types.sequence(n.tag, child),
                };
            },
            .usage => blk: {
                const child = try self.normalizeAssociatedNode(n.a, source, requirements, memo, active, depth + 1);
                if (child == n.a) break :blk id;
                break :blk try self.types.usage(child, @fromBackingInt(@intCast(n.b)), n.c);
            },
            .state_provider => blk: {
                const a = try self.normalizeAssociatedNode(n.a, source, requirements, memo, active, depth + 1);
                const b = try self.normalizeAssociatedNode(n.b, source, requirements, memo, active, depth + 1);
                const c = try self.normalizeAssociatedNode(n.c, source, requirements, memo, active, depth + 1);
                if (a == n.a and b == n.b and c == n.c) break :blk id;
                break :blk try self.types.stateProvider(a, b, c);
            },
            else => id,
        };
        try memo.types.put(self.allocator, id, result);
        return result;
    }
    fn normalizeAssociatedRow(self: *Engine, root: T.Effects.Id, source: ast.Id, requirements: bool, memo: *AssociatedMemo, active: *std.ArrayList(u32), depth: usize) T.Error!T.Effects.Id {
        if (memo.rows.get(root)) |known| return known;
        if (depth >= 256) return error.TypeLimit;
        const id = try self.types.resolveEffects(root, 0);
        const row = self.types.row(id);
        const labels = try self.allocator.dupe(T.Effects.Label, self.types.rowLabels(id));
        defer self.allocator.free(labels);
        var changed = false;
        for (labels) |*label| {
            try self.types.chargeProjection();
            const operation = self.types.operation(label.*);
            const arguments = try self.allocator.dupe(T.Id, self.types.operationArguments(label.*));
            defer self.allocator.free(arguments);
            for (arguments) |*argument| argument.* = try self.normalizeAssociatedNode(argument.*, source, requirements, memo, active, depth + 1);
            const next = try self.types.internScopedOperation(operation.identity, operation.instance, arguments);
            changed = changed or next != label.*;
            label.* = next;
        }
        const result = if (changed) self.types.effects.rowAt(labels, row.tail, row.cursor) catch |err| return T.effectError(err) else id;
        try memo.rows.put(self.allocator, root, result);
        return result;
    }
    fn validateMemberRequirements(self: *Engine, index: u32) T.Error!void {
        const member = self.contract_members.items[index];
        if (member.root == 0 or member.contract.unit != self.unit) return;
        const contract = self.contracts.items[self.catalogs.contract_identities.get(member.contract).?];
        const source = self.member_sources.get(index).?;
        const start = self.pending.items.len;
        defer self.pending.shrinkRetainingCapacity(start);
        _ = try self.normalizeAssociated(member.root, source, true);
        var cursor = start;
        while (cursor < self.pending.items.len) : (cursor += 1) {
            const pending = self.pending.items[cursor];
            const wanted = pending.value;
            if (wanted.kind == .contract and std.meta.eql(wanted.identity, contract.identity)) continue;
            var supplied = false;
            for (self.contract_predicates.items[contract.predicates.start..][0..contract.predicates.len]) |given| {
                if (try self.unifyRequirement(wanted, given)) {
                    supplied = true;
                    break;
                }
            }
            if (supplied) continue;
            if (try self.requirementOpen(wanted) or wanted.kind == .contract) {
                try self.diagnostic(.missing_predicate, source);
                continue;
            }
            self.pending.items[cursor].suspended = false;
            _ = try self.attemptPending(cursor, self.pending.items[cursor]);
            if (!self.pending.items[cursor].solved) try self.diagnostic(.missing_predicate, source);
        }
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
            if (self.catalogs.nominal_names.contains(key)) {
                try self.diagnostic(.duplicate_name, id);
                continue;
            }
            const index: u32 = @intCast(self.nominals.items.len);
            var identity: Identity = .{ .unit = self.unit, .decl = id };
            if (self.tree.declarationTraits(id).is_opaque) identity.decl = n.a | T.opaque_name_bit;
            try self.nominals.append(self.allocator, .{ .private = self.tree.declarationTraits(id).private, .is_opaque = self.tree.declarationTraits(id).is_opaque, .declaration = id, .identity = identity, .name = n.a, .parameters = .{}, .variables = .{} });
            try self.catalogs.nominal_identities.put(self.allocator, identity, index);
            try self.catalogs.nominal_names.put(self.allocator, key, index);
        }
        for (self.nominals.items[1..], 1..) |nominal_, index| {
            if (nominal_.identity.unit != self.unit) continue;
            const n = self.tree.node(nominal_.declaration);
            const meta = self.tree.extra.items[n.c..][0..4];
            if (meta[3] != 0) try self.diagnostic(.unsupported_attribute, nominal_.declaration);
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
        if (nominal_.identity.unit != self.unit or self.tree.node(nominal_.declaration).tag != .type_alias_decl) return 0;
        if (self.active_aliases.contains(index)) {
            try self.diagnostic(.recursive_type_alias, nominal_.declaration);
            return self.types.fresh();
        }
        if (self.active_aliases.count() >= 256) return error.TypeLimit;
        try self.active_aliases.put(self.allocator, index, {});
        defer _ = self.active_aliases.remove(index);
        const saved_defer = self.defer_associated;
        self.defer_associated = true;
        defer self.defer_associated = saved_defer;
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
        const target = try self.annotation(self.tree.node(nominal_.declaration).b);
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
        const expanded = try self.types.substituteWithRows(alias, old, fresh, rows, fresh_rows);
        if (self.defer_associated or !self.has_associated_types) return expanded;
        return try self.normalizeAssociated(expanded, source, true);
    }
    fn dataBodies(self: *Engine) T.Error!void {
        self.closed_type_variables = true;
        defer self.closed_type_variables = false;
        var index: usize = 1;
        while (index < self.nominals.items.len) : (index += 1) {
            const nominal_ = self.nominals.items[index];
            if (nominal_.identity.unit != self.unit) continue;
            if (self.tree.node(nominal_.declaration).tag == .type_alias_decl) {
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
            const declaration = self.tree.node(nominal_.declaration);
            for (self.tree.children(declaration.b), 0..) |id, tag| {
                const n = self.tree.node(id);
                const key = self.catalogKey(n.a);
                if (self.catalogs.constructor_names.contains(key)) {
                    try self.diagnostic(.duplicate_name, id);
                    continue;
                }
                var payload = if (n.b == 0) 0 else try self.constructorPayloadAnnotation(n.b);
                if (payload != 0) {
                    const shape = self.types.node(payload);
                    if (!nominal_.is_opaque and shape.tag == .record and shape.b == 0) payload = 0;
                }
                const storage = self.types.node(payload);
                var parameter = payload;
                if (!nominal_.is_opaque and payload != 0 and storage.tag == .record) parameter = try self.canonicalRecordType(storage);
                const ty = if (payload == 0) result else try self.types.function(parameter, result);
                const constructor: u32 = @intCast(self.constructors.items.len);
                try self.constructors.append(self.allocator, .{ .private = nominal_.private or nominal_.is_opaque, .identity = .{ .unit = self.unit, .decl = id }, .nominal = @intCast(index), .tag = @intCast(tag), .name = n.a, .payload = payload, .declared_record = !nominal_.is_opaque and n.b != 0 and self.tree.node(n.b).tag == .type_record and self.tree.typeConversionOrigin(n.b) == self.tree.span(n.b).start, .scheme = .{ .root = ty, .variables = nominal_.variables } });
                try self.catalogs.constructor_identities.put(self.allocator, .{ .unit = self.unit, .decl = id }, constructor);
                try self.catalogs.constructor_names.put(self.allocator, key, constructor);
                try constructors.append(self.allocator, constructor);
                self.constructor_resolved[id] = constructor;
            }
            self.nominals.items[index].constructors = try self.types.saveList(constructors.items);
        }
        // The least fixed point exposes affinity without exposing opaque
        // payloads. A recursive family gains affinity only from a real owner.
        var imported_affinity = false;
        for (self.nominals.items) |nominal| if (nominal.identity.unit != self.unit and nominal.has_usage) {
            imported_affinity = true;
            break;
        };
        if (self.types.has_usage_types or imported_affinity) {
            var affinity_work: @import("usage_check.zig").Work = .{};
            for (0..self.nominals.items.len) |_| {
                try affinity_work.charge(1);
                var changed = false;
                for (self.constructors.items) |constructor| {
                    try affinity_work.charge(1);
                    if (constructor.payload == 0) continue;
                    const facts = &self.nominals.items[constructor.nominal];
                    if (!facts.affine and try @import("usage_check.zig").affineNominalWork(&self.types, self.nominals.items, constructor.payload, &affinity_work)) {
                        facts.affine = true;
                        changed = true;
                    }
                    if (!facts.has_usage and try @import("usage_check.zig").containsNominalWork(&self.types, self.nominals.items, constructor.payload, &affinity_work)) {
                        facts.has_usage = true;
                        changed = true;
                    }
                }
                if (!changed) break;
            }
        }
        var storage_work: @import("usage_check.zig").Work = .{};
        @import("closed_nominal_storage.zig").facts(&self.types, self.nominals.items, self.constructors.items, self.unit, &storage_work) catch |err| {
            if (err != error.TypeLimit) return err;
            // Ordinary typing needs no optional storage authority. A later
            // resource use must supply a successful bounded proof instead.
            for (self.nominals.items) |*nominal| if (nominal.identity.unit == self.unit) {
                nominal.closed_storage = false;
            };
        };
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
            if (self.catalogs.effect_family_names.contains(key) or self.catalogs.nominal_names.contains(key) or self.catalogs.globals.contains(n.a)) {
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
            try self.effect_families.append(self.allocator, .{ .private = self.tree.declarationTraits(id).private, .identity = .{ .unit = self.unit, .decl = id }, .name = n.a, .callable = self.tree.node(n.b).tag != .effect_operations, .patterns = try self.parameter_patterns.saveList(self.allocator, patterns.items), .parameters = try self.types.saveList(parameters.items), .variables = try self.types.saveList(variables.items), .parameter_names = try self.types.saveList(names.items) });
            try self.catalogs.effect_family_names.put(self.allocator, key, family);
            try self.catalogs.effect_family_identities.put(self.allocator, .{ .unit = self.unit, .decl = id }, family);
            var operations: std.ArrayList(T.Id) = .empty;
            defer operations.deinit(self.allocator);
            if (self.tree.node(n.b).tag == .effect_operations) {
                for (self.tree.children(n.b)) |member| {
                    const operation_ = self.tree.node(member);
                    if (self.catalogs.effect_members.contains(.{ .family = family, .member = operation_.a })) {
                        try self.diagnostic(.duplicate_name, member);
                        continue;
                    }
                    const template = try self.effectSignature(family, member, operation_.a, operation_.b);
                    try self.catalogs.effect_members.put(self.allocator, .{ .family = family, .member = operation_.a }, template);
                    try operations.append(self.allocator, template);
                }
            } else {
                const template = try self.effectSignature(family, id, n.a, n.b);
                try self.catalogs.effect_operation_names.put(self.allocator, key, template);
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
        try self.catalogs.effect_template_identities.put(self.allocator, .{ .unit = self.unit, .decl = identity }, index);
        return index;
    }
    fn textCatalogKey(self: *const Engine, text: []const u8) ?Qualified {
        const separator = std.mem.findScalar(u8, text, '.') orelse
            return .{ .namespace = 0, .member = self.pool.lookup(text) orelse return null };
        return .{ .namespace = self.pool.lookup(text[0..separator]) orelse return null, .member = self.pool.lookup(text[separator + 1 ..]) orelse return null };
    }
    fn operationTemplate(self: *Engine, name: symbols.Symbol) T.Error!?u32 {
        if (self.lookup(name) != null or try self.globalBinding(name) != null) return null;
        const text = self.pool.get(name);
        const root_end = std.mem.findScalar(u8, text, '.') orelse text.len;
        if (self.pool.lookup(text[0..root_end])) |root| if (self.lookup(root) != null or self.catalogs.globals.contains(root)) return null;
        return self.catalogOperationTemplate(name);
    }
    fn catalogOperationTemplate(self: *const Engine, name: symbols.Symbol) ?u32 {
        const text = self.pool.get(name);
        if (self.catalogs.effect_operation_names.get(self.catalogKey(name))) |single| return single;
        const separator = std.mem.findScalarLast(u8, text, '.') orelse return null;
        const family_key = self.textCatalogKey(text[0..separator]) orelse return null;
        const family = self.catalogs.effect_family_names.get(family_key) orelse return null;
        const member = self.pool.lookup(text[separator + 1 ..]) orelse return null;
        return self.catalogs.effect_members.get(.{ .family = family, .member = member });
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
        if (self.catalogs.effect_template_identities.get(identity)) |existing| return existing;
        if (self.effect_templates.items.len == std.math.maxInt(u32)) return error.TypeLimit;
        const state = try self.types.fresh();
        const index: u32 = @intCast(self.effect_templates.items.len);
        try self.effect_templates.append(self.allocator, .{ .identity = identity, .family = 0, .name = 0, .parameter = if (read) T.unit else state, .result = if (read) state else T.unit });
        try self.catalogs.effect_template_identities.put(self.allocator, identity, index);
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
        if (!read and self.active_effect_scopes != 0 and try self.scopeFootprint(operand, 0)) try self.diagnostic(.capability_escape, syntax.b);
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
        if (use.instance.decl != 0) {
            try self.diagnostic(.open_effect_descriptor, original);
            return null;
        }
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
    fn stagingApplication(self: *Engine, id: ast.Id) T.Error!?T.Id {
        var head = id;
        var backwards: [2]ast.Id = undefined;
        var count: usize = 0;
        while (self.tree.node(head).tag == .apply) {
            const application = self.tree.node(head);
            if (count < backwards.len) backwards[count] = application.b;
            count += 1;
            head = application.a;
        }
        const syntax = self.tree.node(head);
        if (syntax.tag != .intrinsic) return null;
        const op = staging.lookup(self.pool.get(syntax.a)) orelse return null;
        if (count != staging.arity(op)) {
            try self.diagnostic(.call_arity, id);
            return try self.types.fresh();
        }
        const operand = backwards[count - 1];
        if (op == .quote) {
            if (self.staging_depth >= 128) {
                try self.diagnostic(.staging_budget, id);
                return try self.types.fresh();
            }
            const parent = self.ambient;
            self.ambient = try self.types.freshEffects();
            const latent = self.ambient;
            self.staging_depth += 1;
            defer {
                self.staging_depth -= 1;
                self.ambient = parent;
            }
            const result = try self.expression(operand);
            const function = try self.types.functionWithEffects(T.unit, result, latent);
            const certified = self.types.node(try self.certifiedLambdaType(id, function, parent));
            const code_type = try staging.code(&self.types, certified.b, certified.c);
            if (try @import("rank_walk.zig").contains(&self.types, code_type, 0, false)) try self.diagnostic(.cross_stage_authority, id);
            return code_type;
        }
        if (op == .splice or op == .lift) {
            if (self.staging_depth == 0) {
                try self.diagnostic(.stage_unavailable, id);
                return try self.types.fresh();
            }
            const future = self.ambient;
            self.ambient = try self.types.freshEffects();
            const construction = self.ambient;
            self.staging_depth -= 1;
            const value = self.expression(operand) catch |err| {
                self.staging_depth += 1;
                self.ambient = future;
                return err;
            };
            self.staging_depth += 1;
            self.ambient = future;
            try self.constrainEffects(construction, 0, operand);
            if (op == .lift) {
                // Nominal arguments prove the source shape. Quote evaluation
                // checks every actual payload before installing a lifted value.
                if (try @import("usage_check.zig").containsNominal(&self.types, self.nominals.items, value) or !try staging.liftable(&self.types, value)) try self.diagnostic(.cross_stage_authority, operand);
                return value;
            }
            const code_type = staging.codeInfo(&self.types, try self.types.resolve(value, 0)) orelse {
                try self.diagnostic(.code_shape_mismatch, operand);
                return try self.types.fresh();
            };
            try self.stagingEffects(code_type.effects, id);
            return code_type.result;
        }
        const value = try self.expression(operand);
        if (op == .same) {
            const right = try self.expression(backwards[0]);
            if (staging.descriptorInfo(&self.types, try self.types.resolve(value, 0)) == null or staging.descriptorInfo(&self.types, try self.types.resolve(right, 0)) == null) try self.diagnostic(.code_shape_mismatch, id);
            return T.boolean;
        }
        if (op == .fields) {
            const target = staging.descriptorInfo(&self.types, try self.types.resolve(value, 0)) orelse {
                try self.diagnostic(.code_shape_mismatch, operand);
                return try self.types.fresh();
            };
            return try self.descriptorFields(target, id);
        }
        const code_type = staging.codeInfo(&self.types, try self.types.resolve(value, 0)) orelse {
            try self.diagnostic(.code_shape_mismatch, operand);
            return try self.types.fresh();
        };
        if (op == .describe) {
            const name = self.pool.intern(self.allocator, "result") catch |err| switch (err) {
                error.SymbolLimit => return error.TypeLimit,
                error.OutOfMemory => return error.OutOfMemory,
            };
            const effects = self.pool.intern(self.allocator, "effects") catch |err| switch (err) {
                error.SymbolLimit => return error.TypeLimit,
                error.OutOfMemory => return error.OutOfMemory,
            };
            return try self.types.record(&.{ .{ .name = name, .ty = try staging.descriptor(&self.types, code_type.result) }, .{ .name = effects, .ty = try self.reflectionType(false) } });
        }
        if (op == .run) {
            const latent = self.types.row(try self.types.resolveEffects(code_type.effects, 0));
            if (latent.labels.len != 0 or latent.tail != .closed) try self.diagnostic(.const_effect, id);
        } else try self.stagingEffects(code_type.effects, id);
        return code_type.result;
    }
    fn descriptorFields(self: *Engine, original: T.Id, source: ast.Id) T.Error!T.Id {
        const target = try self.types.resolve(original, 0);
        const shape = self.types.node(target);
        var fields: std.ArrayList(T.Field) = .empty;
        defer fields.deinit(self.allocator);
        if (shape.tag == .record) {
            for (0..shape.b) |index| try fields.append(self.allocator, self.types.recordField(shape, index));
        } else if (shape.tag == .nominal) {
            const index = self.nominalIndex(.{ .unit = shape.a, .decl = shape.b }) orelse {
                try self.diagnostic(.descriptor_private, source);
                return self.types.fresh();
            };
            const family = self.nominals.items[index];
            if (family.private or family.is_opaque or family.constructors.len == 0) {
                try self.diagnostic(.descriptor_private, source);
                return self.types.fresh();
            }
            const constructors = try self.allocator.dupe(T.Id, self.types.list(family.constructors));
            defer self.allocator.free(constructors);
            for (constructors, 0..) |constructor, variant| {
                if (self.constructors.items[constructor].scheme.variables.len > 32) {
                    try self.diagnostic(.staging_budget, source);
                    return self.types.fresh();
                }
                const instance_type = try self.constructorStorageType(constructor);
                const instance = self.types.node(instance_type);
                var payload: T.Node = .{ .tag = .record };
                if (instance.tag == .function) {
                    try self.constrain(instance.b, target, source);
                    payload = self.types.node(try self.types.resolve(instance.a, 0));
                } else try self.constrain(instance_type, target, source);
                if (payload.tag != .record) {
                    fields.clearRetainingCapacity();
                    break;
                }
                if (variant == 0) {
                    for (0..payload.b) |field| try fields.append(self.allocator, self.types.recordField(payload, field));
                    continue;
                }
                var count: usize = 0;
                for (fields.items) |field| {
                    for (0..payload.b) |field_index| {
                        const other = self.types.recordField(payload, field_index);
                        if (other.name != field.name) continue;
                        try self.constrain(field.ty, other.ty, source);
                        fields.items[count] = field;
                        count += 1;
                        break;
                    }
                }
                fields.items.len = count;
            }
        } else {
            try self.diagnostic(.descriptor_private, source);
            return self.types.fresh();
        }
        for (fields.items) |*field| field.ty = try @import("typed_staging.zig").descriptor(&self.types, try self.types.resolve(field.ty, 0));
        return self.types.record(fields.items);
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
            if (argument.tag == .field_access and self.tree.node(argument.a).tag == .name and self.lookup(self.tree.node(argument.a).a) == null) binding = self.catalogs.qualified.get(.{ .namespace = self.tree.node(argument.a).a, .member = argument.b });
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
            var closed = self.types.row(row).tail == .closed;
            for (self.types.rowLabels(row)) |label| {
                for (self.types.operationArguments(label)) |argument| closed = closed and try self.types.equalClosed(argument, argument);
            }
            if (!closed) {
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
        if (text.len == 0 or (!std.ascii.isLower(text[0]) and text[0] != '_') or std.mem.findScalar(u8, text, '.') != null) {
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
                return self.catalogs.nominal_names.contains(self.catalogKey(n.a));
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
                if (self.catalogs.nominal_names.get(self.catalogKey(n.a))) |index| {
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
                const index = self.catalogs.nominal_names.get(self.catalogKey(symbol)) orelse return error.TypeLimit;
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
            if (self.active_effect_scopes != 0 and try self.scopeFootprint(argument, 0) and (!lazy or try self.demandCaptureFootprint(syntax.b)) and !try self.localStateStore(syntax.a, syntax.b, argument)) try self.diagnostic(.capability_escape, syntax.b);
            self.demand_calls[application] = lazy;
            if (lazy) {
                self.demand_types[application] = function.a;
                self.demand_once[application] = try self.declaredAffineDemand(function.a);
            }
            const result = try self.types.fresh();
            try self.constrain(ty, try self.invocation(argument, result), application);
            ty = result;
            self.expr_types[application] = ty;
        }
        return ty;
    }
    // This first slice proves only structural data footprints. Callable,
    // opaque and unresolved results retain an unknown footprint.
    fn scopeFootprint(self: *Engine, root: T.Id, depth: usize) T.Error!bool {
        var remaining: usize = 65_536;
        return self.scopeFootprintDepth(root, depth, &remaining, &.{}, .{});
    }
    const FootprintBoundary = struct { rank_scope: u32 = 0, exiting: ?Identity = null, storage_depth: ?usize = null, loan: T.Id = 0, capture_usage: bool = false, task_group: T.Id = 0 };
    fn identityFootprint(self: *Engine, identity: Identity, boundary: FootprintBoundary) T.Error!bool {
        if (boundary.task_group != 0) {
            var destination: ?usize = null;
            for (self.scope_lifetimes.items, 0..) |scope, index| {
                if (self.types.head(scope, 0) == self.types.head(boundary.task_group, 0)) destination = index;
            }
            const limit = destination orelse return true;
            for (self.scope_lifetimes.items, 0..) |scope, index| {
                const capability = self.types.node(self.types.head(scope, 0));
                if (!@import("task_types.zig").isRegion(&self.types, self.types.head(scope, 0))) continue;
                if (capability.b == identity.unit and capability.c == identity.decl) return index > limit;
            }
            return true;
        }
        if (boundary.rank_scope != 0 and identity.unit != 0) return false;
        if (boundary.loan != 0) return false;
        if (identity.unit == 0 and identity.decl != 0 and self.types.node(identity.decl).tag == .instance_selection) {
            var remaining: usize = 65_536;
            return self.scopeFootprintDepth(identity.decl, 0, &remaining, &.{}, boundary);
        }
        if (boundary.storage_depth) |depth| {
            if (identity.unit == 0 and identity.decl == 0) return false;
            for (self.scope_lifetimes.items[0..depth]) |capability| {
                const value = self.types.node(try self.types.resolve(capability, 0));
                if (value.tag == .scoped and value.b == identity.unit and value.c == identity.decl) return false;
            }
            return true;
        }
        if (boundary.rank_scope != 0) return false;
        if (boundary.exiting) |owner| return std.meta.eql(owner, identity);
        return true;
    }
    fn scopeFootprintDepth(self: *Engine, root: T.Id, depth: usize, remaining: *usize, inherited: []const T.Id, boundary: FootprintBoundary) T.Error!bool {
        if (depth >= 128 or remaining.* == 0) {
            try self.diagnostic(.capability_analysis_limit, self.owner);
            return true;
        }
        remaining.* -= 1;
        if (boundary.rank_scope != 0) return @import("rank_walk.zig").containsExcept(&self.types, root, boundary.rank_scope, inherited, remaining);
        const resolved = try self.types.resolve(root, 0);
        const value = self.types.node(resolved);
        switch (value.tag) {
            .variable => return !inList(inherited, resolved),
            .scoped => {
                if (boundary.capture_usage) return true;
                if (value.b == 0 and self.types.node(value.c).tag == .instance_selection) return self.scopeFootprintDepth(value.c, depth + 1, remaining, inherited, boundary);
                return self.identityFootprint(.{ .unit = value.b, .decl = value.c }, boundary);
            },
            .instance_selection => {
                const choices = self.types.nominalArguments(value);
                const left = choices[0];
                const right = choices[1];
                return try self.scopeFootprintDepth(left, depth + 1, remaining, inherited, boundary) or try self.scopeFootprintDepth(right, depth + 1, remaining, inherited, boundary);
            },
            .unit, .boolean, .u32, .f32, .never => return false,
            .usage => {
                if (boundary.capture_usage) return true;
                if (boundary.loan != 0 and value.c == boundary.loan) return true;
                return self.scopeFootprintDepth(value.a, depth + 1, remaining, inherited, boundary);
            },
            .demand => {
                if (boundary.task_group == 0) return true;
                var budget: usize = remaining.*;
                if (try self.taskCaptureType(resolved, false, &budget, depth + 1) != null) return true;
                remaining.* = budget;
                return self.scopeFootprintDepth(value.a, depth + 1, remaining, inherited, boundary);
            },
            .array, .list, .cursor => return self.scopeFootprintDepth(value.a, depth + 1, remaining, inherited, boundary),
            .product => {
                const children = try self.allocator.dupe(T.Id, self.types.list(.{ .start = value.a, .len = value.b }));
                defer self.allocator.free(children);
                for (children) |child| if (try self.scopeFootprintDepth(child, depth + 1, remaining, inherited, boundary)) return true;
                return false;
            },
            .record => {
                for (0..value.b) |index| if (try self.scopeFootprintDepth(self.types.recordField(value, index).ty, depth + 1, remaining, inherited, boundary)) return true;
                return false;
            },
            else => return true,
        }
    }
    // This proof is confined to the requesting expression's source. A named
    // helper needs a durable capture/store contract before its body can license
    // a transfer through an otherwise unchanged semantic interface.
    fn dictionaryGoalFootprint(self: *Engine, source: ast.Id, boundary: FootprintBoundary, inherited: []const T.Id, remaining: *usize) T.Error!bool {
        if (boundary.rank_scope == 0) return false;
        for (self.dictionary_uses.items) |use| {
            if (remaining.* == 0) return error.TypeLimit;
            remaining.* -= 1;
            if (use.source != source or use.opening == 0 or use.opening >= self.bindings.items.len) continue;
            const declaration = self.bindings.items[use.opening].declaration;
            const opening = self.tree.node(declaration);
            if (opening.tag != .package_unpack) return error.TypeLimit;
            const owner = self.types.node(use.quantifier);
            const goals = self.types.quantifierGoals(use.quantifier);
            if (owner.tag != .existential or use.goal >= goals.len) return error.TypeLimit;
            const goal = goals[use.goal];
            const binders = try self.allocator.dupe(T.Id, self.types.list(.{ .start = owner.b, .len = owner.c }));
            defer self.allocator.free(binders);
            var replacements: std.ArrayList(T.Id) = .empty;
            defer replacements.deinit(self.allocator);
            for (self.tree.list(.{ .start = opening.b, .len = owner.c })) |binder| try replacements.append(self.allocator, self.expr_types[binder]);
            const instantiated = try self.types.substituteGoal(goal, binders, replacements.items);
            inline for (.{ "ty", "other", "result", "signature" }) |field| {
                const endpoint = @field(instantiated, field);
                if (endpoint != 0 and try @import("rank_walk.zig").containsExcept(&self.types, endpoint, boundary.rank_scope, inherited, remaining)) return true;
            }
        }
        return false;
    }
    fn demandCaptureFootprint(self: *Engine, source: ast.Id) T.Error!bool {
        var remaining: usize = 65_536;
        return self.closureCaptureFootprint(source, source, .{ .capture_usage = true }, &.{}, &remaining, 0);
    }
    fn closureCaptureFootprint(self: *Engine, source: ast.Id, closure: ast.Id, boundary: FootprintBoundary, inherited: []const T.Id, remaining: *usize, depth: usize) T.Error!bool {
        if (source == 0) return false;
        if (depth >= 128 or remaining.* == 0) {
            try self.diagnostic(.capability_analysis_limit, self.owner);
            return true;
        }
        remaining.* -= 1;
        if (try self.dictionaryGoalFootprint(source, boundary, inherited, remaining)) return true;
        const value = self.tree.node(source);
        switch (value.tag) {
            .name => {
                const binding = self.resolved[source];
                if (binding == 0 or self.bindings.items[binding].owner == closure) return false;
                const captured = self.bindings.items[binding];
                if ((boundary.capture_usage or boundary.task_group != 0) and closure != 0 and captured.declaration != 0 and (captured.kind == .parameter or captured.kind == .local)) {
                    const birth = self.tree.span(captured.declaration);
                    const body = self.tree.span(closure);
                    if (birth.start >= body.start and birth.end <= body.end) return false;
                }
                if (boundary.task_group != 0) {
                    var budget: usize = 8192;
                    var capture_type = captured.ty;
                    if (captured.kind == .global or captured.kind == .external) {
                        capture_type = captured.scheme.root;
                        if (captured.named_function and self.expr_types[source] != 0) capture_type = self.expr_types[source];
                    }
                    if (captured.named_function) {
                        var formal = captured.scheme.root;
                        for (0..128) |_| {
                            const shape = self.types.node(self.types.head(formal, 0));
                            if (shape.tag == .forall or shape.tag == .usage) {
                                formal = shape.a;
                                continue;
                            }
                            const actual = self.types.node(self.types.head(capture_type, 0));
                            if (shape.tag == .function and actual.tag == .function) {
                                const row = try self.types.resolveEffects(shape.c, 0);
                                if (self.types.row(row).tail == .closed and self.types.rowLabels(row).len == 0) {
                                    self.types.unifyEffects(actual.c, 0) catch |err| switch (err) {
                                        error.EffectMismatch, error.InfiniteEffect => {
                                            try self.diagnostic(.task_host_contract, source);
                                            return true;
                                        },
                                        else => return err,
                                    };
                                }
                            }
                            break;
                        }
                    }
                    if (!try self.taskLoanEncloses(capture_type, boundary.task_group, &budget, 0)) {
                        try self.diagnostic(.task_capability_shared, source);
                        return true;
                    }
                    if (try self.taskCaptureType(capture_type, false, &budget, 0)) |code| {
                        try self.diagnostic(code, source);
                        return true;
                    }
                    const qualified = self.types.node(self.types.head(capture_type, 0));
                    if (qualified.tag == .usage and qualified.b == @backingInt(T.UsageKind.concurrent)) return false;
                }
                if (boundary.capture_usage) {
                    var work: @import("usage_check.zig").Work = .{ .remaining = remaining.* };
                    const contains = try @import("usage_check.zig").containsNominalWork(&self.types, self.nominals.items, captured.ty, &work);
                    remaining.* = work.remaining;
                    if (contains) return true;
                }
                const operation = captured.operation_ref;
                if (operation != 0) return boundary.capture_usage or try self.identityFootprint(self.operation_uses.items[operation - 1].instance, boundary);
                return try self.bindingFootprint(binding, boundary, inherited, remaining, depth + 1) orelse true;
            },
            .intrinsic, .integer, .float, .string, .boolean, .unit => return false,
            .group, .field_access, .return_stmt, .yield_stmt => return self.closureCaptureFootprint(value.a, closure, boundary, inherited, remaining, depth + 1),
            .field, .unary, .operator_tail => return self.closureCaptureFootprint(value.b, closure, boundary, inherited, remaining, depth + 1),
            .lambda => return self.closureCaptureFootprint(value.b, closure, boundary, inherited, remaining, depth + 1),
            .apply, .index_access => return try self.closureCaptureFootprint(value.a, closure, boundary, inherited, remaining, depth + 1) or try self.closureCaptureFootprint(value.b, closure, boundary, inherited, remaining, depth + 1),
            .binary => return try self.closureCaptureFootprint(value.b, closure, boundary, inherited, remaining, depth + 1) or try self.closureCaptureFootprint(value.c, closure, boundary, inherited, remaining, depth + 1),
            .if_expr, .if_stmt => return try self.closureCaptureFootprint(value.a, closure, boundary, inherited, remaining, depth + 1) or try self.closureCaptureFootprint(value.b, closure, boundary, inherited, remaining, depth + 1) or try self.closureCaptureFootprint(value.c, closure, boundary, inherited, remaining, depth + 1),
            .product, .array, .record, .block, .infix_chain => {
                if (value.tag == .block and try self.closureCaptureFootprint(value.c, closure, boundary, inherited, remaining, depth + 1)) return true;
                for (self.tree.children(source)) |child| if (try self.closureCaptureFootprint(child, closure, boundary, inherited, remaining, depth + 1)) return true;
                return false;
            },
            .let_stmt => {
                const binding = self.tree.binding(source);
                return try self.closureCaptureFootprint(binding.value, closure, boundary, inherited, remaining, depth + 1) or try self.closureCaptureFootprint(binding.fallback, closure, boundary, inherited, remaining, depth + 1);
            },
            .use_stmt, .iterator_bind => return self.closureCaptureFootprint(value.b, closure, boundary, inherited, remaining, depth + 1),
            else => return true,
        }
    }
    // Value relationships are evaluated only at lifetime boundaries. Binding
    // versions and public retained-formal contracts supply the edges; type
    // structure supplies a conservative fallback for unknown value producers.
    fn valueFootprint(self: *Engine, source: ast.Id, boundary: FootprintBoundary, inherited: []const T.Id, remaining: *usize, depth: usize) T.Error!?bool {
        if (source == 0 or source >= self.tree.nodes.items.len) return null;
        if (depth >= 128 or remaining.* == 0) {
            try self.diagnostic(.capability_analysis_limit, self.owner);
            return true;
        }
        remaining.* -= 1;
        const value = self.tree.node(source);
        const ty = self.expr_types[source];
        if (ty != 0) {
            const shape = self.types.node(try self.types.resolve(ty, 0));
            switch (shape.tag) {
                .unit, .boolean, .u32, .f32, .never => return false,
                .scoped, .instance_selection => return try self.scopeFootprintDepth(ty, depth + 1, remaining, inherited, boundary),
                .function => {
                    const latent = try self.types.resolveEffects(shape.c, 0);
                    for (self.types.rowLabels(latent)) |label| if (try self.identityFootprint(self.types.operation(label).instance, boundary)) return true;
                },
                else => {},
            }
        }
        if (try self.dictionaryGoalFootprint(source, boundary, inherited, remaining)) return true;
        switch (value.tag) {
            .intrinsic, .integer, .float, .string, .boolean, .unit, .constructor_ref => return false,
            .group, .return_stmt, .yield_stmt, .type_witness => return self.valueFootprint(value.a, boundary, inherited, remaining, depth + 1),
            .field => {
                if (value.b != 0) return self.valueFootprint(value.b, boundary, inherited, remaining, depth + 1);
                // Record shorthand has no expression node, but its resolved
                // binding is an ordinary immutable version.
                return self.bindingFootprint(self.resolved[source], boundary, inherited, remaining, depth + 1);
            },
            .name => {
                if (self.access_paths[source].len != 0) return try self.projectedFootprint(source, boundary, inherited, remaining, depth + 1);
                const operation = self.operation_refs[source];
                if (operation != 0) return try self.identityFootprint(self.operation_uses.items[operation - 1].instance, boundary);
                return self.bindingFootprint(self.resolved[source], boundary, inherited, remaining, depth + 1);
            },
            .lambda => return try self.closureCaptureFootprint(value.b, source, boundary, inherited, remaining, depth + 1),
            .product, .array, .record => {
                var unknown = false;
                for (self.tree.children(source)) |child| {
                    const footprint = try self.valueFootprint(child, boundary, inherited, remaining, depth + 1);
                    if (footprint) |escapes| {
                        if (escapes) return true;
                    } else unknown = true;
                }
                if (unknown) return null;
                return false;
            },
            .if_expr => {
                const left = try self.valueFootprint(value.b, boundary, inherited, remaining, depth + 1);
                const right = try self.valueFootprint(value.c, boundary, inherited, remaining, depth + 1);
                if (left != null and left.?) return true;
                if (right != null and right.?) return true;
                if (left == null or right == null) return null;
                return false;
            },
            .block => {
                // A State/provider block additionally returns its final cell;
                // its result is not merely the source return expression.
                if (value.c != 0) return null;
                var found = false;
                var unknown = false;
                for (self.tree.children(source)) |child| {
                    const footprint = try self.returnFootprint(child, boundary, inherited, remaining, depth + 1, &found);
                    if (footprint) |escapes| {
                        if (escapes) return true;
                    } else unknown = true;
                }
                if (!found or unknown) return null;
                return false;
            },
            .package_pack => {
                if (boundary.rank_scope == 0) return null;
                var sealed: std.ArrayList(T.Id) = .empty;
                defer sealed.deinit(self.allocator);
                try sealed.appendSlice(self.allocator, inherited);
                for (self.tree.list(.{ .start = value.a, .len = value.b })) |witness| try @import("rank_walk.zig").collectRigids(&self.types, self.expr_types[witness], boundary.rank_scope, &sealed, remaining);
                return self.valueFootprint(self.tree.extra.items[value.c], boundary, sealed.items, remaining, depth + 1);
            },
            .package_unpack => return self.valueFootprint(self.tree.extra.items[value.c + 2], boundary, inherited, remaining, depth + 1),
            .apply => return self.applicationFootprint(source, boundary, inherited, remaining, depth + 1),
            // Projections can only discard authority. Keeping their receiver's
            // union is safe even when an opaque field path is unavailable.
            .field_access, .index_access => return try self.projectedFootprint(source, boundary, inherited, remaining, depth + 1),
            else => return null,
        }
    }
    // Recipes are instantiated in a temporary value graph at the requesting
    // boundary. Public formal ordinals never become live checker identities.
    const CapabilityTerms = @import("capability_contracts.zig");
    fn contractError(err: CapabilityTerms.Error) T.Error {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.TypeLimit;
    }
    fn capabilityHeader(self: *const Engine, binding: BindingId) ?CapabilityTerms.Recipe {
        for (self.capability_roots.items) |entry| if (entry.binding == binding) return .{ .arity = self.bindings.items[binding].capability_parameters.arity(), .root = entry.root, .nodes = self.capability_store.nodes.items, .words = self.capability_store.words.items };
        return null;
    }
    fn refreshCapabilityRecipe(self: *Engine, binding: BindingId) T.Error!void {
        const definition = self.bindings.items[binding];
        if (definition.kind != .global or !definition.capability_parameters.present()) return;
        for (self.capability_roots.items) |*entry| {
            if (entry.binding != binding) continue;
            const updated = @import("capability_contract_source.zig").deriveChecked(self.allocator, &self.capability_store, self.tree, self.pool, self.tree.valueDecl(definition.declaration).body, definition.capability_parameters, self.operation_refs) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.TypeLimit,
            };
            if (updated) |root| entry.root = root;
            return;
        }
    }
    const InputCallback = struct {
        source: ast.Id = 0,
        projected: bool = false,
        flow: CapabilityFlow,
        recipe: ?CapabilityTerms.Recipe = null,
    };
    fn scalarEffectAction(self: *Engine, signature: T.Id, arity: u8) T.Error!bool {
        if (arity != 1) return false;
        const arrow = self.types.node(try self.types.resolve(signature, 0));
        if (arrow.tag != .function) return false;
        const input = self.types.node(try self.types.resolve(arrow.a, 0));
        const output = self.types.node(try self.types.resolve(arrow.b, 0));
        for ([_]T.Tag{ input.tag, output.tag }) |tag| switch (tag) {
            .unit, .boolean, .u32, .f32, .never => {},
            else => return false,
        };
        const row = try self.types.resolveEffects(arrow.c, 0);
        return self.types.row(row).labels.len != 0;
    }
    fn finishCapabilityRole(self: *Engine, id: BindingId) T.Error!void {
        const binding = self.bindings.items[id];
        if (binding.capability_flow != .input_shape) return;
        if (binding.scheme.generative.len != 0) {
            // The completed declaring-arrow recipe owns fresh selections;
            // an initial syntactic shape is not a no-store callback marker.
            self.bindings.items[id].capability_flow = .unknown;
        } else if (try self.scalarEffectAction(binding.ty, binding.capability_parameters.arity())) {
            // Scalar actions have no input authority to retain. Their effects
            // remain independently checked; no constructor recipe is claimed.
            self.bindings.items[id].capability_flow = .unknown;
            self.bindings.items[id].capability_parameters = .{};
            for (self.capability_roots.items, 0..) |entry, index| if (entry.binding == id) {
                _ = self.capability_roots.orderedRemove(index);
                break;
            };
        }
    }
    fn publishInputFunction(self: *Engine, id: BindingId, arity: u8) T.Error!bool {
        const binding = self.bindings.items[id];
        const declaration = self.tree.valueDecl(binding.declaration);
        if (binding.scheme.generative.len != 0) return false;
        if (try self.scalarEffectAction(binding.ty, arity)) return false;
        if (@import("capability_flow.zig").parameterArity(self.tree, declaration.body, declaration.annotation) != arity) return false;
        var prototype: CapabilityTerms.Store = .{};
        defer prototype.deinit(self.allocator);
        const root = (@import("capability_contract_source.zig").deriveInputFunctionWithFunctions(self.allocator, &prototype, self.tree, self.pool, declaration.body, self.operation_refs, &self.types, self.expr_types, arity, self.callbackFunctions()) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return false;
        }) orelse return false;
        const mask = prototype.view().parameterMask(root) catch return false;
        if (self.capability_store.nodes.items.len == 0) _ = self.capability_store.append(self.allocator, .{ .tag = .empty }) catch |err| return contractError(err);
        var formals: [16]CapabilityTerms.Id = undefined;
        for (0..arity) |index| formals[index] = self.capability_store.append(self.allocator, .{ .tag = .parameter, .a = @intCast(index) }) catch |err| return contractError(err);
        const recipe: CapabilityTerms.Recipe = .{ .arity = arity, .root = root, .nodes = prototype.nodes.items, .words = prototype.words.items };
        const imported = self.capability_store.instantiate(self.allocator, recipe, formals[0..arity]) catch |err| return contractError(err);
        var replaced = false;
        for (self.capability_roots.items) |*entry| if (entry.binding == id) {
            entry.root = imported;
            replaced = true;
            break;
        };
        if (!replaced) try self.capability_roots.append(self.allocator, .{ .binding = id, .root = imported });
        self.bindings.items[id].capability_flow = .input_shape;
        self.bindings.items[id].capability_parameters = .init(arity, mask);
        return true;
    }
    const identity_callback_nodes = [_]CapabilityTerms.Term{ .{ .tag = .empty }, .{ .tag = .parameter } };
    fn callbackFunction(context: *const anyopaque, source: ast.Id) ?CapabilityTerms.Recipe {
        const self: *const Engine = @ptrCast(@alignCast(context));
        if (source == 0 or source >= self.resolved.len) return null;
        const id = self.resolved[source];
        if (id == 0 or id >= self.bindings.items.len) return null;
        const binding = self.bindings.items[id];
        if ((binding.kind != .global and binding.kind != .external) or binding.scheme.generative.len != 0) return null;
        if (binding.capability_flow == .identity) return .{ .arity = 1, .root = 1, .nodes = &identity_callback_nodes, .words = &.{} };
        if (binding.capability_flow != .input_shape or binding.capability_parameters.kind != .product or !binding.capability_parameters.valid() or !binding.capability_parameters.present()) return null;
        return self.capabilityHeader(id);
    }
    fn callbackFunctions(self: *const Engine) @import("capability_contract_source.zig").Functions {
        return .{ .context = self, .lookup = callbackFunction };
    }
    fn callableResult(self: *Engine, binding: BindingId, arity: u8) T.Error!bool {
        var result = self.bindings.items[binding].ty;
        var count: usize = 0;
        var remaining: usize = 4096;
        while (count < arity and remaining != 0) {
            remaining -= 1;
            const node = self.types.node(self.types.head(result, 0));
            if (node.tag == .usage or node.tag == .forall) {
                result = node.a;
                continue;
            }
            if (node.tag != .function) return false;
            result = node.b;
            count += 1;
        }
        if (remaining == 0) return false;
        var pending: [4096]T.Id = undefined;
        var length: usize = 1;
        pending[0] = result;
        while (length != 0 and remaining != 0) {
            remaining -= 1;
            length -= 1;
            const node = self.types.node(self.types.head(pending[length], 0));
            if (node.tag == .function) return true;
            switch (node.tag) {
                .product => {
                    if (node.b > pending.len - length) return false;
                    @memcpy(pending[length..][0..node.b], self.types.list(.{ .start = node.a, .len = node.b }));
                    length += node.b;
                },
                .record => {
                    if (node.b > pending.len - length) return false;
                    for (0..node.b) |index| pending[length + index] = self.types.recordField(node, index).ty;
                    length += node.b;
                },
                .usage, .array, .list, .forall => {
                    if (length == pending.len) return false;
                    pending[length] = node.a;
                    length += 1;
                },
                else => {},
            }
        }
        return false;
    }
    fn publishCallback(self: *Engine, binding: BindingId) T.Error!void {
        const definition = self.bindings.items[binding];
        if (definition.kind != .global or !definition.named_function or definition.capability_flow != .unknown or definition.declaration == 0 or (definition.capability_parameters.present() and definition.capability_parameters.kind != .product) or definition.scheme.root == 0) return;
        const declaration = self.tree.valueDecl(definition.declaration);
        const arity = @import("capability_flow.zig").parameterArity(self.tree, declaration.body, declaration.annotation);
        if (arity == 0) return;
        if (!self.has_input_invocations and self.operation_uses.items.len == 0 and !try self.callableResult(binding, arity)) return;
        _ = try self.publishInputFunction(binding, arity);
    }
    fn inputCallback(self: *Engine, source: ast.Id, arity: u8, remaining: *usize, depth: usize) T.Error!?InputCallback {
        if (source == 0 or depth >= 64 or remaining.* == 0) return error.TypeLimit;
        remaining.* -= 1;
        const node = self.tree.node(source);
        if (node.tag == .group) return self.inputCallback(node.a, arity, remaining, depth + 1);
        var result: InputCallback = undefined;
        if (node.tag == .lambda) {
            result = .{ .source = source, .flow = self.capabilityFlowContract(source, 0) };
        } else if (node.tag == .name and self.resolved[source] != 0 and self.access_paths[source].len == 0) {
            const id = self.resolved[source];
            const binding = self.bindings.items[id];
            if (binding.kind == .local and binding.declaration != 0) {
                const declaration = self.tree.node(binding.declaration);
                if (declaration.tag == .rebind_stmt and self.rebindings[binding.declaration].path.len == 0) return self.inputCallback(declaration.b, arity, remaining, depth + 1);
                for (self.tree.nodes.items[binding.declaration..], binding.declaration..) |candidate, index| {
                    if (remaining.* == 0) return error.TypeLimit;
                    remaining.* -= 1;
                    if (candidate.tag == .let_stmt and candidate.a == binding.declaration) return self.inputCallback(self.tree.binding(@intCast(index)).value, arity, remaining, depth + 1);
                }
            }
            if (binding.kind != .global and binding.kind != .external) return null;
            if (binding.kind == .global and binding.capability_flow == .unknown and binding.declaration != 0) _ = try self.publishInputFunction(id, arity);
            const known = self.bindings.items[id];
            result = .{ .flow = known.capability_flow };
            if (known.capability_flow == .input_shape and known.capability_parameters.kind == .product and known.capability_parameters.valid() and known.capability_parameters.arity() == arity and known.scheme.generative.len == 0) {
                result.recipe = self.capabilityHeader(id);
            }
        } else {
            var prototype: CapabilityTerms.Store = .{};
            defer prototype.deinit(self.allocator);
            const root = try self.valueShape(&prototype, source, .{}, &.{}, remaining, depth + 1);
            if (!(prototype.callableArity(root, arity, remaining, depth + 1) catch |err| return contractError(err))) return null;
            return .{ .flow = .input_shape, .source = source, .projected = true };
        }
        if (arity == 1 and (result.flow == .identity or result.flow == .member_unit)) return result;
        if (result.source == 0) {
            if (result.recipe != null) return result;
            return null;
        }
        {
            var prototype: CapabilityTerms.Store = .{};
            defer prototype.deinit(self.allocator);
            const root = @import("capability_contract_source.zig").deriveInputFunctionWithFunctions(self.allocator, &prototype, self.tree, self.pool, result.source, self.operation_refs, &self.types, self.expr_types, arity, self.callbackFunctions()) catch |err| return contractError(err);
            if (root == null) return null;
        }
        return result;
    }
    fn inputCallbackShape(self: *Engine, store: *CapabilityTerms.Store, callback: ast.Id, arguments: []const ast.Id, boundary: FootprintBoundary, inherited: []const T.Id, remaining: *usize, depth: usize) T.Error!CapabilityTerms.Id {
        if (arguments.len == 1 and try self.localStateStoreBudget(callback, arguments[0], self.expr_types[arguments[0]], remaining)) return 0;
        const proof = (try self.inputCallback(callback, @intCast(arguments.len), remaining, depth + 1)) orelse return store.append(self.allocator, .{ .tag = .unknown }) catch |err| return contractError(err);
        if (proof.flow == .identity) return self.valueShape(store, arguments[0], boundary, inherited, remaining, depth + 1);
        if (proof.flow == .member_unit) {
            const function = self.types.node(try self.types.resolve(self.expr_types[callback], 0));
            if (function.tag != .function or try self.scopeFootprintDepth(function.b, depth + 1, remaining, inherited, boundary)) return store.append(self.allocator, .{ .tag = .unknown }) catch |err| return contractError(err);
            return 0;
        }
        var supplied: [16]CapabilityTerms.Id = undefined;
        for (arguments, 0..) |argument, index| supplied[index] = try self.valueShape(store, argument, boundary, inherited, remaining, depth + 1);
        if (proof.projected) {
            const function = try self.valueShape(store, callback, boundary, inherited, remaining, depth + 1);
            return store.invoke(self.allocator, function, supplied[0..arguments.len]) catch |err| return contractError(err);
        }
        var prototype: CapabilityTerms.Store = .{};
        defer prototype.deinit(self.allocator);
        var header = proof.recipe;
        if (header == null) {
            const root = (@import("capability_contract_source.zig").deriveInputFunctionWithFunctions(self.allocator, &prototype, self.tree, self.pool, proof.source, self.operation_refs, &self.types, self.expr_types, @intCast(arguments.len), self.callbackFunctions()) catch |err| return contractError(err)) orelse return error.TypeLimit;
            header = .{ .arity = @intCast(arguments.len), .root = root, .nodes = prototype.nodes.items, .words = prototype.words.items };
        }
        const result = store.instantiate(self.allocator, header.?, supplied[0..arguments.len]) catch |err| return contractError(err);
        const function = self.types.node(try self.types.resolve(self.expr_types[callback], 0));
        if (function.tag != .function) return error.TypeLimit;
        var output = self.expr_types[callback];
        for (arguments) |_| {
            const arrow = self.types.node(try self.types.resolve(output, 0));
            if (arrow.tag != .function) return error.TypeLimit;
            output = arrow.b;
        }
        if (!try self.scopeFootprintDepth(output, depth + 1, remaining, inherited, boundary)) return 0;
        // Captures preceding this argument still belong to the requesting
        // boundary; a formal-input recipe does not erase their authority.
        const captured = try self.valueShape(store, callback, boundary, inherited, remaining, depth + 1);
        return store.aggregate(self.allocator, .join, &.{ result, captured }) catch |err| return contractError(err);
    }
    fn valueShape(self: *Engine, store: *CapabilityTerms.Store, source: ast.Id, boundary: FootprintBoundary, inherited: []const T.Id, remaining: *usize, depth: usize) T.Error!CapabilityTerms.Id {
        if (source == 0 or source >= self.tree.nodes.items.len or depth >= 128 or remaining.* == 0) return error.TypeLimit;
        remaining.* -= 1;
        const value = self.tree.node(source);
        const ty = self.expr_types[source];
        if (ty != 0) {
            const shape = self.types.node(try self.types.resolve(ty, 0));
            switch (shape.tag) {
                .unit, .boolean, .u32, .f32, .never => return 0,
                .scoped, .instance_selection => {
                    if (!try self.scopeFootprintDepth(ty, depth + 1, remaining, inherited, boundary)) return 0;
                    return store.append(self.allocator, .{ .tag = .unknown }) catch |err| return contractError(err);
                },
                else => {},
            }
        }
        if (try self.dictionaryGoalFootprint(source, boundary, inherited, remaining)) return store.append(self.allocator, .{ .tag = .unknown }) catch |err| return contractError(err);
        switch (value.tag) {
            .intrinsic, .integer, .float, .string, .boolean, .unit, .constructor_ref => return 0,
            .group, .return_stmt, .yield_stmt => return self.valueShape(store, value.a, boundary, inherited, remaining, depth + 1),
            .type_witness => return store.append(self.allocator, .{ .tag = .wrapped, .a = try self.valueShape(store, value.a, boundary, inherited, remaining, depth + 1) }) catch |err| return contractError(err),
            .field => {
                if (value.b != 0) return self.valueShape(store, value.b, boundary, inherited, remaining, depth + 1);
                return self.bindingShape(store, self.resolved[source], boundary, inherited, remaining, depth + 1);
            },
            .name => {
                if (self.operation_refs[source] != 0) {
                    if (!try self.identityFootprint(self.operation_uses.items[self.operation_refs[source] - 1].instance, boundary)) return 0;
                    return store.append(self.allocator, .{ .tag = .unknown }) catch |err| return contractError(err);
                }
                var root = try self.bindingShape(store, self.resolved[source], boundary, inherited, remaining, depth + 1);
                for (self.types.list(self.access_paths[source])) |projection| {
                    if (projection == 0 or projection >= self.projection_catalog.items.len) return store.append(self.allocator, .{ .tag = .unknown }) catch |err| return contractError(err);
                    root = store.project(self.allocator, root, self.projection_catalog.items[projection].field, .field) catch |err| return contractError(err);
                }
                return root;
            },
            .field_access => return store.project(self.allocator, try self.valueShape(store, value.a, boundary, inherited, remaining, depth + 1), value.b, .field) catch |err| return contractError(err),
            .index_access => {
                const base = try self.valueShape(store, value.a, boundary, inherited, remaining, depth + 1);
                const index = self.tree.node(value.b);
                if (index.tag == .integer) {
                    return store.project(self.allocator, base, index.a, .index) catch |err| return contractError(err);
                }
                return store.elements(self.allocator, base) catch |err| return contractError(err);
            },
            .product, .array, .record => {
                var children: [4096]u32 = undefined;
                const sources = self.tree.children(source);
                var width: usize = sources.len;
                if (value.tag == .record) width *= 2;
                if (width > children.len) return error.TypeLimit;
                for (sources, 0..) |child, index| {
                    const retained = try self.valueShape(store, child, boundary, inherited, remaining, depth + 1);
                    if (value.tag == .record) {
                        children[index * 2] = self.tree.node(child).a;
                        children[index * 2 + 1] = retained;
                    } else children[index] = retained;
                }
                var tag: CapabilityTerms.Tag = .product;
                if (value.tag == .record) tag = .record;
                const root: CapabilityTerms.Id = store.aggregate(self.allocator, tag, children[0..width]) catch |err| return contractError(err);
                if (value.tag == .record and value.a != 0) return store.append(self.allocator, .{ .tag = .wrapped, .a = root }) catch |err| return contractError(err);
                // aggregate copies child words; this result is a node ID.
                // zig-analyzer: disable-next-line returning-local-slice
                return root;
            },
            .if_expr => return store.aggregate(self.allocator, .join, &.{ try self.valueShape(store, value.b, boundary, inherited, remaining, depth + 1), try self.valueShape(store, value.c, boundary, inherited, remaining, depth + 1) }) catch |err| return contractError(err),
            .apply => {
                if (@import("capability_flow.zig").constructionSource(self.tree, self.pool, source)) |construction| {
                    var children: [3]CapabilityTerms.Id = undefined;
                    for (construction.inputs[0..construction.len], 0..) |input, index| children[index] = try self.valueShape(store, input, boundary, inherited, remaining, depth + 1);
                    if (construction.kind == .computation) return store.append(self.allocator, .{ .tag = .wrapped, .a = children[0] }) catch |err| return contractError(err);
                    return store.aggregate(self.allocator, .captures, children[0..construction.len]) catch |err| return contractError(err);
                }
                if (@import("capability_flow.zig").projectionSource(self.tree, self.pool, source)) |projection| {
                    const receiver = try self.valueShape(store, projection.receiver, boundary, inherited, remaining, depth + 1);
                    var selector = projection.index;
                    while (self.tree.node(selector).tag == .group) selector = self.tree.node(selector).a;
                    const index = self.tree.node(selector);
                    if (index.tag != .integer) return store.elements(self.allocator, receiver) catch |err| return contractError(err);
                    return store.project(self.allocator, receiver, index.a, .index) catch |err| return contractError(err);
                }
                if (self.effect_scope_ids[source] != 0) return self.valueShape(store, self.tree.node(self.effect_scopes.items[self.effect_scope_ids[source] - 1].callback).b, boundary, inherited, remaining, depth + 1);
                var arguments: [16]ast.Id = undefined;
                var count: usize = 0;
                var callee = source;
                for (0..128) |_| {
                    const node = self.tree.node(callee);
                    if (node.tag == .group) {
                        callee = node.a;
                        continue;
                    }
                    if (node.tag != .apply) break;
                    if (count == arguments.len) return error.TypeLimit;
                    arguments[count] = node.b;
                    count += 1;
                    callee = node.a;
                } else return error.TypeLimit;
                if (self.constructor_resolved[callee] != 0 and count == 1) return store.append(self.allocator, .{ .tag = .wrapped, .a = try self.valueShape(store, arguments[0], boundary, inherited, remaining, depth + 1) }) catch |err| return contractError(err);
                const binding = self.resolved[callee];
                if (self.tree.node(callee).tag == .name and binding != 0) {
                    if (self.bindings.items[binding].capability_flow == .identity and count == 1) return self.valueShape(store, arguments[0], boundary, inherited, remaining, depth + 1);
                    const input_contract = self.bindings.items[binding].capability_parameters;
                    if (input_contract.inputInvokes() and input_contract.valid() and count == input_contract.arity()) {
                        var supplied: [16]ast.Id = undefined;
                        for (0..input_contract.argumentCount()) |index| supplied[index] = arguments[count - input_contract.argumentAt(index) - 1];
                        return self.inputCallbackShape(store, arguments[count - input_contract.callback() - 1], supplied[0..input_contract.argumentCount()], boundary, inherited, remaining, depth + 1);
                    }
                    if (self.capabilityHeader(binding)) |header| {
                        if (count == header.arity) {
                            var actual: [16]u32 = undefined;
                            for (0..count) |index| actual[index] = try self.valueShape(store, arguments[count - index - 1], boundary, inherited, remaining, depth + 1);
                            return store.instantiate(self.allocator, header, actual[0..count]) catch |err| return contractError(err);
                        }
                    }
                }
            },
            .block => {
                if (value.c == 0) {
                    const children = self.tree.children(source);
                    if (children.len != 0) {
                        var aliases_only = true;
                        for (children[0 .. children.len - 1]) |child| {
                            if (self.tree.node(child).tag != .let_stmt or self.tree.binding(child).fallback != 0) {
                                aliases_only = false;
                                break;
                            }
                        }
                        const last = self.tree.node(children[children.len - 1]);
                        if (aliases_only and last.tag == .return_stmt) return self.valueShape(store, last.a, boundary, inherited, remaining, depth + 1);
                    }
                }
            },
            else => {},
        }
        const footprint = try self.valueFootprint(source, boundary, inherited, remaining, depth + 1) orelse true;
        if (!footprint) return 0;
        return store.append(self.allocator, .{ .tag = .unknown }) catch |err| return contractError(err);
    }
    fn bindingShape(self: *Engine, store: *CapabilityTerms.Store, binding: BindingId, boundary: FootprintBoundary, inherited: []const T.Id, remaining: *usize, depth: usize) T.Error!CapabilityTerms.Id {
        if (binding == 0 or binding >= self.bindings.items.len or depth >= 128 or remaining.* == 0) return error.TypeLimit;
        const value = self.bindings.items[binding];
        if ((value.kind == .global or value.kind == .external) and value.scheme.generative.len == 0) {
            if (value.capability_flow == .identity) {
                const header: CapabilityTerms.Recipe = .{ .arity = 1, .root = 1, .nodes = &identity_callback_nodes, .words = &.{} };
                return store.callable(self.allocator, header, 0) catch |err| return contractError(err);
            }
            if (value.capability_flow == .input_shape) if (self.capabilityHeader(binding)) |header| return store.callable(self.allocator, header, 0) catch |err| return contractError(err);
        }
        if (value.kind == .local and value.declaration != 0 and value.declaration < self.tree.nodes.items.len) {
            const declaration = self.tree.node(value.declaration);
            if (declaration.tag == .rebind_stmt and self.rebindings[value.declaration].path.len == 0) return self.valueShape(store, declaration.b, boundary, inherited, remaining, depth + 1);
            for (self.tree.nodes.items[value.declaration..], value.declaration..) |node, index| {
                if (remaining.* == 0) return error.TypeLimit;
                remaining.* -= 1;
                if (node.tag == .let_stmt and node.a == value.declaration) return self.valueShape(store, self.tree.binding(@intCast(index)).value, boundary, inherited, remaining, depth + 1);
            }
        }
        const footprint = try self.bindingFootprint(binding, boundary, inherited, remaining, depth + 1) orelse true;
        if (!footprint) return 0;
        return store.append(self.allocator, .{ .tag = .unknown }) catch |err| return contractError(err);
    }
    fn shapeFootprint(view: CapabilityTerms.View, root: CapabilityTerms.Id, remaining: *usize, depth: usize) T.Error!bool {
        if (depth >= 128 or remaining.* == 0 or root >= view.nodes.len) return error.TypeLimit;
        remaining.* -= 1;
        const value = view.nodes[root];
        switch (value.tag) {
            .empty => return false,
            .unknown, .parameter, .argument, .authority => return true,
            .callable => return shapeFootprint(view, value.b, remaining, depth + 1),
            .wrapped, .project, .elements => return shapeFootprint(view, value.a, remaining, depth + 1),
            .captures, .product, .record, .join => {
                for (view.children(value), 0..) |child, index| {
                    if (value.tag == .record and index % 2 == 0) continue;
                    if (try shapeFootprint(view, child, remaining, depth + 1)) return true;
                }
                return false;
            },
        }
    }
    fn projectedFootprint(self: *Engine, source: ast.Id, boundary: FootprintBoundary, inherited: []const T.Id, remaining: *usize, depth: usize) T.Error!bool {
        var store: CapabilityTerms.Store = .{};
        defer store.deinit(self.allocator);
        _ = store.append(self.allocator, .{ .tag = .empty }) catch |err| return contractError(err);
        const root = self.valueShape(&store, source, boundary, inherited, remaining, depth + 1) catch |err| {
            if (err != error.TypeLimit) return err;
            try self.diagnostic(.capability_analysis_limit, source);
            return true;
        };
        return shapeFootprint(store.view(), root, remaining, depth + 1);
    }
    fn bindingFootprint(self: *Engine, binding: BindingId, boundary: FootprintBoundary, inherited: []const T.Id, remaining: *usize, depth: usize) T.Error!?bool {
        if (binding == 0 or binding >= self.bindings.items.len) return null;
        const value = self.bindings.items[binding];
        if (boundary.task_group != 0 and value.named_function and (value.kind == .global or (value.kind == .external and value.external != null))) {
            // This is an exact static producer, not an opaque closure input.
            // Frozen task admission must reconstruct its actual declaration
            // and executable body using the imported unit before execution.
            // The capture walk checked this use's instantiated transfer type;
            // a universal principal itself is not a runtime environment.
            return false;
        }
        // An enclosing input existed before this fresh scope was entered.
        // This value-origin fact is separate from its abstract datatype and
        // unknown latent permission row. Inputs declared inside the scope do
        // not receive that proof.
        if (value.kind == .parameter and value.owner != 0 and boundary.exiting != null) {
            const exiting = boundary.exiting.?;
            if (exiting.unit == self.unit and value.declaration != exiting.decl and exiting.decl < self.tree.nodes.items.len) {
                const birth = self.tree.span(value.owner);
                const entry = self.tree.span(exiting.decl);
                if (birth.start < entry.start and birth.end > entry.end) return false;
            }
        }
        if (value.operation_ref != 0) return try self.identityFootprint(self.operation_uses.items[value.operation_ref - 1].instance, boundary);
        if (value.declaration != 0 and value.declaration < self.tree.nodes.items.len) {
            const declaration = self.tree.node(value.declaration);
            if (value.kind == .global and declaration.tag == .value_decl) return self.valueFootprint(self.tree.valueDecl(value.declaration).body, boundary, inherited, remaining, depth + 1);
            if (value.kind == .local) {
                if (declaration.tag == .rebind_stmt and self.rebindings[value.declaration].path.len == 0) return self.valueFootprint(declaration.b, boundary, inherited, remaining, depth + 1);
                // Simple aliases point to their pattern, not the let node.
                // Search is charged and occurs only on the uncommon lifetime
                // path. Joined/control-flow versions remain unknown.
                for (self.tree.nodes.items[value.declaration..], value.declaration..) |node, index| {
                    if (remaining.* == 0) {
                        try self.diagnostic(.capability_analysis_limit, self.owner);
                        return true;
                    }
                    remaining.* -= 1;
                    if (node.tag == .let_stmt and node.a == value.declaration) return self.valueFootprint(self.tree.binding(@intCast(index)).value, boundary, inherited, remaining, depth + 1);
                }
            }
        }
        return try self.scopeFootprintDepth(value.ty, depth + 1, remaining, inherited, boundary);
    }
    fn returnFootprint(self: *Engine, source: ast.Id, boundary: FootprintBoundary, inherited: []const T.Id, remaining: *usize, depth: usize, found: *bool) T.Error!?bool {
        if (source == 0) return false;
        if (depth >= 128 or remaining.* == 0) {
            try self.diagnostic(.capability_analysis_limit, self.owner);
            return true;
        }
        remaining.* -= 1;
        const value = self.tree.node(source);
        if (value.tag == .return_stmt) {
            found.* = true;
            return self.valueFootprint(value.a, boundary, inherited, remaining, depth + 1);
        }
        if (value.tag == .if_stmt) {
            const left = try self.returnFootprint(value.b, boundary, inherited, remaining, depth + 1, found);
            const right = try self.returnFootprint(value.c, boundary, inherited, remaining, depth + 1, found);
            if (left != null and left.?) return true;
            if (right != null and right.?) return true;
            if (left == null or right == null) return null;
        } else if (value.tag == .block and value.c == 0) {
            for (self.tree.children(source)) |child| {
                const footprint = try self.returnFootprint(child, boundary, inherited, remaining, depth + 1, found);
                if (footprint == null or footprint.?) return footprint;
            }
        }
        return false;
    }
    fn applicationFootprint(self: *Engine, source: ast.Id, boundary: FootprintBoundary, inherited: []const T.Id, remaining: *usize, depth: usize) T.Error!?bool {
        if (@import("capability_flow.zig").constructionSource(self.tree, self.pool, source)) |construction| {
            var unknown = false;
            for (construction.inputs[0..construction.len]) |input| {
                const footprint = try self.valueFootprint(input, boundary, inherited, remaining, depth + 1);
                if (footprint) |escapes| {
                    if (escapes) return true;
                } else unknown = true;
            }
            if (unknown) return null;
            return false;
        }
        if (@import("capability_flow.zig").projectionSource(self.tree, self.pool, source) != null) return try self.projectedFootprint(source, boundary, inherited, remaining, depth + 1);
        if (self.effect_scope_ids[source] != 0) {
            const scope = self.effect_scopes.items[self.effect_scope_ids[source] - 1];
            return self.valueFootprint(self.tree.node(scope.callback).b, boundary, inherited, remaining, depth + 1);
        }
        // A checked resource scope executes cleanup before its result leaves.
        // Only the callback result survives; construction captures of the
        // acquisition and cleanup remain local to this resource invocation.
        for (self.usage_loans.items) |loan| {
            if (remaining.* == 0) return null;
            remaining.* -= 1;
            if (loan.source != source or loan.callback == 0 or loan.acquire == 0) continue;
            var callback = loan.callback;
            while (self.tree.node(callback).tag == .group) {
                if (remaining.* == 0) return null;
                remaining.* -= 1;
                callback = self.tree.node(callback).a;
            }
            if (self.tree.node(callback).tag != .lambda) return null;
            return self.valueFootprint(self.tree.node(callback).b, boundary, inherited, remaining, depth + 1);
        }
        var arguments: [16]ast.Id = undefined;
        var count: usize = 0;
        var callee = source;
        for (0..128) |_| {
            const value = self.tree.node(callee);
            if (value.tag == .group) {
                callee = value.a;
                continue;
            }
            if (value.tag != .apply) break;
            if (count == arguments.len) return null;
            arguments[count] = value.b;
            count += 1;
            callee = value.a;
        } else return null;
        if (self.constructor_resolved[callee] != 0 and count == 1) return self.valueFootprint(arguments[0], boundary, inherited, remaining, depth + 1);
        if (self.tree.node(callee).tag != .name) return null;
        const binding = self.resolved[callee];
        if (binding == 0) return null;
        const definition = self.bindings.items[binding];
        if (definition.capability_flow == .identity and count == 1) return self.valueFootprint(arguments[0], boundary, inherited, remaining, depth + 1);
        const parameters = definition.capability_parameters;
        if (count == parameters.arity() and self.capabilityHeader(binding) != null) return try self.projectedFootprint(source, boundary, inherited, remaining, depth + 1);
        if (!parameters.valid() or !parameters.present()) return null;
        if (count > parameters.arity()) return null;
        // Partial calls physically capture every supplied value, including
        // inputs omitted by the final result relation.
        var retained = parameters.result();
        if (count < parameters.arity()) retained = 0xffff;
        if (count == parameters.arity() and parameters.inputInvokes()) return try self.projectedFootprint(source, boundary, inherited, remaining, depth + 1);
        if (count == parameters.arity() and parameters.kind == .invoke_unit) return null;
        var unknown = false;
        for (0..count) |index| {
            if (retained & (@as(u16, 1) << @intCast(index)) == 0) continue;
            const footprint = try self.valueFootprint(arguments[count - index - 1], boundary, inherited, remaining, depth + 1);
            if (footprint) |escapes| {
                if (escapes) return true;
            } else unknown = true;
        }
        if (unknown) return null;
        return false;
    }
    fn invocationContract(context: *const anyopaque, source: ast.Id) ?@import("capability_flow.zig").Parameters {
        const self: *const Engine = @ptrCast(@alignCast(context));
        const node = self.tree.node(source);
        if (node.tag != .name) return null;
        var binding = self.resolved[source];
        if (binding == 0) {
            if (self.catalogs.globals.get(node.a)) |global| binding = global else {
                const name = self.pool.get(node.a);
                const separator = std.mem.findScalar(u8, name, '.') orelse return null;
                const namespace = self.pool.lookup(name[0..separator]) orelse return null;
                const member = self.pool.lookup(name[separator + 1 ..]) orelse return null;
                binding = self.catalogs.qualified.get(.{ .namespace = namespace, .member = member }) orelse return null;
            }
        }
        if (binding == 0 or binding >= self.bindings.items.len) return null;
        const definition = self.bindings.items[binding];
        if (definition.kind != .global and definition.kind != .external) return null;
        const contract = definition.capability_parameters;
        if (!contract.valid() or !contract.invokes()) return null;
        return contract;
    }
    fn capabilityParameters(self: *const Engine, source: ast.Id, annotation_: ast.Id) @import("capability_flow.zig").Parameters {
        const flow = @import("capability_flow.zig");
        // Existing unary contracts already carry this relation; avoid a second
        // digest record and admission walk for ordinary identity helpers.
        if (flow.source(self.tree, source) != .unknown) return .{};
        const parameters = flow.parameterSourceWithContracts(self.tree, self.pool, source, annotation_, .{ .context = self, .lookup = invocationContract });
        if (parameters.kind != .member_closure_unit) return parameters;
        var expression_ = source;
        while (self.tree.node(expression_).tag == .group) expression_ = self.tree.node(expression_).a;
        var signature_source = annotation_;
        for (0..parameters.arity()) |index| {
            const lambda = self.tree.node(expression_);
            if (lambda.tag != .lambda) return .{};
            const formal = self.tree.parameter(lambda.a);
            var family_annotation = formal.annotation;
            if (family_annotation == 0 and signature_source != 0 and self.tree.node(signature_source).tag == .type_function) {
                const input = self.tree.node(self.tree.node(signature_source).a);
                if (input.tag == .type_binder) family_annotation = input.b;
            }
            if (parameters.result() & (@as(u16, 1) << @intCast(index)) != 0 and self.capabilityFamilyAnnotation(family_annotation) == null) return .{};
            expression_ = lambda.b;
            if (signature_source != 0 and self.tree.node(signature_source).tag == .type_function) signature_source = self.tree.node(signature_source).b;
        }
        return parameters;
    }
    fn capabilityFlowUse(self: *Engine, callee: ast.Id, argument: T.Id) T.Error!bool {
        var source = callee;
        while (self.tree.node(source).tag == .group) source = self.tree.node(source).a;
        var supplied: usize = 0;
        while (self.tree.node(source).tag == .apply or self.tree.node(source).tag == .group) {
            const value = self.tree.node(source);
            if (value.tag == .apply) supplied += 1;
            source = value.a;
        }
        // A constructor builds its result from the supplied payload and has
        // no callable storage sink. Result escape is checked separately.
        if (self.constructor_resolved[source] != 0) return supplied == 0;
        var contract = self.capabilityFlowContract(source, 0);
        var parameters = self.capabilityParameters(source, 0);
        if (self.tree.node(source).tag == .name) {
            const binding = self.resolved[source];
            if (binding != 0) {
                contract = self.bindings.items[binding].capability_flow;
                parameters = self.bindings.items[binding].capability_parameters;
            }
        }
        if (contract != .unknown and parameters.kind == .invoke_unit) parameters = .{};
        if (parameters.present()) {
            if (!parameters.valid() or supplied >= parameters.arity()) return false;
            if (parameters.inputInvokes() and supplied == parameters.callback()) return self.types.node(try self.types.resolve(argument, 0)).tag == .function;
            if (parameters.kind == .invoke_unit and parameters.result() & (@as(u16, 1) << @intCast(supplied)) != 0) return self.types.node(try self.types.resolve(argument, 0)).tag == .function;
            // A deferred partial call may retain supplied values physically.
            // Scoped descriptors erase; unknown callable/container captures do
            // not inherit the unused-input proof of an immediate constructor.
            if (parameters.kind == .member_closure_unit) return self.types.node(try self.types.resolve(argument, 0)).tag == .scoped;
            return true;
        }
        switch (contract) {
            .unknown, .input_shape => return false,
            .identity => return supplied == 0,
            .invoke_unit => return supplied == 0 and self.types.node(try self.types.resolve(argument, 0)).tag == .function,
            .member_unit => return supplied == 0 and self.types.node(try self.types.resolve(argument, 0)).tag == .scoped,
            .member_first_unit, .member_second_unit => return supplied < 2 and self.types.node(try self.types.resolve(argument, 0)).tag == .scoped,
            .invoke_with_capability => {
                const value = self.types.node(try self.types.resolve(argument, 0));
                if (supplied == 0) return value.tag == .scoped;
                return supplied == 1 and value.tag == .function;
            },
        }
    }
    // Only a trusted State frame owns a local cell. Ordinary callbacks and
    // construction-time handlers cannot establish a future storage lifetime.
    fn localStateStore(self: *Engine, callee: ast.Id, argument_source: ast.Id, argument: T.Id) T.Error!bool {
        var remaining: usize = 65_536;
        return self.localStateStoreBudget(callee, argument_source, argument, &remaining);
    }
    fn localStateStoreBudget(self: *Engine, callee: ast.Id, argument_source: ast.Id, argument: T.Id, remaining: *usize) T.Error!bool {
        if (remaining.* == 0) return error.TypeLimit;
        remaining.* -= 1;
        var target = callee;
        while (self.tree.node(target).tag == .group) {
            if (remaining.* == 0) return error.TypeLimit;
            remaining.* -= 1;
            target = self.tree.node(target).a;
        }
        var operation = self.operation_refs[target];
        if (operation == 0 and self.tree.node(target).tag == .name) {
            const binding = self.resolved[target];
            if (binding != 0) operation = self.bindings.items[binding].operation_ref;
        }
        if (operation == 0) return false;
        const use = self.operation_uses.items[operation - 1];
        const signature = self.types.node(try self.types.resolve(use.signature, 0));
        if (signature.tag != .function or try self.types.resolve(signature.b, 0) != T.unit) return false;
        // A callback's latent row may be widened by a generic helper. The
        // selected operation identity, arguments and receiver own its target.
        const arguments = try self.allocator.dupe(T.Id, self.types.list(use.arguments));
        defer self.allocator.free(arguments);
        for (arguments) |*item| {
            if (remaining.* == 0) return error.TypeLimit;
            remaining.* -= 1;
            item.* = try self.types.resolve(item.*, 0);
        }
        const label = try self.types.internScopedOperation(self.effect_templates.items[use.template].identity, use.instance, arguments);
        var index = self.storage_frames.items.len;
        while (index != 0) {
            index -= 1;
            const frame = self.storage_frames.items[index];
            if (remaining.* == 0) return error.TypeLimit;
            remaining.* -= 1;
            if (frame.read != label and frame.write != label) continue;
            if (frame.write == 0 or frame.write != label) return false;
            const boundary: FootprintBoundary = .{ .storage_depth = frame.depth };
            const footprint = try self.valueFootprint(argument_source, boundary, &.{}, remaining, 0) orelse try self.scopeFootprintDepth(argument, 0, remaining, &.{}, boundary);
            return !footprint;
        }
        return false;
    }
    fn intrinsicRead(self: *Engine, callee: ast.Id) bool {
        var source = callee;
        while (true) {
            const value = self.tree.node(source);
            if (value.tag == .group or value.tag == .apply) {
                source = value.a;
                continue;
            }
            if (value.tag != .intrinsic) return false;
            const name = self.pool.get(value.a);
            return std.mem.eql(u8, name, "@array.get") or std.mem.eql(u8, name, "@array.length") or std.mem.eql(u8, name, "@product.get");
        }
    }
    fn directCallbackUse(self: *Engine, callee: ast.Id, argument: T.Id) T.Error!bool {
        const signature = self.types.node(try self.types.resolve(argument, 0));
        if (signature.tag != .function or try self.scopeFootprint(signature.b, 0)) return false;
        var source = callee;
        while (self.tree.node(source).tag == .group) source = self.tree.node(source).a;
        const lambda = self.tree.node(source);
        if (lambda.tag != .lambda or self.tree.parameter(lambda.a).demanded) return false;
        var body = lambda.b;
        while (self.tree.node(body).tag == .group) body = self.tree.node(body).a;
        const call = self.tree.node(body);
        if (call.tag != .apply) return false;
        var target = call.a;
        while (self.tree.node(target).tag == .group) target = self.tree.node(target).a;
        if (self.tree.node(target).tag != .name) return false;
        const parameter = self.resolved[lambda.a];
        return parameter != 0 and self.resolved[target] == parameter;
    }
    fn capabilityFamilyAnnotation(self: *const Engine, original: ast.Id) ?u32 {
        if (original == 0) return null;
        var head = original;
        while (self.tree.node(head).tag == .type_apply) head = self.tree.node(head).a;
        const name = self.tree.node(head);
        if (name.tag != .type_name) return null;
        return self.catalogs.effect_family_names.get(self.catalogKey(name.a));
    }
    fn capabilityDescriptorAnnotation(self: *Engine, original: ast.Id) T.Error!?T.Id {
        const family_index = self.capabilityFamilyAnnotation(original) orelse return null;
        const family = self.effect_families.items[family_index];
        var head = original;
        var syntax: std.ArrayList(ast.Id) = .empty;
        defer syntax.deinit(self.allocator);
        while (self.tree.node(head).tag == .type_apply) {
            try syntax.append(self.allocator, self.tree.node(head).b);
            head = self.tree.node(head).a;
        }
        if (syntax.items.len != family.parameters.len) {
            try self.diagnostic(.type_arity, original);
            return try self.types.fresh();
        }
        std.mem.reverse(ast.Id, syntax.items);
        var arguments: std.ArrayList(T.Id) = .empty;
        defer arguments.deinit(self.allocator);
        for (syntax.items, self.parameter_patterns.list(family.patterns)) |source, pattern_| try arguments.append(self.allocator, try self.parameterArgument(pattern_, source, true, 0));
        return try self.types.nominal(family.identity, arguments.items);
    }
    fn capabilityFlowContract(self: *const Engine, source: ast.Id, annotation_: ast.Id) CapabilityFlow {
        const basic = @import("capability_flow.zig").source(self.tree, source);
        if (basic != .unknown) return basic;
        const member = @import("capability_flow.zig").memberSource(self.tree, self.pool, source);
        const curried = @import("capability_flow.zig").curriedUnitSource(self.tree, source);
        const pair = @import("capability_flow.zig").pairMemberSource(self.tree, self.pool, source);
        if (!member and !curried and pair == null) {
            const summary = @import("capability_flow.zig").parameterSource(self.tree, self.pool, source, annotation_);
            if (summary.kind != .product or summary.arity() == 0) return .unknown;
            if (@import("capability_contract_source.zig").inputFunction(self.tree, self.pool, source, self.operation_refs, &self.types, self.expr_types, summary.arity())) return .input_shape;
            return .unknown;
        }
        var head = source;
        while (self.tree.node(head).tag == .group) head = self.tree.node(head).a;
        const lambda = self.tree.node(head);
        var family_annotation = self.tree.parameter(lambda.a).annotation;
        if (family_annotation == 0 and annotation_ != 0) {
            const signature = self.tree.node(annotation_);
            if (signature.tag == .type_function) {
                const input = self.tree.node(signature.a);
                if (input.tag == .type_binder) family_annotation = input.b;
            }
        }
        if (self.capabilityFamilyAnnotation(family_annotation) == null) return .unknown;
        if (pair) |index| {
            const inner = self.tree.node(lambda.b);
            var second_annotation = self.tree.parameter(inner.a).annotation;
            if (second_annotation == 0 and annotation_ != 0) {
                const result = self.tree.node(self.tree.node(annotation_).b);
                if (result.tag == .type_function) {
                    const input = self.tree.node(result.a);
                    if (input.tag == .type_binder) second_annotation = input.b;
                }
            }
            if (self.capabilityFamilyAnnotation(second_annotation) == null) return .unknown;
            if (index == 0) return .member_first_unit;
            return .member_second_unit;
        }
        if (curried) return .invoke_with_capability;
        return .member_unit;
    }
    fn taskLoanEncloses(self: *Engine, raw: T.Id, group: T.Id, remaining: *usize, depth: usize) T.Error!bool {
        if (depth >= 128 or remaining.* == 0) return false;
        remaining.* -= 1;
        const node = self.types.node(self.types.head(raw, 0));
        switch (node.tag) {
            .usage => {
                if (node.b == @backingInt(T.UsageKind.borrow)) {
                    const destination = self.types.node(self.types.head(group, 0));
                    if (destination.b != self.unit or destination.c >= self.tree.nodes.items.len) return false;
                    const target = self.tree.span(destination.c);
                    var found = false;
                    for (self.bindings.items[1..]) |binding| {
                        if (remaining.* == 0) return false;
                        remaining.* -= 1;
                        if (binding.kind != .parameter or binding.declaration == 0 or binding.owner == 0) continue;
                        const parameter = self.types.node(self.types.head(binding.ty, 0));
                        if (parameter.tag != .usage or parameter.b != @backingInt(T.UsageKind.borrow) or parameter.c != node.c) continue;
                        const birth = self.tree.span(binding.declaration);
                        const owner = self.tree.span(binding.owner);
                        if (birth.start < target.start and owner.start <= target.start and target.end <= owner.end) found = true;
                    }
                    if (!found) return false;
                }
                return self.taskLoanEncloses(node.a, group, remaining, depth + 1);
            },
            .array, .list, .cursor, .demand => return self.taskLoanEncloses(node.a, group, remaining, depth + 1),
            .product => for (self.types.list(.{ .start = node.a, .len = node.b })) |child| {
                if (!try self.taskLoanEncloses(child, group, remaining, depth + 1)) return false;
            },
            .record => for (0..node.b) |index| {
                if (!try self.taskLoanEncloses(self.types.recordField(node, index).ty, group, remaining, depth + 1)) return false;
            },
            .nominal => for (self.types.nominalArguments(node)) |child| {
                if (!try self.taskLoanEncloses(child, group, remaining, depth + 1)) return false;
            },
            else => {},
        }
        return true;
    }
    fn taskClosure(self: *Engine, source: ast.Id, remaining: *usize) ?ast.Id {
        var current = source;
        for (0..128) |_| {
            if (remaining.* == 0) return null;
            remaining.* -= 1;
            const node = self.tree.node(current);
            if (node.tag == .lambda) return current;
            if (node.tag == .group) {
                current = node.a;
                continue;
            }
            if (node.tag != .name) return null;
            const binding = self.resolved[current];
            if (binding == 0) return null;
            const value = self.bindings.items[binding];
            if (value.kind != .local or value.declaration == 0) return null;
            var next: ast.Id = 0;
            for (self.tree.nodes.items[value.declaration..], value.declaration..) |candidate, index| {
                if (remaining.* == 0) return null;
                remaining.* -= 1;
                if (candidate.tag == .let_stmt and candidate.a == value.declaration) {
                    next = self.tree.binding(@intCast(index)).value;
                    break;
                }
            }
            if (next == 0) return null;
            current = next;
        }
        return null;
    }
    fn taskCaptureType(self: *Engine, root: T.Id, owning: bool, remaining: *usize, depth: usize) T.Error!?Code {
        var cell = root;
        for (0..128) |_| {
            const shape = self.types.node(self.types.head(cell, 0));
            if (shape.tag == .usage) {
                cell = shape.a;
                continue;
            }
            if (shape.tag == .demand and (owning or try @import("usage_check.zig").affine(&self.types, shape.a))) {
                // Moving a deferred input requires a closed latent contract.
                // An unsolved row is constrained here, not trusted as pure.
                self.types.unifyEffects(shape.c, 0) catch |err| switch (err) {
                    error.EffectMismatch, error.InfiniteEffect => return .task_host_contract,
                    else => return err,
                };
            }
            break;
        }
        const resolved = try self.types.resolve(root, 0);
        const issue = try @import("task_types.zig").captureIssue(&self.types, resolved, owning, remaining, depth) orelse return null;
        return switch (issue) {
            .transfer => .task_capture_transfer,
            .capability => .task_capability_shared,
            .demand => .task_demand_shared,
            .host => .task_host_contract,
            .budget => .task_budget,
        };
    }
    fn taskApplication(self: *Engine, id: ast.Id) T.Error!?T.Id {
        if (!self.has_tasks) return null;
        const tasks = @import("task_types.zig");
        var head = id;
        var reverse: [4]ast.Id = undefined;
        var count: usize = 0;
        while (true) {
            while (self.tree.node(head).tag == .group) head = self.tree.node(head).a;
            const applied = self.tree.node(head);
            if (applied.tag != .apply) break;
            if (count == reverse.len) return null;
            reverse[count] = applied.b;
            count += 1;
            head = applied.a;
        }
        const leaf = self.tree.node(head);
        if (leaf.tag != .intrinsic) return null;
        const operation = tasks.lookup(self.pool.get(leaf.a)) orelse return null;
        if (count != tasks.arity(operation)) {
            try self.diagnostic(.call_arity, id);
            return try self.types.fresh();
        }
        const first = reverse[count - 1];
        if (operation == .scope) {
            var callback = first;
            while (self.tree.node(callback).tag == .group) callback = self.tree.node(callback).a;
            const lambda = self.tree.node(callback);
            if (lambda.tag != .lambda) {
                try self.diagnostic(.task_escape, first);
                return try self.types.fresh();
            }
            const capability = try self.types.scoped(try self.types.nominal(tasks.group, &.{}), .{ .unit = self.unit, .decl = lambda.a });
            const result = try self.types.fresh();
            const effects = try self.types.freshEffects();
            const required = try self.types.usage(try self.types.functionWithEffects(capability, result, effects), .once, 0);
            try self.scope_lifetimes.append(self.allocator, capability);
            self.active_effect_scopes += 1;
            defer {
                _ = self.scope_lifetimes.pop();
                self.active_effect_scopes -= 1;
            }
            _ = try self.contextualLambda(first, required);
            var remaining: usize = 65_536;
            const boundary: FootprintBoundary = .{ .exiting = .{ .unit = self.unit, .decl = lambda.a } };
            if (try self.valueFootprint(lambda.b, boundary, &.{}, &remaining, 0) orelse try self.scopeFootprintDepth(result, 0, &remaining, &.{}, boundary)) try self.diagnostic(.task_escape, id);
            try self.constrainEffects(effects, self.ambient, id);
            self.expr_types[head] = try self.types.functionWithEffects(required, result, effects);
            return result;
        }
        const input = try self.expression(first);
        if (operation == .spawn) {
            const group = try self.types.resolve(input, 0);
            if (!tasks.isGroup(&self.types, group)) {
                try self.diagnostic(.task_escape, first);
                return try self.types.fresh();
            }
            const result = try self.types.fresh();
            const effects = try self.types.freshEffects();
            const arrow = try self.types.functionWithEffects(T.unit, result, effects);
            const thunk = try self.types.usage(arrow, .once, 0);
            const actual_thunk = try self.contextualLambda(reverse[0], thunk);
            try self.constrain(actual_thunk, thunk, reverse[0]);
            var remaining: usize = 65_536;
            if (self.taskClosure(reverse[0], &remaining)) |callback| {
                if (try self.closureCaptureFootprint(self.tree.node(callback).b, callback, .{ .task_group = group }, &.{}, &remaining, 0)) try self.diagnostic(.task_capture_transfer, reverse[0]);
            } else try self.diagnostic(.task_capture_transfer, reverse[0]);
            const handle = try self.types.usage(try self.types.nominal(tasks.handle, &.{ group, arrow }), .unique, 0);
            const tail = try self.types.function(thunk, handle);
            self.expr_types[head] = try self.types.function(group, tail);
            self.expr_types[self.tree.node(id).a] = tail;
            return handle;
        }
        if (operation == .read or operation == .write) {
            const view = tasks.viewInfo(&self.types, input) orelse {
                try self.diagnostic(.task_regions_overlap, first);
                return try self.types.fresh();
            };
            const element = self.types.node(view.payload).a;
            if (operation == .read) {
                var budget: usize = 8192;
                if (try @import("usage_check.zig").affineNominal(&self.types, self.nominals.items, element) or try self.taskCaptureType(element, false, &budget, 0) != null) try self.diagnostic(.task_capture_transfer, first);
            }
            const index = try self.expression(reverse[count - 2]);
            try self.constrain(index, T.u32_type, reverse[count - 2]);
            var result = element;
            if (operation == .write) {
                const actual = try self.contextualLambda(reverse[0], element);
                try self.constrain(actual, element, reverse[0]);
                var budget: usize = 8192;
                if (try self.taskCaptureType(self.expr_types[reverse[0]], false, &budget, 0) != null) try self.diagnostic(.task_capability_shared, reverse[0]);
                var footprint_budget: usize = 65_536;
                if (try self.valueFootprint(reverse[0], .{}, &.{}, &footprint_budget, 0) orelse try self.scopeFootprint(element, 0)) try self.diagnostic(.task_capability_shared, reverse[0]);
                result = T.unit;
            }
            var tail = try self.types.function(T.u32_type, result);
            if (operation == .write) {
                tail = try self.types.function(T.u32_type, try self.types.function(element, T.unit));
                self.expr_types[self.tree.node(id).a] = try self.types.function(element, T.unit);
                self.expr_types[self.tree.node(self.tree.node(id).a).a] = tail;
            } else self.expr_types[self.tree.node(id).a] = tail;
            self.expr_types[head] = try self.types.function(input, tail);
            return result;
        }
        if (operation == .split) {
            var owner_source = first;
            while (self.tree.node(owner_source).tag == .group) owner_source = self.tree.node(owner_source).a;
            const owner = self.types.node(self.types.head(input, 0));
            if (self.tree.node(owner_source).tag != .name or owner.tag != .usage or owner.b != @backingInt(T.UsageKind.unique) or self.types.node(owner.a).tag != .array) {
                try self.diagnostic(.task_regions_overlap, first);
                return try self.types.fresh();
            }
            const owner_binding = self.resolved[owner_source];
            var ranges_source = reverse[1];
            while (self.tree.node(ranges_source).tag == .group) ranges_source = self.tree.node(ranges_source).a;
            const ranges = self.tree.node(ranges_source);
            if (ranges.tag != .product or ranges.b == 0 or ranges.b > 16) {
                try self.diagnostic(.task_regions_overlap, reverse[1]);
                return try self.types.fresh();
            }
            var bounds: [16][2]u32 = undefined;
            for (self.tree.children(ranges_source), 0..) |range_source, index| {
                var pair = range_source;
                while (self.tree.node(pair).tag == .group) pair = self.tree.node(pair).a;
                if (self.tree.node(pair).tag != .product or self.tree.node(pair).b != 2) {
                    try self.diagnostic(.task_regions_overlap, range_source);
                    return try self.types.fresh();
                }
                for (self.tree.children(pair), 0..) |endpoint, slot| {
                    var value = endpoint;
                    while (self.tree.node(value).tag == .group) value = self.tree.node(value).a;
                    if (self.tree.node(value).tag != .integer) {
                        try self.diagnostic(.task_regions_overlap, endpoint);
                        return try self.types.fresh();
                    }
                    bounds[index][slot] = self.tree.node(value).a;
                }
                if (bounds[index][0] > bounds[index][1]) {
                    try self.diagnostic(.task_regions_overlap, range_source);
                    return try self.types.fresh();
                }
                for (bounds[0..index]) |prior| {
                    if (prior[0] < prior[1] and bounds[index][0] < bounds[index][1] and prior[0] < bounds[index][1] and bounds[index][0] < prior[1]) {
                        try self.diagnostic(.task_regions_overlap, range_source);
                        return try self.types.fresh();
                    }
                }
            }
            const range_type = try self.expression(reverse[1]);
            var callback = reverse[0];
            while (self.tree.node(callback).tag == .group) callback = self.tree.node(callback).a;
            const lambda = self.tree.node(callback);
            if (lambda.tag != .lambda) {
                try self.diagnostic(.task_capture_transfer, callback);
                return try self.types.fresh();
            }
            var views: [16]T.Id = undefined;
            for (views[0..ranges.b], 0..) |*view, ordinal| {
                const version = try self.types.instanceVersion(.{ .unit = self.unit, .decl = owner_binding }, @intCast(ordinal));
                const scope = try self.types.scoped(try self.types.nominal(tasks.view, &.{ owner.a, version }), .{ .unit = self.unit, .decl = lambda.a });
                view.* = try self.types.usage(scope, .unique, 0);
            }
            const parameters = try self.types.product(views[0..ranges.b]);
            const body_result = try self.types.fresh();
            const effects = try self.types.freshEffects();
            const required = try self.types.usage(try self.types.functionWithEffects(parameters, body_result, effects), .once, 0);
            try self.scope_lifetimes.append(self.allocator, self.types.node(views[0]).a);
            self.active_effect_scopes += 1;
            defer {
                _ = self.scope_lifetimes.pop();
                self.active_effect_scopes -= 1;
            }
            _ = try self.contextualLambda(reverse[0], required);
            var remaining: usize = 65_536;
            const boundary: FootprintBoundary = .{ .exiting = .{ .unit = self.unit, .decl = lambda.a } };
            if (try self.valueFootprint(lambda.b, boundary, &.{}, &remaining, 0) orelse try self.scopeFootprintDepth(body_result, 0, &remaining, &.{}, boundary)) try self.diagnostic(.task_escape, id);
            try self.constrainEffects(effects, self.ambient, id);
            const result = try self.types.product(&.{ input, body_result });
            const callback_type = try self.types.functionWithEffects(required, result, effects);
            const range_arrow = try self.types.function(range_type, callback_type);
            self.expr_types[head] = try self.types.function(input, range_arrow);
            self.expr_types[self.tree.node(id).a] = callback_type;
            self.expr_types[self.tree.node(self.tree.node(id).a).a] = range_arrow;
            return result;
        }
        if (operation == .join or operation == .cancel) {
            const wrapper = self.types.node(try self.types.resolve(input, 0));
            if (wrapper.tag != .usage or wrapper.b != @backingInt(T.UsageKind.unique)) {
                try self.diagnostic(.task_handle_consumed, first);
                return try self.types.fresh();
            }
            const handle = self.types.node(try self.types.resolve(wrapper.a, 0));
            if (handle.tag != .nominal or handle.a != tasks.handle.unit or handle.b != tasks.handle.decl or self.types.nominalArguments(handle).len != 2) {
                try self.diagnostic(.task_host_contract, first);
                return try self.types.fresh();
            }
            const arrow = self.types.node(self.types.nominalArguments(handle)[1]);
            try self.constrainEffects(arrow.c, self.ambient, id);
            var result = T.unit;
            if (operation == .join) result = arrow.b;
            self.expr_types[head] = try self.types.functionWithEffects(input, result, arrow.c);
            return result;
        }
        try self.diagnostic(.task_regions_overlap, id);
        return try self.types.fresh();
    }
    fn effectScopeApplication(self: *Engine, id: ast.Id) T.Error!?T.Id {
        const application = self.tree.node(id);
        const head = self.tree.node(application.a);
        if (head.tag != .intrinsic or !std.mem.eql(u8, self.pool.get(head.a), "@effect.scope")) return null;
        var callback = application.b;
        while (self.tree.node(callback).tag == .group) callback = self.tree.node(callback).a;
        const lambda = self.tree.node(callback);
        if (lambda.tag != .lambda) {
            try self.diagnostic(.effect_identity_scope, application.b);
            return try self.types.fresh();
        }
        const parameter = self.tree.parameter(lambda.a);
        if (parameter.name == 0 or parameter.demanded or parameter.annotation == 0) {
            try self.diagnostic(.effect_identity_scope, lambda.a);
            return try self.types.fresh();
        }
        var annotation_head = parameter.annotation;
        var reverse: std.ArrayList(ast.Id) = .empty;
        defer reverse.deinit(self.allocator);
        while (self.tree.node(annotation_head).tag == .type_apply) {
            try reverse.append(self.allocator, self.tree.node(annotation_head).b);
            annotation_head = self.tree.node(annotation_head).a;
        }
        const family_name = self.tree.node(annotation_head);
        const family_index = if (family_name.tag == .type_name) self.catalogs.effect_family_names.get(self.catalogKey(family_name.a)) else null;
        if (family_index == null) {
            try self.diagnostic(.effect_identity_scope, parameter.annotation);
            return try self.types.fresh();
        }
        const family = self.effect_families.items[family_index.?];
        if (reverse.items.len != family.parameters.len) {
            try self.diagnostic(.type_arity, parameter.annotation);
            return try self.types.fresh();
        }
        std.mem.reverse(ast.Id, reverse.items);
        var arguments: std.ArrayList(T.Id) = .empty;
        defer arguments.deinit(self.allocator);
        for (reverse.items, self.parameter_patterns.list(family.patterns)) |syntax, pattern_| {
            const argument = try self.parameterArgument(pattern_, syntax, true, 0);
            try arguments.append(self.allocator, argument);
        }
        const descriptor = try self.types.nominal(family.identity, arguments.items);
        const capability = try self.types.scoped(descriptor, .{ .unit = self.unit, .decl = lambda.a });
        const saved_parameter = self.scoped_parameter;
        const saved_type = self.scoped_parameter_type;
        self.scoped_parameter = lambda.a;
        self.scoped_parameter_type = capability;
        try self.scope_lifetimes.append(self.allocator, capability);
        self.active_effect_scopes += 1;
        defer {
            _ = self.scope_lifetimes.pop();
            self.scoped_parameter = saved_parameter;
            self.scoped_parameter_type = saved_type;
            self.active_effect_scopes -= 1;
        }
        const signature = self.types.node(try self.types.resolve(try self.expression(callback), 0));
        self.expr_types[application.b] = self.expr_types[callback];
        // Direct scopes publish a closed residual contract. Unknown callback
        // rows are outside this slice; they cannot erase a fresh requirement.
        const residual = try self.types.resolveEffects(signature.c, 0);
        const closed_residual = self.types.effects.row(self.types.rowLabels(residual), .closed) catch |err| return T.effectError(err);
        try self.constrainEffects(signature.c, closed_residual, id);
        const widened = self.types.node(try self.types.openCovariant(try self.types.functionWithEffects(signature.a, signature.b, signature.c)));
        try self.constrainEffects(widened.c, self.ambient, id);
        // Unsolved family payload variables came from the enclosing input.
        // Returning those same shapes cannot expose this new owner. Known
        // callable/opaque shapes and every fresh capability still decline.
        const inherited = try self.types.freeVariables(descriptor);
        defer self.allocator.free(inherited);
        var footprint_budget: usize = 65_536;
        const exiting: Identity = .{ .unit = self.unit, .decl = lambda.a };
        const footprint = try self.valueFootprint(lambda.b, .{ .exiting = exiting }, inherited, &footprint_budget, 0) orelse try self.scopeFootprintDepth(signature.b, 0, &footprint_budget, inherited, .{ .exiting = exiting });
        var residual_owner = false;
        for (self.types.rowLabels(residual)) |label| {
            const instance = self.types.operation(label).instance;
            residual_owner = residual_owner or std.meta.eql(instance, exiting);
            if (instance.unit == 0 and instance.decl != 0 and self.types.node(instance.decl).tag == .instance_selection) residual_owner = residual_owner or try self.scopeFootprintDepth(instance.decl, 0, &footprint_budget, inherited, .{ .exiting = exiting });
        }
        if (footprint or residual_owner) try self.diagnostic(.capability_escape, id);
        try self.effect_scopes.append(self.allocator, .{ .node = id, .callback = callback, .parameter = lambda.a, .capability = capability, .result = signature.b, .body_effects = signature.c });
        self.effect_scope_ids[id] = @intCast(self.effect_scopes.items.len);
        return signature.b;
    }
    fn scopedOperation(self: *Engine, source: ast.Id, receiver: T.Id, member: u32, capability_source: ast.Id) T.Error!?T.Id {
        const capability = self.types.node(try self.types.resolve(receiver, 0));
        if (capability.tag != .scoped) return null;
        const descriptor = self.types.node(try self.types.resolve(capability.a, 0));
        if (descriptor.tag != .nominal) return error.TypeLimit;
        const family_index = self.catalogs.effect_family_identities.get(.{ .unit = descriptor.a, .decl = descriptor.b }) orelse return error.TypeLimit;
        const template_index = self.catalogs.effect_members.get(.{ .family = family_index, .member = member }) orelse {
            try self.diagnostic(.unknown_field, source);
            return try self.types.fresh();
        };
        const family = self.effect_families.items[family_index];
        const template = self.effect_templates.items[template_index];
        const arguments = try self.allocator.dupe(T.Id, self.types.nominalArguments(descriptor));
        defer self.allocator.free(arguments);
        const shapes = try self.allocator.dupe(T.Id, self.types.list(family.parameters));
        defer self.allocator.free(shapes);
        const variables = try self.allocator.dupe(T.Id, self.types.list(family.variables));
        defer self.allocator.free(variables);
        const fresh = try self.allocator.alloc(T.Id, variables.len);
        defer self.allocator.free(fresh);
        for (fresh) |*variable| variable.* = try self.types.fresh();
        for (shapes, arguments) |shape, argument| try self.constrain(try self.types.substitute(shape, variables, fresh), argument, source);
        const parameter_type = try self.types.resolve(try self.types.substitute(template.parameter, variables, fresh), 0);
        const result = try self.types.resolve(try self.types.substitute(template.result, variables, fresh), 0);
        const instance: Identity = .{ .unit = capability.b, .decl = capability.c };
        const label = try self.types.internScopedOperation(template.identity, instance, arguments);
        const latent = try self.types.freshEffects();
        const row = self.types.effects.row(&.{label}, self.types.row(latent).tail) catch |err| return T.effectError(err);
        const signature = try self.types.functionWithEffects(parameter_type, result, row);
        try self.operation_uses.append(self.allocator, .{ .node = source, .template = template_index, .arguments = try self.types.saveList(arguments), .signature = signature, .instance = instance, .capability = capability_source });
        self.operation_refs[source] = @intCast(self.operation_uses.items.len);
        return signature;
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
        var token = try self.types.nominal(identity, arguments);
        if (use.instance.decl != 0) token = try self.types.scoped(token, use.instance);
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
        // The direct subset owns one activation per State installation. A
        // pair selected from different owners requires two runtime owner edges.
        if (!std.meta.eql(self.types.operation(read.label).instance, self.types.operation(write.label).instance)) {
            try self.diagnostic(.effect_identity_scope, id);
            return try self.types.fresh();
        }
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
        var token = self.types.node(try self.types.resolve(token_type, 0));
        var instance: Identity = .{ .unit = 0, .decl = 0 };
        if (token.tag == .scoped) {
            instance = .{ .unit = token.b, .decl = token.c };
            token = self.types.node(try self.types.resolve(token.a, 0));
        }
        if (token.tag != .nominal) return error.TypeLimit;
        const arguments = try self.allocator.dupe(T.Id, self.types.nominalArguments(token));
        defer self.allocator.free(arguments);
        for (arguments) |*argument| {
            argument.* = try self.types.resolve(argument.*, 0);
            if (!try self.types.equalClosed(argument.*, argument.*)) return false;
        }
        const label = try self.types.internScopedOperation(.{ .unit = token.a, .decl = token.b }, instance, arguments);
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
            var nominal_ = self.types.node(try self.types.resolve(token, 0));
            var instance: Identity = .{ .unit = 0, .decl = 0 };
            if (nominal_.tag == .scoped) {
                instance = .{ .unit = nominal_.b, .decl = nominal_.c };
                nominal_ = self.types.node(try self.types.resolve(nominal_.a, 0));
            }
            if (nominal_.tag != .nominal) return error.TypeLimit;
            const arguments = try self.allocator.dupe(T.Id, self.types.nominalArguments(nominal_));
            defer self.allocator.free(arguments);
            for (arguments) |*argument| argument.* = try self.types.resolve(argument.*, 0);
            try labels.append(self.allocator, try self.types.internScopedOperation(.{ .unit = nominal_.a, .decl = nominal_.b }, instance, arguments));
        }
        const storage_count = self.storage_frames.items.len;
        defer self.storage_frames.shrinkRetainingCapacity(storage_count);
        if (self.active_effect_scopes != 0 or self.pool.lookup("@effect.scope") != null) {
            var write: T.Effects.Label = 0;
            if (provider_.tag == .state_provider) write = labels.items[1];
            try self.storage_frames.append(self.allocator, .{ .read = labels.items[0], .write = write, .depth = self.scope_lifetimes.items.len });
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
                if (name.len != 0 and (std.ascii.isLower(name[0]) or name[0] == '_') and std.mem.findScalar(u8, name, '.') == null) return;
                for ([_][]const u8{ "Unit", "Bool", "U32", "F32", "Array", "List", "Cursor", "EffectSet", "EffectDescriptor" }) |builtin| if (std.mem.eql(u8, name, builtin)) return;
                if (!self.catalogs.nominal_names.contains(self.catalogKey(node.a))) {
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
        if (self.editorAt(head)) {
            for (arguments) |argument| _ = try self.annotation(argument);
            const result = try self.captureEditor(head, 0, self.catalogKey(self.tree.node(head).a).namespace);
            self.editor_capture.?.kind = .type_;
            self.expr_types[head] = result;
            return result;
        }
        const name = self.tree.node(head).a;
        if (try self.projectionAnnotation(name, arguments, source)) |projection| return projection;
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
        const index = self.catalogs.nominal_names.get(self.catalogKey(name)) orelse {
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
            // Written type applications substitute an owned binder directly.
            // Assigning it to a fresh inference variable would correctly fail
            // the free-binder escape gate, but would also reject `Box a` inside
            // the very quantifier that owns a.
            if (self.types.has_rank_types and self.parameter_patterns.node(param_pattern).kind == .binding and try @import("rank_walk.zig").contains(&self.types, actual, 0, true)) {
                for (old, fresh) |variable, *replacement| if (variable == shape) {
                    replacement.* = actual;
                    break;
                };
            }
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
        if (n.tag == .variable or n.tag == .projection) {
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
            const nominal_definition = self.nominals.items[index];
            if (nominal_definition.is_opaque and nominal_definition.identity.unit != self.unit and !self.catalogs.associated_members.contains(.{ .identity = identity, .member = name })) {
                try self.diagnostic(.private_access, source);
                return .{ .ty = try self.types.fresh(), .projection = 0 };
            }
            const ctors = try self.allocator.dupe(T.Id, self.types.list(nominal_definition.constructors));
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
        const method = if (!writable) (if (self.identityOf(ty)) |receiver| self.catalogs.associated_members.get(.{ .identity = receiver, .member = name }) else null) else null;
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
                var waiting_member = false;
                if (!active_member and !open_self_member) waiting_member = !try self.prepareSelectedGlobal(binding);
                const retained_self_member = !active_member and self.retainsSelfMember(binding, self.associated.items[index]);
                if (active_member or open_self_member or retained_self_member or waiting_member) {
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
                    // A queued member has not been checked yet. Keep an
                    // ordinary field obligation so its eventual signature is
                    // checked against this occurrence's result. Only an active
                    // recursive member retains a residual receiver requirement.
                    deferred.value.kind = if (waiting_member) .field else .receiver;
                    deferred.value.name = name;
                    deferred.value.other = T.unit;
                    deferred.value.result = result;
                    deferred.value.signature = expected_function;
                    deferred.value.source = source;
                    deferred.method_member = !waiting_member;
                    deferred.wait_target = if (waiting_member) binding else 0;
                    if (deferred.origin == 0) deferred.origin = try self.projectionOrigin(source, name, true);
                    try self.pending.append(try self.pendingAllocator(), deferred);
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
                // A getter uses public associated dispatch, not a physical
                // nominal payload projection. Its source type retains the
                // original receiver identity for ordinary member selection.
                identity = .{ .unit = 0, .decl = 0 };
                variants.clearRetainingCapacity();
            }
        } else if (result == 0) {
            try self.diagnostic(if (writable) .missing_field else .missing_member, source);
            if (!writable) try self.explainReceiver(ty, name);
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
            if (pending.owner != binding or pending.scope != declaration or !pending.method_member or (!pending.suspended and !state.on_stack) or pending.solved or pending.covered or pending.declared) continue;
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
        var binding = self.lookup(root) orelse self.catalogs.globals.get(root);
        if (binding == null) {
            const member = parts.next().?;
            if (self.editorAt(id) and parts.peek() == null and self.isNamespace(root))
                return try self.captureEditor(id, 0, root);
            if (self.pool.lookup(member)) |symbol| binding = self.catalogs.qualified.get(.{ .namespace = root, .member = symbol });
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
            if (self.editorAt(id) and parts.peek() == null)
                return try self.captureEditor(id, ty, 0);
            const symbol = self.pool.lookup(part) orelse {
                try self.diagnostic(.unknown_field, id);
                return try self.types.fresh();
            };
            if (try self.scopedOperation(id, ty, symbol, 0)) |operation| {
                self.operation_uses.items[self.operation_refs[id] - 1].capability_binding = target;
                self.access_paths[id] = try self.types.saveList(path.items);
                self.access_types[id] = try self.types.saveList(types_.items);
                if (parts.peek() != null) try self.diagnostic(.effect_identity_scope, id);
                return operation;
            }
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
        defer self.ambient = saved_ambient;
        const latent = self.ambient;
        try self.row_sources.put(self.allocator, self.types.row(latent).tail.variable, id);
        const input = try self.types.fresh();
        if (self.editorAt(id)) {
            return self.types.functionWithEffects(input, try self.captureEditor(id, input, 0), latent);
        }
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
                const raw = if (field.b == 0) try self.shorthand(child, field.a) else try self.expression(field.b);
                const value = try self.runtimeValue(raw, child);
                diverges = diverges or try self.types.resolve(value, 0) == T.never;
                self.expr_types[child] = value;
                self.projections[child] = @intCast(index);
                try fields.append(self.allocator, .{ .name = field.a, .ty = value });
            }
            return if (diverges) T.never else self.types.record(fields.items);
        }
        const constructor = self.catalogs.constructor_names.get(self.catalogKey(n.a)) orelse {
            try self.constructorDiagnostic(self.tree.node(id).a, id);
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
            const raw = if (f.b == 0) try self.shorthand(child, f.a) else try self.expression(f.b);
            const value = try self.runtimeValue(raw, child);
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
        const catalog = self.catalogs.nominal_names.get(key) orelse return null;
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
        if (self.active_effect_scopes != 0) {
            if (try self.scopeFootprint(left, 0)) try self.diagnostic(.capability_escape, middle.b);
            if (try self.scopeFootprint(right, 0)) try self.diagnostic(.capability_escape, outer.b);
        }
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
        if (self.active_effect_scopes != 0 and try self.scopeFootprint(input, 0)) try self.diagnostic(.capability_escape, outer.b);
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
                const ctor = self.catalogs.constructor_names.get(self.catalogKey(n.a)) orelse {
                    try self.constructorDiagnostic(self.tree.node(id).a, id);
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
                if (!self.nominals.items[definition.nominal].is_opaque and self.types.node(definition.payload).tag == .record and shape.tag == .record and self.tree.node(n.b).tag != .pattern_record) {
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
        const statement_position = self.statement_case == id;
        self.statement_case = 0;
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
        var kept = scope;
        defer self.env.shrinkRetainingCapacity(kept);
        const result = try self.types.fresh();
        const arms = self.tree.list(.{ .start = n.b, .len = n.c });
        // A statement case carries rebinding of enclosing locals out of its
        // do: arms, as if/if let statements do (issue #11 follow-up).
        const carry = statement_position and !diverges and self.resolver_scope.block == 0 and arms.len != 0;
        const version_count = if (carry) std.math.mul(usize, arms.len, scope) catch return error.TypeLimit else 0;
        const versions = try self.allocator.alloc(BindingId, version_count);
        defer self.allocator.free(versions);
        const exits = try self.allocator.alloc(bool, if (carry) arms.len else 0);
        defer self.allocator.free(exits);
        for (arms, 0..) |arm_id, arm_index| {
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
            if (!carry) {
                try self.constrain(result, try self.expression(meta[1]), arm_id);
                continue;
            }
            const arm_versions = versions[arm_index * scope ..][0..scope];
            for (self.env.items[0..scope], arm_versions) |entry, *version| version.* = entry.binding;
            var capture: ArmCapture = .{ .block = meta[1], .versions = arm_versions };
            const saved_capture = self.arm_capture;
            self.arm_capture = &capture;
            const arm_type = self.expression(meta[1]);
            self.arm_capture = saved_capture;
            try self.constrain(result, try arm_type, arm_id);
            exits[arm_index] = try self.types.resolve(try arm_type, 0) == T.never;
            if (capture.carrying) try self.statement_arms.append(self.allocator, .{ .node = meta[1] });
        }
        try self.cases.append(self.allocator, id);
        if (carry) {
            self.env.shrinkRetainingCapacity(scope);
            try self.joinCaseArms(id, arms, versions, exits);
            kept = self.env.items.len;
        }
        return if (diverges) T.never else result;
    }
    /// Carries each enclosing local that a statement case's arms rebind out
    /// of the case. Core tests the arms with nested two-arm statement matches:
    /// level k selects arm k or the levels below it, the last level selects
    /// between the last two arms, and a lone arm falls back to its incoming
    /// version. Each level keeps an if let's binary merges. An arm that exits
    /// contributes nothing, like an exiting if branch, and the versions of the
    /// arms that reach the join must agree in type.
    fn joinCaseArms(self: *Engine, id: ast.Id, arms: []const ast.Id, versions: []const BindingId, exits: []const bool) T.Error!void {
        const scope = self.env.items.len;
        for (0..scope) |index| {
            const entry = self.env.items[index];
            const shadowed = for (self.env.items[index + 1 .. scope]) |later| {
                if (later.name == entry.name) break true;
            } else false;
            if (shadowed) continue;
            var changed = false;
            var live: BindingId = 0;
            for (arms, 0..) |arm_id, arm_index| {
                const version = versions[arm_index * scope + index];
                changed = changed or version != entry.binding;
                if (exits[arm_index]) continue;
                if (live == 0) live = version else try self.constrain(self.bindings.items[live].ty, self.bindings.items[version].ty, arm_id);
            }
            if (!changed or live == 0) continue;
            var level = if (arms.len == 1) arms.len else arms.len - 1;
            var joined = if (arms.len == 1) entry.binding else versions[(arms.len - 1) * scope + index];
            var joined_exits = arms.len != 1 and exits[arms.len - 1];
            while (level != 0) {
                level -= 1;
                const version = versions[level * scope + index];
                if (exits[level]) continue;
                if (joined_exits) {
                    joined = version;
                    joined_exits = false;
                    continue;
                }
                if (version == joined) continue;
                if (arms.len == 1) try self.constrain(self.bindings.items[version].ty, self.bindings.items[joined].ty, arms[level]);
                const merged = try self.addBinding(.{ .name = entry.name, .declaration = id, .owner = self.owner, .kind = .local, .ty = self.bindings.items[version].ty, .predecessor = entry.binding });
                try self.merges.append(self.allocator, .{ .node = arms[level], .result = merged, .then_binding = version, .else_binding = joined });
                joined = merged;
            }
            if (!joined_exits and joined != entry.binding) try self.env.append(self.allocator, .{ .name = entry.name, .binding = joined });
        }
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
            if (reverse.items.len == 0) {
                if (self.lookup(name.a)) |binding| {
                    if (self.bindings.items[binding].operation_ref != 0) {
                        const signature = self.types.node(try self.types.resolve(self.bindings.items[binding].ty, 0));
                        if (signature.tag == .function and self.types.rowLabels(signature.c).len == 1) {
                            try labels.append(self.allocator, self.types.rowLabels(signature.c)[0]);
                            continue;
                        }
                    }
                }
                const text = self.pool.get(name.a);
                if (std.mem.findScalarLast(u8, text, '.')) |separator| {
                    if (self.pool.lookup(text[0..separator])) |root_name| if (self.lookup(root_name)) |binding| {
                        const capability = self.types.node(try self.types.resolve(self.bindings.items[binding].ty, 0));
                        if (capability.tag == .scoped) {
                            const descriptor = self.types.node(try self.types.resolve(capability.a, 0));
                            if (descriptor.tag == .nominal) if (self.catalogs.effect_family_identities.get(.{ .unit = descriptor.a, .decl = descriptor.b })) |family| {
                                const member_name = self.pool.lookup(text[separator + 1 ..]);
                                const template = if (member_name) |member_| self.catalogs.effect_members.get(.{ .family = family, .member = member_ }) else null;
                                if (template) |operation| {
                                    try labels.append(self.allocator, try self.types.internScopedOperation(self.effect_templates.items[operation].identity, .{ .unit = capability.b, .decl = capability.c }, self.types.nominalArguments(descriptor)));
                                    continue;
                                }
                            };
                        }
                    };
                }
            }
            if (std.mem.eql(u8, self.pool.get(name.a), "Foreign")) {
                if (reverse.items.len != 0) try self.diagnostic(.type_arity, label_source) else try labels.append(self.allocator, T.foreign_operation);
                continue;
            }
            var family_index: ?u32 = null;
            var member: ?u32 = null;
            if (self.catalogs.effect_family_names.get(self.catalogKey(name.a))) |family| {
                family_index = family;
            } else if (self.catalogs.effect_operation_names.get(self.catalogKey(name.a))) |template| {
                member = template;
                family_index = self.effect_templates.items[template].family;
            } else {
                const text = self.pool.get(name.a);
                if (std.mem.findScalarLast(u8, text, '.')) |separator| {
                    if (self.textCatalogKey(text[0..separator])) |key| if (self.catalogs.effect_family_names.get(key)) |family| {
                        if (self.pool.lookup(text[separator + 1 ..])) |symbol| if (self.catalogs.effect_members.get(.{ .family = family, .member = symbol })) |template| {
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
            for (reverse.items, shapes, self.parameter_patterns.list(family.patterns)) |syntax, shape, param_pattern| {
                const argument = try self.parameterArgument(param_pattern, syntax, true, 0);
                const selected = try self.types.substitute(shape, old, fresh);
                try self.constrain(argument, selected, syntax);
                try arguments.append(self.allocator, try self.types.resolve(selected, 0));
            }
            const operations = try self.allocator.dupe(T.Id, if (member) |template| &.{template} else self.types.list(family.operations));
            defer self.allocator.free(operations);
            for (operations) |template| try labels.append(self.allocator, try self.types.internSymbolicOperation(self.effect_templates.items[template].identity, arguments.items));
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
    fn dependentParameter(self: *Engine, id: ast.Id) T.Error!T.Id {
        const binder = self.tree.node(id);
        const descriptor = try self.capabilityDescriptorAnnotation(binder.b) orelse {
            if (self.proof_header_active) {
                const parameter = try self.annotation(binder.b);
                const binding = try self.addBinding(.{ .name = binder.a, .declaration = id, .owner = id, .kind = .parameter, .ty = parameter });
                try self.env.append(self.allocator, .{ .name = binder.a, .binding = binding });
                self.expr_types[id] = parameter;
                return parameter;
            }
            try self.diagnostic(.effect_identity_scope, id);
            return self.types.fresh();
        };
        const parameter = try self.types.capabilityParameter(descriptor);
        const binding = try self.addBinding(.{ .name = binder.a, .declaration = id, .owner = id, .kind = .parameter, .ty = parameter });
        try self.env.append(self.allocator, .{ .name = binder.a, .binding = binding });
        self.expr_types[id] = parameter;
        return parameter;
    }
    fn validateRankScope(self: *Engine, scope: u32, old_variables: usize, old_versions: usize, old_rows: usize, old_row_versions: usize, source: ast.Id) T.Error!void {
        // Following the current replacement catches older -> fresh -> rigid
        // aliases, including writes whose immediate target was not a skolem.
        const type_writes = self.types.versions.items.len - old_versions;
        if (type_writes > 4096) return error.TypeLimit;
        if (self.types.effects.versions.items.len - old_row_versions > 4096 - type_writes) return error.TypeLimit;
        for (old_versions..self.types.versions.items.len) |index| {
            const write = self.types.versions.items[index];
            if (write.variable < old_variables and try self.types.containsRigid(write.replacement, scope)) {
                try self.diagnostic(.skolem_escape, source);
                return;
            }
        }
        for (old_row_versions..self.types.effects.versions.items.len) |index| {
            const write = self.types.effects.versions.items[index];
            if (write.variable < old_rows and try self.types.containsRigidRow(write.replacement, scope)) {
                try self.diagnostic(.skolem_escape, source);
                return;
            }
        }
    }
    fn dictionaryGivenSelection(self: *Engine, wanted: T.Obligation) T.Error!?DictionaryGiven {
        if (wanted.kind != .contract) return null;
        var found: ?DictionaryGiven = null;
        for (self.dictionary_givens.items) |given| {
            try self.inferenceTransition();
            const goal = given.predicate;
            if (goal.kind != .contract or !std.meta.eql(goal.identity, wanted.identity)) continue;
            if (!try self.types.equalSymbolic(try self.types.resolve(goal.ty, 0), try self.types.resolve(wanted.ty, 0))) continue;
            if (found != null) {
                try self.diagnostic(.ambiguous_qualified, wanted.source);
                return null;
            }
            const contract = self.contracts.items[self.catalogs.contract_identities.get(goal.identity).?];
            const arguments = self.types.node(try self.types.resolve(goal.ty, 0));
            if (arguments.tag != .product or arguments.b != contract.parameters.len) return error.TypeMismatch;
            const old = try self.allocator.dupe(T.Id, self.types.list(contract.variables));
            defer self.allocator.free(old);
            const old_rows = try self.allocator.dupe(u32, self.types.list(contract.row_variables));
            defer self.allocator.free(old_rows);
            const fresh = try self.allocator.alloc(T.Id, old.len);
            defer self.allocator.free(fresh);
            for (fresh) |*variable| variable.* = try self.types.fresh();
            const rows = try self.allocator.alloc(T.Effects.Id, old_rows.len);
            defer self.allocator.free(rows);
            for (rows) |*row| row.* = try self.types.freshEffects();
            const patterns = try self.allocator.dupe(T.Id, self.types.list(contract.parameters));
            defer self.allocator.free(patterns);
            const actual = try self.allocator.dupe(T.Id, self.types.list(.{ .start = arguments.a, .len = arguments.b }));
            defer self.allocator.free(actual);
            for (patterns, actual) |parameter, endpoint| try self.types.unify(try self.types.substituteWithRows(parameter, old, fresh, old_rows, rows), endpoint);
            var members: std.ArrayList(T.Id) = .empty;
            defer members.deinit(self.allocator);
            const declared = try self.allocator.dupe(PI.ContractMember, self.contract_members.items[contract.members.start..][0..contract.members.len]);
            defer self.allocator.free(declared);
            for (declared) |member| {
                var root: T.Id = 0;
                if (member.kind == .value) root = try self.types.resolve(try self.types.substituteWithRows(member.root, old, fresh, old_rows, rows), 0);
                try members.append(self.allocator, root);
            }
            found = .{ .opening = given.opening, .introduction = given.introduction, .quantifier = given.quantifier, .goal = given.goal, .arguments = try self.types.saveList(actual), .member_types = try self.types.saveList(members.items) };
        }
        return found;
    }
    fn packageProjection(self: *Engine, root: T.Id, arguments: []const T.Id, equations: PackEquations, source: ast.Id) T.Error!T.Id {
        const projection = self.types.node(root);
        const member = self.types.projectionMember(projection);
        for (self.dictionary_selections.items[equations.selections.start..][0..equations.selections.len]) |selection| {
            try self.inferenceTransition();
            if (selection.source != equations.source or selection.quantifier != equations.quantifier) return error.TypeMismatch;
            const written = self.types.quantifierGoals(equations.quantifier)[selection.goal];
            if (written.kind != .contract or written.identity.unit != projection.a or written.identity.decl != projection.b) continue;
            const goal = try self.types.substituteGoal(written, equations.binders, equations.witnesses);
            const tuple = self.types.node(self.types.head(goal.ty, 0));
            if (tuple.tag != .product or tuple.b != arguments.len) continue;
            const required = try self.allocator.dupe(T.Id, self.types.list(.{ .start = tuple.a, .len = tuple.b }));
            defer self.allocator.free(required);
            var same = true;
            for (required, arguments) |left, right| {
                if (!try self.types.equalSymbolic(try self.types.resolve(left, 0), try self.types.resolve(right, 0))) same = false;
            }
            if (!same) continue;
            switch (selection.proof) {
                .given => return self.types.projection(.{ .unit = projection.a, .decl = projection.b }, member, arguments),
                .selected => |proof| {
                    const selected = self.selectedMember(proof, member) orelse break;
                    if (selected.kind != .type_) break;
                    return self.types.resolve(selected.root, 0);
                },
            }
        }
        try self.diagnostic(.package_witness_mismatch, source);
        return self.types.fresh();
    }
    fn checkPackagePack(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        const details = self.tree.extra.items[node.c..][0..2];
        const required = try self.annotation(details[1]);
        const package = self.types.node(try self.types.resolve(required, 0));
        if (package.tag != .existential) {
            try self.diagnostic(.package_expected, details[1]);
            return self.types.fresh();
        }
        if (package.c != node.b) {
            try self.diagnostic(.package_witness_mismatch, id);
            return required;
        }
        const binders = try self.allocator.dupe(T.Id, self.types.list(.{ .start = package.b, .len = package.c }));
        defer self.allocator.free(binders);
        var witnesses: std.ArrayList(T.Id) = .empty;
        var witness_work: @import("usage_check.zig").Work = .{};
        defer witnesses.deinit(self.allocator);
        for (self.tree.list(.{ .start = node.a, .len = node.b })) |witness| {
            const witness_type = try self.annotation(witness);
            self.expr_types[witness] = witness_type;
            if (try @import("usage_check.zig").containsNominalWork(&self.types, self.nominals.items, witness_type, &witness_work)) try self.diagnostic(.usage_evidence_mismatch, witness);
            try witnesses.append(self.allocator, witness_type);
        }
        const body = self.types.substitute(package.a, binders, witnesses.items) catch |err| switch (err) {
            error.TypeMismatch => {
                try self.diagnostic(.package_witness_mismatch, id);
                return required;
            },
            else => return err,
        };
        // Infer witnesses from ordinary payload positions. Associated results
        // are noninjective and cannot determine a witness before its proof.
        var probe: AssociatedMemo = .{ .package_probe = true };
        defer probe.deinit(self.allocator);
        var active: std.ArrayList(u32) = .empty;
        defer active.deinit(self.allocator);
        var expected = body;
        if (self.types.has_projections) expected = try self.normalizeAssociatedNode(body, id, false, &probe, &active, 0);
        const value = try self.contextualLambda(details[0], expected);
        try self.constrain(value, expected, details[0]);
        const selection_start = self.dictionary_selections.items.len;
        const source_goals = try self.allocator.dupe(T.Obligation, self.types.quantifierGoals(required));
        defer self.allocator.free(source_goals);
        for (source_goals, 0..) |goal, ordinal| {
            var selected = try self.types.substituteGoal(goal, binders, witnesses.items);
            selected.source = id;
            if (try self.dictionaryGivenSelection(selected)) |given| {
                try self.dictionary_selections.append(self.allocator, .{ .source = id, .quantifier = required, .goal = @intCast(ordinal), .proof = .{ .given = given } });
            } else if (try self.proveAndSavePredicate(&selected, id)) |proof| {
                try self.dictionary_selections.append(self.allocator, .{ .source = id, .quantifier = required, .goal = @intCast(ordinal), .proof = .{ .selected = proof } });
            } else try self.diagnostic(.package_witness_mismatch, id);
        }
        if (self.types.has_projections) {
            var equations: AssociatedMemo = .{ .package = .{ .source = id, .quantifier = required, .selections = .{ .start = @intCast(selection_start), .len = @intCast(self.dictionary_selections.items.len - selection_start) }, .binders = binders, .witnesses = witnesses.items } };
            defer equations.deinit(self.allocator);
            const normalized = try self.normalizeAssociatedNode(body, id, false, &equations, &active, 0);
            try self.constrainRaw(value, normalized, details[0]);
        }
        return required;
    }
    fn checkPackageUnpack(self: *Engine, id: ast.Id) T.Error!T.Id {
        try self.inferenceTransition();
        const node = self.tree.node(id);
        const details = self.tree.extra.items[node.c..][0..3];
        const value = try self.expression(node.a);
        const package = self.types.node(try self.types.resolve(value, 0));
        if (package.tag != .existential) {
            try self.diagnostic(.package_expected, node.a);
            return self.types.fresh();
        }
        if (details[0] != package.c) {
            try self.diagnostic(.package_witness_mismatch, id);
            return self.types.fresh();
        }
        const old_variables = self.types.variables.items.len;
        const old_versions = self.types.versions.items.len;
        const old_rows = self.types.effects.variables.items.len;
        const old_row_versions = self.types.effects.versions.items.len;
        const scope = try self.types.rigidScope();
        try self.rank_implementations.append(self.allocator, .{ .scope = scope, .quantified = value, .node = id });
        const type_scope = self.type_env.items.len;
        const value_scope = self.env.items.len;
        defer self.type_env.shrinkRetainingCapacity(type_scope);
        defer self.env.shrinkRetainingCapacity(value_scope);
        const binders = try self.allocator.dupe(T.Id, self.types.list(.{ .start = package.b, .len = package.c }));
        defer self.allocator.free(binders);
        var rigids: std.ArrayList(T.Id) = .empty;
        defer rigids.deinit(self.allocator);
        for (self.tree.list(.{ .start = node.b, .len = details[0] }), binders, 0..) |binder_id, bound, ordinal| {
            const syntax = self.tree.node(binder_id);
            if (syntax.b != 0 or self.types.node(bound).b != 0) {
                try self.diagnostic(.package_witness_mismatch, binder_id);
                return self.types.fresh();
            }
            for (self.type_env.items[type_scope..]) |entry| if (entry.name == syntax.a) try self.diagnostic(.duplicate_type_parameter, binder_id);
            const rigid = try self.types.rigid(scope, @intCast(ordinal), 0);
            self.expr_types[binder_id] = rigid;
            try rigids.append(self.allocator, rigid);
            try self.type_env.append(self.allocator, .{ .name = syntax.a, .ty = rigid });
        }
        const opened = try self.types.substitute(package.a, binders, rigids.items);
        const binding = try self.addBinding(.{ .name = details[1], .declaration = id, .owner = self.owner, .kind = .local, .ty = opened });
        self.resolved[id] = binding;
        try self.env.append(self.allocator, .{ .name = details[1], .binding = binding });
        const goal_frontier = self.dictionary_givens.items.len;
        defer self.dictionary_givens.shrinkRetainingCapacity(goal_frontier);
        const goals = try self.allocator.dupe(T.Obligation, self.types.quantifierGoals(try self.types.resolve(value, 0)));
        defer self.allocator.free(goals);
        for (goals, 0..) |goal, ordinal| try self.dictionary_givens.append(self.allocator, .{ .opening = binding, .quantifier = try self.types.resolve(value, 0), .goal = @intCast(ordinal), .predicate = try self.types.substituteGoal(goal, binders, rigids.items) });
        const result = try self.expression(details[2]);
        try self.finishDictionaryUses(details[2]);
        try self.finishDictionaryGoals(details[2]);
        try self.validateRankScope(scope, old_variables, old_versions, old_rows, old_row_versions, id);
        var footprint_work: usize = 65_536;
        const retained = try self.valueFootprint(details[2], .{ .rank_scope = scope }, &.{}, &footprint_work, 0);
        if (try self.types.containsRigid(result, scope) or (retained orelse true)) try self.diagnostic(.package_escape, details[2]);
        return result;
    }
    fn resourceScope(self: *Engine, source: ast.Id) T.Error!?T.Id {
        var parts: [3]ast.Id = undefined;
        var head = source;
        var count: usize = 0;
        while (self.tree.node(head).tag == .apply and count < parts.len) {
            const node = self.tree.node(head);
            parts[count] = node.b;
            count += 1;
            head = node.a;
            while (self.tree.node(head).tag == .group) head = self.tree.node(head).a;
        }
        const syntax = self.tree.node(head);
        if (syntax.tag != .intrinsic) return null;
        const name = self.pool.get(syntax.a);
        const acquire_owner = std.mem.eql(u8, name, "@resource.acquire");
        const release_owner = std.mem.eql(u8, name, "@resource.release");
        if (!acquire_owner and !release_owner and !std.mem.eql(u8, name, "@resource.scope")) return null;
        if (acquire_owner or release_owner) {
            var expected: usize = 2;
            if (release_owner) expected = 1;
            if (count != expected) {
                try self.diagnostic(.call_arity, source);
                return try self.types.fresh();
            }
            const latent = try self.types.freshEffects();
            const row = self.types.effects.row(&.{T.foreign_operation}, self.types.row(latent).tail) catch |err| return T.effectError(err);
            try self.constrainEffects(row, self.ambient, source);
            if (release_owner) {
                const input = try self.expression(parts[0]);
                const owner = self.types.node(self.types.head(input, 0));
                if (owner.tag != .usage or owner.b != @backingInt(T.UsageKind.unique) or owner.c != 0 or !@import("cleanup_contracts.zig").payloadNominal(&self.types, self.nominals.items, owner.a)) try self.diagnostic(.cleanup_not_safe, parts[0]);
                self.expr_types[head] = try self.types.functionWithEffects(input, T.unit, row);
                return T.unit;
            }
            for (parts[0..count], 0..) |part, index| {
                if (index == 0) {
                    var candidate = part;
                    while (self.tree.node(candidate).tag == .group) candidate = self.tree.node(candidate).a;
                    if (self.tree.node(candidate).tag == .name) {
                        _ = try self.expression(part);
                        if (@import("cleanup_contracts.zig").sourceHost(self, part)) continue;
                    }
                }
                var direct = part;
                while (self.tree.node(direct).tag == .group) direct = self.tree.node(direct).a;
                if (self.tree.node(direct).tag != .lambda) {
                    try self.diagnostic(.cleanup_not_safe, part);
                    return try self.types.fresh();
                }
            }
            const payload = try self.types.fresh();
            const owner = try self.types.usage(payload, .unique, 0);
            const acquire = try self.types.usage(try self.types.functionWithEffects(T.unit, owner, self.ambient), .once, 0);
            _ = try self.contextualLambda(parts[1], acquire);
            if (!@import("cleanup_contracts.zig").payloadNominal(&self.types, self.nominals.items, payload)) try self.diagnostic(.cleanup_not_safe, parts[1]);
            var release = try self.types.usage(try self.types.functionWithEffects(owner, T.unit, try self.types.freshEffects()), .cleanup, 0);
            if (@import("cleanup_contracts.zig").sourceHost(self, parts[0])) {
                const actual = self.types.node(self.types.head(self.expr_types[parts[0]], 0));
                try self.types.unify(self.types.node(actual.a).a, owner);
            } else {
                _ = try self.contextualLambda(parts[0], release);
                var cleanup_row: T.Effects.Id = 0;
                if (@import("cleanup_contracts.zig").sourceForeign(self, parts[0])) cleanup_row = self.types.effects.row(&.{T.foreign_operation}, .closed) catch |err| return T.effectError(err);
                try self.constrainEffects(self.types.node(self.types.node(self.types.head(self.expr_types[parts[0]], 0)).a).c, cleanup_row, parts[0]);
                release = try self.types.usage(try self.types.functionWithEffects(owner, T.unit, cleanup_row), .cleanup, 0);
                self.expr_types[parts[0]] = release;
            }
            if (!@import("cleanup_contracts.zig").sourceTransferred(self, parts[0])) try self.diagnostic(.cleanup_not_safe, parts[0]);
            try self.usage_loans.append(self.allocator, .{ .source = source, .callback = 0, .parameter = 0, .region = 0, .mutable = false, .acquire = parts[1], .release = parts[0] });
            return owner;
        }
        if (count != 3) {
            try self.diagnostic(.call_arity, source);
            return try self.types.fresh();
        }
        for (parts, 0..) |part, index| {
            if (index == 1) {
                var candidate = part;
                while (self.tree.node(candidate).tag == .group) candidate = self.tree.node(candidate).a;
                if (self.tree.node(candidate).tag == .name) {
                    _ = try self.expression(part);
                    if (@import("cleanup_contracts.zig").sourceHost(self, part)) continue;
                }
            }
            var direct = part;
            while (self.tree.node(direct).tag == .group) direct = self.tree.node(direct).a;
            if (self.tree.node(direct).tag != .lambda) {
                try self.diagnostic(.cleanup_not_safe, part);
                return try self.types.fresh();
            }
        }
        // The invocation journal is a compiler-owned Foreign operation. Its
        // visible row prevents constant/startup execution from bypassing the
        // host leave hook, and preserves other operations in an open tail.
        const latent = try self.types.freshEffects();
        const row = self.types.effects.row(&.{T.foreign_operation}, self.types.row(latent).tail) catch |err| return T.effectError(err);
        try self.constrainEffects(row, self.ambient, source);
        const payload = try self.types.fresh();
        const owner = try self.types.usage(payload, .unique, 0);
        const acquire = try self.types.usage(try self.types.functionWithEffects(T.unit, owner, self.ambient), .once, 0);
        _ = try self.contextualLambda(parts[2], acquire);
        if (!@import("cleanup_contracts.zig").payloadNominal(&self.types, self.nominals.items, payload)) try self.diagnostic(.cleanup_not_safe, parts[2]);
        var release = try self.types.usage(try self.types.functionWithEffects(owner, T.unit, try self.types.freshEffects()), .cleanup, 0);
        if (@import("cleanup_contracts.zig").sourceHost(self, parts[1])) {
            release = self.expr_types[parts[1]];
            const actual = self.types.node(self.types.head(self.expr_types[parts[1]], 0));
            try self.types.unify(self.types.node(actual.a).a, owner);
        } else {
            _ = try self.contextualLambda(parts[1], release);
            var cleanup_row: T.Effects.Id = 0;
            if (@import("cleanup_contracts.zig").sourceForeign(self, parts[1])) cleanup_row = self.types.effects.row(&.{T.foreign_operation}, .closed) catch |err| return T.effectError(err);
            try self.constrainEffects(self.types.node(self.types.node(self.types.head(self.expr_types[parts[1]], 0)).a).c, cleanup_row, parts[1]);
            release = try self.types.usage(try self.types.functionWithEffects(owner, T.unit, cleanup_row), .cleanup, 0);
            self.expr_types[parts[1]] = release;
        }
        if (!@import("cleanup_contracts.zig").source(self, parts[1])) try self.diagnostic(.cleanup_not_safe, parts[1]);
        // Acquisition and cleanup are evaluated before the fresh callback
        // region exists. Only the registered payload is loaned to the body.
        const old_variables = self.types.variables.items.len;
        const old_versions = self.types.versions.items.len;
        const old_rows = self.types.effects.variables.items.len;
        const old_row_versions = self.types.effects.versions.items.len;
        const region_scope = try self.types.rigidScope();
        const region = try self.types.rigid(region_scope, 0, 2);
        const loan = try self.types.usage(payload, .borrow_mut, region);
        const result = try self.types.fresh();
        const callback = try self.types.usage(try self.types.functionWithEffects(loan, result, self.ambient), .once, 0);
        var callback_source = parts[0];
        while (self.tree.node(callback_source).tag == .group) callback_source = self.tree.node(callback_source).a;
        if (self.tree.node(callback_source).tag != .lambda) {
            try self.diagnostic(.multiplicity_unknown, parts[0]);
            return result;
        }
        _ = try self.contextualLambda(parts[0], callback);
        const issue_start = self.diagnostics.items.len;
        try self.validateRankScope(region_scope, old_variables, old_versions, old_rows, old_row_versions, source);
        for (self.diagnostics.items[issue_start..]) |*issue| if (issue.code == .skolem_escape) {
            issue.code = .borrow_escape;
        };
        var remaining: usize = 65_536;
        const inherited = try self.types.freeVariables(payload);
        defer self.allocator.free(inherited);
        const boundary: FootprintBoundary = .{ .loan = region };
        const lambda = self.tree.node(callback_source);
        const escapes = try self.valueFootprint(lambda.b, boundary, inherited, &remaining, 0) orelse try self.scopeFootprintDepth(result, 0, &remaining, inherited, boundary);
        if (escapes) try self.diagnostic(.borrow_escape, parts[0]);
        try self.usage_loans.append(self.allocator, .{ .source = source, .callback = parts[0], .parameter = lambda.a, .region = region, .mutable = true, .acquire = parts[2], .release = parts[1] });
        self.expr_types[parts[2]] = acquire;
        self.expr_types[parts[1]] = release;
        self.expr_types[parts[0]] = callback;
        return result;
    }
    fn usageBorrow(self: *Engine, source: ast.Id) T.Error!?T.Id {
        const application = self.tree.node(source);
        var first = application.a;
        while (self.tree.node(first).tag == .group) first = self.tree.node(first).a;
        const argument = self.tree.node(first);
        if (argument.tag != .apply) return null;
        var leaf = argument.a;
        while (self.tree.node(leaf).tag == .group) leaf = self.tree.node(leaf).a;
        const head = self.tree.node(leaf);
        if (head.tag != .intrinsic) return null;
        const name = self.pool.get(head.a);
        const mutable = std.mem.eql(u8, name, "@usage.borrow_mut");
        if (!mutable and !std.mem.eql(u8, name, "@usage.borrow")) return null;
        const input = try self.expression(argument.b);
        const owner = self.types.node(self.types.head(input, 0));
        if (owner.tag != .usage or (owner.b != @backingInt(T.UsageKind.unique) and owner.b != @backingInt(T.UsageKind.borrow_mut) and (mutable or (owner.b != @backingInt(T.UsageKind.shared) and owner.b != @backingInt(T.UsageKind.borrow))))) {
            try self.diagnostic(.usage_evidence_mismatch, argument.b);
            return try self.types.fresh();
        }
        var callback = application.b;
        while (self.tree.node(callback).tag == .group) callback = self.tree.node(callback).a;
        const lambda = self.tree.node(callback);
        if (lambda.tag != .lambda) {
            try self.diagnostic(.multiplicity_unknown, application.b);
            return try self.types.fresh();
        }
        const old_variables = self.types.variables.items.len;
        const old_versions = self.types.versions.items.len;
        const old_rows = self.types.effects.variables.items.len;
        const old_row_versions = self.types.effects.versions.items.len;
        const region_scope = try self.types.rigidScope();
        const region = try self.types.rigid(region_scope, 0, 2);
        var kind: T.UsageKind = .borrow;
        if (mutable) kind = .borrow_mut;
        const loan = try self.types.usage(owner.a, kind, region);
        const result = try self.types.fresh();
        const required = try self.types.usage(try self.types.functionWithEffects(loan, result, self.ambient), .once, 0);
        _ = try self.contextualLambda(callback, required);
        const issue_start = self.diagnostics.items.len;
        try self.validateRankScope(region_scope, old_variables, old_versions, old_rows, old_row_versions, source);
        for (self.diagnostics.items[issue_start..]) |*issue| if (issue.code == .skolem_escape) {
            issue.code = .borrow_escape;
        };
        self.expr_types[application.b] = required;
        const inherited = try self.types.freeVariables(input);
        defer self.allocator.free(inherited);
        var remaining: usize = 65_536;
        const boundary: FootprintBoundary = .{ .loan = region };
        const escapes = try self.valueFootprint(lambda.b, boundary, inherited, &remaining, 0) orelse try self.scopeFootprintDepth(result, 0, &remaining, inherited, boundary);
        if (escapes) try self.diagnostic(.borrow_escape, application.b);
        try self.usage_loans.append(self.allocator, .{ .source = source, .callback = application.b, .parameter = lambda.a, .region = region, .mutable = mutable });
        self.expr_types[first] = try self.types.function(required, result);
        self.expr_types[leaf] = try self.types.function(input, self.expr_types[first]);
        return result;
    }
    fn contextualLambda(self: *Engine, source: ast.Id, required: T.Id) T.Error!T.Id {
        const syntax = self.tree.node(source);
        if (syntax.tag == .group) {
            const value = try self.contextualLambda(syntax.a, required);
            self.expr_types[source] = value;
            return value;
        }
        const expected = self.types.node(try self.types.resolve(required, 0));
        if (expected.tag == .usage and (expected.b == @backingInt(T.UsageKind.unique) or expected.b == @backingInt(T.UsageKind.shared))) {
            var constructor = syntax.tag == .constructor_ref;
            if (syntax.tag == .apply) {
                var callee = syntax.a;
                while (self.tree.node(callee).tag == .group) callee = self.tree.node(callee).a;
                constructor = self.tree.node(callee).tag == .constructor_ref;
            }
            if (syntax.tag == .integer or syntax.tag == .float or syntax.tag == .boolean or syntax.tag == .unit or syntax.tag == .array or syntax.tag == .product or syntax.tag == .record or constructor) {
                const actual = try self.expression(source);
                try self.constrain(actual, expected.a, source);
                if (@import("cleanup_contracts.zig").payloadNominal(&self.types, self.nominals.items, actual)) {
                    self.expr_types[source] = required;
                    return required;
                }
                try self.diagnostic(.usage_evidence_mismatch, source);
                return actual;
            }
        }

        if (expected.tag == .usage and (expected.b == @backingInt(T.UsageKind.once) or expected.b == @backingInt(T.UsageKind.many) or expected.b == @backingInt(T.UsageKind.cleanup))) {
            if (syntax.tag == .lambda) {
                const actual = try self.contextualLambda(source, expected.a);
                try self.constrain(actual, expected.a, source);
                self.expr_types[source] = required;
                return required;
            }
        }
        if (expected.tag == .forall) {
            try self.inferenceTransition();
            if (syntax.tag == .if_expr) {
                try self.constrain(try self.expression(syntax.a), T.boolean, syntax.a);
                const left = try self.contextualLambda(syntax.b, required);
                const right = try self.contextualLambda(syntax.c, required);
                try self.constrain(left, required, syntax.b);
                try self.constrain(right, required, syntax.c);
                self.expr_types[source] = required;
                return required;
            }
            const old_variables = self.types.variables.items.len;
            const old_versions = self.types.versions.items.len;
            const old_rows = self.types.effects.variables.items.len;
            const old_row_versions = self.types.effects.versions.items.len;
            const instance = try self.types.instantiateRank(required, true);
            try self.rank_implementations.append(self.allocator, .{ .scope = instance.scope, .quantified = required, .node = source });
            const given_frontier = self.dictionary_givens.items.len;
            defer self.dictionary_givens.shrinkRetainingCapacity(given_frontier);
            for (self.types.quantifier_obligations.items[instance.goals.start..][0..instance.goals.len], 0..) |goal, ordinal| {
                try self.dictionary_givens.append(self.allocator, .{ .opening = 0, .introduction = source, .quantifier = required, .goal = @intCast(ordinal), .predicate = goal });
            }
            var value = try self.contextualLambda(source, instance.body);
            if (self.types.node(try self.types.resolve(value, 0)).tag == .forall) value = (try self.types.instantiateRank(value, false)).body;
            const validation_start = self.diagnostics.items.len;
            try self.constrain(value, instance.body, source);
            try self.finishDictionaryUses(source);
            try self.finishDictionaryGoals(source);
            for (self.diagnostics.items[validation_start..]) |*diagnostic_| if (diagnostic_.code == .type_mismatch) {
                diagnostic_.code = .rank_mismatch;
            };
            try self.validateRankScope(instance.scope, old_variables, old_versions, old_rows, old_row_versions, source);
            self.expr_types[source] = required;
            return required;
        }
        const saved_source = self.expected_lambda_source;
        const saved_type = self.expected_lambda_type;
        self.expected_lambda_source = source;
        self.expected_lambda_type = required;
        defer {
            self.expected_lambda_source = saved_source;
            self.expected_lambda_type = saved_type;
        }
        return self.expression(source);
    }
    fn proofContract(self: *const Engine, binding: BindingId) ?*const proof_headers.Owned {
        for (self.proof_contracts.items) |*contract| if (contract.binding == binding) return &contract.header;
        return null;
    }
    fn proofBodySlot(self: *Engine, contract: ProofContract, lambda: ast.Id) proof_terms.Error!?u32 {
        var source = self.tree.valueDecl(self.bindings.items[contract.binding].declaration).body;
        for (0..contract.parameters.len) |slot| {
            try self.proof_body.values.charge(1);
            while (self.tree.node(source).tag == .group) {
                try self.proof_body.values.charge(1);
                source = self.tree.node(source).a;
            }
            if (self.tree.node(source).tag != .lambda) return null;
            if (source == lambda) return @intCast(slot);
            source = self.tree.node(source).b;
        }
        return null;
    }
    fn proofParameter(self: *Engine, lambda: ast.Id, binding: BindingId) T.Error!void {
        self.proof_body.values.charge(self.proof_contracts.items.len) catch |err| {
            _ = try self.proofHeaderFailure(err, lambda);
            return;
        };
        for (self.proof_contracts.items) |*contract| {
            if (contract.binding != self.current) continue;
            const slot = (self.proofBodySlot(contract.*, lambda) catch |err| {
                _ = try self.proofHeaderFailure(err, lambda);
                return;
            }) orelse return;
            contract.parameters[slot] = binding;
            for (contract.header.proof_slots) |proof_slot| if (proof_slot == slot) {
                const arguments = try self.allocator.alloc(proof_terms.Id, slot);
                defer self.allocator.free(arguments);
                @memset(arguments, 0);
                for (contract.header.value_slots, contract.header.values) |value_slot, kind| {
                    if (value_slot >= slot) break;
                    const parameter = contract.parameters[value_slot];
                    if (parameter == 0) {
                        _ = try self.proofHeaderFailure(error.ProofScopeEscape, lambda);
                        return;
                    }
                    arguments[value_slot] = self.proof_body.values.intern(self.allocator, .{ .tag = .version, .kind = kind, .a = parameter, .b = 1 }) catch |err| {
                        _ = try self.proofHeaderFailure(err, lambda);
                        return;
                    };
                }
                const proposition = contract.header.signature().instantiateRequirement(self.allocator, &self.proof_body.values, slot, arguments) catch |err| {
                    _ = try self.proofHeaderFailure(err, lambda);
                    return;
                };
                self.proof_body.parameter(self.allocator, .{ .binding = binding, .contract = contract.binding, .proposition = proposition }) catch |err| {
                    _ = try self.proofHeaderFailure(err, lambda);
                };
                return;
            };
            return;
        }
    }
    fn proofHeaderFailure(self: *Engine, err: proof_headers.Error, source: ast.Id) T.Error!T.Id {
        const code: Code = switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidProofOperand => .invalid_proof_operand,
            error.ProofScopeEscape => .proof_scope_escape,
            error.ProofAnalysisLimit => .proof_analysis_limit,
            error.ContradictoryProof => .contradictory_proof,
            error.InvalidProofKind => .proof_runtime_use,
        };
        try self.diagnostic(code, source);
        return self.types.fresh();
    }
    fn declaredProofAnnotation(self: *Engine, binding: BindingId, source: ast.Id) T.Error!T.Id {
        if (!self.tree.has_numeric_proofs) return self.annotation(source);
        const contains = proof_headers.contains(self.allocator, self.tree, self.pool, source, .{}) catch |err| return self.proofHeaderFailure(err, source);
        if (!contains) return self.annotation(source);
        const previous = self.proof_header_active;
        self.proof_header_active = true;
        defer self.proof_header_active = previous;
        const required = self.annotation(source) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.TypeLimit => return self.proofHeaderFailure(error.ProofAnalysisLimit, source),
            else => return self.proofHeaderFailure(error.InvalidProofKind, source),
        };
        var kinds: std.ArrayList(?proof_terms.Kind) = .empty;
        defer kinds.deinit(self.allocator);
        var syntax = source;
        var ty = required;
        var wrappers: usize = 0;
        while (self.tree.node(syntax).tag == .type_forall) {
            if (wrappers == 128) return self.proofHeaderFailure(error.ProofAnalysisLimit, source);
            wrappers += 1;
            const owner = self.types.node(self.types.head(ty, 0));
            if (owner.tag != .forall) return self.proofHeaderFailure(error.InvalidProofKind, source);
            ty = owner.a;
            syntax = self.tree.extra.items[self.tree.node(syntax).c];
        }
        while (self.tree.node(syntax).tag == .type_function) {
            const arrow = self.types.node(try self.types.resolve(ty, 0));
            if (arrow.tag != .function) return self.proofHeaderFailure(error.InvalidProofKind, source);
            const input = self.types.node(try self.types.resolve(arrow.a, 0));
            const kind: ?proof_terms.Kind = switch (input.tag) {
                .u32 => .u32,
                .array => .array,
                .list => .list,
                else => null,
            };
            try kinds.append(self.allocator, kind);
            ty = arrow.b;
            syntax = self.tree.node(syntax).b;
        }
        var header = (proof_headers.lower(self.allocator, self.tree, self.pool, source, kinds.items, .{}) catch |err| return self.proofHeaderFailure(err, source)) orelse return required;
        var transferred = false;
        defer if (!transferred) header.deinit(self.allocator);
        // A callable kind does not prove that another function implements this
        // positional contract. Only explicit body binders have authority here.
        var body = self.tree.valueDecl(self.bindings.items[binding].declaration).body;
        for (0..header.arity) |_| {
            while (self.tree.node(body).tag == .group) body = self.tree.node(body).a;
            if (self.tree.node(body).tag != .lambda) {
                try self.diagnostic(.proof_runtime_use, body);
                break;
            }
            body = self.tree.node(body).b;
        }
        self.proof_body.values.charge(self.proof_contracts.items.len + header.arity) catch |err| {
            return self.proofHeaderFailure(err, source);
        };
        if (self.proof_contracts.items.len >= self.proof_body.values.limits.terms) {
            return self.proofHeaderFailure(error.ProofAnalysisLimit, source);
        }
        const parameters = try self.allocator.alloc(BindingId, header.arity);
        errdefer self.allocator.free(parameters);
        @memset(parameters, 0);
        try self.proof_contracts.append(self.allocator, .{ .binding = binding, .header = header, .parameters = parameters });
        transferred = true;
        return required;
    }
    fn annotation(self: *Engine, id: ast.Id) T.Error!T.Id {
        if (id == 0) return self.types.fresh();
        if (self.tree.has_numeric_proofs and proof_headers.proofRelation(self.tree, self.pool, id) != null) {
            if (self.proof_header_active) return self.types.proofKind();
            try self.diagnostic(.proof_runtime_use, id);
            return self.types.fresh();
        }
        if (self.depth >= 1024) return error.TypeLimit;
        self.depth += 1;
        defer self.depth -= 1;
        const node = self.tree.node(id);
        if (node.tag == .type_name and self.editorAt(id)) {
            const key = self.catalogKey(node.a);
            const result = try self.captureEditor(id, 0, key.namespace);
            self.editor_capture.?.kind = .type_;
            self.expr_types[id] = result;
            return result;
        }
        switch (node.tag) {
            .type_name => {
                if (self.activeImplementation()) |implementation| {
                    if (self.implementationMemberIndex(self.implementations.items[implementation], node.a)) |member| {
                        if (self.implementation_members.items[member].kind == .type_) return try self.resolveImplementationMember(member);
                    }
                }
                const name = self.pool.get(node.a);
                if (std.mem.eql(u8, name, "EffectSet")) return self.reflectionType(false);
                if (std.mem.eql(u8, name, "EffectDescriptor")) return self.reflectionType(true);
                if (std.mem.eql(u8, name, "Unit")) return T.unit;
                if (std.mem.eql(u8, name, "Bool")) return T.boolean;
                if (std.mem.eql(u8, name, "U32")) return T.u32_type;
                if (std.mem.eql(u8, name, "F32")) return T.f32_type;
                if (name.len != 0 and (std.ascii.isLower(name[0]) or name[0] == '_') and std.mem.findScalar(u8, name, '.') == null) {
                    const variable = try self.typeVariable(node.a, id);
                    const bound = self.types.node(self.types.head(variable, 0));
                    if ((bound.tag == .bound and bound.b == 2) or (bound.tag == .rigid and bound.c == 2)) {
                        try self.diagnostic(.unsupported_type, id);
                        return self.types.fresh();
                    }
                    return variable;
                }
                return self.nominalAnnotation(id, &.{}, id);
            },
            .type_forall, .type_exists => {
                const row_scope = self.row_env.items.len;
                defer self.row_env.shrinkRetainingCapacity(row_scope);
                const scope = self.type_env.items.len;
                defer self.type_env.shrinkRetainingCapacity(scope);
                var binders: std.ArrayList(T.Id) = .empty;
                defer binders.deinit(self.allocator);
                const details = self.tree.extra.items[node.c..][0..2];
                var unsupported_rank = false;
                for (self.tree.list(.{ .start = node.a, .len = node.b }), 0..) |binder_id, ordinal| {
                    const binder = self.tree.node(binder_id);
                    const universal_sorted = node.tag == .type_forall and (binder.b == @backingInt(ast.BinderSort.region) or binder.b == @backingInt(ast.BinderSort.row));
                    if (binder.b != @backingInt(ast.BinderSort.type_) and !universal_sorted) {
                        unsupported_rank = true;
                        try self.diagnostic(.unsupported_type, binder_id);
                    }
                    for (self.type_env.items[scope..]) |entry| if (entry.name == binder.a) {
                        unsupported_rank = true;
                        try self.diagnostic(.duplicate_type_parameter, binder_id);
                    };
                    const bound = try self.types.boundType(@intCast(ordinal), binder.b);
                    try self.type_env.append(self.allocator, .{ .name = binder.a, .ty = bound });
                    if (binder.b == @backingInt(ast.BinderSort.row)) try self.row_env.append(self.allocator, .{ .name = binder.a, .row = try self.types.rowType(bound) });
                    try binders.append(self.allocator, bound);
                }
                if (unsupported_rank) return self.types.fresh();
                const goals = try self.quantifierPredicates(id, binders.items, scope);
                defer self.allocator.free(goals);
                const body = try self.quantifierBody(details[0], binders.items, goals, scope);
                var tag: T.Tag = .forall;
                if (node.tag == .type_exists) tag = .existential;
                return self.types.quantifiedWithGoals(tag, body, binders.items, goals);
            },
            .type_usage => {
                const kind: T.UsageKind = @fromBackingInt(@intCast(node.a));
                const payload = try self.annotation(node.b);

                if (kind == .shared and try @import("usage_check.zig").affineNominal(&self.types, self.nominals.items, payload)) {
                    try self.diagnostic(.usage_evidence_mismatch, id);
                    return self.types.fresh();
                }
                var region: T.Id = 0;
                if (kind == .borrow or kind == .borrow_mut) {
                    for (self.type_env.items) |entry| if (entry.name == node.c) {
                        region = entry.ty;
                    };
                    if (region == 0) {
                        try self.diagnostic(.unsupported_type, id);
                        return self.types.fresh();
                    }
                }
                if (kind == .concurrent and !@import("task_types.zig").concurrentHost(&self.types, payload)) try self.diagnostic(.task_host_contract, id);
                if (kind == .once or kind == .many or kind == .cleanup or kind == .concurrent) {
                    if (self.types.node(self.types.head(payload, 0)).tag != .function) {
                        try self.diagnostic(.unsupported_type, id);
                        return self.types.fresh();
                    }
                }
                const qualified = try self.types.usage(payload, kind, region);
                if (kind == .cleanup and !@import("cleanup_contracts.zig").hostNominal(&self.types, self.nominals.items, qualified) and !@import("cleanup_contracts.zig").pureNominal(&self.types, self.nominals.items, qualified)) try self.diagnostic(.cleanup_not_safe, id);
                return qualified;
            },
            .type_code => return staging.code(&self.types, try self.annotation(node.a), try self.annotationEffects(node.b)),
            .type_descriptor => return staging.descriptor(&self.types, try self.annotation(node.a)),
            .type_demand => return self.types.demand(try self.annotation(node.a)),
            .type_function => {
                const input = self.tree.node(node.a);
                if (input.tag == .type_binder) {
                    const scope = self.env.items.len;
                    defer self.env.shrinkRetainingCapacity(scope);
                    const parameter = try self.dependentParameter(node.a);
                    const result = try self.annotation(node.b);
                    const row = if (node.c == 0) 0 else try self.annotationEffects(node.c);
                    return self.types.functionWithEffects(parameter, result, row);
                }
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
    fn quantifierRepresentatives(self: *Engine, binders: []const T.Id, type_scope: usize, scope: u32) T.Error![]T.Id {
        const representatives = try self.allocator.alloc(T.Id, binders.len);
        errdefer self.allocator.free(representatives);
        for (binders, representatives, 0..) |binder, *representative, ordinal| {
            try self.inferenceTransition();
            const leaf = self.types.node(binder);
            representative.* = try self.types.rigid(scope, @intCast(ordinal), leaf.b);
            self.type_env.items[type_scope + ordinal].ty = representative.*;
            if (leaf.b == @backingInt(ast.BinderSort.row)) {
                const name = self.type_env.items[type_scope + ordinal].name;
                var index = self.row_env.items.len;
                while (index != 0) {
                    index -= 1;
                    if (self.row_env.items[index].name != name) continue;
                    const value = self.types.effects.node(self.row_env.items[index].row);
                    if (value.tail != .formal or value.tail.formal != binder) return error.TypeMismatch;
                    self.row_env.items[index].row = try self.types.rowType(representative.*);
                    break;
                }
            }
        }
        return representatives;
    }
    fn quantifierBody(self: *Engine, source: ast.Id, binders: []const T.Id, goals: []const T.Obligation, type_scope: usize) T.Error!T.Id {
        const old_variables = self.types.variables.items.len;
        const old_versions = self.types.versions.items.len;
        const old_rows = self.types.effects.variables.items.len;
        const old_row_versions = self.types.effects.versions.items.len;
        const scope = try self.types.rigidScope();
        const rows = try self.allocator.dupe(@TypeOf(self.row_env.items[0]), self.row_env.items);
        defer self.allocator.free(rows);
        defer {
            self.row_env.shrinkRetainingCapacity(rows.len);
            @memcpy(self.row_env.items, rows);
            for (binders, 0..) |binder, ordinal| self.type_env.items[type_scope + ordinal].ty = binder;
        }
        const representatives = try self.quantifierRepresentatives(binders, type_scope, scope);
        defer self.allocator.free(representatives);
        const given_frontier = self.annotation_givens.items.len;
        defer self.annotation_givens.shrinkRetainingCapacity(given_frontier);
        for (goals) |goal| try self.annotation_givens.append(self.allocator, try self.types.substituteGoal(goal, binders, representatives));
        const binding_frontier = self.bindings.items.len;
        const body = try self.annotation(source);
        try self.validateRankScope(scope, old_variables, old_versions, old_rows, old_row_versions, source);
        // Dependent annotation parameters outlive this temporary skolem scope,
        // just like the returned signature. Keep their owned types bound too.
        for (binding_frontier..self.bindings.items.len) |index| {
            const binding = self.bindings.items[index];
            if (binding.kind != .parameter or self.tree.node(binding.declaration).tag != .type_binder) continue;
            const ty = try self.types.substitute(try self.types.resolve(binding.ty, 0), representatives, binders);
            self.bindings.items[index].ty = ty;
            self.expr_types[binding.declaration] = ty;
        }
        return self.types.substitute(try self.types.resolve(body, 0), representatives, binders);
    }
    fn quantifierPredicates(self: *Engine, source: ast.Id, binders: []const T.Id, type_scope: usize) T.Error![]T.Obligation {
        const where_node = self.tree.quantifierPredicates(source);
        if (where_node == 0) return try self.allocator.alloc(T.Obligation, 0);
        const scope = try self.types.rigidScope();
        const rows = try self.allocator.dupe(@TypeOf(self.row_env.items[0]), self.row_env.items);
        defer self.allocator.free(rows);
        defer {
            self.row_env.shrinkRetainingCapacity(rows.len);
            @memcpy(self.row_env.items, rows);
        }
        const representatives = try self.quantifierRepresentatives(binders, type_scope, scope);
        defer self.allocator.free(representatives);
        defer {
            for (binders, 0..) |binder, ordinal| self.type_env.items[type_scope + ordinal].ty = binder;
        }
        var goals: std.ArrayList(T.Obligation) = .empty;
        defer goals.deinit(self.allocator);
        const syntax = self.tree.node(where_node);
        for (self.tree.list(.{ .start = syntax.a, .len = syntax.b })) |goal_source| try self.lowerPredicates(goal_source, where_node, &goals);
        for (goals.items) |*goal| {
            inline for (.{ "ty", "other", "result", "signature" }) |field| {
                if (@field(goal.*, field) != 0) @field(goal.*, field) = try self.types.resolve(@field(goal.*, field), 0);
            }
            goal.* = try self.types.substituteGoal(goal.*, representatives, binders);
        }
        return goals.toOwnedSlice(self.allocator);
    }
    fn lowerPredicates(self: *Engine, id: ast.Id, where_node: ast.Id, output: *std.ArrayList(T.Obligation)) T.Error!void {
        const node = self.tree.node(id);
        const index = self.catalogs.contract_names.get(self.catalogKey(node.a)) orelse {
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
        if (contract.requires_implementation) {
            var application: std.ArrayList(T.Id) = .empty;
            defer application.deinit(self.allocator);
            for (shapes) |shape| try application.append(self.allocator, try self.types.resolve(try self.types.substituteWithRows(shape, old, fresh, rows, fresh_rows), 0));
            try output.append(self.allocator, .{ .kind = .contract, .identity = contract.identity, .ty = try self.types.product(application.items), .source = id, .explicit = true, .qualification_unit = self.unit, .qualification_span = self.tree.span(where_node) });
        }
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
        const kind: T.ObligationKind = if (std.mem.eql(u8, name, "type_eq")) .type_eq else if (std.mem.eql(u8, name, "associated")) .dispatch else if (std.mem.eql(u8, name, "receiver")) .receiver else if (std.mem.eql(u8, name, "merge")) .record_merge else if (std.mem.eql(u8, name, "field")) .field else if (std.mem.eql(u8, name, "update")) .update else if (std.mem.eql(u8, name, "operation")) .effect_operation else if (std.mem.eql(u8, name, "type_rep")) .type_rep else if (std.mem.eql(u8, name, "effect_rep")) .effect_rep else {
            try self.diagnostic(.invalid_constraint, id);
            return null;
        };
        self.has_associated_types = self.has_associated_types or kind == .type_eq;
        self.types.has_projections = self.types.has_projections or kind == .type_eq;
        const named = kind == .dispatch or kind == .receiver or kind == .field or kind == .update;
        const expected: usize = switch (kind) {
            .dispatch, .receiver, .update, .record_merge => 3,
            .field, .type_eq => 2,
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
            var row = try self.types.freshEffects();
            if (self.current == 0 and self.closed_type_variables) {
                // Closed annotation names can still denote the contract
                // declaration's owned formal variables. Instantiate those
                // symbolic arguments before demanding executable evidence.
                const label = try self.types.internSymbolicOperation(template.identity, arguments.items);
                row = self.types.effects.row(&.{label}, .closed) catch |err| return T.effectError(err);
            }
            result.ty = try self.types.functionWithEffects(parameter, output, row);
            result.signature = result.ty;
            result.other = try self.types.product(arguments.items);
            result.identity = template.identity;
        } else if (kind != .effect_rep) {
            result.ty = arguments.items[0];
            if (kind == .field or kind == .type_eq) result.result = arguments.items[1] else {
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
            if (try self.types.containsProjection(part)) return true;
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
        return kind == .type_eq or kind == .contract or kind == .record_merge or kind == .dispatch or kind == .field or kind == .writable_field or kind == .receiver or kind == .update or kind == .effect_operation or kind == .type_rep or kind == .effect_rep;
    }
    fn requirementHead(self: *const Engine, wanted: T.Obligation, declared: T.Obligation) bool {
        if (wanted.kind == .dispatch and declared.kind == .dispatch) return if (wanted.name != 0) wanted.name == declared.name else wanted.operator != .none and wanted.operator == declared.operator;
        if (wanted.kind == .field and (declared.kind == .field or declared.kind == .receiver)) return wanted.name == declared.name and (declared.kind == .field or self.types.node(self.types.head(declared.other, 0)).tag == .unit);
        if (wanted.kind == .writable_field and declared.kind == .update) return wanted.name == declared.name;
        if (wanted.kind != declared.kind) return false;
        if (wanted.kind == .effect_operation or wanted.kind == .contract) return wanted.identity.unit == declared.identity.unit and wanted.identity.decl == declared.identity.decl;
        return wanted.name == declared.name;
    }
    fn unifyRequirement(self: *Engine, wanted: T.Obligation, declared: T.Obligation) T.Error!bool {
        if (!self.requirementHead(wanted, declared)) return false;
        if (wanted.kind == .contract) {
            const left = try self.rewriteGiven(wanted.ty, 0);
            const right = try self.rewriteGiven(declared.ty, 0);
            return self.types.equalSymbolic(left, right);
        }
        if (wanted.kind == .type_eq) {
            const left = try self.rewriteGiven(wanted.ty, 0);
            const right = try self.rewriteGiven(wanted.result, 0);
            return self.types.equalSymbolic(left, right);
        }
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
                    // An empty ambient determines the selected method's row.
                    // Nonempty ambients may contain unrelated body effects.
                    const ambient_signature = wanted.kind == .dispatch;
                    const ambient = self.types.row(try self.types.resolveEffects(a_.c, 0));
                    const pure_ambient = ambient.tail == .closed and ambient.labels.len == 0;
                    if (!ambient_signature or pure_ambient) self.types.unifyEffects(a_.c, b_.c) catch |err| switch (err) {
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
            if (state.on_stack and !inList(self.finishing_group, use.target)) return;
        };
        var i: usize = 0;
        while (i < self.pending.items.len) : (i += 1) {
            const pending = self.pending.items[i];
            if (pending.scope != boundary.scope or pending.declared or pending.covered or pending.solved or pending.local_scheme) continue;
            if (pending.value.kind == .callee_use) {
                // Written clauses cover the callee's requirements at this
                // use, including requirements hidden behind shared schemes.
                self.pending.items[i].solved = true;
                try self.expandUse(pending, pending.expansion);
                continue;
            }
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
                            if (self.catalogs.associated_members.get(.{ .identity = receiver, .member = pending.value.name })) |member| {
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
                try self.covered_requirements.append(self.allocator, .{ .scope = boundary.scope, .value = pending.value });
                self.pending.items[i].covered = true;
                self.pending.items[i].suspended = true;
            }
        }
        self.qualifications.items[index].checked = true;
    }
    fn targetRequirements(self: *Engine, target: BindingId, limit: usize, visited: *std.ArrayList(BindingId), output: *std.ArrayList(T.Obligation)) T.Error!void {
        var work: std.ArrayList(BindingId) = .empty;
        defer work.deinit(self.allocator);
        try work.append(self.allocator, target);
        while (work.pop()) |current| {
            try self.inferenceTransition();
            if (inList(visited.items, current)) continue;
            try visited.append(self.allocator, current);
            const scope = self.bindings.items[current].declaration;
            const qualified = for (self.qualifications.items) |boundary| {
                if (boundary.scope == scope) {
                    try output.appendSlice(self.allocator, self.declared_obligations.items[boundary.clauses.start..][0..boundary.clauses.len]);
                    break true;
                }
            } else false;
            if (qualified) continue;
            for (self.pending.items[0..limit]) |pending| if (pending.scope == scope and !pending.solved and !pending.declared and !pending.covered and !pending.local_scheme) try output.append(self.allocator, pending.value);
            var index = self.qualification_uses.items.len;
            while (index != 0) {
                index -= 1;
                const use = self.qualification_uses.items[index];
                if (use.scope == scope) try work.append(self.allocator, use.target);
            }
        }
    }
    fn prepareQualifications(self: *Engine, group: []const BindingId) T.Error!void {
        var index: usize = 0;
        while (index < self.pending.items.len) : (index += 1) {
            const pending = self.pending.items[index];
            if (pending.declared or pending.covered or pending.solved or pending.local_scheme or pending.value.kind != .callee_use) continue;
            const qualified = for (self.qualifications.items) |boundary| {
                if (boundary.scope == pending.scope and inList(group, boundary.owner)) break true;
            } else false;
            if (!qualified) continue;
            try self.inferenceTransition();
            self.pending.items[index].solved = true;
            try self.expandUse(pending, pending.expansion);
        }
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
        const use_count = self.qualification_uses.items.len;
        for (0..use_count) |use_index| {
            const use = self.qualification_uses.items[use_index];
            if (!inList(group, use.target)) continue;
            var visited: std.ArrayList(BindingId) = .empty;
            defer visited.deinit(self.allocator);
            var requirements: std.ArrayList(T.Obligation) = .empty;
            defer requirements.deinit(self.allocator);
            try self.targetRequirements(use.target, limit, &visited, &requirements);
            self.qualification_scope = use.scope;
            for (requirements.items) |constraint| {
                try self.inferenceTransition();
                const forwarded: ForwardedRequirement = .{ .use = use_index, .value = constraint };
                if (self.forwarded_requirements.contains(forwarded)) continue;
                var value = constraint;
                value.source = use.source;
                // A forwarded implicit method projection is required at this
                // reference occurrence, rather than at the member's body.
                try self.appendPending(.{ .owner = use.owner, .origin = try self.memberUseOrigin(value, use.source), .suspended = value.explicit and value.kind != .record_merge, .value = value });
                try self.forwarded_requirements.put(self.allocator, forwarded, {});
            }
        }
    }
    fn explicitRequirement(self: *const Engine, value: T.Obligation) bool {
        return value.explicit or (value.kind == .callee_use and self.bindings.items[value.identity.decl].summary.has_explicit);
    }
    fn scheme(self: *Engine, root: T.Id, excluded: []const T.Id, group: []const BindingId, capture_concrete: bool, certificate_owner: BindingId, qualification_scope: ast.Id) T.Error!T.Scheme {
        return self.schemeInto(root, excluded, group, capture_concrete, certificate_owner, qualification_scope, &self.obligations, null);
    }
    const SchemeCandidate = struct { index: usize, variables: []T.Id, rows: []u32, retained: bool = false };
    fn schemeCandidates(self: *Engine, group: []const BindingId, capture_concrete: bool, qualification_scope: ast.Id, candidates: *std.ArrayList(SchemeCandidate)) T.Error!void {
        const pending_end = self.pending.items.len;
        var index: usize = 0;
        while (index < pending_end) : (index += 1) {
            // Evidence selection may append obligations and move this table.
            const pending = self.pending.items[index];
            if (pending.solved or pending.covered or pending.local_scheme or !inList(group, pending.owner) or (pending.declared and pending.scope != qualification_scope)) continue;
            if (pending.value.kind == .contract and try self.lexicalDictionaryGoal(pending.value)) {
                self.pending.items[index].solved = true;
                continue;
            }
            if (pending.value.kind == .contract and !pending.declared and !try self.requirementOpen(pending.value)) {
                const saved_owner = self.current;
                self.current = pending.owner;
                defer self.current = saved_owner;
                const application = self.types.node(self.types.head(pending.value.ty, 0));
                if (application.tag == .product) {
                    const issues_before = self.diagnostics.items.len;
                    if (try self.selectImplementation(pending.value.identity, self.types.list(.{ .start = application.a, .len = application.b }), pending.value.source)) |_| {
                        self.pending.items[index].solved = true;
                        continue;
                    }
                    if (self.diagnostics.items.len != issues_before) {
                        // A failed closed request is diagnosed once, even if
                        // selection appended another copy while normalizing it.
                        self.pending.items[index].solved = true;
                        continue;
                    }
                }
            }
            if (!capture_concrete and self.explicitRequirement(pending.value) and index < self.local_requirements_start) continue;
            var qualified = false;
            for (self.qualifications.items) |boundary| if (boundary.scope == qualification_scope) {
                qualified = true;
                break;
            };
            if (qualified and !pending.declared and pending.scope == qualification_scope and sourceRequirement(pending.value.kind)) continue;
            var predicate_free: std.ArrayList(T.Id) = .empty;
            defer predicate_free.deinit(self.allocator);
            var parts: std.ArrayList(T.Id) = .empty;
            defer parts.deinit(self.allocator);
            if (!capture_concrete and pending.value.kind == .callee_use and self.bindings.items[pending.value.identity.decl].summary.has_explicit) {
                try self.requirementParts(pending.value, &parts);
            } else {
                for ([_]T.Id{ pending.value.ty, pending.value.other, pending.value.result, pending.value.signature }) |part| if (part != 0) try parts.append(self.allocator, part);
            }
            for (parts.items) |part| {
                if (part == 0) continue;
                const vars = try self.types.freeVariables(part);
                defer self.allocator.free(vars);
                for (vars) |variable| if (!inList(predicate_free.items, variable)) try predicate_free.append(self.allocator, variable);
            }
            var predicate_rows: std.ArrayList(u32) = .empty;
            defer predicate_rows.deinit(self.allocator);
            for (parts.items) |part| {
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
    }
    fn schemeRequirements(self: *Engine, candidates: []const SchemeCandidate, capture_concrete: bool, output: *std.ArrayList(T.Obligation), suspensions: ?*std.ArrayList(usize)) T.Error!T.List {
        const start: u32 = @intCast(output.items.len);
        for (candidates) |candidate| {
            if (!candidate.retained) continue;
            const pending = self.pending.items[candidate.index];
            if (pending.solved or pending.covered) continue;
            if (pending.value.kind == .contract and try self.lexicalDictionaryGoal(pending.value)) {
                self.pending.items[candidate.index].solved = true;
                continue;
            }
            try output.append(self.allocator, .{ .ty = try self.types.resolve(pending.value.ty, 0), .kind = pending.value.kind, .source = pending.value.source, .name = pending.value.name, .result = if (pending.value.result == 0) 0 else try self.types.resolve(pending.value.result, 0), .other = if (pending.value.other == 0) 0 else try self.types.resolve(pending.value.other, 0), .signature = if (pending.value.signature == 0) 0 else try self.types.resolve(pending.value.signature, 0), .operator = pending.value.operator, .identity = pending.value.identity, .explicit = pending.value.explicit, .qualification_span = pending.value.qualification_span, .qualification_unit = pending.value.qualification_unit });
            if (suspensions) |staged| try staged.append(self.allocator, candidate.index) else self.pending.items[candidate.index].suspended = true;
            if (!capture_concrete and self.explicitRequirement(pending.value)) self.pending.items[candidate.index].local_scheme = true;
        }
        return .{ .start = start, .len = @intCast(output.items.len - start) };
    }
    fn schemeInto(self: *Engine, root: T.Id, excluded: []const T.Id, group: []const BindingId, capture_concrete: bool, certificate_owner: BindingId, qualification_scope: ast.Id, output: *std.ArrayList(T.Obligation), suspensions: ?*std.ArrayList(usize)) T.Error!T.Scheme {
        try self.solveFields();
        if (capture_concrete) try self.expandInformedUses(group, false);
        const resolved = try self.types.resolve(root, 0);
        const free = try self.types.freeVariables(resolved);
        defer self.allocator.free(free);
        var candidates: std.ArrayList(SchemeCandidate) = .empty;
        defer {
            for (candidates.items) |candidate| {
                self.allocator.free(candidate.variables);
                self.allocator.free(candidate.rows);
            }
            candidates.deinit(self.allocator);
        }
        try self.schemeCandidates(group, capture_concrete, qualification_scope, &candidates);
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
                var retained = candidate.retained or pending.method_member or self.explicitRequirement(pending.value) or (capture_concrete and (pending.value.kind == .dispatch or pending.value.kind == .result_dispatch or pending.value.kind == .monad_factory or pending.value.kind == .resolver_dispatch or pending.value.kind == .resolver_shape or pending.value.kind == .effect_operation or pending.value.kind == .effect_handler or pending.value.kind == .type_head or pending.value.kind == .callee_use) and !pending.suspended);
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
        for (self.generative_bindings.items) |*binder| if (binder.arrow != 0) {
            binder.arrow = try self.types.closeCovariant(try self.types.resolve(binder.arrow, 0), row_variables.items, protected_rows.items);
        };
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
        const requirements = try self.schemeRequirements(candidates.items, capture_concrete, output, suspensions);
        return .{ .root = closed.root, .variables = span, .row_variables = try self.types.saveList(row_variables.items), .closed_rows = closed.closed_rows, .generative = try @import("generative_schemes.zig").collect(&self.types, self.allocator, closed.root, self.generative_bindings.items), .obligations = requirements };
    }
    fn sharedKind(kind: T.ObligationKind) bool {
        return switch (kind) {
            .dispatch, .result_dispatch, .field, .writable_field, .receiver, .collection, .record_merge, .update, .effect_operation, .type_head, .type_rep, .effect_rep, .callee_use => true,
            else => false,
        };
    }
    /// Describes a completed scheme for sharing. Only obligations whose
    /// outcome is a function of closed types qualify; everything else keeps
    /// the flat instantiation.
    fn summarize(self: *Engine, principal: T.Scheme) T.Error!SchemeSummary {
        return self.summarizeFrom(principal, self.obligations.items);
    }
    fn summarizeFrom(self: *Engine, principal: T.Scheme, obligations: []const T.Obligation) T.Error!SchemeSummary {
        var summary: SchemeSummary = .{ .shareable = principal.root != 0 and principal.obligations.len != 0 and principal.generative.len == 0, .only_result_selected = principal.obligations.len != 0 };
        var flat: u64 = 0;
        for (obligations[principal.obligations.start..][0..principal.obligations.len]) |constraint| {
            if (!sharedKind(constraint.kind)) summary.shareable = false;
            summary.has_explicit = summary.has_explicit or constraint.explicit;
            if (constraint.kind == .callee_use) {
                const callee = self.bindings.items[constraint.identity.decl].summary;
                if (!callee.shareable) summary.shareable = false;
                summary.has_explicit = summary.has_explicit or callee.has_explicit;
                summary.only_result_selected = summary.only_result_selected and callee.only_result_selected;
                flat += callee.flat_size;
            } else {
                summary.only_result_selected = summary.only_result_selected and constraint.kind == .result_dispatch;
                flat += 1;
            }
        }
        summary.flat_size = @intCast(@min(flat, 1 << 30));
        if (principal.root == 0) return summary;
        const free = try self.types.freeVariables(try self.types.resolve(principal.root, 0));
        defer self.allocator.free(free);
        const free_rows = try self.types.freeRowVariables(try self.types.resolve(principal.root, 0));
        defer self.allocator.free(free_rows);
        var public: std.ArrayList(T.Id) = .empty;
        defer public.deinit(self.allocator);
        for (self.types.list(principal.variables)) |variable| if (inList(free, variable)) try public.append(self.allocator, variable);
        var public_rows: std.ArrayList(u32) = .empty;
        defer public_rows.deinit(self.allocator);
        for (self.types.list(principal.row_variables)) |variable| if (inList(free_rows, variable)) try public_rows.append(self.allocator, variable);
        // Every free root variable must be quantified for an instance to be
        // fully described by its public part.
        if (public.items.len != free.len or public_rows.items.len != free_rows.len) summary.shareable = false;
        var parameter_free: std.ArrayList(T.Id) = .empty;
        defer parameter_free.deinit(self.allocator);
        var cursor = try self.types.resolve(principal.root, 0);
        while (self.types.node(cursor).tag == .function) {
            const function = self.types.node(cursor);
            const vars = try self.types.freeVariables(function.a);
            defer self.allocator.free(vars);
            try parameter_free.appendSlice(self.allocator, vars);
            cursor = try self.types.resolve(function.b, 0);
        }
        const flags = try self.allocator.alloc(u32, public.items.len);
        defer self.allocator.free(flags);
        for (public.items, flags) |variable, *flag| flag.* = @intFromBool(inList(parameter_free.items, variable));
        summary.public_inputs = try self.types.saveList(flags);
        const result_free = try self.types.freeVariables(cursor);
        defer self.allocator.free(result_free);
        for (public.items, flags) |variable, *flag| flag.* = @intFromBool(inList(result_free, variable));
        summary.public_outputs = try self.types.saveList(flags);
        var requirements: std.ArrayList(T.Id) = .empty;
        defer requirements.deinit(self.allocator);
        for (obligations[principal.obligations.start..][0..principal.obligations.len]) |constraint| try self.requirementParts(constraint, &requirements);
        var requirement_variables: std.ArrayList(T.Id) = .empty;
        defer requirement_variables.deinit(self.allocator);
        var requirement_rows: std.ArrayList(u32) = .empty;
        defer requirement_rows.deinit(self.allocator);
        for (requirements.items) |part| {
            const variables = try self.types.freeVariables(part);
            defer self.allocator.free(variables);
            try requirement_variables.appendSlice(self.allocator, variables);
            const rows = try self.types.freeRowVariables(part);
            defer self.allocator.free(rows);
            try requirement_rows.appendSlice(self.allocator, rows);
        }
        for (public.items, flags) |variable, *flag| flag.* = @intFromBool(inList(requirement_variables.items, variable));
        summary.requirement_variables = try self.types.saveList(flags);
        const row_flags = try self.allocator.alloc(u32, public_rows.items.len);
        defer self.allocator.free(row_flags);
        for (public_rows.items, row_flags) |row, *flag| flag.* = @intFromBool(inList(requirement_rows.items, row));
        summary.requirement_rows = try self.types.saveList(row_flags);
        summary.public_variables = try self.types.saveList(public.items);
        summary.public_rows = try self.types.saveList(public_rows.items);
        return summary;
    }
    fn instantiate(self: *Engine, binding: BindingId, source: ast.Id) T.Error!T.Id {
        self.bindings.items[binding].read = true;
        self.operation_refs[source] = self.bindings.items[binding].operation_ref;
        const principal = self.bindings.items[binding].scheme;
        if (principal.root == 0) {
            const value = try self.types.resolve(self.bindings.items[binding].ty, 0);
            if (self.exact_argument_types) return value;
            return self.types.openCovariant(value);
        }
        self.counters.instantiations += 1;
        const summary = self.bindings.items[binding].summary;
        if (summary.shareable) return self.shareScheme(binding, source);
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
        var substitution = try self.types.prepareSubstitution(old, fresh_ids, old_rows, fresh_rows);
        defer substitution.deinit(self.types.allocator);
        const value = try self.types.substitutePrepared(&substitution, principal.root);
        try self.appendInstance(principal.obligations, &substitution, source, 0);
        if (principal.generative.len > 32 or principal.generative.len % 2 != 0) return error.TypeLimit;
        const generators = try temporary.dupe(T.Id, self.types.list(principal.generative));
        defer temporary.free(generators);
        for (0..generators.len / 2) |index| {
            const arrow = try self.types.substitutePrepared(&substitution, generators[index * 2]);
            const selection = try self.types.substitutePrepared(&substitution, generators[index * 2 + 1]);
            try self.generative_bindings.append(self.allocator, .{ .arrow = arrow, .selection = selection });
        }
        if (self.exact_argument_types) return value;
        return self.types.openCovariant(value);
    }
    /// Appends one instance of a scheme's obligations. A shared-scheme use
    /// inside the scheme is instantiated as another use, never flattened.
    /// The one prepared substitution serves every obligation of the instance.
    fn appendInstance(self: *Engine, span: T.List, substitution: *T.Store.Substitution, source: ast.Id, expansion: u32) T.Error!void {
        for (self.obligations.items[span.start..][0..span.len]) |constraint| {
            const ty = try self.types.substitutePrepared(substitution, constraint.ty);
            try self.appendPending(.{ .owner = self.current, .expansion = expansion, .origin = try self.memberUseOrigin(constraint, source), .suspended = constraint.explicit and constraint.kind != .record_merge, .method_member = constraint.kind == .receiver and !constraint.explicit, .value = .{ .ty = ty, .kind = constraint.kind, .source = source, .name = constraint.name, .result = if (constraint.result == 0) 0 else try self.types.substitutePrepared(substitution, constraint.result), .other = if (constraint.other == 0) 0 else try self.types.substitutePrepared(substitution, constraint.other), .signature = if (constraint.signature == 0) 0 else try self.types.substitutePrepared(substitution, constraint.signature), .operator = constraint.operator, .identity = constraint.identity, .explicit = constraint.explicit, .qualification_span = constraint.qualification_span, .qualification_unit = constraint.qualification_unit } });
        }
    }
    /// Instantiates only what the caller can observe. The callee's private
    /// variables and obligations are created when the use is resolved.
    fn shareScheme(self: *Engine, binding: BindingId, source: ast.Id) T.Error!T.Id {
        const callee = self.bindings.items[binding];
        const public = try self.allocator.dupe(T.Id, self.types.list(callee.summary.public_variables));
        defer self.allocator.free(public);
        const public_rows = try self.allocator.dupe(u32, self.types.list(callee.summary.public_rows));
        defer self.allocator.free(public_rows);
        const instance = try self.allocator.alloc(T.Id, std.math.add(usize, public.len, public_rows.len) catch return error.TypeLimit);
        defer self.allocator.free(instance);
        for (instance[0..public.len]) |*id| id.* = try self.types.fresh();
        const fresh_rows = try self.allocator.alloc(T.Effects.Id, public_rows.len);
        defer self.allocator.free(fresh_rows);
        for (fresh_rows, instance[public.len..]) |*row, *carrier| {
            row.* = try self.types.freshEffects();
            carrier.* = try self.types.functionWithEffects(T.unit, T.unit, row.*);
        }
        const value = try self.types.substituteWithRows(callee.scheme.root, public, instance[0..public.len], public_rows, fresh_rows);
        try self.appendPending(.{ .owner = self.current, .value = .{ .ty = try self.types.product(instance), .kind = .callee_use, .source = source, .identity = .{ .unit = self.unit, .decl = binding } } });
        self.counters.shared_uses += 1;
        if (self.exact_argument_types) return value;
        return self.types.openCovariant(value);
    }
    /// Appends the callee's own obligations for one shared use, with the
    /// use's instantiation of the public variables. Private variables are new.
    fn expandUse(self: *Engine, use: PendingObligation, expansion: u32) T.Error!void {
        const saved_owner = self.current;
        const saved_scope = self.qualification_scope;
        self.current = use.owner;
        self.qualification_scope = use.scope;
        defer {
            self.current = saved_owner;
            self.qualification_scope = saved_scope;
        }
        const binding = use.value.identity.decl;
        const callee = self.bindings.items[binding];
        const principal = callee.scheme;
        const product = self.types.node(try self.types.resolve(use.value.ty, 0));
        const instance = try self.allocator.dupe(T.Id, self.types.list(.{ .start = product.a, .len = product.b }));
        defer self.allocator.free(instance);
        const public = try self.allocator.dupe(T.Id, self.types.list(callee.summary.public_variables));
        defer self.allocator.free(public);
        const public_rows = try self.allocator.dupe(u32, self.types.list(callee.summary.public_rows));
        defer self.allocator.free(public_rows);
        const old = try self.allocator.dupe(T.Id, self.types.list(principal.variables));
        defer self.allocator.free(old);
        const fresh_ids = try self.allocator.alloc(T.Id, old.len);
        defer self.allocator.free(fresh_ids);
        for (old, fresh_ids) |variable, *id| {
            id.* = if (std.mem.findScalar(T.Id, public, variable)) |at| instance[at] else try self.types.fresh();
        }
        const old_rows = try self.allocator.dupe(u32, self.types.list(principal.row_variables));
        defer self.allocator.free(old_rows);
        const fresh_rows = try self.allocator.alloc(T.Effects.Id, old_rows.len);
        defer self.allocator.free(fresh_rows);
        for (old_rows, fresh_rows) |variable, *row| {
            row.* = if (std.mem.findScalar(u32, public_rows, variable)) |at| self.types.node(instance[public.len + at]).c else try self.types.freshEffects();
        }
        var substitution = try self.types.prepareSubstitution(old, fresh_ids, old_rows, fresh_rows);
        defer substitution.deinit(self.types.allocator);
        try self.appendInstance(principal.obligations, &substitution, use.value.source, expansion);
    }
    fn purityIdentity(context: *anyopaque, allocator: Allocator, identity: Identity, kind: @import("../eval/purity_type_key.zig").Kind) @import("../eval/purity_type_key.zig").OriginError!@import("../eval/purity_type_key.zig").Identity {
        const self: *Engine = @ptrCast(@alignCast(context));
        const module_name = try self.purity_origins.name(allocator, identity.unit, self.unit);
        errdefer allocator.free(module_name);
        const declaration = switch (kind) {
            .nominal => blk: {
                const index = self.catalogs.nominal_identities.get(identity) orelse return error.SourceIdentityUnavailable;
                break :blk try allocator.dupe(u8, self.pool.get(self.nominals.items[index].name));
            },
            .operation => blk: {
                const index = self.catalogs.effect_template_identities.get(identity) orelse return error.SourceIdentityUnavailable;
                const template = self.effect_templates.items[index];
                if (template.family == 0) return error.SourceIdentityUnavailable;
                const family = self.effect_families.items[template.family];
                break :blk if (family.callable) try allocator.dupe(u8, self.pool.get(family.name)) else try allocator.print("{s}.{s}", .{ self.pool.get(family.name), self.pool.get(template.name) });
            },
        };
        return .{ .module = module_name, .declaration = declaration };
    }
    fn purityArguments(context: *anyopaque, allocator: Allocator, identity: Identity, kind: @import("../eval/purity_type_key.zig").Kind, actual: []const T.Id) @import("../eval/purity_type_key.zig").OriginError![]T.Id {
        const self: *Engine = @ptrCast(@alignCast(context));
        const Formal = struct { patterns: P.List, variables: T.List };
        const formal: Formal = switch (kind) {
            .nominal => blk: {
                const nominal = self.nominals.items[self.catalogs.nominal_identities.get(identity) orelse return error.SourceIdentityUnavailable];
                break :blk .{ .patterns = nominal.patterns, .variables = nominal.variables };
            },
            .operation => blk: {
                const template = self.effect_templates.items[self.catalogs.effect_template_identities.get(identity) orelse return error.SourceIdentityUnavailable];
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
        if (self.catalogs.effect_template_identities.get(operation.identity)) |index| {
            const template = self.effect_templates.items[index];
            if (template.family != 0) {
                const family = self.effect_families.items[template.family];
                witness.family = family.name;
                witness.member = template.name;
                witness.compound = !family.callable;
            }
        }
        const key_context: @import("../eval/purity_type_key.zig").Context = .{ .allocator = self.allocator, .types = &self.types, .source = self, .origin = purityIdentity, .arguments = purityArguments };
        const identity: ?@import("../eval/purity_type_key.zig").Identity = key_context.operation(labels[0], 65536) catch |err| switch (err) {
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
        staging_depth: u32,
        depth: usize,
        current: BindingId,
        pending_start: usize,
        owner: ast.Id,
        proof_owner: ast.Id,
        proof_visits: usize,
        qualification_scope: ast.Id,
        target: T.Id,
        loops: std.ArrayList(LoopFrame),
        escape: bool,
        resolver: ResolverScope,
        ambient: T.Effects.Id,
        annotation_binding: ast.Id,
        inherited_types: usize,
        inherited_rows: usize,
        closed_types: bool,
        implicit_rows: bool,
        type_env: ?@TypeOf(@as(Engine, undefined).type_env.items) = null,
        row_env: ?@TypeOf(@as(Engine, undefined).row_env.items) = null,
        computation_annotations: ?[]T.Id = null,
        env: ?[]Entry = null,
        loops_changed: bool = false,
        annotations_changed: bool = false,
        env_changed: bool = false,
        fn restore(self: *GlobalContext, engine: *Engine) void {
            engine.proof_visits = self.proof_visits;
            engine.staging_depth = self.staging_depth;
            engine.closed_type_variables = self.closed_types;
            engine.implicit_row_parameters = self.implicit_rows;
            engine.depth = self.depth;
            if (self.env_changed) {
                engine.env.clearRetainingCapacity();
                engine.env.appendSliceAssumeCapacity(self.env.?);
                engine.current = self.current;
                engine.owner = self.owner;
                engine.proof_owner = self.proof_owner;
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
        operations_before: usize = 0,
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
        try self.inferenceTransition();
        self.counter += 1;
        try self.global_states.put(self.allocator, binding, .{ .state = .active, .index = self.counter, .low = self.counter, .on_stack = true });
        try self.active.append(self.allocator, binding);
        var context: GlobalContext = .{
            .staging_depth = self.staging_depth,
            .closed_types = self.closed_type_variables,
            .implicit_rows = self.implicit_row_parameters,
            .depth = self.depth,
            .current = self.current,
            .pending_start = self.pending_start,
            .owner = self.owner,
            .proof_owner = self.proof_owner,
            .proof_visits = self.proof_visits,
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
        self.proof_visits = 0;
        self.staging_depth = 0;
        if (self.global_driver) self.depth = 0;
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
        self.proof_owner = self.owner;
        self.return_target = 0;
        context.env_changed = true;
        const id = self.bindings.items[binding].declaration;
        self.qualification_scope = id;
        const declaration = self.tree.valueDecl(id);
        if (self.implementation_bindings.get(binding)) |implementation| {
            try self.implementationMethodScope(implementation);
            self.closed_type_variables = true;
            self.implicit_row_parameters = false;
            const initializer_diagnostics = self.diagnostics.items.len;
            try self.beginImplementationQualification(implementation, id, declaration.body);
            self.body_elaborations += 1;
            return .{ .binding = binding, .id = id, .required = self.bindings.items[binding].ty, .initializer_diagnostics = initializer_diagnostics, .operations_before = self.operation_uses.items.len, .context = context };
        }
        try self.collectAnnotationNames(declaration.annotation, 0);
        try self.collectAnnotationNames(declaration.where_node, 0);
        try self.collectAnnotationNames(declaration.body, 0);
        for (self.tree.list(declaration.attributes)) |attribute| try self.collectAnnotationNames(self.tree.node(attribute).a, 0);
        const initializer_diagnostics = self.diagnostics.items.len;
        const saved_defer = self.defer_associated;
        if (self.implementations.items.len != 0) self.defer_associated = true;
        try self.beginQualification(id, declaration.where_node, declaration.annotation, declaration.body);
        self.defer_associated = saved_defer;
        const required = if (declaration.annotation != 0) try self.declaredProofAnnotation(binding, declaration.annotation) else 0;
        if (declaration.annotation != 0) {
            const written = self.tree.node(declaration.annotation);
            if (written.tag == .type_usage or try self.types.containsQuantifier(required) or try @import("usage_check.zig").containsNominal(&self.types, self.nominals.items, required) or (written.tag == .type_function and self.tree.node(written.a).tag == .type_binder) or self.proofContract(binding) != null) self.expr_types[declaration.annotation] = required;
            if (self.types.node(required).tag == .forall) try self.types.bindRankAnnotation(self.bindings.items[binding].ty, required);
        }
        self.body_elaborations += 1;
        self.traceGlobal(.begun, binding);
        return .{ .binding = binding, .id = id, .required = required, .initializer_diagnostics = initializer_diagnostics, .operations_before = self.operation_uses.items.len, .context = context };
    }
    fn finishGlobal(self: *Engine, frame: *const GlobalFrame, value: T.Id) T.Error!void {
        const binding = frame.binding;
        const id = frame.id;
        const required = frame.required;
        const initializer_diagnostics = frame.initializer_diagnostics;
        const declaration = self.tree.valueDecl(id);
        if (required != 0) try self.constrainRaw(self.bindings.items[binding].ty, required, if (declaration.attributes.len == 0) id else declaration.annotation);
        try self.constrain(self.bindings.items[binding].ty, value, if (declaration.attributes.len != 0 and required != 0) declaration.annotation else id);
        if (self.types.has_proof_kinds and self.proofContract(binding) == null) {
            var result = self.types.head(value, 0);
            var remaining: usize = 1024;
            while (self.types.node(result).tag == .function and remaining != 0) : (remaining -= 1) result = self.types.head(self.types.node(result).b, 0);
            if (remaining == 0) try self.diagnostic(.proof_analysis_limit, id);
            if (self.types.node(result).tag == .erased_proof) try self.diagnostic(.proof_scope_escape, id);
        }
        if (self.diagnostics.items.len == initializer_diagnostics) {
            self.initializerPurity(id) catch |err| switch (err) {
                error.OutOfMemory => return err,
                error.InfiniteEffect => try self.diagnostic(.infinite_effect, id),
                else => return err,
            };
        }
        if (self.implementation_bindings.get(binding)) |implementation| try self.validateImplementationBinders(implementation, id);
        if (self.operation_uses.items.len != frame.operations_before) try self.refreshCapabilityRecipe(binding);
        // Complete means the source body has been checked. on_stack remains
        // true until every selected dependency and member scheme stabilizes.
        self.global_states.getPtr(binding).?.state = .complete;
        const now = self.global_states.get(binding).?;
        if (now.low == now.index) try self.finishComponent(binding);
        if (self.diagnostics.items.len == 0) try self.publishCallback(binding);
        self.traceGlobal(.finished, binding);
    }
    fn inferenceTransition(self: *Engine) T.Error!void {
        if (self.inference_transitions + self.types.projection_steps >= self.inference_limit) {
            self.exhaustBudget();
            return error.TypeLimit;
        }
        self.inference_transitions += 1;
        self.types.projection_limit = @min(self.types.projection_limit, self.inference_limit - self.inference_transitions);
    }
    /// Records the innermost declaration being inferred: a solved field's
    /// owner, else the active global, else the declaration being checked.
    fn exhaustBudget(self: *Engine) void {
        const record = self.budget_exhaustion orelse return;
        if (record.exhausted) return;
        const binding = self.dependency_owner orelse if (self.active.items.len != 0) self.active.items[self.active.items.len - 1] else if (self.current != 0) self.current else self.root_global;
        const declaration = if (binding < self.bindings.items.len) self.bindings.items[binding].declaration else 0;
        record.* = .{ .exhausted = true, .name = if (binding < self.bindings.items.len) self.bindings.items[binding].name else 0, .node = declaration, .span = if (declaration != 0) self.tree.span(declaration) else .{ .start = 0, .end = 0 } };
    }
    fn componentLow(self: *Engine, start: usize, binding: BindingId) u32 {
        var low = self.global_states.get(binding).?.low;
        for (self.active.items[start..]) |member| low = @min(low, self.global_states.get(member).?.low);
        self.global_states.getPtr(binding).?.low = low;
        return low;
    }
    fn resetQualifications(self: *Engine, group: []const BindingId) void {
        for (self.qualifications.items) |*boundary| if (inList(group, boundary.owner)) {
            boundary.checked = false;
        };
    }
    fn pendingState(self: *const Engine) usize {
        var count: usize = 0;
        for (self.pending.items) |pending| if (!pending.solved and !pending.declared and !pending.covered and !pending.local_scheme) {
            count += 1;
        };
        return count;
    }
    fn finishComponent(self: *Engine, binding: BindingId) T.Error!void {
        var group: std.ArrayList(BindingId) = .empty;
        defer group.deinit(self.allocator);
        const saved_group = self.finishing_group;
        defer self.finishing_group = saved_group;
        const start = std.mem.findScalar(BindingId, self.active.items, binding).?;
        while (true) {
            try self.inferenceTransition();
            const state = self.global_states.get(binding).?;
            if (self.componentLow(start, binding) != state.index) return;
            group.clearRetainingCapacity();
            var cursor = self.active.items.len;
            while (cursor > start) {
                cursor -= 1;
                try group.append(self.allocator, self.active.items[cursor]);
            }
            self.finishing_group = group.items;
            var recursive = group.items.len > 1;
            for (self.qualification_uses.items) |use| if (inList(group.items, use.owner) and inList(group.items, use.target)) {
                recursive = true;
                break;
            };
            if (recursive) try self.expandInformedUses(group.items, true);
            try self.expandQualificationUses(group.items);
            try self.prepareQualifications(group.items);
            try self.solveFields();
            if (self.selected_globals.items.len != 0) return;
            if (self.componentLow(start, binding) != state.index) return;
            if (self.active.items.len != start + group.items.len) continue;
            const before_pending = self.pending.items.len;
            const schemes = try self.allocator.alloc(T.Scheme, group.items.len);
            defer self.allocator.free(schemes);
            const summaries = try self.allocator.alloc(SchemeSummary, group.items.len);
            defer self.allocator.free(summaries);
            var obligations: std.ArrayList(T.Obligation) = .empty;
            defer obligations.deinit(self.allocator);
            var suspensions: std.ArrayList(usize) = .empty;
            defer suspensions.deinit(self.allocator);
            for (group.items, 0..) |member, index| {
                schemes[index] = try self.schemeInto(self.bindings.items[member].ty, &.{}, group.items, true, member, self.bindings.items[member].declaration, &obligations, &suspensions);
                summaries[index] = try self.summarizeFrom(schemes[index], obligations.items);
                if (recursive) summaries[index].shareable = false;
            }
            if (self.selected_globals.items.len != 0) return;
            if (self.componentLow(start, binding) != state.index) return;
            if (self.active.items.len != start + group.items.len or self.pending.items.len != before_pending) continue;
            const staged_cursor = self.types.cursor();
            const staged_pending = self.pendingState();
            const staged_uses = self.qualification_uses.items.len;
            // Clause matching can bind a receiver and reveal another body.
            // Stage its diagnostics while that final solver work stabilizes.
            const diagnostic_start = self.diagnostics.items.len;
            var qualification: usize = 0;
            while (qualification < self.qualifications.items.len) : (qualification += 1) if (inList(group.items, self.qualifications.items[qualification].owner)) try self.checkQualification(qualification);
            const diagnostics = try self.allocator.dupe(Diagnostic, self.diagnostics.items[diagnostic_start..]);
            defer self.allocator.free(diagnostics);
            self.diagnostics.shrinkRetainingCapacity(diagnostic_start);
            var diagnostics_published = false;
            defer if (!diagnostics_published) deinitDiagnosticPayloads(self.allocator, diagnostics);
            try self.solveFields();
            if (self.selected_globals.items.len != 0) {
                self.resetQualifications(group.items);
                return;
            }
            if (self.componentLow(start, binding) != state.index) {
                self.resetQualifications(group.items);
                return;
            }
            if (self.active.items.len != start + group.items.len or self.pending.items.len != before_pending or self.types.cursor() != staged_cursor or self.pendingState() != staged_pending or self.qualification_uses.items.len != staged_uses) {
                self.resetQualifications(group.items);
                continue;
            }
            // Reserve both visible outputs before committing any member. Scheme
            // retries own their predicates; independent completed output stays
            // in place. Closed-row certificates record real monotonic solver
            // writes and are deduplicated independently of tentative schemes.
            try self.obligations.ensureUnusedCapacity(self.allocator, obligations.items.len);
            try self.diagnostics.ensureUnusedCapacity(self.allocator, diagnostics.len);
            const obligation_start: u32 = @intCast(self.obligations.items.len);
            self.obligations.appendSliceAssumeCapacity(obligations.items);
            for (suspensions.items) |pending| self.pending.items[pending].suspended = true;
            for (schemes) |*principal| principal.obligations.start += obligation_start;
            self.diagnostics.insertSliceAssumeCapacity(diagnostic_start, diagnostics);
            diagnostics_published = true;
            for (group.items, 0..) |member, index| {
                self.bindings.items[member].scheme = schemes[index];
                self.bindings.items[member].summary = summaries[index];
                try self.finishCapabilityRole(member);
                self.global_states.getPtr(member).?.on_stack = false;
            }
            self.active.shrinkRetainingCapacity(start);
            return;
        }
    }
    fn inferGlobal(self: *Engine, binding: BindingId) T.Error!void {
        if (self.global_states.get(binding).?.state != .pending) return self.flushGlobalDiagnostics(binding);
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
        if (self.execution.schedule_globals and !self.global_driver) return self.inferScheduledGlobal(binding);
        var frame = try self.beginGlobal(binding);
        defer frame.context.restore(self);
        const declaration = self.tree.valueDecl(frame.id);
        const value = try self.inferDeclarationBody(declaration);
        try self.finishGlobal(&frame, value);
    }
    fn inferDeclarationBody(self: *Engine, declaration: ast.ValueDecl) T.Error!T.Id {
        if (!self.tree.has_numeric_proofs and !self.types.has_proof_kinds) return self.taggedExpression(self.tree.list(declaration.attributes), declaration.body, 0);
        const before = self.proof_visits;
        const frontier = self.proof_body.frontier(self.proof_contracts.items.len);
        const value = try self.taggedExpression(self.tree.list(declaration.attributes), declaration.body, 0);
        const visits = self.proof_visits - before;
        if (visits != 0) try self.proof_body.debits.append(self.allocator, .{ .binding = self.current, .visits = @intCast(visits), .frontier = frontier, .output = self.proof_body.frontier(self.proof_contracts.items.len) });
        return value;
    }
    /// Reconstruct owned live facts only after every direct interface read has
    /// committed. Active SCC members and unsupported shapes remain ordinary.
    fn bodyAnnotations(self: *const Engine) @import("../reuse/body_check_cache.zig").AnnotationLookup {
        return .{ .context = self, .lookup = struct {
            fn lookup(context: *const anyopaque, name: []const u8) ?usize {
                const engine: *const Engine = @ptrCast(@alignCast(context));
                const symbol = engine.pool.lookup(name) orelse return null;
                const index = engine.catalogs.nominal_names.get(engine.catalogKey(symbol)) orelse return null;
                return index;
            }
        }.lookup, .effect = bodyEffectAnnotation };
    }
    fn bodyEffectAnnotation(context: *const anyopaque, name: []const u8) ?@import("../reuse/body_check_cache.zig").EffectAnnotation {
        const self: *const Engine = @ptrCast(@alignCast(context));
        const symbol = self.pool.lookup(name) orelse return null;
        // Binding-valued operations and scoped capabilities have a different
        // authority from declaration rows and must take ordinary checking.
        if (self.lookup(symbol)) |binding| if (self.bindings.items[binding].operation_ref != 0) return null;
        const key = self.catalogKey(symbol);
        if (self.catalogs.effect_family_names.get(key)) |family| return .{ .family = family };
        if (std.mem.findScalarLast(u8, name, '.')) |separator| {
            if (self.pool.lookup(name[0..separator])) |root| if (self.lookup(root)) |_| return null;
            if (self.textCatalogKey(name[0..separator])) |family_key| if (self.catalogs.effect_family_names.get(family_key)) |family| {
                const member_name = self.pool.lookup(name[separator + 1 ..]) orelse return null;
                const member = self.catalogs.effect_members.get(.{ .family = family, .member = member_name }) orelse return null;
                return .{ .family = family, .member = member };
            };
        }
        return null;
    }
    fn bodyCatalog(self: *Engine) @import("../reuse/body_check_cache.zig").Catalog {
        return .{ .unit = self.unit, .pool = self.pool, .nominals = self.nominals.items, .constructors = self.constructors.items, .effect_families = self.effect_families.items, .effect_templates = self.effect_templates.items, .contracts = self.contracts.items, .contract_members = self.contract_members.items, .contract_predicates = self.contract_predicates.items, .implementations = self.implementations.items, .implementation_members = self.implementation_members.items, .implementation_predicates = self.implementation_predicates.items, .patterns = .{ .store = &self.parameter_patterns }, .values = .{ .bindings = self.bindings.items, .tree = self.tree, .names = self.body_external_names, .annotations = self.bodyAnnotations(), .proof_contracts = self.proof_contracts.items, .capability_contracts = .{ .nodes = self.capability_store.nodes.items, .words = self.capability_store.words.items, .bindings = self.capability_roots.items }, .ready = .{ .context = self, .lookup = struct {
            fn ready(context: *const anyopaque, binding: BindingId) bool {
                const engine: *const Engine = @ptrCast(@alignCast(context));
                return engine.calleeSettled(binding);
            }
        }.ready } } };
    }
    fn reuseBody(self: *Engine, root: ast.Id) T.Error!?T.Id {
        const cache = self.previous_bodies orelse return null;
        if (self.editor_marker != null or self.diagnostics.items.len != 0) return null;
        const C = @import("../reuse/body_check_cache.zig");
        const declaration = self.tree.valueDecl(root);
        const body = cache.find(self.pool.get(declaration.name)) orelse return null;
        if (body.auxiliary) |owner| if (owner.proof_debit) |debit| {
            if (!std.meta.eql(debit.frontier, self.proof_body.frontier(self.proof_contracts.items.len))) return null;
            // Re-enter ordinary checking at a tight budget. Replay must not
            // turn a source proof-limit diagnostic into a late partial error.
            const values = &self.proof_body.values;
            if (debit.visits > values.limits.visits -| values.visits or owner.numeric_body.operands.len > values.limits.terms -| values.terms.items.len or owner.numeric_body.introductions.len > values.limits.terms -| self.proof_body.introductions.items.len or owner.numeric_body.parameters.len > values.limits.terms -| self.proof_body.parameters.items.len or owner.numeric_body.uses.len > values.limits.terms -| self.proof_body.uses.items.len) return null;
        };
        const proof_before = self.proof_visits;
        const span = self.tree.span(root);
        if (span.end > self.body_source.len or !std.mem.eql(u8, body.source, self.body_source[span.start..span.end])) return null;
        const shape = try C.syntax(self.allocator, self.tree, self.pool, root) orelse return null;
        defer self.allocator.free(shape.ids);
        if (!std.mem.eql(u8, &shape.digest, &body.syntax) or shape.ids.len != body.facts.len) return null;
        var recipes: C.RecipeMemo = .{};
        var catalog = self.bodyCatalog();
        catalog.recipes = &recipes;
        var identities: std.AutoHashMapUnmanaged(Identity, Identity) = .empty;
        defer identities.deinit(self.allocator);
        var operations: std.AutoHashMapUnmanaged(Identity, Identity) = .empty;
        defer operations.deinit(self.allocator);
        for (body.nominals) |index| {
            const old = body.owner.nominals[index];
            var identity: Identity = undefined;
            var digest: C.Digest = undefined;
            if (old.kind == .operation) {
                const current = catalog.namedOperation(old.origin, old.name) orelse return null;
                identity = self.effect_templates.items[current].identity;
                digest = C.operationDigest(.{ .store = &self.types }, catalog, current) orelse return null;
            } else if (old.kind == .family) {
                const current = catalog.namedFamily(old.origin, old.name) orelse return null;
                identity = self.effect_families.items[current].identity;
                digest = C.familyDigest(.{ .store = &self.types }, catalog, current) orelse return null;
            } else if (old.kind == .contract) {
                const current = catalog.namedContract(old.origin, old.name) orelse return null;
                identity = current.identity;
                digest = C.contractDigest(catalog, identity) orelse return null;
            } else {
                const current = catalog.namedOrigin(old.origin, old.name) orelse return null;
                identity = self.nominals.items[current].identity;
                digest = C.nominalDigest(.{ .store = &self.types }, catalog, current) orelse return null;
            }
            if (!std.mem.eql(u8, &digest, &old.digest)) return null;
            if (old.kind == .operation) {
                try operations.put(self.allocator, .{ .unit = index + 1, .decl = 0 }, identity);
            } else try identities.put(self.allocator, .{ .unit = index + 1, .decl = 0 }, identity);
        }
        if (body.auxiliary) |owner| for (owner.tables.operation_uses) |use| {
            if (use.instance.unit != 0 or use.instance.decl != 0) continue;
            var source = shape.ids[use.node - 1];
            var remaining: usize = 128;
            while (remaining != 0) : (remaining -= 1) {
                const syntax = self.tree.node(source);
                if (syntax.tag != .apply and syntax.tag != .group) break;
                source = syntax.a;
            }
            if (remaining == 0 or self.tree.node(source).tag != .name) return null;
            const template = try self.operationTemplate(self.tree.node(source).a) orelse return null;
            const expected = operations.get(.{ .unit = use.template, .decl = 0 }) orelse return null;
            if (!std.meta.eql(self.effect_templates.items[template].identity, expected)) return null;
        };
        for (body.type_reads) |read| {
            const id = shape.ids[read.position];
            var digest: C.Digest = undefined;
            if (read.effect) {
                digest = C.effectAnnotationDigest(.{ .store = &self.types }, catalog, self.tree, id) orelse return null;
            } else digest = C.annotationDigest(.{ .store = &self.types }, catalog, self.pool.get(self.tree.node(id).a)) orelse return null;
            if (!std.mem.eql(u8, &digest, &read.digest)) return null;
        }
        const mapped = try self.allocator.alloc(BindingId, body.bindings.len);
        defer self.allocator.free(mapped);
        @memset(mapped, 0);
        for (body.bindings, mapped) |old, *target| {
            if (old.kind == .parameter or old.kind == .local) continue;
            const name = self.pool.lookup(old.name) orelse return null;
            const binding = try self.catalogBinding(name) orelse return null;
            recipes.len = 0;
            catalog = self.bodyCatalog();
            catalog.recipes = &recipes;
            const current = self.bindings.items[binding];
            if (current.operation_ref != 0) return null;
            if (current.kind != old.kind or current.private != old.private or current.named_function != old.named_function or current.capability_flow != old.capability_flow or !std.meta.eql(current.capability_parameters, old.capability_parameters) or (current.external == null) != (old.external == null)) return null;
            if (current.kind == .global) {
                const state = self.global_states.get(binding) orelse return null;
                if (state.state != .complete or state.on_stack or C.runtimeBinding(self.tree, current) != old.runtime) return null;
            }
            const digest = C.readDigest(.{ .store = &self.types }, current, self.obligations.items, self.body_external_names, catalog) orelse return null;
            if (!std.mem.eql(u8, &digest, &old.interface)) return null;
            target.* = binding;
        }
        for (shape.ids, body.facts) |id, fact| if (self.tree.node(id).tag == .binary) {
            if (fact.binding == 0) return null;
            const old = body.bindings[fact.binding - 1];
            if (old.kind != .global and old.kind != .external) return null;
            const target = try discoveryReference(self, .operator, self.tree.node(id).a, 0, &.{}) orelse return null;
            if (target != mapped[fact.binding - 1]) return null;
        };
        recipes.len = 0;
        catalog = self.bodyCatalog();
        catalog.recipes = &recipes;
        if (body.selection_digest) |old_digest| {
            for (self.associated.items) |entry| {
                for (body.members) |member| if (std.mem.eql(u8, member, self.pool.get(entry.member)) and !self.calleeSettled(entry.binding)) return null;
            }
            var digest = C.associatedDigest(.{ .store = &self.types }, catalog, self.tree, self.associated.items, self.bindings.items, self.obligations.items, self.body_external_names, body.members) orelse return null;
            if (body.implementation_selection) digest = C.implementationDigest(.{ .store = &self.types }, catalog, digest) orelse return null;
            if (!std.mem.eql(u8, &digest, &old_digest)) return null;
        }
        const constructors = try self.allocator.alloc(u32, body.constructors.len);
        defer self.allocator.free(constructors);
        for (body.constructors, constructors) |old, *mapped_constructor| {
            const id = shape.ids[old.position];
            const current_id = self.catalogs.constructor_names.get(self.catalogKey(self.tree.node(id).a)) orelse return null;
            const current = self.constructors.items[current_id];
            const nominal = identities.get(old.nominal) orelse return null;
            if (self.nominals.items[current.nominal].identity.unit != nominal.unit or self.nominals.items[current.nominal].identity.decl != nominal.decl or current.tag != old.tag) return null;
            mapped_constructor.* = current_id;
        }
        const fields = try self.allocator.alloc(symbols.Symbol, body.owner.field_names.len);
        defer self.allocator.free(fields);
        for (body.owner.field_names, fields) |name, *field| field.* = self.pool.lookup(name) orelse return null;
        var next_local: usize = self.bindings.items.len;
        for (body.bindings, mapped) |old, *target| if (old.kind == .parameter or old.kind == .local) {
            target.* = std.math.cast(BindingId, next_local) orelse return error.TypeLimit;
            next_local += 1;
        };
        const qualification_spans = try self.allocator.alloc(ast.Span, body.owner.qualifications.len);
        defer self.allocator.free(qualification_spans);
        for (body.owner.qualifications, qualification_spans) |origin, *current| current.* = C.currentQualification(self.tree, self.pool, body.owner.field_names, origin) orelse return null;
        var private_namespace: u32 = 0;
        for (body.owner.bodies, 0..) |*candidate, index| if (candidate == body) {
            private_namespace = @intCast(index + 1);
            break;
        };
        var copier: SchemeCopier = .{ .private_qualifications = qualification_spans, .private_namespace = private_namespace, .private_unit = self.unit, .private_nodes = shape.ids, .private_bindings = mapped, .private_tree = self.tree, .field_mapping = fields, .allocator = self.allocator, .source = .{ .frozen = &body.owner.graph }, .destination = &self.types, .fresh_rows = true, .fresh_variables = true, .nominal_mapping = &identities, .operation_mapping = &operations };
        defer copier.deinit();
        // Ordinary constructor patterns share the current catalog payload.
        // Replaying a frozen copy would introduce an extra nominal/record root
        // and change Core's ordered type graph on the next exact revision.
        for (body.constructors, constructors) |old, current| {
            const syntax = self.tree.node(shape.ids[old.position]);
            if (syntax.tag != .pattern_constructor) continue;
            const constructor = self.constructors.items[current];
            if (constructor.scheme.variables.len != 0 or constructor.scheme.row_variables.len != 0) continue;
            if (syntax.b != 0) {
                const payload_position = std.mem.findScalar(ast.Id, shape.ids, syntax.b) orelse return null;
                const payload_type = body.facts[payload_position].ty;
                var payload = constructor.payload;
                const payload_shape = self.types.node(self.types.head(payload, 0));
                if (!self.nominals.items[constructor.nominal].is_opaque and payload_shape.tag == .record and self.tree.node(syntax.b).tag != .pattern_record) payload = try self.canonicalRecordType(payload_shape);
                if (payload_type != 0) try copier.mapping.put(self.allocator, payload_type, payload);
            }
        }
        const field_plans = try self.allocator.alloc(Projection, body.fields.len);
        defer self.allocator.free(field_plans);
        for (body.fields, field_plans) |field, *plan| {
            const syntax = self.tree.node(shape.ids[field.position]);
            const receiver_position = std.mem.findScalar(ast.Id, shape.ids, syntax.a) orelse return null;
            const receiver = try copier.copy(body.facts[receiver_position].ty, 0);
            var nominal: Identity = .{ .unit = 0, .decl = 0 };
            if (field.nominal.unit != 0) nominal = identities.get(field.nominal) orelse return null;
            plan.* = try self.bodyProjectionPlan(receiver, nominal, syntax.b, body.field_tags[field.tags.start..][0..field.tags.len]) orelse return null;
        }
        const access_plans = try self.allocator.alloc(Projection, body.accesses.len);
        defer self.allocator.free(access_plans);
        const access_types = try self.allocator.alloc(T.Id, body.accesses.len);
        defer self.allocator.free(access_types);
        for (body.accesses, access_plans, access_types) |access, *plan, *ty| {
            ty.* = try copier.copy(access.ty, 0);
            var nominal: Identity = .{ .unit = 0, .decl = 0 };
            if (access.nominal.unit != 0) nominal = identities.get(access.nominal) orelse return null;
            plan.* = try self.bodyProjectionPlan(ty.*, nominal, fields[access.field], body.field_tags[access.tags.start..][0..access.tags.len]) orelse return null;
        }
        for (body.bindings, mapped) |old, *target| if (old.kind == .parameter or old.kind == .local) {
            const ty = try copier.copy(old.ty, 0);
            const name = self.pool.lookup(old.name) orelse 0;
            var principal: T.Scheme = .{};
            if (old.scheme) principal.root = ty;
            const current = try self.addBinding(.{ .name = name, .kind = old.kind, .ty = ty, .scheme = principal, .declaration = shape.ids[old.declaration], .owner = shape.ids[old.owner], .named_function = old.named_function, .private = old.private, .capability_flow = old.capability_flow, .capability_parameters = old.capability_parameters });
            std.debug.assert(target.* == current);
        };
        for (body.local_schemes) |owned_scheme| {
            const frozen = owned_scheme.principal;
            const variables = copier.source.list(frozen.variables);
            const mapped_variables = try self.allocator.alloc(T.Id, variables.len);
            defer self.allocator.free(mapped_variables);
            for (variables, mapped_variables) |variable, *mapped_variable| mapped_variable.* = try copier.copy(variable, 0);
            const requirement_start: u32 = @intCast(self.obligations.items.len);
            for (body.predicates[frozen.obligations.start..][0..frozen.obligations.len]) |predicate| {
                const value = try self.replayedBodyPredicate(&copier, shape.ids, mapped, predicate, span);
                try self.obligations.append(self.allocator, value);
            }
            self.bindings.items[mapped[owned_scheme.binding - 1]].scheme = .{
                .root = try copier.copy(frozen.root, 0),
                .variables = try self.types.saveList(mapped_variables),
                .row_variables = try copier.relocatedRows(copier.source.list(frozen.row_variables)),
                .closed_rows = try copier.relocatedRows(copier.source.list(frozen.closed_rows)),
                .generative = try copier.copyGenerative(frozen.generative),
                .obligations = .{ .start = requirement_start, .len = frozen.obligations.len },
            };
        }
        for (body.bindings, mapped) |old, target| {
            if (old.predecessor != 0) self.bindings.items[target].predecessor = mapped[old.predecessor - 1];
        }
        for (body.merges) |merge| try self.merges.append(self.allocator, .{ .node = shape.ids[merge.position], .result = mapped[merge.result - 1], .then_binding = mapped[merge.yes - 1], .else_binding = mapped[merge.no - 1] });
        if (body.loops) |loops| {
            var carry_index: usize = 0;
            while (carry_index < loops.carries.len) {
                const position = loops.carries[carry_index].position;
                const start = self.loop_carries.items.len;
                while (carry_index < loops.carries.len and loops.carries[carry_index].position == position) : (carry_index += 1) {
                    const carry = loops.carries[carry_index];
                    try self.loop_carries.append(self.allocator, .{ .node = shape.ids[position], .incoming = mapped[carry.incoming - 1], .iteration = mapped[carry.iteration - 1], .backedge = mapped[carry.backedge - 1], .outgoing = mapped[carry.outgoing - 1] });
                }
                if (start > std.math.maxInt(u32)) return error.TypeLimit;
                self.loop_ranges[shape.ids[position]] = .{ .start = @intCast(start), .len = @intCast(self.loop_carries.items.len - start) };
            }
            for (loops.exits) |exit| {
                var current: std.ArrayList(BindingId) = .empty;
                defer current.deinit(self.allocator);
                for (loops.bindings[exit.bindings.start..][0..exit.bindings.len]) |binding| try current.append(self.allocator, mapped[binding - 1]);
                try self.loop_exits.append(self.allocator, .{ .node = shape.ids[exit.position], .loop = shape.ids[exit.loop], .bindings = try self.types.saveList(current.items) });
            }
        }
        for (shape.ids) |id| if (self.tree.node(id).tag == .case_expr) try self.cases.append(self.allocator, id);
        for (shape.ids, body.facts) |id, fact| {
            self.expr_types[id] = try copier.copy(fact.ty, 0);
            if (fact.binding != 0) self.resolved[id] = mapped[fact.binding - 1];
        }
        for (body.constructors, constructors) |old, current| self.constructor_resolved[shape.ids[old.position]] = current;
        for (body.fields, field_plans) |field, plan| {
            const catalog_id: u32 = @intCast(self.projection_catalog.items.len);
            try self.projection_catalog.append(self.allocator, plan);
            self.projection_resolved[shape.ids[field.position]] = catalog_id;
        }
        var access_index: usize = 0;
        while (access_index < body.accesses.len) {
            const position = body.accesses[access_index].position;
            const start = access_index;
            var path: std.ArrayList(u32) = .empty;
            defer path.deinit(self.allocator);
            var types: std.ArrayList(T.Id) = .empty;
            defer types.deinit(self.allocator);
            while (access_index < body.accesses.len and body.accesses[access_index].position == position) : (access_index += 1) {
                try path.append(self.allocator, @intCast(self.projection_catalog.items.len));
                try self.projection_catalog.append(self.allocator, access_plans[access_index]);
            }
            const id = shape.ids[position];
            try types.appendSlice(self.allocator, access_types[start..access_index]);
            try types.append(self.allocator, self.expr_types[id]);
            self.access_paths[id] = try self.types.saveList(path.items);
            self.access_types[id] = try self.types.saveList(types.items);
        }
        for (body.projections) |projection| {
            const id = shape.ids[projection.position];
            var index = projection.index;
            if (projection.owner != 0) {
                const record = self.types.node(self.types.head(self.expr_types[shape.ids[projection.owner - 1]], 0));
                if (record.tag != .record) return error.TypeLimit;
                var mapped_index: ?u32 = null;
                for (0..record.b) |field| if (self.types.recordField(record, field).name == self.tree.node(id).a) {
                    mapped_index = @intCast(field);
                    break;
                };
                index = mapped_index orelse return error.TypeLimit;
            }
            self.projections[id] = index;
        }
        for (body.rebindings) |update| {
            const id = shape.ids[update.position];
            var nodes: std.ArrayList(ast.Id) = .empty;
            defer nodes.deinit(self.allocator);
            var current = self.tree.node(id).a;
            while (self.tree.node(current).tag == .field_access or self.tree.node(current).tag == .index_access) {
                if (nodes.items.len == 128) return error.TypeLimit;
                try nodes.append(self.allocator, current);
                current = self.tree.node(current).a;
            }
            std.mem.reverse(ast.Id, nodes.items);
            var path: std.ArrayList(u32) = .empty;
            defer path.deinit(self.allocator);
            var endpoints: std.ArrayList(T.Id) = .empty;
            defer endpoints.deinit(self.allocator);
            try endpoints.append(self.allocator, self.expr_types[current]);
            for (nodes.items) |selector| {
                try path.append(self.allocator, self.projection_resolved[selector]);
                try endpoints.append(self.allocator, self.expr_types[selector]);
            }
            self.rebindings[id] = .{ .root = mapped[update.root - 1], .self_binding = mapped[update.self_binding - 1], .path = try self.types.saveList(path.items) };
            self.access_types[id] = try self.types.saveList(endpoints.items);
            self.access_nodes[id] = try self.types.saveList(nodes.items);
        }
        for (body.signatures) |signature| {
            const id = shape.ids[signature.position];
            const ty = try copier.copy(signature.ty, 0);
            switch (signature.kind) {
                .dispatch => self.dispatch_signatures[id] = ty,
                .demand => {
                    self.demand_calls[id] = true;
                    self.demand_once[id] = signature.once;
                    self.demand_types[id] = ty;
                },
                .demand_left => {
                    self.demand_binary_left[id] = true;
                    self.demand_binary_left_types[id] = ty;
                },
            }
        }
        if (body.auxiliary) |owner| try self.replayAuxiliary(owner, shape.ids, mapped, &copier, fields, &identities, &operations);
        if (self.tree.has_numeric_proofs or self.types.has_proof_kinds) for (shape.ids) |id| {
            if (self.tree.node(id).tag != .let_stmt or self.resolved[id] == 0) continue;
            const written = self.tree.binding(id);
            if (self.tree.node(written.pattern).tag != .pattern_name) continue;
            self.proof_body.alias(self.allocator, self.resolved[id], written.value) catch |err| {
                _ = try self.proofHeaderFailure(err, id);
                return error.TypeLimit;
            };
        };
        // References to qualified schemes still instantiate their current
        // predicates. The candidate receipt first proves that copying their
        // already solved caller types cannot constrain a newly selected effect.
        for (shape.ids, body.facts, 0..) |id, fact, at| if (fact.binding != 0 and (self.tree.node(id).tag == .name or self.tree.node(id).tag == .binary)) {
            const target = mapped[fact.binding - 1];
            if (self.bindings.items[target].scheme.obligations.len != 0) {
                // Local generalization already transferred these requirements
                // out of the enclosing pending graph into its owned principal.
                var owned_reference = false;
                for (body.predicates) |predicate| if (predicate.local and predicate.position == at) {
                    owned_reference = true;
                    break;
                };
                if (owned_reference) continue;
                var reference_type = self.expr_types[id];
                if (self.access_paths[id].len != 0) reference_type = self.types.list(self.access_types[id])[0];
                try self.constrain(try self.instantiate(target, id), reference_type, id);
            }
        };
        try self.recordClosedRows(self.current, try copier.relocatedRows(body.closed_rows[body.body_closed_rows.start..][0..body.body_closed_rows.len]));
        for (shape.ids, body.facts) |id, fact| if (fact.closed_rows.len != 0) {
            self.lambda_closed_rows[id] = try copier.relocatedRows(body.closed_rows[fact.closed_rows.start..][0..fact.closed_rows.len]);
        };
        for (body.predicates) |predicate| {
            if (predicate.local) continue;
            const value = try self.replayedBodyPredicate(&copier, shape.ids, mapped, predicate, span);
            try self.appendPending(.{ .owner = self.current, .direct = true, .value = value });
        }
        var result_node = declaration.body;
        if (declaration.attributes.len != 0) result_node = self.tree.list(declaration.attributes)[0];
        const ty = self.expr_types[result_node];
        if (ty == 0) return null;
        if (body.auxiliary) |owner| if (owner.proof_debit) |debit| {
            const consumed = self.proof_visits - proof_before;
            if (consumed < debit.visits) self.proof_body.values.charge(debit.visits - consumed) catch |err| {
                _ = try self.proofHeaderFailure(err, root);
                return error.TypeLimit;
            };
            var current = debit;
            current.binding = self.current;
            current.output = self.proof_body.frontier(self.proof_contracts.items.len);
            try self.proof_body.debits.append(self.allocator, current);
        };
        if (self.retained_bodies) |retained| try retained.retain(self.allocator, body);
        self.body_elaborations -= 1;
        return ty;
    }
    fn replayAuxiliary(self: *Engine, owner: *const @import("../reuse/body_auxiliary.zig").Owner, ids: []const ast.Id, bindings: []const BindingId, copier: *SchemeCopier, fields: []const symbols.Symbol, identities: *const std.AutoHashMapUnmanaged(Identity, Identity), operations: *const std.AutoHashMapUnmanaged(Identity, Identity)) T.Error!void {
        const X = @import("../reuse/body_auxiliary.zig");
        var mapper: AuxiliaryReplay = .{ .engine = self, .owner = owner, .ids = ids, .bindings = bindings, .copier = copier, .fields = fields, .identities = identities, .operations = operations, .request_arms = @intCast(self.request_arms.items.len), .resolver_ops = @intCast(self.resolver_ops.items.len), .resolver_completions = @intCast(self.resolver_completions.items.len), .operation_uses = @intCast(self.operation_uses.items.len) };
        var offsets: [X.indexed_tables.len]u32 = undefined;
        inline for (X.indexed_tables, 0..) |table, index| offsets[index] = @intCast(@field(self, table).items.len);
        inline for (X.fields) |field| {
            for (@field(owner.tables, field)) |entry| try @field(self, field).append(self.allocator, try X.mapRecord(entry, &mapper));
        }
        for (owner.indices) |entry| {
            inline for (X.indexed_fields, 0..) |field, index| {
                if (entry.table == index) @field(self, field)[ids[entry.node - 1]] = offsets[index] + entry.value;
            }
        }
        for (owner.operation_bindings) |entry| self.bindings.items[bindings[entry.binding - 1]].operation_ref = mapper.operation_uses + entry.operation;
        for (owner.iterators) |iterator| self.iterator_bodies[ids[iterator.node - 1]] = ids[iterator.body - 1];
        const term_mapping = try self.allocator.alloc(u32, owner.numeric_body.operands.len);
        defer self.allocator.free(term_mapping);
        for (owner.numeric_body.operands, term_mapping, 0..) |operand, *destination, index| {
            var value = operand;
            switch (value.tag) {
                .version => value.a = switch (value.b) {
                    1 => bindings[value.a - 1],
                    2 => ids[value.a - 1],
                    else => return error.TypeLimit,
                },
                .length, .complement => {
                    if (value.a == 0 or value.a > index) return error.TypeLimit;
                    value.a = term_mapping[value.a - 1];
                },
                .literal => {},
                .formal, .capture => return error.TypeLimit,
            }
            destination.* = self.proof_body.values.intern(self.allocator, value) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.TypeLimit,
            };
        }
        for (owner.numeric_body.introductions) |entry| {
            var value = try X.mapRecord(entry, &mapper);
            value.proposition = try replayProofProposition(entry.proposition, term_mapping);
            self.proof_body.introduce(self.allocator, value) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.TypeLimit,
            };
        }
        for (owner.numeric_body.parameters) |entry| {
            var value = try X.mapRecord(entry, &mapper);
            value.contract = self.current;
            value.proposition = try replayProofProposition(entry.proposition, term_mapping);
            self.proof_body.parameter(self.allocator, value) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.TypeLimit,
            };
        }
        for (owner.numeric_body.uses) |entry| {
            var value = try X.mapRecord(entry, &mapper);
            value.proposition = try replayProofProposition(entry.proposition, term_mapping);
            self.proof_body.use(self.allocator, value) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.TypeLimit,
            };
        }
        for (self.proof_contracts.items) |*contract| if (contract.binding == self.current) {
            if (contract.parameters.len != owner.proof_parameters.len) return error.TypeLimit;
            for (contract.parameters, owner.proof_parameters) |*parameter, old| parameter.* = bindings[old - 1];
        };
    }
    fn replayedBodyPredicate(self: *Engine, copier: *SchemeCopier, ids: []const ast.Id, bindings: []const BindingId, predicate: @import("../reuse/body_check_cache.zig").Predicate, root: ast.Span) T.Error!T.Obligation {
        var value = predicate.value;
        value.ty = try copier.copy(value.ty, 0);
        value.other = try copier.copy(value.other, 0);
        value.result = try copier.copy(value.result, 0);
        value.signature = try copier.copy(value.signature, 0);
        value.source = ids[predicate.position];
        value.name = 0;
        if (predicate.name.len != 0) value.name = self.pool.lookup(predicate.name) orelse return error.TypeLimit;
        if (value.kind == .contract) value.identity = copier.nominal_mapping.?.get(value.identity) orelse return error.TypeLimit;
        if (value.kind == .effect_operation) value.identity = copier.operation_mapping.?.get(value.identity) orelse return error.TypeLimit;
        if (value.kind == .callee_use) {
            if (value.identity.unit != 0 or value.identity.decl == 0 or value.identity.decl > bindings.len) return error.TypeLimit;
            value.identity = .{ .unit = self.unit, .decl = bindings[value.identity.decl - 1] };
        }
        if (predicate.local and value.explicit and value.qualification_span != null) {
            const origin = value.qualification_span orelse return error.TypeLimit;
            if (origin.start > origin.end or origin.end > root.end - root.start) return error.TypeLimit;
            value.qualification_span = .{ .start = root.start + origin.start, .end = root.start + origin.end };
            value.qualification_unit = self.unit;
        }
        return value;
    }
    fn bodyProjectionPlan(self: *Engine, receiver: T.Id, nominal: Identity, field: symbols.Symbol, tags: []const u32) T.Error!?Projection {
        if (tags.len == 0) {
            if (receiver == 0) return null;
            if (nominal.unit != 0 or nominal.decl != 0) {
                const head = self.types.node(self.types.head(receiver, 0));
                if (head.tag != .nominal or head.a != nominal.unit or head.b != nominal.decl) return null;
            }
            return .{ .nominal = nominal, .field = field, .variants = .{} };
        }
        var variants: std.ArrayList(u32) = .empty;
        defer variants.deinit(self.allocator);
        for (tags) |tag| {
            var record_type = receiver;
            if (nominal.unit != 0) {
                var payload: ?T.Id = null;
                for (self.constructors.items) |constructor| if (constructor.tag == tag and std.meta.eql(self.nominals.items[constructor.nominal].identity, nominal)) {
                    payload = constructor.payload;
                    break;
                };
                record_type = payload orelse return null;
            }
            const record = self.types.node(self.types.head(record_type, 0));
            if (record.tag != .record) return null;
            var index: ?u32 = null;
            for (0..record.b) |slot| if (self.types.recordField(record, slot).name == field) {
                index = @intCast(slot);
                break;
            };
            try variants.appendSlice(self.allocator, &.{ tag, index orelse return null });
        }
        return .{ .nominal = nominal, .field = field, .variants = try self.types.saveList(variants.items) };
    }
    fn discoveryShadowed(self: *const Engine, locals: []const symbols.Symbol, name: symbols.Symbol) bool {
        if (std.mem.findScalar(symbols.Symbol, locals, name) != null) return true;
        const text = self.pool.get(name);
        if (std.mem.findScalar(u8, text, '.')) |dot| if (self.pool.lookup(text[0..dot])) |root| return std.mem.findScalar(symbols.Symbol, locals, root) != null;
        return false;
    }
    fn discoveryReference(context: *anyopaque, kind: global_references.Kind, name: symbols.Symbol, member: symbols.Symbol, locals: []const symbols.Symbol) global_references.Error!?u32 {
        const self: *Engine = @ptrCast(@alignCast(context));
        var selected: ?BindingId = null;
        switch (kind) {
            .name => if (!self.discoveryShadowed(locals, name)) {
                selected = try self.catalogBinding(name);
                if (selected == null) {
                    const text = self.pool.get(name);
                    if (std.mem.findScalar(u8, text, '.')) |dot| {
                        if (self.pool.lookup(text[0..dot])) |root| selected = self.catalogs.globals.get(root);
                    }
                }
            },
            .qualified => if (!self.discoveryShadowed(locals, name)) {
                selected = self.catalogs.qualified.get(.{ .namespace = name, .member = member });
            },
            .operator => {
                const text = self.pool.get(name);
                const declared = self.catalogs.overrides.get(name);
                const named = if (declared) |override| override.named else text.len != 0 and (std.ascii.isAlphabetic(text[0]) or text[0] == '_');
                const target = if (declared) |override| override.target else name;
                if ((!named or !self.discoveryShadowed(locals, target)) and (declared != null or named)) {
                    if (declared) |override| {
                        if (override.external) |external| selected = self.catalogs.external_targets.get(external) else selected = try self.catalogBinding(target);
                    } else selected = try self.catalogBinding(target);
                }
            },
        }
        const binding = selected orelse return null;
        if (self.bindings.items[binding].kind != .global) return null;
        return binding;
    }
    fn flushGlobalDiagnostics(self: *Engine, binding: BindingId) Allocator.Error!void {
        const diagnostics = self.staged_global_diagnostics.get(binding) orelse return;
        try self.diagnostics.appendSlice(self.allocator, diagnostics);
        _ = self.staged_global_diagnostics.remove(binding);
        self.allocator.free(diagnostics);
    }
    const ScheduledGlobal = struct {
        frame: GlobalFrame,
        references: []global_references.Reference,
        next: usize = 0,
        value: ?T.Id = null,
        finished: bool = false,
        before: ?Global = null,
        owner: BindingId = 0,
        diagnostic_start: usize,
        diagnostic_at: ?usize = null,
    };
    fn scheduledFrame(self: *Engine, binding: BindingId, before: ?Global, owner: BindingId, diagnostic_at: ?usize) T.Error!ScheduledGlobal {
        const references = global_references.discover(self.allocator, self.tree, self.bindings.items[binding].declaration, .{ .context = self, .self_name = self.self_name, .resolve = discoveryReference }, &self.inference_transitions, self.inference_limit) catch |err| {
            if (err == error.TypeLimit and self.inference_transitions >= self.inference_limit) self.exhaustBudget();
            return err;
        };
        errdefer self.allocator.free(references);
        const diagnostic_start = self.diagnostics.items.len;
        const frame = try self.beginGlobal(binding);
        return .{ .frame = frame, .references = references, .before = before, .owner = owner, .diagnostic_start = diagnostic_start, .diagnostic_at = diagnostic_at };
    }
    fn inferScheduledGlobal(self: *Engine, initial: BindingId) T.Error!void {
        std.debug.assert(!self.global_driver);
        self.global_driver = true;
        defer self.global_driver = false;
        var frames: std.ArrayList(ScheduledGlobal) = .empty;
        defer frames.deinit(self.allocator);
        defer while (frames.pop()) |item| {
            var unfinished = item;
            self.allocator.free(unfinished.references);
            unfinished.frame.context.restore(self);
        };
        try frames.ensureUnusedCapacity(self.allocator, 1);
        frames.appendAssumeCapacity(try self.scheduledFrame(initial, null, 0, null));
        while (frames.items.len != 0) {
            try self.inferenceTransition();
            const index = frames.items.len - 1;
            if (frames.items[index].next < frames.items[index].references.len) {
                const reference = frames.items[index].references[frames.items[index].next];
                frames.items[index].next += 1;
                const before = self.global_states.get(reference.binding).?;
                const owner = frames.items[index].frame.binding;
                if (before.state == .pending) {
                    try frames.ensureUnusedCapacity(self.allocator, 1);
                    frames.appendAssumeCapacity(try self.scheduledFrame(reference.binding, before, owner, null));
                } else try self.finishPreparedGlobalOwner(reference.binding, before, owner);
                continue;
            }
            if (frames.items[index].value == null) {
                const declaration = self.tree.valueDecl(frames.items[index].frame.id);
                if (try self.reuseBody(frames.items[index].frame.id)) |value| {
                    frames.items[index].value = value;
                } else {
                    frames.items[index].value = try self.inferDeclarationBody(declaration);
                }
            }
            if (self.selected_globals.items.len != 0) {
                const selected = self.selected_globals.orderedRemove(0);
                const before = self.global_states.get(selected.binding).?;
                if (before.state == .pending) {
                    try frames.ensureUnusedCapacity(self.allocator, 1);
                    frames.appendAssumeCapacity(try self.scheduledFrame(selected.binding, before, selected.owner, selected.diagnostic_at));
                } else try self.finishPreparedGlobalOwner(selected.binding, before, selected.owner);
                continue;
            }
            if (!frames.items[index].finished) {
                try self.finishGlobal(&frames.items[index].frame, frames.items[index].value.?);
                frames.items[index].finished = true;
                if (self.selected_globals.items.len != 0) continue;
            } else {
                const binding = frames.items[index].frame.binding;
                const state = self.global_states.get(binding).?;
                if (state.on_stack and state.low == state.index) try self.finishComponent(binding);
                if (self.selected_globals.items.len != 0) continue;
            }
            var done = frames.pop().?;
            defer self.allocator.free(done.references);
            defer done.frame.context.restore(self);
            if (done.before) |before| {
                try self.finishPreparedGlobalOwner(done.frame.binding, before, done.owner);
                const diagnostics = try self.allocator.dupe(Diagnostic, self.diagnostics.items[done.diagnostic_start..]);
                self.diagnostics.shrinkRetainingCapacity(done.diagnostic_start);
                var retained = false;
                defer if (!retained) {
                    deinitDiagnosticPayloads(self.allocator, diagnostics);
                    self.allocator.free(diagnostics);
                };
                if (done.diagnostic_at) |position| {
                    const at = @min(position, self.diagnostics.items.len);
                    try self.diagnostics.insertSlice(self.allocator, at, diagnostics);
                    for (self.selected_globals.items) |*pending| if (pending.diagnostic_at >= at) {
                        pending.diagnostic_at += diagnostics.len;
                    };
                    self.allocator.free(diagnostics);
                    retained = true;
                } else {
                    std.debug.assert(!self.staged_global_diagnostics.contains(done.frame.binding));
                    try self.staged_global_diagnostics.put(self.allocator, done.frame.binding, diagnostics);
                    retained = true;
                }
            }
        }
    }
    fn prepareSelectedGlobal(self: *Engine, binding: BindingId) T.Error!bool {
        if (self.bindings.items[binding].kind != .external and self.global_driver and self.global_states.get(binding).?.state == .pending) {
            const owner = self.dependency_owner orelse self.current;
            for (self.selected_globals.items) |pending| if (pending.binding == binding and pending.owner == owner) return false;
            try self.selected_globals.append(self.allocator, .{ .binding = binding, .owner = owner, .diagnostic_at = self.diagnostics.items.len });
            return false;
        }
        try self.prepareGlobal(binding);
        return true;
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
                    break :blk self.catalogs.globals.get(node.a) orelse break;
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
        try self.inferenceTransition();
        const owner = self.dependency_owner orelse self.current;
        const saved_owner = self.dependency_owner;
        self.dependency_owner = null;
        defer self.dependency_owner = saved_owner;
        const before = self.global_states.get(binding).?;
        if (before.state == .pending) try self.inferGlobal(binding);
        try self.flushGlobalDiagnostics(binding);
        try self.finishPreparedGlobalOwner(binding, before, owner);
    }
    fn finishPreparedGlobal(self: *Engine, binding: BindingId, before: Global) T.Error!void {
        return self.finishPreparedGlobalOwner(binding, before, self.current);
    }
    fn finishPreparedGlobalOwner(self: *Engine, binding: BindingId, before: Global, owner: BindingId) T.Error!void {
        const after = self.global_states.get(binding).?;
        if (owner != 0 and after.on_stack) {
            var current = self.global_states.get(owner).?;
            current.low = @min(current.low, if (before.state == .pending) after.low else after.index);
            self.global_states.getPtr(owner).?.* = current;
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
        if (self.staging_depth != 0 and !self.bindings.items[binding].named_function and self.types.node(self.types.head(self.bindings.items[binding].ty, 0)).tag != .function) try self.diagnostic(.stage_unavailable, id);
        if (self.bindings.items[binding].kind == .global and self.bindings.items[binding].scheme.root == 0) try self.qualification_uses.append(self.allocator, .{ .scope = self.qualification_scope, .owner = self.current, .target = binding, .source = id });
        try self.recursiveDemandShape(binding, id);
        self.resolved[id] = binding;
        return self.instantiate(binding, id);
    }
    /// An active recursive declaration has no scheme yet. Its lambda header
    /// still determines argument evaluation mode; expose only that monomorphic
    /// shape before a recursive application can assume its arguments are eager.
    fn recursiveDemandShape(self: *Engine, binding: BindingId, id: ast.Id) T.Error!void {
        const item = self.bindings.items[binding];
        if (item.kind != .global or item.scheme.root != 0) return;
        const state = self.global_states.get(binding) orelse return;
        if (!state.on_stack or self.types.node(try self.types.resolve(item.ty, 0)).tag != .variable) return;
        var cursor = self.tree.valueDecl(item.declaration).body;
        var demanded = false;
        while (true) {
            const node = self.tree.node(cursor);
            if (node.tag == .group) {
                cursor = node.a;
                continue;
            }
            if (node.tag != .lambda) break;
            const parameter = self.tree.parameter(node.a);
            demanded = demanded or parameter.demanded;
            cursor = node.b;
        }
        if (!demanded) return;
        var parameters: std.ArrayList(bool) = .empty;
        defer parameters.deinit(self.allocator);
        cursor = self.tree.valueDecl(item.declaration).body;
        while (true) {
            const node = self.tree.node(cursor);
            if (node.tag == .group) {
                cursor = node.a;
                continue;
            }
            if (node.tag != .lambda) break;
            try parameters.append(self.allocator, self.tree.parameter(node.a).demanded);
            cursor = node.b;
        }
        var shape = try self.types.fresh();
        var index = parameters.items.len;
        while (index > 0) {
            index -= 1;
            var input = try self.types.fresh();
            if (parameters.items[index]) input = try self.types.demandWithEffects(input, try self.types.freshEffects());
            shape = try self.types.functionWithEffects(input, shape, try self.types.freshEffects());
        }
        try self.constrain(item.ty, shape, id);
    }
    fn intrinsicArity(name: []const u8) ?usize {
        if (@import("task_types.zig").lookup(name)) |operation| return @import("task_types.zig").arity(operation);
        if (staging.lookup(name)) |op| return staging.arity(op);
        if (proof_terms.constructor(name) != null) return 2;
        if (@import("../backend/simd_intrinsics.zig").lookup(name)) |op| return op.arity;
        if (std.mem.eql(u8, name, "@hole")) return 0;
        if (std.mem.eql(u8, name, "@resource.scope")) return 3;
        if (std.mem.eql(u8, name, "@resource.acquire")) return 2;
        if (std.mem.eql(u8, name, "@resource.release")) return 1;
        if (std.mem.eql(u8, name, "@usage.share") or std.mem.eql(u8, name, "@usage.read") or std.mem.eql(u8, name, "@usage.length")) return 1;
        if (std.mem.eql(u8, name, "@usage.borrow") or std.mem.eql(u8, name, "@usage.borrow_mut")) return 2;
        if (std.mem.eql(u8, name, "@record.merge")) return 2;
        if (@import("../backend/collection_ops.zig").lookup(name)) |op| return op.arity;
        if (std.mem.eql(u8, name, "@state.get") or std.mem.eql(u8, name, "@state.set")) return 1;
        if (std.mem.eql(u8, name, "@effect.of") or std.mem.eql(u8, name, "@effect.descriptor") or std.mem.eql(u8, name, "@effect.count")) return 1;
        if (std.mem.eql(u8, name, "@effect.has") or std.mem.eql(u8, name, "@effect.same")) return 2;
        if (std.mem.eql(u8, name, "@state.run")) return 2;
        if (std.mem.eql(u8, name, "@state.reader") or std.mem.eql(u8, name, "@state.writer")) return 3;
        if (std.mem.eql(u8, name, "@effect.scope")) return 1;
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
        if (self.editorAt(id)) return self.captureEditor(id, 0, 0);
        if (@import("../backend/simd_intrinsics.zig").lookup(text)) |op| {
            const element = if (op.floating) T.f32_type else T.u32_type;
            const vector = try self.types.product(&.{ element, element, element, element });
            const lanes = try self.types.product(&.{ T.u32_type, T.u32_type, T.u32_type, T.u32_type });
            const result_element = if (op.resultLane() == .f32) T.f32_type else T.u32_type;
            const output = try self.types.product(&.{ result_element, result_element, result_element, result_element });
            const pair = try self.types.product(&.{ vector, vector });
            return switch (op.shape) {
                .unary, .convert => self.types.function(vector, output),
                .binary, .compare => self.types.function(vector, try self.types.function(vector, output)),
                .shift, .broadcast => self.types.function(vector, try self.types.function(T.u32_type, vector)),
                .reduce => self.types.function(vector, T.boolean),
                .select => self.types.function(lanes, try self.types.function(pair, vector)),
                .madd => self.types.function(vector, try self.types.function(pair, vector)),
                .shuffle => self.types.function(lanes, try self.types.function(pair, vector)),
                .swizzle => self.types.function(lanes, try self.types.function(vector, vector)),
            };
        }
        if (std.mem.eql(u8, text, "@hole")) {
            if (self.editorAt(id)) return self.captureEditor(id, 0, 0);
            const scope = try self.holeScope();
            try self.holes.append(self.allocator, .{ .node = id, .scope = scope, .owner = self.current });
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
        if (@import("../backend/collection_ops.zig").lookup(text)) |primitive| {
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
                .simd_load => self.types.function(sequence, try self.types.function(T.u32_type, try self.types.product(&.{ element, element, element, element }))),
                .simd_store => self.types.function(sequence, try self.types.function(T.u32_type, try self.types.function(try self.types.product(&.{ element, element, element, element }), sequence))),
                .cursor_has, .cursor_value, .cursor_advance => unreachable,
            };
        }
        try self.diagnostic(.unsupported, id);
        return self.types.fresh();
    }
    fn proofOperand(self: *Engine, source: ast.Id, depth: usize) proof_terms.Error!proof_terms.Id {
        const values = &self.proof_body.values;
        if (depth >= 128) return error.ProofAnalysisLimit;
        try values.charge(1);
        const node = self.tree.node(source);
        if (node.tag == .group) return self.proofOperand(node.a, depth + 1);
        const kind: proof_terms.Kind = switch (self.types.node(self.types.head(self.expr_types[source], 0)).tag) {
            .u32 => .u32,
            .array => .array,
            .list => .list,
            else => return error.InvalidProofOperand,
        };
        if (node.tag == .integer) return values.intern(self.allocator, .{ .tag = .literal, .a = node.a });
        if (node.tag == .name) {
            const binding = self.resolved[source];
            if (binding == 0) return error.InvalidProofOperand;
            if (self.proof_body.sources.get(binding)) |origin| return self.proofOperand(origin, depth + 1);
            return values.intern(self.allocator, .{ .tag = .version, .kind = kind, .a = binding, .b = 1 });
        }
        if (node.tag == .apply and self.tree.node(node.a).tag == .intrinsic) {
            const name = self.pool.get(self.tree.node(node.a).a);
            var collection: ?proof_terms.Kind = null;
            if (std.mem.eql(u8, name, "@array.length")) collection = .array;
            if (std.mem.eql(u8, name, "@list.length")) collection = .list;
            if (collection) |expected| {
                const operand = try self.proofOperand(node.b, depth + 1);
                if ((try values.view().get(operand)).kind != expected) return error.InvalidProofOperand;
                return values.intern(self.allocator, .{ .tag = .length, .a = operand });
            }
        }
        // These two namespaces keep a checked binding distinct from an
        // independently evaluated expression with the same numeric source ID.
        return values.intern(self.allocator, .{ .tag = .version, .kind = kind, .a = source, .b = 2 });
    }
    fn proofProposition(self: *Engine, source: ast.Id, depth: usize) proof_headers.Error!?proof_terms.Proposition {
        if (depth >= 128) return error.ProofAnalysisLimit;
        try self.proof_body.values.charge(1);
        if (self.proof_body.expressions.get(source)) |index| {
            const introduction = self.proof_body.introductions.items[index];
            if (introduction.owner != self.proof_owner) return error.ProofScopeEscape;
            return introduction.proposition;
        }
        const node = self.tree.node(source);
        if (node.tag == .group) return self.proofProposition(node.a, depth + 1);
        if (node.tag == .apply) return self.proofCallResult(source);
        if (node.tag == .block) {
            var result: ?proof_terms.Proposition = null;
            try self.proofReturns(source, &result, depth + 1);
            return result;
        }
        if (node.tag == .if_expr) {
            var result: ?proof_terms.Proposition = null;
            try self.proofJoin(node.b, &result, depth + 1);
            try self.proofJoin(node.c, &result, depth + 1);
            return result;
        }
        if (node.tag == .case_expr) {
            var result: ?proof_terms.Proposition = null;
            for (self.tree.list(.{ .start = node.b, .len = node.c })) |arm| {
                const metadata = self.tree.extra.items[self.tree.node(arm).c..][0..2];
                try self.proofJoin(metadata[1], &result, depth + 1);
            }
            return result;
        }
        if (node.tag != .name) return null;
        const binding = self.resolved[source];
        if (self.proof_body.sources.get(binding)) |origin| return self.proofProposition(origin, depth + 1);
        for (self.proof_body.parameters.items) |parameter| {
            try self.proof_body.values.charge(1);
            if (parameter.binding != binding) continue;
            try self.proof_body.values.charge(self.proof_contracts.items.len);
            for (self.proof_contracts.items) |contract| if (contract.binding == parameter.contract) {
                if (self.current != contract.binding or try self.proofBodySlot(contract, self.proof_owner) == null) return error.ProofScopeEscape;
                return parameter.proposition;
            };
        }
        return null;
    }
    fn proofJoin(self: *Engine, source: ast.Id, result: *?proof_terms.Proposition, depth: usize) proof_headers.Error!void {
        if (self.types.head(self.expr_types[source], 0) == T.never) return;
        const proposition = try self.proofProposition(source, depth) orelse return error.InvalidProofOperand;
        if (result.*) |prior| {
            if (!std.meta.eql(prior, proposition)) return error.InvalidProofOperand;
        } else result.* = proposition;
    }
    fn proofReturns(self: *Engine, source: ast.Id, result: *?proof_terms.Proposition, depth: usize) proof_headers.Error!void {
        if (source == 0) return;
        if (depth >= 128) return error.ProofAnalysisLimit;
        try self.proof_body.values.charge(1);
        const node = self.tree.node(source);
        switch (node.tag) {
            .block => for (self.tree.children(source)) |child| try self.proofReturns(child, result, depth + 1),
            .return_stmt => try self.proofJoin(node.a, result, depth + 1),
            .if_stmt => {
                try self.proofReturns(node.b, result, depth + 1);
                try self.proofReturns(node.c, result, depth + 1);
            },
            .if_let_stmt => for (self.tree.extra.items[node.c..][0..2]) |body| try self.proofReturns(body, result, depth + 1),
            .forever_stmt => try self.proofReturns(node.a, result, depth + 1),
            .range_stmt => try self.proofReturns(node.c, result, depth + 1),
            .for_stmt => try self.proofReturns(self.tree.extra.items[node.c + 1], result, depth + 1),
            else => {},
        }
    }
    fn proofCallResult(self: *Engine, source: ast.Id) proof_headers.Error!?proof_terms.Proposition {
        var arguments: std.ArrayList(ast.Id) = .empty;
        defer arguments.deinit(self.allocator);
        var leaf = source;
        while (self.tree.node(leaf).tag == .apply) {
            try self.proof_body.values.charge(1);
            if (arguments.items.len >= self.proof_body.values.limits.terms) return error.ProofAnalysisLimit;
            try arguments.append(self.allocator, self.tree.node(leaf).b);
            leaf = self.tree.node(leaf).a;
        }
        if (self.tree.node(leaf).tag != .name) return null;
        try self.proof_body.values.charge(self.proof_contracts.items.len);
        const header = self.proofContract(self.resolved[leaf]) orelse return null;
        if (header.result == null or arguments.items.len != header.arity) return null;
        std.mem.reverse(ast.Id, arguments.items);
        const values = try self.allocator.alloc(proof_terms.Id, header.arity);
        defer self.allocator.free(values);
        @memset(values, 0);
        for (header.value_slots) |slot| values[slot] = try self.proofOperand(arguments.items[slot], 0);
        const propositions = try header.signature().instantiate(self.allocator, &self.proof_body.values, values);
        defer self.allocator.free(propositions);
        return propositions[propositions.len - 1];
    }
    fn proofResult(self: *Engine, lambda: ast.Id, body: ast.Id) T.Error!void {
        if (self.types.head(self.expr_types[body], 0) == T.never) return;
        self.proof_body.values.charge(self.proof_contracts.items.len) catch |err| {
            _ = try self.proofHeaderFailure(err, body);
            return;
        };
        for (self.proof_contracts.items) |contract| {
            if (contract.binding != self.current or contract.header.result == null) continue;
            const slot = (self.proofBodySlot(contract, lambda) catch |err| {
                _ = try self.proofHeaderFailure(err, body);
                return;
            }) orelse continue;
            if (slot + 1 != contract.header.arity) continue;
            const values = try self.allocator.alloc(proof_terms.Id, contract.header.arity);
            defer self.allocator.free(values);
            @memset(values, 0);
            for (contract.header.value_slots, contract.header.values) |position, kind| {
                values[position] = self.proof_body.values.intern(self.allocator, .{ .tag = .version, .kind = kind, .a = contract.parameters[position], .b = 1 }) catch |err| {
                    _ = try self.proofHeaderFailure(err, body);
                    return;
                };
            }
            const expected = contract.header.signature().instantiate(self.allocator, &self.proof_body.values, values) catch |err| {
                _ = try self.proofHeaderFailure(err, body);
                return;
            };
            defer self.allocator.free(expected);
            const actual = self.proofProposition(body, 0) catch |err| {
                _ = try self.proofHeaderFailure(err, body);
                return;
            };
            if (!try self.proofEntails(actual, expected[expected.len - 1], body)) try self.diagnostic(.proof_mismatch, body);
            return;
        }
        try self.diagnostic(.proof_scope_escape, body);
    }
    fn proofEntails(self: *Engine, actual: ?proof_terms.Proposition, expected: proof_terms.Proposition, source: ast.Id) T.Error!bool {
        const supplied = actual orelse return false;
        if (std.meta.eql(supplied, expected)) return true;
        return @import("numeric_proof_contracts.zig").entails(self.allocator, &self.proof_body.values, &.{supplied}, expected) catch |err| {
            _ = try self.proofHeaderFailure(err, source);
            return false;
        };
    }
    fn proofCall(self: *Engine, source: ast.Id, witness: ast.Id) T.Error!bool {
        var reverse: std.ArrayList(ast.Id) = .empty;
        defer reverse.deinit(self.allocator);
        var leaf = source;
        while (self.tree.node(leaf).tag == .apply) {
            if (reverse.items.len >= 4096) {
                try self.diagnostic(.proof_analysis_limit, source);
                return false;
            }
            try reverse.append(self.allocator, self.tree.node(leaf).b);
            leaf = self.tree.node(leaf).a;
        }
        if (self.tree.node(leaf).tag != .name or reverse.items.len == 0) {
            try self.diagnostic(.proof_runtime_use, source);
            return false;
        }
        const callee = self.resolved[leaf];
        self.proof_body.values.charge(reverse.items.len + self.proof_contracts.items.len) catch |err| {
            _ = try self.proofHeaderFailure(err, source);
            return false;
        };
        const header = self.proofContract(callee) orelse {
            try self.diagnostic(.proof_runtime_use, source);
            return false;
        };
        std.mem.reverse(ast.Id, reverse.items);
        const slot: u32 = @intCast(reverse.items.len - 1);
        const arguments = try self.allocator.alloc(proof_terms.Id, slot);
        defer self.allocator.free(arguments);
        @memset(arguments, 0);
        for (header.value_slots) |value_slot| {
            if (value_slot >= slot) break;
            arguments[value_slot] = self.proofOperand(reverse.items[value_slot], 0) catch |err| {
                _ = try self.proofHeaderFailure(err, source);
                return false;
            };
        }
        const expected = header.signature().instantiateRequirement(self.allocator, &self.proof_body.values, slot, arguments) catch |err| {
            _ = try self.proofHeaderFailure(err, source);
            return false;
        };
        const actual = self.proofProposition(witness, 0) catch |err| {
            _ = try self.proofHeaderFailure(err, witness);
            return false;
        };
        if (!try self.proofEntails(actual, expected, witness)) {
            try self.diagnostic(.proof_mismatch, witness);
            return false;
        }
        self.proof_body.use(self.allocator, .{ .source = source, .callee = callee, .witness = witness, .proposition = expected }) catch |err| {
            _ = try self.proofHeaderFailure(err, source);
            return false;
        };
        return true;
    }
    fn proofIntroduction(self: *Engine, id: ast.Id) T.Error!?T.Id {
        if (!self.tree.has_numeric_proofs) return null;
        const outer = self.tree.node(id);
        if (outer.tag != .apply) return null;
        const inner = self.tree.node(outer.a);
        if (inner.tag != .apply) return null;
        const primitive = self.tree.node(inner.a);
        if (primitive.tag != .intrinsic) return null;
        const relation = proof_terms.constructor(self.pool.get(primitive.a)) orelse return null;
        // Both checked operands retain source order even for a known-false
        // proposition. A false constructor still needs its runtime trap.
        const left_type = try self.expression(inner.b);
        const right_type = try self.expression(outer.b);
        if (relation != .index) try self.constrain(left_type, T.u32_type, inner.b);
        try self.constrain(right_type, T.u32_type, outer.b);
        const left = self.proofOperand(inner.b, 0) catch |err| return try self.proofHeaderFailure(err, inner.b);
        const right = self.proofOperand(outer.b, 0) catch |err| return try self.proofHeaderFailure(err, outer.b);
        self.proof_body.introduce(self.allocator, .{ .source = id, .owner = self.proof_owner, .arguments = .{ inner.b, outer.b }, .proposition = .{ .relation = relation, .left = left, .right = right } }) catch |err| return try self.proofHeaderFailure(err, id);
        return try self.types.proofKind();
    }
    fn runtimeValue(self: *Engine, ty: T.Id, source: ast.Id) T.Error!T.Id {
        if (!self.types.has_proof_kinds or self.types.node(self.types.head(ty, 0)).tag != .erased_proof) return ty;
        try self.diagnostic(.proof_runtime_use, source);
        return self.types.fresh();
    }
    fn nameExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        if (self.editorAt(id) and self.editor_marker.?.kind == .expression)
            return try self.captureEditor(id, 0, 0);
        if (self.lookup(node.a)) |binding| {
            if (self.tree.has_typed_staging and (self.staging_bindings.get(binding) orelse 0) != self.staging_depth) try self.diagnostic(.stage_unavailable, id);
            self.resolved[id] = binding;
            const ty = try self.instantiate(binding, id);
            if (self.types.has_proof_kinds and self.types.node(self.types.head(ty, 0)).tag == .erased_proof) {
                const proposition = self.proofProposition(id, 0) catch |err| return try self.proofHeaderFailure(err, id);
                if (proposition == null) try self.diagnostic(.proof_mismatch, id);
            }
            return ty;
        }
        if (try self.globalBinding(node.a)) |binding| return try self.globalReference(binding, id);
        if (try self.qualifiedValue(id, node.a)) |ty| return ty;
        if (try self.operationTemplate(node.a)) |template| return try self.operationValue(id, template, null);
        if (try self.typeConstructorValue(self.catalogKey(node.a))) |ty| return ty;
        try self.diagnostic(.unknown_name, id);
        return try self.types.fresh();
    }
    fn fieldExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        var parent = node.a;
        while (self.tree.node(parent).tag == .group) parent = self.tree.node(parent).a;
        const base = self.tree.node(parent);
        if (base.tag == .name and self.lookup(base.a) == null) {
            if (self.catalogs.qualified.get(.{ .namespace = base.a, .member = node.b })) |binding|
                return try self.globalReference(binding, id);
            if (try self.typeConstructorValue(.{ .namespace = base.a, .member = node.b })) |ty| return ty;
        }
        if (self.editorAt(id)) {
            var namespace: symbols.Symbol = 0;
            var receiver: T.Id = 0;
            if (base.tag == .name and self.lookup(base.a) == null and self.isNamespace(base.a)) {
                namespace = base.a;
            } else {
                receiver = try self.expression(node.a);
            }
            return try self.captureEditor(id, receiver, namespace);
        }
        const receiver = try self.expression(node.a);
        if (try self.scopedOperation(id, receiver, node.b, node.a)) |operation| return operation;
        const projected = try self.projectField(receiver, node.b, id, false, null);
        self.projection_resolved[id] = projected.projection;
        return projected.ty;
    }
    fn constructorExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        if (self.editorAt(id)) {
            const key = self.catalogKey(node.a);
            return try self.captureEditor(id, 0, key.namespace);
        }
        const ctor = self.catalogs.constructor_names.get(self.catalogKey(node.a)) orelse {
            try self.constructorDiagnostic(self.tree.node(id).a, id);
            return try self.types.fresh();
        };
        self.constructor_resolved[id] = ctor;
        return try self.types.openCovariant(try self.constructorType(ctor));
    }
    fn witnessExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        const value = try self.expression(node.a);
        const name = self.pool.lookup("Type") orelse {
            try self.constructorDiagnostic(self.tree.node(id).a, id);
            return try self.types.fresh();
        };
        const ctor = self.catalogs.constructor_names.get(self.catalogKey(name)) orelse {
            try self.constructorDiagnostic(self.tree.node(id).a, id);
            return try self.types.fresh();
        };
        self.constructor_resolved[id] = ctor;
        const result = try self.types.fresh();
        try self.constrain(try self.constructorType(ctor), try self.types.function(value, result), id);
        return result;
    }
    fn indexExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        const owner = try self.expression(node.a);
        const index = try self.expression(node.b);
        const element = try self.types.fresh();
        try self.constrain(owner, try self.types.sequence(.array, element), id);
        try self.constrain(index, T.u32_type, node.b);
        return element;
    }
    fn arrayExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        const element = try self.types.fresh();
        var diverges = false;
        for (self.tree.children(id)) |child| {
            const value = try self.runtimeValue(try self.expression(child), child);
            try self.constrain(element, value, child);
            diverges = diverges or try self.types.resolve(value, 0) == T.never;
        }
        return if (diverges) T.never else try self.types.sequence(if (node.c == 1) .list else .array, element);
    }
    fn lambdaExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        const parameter = self.tree.parameter(node.a);
        if (parameter.where_node != 0) try self.diagnostic(.higher_rank_constraint, parameter.where_node);
        var expected: T.Id = 0;
        if (self.expected_lambda_source == id) expected = self.expected_lambda_type;
        var required_arrow: T.Node = .{ .tag = .absent };
        if (expected != 0) required_arrow = self.types.node(try self.types.resolve(expected, 0));
        const contextual = expected != 0 and required_arrow.tag == .function;
        const contextual_capability = contextual and self.types.node(try self.types.resolve(required_arrow.a, 0)).tag == .scoped;
        const scoped = node.a == self.scoped_parameter;
        const saved_selection_parameter = self.scoped_parameter;
        if (!scoped) self.scoped_parameter = 0;
        defer self.scoped_parameter = saved_selection_parameter;
        const descriptor = if (!scoped) try self.capabilityDescriptorAnnotation(parameter.annotation) else null;
        const symbolic_capability = descriptor != null or contextual_capability;
        const element_ty = if (scoped) self.scoped_parameter_type else if (contextual) required_arrow.a else if (descriptor) |family| try self.types.capabilityParameter(family) else if (parameter.is_unit) T.unit else try self.types.fresh();
        if (contextual) {
            if (descriptor) |family| try self.constrain(element_ty, try self.types.capabilityParameter(family), node.a);
            if (parameter.is_unit) try self.constrain(element_ty, T.unit, node.a);
        }
        if (!scoped and !symbolic_capability and parameter.annotation != 0) try self.constrain(element_ty, try self.annotation(parameter.annotation), node.a);
        if (symbolic_capability) {
            try self.scope_lifetimes.append(self.allocator, element_ty);
            self.active_effect_scopes += 1;
        }
        defer if (symbolic_capability) {
            _ = self.scope_lifetimes.pop();
            self.active_effect_scopes -= 1;
        };
        const parameter_ty = if (parameter.demanded) try self.types.demandWithEffects(element_ty, try self.types.freshEffects()) else element_ty;
        const saved_frames = self.storage_frames;
        const has_frames = saved_frames.items.len != 0 and !scoped;
        if (has_frames) self.storage_frames = .empty;
        defer if (has_frames) {
            self.storage_frames.deinit(self.allocator);
            self.storage_frames = saved_frames;
        };
        const saved_ambient = self.ambient;
        self.ambient = try self.types.freshEffects();
        defer self.ambient = saved_ambient;
        const latent = self.ambient;
        try self.row_sources.put(self.allocator, self.types.row(latent).tail.variable, id);
        const scope = self.env.items.len;
        const saved_owner = self.owner;
        const saved_generation_owner = self.generative_owner;
        self.generative_owner = id;
        defer self.generative_owner = saved_generation_owner;
        const saved_proof_owner = self.proof_owner;
        const saved_target = self.return_target;
        const saved_function_body = self.function_body;
        const saved_function_exit_allowed = self.function_exit_allowed;
        const saved_function_exit_target = self.function_exit_target;
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
        self.proof_owner = id;
        self.return_target = 0;
        self.function_exit_allowed = true;
        self.function_exit_target = 0;
        defer {
            self.env.shrinkRetainingCapacity(scope);
            self.owner = saved_owner;
            self.proof_owner = saved_proof_owner;
            self.return_target = saved_target;
            self.function_body = saved_function_body;
            self.function_exit_allowed = saved_function_exit_allowed;
            self.function_exit_target = saved_function_exit_target;
        }
        if (parameter.name != 0) {
            const binding = try self.addBinding(.{ .name = parameter.name, .declaration = node.a, .owner = id, .kind = .parameter, .ty = parameter_ty });
            self.resolved[node.a] = binding;
            try self.env.append(self.allocator, .{ .name = parameter.name, .binding = binding });
            if (contextual) try self.proofParameter(id, binding);
        }
        self.expr_types[node.a] = parameter_ty;
        const result_annotation = if (node.c != 0 and self.tree.node(node.c).tag == .type_effect) self.tree.node(node.c).a else node.c;
        const required = if (result_annotation != 0) try self.annotation(result_annotation) else 0;
        if (node.c != 0 and self.tree.node(node.c).tag == .type_effect) try self.constrainEffects(latent, try self.annotationEffects(self.tree.node(node.c).b), id);
        var result: T.Id = 0;
        self.function_body = node.b;
        if (required != 0) result = try self.contextualLambda(node.b, required) else if (contextual) result = try self.contextualLambda(node.b, required_arrow.b) else result = try self.expression(node.b);
        if (self.function_exit_target != 0) {
            try self.function_exit_lambdas.append(self.allocator, id);
            if (try self.types.resolve(result, 0) != T.never) try self.constrain(self.function_exit_target, result, id);
            result = self.function_exit_target;
        }
        if (required != 0) {
            try self.constrain(result, required, id);
            result = required;
        } else if (try self.types.resolve(result, 0) == T.never) {
            // A lambda's result is a fresh inference variable. Bottom
            // satisfies it without fixing the callable's result type.
            if (contextual and self.types.node(self.types.head(required_arrow.b, 0)).tag == .erased_proof) {
                result = required_arrow.b;
            } else result = try self.types.fresh();
        }
        if (self.types.has_proof_kinds and self.types.node(self.types.head(result, 0)).tag == .erased_proof) try self.proofResult(id, node.b);
        const raw_function = try self.types.functionWithEffects(parameter_ty, result, latent);
        for (self.generative_bindings.items) |*binder| {
            if (binder.owner == id and binder.arrow == 0) binder.arrow = raw_function;
        }
        try self.certifyLambda(id, raw_function, saved_ambient);
        return raw_function;
    }
    fn applicationExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        var direct_source = node.a;
        while (self.tree.node(direct_source).tag == .group) direct_source = self.tree.node(direct_source).a;
        const direct = self.tree.node(direct_source);
        if (direct.tag == .intrinsic and std.mem.eql(u8, self.pool.get(direct.a), "@usage.share")) {
            const input = try self.expression(node.b);
            const owner = self.types.node(self.types.head(input, 0));
            if (owner.tag != .usage or owner.b != @backingInt(T.UsageKind.unique) or owner.c != 0 or !@import("cleanup_contracts.zig").payloadNominal(&self.types, self.nominals.items, owner.a)) {
                try self.diagnostic(.usage_evidence_mismatch, node.b);
                return try self.types.fresh();
            }
            const shared = try self.types.usage(owner.a, .shared, 0);
            self.expr_types[direct_source] = try self.types.function(input, shared);
            return shared;
        }
        if (direct.tag == .intrinsic and (std.mem.eql(u8, self.pool.get(direct.a), "@usage.read") or std.mem.eql(u8, self.pool.get(direct.a), "@usage.length"))) {
            const input = try self.expression(node.b);
            const wrapper = self.types.node(self.types.head(input, 0));
            if (wrapper.tag != .usage or (wrapper.b != @backingInt(T.UsageKind.borrow) and wrapper.b != @backingInt(T.UsageKind.borrow_mut) and wrapper.b != @backingInt(T.UsageKind.shared))) {
                try self.diagnostic(.usage_evidence_mismatch, node.b);
                return try self.types.fresh();
            }
            const payload = self.types.node(self.types.head(wrapper.a, 0));
            var result = wrapper.a;
            if (std.mem.eql(u8, self.pool.get(direct.a), "@usage.length")) {
                if (payload.tag != .array and payload.tag != .list) {
                    try self.diagnostic(.usage_evidence_mismatch, node.b);
                    return try self.types.fresh();
                }
                result = T.u32_type;
            } else if (payload.tag != .unit and payload.tag != .boolean and payload.tag != .u32 and payload.tag != .f32) {
                try self.diagnostic(.usage_evidence_mismatch, node.b);
                return try self.types.fresh();
            }
            self.expr_types[direct_source] = try self.types.function(input, result);
            return result;
        }
        if (try self.taskApplication(id)) |ty| return ty;
        if (try self.resourceScope(id)) |ty| return ty;
        if (try self.usageBorrow(id)) |ty| return ty;

        if (self.tree.has_typed_staging) if (try self.stagingApplication(id)) |ty| return ty;
        if (try self.proofIntroduction(id)) |ty| return ty;
        if (try self.effectScopeApplication(id)) |ty| return ty;
        if (try self.requestCapture(id)) |ty| return ty;
        if (try self.operationApplication(id)) |ty| return ty;
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
                    return try self.types.fresh();
                }
                self.permitted_intrinsic = leaf;
            }
        }
        if (try self.reflectionApplication(id)) |ty| return ty;
        if (try self.builtinStateApplication(id)) |ty| return ty;
        if (try self.effectRunnerApplication(id)) |ty| return ty;
        if (try self.providerApplication(id)) |ty| return ty;
        const head = self.tree.node(node.a);
        if (head.tag == .intrinsic and std.mem.eql(u8, self.pool.get(head.a), "@do.monad")) {
            const token = try self.expression(node.b);
            const result = try self.types.resolver(token);
            const op = try self.addResolverOp(.{ .node = id, .kind = .monad, .payload = token, .result = result, .method_type = try self.types.function(token, result) }, true);
            try self.appendPending(.{ .owner = self.current, .metadata = op, .value = .{ .kind = .monad_factory, .ty = token, .result = result, .source = id } });
            return result;
        }
        if (head.tag == .intrinsic and (std.mem.eql(u8, self.pool.get(head.a), "@force") or std.mem.eql(u8, self.pool.get(head.a), "@demand"))) {
            const suspended = try self.expression(node.b);
            const result = try self.types.fresh();
            try self.constrain(suspended, try self.types.demandWithEffects(result, self.ambient), id);
            return result;
        }
        if (head.tag == .intrinsic and std.mem.eql(u8, self.pool.get(head.a), "@panic")) {
            var argument = node.b;
            while (self.tree.node(argument).tag == .group) argument = self.tree.node(argument).a;
            if (self.tree.node(argument).tag != .string) try self.diagnostic(.call_arity, argument);
            return T.never;
        }
        if (try self.productProjection(id)) |ty| return ty;
        if (try self.associatedApplication(id)) |ty| return ty;
        if (try self.resultApplication(id)) |ty| return ty;
        return self.ordinaryApplication(id, leaf);
    }
    fn ordinaryApplication(self: *Engine, id: ast.Id, leaf: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        var function_ty = try self.types.openCovariant(try self.types.resolve(try self.expression(node.a), 0));
        var rank_goals: T.List = .{};
        if (self.types.node(function_ty).tag == .forall) {
            const instance = try self.types.instantiateRank(function_ty, false);
            function_ty = try self.types.openCovariant(instance.body);
            rank_goals = instance.goals;
            // Each call owns its concrete instance, while the binding
            // continues to expose the declared universal principal.
            self.expr_types[node.a] = function_ty;
        }
        const qualified_id = try self.types.resolve(function_ty, 0);
        const qualified_function = self.types.node(qualified_id);
        const cleanup_call = qualified_function.tag == .usage and qualified_function.b == @backingInt(T.UsageKind.cleanup);
        const concurrent_call = qualified_function.tag == .usage and qualified_function.b == @backingInt(T.UsageKind.concurrent);
        if (qualified_function.tag == .usage and (qualified_function.b == @backingInt(T.UsageKind.once) or qualified_function.b == @backingInt(T.UsageKind.many) or cleanup_call or concurrent_call)) function_ty = qualified_function.a;
        function_ty = try self.freshGenerativeInvocation(id, function_ty);
        self.expr_types[node.a] = function_ty;
        if (cleanup_call or concurrent_call) self.expr_types[node.a] = qualified_id;
        const function = self.types.node(try self.types.resolve(function_ty, 0));
        const lazy = function.tag == .function and self.types.node(self.types.head(function.a, 0)).tag == .demand;
        const saved_exact = self.exact_argument_types;
        self.exact_argument_types = saved_exact or try self.evidenceCall(node.a, 0);
        const argument = blk_argument: {
            if (function.tag == .function and (self.types.node(try self.types.resolve(function.a, 0)).tag == .forall or self.types.node(self.types.head(function.a, 0)).tag == .usage)) break :blk_argument try self.contextualLambda(node.b, function.a);
            break :blk_argument self.checkArgument(node.b, lazy);
        } catch |err| {
            self.exact_argument_types = saved_exact;
            return err;
        };
        self.exact_argument_types = saved_exact;
        if (self.tree.node(leaf).tag == .intrinsic and std.mem.eql(u8, self.pool.get(self.tree.node(leaf).a), "@type.same") and try self.types.containsRigid(argument, 0)) {
            try self.diagnostic(.abstract_representation_access, node.b);
        }
        if (function.tag == .function and self.types.node(self.types.head(function.a, 0)).tag == .erased_proof) {
            if (!try self.proofCall(id, node.b)) return try self.types.fresh();
        } else if (self.types.node(try self.types.resolve(argument, 0)).tag == .erased_proof) {
            try self.diagnostic(.proof_runtime_use, node.b);
            return try self.types.fresh();
        }
        if (self.active_effect_scopes != 0 and try self.scopeFootprint(argument, 0) and (!lazy or try self.demandCaptureFootprint(node.b)) and !try self.capabilityFlowUse(node.a, argument) and !self.intrinsicRead(node.a) and !try self.directCallbackUse(node.a, argument) and !try self.localStateStore(node.a, node.b, argument)) try self.diagnostic(.capability_escape, node.b);
        const parameter = argument;
        self.demand_calls[id] = lazy;
        if (lazy) {
            self.demand_types[id] = function.a;
            self.demand_once[id] = try self.declaredAffineDemand(function.a);
        }
        var result = try self.types.fresh();
        if (function.tag == .function) {
            const result_kind = self.types.node(self.types.head(function.b, 0)).tag;
            if (result_kind == .erased_proof or result_kind == .forall) result = function.b;
        }
        try self.constrain(function_ty, try self.invocation(parameter, result), id);
        for (0..rank_goals.len) |ordinal| {
            var goal = self.types.quantifier_obligations.items[rank_goals.start + ordinal];
            goal.source = id;
            if (goal.kind == .contract) {
                const arguments = self.types.node(self.types.head(goal.ty, 0));
                if (arguments.tag == .product and try self.contractGiven(goal.identity, self.types.list(.{ .start = arguments.a, .len = arguments.b }))) continue;
            }
            try self.appendPending(.{ .owner = self.current, .suspended = goal.explicit, .value = goal });
        }

        return try self.applicationFlow(id, function_ty, argument, try self.freshFormalInvocation(id, result));
    }
    // Only a demand parameter declared affine before instantiation may move
    // its captures. A generic `~value` body may retry the suspension, so a
    // later affine instance must not consume captured owners.
    fn declaredAffineDemand(self: *Engine, parameter: T.Id) T.Error!bool {
        return @import("usage_check.zig").affineNominal(&self.types, self.nominals.items, parameter);
    }
    fn productExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        var fields: std.ArrayList(T.Id) = .empty;
        defer fields.deinit(self.allocator);
        var diverges = false;
        for (self.tree.children(id)) |child| {
            const value = try self.runtimeValue(try self.expression(child), child);
            try fields.append(self.allocator, value);
            diverges = diverges or try self.types.resolve(value, 0) == T.never;
        }
        return if (diverges) T.never else try self.types.product(fields.items);
    }
    fn unaryExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        const operand = try self.expression(node.b);
        const operator = self.pool.get(node.a);
        if (std.mem.eql(u8, operator, "-")) {
            try self.constrain(operand, T.f32_type, id);
            return T.f32_type;
        }
        try self.diagnostic(.invalid_operator, id);
        return try self.types.fresh();
    }
    fn conditionalExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        const condition = try self.expression(node.a);
        try self.constrain(condition, T.boolean, node.a);
        const left = try self.expression(node.b);
        const right = try self.expression(node.c);
        if (self.active_effect_scopes != 0) {
            const left_root = try self.types.resolve(left, 0);
            const right_root = try self.types.resolve(right, 0);
            const left_capability = self.types.node(left_root);
            const right_capability = self.types.node(right_root);
            if (left_capability.tag == .scoped and right_capability.tag == .scoped and !try self.types.equalSymbolic(left_root, right_root)) {
                if (self.scoped_parameter == 0 and self.generative_owner != 0 and self.loop_stack.items.len == 0) {
                    try self.constrain(left_capability.a, right_capability.a, id);
                    const version = try self.generationVersion(id);
                    const term = try self.types.instanceSelection(.{ .unit = self.unit, .decl = id }, &.{ left_root, right_root, version });
                    const selected = try self.types.scoped(left_capability.a, .{ .unit = 0, .decl = term });
                    try self.generative_bindings.append(self.allocator, .{ .owner = self.generative_owner, .origin = id, .selection = selected });
                    return selected;
                }
                const current = self.types.node(self.scoped_parameter_type);
                var selection_budget: usize = 65_536;
                const boundary: FootprintBoundary = .{ .exiting = .{ .unit = current.b, .decl = current.c } };
                const contains_current = try self.scopeFootprintDepth(left_root, 0, &selection_budget, &.{}, boundary) or try self.scopeFootprintDepth(right_root, 0, &selection_budget, &.{}, boundary);
                if (self.scoped_parameter == 0 or self.loop_stack.items.len != 0 or !contains_current) {
                    try self.diagnostic(.effect_identity_scope, id);
                    return left_root;
                }
                try self.constrain(left_capability.a, right_capability.a, id);
                const term = try self.types.instanceSelection(.{ .unit = self.unit, .decl = id }, &.{ left_root, right_root });
                return try self.types.scoped(left_capability.a, .{ .unit = 0, .decl = term });
            }
        }
        try self.constrain(left, right, id);
        return if (left == T.never) right else left;
    }
    fn blockExpression(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        const resolver_type = if (node.c == 0) 0 else try self.expression(node.c);
        if (resolver_type != 0) {
            const resolver = self.types.node(try self.types.resolve(resolver_type, 0));
            if (resolver.tag == .provider or resolver.tag == .state_provider) return try self.providerBlock(id, resolver_type);
        }
        const scope = self.env.items.len;
        const first_binding = self.bindings.items.len;
        const nested = self.function_body != id;
        const old_target = self.return_target;
        const old_owner = self.owner;
        const old_resolver = self.resolver_scope;
        const arm: ?*ArmCapture = if (self.arm_capture) |capture| (if (capture.block == id and resolver_type == 0) capture else null) else null;
        const old_arm_block = self.arm_block;
        const old_arm_return = self.arm_nested_return;
        if (arm != null) {
            self.arm_block = id;
            self.arm_nested_return = 0;
        }
        var result = try self.types.fresh();
        if (self.expected_lambda_source == id and self.types.node(self.types.head(self.expected_lambda_type, 0)).tag == .erased_proof) result = self.expected_lambda_type;
        self.resolver_scope = .{};
        var block_index: u32 = 0;
        if (resolver_type != 0) {
            const tag = self.types.node(try self.types.resolve(resolver_type, 0)).tag;
            if (tag != .variable and tag != .resolver) try self.diagnostic(.invalid_provider, node.c);
            const binding = try self.addBinding(.{ .name = 0, .declaration = id, .owner = id, .kind = .local, .ty = resolver_type, .scheme = .{ .root = resolver_type } });
            self.resolver_scope = .{ .block = id, .resolver = binding, .owner_type = resolver_type, .result = result };
            if (self.resolver_blocks.items.len >= std.math.maxInt(u32)) return error.TypeLimit;
            try self.resolver_blocks.append(self.allocator, .{ .node = id, .resolver = binding, .result = result, .body_effects = self.ambient });
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
            self.arm_block = old_arm_block;
            self.arm_nested_return = old_arm_return;
        }
        const flow = try self.suite(id);
        // A statement case arm reports its final versions of the enclosing
        // locals. Like an if branch, it carries those it rebinds out of the
        // case, or out of a loop it breaks, instead of letting them die here.
        var carried: usize = 0;
        if (arm) |capture| {
            const enclosing = self.env.items[0..capture.versions.len];
            for (enclosing, capture.versions) |entry, *version| version.* = self.latestSuccessor(entry.binding);
            capture.carrying = for (enclosing, capture.versions) |entry, version| {
                if (version != entry.binding) break true;
            } else false;
            carried = capture.versions.len;
            if (capture.carrying and self.arm_nested_return != 0) try self.diagnostic(.case_arm_return, self.arm_nested_return);
        }
        if (nested) try self.deadRebindings(scope, first_binding, carried);
        if (!flow.exits) {
            if (block_index == 0) try self.constrain(result, T.unit, id) else {
                const op = try self.resolverMethod(id, .pure, T.unit, self.resolver_scope.result, 0, false);
                self.resolver_blocks.items[block_index - 1].fallthrough = op;
            }
        }
        return if (flow.exits and flow.breaks and !flow.returns) T.never else result;
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
            .name => try self.nameExpression(id),
            .selector => try self.selectorFunction(id),
            .field_access => try self.fieldExpression(id),
            .constructor_ref => try self.constructorExpression(id),
            .type_witness => try self.witnessExpression(id),
            .record => try self.recordValue(id),
            .index_access => try self.indexExpression(id),
            .array => try self.arrayExpression(id),
            .package_pack => try self.checkPackagePack(id),
            .package_unpack => try self.checkPackageUnpack(id),
            .intrinsic => try self.types.openCovariant(try self.intrinsic(id, node.a)),
            .lambda => try self.lambdaExpression(id),
            .apply => try self.applicationExpression(id),
            .product => try self.productExpression(id),
            .unary => try self.unaryExpression(id),
            .binary => try self.binary(id),
            .case_expr => try self.caseExpression(id),
            .request_case => blk: {
                try self.diagnostic(.request_case_scope, id);
                break :blk try self.types.fresh();
            },
            .if_expr => try self.conditionalExpression(id),
            .block => try self.blockExpression(id),
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
        if (attributes.len == 0) {
            if (self.current != 0 and self.bindings.items[self.current].kind == .global) {
                const declaration = self.tree.valueDecl(self.bindings.items[self.current].declaration);
                if (declaration.body == body and declaration.annotation != 0) {
                    const written = self.tree.node(declaration.annotation);
                    if ((self.expr_types[declaration.annotation] != 0 and (try self.types.containsQuantifier(self.expr_types[declaration.annotation]) or try @import("usage_check.zig").containsNominal(&self.types, self.nominals.items, self.expr_types[declaration.annotation]))) or self.proofContract(self.current) != null or written.tag == .type_usage or (written.tag == .type_function and self.tree.node(written.a).tag == .type_binder)) return self.contextualLambda(body, self.expr_types[declaration.annotation]);
                }
            }
            return self.expression(body);
        }
        const attribute = attributes[0];
        const function_ty = try self.expression(self.tree.node(attribute).a);
        const argument = try self.taggedExpression(attributes[1..], body, depth + 1);
        const result = try self.types.fresh();
        try self.constrain(function_ty, try self.invocation(argument, result), attribute);
        self.expr_types[attribute] = result;
        return result;
    }
    fn freshGenerativeInvocation(self: *Engine, source: ast.Id, original: T.Id) T.Error!T.Id {
        if (self.generative_bindings.items.len == 0) return original;
        const root = try self.types.resolve(original, 0);
        var old: [32]T.Id = undefined;
        var fresh: [32]T.Id = undefined;
        var count: usize = 0;
        const before = self.generative_bindings.items.len;
        for (0..before) |index| {
            const binder = self.generative_bindings.items[index];
            if (binder.arrow == 0 or !try @import("generative_schemes.zig").sameArrow(&self.types, binder.arrow, root)) continue;
            const selected = try self.types.resolve(binder.selection, 0);
            var known = false;
            for (old[0..count]) |prior| if (prior == selected) {
                known = true;
                break;
            };
            if (known) continue;
            if (count == old.len) return error.TypeLimit;
            const value = self.types.node(selected);
            if (value.tag != .scoped or value.b != 0) return error.TypeLimit;
            const term = self.types.node(value.c);
            if (term.tag != .instance_selection) return error.TypeLimit;
            const choices = try self.allocator.dupe(T.Id, self.types.nominalArguments(term));
            defer self.allocator.free(choices);
            if (choices.len != 3) return error.TypeLimit;
            const version = try self.generationVersion(source);
            const created = try self.types.instanceSelection(.{ .unit = term.a, .decl = term.b }, &.{ choices[0], choices[1], version });
            const result = try self.types.scoped(value.a, .{ .unit = 0, .decl = created });
            old[count] = selected;
            fresh[count] = result;
            count += 1;
            old[count] = value.c;
            fresh[count] = created;
            count += 1;
            try self.generative_bindings.append(self.allocator, .{ .owner = self.generative_owner, .origin = source, .selection = result });
        }
        if (count == 0) return original;
        // Returned arrows retain earlier selections, but declare their own
        // later invocation. Relocate both endpoints with the same substitution.
        for (0..before) |index| {
            const binder = self.generative_bindings.items[index];
            if (binder.arrow == 0 or try @import("generative_schemes.zig").sameArrow(&self.types, binder.arrow, root)) continue;
            const before_arrow = try self.types.resolve(binder.arrow, 0);
            const arrow = try self.types.substitute(before_arrow, old[0..count], fresh[0..count]);
            if (try self.types.equalSymbolic(arrow, before_arrow)) continue;
            try self.generative_bindings.append(self.allocator, .{
                .origin = source,
                .arrow = arrow,
                .selection = try self.types.substitute(try self.types.resolve(binder.selection, 0), old[0..count], fresh[0..count]),
            });
        }
        return self.types.substitute(root, old[0..count], fresh[0..count]);
    }
    fn freshFormalInvocation(self: *Engine, source: ast.Id, result: T.Id) T.Error!T.Id {
        if (self.generative_bindings.items.len == 0 and !self.has_input_invocations) return result;
        var arguments: [16]ast.Id = undefined;
        var count: usize = 0;
        var head = source;
        while (self.tree.node(head).tag == .apply or self.tree.node(head).tag == .group) {
            const node = self.tree.node(head);
            if (node.tag == .apply) {
                if (count == arguments.len) return result;
                arguments[count] = node.b;
                count += 1;
            }
            head = node.a;
        }
        if (self.tree.node(head).tag != .name or self.resolved[head] == 0) return result;
        const binding = self.bindings.items[self.resolved[head]];
        var callback: usize = 0;
        if (binding.capability_flow == .invoke_unit) {
            if (count != 1) return result;
        } else {
            const contract = binding.capability_parameters;
            if (!contract.invokes() or !contract.valid() or contract.arity() != count) return result;
            callback = contract.callback();
            if (contract.inputInvokes()) {
                var remaining: usize = 4096;
                var transfers = false;
                for (0..contract.argumentCount()) |index| {
                    const supplied = arguments[count - contract.argumentAt(index) - 1];
                    const argument_type = try self.types.resolve(self.expr_types[supplied], 0);
                    if (self.active_effect_scopes != 0 or self.types.node(argument_type).tag == .scoped) {
                        transfers = transfers or (try self.valueFootprint(supplied, .{}, &.{}, &remaining, 0) orelse try self.scopeFootprint(argument_type, 0));
                    }
                }
                var state_store = false;
                if (transfers and contract.argumentCount() == 1) {
                    const value = arguments[count - contract.argumentAt(0) - 1];
                    state_store = try self.localStateStoreBudget(arguments[count - callback - 1], value, self.expr_types[value], &remaining);
                }
                if (transfers and !state_store and (try self.inputCallback(arguments[count - callback - 1], contract.argumentCount(), &remaining, 0)) == null) {
                    try self.diagnostic(.capability_escape, arguments[count - callback - 1]);
                    return result;
                }
            }
        }
        const original = try self.types.resolve(self.expr_types[arguments[count - callback - 1]], 0);
        const function = self.types.node(original);
        if (function.tag != .function) return result;
        if (!binding.capability_parameters.inputInvokes() and try self.types.resolve(function.a, 0) != T.unit) return result;
        const fresh = try self.freshGenerativeInvocation(source, original);
        if (fresh == original) return result;
        var old_result = original;
        var fresh_result = fresh;
        var inputs: usize = 1;
        if (binding.capability_parameters.inputInvokes()) inputs = binding.capability_parameters.argumentCount();
        for (0..inputs) |_| {
            const old_arrow = self.types.node(try self.types.resolve(old_result, 0));
            const fresh_arrow = self.types.node(try self.types.resolve(fresh_result, 0));
            if (old_arrow.tag != .function or fresh_arrow.tag != .function) return error.TypeMismatch;
            old_result = old_arrow.b;
            fresh_result = fresh_arrow.b;
        }
        if (!try self.types.equalSymbolic(old_result, try self.types.resolve(result, 0))) return error.TypeMismatch;
        return fresh_result;
    }
    fn generationVersion(self: *Engine, source: ast.Id) T.Error!T.Id {
        const point = self.tree.span(source).end + 1;
        var ordinal: u32 = 0;
        // Nested argument blocks can end at their caller's source endpoint.
        // Keep each creation distinct; imported binder copies reserve no slot.
        for (self.generative_bindings.items) |binder| {
            if (binder.owner == 0) continue;
            const scope = self.types.node(self.types.head(binder.selection, 0));
            if (scope.tag != .scoped or scope.b != 0) continue;
            const term = self.types.node(scope.c);
            if (term.tag != .instance_selection) continue;
            const choices = self.types.nominalArguments(term);
            if (choices.len != 3) continue;
            const version = self.types.node(choices[2]);
            if (version.a == self.unit and version.b == point) ordinal = @max(ordinal, version.c + 1);
        }
        return self.types.instanceVersion(.{ .unit = self.unit, .decl = point }, ordinal);
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
    fn evidenceCall(self: *Engine, source: ast.Id, depth: usize) T.Error!bool {
        if (self.implementations.items.len == 0) return false;
        if (depth >= 256 or !try self.associatedStep(source)) return error.TypeLimit;
        const node = self.tree.node(source);
        if (node.tag == .apply or node.tag == .group) return self.evidenceCall(node.a, depth + 1);
        const binding = self.resolved[source];
        if (binding == 0) return false;
        return self.evidenceScheme(binding, depth);
    }
    fn evidenceScheme(self: *Engine, binding: BindingId, depth: usize) T.Error!bool {
        if (depth >= 256 or !try self.associatedStep(self.bindings.items[binding].declaration)) return error.TypeLimit;
        const principal = self.bindings.items[binding].scheme;
        for (self.obligations.items[principal.obligations.start..][0..principal.obligations.len]) |predicate| {
            if (predicate.kind == .contract or predicate.kind == .type_eq) return true;
            if (predicate.kind == .callee_use and predicate.identity.unit == self.unit and try self.evidenceScheme(predicate.identity.decl, depth + 1)) return true;
        }
        return false;
    }
    fn checkArgument(self: *Engine, id: ast.Id, lazy: bool) T.Error!T.Id {
        if (!lazy) {
            const actual = try self.expression(id);
            if (!self.exact_argument_types) return actual;
            var certified: std.ArrayList(u32) = .empty;
            defer certified.deinit(self.allocator);
            for (self.body_closed_rows.items) |decision| {
                if (!try self.associatedStep(id)) return actual;
                if (decision.owner == self.current) try certified.append(self.allocator, decision.variable);
            }
            // A known evidence input may use its lambda's recorded pure row.
            // Closing this copied type cannot change the executable ambient.
            return self.types.closeCovariant(try self.types.resolve(actual, 0), certified.items, &.{});
        }
        const saved_ambient = self.ambient;
        self.ambient = try self.types.freshEffects();
        defer self.ambient = saved_ambient;
        const latent = self.ambient;
        try self.row_sources.put(self.allocator, self.types.row(latent).tail.variable, id);
        const saved_loops = self.loop_stack;
        const saved_escape = self.suspended_loop_escape;
        self.loop_stack = .empty;
        self.suspended_loop_escape = saved_escape or saved_loops.items.len != 0;
        defer {
            self.loop_stack.deinit(self.allocator);
            self.loop_stack = saved_loops;
            self.suspended_loop_escape = saved_escape;
        }
        const saved_proof_owner = self.proof_owner;
        self.proof_owner = id;
        defer self.proof_owner = saved_proof_owner;
        const result = try self.expression(id);
        try self.certifyLambda(id, try self.types.functionWithEffects(T.unit, result, latent), saved_ambient);
        return self.types.demandWithEffects(result, latent);
    }
    fn demandCallee(self: *Engine, ty: T.Id) T.Error!bool {
        const node = self.types.node(try self.types.resolve(ty, 0));
        return node.tag == .function and self.types.node(self.types.head(node.a, 0)).tag == .demand;
    }
    fn binary(self: *Engine, id: ast.Id) T.Error!T.Id {
        const node = self.tree.node(id);
        const operator = self.pool.get(node.a);
        const declared = self.catalogs.overrides.get(node.a);
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
                if (self.catalogs.external_targets.get(external)) |binding| function_ty = try self.globalReference(binding, id);
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
        for (self.pending.items[start..]) |pending| if (pending.owner == self.current and pending.scope == self.qualification_scope and !pending.solved and !pending.covered and self.explicitRequirement(pending.value)) {
            explicit = true;
            break;
        };
        if (!explicit) return;
        var parts: std.ArrayList(T.Id) = .empty;
        defer parts.deinit(self.allocator);
        for (self.pending.items[start..]) |pending| {
            if (pending.owner != self.current or pending.scope != self.qualification_scope or pending.solved or pending.covered or (qualified and !pending.declared)) continue;
            parts.clearRetainingCapacity();
            try self.requirementParts(pending.value, &parts);
            for (parts.items) |part| {
                const values = try self.types.freeVariables(part);
                defer self.allocator.free(values);
                for (values) |variable| if (!inList(self.computed_variables.items, variable)) try self.computed_variables.append(self.allocator, variable);
                const rows = try self.types.freeRowVariables(part);
                defer self.allocator.free(rows);
                for (rows) |row| if (!inList(self.computed_rows.items, row)) try self.computed_rows.append(self.allocator, row);
            }
        }
    }
    fn requirementParts(self: *Engine, requirement: T.Obligation, output: *std.ArrayList(T.Id)) T.Error!void {
        if (requirement.kind == .callee_use) {
            const summary = self.bindings.items[requirement.identity.decl].summary;
            const product = self.types.node(try self.types.resolve(requirement.ty, 0));
            const instance = self.types.list(.{ .start = product.a, .len = product.b });
            for (instance[0..summary.public_variables.len], self.types.list(summary.requirement_variables)) |part, flag| if (flag != 0) try output.append(self.allocator, part);
            for (instance[summary.public_variables.len..], self.types.list(summary.requirement_rows)) |part, flag| if (flag != 0) try output.append(self.allocator, part);
        } else if (sourceRequirement(requirement.kind)) {
            for ([_]T.Id{ requirement.ty, requirement.other, requirement.result, requirement.signature }) |part| if (part != 0) try output.append(self.allocator, part);
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
    fn letStatement(self: *Engine, id: ast.Id) T.Error!Flow {
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
        var contextual: T.Id = 0;
        if (required != 0 and try @import("usage_check.zig").containsNominal(&self.types, self.nominals.items, required)) contextual = required;
        const inferred_value = try self.pureExpression(value_.value, contextual);
        if (required != 0) try self.constrain(inferred_value, required, id);
        // Preserve the written principal root while checking the RHS
        // with equations from this binding's own qualification.
        const value = if (required != 0) required else inferred_value;
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
        if (self.resolved[id] != 0 and self.tree.node(value_.pattern).tag == .pattern_name) {
            var operation_source = value_.value;
            while (self.tree.node(operation_source).tag == .group) operation_source = self.tree.node(operation_source).a;
            self.bindings.items[self.resolved[id]].operation_ref = self.operation_refs[operation_source];
            // Local introductions can follow this alias; imported
            // proof kinds can exist without any local proof syntax.
            if (self.tree.has_numeric_proofs or self.types.has_proof_kinds) self.proof_body.alias(self.allocator, self.resolved[id], value_.value) catch |err| {
                _ = try self.proofHeaderFailure(err, id);
            };
        }
        self.expr_types[id] = if (exits) T.never else T.unit;
        return .{ .exits = exits, .breaks = exits };
    }
    /// A nested do: keeps its own scope (issue #11): only if/if let, loops and
    /// the do: arms of a statement case carry a rebinding outward. A := of an
    /// enclosing name none of whose versions made in the block is ever read,
    /// including versions inside its branches, therefore changes nothing, so
    /// it is rejected. Names below `carried` leave a carrying case arm.
    fn deadRebindings(self: *Engine, scope: usize, first_binding: usize, carried: usize) T.Error!void {
        for (self.env.items[scope..], scope..) |entry, index| {
            if (entry.name == self.self_name) continue;
            const binding = self.bindings.items[entry.binding];
            if (binding.predecessor == 0 or binding.read) continue;
            const last = for (self.env.items[index + 1 ..]) |next| {
                if (next.name == entry.name) break false;
            } else true;
            if (!last) continue;
            var root = binding.predecessor;
            const enclosing = for (0..64) |_| {
                if (root == 0) break false;
                if (for (self.env.items[carried..scope]) |prior| {
                    if (prior.binding == root) break true;
                } else false) break true;
                root = self.bindings.items[root].predecessor;
            } else false;
            if (!enclosing) continue;
            const read = for (self.bindings.items[first_binding..]) |version| {
                if (version.name == entry.name and version.read) break true;
            } else false;
            if (!read) try self.diagnostic(.dead_rebinding, binding.declaration);
        }
    }
    fn rebindStatement(self: *Engine, id: ast.Id) T.Error!Flow {
        const node = self.tree.node(id);
        if (self.tree.node(node.a).tag != .name) return self.rebindFields(id);
        const name = self.tree.node(node.a).a;
        const previous = self.lookup(name) orelse {
            try self.diagnostic(.unknown_rebinding, id);
            return .{};
        };
        const scope = self.env.items.len;
        try self.env.append(self.allocator, .{ .name = self.self_name, .binding = previous });
        const value = try self.pureExpression(node.b, 0);
        self.env.shrinkRetainingCapacity(scope);
        const binding = try self.local(name, value, id);
        self.bindings.items[binding].predecessor = previous;
        self.resolved[id] = binding;
        self.resolved[node.a] = previous;
        self.expr_types[node.a] = self.bindings.items[previous].ty;
        const exits = try self.types.resolve(value, 0) == T.never;
        self.expr_types[id] = if (exits) T.never else T.unit;
        return .{ .exits = exits, .breaks = exits };
    }
    fn returnStatement(self: *Engine, id: ast.Id) T.Error!Flow {
        const node = self.tree.node(id);
        // A return directly in a statement case arm ends the arm like falling
        // off its end. One nested below it would skip the arm's merge.
        if (self.arm_block != 0 and self.owner == self.arm_block and self.arm_nested_return == 0 and std.mem.findScalar(ast.Id, self.tree.children(self.arm_block), id) == null) self.arm_nested_return = id;
        if (self.request_scope.invalid_outer_return and self.owner == self.request_scope.return_scope) {
            try self.diagnostic(.invalid_return, id);
            return .{ .exits = true, .returns = true };
        }
        var value: T.Id = undefined;
        if (self.return_target != 0 and self.types.node(self.types.head(self.return_target, 0)).tag == .erased_proof) {
            value = try self.contextualLambda(node.a, self.return_target);
        } else value = try self.expression(node.a);
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
    }
    fn functionReturnStatement(self: *Engine, id: ast.Id) T.Error!Flow {
        const value = try self.expression(self.tree.node(id).a);
        if (!self.function_exit_allowed) {
            try self.diagnostic(.return_outside_function, id);
        } else {
            if (self.function_exit_target == 0) self.function_exit_target = try self.types.fresh();
            try self.constrain(self.function_exit_target, value, id);
            if (self.resolver_scope.block != 0) {
                try self.diagnostic(.return_across_continuation, id);
            } else if (self.request_scope.loop != 0 and !self.request_scope.completion) {
                if (self.owner == self.request_scope.return_scope and self.function_body == self.owner) {
                    try self.request_controls.append(self.allocator, .{ .node = id, .loop = self.request_scope.loop, .kind = .cancel, .value_type = value, .target_scope = self.owner });
                } else try self.diagnostic(.return_across_continuation, id);
            }
        }
        self.expr_types[id] = T.never;
        return .{ .ty = T.never, .exits = true, .breaks = true };
    }
    fn useStatement(self: *Engine, id: ast.Id) T.Error!Flow {
        const node = self.tree.node(id);
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
    }
    fn statement(self: *Engine, id: ast.Id) T.Error!Flow {
        const node = self.tree.node(id);
        switch (node.tag) {
            .let_stmt => return self.letStatement(id),
            .rebind_stmt => return self.rebindStatement(id),
            .return_stmt => return self.returnStatement(id),
            .function_return_stmt => return self.functionReturnStatement(id),
            .use_stmt, .iterator_bind => return self.useStatement(id),
            .forever_stmt, .range_stmt, .for_stmt => return self.loopStatement(id),
            .break_stmt => return self.breakStatement(id),
            .continue_stmt => return self.continueStatement(id),
            .yield_stmt => return self.requestReply(id),
            .if_stmt, .if_let_stmt => return self.conditional(id),
            .case_expr => return self.caseStatement(id),
            else => {
                const ty = try self.expression(id);
                const exits = self.types.node(try self.types.resolve(ty, 0)).tag == .never;
                return .{ .exits = exits, .breaks = exits };
            },
        }
    }
    fn caseStatement(self: *Engine, id: ast.Id) T.Error!Flow {
        const saved = self.statement_case;
        self.statement_case = id;
        defer self.statement_case = saved;
        const ty = try self.expression(id);
        const exits = self.types.node(try self.types.resolve(ty, 0)).tag == .never;
        return .{ .exits = exits, .breaks = exits };
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
            direct_exit = direct_exit or tag == .return_stmt or tag == .function_return_stmt or tag == .break_stmt or tag == .continue_stmt or tag == .yield_stmt;
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
                try self.request_arms.append(self.allocator, .{ .node = arm_id, .loop = id, .operation_source = arm.a, .operation = self.types.list(handled)[signature_index - 1], .parameter_type = function.a, .reply_type = function.b, .signature = signature, .pattern = arm.b, .suite = arm.c, .state_bindings = state_bindings });
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
        return self.loopExitStatement(id, false);
    }
    fn continueStatement(self: *Engine, id: ast.Id) T.Error!Flow {
        return self.loopExitStatement(id, true);
    }
    fn loopExitStatement(self: *Engine, id: ast.Id, continues: bool) T.Error!Flow {
        self.expr_types[id] = T.never;
        if (self.loop_stack.items.len == 0) {
            try self.diagnostic(if (self.suspended_loop_escape) .invalid_return else if (continues) .continue_scope else .break_scope, id);
            return .{ .exits = true, .breaks = true };
        }
        const frame_index = self.loop_stack.items.len - 1;
        const frame = self.loop_stack.items[frame_index];
        if (continues and self.request_scope.loop == frame.node) {
            try self.diagnostic(.invalid_return, id);
            return .{ .exits = true, .breaks = true };
        }
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
        if (continues and nested_resolver) {
            try self.diagnostic(.invalid_return, id);
            return .{ .exits = true, .breaks = true };
        }
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
        if (!continues) self.loop_stack.items[frame_index].exits += 1;
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
        return self.solveFieldsFrom(0);
    }
    /// Solves obligations at or after `start` to a fixpoint. A shared use
    /// expands at its own chronological position, when its instantiation is
    /// informative enough to resolve.
    fn solveFieldsFrom(self: *Engine, start: usize) T.Error!void {
        // Ready work runs in index order. A write wakes later work in this pass
        // and earlier work in the next, as a full scan would retry it. An
        // effect operation sleeps on its argument and signature types, an
        // open use of a settled callee on its instance types, and a member or
        // operator on the unknown type that blocks selection. Other checks
        // are retried each pass.
        var progress = true;
        while (progress) {
            progress = false;
            var cursor: usize = start;
            while (true) {
                // Yield to the heap driver before retrying a field whose
                // selected body is queued. Its result remains an ordinary
                // obligation until the dependency has an inferred signature.
                if (self.selected_globals.items.len != 0) return;
                try self.syncPendingQueue();
                const i = self.pending_queue.take(cursor) orelse break;
                cursor = i + 1;
                const pending = self.pending.items[i];
                if (pending.solved) {
                    self.pending_queue.complete(i);
                    continue;
                }
                if (pending.suspended) {
                    self.pending_queue.requeue(i);
                    continue;
                }
                if (pending.wait_target != 0) {
                    // A child's local scheme can invoke this solver while its
                    // body is still active. Do not turn this caller's waited-on
                    // field into that child's recursive receiver placeholder.
                    if (self.global_states.get(pending.wait_target).?.state != .complete) {
                        self.pending_queue.requeue(i);
                        continue;
                    }
                    self.pending.items[i].wait_target = 0;
                }
                if (try self.attemptPending(i, pending)) progress = true;
                try self.syncPendingQueue();
                if (i >= self.pending.items.len) continue;
                const after = self.pending.items[i];
                if (after.solved) {
                    self.pending_queue.complete(i);
                } else if (after.value.kind == .effect_operation and !after.suspended) {
                    try self.pending_queue.watch(self.allocator, &self.types, i, &.{ after.value.other, after.value.signature }, false, false);
                } else if (after.value.kind == .callee_use and !after.suspended and self.calleeSettled(after.value.identity.decl)) {
                    // An open use waits only on its instance types once the
                    // callee's summary can no longer change.
                    try self.pending_queue.watch(self.allocator, &self.types, i, &.{after.value.ty}, false, false);
                } else if (try self.pendingSelectionInput(after)) |input| {
                    try self.pending_queue.watch(self.allocator, &self.types, i, &.{input}, false, false);
                } else self.pending_queue.requeue(i);
            }
        }
    }
    fn pendingSelectionInput(self: *Engine, pending: PendingObligation) T.Error!?T.Id {
        if (pending.suspended) return null;
        const input = switch (pending.value.kind) {
            .field, .writable_field, .dispatch => pending.value.ty,
            .result_dispatch => pending.value.result,
            else => return null,
        };
        // attemptPending returns before selecting any body while this head
        // is unknown. Only a write to this variable can make it proceed.
        if (self.types.node(try self.types.resolve(input, 0)).tag != .variable) return null;
        return input;
    }
    fn calleeSettled(self: *const Engine, binding: BindingId) bool {
        if (binding >= self.bindings.items.len) return false;
        if (self.bindings.items[binding].kind == .external) return true;
        const state = self.global_states.get(binding) orelse return false;
        return state.state == .complete and !state.on_stack;
    }
    /// Mirrors the pending list in the work queue: new obligations are ready,
    /// and a list shrunk by rollback drops its stale entries and watches.
    fn syncPendingQueue(self: *Engine) T.Error!void {
        self.pending_queue.truncate(self.pending.items.len);
        while (self.pending_queue.entries.items.len < self.pending.items.len) try self.pending_queue.add(self.allocator, true);
        self.pending_queue.observe(&self.types);
    }
    /// One attempt at a pending obligation; true when it made progress.
    fn attemptPending(self: *Engine, i: usize, pending: PendingObligation) T.Error!bool {
        var progress = false;
        const saved_owner = self.dependency_owner;
        self.dependency_owner = pending.owner;
        defer self.dependency_owner = saved_owner;
        try self.inferenceTransition();
        const constraint = pending.value;
        if (constraint.kind == .callee_use) {
            if (try self.resolveUse(i)) progress = true;
            return progress;
        }
        if (constraint.kind == .record_merge) {
            const result = self.types.mergeRecords(constraint.ty, constraint.other) catch |err| switch (err) {
                error.TypeMismatch => {
                    try self.diagnostic(.type_mismatch, constraint.source);
                    self.pending.items[i].solved = true;
                    progress = true;
                    return progress;
                },
                else => return err,
            };
            if (result) |ty| {
                try self.constrain(ty, constraint.result, constraint.source);
                self.pending.items[i].solved = true;
                progress = true;
            }
            return progress;
        }
        if (constraint.kind == .type_eq) {
            if (try self.requirementOpen(constraint)) return progress;
            try self.constrain(constraint.ty, constraint.result, constraint.source);
            self.pending.items[i].solved = true;
            return true;
        }
        if (constraint.kind == .contract) {
            const root = self.types.node(self.types.head(constraint.ty, 0));
            if (root.tag != .product) return progress;
            if (try self.selectImplementation(constraint.identity, self.types.list(.{ .start = root.a, .len = root.b }), constraint.source)) |_| {
                self.pending.items[i].solved = true;
                return true;
            }
            return progress;
        }
        if (constraint.kind == .collection) {
            const owner = self.types.node(try self.types.resolve(constraint.ty, 0));
            if (owner.tag == .variable or owner.tag == .projection) return progress;
            if (owner.tag == .array or owner.tag == .list) {
                try self.constrain(owner.a, constraint.result, constraint.source);
            } else try self.diagnostic(.type_mismatch, constraint.source);
            self.pending.items[i].solved = true;
            progress = true;
            return progress;
        }
        if (constraint.kind == .monad_factory) {
            const token = self.types.node(try self.types.resolve(constraint.ty, 0));
            if (token.tag == .variable) return progress;
            if (token.tag != .type_constructor) try self.diagnostic(.type_constructor_required, constraint.source);
            self.pending.items[i].solved = true;
            progress = true;
            return progress;
        }
        if (constraint.kind == .resolver_dispatch) {
            self.pending.items[i].suspended = true;
            const selected = try self.resolverDispatch(pending);
            self.pending.items[i].suspended = false;
            if (selected) {
                self.pending.items[i].solved = true;
                progress = true;
            }
            return progress;
        }
        if (constraint.kind == .type_head) {
            const head = try self.witnessResult(constraint.ty);
            if (self.types.node(try self.types.resolve(head, 0)).tag == .variable) return progress;
            try self.constrain(head, constraint.result, constraint.source);
            self.pending.items[i].solved = true;
            progress = true;
            return progress;
        }
        if (constraint.kind == .effect_handler) {
            const extended = self.types.node(try self.types.resolve(constraint.signature, 0));
            const residual = self.types.node(try self.types.resolve(constraint.other, 0));
            if (extended.tag != .function or residual.tag != .function) return error.TypeLimit;
            if (try self.handlerEquation(constraint.ty, extended.c, residual.c, constraint.source)) {
                self.pending.items[i].solved = true;
                progress = true;
            }
            return progress;
        }
        if (constraint.kind == .effect_operation) {
            const arguments = try self.types.resolve(constraint.other, 0);
            if (!try self.types.equalClosed(arguments, arguments)) return progress;
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
            return progress;
        }
        if (constraint.kind == .resolver_shape) {
            const owner = self.types.node(try self.types.resolve(constraint.ty, 0));
            if (owner.tag == .variable or owner.tag == .projection) return progress;
            if (owner.tag != .resolver) {
                try self.diagnostic(.invalid_provider, constraint.source);
            } else {
                const token = self.types.node(try self.types.resolve(owner.a, 0));
                if (token.tag == .variable) return progress;
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
            return progress;
        }
        if (constraint.kind == .update) {
            if (try self.updatedFieldType(constraint.ty, constraint.name, constraint.other, constraint.source)) |updated| {
                try self.constrain(constraint.result, updated, constraint.source);
                self.pending.items[i].solved = true;
                progress = true;
            }
            return progress;
        }
        if (constraint.kind != .field and constraint.kind != .writable_field and constraint.kind != .dispatch and constraint.kind != .result_dispatch) return progress;
        const saved_ambient = self.ambient;
        if (constraint.signature != 0) self.ambient = self.types.node(try self.types.resolve(constraint.signature, 0)).c;
        defer self.ambient = saved_ambient;
        const owner = try self.types.resolve(if (constraint.kind == .result_dispatch) constraint.result else constraint.ty, 0);
        if (self.types.node(owner).tag == .variable or self.types.node(owner).tag == .projection) return progress;
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
            const diagnostics = self.diagnostics.items.len;
            try self.constrain(constraint.result, result, constraint.source);
            if (constraint.kind == .dispatch and self.diagnostics.items.len != diagnostics and self.dispatch_side != .builtin)
                try self.explainSelected(owner, constraint.other, constraint.name, constraint.operator, self.dispatch_side);
            self.pending.items[i].solved = true;
            progress = true;
        }
        return progress;
    }
    /// Resolves one shared scheme use. It stays a use while every observable
    /// variable is still open. Once some are closed and the rest are plain
    /// variables, the callee's closed outcome is a function of the closed
    /// parts and is computed at most once per key. Any other shape expands the
    /// callee's obligations in place, as an ordinary instantiation would.
    fn resolveUse(self: *Engine, index: usize) T.Error!bool {
        const use = self.pending.items[index];
        const callee = self.bindings.items[use.value.identity.decl];
        const product = self.types.node(try self.types.resolve(use.value.ty, 0));
        const instance = try self.allocator.dupe(T.Id, self.types.list(.{ .start = product.a, .len = product.b }));
        defer self.allocator.free(instance);
        const type_count = callee.summary.public_variables.len;
        var key: std.ArrayList(u8) = .empty;
        defer key.deinit(self.allocator);
        try key.appendSlice(self.allocator, std.mem.asBytes(&use.value.identity.decl));
        var open: std.ArrayList(usize) = .empty;
        defer open.deinit(self.allocator);
        var seen_types: std.ArrayList(u32) = .empty;
        defer seen_types.deinit(self.allocator);
        var seen_rows: std.ArrayList(u32) = .empty;
        defer seen_rows.deinit(self.allocator);
        const inputs = self.types.list(callee.summary.public_inputs);
        var input_open = false;
        var input_partial = false;
        var plain = true;
        for (instance, 0..) |item, position| {
            if (position < type_count) {
                const value = self.types.node(item);
                const input = inputs[position] != 0;
                if (value.tag == .variable) {
                    if (input) input_open = true;
                    if (inList(seen_types.items, value.a)) plain = false else try seen_types.append(self.allocator, value.a);
                    try open.append(self.allocator, position);
                    try key.append(self.allocator, 0);
                } else {
                    try key.append(self.allocator, 1);
                    if (!try self.closedKey(item, &key, 0)) {
                        plain = false;
                        if (input) input_partial = true;
                    }
                }
            } else {
                const row = try self.types.resolveEffects(self.types.node(item).c, 0);
                const value = self.types.row(row);
                if (value.tail == .variable and value.labels.len == 0) {
                    if (inList(seen_rows.items, value.tail.variable)) plain = false else try seen_rows.append(self.allocator, value.tail.variable);
                    try open.append(self.allocator, position);
                    try key.append(self.allocator, 0);
                } else {
                    try key.append(self.allocator, 1);
                    if (!try self.closedRowKey(row, &key, 0)) plain = false;
                }
            }
        }
        if (callee.summary.only_result_selected) {
            var result_ready = true;
            for (self.types.list(callee.summary.public_outputs), instance[0..type_count]) |output, actual| if (output != 0 and !try self.types.equalClosed(actual, actual)) {
                result_ready = false;
                break;
            };
            // Only a fixed destination can infer an input for this class of
            // schemes. Keep unknown destinations as graph edges even when an
            // argument has already supplied a concrete type.
            if (!result_ready) return false;
            // With every public type and operation row already fixed, this
            // use has no frontend inference result to export. Preserve its
            // residual edge for mandatory Core checking instead of unfolding
            // the same closed diamond at the expansion-depth boundary.
            if (plain and open.items.len == 0) return false;
        } else if (!input_partial and input_open) return false;
        // Written requirements stay at their original reference until Core
        // checks them. With every public data type already closed there is no
        // frontend result inference to obtain by unfolding their graph.
        if (callee.summary.has_explicit and plain and !input_partial) {
            var data_closed = true;
            for (open.items) |position| if (position < type_count) {
                data_closed = false;
                break;
            };
            if (data_closed) return false;
        }
        self.counters.use_expansions += 1;
        if (input_partial or !plain or self.expansion_depth >= 64) {
            self.pending.items[index].solved = true;
            try self.expandUse(use, 0);
            return true;
        }
        if (self.callee_memo.get(key.items)) |outcome| {
            var matched = true;
            for (open.items, 0..) |position, slot| {
                if (position < type_count) {
                    if (outcome.types[slot] != unchanged_output) self.types.unify(instance[position], outcome.types[slot]) catch |err| switch (err) {
                        error.OutOfMemory, error.TypeLimit => return err,
                        else => matched = false,
                    };
                } else {
                    if (outcome.rows[slot] != unchanged_output) self.types.unifyEffects(self.types.node(instance[position]).c, outcome.rows[slot]) catch |err| switch (err) {
                        error.OutOfMemory, error.TypeLimit => return err,
                        else => matched = false,
                    };
                }
            }
            if (matched) {
                self.counters.memo_hits += 1;
                self.pending.items[index].solved = true;
                return true;
            }
            self.pending.items[index].solved = true;
            try self.expandUse(use, 0);
            return true;
        }
        self.expansion_serial += 1;
        const serial = self.expansion_serial;
        const start = self.pending.items.len;
        const diagnostics = self.diagnostics.items.len;
        self.pending.items[index].suspended = true;
        try self.expandUse(use, serial);
        self.expansion_depth += 1;
        defer self.expansion_depth -= 1;
        try self.solveFieldsFrom(start);
        self.pending.items[index].suspended = false;
        self.pending.items[index].solved = true;
        var complete = self.diagnostics.items.len == diagnostics and self.mark_depth == 0;
        if (complete) for (self.pending.items[start..]) |item| if (item.expansion >= serial and !item.solved) {
            complete = false;
            break;
        };
        const outcome_types = try self.allocator.alloc(T.Id, open.items.len);
        defer self.allocator.free(outcome_types);
        const outcome_rows = try self.allocator.alloc(T.Effects.Id, open.items.len);
        defer self.allocator.free(outcome_rows);
        // An output the callee left unconstrained stays a variable; it is
        // replayed as no change, provided no two outputs became one variable.
        seen_types.clearRetainingCapacity();
        seen_rows.clearRetainingCapacity();
        if (complete) for (open.items, 0..) |position, slot| {
            if (position < type_count) {
                const closed = try self.types.resolve(instance[position], 0);
                const shape = self.types.node(closed);
                if (shape.tag == .variable) {
                    if (inList(seen_types.items, shape.a)) {
                        complete = false;
                        break;
                    }
                    try seen_types.append(self.allocator, shape.a);
                    outcome_types[slot] = unchanged_output;
                } else if (try self.types.equalClosed(closed, closed)) {
                    outcome_types[slot] = closed;
                } else {
                    complete = false;
                    break;
                }
            } else {
                const row = try self.types.resolveEffects(self.types.node(instance[position]).c, 0);
                const shape = self.types.row(row);
                if (shape.tail == .variable and shape.labels.len == 0) {
                    if (inList(seen_rows.items, shape.tail.variable)) {
                        complete = false;
                        break;
                    }
                    try seen_rows.append(self.allocator, shape.tail.variable);
                    outcome_rows[slot] = unchanged_output;
                } else if (shape.tail == .closed) {
                    outcome_rows[slot] = row;
                } else {
                    complete = false;
                    break;
                }
            }
        };
        if (!complete) {
            self.counters.memo_declined += 1;
            return true;
        }
        if (self.callee_memo.contains(key.items)) return true;
        const owned_key = try self.allocator.dupe(u8, key.items);
        errdefer self.allocator.free(owned_key);
        const types_copy = try self.allocator.dupe(T.Id, outcome_types);
        errdefer self.allocator.free(types_copy);
        const rows_copy = try self.allocator.dupe(T.Effects.Id, outcome_rows);
        errdefer self.allocator.free(rows_copy);
        try self.callee_memo.put(self.allocator, owned_key, .{ .types = types_copy, .rows = rows_copy });
        self.counters.memo_misses += 1;
        return true;
    }
    /// Canonical bytes of a closed type, or false for a type that is open or
    /// has no canonical form. Equal bytes mean equal types.
    fn closedKey(self: *Engine, ty: T.Id, out: *std.ArrayList(u8), depth: usize) T.Error!bool {
        if (depth >= 256) return false;
        const value = self.types.node(try self.types.resolve(ty, 0));
        try out.append(self.allocator, @backingInt(value.tag));
        switch (value.tag) {
            .unit, .boolean, .u32, .f32, .never => return true,
            .function => {
                if (!try self.closedRowKey(try self.types.resolveEffects(value.c, 0), out, depth + 1)) return false;
                return try self.closedKey(value.a, out, depth + 1) and try self.closedKey(value.b, out, depth + 1);
            },
            .product => {
                try out.appendSlice(self.allocator, std.mem.asBytes(&value.b));
                for (self.types.list(.{ .start = value.a, .len = value.b })) |child| if (!try self.closedKey(child, out, depth + 1)) return false;
                return true;
            },
            .record => {
                try out.appendSlice(self.allocator, std.mem.asBytes(&value.b));
                const order = try self.allocator.alloc(usize, value.b);
                defer self.allocator.free(order);
                for (order, 0..) |*slot, at| slot.* = at;
                const Context = struct {
                    store: *const T.Store,
                    node: T.Node,
                    fn less(context: @This(), left: usize, right: usize) bool {
                        return context.store.recordField(context.node, left).name < context.store.recordField(context.node, right).name;
                    }
                };
                std.mem.sortUnstable(usize, order, Context{ .store = &self.types, .node = value }, Context.less);
                for (order) |at| {
                    const field = self.types.recordField(value, at);
                    try out.appendSlice(self.allocator, std.mem.asBytes(&field.name));
                    if (!try self.closedKey(field.ty, out, depth + 1)) return false;
                }
                return true;
            },
            .nominal => {
                try out.appendSlice(self.allocator, std.mem.asBytes(&value.a));
                try out.appendSlice(self.allocator, std.mem.asBytes(&value.b));
                const arguments = self.types.nominalArguments(value);
                try out.appendSlice(self.allocator, std.mem.asBytes(&arguments.len));
                for (arguments) |child| if (!try self.closedKey(child, out, depth + 1)) return false;
                return true;
            },
            .array, .list, .cursor, .resolver => return self.closedKey(value.a, out, depth + 1),
            .type_constructor => {
                try out.appendSlice(self.allocator, std.mem.asBytes(&value.a));
                try out.appendSlice(self.allocator, std.mem.asBytes(&value.b));
                return true;
            },
            else => return false,
        }
    }
    fn closedRowKey(self: *Engine, row: T.Effects.Id, out: *std.ArrayList(u8), depth: usize) T.Error!bool {
        const value = self.types.row(row);
        if (value.tail != .closed) return false;
        const labels = self.types.rowLabels(row);
        try out.appendSlice(self.allocator, std.mem.asBytes(&labels.len));
        if (labels.len == 0) return true;
        const owned = try self.allocator.dupe(T.Effects.Label, labels);
        defer self.allocator.free(owned);
        var encoded: std.ArrayList([]u8) = .empty;
        defer {
            for (encoded.items) |item| self.allocator.free(item);
            encoded.deinit(self.allocator);
        }
        for (owned) |label| {
            var bytes: std.ArrayList(u8) = .empty;
            errdefer bytes.deinit(self.allocator);
            const operation = self.types.operation(label);
            try bytes.appendSlice(self.allocator, std.mem.asBytes(&operation.identity.unit));
            try bytes.appendSlice(self.allocator, std.mem.asBytes(&operation.identity.decl));
            try bytes.appendSlice(self.allocator, std.mem.asBytes(&operation.instance.unit));
            try bytes.appendSlice(self.allocator, std.mem.asBytes(&operation.instance.decl));
            for (self.types.operationArguments(label)) |argument| if (!try self.closedKey(argument, &bytes, depth + 1)) {
                bytes.deinit(self.allocator);
                return false;
            };
            try encoded.ensureUnusedCapacity(self.allocator, 1);
            encoded.appendAssumeCapacity(try bytes.toOwnedSlice(self.allocator));
        }
        std.mem.sortUnstable([]u8, encoded.items, {}, struct {
            fn less(_: void, left: []u8, right: []u8) bool {
                return std.mem.lessThan(u8, left, right);
            }
        }.less);
        for (encoded.items) |item| {
            try out.appendSlice(self.allocator, std.mem.asBytes(&item.len));
            try out.appendSlice(self.allocator, item);
        }
        return true;
    }
    /// A completed global keeps a shared use only while nothing about it is
    /// known. A use with any known part is expanded now, as flat instantiation
    /// would have, so its obligations are solved and checked in this module.
    fn expandInformedUses(self: *Engine, group: []const BindingId, recursive: bool) T.Error!void {
        var changed = true;
        while (changed) {
            changed = false;
            var i: usize = 0;
            while (i < self.pending.items.len) : (i += 1) {
                const item = self.pending.items[i];
                if (item.solved or item.suspended or item.value.kind != .callee_use or !inList(group, item.owner)) continue;
                const product = self.types.node(try self.types.resolve(item.value.ty, 0));
                const summary = self.bindings.items[item.value.identity.decl].summary;
                const type_count = summary.public_variables.len;
                if (!recursive and summary.only_result_selected) {
                    if (try self.resolveUse(i)) changed = true;
                    continue;
                }
                if (!recursive and summary.has_explicit) {
                    var closed = true;
                    for (self.types.list(.{ .start = product.a, .len = product.b })[0..type_count]) |part| if (!try self.types.equalClosed(part, part)) {
                        closed = false;
                        break;
                    };
                    if (closed) continue;
                }
                var informed = recursive;
                for (self.types.list(.{ .start = product.a, .len = product.b })[0..type_count]) |part| if (self.types.node(part).tag != .variable) {
                    informed = true;
                    break;
                };
                if (!informed) continue;
                self.pending.items[i].solved = true;
                self.counters.use_expansions += 1;
                try self.expandUse(item, 0);
                changed = true;
            }
            if (changed) try self.solveFields();
        }
    }
    pub fn sourceEditorProbe(self: *const Engine, id: ast.Id) bool {
        return self.editorAt(id);
    }
    fn editorAt(self: *const Engine, id: ast.Id) bool {
        const marker = self.editor_marker orelse return false;
        const span = self.tree.span(id);
        return span.start <= marker.span.start and span.end == marker.span.end;
    }
    fn isNamespace(self: *const Engine, name: symbols.Symbol) bool {
        inline for (.{ "qualified", "nominal_names", "constructor_names", "contract_names", "implementation_names", "effect_family_names", "effect_operation_names" }) |map| {
            var keys = @field(self.catalogs, map).keyIterator();
            while (keys.next()) |key| if (key.namespace == name) return true;
        }
        return false;
    }
    fn captureEditor(self: *Engine, id: ast.Id, receiver: T.Id, namespace: symbols.Symbol) T.Error!T.Id {
        if (self.editor_capture) |previous| if (previous.node == id and self.expr_types[id] != 0)
            return self.expr_types[id];
        var scope_bindings: [33]u32 = undefined;
        var scope_names: [33]u32 = undefined;
        var scope_count: usize = 0;
        var visible: std.ArrayList(u32) = .empty;
        defer visible.deinit(self.allocator);
        var visible_names: std.ArrayList(u32) = .empty;
        defer visible_names.deinit(self.allocator);
        var seen: std.AutoHashMapUnmanaged(symbols.Symbol, void) = .empty;
        defer seen.deinit(self.allocator);
        var truncated = false;
        var index = self.env.items.len;
        while (index != 0) {
            index -= 1;
            const entry = self.env.items[index];
            if (entry.name == 0) continue;
            const unique = try seen.getOrPut(self.allocator, entry.name);
            if (unique.found_existing) continue;
            if (scope_count < scope_bindings.len) {
                scope_bindings[scope_count] = entry.binding;
                scope_names[scope_count] = entry.name;
                scope_count += 1;
            }
            if (!std.mem.startsWith(u8, self.pool.get(entry.name), self.editor_marker.?.prefix)) continue;
            if (visible.items.len == 4096) {
                truncated = true;
                break;
            }
            try visible.append(self.allocator, entry.binding);
            try visible_names.append(self.allocator, entry.name);
        }
        var type_scope: std.ArrayList(u32) = .empty;
        defer type_scope.deinit(self.allocator);
        var type_index = self.type_env.items.len;
        while (type_index != 0) {
            type_index -= 1;
            const entry = self.type_env.items[type_index];
            try type_scope.appendSlice(self.allocator, &.{ entry.name, entry.ty });
        }
        const scope = try self.types.saveList(scope_bindings[0..scope_count]);
        try self.holes.append(self.allocator, .{ .node = id, .scope = scope, .owner = self.current });
        self.editor_capture = .{ .kind = self.editor_marker.?.kind, .node = id, .scope = scope, .scope_names = try self.types.saveList(scope_names[0..scope_count]), .visible = try self.types.saveList(visible.items), .visible_names = try self.types.saveList(visible_names.items), .type_scope = try self.types.saveList(type_scope.items), .truncated = truncated, .owner = self.current, .receiver = receiver, .namespace = namespace };
        return self.types.fresh();
    }
    fn holeScope(self: *Engine) T.Error!T.List {
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
        return self.types.saveList(scope[0..count]);
    }
    fn finishHoles(self: *Engine) T.Error!void {
        const display = @import("../reuse/type_display.zig");
        for (self.holes.items) |hole| {
            if (self.editor_capture) |*capture| if (capture.node == hole.node) {
                if (capture.context != null) continue;
                capture.names = try @import("../reuse/completion_names.zig").capture(self, capture, self.identityOf(capture.receiver));
                capture.context = try @import("../reuse/hole_diagnostics.zig").buildNamed(self, hole.node, hole.scope, hole.owner, self.types.list(capture.scope_names));
                continue;
            };
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
            self.diagnostics.items[self.diagnostics.items.len - 1].hole = try @import("../reuse/hole_diagnostics.zig").build(self, hole.node, hole.scope, hole.owner);
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
            if (pending.value.kind == .callee_use) continue;
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
                try self.explainResult(destination, pending.value.name);
                continue;
            }
            if (pending.value.kind == .dispatch) {
                try self.diagnostic(if (pending.value.name == 0) .ambiguous_operator else .missing_associated, pending.value.source);
                try self.explainDispatch(pending.value.ty, pending.value.other, pending.value.name, pending.value.operator, false);
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
        for (self.resolver_blocks.items) |*block| {
            block.result = try self.types.resolve(block.result, 0);
            block.body_effects = try self.types.resolveEffects(block.body_effects, 0);
        }
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

        for (self.effect_scopes.items) |*effect_scope| {
            effect_scope.capability = try self.types.resolve(effect_scope.capability, 0);
            effect_scope.result = try self.types.resolve(effect_scope.result, 0);
            effect_scope.body_effects = try self.types.resolveEffects(effect_scope.body_effects, 0);
            const capability = self.types.node(effect_scope.capability);
            const row = self.types.row(effect_scope.body_effects);
            if (row.tail != .closed) try self.diagnostic(.effect_identity_scope, effect_scope.node);
            for (self.types.rowLabels(effect_scope.body_effects)) |label| {
                const instance = self.types.operation(label).instance;
                if (instance.unit == capability.b and instance.decl == capability.c) try self.diagnostic(.effect_mismatch, effect_scope.node);
            }
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
        for (self.computations.items) |*computation| {
            computation.ty = try self.types.resolve(computation.ty, 0);
            computation.action_type = try self.types.resolve(computation.action_type, 0);
        }
        for (self.request_loops.items) |*request| {
            inline for (.{ "value_type", "result_type", "state_type", "action_type" }) |field| {
                @field(request, field) = try self.types.resolve(@field(request, field), 0);
            }
        }
        for (self.request_arms.items) |*arm| {
            inline for (.{ "parameter_type", "reply_type", "signature" }) |field| {
                @field(arm, field) = try self.types.resolve(@field(arm, field), 0);
            }
        }
        for (self.obligations.items) |*predicate| {
            predicate.ty = try self.types.resolve(predicate.ty, 0);
            if (predicate.result != 0) predicate.result = try self.types.resolve(predicate.result, 0);
            if (predicate.other != 0) predicate.other = try self.types.resolve(predicate.other, 0);
            if (predicate.signature != 0) predicate.signature = try self.types.resolve(predicate.signature, 0);
        }
        for (self.covered_requirements.items) |*requirement| {
            inline for (.{ "ty", "other", "result", "signature" }) |field| {
                if (@field(requirement.value, field) != 0) @field(requirement.value, field) = try self.types.resolve(@field(requirement.value, field), 0);
            }
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

const AuxiliaryReplay = struct {
    engine: *Engine,
    owner: *const @import("../reuse/body_auxiliary.zig").Owner,
    ids: []const ast.Id,
    bindings: []const BindingId,
    copier: *SchemeCopier,
    fields: []const symbols.Symbol,
    identities: *const std.AutoHashMapUnmanaged(Identity, Identity),
    operations: *const std.AutoHashMapUnmanaged(Identity, Identity),
    request_arms: u32,
    resolver_ops: u32,
    resolver_completions: u32,
    operation_uses: u32,
    pub fn map(self: *AuxiliaryReplay, comptime role: @import("../reuse/body_auxiliary.zig").Route, value: anytype) T.Error!@TypeOf(value) {
        switch (comptime role) {
            .proposition => return value,
            .nodes_pair => return .{ self.ids[value[0] - 1], self.ids[value[1] - 1] },
            .contract_identity => return self.identities.get(value) orelse error.TypeLimit,
            .operation_identity => return self.operations.get(value) orelse error.TypeLimit,
            .callee_identity => {
                if (value.unit != 0 or value.decl == 0 or value.decl > self.bindings.len) return error.TypeLimit;
                return .{ .unit = self.engine.unit, .decl = self.bindings[value.decl - 1] };
            },
            .scope => {
                if (value == 0) return 0;
                return self.copier.copyScope(value);
            },
            .instance => {
                if (value.unit == 0) return .{ .unit = 0, .decl = try self.copier.copy(value.decl, 0) };
                return self.copier.copyPhysical(value);
            },
            .node => {
                if (value == 0) return 0;
                return self.ids[value - 1];
            },
            .binding => {
                if (value == 0) return 0;
                return self.bindings[value - 1];
            },
            .ty => return self.copier.copy(value, 0),
            .row => return self.copier.copyRow(value, 0),
            .label => {
                if (value == 0) return 0;
                return self.copier.copyLabel(value, 0);
            },
            .name => {
                if (value == 0) return 0;
                return self.fields[value - 1];
            },
            .types, .bindings, .request_arms => {
                var elements: std.ArrayList(u32) = .empty;
                defer elements.deinit(self.engine.allocator);
                for (self.owner.list(value)) |element| {
                    const mapped = switch (comptime role) {
                        .types => try self.copier.copy(element, 0),
                        .bindings => self.bindings[element - 1],
                        .request_arms => self.request_arms + element - 1,
                        else => unreachable,
                    };
                    try elements.append(self.engine.allocator, mapped);
                }
                return self.engine.types.saveList(elements.items);
            },
            .resolver_ops => {
                if (value == 0) return 0;
                return self.resolver_ops + value;
            },
            .resolver_completions => {
                if (value == 0) return 0;
                return self.resolver_completions + value;
            },
            .carries => {
                if (value.len == 0) return .{};
                const current = self.engine.loop_ranges[self.ids[value.start - 1]];
                if (current.len != value.len) return error.TypeLimit;
                return current;
            },
            .template => {
                const identity = self.operations.get(.{ .unit = value, .decl = 0 }) orelse return error.TypeLimit;
                for (self.engine.effect_templates.items, 0..) |template, index| if (std.meta.eql(template.identity, identity)) return @intCast(index);
                return error.TypeLimit;
            },
            .constructor => {
                if (value == 0) return 0;
                const old = self.owner.constructors[value - 1];
                const identity = self.identities.get(old.nominal) orelse return error.TypeLimit;
                for (self.engine.constructors.items, 0..) |constructor, index| {
                    if (constructor.tag != old.tag or constructor.nominal >= self.engine.nominals.items.len) continue;
                    if (std.meta.eql(self.engine.nominals.items[constructor.nominal].identity, identity)) return @intCast(index);
                }
                return error.TypeLimit;
            },
            .proof => return switch (value) {
                .given => |given| .{ .given = try @import("../reuse/body_auxiliary.zig").mapRecord(given, self) },
                .selected => |index| blk: {
                    if (index >= self.owner.selections.len) return error.TypeLimit;
                    const selected = self.owner.selections[index];
                    var predicate = try @import("../reuse/body_auxiliary.zig").mapPredicate(selected.predicate, self);
                    if (selected.implementation) {
                        const arguments = try self.map(.types, selected.arguments);
                        predicate.ty = try self.engine.types.product(self.engine.types.list(arguments));
                    }
                    const proof = try self.engine.proveAndSavePredicate(&predicate, predicate.source) orelse return error.TypeMismatch;
                    break :blk .{ .selected = proof };
                },
            },
            else => return value,
        }
    }
};

const SchemeCopier = @import("check_scheme_import.zig").Copier;

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
        if (diagnostic.explanation) |explanation| explanation.deinit(allocator);
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
        target.explanation = null;
        initialized += 1;
        if (diagnostic.purity) |witness| target.purity = try witness.clone(allocator);
        if (diagnostic.detail) |detail| target.detail = try allocator.dupe(u8, detail);
        if (diagnostic.hole) |hole| target.hole = try hole.clone(allocator);
        if (diagnostic.explanation) |explanation| target.explanation = try explanation.clone(allocator);
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
    for (imports) |imported| try headers.append(allocator, .{ .name = imported.name, .namespace = imported.namespace, .member = imported.member, .target = imported.target, .capability_flow = imported.interface.capability_flow, .capability_parameters = imported.interface.capability_parameters, .named_function = imported.interface.named_function, .origin = imported.origin, .expose = imported.expose });
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
    contract_members: []ContractMember,
    implementations: []Implementation,
    implementation_predicates: []T.Obligation,
    implementation_members: []ImplementationMember,
    member_templates: []PI.MemberTemplate,
    selected_proofs: []PI.SelectedProof,
    selected_members: []ImplementationMember,
    selected_edges: []u32,
    selected_uses: []PI.SelectedUse,
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
        allocator.free(self.contract_members);
        allocator.free(self.implementations);
        allocator.free(self.implementation_predicates);
        allocator.free(self.implementation_members);
        allocator.free(self.member_templates);
        allocator.free(self.selected_proofs);
        allocator.free(self.selected_members);
        allocator.free(self.selected_edges);
        allocator.free(self.selected_uses);
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
        .contract_members = checked.contract_members,
        .implementations = checked.implementations,
        .implementation_predicates = checked.implementation_predicates,
        .implementation_members = checked.implementation_members,
        .member_templates = checked.member_templates,
        .selected_proofs = checked.selected_proofs,
        .selected_members = checked.selected_members,
        .selected_edges = checked.selected_edges,
        .selected_uses = checked.selected_uses,
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
    checked.contract_members = &.{};
    checked.implementations = &.{};
    checked.implementation_predicates = &.{};
    checked.implementation_members = &.{};
    checked.member_templates = &.{};
    checked.selected_proofs = &.{};
    checked.selected_members = &.{};
    checked.selected_edges = &.{};
    checked.selected_uses = &.{};
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
const BudgetExhaustion = struct { associated: bool = false, exhausted: bool = false, name: symbols.Symbol = 0, node: ast.Id = 0, span: ast.Span = .{ .start = 0, .end = 0 } };
fn checkInternalExecution(allocator: Allocator, tree: *const ast.Tree, pool: *symbols.Pool, imports: []const ImportedBinding, headers: []const SourceHeader, catalogs: []const ImportedCatalog, source_catalogs: []const SourceCatalog, unit: u32, allow_imports: bool, options: ModuleOptions, source_validation: bool, execution: PrivateExecution) !Checked {
    var exhaustion: BudgetExhaustion = .{};
    return checkEngine(allocator, tree, pool, imports, headers, catalogs, source_catalogs, unit, allow_imports, options, source_validation, execution, &exhaustion) catch |err| {
        if (err != error.TypeLimit or !exhaustion.exhausted) return err;
        return rejectExhaustedBudget(allocator, pool, unit, inferenceBudget(options), exhaustion);
    };
}
/// The partially inferred engine is gone; the module is rejected with one
/// diagnostic that names the budget and the declaration that exhausted it.
fn rejectExhaustedBudget(allocator: Allocator, pool: *const symbols.Pool, unit: u32, limit: usize, exhaustion: BudgetExhaustion) !Checked {
    const detail = if (exhaustion.name != 0)
        try allocator.print("Type inference exceeded this module's budget of {d} steps while checking `{s}`", .{ limit, pool.get(exhaustion.name) })
    else
        try allocator.print("Type inference exceeded this module's budget of {d} steps", .{limit});
    defer allocator.free(detail);
    var rejected = try rejectedSource(allocator, &.{.{ .code = if (exhaustion.associated) .associated_limit else .inference_budget, .span = exhaustion.span, .node = exhaustion.node, .symbol = exhaustion.name, .detail = detail }});
    rejected.unit = unit;
    return rejected;
}
// A shared teardown keeps each fallible checker step from cloning all earlier
// cleanups. Preserve reverse registration order, including scratch-pool lifetime.
noinline fn deinitEngine(engine: *Engine, published: bool) void {
    const allocator = engine.allocator;
    engine.merges.deinit(allocator);
    engine.obligations.deinit(allocator);
    {
        deinitDiagnosticPayloads(allocator, engine.diagnostics.items);
        engine.diagnostics.deinit(allocator);
    }
    engine.bindings.deinit(allocator);
    engine.computed_rows.deinit(allocator);
    engine.computed_variables.deinit(allocator);
    engine.predicate_origins.deinit(allocator);
    engine.declared_obligations.deinit(allocator);
    {
        var staged = engine.staged_global_diagnostics.valueIterator();
        while (staged.next()) |diagnostics| {
            deinitDiagnosticPayloads(allocator, diagnostics.*);
            allocator.free(diagnostics.*);
        }
        engine.staged_global_diagnostics.deinit(allocator);
    }
    engine.selected_globals.deinit(allocator);
    engine.forwarded_requirements.deinit(allocator);
    engine.qualification_uses.deinit(allocator);
    engine.qualifications.deinit(allocator);
    {
        var outcomes = engine.callee_memo.iterator();
        while (outcomes.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.types);
            allocator.free(entry.value_ptr.rows);
        }
        engine.callee_memo.deinit(allocator);
    }
    if (engine.pending_arena) |arena| {
        engine.pending.deinit(arena.allocator());
        engine.scratch_pool.give(arena);
    }
    engine.env.deinit(allocator);
    engine.active.deinit(allocator);
    engine.global_states.deinit(allocator);
    engine.projection_catalog.deinit(allocator);
    engine.constructors.deinit(allocator);
    engine.contract_states.deinit(allocator);
    engine.member_states.deinit(allocator);
    engine.member_sources.deinit(allocator);
    engine.active_predicates.deinit(allocator);
    engine.provisional_equations.deinit(allocator);
    engine.implementation_order.deinit(allocator);
    engine.active_evidence.deinit(allocator);
    engine.implementation_member_states.deinit(allocator);
    engine.implementation_member_sources.deinit(allocator);
    engine.implementation_bindings.deinit(allocator);
    engine.selected_uses.deinit(allocator);
    engine.selected_edges.deinit(allocator);
    engine.selected_members.deinit(allocator);
    engine.selected_proofs.deinit(allocator);
    engine.member_templates.deinit(allocator);
    engine.implementation_members.deinit(allocator);
    engine.implementation_predicates.deinit(allocator);
    engine.implementations.deinit(allocator);
    engine.contract_members.deinit(allocator);
    engine.contract_predicates.deinit(allocator);
    engine.contracts.deinit(allocator);
    engine.nominals.deinit(allocator);
    engine.associated.deinit(allocator);
    engine.cases.deinit(allocator);
    engine.computation_annotations.deinit(allocator);
    engine.row_env.deinit(allocator);
    engine.type_env.deinit(allocator);
    engine.storage_frames.deinit(allocator);
    engine.scope_lifetimes.deinit(allocator);
    engine.loop_stack.deinit(allocator);
    engine.statement_arms.deinit(allocator);
    engine.loop_exits.deinit(allocator);
    engine.loop_carries.deinit(allocator);
    engine.resolver_loops.deinit(allocator);
    engine.resolver_completions.deinit(allocator);
    engine.resolver_joins.deinit(allocator);
    engine.resolver_ops.deinit(allocator);
    engine.resolver_blocks.deinit(allocator);
    if (!published) {
        allocator.free(engine.resolver_loop_ids);
        allocator.free(engine.resolver_join_ids);
        allocator.free(engine.resolver_op_ids);
        allocator.free(engine.resolver_block_ids);
        allocator.free(engine.demand_binary_left);
        allocator.free(engine.demand_binary_left_types);
        allocator.free(engine.demand_types);
        allocator.free(engine.demand_once);
        allocator.free(engine.demand_calls);
        allocator.free(engine.iterator_bodies);
        allocator.free(engine.loop_ranges);
        allocator.free(engine.rebindings);
        allocator.free(engine.access_types);
        allocator.free(engine.access_nodes);
        allocator.free(engine.access_paths);
        allocator.free(engine.projection_resolved);
        allocator.free(engine.projections);
        allocator.free(engine.constructor_resolved);
        allocator.free(engine.resolved);
        allocator.free(engine.expr_types);
        allocator.free(engine.dispatch_signatures);
        allocator.free(engine.lambda_closed_rows);
    }
    engine.row_sources.deinit(allocator);
    engine.function_exit_lambdas.deinit(allocator);
    engine.closed_row_keys.deinit(allocator);
    engine.annotation_givens.deinit(allocator);
    engine.dictionary_givens.deinit(allocator);
    engine.dictionary_uses.deinit(allocator);
    engine.dictionary_selections.deinit(allocator);
    engine.rank_implementations.deinit(allocator);
    engine.covered_requirements.deinit(allocator);
    engine.body_closed_rows.deinit(allocator);
    engine.operation_uses.deinit(allocator);
    engine.effect_templates.deinit(allocator);
    engine.effect_families.deinit(allocator);
    if (!published) {
        allocator.free(engine.operation_refs);
    }
    engine.provider_blocks.deinit(allocator);
    engine.effect_runners.deinit(allocator);
    if (!published) {
        allocator.free(engine.effect_runner_ids);
        allocator.free(engine.provider_block_ids);
    }
    engine.effect_scopes.deinit(allocator);
    if (!published) {
        allocator.free(engine.effect_scope_ids);
    }
    engine.generative_bindings.deinit(allocator);
    engine.capability_roots.deinit(allocator);
    engine.capability_store.deinit(allocator);
    if (!published) {
        allocator.free(engine.tag_origins);
    }
    engine.request_controls.deinit(allocator);
    engine.request_arms.deinit(allocator);
    engine.request_loops.deinit(allocator);
    engine.computations.deinit(allocator);
    engine.reflections.deinit(allocator);
    if (!published) {
        engine.parameter_patterns.deinit(allocator);
    }
    {
        deinitDiagnosticPayloads(allocator, engine.source_header_diagnostics);
        allocator.free(engine.source_header_diagnostics);
    }
    engine.active_aliases.deinit(allocator);
    if (!published) {
        if (engine.editor_capture) |capture| {
            allocator.free(capture.names);
            if (capture.context) |context| context.deinit(allocator);
        }
    }
    engine.holes.deinit(allocator);
    {
        for (engine.proof_contracts.items) |*contract| contract.deinit(allocator);
        engine.proof_contracts.deinit(allocator);
    }
    engine.proof_body.deinit(allocator);
    if (!published) {
        engine.types.deinit();
    }
    engine.pending_queue.deinit(allocator);
    engine.usage_loans.deinit(allocator);
    engine.staging_bindings.deinit(allocator);
    engine.catalogs.deinit(allocator);
    engine.scratch_pool.deinit();
}

fn initializeEngineAccounting(engine: *Engine, options: ModuleOptions) void {
    // The proof store borrows the final Engine address after construction.
    engine.proof_body.values.account = &engine.proof_visits;
    engine.types.projection_limit = @min(1_000_000, inferenceBudget(options));
    if (options.associated_remaining) |remaining| engine.types.projection_limit = @min(engine.types.projection_limit, remaining.*);
}

fn checkEngine(allocator: Allocator, tree: *const ast.Tree, pool: *symbols.Pool, imports: []const ImportedBinding, headers: []const SourceHeader, catalogs: []const ImportedCatalog, source_catalogs: []const SourceCatalog, unit: u32, allow_imports: bool, options: ModuleOptions, source_validation: bool, execution: PrivateExecution, exhaustion: *BudgetExhaustion) !Checked {
    if (!source_validation and hasNumericFailure(tree)) return rejectNumericSource(allocator, tree, pool, imports, catalogs, unit, options);
    var engine: Engine = .{
        .body_source = options.body_source,
        .body_external_names = options.body_external_names,
        .previous_bodies = options.previous_bodies,
        .retained_bodies = options.retained_bodies,
        .editor_marker = options.editor,
        .budget_exhaustion = exhaustion,
        .scratch_pool = .init(allocator),
        .execution = execution,
        .inference_limit = inferenceBudget(options),
        .allocator = allocator,
        .tree = tree,
        .pool = pool,
        .has_tasks = @import("task_types.zig").present(pool),
        .types = try T.Store.initWithOptions(allocator, .{ .closed_graphs = true }),
        .expr_types = &.{},
        .resolved = &.{},
        .self_name = 0,
        .unit = unit,
        .builtin_catalog = options.builtin_catalog,
        .purity_origins = options.purity_origins,
        .source_validation = source_validation,
        .prelude_unit = options.prelude_unit,
        .producer_capabilities = options.producer_capabilities,
        .producer_storage = options.producer_storage,
    };
    // Publication transfers the direct owners to Checked. Drained lists and
    // temporary state stay with Engine, including during a partial publication.
    var published = false;
    defer deinitEngine(&engine, published);
    initializeEngineAccounting(&engine, options);

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

    engine.effect_scope_ids = try allocator.alloc(u32, tree.nodes.items.len);
    @memset(engine.effect_scope_ids, 0);
    engine.provider_block_ids = try allocator.alloc(u32, tree.nodes.items.len);
    @memset(engine.provider_block_ids, 0);
    engine.effect_runner_ids = try allocator.alloc(u32, tree.nodes.items.len);
    @memset(engine.effect_runner_ids, 0);
    engine.operation_refs = try allocator.alloc(u32, tree.nodes.items.len);
    @memset(engine.operation_refs, 0);
    engine.lambda_closed_rows = try allocator.alloc(T.List, tree.nodes.items.len);
    @memset(engine.lambda_closed_rows, .{});
    engine.dispatch_signatures = try allocator.alloc(T.Id, tree.nodes.items.len);
    @memset(engine.dispatch_signatures, 0);
    try engine.effect_families.append(allocator, .{ .identity = .{ .unit = 0, .decl = 0 }, .name = 0 });
    try engine.effect_templates.append(allocator, .{ .identity = .{ .unit = 0, .decl = 0 }, .family = 0, .name = 0, .parameter = 0, .result = 0 });
    engine.expr_types = try allocator.alloc(T.Id, tree.nodes.items.len);
    engine.resolved = try allocator.alloc(BindingId, tree.nodes.items.len);
    engine.constructor_resolved = try allocator.alloc(u32, tree.nodes.items.len);
    @memset(engine.constructor_resolved, 0);
    engine.projections = try allocator.alloc(u32, tree.nodes.items.len);
    @memset(engine.projections, std.math.maxInt(u32));
    engine.projection_resolved = try allocator.alloc(u32, tree.nodes.items.len);
    @memset(engine.projection_resolved, 0);
    engine.access_paths = try allocator.alloc(T.List, tree.nodes.items.len);
    @memset(engine.access_paths, .{});
    engine.access_nodes = try allocator.alloc(T.List, tree.nodes.items.len);
    @memset(engine.access_nodes, .{});
    engine.access_types = try allocator.alloc(T.List, tree.nodes.items.len);
    @memset(engine.access_types, .{});
    engine.rebindings = try allocator.alloc(Rebinding, tree.nodes.items.len);
    @memset(engine.rebindings, .{});
    engine.loop_ranges = try allocator.alloc(T.List, tree.nodes.items.len);
    @memset(engine.loop_ranges, .{});
    engine.iterator_bodies = try allocator.alloc(ast.Id, tree.nodes.items.len);
    @memset(engine.iterator_bodies, 0);
    engine.demand_calls = try allocator.alloc(bool, tree.nodes.items.len);
    @memset(engine.demand_calls, false);
    engine.demand_once = try allocator.alloc(bool, tree.nodes.items.len);
    @memset(engine.demand_once, false);
    engine.demand_types = try allocator.alloc(T.Id, tree.nodes.items.len);
    @memset(engine.demand_types, 0);
    engine.demand_binary_left_types = try allocator.alloc(T.Id, tree.nodes.items.len);
    @memset(engine.demand_binary_left_types, 0);
    engine.demand_binary_left = try allocator.alloc(bool, tree.nodes.items.len);
    @memset(engine.demand_binary_left, false);
    engine.resolver_block_ids = try allocator.alloc(u32, tree.nodes.items.len);
    @memset(engine.resolver_block_ids, 0);
    engine.resolver_op_ids = try allocator.alloc(u32, tree.nodes.items.len);
    @memset(engine.resolver_op_ids, 0);
    engine.resolver_join_ids = try allocator.alloc(u32, tree.nodes.items.len);
    @memset(engine.resolver_join_ids, 0);
    engine.resolver_loop_ids = try allocator.alloc(u32, tree.nodes.items.len);
    @memset(engine.resolver_loop_ids, 0);
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
    // Principal and body passes know their source binders before allocation.
    // Reserve once; additional imported or synthetic bindings can still grow.
    var binding_capacity: usize = imports.len + headers.len + 1;
    for (tree.nodes.items) |node| switch (node.tag) {
        .value_decl => binding_capacity += 1,
        .parameter, .pattern_name => if (!source_validation) {
            binding_capacity += 1;
        },
        else => {},
    };
    try engine.bindings.ensureTotalCapacityPrecise(allocator, binding_capacity);
    _ = try engine.addBinding(.{ .name = 0, .declaration = 0, .owner = 0, .kind = .local, .ty = 0 });
    for (tree.diagnostics.items) |diagnostic| try engine.diagnostics.append(allocator, .{ .code = .syntax, .span = .{ .start = diagnostic.start, .end = diagnostic.end }, .node = 0 });
    defer {
        if (options.associated_remaining) |remaining| remaining.* -= @min(remaining.*, engine.types.projection_steps);
        if (engine.types.projection_exhausted) {
            engine.exhaustBudget();
            exhaustion.associated = true;
        }
    }
    try engine.collectModuleHeaders(imports, headers, catalogs, source_catalogs, allow_imports, options.inherited_fixities);
    try engine.validateModuleBodies();
    // Direct owners move together; each following slice publication fills an
    // initially empty Checked field and leaves its Engine list empty.
    var checked: Checked = .{
        .editor = engine.editor_capture,
        .iterator_bodies = engine.iterator_bodies,
        .tag_origins = engine.tag_origins,
        .effect_scope_ids = engine.effect_scope_ids,
        .effect_runner_ids = engine.effect_runner_ids,
        .provider_block_ids = engine.provider_block_ids,
        .lambda_closed_rows = engine.lambda_closed_rows,
        .dispatch_signatures = engine.dispatch_signatures,
        .operation_refs = engine.operation_refs,
        .resolver_loop_ids = engine.resolver_loop_ids,
        .resolver_block_ids = engine.resolver_block_ids,
        .resolver_op_ids = engine.resolver_op_ids,
        .resolver_join_ids = engine.resolver_join_ids,
        .demand_calls = engine.demand_calls,
        .demand_once = engine.demand_once,
        .demand_types = engine.demand_types,
        .demand_binary_left_types = engine.demand_binary_left_types,
        .demand_binary_left = engine.demand_binary_left,
        .loop_ranges = engine.loop_ranges,
        .unit = unit,
        .constructor_resolved = engine.constructor_resolved,
        .projections = engine.projections,
        .access_paths = engine.access_paths,
        .access_nodes = engine.access_nodes,
        .access_types = engine.access_types,
        .projection_resolved = engine.projection_resolved,
        .rebindings = engine.rebindings,
        .types = engine.types,
        .parameter_patterns = engine.parameter_patterns,
        .expr_types = engine.expr_types,
        .resolved = engine.resolved,
        .bindings = &.{},
        .merges = &.{},
        .obligations = &.{},
        .diagnostics = &.{},
        .body_elaborations = engine.body_elaborations,
        .imported_schemes = if (source_validation) 0 else engine.catalogs.external_targets.count(),
        .counters = counters: {
            var counters = engine.counters;
            counters.inference_steps = engine.inference_transitions + engine.types.projection_steps;
            counters.associated_steps = engine.types.projection_steps;
            break :counters counters;
        },
    };
    published = true;
    errdefer checked.deinit(allocator);
    checked.function_exit_lambdas = try engine.function_exit_lambdas.toOwnedSlice(allocator);
    checked.computations = try engine.computations.toOwnedSlice(allocator);
    checked.request_loops = try engine.request_loops.toOwnedSlice(allocator);
    checked.request_arms = try engine.request_arms.toOwnedSlice(allocator);
    checked.request_controls = try engine.request_controls.toOwnedSlice(allocator);
    checked.reflections = try engine.reflections.toOwnedSlice(allocator);
    checked.bindings = try engine.bindings.toOwnedSlice(allocator);
    checked.diagnostics = try engine.diagnostics.toOwnedSlice(allocator);
    checked.obligations = try engine.obligations.toOwnedSlice(allocator);
    checked.nominals = try engine.nominals.toOwnedSlice(allocator);
    checked.contracts = try engine.contracts.toOwnedSlice(allocator);
    checked.contract_predicates = try engine.contract_predicates.toOwnedSlice(allocator);
    checked.contract_members = try engine.contract_members.toOwnedSlice(allocator);
    checked.implementations = try engine.implementations.toOwnedSlice(allocator);
    checked.implementation_predicates = try engine.implementation_predicates.toOwnedSlice(allocator);
    checked.implementation_members = try engine.implementation_members.toOwnedSlice(allocator);
    checked.member_templates = try engine.member_templates.toOwnedSlice(allocator);
    checked.selected_proofs = try engine.selected_proofs.toOwnedSlice(allocator);
    checked.selected_members = try engine.selected_members.toOwnedSlice(allocator);
    checked.selected_edges = try engine.selected_edges.toOwnedSlice(allocator);
    checked.selected_uses = try engine.selected_uses.toOwnedSlice(allocator);
    checked.constructors = try engine.constructors.toOwnedSlice(allocator);
    checked.projection_catalog = try engine.projection_catalog.toOwnedSlice(allocator);
    checked.associated = try engine.associated.toOwnedSlice(allocator);
    checked.loop_carries = try engine.loop_carries.toOwnedSlice(allocator);
    checked.loop_exits = try engine.loop_exits.toOwnedSlice(allocator);
    checked.statement_arms = try engine.statement_arms.toOwnedSlice(allocator);
    checked.resolver_blocks = try engine.resolver_blocks.toOwnedSlice(allocator);
    checked.resolver_ops = try engine.resolver_ops.toOwnedSlice(allocator);
    checked.resolver_joins = try engine.resolver_joins.toOwnedSlice(allocator);
    checked.resolver_completions = try engine.resolver_completions.toOwnedSlice(allocator);
    checked.resolver_loops = try engine.resolver_loops.toOwnedSlice(allocator);
    checked.effect_families = try engine.effect_families.toOwnedSlice(allocator);
    checked.effect_templates = try engine.effect_templates.toOwnedSlice(allocator);
    checked.operation_uses = try engine.operation_uses.toOwnedSlice(allocator);
    checked.effect_scopes = try engine.effect_scopes.toOwnedSlice(allocator);
    checked.effect_runners = try engine.effect_runners.toOwnedSlice(allocator);
    checked.provider_blocks = try engine.provider_blocks.toOwnedSlice(allocator);
    checked.dictionary_uses = try engine.dictionary_uses.toOwnedSlice(allocator);
    checked.dictionary_selections = try engine.dictionary_selections.toOwnedSlice(allocator);
    checked.rank_implementations = try engine.rank_implementations.toOwnedSlice(allocator);
    checked.body_closed_rows = try engine.body_closed_rows.toOwnedSlice(allocator);
    checked.covered_requirements = try engine.covered_requirements.toOwnedSlice(allocator);
    checked.merges = try engine.merges.toOwnedSlice(allocator);
    std.mem.sortUnstable(@import("capability_contracts.zig").Binding, engine.capability_roots.items, {}, struct {
        fn less(_: void, left: @import("capability_contracts.zig").Binding, right: @import("capability_contracts.zig").Binding) bool {
            return left.binding < right.binding;
        }
    }.less);
    if (engine.capability_roots.items.len != 0) {
        checked.capability_contracts.nodes = try engine.capability_store.nodes.toOwnedSlice(allocator);
        checked.capability_contracts.words = try engine.capability_store.words.toOwnedSlice(allocator);
        checked.capability_contracts.bindings = try engine.capability_roots.toOwnedSlice(allocator);
    }
    checked.proof_contracts = try engine.proof_contracts.toOwnedSlice(allocator);
    checked.proof_bodies = try engine.proof_body.take(allocator);
    checked.usage_loans = try engine.usage_loans.toOwnedSlice(allocator);
    checked.generative_bindings = try allocator.dupe(@import("generative_schemes.zig").Binder, engine.generative_bindings.items);

    if (!source_validation and engine.initializer_rejected) {
        var rejected = try rejectedSource(allocator, checked.diagnostics);
        rejected.initializer_rejected = true;
        rejected.unit = unit;
        checked.deinit(allocator);
        return rejected;
    }
    if (!source_validation and engine.editor_marker == null) if (engine.retained_bodies) |retained| {
        // Keep exact annotation resolution request-local. The completed facts
        // own only sparse recipe digests before this dictionary is released.
        @import("../reuse/body_check_cache.zig").captureIntoResolved(allocator, tree, pool, engine.body_source, &checked, engine.body_external_names, engine.bodyAnnotations(), retained) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
        };
    };
    return checked;
}

fn replayProofProposition(value: proof_terms.Proposition, mapping: []const u32) T.Error!proof_terms.Proposition {
    if (value.left == 0 or value.left > mapping.len or value.right == 0 or value.right > mapping.len) return error.TypeLimit;
    return .{ .relation = value.relation, .left = mapping[value.left - 1], .right = mapping[value.right - 1] };
}
