// Conditional input invocation reconstructs the actual callable before transfer.
namespace blot_check_capability_invocations;
import reuse.principal_interface;

import check.capability_contract_core;
import check.capability_contracts;
import check.capability_flow;
import check.capability_lifetimes;
import check.check_packet_owner;
import check.core;
import check.frozen_core_scopes;
import check.generative_relocation;
import check.types;
import support.error;
import support.option;

import .frozen_core_validation;
type ModuleRef = blot_check_frozen_core_validation::ModuleRef;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Id = blot_check_core::Id;
type Report = blot_check_capability_lifetimes::Report;
type Parameters = blot_check_capability_flow::Parameters;
struct Scope { root: Id, report: blot_support::Option<Report> }
struct Scan { module: const Module&, owners: const ModuleRef[:], graph: blot_check_frozen_core_validation::Graph, remaining: i64 = 65536, scopes: Scope[>..<]& }
fn deinit(self_: Scan&) { for &item in self_.scopes { if item.report.present { item.report.value.deinit(); } } self_.scopes.clear(); }
fn step(self_: Scan&, depth: i64) -> Error { if depth >= 128 || self_.remaining == 0 { return blot_error::Error.invalid_artifact; } self_.remaining -= 1; return blot_error::Error.none; }
fn owner(self_: const Scan&, unit: u32) -> const Module?, Error { if unit == 0 || unit == self_.module.unit { return self_.module, blot_error::Error.none; } for module_owner_ref in self_.owners { let module: const blot_check_core::Module&  = module_owner_ref.value; if module.unit == unit { return module, blot_error::Error.none; } } return null, blot_error::Error.invalid_artifact; }
fn stateReport(self_: Scan&, report: blot_support::Option<Report>, call: Id, contract: Parameters) -> bool, Error {
    if !report.present { return false, blot_error::Error.none; } let result, error = blot_check_capability_lifetimes::localStateInvocation(report.value, self_.module.unit, call, contract.callback(), contract.argumentAt(0), self_.remaining);
    if error == blot_error::Error.out_of_memory { return false, error; } if error != blot_error::Error.none { return false, blot_error::Error.invalid_artifact; } return result, blot_error::Error.none;
}
fn localStateStore(self_: Scan&, scope: Id, call: Id, contract: Parameters) -> bool, Error {
    if scope == 0 || contract.argumentCount() != 1 { return false, blot_error::Error.none; }
    for item in self_.scopes { let error = self_.step(0); if error != blot_error::Error.none { return false, error; } if item.root == scope { return stateReport(self_, item.report, call, contract); } }
    let report, error = blot_check_capability_lifetimes::analyzeScope(self_.module, self_.owners, scope, self_.remaining); var owned = blot_support::none<Report>();
    if error == blot_error::Error.out_of_memory { return false, error; } if error != blot_error::Error.none && error != blot_error::Error.unsupported { return false, blot_error::Error.invalid_artifact; } if error == blot_error::Error.none { owned = blot_support::some(report); }
    self_.scopes.push(Scope { scope, owned , ..}); return stateReport(self_, owned, call, contract);
}
recursive fn authority(self_: Scan&, id: Id, scoped: bool, depth: i64) -> bool, Error {
    let error = self_.step(depth); if error != blot_error::Error.none { return false, error; } if id == 0 || id >= self_.module.nodes.len { return false, blot_error::Error.invalid_artifact; } let n = self_.module.node(id); let ty = self_.module.types.node(n.ty);
    match ty.tag { scoped => { return true, blot_error::Error.none; }, unit, boolean, unsigned32, floating32, never => { return false, blot_error::Error.none; }, _ => {}, }
    match n.tag {
        reference => { let reference = self_.module.reference(id); if reference.unit != 0 && reference.unit != self_.module.unit { return scoped, blot_error::Error.none; } let binding = self_.module.bindings[reference.binding]; if binding.initializer != 0 { return authority(self_, binding.initializer, scoped, depth + 1); } return scoped, blot_error::Error.none; },
        product, record, array => { for child in self_.module.extra[n.a..n.a + n.b] { let result, error = authority(self_, child, scoped, depth + 1); if error != blot_error::Error.none || result { return result, error; } } return false, blot_error::Error.none; },
        construct => { if n.b == 0 { return false, blot_error::Error.none; } return authority(self_, n.b, scoped, depth + 1); },
        closure => { let closure = self_.module.closures[n.a]; for binding in self_.module.extra[closure.captures.start..closure.captures.start + closure.captures.len] { let capture = self_.module.bindings[binding]; if self_.module.types.node(capture.ty).tag == blot_check_types::Tag.scoped { return true, blot_error::Error.none; }
                if capture.initializer != 0 { let result, error = authority(self_, capture.initializer, scoped, depth + 1); if error != blot_error::Error.none || result { return result, error; } } if capture.initializer == 0 && scoped { return true, blot_error::Error.none; }
            } return false, blot_error::Error.none;
        },
        if_value => { let left, error = authority(self_, n.b, scoped, depth + 1); if error != blot_error::Error.none || left { return left, error; } return authority(self_, n.c, scoped, depth + 1); },
        _ => { return scoped, blot_error::Error.none; },
    }
}
struct CallableProof { module: const Module&, owners: const ModuleRef[:], node: Id, arity: u8, remaining: i64&, depth: i64, closure: bool }
fn proveCallable(context: CallableProof&, store: blot_check_capability_contracts::Store&) -> bool, Error {
    var root = blot_support::none<Id>(); var failure = blot_error::Error.none;
    if context.closure { let result, error = blot_check_capability_contract_core::deriveInputFunctionClosureWithOwners(store, context.module, context.module.closures[context.module.node(context.node).a], context.arity, context.owners); root = result; failure = error; }
    else { let result, error = blot_check_capability_contract_core::callableValue(store, context.module, context.node, context.owners); root = result; failure = error; }
    if failure == blot_error::Error.out_of_memory { return false, failure; } if failure != blot_error::Error.none || !root.present { return false, blot_error::Error.none; }
    if context.closure { return true, blot_error::Error.none; } let result, error = store.callableArity(root.value, context.arity, context.remaining, context.depth + 1); if error != blot_error::Error.none { return false, blot_error::Error.none; } return result, blot_error::Error.none;
}
recursive fn noStore(self_: Scan&, id: Id, arity: u8, depth: i64) -> bool, Error {
    let error = self_.step(depth); if error != blot_error::Error.none { return false, error; } if id == 0 || id >= self_.module.nodes.len { return false, blot_error::Error.invalid_artifact; } let n = self_.module.node(id);
    if n.tag == blot_check_core::Tag.reference {
        if n.a >= self_.module.references.len || n.ty >= self_.module.types.nodes.len { return false, blot_error::Error.invalid_artifact; } let reference = self_.module.reference(id); let possible_owner, error = owner(self_, reference.unit); if error != blot_error::Error.none { return false, error; }
        if possible_owner { let module .= possible_owner; if reference.binding >= module.bindings.len { return false, blot_error::Error.invalid_artifact; } let binding = module.bindings[reference.binding];
            if module.owner_id != 0 && module.owner_id == self_.module.owner_id && binding.kind == blot_reuse_principal_interface::Kind.local && binding.initializer != 0 { return noStore(self_, binding.initializer, arity, depth + 1); }
            if binding.kind != blot_reuse_principal_interface::Kind.global || binding.body_id == 0 || binding.body_id >= module.bodies.len { return false, blot_error::Error.none; } let body = module.bodies[binding.body_id]; if body.parameters.len != arity { return false, blot_error::Error.none; } let signature = self_.module.types.node(n.ty); if signature.tag != blot_check_types::Tag.function { return false, blot_error::Error.none; }
            let relation, error = blot_check_generative_relocation::init(module, self_.module, binding.scheme, n.ty, n.ty, 0, 0); if error != blot_error::Error.none { return false, blot_error::Error.none; }
            if arity == 1 && (binding.capability_flow == blot_check_capability_flow::Contract.identity || binding.capability_flow == blot_check_capability_flow::Contract.member_unit) { return blot_check_capability_flow::unaryCore(module, body, binding.capability_flow), blot_error::Error.none; }
            if binding.capability_flow != blot_check_capability_flow::Contract.input_shape || binding.scheme.generative.len != 0 { return false, blot_error::Error.none; }
            return blot_check_capability_contract_core::inputBodyWithOwners(module, body, binding.capability_parameters, self_.owners), blot_error::Error.none;
        } return false, blot_error::Error.invalid_artifact;
    }
    if n.tag == blot_check_core::Tag.if_value { let left, error = noStore(self_, n.b, arity, depth + 1); if error != blot_error::Error.none { return false, error; } let right, error = noStore(self_, n.c, arity, depth + 1); if error != blot_error::Error.none { return false, error; } return left && right, blot_error::Error.none; }
    if n.tag == blot_check_core::Tag.closure && n.a >= self_.module.closures.len { return false, blot_error::Error.invalid_artifact; }
    var context = CallableProof { self_.module, self_.owners, id, arity, self_.remaining, depth, n.tag == blot_check_core::Tag.closure , ..};
    return blot_check_capability_contracts::withStoreValue<CallableProof,bool>(context,proveCallable);
}
recursive fn expression(self_: Scan&, vertex: i64, scoped: bool, parent: Id, scope_root: Id, depth: i64) -> Error {
    let error = self_.step(depth); if error != blot_error::Error.none { return error; } let item = self_.graph.item(vertex); var inside = scoped; var scope = scope_root;
    if item.kind == blot_check_frozen_core_validation::Kind.node && item.id != 0 { let id = item.id as Id; let n = self_.module.node(id); inside = scoped || n.tag == blot_check_core::Tag.effect_scope; if scope == 0 && n.tag == blot_check_core::Tag.effect_scope { scope = id; }
        if parent == 0 && (n.tag == blot_check_core::Tag.call || n.tag == blot_check_core::Tag.apply) { let found = blot_check_capability_flow::coreCall(self_.module, id);
            if found.present { let call = found.value; let possible_owner, error = owner(self_, call.target.unit); if error != blot_error::Error.none { return error; }
                if possible_owner { let producer .= possible_owner; if call.target.binding >= producer.bindings.len { return blot_error::Error.invalid_artifact; } let contract = producer.bindings[call.target.binding].capability_parameters;
                    if contract.inputInvokes() && contract.valid() && contract.arity() == call.len { var transfers = false; for index in 0..contract.argumentCount() { if !transfers { let value, error = authority(self_, call.arguments[contract.argumentAt(index)], inside, 0); if error != blot_error::Error.none { return error; } transfers = value; } }
                        if transfers { let no_store, error = noStore(self_, call.arguments[contract.callback()], contract.argumentCount(), 0); if error != blot_error::Error.none { return error; }
                            if !no_store { let local, error = localStateStore(self_, scope, id, contract); if error != blot_error::Error.none { return error; } if !local { return blot_error::Error.invalid_artifact; } }
                        }
                    }
                } else { return blot_error::Error.invalid_artifact; }
            }
        }
    }
    var slot: i64 = 0; while true { let child = self_.graph.edge(vertex, slot); if !child.present { break; } slot += 1; var application: Id = 0;
        if item.kind == blot_check_frozen_core_validation::Kind.node && item.id != 0 { let n = self_.module.node(item.id as Id); let target = self_.graph.item(child.value);
            if n.tag == blot_check_core::Tag.apply && target.kind == blot_check_frozen_core_validation::Kind.node && target.id == n.a { application = item.id as Id; if parent != 0 { application = parent; } }
        }
        let error = expression(self_, child.value, inside, application, scope, depth + 1); if error != blot_error::Error.none { return error; }
    } return blot_error::Error.none;
}
fn active(module: const Module&, owners: const ModuleRef[:]) -> bool {
    var contracts = false; for binding in module.bindings { if binding.capability_parameters.inputInvokes() { contracts = true; break; } }
    if !contracts { for owner_owner_ref in owners { let owner: const blot_check_core::Module&  = owner_owner_ref.value; for binding in owner.bindings { if binding.capability_parameters.inputInvokes() { contracts = true; break; } } if contracts { break; } } }
    if !contracts { return false; } for node in module.types.nodes { if node.tag == blot_check_types::Tag.scoped { return true; } } return false;
}
fn validate(module: const Module&, owners: const ModuleRef[:]) -> Error {
    if !active(module, owners) { return blot_error::Error.none; } let graph, error = blot_check_frozen_core_validation::initGraph(module); if error != blot_error::Error.none { return error; } var scopes: Scope[>..<] = []; var scan = Scan { module: module, owners: owners, graph: graph, scopes: scopes , ..};
    let error = validateScan(scan); deinit(scan); return error;
}
fn validateScan(scan: Scan&) -> Error { for body in scan.module.bodies { if body.root != 0 { let error = expression(scan, scan.graph.vertex(blot_check_frozen_core_validation::Kind.node, body.root), false, 0, 0, 0); if error != blot_error::Error.none { return error; } } } return blot_error::Error.none; }
fn validateWithScratch(module: const Module&, owners: const ModuleRef[:]) -> Error { let error = validate(module, owners); if error != blot_error::Error.none { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
