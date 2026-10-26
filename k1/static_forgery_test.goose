import static_parse;
import static_verify;
import static_eval;
import static_core;
struct Random {state:u32=1238127}
fn rnd(r:Random&)->u32 {r.state^=r.state<<13;r.state^=r.state>>17;r.state^=r.state<<5;return r.state;}
fn main(){
 let source="static let x: U32 = (1 + 2) * U32.wrapping_add(3,4) & 7\n";
 var original=static_parse::parse(source);assert(original.status==0 && static_verify::verify(source,original.tree));
 let values:i64[8]=[-9223372036854775807,-1,0,1,2,128,200001,9223372036854775807];
 for i in original.tree.nodes.len {for field in 6 {for v in values {
    var forged=copy(original.tree);let old=if field==0 {forged.nodes[i].tag} else if field==1 {forged.nodes[i].ty} else if field==2 {forged.nodes[i].start} else if field==3 {forged.nodes[i].end} else if field==4 {forged.nodes[i].a} else {forged.nodes[i].b};
    if old==v {continue;}
    if field==0 {forged.nodes[i].tag=v;} else if field==1 {forged.nodes[i].ty=v;} else if field==2 {forged.nodes[i].start=v;} else if field==3 {forged.nodes[i].end=v;} else if field==4 {forged.nodes[i].a=v;} else {forged.nodes[i].b=v;}
    assert(!static_verify::verify(source,forged) && static_eval::evaluate(source,forged).status==1);
 }}}
 for i in original.tree.source.len {var forged=copy(original.tree);forged.source[i]='?';assert(!static_verify::verify(source,forged));}
 var random=Random {};
 for i in 15000 {
    var bytes:u8[>..]=[];bytes.append(source);let changes=1+rnd(random)%5;
    for j in changes {let p=rnd(random)%(bytes.len as u32);bytes[p]=(rnd(random)%256) as u8;}
    var candidate=static_parse::parse(bytes);
    if candidate.status==0 {assert(static_verify::verify(bytes,candidate.tree));let out=static_eval::evaluate(bytes,candidate.tree);assert(out.status==0 || out.status==2 || out.status==3);}
    else {assert(!static_verify::verify(bytes,candidate.tree));}
 }
 print("static source and Core forgery controls passed");
}
