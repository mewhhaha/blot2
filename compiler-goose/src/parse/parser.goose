// Source contract: compiler/src/parse/parser.zig. Recursive descent and flat
// operator stack; unsupported checker constructs remain grammar-valid syntax.
namespace blot_parse_parser;
import .ast;
import .token;
import .lexer;
import .symbols;
import support.error;
import support.pooled_buffer;
import check.typed_staging_names;
type Id= u32;
type Tag=blot_parse_token::Tag;
type Error=blot_error::Error;
type Tree=blot_parse_ast::Tree;
type Span=blot_parse_ast::Span;
type List=blot_parse_ast::List;
type Token=blot_parse_token::Token;
type Symbol=blot_parse_symbols::Symbol;
struct Operator { symbol: Symbol, precedence: u32, association: u32, span: Span, known: bool, application: bool=false }
struct Where { predicates: List=List {}, node: Id=0 }
struct LambdaParameter { node: Id, pattern: Id, name: Symbol, start: u32 }
struct Qualifier { kind: u32, name: Symbol=0, value: Id, start: u32 }
struct Parser {
 pool: blot_parse_symbols::Pool&, tree: Tree&, recorded:ScratchIdBuffer?=null,
 index: i64=0, expression_end: i64=0x7fffffffffffffff,
 depth: i64=0, declaration_origin: Span=Span {}, collection_names: u32=0,
 test_count: u32=0, test_line: u32=1, test_line_offset: u32=0,
 failure: Error=blot_error::Error.none
}
fn current(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Token {
 if p.index>=p.expression_end { return Token {t_eof,tokens[p.index].start,tokens[p.index].start}; }
 if p.index<tokens.len { return tokens[p.index]; }
 return Token {t_eof,source.len as u32,source.len as u32};
}
fn at(p: Parser&,source: const u8[:],tokens: const Token[:],tag: Tag) -> bool { return current(p,source,tokens).tag==tag; }
fn peek(p: Parser&,tokens: const Token[:],offset: i64) -> Tag { if p.index+offset<tokens.len { return tokens[p.index+offset].tag; } return t_eof; }
fn text(p: Parser&,source: const u8[:],t: Token) -> const u8[:] { return source[t.start..t.end]; }
fn word(p: Parser&,source: const u8[:],tokens: const Token[:],bytes: const u8[:]) -> bool { return text(p,source,current(p,source,tokens))==bytes; }
fn advance(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Token { let t=current(p,source,tokens); if p.failure==blot_error::Error.none&&p.index<tokens.len { p.index++; } return t; }
fn eat(p: Parser&,source: const u8[:],tokens: const Token[:],tag: Tag) -> bool { if p.failure!=blot_error::Error.none||!at(p,source,tokens,tag) { return false; } advance(p,source,tokens); return true; }
fn report(p: Parser&,source: const u8[:],tokens: const Token[:],code: blot_parse_ast::Code) {
 let t=current(p,source,tokens);
 p.tree.diagnostics.push(blot_parse_ast::Diagnostic {code:code,start:t.start,end:t.end,has_declaration_origin:true,declaration_origin:p.declaration_origin,has_actual_token:true,actual_token:t.tag});
}
fn fail(p: Parser&,source: const u8[:],tokens: const Token[:],code: blot_parse_ast::Code) -> Id { if p.failure==blot_error::Error.none { report(p,source,tokens,code); p.failure=blot_error::Error.syntax; } return 0; }
fn expect(p: Parser&,source: const u8[:],tokens: const Token[:],tag: Tag) -> Token {
 if p.failure!=blot_error::Error.none { return current(p,source,tokens); }
 if !at(p,source,tokens,tag) { fail(p,source,tokens,c_expected_token); let i=p.tree.diagnostics.len-1; p.tree.diagnostics.items[i].has_expected_token=true; p.tree.diagnostics.items[i].expected_token=tag; return current(p,source,tokens); }
 return advance(p,source,tokens);
}
fn newlines(p: Parser&,source: const u8[:],tokens: const Token[:]) { while eat(p,source,tokens,t_newline) {} }
fn recover(p: Parser&,source: const u8[:],tokens: const Token[:],before: i64) {
 p.failure=blot_error::Error.none;
 if p.index==before&&!at(p,source,tokens,t_eof) { advance(p,source,tokens); }
 while !at(p,source,tokens,t_newline)&&!at(p,source,tokens,t_eof) { advance(p,source,tokens); }
 newlines(p,source,tokens); while eat(p,source,tokens,t_dedent) { newlines(p,source,tokens); }
}
fn enter(p: Parser&,source: const u8[:],tokens: const Token[:]) -> bool { if p.failure!=blot_error::Error.none { return false; } if p.depth>=256 { fail(p,source,tokens,c_nesting_limit); return false; } p.depth++; return true; }
fn add(p: Parser&,source: const u8[:],tokens: const Token[:],tag: u32,a: u32,b: u32,c: u32,start: u32) -> Id {
 if p.failure!=blot_error::Error.none { return 0; }
 if p.tree.nodes.len>=0xffffffff { return fail(p,source,tokens,c_table_limit); }
 var end=start; if p.index>0 { end=tokens[p.index-1].end; }
 let id,err=blot_parse_ast::addNodeAndSpan(p.tree,blot_parse_ast::Node {tag,a,b,c},Span {start,end});
 if err!=blot_error::Error.none { p.failure=err; return 0; }
 return id;
}
fn numeric_failure(p: Parser&,source: const u8[:],tokens: const Token[:],t: Token,code: u32) -> Id { return add(p,source,tokens,a_numeric_error,code,t.start,t.end,t.start); }
fn integer_literal(p: Parser&,source: const u8[:],tokens: const Token[:],t: Token,tag: u32) -> Id {
 if p.failure!=blot_error::Error.none { return 0; }
 let value,err=blot_parse_lexer::integer_value(text(p,source,t));
 if err==blot_error::Error.integer_range { return numeric_failure(p,source,tokens,t,blot_parse_ast::numericcode_integer_range); }
 if err!=blot_error::Error.none { return fail(p,source,tokens,c_invalid_literal); } return add(p,source,tokens,tag,value,0,0,t.start);
}
fn extra(p: Parser&,source: const u8[:],tokens: const Token[:],values: const u32[:]) -> u32 {
 if p.failure!=blot_error::Error.none { return 0; }
 if values.len>0xffffffff-p.tree.extra.len { return fail(p,source,tokens,c_table_limit); }
 let start=p.tree.extra.len as u32; p.tree.extra.append(values);
 if p.tree.extra.failure!=blot_error::Error.none { p.failure=p.tree.extra.failure; }
 return start;
}
fn list(p: Parser&,source: const u8[:],tokens: const Token[:],values: const u32[:]) -> List { let start=extra(p,source,tokens,values); return List {start,values.len as u32}; }
fn list_node(p: Parser&,source: const u8[:],tokens: const Token[:],tag: u32,values: const Id[:],start: u32) -> Id { let range=list(p,source,tokens,values); return add(p,source,tokens,tag,range.start,range.len,0,start); }
fn intern(p: Parser&,source: const u8[:],tokens: const Token[:],bytes: const u8[:]) -> Symbol {
 if p.failure!=blot_error::Error.none { return 0; }
 let symbol,err=blot_parse_symbols::intern(p.pool,bytes);
 if err==blot_error::Error.symbol_limit { return fail(p,source,tokens,c_table_limit); }
 if err!=blot_error::Error.none { p.failure=err; return 0; }
 let recorded .= p.recorded;
 if recorded {recorded.push(symbol);if recorded.failure!=blot_error::Error.none {p.failure=recorded.failure;}}
 return symbol;
}
fn identifier_syntax_at(p: Parser&,t: Token) -> Id {
 if p.failure!=blot_error::Error.none { return 0; }
 p.tree.diagnostics.push(blot_parse_ast::Diagnostic {code:c_GPU_FRONTEND_SYNTAX_ERROR,start:p.declaration_origin.start,end:p.declaration_origin.end,has_declaration_origin:true,declaration_origin:p.declaration_origin,has_detail_span:true,detail_span:Span {t.start,t.end},has_actual_token:true,actual_token:t.tag});
 p.failure=blot_error::Error.syntax; return 0;
}
fn identifier_syntax(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id { return identifier_syntax_at(p,current(p,source,tokens)); }
fn identifier(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Symbol {
 if p.failure!=blot_error::Error.none { return 0; } let t=current(p,source,tokens);
 if t.tag!=t_identifier&&t.tag!=t_type_identifier { return fail(p,source,tokens,c_expected_token); }
 advance(p,source,tokens); return intern(p,source,tokens,text(p,source,t));
}
fn lower_identifier(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Symbol { if at(p,source,tokens,t_type_identifier)||at(p,source,tokens,t_kw_true)||at(p,source,tokens,t_kw_false) { return identifier_syntax(p,source,tokens); } return identifier(p,source,tokens); }
fn type_identifier(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Symbol {
 if at(p,source,tokens,t_identifier)||at(p,source,tokens,t_kw_true)||at(p,source,tokens,t_kw_false) { return identifier_syntax(p,source,tokens); }
 let t=expect(p,source,tokens,t_type_identifier); let name=intern(p,source,tokens,text(p,source,t)); if at(p,source,tokens,t_dot) { return identifier_syntax(p,source,tokens); } return name;
}
fn member_tag(tag: Tag) -> bool { return tag==t_identifier||tag==t_type_identifier||tag==t_kw_not||tag==t_kw_with; }
fn member_identifier(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Symbol {
 if p.failure!=blot_error::Error.none { return 0; } let t=current(p,source,tokens);
 if !member_tag(t.tag) { return fail(p,source,tokens,c_expected_token); }
 advance(p,source,tokens); return intern(p,source,tokens,text(p,source,t));
}
fn member_qualified(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Symbol {
 let first=current(p,source,tokens); let name=member_identifier(p,source,tokens);
 if p.failure!=blot_error::Error.none||!at(p,source,tokens,t_dot)||current(p,source,tokens).start!=first.end||!member_tag(peek(p,tokens,1)) { return name; }
 var bytes=Scratchu8Buffer {}; for c in text(p,source,first) { bytes.push(c); }
 var last_end=first.end;
 while p.failure==blot_error::Error.none&&at(p,source,tokens,t_dot)&&current(p,source,tokens).start==last_end&&member_tag(peek(p,tokens,1)) {
  advance(p,source,tokens); let t=advance(p,source,tokens); last_end=t.end; intern(p,source,tokens,text(p,source,t)); bytes.push('.'); for c in text(p,source,t) { bytes.push(c); }
 }
 let __cleanup_result_mq_0: Symbol = intern(p,source,tokens,bytes.items); bytes.deinit(); return __cleanup_result_mq_0;
 bytes.deinit(); }
fn qualified(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Symbol {
 let first=current(p,source,tokens); let name=identifier(p,source,tokens);
 if p.failure!=blot_error::Error.none||!at(p,source,tokens,t_dot)||current(p,source,tokens).start!=first.end||!member_tag(peek(p,tokens,1)) { return name; }
 var bytes=Scratchu8Buffer {};  for c in text(p,source,first) { bytes.push(c); }
 var last_end=first.end;
 while p.failure==blot_error::Error.none&&at(p,source,tokens,t_dot)&&current(p,source,tokens).start==last_end&&member_tag(peek(p,tokens,1)) {
  advance(p,source,tokens); let t=advance(p,source,tokens); last_end=t.end; intern(p,source,tokens,text(p,source,t)); bytes.push('.'); for c in text(p,source,t) { bytes.push(c); }
 }
 let __cleanup_result_1_0: Symbol = intern(p,source,tokens,bytes.items); bytes.deinit(); return __cleanup_result_1_0;
 bytes.deinit(); }
fn constructor_pattern_name(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Symbol {
 let name=qualified(p,source,tokens); if p.failure!=blot_error::Error.none { return 0; }
 if tokens[p.index-1].tag!=t_type_identifier { return identifier_syntax_at(p,tokens[p.index-1]); } return name;
}
fn string_symbol(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Symbol {
 let t=expect(p,source,tokens,t_string); if p.failure!=blot_error::Error.none { return 0; }
 let raw=text(p,source,t); var bytes=Scratchu8Buffer {};  var i=1;
 while i+1<raw.len {
  var ch=raw[i]; if ch=='\\' {
   i++; let e=raw[i]; if e=='n' { ch='\n'; } else if e=='r' { ch='\r'; } else if e=='t' { ch='\t'; } else if e=='"'||e=='\\' { ch=e; } else { let __cleanup_result_2_0: Symbol = fail(p,source,tokens,c_invalid_literal); bytes.deinit(); return __cleanup_result_2_0; }
  }
  bytes.push(ch); i++;
 }
 let __cleanup_result_3_0: Symbol = intern(p,source,tokens,bytes.items); bytes.deinit(); return __cleanup_result_3_0;
 bytes.deinit(); }
recursive fn declaration(p: Parser&,source: const u8[:],tokens: const Token[:],declarations_seen: bool,body_declarations_seen: bool) -> Id {
 var private=false; var is_opaque=false;
 if at(p,source,tokens,t_hash)&&text(p,source,current(p,source,tokens))=="#"&&peek(p,tokens,1)==t_identifier&&peek(p,tokens,2)==t_identifier&&text(p,source,tokens[p.index+2])=="private" {
  let directive=text(p,source,tokens[p.index+1]);
  if directive=="kernel"||directive=="process" {
   advance(p,source,tokens); advance(p,source,tokens);
   let t=current(p,source,tokens); p.declaration_origin=Span {t.start,t.end};
   return fail(p,source,tokens,c_unexpected_token);
  }
 }
 if word(p,source,tokens,"io")&&peek(p,tokens,1)==t_identifier&&text(p,source,tokens[p.index+1])=="private"&&(peek(p,tokens,2)==t_kw_const||peek(p,tokens,2)==t_kw_let||peek(p,tokens,2)==t_kw_func||peek(p,tokens,2)==t_identifier) {
  advance(p,source,tokens);
  let t=current(p,source,tokens); p.declaration_origin=Span {t.start,t.end};
  return fail(p,source,tokens,c_unexpected_token);
 }
 if word(p,source,tokens,"private") { private=true; advance(p,source,tokens); if word(p,source,tokens,"private") { let t=current(p,source,tokens); p.declaration_origin=Span {t.start,t.end}; return fail(p,source,tokens,c_unexpected_token); } }
 if word(p,source,tokens,"export")&&peek(p,tokens,1)==t_l_brace { if private { return fail(p,source,tokens,c_unexpected_token); } return import_decl(p,source,tokens,true); }
 let id=declaration_body(p,source,tokens,declarations_seen,body_declarations_seen,is_opaque,private); if p.failure!=blot_error::Error.none { return 0; }
 if private||is_opaque { let tag=p.tree.node(id).tag; if tag==a_import_decl||(private&&(tag==a_entry_kernel_decl||tag==a_entry_process_decl)) { return fail(p,source,tokens,c_unexpected_token); } p.tree.declaration_traits.push(blot_parse_ast::DeclarationTraits {id,private,is_opaque}); }
 return id;
}
recursive fn declaration_body(p: Parser&,source: const u8[:],tokens: const Token[:],declarations_seen: bool,body_declarations_seen: bool,is_opaque: bool&,private: bool) -> Id {
 let first=current(p,source,tokens); p.declaration_origin=Span {first.start,first.end}; if p.depth==0 {p.collection_names=0;} let start=first.start;
 if at(p,source,tokens,t_kw_import) { if declarations_seen { return fail(p,source,tokens,c_unexpected_token); } return import_decl(p,source,tokens,false); }
 var attributes=ScratchIdBuffer {};
 while p.failure==blot_error::Error.none&&at(p,source,tokens,t_at) { let point=current(p,source,tokens).start; eat(p,source,tokens,t_at); expect(p,source,tokens,t_l_bracket); let body=expression(p,source,tokens); expect(p,source,tokens,t_r_bracket); attributes.push(add(p,source,tokens,a_attribute,body,0,0,point)); newlines(p,source,tokens); }
 let attrs=list(p,source,tokens,attributes.items); if p.failure!=blot_error::Error.none { let __cleanup_result_4_0: Id = 0; attributes.deinit(); return __cleanup_result_4_0; }
 if test_ahead(p,source,tokens) {
  attributes.deinit();
  let token=current(p,source,tokens);
  if private {
   p.declaration_origin=Span{token.start,token.end};
   return fail(p,source,tokens,c_unexpected_token);
  }
  return test_declaration(p,source,tokens,attrs);
 }
 if at(p,source,tokens,t_kw_type)||at(p,source,tokens,t_kw_data) { let __cleanup_result_8_0: Id = type_declaration(p,source,tokens,attrs,start,is_opaque); attributes.deinit(); return __cleanup_result_8_0; }
 if eat(p,source,tokens,t_kw_effect) { let name=qualified(p,source,tokens); expect(p,source,tokens,t_colon); let signature=type_expression(p,source,tokens); let __cleanup_result_9_0: Id = add(p,source,tokens,a_effect_decl,name,signature,extra(p,source,tokens,[attrs.start,attrs.len]),start); attributes.deinit(); return __cleanup_result_9_0; }
 var modifier: Symbol=0; var flags: u32=0;
 if at(p,source,tokens,t_hash)&&text(p,source,current(p,source,tokens))=="#" {
  if peek(p,tokens,1)!=t_identifier { attributes.deinit(); return fail(p,source,tokens,c_unexpected_token); }
  let directive=text(p,source,tokens[p.index+1]);
  if directive=="kernel" { let decl_id=entry_kernel_declaration(p,source,tokens,attrs,start); attributes.deinit(); return decl_id; }
  if directive=="process" { let decl_id=entry_process_declaration(p,source,tokens,attrs,start); attributes.deinit(); return decl_id; }
  if peek(p,tokens,2)==t_kw_const||peek(p,tokens,2)==t_kw_let||peek(p,tokens,2)==t_kw_func {
   advance(p,source,tokens); modifier=lower_identifier(p,source,tokens);
  } else {
   attributes.deinit(); return fail(p,source,tokens,c_unexpected_token);
  }
 } else if at(p,source,tokens,t_identifier)&&word(p,source,tokens,"io") {
  let next_tag=peek(p,tokens,1);
  if next_tag==t_kw_const||next_tag==t_kw_let {
   advance(p,source,tokens); flags=1; modifier=intern(p,source,tokens,"io");
  } else if next_tag==t_kw_func {
   modifier=lower_identifier(p,source,tokens);
  } else if next_tag==t_identifier||next_tag==t_type_identifier||next_tag==t_kw_true||next_tag==t_kw_false {
   let io_start=advance(p,source,tokens).start; flags=1; modifier=intern(p,source,tokens,"io");
   let declaration_id=function_declaration_body(p,source,tokens,attrs,start,io_start,modifier,flags); attributes.deinit(); return declaration_id;
  } else {
   attributes.deinit(); return fail(p,source,tokens,c_expected_token);
  }
 } else {
  if (at(p,source,tokens,t_type_identifier)||at(p,source,tokens,t_kw_true)||at(p,source,tokens,t_kw_false))&&(peek(p,tokens,1)==t_kw_const||peek(p,tokens,1)==t_kw_let||peek(p,tokens,1)==t_kw_func) { let __cleanup_result_10_0: Id = identifier_syntax(p,source,tokens); attributes.deinit(); return __cleanup_result_10_0; }
  if at(p,source,tokens,t_identifier)&&(peek(p,tokens,1)==t_kw_const||peek(p,tokens,1)==t_kw_let||peek(p,tokens,1)==t_kw_func) { modifier=lower_identifier(p,source,tokens); }
 }
 if at(p,source,tokens,t_kw_func) {let declaration_id=function_declaration(p,source,tokens,attrs,start,modifier,flags);attributes.deinit();return declaration_id;}
 var runtime: u32=0; if eat(p,source,tokens,t_kw_const) {} else if eat(p,source,tokens,t_kw_let) { runtime=1; } else { let __cleanup_result_11_0: Id = fail(p,source,tokens,c_expected_token); attributes.deinit(); return __cleanup_result_11_0; }
 let name_point=current(p,source,tokens).start; let name=qualified(p,source,tokens); var annotation: Id=0; if eat(p,source,tokens,t_colon) { annotation=type_expression(p,source,tokens); }
 let constraints=where_clause(p,source,tokens); expect(p,source,tokens,t_equal); let body=expression(p,source,tokens);
 let value=add(p,source,tokens,a_value_decl,name,body,extra(p,source,tokens,[annotation,modifier,runtime,constraints.predicates.start,constraints.predicates.len,attrs.start,attrs.len,flags,constraints.node]),start);
 if p.failure!=blot_error::Error.none { let __cleanup_result_12_0: Id = 0; attributes.deinit(); return __cleanup_result_12_0; }
 if runtime!=0 { p.tree.runtime_names.push(blot_parse_ast::RuntimeName {value,name_point}); } else { p.tree.constant_names.push(blot_parse_ast::RuntimeName {value,name_point}); } let __cleanup_result_13_0: Id = value; attributes.deinit(); return __cleanup_result_13_0;
 attributes.deinit(); }
fn import_decl(p: Parser&,source: const u8[:],tokens: const Token[:],forwarding: bool) -> Id {
 let start=current(p,source,tokens).start; if forwarding { advance(p,source,tokens); } else { expect(p,source,tokens,t_kw_import); }
 var bindings=ScratchIdBuffer {};  var name_space: Symbol=0; var namespace_span=Span {start,start};
 if !forwarding&&eat(p,source,tokens,t_star) { expect(p,source,tokens,t_kw_as); let t=current(p,source,tokens); name_space=lower_identifier(p,source,tokens); namespace_span=Span {t.start,t.end}; }
 else {
  expect(p,source,tokens,t_l_brace);
  while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_brace) { let point=current(p,source,tokens).start; let name=identifier(p,source,tokens); var alias=name; if eat(p,source,tokens,t_kw_as) { alias=identifier(p,source,tokens); } bindings.push(add(p,source,tokens,a_import_binding,name,alias,0,point)); if !eat(p,source,tokens,t_comma) { break; } }
  expect(p,source,tokens,t_r_brace);
 }
 if !eat(p,source,tokens,t_kw_from) { if !word(p,source,tokens,"from") { let __cleanup_result_14_0: Id = fail(p,source,tokens,c_expected_token); bindings.deinit(); return __cleanup_result_14_0; } advance(p,source,tokens); }
 let path_token=current(p,source,tokens); let path=string_symbol(p,source,tokens); let range=list(p,source,tokens,bindings.items); var tag=a_import_decl; if forwarding { tag=a_export_decl; }
 let __cleanup_result_15_0: Id = add(p,source,tokens,tag,path,range.start,extra(p,source,tokens,[range.len,name_space,path_token.start,path_token.end,namespace_span.start,namespace_span.end]),start); bindings.deinit(); return __cleanup_result_15_0;
 bindings.deinit(); }

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
let t_kw_not=blot_parse_token::kw_not;
let t_kw_with=blot_parse_token::kw_with;
let t_kw_fork=blot_parse_token::kw_fork;
let t_semicolon=blot_parse_token::semicolon;
let t_kw_spark=blot_parse_token::kw_spark;

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
let a_fork_expr=blot_parse_ast::tag_fork_expr;
let a_with_stmt=blot_parse_ast::tag_with_stmt;
let a_with_entry=blot_parse_ast::tag_with_entry;
let a_comptime_for=blot_parse_ast::tag_comptime_for;
let a_comptime_if=blot_parse_ast::tag_comptime_if;
let a_comptime_project=blot_parse_ast::tag_comptime_project;
let a_spark_expr=blot_parse_ast::tag_spark_expr;
let a_entry_kernel_decl=blot_parse_ast::tag_entry_kernel_decl;
let a_entry_process_decl=blot_parse_ast::tag_entry_process_decl;
let c_expected_token=blot_parse_ast::code_expected_token;
let c_expected_expression=blot_parse_ast::code_expected_expression;
let c_expected_type=blot_parse_ast::code_expected_type;
let c_expected_pattern=blot_parse_ast::code_expected_pattern;
let c_unexpected_token=blot_parse_ast::code_unexpected_token;
let c_invalid_literal=blot_parse_ast::code_invalid_literal;
let c_nesting_limit=blot_parse_ast::code_nesting_limit;
let c_table_limit=blot_parse_ast::code_table_limit;
let c_private_marker=blot_parse_ast::code_private_marker;
let c_GPU_FRONTEND_SYNTAX_ERROR=blot_parse_ast::code_GPU_FRONTEND_SYNTAX_ERROR;
let c_function_return_required=blot_parse_ast::code_function_return_required;
fn type_declaration(p: Parser&,source: const u8[:],tokens: const Token[:],attrs: List,start: u32,is_opaque: bool&) -> Id {
 let old_data=eat(p,source,tokens,t_kw_data); if !old_data { expect(p,source,tokens,t_kw_type); }
 let name=type_identifier(p,source,tokens); var params=ScratchIdBuffer {};
 if type_atom_tag(current(p,source,tokens).tag) { params.push(type_atom(p,source,tokens)); }
 while p.failure==blot_error::Error.none&&eat(p,source,tokens,t_fat_arrow) { expect(p,source,tokens,t_kw_type); params.push(type_atom(p,source,tokens)); }
 var trait_outputs=ScratchIdBuffer {};
 if !old_data&&eat(p,source,tokens,t_l_brace) {
  newlines(p,source,tokens);
  while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_brace) {
   let out_start=current(p,source,tokens).start;
   let out_name=lower_identifier(p,source,tokens);
   trait_outputs.push(add(p,source,tokens,a_contract_type_member,out_name,0,0,out_start));
   if eat(p,source,tokens,t_comma) { newlines(p,source,tokens); continue; }
   if at(p,source,tokens,t_newline) { newlines(p,source,tokens); continue; }
   break;
  }
  newlines(p,source,tokens); expect(p,source,tokens,t_r_brace);
 }
 if !old_data&&trait_outputs.len==0&&eat(p,source,tokens,t_equal) {
  let body=type_expression(p,source,tokens); let range=list(p,source,tokens,params.items);
  let __cleanup_result_17_0: Id = add(p,source,tokens,a_type_alias_decl,name,body,extra(p,source,tokens,[range.start,range.len,attrs.start,attrs.len]),start); trait_outputs.deinit(); params.deinit(); return __cleanup_result_17_0;
 }
 var effect=false;
 if !old_data {
  expect(p,source,tokens,t_kw_is);
  if word(p,source,tokens,"trait") {
   advance(p,source,tokens); expect(p,source,tokens,t_equal);
   let body_start=expect(p,source,tokens,t_l_brace).start; newlines(p,source,tokens);
   var members=ScratchIdBuffer {};
   for out_id in trait_outputs.items { members.push(out_id); }
   while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_brace) {
    let point=current(p,source,tokens).start;
    let field=lower_identifier(p,source,tokens);
    expect(p,source,tokens,t_colon);
    let ty=type_expression(p,source,tokens);
    members.push(add(p,source,tokens,a_contract_value_member,field,ty,0,point));
    if eat(p,source,tokens,t_comma) { newlines(p,source,tokens); continue; }
    if at(p,source,tokens,t_newline) { newlines(p,source,tokens); continue; }
    break;
   }
   newlines(p,source,tokens); expect(p,source,tokens,t_r_brace);
   let body=list_node(p,source,tokens,a_where_clause,members.items,body_start);
   let range=list(p,source,tokens,params.items);
   let trait_result: Id = add(p,source,tokens,a_contract_decl,name,body,extra(p,source,tokens,[range.start,range.len,attrs.start,attrs.len]),start);
   members.deinit(); trait_outputs.deinit(); params.deinit(); return trait_result;
  }
  if trait_outputs.len!=0 { let err_res=fail(p,source,tokens,c_expected_token); trait_outputs.deinit(); params.deinit(); return err_res; }
  // An opaque representation is data with one private constructor spelled like its type.
  if word(p,source,tokens,"opaque") { advance(p,source,tokens); expect(p,source,tokens,t_equal); let body=type_expression(p,source,tokens); let range=list(p,source,tokens,params.items); let constructor=add(p,source,tokens,a_constructor_ref,name,body,0,start); let constructors=list_node(p,source,tokens,a_constructors,[constructor],start); is_opaque=true; let opaque_result: Id = add(p,source,tokens,a_data_decl,name,constructors,extra(p,source,tokens,[range.start,range.len,attrs.start,attrs.len]),start); trait_outputs.deinit(); params.deinit(); return opaque_result; }
  if eat(p,source,tokens,t_kw_effect) { effect=true; } else { expect(p,source,tokens,t_kw_data); }
 }
 trait_outputs.deinit();
 expect(p,source,tokens,t_equal); var body: Id=0;
 if effect {
  if eat(p,source,tokens,t_l_brace) {
   var operations=ScratchIdBuffer {};  newlines(p,source,tokens);
   while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_brace) {
    let point=current(p,source,tokens).start; let field=lower_identifier(p,source,tokens); expect(p,source,tokens,t_colon); let ty=type_expression(p,source,tokens); operations.push(add(p,source,tokens,a_effect_operation,field,ty,0,point));
    if eat(p,source,tokens,t_comma) { newlines(p,source,tokens); continue; } if at(p,source,tokens,t_newline) { newlines(p,source,tokens); continue; } break;
   }
   expect(p,source,tokens,t_r_brace); body=list_node(p,source,tokens,a_effect_operations,operations.items,start);
   operations.deinit(); } else { body=type_expression(p,source,tokens); }
 } else {
  var constructors=ScratchIdBuffer {};  eat(p,source,tokens,t_pipe);
  while p.failure==blot_error::Error.none {
   newlines(p,source,tokens);
   var c_attrs=ScratchIdBuffer {};
   while p.failure==blot_error::Error.none&&at(p,source,tokens,t_at) {
    let ap=current(p,source,tokens).start; eat(p,source,tokens,t_at); expect(p,source,tokens,t_l_bracket);
    let ab=expression(p,source,tokens); expect(p,source,tokens,t_r_bracket);
    c_attrs.push(add(p,source,tokens,a_attribute,ab,0,0,ap)); newlines(p,source,tokens);
   }
   let point=expect(p,source,tokens,t_hash).start; let constructor=type_identifier(p,source,tokens); var payload: Id=0; if type_atom_at(p,source,tokens,0) { payload=type_expression(p,source,tokens); }
   var c_meta: u32=0;
   if c_attrs.len!=0 { let cr=list(p,source,tokens,c_attrs.items); c_meta=extra(p,source,tokens,[cr.start,cr.len])+1; }
   c_attrs.deinit();
   constructors.push(add(p,source,tokens,a_constructor_ref,constructor,payload,c_meta,point)); if !eat(p,source,tokens,t_pipe) { break; }
  }
  body=list_node(p,source,tokens,a_constructors,constructors.items,start);
  constructors.deinit(); }
 let range=list(p,source,tokens,params.items); var tag=a_data_decl; if effect { tag=a_effect_type_decl; }
 let __cleanup_result_20_0: Id = add(p,source,tokens,tag,name,body,extra(p,source,tokens,[range.start,range.len,attrs.start,attrs.len]),start); params.deinit(); return __cleanup_result_20_0;
 params.deinit(); }
fn where_clause(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Where { let start=current(p,source,tokens).start; if !eat(p,source,tokens,t_kw_where) { return Where {}; } return predicate_body(p,source,tokens,start); }
recursive fn predicate_body(p: Parser&,source: const u8[:],tokens: const Token[:],start: u32) -> Where {
 expect(p,source,tokens,t_l_brace); newlines(p,source,tokens); var predicates=ScratchIdBuffer {};
 while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_brace) { predicates.push(contract_item(p,source,tokens)); if !eat(p,source,tokens,t_comma) { break; } newlines(p,source,tokens); }
 newlines(p,source,tokens); expect(p,source,tokens,t_r_brace); let range=list(p,source,tokens,predicates.items); let id=add(p,source,tokens,a_where_clause,range.start,range.len,0,start); let __cleanup_result_24_0: Where = Where {range,id}; predicates.deinit(); return __cleanup_result_24_0;
 predicates.deinit(); }
recursive fn contract_item(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 let start=current(p,source,tokens).start;
 let kind=qualified(p,source,tokens); var member: Symbol=0; if at(p,source,tokens,t_string) { member=string_symbol(p,source,tokens); }
 var args=ScratchIdBuffer {};
 while p.failure==blot_error::Error.none&&type_atom_at(p,source,tokens,0) {
  let point=current(p,source,tokens).start; let grouped=at(p,source,tokens,t_l_paren); var arg=type_atom(p,source,tokens);
  if p.failure!=blot_error::Error.none { let __cleanup_result_25_0: Id = 0; args.deinit(); return __cleanup_result_25_0; }
  if grouped&&p.tree.span(arg).start!=point { arg=add(p,source,tokens,a_group,arg,0,0,point); } args.push(arg);
 }
 var row: Id=0; if at(p,source,tokens,t_bang) { row=effect_row(p,source,tokens); } let range=list(p,source,tokens,args.items);
 let __cleanup_result_26_0: Id = add(p,source,tokens,a_constraint,kind,member,extra(p,source,tokens,[range.start,range.len,row]),start); args.deinit(); return __cleanup_result_26_0;
 args.deinit(); }
recursive fn type_expression(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 if !enter(p,source,tokens) { return 0; }
 let start=current(p,source,tokens).start; var parts=ScratchIdBuffer {};  parts.push(type_application(p,source,tokens));
 while p.failure==blot_error::Error.none&&eat(p,source,tokens,t_arrow) { parts.push(type_application(p,source,tokens)); }
 var row: Id=0; if at(p,source,tokens,t_bang) { row=effect_row(p,source,tokens); } if p.failure!=blot_error::Error.none { let __cleanup_result_1_0: Id = 0; { p.depth--; } let __cleanup_result_27_0: Id = __cleanup_result_1_0; parts.deinit(); return __cleanup_result_27_0; }
 var value=parts.items[parts.len-1]; var i=parts.len-1;
 while i!=0 {
  i--; let result=value; var effects: Id=0; if i==0 { effects=row; }
  value=add(p,source,tokens,a_type_function,parts.items[i],result,effects,p.tree.span(parts.items[i]).start); if p.failure!=blot_error::Error.none { let __cleanup_result_2_0: Id = 0; { p.depth--; } let __cleanup_result_28_0: Id = __cleanup_result_2_0; parts.deinit(); return __cleanup_result_28_0; }
  var end=p.tree.span(result).end; if i==0&&row!=0 { end=p.tree.span(row).end; } p.tree.spans.items[value].end=end;
 }
 if parts.len==1&&row!=0 { let __cleanup_result_3_0: Id = add(p,source,tokens,a_type_effect,value,row,0,start); { p.depth--; } let __cleanup_result_29_0: Id = __cleanup_result_3_0; parts.deinit(); return __cleanup_result_29_0; } let __cleanup_result_4_0: Id = value; { p.depth--; } let __cleanup_result_30_0: Id = __cleanup_result_4_0; parts.deinit(); return __cleanup_result_30_0;
 { p.depth--; }  parts.deinit(); }
recursive fn type_application(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 let start=current(p,source,tokens).start;
 // `own T`: the parameter of this type is taken over. `own` is a word only
 // before a type; alone, or before `->`, it is still a type variable.
 let taken=at(p,source,tokens,t_identifier)&&text(p,source,current(p,source,tokens))=="own"&&type_atom_at(p,source,tokens,1);
 if taken { advance(p,source,tokens); }
 var value=type_atom(p,source,tokens);
 while p.failure==blot_error::Error.none&&type_atom_at(p,source,tokens,0) { let arg=type_atom(p,source,tokens); value=add(p,source,tokens,a_type_apply,value,arg,0,start); }
 if taken&&p.failure==blot_error::Error.none { let end=p.tree.span(value).end; value=add(p,source,tokens,a_type_usage,blot_parse_ast::usagekind_own as u32,value,0,start); p.tree.spans.items[value].end=end; }
 return value;
}
recursive fn type_atom(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 if !enter(p,source,tokens) { return 0; }  let start=current(p,source,tokens).start;
 if at(p,source,tokens,t_star) {
  advance(p,source,tokens); let inner=type_atom(p,source,tokens);
  let head=add(p,source,tokens,a_type_name,intern(p,source,tokens,"@storage.Shared"),0,0,start);
  let __cleanup_result_star_0: Id = add(p,source,tokens,a_type_apply,head,inner,0,start); { p.depth--; } return __cleanup_result_star_0;
 }
 if at(p,source,tokens,t_hash)&&text(p,source,current(p,source,tokens))=="#"&&peek(p,tokens,1)==t_l_bracket {
  advance(p,source,tokens); advance(p,source,tokens);
  var has_semi=false; var nest=0; var scan=p.index;
  while scan<tokens.len {
   let st=tokens[scan].tag;
   if st==t_l_paren||st==t_l_bracket||st==t_l_brace { nest++; }
   else if st==t_r_paren||st==t_r_bracket||st==t_r_brace { if nest==0 { break; } nest--; }
   else if st==t_semicolon&&nest==0 { has_semi=true; break; }
   else if (st==t_newline||st==t_eof)&&nest==0 { break; }
   scan++;
  }
  var len_node: Id=0;
  if has_semi {
   let lt=current(p,source,tokens);
   if lt.tag==t_integer {
    advance(p,source,tokens);
    let len_name=str("@storage.Len.",text(p,source,lt));
    len_node=add(p,source,tokens,a_type_name,intern(p,source,tokens,len_name),0,0,lt.start);
   } else if lt.tag==t_identifier {
    len_node=add(p,source,tokens,a_type_name,lower_identifier(p,source,tokens),0,0,lt.start);
   } else {
    let __cleanup_result_len_0: Id = fail(p,source,tokens,c_expected_type); { p.depth--; } return __cleanup_result_len_0;
   }
   expect(p,source,tokens,t_semicolon);
  }
  let elem=type_expression(p,source,tokens);
  expect(p,source,tokens,t_r_bracket);
  if has_semi {
   let head=add(p,source,tokens,a_type_name,intern(p,source,tokens,"@storage.SizedArray"),0,0,start);
   let partial=add(p,source,tokens,a_type_apply,head,len_node,0,start);
   let __cleanup_result_sized_0: Id = add(p,source,tokens,a_type_apply,partial,elem,0,start); { p.depth--; } return __cleanup_result_sized_0;
  }
  let head=add(p,source,tokens,a_type_name,intern(p,source,tokens,"Array"),0,0,start);
  let __cleanup_result_arr_0: Id = add(p,source,tokens,a_type_apply,head,elem,0,start); { p.depth--; } return __cleanup_result_arr_0;
 }
 if at(p,source,tokens,t_caret)||(at(p,source,tokens,t_symbol)&&text(p,source,current(p,source,tokens))=="&") {
  let link=advance(p,source,tokens).tag==t_caret; let view=!link&&eat(p,source,tokens,t_l_bracket); var storage_name: const u8[:]="@storage.Ref";
  if link { storage_name="@storage.Link"; } else if view { storage_name="@storage.View"; }
  let name=add(p,source,tokens,a_type_name,intern(p,source,tokens,storage_name),0,0,start); var element: Id=0;
  if view { element=type_expression(p,source,tokens); expect(p,source,tokens,t_r_bracket); } else { element=type_atom(p,source,tokens); }
  let __cleanup_result_5_0: Id = add(p,source,tokens,a_type_apply,name,element,0,start); { p.depth--; } return __cleanup_result_5_0;
 }
 if at(p,source,tokens,t_identifier)||at(p,source,tokens,t_type_identifier) { let __cleanup_result_13_0: Id = add(p,source,tokens,a_type_name,qualified(p,source,tokens),0,0,start); { p.depth--; } return __cleanup_result_13_0; }
 if eat(p,source,tokens,t_l_brace) {
  var fields=ScratchIdBuffer {}; newlines(p,source,tokens);
  while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_brace) {
   let point=current(p,source,tokens).start;
   var f_attrs=ScratchIdBuffer {};
   while p.failure==blot_error::Error.none&&at(p,source,tokens,t_at) {
    let ap=current(p,source,tokens).start; eat(p,source,tokens,t_at); expect(p,source,tokens,t_l_bracket);
    let ab=expression(p,source,tokens); expect(p,source,tokens,t_r_bracket);
    f_attrs.push(add(p,source,tokens,a_attribute,ab,0,0,ap)); newlines(p,source,tokens);
   }
   let name=lower_identifier(p,source,tokens); var value: Id=0; if eat(p,source,tokens,t_colon) { value=type_expression(p,source,tokens); }
   var def_expr: Id=0; if eat(p,source,tokens,t_equal) { def_expr=expression(p,source,tokens); }
   var f_meta: u32=0;
   if f_attrs.len!=0||def_expr!=0 {
    let fr=list(p,source,tokens,f_attrs.items);
    f_meta=extra(p,source,tokens,[fr.start,fr.len,def_expr])+1;
   }
   f_attrs.deinit();
   fields.push(add(p,source,tokens,a_type_field,name,value,f_meta,point));
   if eat(p,source,tokens,t_comma) { newlines(p,source,tokens); continue; }
   if at(p,source,tokens,t_newline) { newlines(p,source,tokens); continue; }
   break;
  }
  newlines(p,source,tokens); expect(p,source,tokens,t_r_brace); let __cleanup_result_14_0: Id = list_node(p,source,tokens,a_type_record,fields.items,start); { p.depth--; } let __cleanup_result_31_0: Id = __cleanup_result_14_0; fields.deinit(); return __cleanup_result_31_0;
  fields.deinit(); }
 let array=eat(p,source,tokens,t_l_bracket); if !array&&!eat(p,source,tokens,t_l_paren) { let __cleanup_result_15_0: Id = fail(p,source,tokens,c_expected_type); { p.depth--; } return __cleanup_result_15_0; }
 if !array&&at(p,source,tokens,t_identifier)&&peek(p,tokens,1)==t_colon { let name=lower_identifier(p,source,tokens); expect(p,source,tokens,t_colon); let annotation=type_expression(p,source,tokens); expect(p,source,tokens,t_r_paren); let __cleanup_result_16_0: Id = add(p,source,tokens,a_type_binder,name,annotation,0,start); { p.depth--; } return __cleanup_result_16_0; }
 var end=t_r_paren; if array { end=t_r_bracket; } var values=ScratchIdBuffer {};  var tuple=false;
 while p.failure==blot_error::Error.none&&!at(p,source,tokens,end) { values.push(type_expression(p,source,tokens)); if !eat(p,source,tokens,t_comma) { break; } tuple=true; }
 expect(p,source,tokens,end); if p.failure!=blot_error::Error.none { let __cleanup_result_17_0: Id = 0; { p.depth--; } let __cleanup_result_32_0: Id = __cleanup_result_17_0; values.deinit(); return __cleanup_result_32_0; }
 if !array&&!tuple&&values.len==1 { p.tree.type_conversion_origins.push(blot_parse_ast::TypeConversionOrigin {values.items[0],start}); let __cleanup_result_18_0: Id = values.items[0]; { p.depth--; } let __cleanup_result_33_0: Id = __cleanup_result_18_0; values.deinit(); return __cleanup_result_33_0; }
 var tag=a_type_product; if array { tag=a_type_array; } let __cleanup_result_19_0: Id = list_node(p,source,tokens,tag,values.items,start); { p.depth--; } let __cleanup_result_34_0: Id = __cleanup_result_19_0; values.deinit(); return __cleanup_result_34_0;
 { p.depth--; }  values.deinit(); }
recursive fn effect_row(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id { let start=expect(p,source,tokens,t_bang).start; return effect_row_body(p,source,tokens,start); }
recursive fn effect_row_body(p: Parser&,source: const u8[:],tokens: const Token[:],start: u32) -> Id {
 expect(p,source,tokens,t_l_brace); var labels=ScratchIdBuffer {};
 while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_pipe)&&!at(p,source,tokens,t_r_brace) { labels.push(type_application(p,source,tokens)); if !eat(p,source,tokens,t_comma) { break; } }
 var tail: Id=0; if eat(p,source,tokens,t_pipe) { let t=current(p,source,tokens); let name=lower_identifier(p,source,tokens); tail=add(p,source,tokens,a_type_name,name,0,0,t.start); }
 expect(p,source,tokens,t_r_brace); let range=list(p,source,tokens,labels.items); let __cleanup_result_37_0: Id = add(p,source,tokens,a_effect_row,range.start,range.len,tail,start); labels.deinit(); return __cleanup_result_37_0;
 labels.deinit(); }
fn fork_ahead(p: Parser&,source: const u8[:],tokens: const Token[:]) -> bool {
 if !at(p,source,tokens,t_identifier)||!word(p,source,tokens,"fork") { return false; }
 var scan=p.index+1;
 if scan>=tokens.len||tokens[scan].tag!=t_identifier { return false; }
 scan++;
 while scan<tokens.len&&tokens[scan].tag==t_comma {
  scan++;
  if scan>=tokens.len||tokens[scan].tag!=t_identifier { return false; }
  scan++;
 }
 return scan<tokens.len&&tokens[scan].tag==t_colon;
}
recursive fn fork_expression(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 let start=advance(p,source,tokens).start;
 var entries=ScratchIdBuffer {};
 while p.failure==blot_error::Error.none {
  let pt=current(p,source,tokens).start;
  let sym=lower_identifier(p,source,tokens);
  let outer=add(p,source,tokens,a_name,sym,0,0,pt);
  entries.push(add(p,source,tokens,a_field,sym,outer,0,pt));
  if !eat(p,source,tokens,t_comma) { break; }
 }
 expect(p,source,tokens,t_colon);
 let body=suite(p,source,tokens);
 let range=list(p,source,tokens,entries.items);
 let result: Id = add(p,source,tokens,a_fork_expr,range.start,range.len,body,start);
 entries.deinit();
 return result;
}
recursive fn expression(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 if !enter(p,source,tokens) { return 0; }
 if fork_ahead(p,source,tokens) { let __cleanup_result_fork_0: Id = fork_expression(p,source,tokens); { p.depth--; } return __cleanup_result_fork_0; }
 if at(p,source,tokens,t_kw_func) { let __cleanup_result_28_0: Id = lambda(p,source,tokens); { p.depth--; } return __cleanup_result_28_0; } if at(p,source,tokens,t_kw_do) { let __cleanup_result_29_0: Id = do_block(p,source,tokens); { p.depth--; } return __cleanup_result_29_0; } if at(p,source,tokens,t_kw_if) { let __cleanup_result_30_0: Id = if_expression(p,source,tokens); { p.depth--; } return __cleanup_result_30_0; } if at(p,source,tokens,t_kw_case) { let __cleanup_result_31_0: Id = case_expression(p,source,tokens); { p.depth--; } return __cleanup_result_31_0; } let __cleanup_result_32_0: Id = infix(p,source,tokens); { p.depth--; } return __cleanup_result_32_0;
 { p.depth--; } }
fn test_ahead(p: Parser&,source: const u8[:],tokens: const Token[:]) -> bool {
 if !at(p,source,tokens,t_identifier) || !word(p,source,tokens,"test") { return false; }
 return peek(p,tokens,1)==t_string ||
  (peek(p,tokens,1)==t_identifier && peek(p,tokens,2)==t_string && text(p,source,tokens[p.index+1])=="expect_trap");
}
fn test_symbol(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Symbol {
 // User identifiers can use the same prefix, including declarations later in the file.
 while true {
  let spelling=str("__blot_test_",p.test_count);
  p.test_count++;
  var collision=false;
  for token in tokens {
   if token.tag==t_identifier && text(p,source,token)==spelling { collision=true; break; }
  }
  if !collision { return intern(p,source,tokens,spelling); }
 }
 abort("test symbol search ended unexpectedly");
}
recursive fn test_declaration(p: Parser&,source: const u8[:],tokens: const Token[:],attributes: List) -> Id {
 let start=advance(p,source,tokens).start;
 let is_trap=eat(p,source,tokens,t_identifier);
 let display_name=string_symbol(p,source,tokens);
 for byte in source[p.test_line_offset..start] {
  if byte=='\n' { p.test_line++; }
 }
 p.test_line_offset=start;
 let parameter=add(p,source,tokens,a_parameter,0,0,extra(p,source,tokens,[1 as u32,0,0,0]),start);
 var body:Id=0;
 if eat(p,source,tokens,t_colon) {
  body=suite(p,source,tokens);
 } else {
  expect(p,source,tokens,t_fat_arrow);
  let parsed,is_suite=lambda_body(p,source,tokens);
  body=parsed;
  if is_suite && p.failure==blot_error::Error.none { p.tree.extra.items[p.tree.node(parameter).c]|=2; }
 }
 if p.failure!=blot_error::Error.none { return 0; }
 let lambda_id=add(p,source,tokens,a_lambda,parameter,body,0,start);
 let name=test_symbol(p,source,tokens);
 let declaration_id=add(p,source,tokens,a_value_decl,name,lambda_id,
  extra(p,source,tokens,[0 as u32,0,0,0,0,attributes.start,attributes.len,0,0]),start);
 if p.failure!=blot_error::Error.none { return 0; }
 p.tree.constant_names.push(blot_parse_ast::RuntimeName{declaration_id,start});
 p.tree.declaration_traits.push(blot_parse_ast::DeclarationTraits{declaration_id,true,false});
 p.tree.test_meta.push(blot_parse_ast::TestMeta{declaration_id,display_name,p.test_line,is_trap});
 return declaration_id;
}
recursive fn function_declaration_body(p:Parser&,source:const u8[:],tokens:const Token[:],attributes:List,start:u32,function_start:u32,modifier:Symbol,flags:u32)->Id {
 let name_token=current(p,source,tokens);if name_token.tag==t_kw_true||name_token.tag==t_kw_false {return identifier_syntax_at(p,name_token);}
 let name_point=name_token.start;let name=qualified(p,source,tokens);if p.failure!=blot_error::Error.none {return 0;}
 if name_token.tag==t_type_identifier&&tokens[p.index-1].start==name_token.start {return identifier_syntax_at(p,name_token);}
 var constraints=Where {};if !enter(p,source,tokens) {return 0;}let body=lambda_tail(p,source,tokens,function_start,true,constraints);p.depth--;if p.failure!=blot_error::Error.none {return 0;}
 let declaration_id=add(p,source,tokens,a_value_decl,name,body,extra(p,source,tokens,[0 as u32,modifier,0,constraints.predicates.start,constraints.predicates.len,attributes.start,attributes.len,flags|2,constraints.node]),start);if p.failure!=blot_error::Error.none {return 0;}
 p.tree.constant_names.push(blot_parse_ast::RuntimeName{declaration_id,name_point});return declaration_id;
}
recursive fn function_declaration(p:Parser&,source:const u8[:],tokens:const Token[:],attributes:List,start:u32,modifier:Symbol,flags:u32)->Id {
 let function_start=expect(p,source,tokens,t_kw_func).start;if p.failure!=blot_error::Error.none {return 0;}
 return function_declaration_body(p,source,tokens,attributes,start,function_start,modifier,flags);
}
recursive fn lambda(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 let start=expect(p,source,tokens,t_kw_func).start;if p.failure!=blot_error::Error.none {return 0;}var constraints=Where {};return lambda_tail(p,source,tokens,start,false,constraints);
}
recursive fn lambda_tail(p:Parser&,source:const u8[:],tokens:const Token[:],start:u32,declaration:bool,declaration_where:Where&)->Id {
 var parameters=ScratchLambdaParameterBuffer {};
 while p.failure==blot_error::Error.none {
  let point=current(p,source,tokens).start; var unit=false; var own=false; var name: Symbol=0; var annotation: Id=0; var constraints=Where {}; var pattern_parameter: Id=0;
  if eat(p,source,tokens,t_l_paren) {
   if eat(p,source,tokens,t_r_paren) { unit=true; }
   else if at(p,source,tokens,t_hash) { pattern_parameter=pattern(p,source,tokens); expect(p,source,tokens,t_r_paren); name=collection_name(p,source,tokens,point); }
   else if at(p,source,tokens,t_identifier)&&text(p,source,current(p,source,tokens))=="own"&&peek(p,tokens,1)==t_identifier&&peek(p,tokens,2)==t_r_paren {
    // `(own name)`: a parameter taken over whose type is left to be found.
    advance(p,source,tokens); own=true; name=lower_identifier(p,source,tokens); expect(p,source,tokens,t_r_paren);
   }
   else {
    name=lower_identifier(p,source,tokens); expect(p,source,tokens,t_colon);
    // `own` before the whole type marks a parameter the function takes
    // over; before a function type's first part it belongs to that type.
    annotation=type_expression(p,source,tokens);
    if p.failure==blot_error::Error.none&&p.tree.node(annotation).tag==a_type_usage&&p.tree.node(annotation).a==(blot_parse_ast::usagekind_own as u32) { own=true; annotation=p.tree.node(annotation).b; } constraints=where_clause(p,source,tokens); expect(p,source,tokens,t_r_paren);
   }
  } else { name=lower_identifier(p,source,tokens); }
  var flags: u32=0; if unit { flags=1; } if own { flags|=8; }
  let parameter=add(p,source,tokens,a_parameter,name,annotation,extra(p,source,tokens,[flags,constraints.predicates.start,constraints.predicates.len,constraints.node]),point);
  if p.failure!=blot_error::Error.none { let __cleanup_result_38_0: Id = 0; parameters.deinit(); return __cleanup_result_38_0; } if pattern_parameter!=0 { p.tree.extra.items[p.tree.node(parameter).c]|=4; }
  parameters.push(LambdaParameter {parameter,pattern_parameter,name,point}); if !eat(p,source,tokens,t_arrow) { break; } if parameters.len>=256 { let __cleanup_result_39_0: Id = fail(p,source,tokens,c_nesting_limit); parameters.deinit(); return __cleanup_result_39_0; }
 }
 var result: Id=0; if eat(p,source,tokens,t_colon) { result=type_expression(p,source,tokens); } if declaration { declaration_where=where_clause(p,source,tokens); } expect(p,source,tokens,t_fat_arrow);
 let parsed_body,is_suite_body=lambda_body(p,source,tokens);
 var body=parsed_body;
 if p.failure!=blot_error::Error.none { let __cleanup_result_41_0: Id = 0; parameters.deinit(); return __cleanup_result_41_0; }
 if is_suite_body { p.tree.extra.items[p.tree.node(parameters.items[parameters.len-1].node).c]|=2; }
 var index=parameters.len;
 while index!=0 {
  index--; let parameter=parameters.items[index];
  if parameter.pattern!=0 { let argument=add(p,source,tokens,a_name,parameter.name,0,0,parameter.start); let binding=add(p,source,tokens,a_let_stmt,parameter.pattern,argument,extra(p,source,tokens,[0 as u32,0,0,0,0]),parameter.start); let result_statement=add(p,source,tokens,a_return_stmt,body,0,0,parameter.start); body=list_node(p,source,tokens,a_block,[binding,result_statement],parameter.start); }
  var annotation: Id=0; if index==parameters.len-1 { annotation=result; } var point=parameter.start; if index==0 { point=start; } body=add(p,source,tokens,a_lambda,parameter.node,body,annotation,point);
 }
 let __cleanup_result_42_0: Id = body; parameters.deinit(); return __cleanup_result_42_0;
 parameters.deinit(); }
recursive fn lambda_body(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id,bool {
 var body: Id=0; var is_suite_body=false;
 if at(p,source,tokens,t_newline)&&peek(p,tokens,1)==t_indent {
  return suite_body(p,source,tokens,true,true);
 } else {
  let returned=eat(p,source,tokens,t_kw_return);
  if returned&&eat(p,source,tokens,t_kw_use) {
   let ret_start=current(p,source,tokens).start;
   let tmp=collection_name(p,source,tokens,ret_start);
   let used=expression(p,source,tokens);
   let use_stmt=add(p,source,tokens,a_use_stmt,tmp,used,0,ret_start);
   let tmp_ref=add(p,source,tokens,a_name,tmp,0,0,ret_start);
   let ret_stmt=add(p,source,tokens,a_function_return_stmt,tmp_ref,0,0,ret_start);
   body=list_node(p,source,tokens,a_block,[use_stmt,ret_stmt],ret_start);
   is_suite_body=true;
  } else if !returned&&(at(p,source,tokens,t_kw_use)||assignment_operator(p,tokens)==t_colon_equal||assignment_operator(p,tokens)==t_equal) {
   let stmt_start=current(p,source,tokens).start;
   let single=statement(p,source,tokens);
   body=list_node(p,source,tokens,a_block,[single],stmt_start);
   is_suite_body=false;
  } else {
   body=expression(p,source,tokens);
   if !returned&&p.failure==blot_error::Error.none&&p.tree.node(body).tag==a_block&&p.tree.node(body).c==0 { is_suite_body=true; }
  }
 }
 return body,is_suite_body;
}
recursive fn do_block(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id { let start=expect(p,source,tokens,t_kw_do).start; var resolver: Id=0; if !at(p,source,tokens,t_colon) { resolver=application(p,source,tokens,false); } expect(p,source,tokens,t_colon); let block_=suite(p,source,tokens); if p.failure!=blot_error::Error.none { return 0; } p.tree.nodes.items[block_].c=resolver; p.tree.spans.items[block_].start=start; return block_; }
recursive fn if_expression(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id { let start=expect(p,source,tokens,t_kw_if).start; let condition=infix(p,source,tokens); expect(p,source,tokens,t_kw_then); let consequence=expression(p,source,tokens); expect(p,source,tokens,t_kw_else); let fallback=expression(p,source,tokens); return add(p,source,tokens,a_if_expr,condition,consequence,fallback,start); }
fn builtin_fixity(spelling: const u8[:]) -> u32, u32, bool {
 if spelling=="|>" { return 5,0,true; }
 if spelling=="or" { return 20,1,true; }
 if spelling=="and" { return 25,1,true; }
 if spelling=="=="||spelling=="!="||spelling=="<"||spelling=="<="||spelling==">"||spelling==">=" { return 30,2,true; }
 if spelling=="|" { return 40,0,true; }
 if spelling=="^" { return 45,0,true; }
 if spelling=="&" { return 50,0,true; }
 if spelling=="<<"||spelling==">>" { return 55,0,true; }
 if spelling=="+"||spelling=="-" { return 60,0,true; }
 if spelling=="*"||spelling=="/"||spelling=="%" { return 70,0,true; }
 return 0,0,false;
}
fn read_operator(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Operator {
 let t=advance(p,source,tokens); let span=Span {t.start,t.end}; let spelling=text(p,source,t);
 let symbol=intern(p,source,tokens,spelling);
 if spelling=="$" { return Operator {symbol,0,1,span,true,true}; }
 let precedence,association,known=builtin_fixity(spelling);
 return Operator {symbol,precedence,association,span,known,false};
}
fn stop_infix_for_not(p: Parser&,source: const u8[:],tokens: const Token[:]) -> bool {
 let tag=current(p,source,tokens).tag;
 if tag==t_kw_and||tag==t_kw_or||tag==t_dollar { return true; }
 if tag==t_symbol {
  let spelling=text(p,source,current(p,source,tokens));
  let prec,_,known=builtin_fixity(spelling);
  if known&&prec<27 { return true; }
 }
 return false;
}
recursive fn not_operand(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 let t=advance(p,source,tokens); let op=intern(p,source,tokens,"not");
 let arg=infix_work(p,source,tokens,true);
 return add(p,source,tokens,a_unary,op,arg,0,t.start);
}
recursive fn infix(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id { return infix_work(p,source,tokens,false); }
recursive fn infix_work(p: Parser&,source: const u8[:],tokens: const Token[:],stop_below_not: bool) -> Id {
 let start=current(p,source,tokens).start; var head: Id=0;
 if at(p,source,tokens,t_kw_not) { head=not_operand(p,source,tokens); } else { head=prefix(p,source,tokens); }
 var operands=ScratchIdBuffer {};  var operators=ScratchOperatorBuffer {};  var unknown=false;
 while p.failure==blot_error::Error.none&&operator_tag(current(p,source,tokens).tag) {
  if stop_below_not&&stop_infix_for_not(p,source,tokens) { break; }
  let op=read_operator(p,source,tokens); unknown=unknown||!op.known; operators.push(op); var rhs: Id=0;
  if at(p,source,tokens,t_kw_func)||at(p,source,tokens,t_kw_do)||at(p,source,tokens,t_kw_if)||at(p,source,tokens,t_kw_case) { rhs=expression(p,source,tokens); }
  else if at(p,source,tokens,t_kw_not) { rhs=not_operand(p,source,tokens); }
  else { rhs=prefix(p,source,tokens); } operands.push(rhs);
 }
 if p.failure!=blot_error::Error.none { let __cleanup_result_43_0: Id = 0; operators.deinit(); operands.deinit(); return __cleanup_result_43_0; } if operators.len==0 { let __cleanup_result_44_0: Id = head; operators.deinit(); operands.deinit(); return __cleanup_result_44_0; }
 if unknown { let __cleanup_result_45_0: Id = infix_chain(p,source,tokens,head,operators.items,operands.items,start); operators.deinit(); operands.deinit(); return __cleanup_result_45_0; }
 var values=ScratchIdBuffer {};  values.append([head]); var stack=ScratchOperatorBuffer {};
 for op,index in operators.items {
  while stack.len!=0 {
   let top=stack.items[stack.len-1]; if top.precedence<op.precedence { break; }
   if top.precedence==op.precedence { if top.association!=op.association||op.association==2 { let __cleanup_result_46_0: Id = infix_chain(p,source,tokens,head,operators.items,operands.items,start); stack.deinit(); values.deinit(); operators.deinit(); operands.deinit(); return __cleanup_result_46_0; } if op.association==1 { break; } }
   stack.resize(stack.len-1); reduce(p,source,tokens,values,top); if p.failure!=blot_error::Error.none { let __cleanup_result_47_0: Id = 0; stack.deinit(); values.deinit(); operators.deinit(); operands.deinit(); return __cleanup_result_47_0; }
  }
  stack.push(op); values.push(operands.items[index]);
 }
 while stack.len!=0 { let op=stack.items[stack.len-1]; stack.resize(stack.len-1); reduce(p,source,tokens,values,op); if p.failure!=blot_error::Error.none { let __cleanup_result_48_0: Id = 0; stack.deinit(); values.deinit(); operators.deinit(); operands.deinit(); return __cleanup_result_48_0; } }
 let __cleanup_result_49_0: Id = values.items[0]; stack.deinit(); values.deinit(); operators.deinit(); operands.deinit(); return __cleanup_result_49_0;
 stack.deinit(); values.deinit(); operators.deinit(); operands.deinit(); }
fn infix_chain(p: Parser&,source: const u8[:],tokens: const Token[:],head: Id,operators: const Operator[:],operands: const Id[:],start: u32) -> Id {
 var tails=ScratchIdBuffer {};
 for op,index in operators {
  var flags=(op.association<<2)|(op.precedence<<4); if op.known { flags|=2; }
  let rhs=operands[index]; let tail=add(p,source,tokens,a_operator_tail,op.symbol,rhs,flags,op.span.start); if p.failure!=blot_error::Error.none { let __cleanup_result_50_0: Id = 0; tails.deinit(); return __cleanup_result_50_0; }
  p.tree.spans.items[tail].end=p.tree.span(rhs).end; p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:tail,span:op.span}); tails.push(tail);
 }
 let range=list(p,source,tokens,tails.items); let __cleanup_result_51_0: Id = add(p,source,tokens,a_infix_chain,head,range.start,range.len,start); tails.deinit(); return __cleanup_result_51_0;
 tails.deinit(); }
fn reduce(p: Parser&,source: const u8[:],tokens: const Token[:],values: ScratchIdBuffer&,op: Operator) {
 if p.failure!=blot_error::Error.none { return; }
 let rhs=values.items[values.len-1]; let lhs=values.items[values.len-2]; values.resize(values.len-2); var id: Id=0;
 if op.application { let argument=add(p,source,tokens,a_group,rhs,0,0,p.tree.span(rhs).start); if p.failure!=blot_error::Error.none { return; } p.tree.spans.items[argument].end=p.tree.span(rhs).end; id=add(p,source,tokens,a_apply,lhs,argument,0,p.tree.span(lhs).start); }
 else { id=add(p,source,tokens,a_binary,op.symbol,lhs,rhs,p.tree.span(lhs).start); }
 if p.failure!=blot_error::Error.none { return; } p.tree.spans.items[id].end=p.tree.span(rhs).end;
 if !op.application { p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:id,span:op.span}); } values.push(id);
}
recursive fn prefix(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 if p.failure!=blot_error::Error.none { return 0; } let t=current(p,source,tokens);
 if t.tag==t_caret||(t.tag==t_symbol&&text(p,source,t)=="&") {
  advance(p,source,tokens); let operand=postfix(p,source,tokens); if p.failure!=blot_error::Error.none { return 0; } let node=p.tree.node(operand);
  if node.tag==a_index_access { var intrinsic: const u8[:]="@storage.at"; if t.tag==t_caret { intrinsic="@storage.link"; } return collection_intrinsic(p,source,tokens,intrinsic,[node.a,node.b],t.start); }
  if t.tag==t_caret { return fail(p,source,tokens,c_expected_expression); }
  var head=operand; while p.tree.node(head).tag==a_apply { head=p.tree.node(head).a; }
  if p.tree.node(head).tag==a_intrinsic&&p.pool.get(p.tree.node(head).a)=="@storage.view" { return operand; }
  if node.tag!=a_name&&node.tag!=a_field_access { return fail(p,source,tokens,c_expected_expression); }
  return collection_intrinsic(p,source,tokens,"@storage.ref",[operand],t.start);
 }
 if t.tag==t_symbol||t.tag==t_star||t.tag==t_caret { advance(p,source,tokens); let op=intern(p,source,tokens,text(p,source,t)); let arg=application(p,source,tokens,true); return add(p,source,tokens,a_unary,op,arg,0,t.start); }
 return application(p,source,tokens,true);
}
recursive fn application(p: Parser&,source: const u8[:],tokens: const Token[:],allow_witness: bool) -> Id {
 let start=current(p,source,tokens).start; var value: Id=0;
 if at(p,source,tokens,t_identifier)&&text(p,source,current(p,source,tokens))=="own"&&atom_tag(peek(p,tokens,1)) {
  // `(own x)` on its own, as an argument in parentheses.
  advance(p,source,tokens); let given=postfix(p,source,tokens); if p.failure!=blot_error::Error.none { return 0; }
  value=add(p,source,tokens,a_group,given,1,0,start); p.tree.spans.items[value].end=p.tree.span(given).end;
 } else { value=postfix(p,source,tokens); }
 while p.failure==blot_error::Error.none {
  if at(p,source,tokens,t_dot) {
   let dot=advance(p,source,tokens);
   if eat(p,source,tokens,t_l_paren) {
    let field_var=lower_identifier(p,source,tokens); expect(p,source,tokens,t_r_paren);
    value=add(p,source,tokens,a_comptime_project,value,field_var,0,start); if p.failure!=blot_error::Error.none { break; }
   } else {
    let point=current(p,source,tokens).start; let member=member_identifier(p,source,tokens);
    value=add(p,source,tokens,a_field_access,value,member,0,start); if p.failure!=blot_error::Error.none { break; }
    p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:value,span:Span {dot.start,dot.end},member:member,member_point:point});
   }
   while p.failure==blot_error::Error.none {
    if at(p,source,tokens,t_dot)&&current(p,source,tokens).start==p.tree.span(value).end {
     let d2=advance(p,source,tokens);
     if eat(p,source,tokens,t_l_paren) {
      let fv2=lower_identifier(p,source,tokens); expect(p,source,tokens,t_r_paren);
      value=add(p,source,tokens,a_comptime_project,value,fv2,0,start); if p.failure!=blot_error::Error.none { break; }
     } else {
      let pt2=current(p,source,tokens).start; let m2=member_identifier(p,source,tokens);
      value=add(p,source,tokens,a_field_access,value,m2,0,start); if p.failure!=blot_error::Error.none { break; }
      p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:value,span:Span {d2.start,d2.end},member:m2,member_point:pt2});
     }
    } else if at(p,source,tokens,t_l_bracket)&&current(p,source,tokens).start==p.tree.span(value).end {
     advance(p,source,tokens); let idx=expression(p,source,tokens);
     if eat(p,source,tokens,t_dot_dot) { let lim=expression(p,source,tokens); expect(p,source,tokens,t_r_bracket); value=collection_intrinsic(p,source,tokens,"@storage.view",[value,idx,lim],start); }
     else { expect(p,source,tokens,t_r_bracket); value=add(p,source,tokens,a_index_access,value,idx,0,start); }
    } else { break; }
   }
   continue;
  }
  if !atom_tag(current(p,source,tokens).tag)||(!allow_witness&&at(p,source,tokens,t_colon)) { break; }
  if at(p,source,tokens,t_colon)&&peek(p,tokens,1)==t_newline { break; }
  // `f (own x)` or `f own x`: the argument is given away. A group node
  // with b = 1 carries it; every other group has b = 0.
  if at(p,source,tokens,t_identifier)&&text(p,source,current(p,source,tokens))=="own"&&atom_tag(peek(p,tokens,1)) {
   let point=current(p,source,tokens).start; advance(p,source,tokens); let given=postfix(p,source,tokens); if p.failure!=blot_error::Error.none { break; }
   let marked=add(p,source,tokens,a_group,given,1,0,point); p.tree.spans.items[marked].end=p.tree.span(given).end;
   value=add(p,source,tokens,a_apply,value,marked,0,start); continue;
  }
  let argument=postfix(p,source,tokens); value=add(p,source,tokens,a_apply,value,argument,0,start);
 }
 return value;
}
recursive fn postfix(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 let start=current(p,source,tokens).start; var value=atom(p,source,tokens);
 while p.failure==blot_error::Error.none {
  if at(p,source,tokens,t_dot)&&current(p,source,tokens).start==p.tree.span(value).end {
   let dot=advance(p,source,tokens);
   if eat(p,source,tokens,t_l_paren) {
    let field_var=lower_identifier(p,source,tokens); expect(p,source,tokens,t_r_paren);
    value=add(p,source,tokens,a_comptime_project,value,field_var,0,start); if p.failure!=blot_error::Error.none { return 0; }
   } else {
    let point=current(p,source,tokens).start; let member=member_identifier(p,source,tokens); value=add(p,source,tokens,a_field_access,value,member,0,start); if p.failure!=blot_error::Error.none { return 0; } p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:value,span:Span {dot.start,dot.end},member:member,member_point:point});
   }
  }
  else if at(p,source,tokens,t_l_paren)&&current(p,source,tokens).start==p.tree.span(value).end { let argument=atom(p,source,tokens); value=add(p,source,tokens,a_apply,value,argument,0,start); }
  else if at(p,source,tokens,t_l_bracket)&&current(p,source,tokens).start==p.tree.span(value).end {
   advance(p,source,tokens); let index=expression(p,source,tokens);
   if eat(p,source,tokens,t_dot_dot) { let limit=expression(p,source,tokens); expect(p,source,tokens,t_r_bracket); value=collection_intrinsic(p,source,tokens,"@storage.view",[value,index,limit],start); }
   else { expect(p,source,tokens,t_r_bracket); value=add(p,source,tokens,a_index_access,value,index,0,start); }
  } else { break; }
 }
 return value;
}
recursive fn atom(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 if !enter(p,source,tokens) { return 0; }  let t=current(p,source,tokens); let start=t.start;
 if t.tag==t_kw_true||t.tag==t_kw_false { advance(p,source,tokens); var value: u32=0; if t.tag==t_kw_true { value=1; } let __cleanup_result_39_0: Id = add(p,source,tokens,a_boolean,value,0,0,start); { p.depth--; } return __cleanup_result_39_0; }
 if t.tag==t_integer { advance(p,source,tokens); let __cleanup_result_40_0: Id = integer_literal(p,source,tokens,t,a_integer); { p.depth--; } return __cleanup_result_40_0; }
 if t.tag==t_float {
  advance(p,source,tokens); let bits,err=blot_parse_lexer::float_bits(text(p,source,t));
  if err==blot_error::Error.float_range { let __cleanup_result_41_0: Id = numeric_failure(p,source,tokens,t,blot_parse_ast::numericcode_float_range); { p.depth--; } return __cleanup_result_41_0; }
  if err==blot_error::Error.invalid_float { let __cleanup_result_42_0: Id = numeric_failure(p,source,tokens,t,blot_parse_ast::numericcode_float_literal); { p.depth--; } return __cleanup_result_42_0; }
  if err!=blot_error::Error.none { p.failure=err; let __cleanup_result_43_0: Id = 0; { p.depth--; } return __cleanup_result_43_0; } let __cleanup_result_44_0: Id = add(p,source,tokens,a_float,bits,0,0,start); { p.depth--; } return __cleanup_result_44_0;
 }
 if t.tag==t_string { let __cleanup_result_45_0: Id = add(p,source,tokens,a_string,string_symbol(p,source,tokens),0,0,start); { p.depth--; } return __cleanup_result_45_0; }
 if t.tag==t_intrinsic {
  advance(p,source,tokens);
  let staging,has_staging=blot_check_typed_staging::lookup(text(p,source,t)); if has_staging { p.tree.has_typed_staging=true; }
  let __cleanup_result_46_0: Id = add(p,source,tokens,a_intrinsic,intern(p,source,tokens,text(p,source,t)),0,0,start); { p.depth--; } return __cleanup_result_46_0;
 }
 if t.tag==t_kw_spark {
  advance(p,source,tokens);
  let result=spark_expression(p,source,tokens,start);
  p.depth--; return result;
 }
 if t.tag==t_identifier&&peek(p,tokens,1)!=t_dot {
  let spelling=text(p,source,t);
  if spelling=="panic" { advance(p,source,tokens); let __cleanup_result_panic_0: Id = add(p,source,tokens,a_intrinsic,intern(p,source,tokens,"@panic"),0,0,start); { p.depth--; } return __cleanup_result_panic_0; }
  if spelling=="_" { advance(p,source,tokens); let __cleanup_result_hole_0: Id = add(p,source,tokens,a_intrinsic,intern(p,source,tokens,"@hole"),0,0,start); { p.depth--; } return __cleanup_result_hole_0; }
 }
 if t.tag==t_identifier||t.tag==t_type_identifier {
  let token_start=p.index; let name=qualified(p,source,tokens); let id=add(p,source,tokens,a_name,name,0,0,start); if p.failure!=blot_error::Error.none { let __cleanup_result_47_0: Id = 0; { p.depth--; } return __cleanup_result_47_0; }
  for index in token_start..p.index { let item=tokens[index]; if item.tag==t_dot { let member,found=p.pool.lookup(text(p,source,tokens[index+1])); p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:id,span:Span {item.start,item.end},member:member,member_point:tokens[index+1].start}); } } let __cleanup_result_48_0: Id = id; { p.depth--; } return __cleanup_result_48_0;
 }
 if t.tag==t_selector { advance(p,source,tokens); let __cleanup_result_49_0: Id = add(p,source,tokens,a_selector,member_qualified(p,source,tokens),0,0,start); { p.depth--; } return __cleanup_result_49_0; }
 if t.tag==t_colon { advance(p,source,tokens); let value=atom(p,source,tokens); let __cleanup_result_50_0: Id = add(p,source,tokens,a_type_witness,value,0,0,start); { p.depth--; } return __cleanup_result_50_0; }
 if t.tag==t_hash {
  if text(p,source,t)=="#" && peek(p,tokens,1)==t_kw_for {
   let value=comptime_for(p,source,tokens,true);
   p.depth--;
   return value;
  }
  advance(p,source,tokens);
  if text(p,source,t)=="#"&&word(p,source,tokens,"run")&&peek(p,tokens,1)!=t_dot { advance(p,source,tokens); p.tree.has_typed_staging=true; let value=expression(p,source,tokens); let __cleanup_result_51_0: Id = collection_intrinsic(p,source,tokens,"@code.evaluate",[value],start); { p.depth--; } return __cleanup_result_51_0; }
  if text(p,source,t)=="#"&&at(p,source,tokens,t_kw_do) { p.tree.has_typed_staging=true; let value=do_block(p,source,tokens); let __cleanup_result_52_0: Id = collection_intrinsic(p,source,tokens,"@code.evaluate",[value],start); { p.depth--; } return __cleanup_result_52_0; }
  if at(p,source,tokens,t_l_bracket) { let __cleanup_result_53_0: Id = collection(p,source,tokens,start); { p.depth--; } return __cleanup_result_53_0; } if at(p,source,tokens,t_l_brace) { let __cleanup_result_54_0: Id = record(p,source,tokens,0,start); { p.depth--; } return __cleanup_result_54_0; }
  let name=qualified(p,source,tokens); if at(p,source,tokens,t_l_brace) { let __cleanup_result_55_0: Id = record(p,source,tokens,name,start); { p.depth--; } return __cleanup_result_55_0; } let __cleanup_result_56_0: Id = add(p,source,tokens,a_constructor_ref,name,0,0,start); { p.depth--; } return __cleanup_result_56_0;
 }
 if t.tag==t_l_brace { let __cleanup_result_57_0: Id = record(p,source,tokens,0,start); { p.depth--; } return __cleanup_result_57_0; }
 if t.tag==t_l_bracket {
  advance(p,source,tokens); var values=ScratchIdBuffer {};
  while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_bracket) { values.push(expression(p,source,tokens)); if !eat(p,source,tokens,t_comma) { break; } }
  expect(p,source,tokens,t_r_bracket);
  let range=list(p,source,tokens,values.items);
  let id=add(p,source,tokens,a_array,range.start,range.len,1,start);
  values.deinit(); { p.depth--; } return id;
 }
 if t.tag==t_l_paren {
  advance(p,source,tokens); var values=ScratchIdBuffer {};  var tuple=false;
  while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_paren) { values.push(expression(p,source,tokens)); if !eat(p,source,tokens,t_comma) { break; } tuple=true; }
  expect(p,source,tokens,t_r_paren); if values.len==0 { let __cleanup_result_59_0: Id = add(p,source,tokens,a_unit,0,0,0,start); { p.depth--; } let __cleanup_result_53_0: Id = __cleanup_result_59_0; values.deinit(); return __cleanup_result_53_0; } if !tuple&&values.len==1 { let __cleanup_result_60_0: Id = add(p,source,tokens,a_group,values.items[0],0,0,start); { p.depth--; } let __cleanup_result_54_0: Id = __cleanup_result_60_0; values.deinit(); return __cleanup_result_54_0; } let __cleanup_result_61_0: Id = list_node(p,source,tokens,a_product,values.items,start); { p.depth--; } let __cleanup_result_55_0: Id = __cleanup_result_61_0; values.deinit(); return __cleanup_result_55_0;
  values.deinit(); }
 if t.tag==t_private_from||t.tag==t_private_where { let __cleanup_result_62_0: Id = fail(p,source,tokens,c_private_marker); { p.depth--; } return __cleanup_result_62_0; } let __cleanup_result_63_0: Id = fail(p,source,tokens,c_expected_expression); { p.depth--; } return __cleanup_result_63_0;
 { p.depth--; } }
