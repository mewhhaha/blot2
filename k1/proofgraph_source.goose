// Private producer for complete U32 tuple signatures and bounded source
// requirements. A separate verifier must re-lex and recheck every field.
namespace proofgraph_source;
import lexer;
import frontend;
struct Span { start: i64 = 0, end: i64 = 0 }
// kind 1 Le, 2 Lt, 3 Eq; operands are one-based formal components.
struct Fact { kind: u32 = 0, left: u32 = 0, right: u32 = 0, start: i64 = 0, end: i64 = 0 }
struct Program { source: u8[] = [], function: Span = Span {}, count: u32 = 0,
                 names: Span[8] = [Span {};8], facts_count: u32 = 0, facts: Fact[16] = [Fact {};16] }
struct Cursor { state: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, bad: bool = false }
fn next(s: u8[:], c: Cursor&) { c.token=lexer::next(s,c.state); if c.token.kind==9 { c.bad=true; } }
fn take(s: u8[:],c: Cursor&,kind:i64,value:u8[:]) -> Span {
    let t=c.token;
    if c.bad || t.kind!=kind || t.start<0 || t.end<t.start || t.end>s.len || (value.len>0 && s[t.start..t.end]!=value) { c.bad=true; return Span {}; }
    next(s,c); return Span { start:t.start,end:t.end };
}
fn name(s:u8[:],c:Cursor&) -> Span {
    let p=take(s,c,1,"");
    if p.end<=p.start || p.start<0 || p.end>s.len || frontend::reserved(s[p.start..p.end]) { c.bad=true; return Span {}; }
    return p;
}
fn eq(s:u8[:],a:Span,b:Span) -> bool { return a.start>=0 && a.end>a.start && a.end<=s.len && b.start>=0 && b.end>b.start && b.end<=s.len && s[a.start..a.end]==s[b.start..b.end]; }
fn selector(s:u8[:],c:Cursor&,count:u32) -> u32 {
    take(s,c,1,"arg"); take(s,c,5,"."); let t=take(s,c,2,"");
    if c.bad || t.end!=t.start+1 || t.start<0 || t.end>s.len || s[t.start]<'0' || s[t.start]>'7' { c.bad=true; return 0; }
    let id=(s[t.start]-'0') as u32+1; if id>count { c.bad=true; return 0; } return id;
}
fn parse(s:u8[:]) -> Program, i64 {
    if s.len>4096 { return Program {},2; }
    var c=Cursor { state:lexer::init(s) }; next(s,c);
    take(s,c,1,"pub"); take(s,c,1,"let"); let function=name(s,c); take(s,c,5,":"); take(s,c,5,"(");
    var count:u32=0;
    loop {
        if count>=8 { return Program {},2; }
        take(s,c,1,"U32"); count+=1;
        if c.token.kind==5 && c.token.end>c.token.start && c.token.end<=s.len && s[c.token.start..c.token.end]=="," { take(s,c,5,","); continue; }
        break;
    }
    take(s,c,5,")"); take(s,c,5,"->"); take(s,c,1,"U32"); take(s,c,5,"!"); take(s,c,5,"{"); take(s,c,5,"}");
    take(s,c,1,"requires"); take(s,c,5,"[");
    var facts: Fact[16] = [Fact {};16]; var nf:u32=0;
    if !(c.token.kind==5 && c.token.end>c.token.start && c.token.end<=s.len && s[c.token.start..c.token.end]=="]") {
        loop {
            if nf>=16 { return Program {},2; }
            let t=c.token; var k:u32=0;
            if t.kind==1 && t.start>=0 && t.end<=s.len && s[t.start..t.end]=="Le" { k=1; take(s,c,1,"Le"); }
            else if t.kind==1 && t.start>=0 && t.end<=s.len && s[t.start..t.end]=="Lt" { k=2; take(s,c,1,"Lt"); }
            else if t.kind==1 && t.start>=0 && t.end<=s.len && s[t.start..t.end]=="Eq" { k=3; take(s,c,1,"Eq"); }
            else { return Program {},1; }
            take(s,c,5,"("); let left=selector(s,c,count); take(s,c,5,","); let right=selector(s,c,count); let close=take(s,c,5,")");
            facts[nf]=Fact { kind:k,left:left,right:right,start:t.start,end:close.end }; nf+=1;
            if c.token.kind==5 && c.token.end>c.token.start && c.token.end<=s.len && s[c.token.start..c.token.end]=="," { take(s,c,5,","); continue; }
            break;
        }
    }
    take(s,c,5,"]"); take(s,c,1,"resources"); take(s,c,5,"{"); take(s,c,1,"depth"); take(s,c,5,":"); take(s,c,2,"1");
    take(s,c,5,","); take(s,c,1,"frame"); take(s,c,5,":"); take(s,c,2,"0"); take(s,c,5,"}"); take(s,c,5,"="); take(s,c,1,"fn"); take(s,c,5,"(");
    var names: Span[8] = [Span {};8];
    for i in count { names[i]=name(s,c); if i+1<count { take(s,c,5,","); } }
    take(s,c,5,")"); take(s,c,5,"=>"); take(s,c,1,"return"); let result=name(s,c);
    if c.token.kind==6 { take(s,c,6,""); } take(s,c,0,"");
    if c.bad || count<2 || !eq(s,result,names[0]) { return Program {},1; }
    for i in count { if eq(s,function,names[i]) { return Program {},1; } for j in i { if eq(s,names[i],names[j]) { return Program {},1; } } }
    return Program { source:s,function:function,count:count,names:names,facts_count:nf,facts:facts },0;
}
