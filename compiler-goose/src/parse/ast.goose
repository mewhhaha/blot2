// Owned syntax tables. Edges are stable numeric IDs; zero is absent.
namespace blot_parse_ast;
import support.pooled_buffer;
import support.error;
import support.native;
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
 has_declaration_origin: bool = false, declaration_origin: Span = Span {..},
 has_detail_span: bool = false, detail_span: Span = Span {..},
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
struct Fixity { operator: blot_parse_symbols::Symbol, target: blot_parse_symbols::Symbol, precedence: u32, association: u32, named: bool, attributes: List = List {..}, literal_error: Id = 0 }
struct DeclarationTraits { declaration: Id, private: bool = false, is_opaque: bool = false }
struct RuntimeName { declaration: Id, point: u32 }
struct DeclarationNodes { root: Id, first: Id, end: Id }
struct OperatorOrigin { node: Id, span: Span, member: blot_parse_symbols::Symbol = 0, member_point: u32 = 0 }
struct TypeConversionOrigin { node: Id, point: u32 }
type TreeError = blot_error::Error;
struct NodeBuffer { storage: Node[:]=[], items: Node[:]=[], len: i64=0, failure: TreeError=TreeError.none }
reusable[] var tree_NodeBuffer_runs: Node[>..]=[];
var inactive_NodeBuffer: NodeBuffer=NodeBuffer {..};
fn ensure(self: NodeBuffer&, minimum: i64) -> TreeError { if self.failure!=TreeError.none { return self.failure; } self.failure=blot_support_pooled_buffer::ensure(self,minimum,tree_NodeBuffer_runs); return self.failure; }
fn push(self: NodeBuffer&, value: Node) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,tree_NodeBuffer_runs); self.len=self.items.len; }
fn append(self: NodeBuffer&, values: const Node[:]) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,tree_NodeBuffer_runs); self.len=self.items.len; }
fn resize(self: NodeBuffer&, length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: NodeBuffer&, length: i64, value: Node) { if length<=self.len { self.resize(length); return; } if self.ensure(length)!=TreeError.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: NodeBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=TreeError.none; }
fn deinit(self: NodeBuffer&) { blot_support_pooled_buffer::deinit(self,tree_NodeBuffer_runs); self.len=0; self.failure=TreeError.none; }
struct SpanBuffer { storage: Span[:]=[], items: Span[:]=[], len: i64=0, failure: TreeError=TreeError.none }
reusable[] var tree_SpanBuffer_runs: Span[>..]=[];
var inactive_SpanBuffer: SpanBuffer=SpanBuffer {..};
fn ensure(self: SpanBuffer&, minimum: i64) -> TreeError { if self.failure!=TreeError.none { return self.failure; } self.failure=blot_support_pooled_buffer::ensure(self,minimum,tree_SpanBuffer_runs); return self.failure; }
fn push(self: SpanBuffer&, value: Span) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,tree_SpanBuffer_runs); self.len=self.items.len; }
fn append(self: SpanBuffer&, values: const Span[:]) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,tree_SpanBuffer_runs); self.len=self.items.len; }
fn resize(self: SpanBuffer&, length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: SpanBuffer&, length: i64, value: Span) { if length<=self.len { self.resize(length); return; } if self.ensure(length)!=TreeError.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: SpanBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=TreeError.none; }
fn deinit(self: SpanBuffer&) { blot_support_pooled_buffer::deinit(self,tree_SpanBuffer_runs); self.len=0; self.failure=TreeError.none; }
struct WordBuffer { storage: u32[:]=[], items: u32[:]=[], len: i64=0, failure: TreeError=TreeError.none }
reusable[] var tree_WordBuffer_runs: u32[>..]=[];
var inactive_WordBuffer: WordBuffer=WordBuffer {..};
fn ensure(self: WordBuffer&, minimum: i64) -> TreeError { if self.failure!=TreeError.none { return self.failure; } self.failure=blot_support_pooled_buffer::ensure(self,minimum,tree_WordBuffer_runs); return self.failure; }
fn push(self: WordBuffer&, value: u32) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,tree_WordBuffer_runs); self.len=self.items.len; }
fn append(self: WordBuffer&, values: const u32[:]) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,tree_WordBuffer_runs); self.len=self.items.len; }
fn resize(self: WordBuffer&, length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: WordBuffer&, length: i64, value: u32) { if length<=self.len { self.resize(length); return; } if self.ensure(length)!=TreeError.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: WordBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=TreeError.none; }
fn deinit(self: WordBuffer&) { blot_support_pooled_buffer::deinit(self,tree_WordBuffer_runs); self.len=0; self.failure=TreeError.none; }
struct NameBuffer { storage: RuntimeName[:]=[], items: RuntimeName[:]=[], len: i64=0, failure: TreeError=TreeError.none }
reusable[] var tree_NameBuffer_runs: RuntimeName[>..]=[];
var inactive_NameBuffer: NameBuffer=NameBuffer {..};
fn ensure(self: NameBuffer&, minimum: i64) -> TreeError { if self.failure!=TreeError.none { return self.failure; } self.failure=blot_support_pooled_buffer::ensure(self,minimum,tree_NameBuffer_runs); return self.failure; }
fn push(self: NameBuffer&, value: RuntimeName) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,tree_NameBuffer_runs); self.len=self.items.len; }
fn append(self: NameBuffer&, values: const RuntimeName[:]) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,tree_NameBuffer_runs); self.len=self.items.len; }
fn resize(self: NameBuffer&, length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: NameBuffer&, length: i64, value: RuntimeName) { if length<=self.len { self.resize(length); return; } if self.ensure(length)!=TreeError.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: NameBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=TreeError.none; }
fn deinit(self: NameBuffer&) { blot_support_pooled_buffer::deinit(self,tree_NameBuffer_runs); self.len=0; self.failure=TreeError.none; }
struct TraitsBuffer { storage: DeclarationTraits[:]=[], items: DeclarationTraits[:]=[], len: i64=0, failure: TreeError=TreeError.none }
reusable[] var tree_TraitsBuffer_runs: DeclarationTraits[>..]=[];
var inactive_TraitsBuffer: TraitsBuffer=TraitsBuffer {..};
fn ensure(self: TraitsBuffer&, minimum: i64) -> TreeError { if self.failure!=TreeError.none { return self.failure; } self.failure=blot_support_pooled_buffer::ensure(self,minimum,tree_TraitsBuffer_runs); return self.failure; }
fn push(self: TraitsBuffer&, value: DeclarationTraits) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,tree_TraitsBuffer_runs); self.len=self.items.len; }
fn append(self: TraitsBuffer&, values: const DeclarationTraits[:]) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,tree_TraitsBuffer_runs); self.len=self.items.len; }
fn resize(self: TraitsBuffer&, length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: TraitsBuffer&, length: i64, value: DeclarationTraits) { if length<=self.len { self.resize(length); return; } if self.ensure(length)!=TreeError.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: TraitsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=TreeError.none; }
fn deinit(self: TraitsBuffer&) { blot_support_pooled_buffer::deinit(self,tree_TraitsBuffer_runs); self.len=0; self.failure=TreeError.none; }
struct DeclarationBuffer { storage: DeclarationNodes[:]=[], items: DeclarationNodes[:]=[], len: i64=0, failure: TreeError=TreeError.none }
reusable[] var tree_DeclarationBuffer_runs: DeclarationNodes[>..]=[];
var inactive_DeclarationBuffer: DeclarationBuffer=DeclarationBuffer {..};
fn ensure(self: DeclarationBuffer&, minimum: i64) -> TreeError { if self.failure!=TreeError.none { return self.failure; } self.failure=blot_support_pooled_buffer::ensure(self,minimum,tree_DeclarationBuffer_runs); return self.failure; }
fn push(self: DeclarationBuffer&, value: DeclarationNodes) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,tree_DeclarationBuffer_runs); self.len=self.items.len; }
fn append(self: DeclarationBuffer&, values: const DeclarationNodes[:]) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,tree_DeclarationBuffer_runs); self.len=self.items.len; }
fn resize(self: DeclarationBuffer&, length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: DeclarationBuffer&, length: i64, value: DeclarationNodes) { if length<=self.len { self.resize(length); return; } if self.ensure(length)!=TreeError.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: DeclarationBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=TreeError.none; }
fn deinit(self: DeclarationBuffer&) { blot_support_pooled_buffer::deinit(self,tree_DeclarationBuffer_runs); self.len=0; self.failure=TreeError.none; }
struct DiagnosticBuffer { storage: Diagnostic[:]=[], items: Diagnostic[:]=[], len: i64=0, failure: TreeError=TreeError.none }
reusable[] var tree_DiagnosticBuffer_runs: Diagnostic[>..]=[];
var inactive_DiagnosticBuffer: DiagnosticBuffer=DiagnosticBuffer {..};
fn ensure(self: DiagnosticBuffer&, minimum: i64) -> TreeError { if self.failure!=TreeError.none { return self.failure; } self.failure=blot_support_pooled_buffer::ensure(self,minimum,tree_DiagnosticBuffer_runs); return self.failure; }
fn push(self: DiagnosticBuffer&, value: Diagnostic) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,tree_DiagnosticBuffer_runs); self.len=self.items.len; }
fn append(self: DiagnosticBuffer&, values: const Diagnostic[:]) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,tree_DiagnosticBuffer_runs); self.len=self.items.len; }
fn resize(self: DiagnosticBuffer&, length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: DiagnosticBuffer&, length: i64, value: Diagnostic) { if length<=self.len { self.resize(length); return; } if self.ensure(length)!=TreeError.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: DiagnosticBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=TreeError.none; }
fn deinit(self: DiagnosticBuffer&) { blot_support_pooled_buffer::deinit(self,tree_DiagnosticBuffer_runs); self.len=0; self.failure=TreeError.none; }
struct OperatorBuffer { storage: OperatorOrigin[:]=[], items: OperatorOrigin[:]=[], len: i64=0, failure: TreeError=TreeError.none }
reusable[] var tree_OperatorBuffer_runs: OperatorOrigin[>..]=[];
var inactive_OperatorBuffer: OperatorBuffer=OperatorBuffer {..};
fn ensure(self: OperatorBuffer&, minimum: i64) -> TreeError { if self.failure!=TreeError.none { return self.failure; } self.failure=blot_support_pooled_buffer::ensure(self,minimum,tree_OperatorBuffer_runs); return self.failure; }
fn push(self: OperatorBuffer&, value: OperatorOrigin) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,tree_OperatorBuffer_runs); self.len=self.items.len; }
fn append(self: OperatorBuffer&, values: const OperatorOrigin[:]) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,tree_OperatorBuffer_runs); self.len=self.items.len; }
fn resize(self: OperatorBuffer&, length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: OperatorBuffer&, length: i64, value: OperatorOrigin) { if length<=self.len { self.resize(length); return; } if self.ensure(length)!=TreeError.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: OperatorBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=TreeError.none; }
fn deinit(self: OperatorBuffer&) { blot_support_pooled_buffer::deinit(self,tree_OperatorBuffer_runs); self.len=0; self.failure=TreeError.none; }
struct ConversionBuffer { storage: TypeConversionOrigin[:]=[], items: TypeConversionOrigin[:]=[], len: i64=0, failure: TreeError=TreeError.none }
reusable[] var tree_ConversionBuffer_runs: TypeConversionOrigin[>..]=[];
var inactive_ConversionBuffer: ConversionBuffer=ConversionBuffer {..};
fn ensure(self: ConversionBuffer&, minimum: i64) -> TreeError { if self.failure!=TreeError.none { return self.failure; } self.failure=blot_support_pooled_buffer::ensure(self,minimum,tree_ConversionBuffer_runs); return self.failure; }
fn push(self: ConversionBuffer&, value: TypeConversionOrigin) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,tree_ConversionBuffer_runs); self.len=self.items.len; }
fn append(self: ConversionBuffer&, values: const TypeConversionOrigin[:]) { if self.failure!=TreeError.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,tree_ConversionBuffer_runs); self.len=self.items.len; }
fn resize(self: ConversionBuffer&, length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: ConversionBuffer&, length: i64, value: TypeConversionOrigin) { if length<=self.len { self.resize(length); return; } if self.ensure(length)!=TreeError.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: ConversionBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=TreeError.none; }
fn deinit(self: ConversionBuffer&) { blot_support_pooled_buffer::deinit(self,tree_ConversionBuffer_runs); self.len=0; self.failure=TreeError.none; }
struct TreeState { owner_id: u64=0, generation: u64=0,
    nodes: NodeBuffer=NodeBuffer {..},
    spans: SpanBuffer=SpanBuffer {..},
    extra: WordBuffer=WordBuffer {..},
    roots: WordBuffer=WordBuffer {..},
    runtime_names: NameBuffer=NameBuffer {..},
    constant_names: NameBuffer=NameBuffer {..},
    declaration_traits: TraitsBuffer=TraitsBuffer {..},
    declaration_nodes: DeclarationBuffer=DeclarationBuffer {..},
    diagnostics: DiagnosticBuffer=DiagnosticBuffer {..},
    operator_origins: OperatorBuffer=OperatorBuffer {..},
    type_conversion_origins: ConversionBuffer=ConversionBuffer {..},
}
reusable var tree_states: TreeState[>..]=[];
var next_tree_generation: u64=1;
struct Tree {
    owner_id: u64=0, lease: u32=0, generation: u64=0, has_typed_staging: bool=false, has_numeric_proofs: bool=false,
    nodes: NodeBuffer&=inactive_NodeBuffer,
    spans: SpanBuffer&=inactive_SpanBuffer,
    extra: WordBuffer&=inactive_WordBuffer,
    roots: WordBuffer&=inactive_WordBuffer,
    runtime_names: NameBuffer&=inactive_NameBuffer,
    constant_names: NameBuffer&=inactive_NameBuffer,
    declaration_traits: TraitsBuffer&=inactive_TraitsBuffer,
    declaration_nodes: DeclarationBuffer&=inactive_DeclarationBuffer,
    diagnostics: DiagnosticBuffer&=inactive_DiagnosticBuffer,
    operator_origins: OperatorBuffer&=inactive_OperatorBuffer,
    type_conversion_origins: ConversionBuffer&=inactive_ConversionBuffer,
}
fn valid(self: const Tree&) -> bool { return self.lease!=0 && self.owner_id!=0 && self.lease-1<tree_states.len && tree_states[self.lease-1].owner_id==self.owner_id && tree_states[self.lease-1].generation==self.generation; }
fn initPooled() -> Tree,TreeError {
    if next_tree_generation==0xffffffffffffffff || tree_states.len>=0xffffffff { return Tree {..},TreeError.out_of_memory; }
    let generation=next_tree_generation; next_tree_generation++;
    let owner=blot_native::fresh_owner_id(); let index=tree_states.alloc_index(TreeState {owner_id:owner,generation:generation, ..});
    let state: TreeState&=tree_states[index];
    var tree=Tree {owner_id:owner,lease:(index+1) as u32,generation:generation,
        nodes:state.nodes,
        spans:state.spans,
        extra:state.extra,
        roots:state.roots,
        runtime_names:state.runtime_names,
        constant_names:state.constant_names,
        declaration_traits:state.declaration_traits,
        declaration_nodes:state.declaration_nodes,
        diagnostics:state.diagnostics,
        operator_origins:state.operator_origins,
        type_conversion_origins:state.type_conversion_origins,
     ..};
    tree.nodes.push(Node {..}); tree.spans.push(Span {..});
    let error=tree.failure(); if error!=TreeError.none { tree.deinit(); return Tree {..},error; }
    return tree,TreeError.none;
}
fn init() -> Tree,TreeError { return initPooled(); }
fn failure(self: const Tree&) -> TreeError {
    assert(self.valid());
    if self.nodes.failure!=TreeError.none { return self.nodes.failure; }
    if self.spans.failure!=TreeError.none { return self.spans.failure; }
    if self.extra.failure!=TreeError.none { return self.extra.failure; }
    if self.roots.failure!=TreeError.none { return self.roots.failure; }
    if self.runtime_names.failure!=TreeError.none { return self.runtime_names.failure; }
    if self.constant_names.failure!=TreeError.none { return self.constant_names.failure; }
    if self.declaration_traits.failure!=TreeError.none { return self.declaration_traits.failure; }
    if self.declaration_nodes.failure!=TreeError.none { return self.declaration_nodes.failure; }
    if self.diagnostics.failure!=TreeError.none { return self.diagnostics.failure; }
    if self.operator_origins.failure!=TreeError.none { return self.operator_origins.failure; }
    if self.type_conversion_origins.failure!=TreeError.none { return self.type_conversion_origins.failure; }
    return TreeError.none;
}
fn deinit(self: Tree&) {
    if self.lease==0 { return; } assert(self.valid());
    self.nodes.deinit();
    self.spans.deinit();
    self.extra.deinit();
    self.roots.deinit();
    self.runtime_names.deinit();
    self.constant_names.deinit();
    self.declaration_traits.deinit();
    self.declaration_nodes.deinit();
    self.diagnostics.deinit();
    self.operator_origins.deinit();
    self.type_conversion_origins.deinit();
    let index=self.lease-1; tree_states[index].owner_id=0; tree_states.free(index); self=Tree {..};
}
fn node(tree: const Tree&, id: Id) -> Node { return tree.nodes.items[id]; }
fn span(tree: const Tree&, id: Id) -> Span { return tree.spans.items[id]; }
fn declaration_nodes(tree: const Tree&, root: Id) -> List, bool {
 for owner in tree.declaration_nodes.items {
  if owner.root != root { continue; }
  if owner.first == 0 || owner.first >= owner.end || owner.end > tree.nodes.len || root < owner.first || root >= owner.end { return List {..}, false; }
  return List {owner.first, owner.end-owner.first, ..}, true;
 }
 return List {..}, false;
}
fn declaration_traits(tree: const Tree&, id: Id) -> DeclarationTraits {
 var lo = 0; var hi = tree.declaration_traits.len;
 while lo < hi { let mid = lo + (hi-lo)/2; let v = tree.declaration_traits.items[mid]; if v.declaration < id { lo = mid+1; } else { hi = mid; } }
 if lo < tree.declaration_traits.len && tree.declaration_traits.items[lo].declaration == id { return tree.declaration_traits.items[lo]; }
 return DeclarationTraits { declaration: id , ..};
}
fn find_name(items: const RuntimeName[:], id: Id) -> u32, bool {
 var lo = 0; var hi = items.len;
 while lo < hi { let mid = lo+(hi-lo)/2; if items[mid].declaration < id { lo = mid+1; } else { hi = mid; } }
 if lo < items.len && items[lo].declaration == id { return items[lo].point, true; }
 return 0, false;
}
fn runtime_name_point(tree: const Tree&, id: Id) -> u32, bool { return find_name(tree.runtime_names.items, id); }
fn value_name_point(tree: const Tree&, id: Id) -> u32, bool {
 let p, found = runtime_name_point(tree,id); if found { return p,true; }
 return find_name(tree.constant_names.items,id);
}
fn numeric_fault(tree: const Tree&, id: Id) -> NumericFault {
 let n = node(tree,id); var actual = blot_parse_token::float;
 if n.a == numericcode_integer_range { actual = blot_parse_token::integer; }
 return NumericFault {id, n.a, Span {n.b,n.c, ..}, actual, ..};
}
fn type_conversion_origin(tree: const Tree&, id: Id) -> u32 {
 var point = span(tree,id).start;
 for origin in tree.type_conversion_origins.items { if origin.node == id && origin.point < point { point = origin.point; } }
 return point;
}
fn list(tree: const Tree&, range: List) -> const u32[:] { return tree.extra.items[range.start..range.start+range.len]; }
fn children(tree: const Tree&, id: Id) -> const Id[:] {
 let n=node(tree,id);
 if n.tag == tag_record { return list(tree,List {n.b,n.c, ..}); }
 if n.tag == tag_product || n.tag == tag_array || n.tag == tag_block || n.tag == tag_constructors || n.tag == tag_effect_operations || n.tag == tag_pattern_product || n.tag == tag_pattern_record || n.tag == tag_pattern_row || n.tag == tag_type_product || n.tag == tag_type_array || n.tag == tag_type_record { return list(tree,List {n.a,n.b, ..}); }
 return tree.extra.items[..0];
}
fn quantifier_predicates(tree: const Tree&, id: Id) -> Id { return tree.extra.items[node(tree,id).c+1]; }
fn value_decl(tree: const Tree&, id: Id) -> ValueDecl {
 let n=node(tree,id); let x=tree.extra.items[n.c..n.c+9];
 return ValueDecl {n.a,n.b,x[0],x[1],x[2]==1,(x[7]&1)!=0,List {x[3],x[4], ..},x[8],List {x[5],x[6], ..}, ..};
}
fn implementation(tree: const Tree&, id: Id) -> ImplementationDecl {
 let n=node(tree,id); let x=tree.extra.items[n.c..n.c+6]; let members=node(tree,n.b);
 return ImplementationDecl {n.a,List {x[0],x[1], ..},x[2],List {members.a,members.b, ..},List {x[3],x[4], ..},x[5], ..};
}
fn parameter(tree: const Tree&, id: Id) -> Parameter {
 let n=node(tree,id); let x=tree.extra.items[n.c..n.c+4];
 return Parameter {n.a,n.b,(x[0]&1)!=0,(x[0]&2)!=0,(x[0]&4)!=0,List {x[1],x[2], ..},x[3], ..};
}
fn binding(tree: const Tree&, id: Id) -> Binding {
 let n=node(tree,id); let x=tree.extra.items[n.c..n.c+5];
 return Binding {n.a,n.b,x[0],List {x[1],x[2], ..},x[4],x[3], ..};
}
fn import_decl(tree: const Tree&, id: Id) -> ImportDecl {
 let n=node(tree,id); let x=tree.extra.items[n.c..n.c+6];
 return ImportDecl {n.a,x[1],List {n.b,x[0], ..},Span {x[2],x[3], ..},Span {x[4],x[5], ..}, ..};
}
fn import_binding(tree: const Tree&, id: Id) -> ImportBinding { let n=node(tree,id); return ImportBinding {n.a,n.b, ..}; }
fn fixity(tree: const Tree&, id: Id) -> Fixity {
 let n=node(tree,id); let x=tree.extra.items[n.c..n.c+3]; var attrs=List {..}; var literal: Id=0;
 if (x[2]&2)!=0 { attrs=List {tree.extra.items[n.c+3],tree.extra.items[n.c+4], ..}; }
 if (x[2]&4)!=0 { literal=tree.extra.items[n.c+5]; }
 return Fixity {n.a,n.b,x[0],x[1],(x[2]&1)!=0,attrs,literal, ..};
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
