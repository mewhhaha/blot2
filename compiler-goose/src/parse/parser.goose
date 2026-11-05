// Source contract: compiler/src/parse/parser.zig. Recursive descent and flat
// operator stack; unsupported checker constructs remain grammar-valid syntax.
namespace blot_parse_parser;
import .ast;
import .token;
import .lexer;
import .symbols;
import support.error;
import support.pooled_buffer;
import check.numeric_proof_terms;
import check.typed_staging;
type Id= u32;
type Tag=blot_parse_token::Tag;
type Error=blot_error::Error;
type Tree=blot_parse_ast::Tree;
type Span=blot_parse_ast::Span;
type List=blot_parse_ast::List;
type Token=blot_parse_token::Token;
type Symbol=blot_parse_symbols::Symbol;
struct Fixity { symbol: Symbol, precedence: u32, association: u32, named: bool, inherited: bool=false }
struct InheritedFixity { operator: Symbol, precedence: u32, association: u32, named: bool }
struct Operator { symbol: Symbol, precedence: u32, association: u32, span: Span, known: bool, named: bool, application: bool=false }
struct Where { predicates: List=List {}, node: Id=0 }
struct LambdaParameter { node: Id, pattern: Id, name: Symbol, start: u32 }
struct Qualifier { kind: u32, name: Symbol=0, value: Id, start: u32 }
struct Parser {
 source: const u8[:], tokens: const Token[:], pool: blot_parse_symbols::Pool&, tree: Tree&,
 fixities: Fixity[>..<]&, index: i64=0, expression_end: i64=0x7fffffffffffffff,
 depth: i64=0, declaration_origin: Span=Span {}, collection_names: u32=0,
 failure: Error=Error.none
}
fn current(p: Parser&) -> Token {
 if p.index>=p.expression_end { return Token {t_eof,p.tokens[p.index].start,p.tokens[p.index].start}; }
 if p.index<p.tokens.len { return p.tokens[p.index]; }
 return Token {t_eof,p.source.len as u32,p.source.len as u32};
}
fn at(p: Parser&,tag: Tag) -> bool { return current(p).tag==tag; }
fn peek(p: Parser&,offset: i64) -> Tag { if p.index+offset<p.tokens.len { return p.tokens[p.index+offset].tag; } return t_eof; }
fn text(p: Parser&,t: Token) -> const u8[:] { return p.source[t.start..t.end]; }
fn word(p: Parser&,bytes: const u8[:]) -> bool { return text(p,current(p))==bytes; }
fn advance(p: Parser&) -> Token { let t=current(p); if p.failure==Error.none&&p.index<p.tokens.len { p.index++; } return t; }
fn eat(p: Parser&,tag: Tag) -> bool { if p.failure!=Error.none||!at(p,tag) { return false; } advance(p); return true; }
fn report(p: Parser&,code: blot_parse_ast::Code) {
 let t=current(p);
 p.tree.diagnostics.push(blot_parse_ast::Diagnostic {code:code,start:t.start,end:t.end,has_declaration_origin:true,declaration_origin:p.declaration_origin,has_actual_token:true,actual_token:t.tag});
}
fn fail(p: Parser&,code: blot_parse_ast::Code) -> Id { if p.failure==Error.none { report(p,code); p.failure=Error.syntax; } return 0; }
fn expect(p: Parser&,tag: Tag) -> Token {
 if p.failure!=Error.none { return current(p); }
 if !at(p,tag) { fail(p,c_expected_token); let i=p.tree.diagnostics.len-1; p.tree.diagnostics.items[i].has_expected_token=true; p.tree.diagnostics.items[i].expected_token=tag; return current(p); }
 return advance(p);
}
fn newlines(p: Parser&) { while eat(p,t_newline) {} }
fn recover(p: Parser&,before: i64) {
 p.failure=Error.none;
 if p.index==before&&!at(p,t_eof) { advance(p); }
 while !at(p,t_newline)&&!at(p,t_eof) { advance(p); }
 newlines(p); while eat(p,t_dedent) { newlines(p); }
}
fn enter(p: Parser&) -> bool { if p.failure!=Error.none { return false; } if p.depth>=256 { fail(p,c_nesting_limit); return false; } p.depth++; return true; }
fn add(p: Parser&,tag: u32,a: u32,b: u32,c: u32,start: u32) -> Id {
 if p.failure!=Error.none { return 0; }
 if p.tree.nodes.len>=0xffffffff { return fail(p,c_table_limit); }
 let id=p.tree.nodes.len as Id;
 p.tree.nodes.push(blot_parse_ast::Node {tag,a,b,c}); let node_error=p.tree.failure(); if node_error!=Error.none { p.failure=node_error; return 0; }
 var end=start; if p.index>0 { end=p.tokens[p.index-1].end; }
 p.tree.spans.push(Span {start,end}); return id;
}
fn numeric_failure(p: Parser&,t: Token,code: u32) -> Id { return add(p,a_numeric_error,code,t.start,t.end,t.start); }
fn integer_literal(p: Parser&,t: Token,tag: u32) -> Id {
 if p.failure!=Error.none { return 0; }
 let value,err=blot_parse_lexer::integer_value(text(p,t));
 if err==Error.integer_range { return numeric_failure(p,t,blot_parse_ast::numericcode_integer_range); }
 if err!=Error.none { return fail(p,c_invalid_literal); } return add(p,tag,value,0,0,t.start);
}
fn extra(p: Parser&,values: const u32[:]) -> u32 {
 if p.failure!=Error.none { return 0; }
 if values.len>0xffffffff-p.tree.extra.len { return fail(p,c_table_limit); }
 let start=p.tree.extra.len as u32; for v in values { p.tree.extra.push(v); } return start;
}
fn list(p: Parser&,values: const u32[:]) -> List { let start=extra(p,values); return List {start,values.len as u32}; }
fn list_node(p: Parser&,tag: u32,values: const Id[:],start: u32) -> Id { let range=list(p,values); return add(p,tag,range.start,range.len,0,start); }
fn intern(p: Parser&,bytes: const u8[:]) -> Symbol {
 if p.failure!=Error.none { return 0; }
 let symbol,err=blot_parse_symbols::intern(p.pool,bytes);
 if err==Error.symbol_limit { return fail(p,c_table_limit); }
 if err!=Error.none { p.failure=err; return 0; } return symbol;
}
fn identifier_syntax_at(p: Parser&,t: Token) -> Id {
 if p.failure!=Error.none { return 0; }
 p.tree.diagnostics.push(blot_parse_ast::Diagnostic {code:c_GPU_FRONTEND_SYNTAX_ERROR,start:p.declaration_origin.start,end:p.declaration_origin.end,has_declaration_origin:true,declaration_origin:p.declaration_origin,has_detail_span:true,detail_span:Span {t.start,t.end},has_actual_token:true,actual_token:t.tag});
 p.failure=Error.syntax; return 0;
}
fn identifier_syntax(p: Parser&) -> Id { return identifier_syntax_at(p,current(p)); }
fn identifier(p: Parser&) -> Symbol {
 if p.failure!=Error.none { return 0; } let t=current(p);
 if t.tag!=t_identifier&&t.tag!=t_type_identifier { return fail(p,c_expected_token); }
 advance(p); return intern(p,text(p,t));
}
fn lower_identifier(p: Parser&) -> Symbol { if at(p,t_type_identifier)||at(p,t_kw_true)||at(p,t_kw_false) { return identifier_syntax(p); } return identifier(p); }
fn type_identifier(p: Parser&) -> Symbol {
 if at(p,t_identifier)||at(p,t_kw_true)||at(p,t_kw_false) { return identifier_syntax(p); }
 let t=expect(p,t_type_identifier); let name=intern(p,text(p,t)); if at(p,t_dot) { return identifier_syntax(p); } return name;
}
fn qualified(p: Parser&) -> Symbol {
 let first=current(p); let name=identifier(p);
 if p.failure!=Error.none||!at(p,t_dot)||(peek(p,1)!=t_identifier&&peek(p,1)!=t_type_identifier) { return name; }
 var bytes=Scratchu8Buffer {};  for c in text(p,first) { bytes.push(c); }
 while p.failure==Error.none&&at(p,t_dot)&&(peek(p,1)==t_identifier||peek(p,1)==t_type_identifier) {
  advance(p); let t=advance(p); intern(p,text(p,t)); bytes.push('.'); for c in text(p,t) { bytes.push(c); }
 }
 let __cleanup_result_1_0: Symbol = intern(p,bytes.items); bytes.deinit(); return __cleanup_result_1_0;
 bytes.deinit(); }
fn constructor_pattern_name(p: Parser&) -> Symbol {
 let name=qualified(p); if p.failure!=Error.none { return 0; }
 if p.tokens[p.index-1].tag!=t_type_identifier { return identifier_syntax_at(p,p.tokens[p.index-1]); } return name;
}
fn string_symbol(p: Parser&) -> Symbol {
 let t=expect(p,t_string); if p.failure!=Error.none { return 0; }
 let raw=text(p,t); var bytes=Scratchu8Buffer {};  var i=1;
 while i+1<raw.len {
  var ch=raw[i]; if ch=='\\' {
   i++; let e=raw[i]; if e=='n' { ch='\n'; } else if e=='r' { ch='\r'; } else if e=='t' { ch='\t'; } else if e=='"'||e=='\\' { ch=e; } else { let __cleanup_result_2_0: Symbol = fail(p,c_invalid_literal); bytes.deinit(); return __cleanup_result_2_0; }
  }
  bytes.push(ch); i++;
 }
 let __cleanup_result_3_0: Symbol = intern(p,bytes.items); bytes.deinit(); return __cleanup_result_3_0;
 bytes.deinit(); }
fn declaration(p: Parser&,declarations_seen: bool,body_declarations_seen: bool) -> Id {
 var private=false; var is_opaque=false;
 if word(p,"entry")&&peek(p,1)==t_identifier&&text(p,p.tokens[p.index+1])=="private" { advance(p); let t=current(p); p.declaration_origin=Span {t.start,t.end}; return fail(p,c_unexpected_token); }
 if word(p,"private") { private=true; advance(p); if word(p,"private") { let t=current(p); p.declaration_origin=Span {t.start,t.end}; return fail(p,c_unexpected_token); } }
 if word(p,"opaque")&&peek(p,1)==t_kw_type { is_opaque=true; advance(p); }
 if word(p,"export")&&peek(p,1)==t_l_brace { if private||is_opaque { return fail(p,c_unexpected_token); } return import_decl(p,true); }
 let id=declaration_body(p,declarations_seen,body_declarations_seen,is_opaque); if p.failure!=Error.none { return 0; }
 if private||is_opaque { let tag=p.tree.node(id).tag; if tag==a_import_decl||tag==a_fixity_decl { return fail(p,c_unexpected_token); } p.tree.declaration_traits.push(blot_parse_ast::DeclarationTraits {id,private,is_opaque}); }
 return id;
}
fn declaration_body(p: Parser&,declarations_seen: bool,body_declarations_seen: bool,is_opaque: bool) -> Id {
 let first=current(p); p.declaration_origin=Span {first.start,first.end}; p.collection_names=0; let start=first.start;
 if at(p,t_kw_import) { if declarations_seen { return fail(p,c_unexpected_token); } return import_decl(p,false); }
 var attributes=ScratchIdBuffer {}; 
 while p.failure==Error.none&&at(p,t_at) { let point=current(p).start; eat(p,t_at); expect(p,t_l_bracket); let body=expression(p); expect(p,t_r_bracket); attributes.push(add(p,a_attribute,body,0,0,point)); newlines(p); }
 let attrs=list(p,attributes.items); if p.failure!=Error.none { let __cleanup_result_4_0: Id = 0; attributes.deinit(); return __cleanup_result_4_0; }
 if at(p,t_kw_infixl)||at(p,t_kw_infixr)||at(p,t_kw_infix) { let __cleanup_result_5_0: Id = fixity_decl(p,attrs,start); attributes.deinit(); return __cleanup_result_5_0; }
 if word(p,"impl") { if is_opaque||attrs.len!=0 { let __cleanup_result_6_0: Id = fail(p,c_unexpected_token); attributes.deinit(); return __cleanup_result_6_0; } let __cleanup_result_7_0: Id = implementation_declaration(p,start); attributes.deinit(); return __cleanup_result_7_0; }
 if at(p,t_kw_type)||at(p,t_kw_data) { let __cleanup_result_8_0: Id = type_declaration(p,attrs,start,is_opaque); attributes.deinit(); return __cleanup_result_8_0; }
 if eat(p,t_kw_effect) { let name=qualified(p); expect(p,t_colon); let signature=type_expression(p); let __cleanup_result_9_0: Id = add(p,a_effect_decl,name,signature,extra(p,[attrs.start,attrs.len]),start); attributes.deinit(); return __cleanup_result_9_0; }
 var modifier: Symbol=0; var flags: u32=0;
 if (at(p,t_type_identifier)||at(p,t_kw_true)||at(p,t_kw_false))&&(peek(p,1)==t_kw_const||peek(p,1)==t_kw_let) { let __cleanup_result_10_0: Id = identifier_syntax(p); attributes.deinit(); return __cleanup_result_10_0; }
 if at(p,t_identifier)&&(peek(p,1)==t_kw_const||peek(p,1)==t_kw_let) { if word(p,"entry") { flags=1; } modifier=lower_identifier(p); }
 var runtime: u32=0; if eat(p,t_kw_const) {} else if eat(p,t_kw_let) { runtime=1; } else { let __cleanup_result_11_0: Id = fail(p,c_expected_token); attributes.deinit(); return __cleanup_result_11_0; }
 let name_point=current(p).start; let name=qualified(p); var annotation: Id=0; if eat(p,t_colon) { annotation=type_expression(p); }
 let constraints=where_clause(p); expect(p,t_equal); let body=expression(p);
 let value=add(p,a_value_decl,name,body,extra(p,[annotation,modifier,runtime,constraints.predicates.start,constraints.predicates.len,attrs.start,attrs.len,flags,constraints.node]),start);
 if p.failure!=Error.none { let __cleanup_result_12_0: Id = 0; attributes.deinit(); return __cleanup_result_12_0; }
 if runtime!=0 { p.tree.runtime_names.push(blot_parse_ast::RuntimeName {value,name_point}); } else { p.tree.constant_names.push(blot_parse_ast::RuntimeName {value,name_point}); } let __cleanup_result_13_0: Id = value; attributes.deinit(); return __cleanup_result_13_0;
 attributes.deinit(); }
