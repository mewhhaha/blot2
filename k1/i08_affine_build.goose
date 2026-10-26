// A narrow source-local builder-use/completion plan for the canonical I08
// loop. This is not a general affine checker or runtime/loan admission.
namespace i08_affine_build;
import i08_core;
import i08_bound_shape;
import i08_affine_core;
fn valid(t:i08_core::Tree&,id:i64,tag:i64)->bool {return id>0 && id<=t.nodes.len && t.nodes[id-1].tag==tag;}
fn ref(t:i08_core::Tree&,id:i64,b:i64)->bool{return valid(t,id,1) && t.nodes[id-1].a==b;}
recursive fn row_value(t:i08_core::Tree&,id:i64,index:i64,depth:i64)->bool {
 if depth>=128 || id<1 || id>t.nodes.len{return false;}let n=t.nodes[id-1];
 if n.tag==1 {return n.a==7;}if n.tag==29 {return true;}
 if n.tag==20 {return row_value(t,n.a,index,depth+1);}
 if n.tag==21 || n.tag==25 {return row_value(t,n.a,index,depth+1) && row_value(t,n.b,index,depth+1);}
 if n.tag==23 && n.b>=1 && n.b<=4 && valid(t,n.a,24) {
  let read=t.nodes[n.a-1];return ref(t,read.a,6) && ref(t,read.b,index);
 }
 return false;
}
fn build(t:i08_core::Tree&,expected:u8[:])->i08_affine_core::Result {
 if !i08_bound_shape::verify(t,expected) || t.bindings.len!=11 || !valid(t,t.root,18) {return i08_affine_core::Result {status:1};}
 let root=t.nodes[t.root-1];if root.b!=3 || !valid(t,root.a,17) {return i08_affine_core::Result {status:1};}let pair=t.nodes[root.a-1];
 if !valid(t,pair.a,16) || !valid(t,pair.b,13) {return i08_affine_core::Result {status:1};}
 let binding=t.nodes[pair.a-1];let ret=t.nodes[pair.b-1];
 if ret.target!=root.target || !valid(t,binding.a,15) || !valid(t,ret.a,28) {return i08_affine_core::Result {status:1};}
 let loop_node=t.nodes[binding.a-1];let freeze=t.nodes[ret.a-1];
 if binding.b<1 || binding.b>t.bindings.len || t.bindings[binding.b-1].kind!=4 || !ref(t,freeze.a,binding.b) ||
    loop_node.g!=1 || !valid(t,loop_node.c,6) || !valid(t,loop_node.d,8) || !valid(t,loop_node.e,9) {return i08_affine_core::Result {status:1};}
 let carry=t.nodes[loop_node.c-1];let inv=t.nodes[loop_node.d-1];let next=t.nodes[loop_node.e-1];
 if carry.b<1 || carry.b>t.bindings.len || t.bindings[carry.b-1].kind!=3 || !ref(t,carry.a,8) ||
    loop_node.f<1 || loop_node.f>t.bindings.len || t.bindings[loop_node.f-1].kind!=2 || !ref(t,loop_node.b,3) ||
    !valid(t,loop_node.a,2) || t.source[t.nodes[loop_node.a-1].start..t.nodes[loop_node.a-1].end]!="0" ||
    inv.c!=1 || !valid(t,inv.a,7) || !ref(t,inv.b,loop_node.f) || next.b!=1 || next.target!=loop_node.target || !valid(t,next.a,27) {return i08_affine_core::Result {status:1};}
 let obs=t.nodes[inv.a-1];let append=t.nodes[next.a-1];
 if obs.b!=1 || !ref(t,obs.a,carry.b) || !ref(t,append.a,carry.b) || !valid(t,append.b,26) {return i08_affine_core::Result {status:1};}
 let row=t.nodes[append.b-1];if !row_value(t,row.a,loop_node.f,0) || !row_value(t,row.b,loop_node.f,0) {return i08_affine_core::Result {status:1};}
 var initials:i64=0;var carries:i64=0;var results:i64=0;
 for n in t.nodes {if n.tag==1 {if n.a==8 {initials+=1;}if n.a==carry.b {carries+=1;}if n.a==binding.b {results+=1;}}}
 if initials!=1 || carries!=2 || results!=1 {return i08_affine_core::Result {status:1};}
 return i08_affine_core::Result {plan:i08_affine_core::Plan {initial:8,view:6,nat:3,capacity:4,loop_id:binding.a,index:loop_node.f,carry_id:carry.b,result:binding.b,carry_node:loop_node.c,invariant_id:loop_node.d,next_node:loop_node.e,append:next.a,row:append.b,freeze:ret.a,return_node:pair.b,root:t.root}};
}
