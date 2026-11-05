// Symbolic resources and chronological emission belong to one retained owner.
namespace blot_reuse_artifact_emitter;
import std;
import backend.wasm;
import backend.runtime_ir;
import runtime.public_owners;
import runtime.list_runtime;
import support.error;
import support.option;
type Error = blot_error::Error;
type ValueType = blot_backend_runtime_ir::ValueType;
type Op = blot_backend_runtime_ir::Op;
struct Span { start: u32 = 0, len: u32 = 0 }
enum Role { literal, function, import_, signature, global, table_function, callable_function, callable_layout, static_address, operation, host_table }
struct Operand { role: Role = Role.literal, value: u32 = 0 }
enum ResourceKind { function, import_, signature, global, arena, host_references, static_data, operation, lists }
enum Event {
    demand { kind: ResourceKind, id: u32, hit: bool },
    operation_symbol { id: u32, key: Span, foreign: bool },
    signature { id: u32, parameters: Span, result: ValueType },
    function { id: u32, signature: u32, result_role: blot_backend_runtime_ir::Role = blot_backend_runtime_ir::ROLE_unknown },
    parameter_roles { function: u32, roles: u64 }, provider_parameter { function: u32, index: u16 },
    callable_layout { function: u32, layout: u32 }, semantic_site { value: blot_backend_wasm::SemanticSite },
    import_ { id: u32, module: Span, name: Span, signature: u32 },
    local { function: u32, ty: ValueType }, instruction { function: u32, op: Op, operand: Operand },
    global { id: u32, scalar: blot_backend_runtime_ir::Scalar, bits: Operand, mutable: bool },
    global_bits { id: u32, bits: Operand }, data { address: u32, bytes: Span }, data_word { address: u32, operand: Operand },
    arena, host_references { value: blot_backend_wasm::HostReferences },
    public_owners { value: blot_runtime_public_owners::Runtime }, cleanup_data { span: Span }, lists,
    list_extension { address: blot_support::Option<u32>, set: blot_support::Option<u32>, snapshot: blot_support::Option<u32> },
    export_ {
        name: Span, index: u32, parameter: blot_backend_runtime_ir::Scalar, result: blot_backend_runtime_ir::Scalar,
        global: bool, callback: blot_support::Option<blot_backend_wasm::Callback>, once: bool,
        parameter_owner: blot_support::Option<blot_backend_wasm::OwnerBoundary>, result_owner: blot_support::Option<blot_backend_wasm::OwnerBoundary>,
        owner_adapter: bool, task_adapter: bool = false, task_runtime: bool = false, entry: bool,
    },
    public_arena, mutable_static, static_field { address: u32, role: blot_backend_runtime_ir::Role }, start { id: u32 },
    instruction_run { function: u32, instructions: Span },
}
struct Record { sequence: u64, owner: u32, event: Event }
struct SymbolicInstruction { op: Op, operand: Operand }