fn import_decl(p: Parser&,forwarding: bool) -> Id {
 let start=current(p).start; if forwarding { advance(p); } else { expect(p,t_kw_import); }
 var bindings=ScratchIdBuffer {};  var name_space: Symbol=0; var namespace_span=Span {start,start};
 if !forwarding&&eat(p,t_star) { expect(p,t_kw_as); let t=current(p); name_space=lower_identifier(p); namespace_span=Span {t.start,t.end}; }
 else {
  expect(p,t_l_brace);
  while p.failure==Error.none&&!at(p,t_r_brace) { let point=current(p).start; let name=identifier(p); var alias=name; if eat(p,t_kw_as) { alias=identifier(p); } bindings.push(add(p,a_import_binding,name,alias,0,point)); if !eat(p,t_comma) { break; } }
  expect(p,t_r_brace);
 }
 if !eat(p,t_kw_from) { if !word(p,"from") { let __cleanup_result_14_0: Id = fail(p,c_expected_token); bindings.deinit(); return __cleanup_result_14_0; } advance(p); }
 let path_token=current(p); let path=string_symbol(p); let range=list(p,bindings.items); var tag=a_import_decl; if forwarding { tag=a_export_decl; }
 let __cleanup_result_15_0: Id = add(p,tag,path,range.start,extra(p,[range.len,name_space,path_token.start,path_token.end,namespace_span.start,namespace_span.end]),start); bindings.deinit(); return __cleanup_result_15_0;
 bindings.deinit(); }
fn fixity_decl(p: Parser&,attrs: List,start: u32) -> Id {
 let head=advance(p).tag; var association: u32=2; if head==t_kw_infixl { association=0; } else if head==t_kw_infixr { association=1; }
 let literal=expect(p,t_integer); if p.failure!=Error.none { return 0; }
 var literal_error: Id=0; let raw_precedence,err=blot_parse_lexer::integer_value(text(p,literal)); var precedence=raw_precedence;
 if err==Error.integer_range { literal_error=numeric_failure(p,literal,blot_parse_ast::numericcode_integer_range); precedence=0; }
 else if err!=Error.none { return fail(p,c_invalid_literal); }
 var symbol: Symbol=0; var target: Symbol=0; var target_span=Span {}; var named=false;
 if eat(p,t_backtick) { named=true; let t=current(p); target_span=Span {t.start,t.end}; symbol=qualified(p); target=symbol; expect(p,t_backtick); }
 else { expect(p,t_l_paren); let op=advance(p); if !operator_tag(op.tag)||op.tag==t_kw_and||op.tag==t_kw_or { return fail(p,c_expected_token); } symbol=intern(p,text(p,op)); expect(p,t_r_paren); expect(p,t_equal); let t=current(p); target_span=Span {t.start,t.end}; target=qualified(p); }
 if p.failure!=Error.none { return 0; }
 var power=precedence; if power>255 { power=255; } var replaced=false;
 for i in 0..p.fixities.len { if p.fixities[i].symbol==symbol&&p.fixities[i].named==named { p.fixities[i]=Fixity {symbol,power,association,named,false}; replaced=true; break; } }
 if !replaced { p.fixities.push(Fixity {symbol,power,association,named,false}); }
 var flags: u32=0; if named { flags|=1; } if attrs.len!=0 { flags|=2; } if literal_error!=0 { flags|=4; }
 let metadata=extra(p,[precedence,association,flags,attrs.start,attrs.len]); if literal_error!=0 { extra(p,[literal_error]); }
 let id=add(p,a_fixity_decl,symbol,target,metadata,start); if p.failure==Error.none { p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:id,span:target_span}); } return id;
}

let t_eof=blot_parse_token::eof;
let t_identifier=blot_parse_token::identifier;
let t_type_identifier=blot_parse_token::type_identifier;
let t_integer=blot_parse_token::integer;
let t_float=blot_parse_token::float;
let t_string=blot_parse_token::string;
let t_intrinsic=blot_parse_token::intrinsic;
let t_symbol=blot_parse_token::symbol;
let t_comment=blot_parse_token::comment;
let t_l_paren=blot_parse_token::l_paren;
let t_r_paren=blot_parse_token::r_paren;
let t_l_bracket=blot_parse_token::l_bracket;
let t_r_bracket=blot_parse_token::r_bracket;
let t_l_brace=blot_parse_token::l_brace;
let t_r_brace=blot_parse_token::r_brace;
let t_comma=blot_parse_token::comma;
let t_dot=blot_parse_token::dot;
let t_selector=blot_parse_token::selector;
let t_dot_dot=blot_parse_token::dot_dot;
let t_colon=blot_parse_token::colon;
let t_colon_equal=blot_parse_token::colon_equal;
let t_arrow=blot_parse_token::arrow;
let t_fat_arrow=blot_parse_token::fat_arrow;
let t_left_arrow=blot_parse_token::left_arrow;
let t_hash=blot_parse_token::hash;
let t_at=blot_parse_token::at;
let t_ellipsis=blot_parse_token::ellipsis;
let t_backtick=blot_parse_token::backtick;
let t_dollar=blot_parse_token::dollar;
let t_star=blot_parse_token::star;
let t_caret=blot_parse_token::caret;
let t_pipe=blot_parse_token::pipe;
let t_bang=blot_parse_token::bang;
let t_equal=blot_parse_token::equal;
let t_kw_import=blot_parse_token::kw_import;
let t_kw_as=blot_parse_token::kw_as;
let t_kw_const=blot_parse_token::kw_const;
let t_kw_let=blot_parse_token::kw_let;
let t_kw_type=blot_parse_token::kw_type;
let t_kw_is=blot_parse_token::kw_is;
let t_kw_data=blot_parse_token::kw_data;
let t_kw_effect=blot_parse_token::kw_effect;
let t_kw_infixl=blot_parse_token::kw_infixl;
let t_kw_infixr=blot_parse_token::kw_infixr;
let t_kw_infix=blot_parse_token::kw_infix;
let t_kw_func=blot_parse_token::kw_func;
let t_kw_if=blot_parse_token::kw_if;
let t_kw_then=blot_parse_token::kw_then;
let t_kw_else=blot_parse_token::kw_else;
let t_kw_do=blot_parse_token::kw_do;
let t_kw_case=blot_parse_token::kw_case;
let t_kw_of=blot_parse_token::kw_of;
let t_kw_for=blot_parse_token::kw_for;
let t_kw_in=blot_parse_token::kw_in;
let t_kw_ever=blot_parse_token::kw_ever;
let t_kw_use=blot_parse_token::kw_use;
let t_kw_return=blot_parse_token::kw_return;
let t_kw_yield=blot_parse_token::kw_yield;
let t_kw_break=blot_parse_token::kw_break;
let t_kw_continue=blot_parse_token::kw_continue;
let t_kw_complete=blot_parse_token::kw_complete;
let t_kw_true=blot_parse_token::kw_true;
let t_kw_false=blot_parse_token::kw_false;
let t_kw_and=blot_parse_token::kw_and;
let t_kw_or=blot_parse_token::kw_or;
let t_kw_from=blot_parse_token::kw_from;
let t_kw_where=blot_parse_token::kw_where;
let t_private_from=blot_parse_token::private_from;
let t_private_where=blot_parse_token::private_where;
let t_newline=blot_parse_token::newline;
let t_indent=blot_parse_token::indent;
let t_dedent=blot_parse_token::dedent;

