namespace blot_eval_scope_components;
import dictionary;
import support.error;
import support.native;
let none: u32=0xffffffff;
struct Node { out: u32=0xffffffff, in: u32=0xffffffff, component: u32, forward: u32=0, backward: u32=0, recursive: bool=false }
struct Edge { from: u32,to: u32,next_out: u32,next_in: u32 }
struct Graph { owner_id: u64=blot_native::fresh_owner_id(),nodes: Node[>..<]&,edges: Edge[>..<]&,keys: dictionary<u64,bool>&,work: u32[>..<]&,generation: u32=0,merges: i64=0 }
fn init(nodes: Node[>..<]&,edges: Edge[>..<]&,keys: dictionary<u64,bool>&,work: u32[>..<]&) -> Graph { return Graph {nodes:nodes,edges:edges,keys:keys,work:work}; }
fn clear(self: Graph&) { self.nodes.resize(0); self.edges.resize(0); self.keys.clear(); self.work.resize(0); self.generation=0; }
fn spend(work: i64&,limit: i64) -> blot_error::Error { if work>=limit { return blot_error::Error.type_limit; } work++; return blot_error::Error.none; }
fn ensure(self: Graph&,count: i64) -> blot_error::Error { if count>=none { return blot_error::Error.type_limit; } while self.nodes.len<count { self.nodes.push(Node {component:self.nodes.len as u32}); } return blot_error::Error.none; }
fn component(self: Graph&,scope: u32) -> u32 { if scope>=self.nodes.len { return scope; } var current=scope; while self.nodes[current].component!=current { current=self.nodes[current].component; } return current; }
fn begin(self: Graph&) { self.generation=(self.generation as u64+1) as u32; if self.generation==0 { for i in 0..self.nodes.len { self.nodes[i].forward=0; self.nodes[i].backward=0; } self.generation=1; } }
fn mark(self: Graph&,start: u32,backward: bool,work: i64&,limit: i64) -> blot_error::Error {
 self.work.resize(0); if backward { self.nodes[start].backward=self.generation; } else { self.nodes[start].forward=self.generation; } self.work.push(start);
 while self.work.len!=0 {
  let scope=self.work[self.work.len-1]; self.work.resize(self.work.len-1); let err=spend(work,limit); if err!=blot_error::Error.none { return err; }
  var next=self.nodes[scope].out; if backward { next=self.nodes[scope].in; }
  while next!=none {
   let error=spend(work,limit); if error!=blot_error::Error.none { return error; } let edge=self.edges[next]; var child=edge.to; next=edge.next_out; if backward { child=edge.from; next=edge.next_in; }
   var seen=self.nodes[child].forward; if backward { seen=self.nodes[child].backward; } if seen==self.generation { continue; }
   if backward { self.nodes[child].backward=self.generation; } else { self.nodes[child].forward=self.generation; } self.work.push(child);
  }
 }
 return blot_error::Error.none;
}
fn reaches(self: Graph&,from: u32,to: u32,work: i64&,limit: i64) -> bool,blot_error::Error {
 if from==to { return true,blot_error::Error.none; } if from>=self.nodes.len||to>=self.nodes.len { return false,blot_error::Error.none; }
 let root=component(self,from); if root==component(self,to)&&self.nodes[root].recursive { return true,blot_error::Error.none; }
 begin(self); let err=mark(self,from,false,work,limit); if err!=blot_error::Error.none { return false,err; } return self.nodes[to].forward==self.generation,blot_error::Error.none;
}
fn beginAncestors(self: Graph&,caller: u32,count: i64) -> blot_error::Error { let err=ensure(self,count); if err!=blot_error::Error.none { return err; } begin(self); self.work.resize(0); self.nodes[caller].backward=self.generation; self.work.push(caller); return blot_error::Error.none; }
fn nextAncestor(self: Graph&,work: i64&,limit: i64) -> u32,bool,blot_error::Error {
 if self.work.len==0 { return 0,false,blot_error::Error.none; } let scope=self.work[self.work.len-1]; self.work.resize(self.work.len-1); let err=spend(work,limit); if err!=blot_error::Error.none { return 0,false,err; }
 var next=self.nodes[scope].in;
 while next!=none { let error=spend(work,limit); if error!=blot_error::Error.none { return 0,false,error; } let edge=self.edges[next]; next=edge.next_in; if self.nodes[edge.from].backward==self.generation { continue; } self.nodes[edge.from].backward=self.generation; self.work.push(edge.from); }
 return scope,true,blot_error::Error.none;
}
fn add(self: Graph&,from: u32,to: u32,count: i64,work: i64&,limit: i64) -> bool,blot_error::Error {
 let key=(from as u64)<<32|to; if self.keys.contains(key) { return false,blot_error::Error.none; }
 let err=spend(work,limit); if err!=blot_error::Error.none { return false,err; }
 if self.edges.len>=limit||self.edges.len>=none { return false,blot_error::Error.type_limit; }
 let error=ensure(self,count); if error!=blot_error::Error.none { return false,error; }
 let can_cycle=from==to||(self.nodes[from].in!=none&&self.nodes[to].out!=none); let index=self.edges.len as u32;
 self.edges.push(Edge {from,to,self.nodes[from].out,self.nodes[to].in}); self.keys.insert(key,true); self.nodes[from].out=index; self.nodes[to].in=index;
 if !can_cycle { return false,blot_error::Error.none; } let root=component(self,from); if root==component(self,to)&&self.nodes[root].recursive { return false,blot_error::Error.none; }
 begin(self); let e1=mark(self,to,false,work,limit); if e1!=blot_error::Error.none { return false,e1; } if self.nodes[from].forward!=self.generation { return false,blot_error::Error.none; }
 let e2=mark(self,from,true,work,limit); if e2!=blot_error::Error.none { return false,e2; } var joined=none;
 for n,scope in self.nodes { let e=spend(work,limit); if e!=blot_error::Error.none { return false,e; } if n.forward==self.generation&&n.backward==self.generation { let c=component(self,scope as u32); if c<joined { joined=c; } } }
 for i in 0..self.nodes.len { let e=spend(work,limit); if e!=blot_error::Error.none { return false,e; } if self.nodes[i].forward==self.generation&&self.nodes[i].backward==self.generation { self.nodes[i].component=joined; } }
 self.nodes[joined].recursive=true; self.merges++; return true,blot_error::Error.none;
}