recursive fn collection_element(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 let previous=p.expression_end; var nesting=0; var index=p.index; var limit=tokens.len; if previous<limit { limit=previous; }
 while index<limit {
  let tag=tokens[index].tag;
  if tag==t_l_paren||tag==t_l_bracket||tag==t_l_brace||tag==t_indent { nesting++; }
  else if tag==t_r_paren||tag==t_r_bracket||tag==t_r_brace||tag==t_dedent { if nesting==0 { break; } nesting--; }
  else if tag==t_pipe&&nesting==0 { p.expression_end=index; break; }
  else if (tag==t_comma||tag==t_eof)&&nesting==0 { break; } index++;
 }
 let value=expression(p,source,tokens); p.expression_end=previous; return value;
}
fn collection_literal(p: Parser&,source: const u8[:],tokens: const Token[:],values: const Id[:],start: u32) -> Id { let range=list(p,source,tokens,values); return add(p,source,tokens,a_array,range.start,range.len,0,start); }
fn collection_intrinsic(p: Parser&,source: const u8[:],tokens: const Token[:],name: const u8[:],args: const Id[:],start: u32) -> Id { var result=add(p,source,tokens,a_intrinsic,intern(p,source,tokens,name),0,0,start); for arg in args { result=add(p,source,tokens,a_apply,result,arg,0,start); } return result; }
fn collection_name(p: Parser&,source: const u8[:],tokens: const Token[:],start: u32) -> Symbol { let spelling=str("$collection.",p.collection_names); p.collection_names++; return intern(p,source,tokens,spelling); }
fn collection_binding(p: Parser&,source: const u8[:],tokens: const Token[:],name: Symbol,value: Id,start: u32) -> Id { let pat=add(p,source,tokens,a_pattern_name,name,0,0,start); return add(p,source,tokens,a_let_stmt,pat,value,extra(p,source,tokens,[0 as u32,0,0,0,0]),start); }
fn collection_loop(p: Parser&,source: const u8[:],tokens: const Token[:],pat: Id,value: Id,end: Id,body: Id,explicit: bool,start: u32) -> Id {
 var expansion: Id=0;
 if end==0 {
  let cursor=collection_name(p,source,tokens,start); let cursor_ref=add(p,source,tokens,a_name,cursor,0,0,start);
  let iter=add(p,source,tokens,a_field_access,value,intern(p,source,tokens,"iter"),0,start); let initialize=add(p,source,tokens,a_iterator_bind,cursor,iter,0,start);
  let step=collection_name(p,source,tokens,start); let next=add(p,source,tokens,a_field_access,cursor_ref,intern(p,source,tokens,"next"),0,start); let next_step=add(p,source,tokens,a_iterator_bind,step,next,0,start);
  let item=collection_name(p,source,tokens,start); let item_pattern=add(p,source,tokens,a_pattern_name,item,0,0,start); let rest=collection_name(p,source,tokens,start); let rest_pattern=add(p,source,tokens,a_pattern_name,rest,0,0,start);
  let pair=list_node(p,source,tokens,a_pattern_product,[item_pattern,rest_pattern],start); let some=add(p,source,tokens,a_pattern_constructor,intern(p,source,tokens,"Some"),pair,0,start);
  let broken=add(p,source,tokens,a_break_stmt,0,0,0,start); let stop=list_node(p,source,tokens,a_block,[broken],start);
  let step_ref=add(p,source,tokens,a_name,step,0,0,start); let unpack=add(p,source,tokens,a_let_stmt,some,step_ref,extra(p,source,tokens,[0 as u32,0,0,stop,0]),start);
  let rest_ref=add(p,source,tokens,a_name,rest,0,0,start); let update=add(p,source,tokens,a_rebind_stmt,cursor_ref,rest_ref,0,start);
  let item_ref=add(p,source,tokens,a_name,item,0,0,start); let bind=add(p,source,tokens,a_let_stmt,pat,item_ref,extra(p,source,tokens,[0 as u32,0,0,0,0]),start);
  if p.failure!=blot_error::Error.none { return 0; } var statements=ScratchIdBuffer {};  statements.append([next_step,unpack,update,bind]); for child in p.tree.children(body) { statements.push(child); }
  let iteration_body=list_node(p,source,tokens,a_block,statements.items,start); let iteration=add(p,source,tokens,a_forever_stmt,iteration_body,0,0,start); expansion=list_node(p,source,tokens,a_block,[initialize,iteration],start);
  statements.deinit(); }
 var explicit_flag: u32=0; if explicit { explicit_flag=1; } return add(p,source,tokens,a_for_stmt,pat,value,extra(p,source,tokens,[end,body,explicit_flag,expansion]),start);
}
recursive fn collection(p: Parser&,source: const u8[:],tokens: const Token[:],start: u32) -> Id {
 expect(p,source,tokens,t_l_bracket); var values=ScratchIdBuffer {};  var spread: i64=-1;
 while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_bracket) {
  if eat(p,source,tokens,t_ellipsis) { if spread>=0 { let __cleanup_result_56_0: Id = fail(p,source,tokens,c_unexpected_token); values.deinit(); return __cleanup_result_56_0; } spread=values.len; }
  values.push(collection_element(p,source,tokens));
  if eat(p,source,tokens,t_pipe) { if spread>=0 { let __cleanup_result_57_0: Id = fail(p,source,tokens,c_unexpected_token); values.deinit(); return __cleanup_result_57_0; } if values.len==1&&at(p,source,tokens,t_identifier)&&peek(p,tokens,1)==t_left_arrow { let __cleanup_result_58_0: Id = comprehension(p,source,tokens,values.items[0],start); values.deinit(); return __cleanup_result_58_0; } spread=values.len; values.push(expression(p,source,tokens)); break; }
  if !eat(p,source,tokens,t_comma) { break; }
 }
 expect(p,source,tokens,t_r_bracket); if p.failure!=blot_error::Error.none { let __cleanup_result_59_0: Id = 0; values.deinit(); return __cleanup_result_59_0; }
 if spread<0 { let __cleanup_result_60_0: Id = collection_literal(p,source,tokens,values.items,start); values.deinit(); return __cleanup_result_60_0; }
 var statements=ScratchIdBuffer {};  var refs=ScratchIdBuffer {};
 for value in values.items { let name=collection_name(p,source,tokens,start); statements.push(add(p,source,tokens,a_iterator_bind,name,value,0,start)); refs.push(add(p,source,tokens,a_name,name,0,0,start)); }
 var result=refs.items[spread]; var index=spread;
 while index!=0 { index--; result=collection_intrinsic(p,source,tokens,"@array.prepend",[result,refs.items[index]],start); }
 for value in refs.items[spread+1..] { result=collection_intrinsic(p,source,tokens,"@array.append",[result,value],start); }
 if values.len==1 { result=collection_intrinsic(p,source,tokens,"@array.identity",[result],start); } statements.push(add(p,source,tokens,a_return_stmt,result,0,0,start)); let __cleanup_result_61_0: Id = list_node(p,source,tokens,a_block,statements.items,start); refs.deinit(); statements.deinit(); values.deinit(); return __cleanup_result_61_0;
 refs.deinit(); statements.deinit(); values.deinit(); }
