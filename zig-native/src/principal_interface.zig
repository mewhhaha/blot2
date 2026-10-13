//! Pointer-free principal catalog payload. Source bodies live in the separate
//! frozen Core module; imports consume these normalized semantic facts only.
const T = @import("types.zig");
const ast = @import("ast.zig");
const F = @import("frozen_types.zig");

pub const Identity = T.NominalIdentity;
pub const Kind = enum { global, local, parameter, external };
pub const ExternalTarget = struct { unit: u32, binding: u32 };
/// An alias participates in the same named type catalog, but expands to this
/// owned type root and never introduces a runtime nominal identity.
pub const Nominal = struct { private: bool = false, is_opaque: bool = false, storage: @import("opaque_storage.zig").Storage = .{}, declaration: u32 = 0, identity: Identity, name: u32, parameters: T.List, variables: T.List, patterns: T.List = .{}, parameter_names: T.List = .{}, constructors: T.List = .{}, alias: T.Id = 0, alias_rows: T.List = .{} };
pub const Constructor = struct { private: bool = false, identity: Identity, nominal: u32, tag: u32, name: u32, scheme: T.Scheme = .{}, payload: T.Id = 0, declared_record: bool = false };
pub const Associated = struct { identity: Identity, member: u32, operator: T.Operator, binding: u32 };
pub const EffectFamily = struct { private: bool = false, identity: Identity, name: u32, callable: bool = false, parameters: T.List = .{}, variables: T.List = .{}, patterns: T.List = .{}, parameter_names: T.List = .{}, operations: T.List = .{} };
pub const EffectTemplate = struct { identity: Identity, family: u32, name: u32, parameter: T.Id, result: T.Id };
pub const Binding = struct { capability_flow: @import("capability_flow.zig").Contract = .unknown, private: bool = false, name: u32, kind: Kind, named_function: bool, ty: T.Id, scheme: T.Scheme, external: ?ExternalTarget };
/// A named, erased bundle of ordinary qualified predicates. Lists belong to
/// the interface type/pattern tables; predicates index contract_predicates.
pub const ContractMember = struct { contract: Identity, name: u32, kind: enum { defined_type, abstract_type, value }, root: T.Id = 0 };
pub const Contract = struct { declaration: u32 = 0, private: bool = false, identity: Identity, name: u32, parameters: T.List = .{}, variables: T.List = .{}, patterns: T.List = .{}, parameter_names: T.List = .{}, row_variables: T.List = .{}, row_parameter_names: T.List = .{}, row_parameters: T.List = .{}, predicates: T.List = .{}, members: T.List = .{}, requires_implementation: bool = false };
/// All lists are owned type-table spans except members/predicates, which name
/// the corresponding flat catalog tables. Identities name original producers.
pub const Implementation = struct { origin_span: ?ast.Span = null, declaration: u32 = 0, private: bool = false, identity: Identity, name: u32, contract: Identity, head: T.List = .{}, variables: T.List = .{}, parameter_names: T.List = .{}, row_variables: T.List = .{}, row_parameter_names: T.List = .{}, row_parameters: T.List = .{}, predicates: T.List = .{}, members: T.List = .{} };
pub const ImplementationMember = struct { name: u32, kind: enum { type_, value }, root: T.Id = 0, target: ExternalTarget = .{ .unit = 0, .binding = 0 } };
pub const MemberTemplate = struct { binding: u32, contract: Identity, name: u32, arguments: T.List };
pub const SelectedUse = struct { source: u32, proof: u32 };
pub const SelectedProof = struct { predicate_target: ExternalTarget = .{ .unit = 0, .binding = 0 }, context: u32 = 0, kind: enum { implementation, predicate } = .implementation, predicate: T.Obligation = .{ .ty = 0, .kind = .type_rep, .source = 0 }, implementation: Identity, contract: Identity, arguments: T.List, members: T.List, prerequisites: T.List };
pub const Interface = struct {
    unit: u32,
    graph: F.Graph,
    patterns: F.PatternGraph,
    bindings: []Binding,
    obligations: []T.Obligation,
    obligation_spans: []ast.Span,
    nominals: []Nominal,
    constructors: []Constructor,
    effect_families: []EffectFamily,
    effect_templates: []EffectTemplate,
    associated: []Associated,
    contracts: []Contract = &.{},
    contract_predicates: []T.Obligation = &.{},
    contract_members: []ContractMember = &.{},
    implementations: []Implementation = &.{},
    implementation_predicates: []T.Obligation = &.{},
    implementation_members: []ImplementationMember = &.{},
    member_templates: []MemberTemplate = &.{},
    selected_proofs: []SelectedProof = &.{},
    selected_members: []ImplementationMember = &.{},
    selected_edges: []u32 = &.{},
};
