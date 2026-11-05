// Core independently reconstructs result paths; capture catalogs grant nothing.
namespace blot_check_capability_contract_core;
import .frozen_core_validation;
type ModuleRef = blot_check_frozen_core_validation::ModuleRef;
import support.structural;
import support.error;
import support.option;
import .capability_contracts;
import .logical_scratch_budget;
type Error = blot_error::Error;
type Id = u32;
type Module = blot_check_core::Module;
type Store = blot_check_capability_contracts::Store;
type Tag = blot_check_capability_contracts::Tag;
struct Alias { binding: u32, value: Id, callable: blot_support::Option<i64> = blot_support::none<i64>() }
struct Environment { values: Alias[128], len: i64 = 0 }
fn bind(self: Environment&, binding: u32, value: Id) -> Error { if self.len == self.values.len { return Error.capability_analysis_limit; } self.values[self.len] = Alias { binding, value }; self.len += 1; return Error.none; }
fn alias(self: const Environment&, binding: u32) -> blot_support::Option<Alias> { var index = self.len; while index != 0 { index -= 1; if self.values[index].binding == binding { return blot_support::some(self.values[index]); } } return blot_support::none<Alias>(); }
fn get(self: const Environment&, binding: u32) -> blot_support::Option<Id> { let found = self.alias(binding); if !found.present { return blot_support::none<Id>(); } return blot_support::some(found.value.value); }
struct CallableOrigin { source: u32, environment: Environment }
struct Builder {
    store: Store&, module: const Module&, remaining: i64 = 65536, input_globals: bool = false, value_origins: bool = false,
    owners: const ModuleRef[:] = [], closed_rows: blot_check_types::List = blot_check_types::List {}, callables: CallableOrigin[>..<]&,
    callable_allocation: blot_check_logical_scratch_budget::ArrayBlock = blot_check_logical_scratch_budget::ArrayBlock {element_size:3088,alignment:8},
}
fn node(self: Builder&, source: u32, depth: i64) -> blot_check_core::Node, Error { if depth >= 128 || self.remaining == 0 { return default<blot_check_core::Node>(), Error.capability_analysis_limit; } self.remaining -= 1; if source == 0 || source >= self.module.nodes.len { return default<blot_check_core::Node>(), Error.unavailable; } return self.module.nodes[source], Error.none; }
fn callableOrigin(self: Builder&, source: u32, environment: const Environment&, depth: i64) -> blot_support::Option<i64>, Error {
    let value, error = self.node(source, depth); if error != Error.none { return blot_support::none<i64>(), error; }
    if value.tag == blot_check_core::Tag.reference { if value.a >= self.module.references.len { return blot_support::none<i64>(), Error.unavailable; } let reference = self.module.references[value.a]; if reference.unit != 0 && reference.unit != self.module.unit { return blot_support::none<i64>(), Error.none; }
        let found = environment.alias(reference.binding); if !found.present { return blot_support::none<i64>(), Error.none; } return found.value.callable, Error.none;
    }
    if value.tag != blot_check_core::Tag.closure { return blot_support::none<i64>(), Error.none; } let index = self.callables.len; let growth = ensureCallables(self,index+1); if growth != Error.none {return blot_support::none<i64>(),growth;} self.callables += CallableOrigin { source, environment }; return blot_support::some(index), Error.none;
}
fn closureCall(self: Builder&, call: blot_check_capability_flow::LocalCoreCall, environment: const Environment&, depth: i64) -> blot_support::Option<Id>, Error {
    if call.len != 1 || (call.target.unit != 0 && call.target.unit != self.module.unit) { return blot_support::none<Id>(), Error.none; } let found = environment.alias(call.target.binding); if !found.present || !found.value.callable.present { return blot_support::none<Id>(), Error.none; }
    let origin = found.value.callable.value; if origin >= self.callables.len { return blot_support::none<Id>(), Error.unavailable; } let source = self.callables[origin].source; let value, error = self.node(source, depth + 1); if error != Error.none { return blot_support::none<Id>(), error; }
    if value.tag != blot_check_core::Tag.closure || value.a >= self.module.closures.len { return blot_support::none<Id>(), Error.unavailable; } let callback = self.module.closures[value.a];
    let argument, error = expression(self, call.arguments[0], environment, depth + 1); if error != Error.none { return blot_support::none<Id>(), error; } var callee = self.callables[origin].environment;
    if callback.parameter.binding != 0 { let error = callee.bind(callback.parameter.binding, argument); if error != Error.none { return blot_support::none<Id>(), error; } }
    let result, error = expression(self, callback.body, callee, depth + 1); return blot_support::some(result), error;
}
enum FunctionUse { value, invocation }
fn producerFor(self: Builder&, producer: const Module&, unit: u32) -> const Module?, Error {
    if unit == 0 || unit == producer.unit { return producer, Error.none; } var selected: const Module? = null;
    for owner_owner_ref in self.owners { let owner: const blot_check_core::Module& = owner_owner_ref.value; if self.remaining == 0 { return null, Error.capability_analysis_limit; } self.remaining -= 1; if owner.unit != unit { continue; }
        if selected { if selected.owner_id == 0 || selected.owner_id != owner.owner_id { return null, Error.unavailable; } } selected .= owner;
    } return selected, Error.none;
}
fn namedFunction(self: Builder&, original: blot_check_core::BindingRef, actual: u32, use: FunctionUse, depth: i64) -> blot_support::Option<Id>, Error {
    var target = original; var producer: const Module& = self.module;
    for attempt in 0..128 { if self.remaining == 0 || depth >= 128 { return blot_support::none<Id>(), Error.capability_analysis_limit; } self.remaining -= 1;
        let selected, error = producerFor(self, producer, target.unit); if error != Error.none { return blot_support::none<Id>(), error; } if !selected { return blot_support::none<Id>(), Error.none; } producer .= selected;
        if target.binding == 0 || target.binding >= producer.bindings.len { return blot_support::none<Id>(), Error.unavailable; } let binding = producer.bindings[target.binding]; if binding.kind == blot_check_check::Kind.external { target = binding.target; continue; }
        if binding.kind != blot_check_check::Kind.global || binding.body_id == 0 || binding.body_id >= producer.bodies.len || binding.scheme.generative.len != 0 { return blot_support::none<Id>(), Error.none; } let body = producer.bodies[binding.body_id]; if !body.is_function { return blot_support::none<Id>(), Error.none; }
        if use == FunctionUse.value && binding.capability_flow != blot_check_capability_flow::Contract.identity && binding.capability_flow != blot_check_capability_flow::Contract.input_shape { return blot_support::none<Id>(), Error.none; }
        let relocation, error = blot_check_generative_relocation::init(producer, self.module, binding.scheme, actual, actual, 0, 0); if error != Error.none { return blot_support::none<Id>(), Error.unavailable; } let work = 65536 - relocation.remaining; if work > self.remaining { return blot_support::none<Id>(), Error.capability_analysis_limit; } self.remaining -= work;
        var arity = binding.capability_parameters.arity();
        if binding.capability_flow == blot_check_capability_flow::Contract.identity { if !blot_check_capability_flow::unaryCore(producer, body, blot_check_capability_flow::Contract.identity) { return blot_support::none<Id>(), Error.unavailable; } arity = 1; }
        else if binding.capability_flow != blot_check_capability_flow::Contract.input_shape && (binding.capability_flow != blot_check_capability_flow::Contract.unknown || binding.capability_parameters.kind != blot_check_capability_flow::ParameterResult.product || !binding.capability_parameters.valid() || !binding.capability_parameters.present()) { return blot_support::none<Id>(), Error.none; }
        if arity == 0 || arity > 16 || body.parameters.len != arity || body.parameters.start > producer.parameters.len || body.parameters.len > producer.parameters.len - body.parameters.start { return blot_support::none<Id>(), Error.unavailable; }
        var callables: CallableOrigin[>..<] = []; var reader = Builder { self.store, producer, remaining: self.remaining, input_globals: true, owners: self.owners, closed_rows: body.closed_rows, callables };
        let result, error = namedBody(reader, producer, body, binding, arity, depth); releaseCallables(reader); self.remaining = reader.remaining; return result, error;
    } return blot_support::none<Id>(), Error.capability_analysis_limit;
}
fn namedBody(reader: Builder&, producer: const Module&, body: blot_check_core::Body, binding: blot_check_core::Binding, arity: u8, depth: i64) -> blot_support::Option<Id>, Error {
    var parameters = Environment {};
    for parameter, index in producer.parameters[body.parameters.start..body.parameters.start + arity] {
        if parameter.binding == 0 { if index != 0 || parameter.ty != blot_check_types::unit { return blot_support::none<Id>(), Error.unavailable; } continue; }
        if parameter.binding >= producer.bindings.len || producer.bindings[parameter.binding].kind != blot_check_check::Kind.parameter { return blot_support::none<Id>(), Error.unavailable; }
        let id, error = reader.store.append(blot_check_capability_contracts::Term { Tag.argument, index as u32 }); if error != Error.none { return blot_support::none<Id>(), error; } let error = parameters.bind(parameter.binding, id); if error != Error.none { return blot_support::none<Id>(), error; }
    }
    let result, error = expression(reader, body.root, parameters, depth + 1); if error != Error.none { return blot_support::none<Id>(), error; } var expected = binding.capability_parameters.result(); if binding.capability_flow == blot_check_capability_flow::Contract.identity { expected = 1; }
    let mask, error = reader.store.view().argumentMask(result, reader.remaining); if error != Error.none { return blot_support::none<Id>(), error; } if mask != expected { return blot_support::none<Id>(), Error.unavailable; }
    let function, error = reader.store.append(blot_check_capability_contracts::Term { Tag.callable, arity, c: result }); return blot_support::some(function), error;
}
fn reference(self: Builder&, catalog: u32, actual: u32, environment: const Environment&, depth: i64) -> Id, Error {
    if catalog >= self.module.references.len { return 0, Error.unavailable; } let value = self.module.references[catalog];
    if value.unit == 0 || value.unit == self.module.unit { let known = environment.get(value.binding); if known.present { return known.value, Error.none; }
        if self.value_origins && value.binding < self.module.bindings.len { let binding = self.module.bindings[value.binding]; if binding.kind == blot_check_check::Kind.local && binding.initializer != 0 { return expression(self, binding.initializer, environment, depth + 1); } if binding.kind == blot_check_check::Kind.parameter { return 0, Error.none; } }
    }
    if self.input_globals { let function, error = namedFunction(self, value, actual, FunctionUse.value, depth + 1); if error != Error.none { return 0, error; } if function.present { return function.value, Error.none; }
        if value.unit != 0 && value.unit != self.module.unit { return 0, Error.none; } if value.binding < self.module.bindings.len && self.module.bindings[value.binding].kind == blot_check_check::Kind.global { return 0, Error.none; }
    }
    if value.unit != 0 && value.unit != self.module.unit { return 0, Error.unavailable; } let found = environment.get(value.binding); if !found.present { return 0, Error.unavailable; } return found.value, Error.none;
}
fn inputStore(self: Builder&, root: Id) -> Error { if self.input_globals { let contains, error = self.store.view().containsParameter(root, self.remaining); if error != Error.none { return error; } if contains { return Error.unavailable; } } return Error.none; }
recursive fn expression(self: Builder&, source: u32, environment: const Environment&, depth: i64) -> Id, Error {
    let value, error = self.node(source, depth); if error != Error.none { return 0, error; }
    match value.tag {
        blot_check_core::Tag.call, blot_check_core::Tag.apply => { return application(self, source, value, environment, depth); },
        blot_check_core::Tag.reference => { return reference(self, value.a, value.ty, environment, depth + 1); },
        blot_check_core::Tag.computation => { let child, error = expression(self, value.a, environment, depth + 1); if error != Error.none { return 0, error; } let error = inputStore(self, child); if error != Error.none { return 0, error; } return self.store.append(blot_check_capability_contracts::Term { Tag.wrapped, child }); },
        blot_check_core::Tag.effect_provider, blot_check_core::Tag.state_provider => { var children: Id[3]; let a, error = expression(self, value.a, environment, depth + 1); if error != Error.none { return 0, error; } children[0] = a; let b, error = expression(self, value.b, environment, depth + 1); if error != Error.none { return 0, error; } children[1] = b; var count: i64 = 2;
            if value.tag == blot_check_core::Tag.state_provider { let c, error = expression(self, value.c, environment, depth + 1); if error != Error.none { return 0, error; } children[2] = c; count = 3; } for child in children[..count] { let error = inputStore(self, child); if error != Error.none { return 0, error; } } return self.store.aggregate(Tag.captures, children[..count]);
        },
        blot_check_core::Tag.usage_borrow => { if value.b >= self.module.nodes.len || self.module.nodes[value.b].tag != blot_check_core::Tag.closure { return 0, Error.unavailable; } let callback = self.module.closure(value.b); var nested = environment;
            let argument, error = expression(self, value.a, environment, depth + 1); if error != Error.none { return 0, error; } let error = nested.bind(callback.parameter.binding, argument); if error != Error.none { return 0, error; } return expression(self, callback.body, nested, depth + 1);
        },
        blot_check_core::Tag.task => { return taskValue(self, source, value, environment, depth); },
        blot_check_core::Tag.usage_share => { return expression(self, value.a, environment, depth + 1); },
        blot_check_core::Tag.resource_acquire, blot_check_core::Tag.resource_release, blot_check_core::Tag.resource_scope, blot_check_core::Tag.usage_read, blot_check_core::Tag.scalar, blot_check_core::Tag.logical => {
            if self.input_globals { if value.tag == blot_check_core::Tag.resource_acquire || value.tag == blot_check_core::Tag.resource_release || value.tag == blot_check_core::Tag.resource_scope { return 0, Error.unavailable; }
                let ignored, error = expression(self, value.a, environment, depth + 1); if error != Error.none { return 0, error; } if (value.tag == blot_check_core::Tag.scalar || value.tag == blot_check_core::Tag.logical) && value.b != 0 { let ignored, error = expression(self, value.b, environment, depth + 1); if error != Error.none { return 0, error; } }
            } return scalarValue(self, value.ty);
        },
        blot_check_core::Tag.constant => { return scalarValue(self, value.ty); },
        blot_check_core::Tag.construct => { var child: Id = 0; if value.b != 0 { let id, error = expression(self, value.b, environment, depth + 1); if error != Error.none { return 0, error; } child = id; } return self.store.append(blot_check_capability_contracts::Term { Tag.wrapped, child }); },
        blot_check_core::Tag.product, blot_check_core::Tag.array, blot_check_core::Tag.record => { return aggregateValue(self, value, environment, depth); },
        blot_check_core::Tag.array_op => {
            if value.c != blot_backend_collection_ops::opCode(blot_check_core::ArrayOp.get) || value.b != 2 || value.a > self.module.extra.len || value.b > self.module.extra.len - value.a { return 0, Error.unavailable; }
            let receiver, error = expression(self, self.module.extra[value.a], environment, depth + 1); if error != Error.none { return 0, error; } let index, error = self.node(self.module.extra[value.a + 1], depth + 1); if error != Error.none { return 0, error; }
            if index.tag != blot_check_core::Tag.constant || index.ty >= self.module.types.nodes.len || self.module.types.nodes[index.ty].tag != blot_check_types::Tag.unsigned32 { return self.store.elements(receiver); } return self.store.project(receiver, index.a, blot_check_capability_contracts::Projection.index);
        },
        blot_check_core::Tag.operation_value => { if value.a >= self.module.operation_values.len { return 0, Error.unavailable; } let receiver, error = expression(self, self.module.operation_values[value.a].capability, environment, depth + 1); if error != Error.none { return 0, error; } let children: Id[1] = [receiver]; return self.store.aggregate(Tag.captures, children); },
        blot_check_core::Tag.project => { if value.b >= self.module.projections.len { return 0, Error.unavailable; } let projection = self.module.projections[value.b]; var selector = projection.field; var kind = blot_check_capability_contracts::Projection.field;
            if projection.field == 0 { if projection.nominal.unit != 0 || projection.nominal.decl != 0 || projection.variants.len != 1 || projection.variants.start >= self.module.projection_variants.len { return 0, Error.unavailable; } let variant = self.module.projection_variants[projection.variants.start]; if variant.tag != 0 { return 0, Error.unavailable; } selector = variant.field; kind = blot_check_capability_contracts::Projection.index; }
            let receiver, error = expression(self, value.a, environment, depth + 1); if error != Error.none { return 0, error; } return self.store.project(receiver, selector, kind);
        },
        blot_check_core::Tag.if_value => { if self.input_globals { let ignored, error = expression(self, value.a, environment, depth + 1); if error != Error.none { return 0, error; } } let left, error = expression(self, value.b, environment, depth + 1); if error != Error.none { return 0, error; } let right, error = expression(self, value.c, environment, depth + 1); if error != Error.none { return 0, error; } let children: Id[2] = [left, right]; return self.store.aggregate(Tag.join, children); },
        blot_check_core::Tag.block_ => { return blockValue(self, source, value, environment, depth); },
        blot_check_core::Tag.match_ => { return matchValue(self, value, environment, depth); },
        blot_check_core::Tag.closure => { if value.a >= self.module.closures.len { return 0, Error.unavailable; } let closure = self.module.closures[value.a]; var nested = environment; let error = nested.bind(closure.parameter.binding, 0); if error != Error.none { return 0, error; }
            var captures: Id[4096]; var count: i64 = 0; let error = capture(self, closure.body, nested, captures, count, depth + 1); if error != Error.none { return 0, error; } for child in captures[..count] { let error = inputStore(self, child); if error != Error.none { return 0, error; } } return self.store.aggregate(Tag.captures, captures[..count]);
        },
        _ => { return 0, Error.unavailable; },
    }
}
fn scalarValue(self: Builder&, ty: u32) -> Id, Error {
    if ty >= self.module.types.nodes.len { return 0, Error.unavailable; } let tag = self.module.types.nodes[ty].tag;
    if tag == blot_check_types::Tag.unit || tag == blot_check_types::Tag.boolean || tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32 { return 0, Error.none; } return 0, Error.unavailable;
}
fn application(self: Builder&, source: u32, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    let call = blot_check_capability_flow::coreCall(self.module, source); if call.present { let result, error = closureCall(self, call.value, environment, depth + 1); if error != Error.none { return 0, error; } if result.present { return result.value, Error.none; } }
    if self.input_globals && value.tag == blot_check_core::Tag.apply { let argument, error = self.node(value.b, depth + 1); if error != Error.none { return 0, error; } let callee, error = self.node(value.a, depth + 1); if error != Error.none { return 0, error; }
        if argument.tag == blot_check_core::Tag.constant && argument.ty == blot_check_types::unit && argument.a == 0 && callee.tag == blot_check_core::Tag.operation_value { if value.ty >= self.module.types.nodes.len { return 0, Error.unavailable; } let ignored, error = expression(self, value.a, environment, depth + 1); if error != Error.none { return 0, error; } let tag = self.module.types.node(value.ty).tag;
            if tag == blot_check_types::Tag.unit || tag == blot_check_types::Tag.boolean || tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32 || tag == blot_check_types::Tag.never { return 0, Error.none; } return self.store.append(blot_check_capability_contracts::Term { Tag.unknown });
        }
    }
    let local = blot_check_capability_flow::localCoreCall(self.module, source); if local.present { var nested = Environment {}; for index in 0..local.value.len { let argument, error = expression(self, local.value.arguments[index], environment, depth + 1); if error != Error.none { return 0, error; } let error = nested.bind(local.value.bindings[index], argument); if error != Error.none { return 0, error; } } return expression(self, local.value.body, nested, depth + 1); }
    if self.input_globals && call.present { let function, error = namedFunction(self, call.value.target, call.value.signature, FunctionUse.invocation, depth + 1); if error != Error.none { return 0, error; } if !function.present { return 0, Error.unavailable; } var arguments: Id[16];
        for index in 0..call.value.len { let argument, error = expression(self, call.value.arguments[index], environment, depth + 1); if error != Error.none { return 0, error; } arguments[index] = argument; } return self.store.invoke(function.value, arguments[..call.value.len]);
    } return 0, Error.unavailable;
}
fn taskValue(self: Builder&, source: u32, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    let op, error = blot_check_task_types::opFromCode(value.c); if error != Error.none { return 0, Error.unavailable; } if value.a > self.module.extra.len || value.b > self.module.extra.len - value.a || value.b != blot_check_task_types::arity(op) { return 0, Error.unavailable; } let operands = self.module.extra[value.a..value.a + value.b];
    match op {
        blot_check_task_types::Op.scope, blot_check_task_types::Op.spawn, blot_check_task_types::Op.split => {
            var slot: i64 = 0; if op == blot_check_task_types::Op.spawn { slot = 1; } if op == blot_check_task_types::Op.split { slot = 2; } var callback_id = operands[slot];
            if op == blot_check_task_types::Op.spawn { let result, error = blot_check_task_core::callable(self.module, callback_id); if error != Error.none { return 0, Error.unavailable; } callback_id = result; }
            let callback_node, error = self.node(callback_id, depth + 1); if error != Error.none { return 0, error; } if callback_node.tag != blot_check_core::Tag.closure { return 0, Error.unavailable; } let callback = self.module.closure(callback_id); var nested = environment; var input: Id = 0;
            if op == blot_check_task_types::Op.split { let plan, error = blot_check_task_regions::partition(self.module, source); if error != Error.none { return 0, Error.unavailable; } let owner, error = expression(self, operands[0], environment, depth + 1); if error != Error.none { return 0, error; } var views: Id[16]; for index in 0..plan.len { views[index] = owner; } let id, error = self.store.aggregate(Tag.product, views[..plan.len]); if error != Error.none { return 0, error; } input = id; }
            let error = nested.bind(callback.parameter.binding, input); if error != Error.none { return 0, error; } let result, error = expression(self, callback.body, nested, depth + 1); if error != Error.none { return 0, error; } if op == blot_check_task_types::Op.scope { return result, Error.none; }
            let owner, error = expression(self, operands[0], environment, depth + 1); if error != Error.none { return 0, error; } if op == blot_check_task_types::Op.spawn && self.input_globals { let captured, error = expression(self, callback_id, environment, depth + 1); if error != Error.none { return 0, error; } let error = inputStore(self, captured); if error != Error.none { return 0, error; } }
            let children: Id[2] = [owner, result]; return self.store.aggregate(Tag.product, children);
        },
        blot_check_task_types::Op.join, blot_check_task_types::Op.receive => { let input, error = expression(self, operands[0], environment, depth + 1); if error != Error.none { return 0, error; } return self.store.project(input, 1, blot_check_capability_contracts::Projection.index); },
        blot_check_task_types::Op.collect => { let input, error = expression(self, operands[0], environment, depth + 1); if error != Error.none { return 0, error; } let shape = self.module.types.node(self.module.typeOf(operands[0])); if shape.tag != blot_check_types::Tag.product || shape.b > 16 { return 0, Error.unavailable; } var results: Id[16];
            for index in 0..shape.b { let item, error = self.store.project(input, index as u32, blot_check_capability_contracts::Projection.index); if error != Error.none { return 0, error; } let result, error = self.store.project(item, 1, blot_check_capability_contracts::Projection.index); if error != Error.none { return 0, error; } results[index] = result; } return self.store.aggregate(Tag.product, results[..shape.b]);
        },
        blot_check_task_types::Op.cancel, blot_check_task_types::Op.write => { if self.input_globals { for operand in operands { let input, error = expression(self, operand, environment, depth + 1); if error != Error.none { return 0, error; } let error = inputStore(self, input); if error != Error.none { return 0, error; } } } return 0, Error.none; },
        blot_check_task_types::Op.read => { let tag = self.module.types.node(value.ty).tag; if tag == blot_check_types::Tag.unit || tag == blot_check_types::Tag.boolean || tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32 { return 0, Error.none; } let input, error = expression(self, operands[0], environment, depth + 1); if error != Error.none { return 0, error; } return self.store.elements(input); },
    }
}
fn aggregateValue(self: Builder&, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    if value.a > self.module.extra.len || value.b > self.module.extra.len - value.a || value.b > 2048 { return 0, Error.unavailable; } var words: u32[4096]; let children = self.module.extra[value.a..value.a + value.b];
    if value.tag == blot_check_core::Tag.record { if value.ty >= self.module.types.nodes.len || value.c > self.module.extra.len || value.b > self.module.extra.len - value.c { return 0, Error.unavailable; } let record = self.module.types.node(value.ty);
        if record.tag != blot_check_types::Tag.record || record.a > self.module.types.extra.len || record.b > (self.module.types.extra.len - record.a) / 2 { return 0, Error.unavailable; }
        for child, index in children { let destination = self.module.extra[value.c + index]; if destination >= record.b { return 0, Error.unavailable; } words[index * 2] = self.module.types.extra[record.a + destination * 2]; let result, error = expression(self, child, environment, depth + 1); if error != Error.none { return 0, error; } words[index * 2 + 1] = result; } return self.store.aggregate(Tag.record, words[..children.len * 2]);
    }
    for child, index in children { let result, error = expression(self, child, environment, depth + 1); if error != Error.none { return 0, error; } words[index] = result; if value.tag == blot_check_core::Tag.array { let error = inputStore(self, result); if error != Error.none { return 0, error; } } } return self.store.aggregate(Tag.product, words[..children.len]);
}
fn blockValue(self: Builder&, source: u32, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    if value.a > self.module.extra.len || value.b > self.module.extra.len - value.a { return 0, Error.unavailable; } var nested = environment; let children = self.module.extra[value.a..value.a + value.b];
    for child, index in children { let statement, error = self.node(child, depth + 1); if error != Error.none { return 0, error; } if statement.tag == blot_check_core::Tag.return_ && index + 1 == children.len && statement.b == source { return expression(self, statement.a, nested, depth + 1); }
        if statement.tag == blot_check_core::Tag.constant && statement.ty == blot_check_types::unit && statement.op == blot_check_core::Op.none && statement.a == 0 && statement.b == 0 && statement.c == 0 { continue; }
        if statement.tag != blot_check_core::Tag.bind { return 0, Error.unavailable; } let result, error = expression(self, statement.b, nested, depth + 1); if error != Error.none { return 0, error; } let origin, error = callableOrigin(self, statement.b, nested, depth + 1); if error != Error.none { return 0, error; }
        let error = nested.bind(statement.a, result); if error != Error.none { return 0, error; } nested.values[nested.len - 1].callable = origin;
    } return 0, Error.unavailable;
}
fn matchValue(self: Builder&, value: blot_check_core::Node, environment: const Environment&, depth: i64) -> Id, Error {
    if value.a >= self.module.matches.len { return 0, Error.unavailable; } let info = self.module.matches[value.a]; if info.statement || info.inputs.len > 16 || info.arms.len > 4096 { return 0, Error.unavailable; } var retained: Id[16];
    for input, index in self.module.extra[info.inputs.start..info.inputs.start + info.inputs.len] { let result, error = expression(self, input, environment, depth + 1); if error != Error.none { return 0, error; } retained[index] = result; }
    var arms: Id[4096]; for arm, index in self.module.match_arms[info.arms.start..info.arms.start + info.arms.len] { var nested = environment; let start = nested.len;
        for row in self.module.pattern_rows[arm.rows.start..arm.rows.start + arm.rows.len] { if row.patterns.len != info.inputs.len { return 0, Error.unavailable; } for pattern_id, ordinal in self.module.extra[row.patterns.start..row.patterns.start + row.patterns.len] { let error = pattern(self, pattern_id, retained[ordinal], nested, start, depth + 1); if error != Error.none { return 0, error; } } }
        if self.input_globals && arm.guard != 0 { let ignored, error = expression(self, arm.guard, nested, depth + 1); if error != Error.none { return 0, error; } } let result, error = expression(self, arm.body, nested, depth + 1); if error != Error.none { return 0, error; } arms[index] = result;
    } return self.store.aggregate(Tag.join, arms[..info.arms.len]);
}
fn bindPattern(self: Builder&, environment: Environment&, start: i64, binding: u32, origin: Id) -> Error {
    for index in start..environment.len { let entry .= environment.values[index]; if entry.binding == binding { if entry.value != origin { let children: Id[2] = [entry.value, origin]; let id, error = self.store.aggregate(Tag.join, children); if error != Error.none { return error; } entry.value = id; } return Error.none; } } return environment.bind(binding, origin);
}
recursive fn pattern(self: Builder&, source: u32, origin: Id, environment: Environment&, start: i64, depth: i64) -> Error {
    if source == 0 || source >= self.module.patterns.len || depth >= 128 || self.remaining == 0 { return Error.unavailable; } self.remaining -= 1; let value = self.module.patterns[source];
    match value.tag {
        blot_check_core::PatternTag.wildcard, blot_check_core::PatternTag.constant => {},
        blot_check_core::PatternTag.bind => { return bindPattern(self, environment, start, value.a, origin); },
        blot_check_core::PatternTag.constructor => { if value.b != 0 { let payload, error = self.store.project(origin, 0, blot_check_capability_contracts::Projection.payload); if error != Error.none { return error; } return pattern(self, value.b, payload, environment, start, depth + 1); } },
        blot_check_core::PatternTag.record_payload => { if value.b != 0 { return pattern(self, value.b, origin, environment, start, depth + 1); } },
        blot_check_core::PatternTag.product => { if value.ty >= self.module.types.nodes.len { return Error.unavailable; } let shape = self.module.types.node(value.ty);
            for child, index in self.module.extra[value.a..value.a + value.b] { var selector = index as u32; var kind = blot_check_capability_contracts::Projection.index;
                if shape.tag == blot_check_types::Tag.record { if index >= shape.b { return Error.unavailable; } selector = self.module.types.extra[shape.a + index * 2]; kind = blot_check_capability_contracts::Projection.field; }
                let selected, error = self.store.project(origin, selector, kind); if error != Error.none { return error; } let error = pattern(self, child, selected, environment, start, depth + 1); if error != Error.none { return error; }
            }
        },
        _ => { return Error.unavailable; },
    } return Error.none;
}
fn captureCallTarget(self: Builder&, original: blot_check_core::BindingRef, depth: i64) -> Error {
    var target = original; var producer: const Module& = self.module;
    for attempt in 0..128 { if self.remaining == 0 || depth >= 128 { return Error.capability_analysis_limit; } self.remaining -= 1;
        let selected, error = producerFor(self, producer, target.unit); if error != Error.none { return error; } if !selected { return Error.unavailable; } producer .= selected;
        if target.binding == 0 || target.binding >= producer.bindings.len { return Error.unavailable; } let binding = producer.bindings[target.binding]; if binding.kind == blot_check_check::Kind.external { target = binding.target; continue; }
        if binding.kind != blot_check_check::Kind.global || binding.body_id == 0 || binding.body_id >= producer.bodies.len { return Error.unavailable; } return Error.none;
    } return Error.capability_analysis_limit;
}
recursive fn capture(self: Builder&, source: u32, environment: const Environment&, captures: Id[4096]&, count: i64&, depth: i64) -> Error {
    let value, error = self.node(source, depth); if error != Error.none { return error; }
    match value.tag {
        blot_check_core::Tag.reference => { if value.a >= self.module.references.len { return Error.unavailable; } let reference = self.module.references[value.a]; var captured: Id = 0;
            if reference.unit == 0 || reference.unit == self.module.unit { let known = environment.get(reference.binding); if known.present { captured = known.value; }
                else if !self.input_globals { let result, error = self.reference(value.a, value.ty, environment, depth + 1); if error != Error.none { return error; } captured = result; }
                else if reference.binding >= self.module.bindings.len || self.module.bindings[reference.binding].kind != blot_check_check::Kind.global { return Error.unavailable; }
            } else if !self.input_globals { return Error.unavailable; }
            if captured == 0 { return Error.none; } for known in captures[..count] { if known == captured { return Error.none; } } if count == captures.len { return Error.capability_analysis_limit; } captures[count] = captured; count += 1;
        },
        blot_check_core::Tag.constant, blot_check_core::Tag.primitive_function => {},
        blot_check_core::Tag.operation_value => { if value.a >= self.module.operation_values.len { return Error.unavailable; } let receiver = self.module.operation_values[value.a].capability; if receiver != 0 { return capture(self, receiver, environment, captures, count, depth + 1); } },
        blot_check_core::Tag.call => { if value.a >= self.module.calls.len || value.b > self.module.extra.len || value.c > self.module.extra.len - value.b { return Error.unavailable; } let error = captureCallTarget(self, self.module.calls[value.a].target, depth + 1); if error != Error.none { return error; }
            for operand in self.module.extra[value.b..value.b + value.c] { let error = capture(self, operand, environment, captures, count, depth + 1); if error != Error.none { return error; } }
        },
        blot_check_core::Tag.apply, blot_check_core::Tag.resource_acquire, blot_check_core::Tag.usage_borrow => { let error = capture(self, value.a, environment, captures, count, depth + 1); if error != Error.none { return error; } return capture(self, value.b, environment, captures, count, depth + 1); },
        blot_check_core::Tag.scalar, blot_check_core::Tag.logical, blot_check_core::Tag.associated => { let error = capture(self, value.a, environment, captures, count, depth + 1); if error != Error.none { return error; } if value.b != 0 { return capture(self, value.b, environment, captures, count, depth + 1); } },
        blot_check_core::Tag.resource_release, blot_check_core::Tag.usage_share, blot_check_core::Tag.usage_read, blot_check_core::Tag.project, blot_check_core::Tag.return_ => { return capture(self, value.a, environment, captures, count, depth + 1); },
        blot_check_core::Tag.task => { for operand in self.module.children(source) { let error = capture(self, operand, environment, captures, count, depth + 1); if error != Error.none { return error; } } },
        blot_check_core::Tag.resource_scope => { let error = capture(self, value.a, environment, captures, count, depth + 1); if error != Error.none { return error; } let error = capture(self, value.b, environment, captures, count, depth + 1); if error != Error.none { return error; } return capture(self, value.c, environment, captures, count, depth + 1); },
        blot_check_core::Tag.construct => { if value.a == 0 || value.a >= self.module.constructors.len || (self.module.constructors[value.a].payload == 0) != (value.b == 0) { return Error.unavailable; } if value.b != 0 { return capture(self, value.b, environment, captures, count, depth + 1); } },
        blot_check_core::Tag.closure => { if value.a >= self.module.closures.len { return Error.unavailable; } let closure = self.module.closures[value.a]; var nested = environment; let error = nested.bind(closure.parameter.binding, 0); if error != Error.none { return error; } return capture(self, closure.body, nested, captures, count, depth + 1); },
        blot_check_core::Tag.block_, blot_check_core::Tag.suite => { if value.a > self.module.extra.len || value.b > self.module.extra.len - value.a { return Error.unavailable; } var nested = environment;
            for child in self.module.extra[value.a..value.a + value.b] { let statement, error = self.node(child, depth + 1); if error != Error.none { return error; }
                if statement.tag == blot_check_core::Tag.bind { let error = capture(self, statement.b, nested, captures, count, depth + 1); if error != Error.none { return error; } let error = nested.bind(statement.a, 0); if error != Error.none { return error; } }
                else if statement.tag == blot_check_core::Tag.pattern_bind { let error = capture(self, statement.b, nested, captures, count, depth + 1); if error != Error.none { return error; } if statement.c != 0 { let error = capture(self, statement.c, nested, captures, count, depth + 1); if error != Error.none { return error; } } let start = nested.len; let error = pattern(self, statement.a, 0, nested, start, depth + 1); if error != Error.none { return error; } }
                else { let error = capture(self, child, nested, captures, count, depth + 1); if error != Error.none { return error; } }
            }
        },
        blot_check_core::Tag.match_ => { return captureMatch(self, value, environment, captures, count, depth); },
        blot_check_core::Tag.if_value => { let error = capture(self, value.a, environment, captures, count, depth + 1); if error != Error.none { return error; } let error = capture(self, value.b, environment, captures, count, depth + 1); if error != Error.none { return error; } return capture(self, value.c, environment, captures, count, depth + 1); },
        blot_check_core::Tag.product, blot_check_core::Tag.record, blot_check_core::Tag.array, blot_check_core::Tag.array_op => { if value.a > self.module.extra.len || value.b > self.module.extra.len - value.a { return Error.unavailable; } for child in self.module.extra[value.a..value.a + value.b] { let error = capture(self, child, environment, captures, count, depth + 1); if error != Error.none { return error; } } },
        _ => { return Error.unavailable; },
    } return Error.none;
}
fn captureMatch(self: Builder&, value: blot_check_core::Node, environment: const Environment&, captures: Id[4096]&, count: i64&, depth: i64) -> Error {
    if value.a >= self.module.matches.len { return Error.unavailable; } let info = self.module.matches[value.a];
    if info.inputs.len > 16 || info.inputs.start > self.module.extra.len || info.inputs.len > self.module.extra.len - info.inputs.start || info.arms.start > self.module.match_arms.len || info.arms.len > self.module.match_arms.len - info.arms.start { return Error.unavailable; }
    for input in self.module.extra[info.inputs.start..info.inputs.start + info.inputs.len] { let error = capture(self, input, environment, captures, count, depth + 1); if error != Error.none { return error; } }
    for arm in self.module.match_arms[info.arms.start..info.arms.start + info.arms.len] { if arm.rows.start > self.module.pattern_rows.len || arm.rows.len > self.module.pattern_rows.len - arm.rows.start { return Error.unavailable; } var nested = environment; let start = nested.len;
        for row in self.module.pattern_rows[arm.rows.start..arm.rows.start + arm.rows.len] { if row.patterns.len != info.inputs.len || row.patterns.start > self.module.extra.len || row.patterns.len > self.module.extra.len - row.patterns.start { return Error.unavailable; }
            for pattern_id in self.module.extra[row.patterns.start..row.patterns.start + row.patterns.len] { let error = pattern(self, pattern_id, 0, nested, start, depth + 1); if error != Error.none { return error; } }
        }
        if arm.guard != 0 { let error = capture(self, arm.guard, nested, captures, count, depth + 1); if error != Error.none { return error; } } let error = capture(self, arm.body, nested, captures, count, depth + 1); if error != Error.none { return error; }
    } return Error.none;
}
fn derive(store: Store&, module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters) -> blot_support::Option<Id>, Error { return deriveWithOwners(store, module, body, summary, []); }
fn deriveWithOwners(store: Store&, module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters, owners: const ModuleRef[:]) -> blot_support::Option<Id>, Error {
    if !blot_check_capability_flow::parameterCoreWithOwners(module, body, summary, owners) || summary.invokes() { return blot_support::none<Id>(), Error.none; }
    var arity = summary.arity(); if summary.kind == blot_check_capability_flow::ParameterResult.member_closure_unit || summary.kind == blot_check_capability_flow::ParameterResult.captured_unit { arity += 1; }
    if body.parameters.len != arity || body.parameters.start > module.parameters.len || body.parameters.len > module.parameters.len - body.parameters.start { return blot_support::none<Id>(), Error.none; }
    let checkpoint = store.mark(); var callables: CallableOrigin[>..<] = []; var input_globals = false;
    if body.binding < module.bindings.len { input_globals = module.bindings[body.binding].capability_flow == blot_check_capability_flow::Contract.input_shape; }
    var builder = Builder { store, module, owners: owners, input_globals: input_globals, closed_rows: body.closed_rows, callables: callables };
    let result, error = deriveBody(builder, body, summary); releaseCallables(builder); if error != Error.none { store.rollback(checkpoint); if error == Error.unavailable { return blot_support::none<Id>(), Error.none; } return blot_support::none<Id>(), error; } return blot_support::some(result), Error.none;
}
fn deriveBody(builder: Builder&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters) -> Id, Error {
    let empty, error = builder.store.append(blot_check_capability_contracts::Term { Tag.empty }); if error != Error.none { return 0, error; } var environment = Environment {};
    for parameter, index in builder.module.parameters[body.parameters.start..body.parameters.start + summary.arity()] { let id, error = builder.store.append(blot_check_capability_contracts::Term { Tag.parameter, index as u32 }); if error != Error.none { return 0, error; } let error = environment.bind(parameter.binding, id); if error != Error.none { return 0, error; } }
    if summary.kind == blot_check_capability_flow::ParameterResult.member_closure_unit || summary.kind == blot_check_capability_flow::ParameterResult.captured_unit {
        let error = environment.bind(builder.module.parameters[body.parameters.start + summary.arity()].binding, 0); if error != Error.none { return 0, error; } var captures: Id[4096]; var count: i64 = 0;
        let error = capture(builder, body.root, environment, captures, count, 0); if error != Error.none { return 0, error; } return builder.store.aggregate(Tag.captures, captures[..count]);
    } return expression(builder, body.root, environment, 0);
}
struct InputBodyCheck { module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters, owners: const ModuleRef[:], result: bool = false }
fn inputBody(module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters) -> bool { return inputBodyWithOwners(module, body, summary, []); }
fn inputBodyWithOwners(module: const Module&, body: blot_check_core::Body, summary: blot_check_capability_flow::Parameters, owners: const ModuleRef[:]) -> bool {
    if !summary.valid() || summary.kind != blot_check_capability_flow::ParameterResult.product || summary.arity() == 0 || body.scheme.generative.len != 0 || body.parameters.len != summary.arity() || body.parameters.start > module.parameters.len || body.parameters.len > module.parameters.len - body.parameters.start { return false; }
    var context = InputBodyCheck { module, body, summary, owners }; let error = blot_check_capability_contracts::withStore<InputBodyCheck,inputBodyCheck>(context); return error == Error.none && context.result;
}
fn inputBodyCheck(context: InputBodyCheck&, store: Store&) -> Error {
    let empty, error = store.append(blot_check_capability_contracts::Term { Tag.empty }); if error != Error.none { return Error.none; } var callables: CallableOrigin[>..<] = [];
    var builder = Builder { store, context.module, owners: context.owners, input_globals: true, closed_rows: context.body.closed_rows, callables: callables }; var environment = Environment {}; if !context.body.is_function { return Error.none; }
    for parameter, index in context.module.parameters[context.body.parameters.start..context.body.parameters.start + context.body.parameters.len] {
        if parameter.binding == 0 { if index != 0 || parameter.ty != blot_check_types::unit { return Error.none; } continue; }
        if parameter.binding >= context.module.bindings.len || context.module.bindings[parameter.binding].kind != blot_check_check::Kind.parameter { return Error.none; }
        let formal, error = store.append(blot_check_capability_contracts::Term { Tag.parameter, index as u32 }); if error != Error.none { return Error.none; } if environment.bind(parameter.binding, formal) != Error.none { return Error.none; }
    }
    let root, error = expression(builder, context.body.root, environment, 0); if error != Error.none || store.view().validate(root, context.summary.arity(), true) != Error.none { return Error.none; } for node in store.nodes.items { if node.tag == Tag.unknown { return Error.none; } }
    let mask, error = store.view().parameterMask(root); context.result = error == Error.none && mask == context.summary.result(); return Error.none;
}
fn deriveInputFunctionClosure(store: Store&, module: const Module&, initial: blot_check_core::ClosureInfo, arity: u8) -> blot_support::Option<Id>, Error { return deriveInputFunctionClosureWithOwners(store, module, initial, arity, []); }
fn deriveInputFunctionClosureWithOwners(store: Store&, module: const Module&, initial: blot_check_core::ClosureInfo, arity: u8, owners: const ModuleRef[:]) -> blot_support::Option<Id>, Error {
    if arity == 0 || arity > 16 { return blot_support::none<Id>(), Error.none; } let checkpoint = store.mark(); var callables: CallableOrigin[>..<] = []; var builder = Builder { store, module, input_globals: true, owners: owners, callables: callables };
    let root, error = inputFunctionBody(builder, initial, arity); if error != Error.none || !root.present { store.rollback(checkpoint); if error == Error.unavailable { return blot_support::none<Id>(), Error.none; } return root, error; } return root, Error.none;
}
fn inputFunctionBody(builder: Builder&, initial: blot_check_core::ClosureInfo, arity: u8) -> blot_support::Option<Id>, Error {
    let empty, error = builder.store.append(blot_check_capability_contracts::Term { Tag.empty }); if error != Error.none { return blot_support::none<Id>(), error; } var environment = Environment {}; let module = builder.module;
    if initial.captures.start > module.extra.len || initial.captures.len > module.extra.len - initial.captures.start { return blot_support::none<Id>(), Error.invalid_capability_contract; }
    for binding in module.extra[initial.captures.start..initial.captures.start + initial.captures.len] { let error = environment.bind(binding, 0); if error != Error.none { return blot_support::none<Id>(), error; } }
    var closure = initial;
    for index in 0..arity { let formal, error = builder.store.append(blot_check_capability_contracts::Term { Tag.parameter, index as u32 }); if error != Error.none { return blot_support::none<Id>(), error; } let error = environment.bind(closure.parameter.binding, formal); if error != Error.none { return blot_support::none<Id>(), error; }
        if index + 1 == arity { let root, error = expression(builder, closure.body, environment, 0); if error != Error.none { if error == Error.unavailable { return blot_support::none<Id>(), Error.none; } return blot_support::none<Id>(), error; }
            if builder.store.view().validate(root, arity, false) != Error.none { return blot_support::none<Id>(), Error.none; } return blot_support::some(root), Error.none;
        }
        let next, error = builder.node(closure.body, 0); if error != Error.none || next.tag != blot_check_core::Tag.closure || next.a >= module.closures.len { return blot_support::none<Id>(), Error.none; } closure = module.closures[next.a];
    } return blot_support::none<Id>(), Error.none;
}
fn deriveClosure(store: Store&, module: const Module&, closure: blot_check_core::ClosureInfo) -> blot_support::Option<Id>, Error { return closureResult(store, module, closure, false); }
fn deriveInputClosure(store: Store&, module: const Module&, closure: blot_check_core::ClosureInfo) -> blot_support::Option<Id>, Error {
    let checkpoint = store.mark(); let root, error = closureResult(store, module, closure, true); if error != Error.none || !root.present { return root, error; }
    if store.view().validate(root.value, 1, false) != Error.none { store.rollback(checkpoint); return blot_support::none<Id>(), Error.none; } return root, Error.none;
}
fn closureResult(store: Store&, module: const Module&, closure: blot_check_core::ClosureInfo, input_globals: bool) -> blot_support::Option<Id>, Error {
    let checkpoint = store.mark(); var callables: CallableOrigin[>..<] = []; var builder = Builder { store, module, input_globals: input_globals, callables: callables };
    let result, error = closureBody(builder, closure); if error != Error.none { store.rollback(checkpoint); if error == Error.unavailable { return blot_support::none<Id>(), Error.none; } return blot_support::none<Id>(), error; } return blot_support::some(result), Error.none;
}
fn closureBody(builder: Builder&, closure: blot_check_core::ClosureInfo) -> Id, Error {
    let empty, error = builder.store.append(blot_check_capability_contracts::Term { Tag.empty }); if error != Error.none { return 0, error; } var environment = Environment {};
    for binding in builder.module.extra[closure.captures.start..closure.captures.start + closure.captures.len] { let error = environment.bind(binding, 0); if error != Error.none { return 0, error; } }
    let formal, error = builder.store.append(blot_check_capability_contracts::Term { Tag.parameter }); if error != Error.none { return 0, error; } let error = environment.bind(closure.parameter.binding, formal); if error != Error.none { return 0, error; } return expression(builder, closure.body, environment, 0);
}
fn callableValue(store: Store&, module: const Module&, source: u32, owners: const ModuleRef[:]) -> blot_support::Option<Id>, Error {
    let checkpoint = store.mark(); let empty, error = store.append(blot_check_capability_contracts::Term { Tag.empty }); if error != Error.none { store.rollback(checkpoint); return blot_support::none<Id>(), error; }
    var callables: CallableOrigin[>..<] = []; var reader = Builder { store, module, owners: owners, input_globals: true, value_origins: true, callables: callables }; let environment = Environment {};
    let result, error = expression(reader, source, environment, 0); if error != Error.none { store.rollback(checkpoint); if error == Error.unavailable { return blot_support::none<Id>(), Error.none; } return blot_support::none<Id>(), error; } return blot_support::some(result), Error.none;
}

