// Core independently reconstructs result paths; capture catalogs grant nothing.
namespace blot_check_capability_contract_core;
import reuse.principal_interface;

import backend.collection_ops;
import check.capability_contracts;
import check.capability_flow;
import check.check_packet_owner;
import check.core;
import check.frozen_core_scopes;
import check.generative_relocation;
import check.logical_scratch_budget;
import check.task_core;
import check.task_regions;
import check.task_types;
import check.types;
import support.error;
import support.option;
import support.structural_adapters;
import support.pooled_buffer;

import .frozen_core_validation;
type ModuleRef = blot_check_frozen_core_validation::ModuleRef;
import support.structural;
type Error = blot_error::Error;
type Id = u32;
type Module = blot_check_core::Module;
type Store = blot_check_capability_contracts::Store;
type Tag = blot_check_capability_contracts::Tag;
struct Alias { binding: u32, value: Id, callable: blot_support::Option<i64>   = blot_support::none<i64>() }
struct Environment { values: Alias[128], len: i64 = 0 }
fn bind(self_: Environment&, binding: u32, value: Id) -> Error { if self_.len == self_.values.len { return blot_error::Error.capability_analysis_limit; } self_.values[self_.len] = Alias { binding, value , ..}; self_.len += 1; return blot_error::Error.none; }
fn alias(self_: const Environment&, binding: u32) -> blot_support::Option<Alias> { var index = self_.len; while index != 0 { index -= 1; if self_.values[index].binding == binding { return blot_support::some(self_.values[index]); } } return blot_support::none<Alias>(); }
fn get(self_: const Environment&, binding: u32) -> blot_support::Option<Id> { let found = self_.alias(binding); if !found.present { return blot_support::none<Id>(); } return blot_support::some(found.value.value); }
struct CallableOrigin { source: u32, environment: Environment }
struct Callables { storage: CallableOrigin[:] = default<CallableOrigin[:]>(), items: CallableOrigin[:] = default<CallableOrigin[:]>() }
reusable[] var callable_runs: CallableOrigin[>..];
struct Builder {
    remaining: i64 = 65536, input_globals: bool = false, value_origins: bool = false,
    closed_rows: blot_check_types::List = blot_check_types::List {..},
    callable_allocation: blot_check_logical_scratch_budget::ArrayBlock = blot_check_logical_scratch_budget::ArrayBlock {element_size:3088,alignment:8, ..},
}
fn node(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, source: u32, depth: i64) -> blot_check_core::Node, Error { if depth >= 128 || self_.remaining == 0 { return default<blot_check_core::Node>(), blot_error::Error.capability_analysis_limit; } self_.remaining -= 1; if source == 0 || source >= view_module.nodes.len { return default<blot_check_core::Node>(), blot_error::Error.unavailable; } return view_module.nodes[source], blot_error::Error.none; }
fn callableOrigin(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, source: u32, environment: const Environment&, depth: i64) -> blot_support::Option<i64>, Error {
    let value, error = node(self_, contract_store, view_module, module_owners, callable_table, source, depth); if error != blot_error::Error.none { return blot_support::none<i64>(), error; }
    if value.tag == blot_check_core::Tag.reference { if value.a >= view_module.references.len { return blot_support::none<i64>(), blot_error::Error.unavailable; } let reference = view_module.references[value.a]; if reference.unit != 0 && reference.unit != view_module.unit { return blot_support::none<i64>(), blot_error::Error.none; }
        let found = environment.alias(reference.binding); if !found.present { return blot_support::none<i64>(), blot_error::Error.none; } return found.value.callable, blot_error::Error.none;
    }
    if value.tag != blot_check_core::Tag.closure { return blot_support::none<i64>(), blot_error::Error.none; } let index = callable_table.items.len; let growth = ensureCallables(self_, contract_store, view_module, module_owners, callable_table,index+1); if growth != blot_error::Error.none {return blot_support::none<i64>(),growth;} let allocation_error=blot_support_pooled_buffer::push(callable_table,CallableOrigin { source, environment , ..},callable_runs); if allocation_error!=blot_error::Error.none {return blot_support::none<i64>(),allocation_error;} return blot_support::some(index), blot_error::Error.none;
}
recursive fn closureCall(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, call: blot_check_capability_flow::LocalCoreCall, environment: const Environment&, depth: i64) -> blot_support::Option<Id>, Error {
    if call.len != 1 || (call.target.unit != 0 && call.target.unit != view_module.unit) { return blot_support::none<Id>(), blot_error::Error.none; } let found = environment.alias(call.target.binding); if !found.present || !found.value.callable.present { return blot_support::none<Id>(), blot_error::Error.none; }
    let origin = found.value.callable.value; if origin >= callable_table.items.len { return blot_support::none<Id>(), blot_error::Error.unavailable; } let source = callable_table.items[origin].source; let value, error = node(self_, contract_store, view_module, module_owners, callable_table, source, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    if value.tag != blot_check_core::Tag.closure || value.a >= view_module.closures.len { return blot_support::none<Id>(), blot_error::Error.unavailable; } let callback = view_module.closures[value.a];
    let argument, error = expression(self_, contract_store, view_module, module_owners, callable_table, call.arguments[0], environment, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } var callee = callable_table.items[origin].environment;
    if callback.parameter.binding != 0 { let error = callee.bind(callback.parameter.binding, argument); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } }
    let result, error = expression(self_, contract_store, view_module, module_owners, callable_table, callback.body, callee, depth + 1); return blot_support::some(result), error;
}
enum FunctionUse { value, invocation }
fn producerFor(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, current: i64, unit: u32) -> const Module?, i64, Error {
    if current < 0 { if unit == 0 || unit == view_module.unit { return view_module, current, blot_error::Error.none; } }
    else { let owner .= module_owners[current].value; if unit == 0 || unit == owner.unit { return owner, current, blot_error::Error.none; } }
    var selected: const Module? = null; var selected_index:i64=-1;
    for owner_owner_ref,index in module_owners { let owner: const blot_check_core::Module& = owner_owner_ref.value; if self_.remaining == 0 { return null, -1, blot_error::Error.capability_analysis_limit; } self_.remaining -= 1; if owner.unit != unit { continue; }
        if selected { if selected.owner_id == 0 || selected.owner_id != owner.owner_id { return null, -1, blot_error::Error.unavailable; } } selected .= owner; selected_index=index;
    } return selected, selected_index, blot_error::Error.none;
}
recursive fn namedFunction(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, original: blot_check_core::BindingRef, actual: u32, use: FunctionUse, depth: i64) -> blot_support::Option<Id>, Error {
    var target = original; var producer_index:i64=-1;
    for attempt in 0..128 { if self_.remaining == 0 || depth >= 128 { return blot_support::none<Id>(), blot_error::Error.capability_analysis_limit; } self_.remaining -= 1;
        let producer, next_producer_index, error = producerFor(self_, contract_store, view_module, module_owners, callable_table, producer_index, target.unit); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if !producer { return blot_support::none<Id>(), blot_error::Error.none; } producer_index=next_producer_index;
        if target.binding == 0 || target.binding >= producer.bindings.len { return blot_support::none<Id>(), blot_error::Error.unavailable; } let binding = producer.bindings[target.binding]; if binding.kind == blot_reuse_principal_interface::Kind.external { target = binding.target; continue; }
        if binding.kind != blot_reuse_principal_interface::Kind.global || binding.body_id == 0 || binding.body_id >= producer.bodies.len || binding.scheme.generative.len != 0 { return blot_support::none<Id>(), blot_error::Error.none; } let body = producer.bodies[binding.body_id]; if !body.is_function { return blot_support::none<Id>(), blot_error::Error.none; }
        if use == FunctionUse.value && binding.capability_flow != blot_check_capability_flow::Contract.identity && binding.capability_flow != blot_check_capability_flow::Contract.input_shape { return blot_support::none<Id>(), blot_error::Error.none; }
        let relocation, error = blot_check_generative_relocation::init(producer, view_module, binding.scheme, actual, actual, 0, 0); if error != blot_error::Error.none { return blot_support::none<Id>(), blot_error::Error.unavailable; } let work = 65536 - relocation.remaining; if work > self_.remaining { return blot_support::none<Id>(), blot_error::Error.capability_analysis_limit; } self_.remaining -= work;
        var arity = binding.capability_parameters.arity();
        if binding.capability_flow == blot_check_capability_flow::Contract.identity { if !blot_check_capability_flow::unaryCore(producer, body, blot_check_capability_flow::Contract.identity) { return blot_support::none<Id>(), blot_error::Error.unavailable; } arity = 1; }
        else if binding.capability_flow != blot_check_capability_flow::Contract.input_shape && (binding.capability_flow != blot_check_capability_flow::Contract.unknown || binding.capability_parameters.kind != blot_check_capability_flow::ParameterResult.product || !binding.capability_parameters.valid() || !binding.capability_parameters.present()) { return blot_support::none<Id>(), blot_error::Error.none; }
        if arity == 0 || arity > 16 || body.parameters.len != arity || body.parameters.start > producer.parameters.len || body.parameters.len > producer.parameters.len - body.parameters.start { return blot_support::none<Id>(), blot_error::Error.unavailable; }
        var callables = Callables {..}; var reader = Builder { remaining: self_.remaining, input_globals: true, closed_rows: body.closed_rows, ..};
        let result, error = namedBody(reader, contract_store, producer, module_owners, callables, producer, body, binding, arity, depth); releaseCallables(reader, contract_store, producer, module_owners, callables); self_.remaining = reader.remaining; return result, error;
    } return blot_support::none<Id>(), blot_error::Error.capability_analysis_limit;
}
recursive fn namedBody(reader: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, producer: const Module&, body: blot_check_core::Body, binding: blot_check_core::Binding, arity: u8, depth: i64) -> blot_support::Option<Id>, Error {
    var parameters = Environment {..};
    for parameter, index in producer.parameters[body.parameters.start..body.parameters.start + arity] {
        if parameter.binding == 0 { if index != 0 || parameter.ty != blot_check_types::unit { return blot_support::none<Id>(), blot_error::Error.unavailable; } continue; }
        if parameter.binding >= producer.bindings.len || producer.bindings[parameter.binding].kind != blot_reuse_principal_interface::Kind.parameter { return blot_support::none<Id>(), blot_error::Error.unavailable; }
        let id, error = contract_store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.argument, index as u32 , ..}); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } let error = parameters.bind(parameter.binding, id); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    }
    let result, error = expression(reader, contract_store, view_module, module_owners, callable_table, body.root, parameters, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } var expected = binding.capability_parameters.result(); if binding.capability_flow == blot_check_capability_flow::Contract.identity { expected = 1; }
    let mask, error = contract_store.view().argumentMask(result, reader.remaining); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if mask != expected { return blot_support::none<Id>(), blot_error::Error.unavailable; }
    let function, error = contract_store.append(blot_check_capability_contracts::Term { tag: blot_check_capability_contracts::Tag.callable, a: arity, c: result , ..}); return blot_support::some(function), error;
}
recursive fn referenceValue(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, catalog: u32, actual: u32, environment: const Environment&, depth: i64) -> Id, Error {
    if catalog >= view_module.references.len { return 0, blot_error::Error.unavailable; } let value = view_module.references[catalog];
    if value.unit == 0 || value.unit == view_module.unit { let known = environment.get(value.binding); if known.present { return known.value, blot_error::Error.none; }
        if self_.value_origins && value.binding < view_module.bindings.len { let binding = view_module.bindings[value.binding]; if binding.kind == blot_reuse_principal_interface::Kind.local && binding.initializer != 0 { return expression(self_, contract_store, view_module, module_owners, callable_table, binding.initializer, environment, depth + 1); } if binding.kind == blot_reuse_principal_interface::Kind.parameter { return 0, blot_error::Error.none; } }
    }
    if self_.input_globals { let function, error = namedFunction(self_, contract_store, view_module, module_owners, callable_table, value, actual, FunctionUse.value, depth + 1); if error != blot_error::Error.none { return 0, error; } if function.present { return function.value, blot_error::Error.none; }
        if value.unit != 0 && value.unit != view_module.unit { return 0, blot_error::Error.none; } if value.binding < view_module.bindings.len && view_module.bindings[value.binding].kind == blot_reuse_principal_interface::Kind.global { return 0, blot_error::Error.none; }
    }
    if value.unit != 0 && value.unit != view_module.unit { return 0, blot_error::Error.unavailable; } let found = environment.get(value.binding); if !found.present { return 0, blot_error::Error.unavailable; } return found.value, blot_error::Error.none;
}
fn inputStore(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, root: Id) -> Error { if self_.input_globals { let contains, error = contract_store.view().containsParameter(root, self_.remaining); if error != blot_error::Error.none { return error; } if contains { return blot_error::Error.unavailable; } } return blot_error::Error.none; }
recursive fn expression(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, source: u32, environment: const Environment&, depth: i64) -> Id, Error {
    let value, error = node(self_, contract_store, view_module, module_owners, callable_table, source, depth); if error != blot_error::Error.none { return 0, error; }
    match value.tag {
        call, apply => { return application(self_, contract_store, view_module, module_owners, callable_table, source, value, environment, depth); },
        reference => { return referenceValue(self_, contract_store, view_module, module_owners, callable_table, value.a, value.ty, environment, depth + 1); },
        computation => { let child, error = expression(self_, contract_store, view_module, module_owners, callable_table, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let error = inputStore(self_, contract_store, view_module, module_owners, callable_table, child); if error != blot_error::Error.none { return 0, error; } return contract_store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.wrapped, child , ..}); },
        effect_provider, state_provider => { var children: Id[3] = [0;3]; let a, error = expression(self_, contract_store, view_module, module_owners, callable_table, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } children[0] = a; let b, error = expression(self_, contract_store, view_module, module_owners, callable_table, value.b, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } children[1] = b; var count: i64 = 2;
            if value.tag == blot_check_core::Tag.state_provider { let c, error = expression(self_, contract_store, view_module, module_owners, callable_table, value.c, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } children[2] = c; count = 3; } for child in children[..count] { let error = inputStore(self_, contract_store, view_module, module_owners, callable_table, child); if error != blot_error::Error.none { return 0, error; } } return contract_store.aggregate(blot_check_capability_contracts::Tag.captures, children[..count]);
        },
        usage_borrow => { if value.b >= view_module.nodes.len || view_module.nodes[value.b].tag != blot_check_core::Tag.closure { return 0, blot_error::Error.unavailable; } let callback = view_module.closure(value.b); var nested = environment;
            let argument, error = expression(self_, contract_store, view_module, module_owners, callable_table, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let error = nested.bind(callback.parameter.binding, argument); if error != blot_error::Error.none { return 0, error; } return expression(self_, contract_store, view_module, module_owners, callable_table, callback.body, nested, depth + 1);
        },
        task => { return taskValue(self_, contract_store, view_module, module_owners, callable_table, source, value, environment, depth); },
        usage_share => { return expression(self_, contract_store, view_module, module_owners, callable_table, value.a, environment, depth + 1); },
        resource_acquire, resource_release, resource_scope, usage_read, scalar, logical => {
            if self_.input_globals { if value.tag == blot_check_core::Tag.resource_acquire || value.tag == blot_check_core::Tag.resource_release || value.tag == blot_check_core::Tag.resource_scope { return 0, blot_error::Error.unavailable; }
                let ignored, error = expression(self_, contract_store, view_module, module_owners, callable_table, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } if (value.tag == blot_check_core::Tag.scalar || value.tag == blot_check_core::Tag.logical) && value.b != 0 { let ignored, error = expression(self_, contract_store, view_module, module_owners, callable_table, value.b, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } }
            } return scalarValue(self_, contract_store, view_module, module_owners, callable_table, value.ty);
        },
        constant => { return scalarValue(self_, contract_store, view_module, module_owners, callable_table, value.ty); },
        construct => { var child: Id = 0; if value.b != 0 { let id, error = expression(self_, contract_store, view_module, module_owners, callable_table, value.b, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } child = id; } return contract_store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.wrapped, child , ..}); },
        product, array, record => { return aggregateValue(self_, contract_store, view_module, module_owners, callable_table, value, environment, depth); },
        array_op => {
            if value.c != blot_backend_collection_ops::opCode(blot_backend_collection_ops::Op.get) || value.b != 2 || value.a > view_module.extra.len || value.b > view_module.extra.len - value.a { return 0, blot_error::Error.unavailable; }
            let receiver, error = expression(self_, contract_store, view_module, module_owners, callable_table, view_module.extra[value.a], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let index, error = node(self_, contract_store, view_module, module_owners, callable_table, view_module.extra[value.a + 1], depth + 1); if error != blot_error::Error.none { return 0, error; }
            if index.tag != blot_check_core::Tag.constant || index.ty >= view_module.types.nodes.len || view_module.types.nodes[index.ty].tag != blot_check_types::Tag.unsigned32 { return contract_store.elements(receiver); } return contract_store.project(receiver, index.a, blot_check_capability_contracts::Projection.index);
        },
        operation_value => { if value.a >= view_module.operation_values.len { return 0, blot_error::Error.unavailable; } let receiver, error = expression(self_, contract_store, view_module, module_owners, callable_table, view_module.operation_values[value.a].capability, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let children: Id[1] = [receiver]; return contract_store.aggregate(blot_check_capability_contracts::Tag.captures, children); },
        project => { if value.b >= view_module.projections.len { return 0, blot_error::Error.unavailable; } let projection = view_module.projections[value.b]; var selector = projection.field; var kind = blot_check_capability_contracts::Projection.field;
            if projection.field == 0 { if projection.nominal.unit != 0 || projection.nominal.decl != 0 || projection.variants.len != 1 || projection.variants.start >= view_module.projection_variants.len { return 0, blot_error::Error.unavailable; } let variant = view_module.projection_variants[projection.variants.start]; if variant.tag != 0 { return 0, blot_error::Error.unavailable; } selector = variant.field; kind = blot_check_capability_contracts::Projection.index; }
            let receiver, error = expression(self_, contract_store, view_module, module_owners, callable_table, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } return contract_store.project(receiver, selector, kind);
        },
        if_value => { if self_.input_globals { let ignored, error = expression(self_, contract_store, view_module, module_owners, callable_table, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } } let left, error = expression(self_, contract_store, view_module, module_owners, callable_table, value.b, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let right, error = expression(self_, contract_store, view_module, module_owners, callable_table, value.c, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let children: Id[2] = [left, right]; return contract_store.aggregate(blot_check_capability_contracts::Tag.join, children); },
        block_ => { return blockValue(self_, contract_store, view_module, module_owners, callable_table, source, value, environment, depth); },
        match_ => { return matchValue(self_, contract_store, view_module, module_owners, callable_table, value, environment, depth); },
        closure => { if value.a >= view_module.closures.len { return 0, blot_error::Error.unavailable; } let closure = view_module.closures[value.a]; var nested = environment; let error = nested.bind(closure.parameter.binding, 0); if error != blot_error::Error.none { return 0, error; }
            var captures: Id[4096] = [0;4096]; var count: i64 = 0; let error = capture(self_, contract_store, view_module, module_owners, callable_table, closure.body, nested, captures, count, depth + 1); if error != blot_error::Error.none { return 0, error; } for child in captures[..count] { let error = inputStore(self_, contract_store, view_module, module_owners, callable_table, child); if error != blot_error::Error.none { return 0, error; } } return contract_store.aggregate(blot_check_capability_contracts::Tag.captures, captures[..count]);
        },
        _ => { return 0, blot_error::Error.unavailable; },
    }
}
fn scalarValue(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, ty: u32) -> Id, Error {
    if ty >= view_module.types.nodes.len { return 0, blot_error::Error.unavailable; } let tag = view_module.types.nodes[ty].tag;
    if tag == blot_check_types::Tag.unit || tag == blot_check_types::Tag.boolean || tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32 { return 0, blot_error::Error.none; } return 0, blot_error::Error.unavailable;
}
recursive fn application(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, source: u32, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    let call = blot_check_capability_flow::coreCall(view_module, source); if call.present { let result, error = closureCall(self_, contract_store, view_module, module_owners, callable_table, call.value, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } if result.present { return result.value, blot_error::Error.none; } }
    if self_.input_globals && value.tag == blot_check_core::Tag.apply { let argument, error = node(self_, contract_store, view_module, module_owners, callable_table, value.b, depth + 1); if error != blot_error::Error.none { return 0, error; } let callee, error = node(self_, contract_store, view_module, module_owners, callable_table, value.a, depth + 1); if error != blot_error::Error.none { return 0, error; }
        if argument.tag == blot_check_core::Tag.constant && argument.ty == blot_check_types::unit && argument.a == 0 && callee.tag == blot_check_core::Tag.operation_value { if value.ty >= view_module.types.nodes.len { return 0, blot_error::Error.unavailable; } let ignored, error = expression(self_, contract_store, view_module, module_owners, callable_table, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let tag = view_module.types.node(value.ty).tag;
            if tag == blot_check_types::Tag.unit || tag == blot_check_types::Tag.boolean || tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32 || tag == blot_check_types::Tag.never { return 0, blot_error::Error.none; } return contract_store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.unknown , ..});
        }
    }
    let local = blot_check_capability_flow::localCoreCall(view_module, source); if local.present { var nested = Environment {..}; for index in 0..local.value.len { let argument, error = expression(self_, contract_store, view_module, module_owners, callable_table, local.value.arguments[index], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let error = nested.bind(local.value.bindings[index], argument); if error != blot_error::Error.none { return 0, error; } } return expression(self_, contract_store, view_module, module_owners, callable_table, local.value.body, nested, depth + 1); }
    if self_.input_globals && call.present { let function, error = namedFunction(self_, contract_store, view_module, module_owners, callable_table, call.value.target, call.value.signature, FunctionUse.invocation, depth + 1); if error != blot_error::Error.none { return 0, error; } if !function.present { return 0, blot_error::Error.unavailable; } var arguments: Id[16] = [0;16];
        for index in 0..call.value.len { let argument, error = expression(self_, contract_store, view_module, module_owners, callable_table, call.value.arguments[index], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } arguments[index] = argument; } return contract_store.invoke(function.value, arguments[..call.value.len]);
    } return 0, blot_error::Error.unavailable;
}
recursive fn taskValue(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, source: u32, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    let op, error = blot_check_task_types::opFromCode(value.c); if error != blot_error::Error.none { return 0, blot_error::Error.unavailable; } if value.a > view_module.extra.len || value.b > view_module.extra.len - value.a || value.b != blot_check_task_types::arity(op) { return 0, blot_error::Error.unavailable; } let operands = view_module.extra[value.a..value.a + value.b];
    match op {
        scope, spawn, split => {
            var slot: i64 = 0; if op == blot_check_task_types::Op.spawn { slot = 1; } if op == blot_check_task_types::Op.split { slot = 2; } var callback_id = operands[slot];
            if op == blot_check_task_types::Op.spawn { let result, error = blot_check_task_core::callable(view_module, callback_id); if error != blot_error::Error.none { return 0, blot_error::Error.unavailable; } callback_id = result; }
            let callback_node, error = node(self_, contract_store, view_module, module_owners, callable_table, callback_id, depth + 1); if error != blot_error::Error.none { return 0, error; } if callback_node.tag != blot_check_core::Tag.closure { return 0, blot_error::Error.unavailable; } let callback = view_module.closure(callback_id); var nested = environment; var input: Id = 0;
            if op == blot_check_task_types::Op.split { let plan, error = blot_check_task_regions::partition(view_module, source); if error != blot_error::Error.none { return 0, blot_error::Error.unavailable; } let owner, error = expression(self_, contract_store, view_module, module_owners, callable_table, operands[0], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } var views: Id[16] = [0;16]; for index in 0..plan.len { views[index] = owner; } let id, error = contract_store.aggregate(blot_check_capability_contracts::Tag.product, views[..plan.len]); if error != blot_error::Error.none { return 0, error; } input = id; }
            let error = nested.bind(callback.parameter.binding, input); if error != blot_error::Error.none { return 0, error; } let result, error = expression(self_, contract_store, view_module, module_owners, callable_table, callback.body, nested, depth + 1); if error != blot_error::Error.none { return 0, error; } if op == blot_check_task_types::Op.scope { return result, blot_error::Error.none; }
            let owner, error = expression(self_, contract_store, view_module, module_owners, callable_table, operands[0], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } if op == blot_check_task_types::Op.spawn && self_.input_globals { let captured, error = expression(self_, contract_store, view_module, module_owners, callable_table, callback_id, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let error = inputStore(self_, contract_store, view_module, module_owners, callable_table, captured); if error != blot_error::Error.none { return 0, error; } }
            let children: Id[2] = [owner, result]; return contract_store.aggregate(blot_check_capability_contracts::Tag.product, children);
        },
        join, receive => { let input, error = expression(self_, contract_store, view_module, module_owners, callable_table, operands[0], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } return contract_store.project(input, 1, blot_check_capability_contracts::Projection.index); },
        collect => { let input, error = expression(self_, contract_store, view_module, module_owners, callable_table, operands[0], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let shape = view_module.types.node(view_module.typeOf(operands[0])); if shape.tag != blot_check_types::Tag.product || shape.b > 16 { return 0, blot_error::Error.unavailable; } var results: Id[16] = [0;16];
            for index in 0..shape.b { let item, error = contract_store.project(input, index as u32, blot_check_capability_contracts::Projection.index); if error != blot_error::Error.none { return 0, error; } let result, error = contract_store.project(item, 1, blot_check_capability_contracts::Projection.index); if error != blot_error::Error.none { return 0, error; } results[index] = result; } return contract_store.aggregate(blot_check_capability_contracts::Tag.product, results[..shape.b]);
        },
        cancel, write => { if self_.input_globals { for operand in operands { let input, error = expression(self_, contract_store, view_module, module_owners, callable_table, operand, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let error = inputStore(self_, contract_store, view_module, module_owners, callable_table, input); if error != blot_error::Error.none { return 0, error; } } } return 0, blot_error::Error.none; },
        read => { let tag = view_module.types.node(value.ty).tag; if tag == blot_check_types::Tag.unit || tag == blot_check_types::Tag.boolean || tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32 { return 0, blot_error::Error.none; } let input, error = expression(self_, contract_store, view_module, module_owners, callable_table, operands[0], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } return contract_store.elements(input); },
    }
}
recursive fn aggregateValue(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    if value.a > view_module.extra.len || value.b > view_module.extra.len - value.a || value.b > 2048 { return 0, blot_error::Error.unavailable; } var words: u32[4096] = [0;4096]; let children = view_module.extra[value.a..value.a + value.b];
    if value.tag == blot_check_core::Tag.record { if value.ty >= view_module.types.nodes.len || value.c > view_module.extra.len || value.b > view_module.extra.len - value.c { return 0, blot_error::Error.unavailable; } let record = view_module.types.node(value.ty);
        if record.tag != blot_check_types::Tag.record || record.a > view_module.types.extra.len || record.b > (view_module.types.extra.len - record.a) / 2 { return 0, blot_error::Error.unavailable; }
        for child, index in children { let destination = view_module.extra[value.c + index]; if destination >= record.b { return 0, blot_error::Error.unavailable; } words[index * 2] = view_module.types.extra[record.a + destination * 2]; let result, error = expression(self_, contract_store, view_module, module_owners, callable_table, child, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } words[index * 2 + 1] = result; } return contract_store.aggregate(blot_check_capability_contracts::Tag.record, words[..children.len * 2]);
    }
    for child, index in children { let result, error = expression(self_, contract_store, view_module, module_owners, callable_table, child, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } words[index] = result; if value.tag == blot_check_core::Tag.array { let error = inputStore(self_, contract_store, view_module, module_owners, callable_table, result); if error != blot_error::Error.none { return 0, error; } } } return contract_store.aggregate(blot_check_capability_contracts::Tag.product, words[..children.len]);
}
recursive fn blockValue(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, source: u32, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    if value.a > view_module.extra.len || value.b > view_module.extra.len - value.a { return 0, blot_error::Error.unavailable; } var nested = environment; let children = view_module.extra[value.a..value.a + value.b];
    for child, index in children { let statement, error = node(self_, contract_store, view_module, module_owners, callable_table, child, depth + 1); if error != blot_error::Error.none { return 0, error; } if statement.tag == blot_check_core::Tag.return_ && index + 1 == children.len && statement.b == source { return expression(self_, contract_store, view_module, module_owners, callable_table, statement.a, nested, depth + 1); }
        if statement.tag == blot_check_core::Tag.constant && statement.ty == blot_check_types::unit && statement.op == blot_check_core::Op.none && statement.a == 0 && statement.b == 0 && statement.c == 0 { continue; }
        if statement.tag != blot_check_core::Tag.bind { return 0, blot_error::Error.unavailable; } let result, error = expression(self_, contract_store, view_module, module_owners, callable_table, statement.b, nested, depth + 1); if error != blot_error::Error.none { return 0, error; } let origin, error = callableOrigin(self_, contract_store, view_module, module_owners, callable_table, statement.b, nested, depth + 1); if error != blot_error::Error.none { return 0, error; }
        let error = nested.bind(statement.a, result); if error != blot_error::Error.none { return 0, error; } nested.values[nested.len - 1].callable = origin;
    } return 0, blot_error::Error.unavailable;
}
recursive fn matchValue(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    if value.a >= view_module.matches.len { return 0, blot_error::Error.unavailable; } let info = view_module.matches[value.a]; if info.statement || info.inputs.len > 16 || info.arms.len > 4096 { return 0, blot_error::Error.unavailable; } var retained: Id[16] = [0;16];
    for input, index in view_module.extra[info.inputs.start..info.inputs.start + info.inputs.len] { let result, error = expression(self_, contract_store, view_module, module_owners, callable_table, input, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } retained[index] = result; }
    var arms: Id[4096] = [0;4096]; for arm, index in view_module.match_arms[info.arms.start..info.arms.start + info.arms.len] { var nested = environment; let start = nested.len;
        for row in view_module.pattern_rows[arm.rows.start..arm.rows.start + arm.rows.len] { if row.patterns.len != info.inputs.len { return 0, blot_error::Error.unavailable; } for pattern_id, ordinal in view_module.extra[row.patterns.start..row.patterns.start + row.patterns.len] { let error = pattern(self_, contract_store, view_module, module_owners, callable_table, pattern_id, retained[ordinal], nested, start, depth + 1); if error != blot_error::Error.none { return 0, error; } } }
        if self_.input_globals && arm.guard_ != 0 { let ignored, error = expression(self_, contract_store, view_module, module_owners, callable_table, arm.guard_, nested, depth + 1); if error != blot_error::Error.none { return 0, error; } } let result, error = expression(self_, contract_store, view_module, module_owners, callable_table, arm.body, nested, depth + 1); if error != blot_error::Error.none { return 0, error; } arms[index] = result;
    } return contract_store.aggregate(blot_check_capability_contracts::Tag.join, arms[..info.arms.len]);
}
fn bindPattern(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, environment: Environment&, start: i64, binding: u32, origin: Id) -> Error {
    for index in start..environment.len { let entry .= environment.values[index]; if entry.binding == binding { if entry.value != origin { let children: Id[2] = [entry.value, origin]; let id, error = contract_store.aggregate(blot_check_capability_contracts::Tag.join, children); if error != blot_error::Error.none { return error; } entry.value = id; } return blot_error::Error.none; } } return environment.bind(binding, origin);
}
recursive fn pattern(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, source: u32, origin: Id, environment: Environment&, start: i64, depth: i64) -> Error {
    if source == 0 || source >= view_module.patterns.len || depth >= 128 || self_.remaining == 0 { return blot_error::Error.unavailable; } self_.remaining -= 1; let value = view_module.patterns[source];
    match value.tag {
        wildcard, constant => {},
        bind => { return bindPattern(self_, contract_store, view_module, module_owners, callable_table, environment, start, value.a, origin); },
        constructor => { if value.b != 0 { let payload, error = contract_store.project(origin, 0, blot_check_capability_contracts::Projection.payload); if error != blot_error::Error.none { return error; } return pattern(self_, contract_store, view_module, module_owners, callable_table, value.b, payload, environment, start, depth + 1); } },
        record_payload => { if value.b != 0 { return pattern(self_, contract_store, view_module, module_owners, callable_table, value.b, origin, environment, start, depth + 1); } },
        product => { if value.ty >= view_module.types.nodes.len { return blot_error::Error.unavailable; } let shape = view_module.types.node(value.ty);
            for child, index in view_module.extra[value.a..value.a + value.b] { var selector = index as u32; var kind = blot_check_capability_contracts::Projection.index;
                if shape.tag == blot_check_types::Tag.record { if index >= shape.b { return blot_error::Error.unavailable; } selector = view_module.types.extra[shape.a + index * 2]; kind = blot_check_capability_contracts::Projection.field; }
                let selected, error = contract_store.project(origin, selector, kind); if error != blot_error::Error.none { return error; } let error = pattern(self_, contract_store, view_module, module_owners, callable_table, child, selected, environment, start, depth + 1); if error != blot_error::Error.none { return error; }
            }
        },
        _ => { return blot_error::Error.unavailable; },
    } return blot_error::Error.none;
}
fn captureCallTarget(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, original: blot_check_core::BindingRef, depth: i64) -> Error {
    var target = original; var producer_index:i64=-1;
    for attempt in 0..128 { if self_.remaining == 0 || depth >= 128 { return blot_error::Error.capability_analysis_limit; } self_.remaining -= 1;
        let producer, next_producer_index, error = producerFor(self_, contract_store, view_module, module_owners, callable_table, producer_index, target.unit); if error != blot_error::Error.none { return error; } if !producer { return blot_error::Error.unavailable; } producer_index=next_producer_index;
        if target.binding == 0 || target.binding >= producer.bindings.len { return blot_error::Error.unavailable; } let binding = producer.bindings[target.binding]; if binding.kind == blot_reuse_principal_interface::Kind.external { target = binding.target; continue; }
        if binding.kind != blot_reuse_principal_interface::Kind.global || binding.body_id == 0 || binding.body_id >= producer.bodies.len { return blot_error::Error.unavailable; } return blot_error::Error.none;
    } return blot_error::Error.capability_analysis_limit;
}
recursive fn capture(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, source: u32, environment: const Environment&, captures: Id[4096]&, count: i64&, depth: i64) -> Error {
    let value, error = node(self_, contract_store, view_module, module_owners, callable_table, source, depth); if error != blot_error::Error.none { return error; }
    match value.tag {
        reference => { if value.a >= view_module.references.len { return blot_error::Error.unavailable; } let reference = view_module.references[value.a]; var captured: Id = 0;
            if reference.unit == 0 || reference.unit == view_module.unit { let known = environment.get(reference.binding); if known.present { captured = known.value; }
                else if !self_.input_globals { let result, error = referenceValue(self_, contract_store, view_module, module_owners, callable_table, value.a, value.ty, environment, depth + 1); if error != blot_error::Error.none { return error; } captured = result; }
                else if reference.binding >= view_module.bindings.len || view_module.bindings[reference.binding].kind != blot_reuse_principal_interface::Kind.global { return blot_error::Error.unavailable; }
            } else if !self_.input_globals { return blot_error::Error.unavailable; }
            if captured == 0 { return blot_error::Error.none; } for known in captures[..count] { if known == captured { return blot_error::Error.none; } } if count == captures.len { return blot_error::Error.capability_analysis_limit; } captures[count] = captured; count += 1;
        },
        constant, primitive_function => {},
        operation_value => { if value.a >= view_module.operation_values.len { return blot_error::Error.unavailable; } let receiver = view_module.operation_values[value.a].capability; if receiver != 0 { return capture(self_, contract_store, view_module, module_owners, callable_table, receiver, environment, captures, count, depth + 1); } },
        call => { if value.a >= view_module.calls.len || value.b > view_module.extra.len || value.c > view_module.extra.len - value.b { return blot_error::Error.unavailable; } let error = captureCallTarget(self_, contract_store, view_module, module_owners, callable_table, view_module.calls[value.a].target, depth + 1); if error != blot_error::Error.none { return error; }
            for operand in view_module.extra[value.b..value.b + value.c] { let error = capture(self_, contract_store, view_module, module_owners, callable_table, operand, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } }
        },
        apply, resource_acquire, usage_borrow => { let error = capture(self_, contract_store, view_module, module_owners, callable_table, value.a, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } return capture(self_, contract_store, view_module, module_owners, callable_table, value.b, environment, captures, count, depth + 1); },
        scalar, logical, associated => { let error = capture(self_, contract_store, view_module, module_owners, callable_table, value.a, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } if value.b != 0 { return capture(self_, contract_store, view_module, module_owners, callable_table, value.b, environment, captures, count, depth + 1); } },
        resource_release, usage_share, usage_read, project, return_ => { return capture(self_, contract_store, view_module, module_owners, callable_table, value.a, environment, captures, count, depth + 1); },
        task => { for operand in view_module.children(source) { let error = capture(self_, contract_store, view_module, module_owners, callable_table, operand, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } } },
        resource_scope => { let error = capture(self_, contract_store, view_module, module_owners, callable_table, value.a, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } let error = capture(self_, contract_store, view_module, module_owners, callable_table, value.b, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } return capture(self_, contract_store, view_module, module_owners, callable_table, value.c, environment, captures, count, depth + 1); },
        construct => { if value.a == 0 || value.a >= view_module.constructors.len || (view_module.constructors[value.a].payload == 0) != (value.b == 0) { return blot_error::Error.unavailable; } if value.b != 0 { return capture(self_, contract_store, view_module, module_owners, callable_table, value.b, environment, captures, count, depth + 1); } },
        closure => { if value.a >= view_module.closures.len { return blot_error::Error.unavailable; } let closure = view_module.closures[value.a]; var nested = environment; let error = nested.bind(closure.parameter.binding, 0); if error != blot_error::Error.none { return error; } return capture(self_, contract_store, view_module, module_owners, callable_table, closure.body, nested, captures, count, depth + 1); },
        block_, suite => { if value.a > view_module.extra.len || value.b > view_module.extra.len - value.a { return blot_error::Error.unavailable; } var nested = environment;
            for child in view_module.extra[value.a..value.a + value.b] { let statement, error = node(self_, contract_store, view_module, module_owners, callable_table, child, depth + 1); if error != blot_error::Error.none { return error; }
                if statement.tag == blot_check_core::Tag.bind { let error = capture(self_, contract_store, view_module, module_owners, callable_table, statement.b, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; } let error = nested.bind(statement.a, 0); if error != blot_error::Error.none { return error; } }
                else if statement.tag == blot_check_core::Tag.pattern_bind { let error = capture(self_, contract_store, view_module, module_owners, callable_table, statement.b, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; } if statement.c != 0 { let error = capture(self_, contract_store, view_module, module_owners, callable_table, statement.c, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; } } let start = nested.len; let error = pattern(self_, contract_store, view_module, module_owners, callable_table, statement.a, 0, nested, start, depth + 1); if error != blot_error::Error.none { return error; } }
                else { let error = capture(self_, contract_store, view_module, module_owners, callable_table, child, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; } }
            }
        },
        match_ => { return captureMatch(self_, contract_store, view_module, module_owners, callable_table, value, environment, captures, count, depth); },
        if_value => { let error = capture(self_, contract_store, view_module, module_owners, callable_table, value.a, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } let error = capture(self_, contract_store, view_module, module_owners, callable_table, value.b, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } return capture(self_, contract_store, view_module, module_owners, callable_table, value.c, environment, captures, count, depth + 1); },
        product, record, array, array_op => { if value.a > view_module.extra.len || value.b > view_module.extra.len - value.a { return blot_error::Error.unavailable; } for child in view_module.extra[value.a..value.a + value.b] { let error = capture(self_, contract_store, view_module, module_owners, callable_table, child, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } } },
        _ => { return blot_error::Error.unavailable; },
    } return blot_error::Error.none;
}
recursive fn captureMatch(self_: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, value: blot_check_core::Node, environment: const Environment&, captures: Id[4096]&, count: i64&, depth: i64) -> Error {
    if value.a >= view_module.matches.len { return blot_error::Error.unavailable; } let info = view_module.matches[value.a];
    if info.inputs.len > 16 || info.inputs.start > view_module.extra.len || info.inputs.len > view_module.extra.len - info.inputs.start || info.arms.start > view_module.match_arms.len || info.arms.len > view_module.match_arms.len - info.arms.start { return blot_error::Error.unavailable; }
    for input in view_module.extra[info.inputs.start..info.inputs.start + info.inputs.len] { let error = capture(self_, contract_store, view_module, module_owners, callable_table, input, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } }
    for arm in view_module.match_arms[info.arms.start..info.arms.start + info.arms.len] { if arm.rows.start > view_module.pattern_rows.len || arm.rows.len > view_module.pattern_rows.len - arm.rows.start { return blot_error::Error.unavailable; } var nested = environment; let start = nested.len;
        for row in view_module.pattern_rows[arm.rows.start..arm.rows.start + arm.rows.len] { if row.patterns.len != info.inputs.len || row.patterns.start > view_module.extra.len || row.patterns.len > view_module.extra.len - row.patterns.start { return blot_error::Error.unavailable; }
            for pattern_id in view_module.extra[row.patterns.start..row.patterns.start + row.patterns.len] { let error = pattern(self_, contract_store, view_module, module_owners, callable_table, pattern_id, 0, nested, start, depth + 1); if error != blot_error::Error.none { return error; } }
        }
        if arm.guard_ != 0 { let error = capture(self_, contract_store, view_module, module_owners, callable_table, arm.guard_, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; } } let error = capture(self_, contract_store, view_module, module_owners, callable_table, arm.body, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; }
    } return blot_error::Error.none;
}
fn derive(store: Store&, module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters) -> blot_support::Option<Id>, Error { return deriveWithOwners(store, module, body, summary, []); }
fn deriveWithOwners(store: Store&, module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters, owners: const ModuleRef[:]) -> blot_support::Option<Id>, Error {
    if !blot_check_capability_flow::parameterCoreWithOwners(module, body, summary, owners) || summary.invokes() { return blot_support::none<Id>(), blot_error::Error.none; }
    var arity = summary.arity(); if summary.kind == blot_check_capability_flow::ParameterResult.member_closure_unit || summary.kind == blot_check_capability_flow::ParameterResult.captured_unit { arity += 1; }
    if body.parameters.len != arity || body.parameters.start > module.parameters.len || body.parameters.len > module.parameters.len - body.parameters.start { return blot_support::none<Id>(), blot_error::Error.none; }
    let checkpoint = store.mark(); var callables = Callables {..}; var input_globals = false;
    if body.binding < module.bindings.len { input_globals = module.bindings[body.binding].capability_flow == blot_check_capability_flow::Contract.input_shape; }
    var builder = Builder { input_globals: input_globals, closed_rows: body.closed_rows, ..};
    let result, error = deriveBody(builder, store, module, owners, callables, body, summary); releaseCallables(builder, store, module, owners, callables); if error != blot_error::Error.none { store.rollback(checkpoint); if error == blot_error::Error.unavailable { return blot_support::none<Id>(), blot_error::Error.none; } return blot_support::none<Id>(), error; } return blot_support::some(result), blot_error::Error.none;
}
fn deriveBody(builder: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters) -> Id, Error {
    let empty, error = contract_store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.empty , ..}); if error != blot_error::Error.none { return 0, error; } var environment = Environment {..};
    for parameter, index in view_module.parameters[body.parameters.start..body.parameters.start + summary.arity()] { let id, error = contract_store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.parameter, index as u32 , ..}); if error != blot_error::Error.none { return 0, error; } let error = environment.bind(parameter.binding, id); if error != blot_error::Error.none { return 0, error; } }
    if summary.kind == blot_check_capability_flow::ParameterResult.member_closure_unit || summary.kind == blot_check_capability_flow::ParameterResult.captured_unit {
        let error = environment.bind(view_module.parameters[body.parameters.start + summary.arity()].binding, 0); if error != blot_error::Error.none { return 0, error; } var captures: Id[4096] = [0;4096]; var count: i64 = 0;
        let error = capture(builder, contract_store, view_module, module_owners, callable_table, body.root, environment, captures, count, 0); if error != blot_error::Error.none { return 0, error; } return contract_store.aggregate(blot_check_capability_contracts::Tag.captures, captures[..count]);
    } return expression(builder, contract_store, view_module, module_owners, callable_table, body.root, environment, 0);
}
fn inputBody(module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters) -> bool { return inputBodyWithOwners(module, body, summary, []); }
recursive fn inputBodyWithOwners(module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters, owners: const ModuleRef[:]) -> bool {
    if !summary.valid() || summary.kind != blot_check_capability_flow::ParameterResult.product || summary.arity() == 0 || body.scheme.generative.len != 0 || body.parameters.len != summary.arity() || body.parameters.start > module.parameters.len || body.parameters.len > module.parameters.len - body.parameters.start { return false; }
    let initialized,error=blot_check_capability_contracts::initPooled(); if error!=blot_error::Error.none {return false;} var store=initialized; var callables=Callables{..};
    let budget_slot=validation_budgets.alloc_index(blot_check_logical_scratch_budget::Budget{limit:1048576,..});
    store.node_allocation=blot_check_logical_scratch_budget::ArrayBlock{element_size:16,alignment:4,..}; store.word_allocation=blot_check_logical_scratch_budget::ArrayBlock{element_size:4,alignment:4,..}; store.budget .= validation_budgets[budget_slot];
    var builder=Builder{input_globals:true,closed_rows:body.closed_rows,..};
    let result=inputBodyCheck(builder,store,module,owners,callables,body,summary); releaseCallables(builder,store,module,owners,callables); store.deinit(); validation_budgets.free(budget_slot); return result;
}
recursive fn inputBodyCheck(builder: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters) -> bool {
    let empty,error=contract_store.append(blot_check_capability_contracts::Term{blot_check_capability_contracts::Tag.empty,..}); if error!=blot_error::Error.none || !body.is_function {return false;} var environment=Environment{..};
    for parameter,index in view_module.parameters[body.parameters.start..body.parameters.start+body.parameters.len] {
        if parameter.binding==0 {if index!=0 || parameter.ty!=blot_check_types::unit {return false;} continue;}
        if parameter.binding>=view_module.bindings.len || view_module.bindings[parameter.binding].kind!=blot_reuse_principal_interface::Kind.parameter {return false;}
        let formal,error=contract_store.append(blot_check_capability_contracts::Term{blot_check_capability_contracts::Tag.parameter,index as u32,..}); if error!=blot_error::Error.none || environment.bind(parameter.binding,formal)!=blot_error::Error.none {return false;}
    }
    let root,error=expression(builder,contract_store,view_module,module_owners,callable_table,body.root,environment,0); if error!=blot_error::Error.none || contract_store.view().validate(root,summary.arity(),true)!=blot_error::Error.none {return false;}
    for node in contract_store.nodes.items {if node.tag==blot_check_capability_contracts::Tag.unknown {return false;}}
    let mask,error=contract_store.view().parameterMask(root); return error==blot_error::Error.none && mask==summary.result();
}
fn deriveInputFunctionClosure(store: Store&, module: const Module&, initial: blot_check_core::ClosureInfo, arity: u8) -> blot_support::Option<Id>, Error { return deriveInputFunctionClosureWithOwners(store, module, initial, arity, []); }
fn deriveInputFunctionClosureWithOwners(store: Store&, module: const Module&, initial: blot_check_core::ClosureInfo, arity: u8, owners: const ModuleRef[:]) -> blot_support::Option<Id>, Error {
    if arity == 0 || arity > 16 { return blot_support::none<Id>(), blot_error::Error.none; } let checkpoint = store.mark(); var callables = Callables {..}; var builder = Builder { input_globals: true, ..};
    let root, error = inputFunctionBody(builder, store, module, owners, callables, initial, arity); releaseCallables(builder, store, module, owners, callables); if error != blot_error::Error.none || !root.present { store.rollback(checkpoint); if error == blot_error::Error.unavailable { return blot_support::none<Id>(), blot_error::Error.none; } return root, error; } return root, blot_error::Error.none;
}
fn inputFunctionBody(builder: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, initial: blot_check_core::ClosureInfo, arity: u8) -> blot_support::Option<Id>, Error {
    let empty, error = contract_store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.empty , ..}); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } var environment = Environment {..}; let module .= view_module;
    if initial.captures.start > module.extra.len || initial.captures.len > module.extra.len - initial.captures.start { return blot_support::none<Id>(), blot_error::Error.invalid_capability_contract; }
    for binding in module.extra[initial.captures.start..initial.captures.start + initial.captures.len] { let error = environment.bind(binding, 0); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } }
    var closure = initial;
    for index in 0..arity { let formal, error = contract_store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.parameter, index as u32 , ..}); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } let error = environment.bind(closure.parameter.binding, formal); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
        if index + 1 == arity { let root, error = expression(builder, contract_store, view_module, module_owners, callable_table, closure.body, environment, 0); if error != blot_error::Error.none { if error == blot_error::Error.unavailable { return blot_support::none<Id>(), blot_error::Error.none; } return blot_support::none<Id>(), error; }
            if contract_store.view().validate(root, arity, false) != blot_error::Error.none { return blot_support::none<Id>(), blot_error::Error.none; } return blot_support::some(root), blot_error::Error.none;
        }
        let next, error = node(builder, contract_store, view_module, module_owners, callable_table, closure.body, 0); if error != blot_error::Error.none || next.tag != blot_check_core::Tag.closure || next.a >= module.closures.len { return blot_support::none<Id>(), blot_error::Error.none; } closure = module.closures[next.a];
    } return blot_support::none<Id>(), blot_error::Error.none;
}
fn deriveClosure(store: Store&, module: const Module&, closure: blot_check_core::ClosureInfo) -> blot_support::Option<Id>, Error { return closureResult(store, module, closure, false); }
fn deriveInputClosure(store: Store&, module: const Module&, closure: blot_check_core::ClosureInfo) -> blot_support::Option<Id>, Error {
    let checkpoint = store.mark(); let root, error = closureResult(store, module, closure, true); if error != blot_error::Error.none || !root.present { return root, error; }
    if store.view().validate(root.value, 1, false) != blot_error::Error.none { store.rollback(checkpoint); return blot_support::none<Id>(), blot_error::Error.none; } return root, blot_error::Error.none;
}
fn closureResult(store: Store&, module: const Module&, closure: blot_check_core::ClosureInfo, input_globals: bool) -> blot_support::Option<Id>, Error {
    let checkpoint = store.mark(); var callables = Callables {..}; var builder = Builder { input_globals: input_globals, ..};
    let result, error = closureBody(builder, store, module, default<const ModuleRef[:]>(), callables, closure); releaseCallables(builder, store, module, default<const ModuleRef[:]>(), callables); if error != blot_error::Error.none { store.rollback(checkpoint); if error == blot_error::Error.unavailable { return blot_support::none<Id>(), blot_error::Error.none; } return blot_support::none<Id>(), error; } return blot_support::some(result), blot_error::Error.none;
}
fn closureBody(builder: Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&, closure: blot_check_core::ClosureInfo) -> Id, Error {
    let empty, error = contract_store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.empty , ..}); if error != blot_error::Error.none { return 0, error; } var environment = Environment {..};
    for binding in view_module.extra[closure.captures.start..closure.captures.start + closure.captures.len] { let error = environment.bind(binding, 0); if error != blot_error::Error.none { return 0, error; } }
    let formal, error = contract_store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.parameter , ..}); if error != blot_error::Error.none { return 0, error; } let error = environment.bind(closure.parameter.binding, formal); if error != blot_error::Error.none { return 0, error; } return expression(builder, contract_store, view_module, module_owners, callable_table, closure.body, environment, 0);
}
fn callableValue(store: Store&, module: const Module&, source: u32, owners: const ModuleRef[:]) -> blot_support::Option<Id>, Error {
    let checkpoint = store.mark(); let empty, error = store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.empty , ..}); if error != blot_error::Error.none { store.rollback(checkpoint); return blot_support::none<Id>(), error; }
    var callables = Callables {..}; var reader = Builder { input_globals: true, value_origins: true, ..}; let environment = Environment {..};
    let result, error = expression(reader, store, module, owners, callables, source, environment, 0); releaseCallables(reader, store, module, owners, callables); if error != blot_error::Error.none { store.rollback(checkpoint); if error == blot_error::Error.unavailable { return blot_support::none<Id>(), blot_error::Error.none; } return blot_support::none<Id>(), error; } return blot_support::some(result), blot_error::Error.none;
}