let a_invalid=blot_parse_ast::tag_invalid;
let a_value_decl=blot_parse_ast::tag_value_decl;
let a_import_decl=blot_parse_ast::tag_import_decl;
let a_export_decl=blot_parse_ast::tag_export_decl;
let a_import_binding=blot_parse_ast::tag_import_binding;
let a_data_decl=blot_parse_ast::tag_data_decl;
let a_type_alias_decl=blot_parse_ast::tag_type_alias_decl;
let a_contract_decl=blot_parse_ast::tag_contract_decl;
let a_contract_type_member=blot_parse_ast::tag_contract_type_member;
let a_contract_value_member=blot_parse_ast::tag_contract_value_member;
let a_implementation_decl=blot_parse_ast::tag_implementation_decl;
let a_effect_decl=blot_parse_ast::tag_effect_decl;
let a_effect_type_decl=blot_parse_ast::tag_effect_type_decl;
let a_fixity_decl=blot_parse_ast::tag_fixity_decl;
let a_attribute=blot_parse_ast::tag_attribute;
let a_constraint=blot_parse_ast::tag_constraint;
let a_where_clause=blot_parse_ast::tag_where_clause;
let a_constructors=blot_parse_ast::tag_constructors;
let a_effect_operations=blot_parse_ast::tag_effect_operations;
let a_effect_operation=blot_parse_ast::tag_effect_operation;
let a_name=blot_parse_ast::tag_name;
let a_intrinsic=blot_parse_ast::tag_intrinsic;
let a_integer=blot_parse_ast::tag_integer;
let a_float=blot_parse_ast::tag_float;
let a_string=blot_parse_ast::tag_string;
let a_boolean=blot_parse_ast::tag_boolean;
let a_unit=blot_parse_ast::tag_unit;
let a_lambda=blot_parse_ast::tag_lambda;
let a_parameter=blot_parse_ast::tag_parameter;
let a_apply=blot_parse_ast::tag_apply;
let a_group=blot_parse_ast::tag_group;
let a_unary=blot_parse_ast::tag_unary;
let a_binary=blot_parse_ast::tag_binary;
let a_infix_chain=blot_parse_ast::tag_infix_chain;
let a_operator_tail=blot_parse_ast::tag_operator_tail;
let a_product=blot_parse_ast::tag_product;
let a_array=blot_parse_ast::tag_array;
let a_block=blot_parse_ast::tag_block;
let a_record=blot_parse_ast::tag_record;
let a_field=blot_parse_ast::tag_field;
let a_selector=blot_parse_ast::tag_selector;
let a_constructor_ref=blot_parse_ast::tag_constructor_ref;
let a_type_witness=blot_parse_ast::tag_type_witness;
let a_field_access=blot_parse_ast::tag_field_access;
let a_index_access=blot_parse_ast::tag_index_access;
let a_let_stmt=blot_parse_ast::tag_let_stmt;
let a_rebind_stmt=blot_parse_ast::tag_rebind_stmt;
let a_use_stmt=blot_parse_ast::tag_use_stmt;
let a_iterator_bind=blot_parse_ast::tag_iterator_bind;
let a_function_return_stmt=blot_parse_ast::tag_function_return_stmt;
let a_return_stmt=blot_parse_ast::tag_return_stmt;
let a_yield_stmt=blot_parse_ast::tag_yield_stmt;
let a_break_stmt=blot_parse_ast::tag_break_stmt;
let a_continue_stmt=blot_parse_ast::tag_continue_stmt;
let a_if_expr=blot_parse_ast::tag_if_expr;
let a_if_stmt=blot_parse_ast::tag_if_stmt;
let a_if_let_stmt=blot_parse_ast::tag_if_let_stmt;
let a_for_stmt=blot_parse_ast::tag_for_stmt;
let a_range_stmt=blot_parse_ast::tag_range_stmt;
let a_forever_stmt=blot_parse_ast::tag_forever_stmt;
let a_case_expr=blot_parse_ast::tag_case_expr;
let a_case_arm=blot_parse_ast::tag_case_arm;
let a_pattern_row=blot_parse_ast::tag_pattern_row;
let a_request_case=blot_parse_ast::tag_request_case;
let a_request_arm=blot_parse_ast::tag_request_arm;
let a_pattern_name=blot_parse_ast::tag_pattern_name;
let a_pattern_integer=blot_parse_ast::tag_pattern_integer;
let a_pattern_boolean=blot_parse_ast::tag_pattern_boolean;
let a_pattern_product=blot_parse_ast::tag_pattern_product;
let a_pattern_constructor=blot_parse_ast::tag_pattern_constructor;
let a_pattern_record=blot_parse_ast::tag_pattern_record;
let a_pattern_field=blot_parse_ast::tag_pattern_field;
let a_pattern_value=blot_parse_ast::tag_pattern_value;
let a_type_name=blot_parse_ast::tag_type_name;
let a_type_apply=blot_parse_ast::tag_type_apply;
let a_type_function=blot_parse_ast::tag_type_function;
let a_type_effect=blot_parse_ast::tag_type_effect;
let a_type_product=blot_parse_ast::tag_type_product;
let a_type_array=blot_parse_ast::tag_type_array;
let a_type_record=blot_parse_ast::tag_type_record;
let a_type_field=blot_parse_ast::tag_type_field;
let a_effect_row=blot_parse_ast::tag_effect_row;
let a_numeric_error=blot_parse_ast::tag_numeric_error;
let a_type_binder=blot_parse_ast::tag_type_binder;
let a_type_usage=blot_parse_ast::tag_type_usage;
let a_type_forall=blot_parse_ast::tag_type_forall;
let a_type_exists=blot_parse_ast::tag_type_exists;
let a_quantified_binder=blot_parse_ast::tag_quantified_binder;
let a_package_pack=blot_parse_ast::tag_package_pack;
let a_package_unpack=blot_parse_ast::tag_package_unpack;
let a_type_code=blot_parse_ast::tag_type_code;
let a_type_descriptor=blot_parse_ast::tag_type_descriptor;
let a_task_region=blot_parse_ast::tag_task_region;
let c_expected_token=blot_parse_ast::code_expected_token;
let c_expected_expression=blot_parse_ast::code_expected_expression;
let c_expected_type=blot_parse_ast::code_expected_type;
let c_expected_pattern=blot_parse_ast::code_expected_pattern;
let c_unexpected_token=blot_parse_ast::code_unexpected_token;
let c_task_spark_scope=blot_parse_ast::code_task_spark_scope;
let c_task_spark_call=blot_parse_ast::code_task_spark_call;
let c_task_receive_tuple=blot_parse_ast::code_task_receive_tuple;
let c_invalid_literal=blot_parse_ast::code_invalid_literal;
let c_operator_associativity=blot_parse_ast::code_operator_associativity;
let c_fixity_order=blot_parse_ast::code_fixity_order;
let c_duplicate_fixity=blot_parse_ast::code_duplicate_fixity;
let c_invalid_precedence=blot_parse_ast::code_invalid_precedence;
let c_nesting_limit=blot_parse_ast::code_nesting_limit;
let c_table_limit=blot_parse_ast::code_table_limit;
let c_private_marker=blot_parse_ast::code_private_marker;
let c_GPU_FRONTEND_SYNTAX_ERROR=blot_parse_ast::code_GPU_FRONTEND_SYNTAX_ERROR;
let c_function_return_required=blot_parse_ast::code_function_return_required;
fn type_declaration(p: Parser&,attrs: List,start: u32,is_opaque: bool) -> Id {
 let old_data=eat(p,t_kw_data); if !old_data { expect(p,t_kw_type); }
 let name=type_identifier(p); var params=ScratchIdBuffer {}; 
 if type_atom_tag(current(p).tag) { params.push(type_atom(p)); }
 while p.failure==Error.none&&eat(p,t_fat_arrow) { expect(p,t_kw_type); params.push(type_atom(p)); }
 if !old_data&&eat(p,t_equal) {
  let body=type_expression(p); let range=list(p,params.items);
  if is_opaque { let constructor=add(p,a_constructor_ref,name,body,0,start); let constructors=list_node(p,a_constructors,[constructor],start); let __cleanup_result_16_0: Id = add(p,a_data_decl,name,constructors.items,extra(p,[range.start,range.len,attrs.start,attrs.len]),start); params.deinit(); return __cleanup_result_16_0; }
  let __cleanup_result_17_0: Id = add(p,a_type_alias_decl,name,body,extra(p,[range.start,range.len,attrs.start,attrs.len]),start); params.deinit(); return __cleanup_result_17_0;
 }
 if is_opaque { let __cleanup_result_18_0: Id = fail(p,c_expected_token); params.deinit(); return __cleanup_result_18_0; }
 var effect=false;
 if !old_data {
  expect(p,t_kw_is);
  if word(p,"contract") { advance(p); expect(p,t_equal); let body=predicate_body(p,current(p).start,true); let range=list(p,params.items); let __cleanup_result_19_0: Id = add(p,a_contract_decl,name,body.node,extra(p,[range.start,range.len,attrs.start,attrs.len]),start); params.deinit(); return __cleanup_result_19_0; }
  if eat(p,t_kw_effect) { effect=true; } else { expect(p,t_kw_data); }
 }
 expect(p,t_equal); var body: Id=0;
 if effect {
  if eat(p,t_l_brace) {
   var operations=ScratchIdBuffer {};  newlines(p);
   while p.failure==Error.none&&!at(p,t_r_brace) {
    let point=current(p).start; let field=lower_identifier(p); expect(p,t_colon); let ty=type_expression(p); operations.push(add(p,a_effect_operation,field,ty,0,point));
    if eat(p,t_comma) { newlines(p); continue; } if at(p,t_newline) { newlines(p); continue; } break;
   }
   expect(p,t_r_brace); body=list_node(p,a_effect_operations,operations.items,start);
   operations.deinit(); } else { body=type_expression(p); }
 } else {
  var constructors=ScratchIdBuffer {};  eat(p,t_pipe);
  while p.failure==Error.none {
   let point=expect(p,t_hash).start; let constructor=type_identifier(p); var payload: Id=0; if type_atom_tag(current(p).tag) { payload=type_expression(p); }
   constructors.push(add(p,a_constructor_ref,constructor,payload,0,point)); if !eat(p,t_pipe) { break; }
  }
  body=list_node(p,a_constructors,constructors.items,start);
  constructors.deinit(); }
 let range=list(p,params.items); var tag=a_data_decl; if effect { tag=a_effect_type_decl; }
 let __cleanup_result_20_0: Id = add(p,tag,name,body,extra(p,[range.start,range.len,attrs.start,attrs.len]),start); params.deinit(); return __cleanup_result_20_0;
 params.deinit(); }
fn implementation_declaration(p: Parser&,start: u32) -> Id {
 advance(p); let name=type_identifier(p); var parameters=ScratchIdBuffer {}; 
 if type_atom_tag(current(p).tag) { parameters.push(type_atom(p)); }
 while p.failure==Error.none&&eat(p,t_fat_arrow) { expect(p,t_kw_type); parameters.push(type_atom(p)); }
 expect(p,t_colon); let head=contract_item(p,false); let prerequisites=where_clause(p); expect(p,t_equal); let body_start=expect(p,t_l_brace).start; newlines(p); var members=ScratchIdBuffer {}; 
 while p.failure==Error.none&&!at(p,t_r_brace) {
  let member_start=current(p).start;
  if eat(p,t_kw_type) { let member=type_identifier(p); expect(p,t_equal); let ty=type_expression(p); members.push(add(p,a_contract_type_member,member,ty,0,member_start)); }
  else {
   expect(p,t_kw_const); let member=identifier(p); var annotation: Id=0; if eat(p,t_colon) { annotation=type_expression(p); } expect(p,t_equal);
   if !at(p,t_kw_func) { let __cleanup_result_21_0: Id = fail(p,c_expected_token); members.deinit(); parameters.deinit(); return __cleanup_result_21_0; }
   let value=expression(p); let method=add(p,a_value_decl,member,value,extra(p,[annotation,0,0,0,0,0,0,0,0]),member_start);
   if p.failure!=Error.none { let __cleanup_result_22_0: Id = 0; members.deinit(); parameters.deinit(); return __cleanup_result_22_0; } members.push(method); p.tree.constant_names.push(blot_parse_ast::RuntimeName {method,member_start});
  }
  if !eat(p,t_comma) { break; } newlines(p);
 }
 newlines(p); expect(p,t_r_brace); let body=list_node(p,a_where_clause,members.items,body_start); let params=list(p,parameters.items);
 let __cleanup_result_23_0: Id = add(p,a_implementation_decl,name,body,extra(p,[params.start,params.len,head,prerequisites.predicates.start,prerequisites.predicates.len,prerequisites.node]),start); members.deinit(); parameters.deinit(); return __cleanup_result_23_0;
 members.deinit(); parameters.deinit(); }
fn where_clause(p: Parser&) -> Where { let start=current(p).start; if !eat(p,t_kw_where) { return Where {}; } return predicate_body(p,start,false); }
fn predicate_body(p: Parser&,start: u32,members: bool) -> Where {
 expect(p,t_l_brace); newlines(p); var predicates=ScratchIdBuffer {}; 
 while p.failure==Error.none&&!at(p,t_r_brace) { predicates.push(contract_item(p,members)); if !eat(p,t_comma) { break; } newlines(p); }
 newlines(p); expect(p,t_r_brace); let range=list(p,predicates.items); let id=add(p,a_where_clause,range.start,range.len,0,start); let __cleanup_result_24_0: Where = Where {range,id}; predicates.deinit(); return __cleanup_result_24_0;
 predicates.deinit(); }
fn contract_item(p: Parser&,members: bool) -> Id {
 let start=current(p).start;
 if members&&eat(p,t_kw_type) { let name=type_identifier(p); var value: Id=0; if eat(p,t_equal) { value=type_expression(p); } return add(p,a_contract_type_member,name,value,0,start); }
 if members&&eat(p,t_kw_const) { let name=identifier(p); expect(p,t_colon); let ty=type_expression(p); return add(p,a_contract_value_member,name,ty,0,start); }
 let kind=qualified(p); var member: Symbol=0; if at(p,t_string) { member=string_symbol(p); }
 var args=ScratchIdBuffer {}; 
 while p.failure==Error.none&&type_atom_tag(current(p).tag) {
  let point=current(p).start; let grouped=at(p,t_l_paren); var arg=type_atom(p);
  if p.failure!=Error.none { let __cleanup_result_25_0: Id = 0; args.deinit(); return __cleanup_result_25_0; }
  if grouped&&p.tree.span(arg).start!=point { arg=add(p,a_group,arg,0,0,point); } args.push(arg);
 }
 var row: Id=0; if at(p,t_bang) { row=effect_row(p); } let range=list(p,args.items);
 let __cleanup_result_26_0: Id = add(p,a_constraint,kind,member,extra(p,[range.start,range.len,row]),start); args.deinit(); return __cleanup_result_26_0;
 args.deinit(); }
fn type_expression(p: Parser&) -> Id {
 if !enter(p) { return 0; } 
 let start=current(p).start; var parts=ScratchIdBuffer {};  parts.push(type_application(p));
 while p.failure==Error.none&&eat(p,t_arrow) { parts.push(type_application(p)); }
 var row: Id=0; if at(p,t_bang) { row=effect_row(p); } if p.failure!=Error.none { let __cleanup_result_1_0: Id = 0; { p.depth--; } let __cleanup_result_27_0: Id = __cleanup_result_1_0; parts.deinit(); return __cleanup_result_27_0; }
 var value=parts.items[parts.len-1]; var i=parts.len-1;
 while i!=0 {
  i--; let result=value; var effects: Id=0; if i==0 { effects=row; }
  value=add(p,a_type_function,parts.items[i],result,effects,p.tree.span(parts.items[i]).start); if p.failure!=Error.none { let __cleanup_result_2_0: Id = 0; { p.depth--; } let __cleanup_result_28_0: Id = __cleanup_result_2_0; parts.deinit(); return __cleanup_result_28_0; }
  var end=p.tree.span(result).end; if i==0&&row!=0 { end=p.tree.span(row).end; } p.tree.spans.items[value].end=end;
 }
 if parts.len==1&&row!=0 { let __cleanup_result_3_0: Id = add(p,a_type_effect,value,row,0,start); { p.depth--; } let __cleanup_result_29_0: Id = __cleanup_result_3_0; parts.deinit(); return __cleanup_result_29_0; } let __cleanup_result_4_0: Id = value; { p.depth--; } let __cleanup_result_30_0: Id = __cleanup_result_4_0; parts.deinit(); return __cleanup_result_30_0;
 { p.depth--; }  parts.deinit(); }
