// Independent source replay; no producer parse is invoked. The retained full
// source, every lexical component span, homogeneous tuple shape/type, and the
// separately re-recognized scalar Core must match exactly before evaluation.
namespace static_product_verify;
import lexer;
import validate;
import static_verify;
import static_parse;
import static_product_core;
struct Reader {lex:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},bad:bool=false}
fn advance(s:u8[:],r:Reader&) {r.t=lexer::next(s,r.lex);if r.t.kind==9 {r.bad=true;}}
fn eq(s:u8[:],t:lexer::Token,k:i64,v:u8[:])->bool {return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==v;}
fn word(s:u8[:],r:Reader&,k:i64,v:u8[:])->bool {if r.bad || !eq(s,r.t,k,v){r.bad=true;return false;}advance(s,r);return !r.bad;}
fn verify(s:u8[:],p:static_product_core::Tree&)->bool {
    if s.len>16777216 || p.source[..]!=s || p.rows<1 || p.width<2 || p.width>16 || p.parts.len>100000 ||
       p.rows>100000/p.width || p.parts.len!=p.rows*p.width {return false;}
    var r=Reader {lex:lexer::init(s)};advance(s,r);
    if !word(s,r,1,"static") || !word(s,r,1,"let"){return false;}
    let name=r.t;if name.kind!=1 || name.start<0 || name.end<=name.start || name.end>s.len || name.start!=p.name_start || name.end!=p.name_end ||
       !validate::name_valid(s[name.start..name.end]) {return false;}
    advance(s,r);if !word(s,r,5,"="){return false;}
    if p.is_array {if !word(s,r,5,"#") || !word(s,r,5,"["){return false;}}
    else if p.rows!=1 {return false;}
    for row in p.rows {
        if !word(s,r,5,"("){return false;}
        for col in p.width {
            let item=p.parts[row*p.width+col];let begin=r.t.start;var last=begin;var level:i64=0;
            while !r.bad && r.t.kind!=0 {
                if eq(s,r.t,5,"(") {level+=1;}
                else if eq(s,r.t,5,")") {if level==0 {break;}level-=1;}
                else if level==0 && eq(s,r.t,5,",") {break;}
                last=r.t.end;advance(s,r);
            }
            if r.bad || level!=0 || begin<0 || last<=begin || last>s.len || begin!=item.start || last!=item.end ||
               (item.ty!=1 && item.ty!=2) {return false;}
            if row>0 && item.ty!=p.parts[col].ty {return false;}
            var own:u8[>..]=[];if item.ty==1 {own.append("static let v: U32 = ");}else {own.append("static let v: F32 = ");}
            own.append(s[begin..last]);own.push('\n');var parsed=static_parse::parse(own);if parsed.status!=0 || !static_verify::verify(own,parsed.tree){return false;}
            if col+1<p.width && !word(s,r,5,","){return false;}
        }
        if !word(s,r,5,")"){return false;}
        if row+1<p.rows && !word(s,r,5,","){return false;}
    }
    if p.is_array && !word(s,r,5,"]"){return false;}
    while !r.bad && r.t.kind==6 {advance(s,r);}
    return !r.bad && r.t.kind==0;
}
