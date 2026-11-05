// Owned syntax tables. Edges are stable numeric IDs; zero is absent.
namespace blot_parse_ast;
import .token;
import .symbols;

type Id = u32;
struct Span { start: u32 = 0, end: u32 = 0 }
struct List { start: u32 = 0, len: u32 = 0 }
type Tag = u32;
let tag_invalid: Tag = 0;
let tag_value_decl: Tag = 1;
let tag_import_decl: Tag = 2;
let tag_export_decl: Tag = 3;
let tag_import_binding: Tag = 4;
let tag_data_decl: Tag = 5;
let tag_type_alias_decl: Tag = 6;
let tag_contract_decl: Tag = 7;
let tag_contract_type_member: Tag = 8;
let tag_contract_value_member: Tag = 9;
let tag_implementation_decl: Tag = 10;
let tag_effect_decl: Tag = 11;
let tag_effect_type_decl: Tag = 12;
let tag_fixity_decl: Tag = 13;
let tag_attribute: Tag = 14;
let tag_constraint: Tag = 15;
let tag_where_clause: Tag = 16;
let tag_constructors: Tag = 17;
let tag_effect_operations: Tag = 18;
let tag_effect_operation: Tag = 19;
let tag_name: Tag = 20;
let tag_intrinsic: Tag = 21;
let tag_integer: Tag = 22;
let tag_float: Tag = 23;
let tag_string: Tag = 24;
let tag_boolean: Tag = 25;
let tag_unit: Tag = 26;
let tag_lambda: Tag = 27;
let tag_parameter: Tag = 28;
let tag_apply: Tag = 29;
let tag_group: Tag = 30;
let tag_unary: Tag = 31;
let tag_binary: Tag = 32;
let tag_infix_chain: Tag = 33;
let tag_operator_tail: Tag = 34;
let tag_product: Tag = 35;
let tag_array: Tag = 36;
let tag_block: Tag = 37;
let tag_record: Tag = 38;
let tag_field: Tag = 39;
let tag_selector: Tag = 40;
let tag_constructor_ref: Tag = 41;
let tag_type_witness: Tag = 42;
let tag_field_access: Tag = 43;
let tag_index_access: Tag = 44;
let tag_let_stmt: Tag = 45;
let tag_rebind_stmt: Tag = 46;
let tag_use_stmt: Tag = 47;
let tag_iterator_bind: Tag = 48;
let tag_function_return_stmt: Tag = 49;
let tag_return_stmt: Tag = 50;
let tag_yield_stmt: Tag = 51;
let tag_break_stmt: Tag = 52;
let tag_continue_stmt: Tag = 53;
let tag_if_expr: Tag = 54;
let tag_if_stmt: Tag = 55;
let tag_if_let_stmt: Tag = 56;
let tag_for_stmt: Tag = 57;
let tag_range_stmt: Tag = 58;
let tag_forever_stmt: Tag = 59;
let tag_case_expr: Tag = 60;
let tag_case_arm: Tag = 61;
let tag_pattern_row: Tag = 62;
let tag_request_case: Tag = 63;
let tag_request_arm: Tag = 64;
let tag_pattern_name: Tag = 65;
let tag_pattern_integer: Tag = 66;
let tag_pattern_boolean: Tag = 67;
let tag_pattern_product: Tag = 68;
let tag_pattern_constructor: Tag = 69;
let tag_pattern_record: Tag = 70;
let tag_pattern_field: Tag = 71;
let tag_pattern_value: Tag = 72;
let tag_type_name: Tag = 73;
let tag_type_apply: Tag = 74;
let tag_type_function: Tag = 75;
let tag_type_effect: Tag = 76;
let tag_type_product: Tag = 77;
let tag_type_array: Tag = 78;
let tag_type_record: Tag = 79;
let tag_type_field: Tag = 80;
let tag_effect_row: Tag = 81;
let tag_numeric_error: Tag = 82;
let tag_type_binder: Tag = 83;
let tag_type_usage: Tag = 84;
let tag_type_forall: Tag = 85;
let tag_type_exists: Tag = 86;
let tag_quantified_binder: Tag = 87;
let tag_package_pack: Tag = 88;
let tag_package_unpack: Tag = 89;
let tag_type_code: Tag = 90;
let tag_type_descriptor: Tag = 91;
let tag_task_region: Tag = 92;
type BinderSort = u32;
let bindersort_type_: BinderSort = 0;
let bindersort_row: BinderSort = 1;
let bindersort_region: BinderSort = 2;
type UsageKind = u32;
let usagekind_unique: UsageKind = 0;
let usagekind_shared: UsageKind = 1;
let usagekind_borrow: UsageKind = 2;
let usagekind_borrow_mut: UsageKind = 3;
let usagekind_once: UsageKind = 4;
let usagekind_many: UsageKind = 5;
let usagekind_cleanup: UsageKind = 6;
let usagekind_concurrent: UsageKind = 7;
type NumericCode = u32;
let numericcode_integer_range: NumericCode = 0;
let numericcode_float_range: NumericCode = 1;
let numericcode_float_literal: NumericCode = 2;
type Code = u32;
let code_expected_token: Code = 0;
let code_expected_expression: Code = 1;
let code_expected_type: Code = 2;
let code_expected_pattern: Code = 3;
let code_unexpected_token: Code = 4;
let code_task_spark_scope: Code = 5;
let code_task_spark_call: Code = 6;
let code_task_receive_tuple: Code = 7;
let code_invalid_literal: Code = 8;
let code_operator_associativity: Code = 9;
let code_fixity_order: Code = 10;
let code_duplicate_fixity: Code = 11;
let code_invalid_precedence: Code = 12;
let code_nesting_limit: Code = 13;
let code_table_limit: Code = 14;
let code_private_marker: Code = 15;
let code_GPU_FRONTEND_SYNTAX_ERROR: Code = 16;
let code_function_return_required: Code = 17;