fn type_application(p: Parser&) -> Id {
 let start=current(p).start; var value=type_atom(p);
 while p.failure==Error.none&&type_atom_tag(current(p).tag) { let arg=type_atom(p); value=add(p,a_type_apply,value,arg,0,start); } return value;
}
fn type_atom(p: Parser&) -> Id {
 if !enter(p) { return 0; }  let start=current(p).start;
 if at(p,t_caret)||(at(p,t_symbol)&&text(p,current(p))=="&") {
  let link=advance(p).tag==t_caret; let view=!link&&eat(p,t_l_bracket); var storage_name: const u8[:]="@storage.Ref";
  if link { storage_name="@storage.Link"; } else if view { storage_name="@storage.View"; }
  let name=add(p,a_type_name,intern(p,storage_name),0,0,start); var element: Id=0;
  if view { element=type_expression(p); expect(p,t_r_bracket); } else { element=type_atom(p); }
  let __cleanup_result_5_0: Id = add(p,a_type_apply,name,element,0,start); { p.depth--; } return __cleanup_result_5_0;
 }
 if word(p,"code")&&peek(p,1)==t_l_bracket {
  advance(p); expect(p,t_l_bracket); let result=type_expression(p); expect(p,t_comma); if !word(p,"row") { let __cleanup_result_6_0: Id = fail(p,c_expected_type); { p.depth--; } return __cleanup_result_6_0; }
  let row_start=advance(p).start; var row: Id=0;
  if at(p,t_l_brace) { row=effect_row_body(p,row_start); } else { let tail_start=current(p).start; let tail=add(p,a_type_name,lower_identifier(p),0,0,tail_start); row=add(p,a_effect_row,0,0,tail,row_start); }
  expect(p,t_r_bracket); p.tree.has_typed_staging=true; let __cleanup_result_7_0: Id = add(p,a_type_code,result,row,0,start); { p.depth--; } return __cleanup_result_7_0;
 }
 if word(p,"descriptor")&&type_atom_tag(peek(p,1)) { advance(p); p.tree.has_typed_staging=true; let ty=type_atom(p); let __cleanup_result_8_0: Id = add(p,a_type_descriptor,ty,0,0,start); { p.depth--; } return __cleanup_result_8_0; }
 if at(p,t_intrinsic) {
  let head=advance(p); let proof,known=blot_check_numeric_proof_terms::type_name(text(p,head)); if !known { let __cleanup_result_9_0: Id = fail(p,c_expected_type); { p.depth--; } return __cleanup_result_9_0; }
  p.tree.has_numeric_proofs=true; var value=add(p,a_type_name,intern(p,text(p,head)),0,0,start);
  for i in 0..2 { let operand=proof_operand(p); value=add(p,a_type_apply,value,operand,0,start); } let __cleanup_result_10_0: Id = value; { p.depth--; } return __cleanup_result_10_0;
 }
 if at(p,t_identifier)&&peek(p,1)==t_l_bracket&&(word(p,"forall")||word(p,"exists")) { let __cleanup_result_11_0: Id = quantified_type(p); { p.depth--; } return __cleanup_result_11_0; }
 if at(p,t_identifier)&&type_atom_tag(peek(p,1)) {
  let kinds: (const u8[:])[8]=["unique","shared","borrow","borrow_mut","once","many","cleanup","concurrent"];
  for kind,index in kinds { if word(p,kind) { advance(p); var region: Symbol=0; if index==2||index==3 { region=lower_identifier(p); } let ty=type_atom(p); let __cleanup_result_12_0: Id = add(p,a_type_usage,index as u32,ty,region,start); { p.depth--; } return __cleanup_result_12_0; } }
 }
 if at(p,t_identifier)||at(p,t_type_identifier) { let __cleanup_result_13_0: Id = add(p,a_type_name,qualified(p),0,0,start); { p.depth--; } return __cleanup_result_13_0; }
 if eat(p,t_l_brace) {
  var fields=ScratchIdBuffer {}; 
  while p.failure==Error.none&&!at(p,t_r_brace) { let point=current(p).start; let name=lower_identifier(p); var value: Id=0; if eat(p,t_colon) { value=type_expression(p); } fields.push(add(p,a_type_field,name,value,0,point)); if !eat(p,t_comma) { break; } }
  expect(p,t_r_brace); let __cleanup_result_14_0: Id = list_node(p,a_type_record,fields.items,start); { p.depth--; } let __cleanup_result_31_0: Id = __cleanup_result_14_0; fields.deinit(); return __cleanup_result_31_0;
  fields.deinit(); }
 let array=eat(p,t_l_bracket); if !array&&!eat(p,t_l_paren) { let __cleanup_result_15_0: Id = fail(p,c_expected_type); { p.depth--; } return __cleanup_result_15_0; }
 if !array&&at(p,t_identifier)&&peek(p,1)==t_colon { let name=lower_identifier(p); expect(p,t_colon); let annotation=type_expression(p); expect(p,t_r_paren); let __cleanup_result_16_0: Id = add(p,a_type_binder,name,annotation,0,start); { p.depth--; } return __cleanup_result_16_0; }
 var end=t_r_paren; if array { end=t_r_bracket; } var values=ScratchIdBuffer {};  var tuple=false;
 while p.failure==Error.none&&!at(p,end) { values.push(type_expression(p)); if !eat(p,t_comma) { break; } tuple=true; }
 expect(p,end); if p.failure!=Error.none { let __cleanup_result_17_0: Id = 0; { p.depth--; } let __cleanup_result_32_0: Id = __cleanup_result_17_0; values.deinit(); return __cleanup_result_32_0; }
 if !array&&!tuple&&values.len==1 { p.tree.type_conversion_origins.push(blot_parse_ast::TypeConversionOrigin {values.items[0],start}); let __cleanup_result_18_0: Id = values.items[0]; { p.depth--; } let __cleanup_result_33_0: Id = __cleanup_result_18_0; values.deinit(); return __cleanup_result_33_0; }
 var tag=a_type_product; if array { tag=a_type_array; } let __cleanup_result_19_0: Id = list_node(p,tag,values.items,start); { p.depth--; } let __cleanup_result_34_0: Id = __cleanup_result_19_0; values.deinit(); return __cleanup_result_34_0;
 { p.depth--; }  values.deinit(); }
fn proof_operand(p: Parser&) -> Id {
 if !enter(p) { return 0; }  let t=current(p);
 if eat(p,t_l_paren) { let value=proof_operand(p); expect(p,t_r_paren); if p.failure==Error.none { p.tree.type_conversion_origins.push(blot_parse_ast::TypeConversionOrigin {value,t.start}); } let __cleanup_result_20_0: Id = value; { p.depth--; } return __cleanup_result_20_0; }
 if eat(p,t_integer) { let __cleanup_result_21_0: Id = integer_literal(p,t,a_integer); { p.depth--; } return __cleanup_result_21_0; }
 if at(p,t_identifier) { let __cleanup_result_22_0: Id = add(p,a_type_name,lower_identifier(p),0,0,t.start); { p.depth--; } return __cleanup_result_22_0; }
 if eat(p,t_intrinsic) { let name=text(p,t); if name!="@array.length"&&name!="@list.length" { let __cleanup_result_23_0: Id = fail(p,c_expected_type); { p.depth--; } return __cleanup_result_23_0; } let head=add(p,a_type_name,intern(p,name),0,0,t.start); let arg=proof_operand(p); let __cleanup_result_24_0: Id = add(p,a_type_apply,head,arg,0,t.start); { p.depth--; } return __cleanup_result_24_0; }
 let __cleanup_result_25_0: Id = fail(p,c_expected_type); { p.depth--; } return __cleanup_result_25_0;
 { p.depth--; } }
fn quantified_binders(p: Parser&) -> List {
 expect(p,t_l_bracket); var binders=ScratchIdBuffer {}; 
 while p.failure==Error.none { let start=current(p).start; var sort: u32=0; if word(p,"row")||word(p,"region") { sort=2; if word(p,"row") { sort=1; } advance(p); } let name=lower_identifier(p); binders.push(add(p,a_quantified_binder,name,sort,0,start)); if !eat(p,t_comma) { break; } }
 expect(p,t_r_bracket); let __cleanup_result_35_0: List = list(p,binders.items); binders.deinit(); return __cleanup_result_35_0;
 binders.deinit(); }
fn quantified_type(p: Parser&) -> Id {
 let start=current(p).start; var tag=a_type_forall; if word(p,"exists") { tag=a_type_exists; } advance(p); let binders=quantified_binders(p); var where=Where {};
 if at(p,t_kw_where)||(at(p,t_identifier)&&word(p,"where")) { let point=advance(p).start; where=predicate_body(p,point,false); }
 expect(p,t_fat_arrow); let body=type_expression(p); return add(p,tag,binders.start,binders.len,extra(p,[body,where.node]),start);
}
fn package_pack(p: Parser&) -> Id {
 let start=advance(p).start; expect(p,t_l_bracket); var witnesses=ScratchIdBuffer {}; 
 while p.failure==Error.none { witnesses.push(type_expression(p)); if !eat(p,t_comma) { break; } }
 expect(p,t_r_bracket); let value=expression(p); expect(p,t_kw_as); let annotation=type_expression(p); let range=list(p,witnesses.items); let __cleanup_result_36_0: Id = add(p,a_package_pack,range.start,range.len,extra(p,[value,annotation]),start); witnesses.deinit(); return __cleanup_result_36_0;
 witnesses.deinit(); }
fn package_opening_ahead(p: Parser&) -> bool {
 var nested=0; var index=p.index+1;
 while index<p.tokens.len {
  let tag=p.tokens[index].tag;
  if tag==t_kw_as&&nested==0 { return true; }
  if tag==t_l_paren||tag==t_l_bracket||tag==t_l_brace { nested++; }
  else if tag==t_r_paren||tag==t_r_bracket||tag==t_r_brace { if nested==0 { return false; } nested--; }
  else if nested==0&&(tag==t_newline||tag==t_eof||tag==t_fat_arrow||tag==t_equal) { return false; } index++;
 }
 return false;
}
fn package_unpack(p: Parser&) -> Id {
 let start=advance(p).start; let package=expression(p); expect(p,t_kw_as); let binders=quantified_binders(p); let name=lower_identifier(p); expect(p,t_kw_in); let body=expression(p); return add(p,a_package_unpack,package,binders.start,extra(p,[binders.len,name,body]),start);
}
fn effect_row(p: Parser&) -> Id { let start=expect(p,t_bang).start; return effect_row_body(p,start); }
fn effect_row_body(p: Parser&,start: u32) -> Id {
 expect(p,t_l_brace); var labels=ScratchIdBuffer {}; 
 while p.failure==Error.none&&!at(p,t_pipe)&&!at(p,t_r_brace) { labels.push(type_application(p)); if !eat(p,t_comma) { break; } }
 var tail: Id=0; if eat(p,t_pipe) { let t=current(p); let name=lower_identifier(p); tail=add(p,a_type_name,name,0,0,t.start); }
 expect(p,t_r_brace); let range=list(p,labels.items); let __cleanup_result_37_0: Id = add(p,a_effect_row,range.start,range.len,tail,start); labels.deinit(); return __cleanup_result_37_0;
 labels.deinit(); }
fn expression(p: Parser&) -> Id {
 if !enter(p) { return 0; } 
 if at(p,t_identifier)&&word(p,"pack")&&peek(p,1)==t_l_bracket { let __cleanup_result_26_0: Id = package_pack(p); { p.depth--; } return __cleanup_result_26_0; }
 if at(p,t_identifier)&&word(p,"unpack")&&package_opening_ahead(p) { let __cleanup_result_27_0: Id = package_unpack(p); { p.depth--; } return __cleanup_result_27_0; }
 if at(p,t_kw_func) { let __cleanup_result_28_0: Id = lambda(p); { p.depth--; } return __cleanup_result_28_0; } if at(p,t_kw_do) { let __cleanup_result_29_0: Id = do_block(p); { p.depth--; } return __cleanup_result_29_0; } if at(p,t_kw_if) { let __cleanup_result_30_0: Id = if_expression(p); { p.depth--; } return __cleanup_result_30_0; } if at(p,t_kw_case) { let __cleanup_result_31_0: Id = case_expression(p); { p.depth--; } return __cleanup_result_31_0; } let __cleanup_result_32_0: Id = infix(p); { p.depth--; } return __cleanup_result_32_0;
 { p.depth--; } }
