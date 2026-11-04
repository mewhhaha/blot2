// Source contract: compiler/src/parse/lexer.zig. Byte spans and layout are public.
namespace blot_parse_lexer;
import .token;
import support.error;
type Tag = blot_parse_token::Tag;
type Token = blot_parse_token::Token;
type Error = blot_error::Error;
type Code = u32;
let invalid_utf8: Code=0; let lexical_error: Code=1; let string_literal: Code=2;
let string_escape: Code=3; let reserved_layout: Code=4; let reserved_selector_marker: Code=5;
let reserved_import_marker: Code=6; let reserved_clause_marker: Code=7;
let layout_tab: Code=8; let layout_indent: Code=9; let layout_suite: Code=10; let layout_dedent: Code=11;
let integer_range: Code=12; let float_range: Code=13; let float_literal: Code=14;
struct Diagnostic { code: Code, start: u32, end: u32 }
fn message(d: Diagnostic) -> const u8[:] {
 if d.code==invalid_utf8 { return "Source is not valid UTF-8"; }
 if d.code==lexical_error { return "No token matches this source character"; }
 if d.code==string_literal { return "Expected a closing quote before the line ends"; }
 if d.code==string_escape { return "String escapes are limited to quote, backslash, n, r and t"; }
 if d.code==reserved_layout { return "Private layout markers cannot appear in source"; }
 if d.code==reserved_selector_marker { return "Use '.' for a field selector"; }
 if d.code==reserved_import_marker { return "Use 'from' in an import declaration"; }
 if d.code==reserved_clause_marker { return "The spelling 'wherE' is reserved before a clause body"; }
 if d.code==layout_tab { return "Use spaces for indentation"; }
 if d.code==layout_indent { return "Top-level declarations must start at column 1"; }
 if d.code==layout_suite { return "Expected an indented suite"; }
 if d.code==layout_dedent { return "Dedent must match an enclosing indentation level"; }
 if d.code==integer_range { return "Integer literal exceeds U32 (4294967295)"; }
 if d.code==float_range { return "Floating-point literal exceeds finite F32 range"; }
 return "Invalid F32 literal";
}
struct Result { tokens: Token[>..<]&, comments: Token[>..<]&, diagnostics: Diagnostic[>..<]& }
fn init(tokens: Token[>..<]&,comments: Token[>..<]&,diagnostics: Diagnostic[>..<]&) -> Result { return Result {tokens,comments,diagnostics}; }
fn emit(list: Token[>..<]&, tag: Tag, start: i64,end: i64) { list.push(Token {tag,start as u32,end as u32}); }
fn diagnose(result: Result&,code: Code,start: i64,end: i64) { result.diagnostics.push(Diagnostic {code,start as u32,end as u32}); }
fn lower(c: u8) -> bool { return c>='a' && c<='z'; }
fn upper(c: u8) -> bool { return c>='A' && c<='Z'; }
fn digit(c: u8) -> bool { return c>='0' && c<='9'; }
fn ident(c: u8) -> bool { return lower(c)||digit(c)||c=='_'; }
fn type_ident(c: u8) -> bool { return ident(c)||upper(c); }
fn hex(c: u8) -> bool { return digit(c)||(c>='a'&&c<='f')||(c>='A'&&c<='F'); }
fn contains(text: const u8[:],c: u8) -> bool { for item in text { if item==c { return true; } } return false; }
fn starts(text: const u8[:],at: i64,value: const u8[:]) -> bool {
 if value.len>text.len-at { return false; } return text[at..at+value.len]==value;
}
fn symbolic(c: u8) -> bool { return contains("+*$%=!<>^&|?~-",c); }
struct Number { end: i64, tag: Tag }
fn digits(source: const u8[:],start: i64,hexadecimal: bool) -> i64 {
 var at=start;
 while at<source.len {
  var valid=digit(source[at]); if hexadecimal { valid=hex(source[at]); }
  if valid { at++; continue; }
  if source[at]=='_' && at+1<source.len {
   valid=digit(source[at+1]); if hexadecimal { valid=hex(source[at+1]); }
   if valid { at+=2; continue; }
  }
  break;
 }
 return at;
}
fn scan_number(source: const u8[:],start: i64) -> Number {
 if source[start]=='0' && start+2<source.len && (source[start+1]=='x'||source[start+1]=='X') && hex(source[start+2]) { return Number {digits(source,start+2,true),blot_parse_token::integer}; }
 var at=digits(source,start,false); var tag=blot_parse_token::integer;
 if at+1<source.len && source[at]=='.' && digit(source[at+1]) { at=digits(source,at+1,false); tag=blot_parse_token::float; }
 if at<source.len && (source[at]=='e'||source[at]=='E') {
  var exponent=at+1; if exponent<source.len && (source[exponent]=='+'||source[exponent]=='-') { exponent++; }
  if exponent<source.len && digit(source[exponent]) { at=digits(source,exponent,false); tag=blot_parse_token::float; }
 }
 return Number {at,tag};
}
fn integer_value(text: const u8[:]) -> u32,Error {
 var radix: u32=10; var at=0;
 if text.len>=2 && text[0]=='0' && (text[1]=='x'||text[1]=='X') { radix=16; at=2; }
 let first=at; if at==text.len { return 0,Error.invalid_integer; }
 var value: u32=0;
 while at<text.len {
  let c=text[at];
  if c=='_' {
   var valid=false; if at+1<text.len { valid=digit(text[at+1]); if radix==16 { valid=hex(text[at+1]); } }
   if at==first || at+1==text.len || text[at-1]=='_' || !valid { return 0,Error.invalid_integer; }
   at++; continue;
  }
  var valid=digit(c); if radix==16 { valid=hex(c); } if !valid { return 0,Error.invalid_integer; }
  var n: u32=0; if digit(c) { n=(c-'0') as u32; } else if upper(c) { n=(c-'A'+10) as u32; } else { n=(c-'a'+10) as u32; }
  if value>(0xffffffff-n)/radix { return 0,Error.integer_range; }
  value=value*radix+n; at++;
 }
 return value,Error.none;
}
// Exact decimal-to-binary32 rounding. Comparing integer significands to dyadic
// midpoints avoids a binary64 intermediate, including subnormal halfway cases.
fn big_mul_add(x: u32[>..<]&,m: u32,a: u32) {
 var carry=a as u64;
 for i in 0..x.len { let v=(x[i] as u64)*m+carry; x[i]=v as! u32; carry=v>>32; }
 if carry!=0 { x.push(carry as u32); }
}
fn big_shift(x: u32[>..<]&,n: i64) { for i in 0..n { big_mul_add(x,2,0); } }
fn big_compare(a: const u32[:],b: const u32[:]) -> i64 {
 var an=a.len; var bn=b.len;
 while an>0 && a[an-1]==0 { an--; } while bn>0 && b[bn-1]==0 { bn--; }
 if an<bn { return -1; } if an>bn { return 1; }
 while an>0 { an--; if a[an]<b[an] { return -1; } if a[an]>b[an] { return 1; } } return 0;
}
fn compare_decimal(digits: const u8[:],exp10: i64,h: u64,p: i64) -> i64 {
 var a: u32[>..<]=[0]; for c in digits { big_mul_add(a,10,(c-'0') as u32); }
 var b: u32[>..<]=[h as! u32]; if h>>32!=0 { b.push((h>>32) as u32); }
 var shift=exp10-p;
 if exp10>=0 { for i in 0..exp10 { big_mul_add(a,5,0); } }
 else { for i in 0..-exp10 { big_mul_add(b,5,0); } }
 if shift>=0 { big_shift(a,shift); } else { big_shift(b,-shift); }
 return big_compare(a,b);
}
fn dyadic(bits: u32) -> u64,i64 {
 let exponent=(bits>>23)&255; let fraction=bits&0x7fffff;
 if exponent==0 { return fraction as u64,-149; }
 return (fraction|0x800000) as u64,(exponent as i64)-150;
}
fn float_bits(text: const u8[:]) -> u32,Error {
 if text.len==0 || !digit(text[0]) { return 0,Error.invalid_float; }
 let scanned=scan_number(text,0);
 if scanned.tag!=blot_parse_token::float || scanned.end!=text.len { return 0,Error.invalid_float; }
 var significant: u8[>..]=[]; var exp10: i64=0; var fractional=false; var at=0;
 while at<text.len && text[at]!='e' && text[at]!='E' {
  let c=text[at]; if c=='.' { fractional=true; } else if c!='_' { significant.push(c); if fractional { exp10--; } } at++;
 }
 if at<text.len {
  at++; var negative=false; if text[at]=='+'||text[at]=='-' { negative=text[at]=='-'; at++; }
  var exponent: i64=0;
  while at<text.len { if text[at]!='_' && exponent<1000000 { exponent=exponent*10+(text[at]-'0') as i64; } at++; }
  if negative { exp10-=exponent; } else { exp10+=exponent; }
 }
 var leading=0; while leading<significant.len && significant[leading]=='0' { leading++; }
 if leading==significant.len { return 0,Error.none; }
 let exact=significant[leading..]; let magnitude=exact.len+exp10;
 if magnitude>40 { return 0,Error.float_range; } if magnitude < -46 { return 0,Error.none; }
 var low: u32=0; var high: u32=0x7f800000;
 while low+1<high {
  let mid=low+(high-low)/2; let h,p=dyadic(mid);
  if compare_decimal(exact,exp10,h,p)>=0 { low=mid; } else { high=mid; }
 }
 let lh,lp=dyadic(low); var hh: u64=1; var hp: i64=128;
 if high<0x7f800000 { let h,p=dyadic(high); hh=h; hp=p; }
 var base=lp; if hp<base { base=hp; }
 let midpoint=(lh<<(lp-base))+(hh<<(hp-base));
 let comparison=compare_decimal(exact,exp10,midpoint,base-1);
 var rounded=low; if comparison>0 || (comparison==0 && (low&1)!=0) { rounded=high; }
 if rounded>=0x7f800000 { return 0,Error.float_range; }
 return rounded,Error.none;
}
fn utf8_width(c: u8) -> i64 {
 if c<0x80 { return 1; } if c>=0xc2 && c<=0xdf { return 2; }
 if c>=0xe0 && c<=0xef { return 3; } if c>=0xf0 && c<=0xf4 { return 4; } return 0;
}
fn decode_point(bytes: const u8[:]) -> u32,Error {
 if bytes.len<1||bytes.len>4||utf8_width(bytes[0])!=bytes.len { return 0,Error.invalid_utf8; }
 if bytes.len==1 { return bytes[0] as u32,Error.none; }
 var point=(bytes[0] & ((1 << (7-bytes.len))-1)) as u32;
 for i in 1..bytes.len { if (bytes[i]&0xc0)!=0x80 { return 0,Error.invalid_utf8; } point=(point<<6)|(bytes[i]&63); }
 if (bytes.len==2&&point<0x80)||(bytes.len==3&&point<0x800)||(bytes.len==4&&point<0x10000)||point>0x10ffff||(point>=0xd800&&point<=0xdfff) { return 0,Error.invalid_utf8; }
 return point,Error.none;
}
fn validate_source(source: const u8[:],result: Result&) {
 var at=0;
 while at<source.len {
  let width=utf8_width(source[at]); if width==0 { diagnose(result,invalid_utf8,at,at+1); return; }
  if width>source.len-at { diagnose(result,invalid_utf8,at,source.len); return; }
  let point,err=decode_point(source[at..at+width]); if err!=Error.none { diagnose(result,invalid_utf8,at,at+width); return; }
  if point>=0xe000 && point<=0xe002 { diagnose(result,reserved_layout,at,at+width); return; }
  at+=width;
 }
}
fn scan(source: const u8[:],result: Result&) {
 var at=0;
 while at<source.len {
  let start=at; let c=source[at];
  if c==' '||c=='\t'||c=='\r'||c=='\n' { at++; continue; }
  if c=='/'&&at+1<source.len&&source[at+1]=='/' { at+=2; while at<source.len&&source[at]!='\r'&&source[at]!='\n' { at++; } emit(result.comments,blot_parse_token::comment,start,at); continue; }
  if c=='"' {
   at++; var terminated=false;
   while at<source.len && source[at]!='\r'&&source[at]!='\n' {
    if source[at]=='"' { at++; terminated=true; break; }
    if source[at]=='\\' {
     if at+1==source.len||source[at+1]=='\r'||source[at+1]=='\n' { break; }
     if !contains("\"\\nrt",source[at+1]) { diagnose(result,string_escape,at,at+2); } at+=2;
    } else { at++; }
   }
   if !terminated { diagnose(result,string_literal,start,at); } emit(result.tokens,blot_parse_token::string,start,at); continue;
  }
  if digit(c) { let n=scan_number(source,at); at=n.end; emit(result.tokens,n.tag,start,at); continue; }
  if starts(source,at,"froM")||starts(source,at,"wherE") {
   var tag=blot_parse_token::private_where; var size=5; if c=='f' { tag=blot_parse_token::private_from; size=4; } at+=size; emit(result.tokens,tag,start,at); continue;
  }
  if lower(c)||upper(c)||c=='_' {
   let capital=upper(c); at++;
   while at<source.len { var valid=ident(source[at]); if capital { valid=type_ident(source[at]); } if !valid { break; } at++; }
   var kind=blot_parse_token::keyword(source[start..at]); if capital&&kind==blot_parse_token::identifier { kind=blot_parse_token::type_identifier; }
   emit(result.tokens,kind,start,at); continue;
  }
  if c=='@'&&at+1<source.len&&(lower(source[at+1])||source[at+1]=='_') {
   at+=2; while at<source.len&&ident(source[at]) { at++; }
   while at+1<source.len&&source[at]=='.'&&(lower(source[at+1])||upper(source[at+1])||source[at+1]=='_') {
    let capital=upper(source[at+1]); at+=2;
    while at<source.len { var valid=ident(source[at]); if capital { valid=type_ident(source[at]); } if !valid { break; } at++; }
   }
   emit(result.tokens,blot_parse_token::intrinsic,start,at); continue;
  }
  if c=='$'&&at+1<source.len&&(lower(source[at+1])||upper(source[at+1])||source[at+1]=='_') { at++; emit(result.tokens,blot_parse_token::hash,start,at); continue; }
  if symbolic(c)||c=='/' {
   at++; if c!='/' { while at<source.len&&symbolic(source[at]) { at++; } }
   let spelling=source[start..at]; var kind=blot_parse_token::symbol;
   if spelling=="->" { kind=blot_parse_token::arrow; } else if spelling=="=>" { kind=blot_parse_token::fat_arrow; } else if spelling=="<-" { kind=blot_parse_token::left_arrow; }
   else if spelling.len==1 {
    if c=='$' { kind=blot_parse_token::dollar; } else if c=='*' { kind=blot_parse_token::star; } else if c=='^' { kind=blot_parse_token::caret; } else if c=='|' { kind=blot_parse_token::pipe; } else if c=='!' { kind=blot_parse_token::bang; } else if c=='=' { kind=blot_parse_token::equal; }
   }
   emit(result.tokens,kind,start,at); continue;
  }
  at++; var kind=blot_parse_token::eof; var recognized=true;
  if c=='(' { kind=blot_parse_token::l_paren; } else if c==')' { kind=blot_parse_token::r_paren; }
  else if c=='[' { kind=blot_parse_token::l_bracket; } else if c==']' { kind=blot_parse_token::r_bracket; }
  else if c=='{' { kind=blot_parse_token::l_brace; } else if c=='}' { kind=blot_parse_token::r_brace; }
  else if c==',' { kind=blot_parse_token::comma; } else if c=='#' { kind=blot_parse_token::hash; }
  else if c=='@' { kind=blot_parse_token::at; } else if c=='`' { kind=blot_parse_token::backtick; }
  else if c==':' { kind=blot_parse_token::colon; if at<source.len&&source[at]=='=' { at++; kind=blot_parse_token::colon_equal; } }
  else if c=='.' { kind=blot_parse_token::dot; if at<source.len&&source[at]=='.' { at++; kind=blot_parse_token::dot_dot; if at<source.len&&source[at]=='.' { at++; kind=blot_parse_token::ellipsis; } } }
  else { recognized=false; }
  if recognized { emit(result.tokens,kind,start,at); } else { at=start+utf8_width(c); var code=lexical_error; if source[start..at]=="·" { code=reserved_selector_marker; } diagnose(result,code,start,at); }
 }
}
struct Frame { indent: i64, depth: i32 }
struct Indentation { width: i64, start: i64, tab: bool }
fn indentation(source: const u8[:],starts: const u32[:],at: u32) -> Indentation {
 var low=0; var high=starts.len;
 while low+1<high { let mid=low+(high-low)/2; if starts[mid]<=at { low=mid; } else { high=mid; } }
 let start=starts[low] as i64; var end=start; var tab=false;
 while end<at&&(source[end]==' '||source[end]=='\t') { tab=tab||source[end]=='\t'; end++; }
 return Indentation {end-start,start,tab};
}
fn broken_line(source: const u8[:],previous: Token,next: Token) -> bool { for c in source[previous.end..next.start] { if c=='\r'||c=='\n' { return true; } } return false; }
fn close(tag: Tag) -> bool { return tag==blot_parse_token::r_paren||tag==blot_parse_token::r_bracket||tag==blot_parse_token::r_brace; }
fn open(tag: Tag) -> bool { return tag==blot_parse_token::l_paren||tag==blot_parse_token::l_bracket||tag==blot_parse_token::l_brace; }
fn layout(source: const u8[:],result: Result&) {
 var raw: Token[>..]=[]; for t in result.tokens { raw.push(t); } result.tokens.resize(0);
 var starts: u32[>..]=[0]; for c,index in source { if c=='\r'||c=='\n' { starts.push((index+1) as u32); } }
 var frames: Frame[>..<]=[Frame {0,0}]; var depth: i32=0; var operations_depth: i32=-1;
 if raw.len!=0 { let first=raw[0]; let width=indentation(source,starts,first.start); if width.tab { diagnose(result,layout_tab,width.start,first.start); return; } if width.width!=0 { diagnose(result,layout_indent,first.start,first.start); return; } }
 for current,index in raw {
  var previous=Token {blot_parse_token::eof,0,0}; var broken=false;
  if index!=0 { previous=raw[index-1]; broken=broken_line(source,previous,current); }
  if close(current.tag)&&frames.len>1&&frames[frames.len-1].depth==depth {
   emit(result.tokens,blot_parse_token::newline,current.start,current.start);
   while frames.len>1&&frames[frames.len-1].depth==depth { frames.resize(frames.len-1); emit(result.tokens,blot_parse_token::dedent,current.start,current.start); if frames.len>1&&frames[frames.len-1].depth==depth { emit(result.tokens,blot_parse_token::newline,current.start,current.start); } }
  } else if broken&&depth==operations_depth {
   if previous.tag!=blot_parse_token::colon&&previous.tag!=blot_parse_token::arrow { emit(result.tokens,blot_parse_token::newline,current.start,current.start); }
  } else if broken {
   let frame=frames[frames.len-1]; var request_clause=false;
   if previous.tag==blot_parse_token::fat_arrow {
    var first=index-1; while first>0&&!broken_line(source,raw[first-1],raw[first]) { first--; }
    request_clause=raw[first].tag==blot_parse_token::kw_effect||raw[first].tag==blot_parse_token::kw_complete;
    for part in raw[first..index-1] { if part.tag==blot_parse_token::equal||part.tag==blot_parse_token::kw_func||part.tag==blot_parse_token::fat_arrow { request_clause=false; } }
   }
   let suite=previous.tag==blot_parse_token::colon||previous.tag==blot_parse_token::kw_of||request_clause;
   if suite||depth==frame.depth {
    let width=indentation(source,starts,current.start); if width.tab { diagnose(result,layout_tab,width.start,current.start); return; }
    if suite {
     if width.width<=indentation(source,starts,previous.start).width { diagnose(result,layout_suite,current.start,current.start); return; }
     emit(result.tokens,blot_parse_token::newline,current.start,current.start); emit(result.tokens,blot_parse_token::indent,current.start,current.start); frames.push(Frame {width.width,depth});
    } else if width.width>frame.indent||(width.width==frame.indent&&current.tag==blot_parse_token::pipe) {
    } else {
     emit(result.tokens,blot_parse_token::newline,current.start,current.start);
     while width.width<frames[frames.len-1].indent { frames.resize(frames.len-1); emit(result.tokens,blot_parse_token::dedent,current.start,current.start); emit(result.tokens,blot_parse_token::newline,current.start,current.start); }
     if width.width!=frames[frames.len-1].indent { diagnose(result,layout_dedent,current.start,current.start); return; }
    }
   }
  }
  if current.tag==blot_parse_token::l_brace&&index>=3&&raw[index-1].tag==blot_parse_token::equal&&raw[index-2].tag==blot_parse_token::kw_effect&&raw[index-3].tag==blot_parse_token::kw_is { operations_depth=depth+1; }
  if open(current.tag) { depth++; } if close(current.tag) { depth--; } if depth<operations_depth { operations_depth=-1; }
  result.tokens.push(current);
 }
 if raw.len!=0 { emit(result.tokens,blot_parse_token::newline,source.len,source.len); while frames.len>1 { frames.resize(frames.len-1); emit(result.tokens,blot_parse_token::dedent,source.len,source.len); emit(result.tokens,blot_parse_token::newline,source.len,source.len); } }
}
fn annotation_colon(source: const u8[:],tokens: const Token[:],index: i64) -> bool {
 var nested=0; var cursor=index;
 while cursor!=0 {
  cursor--; let tag=tokens[cursor].tag;
  if close(tag) { nested++; continue; }
  if open(tag) { if nested!=0 { nested--; continue; } if tag!=blot_parse_token::l_paren { return false; } }
  if nested!=0 { continue; }
  if tag==blot_parse_token::kw_let||tag==blot_parse_token::kw_const||tag==blot_parse_token::kw_func { return true; }
  if tag==blot_parse_token::identifier&&blot_parse_token::text(tokens[cursor],source)=="impl" { return true; }
  if tag==blot_parse_token::newline||tag==blot_parse_token::equal||tag==blot_parse_token::fat_arrow||tag==blot_parse_token::left_arrow||tag==blot_parse_token::comma { return false; }
 }
 return false;
}
fn contextual(source: const u8[:],result: Result&) {
 var importing=false; var braces: i32=0; var annotation: i32=0; var has_annotation=false;
 for index in 0..result.tokens.len {
  let current=result.tokens[index]; let tag=current.tag;
  if tag==blot_parse_token::kw_import { importing=true; } if tag==blot_parse_token::newline { importing=false; }
  if importing&&index+1<result.tokens.len&&result.tokens[index+1].tag==blot_parse_token::string {
   if tag==blot_parse_token::private_from { diagnose(result,reserved_import_marker,current.start,current.end); }
   else if tag==blot_parse_token::identifier&&blot_parse_token::text(current,source)=="from" { result.tokens[index].tag=blot_parse_token::kw_from; }
  }
  if tag==blot_parse_token::l_brace { braces++; } else if tag==blot_parse_token::r_brace { braces--; }
  if has_annotation&&braces<annotation { has_annotation=false; }
  if tag==blot_parse_token::colon&&annotation_colon(source,result.tokens,index) { annotation=braces; has_annotation=true; }
  else if has_annotation&&annotation==braces&&(tag==blot_parse_token::newline||tag==blot_parse_token::equal||tag==blot_parse_token::fat_arrow||tag==blot_parse_token::left_arrow||tag==blot_parse_token::colon_equal) { has_annotation=false; }
  else if has_annotation&&annotation==braces&&index+1<result.tokens.len&&result.tokens[index+1].tag==blot_parse_token::l_brace {
   if tag==blot_parse_token::private_where { diagnose(result,reserved_clause_marker,current.start,current.end); } else if tag==blot_parse_token::identifier&&blot_parse_token::text(current,source)=="where" { result.tokens[index].tag=blot_parse_token::kw_where; }
  }
  if tag==blot_parse_token::dot {
   let adjacent=index!=0&&result.tokens[index-1].end==current.start; var before: u8=0; if current.start!=0 { before=source[current.start-1]; }
   if !adjacent||!(type_ident(before)||before==']'||before==')'||before=='}') { result.tokens[index].tag=blot_parse_token::selector; }
  }
 }
}
fn lex(source: const u8[:],result: Result&) -> Error {
 if source.len>0xffffffff { return Error.source_limit; }
 validate_source(source,result); if result.diagnostics.len==0 { scan(source,result); }
 if result.diagnostics.len==0 { layout(source,result); if result.diagnostics.len==0 { contextual(source,result); } }
 emit(result.tokens,blot_parse_token::eof,source.len,source.len); return Error.none;
}

fn code_name(code: Code) -> const u8[:] {
 if code==invalid_utf8 { return "invalid_utf8"; }
 if code==lexical_error { return "lexical_error"; }
 if code==string_literal { return "string_literal"; }
 if code==string_escape { return "string_escape"; }
 if code==reserved_layout { return "reserved_layout"; }
 if code==reserved_selector_marker { return "reserved_selector_marker"; }
 if code==reserved_import_marker { return "reserved_import_marker"; }
 if code==reserved_clause_marker { return "reserved_clause_marker"; }
 if code==layout_tab { return "layout_tab"; }
 if code==layout_indent { return "layout_indent"; }
 if code==layout_suite { return "layout_suite"; }
 if code==layout_dedent { return "layout_dedent"; }
 if code==integer_range { return "integer_range"; }
 if code==float_range { return "float_range"; }
 if code==float_literal { return "float_literal"; }
 return "unknown";
}
