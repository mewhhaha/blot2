// Independent source-bound consumer of the private canonical builder plan.
// It validates static syntax and linear use only; it does not authenticate a
// runtime loan, initialized backing, builder version, ABI, work receipt or code.
namespace i08_affine_verify;
import i08_core;
import i08_bound_shape;
import i08_affine_core;
fn node(t:i08_core::Tree&,id:i64,tag:i64)->bool {return id>=1 && id<=t.nodes.len && t.nodes[id-1].tag==tag;}
fn name(t:i08_core::Tree&,id:i64,binding:i64)->bool {return node(t,id,1) && t.nodes[id-1].a==binding;}
recursive fn float_term(t:i08_core::Tree&,id:i64,index:i64,depth:i64)->bool {
 if depth>=128 || id<1 || id>t.nodes.len{return false;}let x=t.nodes[id-1];
 if x.tag==29 {return true;}if x.tag==1 {return x.a==7;}
 if x.tag==20 {return float_term(t,x.a,index,depth+1);}
 if x.tag==21 || x.tag==25 {return float_term(t,x.a,index,depth+1) && float_term(t,x.b,index,depth+1);}
 if x.tag!=23 || x.b<1 || x.b>4 || !node(t,x.a,24) {return false;}let read=t.nodes[x.a-1];return name(t,read.a,6) && name(t,read.b,index);
}
fn verify(t:i08_core::Tree&,source:u8[:],p:i08_affine_core::Plan)->bool {
 if !i08_bound_shape::verify(t,source) || t.bindings.len!=11 || p.initial!=8 || p.view!=6 || p.nat!=3 || p.capacity!=4 ||
    p.root!=t.root || !node(t,p.root,18) || !node(t,p.loop_id,15) || !node(t,p.carry_node,6) || !node(t,p.invariant_id,8) ||
    !node(t,p.next_node,9) || !node(t,p.append,27) || !node(t,p.row,26) || !node(t,p.freeze,28) || !node(t,p.return_node,13) {return false;}
 let fn_node=t.nodes[p.root-1];if fn_node.b!=3 || !node(t,fn_node.a,17) {return false;}let seq=t.nodes[fn_node.a-1];
 if !node(t,seq.a,16) || seq.b!=p.return_node {return false;}let binding=t.nodes[seq.a-1];
 if binding.a!=p.loop_id || binding.b!=p.result || p.result<1 || p.result>t.bindings.len || t.bindings[p.result-1].kind!=4 {return false;}
 let ret=t.nodes[p.return_node-1];let freeze=t.nodes[p.freeze-1];
 if ret.target!=fn_node.target || ret.a!=p.freeze || !name(t,freeze.a,p.result) {return false;}
 let cycle=t.nodes[p.loop_id-1];
 if cycle.g!=1 || cycle.f!=p.index || cycle.c!=p.carry_node || cycle.d!=p.invariant_id || cycle.e!=p.next_node ||
    p.index<1 || p.index>t.bindings.len || t.bindings[p.index-1].kind!=2 || !name(t,cycle.b,p.nat) || !node(t,cycle.a,2) {return false;}
 let zero=t.nodes[cycle.a-1];if zero.start<0 || zero.end<=zero.start || zero.end>source.len || source[zero.start..zero.end]!="0" {return false;}
 let carry=t.nodes[p.carry_node-1];if carry.b!=p.carry_id || p.carry_id<1 || p.carry_id>t.bindings.len ||
    t.bindings[p.carry_id-1].kind!=3 || !name(t,carry.a,p.initial) {return false;}
 let inv=t.nodes[p.invariant_id-1];if inv.c!=1 || !name(t,inv.b,p.index) || !node(t,inv.a,7) {return false;}
 let obs=t.nodes[inv.a-1];if obs.b!=1 || !name(t,obs.a,p.carry_id) {return false;}
 let next=t.nodes[p.next_node-1];if next.target!=cycle.target || next.b!=1 || next.a!=p.append {return false;}
 let append=t.nodes[p.append-1];if !name(t,append.a,p.carry_id) || append.b!=p.row {return false;}
 let row=t.nodes[p.row-1];if !float_term(t,row.a,p.index,0) || !float_term(t,row.b,p.index,0) {return false;}
 var initial_reads:i64=0;var carry_reads:i64=0;var result_reads:i64=0;
 for x in t.nodes {if x.tag==1 {if x.a==p.initial {initial_reads+=1;}if x.a==p.carry_id {carry_reads+=1;}if x.a==p.result {result_reads+=1;}}}
 return initial_reads==1 && carry_reads==2 && result_reads==1;
}