// CallablePath = (LowerName ".")? (UpperName ".")* LowerName
fn callable_path(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 if p.failure!=blot_error::Error.none { return 0; }
 let token_start=p.index; let first=current(p,source,tokens); let start=first.start;
 if first.tag!=t_identifier&&first.tag!=t_type_identifier { return fail(p,source,tokens,c_expected_token); }
 advance(p,source,tokens);
 var bytes=Scratchu8Buffer {};
 for c in text(p,source,first) { bytes.push(c); }
 var last_end=first.end;
 var finished_lower=(first.tag==t_identifier);
 var saw_dot=false;
 while p.failure==blot_error::Error.none&&at(p,source,tokens,t_dot)&&current(p,source,tokens).start==last_end {
  if saw_dot&&finished_lower { bytes.deinit(); return fail(p,source,tokens,c_unexpected_token); }
  saw_dot=true;
  advance(p,source,tokens);
  let next=current(p,source,tokens);
  if next.tag!=t_identifier&&next.tag!=t_type_identifier { bytes.deinit(); return fail(p,source,tokens,c_expected_token); }
  advance(p,source,tokens);
  last_end=next.end;
  intern(p,source,tokens,text(p,source,next));
  bytes.push('.');
  for c in text(p,source,next) { bytes.push(c); }
  finished_lower=(next.tag==t_identifier);
 }
 if !finished_lower { bytes.deinit(); return fail(p,source,tokens,c_expected_token); }
 let sym=intern(p,source,tokens,bytes.items);
 bytes.deinit();
 let id=add(p,source,tokens,a_name,sym,0,0,start);
 if p.failure!=blot_error::Error.none { return 0; }
 for index in token_start..p.index {
  let item=tokens[index];
  if item.tag==t_dot {
   let member,found=p.pool.lookup(text(p,source,tokens[index+1]));
   p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:id,span:Span {item.start,item.end},member:member,member_point:tokens[index+1].start});
  }
 }
 return id;
}
recursive fn entry_kernel_declaration(p: Parser&,source: const u8[:],tokens: const Token[:],attributes: List,start: u32) -> Id {
 advance(p,source,tokens); // #
 advance(p,source,tokens); // kernel
 if at(p,source,tokens,t_kw_func) {
  let func_start=advance(p,source,tokens).start;
  let name_point=current(p,source,tokens).start;
  let name=lower_identifier(p,source,tokens);
  if p.failure!=blot_error::Error.none { return 0; }
  var constraints=Where {};
  if !enter(p,source,tokens) { return 0; }
  let body=lambda_tail(p,source,tokens,func_start,true,constraints);
  p.depth--;
  if p.failure!=blot_error::Error.none { return 0; }
  let decl_id=add(p,source,tokens,a_entry_kernel_decl,name,0,extra(p,source,tokens,[0 as u32,body,constraints.node,attributes.start,attributes.len,name_point,constraints.predicates.start,constraints.predicates.len]),start);
  if p.failure!=blot_error::Error.none { return 0; }
  p.tree.constant_names.push(blot_parse_ast::RuntimeName {decl_id,name_point});
  return decl_id;
 }
 expect(p,source,tokens,t_kw_const);
 if p.failure!=blot_error::Error.none { return 0; }
 let name_point=current(p,source,tokens).start;
 let name=lower_identifier(p,source,tokens);
 expect(p,source,tokens,t_colon);
 let annotation=type_expression(p,source,tokens);
 expect(p,source,tokens,t_equal);
 expect(p,source,tokens,t_l_brace);
 newlines(p,source,tokens);
 var prepare_node: Id=0;
 var run_node: Id=0;
 while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_brace) {
  let key=current(p,source,tokens);
  if key.tag!=t_identifier { return fail(p,source,tokens,c_expected_token); }
  let key_text=text(p,source,key);
  advance(p,source,tokens);
  expect(p,source,tokens,t_colon);
  let target=callable_path(p,source,tokens);
  if p.failure!=blot_error::Error.none { return 0; }
  if key_text=="prepare" {
   if prepare_node!=0 { return fail(p,source,tokens,c_unexpected_token); }
   prepare_node=target;
  } else if key_text=="run" {
   if run_node!=0 { return fail(p,source,tokens,c_unexpected_token); }
   run_node=target;
  } else {
   return fail(p,source,tokens,c_unexpected_token);
  }
  if eat(p,source,tokens,t_comma) { newlines(p,source,tokens); continue; }
  if at(p,source,tokens,t_newline) { newlines(p,source,tokens); continue; }
  break;
 }
 newlines(p,source,tokens);
 expect(p,source,tokens,t_r_brace);
 if p.failure!=blot_error::Error.none { return 0; }
 if prepare_node==0||run_node==0 { return fail(p,source,tokens,c_expected_token); }
 let decl_id=add(p,source,tokens,a_entry_kernel_decl,name,annotation,extra(p,source,tokens,[1 as u32,prepare_node,run_node,attributes.start,attributes.len,name_point,0 as u32,0 as u32]),start);
 if p.failure!=blot_error::Error.none { return 0; }
 p.tree.constant_names.push(blot_parse_ast::RuntimeName {decl_id,name_point});
 return decl_id;
}
recursive fn entry_process_declaration(p: Parser&,source: const u8[:],tokens: const Token[:],attributes: List,start: u32) -> Id {
 advance(p,source,tokens); // #
 advance(p,source,tokens); // process
 expect(p,source,tokens,t_kw_const);
 if p.failure!=blot_error::Error.none { return 0; }
 let name_point=current(p,source,tokens).start;
 let name=lower_identifier(p,source,tokens);
 expect(p,source,tokens,t_colon);
 let annotation=type_expression(p,source,tokens);
 expect(p,source,tokens,t_equal);
 expect(p,source,tokens,t_l_brace);
 newlines(p,source,tokens);
 var init_node: Id=0;
 var step_node: Id=0;
 while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_brace) {
  let key=current(p,source,tokens);
  if key.tag!=t_identifier { return fail(p,source,tokens,c_expected_token); }
  let key_text=text(p,source,key);
  advance(p,source,tokens);
  expect(p,source,tokens,t_colon);
  let target=callable_path(p,source,tokens);
  if p.failure!=blot_error::Error.none { return 0; }
  if key_text=="init" {
   if init_node!=0 { return fail(p,source,tokens,c_unexpected_token); }
   init_node=target;
  } else if key_text=="step" {
   if step_node!=0 { return fail(p,source,tokens,c_unexpected_token); }
   step_node=target;
  } else {
   return fail(p,source,tokens,c_unexpected_token);
  }
  if eat(p,source,tokens,t_comma) { newlines(p,source,tokens); continue; }
  if at(p,source,tokens,t_newline) { newlines(p,source,tokens); continue; }
  break;
 }
 newlines(p,source,tokens);
 expect(p,source,tokens,t_r_brace);
 if p.failure!=blot_error::Error.none { return 0; }
 if init_node==0||step_node==0 { return fail(p,source,tokens,c_expected_token); }
 let decl_id=add(p,source,tokens,a_entry_process_decl,name,annotation,extra(p,source,tokens,[init_node,step_node,attributes.start,attributes.len,name_point]),start);
 if p.failure!=blot_error::Error.none { return 0; }
 p.tree.constant_names.push(blot_parse_ast::RuntimeName {decl_id,name_point});
 return decl_id;
}
recursive fn spark_expression(p: Parser&,source: const u8[:],tokens: const Token[:],start: u32) -> Id {
 if !at(p,source,tokens,t_hash)||text(p,source,current(p,source,tokens))!="#" { return fail(p,source,tokens,blot_parse_ast::code_spark_generator); }
 advance(p,source,tokens);
 if !eat(p,source,tokens,t_l_bracket) { return fail(p,source,tokens,blot_parse_ast::code_spark_generator); }
 let body=collection_element(p,source,tokens);
 if p.failure!=blot_error::Error.none { return 0; }
 if !eat(p,source,tokens,t_pipe) { return fail(p,source,tokens,blot_parse_ast::code_spark_generator); }
 let pat=pattern(p,source,tokens);
 if p.failure!=blot_error::Error.none { return 0; }
 if !eat(p,source,tokens,t_left_arrow) { return fail(p,source,tokens,blot_parse_ast::code_spark_generator); }
 let src_first=expression(p,source,tokens);
 if p.failure!=blot_error::Error.none { return 0; }
 var src_end: Id=0;
 if eat(p,source,tokens,t_dot_dot) {
  src_end=expression(p,source,tokens);
  if p.failure!=blot_error::Error.none { return 0; }
 }
 if !at(p,source,tokens,t_r_bracket) { return fail(p,source,tokens,blot_parse_ast::code_spark_generator); }
 advance(p,source,tokens);
 return add(p,source,tokens,a_spark_expr,body,pat,extra(p,source,tokens,[src_first,src_end]),start);
}
recursive fn comprehension(p: Parser&,source: const u8[:],tokens: const Token[:],result: Id,start: u32) -> Id {
 var qualifiers=ScratchQualifierBuffer {};
 while p.failure==blot_error::Error.none {
  let point=current(p,source,tokens).start; var kind: u32=1; var name: Symbol=0;
  if eat(p,source,tokens,t_kw_let) { kind=2; name=lower_identifier(p,source,tokens); expect(p,source,tokens,t_equal); }
  else if at(p,source,tokens,t_identifier)&&peek(p,tokens,1)==t_left_arrow { kind=0; name=lower_identifier(p,source,tokens); expect(p,source,tokens,t_left_arrow); }
  let value=expression(p,source,tokens); qualifiers.push(Qualifier {kind,name,value,point});
  if !eat(p,source,tokens,t_comma) { break; } if at(p,source,tokens,t_r_bracket) { let __cleanup_result_62_0: Id = fail(p,source,tokens,c_expected_expression); qualifiers.deinit(); return __cleanup_result_62_0; }
 }
 expect(p,source,tokens,t_r_bracket); let accumulator=collection_name(p,source,tokens,start); let empty=collection_literal(p,source,tokens,[],start); let initial=collection_binding(p,source,tokens,accumulator,empty,start);
 let target=add(p,source,tokens,a_name,accumulator,0,0,start); let receiver=add(p,source,tokens,a_name,accumulator,0,0,start); let appended=collection_intrinsic(p,source,tokens,"@array.append",[receiver,result],start);
 let rebind=add(p,source,tokens,a_rebind_stmt,target,appended,0,start); var body=list_node(p,source,tokens,a_block,[rebind],start); var index=qualifiers.len;
 while index!=0&&p.failure==blot_error::Error.none {
  index--; let q=qualifiers.items[index]; var statement: Id=0;
  if q.kind==0 { let pat=add(p,source,tokens,a_pattern_name,q.name,0,0,q.start); statement=collection_loop(p,source,tokens,pat,q.value,0,body,false,q.start); }
  else if q.kind==1 { statement=add(p,source,tokens,a_if_stmt,q.value,body,0,q.start); }
  else { let binding=collection_binding(p,source,tokens,q.name,q.value,q.start); var joined=ScratchIdBuffer {};  joined.append([binding]); for child in p.tree.children(body) { joined.push(child); } body=list_node(p,source,tokens,a_block,joined.items,q.start); joined.deinit(); continue;  joined.deinit(); }
  body=list_node(p,source,tokens,a_block,[statement],q.start);
 }
 let final=add(p,source,tokens,a_name,accumulator,0,0,start);
 let returned=add(p,source,tokens,a_return_stmt,final,0,0,start); if p.failure!=blot_error::Error.none { let __cleanup_result_64_0: Id = 0; qualifiers.deinit(); return __cleanup_result_64_0; }
 var statements=ScratchIdBuffer {};  statements.append([initial]); for child in p.tree.children(body) { statements.push(child); } statements.push(returned); let __cleanup_result_65_0: Id = list_node(p,source,tokens,a_block,statements.items,start); statements.deinit(); qualifiers.deinit(); return __cleanup_result_65_0;
 statements.deinit(); qualifiers.deinit(); }
