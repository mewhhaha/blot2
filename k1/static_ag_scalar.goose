// Instrument the actual private scalar evaluation node and child traversal.
// Runtime float primitives and allocator/copy internals remain outside this
// partial semantic accounting.
namespace static_ag_scalar;
import work;
import static_budget;
import static_core;
import static_float;
import static_eval;
struct Result {status:i64=1,bits:u32=0}
fn charge(m:work::Meter&,event:u32)->i64 {let x=work::charge(m,3,event);return if x.status==0 {0} else if x.status==1 {4} else {5};}
fn evaluate(tree:static_core::Tree&,m:work::Meter&,budget:static_budget::Budget&)->Result {
 var values:static_eval::Value[>..]=[];
 for i in tree.nodes.len {
  let node_status=charge(m,2);if node_status!=0{return Result {status:node_status};}let n=tree.nodes[i];
  if !static_budget::step(budget){return Result {status:2};}
  var v=static_eval::Value {depth:1};
  if n.tag==1 {v.bits=n.literal;}else if n.tag==2 {v.bits=static_float::literal(n.literal,n.half);}
  else if n.tag==3 || n.tag==4 {
   if n.a<1 || n.a>i{return Result {};}
   let edge=charge(m,3);if edge!=0{return Result {status:edge};}let a=values[n.a-1];v.depth=a.depth+1;
   if !static_budget::enter(v.depth){return Result {status:2};}v.bits=if n.tag==3 {a.bits} else {a.bits^0x80000000};
  }else {
   if n.a<1 || n.a>i || n.b<1 || n.b>i{return Result {};}
   let edge_a=charge(m,3);if edge_a!=0{return Result {status:edge_a};}let a=values[n.a-1];
   let edge_b=charge(m,3);if edge_b!=0{return Result {status:edge_b};}let b=values[n.b-1];
   v.depth=(if a.depth>b.depth {a.depth} else {b.depth})+1;if !static_budget::enter(v.depth){return Result {status:2};}
   let ty=charge(m,6);if ty!=0{return Result {status:ty};}
   if n.ty==2 {v.bits=static_float::arithmetic(n.tag,a.bits,b.bits);}
   else if n.tag==5 {if (a.bits as u64)+(b.bits as u64)>4294967295{return Result {status:3};}v.bits=a.bits+b.bits;}
   else if n.tag==6 {if a.bits<b.bits{return Result {status:3};}v.bits=a.bits-b.bits;}
   else if n.tag==7 {if (a.bits as u64)*(b.bits as u64)>4294967295{return Result {status:3};}v.bits=(a.bits as u64*b.bits as u64) as u32;}
   else if n.tag==9 {v.bits=a.bits&b.bits;}
   else if n.tag==10 {v.bits=((a.bits as u64+b.bits as u64)&4294967295) as u32;}
   else if n.tag==11 {v.bits=((a.bits as u64+4294967296-b.bits as u64)&4294967295) as u32;}
   else if n.tag==12 {v.bits=((a.bits as u64*b.bits as u64)&4294967295) as u32;}
   else {return Result {};}
  }
  if !static_budget::enter(v.depth){return Result {status:2};}values.push(v);
 }
 if tree.root<1 || tree.root>values.len{return Result {};}
 let edge=charge(m,3);if edge!=0{return Result {status:edge};}return Result {status:0,bits:values[tree.root-1].bits};
}
