// Data-stack emission retains source owner identities through aliases and joins.
namespace blot_backend_scoped_backend;
import std;
import dictionary;
import check.core;
import check.types;
import check.storage_types;
import check.storage_ops;
import check.package_core;
import .runtime_ir;
import .runtime_code;
import .wasm;
import .core_backend;
import .collection_ops;
import .storage_plan;
import .storage_calls;
import .storage_field_plan;
import .storage_transport;
import .storage_deferred_join;
import .storage_type_arguments;
import .storage_type_key;
import .storage_global_footprint;
import .storage_recursive_admission;
import .storage_span_dominance;
import .private_append_region;
import .addressed_input_demand;
import .wasm_scope_outline;
import .scalar_ops;
import runtime.data_stacks;
import runtime.storage_packets;
import eval.core_eval;
import eval.type_evidence;
import eval.body_recipe;
import support.error;
import support.pooled_buffer;
import support.pooled_map;
import support.native;
import check.scheme_equations;
import work_counters;
import support.option;

type Local = blot_backend_runtime_code::Local;
type Range = blot_backend_runtime_ir::Range;
struct WorkLimits { expressions: u32 = 500000 }
struct RequiredNode { unit: u32, id: blot_check_core::Id }
struct RequiredVisitor { pending: RequiredNode[>..<]&, unit: u32 }
fn append(visitor: RequiredVisitor&, id: blot_check_core::Id) -> blot_error::Error {
    if visitor.pending.len >= 100000 { return blot_error::Error.plan_limit; } if id != 0 { visitor.pending.push(RequiredNode { unit: visitor.unit, id: id }); } return blot_error::Error.none;
}
fn appendSlice(visitor: RequiredVisitor&, ids: const blot_check_core::Id[:]) -> blot_error::Error { for id in ids { let error = append(visitor, id); if error != blot_error::Error.none { return error; } } return blot_error::Error.none; }
fn selectorIsIndex<S>(selector: S) -> bool { match selector.kind { index => true, _ => false } }
fn required(units: const blot_check_core::Module[:], entry: u32) -> bool, blot_error::Error {
    var pending: RequiredNode[>..<] = []; var seen = dictionary<u64, bool> {};
    if entry == 0 || entry > units.len { return true, blot_error::Error.none; }
    for body in units[entry - 1].bodies { if body.exported { pending.push(RequiredNode { unit: entry, id: body.root }); } }
    while pending.len != 0 {
        let current = pending.pop(); if current.id == 0 { continue; }
        if current.unit == 0 || current.unit > units.len || seen.count >= 100000 { return true, blot_error::Error.none; }
        let source .= units[current.unit - 1]; if current.id >= source.nodes.len { return true, blot_error::Error.none; }
        let key = (current.unit as u64 << 32) | current.id; if seen.contains(key) { continue; } seen.insert(key, true);
        let node = source.node(current.id); if node.tag == blot_check_core::Tag.storage { return true, blot_error::Error.none; }
        if node.tag == blot_check_core::Tag.update { for selector in source.updateSelectors(current.id) { if selectorIsIndex(selector) { return true, blot_error::Error.none; } } }
        let ty = source.types.node(node.ty); if ty.tag == blot_check_types::Tag.nominal && blot_check_storage_types::identity(ty.a, ty.b).present { return true, blot_error::Error.none; }
        if node.tag == blot_check_core::Tag.reference || node.tag == blot_check_core::Tag.call {
            var target = blot_check_core::BindingRef {}; if node.tag == blot_check_core::Tag.call { target = source.call(current.id).target; } else { target = source.reference(current.id); }
            if target.unit == 0 { target.unit = source.unit; } if target.unit == 0 || target.unit > units.len { return true, blot_error::Error.none; }
            let producer .= units[target.unit - 1]; if target.binding >= producer.bindings.len { return true, blot_error::Error.none; }
            let body .= producer.body(target.binding); if body { pending.push(RequiredNode { unit: target.unit, id: body.root }); }
        }
        if node.tag == blot_check_core::Tag.closure { pending.push(RequiredNode { unit: source.unit, id: source.closures[node.a].body }); }
        let visitor = RequiredVisitor { pending: pending, unit: source.unit };
        let error = blot_eval_body_recipe::appendChildren(visitor, source, current.id, false);
        if error == blot_error::Error.out_of_memory { return false, error; } if error == blot_error::Error.plan_limit { return true, blot_error::Error.none; }
    }
    return false, blot_error::Error.none;
}
recursive fn independentScalarReplacement(source: const blot_check_core::Module&, id: blot_check_core::Id, self_binding: blot_check_core::BindingId, depth: i64, remaining: i64&) -> bool {
    if id == 0 { return true; } if depth > 32 || remaining == 0 || id >= source.nodes.len { return false; } remaining--; let node = source.node(id);
    if node.tag == blot_check_core::Tag.constant { return true; }
    if node.tag == blot_check_core::Tag.reference {
        let reference = source.reference(id); if (reference.unit != 0 && reference.unit != source.unit) || reference.binding == self_binding || reference.binding == 0 || reference.binding >= source.bindings.len { return false; }
        let kind = source.binding(reference.binding).kind; return kind == blot_check_core::BindingKind.local || kind == blot_check_core::BindingKind.parameter;
    }
    if node.tag == blot_check_core::Tag.scalar || node.tag == blot_check_core::Tag.logical {
        if node.tag == blot_check_core::Tag.scalar && node.c != 0 { return false; }
        return independentScalarReplacement(source, node.a, self_binding, depth + 1, remaining) && independentScalarReplacement(source, node.b, self_binding, depth + 1, remaining);
    }
    if node.tag == blot_check_core::Tag.array_op {
        let operation = source.arrayOperation(id); if operation != blot_backend_collection_ops::Op.get && operation != blot_backend_collection_ops::Op.length { return false; }
        for child in source.children(id) { if !independentScalarReplacement(source, child, self_binding, depth + 1, remaining) { return false; } } return true;
    }
    return false;
}
enum ValueTag { scalar, array, ref, view, link, aggregate, callable }
// Recursive metadata links are stable table ranges/IDs. Published child vectors
// are immutable; a writer creates a fresh vector before replacing one field.
struct Value {
    tag: ValueTag = ValueTag.scalar, word: Local, root: blot_support::Option<i64>, other_roots: Range, fields: Range,
    variant_tags: Range, variant_index: blot_support::Option<i64>, variant_possible: Range,
    terminated: bool = false, sequence: bool = false, pool_borrow: bool = false,
    token: Local, epoch_low: Local, epoch_high: Local, index: Local, length: Local,
    depth: i64 = 0, mode: blot_runtime_data_stacks::Mode = blot_runtime_data_stacks::Mode.fixed,
    floating: bool = false, literal: blot_support::Option<u32>, constant_bits: blot_support::Option<u32>, name: const u8[:] = "",
    callable: blot_support::Option<u32>, host: blot_support::Option<blot_backend_wasm::Callback>, nominal: blot_support::Option<blot_check_types::NominalIdentity>, type_evidence: blot_support::Option<u32>, projected_parameter_fields: bool = false,
}
struct ZeroSource { function: blot_support::Option<u32>, word: Local }
fn get<M>(source: ZeroSource&, code: blot_backend_runtime_code::Code<M>&) -> Local, blot_error::Error {
    if !source.function.present || source.function.value != code.function {
        let word, error = code.temp(); if error != blot_error::Error.none { return Local {}, error; } source.word = word; source.function = blot_support::some(code.function);
    }
    return source.word, blot_error::Error.none;
}
enum CallableKind { named, closure, primitive }
struct Callable { unit: u32, node: blot_check_core::Id = 0, target: blot_check_core::BindingId = 0, captures: Range, types: Range, goals: Range }
fn kind(callable: Callable, owner: const blot_check_core::Module&) -> CallableKind { if callable.node == 0 { return CallableKind.named; } if owner.node(callable.node).tag == blot_check_core::Tag.primitive_function { return CallableKind.primitive; } return CallableKind.closure; }
fn signature(callable: Callable, owner: const blot_check_core::Module&) -> blot_check_types::Id {
    let selected = kind(callable, owner); if selected == CallableKind.named { return owner.binding(callable.target).ty; } if selected == CallableKind.closure { return owner.closure(callable.node).function_type; } return owner.typeOf(callable.node);
}
fn lessName(left: const u8[:], right: const u8[:]) -> bool { var length = left.len; if right.len < length { length = right.len; } for index in 0..length { if left[index] != right[index] { return left[index] < right[index]; } } return left.len < right.len; }
fn orderFields(fields: Value[:]) {
    for index in 1..fields.len { let value = fields[index]; var next = index; while next > 0 && lessName(value.name, fields[next - 1].name) { fields[next] = fields[next - 1]; next--; } fields[next] = value; }
}
struct FixedSpan { length: Local, ready: blot_support::Option<Local>, checked_scope: blot_support::Option<i64> }
struct Root {
    word: Local, token: Local, epoch_low: Local, epoch_high: Local, stack: u32, depth: i64, element: Value,
    element_initialized: bool = true, known_empty: bool = false, capacity_request: blot_support::Option<i64>, live: bool = true,
    frozen: bool = false, persistent: bool = false, dedicated: bool = true, fixed_span: blot_support::Option<FixedSpan>, fixed_created: bool = false,
    global_ready: blot_support::Option<Local>, imported_global: bool = false,
}
fn createdDescriptorMatches(owner: Root, value: Value) -> bool {
    return owner.fixed_created && owner.live && !owner.imported_global && owner.element.tag == ValueTag.scalar && owner.element.fields.len == 0 && !owner.element.root.present && !owner.element.host.present &&
        value.tag == ValueTag.array && value.mode == blot_runtime_data_stacks::Mode.fixed && value.other_roots.len == 0 && !value.host.present &&
        value.word.id == owner.word.id && value.token.id == owner.token.id && value.epoch_low.id == owner.epoch_low.id && value.epoch_high.id == owner.epoch_high.id;
}
struct Global { target: blot_check_core::BindingRef, word: u32, token: u32, epoch_low: u32, epoch_high: u32, capacity_request: i64, literal_bytes: blot_support::Option<u32>, initializing: bool = false }
struct TypeRef { unit: u32, ty: blot_check_types::Id, environment: blot_support::Option<Range> }
struct TypeArgument { unit: u32, parameter: blot_check_types::Id, argument: blot_check_types::Id, argument_unit: u32, environment: blot_support::Option<Range> }
struct TypeEvidence { root: TypeRef, arguments: Range }
fn boxTypeEvidenceIn(evidence: TypeEvidence[>..<]&, source: TypeEvidence) -> u32 { let id = evidence.len as u32; evidence.push(source); return id; }
struct Binding { unit: u32, id: blot_check_core::BindingId, value: Value, remaining: u32 }
struct ValueJoin { value: blot_support::Option<Value>, physical: blot_backend_storage_deferred_join::Join, selective: bool = false }
struct Control { unit: u32, id: blot_check_core::Id, nesting: u32, roots_before: i64, result: ValueJoin }
struct LoopSharing { whole: bool = false, fields: Range }
struct FrameMark { word: Local, first: i64, end: i64 }
struct Loop { unit: u32, id: blot_check_core::Id, nesting: u32, roots_before: i64, carries: Range, shared: Range, headers: Range, iterator: blot_support::Option<Local>, mark: FrameMark, depth: i64, read_frame: i64 }
struct RootRead { owner: i64, shape: u32 }
struct ReadFrame { owner_limit: i64, first: Range, persistent: Range }
fn position(frame: ReadFrame, reads: const RootRead[:], owner: i64) -> i64 {
    var low = 0; var high = frame.first.len; while low < high { let middle = low + (high - low) / 2; if reads[frame.first.start + middle].owner < owner { low = middle + 1; } else { high = middle; } } return low;
}
enum WriterKind { read, write }
struct WriterEvent { owner: i64, kind: WriterKind, shape: Value, initializes_rows: bool = true }
struct WriterTrace { inputs: i64, stable: bool = false, events: Range, remaining: i64 = 100000 }
enum FunctionAbi { scalar, registers, result_slot, buffered }
enum AccessContract { ordered { events: Range }, invariant { accesses: Range } }
struct ReturnedOwner { element: Value, element_initialized: bool, known_empty: bool, frozen: bool }
struct CheckedFunctionPlan {
    entry: blot_backend_storage_calls::Entry, input_words: i64, used_input_words: Range, result_aliases: Range, unit_result: bool,
    abi: FunctionAbi, return_registers: i64, result_pointer_first: bool = false, addressed_arguments: Range,
    result: Value, returned_owners: Range, access: AccessContract, regions: Range,
}
struct RecursiveHeader { target: blot_check_core::BindingRef, plan: u32, parameter_owners: Range }
struct InputBundle { parameter: u32, first: u32, words: i64, needed: Range }
struct BundleSnapshot { function: u32, root: i64, address: Local, words: Range, used: Range }
struct RecordKey { unit: u32, ty: blot_check_types::Id }
fn hash(key: RecordKey) -> u64 { ::hash((key.unit as u64 << 32) | key.ty) }
struct RecordField { ty: blot_check_types::Id, symbol: u32, spelling: blot_support::Option<const u8[:]> }
struct RecordMetadata { fields: Range, name_words: i64 }
struct RecordMetadataCache { entries: dictionary<RecordKey, RecordMetadata>&, fields: RecordField[>..<]& }
fn less(left: RecordField, right: RecordField) -> bool { if left.spelling.present { if right.spelling.present { return lessName(left.spelling.value, right.spelling.value); } return true; } if right.spelling.present { return false; } return left.symbol < right.symbol; }
fn get(cache: RecordMetadataCache&, owner: const blot_check_core::Module&, ty: blot_check_types::Id, node: blot_check_types::Node, encoded_words: i64, word_work: i64) -> RecordMetadata, blot_error::Error {
    let key = RecordKey { unit: owner.unit, ty: ty };
    block { let known = cache.entries.get(key); if known { if known.name_words > encoded_words || known.name_words > word_work { return RecordMetadata {}, blot_error::Error.limit; } return copy(known), blot_error::Error.none; } }
    var name_words: i64 = 1;
    for index in 0..node.b {
        let field = owner.types.recordField(node, index); let spelling = owner.fieldSpelling(field.name); var words: i64 = 4;
        if spelling.present { if spelling.value.len > 9223372036854775805 { return RecordMetadata {}, blot_error::Error.limit; } words = spelling.value.len + 2; }
        if words > 9223372036854775807 - name_words { return RecordMetadata {}, blot_error::Error.limit; } name_words += words;
        if name_words > encoded_words || name_words > word_work { return RecordMetadata {}, blot_error::Error.limit; }
    }
    let start = cache.fields.len;
    for index in 0..node.b { let field = owner.types.recordField(node, index); cache.fields.push(RecordField { ty: field.ty, symbol: field.name, spelling: owner.fieldSpelling(field.name) }); }
    for index in 1..node.b { let value = cache.fields[start + index]; var next = index; while next > 0 && less(value, cache.fields[start + next - 1]) { cache.fields[start + next] = cache.fields[start + next - 1]; next--; } cache.fields[start + next] = value; }
    let metadata = RecordMetadata { fields: Range { start: start, len: node.b }, name_words: name_words }; cache.entries.insert(key, metadata); return metadata, blot_error::Error.none;
}

