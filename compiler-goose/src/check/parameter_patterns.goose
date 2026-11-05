// Source argument patterns retain their syntactic kind after AST release.
namespace blot_check_parameter_patterns;
import check.types;
import support.error;
import support.native;
import support.pooled_buffer;
import support.structural_adapters;

import support.structural;
import std;
type Id = u32;
type List = blot_check_types::List;
enum Kind { binding, tuple, array, record }
struct Node { kind: Kind, a: u32, b: u32 = 0 }
struct Field { name: u32, pattern: Id }
struct Store {lease:u32=0,generation:u64=0,nodes:Nodes& =inactive.nodes,extra:Words& =inactive.extra}


fn node(self_: const Store&, id: Id) -> Node { return self_.nodes.items[id]; }
fn list(self_: const Store&, span: List) -> const Id[:] { return self_.extra.items[span.start..span.start + span.len]; }
fn saveList(self_: Store&, values: const Id[:]) -> List, blot_error::Error {
    if values.len > 0xffffffff - self_.extra.len { return List {..}, blot_error::Error.type_limit; }
    let start = self_.extra.len as u32;
    self_.extra.append(values);if self_.extra.failure!=blot_error::Error.none {return List{..},self_.extra.failure;}
    return List { start, values.len as u32 , ..}, blot_error::Error.none;
}
fn add(self_: Store&, value: Node) -> Id, blot_error::Error {
    if self_.nodes.len == 0xffffffff { return 0, blot_error::Error.type_limit; }
    let id = self_.nodes.len as u32;
    self_.nodes.push(value);if self_.nodes.failure!=blot_error::Error.none {return 0,self_.nodes.failure;}
    return id, blot_error::Error.none;
}
fn sequence(self_: Store&, kind: Kind, children: const Id[:]) -> Id, blot_error::Error {
    assert(kind == Kind.tuple || kind == Kind.array);
    let span, error = saveList(self_, children);
    if error != blot_error::Error.none { return 0, error; }
    return add(self_, Node { kind, span.start, span.len , ..});
}
fn record(self_: Store&, fields: const Field[:]) -> Id, blot_error::Error {
    if fields.len > (0xffffffff - self_.extra.len) / 2 { return 0, blot_error::Error.type_limit; }
    let start = self_.extra.len as u32;
    for item in fields {self_.extra.push(item.name);self_.extra.push(item.pattern);if self_.extra.failure!=blot_error::Error.none {return 0,self_.extra.failure;}}
    return add(self_, Node { Kind.record, start, fields.len as u32 , ..});
}
fn field(self_: const Store&, value: Node, index: i64) -> Field {
    assert(value.kind == Kind.record && index < value.b);
    return Field { self_.extra.items[value.a + index * 2], self_.extra.items[value.a + index * 2 + 1] , ..};
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

type Error=blot_error::Error;

struct Nodes {storage:Node[:]=default<Node[:]>(),items:Node[:]=default<Node[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Nodes:Node[>..];
fn ensure(self_:Nodes&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Nodes);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Nodes&,value:Node) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Nodes);self_.len=self_.items.len;}
fn append(self_:Nodes&,values:const Node[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Nodes);self_.len=self_.items.len;}
fn resize(self_:Nodes&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Nodes&,length:i64,value:Node) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Nodes&)->Node {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Nodes&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Nodes&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Nodes&) {blot_support_pooled_buffer::deinit(self_,pool_Nodes);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Nodes&,value:const Node&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Nodes&,values:const Node[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Words {storage:u32[:]=default<u32[:]>(),items:u32[:]=default<u32[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Words:u32[>..];
fn ensure(self_:Words&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Words);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Words&,value:u32) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Words);self_.len=self_.items.len;}
fn append(self_:Words&,values:const u32[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Words);self_.len=self_.items.len;}
fn resize(self_:Words&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Words&,length:i64,value:u32) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Words&)->u32 {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Words&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Words&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Words&) {blot_support_pooled_buffer::deinit(self_,pool_Words);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Words&,value:const u32&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Words&,values:const u32[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct OwnerState {nodes:Nodes=Nodes{..},extra:Words=Words{..},generation:u64=0,live:bool=false}
reusable var owners:OwnerState[>..]=[];
var inactive=OwnerState{..};
fn valid(self_:const Store&)->bool {return self_.lease!=0 && self_.lease-1<owners.len && owners[self_.lease-1].live && owners[self_.lease-1].generation==self_.generation;}
fn initPooled()->Store,Error {if owners.len>=0xffffffff {return Store{..},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let index=owners.alloc_index(OwnerState{generation:generation,live:true, ..});let state:OwnerState& =owners[index];return Store{lease:(index+1) as u32,generation:generation,nodes:state.nodes,extra:state.extra, ..},blot_error::Error.none;}
fn init()->Store,Error {return initPooled();}
fn deinit(self_:Store&) {if self_.lease==0 {return;}assert(valid(self_));self_.nodes.deinit();self_.extra.deinit();let index=self_.lease-1;owners[index].live=false;owners.free(index);self_=Store{..};}
