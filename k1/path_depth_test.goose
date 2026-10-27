import std;
import os;
import short_frontend;
import short_check;
import short_emit;
import short_fact_build;
import short_fact_verify;
fn main(){for n in 118..129 {var s:u8[>..]=[];s.append("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return ");for _ in n {s.append("#True && ");}s.append("x < 5\n");var p=short_frontend::parse(s);if n<128 {assert(p.status==0 && short_check::verify(s,p.program));let b=short_emit::emit(s,p.program);assert(b.len>0 && write_file(str("path-depth-",n,".wasm"),b));}else {assert(p.status!=0);}}
 let source="pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return (#True && x < 5)\n";var p=short_frontend::parse(source);assert(p.status==0);var found=false;for n,i in p.program.tree.nodes {if n.tag==20 {p.program.tree.nodes[i].a=i+1;found=true;break;}}assert(found);let bad=short_fact_build::build(p.program.tree);assert(bad.status!=0);let none: mixed_fact_core::Evidence[0]=[];assert(!short_fact_verify::verify(p.program.tree,p.program.tree.source,none,1,2));var q=short_frontend::parse(source);assert(q.status==0);found=false;for n,i in q.program.tree.nodes {if n.tag==23 {q.program.tree.nodes[i].a=i+1;found=true;break;}}assert(found);let bad_logic=short_fact_build::build(q.program.tree);assert(bad_logic.status!=0);assert(!short_fact_verify::verify(q.program.tree,q.program.tree.source,none,1,2));print("short-circuit depth compatibility and cyclic-tree bounds passed");}
import mixed_fact_core;