fn lambda(p: Parser&) -> Id {
 let start=expect(p,t_kw_func).start; var parameters=ScratchLambdaParameterBuffer {}; 
 while p.failure==Error.none {
  let point=current(p).start; var unit=false; var name: Symbol=0; var annotation: Id=0; var constraints=Where {}; var pattern_parameter: Id=0;
  if eat(p,t_l_paren) {
   if eat(p,t_r_paren) { unit=true; }
   else if at(p,t_hash) { pattern_parameter=pattern(p); expect(p,t_r_paren); name=collection_name(p,point); }
   else { name=lower_identifier(p); expect(p,t_colon); annotation=type_expression(p); constraints=where_clause(p); expect(p,t_r_paren); }
  } else { name=lower_identifier(p); }
  var flags: u32=0; if unit { flags=1; }
  let parameter=add(p,a_parameter,name,annotation,extra(p,[flags,constraints.predicates.start,constraints.predicates.len,constraints.node]),point);
  if p.failure!=Error.none { let __cleanup_result_38_0: Id = 0; parameters.deinit(); return __cleanup_result_38_0; } if pattern_parameter!=0 { p.tree.extra.items[p.tree.node(parameter).c]|=4; }
  parameters.push(LambdaParameter {parameter,pattern_parameter,name,point}); if !eat(p,t_arrow) { break; } if parameters.len>=256 { let __cleanup_result_39_0: Id = fail(p,c_nesting_limit); parameters.deinit(); return __cleanup_result_39_0; }
 }
 var result: Id=0; if eat(p,t_colon) { result=type_expression(p); } expect(p,t_fat_arrow); let returned=eat(p,t_kw_return);
 if !returned&&!at(p,t_kw_do) { let __cleanup_result_40_0: Id = fail(p,c_function_return_required); parameters.deinit(); return __cleanup_result_40_0; } var body=expression(p); if p.failure!=Error.none { let __cleanup_result_41_0: Id = 0; parameters.deinit(); return __cleanup_result_41_0; }
 if !returned { p.tree.extra.items[p.tree.node(parameters.items[parameters.len-1].node).c]|=2; }
 var index=parameters.len;
 while index!=0 {
  index--; let parameter=parameters.items[index];
  if parameter.pattern!=0 { let argument=add(p,a_name,parameter.name,0,0,parameter.start); let binding=add(p,a_let_stmt,parameter.pattern,argument,extra(p,[0,0,0,0,0]),parameter.start); let result_statement=add(p,a_return_stmt,body,0,0,parameter.start); body=list_node(p,a_block,[binding,result_statement],parameter.start); }
  var annotation: Id=0; if index==parameters.len-1 { annotation=result; } var point=parameter.start; if index==0 { point=start; } body=add(p,a_lambda,parameter.node,body,annotation,point);
 }
 let __cleanup_result_42_0: Id = body; parameters.deinit(); return __cleanup_result_42_0;
 parameters.deinit(); }
fn do_block(p: Parser&) -> Id { let start=expect(p,t_kw_do).start; var resolver: Id=0; if !at(p,t_colon) { resolver=application(p,false); } expect(p,t_colon); let block=suite(p); if p.failure!=Error.none { return 0; } p.tree.nodes.items[block].c=resolver; p.tree.spans.items[block].start=start; return block; }
fn if_expression(p: Parser&) -> Id { let start=expect(p,t_kw_if).start; let condition=infix(p); expect(p,t_kw_then); let consequence=expression(p); expect(p,t_kw_else); let fallback=expression(p); return add(p,a_if_expr,condition,consequence,fallback,start); }
fn lookup_fixity(p: Parser&,symbol: Symbol,named: bool) -> Fixity,bool {
 let spelling=p.pool.get(symbol);
 if spelling=="and"||spelling=="or" { var precedence: u32=20; if spelling=="and" { precedence=25; } return Fixity {symbol,precedence,1,false,false},true; }
 for f in p.fixities { if f.symbol==symbol&&f.named==named { return f,true; } }
 if named { return Fixity {symbol,80,0,true,false},true; }
 return Fixity {symbol,0,0,false,false},false;
}
fn read_operator(p: Parser&) -> Operator {
 let t=advance(p); var named=false; var span=Span {t.start,t.end}; var symbol: Symbol=0;
 if t.tag==t_backtick { named=true; span.start=current(p).start; symbol=qualified(p); span.end=current(p).start; expect(p,t_backtick); }
 else { symbol=intern(p,text(p,t)); }
 let found,known=lookup_fixity(p,symbol,named);
 if !known&&!named&&p.pool.get(symbol)=="$" { return Operator {symbol,0,1,span,true,false,true}; }
 var precedence: u32=0; var association: u32=0; if known { precedence=found.precedence; association=found.association; }
 return Operator {symbol,precedence,association,span,known,named,false};
}
fn infix(p: Parser&) -> Id {
 let start=current(p).start; let head=prefix(p); var operands=ScratchIdBuffer {};  var operators=ScratchOperatorBuffer {};  var unknown=false;
 while p.failure==Error.none&&(operator_tag(current(p).tag)||at(p,t_backtick)) {
  let op=read_operator(p); unknown=unknown||!op.known; operators.push(op); var rhs: Id=0;
  if at(p,t_kw_func)||at(p,t_kw_do)||at(p,t_kw_if)||at(p,t_kw_case) { rhs=expression(p); } else { rhs=prefix(p); } operands.push(rhs);
 }
 if p.failure!=Error.none { let __cleanup_result_43_0: Id = 0; operators.deinit(); operands.deinit(); return __cleanup_result_43_0; } if operators.len==0 { let __cleanup_result_44_0: Id = head; operators.deinit(); operands.deinit(); return __cleanup_result_44_0; }
 if unknown { let __cleanup_result_45_0: Id = infix_chain(p,head,operators.items,operands.items,start); operators.deinit(); operands.deinit(); return __cleanup_result_45_0; }
 var values=ScratchIdBuffer {};  values.append([head]); var stack=ScratchOperatorBuffer {}; 
 for op,index in operators.items {
  while stack.len!=0 {
   let top=stack.items[stack.len-1]; if top.precedence<op.precedence { break; }
   if top.precedence==op.precedence { if top.association!=op.association||op.association==2 { let __cleanup_result_46_0: Id = infix_chain(p,head,operators.items,operands.items,start); stack.deinit(); values.deinit(); operators.deinit(); operands.deinit(); return __cleanup_result_46_0; } if op.association==1 { break; } }
   stack.resize(stack.len-1); reduce(p,values,top); if p.failure!=Error.none { let __cleanup_result_47_0: Id = 0; stack.deinit(); values.deinit(); operators.deinit(); operands.deinit(); return __cleanup_result_47_0; }
  }
  stack.push(op); values.push(operands.items[index]);
 }
 while stack.len!=0 { let op=stack.items[stack.len-1]; stack.resize(stack.len-1); reduce(p,values,op); if p.failure!=Error.none { let __cleanup_result_48_0: Id = 0; stack.deinit(); values.deinit(); operators.deinit(); operands.deinit(); return __cleanup_result_48_0; } }
 let __cleanup_result_49_0: Id = values.items[0]; stack.deinit(); values.deinit(); operators.deinit(); operands.deinit(); return __cleanup_result_49_0;
 stack.deinit(); values.deinit(); operators.deinit(); operands.deinit(); }
fn infix_chain(p: Parser&,head: Id,operators: const Operator[:],operands: const Id[:],start: u32) -> Id {
 var tails=ScratchIdBuffer {}; 
 for op,index in operators {
  var flags=(op.association<<2)|(op.precedence<<4); if op.named { flags|=1; } if op.known { flags|=2; }
  let rhs=operands[index]; let tail=add(p,a_operator_tail,op.symbol,rhs,flags,op.span.start); if p.failure!=Error.none { let __cleanup_result_50_0: Id = 0; tails.deinit(); return __cleanup_result_50_0; }
  p.tree.spans.items[tail].end=p.tree.span(rhs).end; p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:tail,span:op.span}); tails.push(tail);
 }
 let range=list(p,tails.items); let __cleanup_result_51_0: Id = add(p,a_infix_chain,head,range.start,range.len,start); tails.deinit(); return __cleanup_result_51_0;
 tails.deinit(); }
fn reduce(p: Parser&,values: ScratchIdBuffer&,op: Operator) {
 if p.failure!=Error.none { return; }
 let rhs=values.items[values.len-1]; let lhs=values.items[values.len-2]; values.resize(values.len-2); var id: Id=0;
 if op.application { let argument=add(p,a_group,rhs,0,0,p.tree.span(rhs).start); if p.failure!=Error.none { return; } p.tree.spans.items[argument].end=p.tree.span(rhs).end; id=add(p,a_apply,lhs,argument,0,p.tree.span(lhs).start); }
 else { id=add(p,a_binary,op.symbol,lhs,rhs,p.tree.span(lhs).start); }
 if p.failure!=Error.none { return; } p.tree.spans.items[id].end=p.tree.span(rhs).end;
 if !op.application { p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:id,span:op.span}); } values.push(id);
}
fn prefix(p: Parser&) -> Id {
 if p.failure!=Error.none { return 0; } let t=current(p);
 if t.tag==t_caret||(t.tag==t_symbol&&text(p,t)=="&") {
  advance(p); let operand=postfix(p); if p.failure!=Error.none { return 0; } let node=p.tree.node(operand);
  if node.tag==a_index_access { var intrinsic: const u8[:]="@storage.at"; if t.tag==t_caret { intrinsic="@storage.link"; } return collection_intrinsic(p,intrinsic,[node.a,node.b],t.start); }
  if t.tag==t_caret { return fail(p,c_expected_expression); }
  var head=operand; while p.tree.node(head).tag==a_apply { head=p.tree.node(head).a; }
  if p.tree.node(head).tag==a_intrinsic&&p.pool.get(p.tree.node(head).a)=="@storage.view" { return operand; }
  if node.tag!=a_name&&node.tag!=a_field_access { return fail(p,c_expected_expression); }
  return collection_intrinsic(p,"@storage.ref",[operand],t.start);
 }
 if t.tag==t_star&&peek(p,1)==t_l_paren { advance(p); let grouped=atom(p); if p.failure!=Error.none { return 0; } let call=p.tree.node(grouped); if call.tag!=a_group||p.tree.node(call.a).tag!=a_apply { return fail(p,c_task_spark_call); } return spark_call(p,call.a,t.start); }
 if t.tag==t_symbol||t.tag==t_star||t.tag==t_caret { advance(p); let op=intern(p,text(p,t)); let arg=application(p,true); return add(p,a_unary,op,arg,0,t.start); }
 return application(p,true);
}
fn spark_call(p: Parser&,call: Id,start: u32) -> Id {
 var operands=ScratchIdBuffer {};  var callee=call;
 while p.tree.node(callee).tag==a_apply { let node=p.tree.node(callee); operands.push(node.b); callee=node.a; }
 var statements=ScratchIdBuffer {};  var invocation=callee;
 if p.tree.node(callee).tag!=a_name&&p.tree.node(callee).tag!=a_intrinsic { let name=collection_name(p,start); statements.push(collection_binding(p,name,callee,start)); invocation=add(p,a_name,name,0,0,start); }
 var index=operands.len;
 while index!=0 { index--; let name=collection_name(p,start); statements.push(collection_binding(p,name,operands.items[index],start)); let arg=add(p,a_name,name,0,0,start); invocation=add(p,a_apply,invocation,arg,0,start); }
 let parameter=add(p,a_parameter,0,0,extra(p,[1,0,0,0]),start); let thunk=add(p,a_lambda,parameter,invocation,0,start); let group=add(p,a_task_region,0,0,0,start);
 let spawn=collection_intrinsic(p,"@task.spawn",[group,thunk],start); statements.push(add(p,a_return_stmt,spawn,0,0,start)); let __cleanup_result_52_0: Id = list_node(p,a_block,statements.items,start); statements.deinit(); operands.deinit(); return __cleanup_result_52_0;
 statements.deinit(); operands.deinit(); }
