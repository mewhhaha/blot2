// Observations describe actual requests and emitted instructions, not reuse law.
namespace blot_backend_startup_emission_facts;
import .wasm;
import .runtime_ir;
import support.error;
let none: u32 = 4294967295;
enum Kind { named,anonymous,runtime_initializer }
type Origin = Kind;
struct Header { function: u32,origin: Kind,unit: u32,identity: u32,complete: bool = false }
enum EventKind { request,runtime_global_request,cell_registration,retained_value,direct_call,imported_call,indirect_call_unknown,global_read }
struct Event { kind: EventKind,caller: u32 = none,target: u32 = none,unit: u32 = 0,identity: u32 = 0,auxiliary: u32 = 0,flag: bool = false }
struct Snapshot { headers: Header[:] = default<Header[:]>(),events: Event[:] = default<Event[:]>() }
struct Store { enabled: bool = false,active: u32 = none,headers: Header[>..<]&,events: Event[>..<]& }
reusable[] var header_runs: Header[>..] = [];
reusable[] var event_runs: Event[>..] = [];
fn init(headers: Header[>..<]&,events: Event[>..<]&) -> Store { Store { headers: headers,events: events } }
fn deinit(snapshot: Snapshot&) { if snapshot.headers.len != 0 { header_runs.free_slice(snapshot.headers); } if snapshot.events.len != 0 { event_runs.free_slice(snapshot.events); } snapshot.headers = default<Header[:]>(); snapshot.events = default<Event[:]>(); }
fn deinit(store: Store&) { store.headers.clear(); store.events.clear(); store.enabled = false; store.active = none; }
fn event(store: Store&,value: Event) -> blot_error::Error { if store.enabled { store.events.push(value); } return blot_error::Error.none; }
fn request(store: Store&,function: u32,origin: Kind,unit: u32,identity: u32,hit: bool) -> blot_error::Error { if !store.enabled { return blot_error::Error.none; } let error = event(store,Event { kind: EventKind.request,caller: store.active,target: function,unit: unit,identity: identity,flag: hit , ..}); if error != blot_error::Error.none { return error; } if !hit { store.headers.push(Header { function,origin,unit,identity , ..}); } return blot_error::Error.none; }
fn complete(store: Store&,function: u32) { if !store.enabled { return; } for &header in store.headers { if header.function == function { header.complete = true; return; } } }
fn capture(store: const Store&,module: const blot_backend_wasm::Module&) -> Snapshot,blot_error::Error {
    var result = Snapshot {..}; if store.headers.len != 0 { result.headers = header_runs.alloc_slice(store.headers.len); for header,index in store.headers { result.headers[index] = header; } } var count = store.events.len;
    for function in module.functions { for instruction in blot_backend_wasm::instructions(module,function) { if instruction.op == blot_backend_runtime_ir::OP_call || instruction.op == blot_backend_runtime_ir::OP_call_import || instruction.op == blot_backend_runtime_ir::OP_call_indirect || instruction.op == blot_backend_runtime_ir::OP_global_get { count++; } } }
    if count != 0 { result.events = event_runs.alloc_slice(count); } for value,index in store.events { result.events[index] = value; } var next = store.events.len;
    for function,owner in module.functions { for instruction,ordinal in blot_backend_wasm::instructions(module,function) {
        var kind = EventKind.direct_call;
        if instruction.op == blot_backend_runtime_ir::OP_call { kind = EventKind.direct_call; } else if instruction.op == blot_backend_runtime_ir::OP_call_import { kind = EventKind.imported_call; } else if instruction.op == blot_backend_runtime_ir::OP_call_indirect { kind = EventKind.indirect_call_unknown; } else if instruction.op == blot_backend_runtime_ir::OP_global_get { kind = EventKind.global_read; } else { continue; }
        result.events[next] = Event { kind: kind,caller: owner as u32,target: instruction.operand,auxiliary: ordinal as u32 , ..}; next++;
    } } return result,blot_error::Error.none;
}