fn functionUseCode(value: FunctionUse) -> u32 {
    match value {
        FunctionUse.value => { return 0; },
        FunctionUse.invocation => { return 1; },
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

fn ensureCallables(self:Builder&,minimum:i64)->Error {let budget .= self.store.budget;if !budget {return Error.none;}return blot_check_logical_scratch_budget::ensure(budget,self.callable_allocation,minimum);}
fn releaseCallables(self:Builder&) {let budget .= self.store.budget;if budget {blot_check_logical_scratch_budget::release(budget,self.callable_allocation);}}
fn deriveWithOwnersBudget(store:Store&,module:const Module&,body:blot_check_core::Body,summary:blot_check_capability_flow::Parameters,owners:const ModuleRef[:],limit:i64=1048576)->blot_support::Option<Id>,Error {
    if store.nodes.len!=0 || store.words.len!=0 || store.budget!=null {return blot_support::none<Id>(),Error.invalid_capability_contract;}
    var budget=blot_check_logical_scratch_budget::Budget{limit:limit};store.node_allocation=blot_check_logical_scratch_budget::ArrayBlock{element_size:16,alignment:4};store.word_allocation=blot_check_logical_scratch_budget::ArrayBlock{element_size:4,alignment:4};store.budget .= budget;
    let result,error=deriveWithOwners(store,module,body,summary,owners);store.budget .= null;return result,error;
}
