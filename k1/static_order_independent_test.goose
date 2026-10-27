import std;
import work;
import static_order_parse;
import static_order_core;
import static_core;
import static_order_verify;
import static_order_pipeline;
import static_publish_build;
import static_publish_wasm;
fn main(){for seed in 300 {var source:u8[>..]=[];source.append("static let x = #[");for row in 1+seed%5 {if row>0 {source.push(',');}format(source,"(",(seed+row)%53,if seed%2==0 {" + 0"} else {" * 1"},",",(seed*5+row)%53,if seed%3==0 {".0 / 0.0"} else {".5"},")");}source.push(']');var base=static_publish_build::build(source);let a=static_order_pipeline::build(source,0);assert(a.status==base.status);if a.status==0 {let t=static_publish_wasm::emit(source,base.image);assert(t[..]==a.wasm[..] && work::schedule_complete(a.work));}else {assert(a.wasm.len==0 && a.work.failed);}}
 let s="static let x = #[(1+2,3.0),(1+2,3.0)]";var w=work::ScheduledWork {};assert(work::schedule_begin(w,1));var p=static_order_parse::parse(s,w);assert(p.status==0 && work::schedule_end(w,1) && work::schedule_begin(w,2));assert(static_order_verify::verify(s,p.owned,w.meter).status==0);
 for original,i in p.owned.scalars {for j in original.nodes.len {for f in 5 {var trees:static_core::Tree[>..]=[];for scalar,k in p.owned.scalars {var t=copy(scalar);if k==i {if f==0 {t.nodes[j].tag+=1;}else if f==1 {t.nodes[j].start=-1;}else if f==2 {t.nodes[j].end=9223372036854775807;}else if f==3 {t.nodes[j].a=-1;}else {t.nodes[j].ty+=1;}}trees.push(copy(t));}var bad=static_order_core::Owned {product:copy(p.owned.product),scalars:copy(trees)};assert(static_order_verify::verify(s,bad,w.meter).status!=0);}}}
 for i in p.owned.product.parts.len {let old=p.owned.product.parts[i];p.owned.product.parts[i].end=9223372036854775807;assert(static_order_verify::verify(s,p.owned,w.meter).status!=0);p.owned.product.parts[i]=old;}
 for i in s.len {var mutated:u8[>..]=[];mutated.append(s);mutated[i]^=1;assert(static_order_verify::verify(mutated,p.owned,w.meter).status!=0);}
 print("independent ordered static differential and retained-tree forgeries passed");}
