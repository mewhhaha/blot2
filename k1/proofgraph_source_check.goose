// Independently re-tokenize the caller's exact source and verify the candidate
// requirement order, formal components, binder names, type and resource fields.
namespace proofgraph_source_check;
import lexer;
import frontend;
import work;
import proofgraph_source;
struct Check { status:u32=0, receipt:work::Receipt=work::Receipt {} }
fn failed(r:work::Receipt)->Check { return Check { status:if r.status==1 { 3 } else if r.status==2 { 2 } else { 4 }, receipt:r }; }
fn take(s:u8[:],ts:lexer::Token[:],i:i64&,kind:i64,text:u8[:])->bool {
    if i<0 || i>=ts.len { return false; } let t=ts[i];
    if t.kind!=kind || t.start<0 || t.end<t.start || t.end>s.len || (text.len>0 && s[t.start..t.end]!=text) { return false; }
    i+=1; return true;
}
fn named(s:u8[:],ts:lexer::Token[:],i:i64&,span:proofgraph_source::Span)->bool {
    if i<0 || i>=ts.len { return false; } let t=ts[i];
    if !take(s,ts,i,1,"") || t.start!=span.start || t.end!=span.end || t.end<=t.start || frontend::reserved(s[t.start..t.end]) { return false; }
    return true;
}
fn same(s:u8[:],a:proofgraph_source::Span,b:proofgraph_source::Span)->bool {
    return a.start>=0 && a.end>a.start && a.end<=s.len && b.start>=0 && b.end>b.start && b.end<=s.len && s[a.start..a.end]==s[b.start..b.end];
}
fn selector(s:u8[:],ts:lexer::Token[:],i:i64&,count:u32,id:u32)->bool {
    if !take(s,ts,i,1,"arg") || !take(s,ts,i,5,".") || i>=ts.len { return false; }
    let t=ts[i];
    if !take(s,ts,i,2,"") || t.end!=t.start+1 || t.start<0 || t.end>s.len || s[t.start]<'0' || s[t.start]>'7' { return false; }
    let value=(s[t.start]-'0') as u32+1; return value<=count && value==id;
}
fn verify(source:u8[:],p:proofgraph_source::Program&,m:work::Meter&,phase:u32)->Check {
    if phase<4 || phase>7 { return Check {status:4}; }
    if source.len>4096 || p.source[..]!=source || p.count<2 || p.count>8 || p.facts_count>16 { return Check {status:1}; }
    var state=lexer::init(source); var ts:lexer::Token[..384]=[];
    loop {
        let r=work::charge(m,phase,1); if r.status!=0 { return failed(r); }
        let t=lexer::next(source,state); if t.kind==9 || ts.len>=384 { return Check {status:1}; }
        ts.push(t); if t.kind==0 { break; }
    }
    var i:i64=0;
    if !take(source,ts,i,1,"pub") || !take(source,ts,i,1,"let") || !named(source,ts,i,p.function) ||
       !take(source,ts,i,5,":") || !take(source,ts,i,5,"(") { return Check {status:1}; }
    for n in p.count {
        if !take(source,ts,i,1,"U32") || (n+1<p.count && !take(source,ts,i,5,",")) { return Check {status:1}; }
    }
    if !take(source,ts,i,5,")") || !take(source,ts,i,5,"->") || !take(source,ts,i,1,"U32") ||
       !take(source,ts,i,5,"!") || !take(source,ts,i,5,"{") || !take(source,ts,i,5,"}") ||
       !take(source,ts,i,1,"requires") || !take(source,ts,i,5,"[") { return Check {status:1}; }
    for n in p.facts_count {
        if i>=ts.len { return Check {status:1}; }
        let f=p.facts[n]; let first=ts[i];
        let kind=if f.kind==1 { "Le" } else if f.kind==2 { "Lt" } else if f.kind==3 { "Eq" } else { "" };
        if kind.len==0 || !take(source,ts,i,1,kind) || first.start!=f.start || !take(source,ts,i,5,"(") ||
           !selector(source,ts,i,p.count,f.left) || !take(source,ts,i,5,",") || !selector(source,ts,i,p.count,f.right) || i>=ts.len { return Check {status:1}; }
        let close=ts[i];
        if !take(source,ts,i,5,")") || close.end!=f.end || (n+1<p.facts_count && !take(source,ts,i,5,",")) { return Check {status:1}; }
    }
    if !take(source,ts,i,5,"]") || !take(source,ts,i,1,"resources") || !take(source,ts,i,5,"{") ||
       !take(source,ts,i,1,"depth") || !take(source,ts,i,5,":") || !take(source,ts,i,2,"1") ||
       !take(source,ts,i,5,",") || !take(source,ts,i,1,"frame") || !take(source,ts,i,5,":") ||
       !take(source,ts,i,2,"0") || !take(source,ts,i,5,"}") || !take(source,ts,i,5,"=") ||
       !take(source,ts,i,1,"fn") || !take(source,ts,i,5,"(") { return Check {status:1}; }
    for n in p.count {
        if !named(source,ts,i,p.names[n]) || (n+1<p.count && !take(source,ts,i,5,",")) { return Check {status:1}; }
        if same(source,p.function,p.names[n]) { return Check {status:1}; }
        for j in n { if same(source,p.names[n],p.names[j]) { return Check {status:1}; } }
    }
    if !take(source,ts,i,5,")") || !take(source,ts,i,5,"=>") || !take(source,ts,i,1,"return") || i>=ts.len { return Check {status:1}; }
    let returned=ts[i]; if !take(source,ts,i,1,"") || !same(source,p.names[0],proofgraph_source::Span { start:returned.start,end:returned.end }) { return Check {status:1}; }
    if i<ts.len && ts[i].kind==6 { i+=1; }
    if !take(source,ts,i,0,"") || i!=ts.len { return Check {status:1}; }
    for n in p.count..8 { if p.names[n].start!=0 || p.names[n].end!=0 { return Check {status:1}; } }
    for n in p.facts_count..16 {
        let f=p.facts[n]; if f.kind!=0 || f.left!=0 || f.right!=0 || f.start!=0 || f.end!=0 { return Check {status:1}; }
    }
    return Check {};
}
