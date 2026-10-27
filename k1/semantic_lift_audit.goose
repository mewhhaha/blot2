import std;import os;import source_resolver;import project_graph;import semantic_leaf_lift;import semantic_leaf_lift_check;
fn main(){let a=args();assert(a.len==2);var root=source_resolver::open_root(a[1],"pkg");assert(root.status==0);let probes:project_graph::Probe[]=[];var g=project_graph::build(root.root,"main.blot",probes);assert(g.status==0);var l=semantic_leaf_lift::build(g.graph,"pkg","main.blot");assert(l.status==0 && l.count==1 && semantic_leaf_lift_check::verify(g.graph,l.graph,"pkg","main.blot"));
 for i in l.graph.modules.len {var bad=copy(l.graph);bad.modules[i].source_end=-1;assert(!semantic_leaf_lift_check::verify(g.graph,bad,"pkg","main.blot"));}
 for i in l.graph.edges.len {var bad=copy(l.graph);bad.edges[i].to=0;assert(!semantic_leaf_lift_check::verify(g.graph,bad,"pkg","main.blot"));}
 let path="leaf.blot";let s="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn z => do:\n  return z\n";
 let good="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n";
 assert(semantic_leaf_lift_check::proof("pkg",path,s,good));
 for bad in ["pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\n", "pub let g: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n", "pub let f: U32 -> U32 ! {} resources {depth: 2, frame: 0} = fn x => return x\n", "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 1} = fn x => return x\n", "pub let f: U32 -> U32 ! {host} resources {depth: 1, frame: 0} = fn x => return x\n"] {assert(!semantic_leaf_lift_check::proof("pkg",path,s,bad));}
 let constant="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn z => do:\n  return 7\n";assert(!semantic_leaf_lift_check::proof("pkg",path,constant,good));
 assert(source_resolver::close_root(root.root));print("independent graph lift bounds, graph forgery and source-semantic mismatch rejected");}
