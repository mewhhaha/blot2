// Conditional input invocation reconstructs the actual callable before transfer.
namespace blot_check_capability_invocations;
import .frozen_core_validation;
type ModuleRef = blot_check_frozen_core_validation::ModuleRef;
import support.error;
import support.option;
import .core;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Id = blot_check_core::Id;
type Report = blot_check_capability_lifetimes::Report;
type Parameters = blot_check_capability_flow::Parameters;
struct Scope { root: Id, report: blot_support::Option<Report> }
struct Scan { module: const Module&, owners: const ModuleRef[:], graph: blot_check_frozen_core_validation::Graph, remaining: i64 = 65536, scopes: Scope[>..<]& }
fn deinit(self: Scan&) { for &item in self.scopes { if item.report.present { item.report.value.deinit(); } } self.scopes.clear(); }
fn step(self: Scan&, depth: i64) -> Error { if depth >= 128 || self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; return Error.none; }
fn owner(self: const Scan&, unit: u32) -> const Module?, Error { if unit == 0 || unit == self.module.unit { return self.module, Error.none; } for module_owner_ref in self.owners { let module: const blot_check_core::Module& = module_owner_ref.value; if module.unit == unit { return module, Error.none; } } return null, Error.invalid_artifact; }
fn stateReport(self: Scan&, report: blot_support::Option<Report>, call: Id, contract: Parameters) -> bool, Error {
    if !report.present { return false, Error.none; } let result, error = blot_check_capability_lifetimes::localStateInvocation(report.value, self.module.unit, call, contract.callback(), contract.argumentAt(0), self.remaining);
    if error == Error.out_of_memory { return false, error; } if error != Error.none { return false, Error.invalid_artifact; } return result, Error.none;
}
fn localStateStore(self: Scan&, scope: Id, call: Id, contract: Parameters) -> bool, Error {
    if scope == 0 || contract.argumentCount() != 1 { return false, Error.none; }
    for item in self.scopes { let error = self.step(0); if error != Error.none { return false, error; } if item.root == scope { return stateReport(self, item.report, call, contract); } }
    let report, error = blot_check_capability_lifetimes::analyzeScope(self.module, self.owners, scope, self.remaining); var owned = blot_support::none<Report>();
    if error == Error.out_of_memory { return false, error; } if error != Error.none && error != Error.unsupported { return false, Error.invalid_artifact; } if error == Error.none { owned = blot_support::some(report); }
    self.scopes += Scope { scope, owned , ..}; return stateReport(self, owned, call, contract);
}
recursive fn authority(self: Scan&, id: Id, scoped: bool, depth: i64) -> bool, Error {
    let error = self.step(depth); if error != Error.none { return false, error; } if id == 0 || id >= self.module.nodes.len { return false, Error.invalid_artifact; } let n = self.module.node(id); let ty = self.module.types.node(n.ty);
    match ty.tag { blot_check_types::Tag.scoped => { return true, Error.none; }, blot_check_types::Tag.unit, blot_check_types::Tag.boolean, blot_check_types::Tag.unsigned32, blot_check_types::Tag.floating32, blot_check_types::Tag.never => { return false, Error.none; }, _ => {}, }
    match n.tag {
        blot_check_core::Tag.reference => { let reference = self.module.reference(id); if reference.unit != 0 && reference.unit != self.module.unit { return scoped, Error.none; } let binding = self.module.bindings[reference.binding]; if binding.initializer != 0 { return authority(self, binding.initializer, scoped, depth + 1); } return scoped, Error.none; },
        blot_check_core::Tag.product, blot_check_core::Tag.record, blot_check_core::Tag.array => { for child in self.module.extra[n.a..n.a + n.b] { let result, error = authority(self, child, scoped, depth + 1); if error != Error.none || result { return result, error; } } return false, Error.none; },
        blot_check_core::Tag.construct => { if n.b == 0 { return false, Error.none; } return authority(self, n.b, scoped, depth + 1); },
        blot_check_core::Tag.closure => { let closure = self.module.closures[n.a]; for binding in self.module.extra[closure.captures.start..closure.captures.start + closure.captures.len] { let capture = self.module.bindings[binding]; if self.module.types.node(capture.ty).tag == blot_check_types::Tag.scoped { return true, Error.none; }
                if capture.initializer != 0 { let result, error = authority(self, capture.initializer, scoped, depth + 1); if error != Error.none || result { return result, error; } } if capture.initializer == 0 && scoped { return true, Error.none; }
            } return false, Error.none;
        },
        blot_check_core::Tag.if_value => { let left, error = authority(self, n.b, scoped, depth + 1); if error != Error.none || left { return left, error; } return authority(self, n.c, scoped, depth + 1); },
        _ => { return scoped, Error.none; },
    }
}
struct CallableProof { module: const Module&, owners: const ModuleRef[:], node: Id, arity: u8, remaining: i64&, depth: i64, closure: bool }
fn proveCallable(context: CallableProof&, store: blot_check_capability_contracts::Store&) -> bool, Error {
    var root = blot_support::none<Id>(); var failure = Error.none;
    if context.closure { let result, error = blot_check_capability_contract_core::deriveInputFunctionClosureWithOwners(store, context.module, context.module.closures[context.module.node(context.node).a], context.arity, context.owners); root = result; failure = error; }
    else { let result, error = blot_check_capability_contract_core::callableValue(store, context.module, context.node, context.owners); root = result; failure = error; }
    if failure == Error.out_of_memory { return false, failure; } if failure != Error.none || !root.present { return false, Error.none; }
    if context.closure { return true, Error.none; } let result, error = store.callableArity(root.value, context.arity, context.remaining, context.depth + 1); if error != Error.none { return false, Error.none; } return result, Error.none;
}
recursive fn noStore(self: Scan&, id: Id, arity: u8, depth: i64) -> bool, Error {
    let error = self.step(depth); if error != Error.none { return false, error; } if id == 0 || id >= self.module.nodes.len { return false, Error.invalid_artifact; } let n = self.module.node(id);
    if n.tag == blot_check_core::Tag.reference {
        if n.a >= self.module.references.len || n.ty >= self.module.types.nodes.len { return false, Error.invalid_artifact; } let reference = self.module.reference(id); let possible_owner, error = owner(self, reference.unit); if error != Error.none { return false, error; }
        if possible_owner { let module .= possible_owner; if reference.binding >= module.bindings.len { return false, Error.invalid_artifact; } let binding = module.bindings[reference.binding];
            if module.owner_id != 0 && module.owner_id == self.module.owner_id && binding.kind == blot_check_check::Kind.local && binding.initializer != 0 { return noStore(self, binding.initializer, arity, depth + 1); }
            if binding.kind != blot_check_check::Kind.global || binding.body_id == 0 || binding.body_id >= module.bodies.len { return false, Error.none; } let body = module.bodies[binding.body_id]; if body.parameters.len != arity { return false, Error.none; } let signature = self.module.types.node(n.ty); if signature.tag != blot_check_types::Tag.function { return false, Error.none; }
            let relation, error = blot_check_generative_relocation::init(module, self.module, binding.scheme, n.ty, n.ty, 0, 0); if error != Error.none { return false, Error.none; }
            if arity == 1 && (binding.capability_flow == blot_check_check::CapabilityFlow.identity || binding.capability_flow == blot_check_check::CapabilityFlow.member_unit) { return blot_check_capability_flow::unaryCore(module, body, binding.capability_flow), Error.none; }
            if binding.capability_flow != blot_check_check::CapabilityFlow.input_shape || binding.scheme.generative.len != 0 { return false, Error.none; }
            return blot_check_capability_contract_core::inputBodyWithOwners(module, body, binding.capability_parameters, self.owners), Error.none;
        } return false, Error.invalid_artifact;
    }
    if n.tag == blot_check_core::Tag.if_value { let left, error = noStore(self, n.b, arity, depth + 1); if error != Error.none { return false, error; } let right, error = noStore(self, n.c, arity, depth + 1); if error != Error.none { return false, error; } return left && right, Error.none; }
    if n.tag == blot_check_core::Tag.closure && n.a >= self.module.closures.len { return false, Error.invalid_artifact; }
    var context = CallableProof { self.module, self.owners, id, arity, self.remaining, depth, n.tag == blot_check_core::Tag.closure , ..};
    return blot_check_capability_contracts::withStoreValue<CallableProof,proveCallable,bool>(context);
}
recursive fn expression(self: Scan&, vertex: i64, scoped: bool, parent: Id, scope_root: Id, depth: i64) -> Error {
    let error = self.step(depth); if error != Error.none { return error; } let item = self.graph.item(vertex); var inside = scoped; var scope = scope_root;
    if item.kind == blot_check_frozen_core_validation::Kind.node && item.id != 0 { let id = item.id as Id; let n = self.module.node(id); inside = scoped || n.tag == blot_check_core::Tag.effect_scope; if scope == 0 && n.tag == blot_check_core::Tag.effect_scope { scope = id; }
        if parent == 0 && (n.tag == blot_check_core::Tag.call || n.tag == blot_check_core::Tag.apply) { let found = blot_check_capability_flow::coreCall(self.module, id);
            if found.present { let call = found.value; let possible_owner, error = owner(self, call.target.unit); if error != Error.none { return error; }
                if possible_owner { let producer .= possible_owner; if call.target.binding >= producer.bindings.len { return Error.invalid_artifact; } let contract = producer.bindings[call.target.binding].capability_parameters;
                    if contract.inputInvokes() && contract.valid() && contract.arity() == call.len { var transfers = false; for index in 0..contract.argumentCount() { if !transfers { let value, error = authority(self, call.arguments[contract.argumentAt(index)], inside, 0); if error != Error.none { return error; } transfers = value; } }
                        if transfers { let no_store, error = noStore(self, call.arguments[contract.callback()], contract.argumentCount(), 0); if error != Error.none { return error; }
                            if !no_store { let local, error = localStateStore(self, scope, id, contract); if error != Error.none { return error; } if !local { return Error.invalid_artifact; } }
                        }
                    }
                } else { return Error.invalid_artifact; }
            }
        }
    }
    var slot: i64 = 0; while true { let child = self.graph.edge(vertex, slot); if !child.present { break; } slot += 1; var application: Id = 0;
        if item.kind == blot_check_frozen_core_validation::Kind.node && item.id != 0 { let n = self.module.node(item.id as Id); let target = self.graph.item(child.value);
            if n.tag == blot_check_core::Tag.apply && target.kind == blot_check_frozen_core_validation::Kind.node && target.id == n.a { application = item.id as Id; if parent != 0 { application = parent; } }
        }
        let error = expression(self, child.value, inside, application, scope, depth + 1); if error != Error.none { return error; }
    } return Error.none;
}
fn active(module: const Module&, owners: const ModuleRef[:]) -> bool {
    var contracts = false; for binding in module.bindings { if binding.capability_parameters.inputInvokes() { contracts = true; break; } }
    if !contracts { for owner_owner_ref in owners { let owner: const blot_check_core::Module& = owner_owner_ref.value; for binding in owner.bindings { if binding.capability_parameters.inputInvokes() { contracts = true; break; } } if contracts { break; } } }
    if !contracts { return false; } for node in module.types.nodes { if node.tag == blot_check_types::Tag.scoped { return true; } } return false;
}
fn validate(module: const Module&, owners: const ModuleRef[:]) -> Error {
    if !active(module, owners) { return Error.none; } let graph, error = blot_check_frozen_core_validation::initGraph(module); if error != Error.none { return error; } var scopes: Scope[>..<] = []; var scan = Scan { module, owners, graph, scopes: scopes , ..};
    let error = validateScan(scan); deinit(scan); return error;
}
fn validateScan(scan: Scan&) -> Error { for body in scan.module.bodies { if body.root != 0 { let error = expression(scan, scan.graph.vertex(blot_check_frozen_core_validation::Kind.node, body.root), false, 0, 0, 0); if error != Error.none { return error; } } } return Error.none; }
fn validateWithScratch(module: const Module&, owners: const ModuleRef[:]) -> Error { let error = validate(module, owners); if error != Error.none { return Error.invalid_artifact; } return Error.none; }