enum FunctionRole { job, arena_allocate, arena_allocate_scalar, arena_recycle, arena_reset, arena_allocate_typed, arena_retain, arena_release, arena_release_lease, arena_retire, arena_free, arena_store_word, arena_copy_words, arena_decrement, arena_root_allocate, arena_root_reserve, arena_root_pop, arena_root_open, arena_root_close, arena_root_enter, arena_root_leave, arena_root_store, arena_root_public_allocate, arena_root_public_reset, arena_root_authority, host_retain, host_release, output_export, runtime_initializer, module_start, unknown, list_new, list_address, list_copy, list_push, list_set, list_from_array, list_to_array, list_chunk_new, list_edit, list_branch, list_own, list_insert, list_replace, list_refresh, list_rotate_left, list_rotate_right, list_balance, list_concat, list_slice, list_join, list_cut, static_closure, list_directory, list_leaf_count, list_write_leaves, arena_cycle_enqueue, arena_cycle_unlink, arena_cycle_visit, arena_cycle_collect, arena_cycle_safe, arena_mark_acyclic, arena_allocate_shaped, arena_root_allocate_shaped, list_address_unchecked, list_set_unchecked, public_owner_publish, public_owner_take, task_mover, list_snapshot }
struct FunctionArtifact {
    owner: u32 = 0, resource_owner: u32 = 0, role: FunctionRole = FunctionRole.unknown,
    signature: u32 = 0, creation_sequence: u64 = 0, locals: Span = Span {..}, instructions: Span = Span {..},
}
struct Operation { key: Span, foreign: bool }
import support.pooled_buffer;
import support.native;
struct Recorder_Record {storage:Record[:]=[],items:Record[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Recorder_Record:Record[>..]=[];
var inactive_Recorder_Record:Recorder_Record=Recorder_Record{..};
fn ensure(self:Recorder_Record&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::ensure(self,minimum,pool_Recorder_Record);return self.failure;}
fn push(self:Recorder_Record&,value:Record) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Recorder_Record);self.len=self.items.len;}
fn append(self:Recorder_Record&,values:const Record[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Recorder_Record);self.len=self.items.len;}
fn resize(self:Recorder_Record&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn clear(self:Recorder_Record&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:Recorder_Record&) {blot_support_pooled_buffer::deinit(self,pool_Recorder_Record);self.len=0;self.failure=Error.none;}
struct Recorder_u8 {storage:u8[:]=[],items:u8[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Recorder_u8:u8[>..]=[];
var inactive_Recorder_u8:Recorder_u8=Recorder_u8{..};
fn ensure(self:Recorder_u8&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::ensure(self,minimum,pool_Recorder_u8);return self.failure;}
fn push(self:Recorder_u8&,value:u8) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Recorder_u8);self.len=self.items.len;}
fn append(self:Recorder_u8&,values:const u8[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Recorder_u8);self.len=self.items.len;}
fn resize(self:Recorder_u8&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn clear(self:Recorder_u8&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:Recorder_u8&) {blot_support_pooled_buffer::deinit(self,pool_Recorder_u8);self.len=0;self.failure=Error.none;}
struct Recorder_ValueType {storage:ValueType[:]=[],items:ValueType[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Recorder_ValueType:ValueType[>..]=[];
var inactive_Recorder_ValueType:Recorder_ValueType=Recorder_ValueType{..};
fn ensure(self:Recorder_ValueType&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::ensure(self,minimum,pool_Recorder_ValueType);return self.failure;}
fn push(self:Recorder_ValueType&,value:ValueType) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Recorder_ValueType);self.len=self.items.len;}
fn append(self:Recorder_ValueType&,values:const ValueType[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Recorder_ValueType);self.len=self.items.len;}
fn resize(self:Recorder_ValueType&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn clear(self:Recorder_ValueType&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:Recorder_ValueType&) {blot_support_pooled_buffer::deinit(self,pool_Recorder_ValueType);self.len=0;self.failure=Error.none;}
struct Recorder_Operation {storage:Operation[:]=[],items:Operation[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Recorder_Operation:Operation[>..]=[];
var inactive_Recorder_Operation:Recorder_Operation=Recorder_Operation{..};
fn ensure(self:Recorder_Operation&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::ensure(self,minimum,pool_Recorder_Operation);return self.failure;}
fn push(self:Recorder_Operation&,value:Operation) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Recorder_Operation);self.len=self.items.len;}
fn append(self:Recorder_Operation&,values:const Operation[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Recorder_Operation);self.len=self.items.len;}
fn resize(self:Recorder_Operation&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn clear(self:Recorder_Operation&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:Recorder_Operation&) {blot_support_pooled_buffer::deinit(self,pool_Recorder_Operation);self.len=0;self.failure=Error.none;}
struct Recorder_SymbolicInstruction {storage:SymbolicInstruction[:]=[],items:SymbolicInstruction[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Recorder_SymbolicInstruction:SymbolicInstruction[>..]=[];
var inactive_Recorder_SymbolicInstruction:Recorder_SymbolicInstruction=Recorder_SymbolicInstruction{..};
fn ensure(self:Recorder_SymbolicInstruction&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::ensure(self,minimum,pool_Recorder_SymbolicInstruction);return self.failure;}
fn push(self:Recorder_SymbolicInstruction&,value:SymbolicInstruction) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Recorder_SymbolicInstruction);self.len=self.items.len;}
fn append(self:Recorder_SymbolicInstruction&,values:const SymbolicInstruction[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Recorder_SymbolicInstruction);self.len=self.items.len;}
fn resize(self:Recorder_SymbolicInstruction&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn clear(self:Recorder_SymbolicInstruction&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:Recorder_SymbolicInstruction&) {blot_support_pooled_buffer::deinit(self,pool_Recorder_SymbolicInstruction);self.len=0;self.failure=Error.none;}

struct Tables {
    records: Recorder_Record&=inactive_Recorder_Record, bytes: Recorder_u8&=inactive_Recorder_u8, parameters: Recorder_ValueType&=inactive_Recorder_ValueType,
    operations: Recorder_Operation&=inactive_Recorder_Operation, pending_instructions: Recorder_SymbolicInstruction&=inactive_Recorder_SymbolicInstruction,
}
struct Recorder {
    recorder_lease:u32=0,recorder_generation:u64=0,
    owner: const u32&? = null, clock: u64&? = null, local_clock: u64 = 0,
    records: Recorder_Record&=inactive_Recorder_Record, bytes: Recorder_u8&=inactive_Recorder_u8, parameters: Recorder_ValueType&=inactive_Recorder_ValueType, operations: Recorder_Operation&=inactive_Recorder_Operation,
    functions: FunctionArtifact[:] = [], locals: ValueType[:] = [], instructions: SymbolicInstruction[:] = [],
    pending_instructions: Recorder_SymbolicInstruction&=inactive_Recorder_SymbolicInstruction, frozen_instructions: bool = false, sealed: bool = false,
    arena: blot_support::Option<blot_backend_wasm::Arena>=blot_support::none<blot_backend_wasm::Arena>(), lists: blot_support::Option<blot_runtime_list_runtime::Runtime>=blot_support::none<blot_runtime_list_runtime::Runtime>(),
}
fn init(t: Tables) -> Recorder { Recorder { records: t.records, bytes: t.bytes, parameters: t.parameters, operations: t.operations, pending_instructions: t.pending_instructions } }
reusable[] var owned_functions: FunctionArtifact[>..] = [];
fn releaseOwned(source: const FunctionArtifact[:]) {
    if source.len == 0 { return; } let first: const FunctionArtifact& = source[0]; let at = owned_functions.index_of(first);
    assert(at >= 0); owned_functions.free_slice(owned_functions[at..at + source.len]);
}
reusable[] var owned_locals: ValueType[>..] = [];
fn releaseOwned(source: const ValueType[:]) {
    if source.len == 0 { return; } let first: const ValueType& = source[0]; let at = owned_locals.index_of(first);
    assert(at >= 0); owned_locals.free_slice(owned_locals[at..at + source.len]);
}
reusable[] var owned_instructions: SymbolicInstruction[>..] = [];
fn releaseOwned(source: const SymbolicInstruction[:]) {
    if source.len == 0 { return; } let first: const SymbolicInstruction& = source[0]; let at = owned_instructions.index_of(first);
    assert(at >= 0); owned_instructions.free_slice(owned_instructions[at..at + source.len]);
}
fn deinit(self: Recorder&) {
    self.records.clear(); self.bytes.clear(); self.parameters.clear(); self.operations.clear();
    releaseOwned(self.functions); releaseOwned(self.locals); releaseOwned(self.instructions);
    self.functions = []; self.locals = []; self.instructions = []; self.pending_instructions.clear();
}
fn reset(self:Recorder&) {
    let lease=self.recorder_lease;let generation=self.recorder_generation;
    let tables=Tables{records:self.records,bytes:self.bytes,parameters:self.parameters,operations:self.operations,pending_instructions:self.pending_instructions,..};
    self.deinit();self=init(tables);self.recorder_lease=lease;self.recorder_generation=generation;
}
fn append(self: Recorder&, event: Event) -> Error {
    assert(!self.sealed);let reserved=self.records.ensure(self.records.len+1);if reserved!=Error.none {return reserved;} var sequence = self.local_clock;
    { let optional_source_58 .= self.clock; if optional_source_58 { let clock .= optional_source_58; sequence = clock; clock++;  } else { self.local_clock++; } }
    var owner: u32 = 0; { let optional_source_57 .= self.owner; if optional_source_57 { let current .= optional_source_57; owner = current;  } }
    self.records.push(Record { sequence, owner, event , ..}); return Error.none;
}
fn appendInstruction(self: Recorder&, function: u32, op: Op, operand: Operand) -> Error {
    assert(!self.sealed && !self.frozen_instructions);let pending_error=self.pending_instructions.ensure(self.pending_instructions.len+1);if pending_error!=Error.none {return pending_error;}let record_error=self.records.ensure(self.records.len+1);if record_error!=Error.none {return record_error;}
    if self.pending_instructions.len == 4294967295 { return Error.out_of_memory; }
    var owner: u32 = 0; { let optional_source_56 .= self.owner; if optional_source_56 { let current .= optional_source_56; owner = current;  } }
    var sequence = self.local_clock; { let optional_source_55 .= self.clock; if optional_source_55 { let clock .= optional_source_55; sequence = clock;  } }
    if self.records.len != 0 {
        let index = self.records.len - 1; let last = self.records.items[index];
        if last.owner == owner {
            match last.event {
                Event.instruction_run run => {
                    if run.function == function && last.sequence + run.instructions.len == sequence &&
                        run.instructions.start as i64 + run.instructions.len == self.pending_instructions.len {
                        self.pending_instructions.push(SymbolicInstruction { op, operand , ..});
                        self.records.items[index].event = Event.instruction_run { function, Span { run.instructions.start, run.instructions.len + 1 , ..} , ..};
                        { let optional_source_54 .= self.clock; if optional_source_54 { let clock .= optional_source_54; clock++;  } else { self.local_clock++; } } return Error.none;
                    }
                }, _ => {},
            }
        }
    }
    let start = self.pending_instructions.len as u32; self.pending_instructions.push(SymbolicInstruction { op, operand , ..});
    return self.append(Event.instruction_run { function, Span { start, 1 , ..} , ..});
}
fn instructionRun(self: const Recorder&, span: Span) -> blot_support::Option<const SymbolicInstruction[:]> {
    var values: const SymbolicInstruction[:] = self.pending_instructions.items;
    if self.frozen_instructions { values = self.instructions; }
    if span.start > values.len || span.len > values.len - span.start { return blot_support::none<const SymbolicInstruction[:]>(); }
    return blot_support::some(values[span.start..span.start + span.len]);
}
fn recordArena(self: Recorder&, arena: blot_backend_wasm::Arena) -> Error {
    assert(!self.arena.present); let error = self.append(Event.arena); if error != Error.none { return error; }
    self.arena = blot_support::some(arena); return Error.none;
}
fn recordLists(self: Recorder&, lists: blot_runtime_list_runtime::Runtime) -> Error {
    assert(!self.lists.present); let error = self.append(Event.lists); if error != Error.none { return error; }
    self.lists = blot_support::some(lists); return Error.none;
}
fn recordListsExtension(self: Recorder&, lists: blot_runtime_list_runtime::Runtime) -> Error {
    assert(self.lists.present);
    let error = self.append(Event.list_extension { lists.address_unchecked, lists.set_unchecked, lists.snapshot , ..});
    if error != Error.none { return error; } self.lists = blot_support::some(lists); return Error.none;
}
fn raw(self: Recorder&, value: const u8[:]) -> Span, Error {
    if self.bytes.len > 4294967295 || value.len > 4294967295 - self.bytes.len { return Span {..}, Error.out_of_memory; }
    let span = Span { self.bytes.len as u32, value.len as u32 , ..}; self.bytes.append(value);if self.bytes.failure!=Error.none {return Span{..},self.bytes.failure;} return span, Error.none;
}
fn signature(self: Recorder&, id: u32, parameters: const ValueType[:], result: ValueType) -> Error {
    let mark = self.parameters.len;
    if mark > 4294967295 || parameters.len > 4294967295 - mark { return Error.out_of_memory; }
    let span = Span { mark as u32, parameters.len as u32 , ..}; self.parameters.append(parameters);if self.parameters.failure!=Error.none {return self.parameters.failure;}
    let error = self.append(Event.signature { id, span, result , ..}); if error != Error.none { self.parameters.resize(mark); } return error;
}
fn importFunction(self: Recorder&, id: u32, namespace_name: const u8[:], name: const u8[:], signature: u32) -> Error {
    let mark = self.bytes.len;
    let ns, e1 = self.raw(namespace_name); if e1 != Error.none { return e1; }
    let imported, e2 = self.raw(name); if e2 != Error.none { self.bytes.resize(mark); return e2; }
    let error = self.append(Event.import_ { id, ns, imported, signature , ..}); if error != Error.none { self.bytes.resize(mark); } return error;
}
fn cleanupData(self: Recorder&, bytes: const u8[:]) -> Error {
    let span, error = self.raw(bytes); if error != Error.none { return error; } return self.append(Event.cleanup_data { span , ..});
}
fn data(self: Recorder&, address: u32, bytes: const u8[:]) -> Error {
    let mark = self.bytes.len; let span, error = self.raw(bytes); if error != Error.none { return error; }
    let result = self.append(Event.data { address, span , ..}); if result != Error.none { self.bytes.resize(mark); } return result;
}
fn exportItem(self: Recorder&, module: blot_backend_wasm::Module&, item: blot_backend_wasm::Export, entry: bool) -> Error {
    let mark = self.bytes.len; let name, error = self.raw(module.name(item.name)); if error != Error.none { return error; }
    let result = self.append(Event.export_ { name, item.index, item.parameter, item.result, item.global, item.callback, item.once,
        item.parameter_owner, item.result_owner, item.owner_adapter, item.task_adapter, item.task_runtime, entry , ..});
    if result != Error.none { self.bytes.resize(mark); } return result;
}
fn captureOperations<S>(self: Recorder&, store: S&) -> Error {
    assert(self.operations.len == 0);
    for entry in store.entries {
        let mark = self.bytes.len; let key, error = self.raw(store.key(entry));
        if error != Error.none { self.bytes.resize(mark); return error; } self.operations.push(Operation { key, entry.foreign , ..});if self.operations.failure!=Error.none {self.bytes.resize(mark);return self.operations.failure;}
    }
    return Error.none;
}
fn operationSymbol(self: Recorder&, id: u32, key: const u8[:], foreign: bool) -> Error {
    let mark = self.bytes.len; let bytes, error = self.raw(key); if error != Error.none { return error; }
    let result = self.append(Event.operation_symbol { id, bytes, foreign , ..}); if result != Error.none { self.bytes.resize(mark); } return result;
}
fn slice(self: const Recorder&, span: Span) -> const u8[:] { self.bytes.items[span.start..span.start + span.len] }
fn seal(self: Recorder&) { self.owner = null; self.clock = null; self.sealed = true; }

fn roleForName(name: const u8[:]) -> FunctionRole {
    const for <N,V> in variants<FunctionRole> { if name == N { return V; } }
    return FunctionRole.unknown;
}
fn prefixedRole(prefix: const u8[:], name: const u8[:]) -> FunctionRole {
    var text: u8[>..<] = []; text.append(prefix); text.append(name); return roleForName(text);
}
fn arenaFunctionName(name: const u8[:]) -> bool {
    for known in blot_backend_wasm::arena_function_fields { if name == known { return true; } } return false;
}
fn classifyList(functions: FunctionArtifact[:], name: const u8[:], id: u32) { functions[id].role = prefixedRole("list_", name); }
fn classifyList(functions: FunctionArtifact[:], name: const u8[:], id: blot_support::Option<u32>) {}
fn freezeFunctions(self: Recorder&, function_owners: const u32[:]) -> Error {
    assert(self.sealed && self.functions.len == 0);let pending_error=self.tableFailure();if pending_error!=Error.none {return pending_error;}
    var count: i64 = 0; var local_count: i64 = 0; var instruction_count: i64 = 0;
    for record in self.records.items {
        match record.event {
            Event.function => { count++; }, Event.local => { local_count++; }, Event.instruction => { instruction_count++; },
            Event.instruction_run run => { instruction_count += run.instructions.len; }, _ => {},
        }
    }
    let functions = owned_functions.alloc_slice(count);
    for index in count { functions[index] = FunctionArtifact {..}; }
    let locals = owned_locals.alloc_slice(local_count); let instructions = owned_instructions.alloc_slice(instruction_count);
    for record in self.records.items {
        match record.event {
            Event.function item => {
                var owner: u32 = 0; if item.id < function_owners.len { owner = function_owners[item.id]; }
                var role = FunctionRole.unknown; if owner != 0 { role = FunctionRole.job; }
                functions[item.id] = FunctionArtifact { owner: owner, resource_owner: record.owner, role: role,
                    signature: item.signature, creation_sequence: record.sequence , ..};
            },
            Event.local item => { functions[item.function].locals.len++; },
            Event.instruction item => { functions[item.function].instructions.len++; },
            Event.instruction_run item => { functions[item.function].instructions.len += item.instructions.len; }, _ => {},
        }
    }
    for record in self.records.items {
        match record.event {
            Event.arena => {
                assert(self.arena.present); let arena = self.arena.value;
                const for <N,A> in fields<blot_backend_wasm::Arena> {
                    if arenaFunctionName(N) { functions[arena.A].role = prefixedRole("arena_", N); }
                }
            },
            Event.host_references references => { functions[references.value.retain].role = FunctionRole.host_retain; functions[references.value.release].role = FunctionRole.host_release; },
            Event.lists => {
                assert(self.lists.present); let runtime = self.lists.value;
                const for <N,A> in fields<blot_runtime_list_runtime::Runtime> { classifyList(functions, N, runtime.A); }
            },
            Event.list_extension item => {
                if item.address.present { functions[item.address.value].role = FunctionRole.list_address_unchecked; }
                if item.set.present { functions[item.set.value].role = FunctionRole.list_set_unchecked; }
                if item.snapshot.present { functions[item.snapshot.value].role = FunctionRole.list_snapshot; }
            },
            Event.public_owners runtime => { functions[runtime.value.publish].role = FunctionRole.public_owner_publish; functions[runtime.value.take].role = FunctionRole.public_owner_take; },
            Event.start item => { functions[item.id].role = FunctionRole.module_start; },
            Event.export_ item => { if !item.global && functions[item.index].owner == 0 { functions[item.index].role = FunctionRole.output_export; } }, _ => {},
        }
    }
    var local_offset: u32 = 0; var instruction_offset: u32 = 0;
    for index in functions.len {
        functions[index].locals.start = local_offset; functions[index].instructions.start = instruction_offset;
        local_offset += functions[index].locals.len; instruction_offset += functions[index].instructions.len;
        functions[index].locals.len = 0; functions[index].instructions.len = 0;
    }
    for index in self.records.len {
        let record = self.records.items[index];
        match record.event {
            Event.local item => {
                let span = functions[item.function].locals; locals[span.start + span.len] = item.ty; functions[item.function].locals.len++;
            },
            Event.instruction item => {
                let span = functions[item.function].instructions;
                instructions[span.start + span.len] = SymbolicInstruction { item.op, item.operand , ..}; functions[item.function].instructions.len++;
            },
            Event.instruction_run item => {
                let span = functions[item.function].instructions; let source = self.instructionRun(item.instructions); assert(source.present);
                let start = span.start + span.len;
                for instruction, at in source.value { instructions[start + at] = instruction; }
                functions[item.function].instructions.len += item.instructions.len;
                self.records.items[index].event = Event.instruction_run { item.function, Span { start, item.instructions.len , ..} , ..};
            }, _ => {},
        }
    }
    releaseOwned(self.functions); releaseOwned(self.locals); releaseOwned(self.instructions);
    self.functions = functions; self.locals = locals; self.instructions = instructions;
    self.pending_instructions.clear(); self.frozen_instructions = true; return Error.none;
}
struct DataRange { original: u32, actual: u32, len: u32 }
struct Replay {
    journal: const Recorder&, functions: u32[>..<]&, signatures: u32[>..<]&, imports: u32[>..<]&,
    globals: u32[>..<]&, operations: u32[>..<]&, data: DataRange[>..<]&,
}
fn put(self: Replay&, map: u32[>..<]&, original: u32, actual: u32) -> Error {
    while map.len <= original { map.push(4294967295); }
    assert(map[original] == 4294967295); map[original] = actual; return Error.none;
}
fn get(self: const Replay&, map: const u32[:], original: u32) -> u32, Error {
    if original >= map.len || map[original] == 4294967295 { return 0, Error.invalid_artifact; } return map[original], Error.none;
}
fn address(self: const Replay&, original: u32) -> u32, Error {
    if original == 0 { return 0, Error.none; }
    for item in self.data { if original >= item.original && original - item.original < item.len { return item.actual + original - item.original, Error.none; } }
    for item in self.data { if original == item.original + item.len { return item.actual + item.len, Error.none; } }
    return 0, Error.invalid_artifact;
}
fn lessBytes(left: const u8[:], right: const u8[:]) -> bool {
    var length = left.len; if length > right.len { length = right.len; }
    for index in length { if left[index] != right[index] { return left[index] < right[index]; } } return left.len < right.len;
}
fn prepareOperations(self: Replay&) -> Error {
    var ordered: u32[>..<] = []; for index in self.journal.operations.len { ordered.push(index as u32); }
    for index in 1..ordered.len {
        let value = ordered[index]; var at = index;
        while at != 0 && lessBytes(self.journal.slice(self.journal.operations.items[value].key), self.journal.slice(self.journal.operations.items[ordered[at - 1]].key)) {
            ordered[at] = ordered[at - 1]; at--;
        }
        ordered[at] = value;
    }
    self.operations.clear(); for index in 0..ordered.len + 1 { self.operations.push(0); }
    var next: u32 = 2;
    for id in ordered { if self.journal.operations.items[id].foreign { self.operations[id + 1] = 1; } else { self.operations[id + 1] = next; next++; } }
    return Error.none;
}
fn resolve(self: const Replay&, operand: Operand) -> u32, Error {
    match operand.role {
        Role.literal, Role.host_table, Role.callable_layout => { return operand.value, Error.none; },
        Role.function, Role.table_function, Role.callable_function => { return self.get(self.functions, operand.value); },
        Role.import_ => { return self.get(self.imports, operand.value); }, Role.signature => { return self.get(self.signatures, operand.value); },
        Role.global => { return self.get(self.globals, operand.value); }, Role.static_address => { return self.address(operand.value); },
        Role.operation => {
            if operand.value == 0 || operand.value >= self.operations.len { return 0, Error.invalid_artifact; }
            return self.operations[operand.value], Error.none;
        },
    }
}
fn mappedListField(self: const Replay&, value: u32) -> u32, Error { self.get(self.functions, value) }
fn mappedListField(self: const Replay&, value: blot_support::Option<u32>) -> blot_support::Option<u32>, Error { return blot_support::none<u32>(), Error.none; }
fn replayInstruction(self: const Replay&, module: blot_backend_wasm::Module&, function: u32, op: Op, operand: Operand) -> Error {
    if operand.role == Role.callable_layout && (op != blot_backend_runtime_ir::OP_ownership || operand.value == 0 || operand.value >= 67108864) { return Error.invalid_artifact; }
    let actual_function, e1 = self.get(self.functions, function); if e1 != Error.none { return e1; }
    let actual_operand, e2 = self.resolve(operand); if e2 != Error.none { return e2; }
    return module.emitReference(actual_function, blot_backend_runtime_ir::Instruction { op, actual_operand , ..}, operand.role);
}
fn materialize(self: const Recorder&, destination: blot_backend_wasm::Module&) -> Error { self.replayInto(destination) }
fn replayInto(self: const Recorder&, module: blot_backend_wasm::Module&) -> Error {
    let table_error=self.tableFailure();if table_error!=Error.none {return table_error;}
    if !self.sealed || module.artifacts != null { return Error.invalid_artifact; }
    if module.data.len != 0 || module.arena.present || module.host_references.present { return Error.unsupported_arena_composition; }
    var functions: u32[>..<] = []; var signatures: u32[>..<] = []; var imports: u32[>..<] = [];
    var globals: u32[>..<] = []; var operations: u32[>..<] = []; var data: DataRange[>..<] = [];
    var replay = Replay { self, functions, signatures, imports, globals, operations, data , ..};
    let prepared = replay.prepareOperations(); if prepared != Error.none { return prepared; }
    for record in self.records.items {
        let error = replayEvent(replay, module, record.event); if error != Error.none { return error; }
    }
    return Error.none;
}
fn replayEvent(replay: Replay&, module: blot_backend_wasm::Module&, event: Event) -> Error {
    match event {
        Event.demand, Event.operation_symbol, Event.public_owners => {},
        Event.cleanup_data item => { return module.setCleanupDataMetadata(replay.journal.slice(item.span)); },
        Event.signature item => {
            let actual, error = module.internType(replay.journal.parameters[item.parameters.start..item.parameters.start + item.parameters.len], item.result);
            if error != Error.none { return error; } return replay.put(replay.signatures, item.id, actual);
        },
        Event.function item => {
            let mapped, e1 = replay.get(replay.signatures, item.signature); if e1 != Error.none { return e1; }
            let signature = module.signatures[mapped]; let actual, e2 = module.addTypedFunction(module.signatureParameters(signature), signature.result, item.result_role);
            if e2 != Error.none { return e2; } return replay.put(replay.functions, item.id, actual);
        },
        Event.import_ item => {
            let mapped, e1 = replay.get(replay.signatures, item.signature); if e1 != Error.none { return e1; }
            let signature = module.signatures[mapped];
            let actual, e2 = module.importFunction(replay.journal.slice(item.module), replay.journal.slice(item.name), module.signatureParameters(signature), signature.result);
            if e2 != Error.none { return e2; } return replay.put(replay.imports, item.id, actual);
        },
        Event.local item => {
            let function, e1 = replay.get(replay.functions, item.function); if e1 != Error.none { return e1; }
            let local, e2 = module.addLocal(function, item.ty); return e2;
        },
        Event.parameter_roles item => { let id, error = replay.get(replay.functions, item.function); if error != Error.none { return error; } return module.setParameterRoles(id, item.roles); },
        Event.provider_parameter item => { let id, error = replay.get(replay.functions, item.function); if error != Error.none { return error; } return module.setProviderParameter(id, item.index as u8); },
        Event.callable_layout item => { let id, error = replay.get(replay.functions, item.function); if error != Error.none { return error; } return module.setCallableLayout(id, item.layout); },
        Event.semantic_site item => {
            var site = item.value; let id, error = replay.get(replay.functions, site.function); if error != Error.none { return error; }
            site.function = id; if site.place != module.functions[id].instructions.len { return Error.invalid_artifact; } return module.recordSemanticSite(site);
        },
        Event.instruction item => { return replay.replayInstruction(module, item.function, item.op, item.operand); },
        Event.instruction_run run => {
            let instructions = replay.journal.instructionRun(run.instructions);
            if !instructions.present || instructions.value.len == 0 { return Error.invalid_artifact; }
            for item in instructions.value { let error = replay.replayInstruction(module, run.function, item.op, item.operand); if error != Error.none { return error; } }
        },
        Event.global item => {
            let bits, e1 = replay.resolve(item.bits); if e1 != Error.none { return e1; }
            let id, e2 = module.addGlobal(item.scalar, bits, item.mutable); if e2 != Error.none { return e2; } return replay.put(replay.globals, item.id, id);
        },
        Event.global_bits item => {
            let id, e1 = replay.get(replay.globals, item.id); if e1 != Error.none { return e1; }
            let bits, e2 = replay.resolve(item.bits); if e2 != Error.none { return e2; } module.globals[id].bits = bits;
        },
        Event.data item => {
            let address = module.data.len as u32; module.data.append(replay.journal.slice(item.bytes));
            replay.data.push(DataRange { item.address, address, item.bytes.len , ..});
        },
        Event.data_word item => {
            let address, e1 = replay.address(item.address); if e1 != Error.none { return e1; }
            if address > module.data.len || 4 > module.data.len - address { return Error.invalid_artifact; }
            let operand, e2 = replay.resolve(item.operand); if e2 != Error.none { return e2; }
            let e3 = module.recordTableReference(item.operand.role, operand, blot_support::none<u32>(), address); if e3 != Error.none { return e3; }
            module.writeDataWord(address, operand);
        },
        Event.arena => {
            if !replay.journal.arena.present { return Error.invalid_artifact; }
            let original = replay.journal.arena.value; var mapped = blot_backend_wasm::Arena {..};
            const for <N,A> in fields<blot_backend_wasm::Arena> {
                var value: u32 = 0; var error = Error.none;
                if arenaFunctionName(N) { let actual, failed = replay.get(replay.functions, original.A); value = actual; error = failed; }
                else { let actual, failed = replay.get(replay.globals, original.A); value = actual; error = failed; }
                if error != Error.none { return error; } mapped.A = value;
            }
            module.arena = blot_support::some(mapped);
        },
        Event.host_references item => {
            let retain, e1 = replay.get(replay.functions, item.value.retain); if e1 != Error.none { return e1; }
            let release, e2 = replay.get(replay.functions, item.value.release); if e2 != Error.none { return e2; }
            let cursor, e3 = replay.get(replay.globals, item.value.cursor); if e3 != Error.none { return e3; }
            let active, e4 = replay.get(replay.globals, item.value.active); if e4 != Error.none { return e4; }
            module.host_references = blot_support::some(blot_backend_wasm::HostReferences { retain, release, cursor, active , ..});
        },
        Event.lists => {
            if !replay.journal.lists.present { return Error.invalid_artifact; }
            let original = replay.journal.lists.value; var runtime = original;
            const for <N,A> in fields<blot_runtime_list_runtime::Runtime> {
                let value, error = mappedListField(replay, original.A); if error != Error.none { return error; } runtime.A = value;
            }
            module.lists = blot_support::some(runtime);
        },
        Event.list_extension item => {
            if !module.lists.present { return Error.invalid_artifact; }
            if item.address.present { let id, error = replay.get(replay.functions, item.address.value); if error != Error.none { return error; } module.lists.value.address_unchecked = blot_support::some(id); }
            if item.set.present { let id, error = replay.get(replay.functions, item.set.value); if error != Error.none { return error; } module.lists.value.set_unchecked = blot_support::some(id); }
            if item.snapshot.present { let id, error = replay.get(replay.functions, item.snapshot.value); if error != Error.none { return error; } module.lists.value.snapshot = blot_support::some(id); }
        },
        Event.export_ item => {
            var index: u32 = 0; var failure = Error.none;
            if item.global { let id, error = replay.get(replay.globals, item.index); index = id; failure = error; }
            else { let id, error = replay.get(replay.functions, item.index); index = id; failure = error; }
            if failure != Error.none { return failure; }
            let name = module.ownName(replay.journal.slice(item.name));
            module.exports.push(blot_backend_wasm::Export { name, index, item.parameter, item.result, item.global, item.callback,
                item.once, item.parameter_owner, item.result_owner, item.owner_adapter, item.task_adapter, item.task_runtime , ..});
            if item.entry { module.functions[index].entry = true; }
        },
        Event.public_arena => { module.public_arena = true; }, Event.mutable_static => { module.mutable_static = true; },
        Event.static_field item => { return module.staticField(item.address, item.role); },
        Event.start item => { let id, error = replay.get(replay.functions, item.id); if error != Error.none { return error; } module.start = blot_support::some(id); },
    }
    return Error.none;
}

fn recordDemand(self: Recorder&, kind: ResourceKind, id: u32, hit: bool) -> Error { self.append(Event.demand { kind, id, hit , ..}) }

fn recordFunction(self: Recorder&, id: u32, signature: u32, role: blot_backend_runtime_ir::Role) -> Error { self.append(Event.function { id, signature, role , ..}) }

fn recordParameterRoles(self: Recorder&, function: u32, roles: u64) -> Error { self.append(Event.parameter_roles { function, roles , ..}) }

fn recordProviderParameter(self: Recorder&, function: u32, index: u16) -> Error { self.append(Event.provider_parameter { function, index , ..}) }

fn recordCallableLayout(self: Recorder&, function: u32, layout: u32) -> Error { self.append(Event.callable_layout { function, layout , ..}) }

fn recordSemanticSite(self: Recorder&, site: blot_backend_wasm::SemanticSite) -> Error { self.append(Event.semantic_site { site , ..}) }

fn recordLocal(self: Recorder&, function: u32, ty: ValueType) -> Error { self.append(Event.local { function, ty , ..}) }

fn recordGlobal(self: Recorder&, id: u32, scalar: blot_backend_runtime_ir::Scalar, bits: Operand, mutable: bool) -> Error { self.append(Event.global { id, scalar, bits, mutable , ..}) }

fn recordGlobalBits(self: Recorder&, id: u32, bits: Operand) -> Error { self.append(Event.global_bits { id, bits , ..}) }

fn recordDataWord(self: Recorder&, address: u32, operand: Operand) -> Error { self.append(Event.data_word { address, operand , ..}) }

fn recordHostReferences(self: Recorder&, value: blot_backend_wasm::HostReferences) -> Error { self.append(Event.host_references { value , ..}) }

fn recordPublicOwners(self: Recorder&, value: blot_runtime_public_owners::Runtime) -> Error { self.append(Event.public_owners { value , ..}) }

fn recordStart(self: Recorder&, id: u32) -> Error { self.append(Event.start { id , ..}) }

fn recordStaticField(self: Recorder&, address: u32, role: blot_backend_runtime_ir::Role) -> Error { self.append(Event.static_field { address, role , ..}) }

fn recordPublicArena(self: Recorder&) -> Error { self.append(Event.public_arena) }

fn recordMutableStatic(self: Recorder&) -> Error { self.append(Event.mutable_static) }

fn roleCode(role: Role) -> u8 {
    match role { Role.literal => 0, Role.function => 1, Role.import_ => 2, Role.signature => 3, Role.global => 4,
        Role.table_function => 5, Role.callable_function => 6, Role.callable_layout => 7, Role.static_address => 8, Role.operation => 9, Role.host_table => 10 }
}

// A recorder can outlive its invocation without pointing into local growers.
var inactive_recorder:Recorder=Recorder{..};
struct RecorderOwner {live:bool=false,generation:u64=0,
records:Recorder_Record=Recorder_Record{..},
bytes:Recorder_u8=Recorder_u8{..},
parameters:Recorder_ValueType=Recorder_ValueType{..},
operations:Recorder_Operation=Recorder_Operation{..},
pending_instructions:Recorder_SymbolicInstruction=Recorder_SymbolicInstruction{..},
canonical:Recorder=Recorder{..}}
reusable var recorder_owners:RecorderOwner[>..]=[];
fn initPooledRef()->Recorder?,Error {
 if recorder_owners.len>=0xffffffff {return null,Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=recorder_owners.alloc_index(RecorderOwner{live:true,generation:generation,..});let state:RecorderOwner&=recorder_owners[at];
 state.canonical=Recorder{recorder_lease:(at+1) as u32,recorder_generation:generation,
records:state.records,bytes:state.bytes,parameters:state.parameters,operations:state.operations,pending_instructions:state.pending_instructions,..};return state.canonical,Error.none;
}
fn validRecorder(self:const Recorder&)->bool {return self.recorder_lease!=0 && self.recorder_lease-1<recorder_owners.len && recorder_owners[self.recorder_lease-1].live && recorder_owners[self.recorder_lease-1].generation==self.recorder_generation;}
fn tableFailure(self:const Recorder&)->Error {
if self.records.failure!=Error.none {return self.records.failure;}
if self.bytes.failure!=Error.none {return self.bytes.failure;}
if self.parameters.failure!=Error.none {return self.parameters.failure;}
if self.operations.failure!=Error.none {return self.operations.failure;}
if self.pending_instructions.failure!=Error.none {return self.pending_instructions.failure;}
return Error.none;}
fn releasePooled(self:Recorder&) {if self.recorder_lease==0 {return;}assert(self.validRecorder());let at=self.recorder_lease-1;self.deinit();
self.records.deinit();
self.bytes.deinit();
self.parameters.deinit();
self.operations.deinit();
self.pending_instructions.deinit();
recorder_owners[at].live=false;self=Recorder{..};recorder_owners.free(at);}