// Compile-wide immutable vectors use IDs and ranges, independent of table moves.
struct Metadata {
    values: Value[>..<]&,words: u32[>..<]&,indexes: i64[>..<]&,flags: bool[>..<]&,locals: Local[>..<]&,types: TypeArgument[>..<]&,evidence: TypeEvidence[>..<]&,callables: Callable[>..<]&,goals: blot_check_core::Obligation[>..<]&,plans: CheckedFunctionPlan[>..<]&,returned: ReturnedOwner[>..<]&,accesses: blot_backend_storage_recursive_admission::Access[>..<]&,events: WriterEvent[>..<]&,regions: i64[>..<]&,bundles: InputBundle[>..<]&,sharing: LoopSharing[>..<]&,reads: RootRead[>..<]&,traces: WriterTrace[>..<]&,
}
fn fields(metadata: const Metadata&,value: Value) -> const Value[:] { metadata.values[value.fields.start..value.fields.start + value.fields.len] }
fn variantTags(metadata: const Metadata&,value: Value) -> const u32[:] { metadata.words[value.variant_tags.start..value.variant_tags.start + value.variant_tags.len] }
fn variantPossible(metadata: const Metadata&,value: Value) -> const bool[:] { metadata.flags[value.variant_possible.start..value.variant_possible.start + value.variant_possible.len] }
fn otherRoots(metadata: const Metadata&,value: Value) -> const i64[:] { metadata.indexes[value.other_roots.start..value.other_roots.start + value.other_roots.len] }
fn callable(metadata: const Metadata&,id: u32) -> const Callable& { metadata.callables[id] }
fn evidence(metadata: const Metadata&,id: u32) -> const TypeEvidence& { metadata.evidence[id] }
fn allocateFields(metadata: Metadata&,value: Value&,count: i64) -> Range { let span = Range { start: metadata.values.len,len: count }; for index in 0..count { metadata.values.push(Value {}); } value.fields = span; return span; }
fn publishValues(metadata: Metadata&,values: const Value[:]) -> Range { let result = Range { start: metadata.values.len,len: values.len }; metadata.values.append(values); return result; }
fn publishWords(metadata: Metadata&,values: const u32[:]) -> Range { let result = Range { start: metadata.words.len,len: values.len }; metadata.words.append(values); return result; }
fn publishFlags(metadata: Metadata&,values: const bool[:]) -> Range { let result = Range { start: metadata.flags.len,len: values.len }; metadata.flags.append(values); return result; }
fn publishTypes(metadata: Metadata&,values: const TypeArgument[:]) -> Range { let result = Range { start: metadata.types.len,len: values.len }; metadata.types.append(values); return result; }
fn deinit(metadata: Metadata&) { metadata.values.clear(); metadata.words.clear(); metadata.indexes.clear(); metadata.flags.clear(); metadata.locals.clear(); metadata.types.clear(); metadata.evidence.clear(); metadata.callables.clear(); metadata.goals.clear(); metadata.plans.clear(); metadata.returned.clear(); metadata.accesses.clear(); metadata.events.clear(); metadata.regions.clear(); metadata.bundles.clear(); metadata.sharing.clear(); metadata.reads.clear(); metadata.traces.clear(); }
recursive fn hasRoot(metadata: const Metadata&,value: Value,root_id: i64) -> bool { if value.root.present && value.root.value == root_id { return true; } for root in otherRoots(metadata,value) { if root == root_id { return true; } } for field in fields(metadata,value) { if hasRoot(metadata,field,root_id) { return true; } } return false; }
recursive fn borrows(metadata: const Metadata&,value: Value,owner: Value) -> bool { if owner.root.present && hasRoot(metadata,value,owner.root.value) { return true; } for root in otherRoots(metadata,owner) { if hasRoot(metadata,value,root) { return true; } } for field in fields(metadata,owner) { if borrows(metadata,value,field) { return true; } } return false; }
struct AppendRegion { unit: u32,plan: blot_backend_private_append_region::Plan }

