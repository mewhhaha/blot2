// Independently decode the private joined scalar, finite-loop and mixed targets.
// Source/Core is checked first; no emitter calls or general M13 authority.
namespace short_target;
import short_core;
import short_check;
import common_decl_header;
import unified_core;
import iteration_core;
import compiler_core;
import wasm_scalar_validation;
struct State {r:wasm_scalar_validation::Reader=wasm_scalar_validation::Reader {},steps:i64=0}
fn op(b:u8[:],s:State&,v:i64)->bool{return wasm_scalar_validation::byte(b,s.r)==v;}
struct Expected {kind:i64=0,value:i64=0}
// Explicit traversal avoids imposing a new recursion bound on left-associative
// source expressions. Actions describe expected instructions, not output.
fn expression(b:u8[:],s:State&,p:unified_core::Program&,id:i64,depth:i64)->bool {
 if depth>128 {return false;}var pending:Expected[>..]=[Expected {kind:1,value:id}];
 while pending.len>0 {
  if pending.len>32768 || s.steps>=32768 {return false;}let a=pending[pending.len-1];pending.pop();s.steps+=1;
  if a.kind==2 {if !op(b,s,a.value){return false;}continue;}
  if a.kind==3 {if !op(b,s,0x41) || wasm_scalar_validation::i32_leb_bits(b,s.r)!=a.value {return false;}continue;}
  if a.kind!=1 || a.value<1 || a.value>p.nodes.len {return false;}let n=p.nodes[a.value-1];
  if n.tag==1 {if !op(b,s,0x20) || wasm_scalar_validation::u32_leb(b,s.r)!=n.a+1 {return false;}}
  else if n.tag==2 {if !op(b,s,0x41) || wasm_scalar_validation::i32_leb_bits(b,s.r)!=n.literal {return false;}}
  else if n.tag==10 || n.tag==11 {if !op(b,s,0x41) || wasm_scalar_validation::i32_leb_bits(b,s.r)!=(if n.tag==10 {1} else {0}) {return false;}}
  else if n.tag==8 {pending.push(Expected {kind:1,value:n.a});}
  else if n.tag==3 || n.tag==4 || n.tag==5 || n.tag==6 || n.tag==7 || n.tag==9 || n.tag==18 {
   let code=if n.tag==3 || n.tag==4 {0x6a} else if n.tag==5 {0x6b} else if n.tag==6 {0x6c} else if n.tag==7 {0x71} else if n.tag==9 {0x49} else {0x4d};
   pending.push(Expected {kind:2,value:code});pending.push(Expected {kind:1,value:n.b});pending.push(Expected {kind:1,value:n.a});
  } else if n.tag==12 || n.tag==13 {
   pending.push(Expected {kind:2,value:0x0b});
   if n.tag==12 {pending.push(Expected {kind:3,value:0});pending.push(Expected {kind:2,value:0x05});pending.push(Expected {kind:1,value:n.b});}
   else {pending.push(Expected {kind:1,value:n.b});pending.push(Expected {kind:2,value:0x05});pending.push(Expected {kind:3,value:1});}
   pending.push(Expected {kind:2,value:0x7f});pending.push(Expected {kind:2,value:0x04});pending.push(Expected {kind:1,value:n.a});
  } else {return false;}
 }
 return true;
}
recursive fn statement(b:u8[:],s:State&,p:unified_core::Program&,id:i64,depth:i64)->bool {
 if depth>128 || id<1 || id>p.nodes.len || s.steps>=32768 {return false;}s.steps+=1;let n=p.nodes[id-1];
 if n.tag==17 {var pending:i64[2048]=[0;2048];pending[0]=id;var count:i64=1;while count>0 {count-=1;let q=pending[count];if q<1 || q>p.nodes.len {return false;}let x=p.nodes[q-1];if x.tag==17 {if count+2>2048{return false;}pending[count]=x.b;pending[count+1]=x.a;count+=2;}else if !statement(b,s,p,q,depth+1){return false;}}return true;}
 if n.tag==14 {return expression(b,s,p,n.a,depth+1) && op(b,s,0x21) && wasm_scalar_validation::u32_leb(b,s.r)==n.b+1;}
 if n.tag==15 {return expression(b,s,p,n.a,depth+1) && op(b,s,0x0f);}
 if n.tag==16 {if !expression(b,s,p,n.a,depth+1) || !op(b,s,0x04) || !op(b,s,0x40) || !statement(b,s,p,n.b,depth+1) {return false;}
  if n.c!=0 && (!op(b,s,0x05) || !statement(b,s,p,n.c,depth+1)) {return false;}return op(b,s,0x0b);}
 return false;
}
// Independently decode the finite-loop variant's typed control tree. The
// context tracks Wasm nesting and the current lexical transfer target.
struct LoopContext {target:i64=0,index:i64=0,carry:i64=0,depth:i64=0,loop_depth:i64=0,exit_depth:i64=0}
fn local(b:u8[:],s:State&,opcode:i64,index:i64)->bool {return op(b,s,opcode) && wasm_scalar_validation::u32_leb(b,s.r)==index;}
recursive fn loop_value_depth(b:u8[:],s:State&,p:compiler_core::Program&,id:i64,level:i64)->bool {
 if level>=128 || id<1 || id>p.body.nodes.len {return false;}let n=p.body.nodes[id-1];
 if n.tag==1 {return local(b,s,0x20,n.a);}if n.tag==3 || n.tag==4 {return op(b,s,0x41) && wasm_scalar_validation::i32_leb_bits(b,s.r)==(if n.tag==3 {1} else {0});}
 if n.tag==20 {return loop_value_depth(b,s,p,n.a,level+1);}
 if n.tag==23 || n.tag==24 {
  if !loop_value_depth(b,s,p,n.a,level+1) || !op(b,s,0x04) || !op(b,s,0x7f) {return false;}
  if n.tag==23 {if !loop_value_depth(b,s,p,n.b,level+1) {return false;}} else {if !op(b,s,0x41) || wasm_scalar_validation::i32_leb_bits(b,s.r)!=1 {return false;}}
  if !op(b,s,0x05) {return false;}if n.tag==23 {if !op(b,s,0x41) || wasm_scalar_validation::i32_leb_bits(b,s.r)!=0 {return false;}} else {if !loop_value_depth(b,s,p,n.b,level+1) {return false;}}return op(b,s,0x0b);
 }
 if n.tag==19 || n.tag==21 || n.tag==22 || n.tag==25 || n.tag==26 || n.tag==27 || n.tag==28 {return loop_value_depth(b,s,p,n.a,level+1) && loop_value_depth(b,s,p,n.b,level+1) && op(b,s,if n.tag==22 {0x49} else if n.tag==28 {0x4d} else if n.tag==25 {0x6b} else if n.tag==26 {0x6c} else if n.tag==27 {0x71} else {0x6a});}
 if n.tag!=2 || n.start<0 || n.end<=n.start || n.end>p.body.source.len {return false;}var value:u64=0;
 for ch in p.body.source[n.start..n.end] {if ch<'0' || ch>'9' {return false;}let d=(ch-'0') as u64;if value>(4294967295-d)/10 {return false;}value=value*10+d;}
 return op(b,s,0x41) && wasm_scalar_validation::i32_leb_bits(b,s.r)==(value as i64);
}
fn loop_value(b:u8[:],s:State&,p:compiler_core::Program&,id:i64)->bool {return loop_value_depth(b,s,p,id,0);}
recursive fn loop_statement(b:u8[:],s:State&,p:compiler_core::Program&,id:i64,ctx:LoopContext,level:i64,limits:i64[:])->bool {
 if level>128 || id<1 || id>p.body.nodes.len || s.steps>=32768 {return false;}s.steps+=1;let n=p.body.nodes[id-1];
 if n.tag==17 {var pending:i64[2048]=[0;2048];pending[0]=id;var count:i64=1;while count>0 {count-=1;let q=pending[count];if q<1 || q>p.body.nodes.len {return false;}let x=p.body.nodes[q-1];if x.tag==17 {if count+2>2048{return false;}pending[count]=x.b;pending[count+1]=x.a;count+=2;}else if !loop_statement(b,s,p,q,ctx,level+1,limits){return false;}}return true;}
 if n.tag==16 {if n.a<1 || n.a>p.body.nodes.len{return false;}let loop_node=p.body.nodes[n.a-1];if loop_node.tag!=15 {return loop_value(b,s,p,n.a) && local(b,s,0x21,n.b);}if loop_node.g!=1 || loop_node.c<1 || loop_node.c>p.body.nodes.len{return false;}
  let carry=p.body.nodes[loop_node.c-1];return loop_statement(b,s,p,n.a,ctx,level+1,limits) && local(b,s,0x20,carry.b) && local(b,s,0x21,n.b);}
 if n.tag==15 {if id>limits.len || !loop_value(b,s,p,n.a) || !local(b,s,0x21,n.f) || !loop_value(b,s,p,n.b) || !local(b,s,0x21,limits[id-1]) {return false;}
  var carry:i64=0;if n.g==1 {if n.c<1 || n.c>p.body.nodes.len {return false;}let c=p.body.nodes[n.c-1];carry=c.b;if !loop_value(b,s,p,c.a) || !local(b,s,0x21,carry) {return false;}}
  if !op(b,s,0x02) || !op(b,s,0x40) || !op(b,s,0x03) || !op(b,s,0x40) {return false;}
  let inner=LoopContext {target:n.target,index:n.f,carry:carry,depth:ctx.depth+2,loop_depth:ctx.depth+2,exit_depth:ctx.depth+1};
  if !local(b,s,0x20,n.f) || !local(b,s,0x20,limits[id-1]) || !op(b,s,0x4f) || !op(b,s,0x0d) || wasm_scalar_validation::u32_leb(b,s.r)!=1 || !loop_statement(b,s,p,n.e,inner,level+1,limits) {return false;}
  return op(b,s,0) && op(b,s,0x0b) && op(b,s,0x0b);
 }
 if n.tag==14 {if !loop_value(b,s,p,n.a) || !op(b,s,0x04) || !op(b,s,0x40) {return false;}var inner=ctx;inner.depth+=1;
  if !loop_statement(b,s,p,n.b,inner,level+1,limits) {return false;}if n.c!=0 && (!op(b,s,0x05) || !loop_statement(b,s,p,n.c,inner,level+1,limits)) {return false;}return op(b,s,0x0b);}
 if n.tag==13 {return loop_value(b,s,p,n.a) && op(b,s,0x0f);}
 if n.tag>=9 && n.tag<=12 {if ctx.target==0 || n.target!=ctx.target {return false;}
  if n.tag==9 || n.tag==10 {if ctx.carry==0 || n.b!=1 || !loop_value(b,s,p,n.a) || !local(b,s,0x21,ctx.carry) {return false;}}
  if n.tag==9 || n.tag==11 {return local(b,s,0x20,ctx.index) && op(b,s,0x41) && wasm_scalar_validation::i32_leb_bits(b,s.r)==1 && op(b,s,0x6a) && local(b,s,0x21,ctx.index) && op(b,s,0x0c) && wasm_scalar_validation::u32_leb(b,s.r)==ctx.depth-ctx.loop_depth;}
  return op(b,s,0x0c) && wasm_scalar_validation::u32_leb(b,s.r)==ctx.depth-ctx.exit_depth;
 }
 return false;
}
fn loop_tree(p:short_core::Program&)->compiler_core::Program {
 let tree=p.tree;var nodes:iteration_core::Node[>..]=[];var bindings:iteration_core::Binding[>..]=[];
 for n in tree.nodes {nodes.push(iteration_core::Node {tag:n.tag,start:n.start,end:n.end,a:n.a,b:n.b,c:n.c,d:n.d,e:n.e,f:n.f,g:n.g,target:n.target});}
 for v in tree.bindings {bindings.push(iteration_core::Binding {start:v.start,end:v.end,kind:v.kind,scope:v.scope});}
 return compiler_core::Program {body:iteration_core::Tree {source:copy(tree.source),bindings:copy(bindings),nodes:copy(nodes),root:tree.root}};
}

