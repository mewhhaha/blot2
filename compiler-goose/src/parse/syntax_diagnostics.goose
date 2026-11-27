// Source contract: compiler/src/parse/syntax_diagnostics.zig.
namespace blot_parse_syntax_diagnostics;
import .ast;
import .lexer;
import .token;
import support.error;
type Cause=u32;
let grammar: Cause=0; let delimiter: Cause=1; let lexical_cause: Cause=2; let native_detail: Cause=3;
struct Publication {
 cause: Cause, code: const u8[:], span: blot_parse_ast::Span, message: const u8[:],
 has_expected_token: bool=false, expected_token: blot_parse_token::Tag=0,
 has_actual_token: bool=false, actual_token: blot_parse_token::Tag=0
}
fn grammar_failure(code: blot_parse_ast::Code) -> bool {
 return code==blot_parse_ast::code_expected_token||code==blot_parse_ast::code_expected_expression||code==blot_parse_ast::code_expected_type||code==blot_parse_ast::code_expected_pattern||code==blot_parse_ast::code_unexpected_token||code==blot_parse_ast::code_GPU_FRONTEND_SYNTAX_ERROR;
}
fn closer(tag: blot_parse_token::Tag) -> blot_parse_token::Tag,bool {
 if tag==blot_parse_token::l_paren { return blot_parse_token::r_paren,true; }
 if tag==blot_parse_token::l_bracket { return blot_parse_token::r_bracket,true; }
 if tag==blot_parse_token::l_brace { return blot_parse_token::r_brace,true; } return 0,false;
}
fn closing(tag: blot_parse_token::Tag) -> bool { return tag==blot_parse_token::r_paren||tag==blot_parse_token::r_bracket||tag==blot_parse_token::r_brace; }
fn surface_token_name(tag: blot_parse_token::Tag) -> const u8[:] {
 if tag==blot_parse_token::eof { return "end of file"; }
 if tag==blot_parse_token::identifier { return "an identifier"; }
 if tag==blot_parse_token::type_identifier { return "a type name"; }
 if tag==blot_parse_token::integer { return "an integer literal"; }
 if tag==blot_parse_token::float { return "a float literal"; }
 if tag==blot_parse_token::string { return "a string literal"; }
 if tag==blot_parse_token::intrinsic { return "an intrinsic"; }
 if tag==blot_parse_token::symbol { return "an operator"; }
 if tag==blot_parse_token::comment { return "a comment"; }
 if tag==blot_parse_token::l_paren { return "'('"; }
 if tag==blot_parse_token::r_paren { return "')'"; }
 if tag==blot_parse_token::l_bracket { return "'['"; }
 if tag==blot_parse_token::r_bracket { return "']'"; }
 if tag==blot_parse_token::l_brace { return "'{'"; }
 if tag==blot_parse_token::r_brace { return "'}'"; }
 if tag==blot_parse_token::comma { return "','"; }
 if tag==blot_parse_token::dot { return "'.'"; }
 if tag==blot_parse_token::selector { return "a field selector"; }
 if tag==blot_parse_token::dot_dot { return "'..'"; }
 if tag==blot_parse_token::colon { return "':'"; }
 if tag==blot_parse_token::colon_equal { return "':='"; }
 if tag==blot_parse_token::arrow { return "'->'"; }
 if tag==blot_parse_token::fat_arrow { return "'=>'"; }
 if tag==blot_parse_token::left_arrow { return "'<-'"; }
 if tag==blot_parse_token::hash { return "'#'"; }
 if tag==blot_parse_token::at { return "'@'"; }
 if tag==blot_parse_token::ellipsis { return "'...'"; }
 if tag==blot_parse_token::backtick { return "'`'"; }
 if tag==blot_parse_token::dollar { return "'$'"; }
 if tag==blot_parse_token::star { return "'*'"; }
 if tag==blot_parse_token::caret { return "'^'"; }
 if tag==blot_parse_token::pipe { return "'|'"; }
 if tag==blot_parse_token::bang { return "'!'"; }
 if tag==blot_parse_token::equal { return "'='"; }
 if tag==blot_parse_token::kw_import { return "'import'"; }
 if tag==blot_parse_token::kw_as { return "'as'"; }
 if tag==blot_parse_token::kw_const { return "'const'"; }
 if tag==blot_parse_token::kw_let { return "'let'"; }
 if tag==blot_parse_token::kw_type { return "'type'"; }
 if tag==blot_parse_token::kw_is { return "'is'"; }
 if tag==blot_parse_token::kw_data { return "'data'"; }
 if tag==blot_parse_token::kw_effect { return "'effect'"; }
 if tag==blot_parse_token::kw_infixl { return "'infixl'"; }
 if tag==blot_parse_token::kw_infixr { return "'infixr'"; }
 if tag==blot_parse_token::kw_infix { return "'infix'"; }
 if tag==blot_parse_token::kw_func { return "'func'"; }
 if tag==blot_parse_token::kw_if { return "'if'"; }
 if tag==blot_parse_token::kw_then { return "'then'"; }
 if tag==blot_parse_token::kw_else { return "'else'"; }
 if tag==blot_parse_token::kw_do { return "'do'"; }
 if tag==blot_parse_token::kw_case { return "'case'"; }
 if tag==blot_parse_token::kw_of { return "'of'"; }
 if tag==blot_parse_token::kw_for { return "'for'"; }
 if tag==blot_parse_token::kw_in { return "'in'"; }
 if tag==blot_parse_token::kw_ever { return "'ever'"; }
 if tag==blot_parse_token::kw_use { return "'use'"; }
 if tag==blot_parse_token::kw_return { return "'return'"; }
 if tag==blot_parse_token::kw_yield { return "'yield'"; }
 if tag==blot_parse_token::kw_break { return "'break'"; }
 if tag==blot_parse_token::kw_continue { return "'continue'"; }
 if tag==blot_parse_token::kw_complete { return "'complete'"; }
 if tag==blot_parse_token::kw_true { return "'true'"; }
 if tag==blot_parse_token::kw_false { return "'false'"; }
 if tag==blot_parse_token::kw_and { return "'and'"; }
 if tag==blot_parse_token::kw_or { return "'or'"; }
 if tag==blot_parse_token::kw_from { return "'from'"; }
 if tag==blot_parse_token::kw_where { return "'where'"; }
 if tag==blot_parse_token::private_from { return "'from'"; }
 if tag==blot_parse_token::private_where { return "'where'"; }
 if tag==blot_parse_token::newline { return "end of line"; }
 if tag==blot_parse_token::indent { return "an indented block"; }
 if tag==blot_parse_token::dedent { return "end of block"; }
 if tag==blot_parse_token::kw_not { return "'not'"; }
 if tag==blot_parse_token::kw_with { return "'with'"; }
 if tag==blot_parse_token::kw_fork { return "'fork'"; }
 if tag==blot_parse_token::semicolon { return "';'"; }
 if tag==blot_parse_token::kw_spark { return "'spark'"; }
 if tag==blot_parse_token::char_literal { return "a character literal"; }
 if tag==blot_parse_token::byte_string { return "a byte string"; }
 return "a token";
}
fn format_publication_message(value: Publication,out: u8[>..<]&) -> bool {
 if value.cause==delimiter {
  if value.has_expected_token && value.has_actual_token {
   out.append("Unmatched delimiter: expected ");
   out.append(surface_token_name(value.expected_token));
   out.append(", found ");
   out.append(surface_token_name(value.actual_token));
   return true;
  }
  if value.has_actual_token {
   out.append("Unexpected closing delimiter ");
   out.append(surface_token_name(value.actual_token));
   return true;
  }
  return false;
 }
 if value.cause==grammar {
  if value.has_expected_token && value.has_actual_token {
   out.append("Expected ");
   out.append(surface_token_name(value.expected_token));
   out.append(", found ");
   out.append(surface_token_name(value.actual_token));
   return true;
  }
  if value.has_expected_token {
   out.append("Expected ");
   out.append(surface_token_name(value.expected_token));
   return true;
  }
  if value.has_actual_token {
   if value.message=="Expected an expression" || value.message=="Expected a type" || value.message=="Expected a pattern" {
    out.append(value.message);
    out.append(", found ");
    out.append(surface_token_name(value.actual_token));
    return true;
   }
   out.append("Unexpected ");
   out.append(surface_token_name(value.actual_token));
   return true;
  }
 }
 return false;
}
fn malformed(span: blot_parse_ast::Span,expected: blot_parse_token::Tag,has_expected: bool,actual: blot_parse_token::Tag) -> Publication {
 return Publication {cause:delimiter,code:"GPU_FRONTEND_MALFORMED_DELIMITER",span:span,message:"A source delimiter does not match its enclosing pair",has_expected_token:has_expected,expected_token:expected,has_actual_token:true,actual_token:actual};
}
fn delimiters(tokens: const blot_parse_token::Token[:]) -> Publication,bool {
 var stack: blot_parse_token::Token[>..<]=[]; var failure=Publication {grammar,"",blot_parse_ast::Span {},""}; var found=false;
 for current in tokens {
  let close,opens=closer(current.tag);
  if opens { stack.push(current); }
  else if closing(current.tag) {
   var expected: blot_parse_token::Tag=0; var has_expected=false;
   if stack.len!=0 { let open=stack[stack.len-1]; stack.resize(stack.len-1); let t,ok=closer(open.tag); expected=t; has_expected=ok; }
   if (!has_expected||expected!=current.tag)&&(!found||failure.span.start>current.start) { failure=malformed(blot_parse_ast::Span {current.start,current.end},expected,has_expected,current.tag); found=true; }
  }
 }
 for open in stack { if !found||failure.span.start>open.start { let expected,has_expected=closer(open.tag); failure=malformed(blot_parse_ast::Span {open.start,open.end},expected,has_expected,blot_parse_token::eof); found=true; } }
 return failure,found;
}
fn parse(tokens: const blot_parse_token::Token[:],detail: blot_parse_ast::Diagnostic) -> Publication,blot_error::Error {
 if grammar_failure(detail.code) {
  let failure,found=delimiters(tokens); if found { return failure,blot_error::Error.none; }
  var span=blot_parse_ast::Span {detail.start,detail.end};
  if detail.has_detail_span && detail.detail_span.end>=detail.detail_span.start {
   span=detail.detail_span;
  } else if detail.start==0 && detail.end==0 && detail.has_declaration_origin {
   span=detail.declaration_origin;
  }
  var base_message: const u8[:] = "This declaration does not match the source grammar";
  if detail.code==blot_parse_ast::code_expected_expression { base_message="Expected an expression"; }
  else if detail.code==blot_parse_ast::code_expected_type { base_message="Expected a type"; }
  else if detail.code==blot_parse_ast::code_expected_pattern { base_message="Expected a pattern"; }
  return Publication {grammar,"GPU_FRONTEND_SYNTAX_ERROR",span,base_message,detail.has_expected_token,detail.expected_token,detail.has_actual_token,detail.actual_token},blot_error::Error.none;
 }
 return Publication {native_detail,blot_parse_ast::code_name(detail.code),blot_parse_ast::Span {detail.start,detail.end},blot_parse_ast::message(detail),detail.has_expected_token,detail.expected_token,detail.has_actual_token,detail.actual_token},blot_error::Error.none;
}
fn lexical(tokens: const blot_parse_token::Token[:],detail: blot_parse_lexer::Diagnostic) -> Publication {
 if detail.code==blot_parse_lexer::lexical_error { return Publication {lexical_cause,"LEX_UNEXPECTED_CHARACTER",blot_parse_ast::Span {detail.start,detail.end},"No token matches this source character"}; }
 if detail.code==blot_parse_lexer::string_literal||detail.code==blot_parse_lexer::string_escape {
  for current in tokens { if current.tag==blot_parse_token::string&&current.start<=detail.start&&detail.start<=current.end { return Publication {lexical_cause,"LEX_UNEXPECTED_CHARACTER",blot_parse_ast::Span {current.start,current.start+1},"The source string token cannot be recognized"}; } }
 }
 return Publication {native_detail,blot_parse_lexer::code_name(detail.code),blot_parse_ast::Span {detail.start,detail.end},blot_parse_lexer::message(detail)};
}
fn utf16_offset(source: const u8[:],byte_offset: u32) -> u32,bool {
 if byte_offset>source.len { return 0,false; } var byte=0; var units: u32=0;
 while byte<byte_offset { let width=blot_parse_lexer::utf8_width(source[byte]); if width==0||width>byte_offset-byte { return 0,false; } let point,err=blot_parse_lexer::decode_point(source[byte..byte+width]); if err!=blot_error::Error.none { return 0,false; } units++; if point>0xffff { units++; } byte+=width; }
 return units,true;
}
fn utf16(value: Publication,source: const u8[:]) -> blot_parse_ast::Span,bool {
 let start,ok_start=utf16_offset(source,value.span.start); if !ok_start { return blot_parse_ast::Span {},false; }
 let end,ok_end=utf16_offset(source,value.span.end); return blot_parse_ast::Span {start,end},ok_end;
}