recursive fn record(p: Parser&,source: const u8[:],tokens: const Token[:],name: Symbol,start: u32) -> Id {
 expect(p,source,tokens,t_l_brace); var fields=ScratchIdBuffer {};
 while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_brace) { let point=current(p,source,tokens).start; let key=lower_identifier(p,source,tokens); var value: Id=0; if eat(p,source,tokens,t_colon) { value=expression(p,source,tokens); } fields.push(add(p,source,tokens,a_field,key,value,0,point)); if !eat(p,source,tokens,t_comma) { break; } }
 expect(p,source,tokens,t_r_brace); let range=list(p,source,tokens,fields.items); let __cleanup_result_66_0: Id = add(p,source,tokens,a_record,name,range.start,range.len,start); fields.deinit(); return __cleanup_result_66_0;
 fields.deinit(); }
recursive fn suite_body(p: Parser&,source: const u8[:],tokens: const Token[:],unwrap_expr: bool,keep_block: bool) -> Id,bool {
 if !enter(p,source,tokens) { return 0,false; }
 let start=expect(p,source,tokens,t_newline).start; expect(p,source,tokens,t_indent); var statements=ScratchIdBuffer {};  newlines(p,source,tokens);
 while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_dedent)&&!at(p,source,tokens,t_eof) {
  if at(p,source,tokens,t_kw_return)&&peek(p,tokens,1)==t_kw_use {
   let ret_start=advance(p,source,tokens).start; advance(p,source,tokens);
   let tmp=collection_name(p,source,tokens,ret_start);
   let used=expression(p,source,tokens);
   let use_stmt=add(p,source,tokens,a_use_stmt,tmp,used,0,ret_start);
   let tmp_ref=add(p,source,tokens,a_name,tmp,0,0,ret_start);
   let ret_stmt=add(p,source,tokens,a_function_return_stmt,tmp_ref,0,0,ret_start);
   statements.push(use_stmt); statements.push(ret_stmt);
  } else {
   statements.push(statement(p,source,tokens));
  }
  if p.failure!=blot_error::Error.none { { p.depth--; } statements.deinit(); return 0,false; } if !at(p,source,tokens,t_newline)&&!at(p,source,tokens,t_dedent) { let err_id=fail(p,source,tokens,c_expected_token); { p.depth--; } statements.deinit(); return err_id,false; } newlines(p,source,tokens); }
 expect(p,source,tokens,t_dedent);
 if unwrap_expr&&p.failure==blot_error::Error.none&&statements.len==1 {
  let only=statements.items[0]; let only_tag=p.tree.node(only).tag;
  if !is_statement_tag(only_tag)&&(!keep_block||only_tag!=a_block) { { p.depth--; } statements.deinit(); return only,false; }
 }
 let block_id: Id = list_node(p,source,tokens,a_block,statements.items,start); { p.depth--; } statements.deinit(); return block_id,true;
}
recursive fn suite(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id { let node,ignored=suite_body(p,source,tokens,false,false); return node; }
recursive fn statement(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 if p.failure!=blot_error::Error.none { return 0; } let start=current(p,source,tokens).start;
 if named_function_ahead(p,source,tokens) {return local_function_declaration(p,source,tokens);}
 if eat(p,source,tokens,t_kw_let) {
  let pat=pattern(p,source,tokens); var annotation: Id=0; if eat(p,source,tokens,t_colon) { annotation=type_expression(p,source,tokens); } let constraints=where_clause(p,source,tokens); expect(p,source,tokens,t_equal); let value=expression(p,source,tokens); var fallback: Id=0;
  if eat(p,source,tokens,t_kw_else) { expect(p,source,tokens,t_colon); fallback=suite(p,source,tokens); } return add(p,source,tokens,a_let_stmt,pat,value,extra(p,source,tokens,[annotation,constraints.predicates.start,constraints.predicates.len,fallback,constraints.node]),start);
 }
 if eat(p,source,tokens,t_kw_return) { let value=expression(p,source,tokens); return add(p,source,tokens,a_function_return_stmt,value,0,0,start); }
 if eat(p,source,tokens,t_kw_break) {
  if at(p,source,tokens,t_newline)||at(p,source,tokens,t_dedent)||at(p,source,tokens,t_eof) { return add(p,source,tokens,a_break_stmt,0,0,0,start); }
  var forwarding: u32=0; if eat(p,source,tokens,t_dollar) { forwarding=1; } let value=expression(p,source,tokens); return add(p,source,tokens,a_return_stmt,value,forwarding,0,start);
 }
 if eat(p,source,tokens,t_kw_continue) { return add(p,source,tokens,a_continue_stmt,0,0,0,start); }
 if at(p,source,tokens,t_kw_if) { return if_statement(p,source,tokens); } if at(p,source,tokens,t_kw_for) { return for_statement(p,source,tokens); } if at(p,source,tokens,t_kw_with) { return with_statement(p,source,tokens); }
 if at(p,source,tokens,t_hash)&&text(p,source,current(p,source,tokens))=="#" {
  if peek(p,tokens,1)==t_kw_for { return comptime_for(p,source,tokens,false); }
  if peek(p,tokens,1)==t_kw_if { return comptime_if_statement(p,source,tokens); }
 }
 if eat(p,source,tokens,t_kw_use) {
  if (at(p,source,tokens,t_type_identifier)||at(p,source,tokens,t_kw_true)||at(p,source,tokens,t_kw_false))&&has_use_binding(p,tokens) { return identifier_syntax(p,source,tokens); }
  if at(p,source,tokens,t_identifier)&&has_use_binding(p,tokens) { let name=lower_identifier(p,source,tokens); var annotation: Id=0; if eat(p,source,tokens,t_colon) { annotation=type_expression(p,source,tokens); } expect(p,source,tokens,t_left_arrow); let value=expression(p,source,tokens); return add(p,source,tokens,a_use_stmt,name,value,annotation,start); }
  let value=expression(p,source,tokens); return add(p,source,tokens,a_use_stmt,0,value,0,start);
 }
 let assignment=assignment_operator(p,tokens);
 if assignment==t_colon_equal {
  if at(p,source,tokens,t_type_identifier)||at(p,source,tokens,t_kw_true)||at(p,source,tokens,t_kw_false) { return identifier_syntax(p,source,tokens); }
  if at(p,source,tokens,t_identifier) { let target=place(p,source,tokens,start); if p.failure!=blot_error::Error.none { return 0; } expect(p,source,tokens,t_colon_equal); let value=expression(p,source,tokens); return add(p,source,tokens,a_rebind_stmt,target,value,0,start); }
 }
 return expression(p,source,tokens);
}
recursive fn local_function_declaration(p:Parser&,source:const u8[:],tokens:const Token[:])->Id {
 let declaration_id=declaration(p,source,tokens,false,false);if p.failure!=blot_error::Error.none {return 0;}
 if p.tree.node(declaration_id).tag!=a_value_decl||!p.tree.value_decl(declaration_id).function_declaration {return fail(p,source,tokens,c_expected_token);}return declaration_id;
}
fn named_function_ahead(p:Parser&,source:const u8[:],tokens:const Token[:])->bool {
 if !at(p,source,tokens,t_kw_func)||peek(p,tokens,1)!=t_identifier {return false;}return peek(p,tokens,2)==t_identifier||peek(p,tokens,2)==t_l_paren;
}
fn has_use_binding(p: Parser&,tokens: const Token[:]) -> bool {
 if peek(p,tokens,1)==t_left_arrow { return true; } if peek(p,tokens,1)!=t_colon { return false; }
 var nesting=0; var i=p.index+2;
 while i<tokens.len {
  let tag=tokens[i].tag; if nesting==0 { if tag==t_left_arrow { return true; } if tag==t_newline||tag==t_dedent||tag==t_eof { return false; } }
  if tag==t_l_paren||tag==t_l_bracket||tag==t_l_brace { nesting++; } else if (tag==t_r_paren||tag==t_r_bracket||tag==t_r_brace)&&nesting!=0 { nesting--; } i++;
 }
 return false;
}
// The target of `:=`: a name followed by field and index steps.
recursive fn place(p: Parser&,source: const u8[:],tokens: const Token[:],start: u32) -> Id {
 var target: Id=0; if at(p,source,tokens,t_identifier) { let name=lower_identifier(p,source,tokens); target=add(p,source,tokens,a_name,name,0,0,start); } else { target=atom(p,source,tokens); }
 while p.failure==blot_error::Error.none&&(at(p,source,tokens,t_dot)||at(p,source,tokens,t_l_bracket)) {
  if at(p,source,tokens,t_dot) { let dot=advance(p,source,tokens);
   if eat(p,source,tokens,t_l_paren) {
    let binder=lower_identifier(p,source,tokens);
    expect(p,source,tokens,t_r_paren);
    target=add(p,source,tokens,a_comptime_project,target,binder,0,start);
    continue;
   }
   let member=member_identifier(p,source,tokens); target=add(p,source,tokens,a_field_access,target,member,0,start); if p.failure!=blot_error::Error.none { return 0; } p.tree.operator_origins.push(blot_parse_ast::OperatorOrigin {node:target,span:Span {dot.start,dot.end},member:member}); }
  else { advance(p,source,tokens); let index=expression(p,source,tokens); expect(p,source,tokens,t_r_bracket); target=add(p,source,tokens,a_index_access,target,index,0,start); }
 }
 return target;
}
// Classify before allocating a target. An ordinary call such as f [a, b]
// must not speculatively parse the argument as an index. A top-level `:=`
// on the statement's line rebinds; the end-of-file tag stands for none.
fn assignment_operator(p: Parser&,tokens: const Token[:]) -> blot_parse_token::Tag {
 var nesting=0; var i=p.index;
 while i<tokens.len {
  let tag=tokens[i].tag; if nesting==0 { if tag==t_colon_equal { return tag; } if tag==t_newline||tag==t_dedent||tag==t_eof||tag==t_comma||tag==t_r_brace||tag==t_r_paren||tag==t_r_bracket { return t_eof; } }
  if tag==t_l_paren||tag==t_l_bracket||tag==t_l_brace { nesting++; } else if (tag==t_r_paren||tag==t_r_bracket||tag==t_r_brace)&&nesting!=0 { nesting--; } i++;
 }
 return t_eof;
}
fn with_entry_has_equal(p: Parser&,tokens: const Token[:]) -> bool {
 var nesting=0; var i=p.index;
 while i<tokens.len {
  let tag=tokens[i].tag;
  if nesting==0 {
   if tag==t_equal { return true; }
   if tag==t_comma||tag==t_colon||tag==t_newline||tag==t_dedent||tag==t_eof { return false; }
  }
  if tag==t_l_paren||tag==t_l_bracket||tag==t_l_brace { nesting++; }
  else if (tag==t_r_paren||tag==t_r_bracket||tag==t_r_brace)&&nesting!=0 { nesting--; }
  i++;
 }
 return false;
}
recursive fn with_statement(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 let start=expect(p,source,tokens,t_kw_with).start;
 var entries=ScratchIdBuffer {};
 while p.failure==blot_error::Error.none {
  let entry_start=current(p,source,tokens).start;
  if with_entry_has_equal(p,tokens) {
   let effect_type=type_application(p,source,tokens);
   expect(p,source,tokens,t_equal);
   let handler=expression(p,source,tokens);
   entries.push(add(p,source,tokens,a_with_entry,effect_type,handler,1,entry_start));
  } else {
   let expr=expression(p,source,tokens);
   entries.push(add(p,source,tokens,a_with_entry,expr,0,0,entry_start));
  }
  if !eat(p,source,tokens,t_comma) { break; }
 }
 expect(p,source,tokens,t_colon);
 let body=suite(p,source,tokens);
 let range=list(p,source,tokens,entries.items);
 let result: Id = add(p,source,tokens,a_with_stmt,range.start,range.len,body,start);
 entries.deinit();
 return result;
}
recursive fn trailing_comptime_else(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 let saved=p.index; newlines(p,source,tokens);
 if !(at(p,source,tokens,t_hash)&&text(p,source,current(p,source,tokens))=="#"&&peek(p,tokens,1)==t_kw_else) { p.index=saved; return 0; }
 advance(p,source,tokens); advance(p,source,tokens); expect(p,source,tokens,t_colon); return suite(p,source,tokens);
}
recursive fn comptime_for(p: Parser&,source: const u8[:],tokens: const Token[:],builder: bool) -> Id {
 let start=advance(p,source,tokens).start; expect(p,source,tokens,t_kw_for);
 let name=lower_identifier(p,source,tokens); expect(p,source,tokens,t_kw_in);
 if !(at(p,source,tokens,t_hash)&&text(p,source,current(p,source,tokens))=="#") { return fail(p,source,tokens,c_expected_token); }
 advance(p,source,tokens);
 var mode: u32=0;
 if word(p,source,tokens,"fields") { advance(p,source,tokens); if builder { mode=2; } }
 else if !builder && word(p,source,tokens,"variants") { advance(p,source,tokens); mode=1; }
 else { return fail(p,source,tokens,c_expected_token); }
 let target_type=type_atom(p,source,tokens);
 expect(p,source,tokens,t_colon);
 let body=suite(p,source,tokens);
 return add(p,source,tokens,a_comptime_for,name,target_type,extra(p,source,tokens,[body,mode]),start);
}
recursive fn comptime_if_statement(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 let start=advance(p,source,tokens).start; expect(p,source,tokens,t_kw_if);
 let condition=expression(p,source,tokens);
 expect(p,source,tokens,t_colon);
 let body=suite(p,source,tokens);
 let fallback=trailing_comptime_else(p,source,tokens);
 return add(p,source,tokens,a_comptime_if,condition,body,fallback,start);
}
recursive fn trailing_else(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id { let saved=p.index; newlines(p,source,tokens); if !eat(p,source,tokens,t_kw_else) { p.index=saved; return 0; } expect(p,source,tokens,t_colon); return suite(p,source,tokens); }
recursive fn if_statement(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 let start=expect(p,source,tokens,t_kw_if).start;
 if eat(p,source,tokens,t_kw_let) { let pat=pattern(p,source,tokens); expect(p,source,tokens,t_equal); let value=expression(p,source,tokens); expect(p,source,tokens,t_colon); let body=suite(p,source,tokens); let fallback=trailing_else(p,source,tokens); return add(p,source,tokens,a_if_let_stmt,pat,value,extra(p,source,tokens,[body,fallback]),start); }
 let condition=expression(p,source,tokens);
 if eat(p,source,tokens,t_kw_then) { let consequence=expression(p,source,tokens); expect(p,source,tokens,t_kw_else); let fallback=expression(p,source,tokens); return add(p,source,tokens,a_if_expr,condition,consequence,fallback,start); }
 expect(p,source,tokens,t_colon); let body=suite(p,source,tokens); let fallback=trailing_else(p,source,tokens); return add(p,source,tokens,a_if_stmt,condition,body,fallback,start);
}
recursive fn for_statement(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 let start=expect(p,source,tokens,t_kw_for).start;
 if eat(p,source,tokens,t_kw_ever) { expect(p,source,tokens,t_colon); let body=suite(p,source,tokens); return add(p,source,tokens,a_forever_stmt,body,0,0,start); }
 let explicit=eat(p,source,tokens,t_kw_let); var has_in=explicit; var i=p.index; var nesting=0;
 while i<tokens.len { let t=tokens[i].tag; if nesting==0&&(t==t_colon||t==t_newline||t==t_eof) { break; } if nesting==0&&t==t_kw_in { has_in=true; break; } if t==t_l_paren||t==t_l_bracket||t==t_l_brace { nesting++; } if (t==t_r_paren||t==t_r_bracket||t==t_r_brace)&&nesting!=0 { nesting--; } i++; }
 if has_in { let pat=pattern(p,source,tokens); expect(p,source,tokens,t_kw_in); let value=expression(p,source,tokens); var end: Id=0; if eat(p,source,tokens,t_dot_dot) { end=expression(p,source,tokens); } expect(p,source,tokens,t_colon); let body=suite(p,source,tokens); return collection_loop(p,source,tokens,pat,value,end,body,explicit,start); }
 let first=expression(p,source,tokens); expect(p,source,tokens,t_dot_dot); let end=expression(p,source,tokens); expect(p,source,tokens,t_colon); let body=suite(p,source,tokens); return add(p,source,tokens,a_range_stmt,first,end,body,start);
}
recursive fn constructor_fields(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 if !enter(p,source,tokens) { return 0; }
 let start=expect(p,source,tokens,t_l_brace).start; var fields=ScratchIdBuffer {};
 while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_brace) { let point=current(p,source,tokens).start; let name=lower_identifier(p,source,tokens); var value: Id=0; if eat(p,source,tokens,t_colon) { value=pattern(p,source,tokens); } fields.push(add(p,source,tokens,a_pattern_field,name,value,0,point)); if !eat(p,source,tokens,t_comma) { break; } }
 expect(p,source,tokens,t_r_brace); let __cleanup_result_67_0: Id = list_node(p,source,tokens,a_pattern_record,fields.items,start); { p.depth--; } let __cleanup_result_70_0: Id = __cleanup_result_67_0; fields.deinit(); return __cleanup_result_70_0;
 { p.depth--; }  fields.deinit(); }
recursive fn pattern(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 if !enter(p,source,tokens) { return 0; }  let t=current(p,source,tokens); let start=t.start;
 if eat(p,source,tokens,t_caret) { let __cleanup_result_68_0: Id = add(p,source,tokens,a_pattern_value,qualified(p,source,tokens),0,0,start); { p.depth--; } return __cleanup_result_68_0; }
 if at(p,source,tokens,t_kw_true)||at(p,source,tokens,t_kw_false) { advance(p,source,tokens); var value: u32=0; if t.tag==t_kw_true { value=1; } let __cleanup_result_69_0: Id = add(p,source,tokens,a_pattern_boolean,value,0,0,start); { p.depth--; } return __cleanup_result_69_0; }
 if at(p,source,tokens,t_type_identifier) { let __cleanup_result_70_0: Id = identifier_syntax(p,source,tokens); { p.depth--; } return __cleanup_result_70_0; } if at(p,source,tokens,t_identifier) { let __cleanup_result_71_0: Id = add(p,source,tokens,a_pattern_name,lower_identifier(p,source,tokens),0,0,start); { p.depth--; } return __cleanup_result_71_0; }
 if eat(p,source,tokens,t_integer) { let __cleanup_result_72_0: Id = integer_literal(p,source,tokens,t,a_pattern_integer); { p.depth--; } return __cleanup_result_72_0; }
 if eat(p,source,tokens,t_hash) { let name=constructor_pattern_name(p,source,tokens); var payload: Id=0; if at(p,source,tokens,t_l_brace) { payload=constructor_fields(p,source,tokens); } else if pattern_tag(current(p,source,tokens).tag) { payload=pattern(p,source,tokens); } let __cleanup_result_73_0: Id = add(p,source,tokens,a_pattern_constructor,name,payload,0,start); { p.depth--; } return __cleanup_result_73_0; }
 if at(p,source,tokens,t_l_brace) { let __cleanup_result_74_0: Id = constructor_fields(p,source,tokens); { p.depth--; } return __cleanup_result_74_0; }
 if eat(p,source,tokens,t_l_paren) { var values=ScratchIdBuffer {};  var tuple=false; while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_r_paren) { values.push(pattern(p,source,tokens)); if !eat(p,source,tokens,t_comma) { break; } tuple=true; } expect(p,source,tokens,t_r_paren); if !tuple&&values.len==1 { let __cleanup_result_75_0: Id = values.items[0]; { p.depth--; } let __cleanup_result_71_0: Id = __cleanup_result_75_0; values.deinit(); return __cleanup_result_71_0; } let __cleanup_result_76_0: Id = list_node(p,source,tokens,a_pattern_product,values.items,start); { p.depth--; } let __cleanup_result_72_0: Id = __cleanup_result_76_0; values.deinit(); return __cleanup_result_72_0;  values.deinit(); }
 let __cleanup_result_77_0: Id = fail(p,source,tokens,c_expected_pattern); { p.depth--; } return __cleanup_result_77_0;
 { p.depth--; } }
