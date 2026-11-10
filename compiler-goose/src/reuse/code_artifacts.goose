// Pinned backend metadata. Numeric IDs refer to these exact owning pools.
namespace blot_reuse_code_artifacts;
import check.core;
import backend.layout;
import backend.call_limits;
import backend.provider_chain;
import support.error;
import support.pooled_buffer;
import support.option;
import support.native;
import eval.type_evidence;
import eval.pool_leases;
import eval.core_eval;
import eval.instance_arguments;
import reuse.substitution_keys;
import reuse.code_expectation;
import reuse.principal_query;
import reuse.refinement_receipt;
import reuse.independent_call_proof;
import eval.selected_query;
import support.blake3;
import support.structural;
import support.wyhash;
import backend.runtime_identity;
import check.effect_evidence;
import reuse.constant_receipt;
import reuse.dependency_certificate;
import reuse.principal_inputs;
import reuse.semantic_query_table;

type Error = blot_error::Error;
const max_parameters: i64 = blot_backend_call_limits::max_parameters;
struct Key {
    dictionaries: bool = false, instance_arguments: u32 = 0,
    target: blot_check_core::BindingRef,
    parameters: u32[16] = [1; 16], count: u8 = 0, result: u32 = 1,
    effects: u32[16] = [0; 16], templates: u32 = 0, template_result: bool = false,
}
struct ClosureKey {
    scalar_environment: bool = false, dictionaries: bool = false,
    unit: u32, catalog: u32, ty: u32, captures: u32, templates: u32 = 0,
    evidence: u32 = 0, rows: u32 = 0, parameter_template: u32 = 0,
    template_result: bool = false, static_values: u32 = 0, staged: u32 = 0,
}
struct CapturedTemplate {
    scalar_environment: bool = false, callable_instances: u32 = 0, staged: u32 = 0,
    unit: u32 = 0, node: u32, captures: u32, templates: u32,
    has_environment: bool, computation: bool = false, evidence: u32 = 0, rows: u32 = 0,
}
struct CallableKey {
    dictionaries: bool = false, bound_dictionaries: bool = false,
    instance_arguments: u32 = 0, target: blot_check_core::BindingRef,
    ty: u32, applied: u32 = 0, templates: u32 = 0,
}
struct ConstructorKey { unit: u32, catalog: u32, ty: u32 }
struct PrimitiveKey { unit: u32, catalog: u32, ty: u32, applied: u32 = 0 }
struct OperationKey { operation: u32, ty: u32, scoped: bool = false }
struct ConstantKey { target: blot_check_core::BindingRef, ty: u32 }
struct HostKey { ty: u32, owned: bool = false }
enum Request {
    named { key: Key }, closure { key: ClosureKey }, callable { key: CallableKey },
    constructor { key: ConstructorKey }, primitive { key: PrimitiveKey },
    operation { key: OperationKey }, host { key: HostKey }, constant { key: ConstantKey },
    runtime_global { target: blot_check_core::BindingRef },
}
enum State { pending, reserved, hit, complete, failed }
struct ValueResult { value: u32, layout: u32 }
struct StaticRead { target: blot_check_core::BindingRef, value: u32 }
struct Span { start: u32 = 0, len: u32 = 0 }
struct Job {
    parent: u32, request: Request, reusable_: bool = true,
    inline_bodies: Span, static_reads: Span, inline_capacity: u32 = 0, static_capacity: u32 = 0, state: State = State.pending,
    function: blot_support::Option<u32>, target_job: u32 = 0,
    mappings: Span, rows: Span, templates: Span, solved: bool = false,
    result_template: blot_support::Option<u32>, value: blot_support::Option<ValueResult>,
    global: blot_support::Option<u32>,
}
fn hasStaticValues(job: Job) -> bool {
    if job.static_reads.len != 0 { return true; }
    match job.request {
        closure key => { return key.key.static_values != 0 || key.key.staged != 0; },
        _ => { return false; },
    }
}
enum Event {
    enter { job: u32 }, hit { job: u32, target: u32, function: u32 },
    reserve { job: u32, function: u32 }, solved { job: u32 },
    complete { job: u32, function: u32, result_template: blot_support::Option<u32> },
    complete_value { job: u32, result: ValueResult },
    complete_global { job: u32, global: u32 }, hit_global { job: u32, target: u32, global: u32 },
    leave { job: u32, parent: u32 },
}
struct StampedEvent { sequence: u64, event: Event }
struct FieldLocation { family: u64, tag: u32, name: u32, field: u32, len: u32 }
struct Operation { key: const u8[:], foreign: bool, runtime: u32 }
enum OperationLocation { instruction { function: u32, index: u32 }, word { address: u32 } }
struct OperationRelocation { operation: u32, location: OperationLocation }
struct Function { request: Request, function: u32, result_template: blot_support::Option<u32> }
struct Serialized { value: u32, ty: u32, address: u32 }
struct RuntimeGlobal { target: blot_check_core::BindingRef, global: u32, initializer: u32, active: bool }
struct Slot { state: u8, traced: bool, value: u32 }
struct RequestCell { state: u32, exit: u32, status: blot_check_core::RequestDecisionKind }
struct RequestHandler { callback: u32, cell: u32, outer: blot_backend_provider_chain::Head }
struct ArrayProof { unit: u32, updates: const bool[:] }
struct DiscardProof { unit: u32, unused: const bool[:] }
type Token = u64;
fn freshToken() -> Token { blot_native::fresh_owner_id() }

// Per-job slices are ranges into caller-owned journal tables. Inline/static
// reads reserve a private run, so nested jobs do not invalidate their ranges.
// A range moves only when its own capacity grows.
struct Context_Job {storage:Job[:]=default<Job[:]>(),items:Job[:]=default<Job[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Context_Job:Job[>..]=[];
fn ensure(self_:Context_Job&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Context_Job);return self_.failure;}
fn push(self_:Context_Job&,value:Job) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Context_Job);self_.len=self_.items.len;}
fn append(self_:Context_Job&,values:const Job[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Context_Job);self_.len=self_.items.len;}
fn resize(self_:Context_Job&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Context_Job&,length:i64,value:Job) {if length<=self_.len {self_.resize(length);return;}if self_.ensure(length)!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:Context_Job&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Context_Job&) {blot_support_pooled_buffer::deinit(self_,pool_Context_Job);self_.len=0;self_.failure=blot_error::Error.none;}
struct Context_StampedEvent {storage:StampedEvent[:]=default<StampedEvent[:]>(),items:StampedEvent[:]=default<StampedEvent[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Context_StampedEvent:StampedEvent[>..]=[];
fn ensure(self_:Context_StampedEvent&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Context_StampedEvent);return self_.failure;}
fn push(self_:Context_StampedEvent&,value:StampedEvent) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Context_StampedEvent);self_.len=self_.items.len;}
fn append(self_:Context_StampedEvent&,values:const StampedEvent[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Context_StampedEvent);self_.len=self_.items.len;}
fn resize(self_:Context_StampedEvent&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Context_StampedEvent&,length:i64,value:StampedEvent) {if length<=self_.len {self_.resize(length);return;}if self_.ensure(length)!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:Context_StampedEvent&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Context_StampedEvent&) {blot_support_pooled_buffer::deinit(self_,pool_Context_StampedEvent);self_.len=0;self_.failure=blot_error::Error.none;}
struct Context_u32 {storage:u32[:]=default<u32[:]>(),items:u32[:]=default<u32[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Context_u32:u32[>..]=[];
fn ensure(self_:Context_u32&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Context_u32);return self_.failure;}
fn push(self_:Context_u32&,value:u32) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Context_u32);self_.len=self_.items.len;}
fn append(self_:Context_u32&,values:const u32[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Context_u32);self_.len=self_.items.len;}
fn resize(self_:Context_u32&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Context_u32&,length:i64,value:u32) {if length<=self_.len {self_.resize(length);return;}if self_.ensure(length)!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:Context_u32&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Context_u32&) {blot_support_pooled_buffer::deinit(self_,pool_Context_u32);self_.len=0;self_.failure=blot_error::Error.none;}
struct Context_blot_check_core__BindingRef {storage:blot_check_core::BindingRef[:]=default<blot_check_core::BindingRef[:]>(),items:blot_check_core::BindingRef[:]=default<blot_check_core::BindingRef[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Context_blot_check_core__BindingRef:blot_check_core::BindingRef[>..]=[];
fn ensure(self_:Context_blot_check_core__BindingRef&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Context_blot_check_core__BindingRef);return self_.failure;}
fn push(self_:Context_blot_check_core__BindingRef&,value:blot_check_core::BindingRef) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Context_blot_check_core__BindingRef);self_.len=self_.items.len;}
fn append(self_:Context_blot_check_core__BindingRef&,values:const blot_check_core::BindingRef[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Context_blot_check_core__BindingRef);self_.len=self_.items.len;}
fn resize(self_:Context_blot_check_core__BindingRef&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Context_blot_check_core__BindingRef&,length:i64,value:blot_check_core::BindingRef) {if length<=self_.len {self_.resize(length);return;}if self_.ensure(length)!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:Context_blot_check_core__BindingRef&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Context_blot_check_core__BindingRef&) {blot_support_pooled_buffer::deinit(self_,pool_Context_blot_check_core__BindingRef);self_.len=0;self_.failure=blot_error::Error.none;}
struct Context_StaticRead {storage:StaticRead[:]=default<StaticRead[:]>(),items:StaticRead[:]=default<StaticRead[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Context_StaticRead:StaticRead[>..]=[];
fn ensure(self_:Context_StaticRead&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Context_StaticRead);return self_.failure;}
fn push(self_:Context_StaticRead&,value:StaticRead) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Context_StaticRead);self_.len=self_.items.len;}
fn append(self_:Context_StaticRead&,values:const StaticRead[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Context_StaticRead);self_.len=self_.items.len;}
fn resize(self_:Context_StaticRead&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Context_StaticRead&,length:i64,value:StaticRead) {if length<=self_.len {self_.resize(length);return;}if self_.ensure(length)!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:Context_StaticRead&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Context_StaticRead&) {blot_support_pooled_buffer::deinit(self_,pool_Context_StaticRead);self_.len=0;self_.failure=blot_error::Error.none;}
struct Context_blot_backend_layout__Mapping {storage:blot_backend_layout::Mapping[:]=default<blot_backend_layout::Mapping[:]>(),items:blot_backend_layout::Mapping[:]=default<blot_backend_layout::Mapping[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Context_blot_backend_layout__Mapping:blot_backend_layout::Mapping[>..]=[];
fn ensure(self_:Context_blot_backend_layout__Mapping&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Context_blot_backend_layout__Mapping);return self_.failure;}
fn push(self_:Context_blot_backend_layout__Mapping&,value:blot_backend_layout::Mapping) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Context_blot_backend_layout__Mapping);self_.len=self_.items.len;}
fn append(self_:Context_blot_backend_layout__Mapping&,values:const blot_backend_layout::Mapping[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Context_blot_backend_layout__Mapping);self_.len=self_.items.len;}
fn resize(self_:Context_blot_backend_layout__Mapping&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Context_blot_backend_layout__Mapping&,length:i64,value:blot_backend_layout::Mapping) {if length<=self_.len {self_.resize(length);return;}if self_.ensure(length)!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:Context_blot_backend_layout__Mapping&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Context_blot_backend_layout__Mapping&) {blot_support_pooled_buffer::deinit(self_,pool_Context_blot_backend_layout__Mapping);self_.len=0;self_.failure=blot_error::Error.none;}
struct Context_blot_backend_layout__RowMapping {storage:blot_backend_layout::RowMapping[:]=default<blot_backend_layout::RowMapping[:]>(),items:blot_backend_layout::RowMapping[:]=default<blot_backend_layout::RowMapping[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Context_blot_backend_layout__RowMapping:blot_backend_layout::RowMapping[>..]=[];
fn ensure(self_:Context_blot_backend_layout__RowMapping&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Context_blot_backend_layout__RowMapping);return self_.failure;}
fn push(self_:Context_blot_backend_layout__RowMapping&,value:blot_backend_layout::RowMapping) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Context_blot_backend_layout__RowMapping);self_.len=self_.items.len;}
fn append(self_:Context_blot_backend_layout__RowMapping&,values:const blot_backend_layout::RowMapping[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Context_blot_backend_layout__RowMapping);self_.len=self_.items.len;}
fn resize(self_:Context_blot_backend_layout__RowMapping&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Context_blot_backend_layout__RowMapping&,length:i64,value:blot_backend_layout::RowMapping) {if length<=self_.len {self_.resize(length);return;}if self_.ensure(length)!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:Context_blot_backend_layout__RowMapping&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Context_blot_backend_layout__RowMapping&) {blot_support_pooled_buffer::deinit(self_,pool_Context_blot_backend_layout__RowMapping);self_.len=0;self_.failure=blot_error::Error.none;}
struct Context_blot_reuse_substitution_keys__Entry {storage:blot_reuse_substitution_keys::Entry[:]=default<blot_reuse_substitution_keys::Entry[:]>(),items:blot_reuse_substitution_keys::Entry[:]=default<blot_reuse_substitution_keys::Entry[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Context_blot_reuse_substitution_keys__Entry:blot_reuse_substitution_keys::Entry[>..]=[];
fn ensure(self_:Context_blot_reuse_substitution_keys__Entry&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Context_blot_reuse_substitution_keys__Entry);return self_.failure;}
fn push(self_:Context_blot_reuse_substitution_keys__Entry&,value:blot_reuse_substitution_keys::Entry) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Context_blot_reuse_substitution_keys__Entry);self_.len=self_.items.len;}
fn append(self_:Context_blot_reuse_substitution_keys__Entry&,values:const blot_reuse_substitution_keys::Entry[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Context_blot_reuse_substitution_keys__Entry);self_.len=self_.items.len;}
fn resize(self_:Context_blot_reuse_substitution_keys__Entry&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Context_blot_reuse_substitution_keys__Entry&,length:i64,value:blot_reuse_substitution_keys::Entry) {if length<=self_.len {self_.resize(length);return;}if self_.ensure(length)!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:Context_blot_reuse_substitution_keys__Entry&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Context_blot_reuse_substitution_keys__Entry&) {blot_support_pooled_buffer::deinit(self_,pool_Context_blot_reuse_substitution_keys__Entry);self_.len=0;self_.failure=blot_error::Error.none;}
struct Context_blot_reuse_independent_call_proof__Record {storage:blot_reuse_independent_call_proof::Record[:]=default<blot_reuse_independent_call_proof::Record[:]>(),items:blot_reuse_independent_call_proof::Record[:]=default<blot_reuse_independent_call_proof::Record[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Context_blot_reuse_independent_call_proof__Record:blot_reuse_independent_call_proof::Record[>..]=[];
fn ensure(self_:Context_blot_reuse_independent_call_proof__Record&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Context_blot_reuse_independent_call_proof__Record);return self_.failure;}
fn push(self_:Context_blot_reuse_independent_call_proof__Record&,value:blot_reuse_independent_call_proof::Record) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Context_blot_reuse_independent_call_proof__Record);self_.len=self_.items.len;}
fn append(self_:Context_blot_reuse_independent_call_proof__Record&,values:const blot_reuse_independent_call_proof::Record[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Context_blot_reuse_independent_call_proof__Record);self_.len=self_.items.len;}
fn resize(self_:Context_blot_reuse_independent_call_proof__Record&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Context_blot_reuse_independent_call_proof__Record&,length:i64,value:blot_reuse_independent_call_proof::Record) {if length<=self_.len {self_.resize(length);return;}if self_.ensure(length)!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:Context_blot_reuse_independent_call_proof__Record&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Context_blot_reuse_independent_call_proof__Record&) {blot_support_pooled_buffer::deinit(self_,pool_Context_blot_reuse_independent_call_proof__Record);self_.len=0;self_.failure=blot_error::Error.none;}

