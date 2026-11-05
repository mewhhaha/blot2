// A private repaired source image for one editor query; build inputs stay intact.
namespace blot_reuse_completion_probe;
import parse.lexer;
import parse.token;
import parse.ast;
import support.option;
import support.error;
type Error=blot_error::Error;
type Span=blot_parse_ast::Span;
enum Kind {expression,member,selector,constructor,type_,intrinsic}
let member_marker:const u8[:]="__blot_editor_probe";
struct Probe {source:u8[:]=default<u8[:]>(),replace:Span=Span{},prefix:const u8[:]=default<const u8[:]>(),kind:Kind=Kind.expression,marker:Span=Span{},original_start:u32=0,original_end:u32=0,original_length:u32=0}
reusable[] var repaired_sources:u8[>..]=[];
fn deinit(self_:Probe&) {if self_.source.len!=0 {repaired_sources.free_slice(self_.source);}self_=Probe{};}
fn originalOffset(self_:Probe,offset:u32)->u32 {if offset<=self_.marker.start {return min(offset,self_.original_start);}if offset<self_.marker.end {return self_.original_start;}let tail=offset-self_.marker.end;var end:u32=0xffffffff;if tail<=0xffffffff-self_.original_end {end=self_.original_end+tail;}return min(self_.original_length,end);}
fn originalSpan(self_:Probe,span:Span)->Span {let start=self_.originalOffset(span.start);var end=self_.originalOffset(span.end);if span.end>self_.marker.start && span.end<=self_.marker.end {end=self_.original_end;}return Span{start,max(start,end)};}
fn alphanumeric(byte:u8)->bool {return (byte>='a' && byte<='z') || (byte>='A' && byte<='Z') || (byte>='0' && byte<='9');}
fn capture(source:const u8[:],position:u32)->blot_support::Option<Probe>,Error {
 if source.len>0xffffffff {return blot_support::none<Probe>(),blot_error::Error.source_limit;}if position>source.len || (position<source.len && (source[position]&0xc0)==0x80) {return blot_support::none<Probe>(),blot_error::Error.invalid_position;}
 var at:i64=0;while at<source.len {let width=blot_parse_lexer::utf8_width(source[at]);if width==0 || width>source.len-at {return blot_support::none<Probe>(),blot_error::Error.invalid_source;}let point,error=blot_parse_lexer::decode_point(source[at..at+width]);if error!=blot_error::Error.none {return blot_support::none<Probe>(),blot_error::Error.invalid_source;}at+=width;}
 var tokens:blot_parse_token::Token[>..<];var comments:blot_parse_token::Token[>..<];var diagnostics:blot_parse_lexer::Diagnostic[>..<];var lexical=blot_parse_lexer::init(tokens,comments,diagnostics);let error=blot_parse_lexer::lex(source,lexical);if error!=blot_error::Error.none {return blot_support::none<Probe>(),error;}
 for comment in comments {if comment.start<=position && position<=comment.end {return blot_support::none<Probe>(),blot_error::Error.none;}}
 for token in tokens {if token.tag!=blot_parse_token::string || position<=token.start {continue;}if position<token.end {return blot_support::none<Probe>(),blot_error::Error.none;}if position==token.end {for issue in diagnostics {if issue.code==blot_parse_lexer::string_literal && issue.start==token.start {return blot_support::none<Probe>(),blot_error::Error.none;}}}}
 var replace=Span{position,position};var prefix:const u8[:]=default<const u8[:]>();var previous=blot_support::none<blot_parse_token::Token>();var hole=false;var intrinsic=false;
 for token in tokens {
  if token.start>position {break;}
  if token.tag==blot_parse_token::identifier || token.tag==blot_parse_token::type_identifier || token.tag==blot_parse_token::intrinsic || token.tag==blot_parse_token::kw_true || token.tag==blot_parse_token::kw_false {
   if position<=token.end {replace=Span{token.start,token.end};prefix=source[token.start..position];hole=token.tag==blot_parse_token::intrinsic && blot_parse_token::text(token,source)=="@hole";
    if hole {prefix=[];}else if token.tag==blot_parse_token::intrinsic {intrinsic=true;var start=token.start+1;for index in token.start..position {if source[index]=='.' {start=(index+1) as u32;}}replace.start=start;prefix=source[start..position];}break;
   }
  }
  if token.end<=position && token.start!=token.end && token.tag!=blot_parse_token::newline {previous=blot_support::some(token);}
 }
 var kind=Kind.expression;if intrinsic {kind=Kind.intrinsic;}var original_start=replace.start;
 if !hole && previous.present {let token=previous.value;if token.end==replace.start {if token.tag==blot_parse_token::dot {kind=Kind.member;}else if token.tag==blot_parse_token::selector {kind=Kind.selector;}else if token.tag==blot_parse_token::hash {kind=Kind.constructor;original_start=replace.start;}}}
 if kind==Kind.member {var start=replace.start;while start!=0 {let byte=source[start-1];if !alphanumeric(byte) && byte!='_' && byte!='.' {break;}start--;}if start!=0 && source[start-1]=='$' {kind=Kind.constructor;}}
 var closing:u8[8];var depth:i64=0;var recover=true;
 for token in tokens {
  if token.tag==blot_parse_token::l_paren || token.tag==blot_parse_token::l_bracket {if depth==closing.len {recover=false;break;}var close:u8=')';if token.tag==blot_parse_token::l_bracket {close=']';}closing[depth]=close;depth++;}
  else if token.tag==blot_parse_token::r_paren || token.tag==blot_parse_token::r_bracket {var close:u8=')';if token.tag==blot_parse_token::r_bracket {close=']';}if depth==0 || closing[depth-1]!=close {recover=false;break;}depth--;}
 }
 if !recover {depth=0;}var bytes:u8[>..];bytes.append(source[..original_start]);let marker_start=bytes.len as u32;bytes.append(member_marker);let marker_end=bytes.len as u32;bytes.append(source[replace.end..]);while depth!=0 {depth--;bytes.push(closing[depth]);}
 let owned=repaired_sources.alloc_slice(bytes.len);for byte,index in bytes {owned[index]=byte;}return blot_support::some(Probe{source:owned,replace:replace,prefix:prefix,kind:kind,marker:Span{marker_start,marker_end},original_start:original_start,original_end:replace.end,original_length:source.len as u32}),blot_error::Error.none;
}