fn application(p: Parser&,allow_witness: bool) -> Id {
 let start=current(p).start; var value=postfix(p);
 while p.failure==Error.none {
  if !atom_tag(current(p).tag)||(!allow_witness&&at(p,t_colon)) { break; }
  if at(p,t_colon)&&peek(p,1)==t_newline { break; }
  let argument=postfix(p); value=add(p,a_apply,value,argument,0,start);
 }
 return value;
}
fn postfix(p: Parser&) -> Id {
 let start=current(p).start; var value=atom(p);
 while p.failure==Error.none {
  if at(p,t_dot) { let dot=advance(p); let point=current(p).start; let member=identifier(p); value=add(p,a_field_access,value,member,0,start); if p.failure!=Error.none { return 0; } p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:value,span:Span {dot.start,dot.end},member:member,member_point:point}); }
  else if at(p,t_l_paren)&&current(p).start==p.tree.span(value).end { let argument=atom(p); value=add(p,a_apply,value,argument,0,start); }
  else if at(p,t_l_bracket)&&current(p).start==p.tree.span(value).end {
   advance(p); let index=expression(p);
   if eat(p,t_dot_dot) { let limit=expression(p); expect(p,t_r_bracket); value=collection_intrinsic(p,"@storage.view",[value,index,limit],start); }
   else { expect(p,t_r_bracket); value=add(p,a_index_access,value,index,0,start); }
  } else { break; }
 }
 return value;
}
fn atom(p: Parser&) -> Id {
 if !enter(p) { return 0; }  let t=current(p); let start=t.start;
 if t.tag==t_pipe {
  advance(p); var nesting=0; var end=p.index;
  while end<p.tokens.len {
   let candidate=p.tokens[end].tag;
   if candidate==t_l_paren||candidate==t_l_bracket||candidate==t_l_brace { nesting++; }
   else if candidate==t_r_paren||candidate==t_r_bracket||candidate==t_r_brace { if nesting==0 { let __cleanup_result_33_0: Id = fail(p,c_expected_token); { p.depth--; } return __cleanup_result_33_0; } nesting--; }
   else if candidate==t_pipe&&nesting==0 { break; }
   else if (candidate==t_newline||candidate==t_eof)&&nesting==0 { let __cleanup_result_34_0: Id = fail(p,c_expected_token); { p.depth--; } return __cleanup_result_34_0; } end++;
  }
  if end>=p.tokens.len||end==p.index { let __cleanup_result_35_0: Id = fail(p,c_expected_expression); { p.depth--; } return __cleanup_result_35_0; }
  let previous=p.expression_end; p.expression_end=end; if previous<end { p.expression_end=previous; }
  let receiver=expression(p); p.expression_end=previous; if p.failure!=Error.none { let __cleanup_result_36_0: Id = 0; { p.depth--; } return __cleanup_result_36_0; }
  if p.index!=end { let __cleanup_result_37_0: Id = fail(p,c_expected_token); { p.depth--; } return __cleanup_result_37_0; } expect(p,t_pipe); let __cleanup_result_38_0: Id = collection_intrinsic(p,"@task.receive",[receiver],start); { p.depth--; } return __cleanup_result_38_0;
 }
 if t.tag==t_kw_true||t.tag==t_kw_false { advance(p); var value: u32=0; if t.tag==t_kw_true { value=1; } let __cleanup_result_39_0: Id = add(p,a_boolean,value,0,0,start); { p.depth--; } return __cleanup_result_39_0; }
 if t.tag==t_integer { advance(p); let __cleanup_result_40_0: Id = integer_literal(p,t,a_integer); { p.depth--; } return __cleanup_result_40_0; }
 if t.tag==t_float {
  advance(p); let bits,err=blot_parse_lexer::float_bits(text(p,t));
  if err==Error.float_range { let __cleanup_result_41_0: Id = numeric_failure(p,t,blot_parse_ast::numericcode_float_range); { p.depth--; } return __cleanup_result_41_0; }
  if err==Error.invalid_float { let __cleanup_result_42_0: Id = numeric_failure(p,t,blot_parse_ast::numericcode_float_literal); { p.depth--; } return __cleanup_result_42_0; }
  if err!=Error.none { p.failure=err; let __cleanup_result_43_0: Id = 0; { p.depth--; } return __cleanup_result_43_0; } let __cleanup_result_44_0: Id = add(p,a_float,bits,0,0,start); { p.depth--; } return __cleanup_result_44_0;
 }
 if t.tag==t_string { let __cleanup_result_45_0: Id = add(p,a_string,string_symbol(p),0,0,start); { p.depth--; } return __cleanup_result_45_0; }
 if t.tag==t_intrinsic {
  advance(p); let staging,has_staging=blot_check_typed_staging::lookup(text(p,t)); if has_staging { p.tree.has_typed_staging=true; }
  let proof,has_proof=blot_check_numeric_proof_terms::constructor(text(p,t)); if has_proof { p.tree.has_numeric_proofs=true; }
  let __cleanup_result_46_0: Id = add(p,a_intrinsic,intern(p,text(p,t)),0,0,start); { p.depth--; } return __cleanup_result_46_0;
 }
 if t.tag==t_identifier||t.tag==t_type_identifier {
  let token_start=p.index; let name=qualified(p); let id=add(p,a_name,name,0,0,start); if p.failure!=Error.none { let __cleanup_result_47_0: Id = 0; { p.depth--; } return __cleanup_result_47_0; }
  for index in token_start..p.index { let item=p.tokens[index]; if item.tag==t_dot { let member,found=p.pool.lookup(text(p,p.tokens[index+1])); p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:id,span:Span {item.start,item.end},member:member,member_point:p.tokens[index+1].start}); } } let __cleanup_result_48_0: Id = id; { p.depth--; } return __cleanup_result_48_0;
 }
 if t.tag==t_selector { advance(p); let __cleanup_result_49_0: Id = add(p,a_selector,qualified(p),0,0,start); { p.depth--; } return __cleanup_result_49_0; }
 if t.tag==t_colon { advance(p); let value=atom(p); let __cleanup_result_50_0: Id = add(p,a_type_witness,value,0,0,start); { p.depth--; } return __cleanup_result_50_0; }
 if t.tag==t_hash {
  advance(p);
  if text(p,t)=="#"&&word(p,"run")&&peek(p,1)!=t_dot { advance(p); p.tree.has_typed_staging=true; let value=expression(p); let __cleanup_result_51_0: Id = collection_intrinsic(p,"@code.evaluate",[value],start); { p.depth--; } return __cleanup_result_51_0; }
  if text(p,t)=="#"&&at(p,t_kw_do) { p.tree.has_typed_staging=true; let value=do_block(p); let __cleanup_result_52_0: Id = collection_intrinsic(p,"@code.evaluate",[value],start); { p.depth--; } return __cleanup_result_52_0; }
  if at(p,t_l_bracket) { let __cleanup_result_53_0: Id = collection(p,false,start); { p.depth--; } return __cleanup_result_53_0; } if at(p,t_l_brace) { let __cleanup_result_54_0: Id = record(p,0,start); { p.depth--; } return __cleanup_result_54_0; }
  let name=qualified(p); if at(p,t_l_brace) { let __cleanup_result_55_0: Id = record(p,name,start); { p.depth--; } return __cleanup_result_55_0; } let __cleanup_result_56_0: Id = add(p,a_constructor_ref,name,0,0,start); { p.depth--; } return __cleanup_result_56_0;
 }
 if t.tag==t_l_brace { let __cleanup_result_57_0: Id = record(p,0,start); { p.depth--; } return __cleanup_result_57_0; } if t.tag==t_l_bracket { let __cleanup_result_58_0: Id = collection(p,true,start); { p.depth--; } return __cleanup_result_58_0; }
 if t.tag==t_l_paren {
  advance(p); var values=ScratchIdBuffer {};  var tuple=false;
  while p.failure==Error.none&&!at(p,t_r_paren) { values.push(expression(p)); if !eat(p,t_comma) { break; } tuple=true; }
  expect(p,t_r_paren); if values.len==0 { let __cleanup_result_59_0: Id = add(p,a_unit,0,0,0,start); { p.depth--; } let __cleanup_result_53_0: Id = __cleanup_result_59_0; values.deinit(); return __cleanup_result_53_0; } if !tuple&&values.len==1 { let __cleanup_result_60_0: Id = add(p,a_group,values.items[0],0,0,start); { p.depth--; } let __cleanup_result_54_0: Id = __cleanup_result_60_0; values.deinit(); return __cleanup_result_54_0; } let __cleanup_result_61_0: Id = list_node(p,a_product,values.items,start); { p.depth--; } let __cleanup_result_55_0: Id = __cleanup_result_61_0; values.deinit(); return __cleanup_result_55_0;
  values.deinit(); }
 if t.tag==t_private_from||t.tag==t_private_where { let __cleanup_result_62_0: Id = fail(p,c_private_marker); { p.depth--; } return __cleanup_result_62_0; } let __cleanup_result_63_0: Id = fail(p,c_expected_expression); { p.depth--; } return __cleanup_result_63_0;
 { p.depth--; } }
fn collection_element(p: Parser&) -> Id {
 let previous=p.expression_end; var nesting=0; var index=p.index; var limit=p.tokens.len; if previous<limit { limit=previous; }
 while index<limit {
  let tag=p.tokens[index].tag;
  if tag==t_l_paren||tag==t_l_bracket||tag==t_l_brace||tag==t_indent { nesting++; }
  else if tag==t_r_paren||tag==t_r_bracket||tag==t_r_brace||tag==t_dedent { if nesting==0 { break; } nesting--; }
  else if tag==t_pipe&&nesting==0 { p.expression_end=index; break; }
  else if (tag==t_comma||tag==t_eof)&&nesting==0 { break; } index++;
 }
 let value=expression(p); p.expression_end=previous; return value;
}
fn collection_literal(p: Parser&,is_list: bool,values: const Id[:],start: u32) -> Id { let range=list(p,values); var kind: u32=0; if is_list { kind=1; } return add(p,a_array,range.start,range.len,kind,start); }
fn collection_intrinsic(p: Parser&,name: const u8[:],args: const Id[:],start: u32) -> Id { var result=add(p,a_intrinsic,intern(p,name),0,0,start); for arg in args { result=add(p,a_apply,result,arg,0,start); } return result; }
fn collection_name(p: Parser&,start: u32) -> Symbol { let spelling=str("$collection.",p.collection_names); p.collection_names++; return intern(p,spelling); }
fn collection_binding(p: Parser&,name: Symbol,value: Id,start: u32) -> Id { let pat=add(p,a_pattern_name,name,0,0,start); return add(p,a_let_stmt,pat,value,extra(p,[0,0,0,0,0]),start); }
fn collection_loop(p: Parser&,pat: Id,value: Id,end: Id,body: Id,explicit: bool,start: u32) -> Id {
 var expansion: Id=0;
 if end==0 {
  let cursor=collection_name(p,start); let cursor_ref=add(p,a_name,cursor,0,0,start);
  let iter=add(p,a_field_access,value,intern(p,"iter"),0,start); let initialize=add(p,a_iterator_bind,cursor,iter,0,start);
  let step=collection_name(p,start); let next=add(p,a_field_access,cursor_ref,intern(p,"next"),0,start); let next_step=add(p,a_iterator_bind,step,next,0,start);
  let item=collection_name(p,start); let item_pattern=add(p,a_pattern_name,item,0,0,start); let rest=collection_name(p,start); let rest_pattern=add(p,a_pattern_name,rest,0,0,start);
  let pair=list_node(p,a_pattern_product,[item_pattern,rest_pattern],start); let some=add(p,a_pattern_constructor,intern(p,"Some"),pair,0,start);
  let broken=add(p,a_break_stmt,0,0,0,start); let stop=list_node(p,a_block,[broken],start);
  let step_ref=add(p,a_name,step,0,0,start); let unpack=add(p,a_let_stmt,some,step_ref,extra(p,[0,0,0,stop,0]),start);
  let rest_ref=add(p,a_name,rest,0,0,start); let update=add(p,a_rebind_stmt,cursor_ref,rest_ref,0,start);
  let item_ref=add(p,a_name,item,0,0,start); let bind=add(p,a_let_stmt,pat,item_ref,extra(p,[0,0,0,0,0]),start);
  if p.failure!=Error.none { return 0; } var statements=ScratchIdBuffer {};  statements.append([next_step,unpack,update,bind]); for child in p.tree.children(body) { statements.push(child); }
  let iteration_body=list_node(p,a_block,statements.items,start); let iteration=add(p,a_forever_stmt,iteration_body,0,0,start); expansion=list_node(p,a_block,[initialize,iteration],start);
  statements.deinit(); }
 var explicit_flag: u32=0; if explicit { explicit_flag=1; } return add(p,a_for_stmt,pat,value,extra(p,[end,body,explicit_flag,expansion]),start);
}
fn collection(p: Parser&,is_list: bool,start: u32) -> Id {
 expect(p,t_l_bracket); var values=ScratchIdBuffer {};  var spread: i64=-1;
 while p.failure==Error.none&&!at(p,t_r_bracket) {
  if eat(p,t_ellipsis) { if spread>=0 { let __cleanup_result_56_0: Id = fail(p,c_unexpected_token); values.deinit(); return __cleanup_result_56_0; } spread=values.len; }
  values.push(collection_element(p));
  if eat(p,t_pipe) { if spread>=0 { let __cleanup_result_57_0: Id = fail(p,c_unexpected_token); values.deinit(); return __cleanup_result_57_0; } if values.len==1&&at(p,t_identifier)&&peek(p,1)==t_left_arrow { let __cleanup_result_58_0: Id = comprehension(p,is_list,values.items[0],start); values.deinit(); return __cleanup_result_58_0; } spread=values.len; values.push(expression(p)); break; }
  if !eat(p,t_comma) { break; }
 }
 expect(p,t_r_bracket); if p.failure!=Error.none { let __cleanup_result_59_0: Id = 0; values.deinit(); return __cleanup_result_59_0; }
 if spread<0 { let __cleanup_result_60_0: Id = collection_literal(p,is_list,values.items,start); values.deinit(); return __cleanup_result_60_0; }
 var statements=ScratchIdBuffer {};  var refs=ScratchIdBuffer {}; 
 for value in values.items { let name=collection_name(p,start); statements.push(add(p,a_iterator_bind,name,value,0,start)); refs.push(add(p,a_name,name,0,0,start)); }
 var result=refs.items[spread]; var index=spread;
 var prepend: const u8[:]="@array.prepend"; var append: const u8[:]="@array.append"; var identity: const u8[:]="@array.identity";
 if is_list { prepend="@list.prepend"; append="@list.append"; identity="@list.identity"; }
 while index!=0 { index--; result=collection_intrinsic(p,prepend,[result,refs.items[index]],start); }
 for value in refs.items[spread+1..] { result=collection_intrinsic(p,append,[result,value],start); }
 if values.len==1 { result=collection_intrinsic(p,identity,[result],start); } statements.push(add(p,a_return_stmt,result,0,0,start)); let __cleanup_result_61_0: Id = list_node(p,a_block,statements.items,start); refs.deinit(); statements.deinit(); values.deinit(); return __cleanup_result_61_0;
 refs.deinit(); statements.deinit(); values.deinit(); }
