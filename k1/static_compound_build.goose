// Source-only producer. Direct pure U32 literal calls occupy an entire tuple
// component. A length-preserving projection lets the existing product parser
// establish tuple grouping without treating projected bytes as authority.
namespace static_compound_build;
import lexer;
import validate;
import static_parse;
import module_frontend;
import static_product_parse;
import static_compound_core;
fn is(s:u8[:],t:lexer::Token,k:i64,v:u8[:])->bool {return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==v;}
fn build(source:u8[:])->static_compound_core::Result {
    var lex=lexer::init(source);var t=lexer::next(source,lex);
    while t.kind!=0 && t.kind!=9 && !is(source,t,1,"static") {t=lexer::next(source,lex);}
    if t.kind!=1 || t.start<=0{return static_compound_core::Result {};}
    let split=t.start;var mod,status=module_frontend::parse(source[..split]);if status!=0{return static_compound_core::Result {};}
    var core=module_frontend::to_core(mod);if module_frontend::verify_core(mod,core)!=0{return static_compound_core::Result {};}
    let tail=source[split..];var projection:u8[>..]=[];projection.append(tail);
    var tokens:lexer::Token[>..]=[];var cursor=lexer::init(tail);var tok=lexer::next(tail,cursor);
    while tok.kind!=0 && tok.kind!=9 {if tokens.len>=200000{return static_compound_core::Result {status:2};}tokens.push(tok);tok=lexer::next(tail,cursor);}
    if tok.kind==9{return static_compound_core::Result {};}
    var calls:static_compound_core::Call[>..]=[];var i:i64=0;
    while i<tokens.len {
        let n=tokens[i];
        if n.kind==1 && i+3<tokens.len && is(tail,tokens[i+1],5,"(") && tokens[i+2].kind==2 && is(tail,tokens[i+3],5,")") {
            if !validate::name_valid(tail[n.start..n.end]) {return static_compound_core::Result {};}
            let v,ok=static_parse::integer(tail,tokens[i+2]);if !ok{return static_compound_core::Result {};}
            var target:i64=-1;for f,j in core.functions {if tail[n.start..n.end]==core.source[f.name_start..f.name_end] {target=j;}}
            if target<0{return static_compound_core::Result {};}
            let end=tokens[i+3].end;for q in n.start..end {projection[q]=if q==n.start {'0'} else {' '};}
            calls.push(static_compound_core::Call {start:n.start,end:end,name_end:n.end,argument:v,target:target});i+=4;
        } else {i+=1;}
    }
    var parsed=static_product_parse::parse(projection);if parsed.status!=0{return static_compound_core::Result {status:parsed.status};}
    for f in core.functions {if projection[parsed.tree.name_start..parsed.tree.name_end]==core.source[f.name_start..f.name_end]{return static_compound_core::Result {};}}
    var ci:i64=0;for part in parsed.tree.parts {
        if ci<calls.len && calls[ci].start==part.start && part.end==part.start+1 && part.ty==1 {ci+=1;}
    }
    if ci!=calls.len{return static_compound_core::Result {};}
    return static_compound_core::Result {status:0,program:static_compound_core::Program {source:source,split:split,projection:copy(projection),product:copy(parsed.tree),calls:copy(calls)}};
}
