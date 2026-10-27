// Private compatibility lowering for an independently source-checked scalar
// predicate. The scalar target decoder revalidates the source-bound plan.
namespace short_legacy_wasm;
import short_core;
import short_check;
import short_validate;
import common_decl_header;
import scalar_core;
import scalar_plan;
import wasm;
import wasm_scalar_validation;
import fixture_geometry;
import validate;
import catalog;
struct Result {matched:bool=false,bytes:u8[]=[]}
fn build(source:u8[:],p:short_core::Program&,fault:i64)->Result {
 if !short_check::verify(source,p) || p.head.argument!=1 || p.head.result!=2 {return Result {};}
 let t=p.tree;if t.root<1 || t.root>t.nodes.len || t.bindings.len!=1 {return Result {};}
 let root=t.nodes[t.root-1];if root.tag!=18 || root.a<1 || root.a>t.nodes.len {return Result {};}
 let ret=t.nodes[root.a-1];if ret.tag!=13 || ret.a<1 || ret.a>t.nodes.len {return Result {};}
 let op=t.nodes[ret.a-1];if op.tag!=22 || op.a<1 || op.b<1 || op.a>t.nodes.len || op.b>t.nodes.len {return Result {};}
 let a=t.nodes[op.a-1];let b=t.nodes[op.b-1];var ak:i64=0;var bk:i64=0;var av:u32=0;var bv:u32=0;
 if a.tag==1 && a.a==1 {} else if a.tag==2 {let n,ok=short_validate::lit(t.source,a);if !ok{return Result {};}ak=1;av=n as u32;}else{return Result {};}
 if b.tag==1 && b.a==1 {} else if b.tag==2 {let n,ok=short_validate::lit(t.source,b);if !ok{return Result {};}bk=1;bv=n as u32;}else{return Result {};}
 let flat=common_decl_header::project(source,p.head);let base=p.fn_start;let binding=t.bindings[0];
 if base<0 || base>flat.len || a.end<0 || b.start<a.end || b.start>t.source.len {return Result {};}
 var opstart:i64= -1;for i in a.end..b.start {if t.source[i]=='<' {opstart=i;break;}}
 if opstart<0{return Result {};}
 var c=scalar_core::build(2,2,ak,av,bk,bv);c.name_start=p.name_start;c.name_end=p.name_end;
 c.parameter_start=base+binding.start;c.parameter_end=base+binding.end;
 c.left_start=base+a.start;c.left_end=base+a.end;c.operator_start=base+opstart;c.operator_end=base+opstart+1;c.right_start=base+b.start;c.right_end=base+b.end;
 let plan=scalar_plan::make(c);if !scalar_plan::validate(plan) {return Result {};}
 if validate::scalar_v2(flat,c,catalog::edition(),catalog::semantic_policy(),catalog::optimization_policy(),catalog::wasm_abi())!=0 {return Result {};}
 // Once a source-checked legacy plan matches, failures must not select an
 // observably different encoding. Fault modes are private regression hooks.
 if fault==1 {return Result {matched:true};}
 var bytes=wasm::emit_scalar_v2(flat[c.name_start..c.name_end],plan);
 if fault==2 && bytes.len>0 {bytes[0]^=1;}
 var geometry,ok=fixture_geometry::build();
 if !ok || wasm_scalar_validation::verify(flat,plan,geometry,bytes)!=0 {return Result {matched:true};}
 return Result {matched:true,bytes:bytes};
}
fn emit(source:u8[:],p:short_core::Program&)->u8[] {let r=build(source,p,0);return copy(r.bytes);}

