// Test-only driver: publish graph source bytes only after a complete build.
import os;
import source_resolver;
import project_graph;
fn main() {
 let a=args();if a.len!=2 {exit(2);}
 var opened=source_resolver::open_root(a[1],"pkg");if opened.status!=0 {exit(3);}
 let empty:project_graph::Probe[]=[];
 let r=project_graph::build(opened.root,"race.blot",empty);
 let closed=source_resolver::close_root(opened.root);
 if r.status!=0 || !closed {exit(1);}
 write_stdout(r.graph.sources);
}
