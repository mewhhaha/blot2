// Source argument patterns retain their syntactic kind after AST release.
namespace blot_check_parameter_patterns;
import support.structural;
import std;
import support.error;
type Id = u32;
type List = blot_check_types::List;
enum Kind { binding, tuple, array, record }
struct Node { kind: Kind, a: u32, b: u32 = 0 }
struct Field { name: u32, pattern: Id }
struct Store {lease:u32=0,generation:u64=0,nodes:Nodes&=inactive.nodes,extra:Words&=inactive.extra}


fn node(self: const Store&, id: Id) -> Node { return self.nodes.items[id]; }
fn list(self: const Store&, span: List) -> const Id[:] { return self.extra.items[span.start..span.start + span.len]; }
fn saveList(self: Store&, values: const Id[:]) -> List, blot_error::Error {
    if values.len > 0xffffffff - self.extra.len { return List {..}, blot_error::Error.type_limit; }
    let start = self.extra.len as u32;
    self.extra.append(values);if self.extra.failure!=blot_error::Error.none {return List{..},self.extra.failure;}
    return List { start, values.len as u32 , ..}, blot_error::Error.none;
}
fn add(self: Store&, value: Node) -> Id, blot_error::Error {
    if self.nodes.len == 0xffffffff { return 0, blot_error::Error.type_limit; }
    let id = self.nodes.len as u32;
    self.nodes.push(value);if self.nodes.failure!=blot_error::Error.none {return 0,self.nodes.failure;}
    return id, blot_error::Error.none;
}
fn sequence(self: Store&, kind: Kind, children: const Id[:]) -> Id, blot_error::Error {
    assert(kind == Kind.tuple || kind == Kind.array);
    let span, error = saveList(self, children);
    if error != blot_error::Error.none { return 0, error; }
    return add(self, Node { kind, span.start, span.len , ..});
}
fn record(self: Store&, fields: const Field[:]) -> Id, blot_error::Error {
    if fields.len > (0xffffffff - self.extra.len) / 2 { return 0, blot_error::Error.type_limit; }
    let start = self.extra.len as u32;
    for item in fields {self.extra.push(item.name);self.extra.push(item.pattern);if self.extra.failure!=blot_error::Error.none {return 0,self.extra.failure;}}
    return add(self, Node { Kind.record, start, fields.len as u32 , ..});
}
fn field(self: const Store&, value: Node, index: i64) -> Field {
    assert(value.kind == Kind.record && index < value.b);
    return Field { self.extra.items[value.a + index * 2], self.extra.items[value.a + index * 2 + 1] , ..};
}

fn kindCode(value: Kind) -> u32 {
    match value {
        binding => { return 0; },
        tuple => { return 1; },
        array => { return 2; },
        record => { return 3; },
    }
}
fn kindFromCode(code: u32) -> Kind, blot_error::Error {
    match code {
        0 => { return Kind.binding, blot_error::Error.none; },
        1 => { return Kind.tuple, blot_error::Error.none; },
        2 => { return Kind.array, blot_error::Error.none; },
        3 => { return Kind.record, blot_error::Error.none; },
        _ => { return Kind.binding, blot_error::Error.invalid_artifact; },
    }
}

fn blot_structural::equal(left: blot_check_parameter_patterns::Kind, right: blot_check_parameter_patterns::Kind) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_parameter_patterns::Kind) { blot_structural::hash(sink, blot_check_parameter_patterns::kindCode(value) as! u8); }

import support.pooled_buffer;
import support.native;
type Error=blot_error::Error;

struct Nodes {storage:Node[:]=[],items:Node[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Nodes:Node[>..];
fn ensure(self:Nodes&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Nodes);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Nodes&,value:Node) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Nodes);self.len=self.items.len;}
fn append(self:Nodes&,values:const Node[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Nodes);self.len=self.items.len;}
fn resize(self:Nodes&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Nodes&,length:i64,value:Node) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Nodes&)->Node {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Nodes&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Nodes&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Nodes&) {blot_support_pooled_buffer::deinit(self,pool_Nodes);self.len=0;self.failure=Error.none;}
fn index_of(self:const Nodes&,value:const Node&)->i64 {return self.items.index_of(value);}
fn restore(self:Nodes&,values:const Node[:])->Error {self.clear();self.append(values);return self.failure;}

struct Words {storage:u32[:]=[],items:u32[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Words:u32[>..];
fn ensure(self:Words&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Words);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Words&,value:u32) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Words);self.len=self.items.len;}
fn append(self:Words&,values:const u32[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Words);self.len=self.items.len;}
fn resize(self:Words&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Words&,length:i64,value:u32) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Words&)->u32 {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Words&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Words&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Words&) {blot_support_pooled_buffer::deinit(self,pool_Words);self.len=0;self.failure=Error.none;}
fn index_of(self:const Words&,value:const u32&)->i64 {return self.items.index_of(value);}
fn restore(self:Words&,values:const u32[:])->Error {self.clear();self.append(values);return self.failure;}

struct OwnerState {nodes:Nodes=Nodes{..},extra:Words=Words{..},generation:u64=0,live:bool=false}
reusable var owners:OwnerState[>..]=[];
var inactive=OwnerState{..};
fn valid(self:const Store&)->bool {return self.lease!=0 && self.lease-1<owners.len && owners[self.lease-1].live && owners[self.lease-1].generation==self.generation;}
fn initPooled()->Store,Error {if owners.len>=0xffffffff {return Store{..},Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let index=owners.alloc_index(OwnerState{generation:generation,live:true, ..});let state:OwnerState&=owners[index];return Store{lease:(index+1) as u32,generation:generation,nodes:state.nodes,extra:state.extra, ..},Error.none;}
fn init()->Store,Error {return initPooled();}
fn deinit(self:Store&) {if self.lease==0 {return;}assert(valid(self));self.nodes.deinit();self.extra.deinit();let index=self.lease-1;owners[index].live=false;owners.free(index);self=Store{..};}
