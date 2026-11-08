// Owned input relationships are independent of ordinary type/effect headers.
namespace blot_check_capability_flow;
import reuse.principal_interface;

import backend.collection_ops;
import check.capability_contract_core;
import check.capability_contract_source;
import check.check_packet_owner;
import check.core;
import check.effects;
import check.frozen_core_scopes;
import check.rank_equal;
import check.types;
import parse.ast;
import parse.symbols;
import support.error;
import support.option;
import support.structural_adapters;

import .frozen_core_validation;
type ModuleRef = blot_check_frozen_core_validation::ModuleRef;
import std;
import support.structural;
type Error = blot_error::Error;
type AstId = blot_parse_ast::Id;
type Tree = blot_parse_ast::Tree;
type Pool = blot_parse_symbols::Pool;
type Module = blot_check_core::Module;
type Mask = blot_support::Option<u16>;
enum Contract { unknown, identity, invoke_unit, member_unit, invoke_with_capability, member_first_unit, member_second_unit, input_shape, consume_task, scope_task, spawn_task }
enum ParameterResult { product, invoke_unit, invalid, member_closure_unit, captured_unit, invoke_input, invoke_inputs }
struct Parameters { kind: ParameterResult = ParameterResult.product, mask: u16 = 0, inputs: u8 = 0, invocation_arguments: u64 = 0, invocation_count: u8 = 0 }
fn init(inputs: u8, mask: u16) -> Parameters { return Parameters { mask: mask, inputs: inputs , ..}; }
fn result(self_: Parameters) -> u16 { if self_.kind == ParameterResult.invoke_input { return (1 as u16) << self_.callback(); } return self_.mask; }
fn invokes(self_: Parameters) -> bool { return self_.kind == ParameterResult.invoke_unit || self_.inputInvokes(); }
fn inputInvokes(self_: Parameters) -> bool { return self_.kind == ParameterResult.invoke_input || self_.kind == ParameterResult.invoke_inputs; }
fn argumentCount(self_: Parameters) -> u8 { if self_.kind == ParameterResult.invoke_input { return 1; } if self_.kind == ParameterResult.invoke_inputs { return self_.invocation_count; } return 0; }
fn argumentAt(self_: Parameters, index: i64) -> u8 { if self_.kind == ParameterResult.invoke_input { return self_.argument(); } return ((self_.invocation_arguments >> (index * 4)) & 15) as u8; }
fn callback(self_: Parameters) -> u8 { if self_.kind == ParameterResult.invoke_input { return (self_.mask & 15) as u8; } return ctz(self_.mask) as u8; }
fn argument(self_: Parameters) -> u8 { return ((self_.mask >> 4) & 15) as u8; }
fn arity(self_: Parameters) -> u8 { return self_.inputs; }
fn present(self_: Parameters) -> bool { return self_.arity() != 0; }
fn valid(self_: Parameters) -> bool {
    if self_.kind == ParameterResult.invalid { return false; } if self_.kind != ParameterResult.invoke_inputs && (self_.invocation_arguments != 0 || self_.invocation_count != 0) { return false; }
    if self_.kind == ParameterResult.invoke_inputs {
        if self_.inputs == 0 || self_.inputs > 16 || popcount(self_.mask) != 1 || self_.callback() >= self_.inputs || self_.invocation_count < 2 || self_.invocation_count > 16 { return false; }
        if self_.invocation_count != 16 && self_.invocation_arguments >> (self_.invocation_count * 4) != 0 { return false; }
        for index in 0..self_.invocation_count { let selected = self_.argumentAt(index); if selected >= self_.inputs || selected == self_.callback() { return false; } } return true;
    }
    let inputs = self_.arity(); if inputs == 0 { return self_.kind == ParameterResult.product && self_.result() == 0; } if inputs > 16 { return false; }
    if self_.kind == ParameterResult.invoke_input { return self_.mask <= 255 && self_.callback() < inputs && self_.argument() < inputs && self_.callback() != self_.argument(); }
    if (self_.kind == ParameterResult.member_closure_unit || self_.kind == ParameterResult.captured_unit) && inputs == 16 { return false; } let available = ((1 as u32) << inputs) - 1; if ((self_.result() as u32) & ~available) != 0 { return false; }
    if self_.kind == ParameterResult.invoke_unit || self_.kind == ParameterResult.member_closure_unit { return popcount(self_.result()) == 1; } return true;
}
fn unwrap(tree: const Tree&, initial: AstId) -> AstId { var current = initial; for attempt in 0..128 { if current == 0 || current >= tree.nodes.len { return 0; } let value = tree.node(current); if value.tag != blot_parse_ast::tag_group { return current; } current = value.a; } return 0; }
fn unwrapped(tree: const Tree&, initial: AstId) -> blot_parse_ast::Node { let id = unwrap(tree, initial); if id == 0 { return blot_parse_ast::Node { tag: blot_parse_ast::tag_invalid , ..}; } return tree.node(id); }
fn taskUnarySource(tree: const Tree&, pool: Pool&, initial: AstId, primitive: const u8[:]) -> bool {
    let lambda = unwrapped(tree, initial); if lambda.tag != blot_parse_ast::tag_lambda { return false; } let parameter = tree.parameter(lambda.a); if parameter.name == 0 || parameter.is_unit { return false; }
    let body = unwrapped(tree, lambda.b); if body.tag != blot_parse_ast::tag_apply { return false; } let callee = unwrapped(tree, body.a); let argument = unwrapped(tree, body.b);
    return callee.tag == blot_parse_ast::tag_intrinsic && pool.get(callee.a) == primitive && argument.tag == blot_parse_ast::tag_name && argument.a == parameter.name;
}
fn taskSpawnSource(tree: const Tree&, pool: Pool&, initial: AstId) -> bool {
    let outer = unwrapped(tree, initial); if outer.tag != blot_parse_ast::tag_lambda { return false; } let inner = unwrapped(tree, outer.b); if inner.tag != blot_parse_ast::tag_lambda { return false; }
    let group = tree.parameter(outer.a); let action = tree.parameter(inner.a); if group.name == 0 || action.name == 0 || group.name == action.name || group.is_unit || action.is_unit { return false; }
    let call = unwrapped(tree, inner.b); if call.tag != blot_parse_ast::tag_apply { return false; } let first = unwrapped(tree, call.a); if first.tag != blot_parse_ast::tag_apply { return false; }
    let head = unwrapped(tree, first.a); let left = unwrapped(tree, first.b); let right = unwrapped(tree, call.b);
    return head.tag == blot_parse_ast::tag_intrinsic && pool.get(head.a) == "@task.spawn" && left.tag == blot_parse_ast::tag_name && left.a == group.name && right.tag == blot_parse_ast::tag_name && right.a == action.name;
}
fn taskJoinSource(tree: const Tree&, pool: Pool&, initial: AstId) -> bool { return taskUnarySource(tree, pool, initial, "@task.join") || taskUnarySource(tree, pool, initial, "@task.receive"); }
fn taskScopeSource(tree: const Tree&, pool: Pool&, initial: AstId) -> bool { return taskUnarySource(tree, pool, initial, "@task.scope"); }
fn source(tree: const Tree&, initial: AstId) -> Contract {
    let lambda = unwrapped(tree, initial); if lambda.tag != blot_parse_ast::tag_lambda { return Contract.unknown; } let parameter = tree.parameter(lambda.a); if parameter.name == 0 || parameter.is_unit { return Contract.unknown; }
    let value = unwrapped(tree, lambda.b); if value.tag == blot_parse_ast::tag_name && value.a == parameter.name { return Contract.identity; } if value.tag != blot_parse_ast::tag_apply { return Contract.unknown; }
    let callee = unwrapped(tree, value.a); let argument = unwrapped(tree, value.b); if callee.tag == blot_parse_ast::tag_name && callee.a == parameter.name && argument.tag == blot_parse_ast::tag_unit { return Contract.invoke_unit; } return Contract.unknown;
}
fn memberSource(tree: const Tree&, pool: Pool&, initial: AstId) -> bool {
    let lambda = unwrapped(tree, initial); if lambda.tag != blot_parse_ast::tag_lambda { return false; } let parameter = tree.parameter(lambda.a); if parameter.name == 0 { return false; }
    let value = unwrapped(tree, lambda.b); if value.tag != blot_parse_ast::tag_apply || unwrapped(tree, value.b).tag != blot_parse_ast::tag_unit { return false; } let callee = unwrapped(tree, value.a);
    if callee.tag == blot_parse_ast::tag_field_access { let receiver = unwrapped(tree, callee.a); return receiver.tag == blot_parse_ast::tag_name && receiver.a == parameter.name; }
    if callee.tag != blot_parse_ast::tag_name { return false; } let name = pool.get(callee.a); let input = pool.get(parameter.name); return name.len > input.len + 1 && name.starts_with(input) && name[input.len] == '.';
}
fn curriedUnitSource(tree: const Tree&, initial: AstId) -> bool { let lambda = unwrapped(tree, initial); if lambda.tag != blot_parse_ast::tag_lambda { return false; } let parameter = tree.parameter(lambda.a); if parameter.name == 0 || parameter.is_unit { return false; } return tree.node(lambda.b).tag == blot_parse_ast::tag_lambda && source(tree, lambda.b) == Contract.invoke_unit; }
fn pairMemberSource(tree: const Tree&, pool: Pool&, initial: AstId) -> blot_support::Option<u8> {
    let outer = unwrapped(tree, initial); if outer.tag != blot_parse_ast::tag_lambda { return blot_support::none<u8>(); } let inner = tree.node(outer.b); if inner.tag != blot_parse_ast::tag_lambda { return blot_support::none<u8>(); }
    let left = tree.parameter(outer.a); let right = tree.parameter(inner.a); if left.name == 0 || right.name == 0 || left.is_unit || right.is_unit { return blot_support::none<u8>(); }
    let call = unwrapped(tree, inner.b); if call.tag != blot_parse_ast::tag_apply || unwrapped(tree, call.b).tag != blot_parse_ast::tag_unit { return blot_support::none<u8>(); }
    var receiver: u32 = 0; let callee = unwrapped(tree, call.a);
    if callee.tag == blot_parse_ast::tag_field_access { let root = unwrapped(tree, callee.a); if root.tag == blot_parse_ast::tag_name { receiver = root.a; } }
    else if callee.tag == blot_parse_ast::tag_name { let text = pool.get(callee.a); let separator = blot_check_capability_contract_source::findLast(text, '.'); if separator < 0 { return blot_support::none<u8>(); } let found,present = pool.lookup(text[..separator]); if !present { return blot_support::none<u8>(); } receiver = found; }
    if receiver == right.name { return blot_support::some(1 as u8); } if receiver == left.name { return blot_support::some(0 as u8); } return blot_support::none<u8>();
}
fn parameterArity(tree: const Tree&, initial: AstId, annotation: AstId) -> u8 {
    var source = initial; var count: u8 = 0; var signature = annotation; var transparent = annotation == 0;
    for attempt in 0..128 { if signature == 0 { break; } let written = tree.node(signature); if written.tag == blot_parse_ast::tag_type_usage { signature = written.b; } else if written.tag == blot_parse_ast::tag_type_forall { signature = tree.extra.items[written.c]; } else if written.tag == blot_parse_ast::tag_type_effect { signature = written.a; } else { break; } }
    while true { if !transparent && tree.node(source).tag == blot_parse_ast::tag_group { break; } source = unwrap(tree, source); if source == 0 { return 0; } let lambda = tree.node(source); if lambda.tag != blot_parse_ast::tag_lambda { break; } let parameter = tree.parameter(lambda.a);
        if parameter.is_unit && count != 0 { return 0; } if count == 16 || (parameter.name == 0 && !parameter.is_unit) { return 0; } count += 1; source = lambda.b; var result = lambda.c;
        if signature != 0 && tree.node(signature).tag == blot_parse_ast::tag_type_function { signature = tree.node(signature).b; } if result == 0 { result = signature; } if result != 0 && tree.node(result).tag == blot_parse_ast::tag_type_effect { result = tree.node(result).a; }
        if result != 0 && (tree.node(result).tag == blot_parse_ast::tag_type_usage || tree.node(result).tag == blot_parse_ast::tag_type_forall) { break; } transparent = annotation == 0 && lambda.c == 0;
    } return count;
}
struct SourceBinding { name: u32, retained: u16 }
struct SourceBindings { entries: SourceBinding[128], len: i64 = 0 }
fn bind(self_: SourceBindings&, name: u32, retained: u16) -> Error { if self_.len == self_.entries.len { return blot_error::Error.limit; } self_.entries[self_.len] = SourceBinding { name, retained , ..}; self_.len += 1; return blot_error::Error.none; }
fn get(self_: const SourceBindings&, name: u32) -> Mask { var index = self_.len; while index != 0 { index -= 1; if self_.entries[index].name == name { return blot_support::some(self_.entries[index].retained); } } return blot_support::none<u16>(); }
fn parameterName(name: u32, names: const u32[:]) -> Mask { var index = names.len; while index != 0 { index -= 1; if name == names[index] { return blot_support::some((1 as u16) << index); } } return blot_support::none<u16>(); }
struct SourceContracts { engine: const blot_check_check::Engine& }
fn lookup(self_: const SourceContracts&, source: AstId) -> blot_support::Option<Parameters> { return self_.engine.invocationContract(source); }
fn parameterSource(tree: const Tree&, pool: Pool&, initial: AstId, annotation: AstId) -> Parameters { return parameterSourceWithContracts(tree, pool, initial, annotation, null); }
fn parameterSourceWithContracts(tree: const Tree&, pool: Pool&, initial: AstId, annotation: AstId, contracts: const SourceContracts?) -> Parameters {
    var names: u32[16] = [0;16]; var count: i64 = 0; var expression = unwrap(tree, initial); if expression == 0 { return Parameters {..}; } var transparent = annotation == 0; var signature = annotation;
    for attempt in 0..128 { if signature == 0 { break; } let written = tree.node(signature); if written.tag == blot_parse_ast::tag_type_usage { signature = written.b; } else if written.tag == blot_parse_ast::tag_type_forall { signature = tree.extra.items[written.c]; } else if written.tag == blot_parse_ast::tag_type_effect { signature = written.a; } else { break; } }
    while true { if !transparent && tree.node(expression).tag == blot_parse_ast::tag_group { break; } expression = unwrap(tree, expression); if expression == 0 { return Parameters {..}; } let lambda = tree.node(expression); if lambda.tag != blot_parse_ast::tag_lambda { break; } let parameter = tree.parameter(lambda.a);
        if parameter.is_unit && count != 0 { return unitSourceResult(tree, pool, expression, lambda, names[..count]); }
        if count == names.len || parameter.name == 0 || parameter.is_unit { return Parameters {..}; } names[count] = parameter.name; count += 1; expression = lambda.b; var result = lambda.c;
        if signature != 0 && tree.node(signature).tag == blot_parse_ast::tag_type_function { signature = tree.node(signature).b; } if result == 0 { result = signature; } if result != 0 && tree.node(result).tag == blot_parse_ast::tag_type_effect { result = tree.node(result).a; }
        if result != 0 && (tree.node(result).tag == blot_parse_ast::tag_type_usage || tree.node(result).tag == blot_parse_ast::tag_type_forall) { break; } transparent = annotation == 0 && lambda.c == 0;
    }
    expression = unwrap(tree, expression); if expression == 0 || count == 0 { return Parameters {..}; } var remaining: i64 = 4096; var bindings = SourceBindings {..};
    for name, index in names[..count] { if bindings.bind(name, (1 as u16) << index) != blot_error::Error.none { return Parameters {..}; } }
    let invocation = sourceInvocation(tree, expression, bindings, count as u8, contracts, remaining, 0); if invocation.present { return invocation.value; }
    let result = sourceParameters(tree, pool, expression, bindings, remaining, 0); if !result.present { return Parameters {..}; } return init(count as u8, result.value);
}
fn unitSourceResult(tree: const Tree&, pool: Pool&, expression: AstId, lambda: blot_parse_ast::Node, names: const u32[:]) -> Parameters {
    if names.len == 16 { return capturedSource(tree, pool, expression, names); } let member = unwrap(tree, lambda.b); if member == 0 { return capturedSource(tree, pool, expression, names); } let call = tree.node(member);
    if call.tag != blot_parse_ast::tag_apply || unwrapped(tree, call.b).tag != blot_parse_ast::tag_unit { return capturedSource(tree, pool, expression, names); } let callee = unwrapped(tree, call.a); var receiver: u32 = 0;
    if callee.tag == blot_parse_ast::tag_field_access { let root = unwrapped(tree, callee.a); if root.tag != blot_parse_ast::tag_name { return capturedSource(tree, pool, expression, names); } receiver = root.a; }
    else if callee.tag == blot_parse_ast::tag_name { let name = pool.get(callee.a); let separator = blot_check_capability_contract_source::findLast(name, '.'); if separator < 0 { return capturedSource(tree, pool, expression, names); } let found,present = pool.lookup(name[..separator]); if !present { return capturedSource(tree, pool, expression, names); } receiver = found; }
    else { return capturedSource(tree, pool, expression, names); }
    let selected = parameterName(receiver, names); if !selected.present { return capturedSource(tree, pool, expression, names); } return Parameters { kind: ParameterResult.member_closure_unit, mask: selected.value , inputs: names.len as u8, ..};
}
fn invocationResult(inputs: u8, callback: u16, arguments: const u16[:], unit: bool) -> blot_support::Option<Parameters> {
    if popcount(callback) != 1 || arguments.len > 16 { return blot_support::none<Parameters>(); } if unit { return blot_support::some(Parameters { kind: ParameterResult.invoke_unit, mask: callback , inputs: inputs, ..}); } if arguments.len == 0 { return blot_support::none<Parameters>(); } var selected: u64 = 0;
    for argument, index in arguments { if popcount(argument) != 1 || argument == callback { return blot_support::none<Parameters>(); } selected |= (ctz(argument) as u64) << (index * 4); }
    var result = Parameters { kind: ParameterResult.invoke_inputs, mask: callback, inputs: inputs, invocation_arguments: selected, invocation_count: arguments.len as u8 , ..};
    if arguments.len == 1 { result = Parameters { kind: ParameterResult.invoke_input, mask: (ctz(callback) as u16) | ((selected as u16) << 4) , inputs: inputs, ..}; } if !result.valid() { return blot_support::none<Parameters>(); } return blot_support::some(result);
}
recursive fn sourceInvocation(tree: const Tree&, initial: AstId, bindings: const SourceBindings&, inputs: u8, contracts: const SourceContracts?, remaining: i64&, depth: i64) -> blot_support::Option<Parameters> {
    if remaining == 0 || depth >= 128 { return blot_support::none<Parameters>(); } remaining -= 1; var head = unwrap(tree, initial); if head == 0 { return blot_support::none<Parameters>(); } var reverse: AstId[16] = [0;16]; var count: i64 = 0;
    while tree.node(head).tag == blot_parse_ast::tag_apply { if count == reverse.len { return blot_support::none<Parameters>(); } reverse[count] = tree.node(head).b; count += 1; head = unwrap(tree, tree.node(head).a); if head == 0 { return blot_support::none<Parameters>(); } }
    if count == 0 || tree.node(head).tag != blot_parse_ast::tag_name { return blot_support::none<Parameters>(); } let callback = bindings.get(tree.node(head).a);
    if callback.present { var arguments: u16[16] = [0;16]; if count == 1 && unwrapped(tree, reverse[0]).tag == blot_parse_ast::tag_unit { return invocationResult(inputs, callback.value, [], true); }
        for index in 0..count { let argument = unwrapped(tree, reverse[count - index - 1]); if argument.tag != blot_parse_ast::tag_name { return blot_support::none<Parameters>(); } let selected = bindings.get(argument.a); if !selected.present { return blot_support::none<Parameters>(); } arguments[index] = selected.value; } return invocationResult(inputs, callback.value, arguments[..count], false);
    }
    let catalog .= contracts; if catalog { let found = catalog.lookup(head); if found.present { let contract = found.value; if !contract.valid() || !contract.invokes() || contract.arity() != count { return blot_support::none<Parameters>(); } var actuals: u16[16] = [0;16];
            for index in 0..count { let actual = unwrapped(tree, reverse[count - index - 1]); if actual.tag != blot_parse_ast::tag_name { return blot_support::none<Parameters>(); } let selected = bindings.get(actual.a); if !selected.present { return blot_support::none<Parameters>(); } actuals[index] = selected.value; }
            var selected: u16[16] = [0;16]; for index in 0..contract.argumentCount() { selected[index] = actuals[contract.argumentAt(index)]; } return invocationResult(inputs, actuals[contract.callback()], selected[..contract.argumentCount()], contract.kind == ParameterResult.invoke_unit);
    } }
    if remaining < tree.roots.len { return blot_support::none<Parameters>(); } remaining -= tree.roots.len; let call = localSourceCall(tree, initial); if !call.present { return blot_support::none<Parameters>(); } var nested = SourceBindings {..};
    for index in 0..call.value.len { let node = unwrapped(tree, call.value.arguments[index]); if node.tag != blot_parse_ast::tag_name { return blot_support::none<Parameters>(); } let retained = bindings.get(node.a); if !retained.present || nested.bind(call.value.parameters[index], retained.value) != blot_error::Error.none { return blot_support::none<Parameters>(); } }
    return sourceInvocation(tree, call.value.body, nested, inputs, contracts, remaining, depth + 1);
}
enum ConstructionKind { computation, provider, state }
struct Construction { kind: ConstructionKind, inputs: AstId[3] = [0; 3], len: i64 }
fn constructionSource(tree: const Tree&, pool: Pool&, initial: AstId) -> blot_support::Option<Construction> {
    var reverse: AstId[3] = [0;3]; var count: i64 = 0; var head = initial; var finished = false;
    for attempt in 0..128 { head = unwrap(tree, head); if head == 0 { return blot_support::none<Construction>(); } let node = tree.node(head); if node.tag != blot_parse_ast::tag_apply { finished = true; break; } if count == reverse.len { return blot_support::none<Construction>(); } reverse[count] = node.b; count += 1; head = node.a; }
    if !finished { return blot_support::none<Construction>(); } let node = tree.node(head); if node.tag != blot_parse_ast::tag_intrinsic { return blot_support::none<Construction>(); } let name = pool.get(node.a); var kind = ConstructionKind.computation; var arity: i64 = 1;
    if name == "@effect.provider" { kind = ConstructionKind.provider; arity = 2; } else if name == "@effect.state" { kind = ConstructionKind.state; arity = 3; } else if name != "@computation" { return blot_support::none<Construction>(); }
    if count != arity { return blot_support::none<Construction>(); } var result = Construction { kind: kind, len: arity , ..}; for index in 0..arity { result.inputs[index] = reverse[arity - index - 1]; } return blot_support::some(result);
}
fn capturedSource(tree: const Tree&, pool: Pool&, expression: AstId, names: const u32[:]) -> Parameters {
    if names.len == 0 || names.len >= 16 { return Parameters {..}; } var bindings = SourceBindings {..}; for name, index in names { bindings.entries[index] = SourceBinding { name, (1 as u16) << index , ..}; } bindings.len = names.len; var remaining: i64 = 4096;
    let mask = sourceCaptures(tree, pool, expression, bindings, [], remaining, 0); if !mask.present { return Parameters {..}; } return Parameters { kind: ParameterResult.captured_unit, mask: mask.value , inputs: names.len as u8, ..};
}
struct LocalSourceCall { name: u32 = 0, body: AstId, arguments: AstId[16], parameters: u32[16], len: i64 }
fn localSourceCall(tree: const Tree&, initial: AstId) -> blot_support::Option<LocalSourceCall> {
    var result = LocalSourceCall { body: 0, len: 0 , ..}; var callee = unwrap(tree, initial); if callee == 0 { return blot_support::none<LocalSourceCall>(); }
    while tree.node(callee).tag == blot_parse_ast::tag_apply { if result.len == result.arguments.len { return blot_support::none<LocalSourceCall>(); } result.arguments[result.len] = tree.node(callee).b; result.len += 1; callee = unwrap(tree, tree.node(callee).a); if callee == 0 { return blot_support::none<LocalSourceCall>(); } }
    if result.len == 0 || tree.node(callee).tag != blot_parse_ast::tag_name { return blot_support::none<LocalSourceCall>(); } result.name = tree.node(callee).a; var body: AstId = 0; var found = false;
    for root in tree.roots.items { if tree.node(root).tag == blot_parse_ast::tag_value_decl && tree.value_decl(root).name == tree.node(callee).a { body = tree.value_decl(root).body; found = true; break; } } if !found { return blot_support::none<LocalSourceCall>(); }
    for index in 0..result.len { body = unwrap(tree, body); if body == 0 { return blot_support::none<LocalSourceCall>(); } let lambda = tree.node(body); if lambda.tag != blot_parse_ast::tag_lambda { return blot_support::none<LocalSourceCall>(); } let parameter = tree.parameter(lambda.a); if parameter.name == 0 || parameter.is_unit { return blot_support::none<LocalSourceCall>(); } result.parameters[index] = parameter.name; body = lambda.b; }
    result.body = unwrap(tree, body); if result.body == 0 || tree.node(result.body).tag == blot_parse_ast::tag_lambda { return blot_support::none<LocalSourceCall>(); }
    for index in 0..result.len / 2 { let saved = result.arguments[index]; result.arguments[index] = result.arguments[result.len - index - 1]; result.arguments[result.len - index - 1] = saved; } return blot_support::some(result);
}
struct LocalCoreCall { body: u32, target: blot_check_core::BindingRef, signature: u32, arguments: u32[16], len: i64 = 0, bindings: u32[16] }
fn coreCall(module: const Module&, id: u32) -> blot_support::Option<LocalCoreCall> {
    if id == 0 || id >= module.nodes.len { return blot_support::none<LocalCoreCall>(); } let node = module.nodes[id]; var result = LocalCoreCall { body: 0, target: blot_check_core::BindingRef {..}, signature: 0 , ..};
    if node.tag == blot_check_core::Tag.call { if node.a >= module.calls.len || node.c > result.arguments.len || node.b > module.extra.len || node.c > module.extra.len - node.b { return blot_support::none<LocalCoreCall>(); }
        result.target = module.calls[node.a].target; result.signature = module.calls[node.a].callee_type; result.len = node.c; for index in 0..result.len { result.arguments[index] = module.extra[node.b + index]; }
    } else {
        var callee = id; while true { if callee == 0 || callee >= module.nodes.len { return blot_support::none<LocalCoreCall>(); } let applied = module.nodes[callee]; if applied.tag != blot_check_core::Tag.apply { break; } if result.len == result.arguments.len || applied.b == 0 || applied.b >= module.nodes.len { return blot_support::none<LocalCoreCall>(); } result.arguments[result.len] = applied.b; result.len += 1; callee = applied.a; }
        for index in 0..result.len / 2 { let saved = result.arguments[index]; result.arguments[index] = result.arguments[result.len - index - 1]; result.arguments[result.len - index - 1] = saved; } let head = module.nodes[callee];
        if head.tag == blot_check_core::Tag.call { if head.a >= module.calls.len || head.c > result.arguments.len - result.len || head.b > module.extra.len || head.c > module.extra.len - head.b { return blot_support::none<LocalCoreCall>(); }
            var index = result.len; while index != 0 { index -= 1; result.arguments[head.c + index] = result.arguments[index]; } for index in 0..head.c { result.arguments[index] = module.extra[head.b + index]; } result.len += head.c; result.target = module.calls[head.a].target; result.signature = module.calls[head.a].callee_type;
        } else { if head.tag != blot_check_core::Tag.reference || head.a >= module.references.len { return blot_support::none<LocalCoreCall>(); } result.target = module.reference(callee); result.signature = head.ty; }
    }
    for index in 0..result.len { if result.arguments[index] == 0 || result.arguments[index] >= module.nodes.len { return blot_support::none<LocalCoreCall>(); } } return blot_support::some(result);
}
fn localCoreCall(module: const Module&, id: u32) -> blot_support::Option<LocalCoreCall> { let call = coreCall(module, id); if !call.present { return call; } return coreCallBody(module, call.value); }
fn coreCallBody(module: const Module&, original: LocalCoreCall) -> blot_support::Option<LocalCoreCall> {
    var result = original; let target = result.target; if (target.unit != 0 && target.unit != module.unit) || target.binding == 0 || target.binding >= module.bindings.len { return blot_support::none<LocalCoreCall>(); } let binding = module.bindings[target.binding];
    if binding.body_id == 0 || binding.body_id >= module.bodies.len { return blot_support::none<LocalCoreCall>(); } let body = module.bodies[binding.body_id]; if body.parameters.len > result.len || body.parameters.start > module.parameters.len || body.parameters.len > module.parameters.len - body.parameters.start { return blot_support::none<LocalCoreCall>(); }
    var bound: i64 = 0; for parameter in module.parameters[body.parameters.start..body.parameters.start + body.parameters.len] { if parameter.binding == 0 || parameter.binding >= module.bindings.len || module.bindings[parameter.binding].kind != blot_reuse_principal_interface::Kind.parameter { return blot_support::none<LocalCoreCall>(); }
        for index in 0..bound { if result.bindings[index] == parameter.binding { return blot_support::none<LocalCoreCall>(); } } result.bindings[bound] = parameter.binding; bound += 1;
    }
    result.body = body.root; while bound < result.len { if result.body == 0 || result.body >= module.nodes.len { return blot_support::none<LocalCoreCall>(); } let value = module.nodes[result.body]; if value.tag != blot_check_core::Tag.closure || value.a >= module.closures.len { return blot_support::none<LocalCoreCall>(); }
        let closure = module.closures[value.a]; let parameter = closure.parameter.binding; if parameter == 0 || parameter >= module.bindings.len || module.bindings[parameter].kind != blot_reuse_principal_interface::Kind.parameter { return blot_support::none<LocalCoreCall>(); } for index in 0..bound { if result.bindings[index] == parameter { return blot_support::none<LocalCoreCall>(); } }
        result.bindings[bound] = parameter; bound += 1; result.body = closure.body;
    } if result.body == 0 || result.body >= module.nodes.len { return blot_support::none<LocalCoreCall>(); } return blot_support::some(result);
}
struct SourceProjection { receiver: AstId, index: AstId }
fn projectionSource(tree: const Tree&, pool: Pool&, initial: AstId) -> blot_support::Option<SourceProjection> {
    let outer = unwrapped(tree, initial); if outer.tag != blot_parse_ast::tag_apply { return blot_support::none<SourceProjection>(); } let inner = unwrapped(tree, outer.a); if inner.tag != blot_parse_ast::tag_apply { return blot_support::none<SourceProjection>(); } let callee = unwrapped(tree, inner.a); if callee.tag != blot_parse_ast::tag_intrinsic { return blot_support::none<SourceProjection>(); }
    let name = pool.get(callee.a); if name != "@array.get" && name != "@product.get" { return blot_support::none<SourceProjection>(); } return blot_support::some(SourceProjection { inner.b, outer.b , ..});
}
recursive fn sourcePattern(tree: const Tree&, source: AstId, retained: u16, bindings: SourceBindings&, start: i64, remaining: i64&, depth: i64) -> bool {
    if source == 0 || remaining == 0 || depth >= 64 { return false; } remaining -= 1; let pattern = tree.node(source);
    match pattern.tag {
        blot_parse_ast::tag_pattern_integer, blot_parse_ast::tag_pattern_boolean => { return true; },
        blot_parse_ast::tag_pattern_name, blot_parse_ast::tag_pattern_field => {
            if pattern.tag == blot_parse_ast::tag_pattern_field && pattern.b != 0 { return sourcePattern(tree, pattern.b, retained, bindings, start, remaining, depth + 1); }
            for index in start..bindings.len { if bindings.entries[index].name == pattern.a { bindings.entries[index].retained |= retained; return true; } } return bindings.bind(pattern.a, retained) == blot_error::Error.none;
        },
        blot_parse_ast::tag_pattern_constructor => { if pattern.b == 0 { return true; } return sourcePattern(tree, pattern.b, retained, bindings, start, remaining, depth + 1); },
        blot_parse_ast::tag_pattern_product, blot_parse_ast::tag_pattern_record => { for child in tree.children(source) { if !sourcePattern(tree, child, retained, bindings, start, remaining, depth + 1) { return false; } } return true; },
        _ => { return false; },
    }
}
recursive fn sourceParameters(tree: const Tree&, pool: Pool&, initial: AstId, bindings: const SourceBindings&, remaining: i64&, depth: i64) -> Mask {
    if remaining == 0 || depth >= 64 { return blot_support::none<u16>(); } remaining -= 1; let source = unwrap(tree, initial); if source == 0 { return blot_support::none<u16>(); } let value = tree.node(source);
    match value.tag {
        blot_parse_ast::tag_name => { let known = bindings.get(value.a); if known.present { return known; } let text = pool.get(value.a); let separator = blot_check_capability_contract_source::find(text, '.'); if separator < 0 { return blot_support::none<u16>(); } let receiver,present = pool.lookup(text[..separator]); if !present { return blot_support::none<u16>(); } return bindings.get(receiver); },
        blot_parse_ast::tag_field_access => { return sourceParameters(tree, pool, value.a, bindings, remaining, depth + 1); },
        blot_parse_ast::tag_index_access => { let index = sourceParameters(tree, pool, value.b, bindings, remaining, depth + 1); if !index.present { return index; } return sourceParameters(tree, pool, value.a, bindings, remaining, depth + 1); },
        blot_parse_ast::tag_field => { if value.b == 0 { return bindings.get(value.a); } return sourceParameters(tree, pool, value.b, bindings, remaining, depth + 1); },
        blot_parse_ast::tag_integer, blot_parse_ast::tag_float, blot_parse_ast::tag_boolean, blot_parse_ast::tag_unit, blot_parse_ast::tag_constructor_ref => { return blot_support::some(0 as u16); },
        blot_parse_ast::tag_apply => {
            let call = localSourceCall(tree, source); if call.present { if bindings.get(call.value.name).present { return blot_support::none<u16>(); } var nested = SourceBindings {..};
                for index in 0..call.value.len { let argument = sourceParameters(tree, pool, call.value.arguments[index], bindings, remaining, depth + 1); if !argument.present || nested.bind(call.value.parameters[index], argument.value) != blot_error::Error.none { return blot_support::none<u16>(); } } return sourceParameters(tree, pool, call.value.body, nested, remaining, depth + 1);
            }
            let construction = constructionSource(tree, pool, source); if construction.present { var result: u16 = 0; for index in 0..construction.value.len { let input = sourceParameters(tree, pool, construction.value.inputs[index], bindings, remaining, depth + 1); if !input.present { return input; } result |= input.value; } return blot_support::some(result); }
            let projection = projectionSource(tree, pool, source); if projection.present { let index = sourceParameters(tree, pool, projection.value.index, bindings, remaining, depth + 1); if !index.present { return index; } return sourceParameters(tree, pool, projection.value.receiver, bindings, remaining, depth + 1); }
            let callee = unwrapped(tree, value.a); if callee.tag != blot_parse_ast::tag_constructor_ref { return blot_support::none<u16>(); } return sourceParameters(tree, pool, value.b, bindings, remaining, depth + 1);
        },
        blot_parse_ast::tag_type_witness => { return sourceParameters(tree, pool, value.a, bindings, remaining, depth + 1); },
        blot_parse_ast::tag_if_expr => { let condition = sourceParameters(tree, pool, value.a, bindings, remaining, depth + 1); if !condition.present { return condition; } let left = sourceParameters(tree, pool, value.b, bindings, remaining, depth + 1); if !left.present { return left; } let right = sourceParameters(tree, pool, value.c, bindings, remaining, depth + 1); if !right.present { return right; } return blot_support::some(left.value | right.value); },
        blot_parse_ast::tag_block => {
            if value.c != 0 { return blot_support::none<u16>(); } var environment = bindings; let children = tree.children(source);
            for child, index in children { let statement = tree.node(child); if statement.tag == blot_parse_ast::tag_return_stmt && index + 1 == children.len { return sourceParameters(tree, pool, statement.a, environment, remaining, depth + 1); } if statement.tag != blot_parse_ast::tag_let_stmt { return blot_support::none<u16>(); }
                let binding = tree.binding(child); let pattern = tree.node(binding.pattern); if pattern.tag != blot_parse_ast::tag_pattern_name || binding.fallback != 0 { return blot_support::none<u16>(); } let retained = sourceParameters(tree, pool, binding.value, environment, remaining, depth + 1); if !retained.present || environment.bind(pattern.a, retained.value) != blot_error::Error.none { return blot_support::none<u16>(); }
            } return blot_support::none<u16>();
        },
        blot_parse_ast::tag_case_expr => { return sourceCaseParameters(tree, pool, value, bindings, remaining, depth); },
        blot_parse_ast::tag_lambda => { return sourceCaptures(tree, pool, source, bindings, [], remaining, depth + 1); },
        blot_parse_ast::tag_product, blot_parse_ast::tag_array, blot_parse_ast::tag_record => { var result: u16 = 0; for child in tree.children(source) { let retained = sourceParameters(tree, pool, child, bindings, remaining, depth + 1); if !retained.present { return retained; } result |= retained.value; } return blot_support::some(result); },
        _ => { return blot_support::none<u16>(); },
    }
}
fn sourceCaseParameters(tree: const Tree&, pool: Pool&, value: blot_parse_ast::Node, bindings: const SourceBindings&, remaining: i64&, depth: i64) -> Mask {
    let inputs = tree.extra.items[value.a..value.a + 2]; if inputs[1] > 16 { return blot_support::none<u16>(); } var retained: u16[16] = [0;16];
    for input, index in tree.list(blot_parse_ast::List { inputs[0], inputs[1] , ..}) { let mask = sourceParameters(tree, pool, input, bindings, remaining, depth + 1); if !mask.present { return mask; } retained[index] = mask.value; }
    var result: u16 = 0;
    for arm_id in tree.list(blot_parse_ast::List { value.b, value.c , ..}) { let arm = tree.node(arm_id); var environment = bindings; let start = environment.len;
        for row in tree.list(blot_parse_ast::List { arm.a, arm.b , ..}) { let patterns = tree.children(row); if patterns.len != inputs[1] { return blot_support::none<u16>(); } for pattern, index in patterns { if !sourcePattern(tree, pattern, retained[index], environment, start, remaining, depth + 1) { return blot_support::none<u16>(); } } }
        let details = tree.extra.items[arm.c..arm.c + 2]; if details[0] != 0 { let guard_ = sourceParameters(tree, pool, details[0], environment, remaining, depth + 1); if !guard_.present { return guard_; } }
        let mask = sourceParameters(tree, pool, details[1], environment, remaining, depth + 1); if !mask.present { return mask; } result |= mask.value;
    } return blot_support::some(result);
}
fn pureCallee(tree: const Tree&, pool: Pool&, initial: AstId) -> bool {
    var current = initial; for attempt in 0..128 { let value = unwrapped(tree, current); if value.tag == blot_parse_ast::tag_apply { current = value.a; continue; } if value.tag != blot_parse_ast::tag_intrinsic { return false; } let name = pool.get(value.a);
        if name.starts_with("@u32.") || name.starts_with("@f32.") { return true; } return name == "@product.get" || name == "@array.get" || name == "@array.set" || name == "@array.length" || name == "@array.fill";
    } return false;
}
fn hasName(locals: const u32[:], name: u32) -> bool { for local in locals { if local == name { return true; } } return false; }
recursive fn sourceCaptures(tree: const Tree&, pool: Pool&, initial: AstId, bindings: const SourceBindings&, locals: const u32[:], remaining: i64&, depth: i64) -> Mask {
    if remaining == 0 || depth >= 64 { return blot_support::none<u16>(); } remaining -= 1; let source = unwrap(tree, initial); if source == 0 { return blot_support::none<u16>(); } let value = tree.node(source);
    match value.tag {
        blot_parse_ast::tag_intrinsic, blot_parse_ast::tag_integer, blot_parse_ast::tag_float, blot_parse_ast::tag_string, blot_parse_ast::tag_boolean, blot_parse_ast::tag_unit => { return blot_support::some(0 as u16); },
        blot_parse_ast::tag_name => { if hasName(locals, value.a) { return blot_support::some(0 as u16); } let formal = bindings.get(value.a); if formal.present { return formal; } let text = pool.get(value.a); let separator = blot_check_capability_contract_source::find(text, '.'); if separator < 0 { return blot_support::none<u16>(); }
            let receiver,present = pool.lookup(text[..separator]); if !present { return blot_support::none<u16>(); } if hasName(locals, receiver) { return blot_support::some(0 as u16); } return bindings.get(receiver);
        },
        blot_parse_ast::tag_field => { if value.b == 0 { if hasName(locals, value.a) { return blot_support::some(0 as u16); } return bindings.get(value.a); } return sourceCaptures(tree, pool, value.b, bindings, locals, remaining, depth + 1); },
        blot_parse_ast::tag_lambda => { if locals.len == 64 { return blot_support::none<u16>(); } var nested: u32[64] = [0;64]; for local, index in locals { nested[index] = local; } nested[locals.len] = tree.parameter(value.a).name; return sourceCaptures(tree, pool, value.b, bindings, nested[..locals.len + 1], remaining, depth + 1); },
        blot_parse_ast::tag_field_access, blot_parse_ast::tag_return_stmt, blot_parse_ast::tag_function_return_stmt, blot_parse_ast::tag_yield_stmt => { return sourceCaptures(tree, pool, value.a, bindings, locals, remaining, depth + 1); },
        blot_parse_ast::tag_apply, blot_parse_ast::tag_index_access => {
            if value.tag == blot_parse_ast::tag_apply { let argument = unwrapped(tree, value.b); if unwrap(tree, value.b) == 0 || (argument.tag != blot_parse_ast::tag_unit && !pureCallee(tree, pool, value.a)) { return blot_support::none<u16>(); } }
            let left = sourceCaptures(tree, pool, value.a, bindings, locals, remaining, depth + 1); if !left.present { return left; } let right = sourceCaptures(tree, pool, value.b, bindings, locals, remaining, depth + 1); if !right.present { return right; } return blot_support::some(left.value | right.value);
        },
        blot_parse_ast::tag_unary => { if pool.get(value.a) != "-" { return blot_support::none<u16>(); } return sourceCaptures(tree, pool, value.b, bindings, locals, remaining, depth + 1); },
        blot_parse_ast::tag_binary => { let left = sourceCaptures(tree, pool, value.b, bindings, locals, remaining, depth + 1); if !left.present { return left; } let right = sourceCaptures(tree, pool, value.c, bindings, locals, remaining, depth + 1); if !right.present { return right; } return blot_support::some(left.value | right.value); },
        blot_parse_ast::tag_block => {
            if value.c != 0 { return blot_support::none<u16>(); } var nested = bindings; var result: u16 = 0;
            for child in tree.children(source) { let statement = tree.node(child);
                if statement.tag == blot_parse_ast::tag_let_stmt { let binding = tree.binding(child); if binding.fallback != 0 { return blot_support::none<u16>(); } let mask = sourceCaptures(tree, pool, binding.value, nested, locals, remaining, depth + 1); if !mask.present { return mask; } result |= mask.value; let start = nested.len; if !sourcePattern(tree, binding.pattern, 0, nested, start, remaining, depth + 1) { return blot_support::none<u16>(); } }
                else { let mask = sourceCaptures(tree, pool, child, nested, locals, remaining, depth + 1); if !mask.present { return mask; } result |= mask.value; }
            } return blot_support::some(result);
        },
        blot_parse_ast::tag_case_expr => { return sourceCaseCaptures(tree, pool, value, bindings, locals, remaining, depth); },
        blot_parse_ast::tag_if_expr => { let condition = sourceCaptures(tree, pool, value.a, bindings, locals, remaining, depth + 1); if !condition.present { return condition; } let left = sourceCaptures(tree, pool, value.b, bindings, locals, remaining, depth + 1); if !left.present { return left; } let right = sourceCaptures(tree, pool, value.c, bindings, locals, remaining, depth + 1); if !right.present { return right; } return blot_support::some(condition.value | left.value | right.value); },
        blot_parse_ast::tag_product, blot_parse_ast::tag_record, blot_parse_ast::tag_array => { var result: u16 = 0; for child in tree.children(source) { let mask = sourceCaptures(tree, pool, child, bindings, locals, remaining, depth + 1); if !mask.present { return mask; } result |= mask.value; } return blot_support::some(result); },
        _ => { return blot_support::none<u16>(); },
    }
}
fn sourceCaseCaptures(tree: const Tree&, pool: Pool&, value: blot_parse_ast::Node, bindings: const SourceBindings&, locals: const u32[:], remaining: i64&, depth: i64) -> Mask {
    let inputs = tree.extra.items[value.a..value.a + 2]; if inputs[1] > 16 { return blot_support::none<u16>(); } var result: u16 = 0;
    for input in tree.list(blot_parse_ast::List { inputs[0], inputs[1] , ..}) { let mask = sourceCaptures(tree, pool, input, bindings, locals, remaining, depth + 1); if !mask.present { return mask; } result |= mask.value; }
    for arm_id in tree.list(blot_parse_ast::List { value.b, value.c , ..}) { let arm = tree.node(arm_id); var nested = bindings; let start = nested.len;
        for row in tree.list(blot_parse_ast::List { arm.a, arm.b , ..}) { let patterns = tree.children(row); if patterns.len != inputs[1] { return blot_support::none<u16>(); } for pattern in patterns { if !sourcePattern(tree, pattern, 0, nested, start, remaining, depth + 1) { return blot_support::none<u16>(); } } }
        let details = tree.extra.items[arm.c..arm.c + 2]; if details[0] != 0 { let mask = sourceCaptures(tree, pool, details[0], nested, locals, remaining, depth + 1); if !mask.present { return mask; } result |= mask.value; }
        let mask = sourceCaptures(tree, pool, details[1], nested, locals, remaining, depth + 1); if !mask.present { return mask; } result |= mask.value;
    } return blot_support::some(result);
}
fn parameterCore(module: const Module&, body: blot_check_core::Body, summary: Parameters) -> bool { return parameterCoreWithOwners(module, body, summary, []); }
fn parameterCoreWithOwners(module: const Module&, body: blot_check_core::Body, summary: Parameters, owners: const ModuleRef[:]) -> bool {
    if !summary.valid() || !summary.present() || !body.is_function { return false; } var arity = summary.arity() as u32;
    if summary.kind == ParameterResult.member_closure_unit || summary.kind == ParameterResult.captured_unit { arity += 1; }
    if body.parameters.len != arity || body.parameters.start > module.parameters.len || body.parameters.len > module.parameters.len - body.parameters.start || body.root == 0 || body.root >= module.nodes.len { return false; }
    let root = module.nodes[body.root]; var remaining: i64 = 4096; let parameters = module.parameters[body.parameters.start..body.parameters.start + summary.arity()];
    if summary.invokes() { let reconstructed = invocationCore(module, body, owners, remaining); return reconstructed.present && summary == reconstructed.value; }
    if summary.kind == ParameterResult.product {
        if body.binding < module.bindings.len && module.bindings[body.binding].capability_flow == Contract.input_shape { return blot_check_capability_contract_core::inputBodyWithOwners(module, body, summary, owners); }
        let result = coreParameters(module, body.root, parameters, [], remaining, 0); return result.present && result.value == summary.result();
    }
    if summary.kind == ParameterResult.captured_unit { let unit = module.parameters[body.parameters.start + summary.arity()]; if unit.ty != blot_check_types::unit { return false; } let ignored: u32[1] = [unit.binding]; let result = coreCaptures(module, body.root, parameters, [], ignored, remaining, 0, body.closed_rows); return result.present && result.value == summary.result(); }
    if root.tag != blot_check_core::Tag.apply || root.b == 0 || root.b >= module.nodes.len { return false; } let argument = module.nodes[root.b];
    if summary.kind != ParameterResult.member_closure_unit || argument.tag != blot_check_core::Tag.constant || argument.ty != blot_check_types::unit || argument.a != 0 || root.a == 0 || root.a >= module.nodes.len { return false; }
    var selected = root.a; if summary.kind == ParameterResult.member_closure_unit { if module.parameters[body.parameters.start + summary.arity()].ty != blot_check_types::unit { return false; } let operation = module.nodes[selected];
        if operation.tag != blot_check_core::Tag.operation_value || operation.a >= module.operation_values.len { return false; } selected = module.operation_values[operation.a].capability; if selected == 0 || selected >= module.nodes.len { return false; } let capability = module.nodes[selected]; if capability.ty >= module.types.nodes.len || module.types.nodes[capability.ty].tag != blot_check_types::Tag.scoped { return false; }
    }
    if module.nodes[selected].tag != blot_check_core::Tag.reference { return false; } let target = coreParameters(module, selected, parameters, [], remaining, 0); return target.present && target.value == summary.result();
}
struct CoreInvocationBinding { binding: u32, mask: u16 }
struct CoreInvocationBindings { entries: CoreInvocationBinding[16], len: i64 = 0 }
fn get(self_: const CoreInvocationBindings&, binding: u32) -> Mask { for index in 0..self_.len { if self_.entries[index].binding == binding { return blot_support::some(self_.entries[index].mask); } } return blot_support::none<u16>(); }
fn bind(self_: CoreInvocationBindings&, binding: u32, mask: u16) -> bool { if binding == 0 || self_.len == self_.entries.len || self_.get(binding).present { return false; } self_.entries[self_.len] = CoreInvocationBinding { binding, mask , ..}; self_.len += 1; return true; }
fn invocationCore(module: const Module&, body: blot_check_core::Body, owners: const ModuleRef[:], remaining: i64&) -> blot_support::Option<Parameters> {
    if !body.is_function || body.parameters.len == 0 || body.parameters.len > 16 || body.parameters.start > module.parameters.len || body.parameters.len > module.parameters.len - body.parameters.start { return blot_support::none<Parameters>(); } var bindings = CoreInvocationBindings {..};
    for parameter, index in module.parameters[body.parameters.start..body.parameters.start + body.parameters.len] { if remaining == 0 { return blot_support::none<Parameters>(); } remaining -= 1;
        if parameter.binding == 0 || parameter.binding >= module.bindings.len || module.bindings[parameter.binding].kind != blot_reuse_principal_interface::Kind.parameter || !bindings.bind(parameter.binding, (1 as u16) << index) { return blot_support::none<Parameters>(); }
    } return coreInvocation(module, body.root, bindings, body.parameters.len as u8, owners, remaining, 0);
}
fn coreInvocationOwner(module: const Module&, owners: const ModuleRef[:], unit: u32, remaining: i64&) -> const Module? {
    if unit == 0 || unit == module.unit { return module; }
    var selected: const Module? = null;
    for entry in owners {
        let owner .= entry.value;
        if remaining == 0 { return null; } remaining -= 1;
        if owner.unit != unit { continue; }
        if selected { if selected.owner_id == 0 || selected.owner_id != owner.owner_id { return null; } }
        selected .= owner;
    }
    return selected;
}
recursive fn coreInvocation(module: const Module&, id: u32, bindings: const CoreInvocationBindings&, inputs: u8, owners: const ModuleRef[:], remaining: i64&, depth: i64) -> blot_support::Option<Parameters> {
    if remaining < 17 || depth >= 128 { return blot_support::none<Parameters>(); } remaining -= 17; let found = coreCall(module, id); if !found.present { return blot_support::none<Parameters>(); } let call = found.value;
    if call.target.unit == 0 || call.target.unit == module.unit { let callback = bindings.get(call.target.binding);
        if callback.present { var arguments: u16[16] = [0;16]; if call.len == 1 { let argument = module.node(call.arguments[0]); if argument.tag == blot_check_core::Tag.constant && argument.ty == blot_check_types::unit && argument.a == 0 && argument.b == 0 && argument.c == 0 && argument.op == blot_check_core::Op.none { return invocationResult(inputs, callback.value, [], true); } }
            for index in 0..call.len { let node = module.node(call.arguments[index]); if node.tag != blot_check_core::Tag.reference || node.a >= module.references.len { return blot_support::none<Parameters>(); } let reference = module.references[node.a]; if reference.unit != 0 && reference.unit != module.unit { return blot_support::none<Parameters>(); } let mask = bindings.get(reference.binding); if !mask.present { return blot_support::none<Parameters>(); } arguments[index] = mask.value; }
            return invocationResult(inputs, callback.value, arguments[..call.len], false);
        }
    }
    let producer .= coreInvocationOwner(module, owners, call.target.unit, remaining);
    if !producer { return blot_support::none<Parameters>(); }
    if call.target.binding == 0 || call.target.binding >= producer.bindings.len { return blot_support::none<Parameters>(); } let binding = producer.bindings[call.target.binding]; if binding.kind != blot_reuse_principal_interface::Kind.global || binding.body_id == 0 || binding.body_id >= producer.bodies.len { return blot_support::none<Parameters>(); } let body = producer.bodies[binding.body_id];
    if !body.is_function || body.parameters.len != call.len || body.parameters.start > producer.parameters.len || body.parameters.len > producer.parameters.len - body.parameters.start { return blot_support::none<Parameters>(); } var nested = CoreInvocationBindings {..};
    for index in 0..call.len { let formal = producer.parameters[body.parameters.start + index]; if formal.binding == 0 || formal.binding >= producer.bindings.len || producer.bindings[formal.binding].kind != blot_reuse_principal_interface::Kind.parameter { return blot_support::none<Parameters>(); } let node = module.node(call.arguments[index]); if node.tag != blot_check_core::Tag.reference || node.a >= module.references.len { return blot_support::none<Parameters>(); }
        let reference = module.references[node.a]; if reference.unit != 0 && reference.unit != module.unit { return blot_support::none<Parameters>(); } let mask = bindings.get(reference.binding); if !mask.present || !nested.bind(formal.binding, mask.value) { return blot_support::none<Parameters>(); }
    } return coreInvocation(producer, body.root, nested, inputs, owners, remaining, depth + 1);
}
fn unaryCore(module: const Module&, body: blot_check_core::Body, contract: Contract) -> bool { return unaryCoreWithOwners(module, body, contract, []); }
fn equal(module: const Module&, left: u32, right: u32) -> bool { let result, error = blot_check_rank_equal::equal(module.types, left, right, true); return error == blot_error::Error.none && result; }
recursive fn unaryCoreWithOwners(module: const Module&, body: blot_check_core::Body, contract: Contract, owners: const ModuleRef[:]) -> bool {
    if contract == Contract.input_shape { if body.binding >= module.bindings.len { return false; } return blot_check_capability_contract_core::inputBodyWithOwners(module, body, module.bindings[body.binding].capability_parameters, owners); }
    if contract != Contract.identity && contract != Contract.member_unit { return false; }
    if !body.is_function || body.parameters.len != 1 || body.parameters.start >= module.parameters.len || body.root == 0 || body.root >= module.nodes.len || body.scheme.root >= module.types.nodes.len { return false; }
    let function = module.types.node(body.scheme.root); if function.tag != blot_check_types::Tag.function || function.a >= module.types.nodes.len || function.b >= module.types.nodes.len { return false; } let parameter = module.parameters[body.parameters.start];
    if parameter.ty >= module.types.nodes.len || module.nodes[body.root].ty >= module.types.nodes.len || !equal(module, function.a, parameter.ty) || !equal(module, function.b, module.nodes[body.root].ty) { return false; } var value = module.nodes[body.root];
    if contract == Contract.member_unit { if value.tag != blot_check_core::Tag.apply || value.a == 0 || value.a >= module.nodes.len || value.b == 0 || value.b >= module.nodes.len { return false; } let argument = module.nodes[value.b]; if argument.tag != blot_check_core::Tag.constant || argument.ty != blot_check_types::unit || argument.a != 0 { return false; }
        value = module.nodes[value.a]; if value.tag != blot_check_core::Tag.operation_value || value.a >= module.operation_values.len { return false; } let receiver = module.operation_values[value.a].capability; if receiver == 0 || receiver >= module.nodes.len { return false; } value = module.nodes[receiver];
    }
    if value.tag != blot_check_core::Tag.reference || value.a >= module.references.len { return false; } let reference = module.references[value.a]; if value.ty >= module.types.nodes.len || !equal(module, value.ty, parameter.ty) { return false; }
    return (reference.unit == 0 || reference.unit == module.unit) && reference.binding == parameter.binding;
}
struct CoreAlias { binding: u32, retained: u16 }
struct Formal { binding: u32 }
fn retainedCore(module: const Module&, source: u32, bindings: const u32[:], remaining: i64&) -> Mask {
    if bindings.len > 16 { return blot_support::none<u16>(); } var parameters: Formal[16] = [default<Formal>();16];
    for binding, index in bindings { if binding == 0 || binding >= module.bindings.len || module.bindings[binding].kind != blot_reuse_principal_interface::Kind.parameter { return blot_support::none<u16>(); } for prior in bindings[..index] { if prior == binding { return blot_support::none<u16>(); } } parameters[index] = Formal { binding , ..}; }
    return coreParameters(module, source, parameters[..bindings.len], [], remaining, 0);
}
fn primitiveType(tag: blot_check_types::Tag) -> bool { return tag == blot_check_types::Tag.unit || tag == blot_check_types::Tag.boolean || tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32; }
recursive fn coreParameters<P>(module: const Module&, source: u32, parameters: const P[:], aliases: const CoreAlias[:], remaining: i64&, depth: i64) -> Mask {
    if remaining == 0 || depth >= 64 || source == 0 || source >= module.nodes.len { return blot_support::none<u16>(); } remaining -= 1; let value = module.nodes[source];
    match value.tag {
        call, apply => { let found = localCoreCall(module, source); if !found.present { return blot_support::none<u16>(); } let call = found.value; var nested: CoreAlias[16] = [default<CoreAlias>();16];
            for index in 0..call.len { let retained = coreParameters(module, call.arguments[index], parameters, aliases, remaining, depth + 1); if !retained.present { return retained; } nested[index] = CoreAlias { call.bindings[index], retained.value , ..}; } return coreParameters(module, call.body, parameters, nested[..call.len], remaining, depth + 1);
        },
        reference => { if value.a >= module.references.len { return blot_support::none<u16>(); } let reference = module.references[value.a]; if reference.unit != 0 && reference.unit != module.unit { return blot_support::none<u16>(); } var alias = aliases.len;
            while alias != 0 { alias -= 1; if aliases[alias].binding == reference.binding { return blot_support::some(aliases[alias].retained); } } for parameter, index in parameters { if reference.binding == parameter.binding { return blot_support::some((1 as u16) << index); } } return blot_support::none<u16>();
        },
        constant => { if value.ty >= module.types.nodes.len || !primitiveType(module.types.nodes[value.ty].tag) { return blot_support::none<u16>(); } return blot_support::some(0 as u16); },
        array_op => { if value.c != blot_backend_collection_ops::opCode(blot_backend_collection_ops::Op.get) || value.b != 2 || value.a > module.extra.len || value.b > module.extra.len - value.a { return blot_support::none<u16>(); }
            let index = coreParameters(module, module.extra[value.a + 1], parameters, aliases, remaining, depth + 1); if !index.present { return index; } return coreParameters(module, module.extra[value.a], parameters, aliases, remaining, depth + 1);
        },
        operation_value => { if value.a >= module.operation_values.len { return blot_support::none<u16>(); } return coreParameters(module, module.operation_values[value.a].capability, parameters, aliases, remaining, depth + 1); },
        computation => { return coreParameters(module, value.a, parameters, aliases, remaining, depth + 1); },
        effect_provider, state_provider => { let first = coreParameters(module, value.a, parameters, aliases, remaining, depth + 1); if !first.present { return first; } let second = coreParameters(module, value.b, parameters, aliases, remaining, depth + 1); if !second.present { return second; } var result = first.value | second.value;
            if value.tag == blot_check_core::Tag.state_provider { let third = coreParameters(module, value.c, parameters, aliases, remaining, depth + 1); if !third.present { return third; } result |= third.value; } return blot_support::some(result);
        },
        project => { if value.b >= module.projections.len { return blot_support::none<u16>(); } return coreParameters(module, value.a, parameters, aliases, remaining, depth + 1); },
        construct => { if value.b == 0 { return blot_support::some(0 as u16); } return coreParameters(module, value.b, parameters, aliases, remaining, depth + 1); },
        block_ => { if value.a > module.extra.len || value.b > module.extra.len - value.a || aliases.len > 128 { return blot_support::none<u16>(); } var environment: CoreAlias[128] = [default<CoreAlias>();128]; for alias, index in aliases { environment[index] = alias; } var count = aliases.len; let children = module.extra[value.a..value.a + value.b];
            for child, index in children { if child == 0 || child >= module.nodes.len { return blot_support::none<u16>(); } let statement = module.nodes[child]; if statement.tag == blot_check_core::Tag.return_ && index + 1 == children.len { if statement.b != source { return blot_support::none<u16>(); } return coreParameters(module, statement.a, parameters, environment[..count], remaining, depth + 1); }
                if statement.tag != blot_check_core::Tag.bind || count == environment.len { return blot_support::none<u16>(); } let retained = coreParameters(module, statement.b, parameters, environment[..count], remaining, depth + 1); if !retained.present { return retained; } environment[count] = CoreAlias { statement.a, retained.value , ..}; count += 1;
            } return blot_support::none<u16>();
        },
        if_value => { let condition = coreParameters(module, value.a, parameters, aliases, remaining, depth + 1); if !condition.present { return condition; } let left = coreParameters(module, value.b, parameters, aliases, remaining, depth + 1); if !left.present { return left; } let right = coreParameters(module, value.c, parameters, aliases, remaining, depth + 1); if !right.present { return right; } return blot_support::some(left.value | right.value); },
        match_ => { return coreCaseParameters(module, value, parameters, aliases, remaining, depth); },
        closure => { if value.a >= module.closures.len { return blot_support::none<u16>(); } let closure = module.closures[value.a]; let ignored: u32[1] = [closure.parameter.binding]; let actual = coreCaptures(module, closure.body, parameters, aliases, ignored, remaining, depth + 1, closure.closed_rows); if !actual.present { return actual; }
            let declared = declaredCoreCaptures(module, closure, parameters, aliases, ignored, remaining); if !declared.present { return declared; } return blot_support::some(actual.value | declared.value);
        },
        product, record, array => { if value.a > module.extra.len || value.b > module.extra.len - value.a { return blot_support::none<u16>(); } var result: u16 = 0; for child in module.extra[value.a..value.a + value.b] { let retained = coreParameters(module, child, parameters, aliases, remaining, depth + 1); if !retained.present { return retained; } result |= retained.value; } return blot_support::some(result); },
        _ => { return blot_support::none<u16>(); },
    }
}
fn coreCaseParameters<P>(module: const Module&, value: blot_check_core::Node, parameters: const P[:], aliases: const CoreAlias[:], remaining: i64&, depth: i64) -> Mask {
    if value.a >= module.matches.len || aliases.len > 128 { return blot_support::none<u16>(); } let info = module.matches[value.a];
    if info.statement || info.inputs.len > 16 || info.inputs.start > module.extra.len || info.inputs.len > module.extra.len - info.inputs.start || info.arms.start > module.match_arms.len || info.arms.len > module.match_arms.len - info.arms.start { return blot_support::none<u16>(); }
    var retained: u16[16] = [0;16]; for input, index in module.extra[info.inputs.start..info.inputs.start + info.inputs.len] { let mask = coreParameters(module, input, parameters, aliases, remaining, depth + 1); if !mask.present { return mask; } retained[index] = mask.value; } var result: u16 = 0;
    for arm in module.match_arms[info.arms.start..info.arms.start + info.arms.len] { if arm.rows.start > module.pattern_rows.len || arm.rows.len > module.pattern_rows.len - arm.rows.start { return blot_support::none<u16>(); } var environment: CoreAlias[128] = [default<CoreAlias>();128]; for alias, index in aliases { environment[index] = alias; } var count = aliases.len;
        for row in module.pattern_rows[arm.rows.start..arm.rows.start + arm.rows.len] { if row.patterns.len != info.inputs.len || row.patterns.start > module.extra.len || row.patterns.len > module.extra.len - row.patterns.start { return blot_support::none<u16>(); }
            for pattern, index in module.extra[row.patterns.start..row.patterns.start + row.patterns.len] { if !corePattern(module, pattern, retained[index], environment, count, aliases.len, remaining, depth + 1) { return blot_support::none<u16>(); } }
        }
        if arm.guard_ != 0 { let mask = coreParameters(module, arm.guard_, parameters, environment[..count], remaining, depth + 1); if !mask.present { return mask; } } let mask = coreParameters(module, arm.body, parameters, environment[..count], remaining, depth + 1); if !mask.present { return mask; } result |= mask.value;
    } return blot_support::some(result);
}
recursive fn corePattern(module: const Module&, source: u32, retained: u16, environment: CoreAlias[128]&, count: i64&, start: i64, remaining: i64&, depth: i64) -> bool {
    if source == 0 || source >= module.patterns.len || remaining == 0 || depth >= 64 { return false; } remaining -= 1; let pattern = module.patterns[source];
    match pattern.tag {
        wildcard, constant => { return true; },
        bind => { for index in start..count { if environment[index].binding == pattern.a { environment[index].retained |= retained; return true; } } if count == environment.len { return false; } environment[count] = CoreAlias { pattern.a, retained , ..}; count += 1; return true; },
        constructor, record_payload => { if pattern.b == 0 { return true; } return corePattern(module, pattern.b, retained, environment, count, start, remaining, depth + 1); },
        product => { if pattern.a > module.extra.len || pattern.b > module.extra.len - pattern.a { return false; } for child in module.extra[pattern.a..pattern.a + pattern.b] { if !corePattern(module, child, retained, environment, count, start, remaining, depth + 1) { return false; } } return true; },
        _ => { return false; },
    }
}
fn declaredCoreCaptures<P>(module: const Module&, closure: blot_check_core::ClosureInfo, parameters: const P[:], aliases: const CoreAlias[:], ignored: const u32[:], remaining: i64&) -> Mask {
    let captures = closure.captures; if captures.start > module.extra.len || captures.len > module.extra.len - captures.start { return blot_support::none<u16>(); } var result: u16 = 0;
    for binding in module.extra[captures.start..captures.start + captures.len] { if remaining == 0 || binding == 0 || binding >= module.bindings.len { return blot_support::none<u16>(); } remaining -= 1; if hasName(ignored, binding) { continue; } var known = false; var index = aliases.len;
        while index != 0 { index -= 1; if aliases[index].binding != binding { continue; } result |= aliases[index].retained; known = true; break; } if known { continue; }
        for parameter, ordinal in parameters { if parameter.binding == binding { result |= (1 as u16) << ordinal; known = true; break; } } if !known { return blot_support::none<u16>(); }
    } return blot_support::some(result);
}
fn scalarCallOperands(module: const Module&, id: u32, closed_rows: blot_check_types::List, remaining: i64&) -> blot_support::Option<const u32[:]> {
    if id == 0 || id >= module.nodes.len || remaining == 0 { return blot_support::none<const u32[:]>(); } remaining -= 1; let node = module.nodes[id];
    if node.tag != blot_check_core::Tag.call || node.a >= module.calls.len || node.c > 16 || node.b > module.extra.len || node.c > module.extra.len - node.b { return blot_support::none<const u32[:]>(); } let call = module.calls[node.a]; if call.target.binding == 0 { return blot_support::none<const u32[:]>(); }
    if call.target.unit == 0 || call.target.unit == module.unit { if call.target.binding >= module.bindings.len { return blot_support::none<const u32[:]>(); } let kind = module.bindings[call.target.binding].kind; if kind != blot_reuse_principal_interface::Kind.global && kind != blot_reuse_principal_interface::Kind.external { return blot_support::none<const u32[:]>(); } }
    var signature = call.callee_type; let operands = module.extra[node.b..node.b + node.c];
    for operand in operands { if remaining == 0 { return blot_support::none<const u32[:]>(); } remaining -= 1;
        if operand == 0 || operand >= module.nodes.len || signature == 0 || signature >= module.types.nodes.len { return blot_support::none<const u32[:]>(); } let arrow = module.types.node(signature);
        if arrow.tag != blot_check_types::Tag.function || arrow.a == 0 || arrow.a >= module.types.nodes.len || arrow.c >= module.types.effects.rows.len || !primitiveType(module.types.node(arrow.a).tag) || module.nodes[operand].ty != arrow.a { return blot_support::none<const u32[:]>(); } let row = module.types.effects.rows[arrow.c]; if row.labels.len != 0 { return blot_support::none<const u32[:]>(); }
        if row.tail != blot_check_effects::Tail.closed {
            if closed_rows.start > module.types.extra.len || closed_rows.len > module.types.extra.len - closed_rows.start { return blot_support::none<const u32[:]>(); } var variable: u32 = 0;
            match row.tail { variable payload => { variable = payload.value; }, _ => { return blot_support::none<const u32[:]>(); }, }
            var certified = false; for candidate in module.types.extra[closed_rows.start..closed_rows.start + closed_rows.len] { if remaining == 0 { return blot_support::none<const u32[:]>(); } remaining -= 1; if candidate == variable { certified = true; } } if !certified { return blot_support::none<const u32[:]>(); }
        } signature = arrow.b;
    }
    if signature == 0 || signature >= module.types.nodes.len || node.ty != signature || !primitiveType(module.types.node(signature).tag) { return blot_support::none<const u32[:]>(); } return blot_support::some<const u32[:]>(operands);
}
recursive fn coreCaptures<P>(module: const Module&, source: u32, parameters: const P[:], aliases: const CoreAlias[:], ignored: const u32[:], remaining: i64&, depth: i64, closed_rows: blot_check_types::List) -> Mask {
    if remaining == 0 || depth >= 64 || source == 0 || source >= module.nodes.len { return blot_support::none<u16>(); } remaining -= 1; let value = module.nodes[source];
    match value.tag {
        reference => { if value.a >= module.references.len { return blot_support::none<u16>(); } let reference = module.references[value.a]; if reference.unit != 0 && reference.unit != module.unit { return blot_support::none<u16>(); } if hasName(ignored, reference.binding) { return blot_support::some(0 as u16); } var alias = aliases.len;
            while alias != 0 { alias -= 1; if aliases[alias].binding == reference.binding { return blot_support::some(aliases[alias].retained); } } for parameter, index in parameters { if reference.binding == parameter.binding { return blot_support::some((1 as u16) << index); } } return blot_support::none<u16>();
        },
        constant => { if value.ty >= module.types.nodes.len || !primitiveType(module.types.nodes[value.ty].tag) { return blot_support::none<u16>(); } return blot_support::some(0 as u16); },
        primitive_function => { return blot_support::some(0 as u16); },
        operation_value => { if value.a >= module.operation_values.len { return blot_support::none<u16>(); } let operation = module.operation_values[value.a]; if operation.capability == 0 { return blot_support::none<u16>(); } return coreCaptures(module, operation.capability, parameters, aliases, ignored, remaining, depth + 1, closed_rows); },
        call => { let operands = scalarCallOperands(module, source, closed_rows, remaining); if !operands.present { return blot_support::none<u16>(); } var result: u16 = 0; for operand in operands.value { let mask = coreCaptures(module, operand, parameters, aliases, ignored, remaining, depth + 1, closed_rows); if !mask.present { return mask; } result |= mask.value; } return blot_support::some(result); },
        apply => { if value.b == 0 || value.b >= module.nodes.len { return blot_support::none<u16>(); } let argument = module.nodes[value.b]; if argument.tag != blot_check_core::Tag.constant || argument.ty != blot_check_types::unit || argument.a != 0 { return blot_support::none<u16>(); }
            let left = coreCaptures(module, value.a, parameters, aliases, ignored, remaining, depth + 1, closed_rows); if !left.present { return left; } let right = coreCaptures(module, value.b, parameters, aliases, ignored, remaining, depth + 1, closed_rows); if !right.present { return right; } return blot_support::some(left.value | right.value);
        },
        scalar, logical => { let left = coreCaptures(module, value.a, parameters, aliases, ignored, remaining, depth + 1, closed_rows); if !left.present || value.b == 0 { return left; } let right = coreCaptures(module, value.b, parameters, aliases, ignored, remaining, depth + 1, closed_rows); if !right.present { return right; } return blot_support::some(left.value | right.value); },
        project, return_ => { return coreCaptures(module, value.a, parameters, aliases, ignored, remaining, depth + 1, closed_rows); },
        construct => { return coreCaptures(module, value.b, parameters, aliases, ignored, remaining, depth + 1, closed_rows); },
        closure => { if value.a >= module.closures.len || ignored.len == 64 { return blot_support::none<u16>(); } let closure = module.closures[value.a]; var locals: u32[64] = [0;64]; for value, index in ignored { locals[index] = value; } locals[ignored.len] = closure.parameter.binding; let nested = locals[..ignored.len + 1];
            let actual = coreCaptures(module, closure.body, parameters, aliases, nested, remaining, depth + 1, closed_rows); if !actual.present { return actual; } let declared = declaredCoreCaptures(module, closure, parameters, aliases, nested, remaining); if !declared.present { return declared; } return blot_support::some(actual.value | declared.value);
        },
        block_, suite => { if value.a > module.extra.len || value.b > module.extra.len - value.a || aliases.len > 128 { return blot_support::none<u16>(); } var nested: CoreAlias[128] = [default<CoreAlias>();128]; for alias, index in aliases { nested[index] = alias; } var count = aliases.len; var result: u16 = 0;
            for child in module.extra[value.a..value.a + value.b] { if child == 0 || child >= module.nodes.len { return blot_support::none<u16>(); } let statement = module.nodes[child];
                if statement.tag == blot_check_core::Tag.bind { let mask = coreCaptures(module, statement.b, parameters, nested[..count], ignored, remaining, depth + 1, closed_rows); if !mask.present { return mask; } result |= mask.value; if count == nested.len { return blot_support::none<u16>(); } nested[count] = CoreAlias { statement.a, 0 , ..}; count += 1; }
                else if statement.tag == blot_check_core::Tag.pattern_bind { let mask = coreCaptures(module, statement.b, parameters, nested[..count], ignored, remaining, depth + 1, closed_rows); if !mask.present { return mask; } result |= mask.value;
                    if statement.c != 0 { let mask = coreCaptures(module, statement.c, parameters, nested[..count], ignored, remaining, depth + 1, closed_rows); if !mask.present { return mask; } result |= mask.value; } let start = count; if !corePattern(module, statement.a, 0, nested, count, start, remaining, depth + 1) { return blot_support::none<u16>(); }
                }
                else { let mask = coreCaptures(module, child, parameters, nested[..count], ignored, remaining, depth + 1, closed_rows); if !mask.present { return mask; } result |= mask.value; }
            } return blot_support::some(result);
        },
        match_ => { return coreCaseCaptures(module, value, parameters, aliases, ignored, remaining, depth, closed_rows); },
        if_value => { let condition = coreCaptures(module, value.a, parameters, aliases, ignored, remaining, depth + 1, closed_rows); if !condition.present { return condition; } let left = coreCaptures(module, value.b, parameters, aliases, ignored, remaining, depth + 1, closed_rows); if !left.present { return left; } let right = coreCaptures(module, value.c, parameters, aliases, ignored, remaining, depth + 1, closed_rows); if !right.present { return right; } return blot_support::some(condition.value | left.value | right.value); },
        product, record, array, array_op => { if value.a > module.extra.len || value.b > module.extra.len - value.a { return blot_support::none<u16>(); } var result: u16 = 0; for child in module.extra[value.a..value.a + value.b] { let mask = coreCaptures(module, child, parameters, aliases, ignored, remaining, depth + 1, closed_rows); if !mask.present { return mask; } result |= mask.value; } return blot_support::some(result); },
        _ => { return blot_support::none<u16>(); },
    }
}
fn coreCaseCaptures<P>(module: const Module&, value: blot_check_core::Node, parameters: const P[:], aliases: const CoreAlias[:], ignored: const u32[:], remaining: i64&, depth: i64, closed_rows: blot_check_types::List) -> Mask {
    if value.a >= module.matches.len || aliases.len > 128 { return blot_support::none<u16>(); } let info = module.matches[value.a];
    if info.inputs.len > 16 || info.inputs.start > module.extra.len || info.inputs.len > module.extra.len - info.inputs.start || info.arms.start > module.match_arms.len || info.arms.len > module.match_arms.len - info.arms.start { return blot_support::none<u16>(); } var result: u16 = 0;
    for input in module.extra[info.inputs.start..info.inputs.start + info.inputs.len] { let mask = coreCaptures(module, input, parameters, aliases, ignored, remaining, depth + 1, closed_rows); if !mask.present { return mask; } result |= mask.value; }
    for arm in module.match_arms[info.arms.start..info.arms.start + info.arms.len] { if arm.rows.start > module.pattern_rows.len || arm.rows.len > module.pattern_rows.len - arm.rows.start { return blot_support::none<u16>(); } var nested: CoreAlias[128] = [default<CoreAlias>();128]; for alias, index in aliases { nested[index] = alias; } var count = aliases.len;
        for row in module.pattern_rows[arm.rows.start..arm.rows.start + arm.rows.len] { if row.patterns.len != info.inputs.len || row.patterns.start > module.extra.len || row.patterns.len > module.extra.len - row.patterns.start { return blot_support::none<u16>(); }
            for pattern in module.extra[row.patterns.start..row.patterns.start + row.patterns.len] { if !corePattern(module, pattern, 0, nested, count, aliases.len, remaining, depth + 1) { return blot_support::none<u16>(); } }
        }
        if arm.guard_ != 0 { let mask = coreCaptures(module, arm.guard_, parameters, nested[..count], ignored, remaining, depth + 1, closed_rows); if !mask.present { return mask; } result |= mask.value; }
        let mask = coreCaptures(module, arm.body, parameters, nested[..count], ignored, remaining, depth + 1, closed_rows); if !mask.present { return mask; } result |= mask.value;
    } return blot_support::some(result);
}