fn pattern_row(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id { let start=current(p,source,tokens).start; var values=ScratchIdBuffer {};  values.push(pattern(p,source,tokens)); while p.failure==blot_error::Error.none&&eat(p,source,tokens,t_comma) { values.push(pattern(p,source,tokens)); } let __cleanup_result_73_0: Id = list_node(p,source,tokens,a_pattern_row,values.items,start); values.deinit(); return __cleanup_result_73_0;  values.deinit(); }
recursive fn case_expression(p: Parser&,source: const u8[:],tokens: const Token[:]) -> Id {
 let start=expect(p,source,tokens,t_kw_case).start; var values=ScratchIdBuffer {};
 values.push(expression(p,source,tokens)); while p.failure==blot_error::Error.none&&eat(p,source,tokens,t_comma) { values.push(expression(p,source,tokens)); }
 expect(p,source,tokens,t_kw_of); expect(p,source,tokens,t_newline); expect(p,source,tokens,t_indent); newlines(p,source,tokens); var arms=ScratchIdBuffer {};
 while p.failure==blot_error::Error.none&&!at(p,source,tokens,t_dedent)&&!at(p,source,tokens,t_eof) {
  let point=current(p,source,tokens).start;
  var rows=ScratchIdBuffer {};  rows.push(pattern_row(p,source,tokens)); while p.failure==blot_error::Error.none&&eat(p,source,tokens,t_pipe) { rows.push(pattern_row(p,source,tokens)); } var guard_: Id=0; if eat(p,source,tokens,t_kw_if) { guard_=expression(p,source,tokens); }
  expect(p,source,tokens,t_fat_arrow); var body: Id=0;
  if at(p,source,tokens,t_newline)&&peek(p,tokens,1)==t_indent {
   let parsed_arm,ignored=suite_body(p,source,tokens,true,false);
   body=parsed_arm;
  } else {
   body=expression(p,source,tokens);
  }
  let range=list(p,source,tokens,rows.items); arms.push(add(p,source,tokens,a_case_arm,range.start,range.len,extra(p,source,tokens,[guard_,body]),point));
  rows.deinit();
  if p.failure!=blot_error::Error.none { let __cleanup_result_76_0: Id = 0; arms.deinit(); values.deinit(); return __cleanup_result_76_0; } if !at(p,source,tokens,t_newline)&&!at(p,source,tokens,t_dedent) { let __cleanup_result_77_0: Id = fail(p,source,tokens,c_expected_token); arms.deinit(); values.deinit(); return __cleanup_result_77_0; } newlines(p,source,tokens);
 }
 expect(p,source,tokens,t_dedent); let inputs=list(p,source,tokens,values.items); let cases=list(p,source,tokens,arms.items); let __cleanup_result_78_0: Id = add(p,source,tokens,a_case_expr,extra(p,source,tokens,[inputs.start,inputs.len]),cases.start,cases.len,start); arms.deinit(); values.deinit(); return __cleanup_result_78_0;
 arms.deinit(); values.deinit(); }
fn operator_tag(tag: Tag) -> bool { return tag==t_symbol||tag==t_dollar||tag==t_star||tag==t_caret||tag==t_pipe||tag==t_kw_and||tag==t_kw_or; }
fn atom_tag(tag: Tag) -> bool { return tag==t_integer||tag==t_float||tag==t_string||tag==t_intrinsic||tag==t_identifier||tag==t_type_identifier||tag==t_selector||tag==t_hash||tag==t_l_paren||tag==t_l_bracket||tag==t_l_brace||tag==t_colon||tag==t_kw_true||tag==t_kw_false||tag==t_kw_spark; }
fn type_atom_tag(tag: Tag) -> bool { return tag==t_identifier||tag==t_type_identifier||tag==t_intrinsic||tag==t_l_paren||tag==t_l_bracket||tag==t_l_brace||tag==t_caret||tag==t_symbol; }
fn type_atom_at(p: Parser&,source: const u8[:],tokens: const Token[:],offset: i64) -> bool {
 let idx=p.index+offset; if idx>=tokens.len { return false; }
 let tag=tokens[idx].tag;
 if type_atom_tag(tag)||tag==t_star { return true; }
 if tag==t_hash&&text(p,source,tokens[idx])=="#"&&peek(p,tokens,offset+1)==t_l_bracket { return true; }
 return false;
}
fn is_statement_tag(tag: blot_parse_ast::Tag) -> bool {
 return tag==a_let_stmt||tag==a_rebind_stmt||tag==a_use_stmt||tag==a_iterator_bind||tag==a_function_return_stmt||tag==a_return_stmt||tag==a_break_stmt||tag==a_continue_stmt||tag==a_if_stmt||tag==a_if_let_stmt||tag==a_for_stmt||tag==a_range_stmt||tag==a_forever_stmt||tag==a_with_stmt||tag==a_comptime_for||tag==a_comptime_if||tag==a_value_decl;
}
fn pattern_tag(tag: Tag) -> bool { return tag==t_identifier||tag==t_integer||tag==t_hash||tag==t_caret||tag==t_l_paren||tag==t_l_brace||tag==t_kw_true||tag==t_kw_false; }
fn parser_context(pool: blot_parse_symbols::Pool&,tree: Tree&) -> Parser {
 return Parser {pool:pool,tree:tree};
}
fn parse_work(source: const u8[:],tokens: const Token[:],pool: blot_parse_symbols::Pool&,tree: Tree&,recorded:ScratchIdBuffer?) -> Error {
 if tokens.len > 64 {
  let est = tokens.len / 2 + 16;
  if tree.nodes.storage.len < est { let _ = tree.nodes.ensure(est); }
  if tree.spans.storage.len < est { let _ = tree.spans.ensure(est); }
  let extra_est = tokens.len / 4 + 16;
  if tree.extra.storage.len < extra_est { let _ = tree.extra.ensure(extra_est); }
 }
 var p=parser_context(pool,tree);p.recorded .= recorded;
 var declarations_seen=false; var body_declarations_seen=false;
 while !at(p,source,tokens,t_eof) {
  newlines(p,source,tokens); if at(p,source,tokens,t_eof) { break; } let before=p.index; let first_node=tree.nodes.len as Id;
  let root=declaration(p,source,tokens,declarations_seen,body_declarations_seen);
  if p.failure==blot_error::Error.syntax { recover(p,source,tokens,before); continue; } if p.failure!=blot_error::Error.none { return p.failure; }
  tree.roots.push(root); tree.declaration_nodes.push(blot_parse_ast::DeclarationNodes {root,first_node,tree.nodes.len as Id});
  let tag=tree.node(root).tag; if tag!=a_import_decl&&tag!=a_export_decl { declarations_seen=true; body_declarations_seen=true; }
  if !at(p,source,tokens,t_newline)&&!at(p,source,tokens,t_eof) { report(p,source,tokens,c_unexpected_token); recover(p,source,tokens,before); } newlines(p,source,tokens);
 }
 return tree.failure();
}
fn parse_with_recorded(source: const u8[:],tokens: const Token[:],pool: blot_parse_symbols::Pool&,tree: Tree&,recorded:ScratchIdBuffer?=null) -> Error {
 return parse_work(source,tokens,pool,tree,recorded);
}
fn parse(source: const u8[:],tokens: const Token[:],pool: blot_parse_symbols::Pool&,tree: Tree&) -> Error { return parse_work(source,tokens,pool,tree,null); }

struct ScratchIdBuffer { storage: Id[:]=default<Id[:]>(),items: Id[:]=default<Id[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_ScratchIdBuffer: Id[>..]=[];
fn ensure(self_: ScratchIdBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_ScratchIdBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: ScratchIdBuffer&,value: Id) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_ScratchIdBuffer); self_.len=self_.items.len; }
fn append(self_: ScratchIdBuffer&,values: const Id[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_ScratchIdBuffer); self_.len=self_.items.len; }
fn resize(self_: ScratchIdBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: ScratchIdBuffer&,length: i64,value: Id) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: ScratchIdBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: ScratchIdBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_ScratchIdBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct ScratchQualifierBuffer { storage: Qualifier[:]=default<Qualifier[:]>(),items: Qualifier[:]=default<Qualifier[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_ScratchQualifierBuffer: Qualifier[>..]=[];
fn ensure(self_: ScratchQualifierBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_ScratchQualifierBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: ScratchQualifierBuffer&,value: Qualifier) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_ScratchQualifierBuffer); self_.len=self_.items.len; }
fn append(self_: ScratchQualifierBuffer&,values: const Qualifier[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_ScratchQualifierBuffer); self_.len=self_.items.len; }
fn resize(self_: ScratchQualifierBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: ScratchQualifierBuffer&,length: i64,value: Qualifier) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: ScratchQualifierBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: ScratchQualifierBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_ScratchQualifierBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct ScratchOperatorBuffer { storage: Operator[:]=default<Operator[:]>(),items: Operator[:]=default<Operator[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_ScratchOperatorBuffer: Operator[>..]=[];
fn ensure(self_: ScratchOperatorBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_ScratchOperatorBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: ScratchOperatorBuffer&,value: Operator) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_ScratchOperatorBuffer); self_.len=self_.items.len; }
fn append(self_: ScratchOperatorBuffer&,values: const Operator[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_ScratchOperatorBuffer); self_.len=self_.items.len; }
fn resize(self_: ScratchOperatorBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: ScratchOperatorBuffer&,length: i64,value: Operator) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: ScratchOperatorBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: ScratchOperatorBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_ScratchOperatorBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct ScratchLambdaParameterBuffer { storage: LambdaParameter[:]=default<LambdaParameter[:]>(),items: LambdaParameter[:]=default<LambdaParameter[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_ScratchLambdaParameterBuffer: LambdaParameter[>..]=[];
fn ensure(self_: ScratchLambdaParameterBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_ScratchLambdaParameterBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: ScratchLambdaParameterBuffer&,value: LambdaParameter) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_ScratchLambdaParameterBuffer); self_.len=self_.items.len; }
fn append(self_: ScratchLambdaParameterBuffer&,values: const LambdaParameter[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_ScratchLambdaParameterBuffer); self_.len=self_.items.len; }
fn resize(self_: ScratchLambdaParameterBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: ScratchLambdaParameterBuffer&,length: i64,value: LambdaParameter) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: ScratchLambdaParameterBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: ScratchLambdaParameterBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_ScratchLambdaParameterBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct Scratchu8Buffer { storage: u8[:]=default<u8[:]>(),items: u8[:]=default<u8[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_Scratchu8Buffer: u8[>..]=[];
fn ensure(self_: Scratchu8Buffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Scratchu8Buffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: Scratchu8Buffer&,value: u8) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Scratchu8Buffer); self_.len=self_.items.len; }
fn append(self_: Scratchu8Buffer&,values: const u8[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Scratchu8Buffer); self_.len=self_.items.len; }
fn resize(self_: Scratchu8Buffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: Scratchu8Buffer&,length: i64,value: u8) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: Scratchu8Buffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: Scratchu8Buffer&) { blot_support_pooled_buffer::deinit(self_,pool_Scratchu8Buffer); self_.len=0; self_.failure=blot_error::Error.none; }
