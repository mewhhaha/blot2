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
pub const Nominal = struct { identity: Identity, name: u32, parameters: T.List, variables: T.List, patterns: T.List = .{}, parameter_names: T.List = .{}, constructors: T.List = .{}, alias: T.Id = 0, alias_rows: T.List = .{} };
pub const Constructor = struct { identity: Identity, nominal: u32, tag: u32, name: u32, scheme: T.Scheme = .{}, payload: T.Id = 0, declared_record: bool = false };
pub const Associated = struct { identity: Identity, member: u32, operator: T.Operator, binding: u32 };
pub const EffectFamily = struct { identity: Identity, name: u32, callable: bool = false, parameters: T.List = .{}, variables: T.List = .{}, patterns: T.List = .{}, parameter_names: T.List = .{}, operations: T.List = .{} };
pub const EffectTemplate = struct { identity: Identity, family: u32, name: u32, parameter: T.Id, result: T.Id };
pub const Binding = struct { name: u32, kind: Kind, named_function: bool, ty: T.Id, scheme: T.Scheme, external: ?ExternalTarget };
/// A named, erased bundle of ordinary qualified predicates. Lists belong to
/// the interface type/pattern tables; predicates index contract_predicates.
pub const Contract = struct { identity: Identity, name: u32, parameters: T.List = .{}, variables: T.List = .{}, patterns: T.List = .{}, parameter_names: T.List = .{}, row_variables: T.List = .{}, predicates: T.List = .{} };
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
};
