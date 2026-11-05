// Body-free catalog payload. Every list names this interface's frozen tables.
namespace blot_reuse_principal_interface;
import check.types;
import check.frozen_types;
import check.capability_flow;
import check.capability_contracts;
import check.numeric_proof_headers;
import parse.ast;
import backend.opaque_storage;
import support.option;
type Identity = blot_check_types::NominalIdentity;
type List = blot_check_types::List;
type Id = blot_check_types::Id;
enum Kind { global, local, parameter, external }
struct ExternalTarget { unit: u32, binding: u32 }
struct Nominal {
    affine: bool = false, has_usage: bool = false, closed_storage: bool = false,
    private: bool = false, is_opaque: bool = false,
    storage: blot_backend_opaque_storage::Storage = blot_backend_opaque_storage::Storage {..},
    declaration: u32 = 0, identity: Identity, name: u32, parameters: List,
    variables: List, patterns: List = List {..}, parameter_names: List = List {..},
    constructors: List = List {..}, alias: Id = 0, alias_rows: List = List {..},
}
struct Constructor {
    private: bool = false, identity: Identity, nominal: u32, tag: u32, name: u32,
    scheme: blot_check_types::Scheme = blot_check_types::Scheme {..}, payload: Id = 0,
    declared_record: bool = false,
}
struct Associated { identity: Identity, member: u32, operator: blot_check_types::Operator, binding: u32 }
struct EffectFamily {
    private: bool = false, identity: Identity, name: u32, callable: bool = false,
    parameters: List = List {..}, variables: List = List {..}, patterns: List = List {..},
    parameter_names: List = List {..}, operations: List = List {..},
}
struct EffectTemplate { identity: Identity, family: u32, name: u32, parameter: Id, result: Id }
struct Binding {
    capability_flow: blot_check_capability_flow::Contract = blot_check_capability_flow::Contract.unknown,
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
struct SelectedUse { source: u32, proof: u32 }
enum SelectedProofKind { implementation, predicate }
struct SelectedProof {
    predicate_target: ExternalTarget = ExternalTarget { 0, 0 , ..}, context: u32 = 0,
    kind: SelectedProofKind = SelectedProofKind.implementation,
    predicate: blot_check_types::Obligation = blot_check_types::Obligation {
        ty: 0, kind: blot_check_types::ObligationKind.type_rep, source: 0,
     ..},
    implementation: Identity, contract: Identity, arguments: List, members: List, prerequisites: List,
}
struct Interface {
    has_rank_contracts: bool = false, has_usage_contracts: bool = false,
    has_numeric_proofs: bool = false, proof_contracts: const blot_check_numeric_proof_headers::Named[:],
    capability_contracts: blot_check_capability_contracts::Collection,
    unit: u32, graph: blot_check_frozen_types::Graph, patterns: blot_check_frozen_types::PatternGraph,
    bindings: const Binding[:], obligations: const blot_check_types::Obligation[:],
    obligation_spans: const blot_parse_ast::Span[:], nominals: const Nominal[:],
    constructors: const Constructor[:], effect_families: const EffectFamily[:],
    effect_templates: const EffectTemplate[:], associated: const Associated[:],
    contracts: const Contract[:], contract_predicates: const blot_check_types::Obligation[:],
    contract_members: const ContractMember[:], implementations: const Implementation[:],
    implementation_predicates: const blot_check_types::Obligation[:],
    implementation_members: const ImplementationMember[:], member_templates: const MemberTemplate[:],
    selected_proofs: const SelectedProof[:], selected_members: const ImplementationMember[:],
    selected_edges: const u32[:],
}
