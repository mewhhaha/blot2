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
        let source = units[current.unit - 1]; if current.id >= source.nodes.len { return true, blot_error::Error.none; }
        let key = (current.unit as u64 << 32) | current.id; if seen.contains(key) { continue; } seen.insert(key, true);
        let node = source.node(current.id); if node.tag == blot_check_core::Tag.storage { return true, blot_error::Error.none; }
        if node.tag == blot_check_core::Tag.update { for selector in source.updateSelectors(current.id) { if selectorIsIndex(selector) { return true, blot_error::Error.none; } } }
        let ty = source.types.node(node.ty); if ty.tag == blot_check_types::Tag.nominal && blot_check_storage_types::identity(ty.a, ty.b).present { return true, blot_error::Error.none; }
        if node.tag == blot_check_core::Tag.reference || node.tag == blot_check_core::Tag.call {
            var target = blot_check_core::BindingRef {}; if node.tag == blot_check_core::Tag.call { target = source.call(current.id).target; } else { target = source.reference(current.id); }
            if target.unit == 0 { target.unit = source.unit; } if target.unit == 0 || target.unit > units.len { return true, blot_error::Error.none; }
            let producer = units[target.unit - 1]; if target.binding >= producer.bindings.len { return true, blot_error::Error.none; }
            let body = producer.body(target.binding); if body.present { pending.push(RequiredNode { unit: target.unit, id: body.value.root }); }
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
