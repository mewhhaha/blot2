// Producer for a fixed particle function/loop contract with bounded F32 body
// expressions; arbitrary declarations, names, calls, effects, types and loops
// remain unsupported. Shared lexer and trusted Context are not source authority.
namespace particle_lower_parse;
import lexer;
import particle_source_core;
import particle_lower_core;
struct Cursor {lex:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},status:i64=0,depth:i64=0,
    nodes:particle_lower_core::Node[..256]=[],context:particle_source_core::Context=particle_source_core::Context {}}
fn advance(s:u8[:],c:Cursor&) {if c.status!=0{return;}c.t=lexer::next(s,c.lex);if c.t.kind==9 {c.status=1;}}
fn is(s:u8[:],t:lexer::Token,kind:i64,text:u8[:])->bool {return t.kind==kind && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==text;}
fn take(s:u8[:],c:Cursor&,kind:i64,text:u8[:])->bool {if c.status!=0 || !is(s,c.t,kind,text) {if c.status==0 {c.status=1;}return false;}advance(s,c);return c.status==0;}
fn push(c:Cursor&,node:particle_lower_core::Node)->u32 {if c.status!=0{return 0;}if c.nodes.len>=256 {c.status=2;return 0;}c.nodes.push(node);return c.nodes.len as u32;}
fn atom(s:u8[:],c:Cursor&)->u32 {
    let t=c.t;if c.status!=0{return 0;}
    if is(s,t,1,"dt") {advance(s,c);return push(c,particle_lower_core::Node {kind:2,start:t.start,end:t.end,symbol:c.context.dt,version:c.context.dt_version});}
    if is(s,t,1,"source") {
        advance(s,c);if !take(s,c,5,"[") || !take(s,c,1,"i") || !take(s,c,5,"]") || !take(s,c,5,".") {return 0;}
        let f=c.t; var offset:u32=0;
        if is(s,f,1,"x") {offset=0;} else if is(s,f,1,"y") {offset=1;} else if is(s,f,1,"vx") {offset=2;} else if is(s,f,1,"vy") {offset=3;} else {c.status=1;return 0;}
        advance(s,c);return push(c,particle_lower_core::Node {kind:1,start:t.start,end:f.end,field_start:f.start,field_end:f.end,field:offset,
            symbol:c.context.input,version:c.context.input_version,index:c.context.index,domain:c.context.input_domain,proof:3});
    }
    if is(s,t,5,"(") {
        if c.depth>=32 {c.status=2;return 0;}c.depth+=1;advance(s,c);let e=expr(s,c);
        if c.status!=0 {c.depth-=1;return 0;}
        if !take(s,c,5,")") {c.depth-=1;return 0;}c.depth-=1;return e;
    }
    c.status=1;return 0;
}
fn product(s:u8[:],c:Cursor&)->u32 {
    var left=atom(s,c);
    while c.status==0 && is(s,c.t,5,"*") {let op=c.t;advance(s,c);let right=atom(s,c);if right==0{return 0;}
        left=push(c,particle_lower_core::Node {kind:3,start:op.start,end:op.end,left:left,right:right});}
    return left;
}
recursive fn expr(s:u8[:],c:Cursor&)->u32 {
    var left=product(s,c);
    while c.status==0 && is(s,c.t,5,"+") {let op=c.t;advance(s,c);let right=product(s,c);if right==0{return 0;}
        left=push(c,particle_lower_core::Node {kind:4,start:op.start,end:op.end,left:left,right:right});}
    return left;
}
fn parse(source:u8[:],context:particle_source_core::Context)->particle_lower_core::Core,i64 {
    if source.len>65536{return particle_lower_core::Core {},2;}
    if !particle_source_core::context_valid(context){return particle_lower_core::Core {},1;}
    var c=Cursor {lex:lexer::init(source),context:context};advance(source,c);while c.status==0 && c.t.kind==6 {advance(source,c);}
    var sites=particle_lower_core::Sites {};
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
        if c.status!=0 {return particle_lower_core::Core {},c.status;}
        if text=="\n" {if c.t.kind!=6{return particle_lower_core::Core {},1;}advance(source,c);continue;}
        if text=="\t" {if c.t.kind!=7{return particle_lower_core::Core {},1;}advance(source,c);continue;}
        let ch=text[0];let kind=if ch>='0' && ch<='9' {2} else if (ch>='a' && ch<='z')||(ch>='A' && ch<='Z')||ch=='_' {1} else {5};
        if !is(source,c.t,kind,text){return particle_lower_core::Core {},1;}
        let span=particle_source_core::Span {start:c.t.start,end:c.t.end};
        if text=="requires" {sites.requires_site=span;} else if text=="for" {sites.for_site=span;}
        else if text=="invariant" {sites.invariant_site=span;} else if text=="next" {sites.next_site=span;}
        else if text=="append" {sites.append_site=span;}
        advance(source,c);
    }
    let x=expr(source,c); if x==0 || !take(source,c,5,",") || !take(source,c,1,"y") || !take(source,c,5,":") {return particle_lower_core::Core {},if c.status==2 {2} else {1};}
    let y=expr(source,c); if y==0 || !take(source,c,5,"}") || !take(source,c,5,")") || !take(source,c,5,")") {return particle_lower_core::Core {},if c.status==2 {2} else {1};}
    if c.t.kind==6 {advance(source,c);}if c.t.kind!=8{return particle_lower_core::Core {},1;}advance(source,c);
    if c.t.kind!=8{return particle_lower_core::Core {},1;}advance(source,c);
    if !is(source,c.t,1,"return") {return particle_lower_core::Core {},1;}
    sites.return_site=particle_source_core::Span {start:c.t.start,end:c.t.end};advance(source,c);
    if !take(source,c,1,"builder") || !take(source,c,5,".") || !is(source,c.t,1,"freeze") {return particle_lower_core::Core {},1;}
    sites.freeze_site=particle_source_core::Span {start:c.t.start,end:c.t.end};advance(source,c);
    if !take(source,c,5,"(") || !take(source,c,1,"built") || !take(source,c,5,")") {return particle_lower_core::Core {},1;}
    if c.t.kind==6 {advance(source,c);}if c.t.kind!=8{return particle_lower_core::Core {},1;}advance(source,c);
    while c.status==0 && c.t.kind==6 {advance(source,c);}if c.status!=0 || c.t.kind!=0{return particle_lower_core::Core {},1;}
    return particle_lower_core::Core {source:source,context:context,sites:sites,proofs:particle_source_core::proofs(context,particle_lower_core::proof_sites(sites)),nodes:copy(c.nodes),x_root:x,y_root:y},0;
}
