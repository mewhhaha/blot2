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
struct Builder {
    store: Store&, module: const Module&, remaining: i64 = 65536, input_globals: bool = false, value_origins: bool = false,
    owners: const ModuleRef[:] = default<const ModuleRef[:]>(), closed_rows: blot_check_types::List = blot_check_types::List {..}, callables: CallableOrigin[>..<]&,
    callable_allocation: blot_check_logical_scratch_budget::ArrayBlock = blot_check_logical_scratch_budget::ArrayBlock {element_size:3088,alignment:8, ..},
}
fn node(self_: Builder&, source: u32, depth: i64) -> blot_check_core::Node, Error { if depth >= 128 || self_.remaining == 0 { return default<blot_check_core::Node>(), blot_error::Error.capability_analysis_limit; } self_.remaining -= 1; if source == 0 || source >= self_.module.nodes.len { return default<blot_check_core::Node>(), blot_error::Error.unavailable; } return self_.module.nodes[source], blot_error::Error.none; }
fn callableOrigin(self_: Builder&, source: u32, environment: const Environment&, depth: i64) -> blot_support::Option<i64>, Error {
    let value, error = self_.node(source, depth); if error != blot_error::Error.none { return blot_support::none<i64>(), error; }
    if value.tag == blot_check_core::Tag.reference { if value.a >= self_.module.references.len { return blot_support::none<i64>(), blot_error::Error.unavailable; } let reference = self_.module.references[value.a]; if reference.unit != 0 && reference.unit != self_.module.unit { return blot_support::none<i64>(), blot_error::Error.none; }
        let found = environment.alias(reference.binding); if !found.present { return blot_support::none<i64>(), blot_error::Error.none; } return found.value.callable, blot_error::Error.none;
    }
    if value.tag != blot_check_core::Tag.closure { return blot_support::none<i64>(), blot_error::Error.none; } let index = self_.callables.len; let growth = ensureCallables(self_,index+1); if growth != blot_error::Error.none {return blot_support::none<i64>(),growth;} self_.callables += CallableOrigin { source, environment , ..}; return blot_support::some(index), blot_error::Error.none;
}
fn closureCall(self_: Builder&, call: blot_check_capability_flow::LocalCoreCall, environment: const Environment&, depth: i64) -> blot_support::Option<Id>, Error {
    if call.len != 1 || (call.target.unit != 0 && call.target.unit != self_.module.unit) { return blot_support::none<Id>(), blot_error::Error.none; } let found = environment.alias(call.target.binding); if !found.present || !found.value.callable.present { return blot_support::none<Id>(), blot_error::Error.none; }
    let origin = found.value.callable.value; if origin >= self_.callables.len { return blot_support::none<Id>(), blot_error::Error.unavailable; } let source = self_.callables[origin].source; let value, error = self_.node(source, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    if value.tag != blot_check_core::Tag.closure || value.a >= self_.module.closures.len { return blot_support::none<Id>(), blot_error::Error.unavailable; } let callback = self_.module.closures[value.a];
    let argument, error = expression(self_, call.arguments[0], environment, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } var callee = self_.callables[origin].environment;
    if callback.parameter.binding != 0 { let error = callee.bind(callback.parameter.binding, argument); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } }
    let result, error = expression(self_, callback.body, callee, depth + 1); return blot_support::some(result), error;
}
enum FunctionUse { value, invocation }
fn producerFor(self_: Builder&, producer: const Module&, unit: u32) -> const Module?, Error {
    if unit == 0 || unit == producer.unit { return producer, blot_error::Error.none; } var selected: const Module? = null;
    for owner_owner_ref in self_.owners { let owner: const blot_check_core::Module&  = owner_owner_ref.value; if self_.remaining == 0 { return null, blot_error::Error.capability_analysis_limit; } self_.remaining -= 1; if owner.unit != unit { continue; }
        if selected { if selected.owner_id == 0 || selected.owner_id != owner.owner_id { return null, blot_error::Error.unavailable; } } selected .= owner;
    } return selected, blot_error::Error.none;
}
fn namedFunction(self_: Builder&, original: blot_check_core::BindingRef, actual: u32, use: FunctionUse, depth: i64) -> blot_support::Option<Id>, Error {
    var target = original; var producer: const Module&  = self_.module;
    for attempt in 0..128 { if self_.remaining == 0 || depth >= 128 { return blot_support::none<Id>(), blot_error::Error.capability_analysis_limit; } self_.remaining -= 1;
        let selected, error = producerFor(self_, producer, target.unit); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if !selected { return blot_support::none<Id>(), blot_error::Error.none; } producer .= selected;
        if target.binding == 0 || target.binding >= producer.bindings.len { return blot_support::none<Id>(), blot_error::Error.unavailable; } let binding = producer.bindings[target.binding]; if binding.kind == blot_reuse_principal_interface::Kind.external { target = binding.target; continue; }
        if binding.kind != blot_reuse_principal_interface::Kind.global || binding.body_id == 0 || binding.body_id >= producer.bodies.len || binding.scheme.generative.len != 0 { return blot_support::none<Id>(), blot_error::Error.none; } let body = producer.bodies[binding.body_id]; if !body.is_function { return blot_support::none<Id>(), blot_error::Error.none; }
        if use == FunctionUse.value && binding.capability_flow != blot_check_capability_flow::Contract.identity && binding.capability_flow != blot_check_capability_flow::Contract.input_shape { return blot_support::none<Id>(), blot_error::Error.none; }
        let relocation, error = blot_check_generative_relocation::init(producer, self_.module, binding.scheme, actual, actual, 0, 0); if error != blot_error::Error.none { return blot_support::none<Id>(), blot_error::Error.unavailable; } let work = 65536 - relocation.remaining; if work > self_.remaining { return blot_support::none<Id>(), blot_error::Error.capability_analysis_limit; } self_.remaining -= work;
        var arity = binding.capability_parameters.arity();
        if binding.capability_flow == blot_check_capability_flow::Contract.identity { if !blot_check_capability_flow::unaryCore(producer, body, blot_check_capability_flow::Contract.identity) { return blot_support::none<Id>(), blot_error::Error.unavailable; } arity = 1; }
        else if binding.capability_flow != blot_check_capability_flow::Contract.input_shape && (binding.capability_flow != blot_check_capability_flow::Contract.unknown || binding.capability_parameters.kind != blot_check_capability_flow::ParameterResult.product || !binding.capability_parameters.valid() || !binding.capability_parameters.present()) { return blot_support::none<Id>(), blot_error::Error.none; }
        if arity == 0 || arity > 16 || body.parameters.len != arity || body.parameters.start > producer.parameters.len || body.parameters.len > producer.parameters.len - body.parameters.start { return blot_support::none<Id>(), blot_error::Error.unavailable; }
        var callables: CallableOrigin[>..<] = []; var reader = Builder { store: self_.store, module: producer, remaining: self_.remaining, input_globals: true, owners: self_.owners, closed_rows: body.closed_rows, callables: callables , ..};
        let result, error = namedBody(reader, producer, body, binding, arity, depth); releaseCallables(reader); self_.remaining = reader.remaining; return result, error;
    } return blot_support::none<Id>(), blot_error::Error.capability_analysis_limit;
}
fn namedBody(reader: Builder&, producer: const Module&, body: blot_check_core::Body, binding: blot_check_core::Binding, arity: u8, depth: i64) -> blot_support::Option<Id>, Error {
    var parameters = Environment {..};
    for parameter, index in producer.parameters[body.parameters.start..body.parameters.start + arity] {
        if parameter.binding == 0 { if index != 0 || parameter.ty != blot_check_types::unit { return blot_support::none<Id>(), blot_error::Error.unavailable; } continue; }
        if parameter.binding >= producer.bindings.len || producer.bindings[parameter.binding].kind != blot_reuse_principal_interface::Kind.parameter { return blot_support::none<Id>(), blot_error::Error.unavailable; }
        let id, error = reader.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.argument, index as u32 , ..}); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } let error = parameters.bind(parameter.binding, id); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    }
    let result, error = expression(reader, body.root, parameters, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } var expected = binding.capability_parameters.result(); if binding.capability_flow == blot_check_capability_flow::Contract.identity { expected = 1; }
    let mask, error = reader.store.view().argumentMask(result, reader.remaining); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if mask != expected { return blot_support::none<Id>(), blot_error::Error.unavailable; }
    let function, error = reader.store.append(blot_check_capability_contracts::Term { tag: blot_check_capability_contracts::Tag.callable, a: arity, c: result , ..}); return blot_support::some(function), error;
}
fn reference(self_: Builder&, catalog: u32, actual: u32, environment: const Environment&, depth: i64) -> Id, Error {
    if catalog >= self_.module.references.len { return 0, blot_error::Error.unavailable; } let value = self_.module.references[catalog];
    if value.unit == 0 || value.unit == self_.module.unit { let known = environment.get(value.binding); if known.present { return known.value, blot_error::Error.none; }
        if self_.value_origins && value.binding < self_.module.bindings.len { let binding = self_.module.bindings[value.binding]; if binding.kind == blot_reuse_principal_interface::Kind.local && binding.initializer != 0 { return expression(self_, binding.initializer, environment, depth + 1); } if binding.kind == blot_reuse_principal_interface::Kind.parameter { return 0, blot_error::Error.none; } }
    }
    if self_.input_globals { let function, error = namedFunction(self_, value, actual, FunctionUse.value, depth + 1); if error != blot_error::Error.none { return 0, error; } if function.present { return function.value, blot_error::Error.none; }
        if value.unit != 0 && value.unit != self_.module.unit { return 0, blot_error::Error.none; } if value.binding < self_.module.bindings.len && self_.module.bindings[value.binding].kind == blot_reuse_principal_interface::Kind.global { return 0, blot_error::Error.none; }
    }
    if value.unit != 0 && value.unit != self_.module.unit { return 0, blot_error::Error.unavailable; } let found = environment.get(value.binding); if !found.present { return 0, blot_error::Error.unavailable; } return found.value, blot_error::Error.none;
}
fn inputStore(self_: Builder&, root: Id) -> Error { if self_.input_globals { let contains, error = self_.store.view().containsParameter(root, self_.remaining); if error != blot_error::Error.none { return error; } if contains { return blot_error::Error.unavailable; } } return blot_error::Error.none; }
recursive fn expression(self_: Builder&, source: u32, environment: const Environment&, depth: i64) -> Id, Error {
    let value, error = self_.node(source, depth); if error != blot_error::Error.none { return 0, error; }
    match value.tag {
        call, apply => { return application(self_, source, value, environment, depth); },
        reference => { return reference(self_, value.a, value.ty, environment, depth + 1); },
        computation => { let child, error = expression(self_, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let error = inputStore(self_, child); if error != blot_error::Error.none { return 0, error; } return self_.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.wrapped, child , ..}); },
        effect_provider, state_provider => { var children: Id[3]; let a, error = expression(self_, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } children[0] = a; let b, error = expression(self_, value.b, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } children[1] = b; var count: i64 = 2;
            if value.tag == blot_check_core::Tag.state_provider { let c, error = expression(self_, value.c, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } children[2] = c; count = 3; } for child in children[..count] { let error = inputStore(self_, child); if error != blot_error::Error.none { return 0, error; } } return self_.store.aggregate(blot_check_capability_contracts::Tag.captures, children[..count]);
        },
        usage_borrow => { if value.b >= self_.module.nodes.len || self_.module.nodes[value.b].tag != blot_check_core::Tag.closure { return 0, blot_error::Error.unavailable; } let callback = self_.module.closure(value.b); var nested = environment;
            let argument, error = expression(self_, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let error = nested.bind(callback.parameter.binding, argument); if error != blot_error::Error.none { return 0, error; } return expression(self_, callback.body, nested, depth + 1);
        },
        task => { return taskValue(self_, source, value, environment, depth); },
        usage_share => { return expression(self_, value.a, environment, depth + 1); },
        resource_acquire, resource_release, resource_scope, usage_read, scalar, logical => {
            if self_.input_globals { if value.tag == blot_check_core::Tag.resource_acquire || value.tag == blot_check_core::Tag.resource_release || value.tag == blot_check_core::Tag.resource_scope { return 0, blot_error::Error.unavailable; }
                let ignored, error = expression(self_, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } if (value.tag == blot_check_core::Tag.scalar || value.tag == blot_check_core::Tag.logical) && value.b != 0 { let ignored, error = expression(self_, value.b, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } }
            } return scalarValue(self_, value.ty);
        },
        constant => { return scalarValue(self_, value.ty); },
        construct => { var child: Id = 0; if value.b != 0 { let id, error = expression(self_, value.b, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } child = id; } return self_.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.wrapped, child , ..}); },
        product, array, record => { return aggregateValue(self_, value, environment, depth); },
        array_op => {
            if value.c != blot_backend_collection_ops::opCode(blot_backend_collection_ops::Op.get) || value.b != 2 || value.a > self_.module.extra.len || value.b > self_.module.extra.len - value.a { return 0, blot_error::Error.unavailable; }
            let receiver, error = expression(self_, self_.module.extra[value.a], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let index, error = self_.node(self_.module.extra[value.a + 1], depth + 1); if error != blot_error::Error.none { return 0, error; }
            if index.tag != blot_check_core::Tag.constant || index.ty >= self_.module.types.nodes.len || self_.module.types.nodes[index.ty].tag != blot_check_types::Tag.unsigned32 { return self_.store.elements(receiver); } return self_.store.project(receiver, index.a, blot_check_capability_contracts::Projection.index);
        },
        operation_value => { if value.a >= self_.module.operation_values.len { return 0, blot_error::Error.unavailable; } let receiver, error = expression(self_, self_.module.operation_values[value.a].capability, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let children: Id[1] = [receiver]; return self_.store.aggregate(blot_check_capability_contracts::Tag.captures, children); },
        project => { if value.b >= self_.module.projections.len { return 0, blot_error::Error.unavailable; } let projection = self_.module.projections[value.b]; var selector = projection.field; var kind = blot_check_capability_contracts::Projection.field;
            if projection.field == 0 { if projection.nominal.unit != 0 || projection.nominal.decl != 0 || projection.variants.len != 1 || projection.variants.start >= self_.module.projection_variants.len { return 0, blot_error::Error.unavailable; } let variant = self_.module.projection_variants[projection.variants.start]; if variant.tag != 0 { return 0, blot_error::Error.unavailable; } selector = variant.field; kind = blot_check_capability_contracts::Projection.index; }
            let receiver, error = expression(self_, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } return self_.store.project(receiver, selector, kind);
        },
        if_value => { if self_.input_globals { let ignored, error = expression(self_, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } } let left, error = expression(self_, value.b, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let right, error = expression(self_, value.c, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let children: Id[2] = [left, right]; return self_.store.aggregate(blot_check_capability_contracts::Tag.join, children); },
        block_ => { return blockValue(self_, source, value, environment, depth); },
        match_ => { return matchValue(self_, value, environment, depth); },
        closure => { if value.a >= self_.module.closures.len { return 0, blot_error::Error.unavailable; } let closure = self_.module.closures[value.a]; var nested = environment; let error = nested.bind(closure.parameter.binding, 0); if error != blot_error::Error.none { return 0, error; }
            var captures: Id[4096]; var count: i64 = 0; let error = capture(self_, closure.body, nested, captures, count, depth + 1); if error != blot_error::Error.none { return 0, error; } for child in captures[..count] { let error = inputStore(self_, child); if error != blot_error::Error.none { return 0, error; } } return self_.store.aggregate(blot_check_capability_contracts::Tag.captures, captures[..count]);
        },
        _ => { return 0, blot_error::Error.unavailable; },
    }
}
fn scalarValue(self_: Builder&, ty: u32) -> Id, Error {
    if ty >= self_.module.types.nodes.len { return 0, blot_error::Error.unavailable; } let tag = self_.module.types.nodes[ty].tag;
    if tag == blot_check_types::Tag.unit || tag == blot_check_types::Tag.boolean || tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32 { return 0, blot_error::Error.none; } return 0, blot_error::Error.unavailable;
}
fn application(self_: Builder&, source: u32, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    let call = blot_check_capability_flow::coreCall(self_.module, source); if call.present { let result, error = closureCall(self_, call.value, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } if result.present { return result.value, blot_error::Error.none; } }
    if self_.input_globals && value.tag == blot_check_core::Tag.apply { let argument, error = self_.node(value.b, depth + 1); if error != blot_error::Error.none { return 0, error; } let callee, error = self_.node(value.a, depth + 1); if error != blot_error::Error.none { return 0, error; }
        if argument.tag == blot_check_core::Tag.constant && argument.ty == blot_check_types::unit && argument.a == 0 && callee.tag == blot_check_core::Tag.operation_value { if value.ty >= self_.module.types.nodes.len { return 0, blot_error::Error.unavailable; } let ignored, error = expression(self_, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let tag = self_.module.types.node(value.ty).tag;
            if tag == blot_check_types::Tag.unit || tag == blot_check_types::Tag.boolean || tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32 || tag == blot_check_types::Tag.never { return 0, blot_error::Error.none; } return self_.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.unknown , ..});
        }
    }
    let local = blot_check_capability_flow::localCoreCall(self_.module, source); if local.present { var nested = Environment {..}; for index in 0..local.value.len { let argument, error = expression(self_, local.value.arguments[index], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let error = nested.bind(local.value.bindings[index], argument); if error != blot_error::Error.none { return 0, error; } } return expression(self_, local.value.body, nested, depth + 1); }
    if self_.input_globals && call.present { let function, error = namedFunction(self_, call.value.target, call.value.signature, FunctionUse.invocation, depth + 1); if error != blot_error::Error.none { return 0, error; } if !function.present { return 0, blot_error::Error.unavailable; } var arguments: Id[16];
        for index in 0..call.value.len { let argument, error = expression(self_, call.value.arguments[index], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } arguments[index] = argument; } return self_.store.invoke(function.value, arguments[..call.value.len]);
    } return 0, blot_error::Error.unavailable;
}
fn taskValue(self_: Builder&, source: u32, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    let op, error = blot_check_task_types::opFromCode(value.c); if error != blot_error::Error.none { return 0, blot_error::Error.unavailable; } if value.a > self_.module.extra.len || value.b > self_.module.extra.len - value.a || value.b != blot_check_task_types::arity(op) { return 0, blot_error::Error.unavailable; } let operands = self_.module.extra[value.a..value.a + value.b];
    match op {
        scope, spawn, split => {
            var slot: i64 = 0; if op == blot_check_task_types::Op.spawn { slot = 1; } if op == blot_check_task_types::Op.split { slot = 2; } var callback_id = operands[slot];
            if op == blot_check_task_types::Op.spawn { let result, error = blot_check_task_core::callable(self_.module, callback_id); if error != blot_error::Error.none { return 0, blot_error::Error.unavailable; } callback_id = result; }
            let callback_node, error = self_.node(callback_id, depth + 1); if error != blot_error::Error.none { return 0, error; } if callback_node.tag != blot_check_core::Tag.closure { return 0, blot_error::Error.unavailable; } let callback = self_.module.closure(callback_id); var nested = environment; var input: Id = 0;
            if op == blot_check_task_types::Op.split { let plan, error = blot_check_task_regions::partition(self_.module, source); if error != blot_error::Error.none { return 0, blot_error::Error.unavailable; } let owner, error = expression(self_, operands[0], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } var views: Id[16]; for index in 0..plan.len { views[index] = owner; } let id, error = self_.store.aggregate(blot_check_capability_contracts::Tag.product, views[..plan.len]); if error != blot_error::Error.none { return 0, error; } input = id; }
            let error = nested.bind(callback.parameter.binding, input); if error != blot_error::Error.none { return 0, error; } let result, error = expression(self_, callback.body, nested, depth + 1); if error != blot_error::Error.none { return 0, error; } if op == blot_check_task_types::Op.scope { return result, blot_error::Error.none; }
            let owner, error = expression(self_, operands[0], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } if op == blot_check_task_types::Op.spawn && self_.input_globals { let captured, error = expression(self_, callback_id, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let error = inputStore(self_, captured); if error != blot_error::Error.none { return 0, error; } }
            let children: Id[2] = [owner, result]; return self_.store.aggregate(blot_check_capability_contracts::Tag.product, children);
        },
        join, receive => { let input, error = expression(self_, operands[0], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } return self_.store.project(input, 1, blot_check_capability_contracts::Projection.index); },
        collect => { let input, error = expression(self_, operands[0], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let shape = self_.module.types.node(self_.module.typeOf(operands[0])); if shape.tag != blot_check_types::Tag.product || shape.b > 16 { return 0, blot_error::Error.unavailable; } var results: Id[16];
            for index in 0..shape.b { let item, error = self_.store.project(input, index as u32, blot_check_capability_contracts::Projection.index); if error != blot_error::Error.none { return 0, error; } let result, error = self_.store.project(item, 1, blot_check_capability_contracts::Projection.index); if error != blot_error::Error.none { return 0, error; } results[index] = result; } return self_.store.aggregate(blot_check_capability_contracts::Tag.product, results[..shape.b]);
        },
        cancel, write => { if self_.input_globals { for operand in operands { let input, error = expression(self_, operand, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let error = inputStore(self_, input); if error != blot_error::Error.none { return 0, error; } } } return 0, blot_error::Error.none; },
        read => { let tag = self_.module.types.node(value.ty).tag; if tag == blot_check_types::Tag.unit || tag == blot_check_types::Tag.boolean || tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32 { return 0, blot_error::Error.none; } let input, error = expression(self_, operands[0], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } return self_.store.elements(input); },
    }
}
fn aggregateValue(self_: Builder&, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    if value.a > self_.module.extra.len || value.b > self_.module.extra.len - value.a || value.b > 2048 { return 0, blot_error::Error.unavailable; } var words: u32[4096]; let children = self_.module.extra[value.a..value.a + value.b];
    if value.tag == blot_check_core::Tag.record { if value.ty >= self_.module.types.nodes.len || value.c > self_.module.extra.len || value.b > self_.module.extra.len - value.c { return 0, blot_error::Error.unavailable; } let record = self_.module.types.node(value.ty);
        if record.tag != blot_check_types::Tag.record || record.a > self_.module.types.extra.len || record.b > (self_.module.types.extra.len - record.a) / 2 { return 0, blot_error::Error.unavailable; }
        for child, index in children { let destination = self_.module.extra[value.c + index]; if destination >= record.b { return 0, blot_error::Error.unavailable; } words[index * 2] = self_.module.types.extra[record.a + destination * 2]; let result, error = expression(self_, child, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } words[index * 2 + 1] = result; } return self_.store.aggregate(blot_check_capability_contracts::Tag.record, words[..children.len * 2]);
    }
    for child, index in children { let result, error = expression(self_, child, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } words[index] = result; if value.tag == blot_check_core::Tag.array { let error = inputStore(self_, result); if error != blot_error::Error.none { return 0, error; } } } return self_.store.aggregate(blot_check_capability_contracts::Tag.product, words[..children.len]);
}
fn blockValue(self_: Builder&, source: u32, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    if value.a > self_.module.extra.len || value.b > self_.module.extra.len - value.a { return 0, blot_error::Error.unavailable; } var nested = environment; let children = self_.module.extra[value.a..value.a + value.b];
    for child, index in children { let statement, error = self_.node(child, depth + 1); if error != blot_error::Error.none { return 0, error; } if statement.tag == blot_check_core::Tag.return_ && index + 1 == children.len && statement.b == source { return expression(self_, statement.a, nested, depth + 1); }
        if statement.tag == blot_check_core::Tag.constant && statement.ty == blot_check_types::unit && statement.op == blot_check_core::Op.none && statement.a == 0 && statement.b == 0 && statement.c == 0 { continue; }
        if statement.tag != blot_check_core::Tag.bind { return 0, blot_error::Error.unavailable; } let result, error = expression(self_, statement.b, nested, depth + 1); if error != blot_error::Error.none { return 0, error; } let origin, error = callableOrigin(self_, statement.b, nested, depth + 1); if error != blot_error::Error.none { return 0, error; }
        let error = nested.bind(statement.a, result); if error != blot_error::Error.none { return 0, error; } nested.values[nested.len - 1].callable = origin;
    } return 0, blot_error::Error.unavailable;
}
fn matchValue(self_: Builder&, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    if value.a >= self_.module.matches.len { return 0, blot_error::Error.unavailable; } let info = self_.module.matches[value.a]; if info.statement || info.inputs.len > 16 || info.arms.len > 4096 { return 0, blot_error::Error.unavailable; } var retained: Id[16];
    for input, index in self_.module.extra[info.inputs.start..info.inputs.start + info.inputs.len] { let result, error = expression(self_, input, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } retained[index] = result; }
    var arms: Id[4096]; for arm, index in self_.module.match_arms[info.arms.start..info.arms.start + info.arms.len] { var nested = environment; let start = nested.len;
        for row in self_.module.pattern_rows[arm.rows.start..arm.rows.start + arm.rows.len] { if row.patterns.len != info.inputs.len { return 0, blot_error::Error.unavailable; } for pattern_id, ordinal in self_.module.extra[row.patterns.start..row.patterns.start + row.patterns.len] { let error = pattern(self_, pattern_id, retained[ordinal], nested, start, depth + 1); if error != blot_error::Error.none { return 0, error; } } }
        if self_.input_globals && arm.guard_ != 0 { let ignored, error = expression(self_, arm.guard_, nested, depth + 1); if error != blot_error::Error.none { return 0, error; } } let result, error = expression(self_, arm.body, nested, depth + 1); if error != blot_error::Error.none { return 0, error; } arms[index] = result;
    } return self_.store.aggregate(blot_check_capability_contracts::Tag.join, arms[..info.arms.len]);
}
fn bindPattern(self_: Builder&, environment: Environment&, start: i64, binding: u32, origin: Id) -> Error {
    for index in start..environment.len { let entry .= environment.values[index]; if entry.binding == binding { if entry.value != origin { let children: Id[2] = [entry.value, origin]; let id, error = self_.store.aggregate(blot_check_capability_contracts::Tag.join, children); if error != blot_error::Error.none { return error; } entry.value = id; } return blot_error::Error.none; } } return environment.bind(binding, origin);
}
recursive fn pattern(self_: Builder&, source: u32, origin: Id, environment: Environment&, start: i64, depth: i64) -> Error {
    if source == 0 || source >= self_.module.patterns.len || depth >= 128 || self_.remaining == 0 { return blot_error::Error.unavailable; } self_.remaining -= 1; let value = self_.module.patterns[source];
    match value.tag {
        wildcard, constant => {},
        bind => { return bindPattern(self_, environment, start, value.a, origin); },
        constructor => { if value.b != 0 { let payload, error = self_.store.project(origin, 0, blot_check_capability_contracts::Projection.payload); if error != blot_error::Error.none { return error; } return pattern(self_, value.b, payload, environment, start, depth + 1); } },
        record_payload => { if value.b != 0 { return pattern(self_, value.b, origin, environment, start, depth + 1); } },
        product => { if value.ty >= self_.module.types.nodes.len { return blot_error::Error.unavailable; } let shape = self_.module.types.node(value.ty);
            for child, index in self_.module.extra[value.a..value.a + value.b] { var selector = index as u32; var kind = blot_check_capability_contracts::Projection.index;
                if shape.tag == blot_check_types::Tag.record { if index >= shape.b { return blot_error::Error.unavailable; } selector = self_.module.types.extra[shape.a + index * 2]; kind = blot_check_capability_contracts::Projection.field; }
                let selected, error = self_.store.project(origin, selector, kind); if error != blot_error::Error.none { return error; } let error = pattern(self_, child, selected, environment, start, depth + 1); if error != blot_error::Error.none { return error; }
            }
        },
        _ => { return blot_error::Error.unavailable; },
    } return blot_error::Error.none;
}
fn captureCallTarget(self_: Builder&, original: blot_check_core::BindingRef, depth: i64) -> Error {
    var target = original; var producer: const Module&  = self_.module;
    for attempt in 0..128 { if self_.remaining == 0 || depth >= 128 { return blot_error::Error.capability_analysis_limit; } self_.remaining -= 1;
        let selected, error = producerFor(self_, producer, target.unit); if error != blot_error::Error.none { return error; } if !selected { return blot_error::Error.unavailable; } producer .= selected;
        if target.binding == 0 || target.binding >= producer.bindings.len { return blot_error::Error.unavailable; } let binding = producer.bindings[target.binding]; if binding.kind == blot_reuse_principal_interface::Kind.external { target = binding.target; continue; }
        if binding.kind != blot_reuse_principal_interface::Kind.global || binding.body_id == 0 || binding.body_id >= producer.bodies.len { return blot_error::Error.unavailable; } return blot_error::Error.none;
    } return blot_error::Error.capability_analysis_limit;
}
recursive fn capture(self_: Builder&, source: u32, environment: const Environment&, captures: Id[4096]&, count: i64&, depth: i64) -> Error {
    let value, error = self_.node(source, depth); if error != blot_error::Error.none { return error; }
    match value.tag {
        reference => { if value.a >= self_.module.references.len { return blot_error::Error.unavailable; } let reference = self_.module.references[value.a]; var captured: Id = 0;
            if reference.unit == 0 || reference.unit == self_.module.unit { let known = environment.get(reference.binding); if known.present { captured = known.value; }
                else if !self_.input_globals { let result, error = self_.reference(value.a, value.ty, environment, depth + 1); if error != blot_error::Error.none { return error; } captured = result; }
                else if reference.binding >= self_.module.bindings.len || self_.module.bindings[reference.binding].kind != blot_reuse_principal_interface::Kind.global { return blot_error::Error.unavailable; }
            } else if !self_.input_globals { return blot_error::Error.unavailable; }
            if captured == 0 { return blot_error::Error.none; } for known in captures[..count] { if known == captured { return blot_error::Error.none; } } if count == captures.len { return blot_error::Error.capability_analysis_limit; } captures[count] = captured; count += 1;
        },
        constant, primitive_function => {},
        operation_value => { if value.a >= self_.module.operation_values.len { return blot_error::Error.unavailable; } let receiver = self_.module.operation_values[value.a].capability; if receiver != 0 { return capture(self_, receiver, environment, captures, count, depth + 1); } },
        call => { if value.a >= self_.module.calls.len || value.b > self_.module.extra.len || value.c > self_.module.extra.len - value.b { return blot_error::Error.unavailable; } let error = captureCallTarget(self_, self_.module.calls[value.a].target, depth + 1); if error != blot_error::Error.none { return error; }
            for operand in self_.module.extra[value.b..value.b + value.c] { let error = capture(self_, operand, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } }
        },
        apply, resource_acquire, usage_borrow => { let error = capture(self_, value.a, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } return capture(self_, value.b, environment, captures, count, depth + 1); },
        scalar, logical, associated => { let error = capture(self_, value.a, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } if value.b != 0 { return capture(self_, value.b, environment, captures, count, depth + 1); } },
        resource_release, usage_share, usage_read, project, return_ => { return capture(self_, value.a, environment, captures, count, depth + 1); },
        task => { for operand in self_.module.children(source) { let error = capture(self_, operand, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } } },
        resource_scope => { let error = capture(self_, value.a, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } let error = capture(self_, value.b, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } return capture(self_, value.c, environment, captures, count, depth + 1); },
        construct => { if value.a == 0 || value.a >= self_.module.constructors.len || (self_.module.constructors[value.a].payload == 0) != (value.b == 0) { return blot_error::Error.unavailable; } if value.b != 0 { return capture(self_, value.b, environment, captures, count, depth + 1); } },
        closure => { if value.a >= self_.module.closures.len { return blot_error::Error.unavailable; } let closure = self_.module.closures[value.a]; var nested = environment; let error = nested.bind(closure.parameter.binding, 0); if error != blot_error::Error.none { return error; } return capture(self_, closure.body, nested, captures, count, depth + 1); },
        block_, suite => { if value.a > self_.module.extra.len || value.b > self_.module.extra.len - value.a { return blot_error::Error.unavailable; } var nested = environment;
            for child in self_.module.extra[value.a..value.a + value.b] { let statement, error = self_.node(child, depth + 1); if error != blot_error::Error.none { return error; }
                if statement.tag == blot_check_core::Tag.bind { let error = capture(self_, statement.b, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; } let error = nested.bind(statement.a, 0); if error != blot_error::Error.none { return error; } }
                else if statement.tag == blot_check_core::Tag.pattern_bind { let error = capture(self_, statement.b, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; } if statement.c != 0 { let error = capture(self_, statement.c, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; } } let start = nested.len; let error = pattern(self_, statement.a, 0, nested, start, depth + 1); if error != blot_error::Error.none { return error; } }
                else { let error = capture(self_, child, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; } }
            }
        },
        match_ => { return captureMatch(self_, value, environment, captures, count, depth); },
        if_value => { let error = capture(self_, value.a, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } let error = capture(self_, value.b, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } return capture(self_, value.c, environment, captures, count, depth + 1); },
        product, record, array, array_op => { if value.a > self_.module.extra.len || value.b > self_.module.extra.len - value.a { return blot_error::Error.unavailable; } for child in self_.module.extra[value.a..value.a + value.b] { let error = capture(self_, child, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } } },
        _ => { return blot_error::Error.unavailable; },
    } return blot_error::Error.none;
}
fn captureMatch(self_: Builder&, value: blot_check_core::Node, environment: const Environment&, captures: Id[4096]&, count: i64&, depth: i64) -> Error {
    if value.a >= self_.module.matches.len { return blot_error::Error.unavailable; } let info = self_.module.matches[value.a];
    if info.inputs.len > 16 || info.inputs.start > self_.module.extra.len || info.inputs.len > self_.module.extra.len - info.inputs.start || info.arms.start > self_.module.match_arms.len || info.arms.len > self_.module.match_arms.len - info.arms.start { return blot_error::Error.unavailable; }
    for input in self_.module.extra[info.inputs.start..info.inputs.start + info.inputs.len] { let error = capture(self_, input, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } }
    for arm in self_.module.match_arms[info.arms.start..info.arms.start + info.arms.len] { if arm.rows.start > self_.module.pattern_rows.len || arm.rows.len > self_.module.pattern_rows.len - arm.rows.start { return blot_error::Error.unavailable; } var nested = environment; let start = nested.len;
        for row in self_.module.pattern_rows[arm.rows.start..arm.rows.start + arm.rows.len] { if row.patterns.len != info.inputs.len || row.patterns.start > self_.module.extra.len || row.patterns.len > self_.module.extra.len - row.patterns.start { return blot_error::Error.unavailable; }
            for pattern_id in self_.module.extra[row.patterns.start..row.patterns.start + row.patterns.len] { let error = pattern(self_, pattern_id, 0, nested, start, depth + 1); if error != blot_error::Error.none { return error; } }
        }
        if arm.guard_ != 0 { let error = capture(self_, arm.guard_, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; } } let error = capture(self_, arm.body, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; }
    } return blot_error::Error.none;
}
fn derive(store: Store&, module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters) -> blot_support::Option<Id>, Error { return deriveWithOwners(store, module, body, summary, []); }
fn deriveWithOwners(store: Store&, module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters, owners: const ModuleRef[:]) -> blot_support::Option<Id>, Error {
    if !blot_check_capability_flow::parameterCoreWithOwners(module, body, summary, owners) || summary.invokes() { return blot_support::none<Id>(), blot_error::Error.none; }
    var arity = summary.arity(); if summary.kind == blot_check_capability_flow::ParameterResult.member_closure_unit || summary.kind == blot_check_capability_flow::ParameterResult.captured_unit { arity += 1; }
    if body.parameters.len != arity || body.parameters.start > module.parameters.len || body.parameters.len > module.parameters.len - body.parameters.start { return blot_support::none<Id>(), blot_error::Error.none; }
    let checkpoint = store.mark(); var callables: CallableOrigin[>..<] = []; var input_globals = false;
    if body.binding < module.bindings.len { input_globals = module.bindings[body.binding].capability_flow == blot_check_capability_flow::Contract.input_shape; }
    var builder = Builder { store: store, module: module, owners: owners, input_globals: input_globals, closed_rows: body.closed_rows, callables: callables , ..};
    let result, error = deriveBody(builder, body, summary); releaseCallables(builder); if error != blot_error::Error.none { store.rollback(checkpoint); if error == blot_error::Error.unavailable { return blot_support::none<Id>(), blot_error::Error.none; } return blot_support::none<Id>(), error; } return blot_support::some(result), blot_error::Error.none;
}
fn deriveBody(builder: Builder&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters) -> Id, Error {
    let empty, error = builder.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.empty , ..}); if error != blot_error::Error.none { return 0, error; } var environment = Environment {..};
    for parameter, index in builder.module.parameters[body.parameters.start..body.parameters.start + summary.arity()] { let id, error = builder.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.parameter, index as u32 , ..}); if error != blot_error::Error.none { return 0, error; } let error = environment.bind(parameter.binding, id); if error != blot_error::Error.none { return 0, error; } }
    if summary.kind == blot_check_capability_flow::ParameterResult.member_closure_unit || summary.kind == blot_check_capability_flow::ParameterResult.captured_unit {
        let error = environment.bind(builder.module.parameters[body.parameters.start + summary.arity()].binding, 0); if error != blot_error::Error.none { return 0, error; } var captures: Id[4096]; var count: i64 = 0;
        let error = capture(builder, body.root, environment, captures, count, 0); if error != blot_error::Error.none { return 0, error; } return builder.store.aggregate(blot_check_capability_contracts::Tag.captures, captures[..count]);
    } return expression(builder, body.root, environment, 0);
}
struct InputBodyCheck { module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters, owners: const ModuleRef[:], result: bool = false }
fn inputBody(module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters) -> bool { return inputBodyWithOwners(module, body, summary, []); }
fn inputBodyWithOwners(module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters, owners: const ModuleRef[:]) -> bool {
    if !summary.valid() || summary.kind != blot_check_capability_flow::ParameterResult.product || summary.arity() == 0 || body.scheme.generative.len != 0 || body.parameters.len != summary.arity() || body.parameters.start > module.parameters.len || body.parameters.len > module.parameters.len - body.parameters.start { return false; }
    var context = InputBodyCheck { module, body, summary, owners , ..}; let error = blot_check_capability_contracts::withStore<InputBodyCheck>(context,inputBodyCheck); return error == blot_error::Error.none && context.result;
}
fn inputBodyCheck(context: InputBodyCheck&, store: Store&) -> Error {
    let empty, error = store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.empty , ..}); if error != blot_error::Error.none { return blot_error::Error.none; } var callables: CallableOrigin[>..<] = [];
    var builder = Builder { store: store, module: context.module, owners: context.owners, input_globals: true, closed_rows: context.body.closed_rows, callables: callables , ..}; var environment = Environment {..}; if !context.body.is_function { return blot_error::Error.none; }
    for parameter, index in context.module.parameters[context.body.parameters.start..context.body.parameters.start + context.body.parameters.len] {
        if parameter.binding == 0 { if index != 0 || parameter.ty != blot_check_types::unit { return blot_error::Error.none; } continue; }
        if parameter.binding >= context.module.bindings.len || context.module.bindings[parameter.binding].kind != blot_reuse_principal_interface::Kind.parameter { return blot_error::Error.none; }
        let formal, error = store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.parameter, index as u32 , ..}); if error != blot_error::Error.none { return blot_error::Error.none; } if environment.bind(parameter.binding, formal) != blot_error::Error.none { return blot_error::Error.none; }
    }
    let root, error = expression(builder, context.body.root, environment, 0); if error != blot_error::Error.none || store.view().validate(root, context.summary.arity(), true) != blot_error::Error.none { return blot_error::Error.none; } for node in store.nodes.items { if node.tag == blot_check_capability_contracts::Tag.unknown { return blot_error::Error.none; } }
    let mask, error = store.view().parameterMask(root); context.result = error == blot_error::Error.none && mask == context.summary.result(); return blot_error::Error.none;
}
fn deriveInputFunctionClosure(store: Store&, module: const Module&, initial: blot_check_core::ClosureInfo, arity: u8) -> blot_support::Option<Id>, Error { return deriveInputFunctionClosureWithOwners(store, module, initial, arity, []); }
fn deriveInputFunctionClosureWithOwners(store: Store&, module: const Module&, initial: blot_check_core::ClosureInfo, arity: u8, owners: const ModuleRef[:]) -> blot_support::Option<Id>, Error {
    if arity == 0 || arity > 16 { return blot_support::none<Id>(), blot_error::Error.none; } let checkpoint = store.mark(); var callables: CallableOrigin[>..<] = []; var builder = Builder { store: store, module: module, input_globals: true, owners: owners, callables: callables , ..};
    let root, error = inputFunctionBody(builder, initial, arity); if error != blot_error::Error.none || !root.present { store.rollback(checkpoint); if error == blot_error::Error.unavailable { return blot_support::none<Id>(), blot_error::Error.none; } return root, error; } return root, blot_error::Error.none;
}
fn inputFunctionBody(builder: Builder&, initial: blot_check_core::ClosureInfo, arity: u8) -> blot_support::Option<Id>, Error {
    let empty, error = builder.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.empty , ..}); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } var environment = Environment {..}; let module = builder.module;
    if initial.captures.start > module.extra.len || initial.captures.len > module.extra.len - initial.captures.start { return blot_support::none<Id>(), blot_error::Error.invalid_capability_contract; }
    for binding in module.extra[initial.captures.start..initial.captures.start + initial.captures.len] { let error = environment.bind(binding, 0); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } }
    var closure = initial;
    for index in 0..arity { let formal, error = builder.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.parameter, index as u32 , ..}); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } let error = environment.bind(closure.parameter.binding, formal); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
        if index + 1 == arity { let root, error = expression(builder, closure.body, environment, 0); if error != blot_error::Error.none { if error == blot_error::Error.unavailable { return blot_support::none<Id>(), blot_error::Error.none; } return blot_support::none<Id>(), error; }
            if builder.store.view().validate(root, arity, false) != blot_error::Error.none { return blot_support::none<Id>(), blot_error::Error.none; } return blot_support::some(root), blot_error::Error.none;
        }
        let next, error = builder.node(closure.body, 0); if error != blot_error::Error.none || next.tag != blot_check_core::Tag.closure || next.a >= module.closures.len { return blot_support::none<Id>(), blot_error::Error.none; } closure = module.closures[next.a];
    } return blot_support::none<Id>(), blot_error::Error.none;
}
fn deriveClosure(store: Store&, module: const Module&, closure: blot_check_core::ClosureInfo) -> blot_support::Option<Id>, Error { return closureResult(store, module, closure, false); }
fn deriveInputClosure(store: Store&, module: const Module&, closure: blot_check_core::ClosureInfo) -> blot_support::Option<Id>, Error {
    let checkpoint = store.mark(); let root, error = closureResult(store, module, closure, true); if error != blot_error::Error.none || !root.present { return root, error; }
    if store.view().validate(root.value, 1, false) != blot_error::Error.none { store.rollback(checkpoint); return blot_support::none<Id>(), blot_error::Error.none; } return root, blot_error::Error.none;
}
fn closureResult(store: Store&, module: const Module&, closure: blot_check_core::ClosureInfo, input_globals: bool) -> blot_support::Option<Id>, Error {
    let checkpoint = store.mark(); var callables: CallableOrigin[>..<] = []; var builder = Builder { store: store, module: module, input_globals: input_globals, callables: callables , ..};
    let result, error = closureBody(builder, closure); if error != blot_error::Error.none { store.rollback(checkpoint); if error == blot_error::Error.unavailable { return blot_support::none<Id>(), blot_error::Error.none; } return blot_support::none<Id>(), error; } return blot_support::some(result), blot_error::Error.none;
}
fn closureBody(builder: Builder&, closure: blot_check_core::ClosureInfo) -> Id, Error {
    let empty, error = builder.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.empty , ..}); if error != blot_error::Error.none { return 0, error; } var environment = Environment {..};
    for binding in builder.module.extra[closure.captures.start..closure.captures.start + closure.captures.len] { let error = environment.bind(binding, 0); if error != blot_error::Error.none { return 0, error; } }
    let formal, error = builder.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.parameter , ..}); if error != blot_error::Error.none { return 0, error; } let error = environment.bind(closure.parameter.binding, formal); if error != blot_error::Error.none { return 0, error; } return expression(builder, closure.body, environment, 0);
}
fn callableValue(store: Store&, module: const Module&, source: u32, owners: const ModuleRef[:]) -> blot_support::Option<Id>, Error {
    let checkpoint = store.mark(); let empty, error = store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.empty , ..}); if error != blot_error::Error.none { store.rollback(checkpoint); return blot_support::none<Id>(), error; }
    var callables: CallableOrigin[>..<] = []; var reader = Builder { store: store, module: module, owners: owners, input_globals: true, value_origins: true, callables: callables , ..}; let environment = Environment {..};
    let result, error = expression(reader, source, environment, 0); if error != blot_error::Error.none { store.rollback(checkpoint); if error == blot_error::Error.unavailable { return blot_support::none<Id>(), blot_error::Error.none; } return blot_support::none<Id>(), error; } return blot_support::some(result), blot_error::Error.none;
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

fn ensureCallables(self_:Builder&,minimum:i64)->Error {let budget .= self_.store.budget;if !budget {return blot_error::Error.none;}return blot_check_logical_scratch_budget::ensure(budget,self_.callable_allocation,minimum);}
fn releaseCallables(self_:Builder&) {let budget .= self_.store.budget;if budget {blot_check_logical_scratch_budget::release(budget,self_.callable_allocation);}}
fn deriveWithOwnersBudget(store:Store&,module:const Module&,body:blot_check_core::Body,summary:blot_check_capability_flow::Parameters,owners:const ModuleRef[:],limit:i64=1048576)->blot_support::Option<Id>,Error {
    if store.nodes.len!=0 || store.words.len!=0 || store.budget!=null {return blot_support::none<Id>(),blot_error::Error.invalid_capability_contract;}
    var budget=blot_check_logical_scratch_budget::Budget{limit:limit, ..};store.node_allocation=blot_check_logical_scratch_budget::ArrayBlock{element_size:16,alignment:4, ..};store.word_allocation=blot_check_logical_scratch_budget::ArrayBlock{element_size:4,alignment:4, ..};store.budget .= budget;
    let result,error=deriveWithOwners(store,module,body,summary,owners);store.budget .= null;return result,error;
}