struct Context {
    context_lease:u32=0,context_generation:u64=0,
    allocation_owner: u64 = 0,
    active_job: u32 = 0, clock: u64 = 0,
    jobs: Context_Job& =inactive_Context_Job, events: Context_StampedEvent& =inactive_Context_StampedEvent,
    function_jobs: Context_u32& =inactive_Context_u32, global_jobs: Context_u32& =inactive_Context_u32,
    inline_bodies: Context_blot_check_core__BindingRef& =inactive_Context_blot_check_core__BindingRef, static_reads: Context_StaticRead& =inactive_Context_StaticRead,
    mappings: Context_blot_backend_layout__Mapping& =inactive_Context_blot_backend_layout__Mapping, rows: Context_blot_backend_layout__RowMapping& =inactive_Context_blot_backend_layout__RowMapping,
    templates: Context_blot_reuse_substitution_keys__Entry& =inactive_Context_blot_reuse_substitution_keys__Entry,
    pools: blot_support::Option<Pools> =blot_support::none<Pools>(),
    principal_queries: blot_reuse_principal_query::Table& =inactive_context_principal_queries,
    principal_graphs: blot_eval_core_eval::RetainedPrincipalGraphs& =inactive_context_principal_graphs,
    specialization_queries: blot_eval_selected_query::Table& =inactive_context_specialization_queries,
    independent_calls: Context_blot_reuse_independent_call_proof__Record& =inactive_Context_blot_reuse_independent_call_proof__Record,
    refinement_queries: blot_reuse_refinement_receipt::Table& =inactive_context_refinement_queries,
}
struct Scope { context: Context&?, id: u32, parent: u32, live: bool = true }
fn requiredContext(context:Context?)->Context& {assert(context);return context;}
fn depth(self_: const Context&) -> i64 {
    var id = self_.active_job; var count: i64 = 0;
    while id != 0 { id = self_.jobs.items[id - 1].parent; count++; }
    return count;
}
fn appendEvent(self_: Context&, event: Event) {
    self_.events.push(StampedEvent { self_.clock, event , ..}); self_.clock++;
}
fn enter(self_: Context&, request: Request) -> Scope, Error {
    if self_.jobs.len == 4294967295 { return Scope { self_, 0, 0, false , ..}, blot_error::Error.out_of_memory; }
    let id = (self_.jobs.len + 1) as u32;
    let parent = self_.active_job;
    self_.jobs.push(Job { parent: parent, request: request , ..});if self_.jobs.failure!=blot_error::Error.none {return Scope{context:self_,id:0,parent:parent,live:false,..},self_.jobs.failure;}
    appendEvent(self_, Event.enter { id , ..});if self_.events.failure!=blot_error::Error.none {self_.jobs.resize(self_.jobs.len-1);return Scope{context:self_,id:0,parent:parent,live:false,..},self_.events.failure;}self_.active_job = id;
    return Scope { self_, id, parent , ..}, blot_error::Error.none;
}
fn requireFreshCode(self_: Context&) {
    if self_.active_job != 0 { self_.jobs.items[self_.active_job - 1].reusable_ = false; }
}
fn materializeStaticValue(self_: Context&) {
    if self_.active_job == 0 { return; }
    let job = self_.jobs.items[self_.active_job - 1];
    match job.request { constant => {}, _ => { if !job.hasStaticValues() { self_.requireFreshCode(); } } }
}
fn appendSpan<T,B>(items: B&, span: Span, value: T, capacity: u32&) -> Span {
    var start = span.start;
    if span.len == capacity {
        // Zig 0.17 ArrayList grows from the requested minimum, with one cache
        // line of initial slots. These are real reserved slots in our owner,
        // so interleaved jobs keep their ranges until the range itself grows.
        let width = bytes_of([default<T>()]).len as u32;
        var initial = 64 / width; if initial == 0 { initial = 1; }
        let minimum = span.len + 1; let grown = minimum + minimum / 2 + initial;
        start = items.len as u32;
        for index in grown { items.push(default<T>()); }
        for index in span.len { items.items[start + index] = items.items[span.start + index]; }
        capacity = grown;
    }
    items.items[start + span.len] = value; return Span { start, span.len + 1 , ..};
}
fn readInlineBody(self_: Context&, target: blot_check_core::BindingRef) -> Error {
    if self_.active_job == 0 { return blot_error::Error.none; }
    let index = self_.active_job - 1; let span = self_.jobs.items[index].inline_bodies;
    for at in span.len { if self_.inline_bodies.items[span.start + at] == target { return blot_error::Error.none; } }
    self_.jobs.items[index].inline_bodies = appendSpan(self_.inline_bodies, span, target, self_.jobs.items[index].inline_capacity);
    return blot_error::Error.none;
}
fn readStaticValue(self_: Context&, target: blot_check_core::BindingRef, value: u32) -> Error {
    if self_.active_job == 0 { return blot_error::Error.none; }
    let index = self_.active_job - 1; let span = self_.jobs.items[index].static_reads;
    for at in span.len {
        let read = self_.static_reads.items[span.start + at];
        if read.target == target && read.value == value { return blot_error::Error.none; }
    }
    self_.jobs.items[index].static_reads = appendSpan(self_.static_reads, span, StaticRead { target, value , ..}, self_.jobs.items[index].static_capacity);
    return blot_error::Error.none;
}
fn hasStaticValues(self_: const Context&) -> bool {
    return self_.active_job != 0 && self_.jobs.items[self_.active_job - 1].hasStaticValues();
}
fn functionCapacity(self_: Context&, function: u32) {
    while self_.function_jobs.len <= function { self_.function_jobs.push(0); }
}
fn hit(self_: Scope&, function: u32) -> Error {
    let context:Context& =requiredContext(self_.context);
    assert(self_.live && context.active_job == self_.id);
    context.functionCapacity(function);
    let target = context.function_jobs.items[function];
    context.appendEvent(Event.hit { self_.id, target, function , ..});
    context.jobs.items[self_.id - 1].function = blot_support::some(function);
    context.jobs.items[self_.id - 1].target_job = target;
    context.jobs.items[self_.id - 1].state = State.hit; return blot_error::Error.none;
}
fn reserve(self_: Scope&, function: u32) -> Error {
    let context:Context& =requiredContext(self_.context);
    assert(self_.live && context.active_job == self_.id);
    context.functionCapacity(function); assert(context.function_jobs.items[function] == 0);
    context.appendEvent(Event.reserve { self_.id, function , ..});
    context.function_jobs.items[function] = self_.id;
    context.jobs.items[self_.id - 1].function = blot_support::some(function);
    context.jobs.items[self_.id - 1].state = State.reserved; return blot_error::Error.none;
}
fn solved(self_: Scope&, mappings: const blot_backend_layout::Mapping[:],
    rows: const blot_backend_layout::RowMapping[:], templates: const blot_reuse_substitution_keys::Entry[:]) -> Error {
    let context:Context& =requiredContext(self_.context);
    assert(self_.live && context.active_job == self_.id);
    let m = Span { context.mappings.len as u32, mappings.len as u32 , ..};
    let r = Span { context.rows.len as u32, rows.len as u32 , ..};
    let t = Span { context.templates.len as u32, templates.len as u32 , ..};
    context.mappings.append(mappings); context.rows.append(rows); context.templates.append(templates);
    context.appendEvent(Event.solved { self_.id , ..});
    context.jobs.items[self_.id - 1].mappings = m; context.jobs.items[self_.id - 1].rows = r;
    context.jobs.items[self_.id - 1].templates = t; context.jobs.items[self_.id - 1].solved = true;
    return blot_error::Error.none;
}
fn complete(self_: Scope&, function: u32, result_template: blot_support::Option<u32>) -> Error {
    let context:Context& =requiredContext(self_.context);
    assert(self_.live && context.active_job == self_.id);
    context.functionCapacity(function); let owner = context.function_jobs.items[function];
    assert(owner == 0 || owner == self_.id);
    context.appendEvent(Event.complete { self_.id, function, result_template , ..});
    context.function_jobs.items[function] = self_.id;
    context.jobs.items[self_.id - 1].function = blot_support::some(function);
    context.jobs.items[self_.id - 1].result_template = result_template;
    context.jobs.items[self_.id - 1].state = State.complete; return blot_error::Error.none;
}
fn completeValue(self_: Scope&, value: u32, shape: u32) -> Error {
    let context:Context& =requiredContext(self_.context);
    assert(self_.live && context.active_job == self_.id);
    let result = ValueResult { value, shape , ..};
    context.appendEvent(Event.complete_value { self_.id, result , ..});
    context.jobs.items[self_.id - 1].value = blot_support::some(result);
    context.jobs.items[self_.id - 1].state = State.complete; return blot_error::Error.none;
}
fn completeGlobal(self_: Scope&, global: u32) -> Error {
    let context:Context& =requiredContext(self_.context);
    assert(self_.live && context.active_job == self_.id);
    while context.global_jobs.len <= global { context.global_jobs.push(0); }
    assert(context.global_jobs.items[global] == 0);
    context.appendEvent(Event.complete_global { self_.id, global , ..});
    context.global_jobs.items[global] = self_.id;
    context.jobs.items[self_.id - 1].global = blot_support::some(global);
    context.jobs.items[self_.id - 1].state = State.complete; return blot_error::Error.none;
}
fn hitGlobal(self_: Scope&, global: u32) -> Error {
    let context:Context& =requiredContext(self_.context);
    assert(self_.live && context.active_job == self_.id);
    var target: u32 = 0; if global < context.global_jobs.len { target = context.global_jobs.items[global]; }
    context.appendEvent(Event.hit_global { self_.id, target, global , ..});
    context.jobs.items[self_.id - 1].global = blot_support::some(global);
    context.jobs.items[self_.id - 1].target_job = target;
    context.jobs.items[self_.id - 1].state = State.hit; return blot_error::Error.none;
}
fn deinit(self_: Scope&) {
    let context:Context& =requiredContext(self_.context);
    assert(self_.live && context.active_job == self_.id);
    let state = context.jobs.items[self_.id - 1].state;
    if state == State.pending || state == State.reserved { context.jobs.items[self_.id - 1].state = State.failed; }
    context.appendEvent(Event.leave { self_.id, self_.parent , ..});
    context.active_job = self_.parent; self_.live = false;
}

