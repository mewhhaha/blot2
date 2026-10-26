// Bounded source producer: `static let x = (e,e,...)` or homogeneous
// `static let x = #[(e,e,...),...]`; scalar U32/F32 components use the prior
// checked scalar grammar. Empty arrays and untyped scalar-array shorthand are
// deliberately unsupported. Calls, effects and runtime identities reject.
namespace static_product_parse;
import lexer;
import validate;
import static_core;
import static_parse;
import static_product_core;
struct Cursor {lex:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},bad:bool=false}
fn advance(s:u8[:],c:Cursor&) {c.t=lexer::next(s,c.lex);if c.t.kind==9 {c.bad=true;}}
fn is(s:u8[:],t:lexer::Token,k:i64,v:u8[:])->bool {return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==v;}
fn take(s:u8[:],c:Cursor&,k:i64,v:u8[:])->bool {if c.bad || !is(s,c.t,k,v) {c.bad=true;return false;}advance(s,c);return !c.bad;}
fn expr(s:u8[:],start:i64,end:i64,ty:i64)->u8[>..] {
    var out:u8[>..]=[];if ty==1 {out.append("static let v: U32 = ");}else {out.append("static let v: F32 = ");}
    out.append(s[start..end]);out.push('\n');return out;
}
fn part(s:u8[:],c:Cursor&) -> static_product_core::Part,bool {
    let start=c.t.start;var end=start;var nest:i64=0;
    while !c.bad && c.t.kind!=0 {
        if is(s,c.t,5,"(") {nest+=1;}
        else if is(s,c.t,5,")") {if nest==0 {break;}nest-=1;}
        else if nest==0 && is(s,c.t,5,",") {break;}
        end=c.t.end;advance(s,c);
    }
    if c.bad || nest!=0 || start<0 || end<=start || end>s.len{return static_product_core::Part {},false;}
    for ty in [1,2] {let synthetic=expr(s,start,end,ty);var r=static_parse::parse(synthetic);
        if r.status==0 {return static_product_core::Part {start:start,end:end,ty:ty},true;}}
    return static_product_core::Part {},false;
}
fn parse(s:u8[:])->static_product_core::Result {
    var c=Cursor {lex:lexer::init(s)};advance(s,c);
    if !take(s,c,1,"static") || !take(s,c,1,"let") {return static_product_core::Result {};}
    let name=c.t;if name.kind!=1 || name.start<0 || name.end<=name.start || name.end>s.len || !validate::name_valid(s[name.start..name.end]) {return static_product_core::Result {};}
    advance(s,c);if !take(s,c,5,"="){return static_product_core::Result {};}
    var array=false;if is(s,c.t,5,"#") {advance(s,c);if !take(s,c,5,"["){return static_product_core::Result {};}array=true;}
    var parts:static_product_core::Part[>..]=[];var width:i64=0;var rows:i64=0;var types:i64[16]=[0;16];
    loop {
        if !take(s,c,5,"("){return static_product_core::Result {};}
        var count:i64=0;
        loop {
            if count>=16 || parts.len>=100000 {return static_product_core::Result {status:2};}
            let p,ok=part(s,c);if !ok {return static_product_core::Result {};}
            if rows==0 {types[count]=p.ty;}else if count>=width || types[count]!=p.ty{return static_product_core::Result {};}
            parts.push(p);count+=1;
            if is(s,c.t,5,",") {advance(s,c);}else {break;}
        }
        if count<2 || !take(s,c,5,")") || (rows>0 && count!=width) {return static_product_core::Result {};}
        if rows==0 {width=count;}rows+=1;
        if !array || !is(s,c.t,5,","){break;}advance(s,c);
    }
    if array && !take(s,c,5,"]"){return static_product_core::Result {};}
    while !c.bad && c.t.kind==6 {advance(s,c);}
    if c.bad || c.t.kind!=0 {return static_product_core::Result {};}
    return static_product_core::Result {status:0,tree:static_product_core::Tree {source:s,name_start:name.start,name_end:name.end,is_array:array,width:width,rows:rows,parts:parts}};
}