fn contractCode(value: Contract) -> u32 {
    match value {
        unknown => { return 0; },
        identity => { return 1; },
        invoke_unit => { return 2; },
        member_unit => { return 3; },
        invoke_with_capability => { return 4; },
        member_first_unit => { return 5; },
        member_second_unit => { return 6; },
        input_shape => { return 7; },
        consume_task => { return 8; },
        scope_task => { return 9; },
        spawn_task => { return 10; },
    }
}
fn contractFromCode(code: u32) -> Contract, blot_error::Error {
    match code {
        0 => { return Contract.unknown, blot_error::Error.none; },
        1 => { return Contract.identity, blot_error::Error.none; },
        2 => { return Contract.invoke_unit, blot_error::Error.none; },
        3 => { return Contract.member_unit, blot_error::Error.none; },
        4 => { return Contract.invoke_with_capability, blot_error::Error.none; },
        5 => { return Contract.member_first_unit, blot_error::Error.none; },
        6 => { return Contract.member_second_unit, blot_error::Error.none; },
        7 => { return Contract.input_shape, blot_error::Error.none; },
        8 => { return Contract.consume_task, blot_error::Error.none; },
        9 => { return Contract.scope_task, blot_error::Error.none; },
        10 => { return Contract.spawn_task, blot_error::Error.none; },
        _ => { return Contract.unknown, blot_error::Error.invalid_artifact; },
    }
}
fn blot_structural::equal(left: blot_check_capability_flow::Contract, right: blot_check_capability_flow::Contract) -> bool { return left == right; }
fn blot_check_capability_flow::blotStructuralHash<S>(value: blot_check_capability_flow::Contract,sink: S&) { blot_structural::hash(sink, blot_check_capability_flow::contractCode(value) as! u8); }
fn parameterResultCode(value: ParameterResult) -> u32 {
    match value {
        product => { return 0; },
        invoke_unit => { return 1; },
        invalid => { return 2; },
        member_closure_unit => { return 3; },
        captured_unit => { return 4; },
        invoke_input => { return 5; },
        invoke_inputs => { return 6; },
    }
}
fn parameterResultFromCode(code: u32) -> ParameterResult, blot_error::Error {
    match code {
        0 => { return ParameterResult.product, blot_error::Error.none; },
        1 => { return ParameterResult.invoke_unit, blot_error::Error.none; },
        2 => { return ParameterResult.invalid, blot_error::Error.none; },
        3 => { return ParameterResult.member_closure_unit, blot_error::Error.none; },
        4 => { return ParameterResult.captured_unit, blot_error::Error.none; },
        5 => { return ParameterResult.invoke_input, blot_error::Error.none; },
        6 => { return ParameterResult.invoke_inputs, blot_error::Error.none; },
        _ => { return ParameterResult.product, blot_error::Error.invalid_artifact; },
    }
}
fn blot_structural::equal(left: blot_check_capability_flow::ParameterResult, right: blot_check_capability_flow::ParameterResult) -> bool { return left == right; }
fn blot_check_capability_flow::blotStructuralHash<S>(value: blot_check_capability_flow::ParameterResult,sink: S&) { blot_structural::hash(sink, blot_check_capability_flow::parameterResultCode(value) as! u8); }
fn constructionKindCode(value: ConstructionKind) -> u32 {
    match value {
        computation => { return 0; },
        provider => { return 1; },
        state => { return 2; },
    }
}
fn constructionKindFromCode(code: u32) -> ConstructionKind, blot_error::Error {
    match code {
        0 => { return ConstructionKind.computation, blot_error::Error.none; },
        1 => { return ConstructionKind.provider, blot_error::Error.none; },
        2 => { return ConstructionKind.state, blot_error::Error.none; },
        _ => { return ConstructionKind.computation, blot_error::Error.invalid_artifact; },
    }
}
fn blot_structural::equal(left: blot_check_capability_flow::ConstructionKind, right: blot_check_capability_flow::ConstructionKind) -> bool { return left == right; }
fn blot_check_capability_flow::blotStructuralHash<S>(value: blot_check_capability_flow::ConstructionKind,sink: S&) { blot_structural::hash(sink, blot_check_capability_flow::constructionKindCode(value) as! u8); }
