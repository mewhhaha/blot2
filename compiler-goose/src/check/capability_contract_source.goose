// Positional source shapes retain owned slots, fields and exact no-store facts.
namespace blot_check_capability_contract_source;
import std;
import support.error;
import support.option;
import .capability_contracts;
type Error = blot_error::Error;
type Id = blot_check_capability_contracts::Id;
type Store = blot_check_capability_contracts::Store;
type Tag = blot_check_capability_contracts::Tag;
type AstId = blot_parse_ast::Id;
struct Functions { engine: const blot_check_check::Engine& }
fn lookup(self: const Functions&, source: AstId) -> blot_support::Option<blot_check_capability_contracts::Recipe> { return self.engine.callbackFunction(source); }
struct Entry { name: u32, value: Id }
struct Environment { entries: Entry[128], len: i64 = 0 }
fn bind(self: Environment&, name: u32, value: Id) -> Error { if self.len == self.entries.len { return Error.capability_analysis_limit; } self.entries[self.len] = Entry { name, value }; self.len += 1; return Error.none; }
fn get(self: const Environment&, name: u32) -> blot_support::Option<Id> { var index = self.len; while index != 0 { index -= 1; if self.entries[index].name == name { return blot_support::some(self.entries[index].value); } } return blot_support::none<Id>(); }
struct Builder {
    store: Store&, tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, remaining: i64 = 65536, operations: const u32[:] = [], lexical_captures: bool = false,
    input_types: const blot_check_types::Store? = null, input_expr_types: const u32[:] = [], functions: const Functions? = null,
}
fn node(self: Builder&, initial: AstId, depth: i64) -> blot_parse_ast::Node, Error {
    if depth >= 128 || self.remaining == 0 { return default<blot_parse_ast::Node>(), Error.capability_analysis_limit; } self.remaining -= 1; var current = initial;
    for attempt in 0..128 { if current == 0 || current >= self.tree.nodes.len { return default<blot_parse_ast::Node>(), Error.unavailable; } let value = self.tree.node(current); if value.tag != blot_parse_ast::tag_group { return value, Error.none; } current = value.a; } return default<blot_parse_ast::Node>(), Error.capability_analysis_limit;
}
fn name(self: Builder&, symbol: u32, environment: const Environment&, capturing: bool) -> Id, Error { return namePath(self, symbol, environment, capturing, false); }
fn find(text: const u8[:], wanted: u8) -> i64 { for byte, index in text { if byte == wanted { return index; } } return -1; }
fn findLast(text: const u8[:], wanted: u8) -> i64 { var index = text.len; while index != 0 { index -= 1; if text[index] == wanted { return index; } } return -1; }
fn namePath(self: Builder&, symbol: u32, environment: const Environment&, capturing: bool, operation: bool) -> Id, Error {
    let known = environment.get(symbol); if known.present { return known.value, Error.none; } let text = self.pool.get(symbol); let separator = find(text, '.');
    if separator < 0 { if self.lexical_captures { return 0, Error.none; } return 0, Error.unavailable; } let root = self.pool.lookup(text[..separator]); if !root.present { return 0, Error.unavailable; } let initial = environment.get(root.value);
    if !initial.present { if self.lexical_captures { return 0, Error.none; } return 0, Error.unavailable; } var value = initial.value; if capturing { return value, Error.none; } var limit = text.len;
    if operation { limit = findLast(text, '.'); if limit < 0 { return 0, Error.unavailable; } } var start = separator + 1;
    while start < limit { var end = limit; let next = find(text[start..limit], '.'); if next >= 0 { end = start + next; } let field = self.pool.lookup(text[start..end]); if !field.present { return 0, Error.unavailable; }
        let result, error = self.store.project(value, field.value, blot_check_capability_contracts::Projection.field); if error != Error.none { return 0, error; } value = result; start = end + 1;
    } return value, Error.none;
}
fn inputStore(self: Builder&, root: Id) -> Error { if self.lexical_captures { let found, error = self.store.view().containsParameter(root, self.remaining); if error != Error.none { return error; } if found { return Error.unavailable; } } return Error.none; }
fn selectIndex(self: Builder&, receiver: AstId, index: AstId, environment: const Environment&, depth: i64) -> Id, Error {
    let base, error = expression(self, receiver, environment, depth + 1); if error != Error.none { return 0, error; } let selector, error = self.node(index, depth + 1); if error != Error.none { return 0, error; }
    if selector.tag != blot_parse_ast::tag_integer { return self.store.elements(base); } return self.store.project(base, selector.a, blot_check_capability_contracts::Projection.index);
}
fn textLength(text: const u8[:]) -> i64, Error { var at: i64 = 0; var count: i64 = 0;
    while at < text.len { let width = blot_parse_lexer::utf8_width(text[at]); if width == 0 || width > text.len - at { return 0, Error.unavailable; } let point, error = blot_parse_lexer::decode_point(text[at..at + width]); if error != Error.none { return 0, Error.unavailable; } at += width; count += 1; } return count, Error.none;
}
recursive fn expression(self: Builder&, source: AstId, environment: const Environment&, depth: i64) -> Id, Error {
    let value, error = self.node(source, depth); if error != Error.none { return 0, error; } var ungrouped = source; while self.tree.node(ungrouped).tag == blot_parse_ast::tag_group { ungrouped = self.tree.node(ungrouped).a; }
    match value.tag {
        blot_parse_ast::tag_name => {
            if ungrouped < self.operations.len && self.operations[ungrouped] != 0 { let path, error = namePath(self, value.a, environment, false, true); if error != Error.none { return 0, error; } let children: Id[1] = [path]; return self.store.aggregate(Tag.captures, children); }
            if !environment.get(value.a).present { let functions .= self.functions; if functions { let header = functions.lookup(ungrouped); if header.present { return self.store.callable(header.value, 0); } } } return name(self, value.a, environment, false);
        },
        blot_parse_ast::tag_integer, blot_parse_ast::tag_float, blot_parse_ast::tag_boolean, blot_parse_ast::tag_unit => { return 0, Error.none; },
        blot_parse_ast::tag_string => { let count, error = textLength(self.pool.get(value.a)); if error != Error.none { return 0, error; } var children: u32[2048] = [0; 2048]; if count > children.len { return 0, Error.capability_analysis_limit; } return self.store.aggregate(Tag.product, children[..count]); },
        blot_parse_ast::tag_constructor_ref => { return self.store.append(blot_check_capability_contracts::Term { Tag.wrapped }); },
        blot_parse_ast::tag_type_witness => { let id, error = expression(self, value.a, environment, depth + 1); if error != Error.none { return 0, error; } return self.store.append(blot_check_capability_contracts::Term { Tag.wrapped, id }); },
        blot_parse_ast::tag_field => { if value.b == 0 { let found = environment.get(value.a); if !found.present { return 0, Error.unavailable; } return found.value, Error.none; } return expression(self, value.b, environment, depth + 1); },
        blot_parse_ast::tag_field_access => { let receiver, error = expression(self, value.a, environment, depth + 1); if error != Error.none { return 0, error; } if ungrouped < self.operations.len && self.operations[ungrouped] != 0 { let children: Id[1] = [receiver]; return self.store.aggregate(Tag.captures, children); } return self.store.project(receiver, value.b, blot_check_capability_contracts::Projection.field); },
        blot_parse_ast::tag_index_access => { return selectIndex(self, value.a, value.b, environment, depth + 1); },
        blot_parse_ast::tag_apply => { return application(self, ungrouped, value, environment, depth); },
        blot_parse_ast::tag_product, blot_parse_ast::tag_array => { var children: u32[4096]; let sources = self.tree.children(ungrouped); if sources.len > children.len { return 0, Error.capability_analysis_limit; }
            for child, index in sources { let id, error = expression(self, child, environment, depth + 1); if error != Error.none { return 0, error; } children[index] = id; if value.tag == blot_parse_ast::tag_array { let error = inputStore(self, id); if error != Error.none { return 0, error; } } } return self.store.aggregate(Tag.product, children[..sources.len]);
        },
        blot_parse_ast::tag_record => { var fields: u32[4096]; let sources = self.tree.children(ungrouped); if sources.len > fields.len / 2 { return 0, Error.capability_analysis_limit; }
            for child, index in sources { let field = self.tree.node(child); fields[index * 2] = field.a; let id, error = expression(self, child, environment, depth + 1); if error != Error.none { return 0, error; } fields[index * 2 + 1] = id; }
            let record, error = self.store.aggregate(Tag.record, fields[..sources.len * 2]); if error != Error.none { return 0, error; } if value.a != 0 { return self.store.append(blot_check_capability_contracts::Term { Tag.wrapped, record }); } return record, Error.none;
        },
        blot_parse_ast::tag_if_expr => { if self.lexical_captures { let ignored, error = expression(self, value.a, environment, depth + 1); if error != Error.none { return 0, error; } } let left, error = expression(self, value.b, environment, depth + 1); if error != Error.none { return 0, error; } let right, error = expression(self, value.c, environment, depth + 1); if error != Error.none { return 0, error; } let children: Id[2] = [left, right]; return self.store.aggregate(Tag.join, children); },
        blot_parse_ast::tag_block => { return blockValue(self, ungrouped, value, environment, depth); },
        blot_parse_ast::tag_case_expr => { return caseValue(self, value, environment, depth); },
        blot_parse_ast::tag_lambda => { var captures: Id[4096]; var count: i64 = 0; let error = capture(self, source, environment, captures, count, depth + 1); if error != Error.none { return 0, error; } for value in captures[..count] { let error = inputStore(self, value); if error != Error.none { return 0, error; } } return self.store.aggregate(Tag.captures, captures[..count]); },
        _ => { return 0, Error.unavailable; },
    }
}
fn application(self: Builder&, ungrouped: AstId, value: blot_parse_ast::Node, environment: const Environment&, depth: i64) -> Id, Error {
    if self.lexical_captures {
        let argument, error = self.node(value.b, depth + 1); if error != Error.none { return 0, error; } var callee_source = value.a; while self.tree.node(callee_source).tag == blot_parse_ast::tag_group { callee_source = self.tree.node(callee_source).a; }
        var head = ungrouped; var operands: AstId[16]; var count: i64 = 0;
        while true { let applied, error = self.node(head, depth + 1); if error != Error.none { return 0, error; } if applied.tag != blot_parse_ast::tag_apply { break; } if count == operands.len { return 0, Error.unavailable; } operands[count] = applied.b; count += 1; head = applied.a; }
        let primitive, error = self.node(head, depth + 1); if error != Error.none { return 0, error; }
        if primitive.tag == blot_parse_ast::tag_intrinsic { let text = self.pool.get(primitive.a); if text.starts_with("@u32.") || text.starts_with("@f32.") { for operand in operands[..count] { let ignored, error = expression(self, operand, environment, depth + 1); if error != Error.none { return 0, error; } } return 0, Error.none; } }
        if argument.tag == blot_parse_ast::tag_unit && callee_source < self.operations.len && self.operations[callee_source] != 0 {
            let ignored, error = expression(self, callee_source, environment, depth + 1); if error != Error.none { return 0, error; }
            let types .= self.input_types; if types { if ungrouped >= self.input_expr_types.len { return 0, Error.unavailable; }
                match types.node(types.head(self.input_expr_types[ungrouped], 0)).tag { blot_check_types::Tag.unit, blot_check_types::Tag.boolean, blot_check_types::Tag.unsigned32, blot_check_types::Tag.floating32, blot_check_types::Tag.never => { return 0, Error.none; }, _ => {}, }
            } return self.store.append(blot_check_capability_contracts::Term { Tag.unknown });
        }
    }
    let call = blot_check_capability_flow::localSourceCall(self.tree, ungrouped);
    if call.present { if environment.get(call.value.name).present { return 0, Error.unavailable; } var nested = Environment {};
        for index in 0..call.value.len { let argument, error = expression(self, call.value.arguments[index], environment, depth + 1); if error != Error.none { return 0, error; } let error = nested.bind(call.value.parameters[index], argument); if error != Error.none { return 0, error; } } return expression(self, call.value.body, nested, depth + 1);
    }
    if self.lexical_captures { let functions .= self.functions; if functions { var callee = ungrouped; var reverse: AstId[16]; var count: i64 = 0;
            while true { let node, error = self.node(callee, depth + 1); if error != Error.none { return 0, error; } if node.tag != blot_parse_ast::tag_apply { break; } if count == reverse.len { return 0, Error.unavailable; } reverse[count] = node.b; count += 1; callee = node.a; }
            let header = functions.lookup(callee); if header.present { if header.value.arity != count { return 0, Error.unavailable; } var arguments: Id[16];
                for index in 0..count { let id, error = expression(self, reverse[count - index - 1], environment, depth + 1); if error != Error.none { return 0, error; } arguments[index] = id; } return self.store.instantiate(header.value, arguments[..count]);
            }
    } }
    let construction = blot_check_capability_flow::constructionSource(self.tree, self.pool, ungrouped);
    if construction.present { var children: Id[3]; for index in 0..construction.value.len { let id, error = expression(self, construction.value.inputs[index], environment, depth + 1); if error != Error.none { return 0, error; } children[index] = id; }
        for child in children[..construction.value.len] { let error = inputStore(self, child); if error != Error.none { return 0, error; } }
        if construction.value.kind == blot_check_capability_flow::ConstructionKind.computation { return self.store.append(blot_check_capability_contracts::Term { Tag.wrapped, children[0] }); } return self.store.aggregate(Tag.captures, children[..construction.value.len]);
    }
    let projection = blot_check_capability_flow::projectionSource(self.tree, self.pool, ungrouped); if projection.present { return selectIndex(self, projection.value.receiver, projection.value.index, environment, depth + 1); }
    let callee, error = self.node(value.a, depth + 1); if error != Error.none { return 0, error; }
    if callee.tag == blot_parse_ast::tag_intrinsic { let name = self.pool.get(callee.a); if name == "@usage.read" || name == "@usage.length" { if self.lexical_captures { let ignored, error = expression(self, value.b, environment, depth + 1); if error != Error.none { return 0, error; } } return 0, Error.none; } }
    if callee.tag != blot_parse_ast::tag_constructor_ref { return 0, Error.unavailable; } let id, error = expression(self, value.b, environment, depth + 1); if error != Error.none { return 0, error; } return self.store.append(blot_check_capability_contracts::Term { Tag.wrapped, id });
}
fn blockValue(self: Builder&, source: AstId, value: blot_parse_ast::Node, environment: const Environment&, depth: i64) -> Id, Error {
    if value.c != 0 { return 0, Error.unavailable; } var nested = environment; let children = self.tree.children(source);
    for child, index in children { let statement = self.tree.node(child); if statement.tag == blot_parse_ast::tag_return_stmt && index + 1 == children.len { return expression(self, statement.a, nested, depth + 1); }
        if self.lexical_captures && statement.tag == blot_parse_ast::tag_use_stmt { let retained, error = expression(self, statement.b, nested, depth + 1); if error != Error.none { return 0, error; } if statement.a != 0 { let error = nested.bind(statement.a, retained); if error != Error.none { return 0, error; } } continue; }
        if statement.tag != blot_parse_ast::tag_let_stmt { return 0, Error.unavailable; } let binding = self.tree.binding(child); let alias = self.tree.node(binding.pattern); if alias.tag != blot_parse_ast::tag_pattern_name || binding.fallback != 0 { return 0, Error.unavailable; }
        let id, error = expression(self, binding.value, nested, depth + 1); if error != Error.none { return 0, error; } let error = nested.bind(alias.a, id); if error != Error.none { return 0, error; }
    } return 0, Error.unavailable;
}
fn caseValue(self: Builder&, value: blot_parse_ast::Node, environment: const Environment&, depth: i64) -> Id, Error {
    let inputs = self.tree.extra[value.a..value.a + 2]; if inputs[1] > 16 || value.c > 4096 { return 0, Error.capability_analysis_limit; } var retained: Id[16];
    for input, index in self.tree.list(blot_parse_ast::List { inputs[0], inputs[1] }) { let id, error = expression(self, input, environment, depth + 1); if error != Error.none { return 0, error; } retained[index] = id; }
    var arms: Id[4096]; for arm_id, index in self.tree.list(blot_parse_ast::List { value.b, value.c }) { let arm = self.tree.node(arm_id); var nested = environment; let start = nested.len;
        for row in self.tree.list(blot_parse_ast::List { arm.a, arm.b }) { let patterns = self.tree.children(row); if patterns.len != inputs[1] { return 0, Error.unavailable; }
            for pattern, ordinal in patterns { let error = bindShapePattern(self, pattern, retained[ordinal], nested, start, depth + 1); if error != Error.none { return 0, error; } }
        }
        let details = self.tree.extra[arm.c..arm.c + 2]; if self.lexical_captures && details[0] != 0 { let ignored, error = expression(self, details[0], nested, depth + 1); if error != Error.none { return 0, error; } }
        let id, error = expression(self, details[1], nested, depth + 1); if error != Error.none { return 0, error; } arms[index] = id;
    } return self.store.aggregate(Tag.join, arms[..value.c]);
}
fn bindPattern(self: Builder&, environment: Environment&, start: i64, name: u32, value: Id) -> Error {
    for index in start..environment.len { let entry .= environment.entries[index]; if entry.name == name { if entry.value != value { let children: Id[2] = [entry.value, value]; let id, error = self.store.aggregate(Tag.join, children); if error != Error.none { return error; } entry.value = id; } return Error.none; } } return environment.bind(name, value);
}
fn directPayload(self: Builder&, name: u32) -> bool {
    for root in self.tree.roots { let declaration = self.tree.node(root); if declaration.tag != blot_parse_ast::tag_data_decl { continue; }
        for constructor in self.tree.children(declaration.b) { let node = self.tree.node(constructor); if node.a != name { continue; }
            for traits in self.tree.declaration_traits { if traits.declaration == root && traits.is_opaque { return true; } } return node.b == 0 || self.tree.node(node.b).tag != blot_parse_ast::tag_type_record;
        }
    } return false;
}
recursive fn bindShapePattern(self: Builder&, source: AstId, origin: Id, environment: Environment&, start: i64, depth: i64) -> Error {
    let value, error = self.node(source, depth); if error != Error.none { return error; }
    match value.tag {
        blot_parse_ast::tag_pattern_name => { return bindPattern(self, environment, start, value.a, origin); },
        blot_parse_ast::tag_pattern_integer, blot_parse_ast::tag_pattern_boolean => {},
        blot_parse_ast::tag_pattern_field => { let field, error = self.store.project(origin, value.a, blot_check_capability_contracts::Projection.field); if error != Error.none { return error; } if value.b != 0 { return bindShapePattern(self, value.b, field, environment, start, depth + 1); } return bindPattern(self, environment, start, value.a, field); },
        blot_parse_ast::tag_pattern_constructor => { if value.b != 0 { if !directPayload(self, value.a) { return Error.unavailable; } let payload, error = self.store.project(origin, 0, blot_check_capability_contracts::Projection.payload); if error != Error.none { return error; } return bindShapePattern(self, value.b, payload, environment, start, depth + 1); } },
        blot_parse_ast::tag_pattern_product => { for child, index in self.tree.children(source) { let selected, error = self.store.project(origin, index as u32, blot_check_capability_contracts::Projection.index); if error != Error.none { return error; } let error = bindShapePattern(self, child, selected, environment, start, depth + 1); if error != Error.none { return error; } } },
        blot_parse_ast::tag_pattern_record => { for child in self.tree.children(source) { let error = bindShapePattern(self, child, origin, environment, start, depth + 1); if error != Error.none { return error; } } },
        _ => { return Error.unavailable; },
    } return Error.none;
}
recursive fn capture(self: Builder&, source: AstId, environment: const Environment&, captures: Id[4096]&, count: i64&, depth: i64) -> Error {
    let value, error = self.node(source, depth); if error != Error.none { return error; } var ungrouped = source; while self.tree.node(ungrouped).tag == blot_parse_ast::tag_group { ungrouped = self.tree.node(ungrouped).a; }
    match value.tag {
        blot_parse_ast::tag_name => { let captured, error = name(self, value.a, environment, true); if error != Error.none { return error; } if captured == 0 { return Error.none; } for known in captures[..count] { if known == captured { return Error.none; } }
            if count == captures.len { return Error.capability_analysis_limit; } captures[count] = captured; count += 1;
        },
        blot_parse_ast::tag_intrinsic, blot_parse_ast::tag_integer, blot_parse_ast::tag_float, blot_parse_ast::tag_string, blot_parse_ast::tag_boolean, blot_parse_ast::tag_unit => {},
        blot_parse_ast::tag_lambda => { var nested = environment; let error = nested.bind(self.tree.parameter(value.a).name, 0); if error != Error.none { return error; } return capture(self, value.b, nested, captures, count, depth + 1); },
        blot_parse_ast::tag_apply, blot_parse_ast::tag_index_access => { let error = capture(self, value.a, environment, captures, count, depth + 1); if error != Error.none { return error; } return capture(self, value.b, environment, captures, count, depth + 1); },
        blot_parse_ast::tag_field_access, blot_parse_ast::tag_return_stmt, blot_parse_ast::tag_function_return_stmt, blot_parse_ast::tag_yield_stmt => { return capture(self, value.a, environment, captures, count, depth + 1); },
        blot_parse_ast::tag_field => { if value.b != 0 { return capture(self, value.b, environment, captures, count, depth + 1); } let known = environment.get(value.a); if !known.present { return Error.unavailable; } if count == captures.len { return Error.capability_analysis_limit; } captures[count] = known.value; count += 1; },
        blot_parse_ast::tag_unary, blot_parse_ast::tag_operator_tail => { return capture(self, value.b, environment, captures, count, depth + 1); },
        blot_parse_ast::tag_binary => { let error = capture(self, value.b, environment, captures, count, depth + 1); if error != Error.none { return error; } return capture(self, value.c, environment, captures, count, depth + 1); },
        blot_parse_ast::tag_block => { if value.c != 0 { return Error.unavailable; } var nested = environment;
            for child in self.tree.children(ungrouped) { let statement = self.tree.node(child);
                if statement.tag == blot_parse_ast::tag_let_stmt { let binding = self.tree.binding(child); if binding.fallback != 0 { return Error.unavailable; } let error = capture(self, binding.value, nested, captures, count, depth + 1); if error != Error.none { return error; } let start = nested.len; let error = bindShapePattern(self, binding.pattern, 0, nested, start, depth + 1); if error != Error.none { return error; } }
                else { let error = capture(self, child, nested, captures, count, depth + 1); if error != Error.none { return error; } }
            }
        },
        blot_parse_ast::tag_case_expr => { let inputs = self.tree.extra[value.a..value.a + 2]; if inputs[1] > 16 { return Error.unavailable; }
            for input in self.tree.list(blot_parse_ast::List { inputs[0], inputs[1] }) { let error = capture(self, input, environment, captures, count, depth + 1); if error != Error.none { return error; } }
            for arm_id in self.tree.list(blot_parse_ast::List { value.b, value.c }) { let arm = self.tree.node(arm_id); var nested = environment; let start = nested.len;
                for row in self.tree.list(blot_parse_ast::List { arm.a, arm.b }) { let patterns = self.tree.children(row); if patterns.len != inputs[1] { return Error.unavailable; } for pattern in patterns { let error = bindShapePattern(self, pattern, 0, nested, start, depth + 1); if error != Error.none { return error; } } }
                let details = self.tree.extra[arm.c..arm.c + 2]; if details[0] != 0 { let error = capture(self, details[0], nested, captures, count, depth + 1); if error != Error.none { return error; } } let error = capture(self, details[1], nested, captures, count, depth + 1); if error != Error.none { return error; }
            }
        },
        blot_parse_ast::tag_if_expr => { let error = capture(self, value.a, environment, captures, count, depth + 1); if error != Error.none { return error; } let error = capture(self, value.b, environment, captures, count, depth + 1); if error != Error.none { return error; } return capture(self, value.c, environment, captures, count, depth + 1); },
        blot_parse_ast::tag_product, blot_parse_ast::tag_record, blot_parse_ast::tag_array => { for child in self.tree.children(ungrouped) { let error = capture(self, child, environment, captures, count, depth + 1); if error != Error.none { return error; } } },
        _ => { return Error.unavailable; },
    } return Error.none;
}
fn derive(store: Store&, tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, summary: blot_check_capability_flow::Parameters) -> blot_support::Option<Id>, Error { return deriveChecked(store, tree, pool, source, summary, []); }
fn deriveChecked(store: Store&, tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, summary: blot_check_capability_flow::Parameters, operations: const u32[:]) -> blot_support::Option<Id>, Error {
    if !summary.valid() || !summary.present() || summary.invokes() { return blot_support::none<Id>(), Error.none; }
    var builder = Builder { store, tree, pool, operations: operations }; return deriveBody(builder, source, summary.arity(), false);
}
fn deriveBody(builder: Builder&, source: AstId, arity: u32, require_names: bool) -> blot_support::Option<Id>, Error {
    let checkpoint = builder.store.mark(); let result, error = deriveBodyInner(builder, source, arity, require_names);
    if error != Error.none { builder.store.rollback(checkpoint); if error == Error.unavailable { return blot_support::none<Id>(), Error.none; } return blot_support::none<Id>(), error; }
    let validation = builder.store.view().validate(result, arity, true); if validation != Error.none { builder.store.rollback(checkpoint); return blot_support::none<Id>(), Error.none; } return blot_support::some(result), Error.none;
}
fn deriveBodyInner(builder: Builder&, source: AstId, arity: u32, require_names: bool) -> Id, Error {
    let empty, error = builder.store.append(blot_check_capability_contracts::Term { Tag.empty }); if error != Error.none { return 0, error; } var environment = Environment {}; var body = source;
    for index in 0..arity { let lambda, error = builder.node(body, 0); if error != Error.none { return 0, error; } if lambda.tag != blot_parse_ast::tag_lambda { return 0, Error.unavailable; } let parameter = builder.tree.parameter(lambda.a);
        if require_names && parameter.name == 0 && !parameter.is_unit { return 0, Error.unavailable; }
        if !require_names || parameter.name != 0 { let id, error = builder.store.append(blot_check_capability_contracts::Term { Tag.parameter, index as u32 }); if error != Error.none { return 0, error; } let error = environment.bind(parameter.name, id); if error != Error.none { return 0, error; } } body = lambda.b;
    } return expression(builder, body, environment, 0);
}
fn deriveClosure(store: Store&, tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, operations: const u32[:], types: const blot_check_types::Store&, expr_types: const u32[:]) -> blot_support::Option<Id>, Error { return deriveInputFunction(store, tree, pool, source, operations, types, expr_types, 1); }
fn deriveInputFunction(store: Store&, tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, operations: const u32[:], types: const blot_check_types::Store&, expr_types: const u32[:], arity: u8) -> blot_support::Option<Id>, Error { return deriveInputFunctionWithFunctions(store, tree, pool, source, operations, types, expr_types, arity, null); }
fn deriveInputFunctionWithFunctions(store: Store&, tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, operations: const u32[:], types: const blot_check_types::Store&, expr_types: const u32[:], arity: u8, functions: const Functions?) -> blot_support::Option<Id>, Error {
    if arity == 0 || arity > 16 { return blot_support::none<Id>(), Error.none; }
    var builder = Builder { store, tree, pool, operations: operations, lexical_captures: true, input_types: types, input_expr_types: expr_types, functions: functions }; return deriveBody(builder, source, arity, true);
}
struct InputCheck { tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, operations: const u32[:], types: const blot_check_types::Store&, expr_types: const u32[:], arity: u8, result: bool = false }
fn inputCheck(context: InputCheck&, store: Store&) -> Error {
    let root, error = deriveInputFunction(store, context.tree, context.pool, context.source, context.operations, context.types, context.expr_types, context.arity); if error != Error.none || !root.present { return Error.none; }
    if store.view().validate(root.value, context.arity, true) != Error.none { return Error.none; } for node in store.nodes { if node.tag == Tag.unknown { return Error.none; } } context.result = true; return Error.none;
}
fn inputFunction(tree: const blot_parse_ast::Tree&, pool: blot_parse_symbols::Pool&, source: AstId, operations: const u32[:], types: const blot_check_types::Store&, expr_types: const u32[:], arity: u8) -> bool {
    var context = InputCheck { tree, pool, source, operations, types, expr_types, arity }; let error = blot_check_capability_contracts::withStore<InputCheck,inputCheck>(context); return error == Error.none && context.result;
}