let stamp_buffer_bytes: i64 = 4096;
struct StampCounts {
    stamps: i64 = 0, bytes: i64 = 0, input_updates: i64 = 0,
    hash_updates: i64 = 0, buffer_flushes: i64 = 0, direct_chunks: i64 = 0,
}
fn delta(after: StampCounts, before: StampCounts) -> StampCounts {
    return StampCounts { after.stamps - before.stamps, after.bytes - before.bytes,
        after.input_updates - before.input_updates, after.hash_updates - before.hash_updates,
        after.buffer_flushes - before.buffer_flushes, after.direct_chunks - before.direct_chunks , ..};
}
enum StampAlgorithm { buffered, reference }
struct Stamping { algorithm: StampAlgorithm = StampAlgorithm.buffered, counts: StampCounts? = null }
struct StampHash {
    hash: blot_support_blake3::State, bytes: u8[4096], len: i64 = 0,
    buffered: bool, counts: StampCounts = StampCounts {..},
}
fn flush(self_: StampHash&) {
    if self_.len == 0 { return; }
    self_.hash.update(self_.bytes[..self_.len]); self_.counts.hash_updates++;
    self_.counts.buffer_flushes++; self_.len = 0;
}
fn update(self_: StampHash&, source: const u8[:]) {
    self_.counts.input_updates++; self_.counts.bytes += source.len;
    if !self_.buffered { self_.hash.update(source); self_.counts.hash_updates++; return; }
    if source.len >= stamp_buffer_bytes {
        self_.flush(); self_.hash.update(source); self_.counts.hash_updates++; self_.counts.direct_chunks++; return;
    }
    var at: i64 = 0;
    while at < source.len {
        var take = stamp_buffer_bytes - self_.len;
        if take > source.len - at { take = source.len - at; }
        for index in take { self_.bytes[self_.len + index] = source[at + index]; }
        self_.len += take; at += take; if self_.len == stamp_buffer_bytes { self_.flush(); }
    }
}
fn stamp<T>(options: Stamping, value: T) -> u8[32] {
    var hash = StampHash { hash: blot_support_blake3::init(), buffered: options.algorithm == StampAlgorithm.buffered , ..};
    hash.update("BLOT-PINNED-ARTIFACT-1"); blot_structural::hash(hash, value); hash.flush();
    hash.counts.stamps = 1;
    { let optional_source_16 .= options.counts; if optional_source_16 { let counts .= optional_source_16;
        counts.stamps += hash.counts.stamps; counts.bytes += hash.counts.bytes;
        counts.input_updates += hash.counts.input_updates; counts.hash_updates += hash.counts.hash_updates;
        counts.buffer_flushes += hash.counts.buffer_flushes; counts.direct_chunks += hash.counts.direct_chunks;
     } }
    return hash.hash.final();
}
fn stamp<T>(value: T) -> u8[32] { stamp(Stamping {..}, value) }
fn stampBuffered<T>(value: T) -> u8[32] { stamp(Stamping { algorithm: StampAlgorithm.buffered , ..}, value) }
fn stampReference<T>(value: T) -> u8[32] { stamp(Stamping { algorithm: StampAlgorithm.reference , ..}, value) }

// Goose composite equality compares slice members by buffer identity. Keeping
// the fixed header itself gives an exact boundary comparison; no address hash
// or lossy process-local pointer conversion is necessary.
fn headerPrint(module: const blot_check_core::Module&) -> blot_check_core::StampView {
    return blot_check_core::stampView(module);
}
fn sameStorage(left: blot_check_core::Module, right: blot_check_core::Module) -> bool {
    return headerPrint(left) == headerPrint(right);
}
struct CompareStream { bytes: u8[>..<]&, compare: bool = false, at: i64 = 0, same: bool = true }
fn update(self_: CompareStream&, bytes: const u8[:]) {
    if !self_.compare { self_.bytes.append(bytes); return; }
    if self_.at > self_.bytes.len || bytes.len > self_.bytes.len - self_.at { self_.same = false; return; }
    if self_.same { for byte, index in bytes { if byte != self_.bytes[self_.at + index] { self_.same = false; break; } } }
    self_.at += bytes.len;
}
fn sameStampValue<T>(left: T, right: T) -> bool {
    var bytes: u8[>..<] = []; var sink = CompareStream { bytes: bytes , ..};
    blot_structural::hash(sink, left); sink.compare = true;
    blot_structural::hash(sink, right); return sink.same && sink.at == bytes.len;
}
fn sameStampValue(left: blot_check_core::Module, right: blot_check_core::Module) -> bool {
    return sameStampValue(blot_check_core::stampView(left), blot_check_core::stampView(right));
}
fn stamp(module: blot_check_core::Module) -> u8[32] { stamp(blot_check_core::stampView(module)) }
var inactive_pin_module: blot_check_core::Module = blot_check_core::Module {..};
struct ModulePin {
    unit: u32, module: const blot_check_core::Module& = inactive_pin_module, canonical_path: const u8[:], token: Token,
    header: blot_check_core::StampView, stamp: blot_support::Option<u8[32]>,
}
fn init(unit: u32, module: const blot_check_core::Module&, path: const u8[:]) -> ModulePin {
    return ModulePin { unit: unit, module: module, canonical_path: path, token: freshToken(), header: headerPrint(module) , ..};
}
fn validated(unit: u32, module: const blot_check_core::Module&, path: const u8[:]) -> ModulePin {
    var pin = init(unit, module, path); pin.stamp = blot_support::some(stamp(module)); return pin;
}
struct ModuleStampEntry {
    module: blot_check_core::Module, token: Token, digest: blot_support::Option<u8[32]>,
}
struct ModuleStamps {
    current: const blot_check_core::Module[:], previous: const Pools? = null,
    compare_contents: bool = false, validate: bool = false,
    computed: i64 = 0, reused: i64 = 0,
    comparisons: i64 = 0, copied: i64 = 0, hashed: i64 = 0,
    // Header snapshots borrow this invocation's current/previous Core owners.
    entries: blot_support_pooled_buffer::Buffer<ModuleStampEntry> =blot_support_pooled_buffer::Buffer<ModuleStampEntry>{..},
}
reusable[] var module_stamp_entries:ModuleStampEntry[>..]=[];
fn deinit(self_:ModuleStamps&) {blot_support_pooled_buffer::deinit(self_.entries,module_stamp_entries);}
fn ownedModule(self_:const ModuleStamps&,module:const blot_check_core::Module&)->const blot_check_core::Module? {
 for &candidate in self_.current {if candidate .== module {return candidate;}}
 let old .= self_.previous;if old {if module.unit!=0 && module.unit<=old.modules.len && old.modules[module.unit-1].module .== module {return old.modules[module.unit-1].module;}for pin in old.modules {if pin.module .== module {return pin.module;}}}
 return null;
}
fn owns(self_:const ModuleStamps&,module:const blot_check_core::Module&)->bool {return ownedModule(self_,module)!=null;}