fn comprehension(p: Parser&,is_list: bool,result: Id,start: u32) -> Id {
 var qualifiers=ScratchQualifierBuffer {}; 
 while p.failure==Error.none {
  let point=current(p).start; var kind: u32=1; var name: Symbol=0;
  if eat(p,t_kw_let) { kind=2; name=lower_identifier(p); expect(p,t_equal); }
  else if at(p,t_identifier)&&peek(p,1)==t_left_arrow { kind=0; name=lower_identifier(p); expect(p,t_left_arrow); }
  let value=expression(p); qualifiers.push(Qualifier {kind,name,value,point});
  if !eat(p,t_comma) { break; } if at(p,t_r_bracket) { let __cleanup_result_62_0: Id = fail(p,c_expected_expression); qualifiers.deinit(); return __cleanup_result_62_0; }
 }
 expect(p,t_r_bracket); let accumulator=collection_name(p,start); let empty=collection_literal(p,true,[],start); let initial=collection_binding(p,accumulator,empty,start);
 let target=add(p,a_name,accumulator,0,0,start); let receiver=add(p,a_name,accumulator,0,0,start); let appended=collection_intrinsic(p,"@list.append",[receiver,result],start);
 let rebind=add(p,a_rebind_stmt,target,appended,0,start); var body=list_node(p,a_block,[rebind],start); var index=qualifiers.len;
 while index!=0&&p.failure==Error.none {
  index--; let q=qualifiers.items[index]; var statement: Id=0;
  if q.kind==0 { let pat=add(p,a_pattern_name,q.name,0,0,q.start); statement=collection_loop(p,pat,q.value,0,body,false,q.start); }
  else if q.kind==1 { statement=add(p,a_if_stmt,q.value,body,0,q.start); }
  else { let binding=collection_binding(p,q.name,q.value,q.start); var joined=ScratchIdBuffer {};  joined.append([binding]); for child in p.tree.children(body) { joined.push(child); } body=list_node(p,a_block,joined.items,q.start); joined.deinit(); continue;  joined.deinit(); }
  body=list_node(p,a_block,[statement],q.start);
 }
 var final=add(p,a_name,accumulator,0,0,start); if !is_list { final=collection_intrinsic(p,"@array.from_list",[final],start); }
 let returned=add(p,a_return_stmt,final,0,0,start); if p.failure!=Error.none { let __cleanup_result_64_0: Id = 0; qualifiers.deinit(); return __cleanup_result_64_0; }
 var statements=ScratchIdBuffer {};  statements.append([initial]); for child in p.tree.children(body) { statements.push(child); } statements.push(returned); let __cleanup_result_65_0: Id = list_node(p,a_block,statements.items,start); statements.deinit(); qualifiers.deinit(); return __cleanup_result_65_0;
 statements.deinit(); qualifiers.deinit(); }
fn record(p: Parser&,name: Symbol,start: u32) -> Id {
 expect(p,t_l_brace); var fields=ScratchIdBuffer {}; 
 while p.failure==Error.none&&!at(p,t_r_brace) { let point=current(p).start; let key=lower_identifier(p); var value: Id=0; if eat(p,t_colon) { value=expression(p); } fields.push(add(p,a_field,key,value,0,point)); if !eat(p,t_comma) { break; } }
 expect(p,t_r_brace); let range=list(p,fields.items); let __cleanup_result_66_0: Id = add(p,a_record,name,range.start,range.len,start); fields.deinit(); return __cleanup_result_66_0;
 fields.deinit(); }
fn suite(p: Parser&) -> Id {
 if !enter(p) { return 0; } 
 let start=expect(p,t_newline).start; expect(p,t_indent); var statements=ScratchIdBuffer {};  newlines(p);
 while p.failure==Error.none&&!at(p,t_dedent)&&!at(p,t_eof) { statements.push(statement(p)); if p.failure!=Error.none { let __cleanup_result_64_0: Id = 0; { p.depth--; } let __cleanup_result_67_0: Id = __cleanup_result_64_0; statements.deinit(); return __cleanup_result_67_0; } if !at(p,t_newline)&&!at(p,t_dedent) { let __cleanup_result_65_0: Id = fail(p,c_expected_token); { p.depth--; } let __cleanup_result_68_0: Id = __cleanup_result_65_0; statements.deinit(); return __cleanup_result_68_0; } newlines(p); }
 expect(p,t_dedent); let __cleanup_result_66_0: Id = list_node(p,a_block,statements.items,start); { p.depth--; } let __cleanup_result_69_0: Id = __cleanup_result_66_0; statements.deinit(); return __cleanup_result_69_0;
 { p.depth--; }  statements.deinit(); }
fn statement(p: Parser&) -> Id {
 if p.failure!=Error.none { return 0; } let start=current(p).start;
 if eat(p,t_kw_let) {
  let pat=pattern(p); var annotation: Id=0; if eat(p,t_colon) { annotation=type_expression(p); } let constraints=where_clause(p); expect(p,t_equal); let value=expression(p); var fallback: Id=0;
  if eat(p,t_kw_else) { expect(p,t_colon); fallback=suite(p); } return add(p,a_let_stmt,pat,value,extra(p,[annotation,constraints.predicates.start,constraints.predicates.len,fallback,constraints.node]),start);
 }
 if eat(p,t_kw_return) { let value=expression(p); return add(p,a_function_return_stmt,value,0,0,start); }
 if eat(p,t_kw_yield) { let value=expression(p); return add(p,a_yield_stmt,value,0,0,start); }
 if eat(p,t_kw_break) {
  if at(p,t_newline)||at(p,t_dedent)||at(p,t_eof) { return add(p,a_break_stmt,0,0,0,start); }
  var forwarding: u32=0; if eat(p,t_dollar) { forwarding=1; } let value=expression(p); return add(p,a_return_stmt,value,forwarding,0,start);
 }
 if eat(p,t_kw_continue) { return add(p,a_continue_stmt,0,0,0,start); }
 if at(p,t_kw_if) { return if_statement(p); } if at(p,t_kw_for) { return for_statement(p); }
 if eat(p,t_kw_use) {
  if (at(p,t_type_identifier)||at(p,t_kw_true)||at(p,t_kw_false))&&has_use_binding(p) { return identifier_syntax(p); }
  if at(p,t_identifier)&&has_use_binding(p) { let name=lower_identifier(p); var annotation: Id=0; if eat(p,t_colon) { annotation=type_expression(p); } expect(p,t_left_arrow); let value=expression(p); return add(p,a_use_stmt,name,value,annotation,start); }
  let value=expression(p); return add(p,a_use_stmt,0,value,0,start);
 }
 if (at(p,t_type_identifier)||at(p,t_kw_true)||at(p,t_kw_false))&&has_rebinding(p) { return identifier_syntax(p); }
 if at(p,t_identifier)&&has_rebinding(p) {
  let name=lower_identifier(p); var target=add(p,a_name,name,0,0,start);
  while p.failure==Error.none&&(at(p,t_dot)||at(p,t_l_bracket)) {
   if at(p,t_dot) { let dot=advance(p); let member=identifier(p); target=add(p,a_field_access,target,member,0,start); if p.failure!=Error.none { return 0; } p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:target,span:Span {dot.start,dot.end},member:member}); }
   else { advance(p); let index=expression(p); expect(p,t_r_bracket); target=add(p,a_index_access,target,index,0,start); }
  }
  expect(p,t_colon_equal); let value=expression(p); return add(p,a_rebind_stmt,target,value,0,start);
 }
 return expression(p);
}
fn has_use_binding(p: Parser&) -> bool {
 if peek(p,1)==t_left_arrow { return true; } if peek(p,1)!=t_colon { return false; }
 var nesting=0; var i=p.index+2;
 while i<p.tokens.len {
  let tag=p.tokens[i].tag; if nesting==0 { if tag==t_left_arrow { return true; } if tag==t_newline||tag==t_dedent||tag==t_eof { return false; } }
  if tag==t_l_paren||tag==t_l_bracket||tag==t_l_brace { nesting++; } else if (tag==t_r_paren||tag==t_r_bracket||tag==t_r_brace)&&nesting!=0 { nesting--; } i++;
 }
 return false;
}
fn has_rebinding(p: Parser&) -> bool {
 var nesting=0; var i=p.index;
 while i<p.tokens.len {
  let tag=p.tokens[i].tag; if nesting==0 { if tag==t_colon_equal { return true; } if tag==t_newline||tag==t_dedent||tag==t_eof { return false; } }
  if tag==t_l_paren||tag==t_l_bracket||tag==t_l_brace { nesting++; } else if (tag==t_r_paren||tag==t_r_bracket||tag==t_r_brace)&&nesting!=0 { nesting--; } i++;
 }
 return false;
}
fn trailing_else(p: Parser&) -> Id { let saved=p.index; newlines(p); if !eat(p,t_kw_else) { p.index=saved; return 0; } expect(p,t_colon); return suite(p); }
fn if_statement(p: Parser&) -> Id {
 let start=expect(p,t_kw_if).start;
 if eat(p,t_kw_let) { let pat=pattern(p); expect(p,t_equal); let value=expression(p); expect(p,t_colon); let body=suite(p); let fallback=trailing_else(p); return add(p,a_if_let_stmt,pat,value,extra(p,[body,fallback]),start); }
 let condition=expression(p);
 if eat(p,t_kw_then) { let consequence=expression(p); expect(p,t_kw_else); let fallback=expression(p); return add(p,a_if_expr,condition,consequence,fallback,start); }
 expect(p,t_colon); let body=suite(p); let fallback=trailing_else(p); return add(p,a_if_stmt,condition,body,fallback,start);
}
fn for_statement(p: Parser&) -> Id {
 let start=expect(p,t_kw_for).start;
 if eat(p,t_kw_ever) { expect(p,t_colon); let body=suite(p); return add(p,a_forever_stmt,body,0,0,start); }
 let explicit=eat(p,t_kw_let); var has_in=explicit; var i=p.index; var nesting=0;
 while i<p.tokens.len { let t=p.tokens[i].tag; if nesting==0&&(t==t_colon||t==t_newline||t==t_eof) { break; } if nesting==0&&t==t_kw_in { has_in=true; break; } if t==t_l_paren||t==t_l_bracket||t==t_l_brace { nesting++; } if (t==t_r_paren||t==t_r_bracket||t==t_r_brace)&&nesting!=0 { nesting--; } i++; }
 if has_in { let pat=pattern(p); expect(p,t_kw_in); let value=expression(p); var end: Id=0; if eat(p,t_dot_dot) { end=expression(p); } expect(p,t_colon); let body=suite(p); return collection_loop(p,pat,value,end,body,explicit,start); }
 let first=expression(p); expect(p,t_dot_dot); let end=expression(p); expect(p,t_colon); let body=suite(p); return add(p,a_range_stmt,first,end,body,start);
}
fn constructor_fields(p: Parser&) -> Id {
 if !enter(p) { return 0; } 
 let start=expect(p,t_l_brace).start; var fields=ScratchIdBuffer {}; 
 while p.failure==Error.none&&!at(p,t_r_brace) { let point=current(p).start; let name=lower_identifier(p); var value: Id=0; if eat(p,t_colon) { value=pattern(p); } fields.push(add(p,a_pattern_field,name,value,0,point)); if !eat(p,t_comma) { break; } }
 expect(p,t_r_brace); let __cleanup_result_67_0: Id = list_node(p,a_pattern_record,fields.items,start); { p.depth--; } let __cleanup_result_70_0: Id = __cleanup_result_67_0; fields.deinit(); return __cleanup_result_70_0;
 { p.depth--; }  fields.deinit(); }
