// Positional source shapes retain owned slots, fields and exact no-store facts.
namespace blot_check_capability_contract_source;
import check.capability_contracts;
import check.capability_flow;
import check.check_packet_owner;
import check.types;
import parse.ast;
import parse.lexer;
import parse.symbols;
import support.error;
import support.option;

import std;
type Error = blot_error::Error;
type Id = blot_check_capability_contracts::Id;
type Store = blot_check_capability_contracts::Store;
type Tag = blot_check_capability_contracts::Tag;
type AstId = blot_parse_ast::Id;
struct Functions { engine: const blot_check_check::Engine& }
fn lookup(self_: const Functions&, source: AstId) -> blot_support::Option<blot_check_capability_contracts::Recipe> { return self_.engine.callbackFunction(source); }
struct Entry { name: u32, value: Id }
struct Environment { entries: Entry[128], len: i64 = 0 }
fn bind(self_: Environment&, name: u32, value: Id) -> Error { if self_.len == self_.entries.len { return blot_error::Error.capability_analysis_limit; } self_.entries[self_.len] = Entry { name, value , ..}; self_.len += 1; return blot_error::Error.none; }
fn get(self_: const Environment&, name: u32) -> blot_support::Option<Id> { var index = self_.len; while index != 0 { index -= 1; if self_.entries[index].name == name { return blot_support::some(self_.entries[index].value); } } return blot_support::none<Id>(); }
struct Builder {
    store: Store&, tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, remaining: i64 = 65536, operations: const u32[:] = default<const u32[:]>(), lexical_captures: bool = false,
    input_types: const blot_check_types::Store? = null, input_expr_types: const u32[:] = default<const u32[:]>(), functions: const Functions? = null,
}
fn node(self_: Builder&, initial: AstId, depth: i64) -> blot_parse_ast::Node, Error {
    if depth >= 128 || self_.remaining == 0 { return default<blot_parse_ast::Node>(), blot_error::Error.capability_analysis_limit; } self_.remaining -= 1; var current = initial;
    for attempt in 0..128 { if current == 0 || current >= self_.tree.nodes.len { return default<blot_parse_ast::Node>(), blot_error::Error.unavailable; } let value = self_.tree.node(current); if value.tag != blot_parse_ast::tag_group { return value, blot_error::Error.none; } current = value.a; } return default<blot_parse_ast::Node>(), blot_error::Error.capability_analysis_limit;
}
fn name(self_: Builder&, symbol: u32, environment: const Environment&, capturing: bool) -> Id, Error { return namePath(self_, symbol, environment, capturing, false); }
fn find(text: const u8[:], wanted: u8) -> i64 { for byte, index in text { if byte == wanted { return index; } } return -1; }
fn findLast(text: const u8[:], wanted: u8) -> i64 { var index = text.len; while index != 0 { index -= 1; if text[index] == wanted { return index; } } return -1; }
fn namePath(self_: Builder&, symbol: u32, environment: const Environment&, capturing: bool, operation: bool) -> Id, Error {
    let known = environment.get(symbol); if known.present { return known.value, blot_error::Error.none; } let text = self_.pool.get(symbol); let separator = find(text, '.');
    if separator < 0 { if self_.lexical_captures { return 0, blot_error::Error.none; } return 0, blot_error::Error.unavailable; } let root,present = self_.pool.lookup(text[..separator]); if !present { return 0, blot_error::Error.unavailable; } let initial = environment.get(root);
    if !initial.present { if self_.lexical_captures { return 0, blot_error::Error.none; } return 0, blot_error::Error.unavailable; } var value = initial.value; if capturing { return value, blot_error::Error.none; } var limit = text.len;
    if operation { limit = findLast(text, '.'); if limit < 0 { return 0, blot_error::Error.unavailable; } } var start = separator + 1;
    while start < limit { var end = limit; let next = find(text[start..limit], '.'); if next >= 0 { end = start + next; } let field,present = self_.pool.lookup(text[start..end]); if !present { return 0, blot_error::Error.unavailable; }
        let result, error = self_.store.project(value, field, blot_check_capability_contracts::Projection.field); if error != blot_error::Error.none { return 0, error; } value = result; start = end + 1;
    } return value, blot_error::Error.none;
}
fn inputStore(self_: Builder&, root: Id) -> Error { if self_.lexical_captures { let found, error = self_.store.view().containsParameter(root, self_.remaining); if error != blot_error::Error.none { return error; } if found { return blot_error::Error.unavailable; } } return blot_error::Error.none; }
recursive fn selectIndex(self_: Builder&, receiver: AstId, index: AstId, environment: const Environment&, depth: i64) -> Id, Error {
    let base, error = expression(self_, receiver, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let selector, error = self_.node(index, depth + 1); if error != blot_error::Error.none { return 0, error; }
    if selector.tag != blot_parse_ast::tag_integer { return self_.store.elements(base); } return self_.store.project(base, selector.a, blot_check_capability_contracts::Projection.index);
}
fn textLength(text: const u8[:]) -> i64, Error { var at: i64 = 0; var count: i64 = 0;
    while at < text.len { let width = blot_parse_lexer::utf8_width(text[at]); if width == 0 || width > text.len - at { return 0, blot_error::Error.unavailable; } let point, error = blot_parse_lexer::decode_point(text[at..at + width]); if error != blot_error::Error.none { return 0, blot_error::Error.unavailable; } at += width; count += 1; } return count, blot_error::Error.none;
}
recursive fn expression(self_: Builder&, source: AstId, environment: const Environment&, depth: i64) -> Id, Error {
    let value, error = self_.node(source, depth); if error != blot_error::Error.none { return 0, error; } var ungrouped = source; while self_.tree.node(ungrouped).tag == blot_parse_ast::tag_group { ungrouped = self_.tree.node(ungrouped).a; }
    match value.tag {
        blot_parse_ast::tag_name => {
            if ungrouped < self_.operations.len && self_.operations[ungrouped] != 0 { let path, error = namePath(self_, value.a, environment, false, true); if error != blot_error::Error.none { return 0, error; } let children: Id[1] = [path]; return self_.store.aggregate(blot_check_capability_contracts::Tag.captures, children); }
            if !environment.get(value.a).present { let functions .= self_.functions; if functions { let header = functions.lookup(ungrouped); if header.present { return self_.store.callable(header.value, 0); } } } return name(self_, value.a, environment, false);
        },
        blot_parse_ast::tag_integer, blot_parse_ast::tag_float, blot_parse_ast::tag_boolean, blot_parse_ast::tag_unit => { return 0, blot_error::Error.none; },
        blot_parse_ast::tag_string => { let count, error = textLength(self_.pool.get(value.a)); if error != blot_error::Error.none { return 0, error; } var children: u32[2048] = [0; 2048]; if count > children.len { return 0, blot_error::Error.capability_analysis_limit; } return self_.store.aggregate(blot_check_capability_contracts::Tag.product, children[..count]); },
        blot_parse_ast::tag_constructor_ref => { return self_.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.wrapped , ..}); },
        blot_parse_ast::tag_type_witness => { let id, error = expression(self_, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } return self_.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.wrapped, id , ..}); },
        blot_parse_ast::tag_field => { if value.b == 0 { let found = environment.get(value.a); if !found.present { return 0, blot_error::Error.unavailable; } return found.value, blot_error::Error.none; } return expression(self_, value.b, environment, depth + 1); },
        blot_parse_ast::tag_field_access => { let receiver, error = expression(self_, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } if ungrouped < self_.operations.len && self_.operations[ungrouped] != 0 { let children: Id[1] = [receiver]; return self_.store.aggregate(blot_check_capability_contracts::Tag.captures, children); } return self_.store.project(receiver, value.b, blot_check_capability_contracts::Projection.field); },
        blot_parse_ast::tag_index_access => { return selectIndex(self_, value.a, value.b, environment, depth + 1); },
        blot_parse_ast::tag_apply => { return application(self_, ungrouped, value, environment, depth); },
        blot_parse_ast::tag_product, blot_parse_ast::tag_array => { var children: u32[4096] = [0;4096]; let ast_sources_source=ungrouped;let ast_sources_count=self_.tree.children(ast_sources_source).len; if ast_sources_count > children.len { return 0, blot_error::Error.capability_analysis_limit; }
            let ast_walk_1_source=ast_sources_source;let ast_walk_1_count=self_.tree.children(ast_walk_1_source).len;for index in 0..ast_walk_1_count {let child=self_.tree.children(ast_walk_1_source)[index]; let id, error = expression(self_, child, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } children[index] = id; if value.tag == blot_parse_ast::tag_array { let error = inputStore(self_, id); if error != blot_error::Error.none { return 0, error; } } } return self_.store.aggregate(blot_check_capability_contracts::Tag.product, children[..ast_sources_count]);
        },
        blot_parse_ast::tag_record => { var fields: u32[4096] = [0;4096]; let ast_sources_source=ungrouped;let ast_sources_count=self_.tree.children(ast_sources_source).len; if ast_sources_count > fields.len / 2 { return 0, blot_error::Error.capability_analysis_limit; }
            let ast_walk_2_source=ast_sources_source;let ast_walk_2_count=self_.tree.children(ast_walk_2_source).len;for index in 0..ast_walk_2_count {let child=self_.tree.children(ast_walk_2_source)[index]; let field = self_.tree.node(child); fields[index * 2] = field.a; let id, error = expression(self_, child, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } fields[index * 2 + 1] = id; }
            let record, error = self_.store.aggregate(blot_check_capability_contracts::Tag.record, fields[..ast_sources_count * 2]); if error != blot_error::Error.none { return 0, error; } if value.a != 0 { return self_.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.wrapped, record , ..}); } return record, blot_error::Error.none;
        },
        blot_parse_ast::tag_if_expr => { if self_.lexical_captures { let ignored, error = expression(self_, value.a, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } } let left, error = expression(self_, value.b, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let right, error = expression(self_, value.c, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let children: Id[2] = [left, right]; return self_.store.aggregate(blot_check_capability_contracts::Tag.join, children); },
        blot_parse_ast::tag_block => { return blockValue(self_, ungrouped, value, environment, depth); },
        blot_parse_ast::tag_case_expr => { return caseValue(self_, value, environment, depth); },
        blot_parse_ast::tag_lambda => { var captures: Id[4096] = [0;4096]; var count: i64 = 0; let error = capture(self_, source, environment, captures, count, depth + 1); if error != blot_error::Error.none { return 0, error; } for value in captures[..count] { let error = inputStore(self_, value); if error != blot_error::Error.none { return 0, error; } } return self_.store.aggregate(blot_check_capability_contracts::Tag.captures, captures[..count]); },
        _ => { return 0, blot_error::Error.unavailable; },
    }
}
recursive fn application(self_: Builder&, ungrouped: AstId, value: blot_parse_ast::Node, environment: const Environment&, depth: i64) -> Id, Error {
    if self_.lexical_captures {
        let argument, error = self_.node(value.b, depth + 1); if error != blot_error::Error.none { return 0, error; } var callee_source = value.a; while self_.tree.node(callee_source).tag == blot_parse_ast::tag_group { callee_source = self_.tree.node(callee_source).a; }
        var head = ungrouped; var operands: AstId[16] = [0;16]; var count: i64 = 0;
        while true { let applied, error = self_.node(head, depth + 1); if error != blot_error::Error.none { return 0, error; } if applied.tag != blot_parse_ast::tag_apply { break; } if count == operands.len { return 0, blot_error::Error.unavailable; } operands[count] = applied.b; count += 1; head = applied.a; }
        let primitive, error = self_.node(head, depth + 1); if error != blot_error::Error.none { return 0, error; }
        if primitive.tag == blot_parse_ast::tag_intrinsic { let text = self_.pool.get(primitive.a); if text.starts_with("@u32.") || text.starts_with("@f32.") { for operand in operands[..count] { let ignored, error = expression(self_, operand, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } } return 0, blot_error::Error.none; } }
        if argument.tag == blot_parse_ast::tag_unit && callee_source < self_.operations.len && self_.operations[callee_source] != 0 {
            let ignored, error = expression(self_, callee_source, environment, depth + 1); if error != blot_error::Error.none { return 0, error; }
            let types .= self_.input_types; if types { if ungrouped >= self_.input_expr_types.len { return 0, blot_error::Error.unavailable; }
                match types.node(types.head(self_.input_expr_types[ungrouped], 0)).tag { unit, boolean, unsigned32, floating32, never => { return 0, blot_error::Error.none; }, _ => {}, }
            } return self_.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.unknown , ..});
        }
    }
    let call = blot_check_capability_flow::localSourceCall(self_.tree, ungrouped);
    if call.present { if environment.get(call.value.name).present { return 0, blot_error::Error.unavailable; } var nested = Environment {..};
        for index in 0..call.value.len { let argument, error = expression(self_, call.value.arguments[index], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } let error = nested.bind(call.value.parameters[index], argument); if error != blot_error::Error.none { return 0, error; } } return expression(self_, call.value.body, nested, depth + 1);
    }
    if self_.lexical_captures { let functions .= self_.functions; if functions { var callee = ungrouped; var reverse: AstId[16] = [0;16]; var count: i64 = 0;
            while true { let node, error = self_.node(callee, depth + 1); if error != blot_error::Error.none { return 0, error; } if node.tag != blot_parse_ast::tag_apply { break; } if count == reverse.len { return 0, blot_error::Error.unavailable; } reverse[count] = node.b; count += 1; callee = node.a; }
            let header = functions.lookup(callee); if header.present { if header.value.arity != count { return 0, blot_error::Error.unavailable; } var arguments: Id[16] = [0;16];
                for index in 0..count { let id, error = expression(self_, reverse[count - index - 1], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } arguments[index] = id; } return self_.store.instantiate(header.value, arguments[..count]);
            }
    } }
    let construction = blot_check_capability_flow::constructionSource(self_.tree, self_.pool, ungrouped);
    if construction.present { var children: Id[3] = [0;3]; for index in 0..construction.value.len { let id, error = expression(self_, construction.value.inputs[index], environment, depth + 1); if error != blot_error::Error.none { return 0, error; } children[index] = id; }
        for child in children[..construction.value.len] { let error = inputStore(self_, child); if error != blot_error::Error.none { return 0, error; } }
        if construction.value.kind == blot_check_capability_flow::ConstructionKind.computation { return self_.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.wrapped, children[0] , ..}); } return self_.store.aggregate(blot_check_capability_contracts::Tag.captures, children[..construction.value.len]);
    }
    let projection = blot_check_capability_flow::projectionSource(self_.tree, self_.pool, ungrouped); if projection.present { return selectIndex(self_, projection.value.receiver, projection.value.index, environment, depth + 1); }
    let callee, error = self_.node(value.a, depth + 1); if error != blot_error::Error.none { return 0, error; }
    if callee.tag == blot_parse_ast::tag_intrinsic { let name = self_.pool.get(callee.a); if name == "@usage.read" || name == "@usage.length" { if self_.lexical_captures { let ignored, error = expression(self_, value.b, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } } return 0, blot_error::Error.none; } }
    if callee.tag != blot_parse_ast::tag_constructor_ref { return 0, blot_error::Error.unavailable; } let id, error = expression(self_, value.b, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } return self_.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.wrapped, id , ..});
}
recursive fn blockValue(self_: Builder&, source: AstId, value: blot_parse_ast::Node, environment: const Environment&, depth: i64) -> Id, Error {
    if value.c != 0 { return 0, blot_error::Error.unavailable; } var nested = environment; let ast_children_source=source;let ast_children_count=self_.tree.children(ast_children_source).len;
    let ast_walk_3_source=ast_children_source;let ast_walk_3_count=self_.tree.children(ast_walk_3_source).len;for index in 0..ast_walk_3_count {let child=self_.tree.children(ast_walk_3_source)[index]; let statement = self_.tree.node(child); if statement.tag == blot_parse_ast::tag_return_stmt && index + 1 == ast_children_count { return expression(self_, statement.a, nested, depth + 1); }
        if self_.lexical_captures && statement.tag == blot_parse_ast::tag_use_stmt { let retained, error = expression(self_, statement.b, nested, depth + 1); if error != blot_error::Error.none { return 0, error; } if statement.a != 0 { let error = nested.bind(statement.a, retained); if error != blot_error::Error.none { return 0, error; } } continue; }
        if statement.tag != blot_parse_ast::tag_let_stmt { return 0, blot_error::Error.unavailable; } let binding = self_.tree.binding(child); let alias = self_.tree.node(binding.pattern); if alias.tag != blot_parse_ast::tag_pattern_name || binding.fallback != 0 { return 0, blot_error::Error.unavailable; }
        let id, error = expression(self_, binding.value, nested, depth + 1); if error != blot_error::Error.none { return 0, error; } let error = nested.bind(alias.a, id); if error != blot_error::Error.none { return 0, error; }
    } return 0, blot_error::Error.unavailable;
}
recursive fn caseValue(self_: Builder&, value: blot_parse_ast::Node, environment: const Environment&, depth: i64) -> Id, Error {
    let ast_inputs_start=(value.a) as i64;let ast_inputs_count=self_.tree.extra.items[ast_inputs_start..value.a + 2].len;let inputs=blot_parse_ast::List{start:ast_inputs_start as u32,len:ast_inputs_count as u32,..}; if self_.tree.list(inputs)[1] > 16 || value.c > 4096 { return 0, blot_error::Error.capability_analysis_limit; } var retained: Id[16] = [0;16];
    let ast_walk_4_source=blot_parse_ast::List { self_.tree.list(inputs)[0], self_.tree.list(inputs)[1] , ..};let ast_walk_4_count=self_.tree.list(ast_walk_4_source).len;for index in 0..ast_walk_4_count {let input=self_.tree.list(ast_walk_4_source)[index]; let id, error = expression(self_, input, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } retained[index] = id; }
    var arms: Id[4096] = [0;4096]; let ast_walk_5_source=blot_parse_ast::List { value.b, value.c , ..};let ast_walk_5_count=self_.tree.list(ast_walk_5_source).len;for index in 0..ast_walk_5_count {let arm_id=self_.tree.list(ast_walk_5_source)[index]; let arm = self_.tree.node(arm_id); var nested = environment; let start = nested.len;
        let ast_walk_6_source=blot_parse_ast::List { arm.a, arm.b , ..};let ast_walk_6_count=self_.tree.list(ast_walk_6_source).len;for ast_walk_6_index in 0..ast_walk_6_count {let row=self_.tree.list(ast_walk_6_source)[ast_walk_6_index]; let ast_patterns_source=row;let ast_patterns_count=self_.tree.children(ast_patterns_source).len; if ast_patterns_count != self_.tree.list(inputs)[1] { return 0, blot_error::Error.unavailable; }
            let ast_walk_7_source=ast_patterns_source;let ast_walk_7_count=self_.tree.children(ast_walk_7_source).len;for ordinal in 0..ast_walk_7_count {let pattern=self_.tree.children(ast_walk_7_source)[ordinal]; let error = bindShapePattern(self_, pattern, retained[ordinal], nested, start, depth + 1); if error != blot_error::Error.none { return 0, error; } }
        }
        let ast_details_start=(arm.c) as i64;let ast_details_count=self_.tree.extra.items[ast_details_start..arm.c + 2].len;let details=blot_parse_ast::List{start:ast_details_start as u32,len:ast_details_count as u32,..}; if self_.lexical_captures && self_.tree.list(details)[0] != 0 { let ignored, error = expression(self_, self_.tree.list(details)[0], nested, depth + 1); if error != blot_error::Error.none { return 0, error; } }
        let id, error = expression(self_, self_.tree.list(details)[1], nested, depth + 1); if error != blot_error::Error.none { return 0, error; } arms[index] = id;
    } return self_.store.aggregate(blot_check_capability_contracts::Tag.join, arms[..value.c]);
}
fn bindPattern(self_: Builder&, environment: Environment&, start: i64, name: u32, value: Id) -> Error {
    for index in start..environment.len { let entry .= environment.entries[index]; if entry.name == name { if entry.value != value { let children: Id[2] = [entry.value, value]; let id, error = self_.store.aggregate(blot_check_capability_contracts::Tag.join, children); if error != blot_error::Error.none { return error; } entry.value = id; } return blot_error::Error.none; } } return environment.bind(name, value);
}
fn directPayload(self_: Builder&, name: u32) -> bool {
    let ast_walk_8_count=self_.tree.roots.items.len;for ast_walk_8_index in 0..ast_walk_8_count {let root=self_.tree.roots.items[ast_walk_8_index]; let declaration = self_.tree.node(root); if declaration.tag != blot_parse_ast::tag_data_decl { continue; }
        let ast_walk_9_source=declaration.b;let ast_walk_9_count=self_.tree.children(ast_walk_9_source).len;for ast_walk_9_index in 0..ast_walk_9_count {let constructor=self_.tree.children(ast_walk_9_source)[ast_walk_9_index]; let node = self_.tree.node(constructor); if node.a != name { continue; }
            let ast_walk_10_count=self_.tree.declaration_traits.items.len;for ast_walk_10_index in 0..ast_walk_10_count {let traits=self_.tree.declaration_traits.items[ast_walk_10_index]; if traits.declaration == root && traits.is_opaque { return true; } } return node.b == 0 || self_.tree.node(node.b).tag != blot_parse_ast::tag_type_record;
        }
    } return false;
}
recursive fn bindShapePattern(self_: Builder&, source: AstId, origin: Id, environment: Environment&, start: i64, depth: i64) -> Error {
    let value, error = self_.node(source, depth); if error != blot_error::Error.none { return error; }
    match value.tag {
        blot_parse_ast::tag_pattern_name => { return bindPattern(self_, environment, start, value.a, origin); },
        blot_parse_ast::tag_pattern_integer, blot_parse_ast::tag_pattern_boolean => {},
        blot_parse_ast::tag_pattern_field => { let field, error = self_.store.project(origin, value.a, blot_check_capability_contracts::Projection.field); if error != blot_error::Error.none { return error; } if value.b != 0 { return bindShapePattern(self_, value.b, field, environment, start, depth + 1); } return bindPattern(self_, environment, start, value.a, field); },
        blot_parse_ast::tag_pattern_constructor => { if value.b != 0 { if !directPayload(self_, value.a) { return blot_error::Error.unavailable; } let payload, error = self_.store.project(origin, 0, blot_check_capability_contracts::Projection.payload); if error != blot_error::Error.none { return error; } return bindShapePattern(self_, value.b, payload, environment, start, depth + 1); } },
        blot_parse_ast::tag_pattern_product => { let ast_walk_11_source=source;let ast_walk_11_count=self_.tree.children(ast_walk_11_source).len;for index in 0..ast_walk_11_count {let child=self_.tree.children(ast_walk_11_source)[index]; let selected, error = self_.store.project(origin, index as u32, blot_check_capability_contracts::Projection.index); if error != blot_error::Error.none { return error; } let error = bindShapePattern(self_, child, selected, environment, start, depth + 1); if error != blot_error::Error.none { return error; } } },
        blot_parse_ast::tag_pattern_record => { let ast_walk_12_source=source;let ast_walk_12_count=self_.tree.children(ast_walk_12_source).len;for ast_walk_12_index in 0..ast_walk_12_count {let child=self_.tree.children(ast_walk_12_source)[ast_walk_12_index]; let error = bindShapePattern(self_, child, origin, environment, start, depth + 1); if error != blot_error::Error.none { return error; } } },
        _ => { return blot_error::Error.unavailable; },
    } return blot_error::Error.none;
}
recursive fn capture(self_: Builder&, source: AstId, environment: const Environment&, captures: Id[4096]&, count: i64&, depth: i64) -> Error {
    let value, error = self_.node(source, depth); if error != blot_error::Error.none { return error; } var ungrouped = source; while self_.tree.node(ungrouped).tag == blot_parse_ast::tag_group { ungrouped = self_.tree.node(ungrouped).a; }
    match value.tag {
        blot_parse_ast::tag_name => { let captured, error = name(self_, value.a, environment, true); if error != blot_error::Error.none { return error; } if captured == 0 { return blot_error::Error.none; } for known in captures[..count] { if known == captured { return blot_error::Error.none; } }
            if count == captures.len { return blot_error::Error.capability_analysis_limit; } captures[count] = captured; count += 1;
        },
        blot_parse_ast::tag_intrinsic, blot_parse_ast::tag_integer, blot_parse_ast::tag_float, blot_parse_ast::tag_string, blot_parse_ast::tag_boolean, blot_parse_ast::tag_unit => {},
        blot_parse_ast::tag_lambda => { var nested = environment; let error = nested.bind(self_.tree.parameter(value.a).name, 0); if error != blot_error::Error.none { return error; } return capture(self_, value.b, nested, captures, count, depth + 1); },
        blot_parse_ast::tag_apply, blot_parse_ast::tag_index_access => { let error = capture(self_, value.a, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } return capture(self_, value.b, environment, captures, count, depth + 1); },
        blot_parse_ast::tag_field_access, blot_parse_ast::tag_return_stmt, blot_parse_ast::tag_function_return_stmt, blot_parse_ast::tag_yield_stmt => { return capture(self_, value.a, environment, captures, count, depth + 1); },
        blot_parse_ast::tag_field => { if value.b != 0 { return capture(self_, value.b, environment, captures, count, depth + 1); } let known = environment.get(value.a); if !known.present { return blot_error::Error.unavailable; } if count == captures.len { return blot_error::Error.capability_analysis_limit; } captures[count] = known.value; count += 1; },
        blot_parse_ast::tag_unary, blot_parse_ast::tag_operator_tail => { return capture(self_, value.b, environment, captures, count, depth + 1); },
        blot_parse_ast::tag_binary => { let error = capture(self_, value.b, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } return capture(self_, value.c, environment, captures, count, depth + 1); },
        blot_parse_ast::tag_block => { if value.c != 0 { return blot_error::Error.unavailable; } var nested = environment;
            let ast_walk_13_source=ungrouped;let ast_walk_13_count=self_.tree.children(ast_walk_13_source).len;for ast_walk_13_index in 0..ast_walk_13_count {let child=self_.tree.children(ast_walk_13_source)[ast_walk_13_index]; let statement = self_.tree.node(child);
                if statement.tag == blot_parse_ast::tag_let_stmt { let binding = self_.tree.binding(child); if binding.fallback != 0 { return blot_error::Error.unavailable; } let error = capture(self_, binding.value, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; } let start = nested.len; let error = bindShapePattern(self_, binding.pattern, 0, nested, start, depth + 1); if error != blot_error::Error.none { return error; } }
                else { let error = capture(self_, child, nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; } }
            }
        },
        blot_parse_ast::tag_case_expr => { let ast_inputs_start=(value.a) as i64;let ast_inputs_count=self_.tree.extra.items[ast_inputs_start..value.a + 2].len;let inputs=blot_parse_ast::List{start:ast_inputs_start as u32,len:ast_inputs_count as u32,..}; if self_.tree.list(inputs)[1] > 16 { return blot_error::Error.unavailable; }
            let ast_walk_14_source=blot_parse_ast::List { self_.tree.list(inputs)[0], self_.tree.list(inputs)[1] , ..};let ast_walk_14_count=self_.tree.list(ast_walk_14_source).len;for ast_walk_14_index in 0..ast_walk_14_count {let input=self_.tree.list(ast_walk_14_source)[ast_walk_14_index]; let error = capture(self_, input, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } }
            let ast_walk_15_source=blot_parse_ast::List { value.b, value.c , ..};let ast_walk_15_count=self_.tree.list(ast_walk_15_source).len;for ast_walk_15_index in 0..ast_walk_15_count {let arm_id=self_.tree.list(ast_walk_15_source)[ast_walk_15_index]; let arm = self_.tree.node(arm_id); var nested = environment; let start = nested.len;
                let ast_walk_16_source=blot_parse_ast::List { arm.a, arm.b , ..};let ast_walk_16_count=self_.tree.list(ast_walk_16_source).len;for ast_walk_16_index in 0..ast_walk_16_count {let row=self_.tree.list(ast_walk_16_source)[ast_walk_16_index]; let ast_patterns_source=row;let ast_patterns_count=self_.tree.children(ast_patterns_source).len; if ast_patterns_count != self_.tree.list(inputs)[1] { return blot_error::Error.unavailable; } let ast_walk_17_source=ast_patterns_source;let ast_walk_17_count=self_.tree.children(ast_walk_17_source).len;for ast_walk_17_index in 0..ast_walk_17_count {let pattern=self_.tree.children(ast_walk_17_source)[ast_walk_17_index]; let error = bindShapePattern(self_, pattern, 0, nested, start, depth + 1); if error != blot_error::Error.none { return error; } } }
                let ast_details_start=(arm.c) as i64;let ast_details_count=self_.tree.extra.items[ast_details_start..arm.c + 2].len;let details=blot_parse_ast::List{start:ast_details_start as u32,len:ast_details_count as u32,..}; if self_.tree.list(details)[0] != 0 { let error = capture(self_, self_.tree.list(details)[0], nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; } } let error = capture(self_, self_.tree.list(details)[1], nested, captures, count, depth + 1); if error != blot_error::Error.none { return error; }
            }
        },
        blot_parse_ast::tag_if_expr => { let error = capture(self_, value.a, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } let error = capture(self_, value.b, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } return capture(self_, value.c, environment, captures, count, depth + 1); },
        blot_parse_ast::tag_product, blot_parse_ast::tag_record, blot_parse_ast::tag_array => { let ast_walk_18_source=ungrouped;let ast_walk_18_count=self_.tree.children(ast_walk_18_source).len;for ast_walk_18_index in 0..ast_walk_18_count {let child=self_.tree.children(ast_walk_18_source)[ast_walk_18_index]; let error = capture(self_, child, environment, captures, count, depth + 1); if error != blot_error::Error.none { return error; } } },
        _ => { return blot_error::Error.unavailable; },
    } return blot_error::Error.none;
}
fn derive(store: Store&, tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, summary: blot_check_capability_flow::Parameters) -> blot_support::Option<Id>, Error { return deriveChecked(store, tree, pool, source, summary, []); }
fn deriveChecked(store: Store&, tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, summary: blot_check_capability_flow::Parameters, operations: const u32[:]) -> blot_support::Option<Id>, Error {
    if !summary.valid() || !summary.present() || summary.invokes() { return blot_support::none<Id>(), blot_error::Error.none; }
    var builder = Builder { store: store, tree: tree, pool: pool, operations: operations , ..}; return deriveBody(builder, source, summary.arity(), false);
}
fn deriveBody(builder: Builder&, source: AstId, arity: u32, require_names: bool) -> blot_support::Option<Id>, Error {
    let checkpoint = builder.store.mark(); let result, error = deriveBodyInner(builder, source, arity, require_names);
    if error != blot_error::Error.none { builder.store.rollback(checkpoint); if error == blot_error::Error.unavailable { return blot_support::none<Id>(), blot_error::Error.none; } return blot_support::none<Id>(), error; }
    let validation = builder.store.view().validate(result, arity, true); if validation != blot_error::Error.none { builder.store.rollback(checkpoint); return blot_support::none<Id>(), blot_error::Error.none; } return blot_support::some(result), blot_error::Error.none;
}
fn deriveBodyInner(builder: Builder&, source: AstId, arity: u32, require_names: bool) -> Id, Error {
    let empty, error = builder.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.empty , ..}); if error != blot_error::Error.none { return 0, error; } var environment = Environment {..}; var body = source;
    for index in 0..arity { let lambda, error = builder.node(body, 0); if error != blot_error::Error.none { return 0, error; } if lambda.tag != blot_parse_ast::tag_lambda { return 0, blot_error::Error.unavailable; } let parameter = builder.tree.parameter(lambda.a);
        if require_names && parameter.name == 0 && !parameter.is_unit { return 0, blot_error::Error.unavailable; }
        if !require_names || parameter.name != 0 { let id, error = builder.store.append(blot_check_capability_contracts::Term { blot_check_capability_contracts::Tag.parameter, index as u32 , ..}); if error != blot_error::Error.none { return 0, error; } let error = environment.bind(parameter.name, id); if error != blot_error::Error.none { return 0, error; } } body = lambda.b;
    } return expression(builder, body, environment, 0);
}
fn deriveClosure(store: Store&, tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, operations: const u32[:], types: const blot_check_types::Store&, expr_types: const u32[:]) -> blot_support::Option<Id>, Error { return deriveInputFunction(store, tree, pool, source, operations, types, expr_types, 1); }
fn deriveInputFunction(store: Store&, tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, operations: const u32[:], types: const blot_check_types::Store&, expr_types: const u32[:], arity: u8) -> blot_support::Option<Id>, Error { return deriveInputFunctionWithFunctions(store, tree, pool, source, operations, types, expr_types, arity, null); }
fn deriveInputFunctionWithFunctions(store: Store&, tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, operations: const u32[:], types: const blot_check_types::Store&, expr_types: const u32[:], arity: u8, functions: const Functions?) -> blot_support::Option<Id>, Error {
    if arity == 0 || arity > 16 { return blot_support::none<Id>(), blot_error::Error.none; }
    var builder = Builder { store: store, tree: tree, pool: pool, operations: operations, lexical_captures: true, input_types: types, input_expr_types: expr_types, functions: functions , ..}; return deriveBody(builder, source, arity, true);
}
struct InputCheck { tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, operations: const u32[:], types: const blot_check_types::Store&, expr_types: const u32[:], arity: u8, result: bool = false }
fn inputCheck(context: InputCheck&, store: Store&) -> Error {
    let root, error = deriveInputFunction(store, context.tree, context.pool, context.source, context.operations, context.types, context.expr_types, context.arity); if error != blot_error::Error.none || !root.present { return blot_error::Error.none; }
    if store.view().validate(root.value, context.arity, true) != blot_error::Error.none { return blot_error::Error.none; } for node in store.nodes.items { if node.tag == blot_check_capability_contracts::Tag.unknown { return blot_error::Error.none; } } context.result = true; return blot_error::Error.none;
}
fn inputFunction(tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, operations: const u32[:], types: const blot_check_types::Store&, expr_types: const u32[:], arity: u8) -> bool {
    var context = InputCheck { tree, pool, source, operations, types, expr_types, arity , ..}; let error = blot_check_capability_contracts::withStore<InputCheck>(context,inputCheck); return error == blot_error::Error.none && context.result;
}