fn verify(source:u8[:],p:short_core::Program&,bytes:u8[:])->bool {
 if !short_check::verify(source,p) || bytes.len<8 || bytes.len>source.len+65536 || bytes[..8]!=[0 as u8,97,115,109,1,0,0,0] {return false;}
 let flat=common_decl_header::project(source,p.head);if p.name_start<0 || p.name_end<=p.name_start || p.name_end>flat.len{return false;}let name=flat[p.name_start..p.name_end];var root=wasm_scalar_validation::Reader {at:8,end:bytes.len};
 let ty=wasm_scalar_validation::section(bytes,root,1);if !wasm_scalar_validation::equal_payload(bytes,ty,[1,0x60,2,0x7f,0x7f,1,0x7f]) {return false;}
 let f=wasm_scalar_validation::section(bytes,root,3);if !wasm_scalar_validation::equal_payload(bytes,f,[1,0]) {return false;}
 var mem=wasm_scalar_validation::section(bytes,root,5);if wasm_scalar_validation::byte(bytes,mem)!=1 || wasm_scalar_validation::byte(bytes,mem)!=1 || wasm_scalar_validation::u32_leb(bytes,mem)!=275 || wasm_scalar_validation::u32_leb(bytes,mem)!=275 || !wasm_scalar_validation::done(mem) {return false;}
 var ex=wasm_scalar_validation::section(bytes,root,7);if wasm_scalar_validation::u32_leb(bytes,ex)!=1 {return false;}let n=wasm_scalar_validation::u32_leb(bytes,ex);
 if n<0 || n>ex.end-ex.at {return false;}let a=ex.at;ex.at+=n;if bytes[a..ex.at]!=name || wasm_scalar_validation::byte(bytes,ex)!=0 || wasm_scalar_validation::u32_leb(bytes,ex)!=0 || !wasm_scalar_validation::done(ex) {return false;}
 var code=wasm_scalar_validation::section(bytes,root,10);if wasm_scalar_validation::u32_leb(bytes,code)!=1 {return false;}let size=wasm_scalar_validation::u32_leb(bytes,code);if size<0 || size>code.end-code.at {return false;}
 var s=State {r:wasm_scalar_validation::Reader {at:code.at,end:code.at+size}};code.at+=size;if !wasm_scalar_validation::done(code) {return false;}
 var loop_program=loop_tree(p);
 var limits:i64[2048]=[0;2048];var loops:i64=0;for node,i in loop_program.body.nodes {if node.tag==15 {loops+=1;if loops>128 || i>=limits.len {return false;}limits[i]=loop_program.body.bindings.len+loops;}}
 let locals=loop_program.body.bindings.len-1+loops;if locals<0 || locals>255{return false;}
 if locals==0 {if !op(bytes,s,0){return false;}}else {if !op(bytes,s,1) || wasm_scalar_validation::u32_leb(bytes,s.r)!=locals || !op(bytes,s,0x7f){return false;}}
 let root_id=loop_program.body.root;if root_id<1 || root_id>loop_program.body.nodes.len || loop_program.body.nodes[root_id-1].tag!=18 {return false;}
 if !loop_statement(bytes,s,loop_program,loop_program.body.nodes[root_id-1].a,LoopContext {},0,limits){return false;}
 if !op(bytes,s,0) || !op(bytes,s,0x0b) || !wasm_scalar_validation::done(s.r) {return false;}
 var custom=wasm_scalar_validation::section(bytes,root,0);let key=wasm_scalar_validation::u32_leb(bytes,custom);if key<0 || key>custom.end-custom.at || bytes[custom.at..custom.at+key]!="blot.k1.fixture.memory" {return false;}custom.at+=key;
 let metadata="{\"version\":1,\"page_bytes\":65536,\"pages\":275,\"granule_bytes\":4096,\"static_bytes\":0,\"dictionary_bytes\":0,\"control\":[0,16],\"owners\":[16,8192],\"owner_slots\":256,\"owner_stride\":32,\"bitmap\":[8208,512],\"frame\":[8720,1048576],\"ingress\":[1057296,65536],\"egress\":[1122832,65536],\"alignment_padding\":[1188368,3568],\"pool\":[1191936,16777216],\"page_padding\":[17969152,53248],\"memory_bytes\":18022400}";
 return custom.ok && bytes[custom.at..custom.end]==metadata && wasm_scalar_validation::done(root);
}
