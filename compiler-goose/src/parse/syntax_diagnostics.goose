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
  var span=blot_parse_ast::Span {detail.start,detail.end}; if detail.has_declaration_origin { span=detail.declaration_origin; }
  return Publication {grammar,"GPU_FRONTEND_SYNTAX_ERROR",span,"This declaration does not match the source grammar",detail.has_expected_token,detail.expected_token,detail.has_actual_token,detail.actual_token},blot_error::Error.none;
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
