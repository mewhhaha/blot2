// Replays original bytes, resolves each pure callee from independently checked
// module Core, reconstructs each projected byte and call record, then runs the
// independent product/scalar source recognizers. No caller IDs are authority.
namespace static_compound_verify;
import lexer;
import validate;
import static_parse;
import module_frontend;
import static_product_verify;
import static_compound_core;
fn token(s:u8[:],t:lexer::Token,k:i64,v:u8[:])->bool {return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==v;}
fn verify(source:u8[:],p:static_compound_core::Program&)->bool {
    if source.len>16777216 || source!=p.source[..] || p.split<=0 || p.split>=source.len || p.calls.len>100000{return false;}
    var root=lexer::init(source);var q=lexer::next(source,root);
    while q.kind!=0 && q.kind!=9 && !token(source,q,1,"static") {q=lexer::next(source,root);}
    if q.kind!=1 || q.start!=p.split{return false;}
    var mod,status=module_frontend::parse(source[..p.split]);if status!=0{return false;}
    var core=module_frontend::to_core(mod);if module_frontend::verify_core(mod,core)!=0{return false;}
    let tail=source[p.split..];var expected:u8[>..]=[];expected.append(tail);
    var ts:lexer::Token[>..]=[];var lex=lexer::init(tail);q=lexer::next(tail,lex);
    while q.kind!=0 && q.kind!=9 {if ts.len>=200000{return false;}ts.push(q);q=lexer::next(tail,lex);}
    if q.kind==9{return false;}var at:i64=0;var call:i64=0;
    while at<ts.len {
        let name=ts[at];
        if name.kind==1 && at+3<ts.len && token(tail,ts[at+1],5,"(") && ts[at+2].kind==2 && token(tail,ts[at+3],5,")") {
            if call>=p.calls.len || !validate::name_valid(tail[name.start..name.end]){return false;}
            let literal,ok=static_parse::integer(tail,ts[at+2]);if !ok{return false;}
            var target:i64=-1;for fnc,j in core.functions {if tail[name.start..name.end]==core.source[fnc.name_start..fnc.name_end] {target=j;}}
            let end=ts[at+3].end;let found=p.calls[call];
            if target<0 || found.start!=name.start || found.end!=end || found.name_end!=name.end || found.argument!=literal || found.target!=target{return false;}
            for k in name.start..end {expected[k]=if k==name.start {'0'} else {' '};}
            call+=1;at+=4;
        } else {at+=1;}
    }
    if call!=p.calls.len || expected[..]!=p.projection[..] || !static_product_verify::verify(expected,p.product){return false;}
    for f in core.functions {if expected[p.product.name_start..p.product.name_end]==core.source[f.name_start..f.name_end]{return false;}}
    var used:i64=0;for part in p.product.parts {
        if used<p.calls.len && p.calls[used].start==part.start && part.end==part.start+1 && part.ty==1 {used+=1;}
    }
    return used==p.calls.len;
}