fn pattern(p: Parser&) -> Id {
 if !enter(p) { return 0; }  let t=current(p); let start=t.start;
 if eat(p,t_caret) { let __cleanup_result_68_0: Id = add(p,a_pattern_value,qualified(p),0,0,start); { p.depth--; } return __cleanup_result_68_0; }
 if at(p,t_kw_true)||at(p,t_kw_false) { advance(p); var value: u32=0; if t.tag==t_kw_true { value=1; } let __cleanup_result_69_0: Id = add(p,a_pattern_boolean,value,0,0,start); { p.depth--; } return __cleanup_result_69_0; }
 if at(p,t_type_identifier) { let __cleanup_result_70_0: Id = identifier_syntax(p); { p.depth--; } return __cleanup_result_70_0; } if at(p,t_identifier) { let __cleanup_result_71_0: Id = add(p,a_pattern_name,lower_identifier(p),0,0,start); { p.depth--; } return __cleanup_result_71_0; }
 if eat(p,t_integer) { let __cleanup_result_72_0: Id = integer_literal(p,t,a_pattern_integer); { p.depth--; } return __cleanup_result_72_0; }
 if eat(p,t_hash) { let name=constructor_pattern_name(p); var payload: Id=0; if at(p,t_l_brace) { payload=constructor_fields(p); } else if pattern_tag(current(p).tag) { payload=pattern(p); } let __cleanup_result_73_0: Id = add(p,a_pattern_constructor,name,payload,0,start); { p.depth--; } return __cleanup_result_73_0; }
 if at(p,t_l_brace) { let __cleanup_result_74_0: Id = constructor_fields(p); { p.depth--; } return __cleanup_result_74_0; }
 if eat(p,t_l_paren) { var values=ScratchIdBuffer {};  var tuple=false; while p.failure==Error.none&&!at(p,t_r_paren) { values.push(pattern(p)); if !eat(p,t_comma) { break; } tuple=true; } expect(p,t_r_paren); if !tuple&&values.len==1 { let __cleanup_result_75_0: Id = values.items[0]; { p.depth--; } let __cleanup_result_71_0: Id = __cleanup_result_75_0; values.deinit(); return __cleanup_result_71_0; } let __cleanup_result_76_0: Id = list_node(p,a_pattern_product,values.items,start); { p.depth--; } let __cleanup_result_72_0: Id = __cleanup_result_76_0; values.deinit(); return __cleanup_result_72_0;  values.deinit(); }
 let __cleanup_result_77_0: Id = fail(p,c_expected_pattern); { p.depth--; } return __cleanup_result_77_0;
 { p.depth--; } }
fn pattern_row(p: Parser&) -> Id { let start=current(p).start; var values=ScratchIdBuffer {};  values.push(pattern(p)); while p.failure==Error.none&&eat(p,t_comma) { values.push(pattern(p)); } let __cleanup_result_73_0: Id = list_node(p,a_pattern_row,values.items,start); values.deinit(); return __cleanup_result_73_0;  values.deinit(); }
fn case_expression(p: Parser&) -> Id {
 let start=expect(p,t_kw_case).start; let request_name=at(p,t_identifier)&&peek(p,1)==t_kw_of; var values=ScratchIdBuffer {}; 
 values.push(expression(p)); while p.failure==Error.none&&eat(p,t_comma) { values.push(expression(p)); }
 expect(p,t_kw_of); expect(p,t_newline); expect(p,t_indent); newlines(p); var arms=ScratchIdBuffer {};  let requests=at(p,t_kw_effect)||at(p,t_kw_complete);
 if requests&&!request_name { let __cleanup_result_74_0: Id = identifier_syntax(p); arms.deinit(); values.deinit(); return __cleanup_result_74_0; }
 while p.failure==Error.none&&!at(p,t_dedent)&&!at(p,t_eof) {
  let point=current(p).start;
  if requests {
   let complete=eat(p,t_kw_complete); var operation: Id=0;
   if !complete { expect(p,t_kw_effect); let operation_token=current(p).tag; if operation_token!=t_identifier&&operation_token!=t_type_identifier&&operation_token!=t_l_paren { let __cleanup_result_75_0: Id = identifier_syntax(p); arms.deinit(); values.deinit(); return __cleanup_result_75_0; } let operation_start=current(p).start; if operation_token==t_l_paren { operation=atom(p); } else { operation=add(p,a_name,qualified(p),0,0,operation_start); } }
   let pat=pattern(p); expect(p,t_fat_arrow); let body=suite(p); arms.push(add(p,a_request_arm,operation,pat,body,point));
  } else {
   var rows=ScratchIdBuffer {};  rows.push(pattern_row(p)); while p.failure==Error.none&&eat(p,t_pipe) { rows.push(pattern_row(p)); } var guard: Id=0; if eat(p,t_kw_if) { guard=expression(p); }
   expect(p,t_fat_arrow); let body=expression(p); let range=list(p,rows.items); arms.push(add(p,a_case_arm,range.start,range.len,extra(p,[guard,body]),point));
   rows.deinit(); }
  if p.failure!=Error.none { let __cleanup_result_76_0: Id = 0; arms.deinit(); values.deinit(); return __cleanup_result_76_0; } if !at(p,t_newline)&&!at(p,t_dedent) { let __cleanup_result_77_0: Id = fail(p,c_expected_token); arms.deinit(); values.deinit(); return __cleanup_result_77_0; } newlines(p);
 }
 expect(p,t_dedent); let inputs=list(p,values.items); let cases=list(p,arms.items); var tag=a_case_expr; if requests { tag=a_request_case; } let __cleanup_result_78_0: Id = add(p,tag,extra(p,[inputs.start,inputs.len]),cases.start,cases.len,start); arms.deinit(); values.deinit(); return __cleanup_result_78_0;
 arms.deinit(); values.deinit(); }
fn operator_tag(tag: Tag) -> bool { return tag==t_symbol||tag==t_dollar||tag==t_star||tag==t_caret||tag==t_pipe||tag==t_kw_and||tag==t_kw_or; }
fn atom_tag(tag: Tag) -> bool { return tag==t_integer||tag==t_float||tag==t_string||tag==t_intrinsic||tag==t_identifier||tag==t_type_identifier||tag==t_selector||tag==t_hash||tag==t_l_paren||tag==t_l_bracket||tag==t_l_brace||tag==t_colon||tag==t_kw_true||tag==t_kw_false; }
fn type_atom_tag(tag: Tag) -> bool { return tag==t_identifier||tag==t_type_identifier||tag==t_intrinsic||tag==t_l_paren||tag==t_l_bracket||tag==t_l_brace||tag==t_caret||tag==t_symbol; }
fn pattern_tag(tag: Tag) -> bool { return tag==t_identifier||tag==t_integer||tag==t_hash||tag==t_caret||tag==t_l_paren||tag==t_l_brace||tag==t_kw_true||tag==t_kw_false; }
fn parse_with_fixities(source: const u8[:],tokens: const Token[:],pool: blot_parse_symbols::Pool&,tree: Tree&,inherited: const InheritedFixity[:]) -> Error {
 var fixities: Fixity[>..<]=[]; var p=Parser {source:source,tokens:tokens,pool:pool,tree:tree,fixities:fixities};
 for f in inherited { fixities.push(Fixity {f.operator,f.precedence,f.association,f.named,true}); }
 var declarations_seen=false; var body_declarations_seen=false;
 while !at(p,t_eof) {
  newlines(p); if at(p,t_eof) { break; } let before=p.index; let first_node=tree.nodes.len as Id;
  let root=declaration(p,declarations_seen,body_declarations_seen);
  if p.failure==Error.syntax { recover(p,before); continue; } if p.failure!=Error.none { return p.failure; }
  tree.roots.push(root); tree.declaration_nodes.push(blot_parse_ast::DeclarationNodes {root,first_node,tree.nodes.len as Id});
  let tag=tree.node(root).tag; if tag!=a_import_decl&&tag!=a_export_decl { declarations_seen=true; } if tag!=a_import_decl&&tag!=a_export_decl&&tag!=a_fixity_decl { body_declarations_seen=true; }
  if !at(p,t_newline)&&!at(p,t_eof) { report(p,c_unexpected_token); recover(p,before); } newlines(p);
 }
 return tree.failure();
}
fn parse(source: const u8[:],tokens: const Token[:],pool: blot_parse_symbols::Pool&,tree: Tree&) -> Error { return parse_with_fixities(source,tokens,pool,tree,[]); }

struct ScratchIdBuffer { storage: Id[:]=[],items: Id[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_ScratchIdBuffer: Id[>..]=[];
fn ensure(self: ScratchIdBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_ScratchIdBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: ScratchIdBuffer&,value: Id) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_ScratchIdBuffer); self.len=self.items.len; }
fn append(self: ScratchIdBuffer&,values: const Id[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_ScratchIdBuffer); self.len=self.items.len; }
fn resize(self: ScratchIdBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: ScratchIdBuffer&,length: i64,value: Id) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: ScratchIdBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: ScratchIdBuffer&) { blot_support_pooled_buffer::deinit(self,pool_ScratchIdBuffer); self.len=0; self.failure=Error.none; }
struct ScratchQualifierBuffer { storage: Qualifier[:]=[],items: Qualifier[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_ScratchQualifierBuffer: Qualifier[>..]=[];
fn ensure(self: ScratchQualifierBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_ScratchQualifierBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: ScratchQualifierBuffer&,value: Qualifier) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_ScratchQualifierBuffer); self.len=self.items.len; }
fn append(self: ScratchQualifierBuffer&,values: const Qualifier[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_ScratchQualifierBuffer); self.len=self.items.len; }
fn resize(self: ScratchQualifierBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: ScratchQualifierBuffer&,length: i64,value: Qualifier) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: ScratchQualifierBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: ScratchQualifierBuffer&) { blot_support_pooled_buffer::deinit(self,pool_ScratchQualifierBuffer); self.len=0; self.failure=Error.none; }
struct ScratchOperatorBuffer { storage: Operator[:]=[],items: Operator[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_ScratchOperatorBuffer: Operator[>..]=[];
fn ensure(self: ScratchOperatorBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_ScratchOperatorBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: ScratchOperatorBuffer&,value: Operator) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_ScratchOperatorBuffer); self.len=self.items.len; }
fn append(self: ScratchOperatorBuffer&,values: const Operator[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_ScratchOperatorBuffer); self.len=self.items.len; }
fn resize(self: ScratchOperatorBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: ScratchOperatorBuffer&,length: i64,value: Operator) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: ScratchOperatorBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: ScratchOperatorBuffer&) { blot_support_pooled_buffer::deinit(self,pool_ScratchOperatorBuffer); self.len=0; self.failure=Error.none; }
struct ScratchLambdaParameterBuffer { storage: LambdaParameter[:]=[],items: LambdaParameter[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_ScratchLambdaParameterBuffer: LambdaParameter[>..]=[];
fn ensure(self: ScratchLambdaParameterBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_ScratchLambdaParameterBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: ScratchLambdaParameterBuffer&,value: LambdaParameter) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_ScratchLambdaParameterBuffer); self.len=self.items.len; }
fn append(self: ScratchLambdaParameterBuffer&,values: const LambdaParameter[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_ScratchLambdaParameterBuffer); self.len=self.items.len; }
fn resize(self: ScratchLambdaParameterBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: ScratchLambdaParameterBuffer&,length: i64,value: LambdaParameter) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: ScratchLambdaParameterBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: ScratchLambdaParameterBuffer&) { blot_support_pooled_buffer::deinit(self,pool_ScratchLambdaParameterBuffer); self.len=0; self.failure=Error.none; }
struct Scratchu8Buffer { storage: u8[:]=[],items: u8[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_Scratchu8Buffer: u8[>..]=[];
fn ensure(self: Scratchu8Buffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Scratchu8Buffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: Scratchu8Buffer&,value: u8) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_Scratchu8Buffer); self.len=self.items.len; }
fn append(self: Scratchu8Buffer&,values: const u8[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_Scratchu8Buffer); self.len=self.items.len; }
fn resize(self: Scratchu8Buffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: Scratchu8Buffer&,length: i64,value: u8) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: Scratchu8Buffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: Scratchu8Buffer&) { blot_support_pooled_buffer::deinit(self,pool_Scratchu8Buffer); self.len=0; self.failure=Error.none; }
