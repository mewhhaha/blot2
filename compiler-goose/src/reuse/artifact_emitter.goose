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
struct Recorder_Record {storage:Record[:]=default<Record[:]>(),items:Record[:]=default<Record[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Recorder_Record:Record[>..]=[];
fn ensure(self_:Recorder_Record&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Recorder_Record);return self_.failure;}
fn push(self_:Recorder_Record&,value:Record) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Recorder_Record);self_.len=self_.items.len;}
fn append(self_:Recorder_Record&,values:const Record[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Recorder_Record);self_.len=self_.items.len;}
fn resize(self_:Recorder_Record&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn clear(self_:Recorder_Record&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Recorder_Record&) {blot_support_pooled_buffer::deinit(self_,pool_Recorder_Record);self_.len=0;self_.failure=blot_error::Error.none;}
struct Recorder_u8 {storage:u8[:]=default<u8[:]>(),items:u8[:]=default<u8[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Recorder_u8:u8[>..]=[];
fn ensure(self_:Recorder_u8&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Recorder_u8);return self_.failure;}
fn push(self_:Recorder_u8&,value:u8) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Recorder_u8);self_.len=self_.items.len;}
fn append(self_:Recorder_u8&,values:const u8[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Recorder_u8);self_.len=self_.items.len;}
fn resize(self_:Recorder_u8&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn clear(self_:Recorder_u8&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Recorder_u8&) {blot_support_pooled_buffer::deinit(self_,pool_Recorder_u8);self_.len=0;self_.failure=blot_error::Error.none;}
struct Recorder_ValueType {storage:ValueType[:]=default<ValueType[:]>(),items:ValueType[:]=default<ValueType[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Recorder_ValueType:ValueType[>..]=[];
fn ensure(self_:Recorder_ValueType&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Recorder_ValueType);return self_.failure;}
fn push(self_:Recorder_ValueType&,value:ValueType) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Recorder_ValueType);self_.len=self_.items.len;}
fn append(self_:Recorder_ValueType&,values:const ValueType[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Recorder_ValueType);self_.len=self_.items.len;}
fn resize(self_:Recorder_ValueType&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn clear(self_:Recorder_ValueType&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Recorder_ValueType&) {blot_support_pooled_buffer::deinit(self_,pool_Recorder_ValueType);self_.len=0;self_.failure=blot_error::Error.none;}
struct Recorder_Operation {storage:Operation[:]=default<Operation[:]>(),items:Operation[:]=default<Operation[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Recorder_Operation:Operation[>..]=[];
fn ensure(self_:Recorder_Operation&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Recorder_Operation);return self_.failure;}
fn push(self_:Recorder_Operation&,value:Operation) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Recorder_Operation);self_.len=self_.items.len;}
fn append(self_:Recorder_Operation&,values:const Operation[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Recorder_Operation);self_.len=self_.items.len;}
fn resize(self_:Recorder_Operation&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn clear(self_:Recorder_Operation&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Recorder_Operation&) {blot_support_pooled_buffer::deinit(self_,pool_Recorder_Operation);self_.len=0;self_.failure=blot_error::Error.none;}
struct Recorder_SymbolicInstruction {storage:SymbolicInstruction[:]=default<SymbolicInstruction[:]>(),items:SymbolicInstruction[:]=default<SymbolicInstruction[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Recorder_SymbolicInstruction:SymbolicInstruction[>..]=[];
fn ensure(self_:Recorder_SymbolicInstruction&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Recorder_SymbolicInstruction);return self_.failure;}
fn push(self_:Recorder_SymbolicInstruction&,value:SymbolicInstruction) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Recorder_SymbolicInstruction);self_.len=self_.items.len;}
fn append(self_:Recorder_SymbolicInstruction&,values:const SymbolicInstruction[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Recorder_SymbolicInstruction);self_.len=self_.items.len;}
fn resize(self_:Recorder_SymbolicInstruction&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn clear(self_:Recorder_SymbolicInstruction&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Recorder_SymbolicInstruction&) {blot_support_pooled_buffer::deinit(self_,pool_Recorder_SymbolicInstruction);self_.len=0;self_.failure=blot_error::Error.none;}

struct Tables {
    records: Recorder_Record& =inactive_Recorder_Record, bytes: Recorder_u8& =inactive_Recorder_u8, parameters: Recorder_ValueType& =inactive_Recorder_ValueType,
    operations: Recorder_Operation& =inactive_Recorder_Operation, pending_instructions: Recorder_SymbolicInstruction& =inactive_Recorder_SymbolicInstruction,
}
struct Recorder {
    recorder_lease:u32=0,recorder_generation:u64=0,
    owner: const u32&? = null, clock: u64&? = null, local_clock: u64 = 0,
    records: Recorder_Record& =inactive_Recorder_Record, bytes: Recorder_u8& =inactive_Recorder_u8, parameters: Recorder_ValueType& =inactive_Recorder_ValueType, operations: Recorder_Operation& =inactive_Recorder_Operation,
    functions: FunctionArtifact[:] = default<FunctionArtifact[:]>(), locals: ValueType[:] = default<ValueType[:]>(), instructions: SymbolicInstruction[:] = default<SymbolicInstruction[:]>(),
    pending_instructions: Recorder_SymbolicInstruction& =inactive_Recorder_SymbolicInstruction, frozen_instructions: bool = false, sealed: bool = false,
    arena: blot_support::Option<blot_backend_wasm::Arena> =blot_support::none<blot_backend_wasm::Arena>(), lists: blot_support::Option<blot_runtime_list_runtime::Runtime> =blot_support::none<blot_runtime_list_runtime::Runtime>(),
}
fn init(t: Tables) -> Recorder { Recorder { records: t.records, bytes: t.bytes, parameters: t.parameters, operations: t.operations, pending_instructions: t.pending_instructions } }
reusable[] var owned_functions: FunctionArtifact[>..] = [];
fn releaseOwned(source: const FunctionArtifact[:]) {
    if source.len == 0 { return; } owned_functions.free_slice(source);
}
reusable[] var owned_locals: ValueType[>..] = [];
fn releaseOwned(source: const ValueType[:]) {
    if source.len == 0 { return; } owned_locals.free_slice(source);
}
reusable[] var owned_instructions: SymbolicInstruction[>..] = [];
fn releaseOwned(source: const SymbolicInstruction[:]) {
    if source.len == 0 { return; } owned_instructions.free_slice(source);
}
fn deinit(self_: Recorder&) {
    self_.records.clear(); self_.bytes.clear(); self_.parameters.clear(); self_.operations.clear();
    releaseOwned(self_.functions); releaseOwned(self_.locals); releaseOwned(self_.instructions);
    self_.functions = default<FunctionArtifact[:]>(); self_.locals = default<ValueType[:]>(); self_.instructions = default<SymbolicInstruction[:]>(); self_.pending_instructions.clear();
}
fn reset(self_:Recorder&) {
    self_.deinit();
    self_.owner .=null;self_.clock .=null;self_.local_clock=0;
    self_.frozen_instructions=false;self_.sealed=false;
    self_.arena=blot_support::none<blot_backend_wasm::Arena>();
    self_.lists=blot_support::none<blot_runtime_list_runtime::Runtime>();
}

fn append(self_: Recorder&, event: Event) -> Error {
    assert(!self_.sealed);let reserved=self_.records.ensure(self_.records.len+1);if reserved!=blot_error::Error.none {return reserved;} var sequence = self_.local_clock;
    { let optional_source_58 .= self_.clock; if optional_source_58 { let clock .= optional_source_58; sequence = clock; clock++;  } else { self_.local_clock++; } }
    var owner: u32 = 0; { let optional_source_57 .= self_.owner; if optional_source_57 { let current .= optional_source_57; owner = current;  } }
    self_.records.push(Record { sequence, owner, event , ..}); return blot_error::Error.none;
}
fn appendInstruction(self_: Recorder&, function: u32, op: Op, operand: Operand) -> Error {
    assert(!self_.sealed && !self_.frozen_instructions);let pending_error=self_.pending_instructions.ensure(self_.pending_instructions.len+1);if pending_error!=blot_error::Error.none {return pending_error;}let record_error=self_.records.ensure(self_.records.len+1);if record_error!=blot_error::Error.none {return record_error;}
    if self_.pending_instructions.len == 4294967295 { return blot_error::Error.out_of_memory; }
    var owner: u32 = 0; { let optional_source_56 .= self_.owner; if optional_source_56 { let current .= optional_source_56; owner = current;  } }
    var sequence = self_.local_clock; { let optional_source_55 .= self_.clock; if optional_source_55 { let clock .= optional_source_55; sequence = clock;  } }
    if self_.records.len != 0 {
        let index = self_.records.len - 1; let last = self_.records.items[index];
        if last.owner == owner {
            match last.event {
                instruction_run run => {
                    if run.function == function && last.sequence + run.instructions.len == sequence &&
                        run.instructions.start as i64 + run.instructions.len == self_.pending_instructions.len {
                        self_.pending_instructions.push(SymbolicInstruction { op, operand , ..});
                        self_.records.items[index].event = Event.instruction_run { function, Span { run.instructions.start, run.instructions.len + 1 , ..} , ..};
                        { let optional_source_54 .= self_.clock; if optional_source_54 { let clock .= optional_source_54; clock++;  } else { self_.local_clock++; } } return blot_error::Error.none;
                    }
                }, _ => {},
            }
        }
    }
    let start = self_.pending_instructions.len as u32; self_.pending_instructions.push(SymbolicInstruction { op, operand , ..});
    return self_.append(Event.instruction_run { function, Span { start, 1 , ..} , ..});
}
fn instructionRun(self_: const Recorder&, span: Span) -> blot_support::Option<const SymbolicInstruction[:]> {
    var values: const SymbolicInstruction[:] = self_.pending_instructions.items;
    if self_.frozen_instructions { values = self_.instructions; }
    if span.start > values.len || span.len > values.len - span.start { return blot_support::none<const SymbolicInstruction[:]>(); }
    return blot_support::some<const SymbolicInstruction[:]>(values[span.start..span.start + span.len]);
}
fn recordArena(self_: Recorder&, arena: blot_backend_wasm::Arena) -> Error {
    assert(!self_.arena.present); let error = self_.append(Event.arena); if error != blot_error::Error.none { return error; }
    self_.arena = blot_support::some(arena); return blot_error::Error.none;
}
fn recordLists(self_: Recorder&, lists: blot_runtime_list_runtime::Runtime) -> Error {
    assert(!self_.lists.present); let error = self_.append(Event.lists); if error != blot_error::Error.none { return error; }
    self_.lists = blot_support::some(lists); return blot_error::Error.none;
}
fn recordListsExtension(self_: Recorder&, lists: blot_runtime_list_runtime::Runtime) -> Error {
    assert(self_.lists.present);
    let error = self_.append(Event.list_extension { lists.address_unchecked, lists.set_unchecked, lists.snapshot , ..});
    if error != blot_error::Error.none { return error; } self_.lists = blot_support::some(lists); return blot_error::Error.none;
}
fn raw(self_: Recorder&, value: const u8[:]) -> Span, Error {
    if self_.bytes.len > 4294967295 || value.len > 4294967295 - self_.bytes.len { return Span {..}, blot_error::Error.out_of_memory; }
    let span = Span { self_.bytes.len as u32, value.len as u32 , ..}; self_.bytes.append(value);if self_.bytes.failure!=blot_error::Error.none {return Span{..},self_.bytes.failure;} return span, blot_error::Error.none;
}
fn signature(self_: Recorder&, id: u32, parameters: const ValueType[:], result: ValueType) -> Error {
    let mark = self_.parameters.len;
    if mark > 4294967295 || parameters.len > 4294967295 - mark { return blot_error::Error.out_of_memory; }
    let span = Span { mark as u32, parameters.len as u32 , ..}; self_.parameters.append(parameters);if self_.parameters.failure!=blot_error::Error.none {return self_.parameters.failure;}
    let error = self_.append(Event.signature { id, span, result , ..}); if error != blot_error::Error.none { self_.parameters.resize(mark); } return error;
}
fn importFunction(self_: Recorder&, id: u32, namespace_name: const u8[:], name: const u8[:], signature: u32) -> Error {
    let mark = self_.bytes.len;
    let ns, e1 = self_.raw(namespace_name); if e1 != blot_error::Error.none { return e1; }
    let imported, e2 = self_.raw(name); if e2 != blot_error::Error.none { self_.bytes.resize(mark); return e2; }
    let error = self_.append(Event.import_ { id, ns, imported, signature , ..}); if error != blot_error::Error.none { self_.bytes.resize(mark); } return error;
}
fn cleanupData(self_: Recorder&, bytes: const u8[:]) -> Error {
    let span, error = self_.raw(bytes); if error != blot_error::Error.none { return error; } return self_.append(Event.cleanup_data { span , ..});
}
fn data(self_: Recorder&, address: u32, bytes: const u8[:]) -> Error {
    let mark = self_.bytes.len; let span, error = self_.raw(bytes); if error != blot_error::Error.none { return error; }
    let result = self_.append(Event.data { address, span , ..}); if result != blot_error::Error.none { self_.bytes.resize(mark); } return result;
}
fn exportItem(self_: Recorder&, module: blot_backend_wasm::Module&, item: blot_backend_wasm::Export, entry: bool) -> Error {
    let mark = self_.bytes.len; let name, error = self_.raw(module.name(item.name)); if error != blot_error::Error.none { return error; }
    let result = self_.append(Event.export_ { name, item.index, item.parameter, item.result, item.global, item.callback, item.once,
        item.parameter_owner, item.result_owner, item.owner_adapter, item.task_adapter, item.task_runtime, entry , ..});
    if result != blot_error::Error.none { self_.bytes.resize(mark); } return result;
}
fn captureOperations<S>(self_: Recorder&, store: S&) -> Error {
    assert(self_.operations.len == 0);
    for entry in store.entries {
        let mark = self_.bytes.len; let key, error = self_.raw(store.key(entry));
        if error != blot_error::Error.none { self_.bytes.resize(mark); return error; } self_.operations.push(Operation { key, entry.foreign , ..});if self_.operations.failure!=blot_error::Error.none {self_.bytes.resize(mark);return self_.operations.failure;}
    }
    return blot_error::Error.none;
}
fn operationSymbol(self_: Recorder&, id: u32, key: const u8[:], foreign: bool) -> Error {
    let mark = self_.bytes.len; let bytes, error = self_.raw(key); if error != blot_error::Error.none { return error; }
    let result = self_.append(Event.operation_symbol { id, bytes, foreign , ..}); if result != blot_error::Error.none { self_.bytes.resize(mark); } return result;
}
fn slice(self_: const Recorder&, span: Span) -> const u8[:] { self_.bytes.items[span.start..span.start + span.len] }
fn seal(self_: Recorder&) { self_.owner .= null; self_.clock .= null; self_.sealed = true; }

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
fn freezeFunctions(self_: Recorder&, function_owners: const u32[:]) -> Error {
    assert(self_.sealed && self_.functions.len == 0);let pending_error=self_.tableFailure();if pending_error!=blot_error::Error.none {return pending_error;}
    var count: i64 = 0; var local_count: i64 = 0; var instruction_count: i64 = 0;
    for record in self_.records.items {
        match record.event {
            function => { count++; }, local => { local_count++; }, instruction => { instruction_count++; },
            instruction_run run => { instruction_count += run.instructions.len; }, _ => {},
        }
    }
    let functions = owned_functions.alloc_slice(count);
    for index in count { functions[index] = FunctionArtifact {..}; }
    let locals = owned_locals.alloc_slice(local_count); let instructions = owned_instructions.alloc_slice(instruction_count);
    for record in self_.records.items {
        match record.event {
            function item => {
                var owner: u32 = 0; if item.id < function_owners.len { owner = function_owners[item.id]; }
                var role = FunctionRole.unknown; if owner != 0 { role = FunctionRole.job; }
                functions[item.id] = FunctionArtifact { owner: owner, resource_owner: record.owner, role: role,
                    signature: item.signature, creation_sequence: record.sequence , ..};
            },
            local item => { functions[item.function].locals.len++; },
            instruction item => { functions[item.function].instructions.len++; },
            instruction_run item => { functions[item.function].instructions.len += item.instructions.len; }, _ => {},
        }
    }
    for record in self_.records.items {
        match record.event {
            arena => {
                assert(self_.arena.present); let arena = self_.arena.value;
                const for <N,A> in fields<blot_backend_wasm::Arena> {
                    if arenaFunctionName(N) { functions[arena.A].role = prefixedRole("arena_", N); }
                }
            },
            host_references references => { functions[references.value.retain].role = FunctionRole.host_retain; functions[references.value.release].role = FunctionRole.host_release; },
            lists => {
                assert(self_.lists.present); let runtime = self_.lists.value;
                const for <N,A> in fields<blot_runtime_list_runtime::Runtime> { classifyList(functions, N, runtime.A); }
            },
            list_extension item => {
                if item.address.present { functions[item.address.value].role = FunctionRole.list_address_unchecked; }
                if item.set.present { functions[item.set.value].role = FunctionRole.list_set_unchecked; }
                if item.snapshot.present { functions[item.snapshot.value].role = FunctionRole.list_snapshot; }
            },
            public_owners runtime => { functions[runtime.value.publish].role = FunctionRole.public_owner_publish; functions[runtime.value.take].role = FunctionRole.public_owner_take; },
            start item => { functions[item.id].role = FunctionRole.module_start; },
            export_ item => { if !item.global && functions[item.index].owner == 0 { functions[item.index].role = FunctionRole.output_export; } }, _ => {},
        }
    }
    var local_offset: u32 = 0; var instruction_offset: u32 = 0;
    for index in functions.len {
        functions[index].locals.start = local_offset; functions[index].instructions.start = instruction_offset;
        local_offset += functions[index].locals.len; instruction_offset += functions[index].instructions.len;
        functions[index].locals.len = 0; functions[index].instructions.len = 0;
    }
    for index in self_.records.len {
        let record = self_.records.items[index];
        match record.event {
            local item => {
                let span = functions[item.function].locals; locals[span.start + span.len] = item.ty; functions[item.function].locals.len++;
            },
            instruction item => {
                let span = functions[item.function].instructions;
                instructions[span.start + span.len] = SymbolicInstruction { item.op, item.operand , ..}; functions[item.function].instructions.len++;
            },
            instruction_run item => {
                let span = functions[item.function].instructions; let source = self_.instructionRun(item.instructions); assert(source.present);
                let start = span.start + span.len;
                for instruction, at in source.value { instructions[start + at] = instruction; }
                functions[item.function].instructions.len += item.instructions.len;
                self_.records.items[index].event = Event.instruction_run { item.function, Span { start, item.instructions.len , ..} , ..};
            }, _ => {},
        }
    }
    releaseOwned(self_.functions); releaseOwned(self_.locals); releaseOwned(self_.instructions);
    self_.functions = functions; self_.locals = locals; self_.instructions = instructions;
    self_.pending_instructions.clear(); self_.frozen_instructions = true; return blot_error::Error.none;
}
struct DataRange { original: u32, actual: u32, len: u32 }
struct Replay {
    journal: const Recorder&, functions: u32[>..<]&, signatures: u32[>..<]&, imports: u32[>..<]&,
    globals: u32[>..<]&, operations: u32[>..<]&, data: DataRange[>..<]&,
}
fn put(self_: Replay&, map: u32[>..<]&, original: u32, actual: u32) -> Error {
    while map.len <= original { map.push(4294967295); }
    assert(map[original] == 4294967295); map[original] = actual; return blot_error::Error.none;
}
fn get(self_: const Replay&, map: const u32[:], original: u32) -> u32, Error {
    if original >= map.len || map[original] == 4294967295 { return 0, blot_error::Error.invalid_artifact; } return map[original], blot_error::Error.none;
}
fn address(self_: const Replay&, original: u32) -> u32, Error {
    if original == 0 { return 0, blot_error::Error.none; }
    for item in self_.data { if original >= item.original && original - item.original < item.len { return item.actual + original - item.original, blot_error::Error.none; } }
    for item in self_.data { if original == item.original + item.len { return item.actual + item.len, blot_error::Error.none; } }
    return 0, blot_error::Error.invalid_artifact;
}
fn lessBytes(left: const u8[:], right: const u8[:]) -> bool {
    var length = left.len; if length > right.len { length = right.len; }
    for index in length { if left[index] != right[index] { return left[index] < right[index]; } } return left.len < right.len;
}
fn prepareOperations(self_: Replay&) -> Error {
    var ordered: u32[>..<] = []; for index in self_.journal.operations.len { ordered.push(index as u32); }
    for index in 1..ordered.len {
        let value = ordered[index]; var at = index;
        while at != 0 && lessBytes(self_.journal.slice(self_.journal.operations.items[value].key), self_.journal.slice(self_.journal.operations.items[ordered[at - 1]].key)) {
            ordered[at] = ordered[at - 1]; at--;
        }
        ordered[at] = value;
    }
    self_.operations.clear(); for index in 0..ordered.len + 1 { self_.operations.push(0); }
    var next: u32 = 2;
    for id in ordered { if self_.journal.operations.items[id].foreign { self_.operations[id + 1] = 1; } else { self_.operations[id + 1] = next; next++; } }
    return blot_error::Error.none;
}
fn resolve(self_: const Replay&, operand: Operand) -> u32, Error {
    match operand.role {
        literal, host_table, callable_layout => { return operand.value, blot_error::Error.none; },
        function, table_function, callable_function => { return self_.get(self_.functions, operand.value); },
        import_ => { return self_.get(self_.imports, operand.value); }, signature => { return self_.get(self_.signatures, operand.value); },
        global => { return self_.get(self_.globals, operand.value); }, static_address => { return self_.address(operand.value); },
        operation => {
            if operand.value == 0 || operand.value >= self_.operations.len { return 0, blot_error::Error.invalid_artifact; }
            return self_.operations[operand.value], blot_error::Error.none;
        },
    }
}
fn mappedListField(self_: const Replay&, value: u32) -> u32, Error { return self_.get(self_.functions, value); }
fn mappedListField(self_: const Replay&, value: blot_support::Option<u32>) -> blot_support::Option<u32>, Error { return blot_support::none<u32>(), blot_error::Error.none; }
fn replayInstruction(self_: const Replay&, module: blot_backend_wasm::Module&, function: u32, op: Op, operand: Operand) -> Error {
    if operand.role == Role.callable_layout && (op != blot_backend_runtime_ir::OP_ownership || operand.value == 0 || operand.value >= 67108864) { return blot_error::Error.invalid_artifact; }
    let actual_function, e1 = self_.get(self_.functions, function); if e1 != blot_error::Error.none { return e1; }
    let actual_operand, e2 = self_.resolve(operand); if e2 != blot_error::Error.none { return e2; }
    return module.emitReference(actual_function, blot_backend_runtime_ir::instruction(op,actual_operand), operand.role);
}
fn materialize(self_: const Recorder&, destination: blot_backend_wasm::Module&) -> Error { self_.replayInto(destination) }
fn replayInto(self_: const Recorder&, module: blot_backend_wasm::Module&) -> Error {
    let table_error=self_.tableFailure();if table_error!=blot_error::Error.none {return table_error;}
    if !self_.sealed || module.artifacts != null { return blot_error::Error.invalid_artifact; }
    if module.data.len != 0 || module.arena.present || module.host_references.present { return blot_error::Error.unsupported_arena_composition; }
    var functions: u32[>..<] = []; var signatures: u32[>..<] = []; var imports: u32[>..<] = [];
    var globals: u32[>..<] = []; var operations: u32[>..<] = []; var data: DataRange[>..<] = [];
    var replay = Replay { self_, functions, signatures, imports, globals, operations, data , ..};
    let prepared = replay.prepareOperations(); if prepared != blot_error::Error.none { return prepared; }
    for record in self_.records.items {
        let error = replayEvent(replay, module, record.event); if error != blot_error::Error.none { return error; }
    }
    return blot_error::Error.none;
}
fn replayEvent(replay: Replay&, module: blot_backend_wasm::Module&, event: Event) -> Error {
    match event {
        demand, operation_symbol, public_owners => {},
        cleanup_data item => { return module.setCleanupDataMetadata(replay.journal.slice(item.span)); },
        signature item => {
            let actual, error = module.internType(replay.journal.parameters.items[item.parameters.start..item.parameters.start + item.parameters.len], item.result);
            if error != blot_error::Error.none { return error; } return replay.put(replay.signatures, item.id, actual);
        },
        function item => {
            let mapped, e1 = replay.get(replay.signatures, item.signature); if e1 != blot_error::Error.none { return e1; }
            let signature = module.signatures[mapped]; let actual, e2 = module.addTypedFunction(module.signatureParameters(signature), signature.result, item.result_role);
            if e2 != blot_error::Error.none { return e2; } return replay.put(replay.functions, item.id, actual);
        },
        import_ item => {
            let mapped, e1 = replay.get(replay.signatures, item.signature); if e1 != blot_error::Error.none { return e1; }
            let signature = module.signatures[mapped];
            let actual, e2 = module.importFunction(replay.journal.slice(item.module), replay.journal.slice(item.name), module.signatureParameters(signature), signature.result);
            if e2 != blot_error::Error.none { return e2; } return replay.put(replay.imports, item.id, actual);
        },
        local item => {
            let function, e1 = replay.get(replay.functions, item.function); if e1 != blot_error::Error.none { return e1; }
            let local, e2 = module.addLocal(function, item.ty); return e2;
        },
        parameter_roles item => { let id, error = replay.get(replay.functions, item.function); if error != blot_error::Error.none { return error; } return module.setParameterRoles(id, item.roles); },
        provider_parameter item => { let id, error = replay.get(replay.functions, item.function); if error != blot_error::Error.none { return error; } return module.setProviderParameter(id, item.index as u8); },
        callable_layout item => { let id, error = replay.get(replay.functions, item.function); if error != blot_error::Error.none { return error; } return module.setCallableLayout(id, item.layout); },
        semantic_site item => {
            var site = item.value; let id, error = replay.get(replay.functions, site.function); if error != blot_error::Error.none { return error; }
            site.function = id; if site.place != module.functions[id].instructions.len { return blot_error::Error.invalid_artifact; } return module.recordSemanticSite(site);
        },
        instruction item => { return replay.replayInstruction(module, item.function, item.op, item.operand); },
        instruction_run run => {
            let instructions = replay.journal.instructionRun(run.instructions);
            if !instructions.present || instructions.value.len == 0 { return blot_error::Error.invalid_artifact; }
            for item in instructions.value { let error = replay.replayInstruction(module, run.function, item.op, item.operand); if error != blot_error::Error.none { return error; } }
        },
        global item => {
            let bits, e1 = replay.resolve(item.bits); if e1 != blot_error::Error.none { return e1; }
            let id, e2 = module.addGlobal(item.scalar, bits, item.mutable); if e2 != blot_error::Error.none { return e2; } return replay.put(replay.globals, item.id, id);
        },
        global_bits item => {
            let id, e1 = replay.get(replay.globals, item.id); if e1 != blot_error::Error.none { return e1; }
            let bits, e2 = replay.resolve(item.bits); if e2 != blot_error::Error.none { return e2; } module.globals[id].bits = bits;
        },
        data item => {
            let address = module.data.len as u32; module.data.append(replay.journal.slice(item.bytes));
            replay.data.push(DataRange { item.address, address, item.bytes.len , ..});
        },
        data_word item => {
            let address, e1 = replay.address(item.address); if e1 != blot_error::Error.none { return e1; }
            if address > module.data.len || 4 > module.data.len - address { return blot_error::Error.invalid_artifact; }
            let operand, e2 = replay.resolve(item.operand); if e2 != blot_error::Error.none { return e2; }
            let e3 = module.recordTableReference(item.operand.role, operand, blot_support::none<u32>(), address); if e3 != blot_error::Error.none { return e3; }
            module.writeDataWord(address, operand);
        },
        arena => {
            if !replay.journal.arena.present { return blot_error::Error.invalid_artifact; }
            let original = replay.journal.arena.value; var mapped = blot_backend_wasm::Arena {..};
            const for <N,A> in fields<blot_backend_wasm::Arena> {
                var value: u32 = 0; var error = blot_error::Error.none;
                if arenaFunctionName(N) { let actual, failed = replay.get(replay.functions, original.A); value = actual; error = failed; }
                else { let actual, failed = replay.get(replay.globals, original.A); value = actual; error = failed; }
                if error != blot_error::Error.none { return error; } mapped.A = value;
            }
            module.arena = blot_support::some(mapped);
        },
        host_references item => {
            let retain, e1 = replay.get(replay.functions, item.value.retain); if e1 != blot_error::Error.none { return e1; }
            let release, e2 = replay.get(replay.functions, item.value.release); if e2 != blot_error::Error.none { return e2; }
            let cursor, e3 = replay.get(replay.globals, item.value.cursor); if e3 != blot_error::Error.none { return e3; }
            let active, e4 = replay.get(replay.globals, item.value.active); if e4 != blot_error::Error.none { return e4; }
            module.host_references = blot_support::some(blot_backend_wasm::HostReferences { retain, release, cursor, active , ..});
        },
        lists => {
            if !replay.journal.lists.present { return blot_error::Error.invalid_artifact; }
            let original = replay.journal.lists.value; var runtime = original;
            const for <N,A> in fields<blot_runtime_list_runtime::Runtime> {
                let value, error = mappedListField(replay, original.A); if error != blot_error::Error.none { return error; } runtime.A = value;
            }
            module.lists = blot_support::some(runtime);
        },
        list_extension item => {
            if !module.lists.present { return blot_error::Error.invalid_artifact; }
            if item.address.present { let id, error = replay.get(replay.functions, item.address.value); if error != blot_error::Error.none { return error; } module.lists.value.address_unchecked = blot_support::some(id); }
            if item.set.present { let id, error = replay.get(replay.functions, item.set.value); if error != blot_error::Error.none { return error; } module.lists.value.set_unchecked = blot_support::some(id); }
            if item.snapshot.present { let id, error = replay.get(replay.functions, item.snapshot.value); if error != blot_error::Error.none { return error; } module.lists.value.snapshot = blot_support::some(id); }
        },
        export_ item => {
            var index: u32 = 0; var failure = blot_error::Error.none;
            if item.global { let id, error = replay.get(replay.globals, item.index); index = id; failure = error; }
            else { let id, error = replay.get(replay.functions, item.index); index = id; failure = error; }
            if failure != blot_error::Error.none { return failure; }
            let name = module.ownName(replay.journal.slice(item.name));
            module.exports.push(blot_backend_wasm::Export { name, index, item.parameter, item.result, item.global, item.callback,
                item.once, item.parameter_owner, item.result_owner, item.owner_adapter, item.task_adapter, item.task_runtime , ..});
            if item.entry { module.functions[index].entry = true; }
        },
        public_arena => { module.public_arena = true; }, mutable_static => { module.mutable_static = true; },
        static_field item => { return module.staticField(item.address, item.role); },
        start item => { let id, error = replay.get(replay.functions, item.id); if error != blot_error::Error.none { return error; } module.start = blot_support::some(id); },
    }
    return blot_error::Error.none;
}

fn recordDemand(self_: Recorder&, kind: ResourceKind, id: u32, hit: bool) -> Error { self_.append(Event.demand { kind, id, hit , ..}) }

fn recordFunction(self_: Recorder&, id: u32, signature: u32, role: blot_backend_runtime_ir::Role) -> Error { self_.append(Event.function { id, signature, role , ..}) }

fn recordParameterRoles(self_: Recorder&, function: u32, roles: u64) -> Error { self_.append(Event.parameter_roles { function, roles , ..}) }

fn recordProviderParameter(self_: Recorder&, function: u32, index: u16) -> Error { self_.append(Event.provider_parameter { function, index , ..}) }

fn recordCallableLayout(self_: Recorder&, function: u32, layout: u32) -> Error { self_.append(Event.callable_layout { function, layout , ..}) }

fn recordSemanticSite(self_: Recorder&, site: blot_backend_wasm::SemanticSite) -> Error { self_.append(Event.semantic_site { site , ..}) }

fn recordLocal(self_: Recorder&, function: u32, ty: ValueType) -> Error { self_.append(Event.local { function, ty , ..}) }

fn recordGlobal(self_: Recorder&, id: u32, scalar: blot_backend_runtime_ir::Scalar, bits: Operand, mutable: bool) -> Error { self_.append(Event.global { id, scalar, bits, mutable , ..}) }

fn recordGlobalBits(self_: Recorder&, id: u32, bits: Operand) -> Error { self_.append(Event.global_bits { id, bits , ..}) }

fn recordDataWord(self_: Recorder&, address: u32, operand: Operand) -> Error { self_.append(Event.data_word { address, operand , ..}) }

fn recordHostReferences(self_: Recorder&, value: blot_backend_wasm::HostReferences) -> Error { self_.append(Event.host_references { value , ..}) }

fn recordPublicOwners(self_: Recorder&, value: blot_runtime_public_owners::Runtime) -> Error { self_.append(Event.public_owners { value , ..}) }

fn recordStart(self_: Recorder&, id: u32) -> Error { self_.append(Event.start { id , ..}) }

fn recordStaticField(self_: Recorder&, address: u32, role: blot_backend_runtime_ir::Role) -> Error { self_.append(Event.static_field { address, role , ..}) }

fn recordPublicArena(self_: Recorder&) -> Error { self_.append(Event.public_arena) }

fn recordMutableStatic(self_: Recorder&) -> Error { self_.append(Event.mutable_static) }

fn roleCode(role: Role) -> u8 {
    match role { literal => 0, function => 1, import_ => 2, signature => 3, global => 4,
        table_function => 5, callable_function => 6, callable_layout => 7, static_address => 8, operation => 9, host_table => 10 }
}

// A recorder can outlive its invocation without pointing into local growers.
struct RecorderOwner {live:bool=false,generation:u64=0,
records:Recorder_Record=Recorder_Record{..},
bytes:Recorder_u8=Recorder_u8{..},
parameters:Recorder_ValueType=Recorder_ValueType{..},
operations:Recorder_Operation=Recorder_Operation{..},
pending_instructions:Recorder_SymbolicInstruction=Recorder_SymbolicInstruction{..},
canonical:Recorder=Recorder{..}}
reusable var recorder_owners:RecorderOwner[>..]=[];
fn initPooledRef()->Recorder?,Error {
 if recorder_owners.len>=0xffffffff {return null,blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=recorder_owners.alloc_index(RecorderOwner{live:true,generation:generation,..});let state:RecorderOwner& =recorder_owners[at];
 state.canonical=Recorder{recorder_lease:(at+1) as u32,recorder_generation:generation,
records:state.records,bytes:state.bytes,parameters:state.parameters,operations:state.operations,pending_instructions:state.pending_instructions,..};return state.canonical,blot_error::Error.none;
}
fn validRecorder(self_:const Recorder&)->bool {return self_.recorder_lease!=0 && self_.recorder_lease-1<recorder_owners.len && recorder_owners[self_.recorder_lease-1].live && recorder_owners[self_.recorder_lease-1].generation==self_.recorder_generation;}
fn tableFailure(self_:const Recorder&)->Error {
if self_.records.failure!=blot_error::Error.none {return self_.records.failure;}
if self_.bytes.failure!=blot_error::Error.none {return self_.bytes.failure;}
if self_.parameters.failure!=blot_error::Error.none {return self_.parameters.failure;}
if self_.operations.failure!=blot_error::Error.none {return self_.operations.failure;}
if self_.pending_instructions.failure!=blot_error::Error.none {return self_.pending_instructions.failure;}
return blot_error::Error.none;}
fn releasePooled(self_:Recorder&) {if self_.recorder_lease==0 {return;}assert(self_.validRecorder());let at=self_.recorder_lease-1;self_.deinit();
self_.records.deinit();
self_.bytes.deinit();
self_.parameters.deinit();
self_.operations.deinit();
self_.pending_instructions.deinit();
recorder_owners[at].live=false;self_=Recorder{..};recorder_owners.free(at);}
