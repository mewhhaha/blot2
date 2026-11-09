namespace blot_eval_scope_components;
import support.error;
import support.native;
import support.pooled_buffer;
import support.pooled_map;

import dictionary;
type Error=blot_error::Error;
let none: u32=0xffffffff;
struct Node { out: u32=0xffffffff, in_: u32=0xffffffff, component: u32, forward: u32=0, backward: u32=0, recursive_: bool=false }
struct Edge { from: u32,to: u32,next_out: u32,next_in: u32 }
struct NodeBuffer { storage: Node[:]=default<Node[:]>(),items: Node[:]=default<Node[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_NodeBuffer: Node[>..]=[];
fn ensure(self_: NodeBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_NodeBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: NodeBuffer&,value: Node) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_NodeBuffer); self_.len=self_.items.len; }
fn append(self_: NodeBuffer&,values: const Node[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_NodeBuffer); self_.len=self_.items.len; }
fn resize(self_: NodeBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: NodeBuffer&,length: i64,value: Node) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: NodeBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: NodeBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_NodeBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct EdgeBuffer { storage: Edge[:]=default<Edge[:]>(),items: Edge[:]=default<Edge[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_EdgeBuffer: Edge[>..]=[];
fn ensure(self_: EdgeBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_EdgeBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: EdgeBuffer&,value: Edge) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_EdgeBuffer); self_.len=self_.items.len; }
fn append(self_: EdgeBuffer&,values: const Edge[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_EdgeBuffer); self_.len=self_.items.len; }
fn resize(self_: EdgeBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: EdgeBuffer&,length: i64,value: Edge) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: EdgeBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: EdgeBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_EdgeBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct WordBuffer { storage: u32[:]=default<u32[:]>(),items: u32[:]=default<u32[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_WordBuffer: u32[>..]=[];
fn ensure(self_: WordBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_WordBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: WordBuffer&,value: u32) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_WordBuffer); self_.len=self_.items.len; }
fn append(self_: WordBuffer&,values: const u32[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_WordBuffer); self_.len=self_.items.len; }
fn resize(self_: WordBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: WordBuffer&,length: i64,value: u32) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: WordBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: WordBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_WordBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct KeyMap { count: i64=0,slots: dictionary_slot<u64,bool>[:]=default<dictionary_slot<u64,bool>[:]>() }
reusable[] var pool_KeyMap: dictionary_slot<u64,bool>[>..]=[];
fn get(self_: const KeyMap&,key: u64) -> bool? { let view=blot_support_pooled_map::Map<u64,bool> {count:self_.count,slots:self_.slots}; let index=blot_support_pooled_map::probe(view,key); if index<0 { return null; } return self_.slots[index].val; }
fn contains(self_: const KeyMap&,key: u64) -> bool { return self_.get(key)!=null; }
fn insert(self_: KeyMap&,key: u64,value: bool) { var view=blot_support_pooled_map::Map<u64,bool> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::insert(view,key,value,pool_KeyMap); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: KeyMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: KeyMap&) { if self_.slots.len!=0 { pool_KeyMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<u64,bool>[:]>(); self_.count=0; }
fn restore(self_: KeyMap&,slots: const dictionary_slot<u64,bool>[:],count: i64) { release(self_); self_.count=count; if slots.len!=0 { let restored=pool_KeyMap.alloc_slice(slots.len); for slot,index in slots { restored[index]=slot; } self_.slots=restored; } }
struct GraphState { nodes: NodeBuffer=NodeBuffer {},edges: EdgeBuffer=EdgeBuffer {},work: WordBuffer=WordBuffer {},keys: KeyMap=KeyMap {},owner_id: u64=0,generation: u32=0,merges: i64=0,lease_generation: u64=0,live: bool=false }
reusable var Graph_states: GraphState[>..]=[];
var inactive_Graph: GraphState=GraphState {};
var next_Graph_generation: u64=1;
struct Graph { nodes: NodeBuffer& =inactive_Graph.nodes,edges: EdgeBuffer& =inactive_Graph.edges,work: WordBuffer& =inactive_Graph.work,keys: KeyMap& =inactive_Graph.keys,owner_id: u64& =inactive_Graph.owner_id,generation: u32& =inactive_Graph.generation,merges: i64& =inactive_Graph.merges,lease: u32=0,lease_generation: u64=0 }
fn initPooled() -> Graph,blot_error::Error { if next_Graph_generation==0xffffffffffffffff||Graph_states.len>=0xffffffff { return Graph {},blot_error::Error.out_of_memory; } let generation=next_Graph_generation; next_Graph_generation++; let index=Graph_states.alloc_index(GraphState {owner_id:blot_native::fresh_owner_id(),lease_generation:generation,live:true}); let state: GraphState& =Graph_states[index]; return Graph {nodes:state.nodes,edges:state.edges,work:state.work,keys:state.keys,owner_id:state.owner_id,generation:state.generation,merges:state.merges,lease:(index+1) as u32,lease_generation:generation},blot_error::Error.none; }
fn deinit(self_: Graph&) { if self_.lease==0 { return; } let index=self_.lease-1; assert(index<Graph_states.len&&Graph_states[index].live&&Graph_states[index].lease_generation==self_.lease_generation); self_.nodes.deinit(); self_.edges.deinit(); self_.work.deinit(); release(self_.keys); Graph_states[index].live=false; Graph_states.free(index); self_=Graph {}; }
fn clear(self_: Graph&) { self_.nodes.resize(0); self_.edges.resize(0); self_.keys.clear(); self_.work.resize(0); self_.generation=0; }
fn spend(work: i64&,limit: i64) -> blot_error::Error { if work>=limit { return blot_error::Error.type_limit; } work++; return blot_error::Error.none; }
fn ensure(self_: Graph&,count: i64) -> blot_error::Error { if count>=none { return blot_error::Error.type_limit; } while self_.nodes.len<count { self_.nodes.push(Node {component:self_.nodes.len as u32}); } return blot_error::Error.none; }
fn component(self_: Graph&,scope: u32) -> u32 { if scope>=self_.nodes.len { return scope; } var current=scope; while self_.nodes.items[current].component!=current { current=self_.nodes.items[current].component; } return current; }
fn begin(self_: Graph&) { self_.generation=(self_.generation as u64+1) as! u32; if self_.generation==0 { for i in 0..self_.nodes.len { self_.nodes.items[i].forward=0; self_.nodes.items[i].backward=0; } self_.generation=1; } }
fn mark(self_: Graph&,start: u32,backward: bool,work: i64&,limit: i64) -> blot_error::Error {
 self_.work.resize(0); if backward { self_.nodes.items[start].backward=self_.generation; } else { self_.nodes.items[start].forward=self_.generation; } self_.work.push(start);
 while self_.work.len!=0 {
  let scope=self_.work.items[self_.work.len-1]; self_.work.resize(self_.work.len-1); let err=spend(work,limit); if err!=blot_error::Error.none { return err; }
  var next=self_.nodes.items[scope].out; if backward { next=self_.nodes.items[scope].in_; }
  while next!=none {
   let error=spend(work,limit); if error!=blot_error::Error.none { return error; } let edge=self_.edges.items[next]; var child=edge.to; next=edge.next_out; if backward { child=edge.from; next=edge.next_in; }
   var seen=self_.nodes.items[child].forward; if backward { seen=self_.nodes.items[child].backward; } if seen==self_.generation { continue; }
   if backward { self_.nodes.items[child].backward=self_.generation; } else { self_.nodes.items[child].forward=self_.generation; } self_.work.push(child);
  }
 }
 return blot_error::Error.none;
}
fn reaches(self_: Graph&,from: u32,to: u32,work: i64&,limit: i64) -> bool,blot_error::Error {
 if from==to { return true,blot_error::Error.none; } if from>=self_.nodes.len||to>=self_.nodes.len { return false,blot_error::Error.none; }
 let root=component(self_,from); if root==component(self_,to)&&self_.nodes.items[root].recursive_ { return true,blot_error::Error.none; }
 begin(self_); let err=mark(self_,from,false,work,limit); if err!=blot_error::Error.none { return false,err; } return self_.nodes.items[to].forward==self_.generation,blot_error::Error.none;
}
fn beginAncestors(self_: Graph&,caller: u32,count: i64) -> blot_error::Error { let err=ensure(self_,count); if err!=blot_error::Error.none { return err; } begin(self_); self_.work.resize(0); self_.nodes.items[caller].backward=self_.generation; self_.work.push(caller); return blot_error::Error.none; }
fn nextAncestor(self_: Graph&,work: i64&,limit: i64) -> u32,bool,blot_error::Error {
 if self_.work.len==0 { return 0,false,blot_error::Error.none; } let scope=self_.work.items[self_.work.len-1]; self_.work.resize(self_.work.len-1); let err=spend(work,limit); if err!=blot_error::Error.none { return 0,false,err; }
 var next=self_.nodes.items[scope].in_;
 while next!=none { let error=spend(work,limit); if error!=blot_error::Error.none { return 0,false,error; } let edge=self_.edges.items[next]; next=edge.next_in; if self_.nodes.items[edge.from].backward==self_.generation { continue; } self_.nodes.items[edge.from].backward=self_.generation; self_.work.push(edge.from); }
 return scope,true,blot_error::Error.none;
}
fn add(self_: Graph&,from: u32,to: u32,count: i64,work: i64&,limit: i64) -> bool,blot_error::Error {
 let key=(from as u64)<<32|to; if self_.keys.contains(key) { return false,blot_error::Error.none; }
 let err=spend(work,limit); if err!=blot_error::Error.none { return false,err; }
 if self_.edges.len>=limit||self_.edges.len>=none { return false,blot_error::Error.type_limit; }
 let error=ensure(self_,count); if error!=blot_error::Error.none { return false,error; }
 let can_cycle=from==to||(self_.nodes.items[from].in_!=none&&self_.nodes.items[to].out!=none); let index=self_.edges.len as u32;
 self_.edges.push(Edge {from,to,self_.nodes.items[from].out,self_.nodes.items[to].in_}); self_.keys.insert(key,true); self_.nodes.items[from].out=index; self_.nodes.items[to].in_=index;
 if !can_cycle { return false,blot_error::Error.none; } let root=component(self_,from); if root==component(self_,to)&&self_.nodes.items[root].recursive_ { return false,blot_error::Error.none; }
 begin(self_); let e1=mark(self_,to,false,work,limit); if e1!=blot_error::Error.none { return false,e1; } if self_.nodes.items[from].forward!=self_.generation { return false,blot_error::Error.none; }
 let e2=mark(self_,from,true,work,limit); if e2!=blot_error::Error.none { return false,e2; } var joined=none;
 for n,scope in self_.nodes.items { let e=spend(work,limit); if e!=blot_error::Error.none { return false,e; } if n.forward==self_.generation&&n.backward==self_.generation { let c=component(self_,scope as u32); if c<joined { joined=c; } } }
 for i in 0..self_.nodes.len { let e=spend(work,limit); if e!=blot_error::Error.none { return false,e; } if self_.nodes.items[i].forward==self_.generation&&self_.nodes.items[i].backward==self_.generation { self_.nodes.items[i].component=joined; } }
 self_.nodes.items[joined].recursive_=true; self_.merges++; return true,blot_error::Error.none;
}