struct Node { tag: Tag = 0, a: u32 = 0, b: u32 = 0, c: u32 = 0 }
struct NumericFault { node: Id, code: NumericCode, span: Span, actual_token: blot_parse_token::Tag }
struct Diagnostic {
 code: Code, start: u32, end: u32,
 has_declaration_origin: bool = false, declaration_origin: Span = Span {},
 has_detail_span: bool = false, detail_span: Span = Span {},
 has_actual_token: bool = false, actual_token: blot_parse_token::Tag = blot_parse_token::eof,
 has_expected_token: bool = false, expected_token: blot_parse_token::Tag = blot_parse_token::eof
}
fn message(value: Diagnostic) -> const u8[:] {
 if value.code == code_GPU_FRONTEND_SYNTAX_ERROR { return "This syntax is not allowed in this position"; }
 if value.code == code_expected_token { return "Expected a syntax token"; }
 if value.code == code_expected_expression { return "Expected an expression"; }
 if value.code == code_function_return_required { return "A function body requires return or a do block with explicit returns"; }
 if value.code == code_expected_type { return "Expected a type"; }
 if value.code == code_expected_pattern { return "Expected a pattern"; }
 if value.code == code_unexpected_token { return "Unexpected syntax token"; }
 if value.code == code_task_spark_scope { return "A sparked call needs an enclosing task group"; }
 if value.code == code_task_spark_call { return "Spark needs a parenthesized function call"; }
 if value.code == code_task_receive_tuple { return "Tuple receive is not available yet; join each handle explicitly"; }
 if value.code == code_invalid_literal { return "Invalid literal"; }
 if value.code == code_operator_associativity { return "Equal-precedence operators need compatible associativity or parentheses"; }
 if value.code == code_fixity_order { return "Fixity declarations must precede other declarations"; }
 if value.code == code_duplicate_fixity { return "An operator fixity was declared more than once"; }
 if value.code == code_invalid_precedence { return "Operator precedence must be between 0 and 255"; }
 if value.code == code_nesting_limit { return "Syntax nesting exceeds the parser limit"; }
 if value.code == code_table_limit { return "Syntax exceeds the 32-bit table limit"; }
 if value.code == code_private_marker { return "Private frontend markers are not source syntax"; }
 return "Unknown syntax diagnostic";
}

