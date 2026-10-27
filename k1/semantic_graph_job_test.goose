import std;import os;import source_resolver;import semantic_graph_job;
fn main(){let a=args();assert(a.len==2);var root=source_resolver::open_root(a[1],"pkg");assert(root.status==0);let abi:u8[32]=[7;32];
 for d in 6 {for used in 6 {let out=semantic_graph_job::compile(root.root,"main.blot","first",abi,used as u32,d as u32,0,0,0);let expected=used>d || d-used<3;assert((out.status==2)==expected);assert((out.status==0)==!expected);assert((out.wasm.len>0)==!expected);}}
 for f in 1..4 {let out=semantic_graph_job::compile(root.root,"main.blot","first",abi,0,128,0,0,f as u32);assert(out.status==20 && out.wasm.len==0);}
 let frame=semantic_graph_job::compile(root.root,"main.blot","first",abi,0,128,1,0,0);assert(frame.status==3 && frame.wasm.len==0);
 let invalid=semantic_graph_job::compile(root.root,"main.blot","first",abi[..31],0,128,0,0,0);assert(invalid.status==1 && invalid.wasm.len==0);
 let wrong=semantic_graph_job::compile(root.root,"main.blot","missing",abi,0,128,0,0,0);assert(wrong.status==1 && wrong.wasm.len==0);
 assert(source_resolver::close_root(root.root));let dead=semantic_graph_job::compile(root.root,"main.blot","first",abi,0,128,0,0,0);assert(dead.status!=0 && dead.wasm.len==0);
 print("graph job all-entry resource/identity/failpoint controls passed");}