fn find(self_: const ModuleStamps&, module: blot_check_core::Module) -> blot_support::Option<i64> {
    for entry, index in self_.entries.items {
        if entry.module.unit == module.unit && sameStorage(entry.module, module) { return blot_support::some(index); }
    }
    return blot_support::none<i64>();
}
fn record(self_: ModuleStamps&, requested: const blot_check_core::Module&, token: Token,
    digest: blot_support::Option<u8[32]>) -> i64, Error {
    let module .= ownedModule(self_,requested);assert(module);
    var known = digest;
    if self_.validate && !known.present { known = blot_support::some(stamp(module)); self_.hashed++; }
    let index=self_.entries.items.len;let error=blot_support_pooled_buffer::ensure(self_.entries,index+1,module_stamp_entries);if error!=blot_error::Error.none {return 0,error;}
    let storage=module_stamp_entries.realloc_slice(self_.entries.storage,self_.entries.storage.len);storage[index]=ModuleStampEntry{module,token,known,..};self_.entries.storage=storage;self_.entries.items=storage[..index+1];
    return index,blot_error::Error.none;
}
fn proveSame(self_: ModuleStamps&, left: const blot_check_core::Module&, right: const blot_check_core::Module&) -> bool, Error {
    if !self_.compare_contents || !self_.owns(left) || !self_.owns(right) { return false, blot_error::Error.none; }
    let known = self_.find(left); if !known.present { return false, blot_error::Error.none; }
    let entry = self_.entries.items[known.value]; if sameStorage(left, right) { return true, blot_error::Error.none; }
    self_.comparisons++; if !sameStampValue(left, right) { return false, blot_error::Error.none; }
    let index, error = self_.record(right, entry.token, entry.digest); if error != blot_error::Error.none { return false, error; }
    self_.reused++; self_.copied++; return true, blot_error::Error.none;
}
fn tokenEntry(self_: ModuleStamps&, module: const blot_check_core::Module&) -> blot_support::Option<i64>, Error {
    if !self_.owns(module) { return blot_support::none<i64>(), blot_error::Error.none; }
    let found = self_.find(module); if found.present { self_.reused++; return found, blot_error::Error.none; }
    { let optional_source_14 .= self_.previous; if optional_source_14 { let old .= optional_source_14;
        for pin in old.modules {
            if pin.module.unit != module.unit || !sameStorage(pin.module, module) || headerPrint(pin.module) != pin.header { continue; }
            self_.reused++; let index, error = self_.record(module, pin.token, blot_support::none<u8[32]>());
            return blot_support::some(index), error;
        }
     } }
    if self_.compare_contents {
        let count = self_.entries.items.len;
        for index in count {
            let known = self_.entries.items[index]; if known.module.unit != module.unit { continue; }
            self_.comparisons++; if !sameStampValue(known.module, module) { continue; }
            self_.reused++; self_.copied++; let id, error = self_.record(module, known.token, known.digest);
            return blot_support::some(id), error;
        }
    }
    self_.computed++; let index, error = self_.record(module, freshToken(), blot_support::none<u8[32]>());
    return blot_support::some(index), error;
}
fn get(self_: ModuleStamps&, module: const blot_check_core::Module&) -> Token, Error {
    let known, error = self_.tokenEntry(module); if error != blot_error::Error.none { return 0, error; }
    if !known.present { return freshToken(), blot_error::Error.none; }
    return self_.entries.items[known.value].token, blot_error::Error.none;
}
fn intact(self_: ModuleStamps&, pin: const ModulePin&) -> bool, Error {
    if headerPrint(pin.module) != pin.header { return false, blot_error::Error.none; }
    let known, error = self_.tokenEntry(pin.module); if error != blot_error::Error.none { return false, error; }
    if !known.present { return pinIntact(pin, null); }
    if self_.entries.items[known.value].token != pin.token { return false, blot_error::Error.none; }
    if !pin.stamp.present { return true, blot_error::Error.none; }
    if !self_.entries.items[known.value].digest.present {
        self_.entries.items[known.value].digest = blot_support::some(stamp(self_.entries.items[known.value].module)); self_.hashed++;
    }
    return pin.stamp.value == self_.entries.items[known.value].digest.value, blot_error::Error.none;
}
fn digestOf(self_: ModuleStamps&, module: const blot_check_core::Module&) -> blot_support::Option<u8[32]>, Error {
    if !self_.validate { return blot_support::none<u8[32]>(), blot_error::Error.none; }
    let known, error = self_.tokenEntry(module); if error != blot_error::Error.none { return blot_support::none<u8[32]>(), error; }
    if !known.present { return blot_support::some(stamp(module)), blot_error::Error.none; }
    return self_.entries.items[known.value].digest, blot_error::Error.none;
}
recursive fn pinIntact(pin: const ModulePin&, memo: ModuleStamps? = null) -> bool, Error {
    { let optional_source_13 .= memo; if optional_source_13 { let tokens .= optional_source_13; if tokens.owns(pin.module) { return tokens.intact(pin); }  } }
    if headerPrint(pin.module) != pin.header { return false, blot_error::Error.none; }
    if !pin.stamp.present { return true, blot_error::Error.none; }
    return pin.stamp.value == stamp(pin.module), blot_error::Error.none;
}

struct IdentityMetadata { bytes: const u8[:], symbols: const blot_backend_runtime_identity::Name[:], owners: const blot_backend_runtime_identity::Name[:] }
fn view(self_: IdentityMetadata) -> blot_backend_runtime_identity::View {
    return blot_backend_runtime_identity::View { self_.bytes, self_.symbols, self_.owners , ..};
}
struct Substitutions { entries: const blot_reuse_substitution_keys::Entry[:] = default<const blot_reuse_substitution_keys::Entry[:]>(), spans: const Span[:] = default<const Span[:]>() }
fn get(self_: const Substitutions&, id: u32) -> const blot_reuse_substitution_keys::Entry[:] {
    if id == 0 { return default<const blot_reuse_substitution_keys::Entry[:]>(); } let span = self_.spans[id - 1]; return self_.entries[span.start..span.start + span.len];
}
struct Layouts {
    nodes: const blot_backend_layout::Node[:], extra: const u32[:],
    effects: blot_check_effect_evidence::Snapshot,
    universal_dictionaries: const blot_backend_layout::UniversalDictionaries[:] = default<const blot_backend_layout::UniversalDictionaries[:]>(),
}
fn children(self_: const Layouts&, id: u32) -> const u32[:] {
    let n = self_.nodes[id];
    match n.tag {
        product => { return self_.extra[n.a..n.a + n.b]; },
        record => { return self_.extra[n.a..n.a + n.b * 2]; },
        nominal => { return self_.extra[n.c + 1..n.c + 1 + self_.extra[n.c]]; },
        universal, existential => { return self_.extra[n.c..n.c + n.b]; },
        _ => { return default<const u32[:]>(); },
    }
}
fn dictionaryRecord(self_: const Layouts&, owner: u32) -> blot_support::Option<blot_backend_layout::UniversalDictionaries> {
    var low: i64 = 0; var high = self_.universal_dictionaries.len;
    while low < high {
        let middle = low + (high - low) / 2;
        if self_.universal_dictionaries[middle].owner < owner { low = middle + 1; } else { high = middle; }
    }
    if low == self_.universal_dictionaries.len || self_.universal_dictionaries[low].owner != owner {
        return blot_support::none<blot_backend_layout::UniversalDictionaries>();
    }
    return blot_support::some(self_.universal_dictionaries[low]);
}
fn hasDictionaryABI(self_: const Layouts&, owner: u32) -> bool { self_.dictionaryRecord(owner).present }
fn dictionarySlots(self_: const Layouts&, owner: u32) -> const u32[:] {
    let record = self_.dictionaryRecord(owner); if !record.present { return default<const u32[:]>(); }
    return self_.extra[record.value.start..record.value.start + record.value.len];
}
struct Bridge {
    nodes: const blot_reuse_code_expectation::Node[:], extra: const u32[:], to: const u32[:], from: const u32[:],
    row_to: const u32[:], row_from: const u32[:], shapes: const u32[:],
}
struct Pools {
    project_identity: bool, generation: u64 = 0,
    identity: blot_support::Option<IdentityMetadata>, modules: const ModulePin[:],
    dependency_certificate: blot_support::Option<blot_reuse_dependency_certificate::Certificate>,
    leases: blot_eval_pool_leases::Leases = blot_eval_pool_leases::none,
    layouts: Layouts, evaluator: blot_eval_core_eval::Snapshot,
    constant_records: const blot_reuse_constant_receipt::Record[:],
    rows: Substitutions, templates: Substitutions, static_values: Substitutions,
    instance_arguments: blot_eval_instance_arguments::Owned,
    captures: const CapturedTemplate[:], bridge: blot_support::Option<Bridge>,
    field_locations: const FieldLocation[:], field_locations_stamp: u8[32],
    operations: const Operation[:], operation_relocations: const OperationRelocation[:],
    operations_finalized: bool, functions: const Function[:], serialized: const Serialized[:],
    runtime_globals: const RuntimeGlobal[:], runtime_order: const u32[:],
    binding_offsets: const i64[:], node_offsets: const i64[:], slots: const Slot[:], visited_nodes: const bool[:],
    provider_frames: const blot_backend_provider_chain::Frame[:], provider_cells: const blot_backend_provider_chain::Cell[:],
    request_cells: const RequestCell[:], request_handlers: const RequestHandler[:], break_values: const u32[:],
    array_proofs: const ArrayProof[:], discard_proofs: const DiscardProof[:],
    evaluator_steps: i64, evaluator_demanded: i64, evaluator_traced_bodies: i64, evaluator_traced_nodes: i64,
}