fn functionUseCode(value: FunctionUse) -> u32 {
    match value {
        value => { return 0; },
        invocation => { return 1; },
    }
}
fn functionUseFromCode(code: u32) -> FunctionUse, blot_error::Error {
    match code {
        0 => { return FunctionUse.value, blot_error::Error.none; },
        1 => { return FunctionUse.invocation, blot_error::Error.none; },
        _ => { return FunctionUse.value, blot_error::Error.invalid_artifact; },
    }
}
fn blot_structural::equal(left: blot_check_capability_contract_core::FunctionUse, right: blot_check_capability_contract_core::FunctionUse) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_capability_contract_core::FunctionUse) { blot_structural::hash(sink, blot_check_capability_contract_core::functionUseCode(value) as! u8); }

fn ensureCallables(self_:Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&,minimum:i64)->Error {let budget .= contract_store.budget;if !budget {return blot_error::Error.none;}return blot_check_logical_scratch_budget::ensure(budget,self_.callable_allocation,minimum);}
fn releaseCallables(self_:Builder&, contract_store: Store&, view_module: const Module&, module_owners: const ModuleRef[:], callable_table: Callables&) {let budget .= contract_store.budget;if budget {blot_check_logical_scratch_budget::release(budget,self_.callable_allocation);}blot_support_pooled_buffer::deinit(callable_table,callable_runs);}
reusable var validation_budgets:blot_check_logical_scratch_budget::Budget[>..];
fn deriveWithOwnersBudget(store:Store&,module:const Module&,body:blot_check_core::Body,summary:blot_check_capability_flow::Parameters,owners:const ModuleRef[:],limit:i64=1048576)->blot_support::Option<Id>,Error {
    if store.nodes.len!=0 || store.words.len!=0 || store.budget!=null {return blot_support::none<Id>(),blot_error::Error.invalid_capability_contract;}
    let budget_slot=validation_budgets.alloc_index(blot_check_logical_scratch_budget::Budget{limit:limit, ..});store.node_allocation=blot_check_logical_scratch_budget::ArrayBlock{element_size:16,alignment:4, ..};store.word_allocation=blot_check_logical_scratch_budget::ArrayBlock{element_size:4,alignment:4, ..};store.budget .= validation_budgets[budget_slot];
    let result,error=deriveWithOwners(store,module,body,summary,owners);store.budget .= null;validation_budgets.free(budget_slot);return result,error;
}
