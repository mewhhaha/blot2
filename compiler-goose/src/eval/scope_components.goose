namespace blot_eval_scope_components;
import dictionary;
import support.pooled_map;
import support.pooled_buffer;
type Error=blot_error::Error;
import support.error;
import support.native;
let none: u32=0xffffffff;
struct Node { out: u32=0xffffffff, in: u32=0xffffffff, component: u32, forward: u32=0, backward: u32=0, recursive: bool=false }
struct Edge { from: u32,to: u32,next_out: u32,next_in: u32 }
struct NodeBuffer { storage: Node[:]=[],items: Node[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_NodeBuffer: Node[>..]=[];
fn ensure(self: NodeBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_NodeBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: NodeBuffer&,value: Node) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_NodeBuffer); self.len=self.items.len; }
fn append(self: NodeBuffer&,values: const Node[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_NodeBuffer); self.len=self.items.len; }
fn resize(self: NodeBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: NodeBuffer&,length: i64,value: Node) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: NodeBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: NodeBuffer&) { blot_support_pooled_buffer::deinit(self,pool_NodeBuffer); self.len=0; self.failure=Error.none; }
struct EdgeBuffer { storage: Edge[:]=[],items: Edge[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_EdgeBuffer: Edge[>..]=[];
fn ensure(self: EdgeBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_EdgeBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: EdgeBuffer&,value: Edge) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_EdgeBuffer); self.len=self.items.len; }
fn append(self: EdgeBuffer&,values: const Edge[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_EdgeBuffer); self.len=self.items.len; }
fn resize(self: EdgeBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: EdgeBuffer&,length: i64,value: Edge) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: EdgeBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: EdgeBuffer&) { blot_support_pooled_buffer::deinit(self,pool_EdgeBuffer); self.len=0; self.failure=Error.none; }
struct WordBuffer { storage: u32[:]=[],items: u32[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_WordBuffer: u32[>..]=[];
fn ensure(self: WordBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_WordBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: WordBuffer&,value: u32) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_WordBuffer); self.len=self.items.len; }
fn append(self: WordBuffer&,values: const u32[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_WordBuffer); self.len=self.items.len; }
fn resize(self: WordBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: WordBuffer&,length: i64,value: u32) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: WordBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: WordBuffer&) { blot_support_pooled_buffer::deinit(self,pool_WordBuffer); self.len=0; self.failure=Error.none; }
struct KeyMap { count: i64=0,slots: dictionary_slot<u64,bool>[:]=[] }
reusable[] var pool_KeyMap: dictionary_slot<u64,bool>[>..]=[];
fn get(self: const KeyMap&,key: u64) -> bool? { let view=blot_support_pooled_map::Map<u64,bool> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const KeyMap&,key: u64) -> bool { return self.get(key)!=null; }
fn insert(self: KeyMap&,key: u64,value: bool) { var view=blot_support_pooled_map::Map<u64,bool> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_KeyMap); self.count=view.count; self.slots=view.slots; }
fn clear(self: KeyMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: KeyMap&) { if self.slots.len!=0 { pool_KeyMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
fn restore(self: KeyMap&,slots: const dictionary_slot<u64,bool>[:],count: i64) { release(self); self.count=count; if slots.len!=0 { self.slots=pool_KeyMap.alloc_slice(slots.len); for slot,index in slots { self.slots[index]=slot; } } }
struct GraphState { nodes: NodeBuffer=NodeBuffer {},edges: EdgeBuffer=EdgeBuffer {},work: WordBuffer=WordBuffer {},keys: KeyMap=KeyMap {},owner_id: u64=0,generation: u32=0,merges: i64=0,lease_generation: u64=0,live: bool=false }
reusable var Graph_states: GraphState[>..]=[];
var inactive_Graph: GraphState=GraphState {};
var next_Graph_generation: u64=1;
struct Graph { nodes: NodeBuffer&=inactive_Graph.nodes,edges: EdgeBuffer&=inactive_Graph.edges,work: WordBuffer&=inactive_Graph.work,keys: KeyMap&=inactive_Graph.keys,owner_id: u64&=inactive_Graph.owner_id,generation: u32&=inactive_Graph.generation,merges: i64&=inactive_Graph.merges,lease: u32=0,lease_generation: u64=0 }
fn initPooled() -> Graph,blot_error::Error { if next_Graph_generation==0xffffffffffffffff||Graph_states.len>=0xffffffff { return Graph {},blot_error::Error.out_of_memory; } let generation=next_Graph_generation; next_Graph_generation++; let index=Graph_states.alloc_index(GraphState {lease_generation:generation,live:true,owner_id:blot_native::fresh_owner_id()}); let state: GraphState&=Graph_states[index]; return Graph {nodes:state.nodes,edges:state.edges,work:state.work,keys:state.keys,owner_id:state.owner_id,generation:state.generation,merges:state.merges,lease:(index+1) as u32,lease_generation:generation},blot_error::Error.none; }
fn deinit(self: Graph&) { if self.lease==0 { return; } let index=self.lease-1; assert(index<Graph_states.len&&Graph_states[index].live&&Graph_states[index].lease_generation==self.lease_generation); self.nodes.deinit(); self.edges.deinit(); self.work.deinit(); release(self.keys); Graph_states[index].live=false; Graph_states.free(index); self=Graph {}; }
fn clear(self: Graph&) { self.nodes.resize(0); self.edges.resize(0); self.keys.clear(); self.work.resize(0); self.generation=0; }
fn spend(work: i64&,limit: i64) -> blot_error::Error { if work>=limit { return blot_error::Error.type_limit; } work++; return blot_error::Error.none; }
fn ensure(self: Graph&,count: i64) -> blot_error::Error { if count>=none { return blot_error::Error.type_limit; } while self.nodes.len<count { self.nodes.push(Node {component:self.nodes.len as u32}); } return blot_error::Error.none; }
fn component(self: Graph&,scope: u32) -> u32 { if scope>=self.nodes.len { return scope; } var current=scope; while self.nodes.items[current].component!=current { current=self.nodes.items[current].component; } return current; }
fn begin(self: Graph&) { self.generation=(self.generation as u64+1) as! u32; if self.generation==0 { for i in 0..self.nodes.len { self.nodes.items[i].forward=0; self.nodes.items[i].backward=0; } self.generation=1; } }
fn mark(self: Graph&,start: u32,backward: bool,work: i64&,limit: i64) -> blot_error::Error {
 self.work.resize(0); if backward { self.nodes.items[start].backward=self.generation; } else { self.nodes.items[start].forward=self.generation; } self.work.push(start);
 while self.work.len!=0 {
  let scope=self.work.items[self.work.len-1]; self.work.resize(self.work.len-1); let err=spend(work,limit); if err!=blot_error::Error.none { return err; }
  var next=self.nodes.items[scope].out; if backward { next=self.nodes.items[scope].in; }
  while next!=none {
   let error=spend(work,limit); if error!=blot_error::Error.none { return error; } let edge=self.edges.items[next]; var child=edge.to; next=edge.next_out; if backward { child=edge.from; next=edge.next_in; }
   var seen=self.nodes.items[child].forward; if backward { seen=self.nodes.items[child].backward; } if seen==self.generation { continue; }
   if backward { self.nodes.items[child].backward=self.generation; } else { self.nodes.items[child].forward=self.generation; } self.work.push(child);
  }
 }
 return blot_error::Error.none;
}
fn reaches(self: Graph&,from: u32,to: u32,work: i64&,limit: i64) -> bool,blot_error::Error {
 if from==to { return true,blot_error::Error.none; } if from>=self.nodes.len||to>=self.nodes.len { return false,blot_error::Error.none; }
 let root=component(self,from); if root==component(self,to)&&self.nodes.items[root].recursive { return true,blot_error::Error.none; }
 begin(self); let err=mark(self,from,false,work,limit); if err!=blot_error::Error.none { return false,err; } return self.nodes.items[to].forward==self.generation,blot_error::Error.none;
}
fn beginAncestors(self: Graph&,caller: u32,count: i64) -> blot_error::Error { let err=ensure(self,count); if err!=blot_error::Error.none { return err; } begin(self); self.work.resize(0); self.nodes.items[caller].backward=self.generation; self.work.push(caller); return blot_error::Error.none; }
fn nextAncestor(self: Graph&,work: i64&,limit: i64) -> u32,bool,blot_error::Error {
 if self.work.len==0 { return 0,false,blot_error::Error.none; } let scope=self.work.items[self.work.len-1]; self.work.resize(self.work.len-1); let err=spend(work,limit); if err!=blot_error::Error.none { return 0,false,err; }
 var next=self.nodes.items[scope].in;
 while next!=none { let error=spend(work,limit); if error!=blot_error::Error.none { return 0,false,error; } let edge=self.edges.items[next]; next=edge.next_in; if self.nodes.items[edge.from].backward==self.generation { continue; } self.nodes.items[edge.from].backward=self.generation; self.work.push(edge.from); }
 return scope,true,blot_error::Error.none;
}
fn add(self: Graph&,from: u32,to: u32,count: i64,work: i64&,limit: i64) -> bool,blot_error::Error {
 let key=(from as u64)<<32|to; if self.keys.contains(key) { return false,blot_error::Error.none; }
 let err=spend(work,limit); if err!=blot_error::Error.none { return false,err; }
 if self.edges.len>=limit||self.edges.len>=none { return false,blot_error::Error.type_limit; }
 let error=ensure(self,count); if error!=blot_error::Error.none { return false,error; }
 let can_cycle=from==to||(self.nodes.items[from].in!=none&&self.nodes.items[to].out!=none); let index=self.edges.len as u32;
 self.edges.push(Edge {from,to,self.nodes.items[from].out,self.nodes.items[to].in}); self.keys.insert(key,true); self.nodes.items[from].out=index; self.nodes.items[to].in=index;
 if !can_cycle { return false,blot_error::Error.none; } let root=component(self,from); if root==component(self,to)&&self.nodes.items[root].recursive { return false,blot_error::Error.none; }
 begin(self); let e1=mark(self,to,false,work,limit); if e1!=blot_error::Error.none { return false,e1; } if self.nodes.items[from].forward!=self.generation { return false,blot_error::Error.none; }
 let e2=mark(self,from,true,work,limit); if e2!=blot_error::Error.none { return false,e2; } var joined=none;
 for n,scope in self.nodes.items { let e=spend(work,limit); if e!=blot_error::Error.none { return false,e; } if n.forward==self.generation&&n.backward==self.generation { let c=component(self,scope as u32); if c<joined { joined=c; } } }
 for i in 0..self.nodes.len { let e=spend(work,limit); if e!=blot_error::Error.none { return false,e; } if self.nodes.items[i].forward==self.generation&&self.nodes.items[i].backward==self.generation { self.nodes.items[i].component=joined; } }
 self.nodes.items[joined].recursive=true; self.merges++; return true,blot_error::Error.none;
}