// Concrete typed reusable runs own nonshared metadata. No raw heap casts.
reusable[] var owned_bytes: u8[>..] = [];
fn allocateOwned_bytes(len: i64) -> u8[:] { return owned_bytes.alloc_slice(len); }
fn copyOwned(source: const u8[:]) -> const u8[:] {
    if source.len == 0 { return default<const u8[:]>(); }
    let out = owned_bytes.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const u8[:]) {
    if source.len == 0 { return; }
    owned_bytes.free_slice(source);
}
reusable[] var owned_words: u32[>..] = [];
fn allocateOwned_words(len: i64) -> u32[:] { return owned_words.alloc_slice(len); }
fn copyOwned(source: const u32[:]) -> const u32[:] {
    if source.len == 0 { return default<const u32[:]>(); }
    let out = owned_words.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const u32[:]) {
    if source.len == 0 { return; }
    owned_words.free_slice(source);
}
reusable[] var owned_sizes: i64[>..] = [];
fn allocateOwned_sizes(len: i64) -> i64[:] { return owned_sizes.alloc_slice(len); }
fn copyOwned(source: const i64[:]) -> const i64[:] {
    if source.len == 0 { return default<const i64[:]>(); }
    let out = owned_sizes.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const i64[:]) {
    if source.len == 0 { return; }
    owned_sizes.free_slice(source);
}
reusable[] var owned_bits: bool[>..] = [];
fn allocateOwned_bits(len: i64) -> bool[:] { return owned_bits.alloc_slice(len); }
fn copyOwned(source: const bool[:]) -> const bool[:] {
    if source.len == 0 { return default<const bool[:]>(); }
    let out = owned_bits.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const bool[:]) {
    if source.len == 0 { return; }
    owned_bits.free_slice(source);
}
reusable[] var owned_pins: ModulePin[>..] = [];
fn allocateOwned_pins(len: i64) -> ModulePin[:] { return owned_pins.alloc_slice(len); }
fn copyOwned(source: const ModulePin[:]) -> const ModulePin[:] {
    if source.len == 0 { return default<const ModulePin[:]>(); }
    let out = owned_pins.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const ModulePin[:]) {
    if source.len == 0 { return; }
    owned_pins.free_slice(source);
}
// Retarget uniquely owned pin records after the publication owner copied every
// immutable Core header and retained its actual payload journal. No proof grows.
fn rebindModuleHeaders(pools:Pools&,headers:const blot_check_core::Module[:])->Error {
 if pools.modules.len!=headers.len {return blot_error::Error.invalid_artifact;}
 for pin,index in pools.modules {let header=headers[index];var unit=header.unit;if unit==0 {unit=(index+1) as u32;}if pin.unit!=unit || pin.header!=headerPrint(header) || !sameStorage(pin.module,header) {return blot_error::Error.invalid_artifact;}}
 if pools.modules.len==0 {return blot_error::Error.none;}
 let pins=owned_pins.realloc_slice(pools.modules,pools.modules.len);
 for index in headers.len {pins[index].module .= headers[index];}return blot_error::Error.none;
}
reusable[] var owned_spans: Span[>..] = [];
fn allocateOwned_spans(len: i64) -> Span[:] { return owned_spans.alloc_slice(len); }
fn copyOwned(source: const Span[:]) -> const Span[:] {
    if source.len == 0 { return default<const Span[:]>(); }
    let out = owned_spans.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const Span[:]) {
    if source.len == 0 { return; }
    owned_spans.free_slice(source);
}
reusable[] var owned_entries: blot_reuse_substitution_keys::Entry[>..] = [];
fn allocateOwned_entries(len: i64) -> blot_reuse_substitution_keys::Entry[:] { return owned_entries.alloc_slice(len); }
fn copyOwned(source: const blot_reuse_substitution_keys::Entry[:]) -> const blot_reuse_substitution_keys::Entry[:] {
    if source.len == 0 { return default<const blot_reuse_substitution_keys::Entry[:]>(); }
    let out = owned_entries.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const blot_reuse_substitution_keys::Entry[:]) {
    if source.len == 0 { return; }
    owned_entries.free_slice(source);
}
reusable[] var owned_nodes: blot_eval_type_evidence::Node[>..] = [];
fn allocateOwned_nodes(len: i64) -> blot_eval_type_evidence::Node[:] { return owned_nodes.alloc_slice(len); }
fn copyOwned(source: const blot_eval_type_evidence::Node[:]) -> const blot_eval_type_evidence::Node[:] {
    if source.len == 0 { return default<const blot_eval_type_evidence::Node[:]>(); }
    let out = owned_nodes.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const blot_eval_type_evidence::Node[:]) {
    if source.len == 0 { return; }
    owned_nodes.free_slice(source);
}
reusable[] var owned_instances: blot_check_types::NominalIdentity[>..] = [];
fn allocateOwned_instances(len: i64) -> blot_check_types::NominalIdentity[:] { return owned_instances.alloc_slice(len); }
fn copyOwned(source: const blot_check_types::NominalIdentity[:]) -> const blot_check_types::NominalIdentity[:] {
    if source.len == 0 { return default<const blot_check_types::NominalIdentity[:]>(); }
    let out = owned_instances.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const blot_check_types::NominalIdentity[:]) {
    if source.len == 0 { return; }
    owned_instances.free_slice(source);
}
reusable[] var owned_instance_spans: blot_eval_instance_arguments::Span[>..] = [];
fn allocateOwned_instance_spans(len: i64) -> blot_eval_instance_arguments::Span[:] { return owned_instance_spans.alloc_slice(len); }
fn copyOwned(source: const blot_eval_instance_arguments::Span[:]) -> const blot_eval_instance_arguments::Span[:] {
    if source.len == 0 { return default<const blot_eval_instance_arguments::Span[:]>(); }
    let out = owned_instance_spans.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const blot_eval_instance_arguments::Span[:]) {
    if source.len == 0 { return; }
    owned_instance_spans.free_slice(source);
}
reusable[] var owned_operations: Operation[>..] = [];
fn allocateOwned_operations(len: i64) -> Operation[:] { return owned_operations.alloc_slice(len); }
fn copyOwned(source: const Operation[:]) -> const Operation[:] {
    if source.len == 0 { return default<const Operation[:]>(); }
    let out = owned_operations.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const Operation[:]) {
    if source.len == 0 { return; }
    owned_operations.free_slice(source);
}
reusable[] var owned_arrays: ArrayProof[>..] = [];
fn allocateOwned_arrays(len: i64) -> ArrayProof[:] { return owned_arrays.alloc_slice(len); }
fn copyOwned(source: const ArrayProof[:]) -> const ArrayProof[:] {
    if source.len == 0 { return default<const ArrayProof[:]>(); }
    let out = owned_arrays.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const ArrayProof[:]) {
    if source.len == 0 { return; }
    owned_arrays.free_slice(source);
}
reusable[] var owned_discards: DiscardProof[>..] = [];
fn allocateOwned_discards(len: i64) -> DiscardProof[:] { return owned_discards.alloc_slice(len); }
fn copyOwned(source: const DiscardProof[:]) -> const DiscardProof[:] {
    if source.len == 0 { return default<const DiscardProof[:]>(); }
    let out = owned_discards.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const DiscardProof[:]) {
    if source.len == 0 { return; }
    owned_discards.free_slice(source);
}
reusable[] var owned_constants: blot_reuse_constant_receipt::Record[>..] = [];
fn allocateOwned_constants(len: i64) -> blot_reuse_constant_receipt::Record[:] { return owned_constants.alloc_slice(len); }
fn copyOwned(source: const blot_reuse_constant_receipt::Record[:]) -> const blot_reuse_constant_receipt::Record[:] {
    if source.len == 0 { return default<const blot_reuse_constant_receipt::Record[:]>(); }
    let out = owned_constants.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const blot_reuse_constant_receipt::Record[:]) {
    if source.len == 0 { return; }
    owned_constants.free_slice(source);
}