struct ValueDecl { name: blot_parse_symbols::Symbol, body: Id, annotation: Id, modifier: blot_parse_symbols::Symbol, runtime: bool, exported: bool, where: List, where_node: Id, attributes: List }
struct ImplementationDecl { name: blot_parse_symbols::Symbol, parameters: List, head: Id, members: List, where: List, where_node: Id }
struct Parameter { name: blot_parse_symbols::Symbol, annotation: Id, is_unit: bool, requires_return: bool, pattern_bound: bool, where: List, where_node: Id }
struct Binding { pattern: Id, value: Id, annotation: Id, where: List, where_node: Id, fallback: Id }
struct ImportDecl { path: blot_parse_symbols::Symbol, namespace: blot_parse_symbols::Symbol, bindings: List, path_span: Span, namespace_span: Span }
struct ImportBinding { name: blot_parse_symbols::Symbol, alias: blot_parse_symbols::Symbol }
struct Fixity { operator: blot_parse_symbols::Symbol, target: blot_parse_symbols::Symbol, precedence: u32, association: u32, named: bool, attributes: List = List {}, literal_error: Id = 0 }
struct DeclarationTraits { declaration: Id, private: bool = false, is_opaque: bool = false }
struct RuntimeName { declaration: Id, point: u32 }
struct DeclarationNodes { root: Id, first: Id, end: Id }
struct OperatorOrigin { node: Id, span: Span, member: blot_parse_symbols::Symbol = 0, member_point: u32 = 0 }
struct TypeConversionOrigin { node: Id, point: u32 }
struct Tree {
 has_typed_staging: bool = false, has_numeric_proofs: bool = false,
 nodes: Node[>..<]&, spans: Span[>..<]&, extra: u32[>..<]&, roots: Id[>..<]&,
 runtime_names: RuntimeName[>..<]&, constant_names: RuntimeName[>..<]&,
 declaration_traits: DeclarationTraits[>..<]&, declaration_nodes: DeclarationNodes[>..<]&,
 diagnostics: Diagnostic[>..<]&, operator_origins: OperatorOrigin[>..<]&,
 type_conversion_origins: TypeConversionOrigin[>..<]&
}
fn init(nodes: Node[>..<]&, spans: Span[>..<]&, extra: u32[>..<]&, roots: Id[>..<]&, runtime_names: RuntimeName[>..<]&, constant_names: RuntimeName[>..<]&, declaration_traits: DeclarationTraits[>..<]&, declaration_nodes: DeclarationNodes[>..<]&, diagnostics: Diagnostic[>..<]&, operator_origins: OperatorOrigin[>..<]&, type_conversion_origins: TypeConversionOrigin[>..<]&) -> Tree {
 nodes.push(Node {}); spans.push(Span {});
 return Tree {nodes:nodes,spans:spans,extra:extra,roots:roots,runtime_names:runtime_names,constant_names:constant_names,declaration_traits:declaration_traits,declaration_nodes:declaration_nodes,diagnostics:diagnostics,operator_origins:operator_origins,type_conversion_origins:type_conversion_origins};
}
fn node(tree: const Tree&, id: Id) -> Node { return tree.nodes[id]; }
fn span(tree: const Tree&, id: Id) -> Span { return tree.spans[id]; }
fn declaration_nodes(tree: const Tree&, root: Id) -> List, bool {
 for owner in tree.declaration_nodes {
  if owner.root != root { continue; }
  if owner.first == 0 || owner.first >= owner.end || owner.end > tree.nodes.len || root < owner.first || root >= owner.end { return List {}, false; }
  return List {owner.first, owner.end-owner.first}, true;
 }
 return List {}, false;
}
fn declaration_traits(tree: const Tree&, id: Id) -> DeclarationTraits {
 var lo = 0; var hi = tree.declaration_traits.len;
 while lo < hi { let mid = lo + (hi-lo)/2; let v = tree.declaration_traits[mid]; if v.declaration < id { lo = mid+1; } else { hi = mid; } }
 if lo < tree.declaration_traits.len && tree.declaration_traits[lo].declaration == id { return tree.declaration_traits[lo]; }
 return DeclarationTraits { declaration: id };
}
fn find_name(items: const RuntimeName[:], id: Id) -> u32, bool {
 var lo = 0; var hi = items.len;
 while lo < hi { let mid = lo+(hi-lo)/2; if items[mid].declaration < id { lo = mid+1; } else { hi = mid; } }
 if lo < items.len && items[lo].declaration == id { return items[lo].point, true; }
 return 0, false;
}
fn runtime_name_point(tree: const Tree&, id: Id) -> u32, bool { return find_name(tree.runtime_names, id); }
fn value_name_point(tree: const Tree&, id: Id) -> u32, bool {
 let p, found = runtime_name_point(tree,id); if found { return p,true; }
 return find_name(tree.constant_names,id);
}
fn numeric_fault(tree: const Tree&, id: Id) -> NumericFault {
 let n = node(tree,id); var actual = blot_parse_token::float;
 if n.a == numericcode_integer_range { actual = blot_parse_token::integer; }
 return NumericFault {id, n.a, Span {n.b,n.c}, actual};
}
fn type_conversion_origin(tree: const Tree&, id: Id) -> u32 {
 var point = span(tree,id).start;
 for origin in tree.type_conversion_origins { if origin.node == id && origin.point < point { point = origin.point; } }
 return point;
}
fn list(tree: const Tree&, range: List) -> const u32[:] { return tree.extra[range.start..range.start+range.len]; }
fn children(tree: const Tree&, id: Id) -> const Id[:] {
 let n=node(tree,id);
 if n.tag == tag_record { return list(tree,List {n.b,n.c}); }
 if n.tag == tag_product || n.tag == tag_array || n.tag == tag_block || n.tag == tag_constructors || n.tag == tag_effect_operations || n.tag == tag_pattern_product || n.tag == tag_pattern_record || n.tag == tag_pattern_row || n.tag == tag_type_product || n.tag == tag_type_array || n.tag == tag_type_record { return list(tree,List {n.a,n.b}); }
 return tree.extra[..0];
}
fn quantifier_predicates(tree: const Tree&, id: Id) -> Id { return tree.extra[node(tree,id).c+1]; }
fn value_decl(tree: const Tree&, id: Id) -> ValueDecl {
 let n=node(tree,id); let x=tree.extra[n.c..n.c+9];
 return ValueDecl {n.a,n.b,x[0],x[1],x[2]==1,(x[7]&1)!=0,List {x[3],x[4]},x[8],List {x[5],x[6]}};
}
fn implementation(tree: const Tree&, id: Id) -> ImplementationDecl {
 let n=node(tree,id); let x=tree.extra[n.c..n.c+6]; let members=node(tree,n.b);
 return ImplementationDecl {n.a,List {x[0],x[1]},x[2],List {members.a,members.b},List {x[3],x[4]},x[5]};
}
fn parameter(tree: const Tree&, id: Id) -> Parameter {
 let n=node(tree,id); let x=tree.extra[n.c..n.c+4];
 return Parameter {n.a,n.b,(x[0]&1)!=0,(x[0]&2)!=0,(x[0]&4)!=0,List {x[1],x[2]},x[3]};
}
fn binding(tree: const Tree&, id: Id) -> Binding {
 let n=node(tree,id); let x=tree.extra[n.c..n.c+5];
 return Binding {n.a,n.b,x[0],List {x[1],x[2]},x[4],x[3]};
}
fn import_decl(tree: const Tree&, id: Id) -> ImportDecl {
 let n=node(tree,id); let x=tree.extra[n.c..n.c+6];
 return ImportDecl {n.a,x[1],List {n.b,x[0]},Span {x[2],x[3]},Span {x[4],x[5]}};
}
fn import_binding(tree: const Tree&, id: Id) -> ImportBinding { let n=node(tree,id); return ImportBinding {n.a,n.b}; }
fn fixity(tree: const Tree&, id: Id) -> Fixity {
 let n=node(tree,id); let x=tree.extra[n.c..n.c+3]; var attrs=List {}; var literal: Id=0;
 if (x[2]&2)!=0 { attrs=List {tree.extra[n.c+3],tree.extra[n.c+4]}; }
 if (x[2]&4)!=0 { literal=tree.extra[n.c+5]; }
 return Fixity {n.a,n.b,x[0],x[1],(x[2]&1)!=0,attrs,literal};
}

fn code_name(code: Code) -> const u8[:] {
 if code==code_expected_token { return "expected_token"; }
 if code==code_expected_expression { return "expected_expression"; }
 if code==code_expected_type { return "expected_type"; }
 if code==code_expected_pattern { return "expected_pattern"; }
 if code==code_unexpected_token { return "unexpected_token"; }
 if code==code_task_spark_scope { return "task_spark_scope"; }
 if code==code_task_spark_call { return "task_spark_call"; }
 if code==code_task_receive_tuple { return "task_receive_tuple"; }
 if code==code_invalid_literal { return "invalid_literal"; }
 if code==code_operator_associativity { return "operator_associativity"; }
 if code==code_fixity_order { return "fixity_order"; }
 if code==code_duplicate_fixity { return "duplicate_fixity"; }
 if code==code_invalid_precedence { return "invalid_precedence"; }
 if code==code_nesting_limit { return "nesting_limit"; }
 if code==code_table_limit { return "table_limit"; }
 if code==code_private_marker { return "private_marker"; }
 if code==code_GPU_FRONTEND_SYNTAX_ERROR { return "GPU_FRONTEND_SYNTAX_ERROR"; }
 if code==code_function_return_required { return "function_return_required"; }
 return "unknown";
}