struct Values { storage: Value[:] = [],items: Value[:] = [] }
reusable[] var Values_runs: Value[>..] = [];
fn reserve(buffer: Values&,minimum: i64) -> blot_error::Error { blot_support_pooled_buffer::ensure(buffer,minimum,Values_runs) }
fn push(buffer: Values&,value: Value) -> blot_error::Error { blot_support_pooled_buffer::push(buffer,value,Values_runs) }
fn resize(buffer: Values&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn clear(buffer: Values&) { blot_support_pooled_buffer::clear(buffer); }
fn deinit(buffer: Values&) { blot_support_pooled_buffer::deinit(buffer,Values_runs); }

struct Roots { storage: Root[:] = [],items: Root[:] = [] }
reusable[] var Roots_runs: Root[>..] = [];
fn reserve(buffer: Roots&,minimum: i64) -> blot_error::Error { blot_support_pooled_buffer::ensure(buffer,minimum,Roots_runs) }
fn push(buffer: Roots&,value: Root) -> blot_error::Error { blot_support_pooled_buffer::push(buffer,value,Roots_runs) }
fn resize(buffer: Roots&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn clear(buffer: Roots&) { blot_support_pooled_buffer::clear(buffer); }
fn deinit(buffer: Roots&) { blot_support_pooled_buffer::deinit(buffer,Roots_runs); }

struct Bindings { storage: Binding[:] = [],items: Binding[:] = [] }
reusable[] var Bindings_runs: Binding[>..] = [];
fn reserve(buffer: Bindings&,minimum: i64) -> blot_error::Error { blot_support_pooled_buffer::ensure(buffer,minimum,Bindings_runs) }
fn push(buffer: Bindings&,value: Binding) -> blot_error::Error { blot_support_pooled_buffer::push(buffer,value,Bindings_runs) }
fn resize(buffer: Bindings&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn clear(buffer: Bindings&) { blot_support_pooled_buffer::clear(buffer); }
fn deinit(buffer: Bindings&) { blot_support_pooled_buffer::deinit(buffer,Bindings_runs); }

struct Controls { storage: Control[:] = [],items: Control[:] = [] }
reusable[] var Controls_runs: Control[>..] = [];
fn reserve(buffer: Controls&,minimum: i64) -> blot_error::Error { blot_support_pooled_buffer::ensure(buffer,minimum,Controls_runs) }
fn push(buffer: Controls&,value: Control) -> blot_error::Error { blot_support_pooled_buffer::push(buffer,value,Controls_runs) }
fn resize(buffer: Controls&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn clear(buffer: Controls&) { blot_support_pooled_buffer::clear(buffer); }
fn deinit(buffer: Controls&) { blot_support_pooled_buffer::deinit(buffer,Controls_runs); }

struct Loops { storage: Loop[:] = [],items: Loop[:] = [] }
reusable[] var Loops_runs: Loop[>..] = [];
fn reserve(buffer: Loops&,minimum: i64) -> blot_error::Error { blot_support_pooled_buffer::ensure(buffer,minimum,Loops_runs) }
fn push(buffer: Loops&,value: Loop) -> blot_error::Error { blot_support_pooled_buffer::push(buffer,value,Loops_runs) }
fn resize(buffer: Loops&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn clear(buffer: Loops&) { blot_support_pooled_buffer::clear(buffer); }
fn deinit(buffer: Loops&) { blot_support_pooled_buffer::deinit(buffer,Loops_runs); }

struct ReadFrames { storage: ReadFrame[:] = [],items: ReadFrame[:] = [] }
reusable[] var ReadFrames_runs: ReadFrame[>..] = [];
fn reserve(buffer: ReadFrames&,minimum: i64) -> blot_error::Error { blot_support_pooled_buffer::ensure(buffer,minimum,ReadFrames_runs) }
fn push(buffer: ReadFrames&,value: ReadFrame) -> blot_error::Error { blot_support_pooled_buffer::push(buffer,value,ReadFrames_runs) }
fn resize(buffer: ReadFrames&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn clear(buffer: ReadFrames&) { blot_support_pooled_buffer::clear(buffer); }
fn deinit(buffer: ReadFrames&) { blot_support_pooled_buffer::deinit(buffer,ReadFrames_runs); }

struct Globals { storage: Global[:] = [],items: Global[:] = [] }
reusable[] var Globals_runs: Global[>..] = [];
fn reserve(buffer: Globals&,minimum: i64) -> blot_error::Error { blot_support_pooled_buffer::ensure(buffer,minimum,Globals_runs) }
fn push(buffer: Globals&,value: Global) -> blot_error::Error { blot_support_pooled_buffer::push(buffer,value,Globals_runs) }
fn resize(buffer: Globals&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn clear(buffer: Globals&) { blot_support_pooled_buffer::clear(buffer); }
fn deinit(buffer: Globals&) { blot_support_pooled_buffer::deinit(buffer,Globals_runs); }

struct Flags { storage: bool[:] = [],items: bool[:] = [] }
reusable[] var Flags_runs: bool[>..] = [];
fn reserve(buffer: Flags&,minimum: i64) -> blot_error::Error { blot_support_pooled_buffer::ensure(buffer,minimum,Flags_runs) }
fn push(buffer: Flags&,value: bool) -> blot_error::Error { blot_support_pooled_buffer::push(buffer,value,Flags_runs) }
fn resize(buffer: Flags&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn clear(buffer: Flags&) { blot_support_pooled_buffer::clear(buffer); }
fn deinit(buffer: Flags&) { blot_support_pooled_buffer::deinit(buffer,Flags_runs); }

struct AppendRegions { storage: AppendRegion[:] = [],items: AppendRegion[:] = [] }
reusable[] var AppendRegions_runs: AppendRegion[>..] = [];
fn reserve(buffer: AppendRegions&,minimum: i64) -> blot_error::Error { blot_support_pooled_buffer::ensure(buffer,minimum,AppendRegions_runs) }
fn push(buffer: AppendRegions&,value: AppendRegion) -> blot_error::Error { blot_support_pooled_buffer::push(buffer,value,AppendRegions_runs) }
fn resize(buffer: AppendRegions&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn clear(buffer: AppendRegions&) { blot_support_pooled_buffer::clear(buffer); }
fn deinit(buffer: AppendRegions&) { blot_support_pooled_buffer::deinit(buffer,AppendRegions_runs); }

struct BundleSnapshots { storage: BundleSnapshot[:] = [],items: BundleSnapshot[:] = [] }
reusable[] var BundleSnapshots_runs: BundleSnapshot[>..] = [];
fn reserve(buffer: BundleSnapshots&,minimum: i64) -> blot_error::Error { blot_support_pooled_buffer::ensure(buffer,minimum,BundleSnapshots_runs) }
fn push(buffer: BundleSnapshots&,value: BundleSnapshot) -> blot_error::Error { blot_support_pooled_buffer::push(buffer,value,BundleSnapshots_runs) }
fn resize(buffer: BundleSnapshots&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn clear(buffer: BundleSnapshots&) { blot_support_pooled_buffer::clear(buffer); }
fn deinit(buffer: BundleSnapshots&) { blot_support_pooled_buffer::deinit(buffer,BundleSnapshots_runs); }

struct WordSet { count: i64 = 0,slots: dictionary_slot<u32,bool>[:] = [] }
reusable[] var WordSet_slots: dictionary_slot<u32,bool>[>..] = [];
fn get(map: const WordSet&,key: u32) -> bool? { blot_support_pooled_map::get(map,key) }
fn contains(map: const WordSet&,key: u32) -> bool { return get(map,key) != null; }
fn insert(map: WordSet&,key: u32,value: bool) -> blot_error::Error { blot_support_pooled_map::insert(map,key,value,WordSet_slots); return blot_error::Error.none; }
fn clear(map: WordSet&) { blot_support_pooled_map::clear(map); }
fn deinit(map: WordSet&) { blot_support_pooled_map::deinit(map,WordSet_slots); }

struct IndexSet { count: i64 = 0,slots: dictionary_slot<i64,bool>[:] = [] }
reusable[] var IndexSet_slots: dictionary_slot<i64,bool>[>..] = [];
fn get(map: const IndexSet&,key: i64) -> bool? { blot_support_pooled_map::get(map,key) }
fn contains(map: const IndexSet&,key: i64) -> bool { return get(map,key) != null; }
fn insert(map: IndexSet&,key: i64,value: bool) -> blot_error::Error { blot_support_pooled_map::insert(map,key,value,IndexSet_slots); return blot_error::Error.none; }
fn clear(map: IndexSet&) { blot_support_pooled_map::clear(map); }
fn deinit(map: IndexSet&) { blot_support_pooled_map::deinit(map,IndexSet_slots); }

struct PlainLayouts { count: i64 = 0,slots: dictionary_slot<u64,Value>[:] = [] }
reusable[] var PlainLayouts_slots: dictionary_slot<u64,Value>[>..] = [];
fn get(map: const PlainLayouts&,key: u64) -> Value? { blot_support_pooled_map::get(map,key) }
fn contains(map: const PlainLayouts&,key: u64) -> bool { return get(map,key) != null; }
fn insert(map: PlainLayouts&,key: u64,value: Value) -> blot_error::Error { blot_support_pooled_map::insert(map,key,value,PlainLayouts_slots); return blot_error::Error.none; }
fn clear(map: PlainLayouts&) { blot_support_pooled_map::clear(map); }
fn deinit(map: PlainLayouts&) { blot_support_pooled_map::deinit(map,PlainLayouts_slots); }

struct PlanMap { count: i64 = 0,slots: dictionary_slot<u32,u32>[:] = [] }
reusable[] var PlanMap_slots: dictionary_slot<u32,u32>[>..] = [];
fn get(map: const PlanMap&,key: u32) -> u32? { blot_support_pooled_map::get(map,key) }
fn contains(map: const PlanMap&,key: u32) -> bool { return get(map,key) != null; }
fn insert(map: PlanMap&,key: u32,value: u32) -> blot_error::Error { blot_support_pooled_map::insert(map,key,value,PlanMap_slots); return blot_error::Error.none; }
fn clear(map: PlanMap&) { blot_support_pooled_map::clear(map); }
fn deinit(map: PlanMap&) { blot_support_pooled_map::deinit(map,PlanMap_slots); }

struct TransportMap { count: i64 = 0,slots: dictionary_slot<u32,blot_backend_storage_transport::Index?>[:] = [] }
reusable[] var TransportMap_slots: dictionary_slot<u32,blot_backend_storage_transport::Index?>[>..] = [];
fn get(map: const TransportMap&,key: u32) -> blot_backend_storage_transport::Index?? { blot_support_pooled_map::get(map,key) }
fn contains(map: const TransportMap&,key: u32) -> bool { return get(map,key) != null; }
fn insert(map: TransportMap&,key: u32,value: blot_backend_storage_transport::Index?) -> blot_error::Error { blot_support_pooled_map::insert(map,key,value,TransportMap_slots); return blot_error::Error.none; }
fn clear(map: TransportMap&) { blot_support_pooled_map::clear(map); }
fn deinit(map: TransportMap&) { blot_support_pooled_map::deinit(map,TransportMap_slots); }

struct DeclinedCalls { count: i64 = 0,slots: dictionary_slot<blot_backend_storage_calls::Key,bool>[:] = [] }
reusable[] var DeclinedCalls_slots: dictionary_slot<blot_backend_storage_calls::Key,bool>[>..] = [];
fn get(map: const DeclinedCalls&,key: blot_backend_storage_calls::Key) -> bool? { blot_support_pooled_map::get(map,key) }
fn contains(map: const DeclinedCalls&,key: blot_backend_storage_calls::Key) -> bool { return get(map,key) != null; }
fn insert(map: DeclinedCalls&,key: blot_backend_storage_calls::Key,value: bool) -> blot_error::Error { blot_support_pooled_map::insert(map,key,value,DeclinedCalls_slots); return blot_error::Error.none; }
fn clear(map: DeclinedCalls&) { blot_support_pooled_map::clear(map); }
fn deinit(map: DeclinedCalls&) { blot_support_pooled_map::deinit(map,DeclinedCalls_slots); }

struct Dispatches { count: i64 = 0,slots: dictionary_slot<DispatchKey,blot_support::Option<blot_check_core::BindingRef>>[:] = [] }
reusable[] var Dispatches_slots: dictionary_slot<DispatchKey,blot_support::Option<blot_check_core::BindingRef>>[>..] = [];
fn get(map: const Dispatches&,key: DispatchKey) -> blot_support::Option<blot_check_core::BindingRef>? { blot_support_pooled_map::get(map,key) }
fn contains(map: const Dispatches&,key: DispatchKey) -> bool { return get(map,key) != null; }
fn insert(map: Dispatches&,key: DispatchKey,value: blot_support::Option<blot_check_core::BindingRef>) -> blot_error::Error { blot_support_pooled_map::insert(map,key,value,Dispatches_slots); return blot_error::Error.none; }
fn clear(map: Dispatches&) { blot_support_pooled_map::clear(map); }
fn deinit(map: Dispatches&) { blot_support_pooled_map::deinit(map,Dispatches_slots); }

struct DispatchKey { unit: u32,identity: blot_check_types::NominalIdentity,member: u32,operator: blot_check_types::Operator,field: bool = false }
fn hash(key: DispatchKey) -> u64 { var result = ::hash(key.unit); result = result ^ ::hash((key.identity.unit as u64 << 32) | key.identity.decl); result = result ^ ::hash((key.member as u64 << 32) | blot_check_types::operatorCode(key.operator)); return result ^ ::hash(key.field); }
reusable[] var call_evidence_runs: u32[>..] = [];
struct DescriptorCalls {
    metadata: Metadata&,calls: blot_backend_storage_calls::Cache,plans: PlanMap,declined: DeclinedCalls,addressed_declined: DeclinedCalls,transports: TransportMap,
    record_metadata: RecordMetadataCache&,global_footprint: blot_support::Option<blot_backend_storage_global_footprint::Index>,primitive_evidence: Range,
    recursion: blot_backend_storage_recursive_admission::Cache,
}
fn initPrimitiveEvidence(self: DescriptorCalls&,units: const blot_check_core::Module[:]) -> blot_error::Error {
    if units.len > 858993459 { return blot_error::Error.out_of_memory; } let first = self.metadata.evidence.len;
    for unit in units { for primitive in 0..5 { self.metadata.evidence.push(TypeEvidence { root: TypeRef { unit: unit.unit,ty: blot_check_types::unit + primitive as u32,environment: blot_support::none<Range>() },arguments: Range {} }); } }
    self.primitive_evidence = Range { start: first,len: units.len * 5 }; return blot_error::Error.none;
}
fn copyEvidenceKey(self: DescriptorCalls&,key: blot_backend_storage_calls::Key) -> blot_backend_storage_calls::Key,blot_error::Error {
    var owned = key; if key.evidence.len != 0 { let values = call_evidence_runs.alloc_slice(key.evidence.len); for word,index in key.evidence { values[index] = word; } owned.evidence = values; } return owned,blot_error::Error.none;
}
fn decline(self: DescriptorCalls&,key: blot_backend_storage_calls::Key) -> blot_error::Error { if self.declined.contains(key) { return blot_error::Error.none; } let owned,error = copyEvidenceKey(self,key); if error != blot_error::Error.none { return error; } return self.declined.insert(owned,true); }
fn declineAddressed(self: DescriptorCalls&,key: blot_backend_storage_calls::Key) -> blot_error::Error { if self.addressed_declined.count >= 4096 || self.addressed_declined.contains(key) { return blot_error::Error.none; } let owned,error = copyEvidenceKey(self,key); if error != blot_error::Error.none { return error; } return self.addressed_declined.insert(owned,true); }
fn deinit(self: DescriptorCalls&) { self.recursion.deinit(); if self.global_footprint.present { self.global_footprint.value.deinit(); } self.global_footprint = blot_support::none<blot_backend_storage_global_footprint::Index>(); self.calls.deinit(); self.plans.deinit(); for slot in self.declined.slots { if slot.tag != 0 && slot.key.evidence.len != 0 { call_evidence_runs.free_slice(slot.key.evidence); } } for slot in self.addressed_declined.slots { if slot.tag != 0 && slot.key.evidence.len != 0 { call_evidence_runs.free_slice(slot.key.evidence); } } self.declined.deinit(); self.addressed_declined.deinit(); for slot in self.transports.slots { if slot.tag != 0 && slot.val != null { slot.val.deinit(); } } self.transports.deinit(); self.record_metadata.entries.clear(); self.record_metadata.fields.clear(); }
struct MethodSelector { units: const blot_check_core::Module[:],entry: u32,allocation_owner: u64,session: blot_eval_core_eval::Session? = null,bounds: blot_check_scheme_equations::Workspace& }
fn deinit(self: MethodSelector&) { if self.session { blot_eval_core_eval::deinitOwnedSession(self.session); self.session .= null; } self.bounds.deinit(); }
fn get(self: MethodSelector&) -> blot_eval_core_eval::Session?,blot_error::Error {
    if self.session == null { let session,error = blot_eval_core_eval::initOwnedSession(self.units,self.allocation_owner); if error != blot_error::Error.none { return null,error; } assert(session); self.session .= session; self.session.diagnostic_context.entry = self.entry; } return self.session,blot_error::Error.none;
}
struct Generator {
    metadata: Metadata&,uses: const u32[:] = [],active_goals: const blot_check_core::Obligation[:] = [],entry_unit: u32,
    specialization_origin: blot_support::Option<blot_eval_core_eval::SourceLocation>,context_sensitive: bool = false,
    methods: MethodSelector&,calls: blot_backend_storage_calls::Cache,shared_calls: blot_backend_storage_calls::Cache&,descriptor_calls: DescriptorCalls&,field_recipes: blot_backend_storage_field_plan::Cache&,
    numeric_call_peak: i64 = 0,scalar_admission: blot_backend_storage_calls::ScalarAdmission&,active_calls: blot_backend_storage_calls::ActiveCalls&,specialize: bool = true,
    protected: Values,append_regions: AppendRegions,units: const blot_check_core::Module[:],module: blot_backend_wasm::Module&,runtime: blot_runtime_data_stacks::Runtime,
    transport: blot_support::Option<blot_runtime_storage_packets::Runtime>,transport_region: blot_support::Option<u32>,fixed_region: u32 = 0,destination: blot_support::Option<Value>,external_destination: blot_support::Option<i64>,
    c: blot_backend_runtime_code::Code<blot_backend_wasm::Module>,zero_source: ZeroSource,recursive_header: blot_support::Option<RecursiveHeader>,recursive_scope: bool = false,input_bundles: Range,
    bundle_snapshots: BundleSnapshots,bundle_scan: i64 = 0,bundle_function: blot_support::Option<u32>,bundle_retained_bytes: i64 = 0,bundle_retained_count: i64 = 0,bundle_sources: WordSet,
    span_scopes: blot_backend_storage_span_dominance::Scopes,stacks: Flags,globals: Globals,globals_ready: bool = false,global_roots: Range,type_arguments: blot_backend_storage_type_arguments::Stack<TypeArgument>,
    max_stacks: u32 = 0,used_regions: IndexSet,roots: Roots,bindings: Bindings,controls: Controls,mutable_join_words: WordSet,indexed_mutable_roots: i64 = 0,loops: Loops,read_frames: ReadFrames,
    diagnostic: blot_support::Option<blot_backend_core_backend::Diagnostic>,depth: i64 = 0,nesting: u32 = 0,steps: i64 = 0,work_limits: WorkLimits,emission_work: blot_work_counters::Counters&,outlining: blot_backend_wasm_scope_outline::Context&,layout_steps: i64 = 0,
    plain_layouts: PlainLayouts,writer_trace: blot_support::Option<u32>,planning_writer: bool = false,emitting_function_plan: bool = false,planning_owner_graph: bool = false,
    validation_budget: i64&,proof_cache: blot_check_package_core::SourceProofCache&,dispatches: Dispatches&,capacity_requests: blot_backend_storage_plan::CapacityRequests&,capacity_prefix: blot_support::Option<i64>,invalid_literals: WordSet,
}
fn deinit(self: Generator&) {
    self.span_scopes.deinit(); self.calls.deinit(); self.protected.deinit(); self.append_regions.deinit(); self.roots.deinit(); self.stacks.deinit(); self.used_regions.deinit(); self.globals.deinit(); self.type_arguments.deinit(); self.invalid_literals.deinit(); self.mutable_join_words.deinit(); self.bundle_snapshots.deinit(); self.bundle_sources.deinit(); self.plain_layouts.deinit(); self.bindings.deinit(); for &control in self.controls.items { control.result.physical.deinit(); } self.controls.deinit(); self.loops.deinit(); self.read_frames.deinit();
}
fn boxCallable(self: Generator&,source: Callable) -> u32,blot_error::Error { if self.metadata.callables.len >= 4294967295 { return 0,blot_error::Error.out_of_memory; } let id = self.metadata.callables.len as u32; self.metadata.callables.push(source); return id,blot_error::Error.none; }
fn fail(self: Generator&,module: const blot_check_core::Module&,id: u32,code: blot_backend_core_backend::Code,detail: const u8[:]) -> blot_error::Error { if !self.diagnostic.present { self.diagnostic = blot_support::some(blot_backend_core_backend::Diagnostic { unit: module.unit,span: module.span(id),code,detail }); } return blot_error::Error.declined; }
fn unsupported(self: Generator&,module: const blot_check_core::Module&,id: u32) -> blot_error::Error { fail(self,module,id,blot_backend_core_backend::Code.storage_unsupported,"This form is not yet supported by the bounded scoped-storage backend") }
fn unit(self: Generator&,id: u32) -> const blot_check_core::Module?,blot_error::Error { if id == 0 || id > self.units.len { return null,blot_error::Error.declined; } return self.units[id - 1],blot_error::Error.none; }
fn boxTypeEvidence(self: Generator&,source: TypeEvidence) -> u32,blot_error::Error {
    if !source.root.environment.present && source.arguments.len == 0 && source.root.ty >= blot_check_types::unit && source.root.ty <= blot_check_types::never && source.root.unit != 0 && source.root.unit <= self.descriptor_calls.primitive_evidence.len / 5 { let index = (source.root.unit - 1) as i64 * 5 + (source.root.ty - blot_check_types::unit) as i64; if index < self.descriptor_calls.primitive_evidence.len { let id = self.descriptor_calls.primitive_evidence.start + index; if self.metadata.evidence[id].root.unit == source.root.unit { return id as u32,blot_error::Error.none; } } }
    if self.metadata.evidence.len >= 4294967295 { return 0,blot_error::Error.out_of_memory; } return boxTypeEvidenceIn(self.metadata.evidence,source),blot_error::Error.none;
}
fn constant(self: Generator&,number: u32) -> Value,blot_error::Error { let word,error = self.c.temp(); if error != blot_error::Error.none { return Value {},error; } let written = self.c.set(word,number); if written != blot_error::Error.none { return Value {},written; } return Value { word },blot_error::Error.none; }
fn unitValue(self: Generator&) -> Value,blot_error::Error { let word,error = self.zero_source.get(self.c); if error != blot_error::Error.none { return Value {},error; } saturate(self.emission_work.scoped_zero_values_shared,1); return Value { word },blot_error::Error.none; }
fn terminated(self: Generator&) -> Value,blot_error::Error { var value,error = unitValue(self); if error != blot_error::Error.none { return Value {},error; } value.terminated = true; return value,blot_error::Error.none; }
fn hasWord(value: Value) -> bool { value.tag != ValueTag.aggregate || value.variant_tags.len != 0 }
fn scalar(self: Generator&,module: const blot_check_core::Module&,id: u32,value: Value) -> Local,blot_error::Error { if value.tag != ValueTag.scalar { return Local {},unsupported(self,module,id); } return value.word,blot_error::Error.none; }
fn saturate(counter: u64&,amount: u64) { if amount > 18446744073709551615 - counter { counter = 18446744073709551615; } else { counter += amount; } }
fn knownLiteral(self: Generator&,value: Value) -> blot_support::Option<u32> { if self.invalid_literals.contains(value.word.id) { return blot_support::none<u32>(); } return value.literal; }
fn knownConstant(self: Generator&,value: Value) -> blot_support::Option<u32> { if self.invalid_literals.contains(value.word.id) { return blot_support::none<u32>(); } return value.constant_bits; }
fn immutableBindingValue(self: Generator&,original: Value,parameter: bool) -> Value { var value = original; if value.tag == ValueTag.scalar { value.literal = knownLiteral(self,original); value.constant_bits = knownConstant(self,original); value.depth = self.depth; if parameter { saturate(self.emission_work.scoped_parameter_words_shared,1); } else { saturate(self.emission_work.scoped_local_words_shared,1); } } return value; }
recursive fn snapshot(self: Generator&,original: Value) -> Value,blot_error::Error {
    var value = original; value.literal = knownLiteral(self,original); value.constant_bits = knownConstant(self,original);
    if value.tag == ValueTag.scalar { let word,error = self.c.temp(); if error != blot_error::Error.none { return Value {},error; } value.word = word; let assigned = self.c.set(word,original.word); if assigned != blot_error::Error.none { return Value {},assigned; } value.depth = self.depth; }
    if value.tag == ValueTag.view || value.tag == ValueTag.link || (value.tag == ValueTag.ref && (value.root.present || value.pool_borrow)) {
        let word,e = self.c.temp(); if e != blot_error::Error.none { return Value {},e; } value.word = word;
        let token,e2 = self.c.temp(); if e2 != blot_error::Error.none { return Value {},e2; } value.token = token;
        let low,e3 = self.c.temp(); if e3 != blot_error::Error.none { return Value {},e3; } value.epoch_low = low;
        let high,e4 = self.c.temp(); if e4 != blot_error::Error.none { return Value {},e4; } value.epoch_high = high;
        let index,e5 = self.c.temp(); if e5 != blot_error::Error.none { return Value {},e5; } value.index = index;
        var error = self.c.set(value.word,original.word); if error != blot_error::Error.none { return Value {},error; } error = self.c.set(value.token,original.token); if error != blot_error::Error.none { return Value {},error; } error = self.c.set(value.epoch_low,original.epoch_low); if error != blot_error::Error.none { return Value {},error; } error = self.c.set(value.epoch_high,original.epoch_high); if error != blot_error::Error.none { return Value {},error; } error = self.c.set(value.index,original.index); if error != blot_error::Error.none { return Value {},error; }
        if value.tag == ValueTag.view { let length,e = self.c.temp(); if e != blot_error::Error.none { return Value {},e; } value.length = length; let assigned = self.c.set(length,original.length); if assigned != blot_error::Error.none { return Value {},assigned; } }
    }
    if value.tag == ValueTag.aggregate { if value.variant_tags.len != 0 { let word,error = self.c.temp(); if error != blot_error::Error.none { return Value {},error; } value.word = word; let assigned = self.c.set(word,original.word); if assigned != blot_error::Error.none { return Value {},assigned; } } let destination = allocateFields(self.metadata,value,original.fields.len); for index in 0..original.fields.len { let input = self.metadata.values[original.fields.start + index]; let result,error = snapshot(self,input); if error != blot_error::Error.none { return Value {},error; } self.metadata.values[destination.start + index] = result; } }
    return value,blot_error::Error.none;
}
fn bind(self: Generator&,module: const blot_check_core::Module&,id: u32,original: Value) -> blot_error::Error { var value = original; if !self.scalar_admission.hasScalarReferences() { value = immutableBindingValue(self,original,module.binding(id).kind == blot_check_core::BindingKind.parameter); } else { let copied,error = snapshot(self,original); if error != blot_error::Error.none { return error; } value = copied; } var remaining: u32 = 0; if id < self.uses.len { remaining = self.uses[id]; } return self.bindings.push(Binding { unit: module.unit,id,value,remaining }); }
fn bindingValue(self: Generator&,module: const blot_check_core::Module&,id: u32) -> Value,blot_error::Error { var index = self.bindings.items.len; while index != 0 { index--; let binding: Binding& = self.bindings.items[index]; if binding.unit == module.unit && binding.id == id { if binding.remaining != 0 { binding.remaining--; } return binding.value,blot_error::Error.none; } } return Value {},blot_error::Error.declined; }
fn returnedRoot(self: Generator&,index: i64) -> bool { for control in self.controls.items { if control.result.value.present && hasRoot(self.metadata,control.result.value.value,index) { return true; } } return false; }
fn closeRuntime(self: Generator&,first: i64,keep: Value) -> blot_error::Error { var cursor = self.roots.items.len; while cursor > first { cursor--; let owner = self.roots.items[cursor]; if !owner.live || owner.persistent || hasRoot(self.metadata,keep,cursor) { continue; } var error = self.c.value(owner.token); if error != blot_error::Error.none { return error; } error = self.c.value(owner.epoch_low); if error != blot_error::Error.none { return error; } error = self.c.value(owner.epoch_high); if error != blot_error::Error.none { return error; } error = self.c.op(blot_backend_runtime_ir::OP_call,self.runtime.functions.close); if error != blot_error::Error.none { return error; } error = self.c.set(owner.token,0); if error != blot_error::Error.none { return error; } } return blot_error::Error.none; }
fn frameMark(self: Generator&) -> FrameMark,blot_error::Error { let mark,error = self.c.temp(); if error != blot_error::Error.none { return FrameMark {},error; } let first = self.module.instructions(self.c.function).len; var assigned = self.c.value(self.fixed_region); if assigned != blot_error::Error.none { return FrameMark {},assigned; } assigned = self.c.op(blot_backend_runtime_ir::OP_call,self.runtime.functions.mark); if assigned != blot_error::Error.none { return FrameMark {},assigned; } assigned = self.c.set(mark); if assigned != blot_error::Error.none { return FrameMark {},assigned; } return FrameMark { word: mark,first,end: self.module.instructions(self.c.function).len },blot_error::Error.none; }
fn rewindUnescaped(self: Generator&,first: i64,mark: FrameMark,keep: Value) -> blot_error::Error {
    if first == self.roots.items.len { let error = self.module.materializeBody(self.c.function); if error != blot_error::Error.none { return error; } let body = self.module.functions[self.c.function].instructions; for index in mark.first..mark.end { self.module.instructions[body.start + index] = blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_nop); } return blot_error::Error.none; }
    if self.external_destination.present && hasRoot(self.metadata,keep,self.external_destination.value) { return blot_error::Error.none; } for index in first..self.roots.items.len { if hasRoot(self.metadata,keep,index) { return blot_error::Error.none; } }
    var error = self.c.value(self.fixed_region); if error != blot_error::Error.none { return error; } error = self.c.value(mark.word); if error != blot_error::Error.none { return error; } return self.c.op(blot_backend_runtime_ir::OP_call,self.runtime.functions.rewind);
}
fn root(self: Generator&,module: const blot_check_core::Module&,id: u32,value: Value) -> Root?,blot_error::Error { if !value.root.present { return null,unsupported(self,module,id); } return self.roots.items[value.root.value],blot_error::Error.none; }
fn borrowed(self: Generator&,owner: Value) -> bool { for binding in self.bindings.items { if binding.remaining != 0 && borrows(self.metadata,binding.value,owner) { return true; } } for value in self.protected.items { if borrows(self.metadata,value,owner) { return true; } } for root in self.roots.items { if root.live && borrows(self.metadata,root.element,owner) { return true; } } return false; }
