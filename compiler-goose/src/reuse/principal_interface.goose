// Body-free catalog payload. Every list names this interface's frozen tables.
namespace blot_reuse_principal_interface;
import check.types;
import check.frozen_types;
import check.capability_flow;
import parse.ast;
import backend.opaque_storage;
import support.option;
type Identity = blot_check_types::NominalIdentity;
type List = blot_check_types::List;
type Id = blot_check_types::Id;
enum Kind { global, local, parameter, external }
struct ExternalTarget { unit: u32, binding: u32 }
fn hash(value:ExternalTarget)->u64 {return ::hash_combine(::hash(value.unit),::hash(value.binding));}
struct Nominal {
    affine: bool = false, has_usage: bool = false, closed_storage: bool = false,
    private: bool = false, is_opaque: bool = false,
    storage: blot_backend_opaque_storage::Storage = blot_backend_opaque_storage::Storage {..},
    declaration: u32 = 0, identity: Identity, name: u32, parameters: List,
    variables: List, patterns: List = List {..}, parameter_names: List = List {..},
    constructors: List = List {..}, alias: Id = 0, alias_rows: List = List {..},
}
// Only private worker packets use this reserved type ID for an origin reference.
let forwarded_constructor:u32=0xffffffff;
struct Constructor {
    private: bool = false, identity: Identity, nominal: u32, tag: u32, name: u32,
    scheme: blot_check_types::Scheme = blot_check_types::Scheme {..}, payload: Id = 0,
    declared_record: bool = false,
    // In a worker's checked module, scheme.root can hold the call parameter.
    // The result of this pure monomorphic constructor is its family.
    deferred_result: bool = false,
}
struct Associated { identity: Identity, member: u32, operator: blot_check_types::Operator, binding: u32 }
struct EffectFamily {
    private: bool = false, identity: Identity, name: u32, callable: bool = false,
    parameters: List = List {..}, variables: List = List {..}, patterns: List = List {..},
    parameter_names: List = List {..}, operations: List = List {..},
}
struct EffectTemplate { identity: Identity, family: u32, name: u32, parameter: Id, result: Id }
struct Binding {
    capability_parameters: blot_check_capability_flow::Parameters = blot_check_capability_flow::Parameters {..},
    private: bool = false, name: u32, kind: Kind, named_function: bool,
    ty: Id, scheme: blot_check_types::Scheme, external: blot_support::Option<ExternalTarget>,
}
enum ContractMemberKind { defined_type, abstract_type, value }
struct ContractMember { contract: Identity, name: u32, kind: ContractMemberKind, root: Id = 0 }
struct Contract {
    declaration: u32 = 0, private: bool = false, identity: Identity, name: u32,
    parameters: List = List {..}, variables: List = List {..}, patterns: List = List {..},
    parameter_names: List = List {..}, row_variables: List = List {..},
    row_parameter_names: List = List {..}, row_parameters: List = List {..},
    predicates: List = List {..}, members: List = List {..}, requires_implementation: bool = false,
}
struct Implementation {
    origin_span: blot_support::Option<blot_parse_ast::Span>, declaration: u32 = 0,
    private: bool = false, identity: Identity, name: u32, contract: Identity,
    head: List = List {..}, variables: List = List {..}, parameter_names: List = List {..},
    row_variables: List = List {..}, row_parameter_names: List = List {..},
    row_parameters: List = List {..}, predicates: List = List {..}, members: List = List {..},
}
enum ImplementationMemberKind { type_, value }
struct ImplementationMember {
    name: u32, kind: ImplementationMemberKind, root: Id = 0,
    target: ExternalTarget = ExternalTarget { 0, 0 , ..},
}
struct MemberTemplate { binding: u32, contract: Identity, name: u32, arguments: List }
struct Interface {
    unit: u32, graph: blot_check_frozen_types::Graph, patterns: blot_check_frozen_types::PatternGraph,
    bindings: const Binding[:], obligations: const blot_check_types::Obligation[:],
    nominals: const Nominal[:],
    constructors: const Constructor[:], effect_families: const EffectFamily[:],
    effect_templates: const EffectTemplate[:], associated: const Associated[:],
    contracts: const Contract[:], contract_predicates: const blot_check_types::Obligation[:],
    contract_members: const ContractMember[:], implementations: const Implementation[:],
    implementation_predicates: const blot_check_types::Obligation[:],
    implementation_members: const ImplementationMember[:], member_templates: const MemberTemplate[:],
}