fn capture(store: const blot_reuse_substitution_keys::Store&) -> Substitutions {
    let entries = copyOwned(store.entries);
    let spans = allocateOwned_spans(store.spans.len);
    for from, index in store.spans { spans[index] = Span { from.start, from.len , ..}; }
    return Substitutions { entries, spans , ..};
}
fn deinit(self_: Substitutions&) { releaseOwned(self_.entries); releaseOwned(self_.spans); self_ = Substitutions {..}; }
fn captureBridge<C>(store: const C&) -> Bridge {
    return Bridge { copyOwned(store.partial.nodes.items), copyOwned(store.partial.extra.items),
        copyOwned(store.to), copyOwned(store.from), copyOwned(store.row_to), copyOwned(store.row_from), copyOwned(store.shapes) , ..};
}
fn deinit(self_: Bridge&) {
    releaseOwned(self_.nodes); releaseOwned(self_.extra); releaseOwned(self_.to); releaseOwned(self_.from);
    releaseOwned(self_.row_to); releaseOwned(self_.row_from); releaseOwned(self_.shapes);
}
struct CaptureState { shared: blot_eval_pool_leases::Builder, failure: Error = blot_error::Error.none }
fn capture_identity_bytes(self_: CaptureState&, source: const u8[:], previous: const u8[:]) -> const u8[:] {
    if self_.failure != blot_error::Error.none { return default<const u8[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_identity_bytes(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_identity_symbols(self_: CaptureState&, source: const blot_backend_runtime_identity::Name[:], previous: const blot_backend_runtime_identity::Name[:]) -> const blot_backend_runtime_identity::Name[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_backend_runtime_identity::Name[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_identity_symbols(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_identity_owners(self_: CaptureState&, source: const blot_backend_runtime_identity::Name[:], previous: const blot_backend_runtime_identity::Name[:]) -> const blot_backend_runtime_identity::Name[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_backend_runtime_identity::Name[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_identity_owners(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_layout_nodes(self_: CaptureState&, source: const blot_backend_layout::Node[:], previous: const blot_backend_layout::Node[:]) -> const blot_backend_layout::Node[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_backend_layout::Node[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_layout_nodes(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_layout_extra(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_layout_extra(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_layout_universal_dictionaries(self_: CaptureState&, source: const blot_backend_layout::UniversalDictionaries[:], previous: const blot_backend_layout::UniversalDictionaries[:]) -> const blot_backend_layout::UniversalDictionaries[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_backend_layout::UniversalDictionaries[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_layout_universal_dictionaries(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_layout_operations(self_: CaptureState&, source: const blot_check_effect_evidence::Operation[:], previous: const blot_check_effect_evidence::Operation[:]) -> const blot_check_effect_evidence::Operation[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_check_effect_evidence::Operation[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_layout_operations(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_layout_arguments(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_layout_arguments(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_layout_rows(self_: CaptureState&, source: const blot_check_effect_evidence::Row[:], previous: const blot_check_effect_evidence::Row[:]) -> const blot_check_effect_evidence::Row[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_check_effect_evidence::Row[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_layout_rows(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_layout_labels(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_layout_labels(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_values(self_: CaptureState&, source: const blot_eval_eval_values::ValueInfo[:], previous: const blot_eval_eval_values::ValueInfo[:]) -> const blot_eval_eval_values::ValueInfo[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_eval_eval_values::ValueInfo[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_values(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_children(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_children(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_closures(self_: CaptureState&, source: const blot_eval_eval_values::ClosureValue[:], previous: const blot_eval_eval_values::ClosureValue[:]) -> const blot_eval_eval_values::ClosureValue[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_eval_eval_values::ClosureValue[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_closures(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_value_evidence(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_value_evidence(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_type_mappings(self_: CaptureState&, source: const blot_eval_type_evidence::Mapping[:], previous: const blot_eval_type_evidence::Mapping[:]) -> const blot_eval_type_evidence::Mapping[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_eval_type_evidence::Mapping[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_type_mappings(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_row_mappings(self_: CaptureState&, source: const blot_eval_type_evidence::RowMapping[:], previous: const blot_eval_type_evidence::RowMapping[:]) -> const blot_eval_type_evidence::RowMapping[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_eval_type_evidence::RowMapping[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_row_mappings(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_evidence_nodes(self_: CaptureState&, source: const blot_eval_type_evidence::Node[:], previous: const blot_eval_type_evidence::Node[:]) -> const blot_eval_type_evidence::Node[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_eval_type_evidence::Node[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_evidence_nodes(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_evidence_extra(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_evidence_extra(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_evidence_quantifier_goals(self_: CaptureState&, source: const blot_eval_type_evidence::QuantifierGoals[:], previous: const blot_eval_type_evidence::QuantifierGoals[:]) -> const blot_eval_type_evidence::QuantifierGoals[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_eval_type_evidence::QuantifierGoals[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_evidence_quantifier_goals(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_evidence_quantifier_obligations(self_: CaptureState&, source: const blot_eval_type_evidence::Goal[:], previous: const blot_eval_type_evidence::Goal[:]) -> const blot_eval_type_evidence::Goal[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_eval_type_evidence::Goal[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_evidence_quantifier_obligations(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_evidence_operations(self_: CaptureState&, source: const blot_check_effect_evidence::Operation[:], previous: const blot_check_effect_evidence::Operation[:]) -> const blot_check_effect_evidence::Operation[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_check_effect_evidence::Operation[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_evidence_operations(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_evidence_arguments(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_evidence_arguments(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_evidence_rows(self_: CaptureState&, source: const blot_check_effect_evidence::Row[:], previous: const blot_check_effect_evidence::Row[:]) -> const blot_check_effect_evidence::Row[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_check_effect_evidence::Row[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_evidence_rows(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_evidence_labels(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_evidence_labels(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_value_records(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_value_records(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_record_layouts(self_: CaptureState&, source: const blot_check_core::List[:], previous: const blot_check_core::List[:]) -> const blot_check_core::List[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_check_core::List[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_record_layouts(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_field_names(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_field_names(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_implementation_proofs(self_: CaptureState&, source: const blot_eval_implementation_evidence::Proof[:], previous: const blot_eval_implementation_evidence::Proof[:]) -> const blot_eval_implementation_evidence::Proof[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_eval_implementation_evidence::Proof[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_implementation_proofs(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_implementation_arguments(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_implementation_arguments(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_implementation_members(self_: CaptureState&, source: const blot_eval_implementation_evidence::Member[:], previous: const blot_eval_implementation_evidence::Member[:]) -> const blot_eval_implementation_evidence::Member[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_eval_implementation_evidence::Member[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_implementation_members(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_implementation_edges(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_implementation_edges(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_captures(self_: CaptureState&, source: const blot_reuse_code_artifacts::CapturedTemplate[:], previous: const blot_reuse_code_artifacts::CapturedTemplate[:]) -> const blot_reuse_code_artifacts::CapturedTemplate[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_reuse_code_artifacts::CapturedTemplate[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_captures(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_field_locations(self_: CaptureState&, source: const blot_reuse_code_artifacts::FieldLocation[:], previous: const blot_reuse_code_artifacts::FieldLocation[:]) -> const blot_reuse_code_artifacts::FieldLocation[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_reuse_code_artifacts::FieldLocation[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_field_locations(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_functions(self_: CaptureState&, source: const blot_reuse_code_artifacts::Function[:], previous: const blot_reuse_code_artifacts::Function[:]) -> const blot_reuse_code_artifacts::Function[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_reuse_code_artifacts::Function[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_functions(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_serialized(self_: CaptureState&, source: const blot_reuse_code_artifacts::Serialized[:], previous: const blot_reuse_code_artifacts::Serialized[:]) -> const blot_reuse_code_artifacts::Serialized[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_reuse_code_artifacts::Serialized[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_serialized(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_runtime_globals(self_: CaptureState&, source: const blot_reuse_code_artifacts::RuntimeGlobal[:], previous: const blot_reuse_code_artifacts::RuntimeGlobal[:]) -> const blot_reuse_code_artifacts::RuntimeGlobal[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_reuse_code_artifacts::RuntimeGlobal[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_runtime_globals(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_runtime_order(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_runtime_order(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_binding_offsets(self_: CaptureState&, source: const i64[:], previous: const i64[:]) -> const i64[:] {
    if self_.failure != blot_error::Error.none { return default<const i64[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_binding_offsets(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_node_offsets(self_: CaptureState&, source: const i64[:], previous: const i64[:]) -> const i64[:] {
    if self_.failure != blot_error::Error.none { return default<const i64[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_node_offsets(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_slots(self_: CaptureState&, source: const blot_reuse_code_artifacts::Slot[:], previous: const blot_reuse_code_artifacts::Slot[:]) -> const blot_reuse_code_artifacts::Slot[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_reuse_code_artifacts::Slot[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_slots(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_visited_nodes(self_: CaptureState&, source: const bool[:], previous: const bool[:]) -> const bool[:] {
    if self_.failure != blot_error::Error.none { return default<const bool[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_visited_nodes(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_provider_frames(self_: CaptureState&, source: const blot_backend_provider_chain::Frame[:], previous: const blot_backend_provider_chain::Frame[:]) -> const blot_backend_provider_chain::Frame[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_backend_provider_chain::Frame[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_provider_frames(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_provider_cells(self_: CaptureState&, source: const blot_backend_provider_chain::Cell[:], previous: const blot_backend_provider_chain::Cell[:]) -> const blot_backend_provider_chain::Cell[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_backend_provider_chain::Cell[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_provider_cells(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_request_cells(self_: CaptureState&, source: const blot_reuse_code_artifacts::RequestCell[:], previous: const blot_reuse_code_artifacts::RequestCell[:]) -> const blot_reuse_code_artifacts::RequestCell[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_reuse_code_artifacts::RequestCell[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_request_cells(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_request_handlers(self_: CaptureState&, source: const blot_reuse_code_artifacts::RequestHandler[:], previous: const blot_reuse_code_artifacts::RequestHandler[:]) -> const blot_reuse_code_artifacts::RequestHandler[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_reuse_code_artifacts::RequestHandler[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_request_handlers(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_break_values(self_: CaptureState&, source: const u32[:], previous: const u32[:]) -> const u32[:] {
    if self_.failure != blot_error::Error.none { return default<const u32[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_break_values(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_operation_relocations(self_: CaptureState&, source: const blot_reuse_code_artifacts::OperationRelocation[:], previous: const blot_reuse_code_artifacts::OperationRelocation[:]) -> const blot_reuse_code_artifacts::OperationRelocation[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_reuse_code_artifacts::OperationRelocation[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_operation_relocations(self_.shared, source, previous);
    self_.failure = error; return result;
}
fn capture_code_origins(self_: CaptureState&, source: const blot_check_staging_origins::Record[:], previous: const blot_check_staging_origins::Record[:]) -> const blot_check_staging_origins::Record[:] {
    if self_.failure != blot_error::Error.none { return default<const blot_check_staging_origins::Record[:]>(); }
    let result, error = blot_eval_pool_leases::dupe_code_origins(self_.shared, source, previous);
    self_.failure = error; return result;
}

fn deinit(self_: Pools&) {
    for record in self_.constant_records { var owned = record; owned.deinit(); }
    releaseOwned(self_.constant_records);
    if self_.dependency_certificate.present { self_.dependency_certificate.value.deinit(); }
    let leases = self_.leases;
    if self_.identity.present { let error = blot_eval_pool_leases::free_identity_bytes(leases, self_.identity.value.bytes); assert(error == blot_error::Error.none); }
    if self_.identity.present { let error = blot_eval_pool_leases::free_identity_symbols(leases, self_.identity.value.symbols); assert(error == blot_error::Error.none); }
    if self_.identity.present { let error = blot_eval_pool_leases::free_identity_owners(leases, self_.identity.value.owners); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_layout_nodes(leases, self_.layouts.nodes); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_layout_extra(leases, self_.layouts.extra); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_layout_universal_dictionaries(leases, self_.layouts.universal_dictionaries); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_layout_operations(leases, self_.layouts.effects.operations); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_layout_arguments(leases, self_.layouts.effects.arguments); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_layout_rows(leases, self_.layouts.effects.rows); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_layout_labels(leases, self_.layouts.effects.labels); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_values(leases, self_.evaluator.values); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_children(leases, self_.evaluator.children); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_closures(leases, self_.evaluator.closures); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_value_evidence(leases, self_.evaluator.value_evidence); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_type_mappings(leases, self_.evaluator.type_mappings); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_row_mappings(leases, self_.evaluator.row_mappings); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_evidence_nodes(leases, self_.evaluator.evidence.nodes); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_evidence_extra(leases, self_.evaluator.evidence.extra); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_evidence_quantifier_goals(leases, self_.evaluator.evidence.quantifier_goals); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_evidence_quantifier_obligations(leases, self_.evaluator.evidence.quantifier_obligations); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_evidence_operations(leases, self_.evaluator.evidence.effects.operations); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_evidence_arguments(leases, self_.evaluator.evidence.effects.arguments); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_evidence_rows(leases, self_.evaluator.evidence.effects.rows); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_evidence_labels(leases, self_.evaluator.evidence.effects.labels); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_value_records(leases, self_.evaluator.value_records); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_record_layouts(leases, self_.evaluator.record_layouts); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_field_names(leases, self_.evaluator.field_names); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_implementation_proofs(leases, self_.evaluator.implementation_proofs.proofs); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_implementation_arguments(leases, self_.evaluator.implementation_proofs.arguments); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_implementation_members(leases, self_.evaluator.implementation_proofs.members); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_implementation_edges(leases, self_.evaluator.implementation_proofs.edges); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_captures(leases, self_.captures); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_field_locations(leases, self_.field_locations); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_functions(leases, self_.functions); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_serialized(leases, self_.serialized); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_runtime_globals(leases, self_.runtime_globals); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_runtime_order(leases, self_.runtime_order); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_binding_offsets(leases, self_.binding_offsets); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_node_offsets(leases, self_.node_offsets); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_slots(leases, self_.slots); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_visited_nodes(leases, self_.visited_nodes); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_provider_frames(leases, self_.provider_frames); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_provider_cells(leases, self_.provider_cells); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_request_cells(leases, self_.request_cells); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_request_handlers(leases, self_.request_handlers); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_break_values(leases, self_.break_values); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_operation_relocations(leases, self_.operation_relocations); assert(error == blot_error::Error.none); }
    block { let error = blot_eval_pool_leases::free_code_origins(leases, self_.evaluator.code_origins); assert(error == blot_error::Error.none); }
    for pin in self_.modules { releaseOwned(pin.canonical_path); } releaseOwned(self_.modules);
    self_.rows.deinit(); self_.templates.deinit(); self_.static_values.deinit();
    releaseOwned(self_.instance_arguments.values); releaseOwned(self_.instance_arguments.spans);
    if self_.bridge.present { self_.bridge.value.deinit(); }
    for operation in self_.operations { releaseOwned(operation.key); } releaseOwned(self_.operations);
    for proof in self_.array_proofs { releaseOwned(proof.updates); } releaseOwned(self_.array_proofs);
    for proof in self_.discard_proofs { releaseOwned(proof.unused); } releaseOwned(self_.discard_proofs);
    self_ = default<Pools>();
}

fn capture<G>(generator: G&, identity: blot_support::Option<blot_backend_runtime_identity::View>, memo: ModuleStamps? = null) -> Pools, Error {
    var previous: const Pools? = null;
    { let optional_source_12 .= memo; if optional_source_12 { let cache .= optional_source_12; previous = cache.previous;  } }
    var candidate = default<Pools>();
    var copying = CaptureState { shared: blot_eval_pool_leases::Builder {..} , ..};
    { let optional_source_11 .= previous; if optional_source_11 { let old .= optional_source_11; copying.shared.previous = old.leases;  } }
    candidate.project_identity = identity.present;
    if identity.present {
        var old = default<IdentityMetadata>();
        { let optional_source_10 .= previous; if optional_source_10 { let prior .= optional_source_10; if prior.identity.present { old = prior.identity.value; }  } }
        candidate.identity = blot_support::some(IdentityMetadata {
            copying.capture_identity_bytes(identity.value.bytes, old.bytes),
            copying.capture_identity_symbols(identity.value.symbols, old.symbols),
            copying.capture_identity_owners(identity.value.owners, old.owners),
         ..});
    }
    let modules = allocateOwned_pins(generator.units.len);
    for &module, index in generator.units {
        var unit = module.unit; if unit == 0 { unit = (index + 1) as u32; }
        let path=selectedOwnerPath(candidate.identity,unit);
        modules[index] = init(unit, module, copyOwned(path));
    }
    candidate.modules = modules;
    { let optional_source_9 .= memo; if optional_source_9 { let tokens .= optional_source_9;
        for index in modules.len {
            let token, token_error = tokens.get(modules[index].module);
            if token_error != blot_error::Error.none { candidate.leases = copying.shared.leases; candidate.deinit(); return default<Pools>(), token_error; }
            modules[index].token = token;
            let digest, digest_error = tokens.digestOf(modules[index].module);
            if digest_error != blot_error::Error.none { candidate.leases = copying.shared.leases; candidate.deinit(); return default<Pools>(), digest_error; }
            modules[index].stamp = digest;
        }
     } }
    var old_layouts = default<Layouts>();
    var old_evaluator = default<blot_eval_core_eval::Snapshot>();
    var old = default<Pools>();
    { let optional_source_8 .= previous; if optional_source_8 { let prior .= optional_source_8; old = prior; old_layouts = prior.layouts; old_evaluator = prior.evaluator;  } }
    let layout_store = generator.representations.store;
    candidate.layouts.nodes = copying.capture_layout_nodes(layout_store.nodes, old_layouts.nodes);
    candidate.layouts.extra = copying.capture_layout_extra(layout_store.extra, old_layouts.extra);
    candidate.layouts.universal_dictionaries = copying.capture_layout_universal_dictionaries(layout_store.universal_dictionaries, old_layouts.universal_dictionaries);
    candidate.layouts.effects.operations = copying.capture_layout_operations(layout_store.effects.operations.items, old_layouts.effects.operations);
    candidate.layouts.effects.arguments = copying.capture_layout_arguments(layout_store.effects.arguments.items, old_layouts.effects.arguments);
    candidate.layouts.effects.rows = copying.capture_layout_rows(layout_store.effects.rows.items, old_layouts.effects.rows);
    candidate.layouts.effects.labels = copying.capture_layout_labels(layout_store.effects.labels.items, old_layouts.effects.labels);
    candidate.layouts.effects.owner_id = blot_native::fresh_owner_id();
    let before_evaluator = copying.shared.stats;
    let session .= generator.evaluator;
    candidate.evaluator.code_origins = copying.capture_code_origins(session.storage.code_origins, old_evaluator.code_origins);
    candidate.evaluator.values = copying.capture_values(session.storage.values, old_evaluator.values);
    candidate.evaluator.children = copying.capture_children(session.storage.children, old_evaluator.children);
    candidate.evaluator.closures = copying.capture_closures(session.storage.closures, old_evaluator.closures);
    candidate.evaluator.value_evidence = copying.capture_value_evidence(session.storage.value_evidence, old_evaluator.value_evidence);
    candidate.evaluator.type_mappings = copying.capture_type_mappings(session.storage.type_mappings, old_evaluator.type_mappings);
    candidate.evaluator.row_mappings = copying.capture_row_mappings(session.storage.row_mappings, old_evaluator.row_mappings);
    candidate.evaluator.value_records = copying.capture_value_records(session.storage.value_records, old_evaluator.value_records);
    candidate.evaluator.record_layouts = copying.capture_record_layouts(session.storage.record_layouts, old_evaluator.record_layouts);
    candidate.evaluator.field_names = copying.capture_field_names(session.storage.field_names, old_evaluator.field_names);
    candidate.evaluator.implementation_proofs.proofs = copying.capture_implementation_proofs(session.implementation_proofs.proofs, old_evaluator.implementation_proofs.proofs);
    candidate.evaluator.implementation_proofs.arguments = copying.capture_implementation_arguments(session.implementation_proofs.arguments, old_evaluator.implementation_proofs.arguments);
    candidate.evaluator.implementation_proofs.members = copying.capture_implementation_members(session.implementation_proofs.members, old_evaluator.implementation_proofs.members);
    candidate.evaluator.implementation_proofs.edges = copying.capture_implementation_edges(session.implementation_proofs.edges, old_evaluator.implementation_proofs.edges);
    candidate.evaluator.evidence.nodes = copying.capture_evidence_nodes(session.storage.evidence.nodes.items, old_evaluator.evidence.nodes);
    candidate.evaluator.evidence.extra = copying.capture_evidence_extra(session.storage.evidence.extra.items, old_evaluator.evidence.extra);
    candidate.evaluator.evidence.quantifier_goals = copying.capture_evidence_quantifier_goals(session.storage.evidence.quantifier_goals.items, old_evaluator.evidence.quantifier_goals);
    candidate.evaluator.evidence.quantifier_obligations = copying.capture_evidence_quantifier_obligations(session.storage.evidence.quantifier_obligations.items, old_evaluator.evidence.quantifier_obligations);
    candidate.evaluator.evidence.effects.operations = copying.capture_evidence_operations(session.storage.evidence.effects.operations.items, old_evaluator.evidence.effects.operations);
    candidate.evaluator.evidence.effects.arguments = copying.capture_evidence_arguments(session.storage.evidence.effects.arguments.items, old_evaluator.evidence.effects.arguments);
    candidate.evaluator.evidence.effects.rows = copying.capture_evidence_rows(session.storage.evidence.effects.rows.items, old_evaluator.evidence.effects.rows);
    candidate.evaluator.evidence.effects.labels = copying.capture_evidence_labels(session.storage.evidence.effects.labels.items, old_evaluator.evidence.effects.labels);
    candidate.evaluator.evidence.effects.owner_id = blot_native::fresh_owner_id();
    session.counters.snapshot_copy_bytes += copying.shared.stats.copied_bytes - before_evaluator.copied_bytes;
    session.counters.snapshot_copy_allocations += copying.shared.stats.copied_fields - before_evaluator.copied_fields;
    // Every nested receipt is cloned before its record array is published.
    var constants: blot_reuse_constant_receipt::Record[>..<] = [];
    for record in session.retained.constant_records {
        let owned, error = record.clone();
        if error != blot_error::Error.none {
            for &prior in constants { prior.deinit(); }
            candidate.leases = copying.shared.leases; candidate.deinit(); return default<Pools>(), error;
        }
        constants.push(owned);
    }
    candidate.constant_records = copyOwned(constants);
    candidate.rows = capture(generator.representations.row_keys);
    candidate.templates = capture(generator.representations.template_keys);
    candidate.static_values = capture(generator.representations.static_keys);
    candidate.instance_arguments = blot_eval_instance_arguments::Owned {
        owner_id: blot_native::fresh_owner_id(),
        values: copyOwned(generator.representations.instance_arguments.values),
        spans: copyOwned(generator.representations.instance_arguments.spans),
     ..};
    candidate.captures = copying.capture_captures(generator.planning.template_catalog, old.captures);
    { let optional_source_7 .= generator.representations.connection; if optional_source_7 { let connection .= optional_source_7; candidate.bridge = blot_support::some(captureBridge(connection));  } }
    var locations: FieldLocation[>..<] = [];
    for slot in session.field_locations.slots {
        if slot.tag != 0 { locations.push(FieldLocation { slot.key.family, slot.key.tag, slot.key.name, slot.val.field, slot.val.len , ..}); }
    }
    // Source field-location order is family/tag/name, independent of buckets.
    for index in 1..locations.len {
        let value = locations[index]; var at = index;
        while at != 0 {
            let left = locations[at - 1];
            let less = value.family < left.family || value.family == left.family &&
                (value.tag < left.tag || value.tag == left.tag && value.name < left.name);
            if !less { break; } locations[at] = left; at--;
        }
        locations[at] = value;
    }
    candidate.field_locations = copying.capture_field_locations(locations, old.field_locations);
    candidate.field_locations_stamp = stamp(candidate.field_locations);
    let operations = allocateOwned_operations(generator.planning.runtime_operations.entries.len);
    for entry, index in generator.planning.runtime_operations.entries {
        operations[index] = Operation { copyOwned(generator.planning.runtime_operations.key(entry)), entry.foreign, entry.runtime , ..};
    }
    candidate.operations = operations;
    var relocations: OperationRelocation[>..<] = [];
    for entry in generator.planning.runtime_operations.relocations {
        var location = default<OperationLocation>();
        if entry.location.word { location = OperationLocation.word { entry.location.index , ..}; }
        else { location = OperationLocation.instruction { entry.location.function, entry.location.index , ..}; }
        relocations.push(OperationRelocation { entry.operation, location , ..});
    }
    candidate.operation_relocations = copying.capture_operation_relocations(relocations, old.operation_relocations);
    candidate.operations_finalized = generator.planning.runtime_operations.finalized;
    var functions: Function[>..<] = [];
    for entry in generator.planning.instances.slots {
        if entry.tag != 0 {
            var result_template = blot_support::none<u32>();
            { let optional_source_6 .= generator.planning.template_results.get(entry.key); if optional_source_6 { let found = optional_source_6; result_template = blot_support::some(found);  } }
            functions.push(Function { Request.named { entry.key }, entry.val, result_template , ..});
        }
    }
    for entry in generator.planning.closures.slots {
        if entry.tag != 0 {
            var result_template = blot_support::none<u32>();
            { let optional_source_5 .= generator.planning.closure_template_results.get(entry.key); if optional_source_5 { let found = optional_source_5; result_template = blot_support::some(found);  } }
            functions.push(Function { Request.closure { entry.key }, entry.val, result_template , ..});
        }
    }
    for entry in generator.planning.callables.slots {
        if entry.tag != 0 {
            var result_template = blot_support::none<u32>();
            functions.push(Function { Request.callable { entry.key }, entry.val, result_template , ..});
        }
    }
    for entry in generator.planning.constructor_functions.slots {
        if entry.tag != 0 {
            var result_template = blot_support::none<u32>();
            functions.push(Function { Request.constructor { entry.key }, entry.val, result_template , ..});
        }
    }
    for entry in generator.planning.primitive_functions.slots {
        if entry.tag != 0 {
            var result_template = blot_support::none<u32>();
            functions.push(Function { Request.primitive { entry.key }, entry.val, result_template , ..});
        }
    }
    for entry in generator.planning.operation_functions.slots {
        if entry.tag != 0 {
            var result_template = blot_support::none<u32>();
            functions.push(Function { Request.operation { entry.key }, entry.val, result_template , ..});
        }
    }
    for entry in generator.planning.host_functions.slots {
        if entry.tag != 0 {
            var result_template = blot_support::none<u32>();
            functions.push(Function { Request.host { entry.key }, entry.val, result_template , ..});
        }
    }
    for index in 1..functions.len {
        let value = functions[index]; var at = index;
        while at != 0 && value.function < functions[at - 1].function { functions[at] = functions[at - 1]; at--; }
        functions[at] = value;
    }
    candidate.functions = copying.capture_functions(functions, old.functions);
    var serialized: Serialized[>..<] = [];
    for entry in generator.static_data.cache.slots {
        if entry.tag != 0 { serialized.push(Serialized { entry.key.value, entry.key.ty, entry.val , ..}); }
    }
    candidate.serialized = copying.capture_serialized(serialized, old.serialized);
    var globals: RuntimeGlobal[>..<] = [];
    for entry in generator.planning.runtime_globals.slots {
        if entry.tag != 0 { globals.push(RuntimeGlobal { entry.key, entry.val.global, entry.val.initializer, entry.val.active , ..}); }
    }
    candidate.runtime_globals = copying.capture_runtime_globals(globals, old.runtime_globals);
    candidate.runtime_order = copying.capture_runtime_order(generator.planning.runtime_order, old.runtime_order);
    candidate.binding_offsets = copying.capture_binding_offsets(session.binding_offsets, old.binding_offsets);
    candidate.node_offsets = copying.capture_node_offsets(session.node_offsets, old.node_offsets);
    candidate.visited_nodes = copying.capture_visited_nodes(session.visited_nodes, old.visited_nodes);
    candidate.provider_frames = copying.capture_provider_frames(session.providers.frames, old.provider_frames);
    candidate.provider_cells = copying.capture_provider_cells(session.providers.cells, old.provider_cells);
    candidate.break_values = copying.capture_break_values(session.break_values, old.break_values);
    var slots: Slot[>..<] = [];
    for from in session.slots { slots.push(Slot { blot_eval_core_eval::slotStateCode(from.state), from.traced, from.value , ..}); }
    candidate.slots = copying.capture_slots(slots, old.slots);
    var requests: RequestCell[>..<] = [];
    for from in session.request_cells { requests.push(RequestCell { from.state, from.exit, from.status , ..}); }
    candidate.request_cells = copying.capture_request_cells(requests, old.request_cells);
    var handlers: RequestHandler[>..<] = [];
    for from in session.request_handlers { handlers.push(RequestHandler { from.callback, from.cell, from.outer , ..}); }
    candidate.request_handlers = copying.capture_request_handlers(handlers, old.request_handlers);
    let arrays = allocateOwned_arrays(generator.planning.array_proofs.count);
    var count: i64 = 0;
    for entry in generator.planning.array_proofs.slots {
        if entry.tag != 0 { arrays[count] = ArrayProof { entry.key, copyOwned(entry.val.updates) , ..}; count++; }
    }
    candidate.array_proofs = arrays;
    let discards = allocateOwned_discards(generator.planning.discard_proofs.count);
    count = 0;
    for entry in generator.planning.discard_proofs.slots {
        if entry.tag != 0 { discards[count] = DiscardProof { entry.key, copyOwned(entry.val.unused) , ..}; count++; }
    }
    candidate.discard_proofs = discards;
    candidate.evaluator_steps = session.steps; candidate.evaluator_demanded = session.demanded;
    candidate.evaluator_traced_bodies = session.traced_bodies; candidate.evaluator_traced_nodes = session.traced_nodes;
    candidate.leases = copying.shared.leases;
    if copying.failure != blot_error::Error.none {
        let error = copying.failure; candidate.deinit(); return default<Pools>(), error;
    }
    session.counters.metadata_shared_fields += copying.shared.stats.shared_fields;
    session.counters.metadata_shared_bytes += copying.shared.stats.shared_bytes;
    session.counters.metadata_copied_fields += copying.shared.stats.copied_fields;
    session.counters.metadata_copied_bytes += copying.shared.stats.copied_bytes;
    return candidate, blot_error::Error.none;
}
fn capturePools<G>(self_: Context&, generator: G&, identity: blot_support::Option<blot_backend_runtime_identity::View>) -> Error {
    return self_.capturePoolsWithStamps(generator, identity, null);
}
fn capturePoolsWithStamps<G>(self_: Context&, generator: G&, identity: blot_support::Option<blot_backend_runtime_identity::View>, memo: ModuleStamps?) -> Error {
    let table_error=self_.tableFailure();if table_error!=blot_error::Error.none {return table_error;}

    assert(self_.active_job == 0);
    var candidate, error = capture(generator, identity, memo); if error != blot_error::Error.none { return error; }
    candidate.generation = 1;
    if self_.pools.present { candidate.generation = self_.pools.value.generation + 1; self_.pools.value.deinit(); }
    self_.pools = blot_support::some(candidate); return blot_error::Error.none;
}

type PrincipalProof = blot_reuse_principal_query::Record;
fn recordPrincipal(self_: Context&, target: blot_check_core::BindingRef, options: blot_eval_core_eval::Options,
    solved: blot_eval_core_eval::SolvedEvidence, inputs: const blot_reuse_principal_inputs::Key? = null) -> Error {
    if solved.selected.len != 0 { return blot_error::Error.none; }
    var cursor = self_.principal_queries.candidates(blot_reuse_principal_query::fingerprint(target), blot_reuse_semantic_query_table::Order.oldest_first);
    loop {
        let position = cursor.next(); if !position.present { break; }
        if self_.principal_queries.records[position.value].key.target == target { return blot_error::Error.none; }
    }
    let mappings = blot_eval_core_eval::copySolvedTypes(solved.types);
    let rows = blot_eval_core_eval::copySolvedRows(solved.rows);
    var input_key = blot_support::none<blot_reuse_principal_inputs::Key>();
    { let optional_source_4 .= inputs; if optional_source_4 { let observed .= optional_source_4;
        let owned, error = observed.clone();
        if error != blot_error::Error.none { blot_eval_core_eval::releaseSolvedTypes(mappings); blot_eval_core_eval::releaseSolvedRows(rows); return error; }
        input_key = blot_support::some(owned);
     } }
    var builder = self_.principal_queries.begin(blot_reuse_principal_query::Key { target, options , ..});
    builder.read(blot_reuse_principal_query::Dependencies { input_key , ..});
    builder.stage(blot_eval_core_eval::SolvedEvidence { types: mappings, rows: rows , ..});
    var candidate = builder.complete(); builder.abort();
    if !candidate.present { return blot_error::Error.none; }
    let prepared, error = self_.principal_queries.prepare(candidate.value);
    if error != blot_error::Error.none { candidate.value.abort(); return error; }
    if !prepared.present { candidate.value.abort(); return blot_error::Error.none; }
    let handle = self_.principal_queries.publish(prepared.value, candidate.value);
    candidate.value.abort(); return blot_error::Error.none;
}
fn deinit(self_: Context&) {
    assert(self_.active_job == 0);
    self_.principal_queries.deinit(); self_.principal_graphs.queries.deinit(); self_.specialization_queries.deinit(); self_.refinement_queries.deinit();
    for &record in self_.independent_calls.items { record.deinit(); } self_.independent_calls.clear();
    self_.jobs.clear(); self_.events.clear(); self_.function_jobs.clear(); self_.global_jobs.clear();
    self_.inline_bodies.clear(); self_.static_reads.clear(); self_.mappings.clear(); self_.rows.clear(); self_.templates.clear();
    if self_.pools.present { self_.pools.value.deinit(); self_.pools.present = false; }
}

fn requestCode(request: Request) -> u8 {
    match request {
        named => 0, closure => 1, callable => 2, constructor => 3,
        primitive => 4, operation => 5, host => 6, constant => 7, runtime_global => 8,
    }
}

// Canonical metadata is owned independently of a lexical compiler invocation.
struct ContextOwner {live:bool=false,generation:u64=0,
jobs:Context_Job=Context_Job{..},
events:Context_StampedEvent=Context_StampedEvent{..},
function_jobs:Context_u32=Context_u32{..},
global_jobs:Context_u32=Context_u32{..},
inline_bodies:Context_blot_check_core__BindingRef=Context_blot_check_core__BindingRef{..},
static_reads:Context_StaticRead=Context_StaticRead{..},
mappings:Context_blot_backend_layout__Mapping=Context_blot_backend_layout__Mapping{..},
rows:Context_blot_backend_layout__RowMapping=Context_blot_backend_layout__RowMapping{..},
templates:Context_blot_reuse_substitution_keys__Entry=Context_blot_reuse_substitution_keys__Entry{..},
independent_calls:Context_blot_reuse_independent_call_proof__Record=Context_blot_reuse_independent_call_proof__Record{..},
principal_queries:blot_reuse_principal_query::Table=default<blot_reuse_principal_query::Table>(),
principal_graphs:blot_eval_core_eval::RetainedPrincipalGraphs=default<blot_eval_core_eval::RetainedPrincipalGraphs>(),
specialization_queries:blot_eval_selected_query::Table=default<blot_eval_selected_query::Table>(),
refinement_queries:blot_reuse_refinement_receipt::Table=default<blot_reuse_refinement_receipt::Table>(),
canonical:Context=Context{..}}
reusable var context_owners:ContextOwner[>..]=[];
fn validContext(self_:const Context&)->bool {return self_.context_lease!=0 && self_.context_lease-1<context_owners.len && context_owners[self_.context_lease-1].live && context_owners[self_.context_lease-1].generation==self_.context_generation;}
fn initPooledRef(allocation_owner:u64=0)->Context?,Error {
 if context_owners.len>=0xffffffff {return null,blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=context_owners.alloc_index(ContextOwner{live:true,generation:generation,..});let state:ContextOwner& =context_owners[at];
 state.principal_queries=blot_reuse_principal_query::init();state.principal_graphs=blot_eval_core_eval::initRetainedPrincipalGraphs();state.specialization_queries=blot_eval_selected_query::init();state.refinement_queries=blot_reuse_refinement_receipt::init();
 state.canonical=Context{ context_lease:(at+1) as u32, context_generation:generation, allocation_owner:allocation_owner, jobs:state.jobs, events:state.events, function_jobs:state.function_jobs, global_jobs:state.global_jobs, inline_bodies:state.inline_bodies, static_reads:state.static_reads, mappings:state.mappings, rows:state.rows, templates:state.templates, principal_queries:state.principal_queries, principal_graphs:state.principal_graphs, specialization_queries:state.specialization_queries, independent_calls:state.independent_calls, refinement_queries:state.refinement_queries, .. };return state.canonical,blot_error::Error.none;
}
fn tableFailure(self_:const Context&)->Error {
if self_.jobs.failure!=blot_error::Error.none {return self_.jobs.failure;}
if self_.events.failure!=blot_error::Error.none {return self_.events.failure;}
if self_.function_jobs.failure!=blot_error::Error.none {return self_.function_jobs.failure;}
if self_.global_jobs.failure!=blot_error::Error.none {return self_.global_jobs.failure;}
if self_.inline_bodies.failure!=blot_error::Error.none {return self_.inline_bodies.failure;}
if self_.static_reads.failure!=blot_error::Error.none {return self_.static_reads.failure;}
if self_.mappings.failure!=blot_error::Error.none {return self_.mappings.failure;}
if self_.rows.failure!=blot_error::Error.none {return self_.rows.failure;}
if self_.templates.failure!=blot_error::Error.none {return self_.templates.failure;}
if self_.independent_calls.failure!=blot_error::Error.none {return self_.independent_calls.failure;}
return blot_error::Error.none;}
fn releasePooled(self_:Context&) {if self_.context_lease==0 {return;}assert(self_.validContext());let at=self_.context_lease-1;self_.deinit();
self_.jobs.deinit();
self_.events.deinit();
self_.function_jobs.deinit();
self_.global_jobs.deinit();
self_.inline_bodies.deinit();
self_.static_reads.deinit();
self_.mappings.deinit();
self_.rows.deinit();
self_.templates.deinit();
self_.independent_calls.deinit();
self_.principal_graphs.deinit();context_owners[at].live=false;self_=Context{..};context_owners.free(at);}

fn selectedOwnerPath(identity:blot_support::Option<IdentityMetadata>,unit:u32)->const u8[:] {if identity.present {let found=identity.value.view().owner(unit);if found.present {return found.value;}}return default<const u8[:]>();}

fn registeredPools(source:const Context&)->const Pools& {assert(source.validContext());let state:const ContextOwner& =context_owners[source.context_lease-1];let owned:const Context& =state.canonical;assert(source .== owned && owned.pools.present);return owned.pools.value;}
