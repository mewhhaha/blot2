// Independent exact-source recognizer for the private particle lowering slice.
// Expression grouping/precedence is rebuilt by a bounded shunting-yard pass,
// not by calling the producer. Trusted Context is not source-level authority,
// general type/loan admission, a portable proof receipt, or an ABI certificate.
namespace particle_lower_verify;
import lexer;
import particle_source_core;
import particle_lower_core;

struct Reader {lex:lexer::State=lexer::State {}, t:lexer::Token=lexer::Token {}, bad:bool=false, next_node:i64=0}
struct Operator {kind:i64=0,start:i64=0,end:i64=0}
fn advance(s:u8[:],r:Reader&) {if !r.bad {r.t=lexer::next(s,r.lex);if r.t.kind==9 {r.bad=true;}}}
fn same(s:u8[:],t:lexer::Token,k:i64,v:u8[:]) -> bool {return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==v;}
fn take(s:u8[:],r:Reader&,k:i64,v:u8[:]) -> bool {if r.bad || !same(s,r.t,k,v) {r.bad=true;return false;}advance(s,r);return !r.bad;}
fn event(r:Reader&,core:particle_lower_core::Core&,x:particle_lower_core::Node) -> u32 {
    if r.bad || r.next_node<0 || r.next_node>=core.nodes.len || !particle_lower_core::same_node(core.nodes[r.next_node],x) {r.bad=true;return 0;}
    r.next_node+=1;return r.next_node as u32;
}
fn precedence(op:i64)->i64 {return if op==3 {2} else if op==4 {1} else {0};}
fn reduce(r:Reader&,core:particle_lower_core::Core&,ops:Operator[..256]&,values:u32[..256]&) -> bool {
    if r.bad || ops.len==0 || values.len<2 {r.bad=true;return false;}
    let op=ops[ops.len-1];ops.pop();if op.kind!=3 && op.kind!=4 {r.bad=true;return false;}
    let right=values[values.len-1];values.pop();let left=values[values.len-1];values.pop();
    let id=event(r,core,particle_lower_core::Node {kind:op.kind as u32,start:op.start,end:op.end,left:left,right:right});
    if id==0 {return false;}values.push(id);return true;
}
// Parse one expression, stopping before its top-level comma/closing brace.
// Every reduction emits a postorder event, so no DAG sharing or cross-row
// child can be smuggled into the candidate nodes.
fn expression(s:u8[:],r:Reader&,core:particle_lower_core::Core&,ctx:particle_source_core::Context) -> u32 {
    var ops:Operator[..256]=[];var values:u32[..256]=[];var expect_value=true;var depth:i64=0;
    while !r.bad {
        let t=r.t;
        if expect_value {
            if same(s,t,5,"(") {if depth>=32 || ops.len>=256 {r.bad=true;break;}ops.push(Operator {});depth+=1;advance(s,r);continue;}
            var id:u32=0;
            if same(s,t,1,"dt") {advance(s,r);id=event(r,core,particle_lower_core::Node {kind:2,start:t.start,end:t.end,symbol:ctx.dt,version:ctx.dt_version});}
            else if same(s,t,1,"source") {
                advance(s,r);if !take(s,r,5,"[") || !take(s,r,1,"i") || !take(s,r,5,"]") || !take(s,r,5,".") {break;}
                let f=r.t;var field:u32=0;
                if same(s,f,1,"x") {field=0;}else if same(s,f,1,"y") {field=1;}
                else if same(s,f,1,"vx") {field=2;}else if same(s,f,1,"vy") {field=3;}else {r.bad=true;break;}
                advance(s,r);id=event(r,core,particle_lower_core::Node {kind:1,start:t.start,end:f.end,field_start:f.start,field_end:f.end,field:field,
                    symbol:ctx.input,version:ctx.input_version,index:ctx.index,domain:ctx.input_domain,proof:3});
            } else {r.bad=true;break;}
            if id==0 || values.len>=256 {r.bad=true;break;}values.push(id);expect_value=false;continue;
        }
        if same(s,t,5,"+") || same(s,t,5,"*") {
            let kind=if same(s,t,5,"*") {3} else {4};
            while !r.bad && ops.len>0 && ops[ops.len-1].kind!=0 && precedence(ops[ops.len-1].kind)>=precedence(kind) {if !reduce(r,core,ops,values) {break;}}
            if r.bad || ops.len>=256 {r.bad=true;break;}ops.push(Operator {kind:kind,start:t.start,end:t.end});advance(s,r);expect_value=true;continue;
        }
        if same(s,t,5,")") {
            if depth==0 {r.bad=true;break;}
            while !r.bad && ops.len>0 && ops[ops.len-1].kind!=0 {if !reduce(r,core,ops,values) {break;}}
            if r.bad || ops.len==0 {r.bad=true;break;}ops.pop();depth-=1;advance(s,r);continue;
        }
        if depth==0 && (same(s,t,5,",") || same(s,t,5,"}")) {break;}
        r.bad=true;break;
    }
    if r.bad || expect_value || depth!=0 {r.bad=true;return 0;}
    while ops.len>0 {if !reduce(r,core,ops,values) {return 0;}}
    if values.len!=1 {r.bad=true;return 0;}return values[0];
}
fn verify(core:particle_lower_core::Core&,source:u8[:],ctx:particle_source_core::Context) -> bool {
    if source.len>65536 || core.source!=source || core.nodes.len<2 || core.nodes.len>256 ||
       !particle_source_core::context_valid(ctx) || !particle_source_core::same_context(core.context,ctx) {return false;}
    var r=Reader {lex:lexer::init(source)};advance(source,r);while !r.bad && r.t.kind==6 {advance(source,r);}
    var sites=particle_lower_core::Sites {};
    // Fixed checked interface and loop skeleton. Each token's kind and bytes
    // are checked independently; captured sites are rederived from source.
    for text in [
        "pub","let","project",":","forall","[","r",":","Region",",","s",":","Region",",","n",":","Nat",",","c",":","Nat",",","d",":","Domain","]","=>",
        "Fn","[","static",",","Many",",","(","View","[","r",",","{","x",":","F32",",","y",":","F32",",","vx",":","F32",",","vy",":","F32","}",",","n",",","d","]",",",
        "F32",",","Builder","[","s",",","{","x",":","F32",",","y",":","F32","}",",","0",",","c",",","Append","]",")",",",
        "exists","[","e",":","Domain","]","=>","View","[","s",",","{","x",":","F32",",","y",":","F32","}",",","n",",","e","]","]",
        "!","{","read","r",",","write","s","}","requires","[","Le","(","n",",","c",")","]","resources","{","depth",":","2",",","frame",":","256","}","=","fn","(","source",",","dt",",","initial",")","=>","do",":",
        "\n","\t","let","built","=","for","i","in","0","..","n","carry","(","b","=","initial",")","\n","\t",
        "invariant","[","Eq","(","Init","(","b",")",",","i",")","]","do",":","\n","\t",
        "next","(","builder",".","append","(","b",",","{","x",":"
    ] {
        if r.bad {return false;}
        if text=="\n" {if r.t.kind!=6 {return false;}advance(source,r);continue;}
        if text=="\t" {if r.t.kind!=7 {return false;}advance(source,r);continue;}
        let ch=text[0];let k=if ch>='0' && ch<='9' {2} else if (ch>='a' && ch<='z') || (ch>='A' && ch<='Z') || ch=='_' {1} else {5};
        if !same(source,r.t,k,text) {return false;}
        let site=particle_source_core::Span {start:r.t.start,end:r.t.end};
        if text=="requires" {sites.requires_site=site;}else if text=="for" {sites.for_site=site;}
        else if text=="invariant" {sites.invariant_site=site;}else if text=="next" {sites.next_site=site;}
        else if text=="append" {sites.append_site=site;}
        advance(source,r);
    }
    let x=expression(source,r,core,ctx);if r.bad || x==0 || x!=r.next_node || x!=core.x_root ||
       !take(source,r,5,",") || !take(source,r,1,"y") || !take(source,r,5,":") {return false;}
    let y=expression(source,r,core,ctx);if r.bad || y==0 || y!=r.next_node || y!=core.y_root || r.next_node!=core.nodes.len ||
       !take(source,r,5,"}") || !take(source,r,5,")") || !take(source,r,5,")") {return false;}
    if r.t.kind==6 {advance(source,r);}if r.t.kind!=8 {return false;}advance(source,r);
    if r.t.kind!=8 {return false;}advance(source,r);
    if !same(source,r.t,1,"return") {return false;}sites.return_site=particle_source_core::Span {start:r.t.start,end:r.t.end};advance(source,r);
    if !take(source,r,1,"builder") || !take(source,r,5,".") || !same(source,r.t,1,"freeze") {return false;}
    sites.freeze_site=particle_source_core::Span {start:r.t.start,end:r.t.end};advance(source,r);
    if !take(source,r,5,"(") || !take(source,r,1,"built") || !take(source,r,5,")") {return false;}
    if r.t.kind==6 {advance(source,r);}if r.t.kind!=8 {return false;}advance(source,r);
    while !r.bad && r.t.kind==6 {advance(source,r);}
    if r.bad || r.t.kind!=0 || !particle_lower_core::same_sites(core.sites,sites) {return false;}
    let proof:particle_source_core::Evidence[6]=[
        particle_source_core::Evidence {rule:1,owner:ctx.owner,left:ctx.length,right:ctx.capacity,site:sites.requires_site.start},
        particle_source_core::Evidence {rule:2,owner:ctx.owner,left:ctx.builder,right:ctx.index,version:ctx.builder_version,site:sites.invariant_site.start},
        particle_source_core::Evidence {rule:3,owner:ctx.owner,left:ctx.index,right:ctx.length,version:ctx.input_version,site:sites.for_site.start},
        particle_source_core::Evidence {rule:4,owner:ctx.owner,left:ctx.builder,right:ctx.capacity,version:ctx.builder_version,dep1:1,dep2:2,dep3:3,site:sites.append_site.start},
        particle_source_core::Evidence {rule:5,owner:ctx.owner,left:ctx.next_builder,right:ctx.index,version:ctx.next_version,dep1:2,dep2:4,site:sites.next_site.start},
        particle_source_core::Evidence {rule:6,owner:ctx.owner,left:ctx.result,right:ctx.length,version:ctx.result_version,dep1:2,dep2:5,site:sites.return_site.start}
    ];
    for i in 6 {if !particle_source_core::same_evidence(core.proofs[i],proof[i]) {return false;}}
    return true;
}
