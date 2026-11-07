// A run owns serialized-value addresses and static closure publications.
namespace blot_backend_backend_static_data;
import .layout;
import eval.core_eval;
import support.error;
import support.pooled_map;
import support.pooled_buffer;
type Error = blot_error::Error;
struct SerializedKey { value: blot_eval_core_eval::ValueId,ty: blot_backend_layout::Id }
fn hash(key: SerializedKey) -> u64 { ::hash((key.value as u64 << 32) | key.ty) }
type Cache = blot_support_pooled_map::Map<SerializedKey,u32>;
reusable[] var cache_slots: dictionary_slot<SerializedKey,u32>[>..] = [];
fn get(self_: const Cache&,key: SerializedKey) -> u32? { blot_support_pooled_map::get(self_,key) }
fn insert(self_: Cache&,key: SerializedKey,value: u32) -> Error { blot_support_pooled_map::insert(self_,key,value,cache_slots); return blot_error::Error.none; }
fn remove(self_: Cache&,key: SerializedKey) -> bool { blot_support_pooled_map::remove(self_,key) }
fn clear(self_: Cache&) { blot_support_pooled_map::clear(self_); }
fn deinit(self_: Cache&) { blot_support_pooled_map::deinit(self_,cache_slots); }
struct Closures { storage: u32[:] = default<u32[:]>(),items: u32[:] = default<u32[:]>() }
reusable[] var closure_runs: u32[>..] = [];
fn push(self_: Closures&,value: u32) -> Error { blot_support_pooled_buffer::push(self_,value,closure_runs) }
fn clear(self_: Closures&) { blot_support_pooled_buffer::clear(self_); }
fn deinit(self_: Closures&) { blot_support_pooled_buffer::deinit(self_,closure_runs); }
struct State { cache: Cache,closures: Closures }
fn init() -> State { State {..} }
fn deinit(self_: State&) { self_.cache.deinit(); self_.closures.deinit(); }
import .core_backend;
import .backend_emission;
import .runtime_ir;
import .substitution_buffers;
import .numeric_rows;
import .startup_emission_facts;
import check.core;
import check.types;
import check.task_types;
import eval.eval_values;
import eval.type_evidence;
import reuse.artifact_emitter;
import runtime.runtime_layout;
import runtime.runtime_cleanup;
import runtime.list_runtime;
import support.option;
type Generator = blot_backend_core_backend::Generator;
type Code = blot_backend_core_backend::Code;
type Tag = blot_backend_layout::Tag;
type ValueId = blot_eval_core_eval::ValueId;
type ValueInfo = blot_eval_core_eval::ValueInfo;
type ValueKind = blot_eval_core_eval::ValueKind;
type Words = blot_backend_substitution_buffers::Words;
type Mappings = blot_backend_substitution_buffers::Mappings;
type Rows = blot_backend_substitution_buffers::Rows;
fn staticFailure(g: Generator&,owner: u32,code: Code) -> Error { return g.decline(owner,blot_check_core::Span {..},code); }
fn representation(g: Generator&,evidence: u32,owner: u32) -> u32,Error {
    let result,error = g.representations.fromEvidence(g.evaluator.evidenceStore(),evidence);
    if error == blot_error::Error.none || error == blot_error::Error.out_of_memory { return result,error; }
    return 0,staticFailure(g,owner,blot_check_diagnostic_code::Code.unresolved_type);
}
fn staticOwner(g: Generator&,unit: u32,mappings: const blot_backend_layout::Mapping[:]) -> blot_backend_backend_emission::Owner,Error {
    let cleanup,error = blot_runtime_runtime_cleanup::initPooled();
    return blot_backend_backend_emission::Owner { generator: g,unit_id: unit,function_id: 0,provider_local: blot_support::some(0 as u32),mappings: mappings,cleanups: cleanup,..},error;
}
recursive fn taskCallbackRows(source: const blot_check_core::Module&,ty: u32,depth: i64) -> bool {
    if depth >= 128 { return false; } if blot_check_task_types::scopeCallback(source.types,ty).present { return true; }
    let node = source.types.node(ty);
    if node.tag == blot_check_types::Tag.function { return taskCallbackRows(source,node.a,depth + 1) || taskCallbackRows(source,node.b,depth + 1); }
    if node.tag == blot_check_types::Tag.usage || node.tag == blot_check_types::Tag.forall { return taskCallbackRows(source,node.a,depth + 1); }
    return false;
}
fn reference(g: Generator&,address: u32,bits: u32) -> Error { return g.module.dataReference(address,blot_reuse_artifact_emitter::Operand { role: blot_reuse_artifact_emitter::Role.static_address,value: bits,..}); }
fn dataValueReference(self_: State&,g: Generator&,address: u32,value: ValueId,bits: u32) -> Error {
    if bits == 0 { return blot_error::Error.none; } var child = value;
    for attempt in 0..256 {
        if g.evaluator.valueScalar(child).present { return blot_error::Error.none; }
        let info = g.evaluator.valueInfo(child); if info.kind != blot_eval_eval_values::ValueKind.nominal || info.len != 1 { break; }
        let owner = (info.nominal >> 32) as u32; let declaration = info.nominal as u32; var opaque = false;
        for nominal in g.unit(owner).nominals { if nominal.identity.decl == declaration && nominal.is_opaque { opaque = true; break; } }
        if !opaque { break; } child = g.evaluator.valueChildren(child)[0];
    }
    return reference(g,address,bits);
}
fn closureData(self_: State&,g: Generator&,function_id: u32,environment: u32) -> u32,Error {
    let address,error = g.module.dataWords([function_id,environment]); if error != blot_error::Error.none { return 0,error; }
    let callable = g.module.dataReference(address,blot_reuse_artifact_emitter::Operand { role: blot_reuse_artifact_emitter::Role.callable_function,value: function_id,..}); if callable != blot_error::Error.none { return 0,callable; }
    let captured = reference(g,address + blot_runtime_runtime_layout::Closure_environment,environment); return address,captured;
}
recursive fn serializeCarrier(self_: State&,g: Generator&,value: ValueId,from: u32,to: u32,owner: u32,depth: i64) -> u32,Error {
    if depth >= 128 { return 0,staticFailure(g,owner,blot_check_diagnostic_code::Code.complexity); }
    if from == to { return serialize(self_,g,value,to,depth + 1); }
    let input = g.representations.store.node(from); let output = g.representations.store.node(to);
    if output.tag == blot_backend_layout::Tag.opened || output.tag == blot_backend_layout::Tag.associated {
        let payload,error = serialize(self_,g,value,from,depth + 1); if error != blot_error::Error.none { return 0,error; }
        let cell,allocated = g.module.dataWords([0,payload]); if allocated != blot_error::Error.none { return 0,allocated; }
        if g.layoutRole(from) == blot_backend_runtime_ir::ROLE_reference { let marked = dataValueReference(self_,g,cell + 4,value,payload); if marked != blot_error::Error.none { return 0,marked; } }
        return cell,blot_error::Error.none;
    }
    if input.tag != output.tag { return 0,staticFailure(g,owner,blot_check_diagnostic_code::Code.unresolved_type); }
    if input.tag == blot_backend_layout::Tag.function {
        let initialized,error = staticOwner(g,owner,[]); if error != blot_error::Error.none { return 0,error; } var emitter = initialized;
        let rows = emitter.carrierRows(input.c,output.c,0); if rows != blot_error::Error.none { emitter.deinit(); return 0,rows; }
        let adapter,adapted = emitter.carrierFunction(from,to,depth + 1); emitter.deinit(); if adapted != blot_error::Error.none { return 0,adapted; }
        let captured,serialized = serialize(self_,g,value,from,depth + 1); if serialized != blot_error::Error.none { return 0,serialized; } return closureData(self_,g,adapter,captured);
    }
    if input.tag == blot_backend_layout::Tag.nominal {
        let info = g.evaluator.valueInfo(value);
        if input.a != output.a || input.b != output.b || info.kind != blot_eval_eval_values::ValueKind.nominal || info.len > 1 { return 0,staticFailure(g,owner,blot_check_diagnostic_code::Code.unresolved_type); }
        if g.representations.store.scalar(to).present { return info.bits,blot_error::Error.none; }
        var payload: u32 = 0; var payload_reference = false;
        if info.len != 0 {
            let actual,error = g.nominalPayload(info.nominal,info.bits,from); if error != blot_error::Error.none { return 0,error; }
            let expected,expected_error = g.nominalPayload(info.nominal,info.bits,to); if expected_error != blot_error::Error.none { return 0,expected_error; }
            payload_reference = g.layoutRole(expected) == blot_backend_runtime_ir::ROLE_reference;
            let converted,conversion_error = serializeCarrier(self_,g,g.evaluator.valueChildren(value)[0],actual,expected,owner,depth + 1); if conversion_error != blot_error::Error.none { return 0,conversion_error; } payload = converted;
        }
        let producer = (info.nominal >> 32) as u32; let declaration = info.nominal as u32;
        for nominal in g.unit(producer).nominals { if nominal.identity.decl == declaration && nominal.is_opaque { return payload,blot_error::Error.none; } }
        let address,error = g.module.dataWords([info.bits,payload]); if error != blot_error::Error.none { return 0,error; }
        if payload_reference { let marked = reference(g,address + 4,payload); if marked != blot_error::Error.none { return 0,marked; } } return address,blot_error::Error.none;
    }
    var words = Words {..}; var leaves = Words {..};
    recursive fn aggregate() -> u32,Error {
        if input.tag == blot_backend_layout::Tag.array || input.tag == blot_backend_layout::Tag.list {
            let row_words,error = g.rowWords(output.a); if error != blot_error::Error.none { return 0,error; } if row_words != 0 { return 0,staticFailure(g,owner,blot_check_diagnostic_code::Code.unsupported); }
            let count = g.evaluator.valueChildren(value).len;
            if input.tag == blot_backend_layout::Tag.array { let added = words.push(count as u32); if added != blot_error::Error.none { return 0,added; } }
            for index in 0..count { let child = g.evaluator.valueChildren(value)[index]; let converted,error = serializeCarrier(self_,g,child,input.a,output.a,owner,depth + 1); if error != blot_error::Error.none { return 0,error; } let added = words.push(converted); if added != blot_error::Error.none { return 0,added; } }
            if input.tag == blot_backend_layout::Tag.array {
                let address,error = g.module.dataWords(words.items); if error != blot_error::Error.none { return 0,error; }
                if g.layoutRole(output.a) == blot_backend_runtime_ir::ROLE_reference { for index in 1..words.items.len { let marked = reference(g,address + (index * 4) as u32,words.items[index]); if marked != blot_error::Error.none { return 0,marked; } } } return address,blot_error::Error.none;
            }
            var offset: i64 = 0;
            while offset < words.items.len {
                let end = min(words.items.len,offset + blot_runtime_list_runtime::leafLimit(1));
                let leaf,error = blot_runtime_list_runtime::staticChunk(g.module,words.items[offset..end]); if error != blot_error::Error.none { return 0,error; }
                if g.layoutRole(output.a) == blot_backend_runtime_ir::ROLE_reference { for index in offset..end { let marked = reference(g,leaf + blot_runtime_list_runtime::header + ((index - offset) * 4) as u32,words.items[index]); if marked != blot_error::Error.none { return 0,marked; } } }
                let added = leaves.push(leaf); if added != blot_error::Error.none { return 0,added; } offset = end;
            }
            if g.layoutRole(output.a) == blot_backend_runtime_ir::ROLE_scalar { return blot_runtime_list_runtime::staticScalarDescriptor(g.module,count as u32,leaves.items,1); }
            return blot_runtime_list_runtime::staticDescriptor(g.module,count as u32,leaves.items);
        }
        if input.tag == blot_backend_layout::Tag.product || input.tag == blot_backend_layout::Tag.record {
            let field_count = g.representations.store.children(from).len; let record = input.tag == blot_backend_layout::Tag.record; var stride: i64 = 1; var bias: i64 = 0; if record { stride = 2; bias = 1; }
            if field_count != g.representations.store.children(to).len || g.evaluator.valueChildren(value).len != field_count / stride { return 0,staticFailure(g,owner,blot_check_diagnostic_code::Code.unresolved_type); }
            for index in 0..field_count / stride {
                var slot = index;
                if record {
                    let name = g.representations.store.children(from)[index * 2]; if name != g.representations.store.children(to)[index * 2] { return 0,staticFailure(g,owner,blot_check_diagnostic_code::Code.unresolved_type); }
                    var found = false; var at: i64 = 0; for field in g.evaluator.recordFieldNames(value) { if field == name { slot = at; found = true; break; } at++; }
                    if !found { return 0,staticFailure(g,owner,blot_check_diagnostic_code::Code.unresolved_type); }
                }
                let child = g.evaluator.valueChildren(value)[slot]; let position = index * stride + bias; let actual = g.representations.store.children(from)[position]; let expected = g.representations.store.children(to)[position];
                let converted,error = serializeCarrier(self_,g,child,actual,expected,owner,depth + 1); if error != blot_error::Error.none { return 0,error; } let added = words.push(converted); if added != blot_error::Error.none { return 0,added; }
            }
            let address,error = g.module.dataWords(words.items); if error != blot_error::Error.none { return 0,error; }
            for index in 0..words.items.len { if g.layoutRole(g.representations.store.children(to)[index * stride + bias]) == blot_backend_runtime_ir::ROLE_reference { let marked = reference(g,address + (index * 4) as u32,words.items[index]); if marked != blot_error::Error.none { return 0,marked; } } } return address,blot_error::Error.none;
        }
        return 0,staticFailure(g,owner,blot_check_diagnostic_code::Code.unsupported);
    }
    let address,error = aggregate(); leaves.deinit(); words.deinit(); return address,error;
}
reusable[] var goal_runs: blot_check_types::Obligation[>..] = [];
fn copyGoals(values: const blot_check_types::Obligation[:]) -> blot_check_types::Obligation[:] { if values.len == 0 { return []; } let result = goal_runs.alloc_slice(values.len); for index in 0..values.len { result[index] = values[index]; } return result; }
fn freeGoals(values: blot_check_types::Obligation[:]) { if values.len != 0 { goal_runs.free_slice(values); } }
recursive fn serializePackage(self_: State&,g: Generator&,value: ValueId,ty: u32,depth: i64) -> u32,Error {
    let info = g.evaluator.valueInfo(value); let package = g.representations.store.node(ty);
    if package.tag != blot_backend_layout::Tag.existential || info.len == 0 || info.bits == 0 || info.nominal > 4294967295 { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); }
    var selected_unit: u32 = 0; var selected_quantifier: u32 = 0; var remaining: i64 = 65536;
    for source in g.units {
        var ordinal: u32 = 0;
        for node in source.types.nodes.items {
            if remaining == 0 { return 0,staticFailure(g,source.unit,blot_check_diagnostic_code::Code.complexity); } remaining--;
            if node.tag == blot_check_types::Tag.existential {
                let semantic,error = g.evaluator.storage.evidence.projectWithRows(source.types,ordinal,[],[]);
                if error == blot_error::Error.out_of_memory { return 0,error; }
                if error == blot_error::Error.none && semantic == info.bits { selected_unit = source.unit; selected_quantifier = ordinal; break; }
            }
            ordinal++;
        }
        if selected_unit != 0 { break; }
    }
    if selected_unit == 0 { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); }
    let source .= g.unit(selected_unit); let quantifier = source.types.node(selected_quantifier);
    var witnesses = Words {..}; var mappings = Mappings {..}; var words = Words {..}; let goals = copyGoals(source.types.quantifierGoals(selected_quantifier));
    recursive fn build() -> u32,Error {
        let copied = witnesses.append(g.evaluator.storage.evidence.children(info.nominal as u32)); if copied != blot_error::Error.none { return 0,copied; }
        if witnesses.items.len != quantifier.c { return 0,staticFailure(g,selected_unit,blot_check_diagnostic_code::Code.unresolved_type); }
        for index in 0..witnesses.items.len {
            let binder = source.types.list(blot_check_types::List {start: quantifier.b,len: quantifier.c})[index];
            let actual,error = representation(g,witnesses.items[index],selected_unit); if error != blot_error::Error.none { return 0,error; }
            let added = mappings.push(blot_backend_layout::Mapping {variable: binder,layout: actual}); if added != blot_error::Error.none { return 0,added; }
        }
        let payload_type,error = g.representations.store.fromTypeWithRows(source,quantifier.a,mappings.items,[],false);
        if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0,error; } return 0,staticFailure(g,selected_unit,blot_check_diagnostic_code::Code.unresolved_type); }
        let payload,serialized = serializeCarrier(self_,g,g.evaluator.valueChildren(value)[0],payload_type,package.a,selected_unit,depth + 1); if serialized != blot_error::Error.none { return 0,serialized; }
        let appended = words.push(payload); if appended != blot_error::Error.none { return 0,appended; }
        let abstract_value,abstract_error = staticOwner(g,selected_unit,[]); if abstract_error != blot_error::Error.none { return 0,abstract_error; } var abstract = abstract_value;
        let concrete_value,concrete_error = staticOwner(g,selected_unit,mappings.items); if concrete_error != blot_error::Error.none { abstract.deinit(); return 0,concrete_error; } var concrete = concrete_value;
        recursive fn members() -> u32,Error {
            for goal_ordinal in 0..goals.len {
                let goal = goals[goal_ordinal]; var found = false; var members = blot_check_core::List {..};
                for candidate in source.contracts { if candidate.identity == goal.identity { members = candidate.members; found = true; break; } }
                if !found { return 0,staticFailure(g,selected_unit,blot_check_diagnostic_code::Code.unresolved_type); }
                for ordinal in 0..members.len {
                    let member = source.contract_members[members.start + ordinal]; if member.kind != blot_reuse_principal_interface::ContractMemberKind.value { continue; }
                    let index = words.items.len; if index >= info.len { return 0,staticFailure(g,selected_unit,blot_check_diagnostic_code::Code.unresolved_type); }
                    let implementation = g.evaluator.valueChildren(value)[index]; let member_signature = g.evaluator.valueEvidence(implementation); var from: u32 = 0;
                    if member_signature != 0 { let actual,error = representation(g,member_signature,selected_unit); if error != blot_error::Error.none { return 0,error; } from = actual; }
                    else { let actual,error = concrete.dictionaryMemberLayout(0,selected_quantifier,goal_ordinal as u32,ordinal); if error != blot_error::Error.none { return 0,error; } from = actual; }
                    let to,error = abstract.dictionaryMemberLayout(0,selected_quantifier,goal_ordinal as u32,ordinal); if error != blot_error::Error.none { return 0,error; }
                    let converted,conversion_error = serializeCarrier(self_,g,implementation,from,to,selected_unit,depth + 1); if conversion_error != blot_error::Error.none { return 0,conversion_error; }
                    let added = words.push(converted); if added != blot_error::Error.none { return 0,added; }
                }
            }
            if words.items.len != info.len { return 0,staticFailure(g,selected_unit,blot_check_diagnostic_code::Code.unresolved_type); }
            let address,error = g.module.dataWords(words.items); if error != blot_error::Error.none { return 0,error; }
            if g.layoutRole(package.a) == blot_backend_runtime_ir::ROLE_reference { let marked = reference(g,address,words.items[0]); if marked != blot_error::Error.none { return 0,marked; } }
            for index in 1..words.items.len { let marked = reference(g,address + (index * 4) as u32,words.items[index]); if marked != blot_error::Error.none { return 0,marked; } } return address,blot_error::Error.none;
        }
        let result,result_error = members(); concrete.deinit(); abstract.deinit(); return result,result_error;
    }
    let address,error = build(); freeGoals(goals); words.deinit(); mappings.deinit(); witnesses.deinit(); return address,error;
}
recursive fn serialize(self_: State&,g: Generator&,id: ValueId,ty: u32,depth: i64) -> u32,Error {
    if depth >= 256 { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.complexity); }
    let shape = g.representations.store.node(ty);
    if shape.tag == blot_backend_layout::Tag.owning {
        if g.artifacts { g.artifacts.materializeStaticValue(); }
        let payload,error = serialize(self_,g,id,shape.a,depth + 1); if error != blot_error::Error.none { return 0,error; }
        let address,allocated = g.module.dataWords([payload,0]); if allocated != blot_error::Error.none { return 0,allocated; }
        if g.layoutRole(shape.a) == blot_backend_runtime_ir::ROLE_reference { let marked = dataValueReference(self_,g,address,id,payload); if marked != blot_error::Error.none { return 0,marked; } } return address,blot_error::Error.none;
    }
    let scalar = g.evaluator.valueScalar(id); if scalar.present { return scalar.value.bits,blot_error::Error.none; }
    let info = g.evaluator.valueInfo(id);
    if info.kind == blot_eval_eval_values::ValueKind.nominal {
        let owner = (info.nominal >> 32) as u32; let declaration = info.nominal as u32;
        for nominal in g.unit(owner).nominals {
            if !nominal.is_opaque || nominal.identity.decl != declaration { continue; }
            if info.len == 0 { return 0,blot_error::Error.none; } if info.len != 1 { return 0,staticFailure(g,owner,blot_check_diagnostic_code::Code.unresolved_type); }
            let payload,error = g.nominalPayload(info.nominal,info.bits,ty); if error != blot_error::Error.none { return 0,error; } return serialize(self_,g,g.evaluator.valueChildren(id)[0],payload,depth + 1);
        }
    }
    let event = g.planning.startup_facts.event(blot_backend_startup_emission_facts::Event {kind: blot_backend_startup_emission_facts::EventKind.retained_value,caller: g.planning.startup_facts.active,target: id,auxiliary: blot_eval_eval_values::valueKindCode(info.kind),..}); if event != blot_error::Error.none { return 0,event; }
    if info.kind == blot_eval_eval_values::ValueKind.type_constructor || info.kind == blot_eval_eval_values::ValueKind.resolver { return 0,blot_error::Error.none; }
    let key = SerializedKey {value: id,ty: ty}; { let known .= self_.cache.get(key); if known { let demanded = g.module.demandResource(blot_reuse_artifact_emitter::ResourceKind.static_data,known,true); return known,demanded; } }
    if g.artifacts { g.artifacts.materializeStaticValue(); }
    if info.kind == blot_eval_eval_values::ValueKind.package { let address,error = serializePackage(self_,g,id,ty,depth); if error != blot_error::Error.none { return 0,error; } let cached = self_.cache.insert(key,address); return address,cached; }
    if info.kind == blot_eval_eval_values::ValueKind.computation || info.kind == blot_eval_eval_values::ValueKind.request_decision { return serializeDecision(self_,g,id,ty,depth,info,key); }
    if info.kind == blot_eval_eval_values::ValueKind.provider || info.kind == blot_eval_eval_values::ValueKind.state_provider { return serializeProvider(self_,g,id,ty,depth,info,key); }
    if info.kind == blot_eval_eval_values::ValueKind.closure { return serializeClosureValue(self_,g,id,ty,depth,info,key); }
    if info.kind == blot_eval_eval_values::ValueKind.cursor {
        if info.len != 1 || shape.tag != blot_backend_layout::Tag.cursor { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); }
        let source = g.evaluator.valueChildren(id)[0]; let pointer,error = serialize(self_,g,source,shape.a,depth + 1); if error != blot_error::Error.none { return 0,error; }
        let address,allocated = g.module.dataWords([pointer,info.bits]); if allocated != blot_error::Error.none { return 0,allocated; }
        let marked = dataValueReference(self_,g,address,source,pointer); if marked != blot_error::Error.none { return 0,marked; } let cached = self_.cache.insert(key,address); return address,cached;
    }
    if info.kind == blot_eval_eval_values::ValueKind.array || info.kind == blot_eval_eval_values::ValueKind.list { let row_words,error = g.collectionRowWords(ty); if error != blot_error::Error.none { return 0,error; } if row_words != 0 { return serializePackedCollection(self_,g,id,ty,depth,info,key,row_words); } }
    return serializeAggregate(self_,g,id,ty,depth,info,key);
}
recursive fn serializeDecision(self_: State&,g: Generator&,id: ValueId,ty: u32,depth: i64,info: ValueInfo,key: SerializedKey) -> u32,Error {
    let shape = g.representations.store.node(ty); if shape.tag != blot_backend_layout::Tag.nominal || shape.a != 4294967295 { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); }
    let arguments = g.representations.store.children(ty); let children = g.evaluator.valueChildren(id);
    if info.kind == blot_eval_eval_values::ValueKind.computation {
        if shape.b != 5 || arguments.len != 1 || children.len != 1 { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); }
        let address,error = serialize(self_,g,children[0],arguments[0],depth + 1); if error != blot_error::Error.none { return 0,error; } let cached = self_.cache.insert(key,address); return address,cached;
    }
    if shape.b != 6 || arguments.len != 3 || children.len != 2 || info.bits > blot_check_core::requestDecisionKindCode(blot_check_core::RequestDecisionKind.break_) { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); }
    var payload_type: u32 = 1; if info.bits == blot_check_core::requestDecisionKindCode(blot_check_core::RequestDecisionKind.reply) { payload_type = arguments[0]; } else if info.bits == blot_check_core::requestDecisionKindCode(blot_check_core::RequestDecisionKind.cancel) { payload_type = arguments[2]; }
    let state_type = arguments[1]; let payload = children[0]; let state = children[1];
    let payload_bits,error = serialize(self_,g,payload,payload_type,depth + 1); if error != blot_error::Error.none { return 0,error; }
    let state_bits,state_error = serialize(self_,g,state,state_type,depth + 1); if state_error != blot_error::Error.none { return 0,state_error; }
    let address,allocated = g.module.dataWords([info.bits,payload_bits,state_bits]); if allocated != blot_error::Error.none { return 0,allocated; }
    let payload_ref = dataValueReference(self_,g,address + blot_runtime_runtime_layout::Decision_payload,payload,payload_bits); if payload_ref != blot_error::Error.none { return 0,payload_ref; }
    let state_ref = dataValueReference(self_,g,address + blot_runtime_runtime_layout::Decision_state,state,state_bits); if state_ref != blot_error::Error.none { return 0,state_ref; } let cached = self_.cache.insert(key,address); return address,cached;
}
recursive fn serializeProvider(self_: State&,g: Generator&,id: ValueId,ty: u32,depth: i64,info: ValueInfo,key: SerializedKey) -> u32,Error {
    let shape = g.representations.store.node(ty); if info.len != 1 { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.constant_expression); }
    let child = g.evaluator.valueChildren(id)[0]; var address: u32 = 0;
    if info.kind == blot_eval_eval_values::ValueKind.provider {
        if shape.tag != blot_backend_layout::Tag.provider { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); } let actual = g.evaluator.valueEvidence(child); if actual == 0 { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); }
        let implementation_type,error = representation(g,actual,1); if error != blot_error::Error.none { return 0,error; }
        let operation,operation_error = g.runtimeOperation(info.bits,1,blot_check_core::Span {..}); if operation_error != blot_error::Error.none { return 0,operation_error; }
        let implementation,serialized = serialize(self_,g,child,implementation_type,depth + 1); if serialized != blot_error::Error.none { return 0,serialized; }
        let allocated,allocation_error = g.module.dataWords([0,implementation]); if allocation_error != blot_error::Error.none { return 0,allocation_error; } address = allocated;
        let marked = dataValueReference(self_,g,address + blot_runtime_runtime_layout::Provider_implementation,child,implementation); if marked != blot_error::Error.none { return 0,marked; }
        let bound = g.runtimeDataWord(address + blot_runtime_runtime_layout::Provider_operation,operation); if bound != blot_error::Error.none { return 0,bound; }
    } else {
        if shape.tag != blot_backend_layout::Tag.state_provider || info.nominal > 4294967295 { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); }
        let read,error = g.runtimeOperation(info.bits,1,blot_check_core::Span {..}); if error != blot_error::Error.none { return 0,error; }
        let write,write_error = g.runtimeOperation(info.nominal as u32,1,blot_check_core::Span {..}); if write_error != blot_error::Error.none { return 0,write_error; }
        let initial,serialized = serialize(self_,g,child,shape.c,depth + 1); if serialized != blot_error::Error.none { return 0,serialized; }
        let allocated,allocation_error = g.module.dataWords([0,0,initial]); if allocation_error != blot_error::Error.none { return 0,allocation_error; } address = allocated;
        let marked = dataValueReference(self_,g,address + blot_runtime_runtime_layout::StateProvider_initial,child,initial); if marked != blot_error::Error.none { return 0,marked; }
        let read_bound = g.runtimeDataWord(address + blot_runtime_runtime_layout::StateProvider_read,read); if read_bound != blot_error::Error.none { return 0,read_bound; }
        let write_bound = g.runtimeDataWord(address + blot_runtime_runtime_layout::StateProvider_write,write); if write_bound != blot_error::Error.none { return 0,write_bound; }
    }
    let cached = self_.cache.insert(key,address); return address,cached;
}
recursive fn serializeClosureValue(self_: State&,g: Generator&,id: ValueId,ty: u32,depth: i64,info: ValueInfo,key: SerializedKey) -> u32,Error {
    let shape = g.representations.store.node(ty);
    if shape.tag == blot_backend_layout::Tag.universal || (shape.tag == blot_backend_layout::Tag.function && g.representations.store.node(shape.a).tag == blot_backend_layout::Tag.universal) { return serializeClosure(self_,g,id,ty,depth); }
    var selected = ty; let initially_expected,conversion_error = g.representations.toEvidence(g.evaluator.evidenceStore(),ty); var expected = initially_expected;
    if conversion_error != blot_error::Error.none {
        if conversion_error == blot_error::Error.out_of_memory { return 0,conversion_error; }
        if conversion_error != blot_error::Error.unresolved_type { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); }
        let inferred,inference_error = g.evaluator.inferClosure(id);
        if inference_error != blot_error::Error.none {
            if inference_error == blot_error::Error.out_of_memory { return 0,inference_error; }
            if g.evaluator.diagnostic.present && g.evaluator.diagnostic.value.code == blot_check_diagnostic_code::Code.unsupported { var budget: i64 = 100000; if !g.retainedLayoutConcrete(ty,true,0,budget) { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); } }
            return 0,g.evaluationFailure();
        }
        let actual,actual_error = representation(g,g.evaluator.valueEvidence(inferred),1); if actual_error != blot_error::Error.none { return 0,actual_error; }
        let completed,completed_error = g.completeRetainedRows(ty,actual,0); if completed_error != blot_error::Error.none { return 0,completed_error; } selected = completed;
        let resolved,resolved_error = g.representations.toEvidence(g.evaluator.evidenceStore(),selected); if resolved_error != blot_error::Error.none { if resolved_error == blot_error::Error.out_of_memory { return 0,resolved_error; } return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); } expected = resolved;
    }
    let specialized,error = g.evaluator.specializeClosure(id,expected); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0,error; } return 0,g.evaluationFailure(); }
    let address,serialized = serializeClosure(self_,g,specialized,selected,depth); if serialized != blot_error::Error.none { return 0,serialized; } let cached = self_.cache.insert(key,address); return address,cached;
}
fn numericChild(g: Generator&,value: ValueId,ty: u32,offset: u32) -> ValueId,Error {
    let node = g.representations.store.node(ty); let values = g.evaluator.valueChildren(value);
    if node.tag == blot_backend_layout::Tag.nominal { if offset != 4 || values.len != 1 { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); } return values[0],blot_error::Error.none; }
    let index = offset / 4;
    if node.tag == blot_backend_layout::Tag.record {
        let fields = g.representations.store.children(ty); if index >= fields.len / 2 { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); } let name = fields[index * 2]; var slot: i64 = 0;
        for field in g.evaluator.recordFieldNames(value) { if field == name && slot < values.len { return values[slot],blot_error::Error.none; } slot++; } return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type);
    }
    if node.tag != blot_backend_layout::Tag.product || index >= values.len { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); } return values[index],blot_error::Error.none;
}
recursive fn numericGuard(g: Generator&,plan: const blot_backend_numeric_rows::Plan&,guard_: blot_support::Option<u8>,values: const ValueId[:]) -> bool {
    if !guard_.present { return true; } let condition = plan.guards[guard_.value]; return numericGuard(g,plan,condition.parent,values) && g.evaluator.valueInfo(values[condition.owner]).bits == condition.tag;
}
recursive fn serializeNumericRow(self_: State&,g: Generator&,row: ValueId,plan: blot_backend_numeric_rows::Plan,depth: i64,words: Words&) -> Error {
    var values: ValueId[32] = [0;32];
    for index in 0..plan.storage_count {
        let storage = plan.storage[index]; if storage.parent.present {
            let owner = storage.parent.value; if !numericGuard(g,plan,plan.storage[owner].guard_,values) { continue; }
            let child,error = numericChild(g,values[owner],plan.storage[owner].layout,storage.offset); if error != blot_error::Error.none { return error; } values[index] = child;
        } else { values[index] = row; }
    }
    var physical: u32[16] = [0;16];
    for leaf in plan.leaves[..plan.leaf_count] {
        if !numericGuard(g,plan,leaf.guard_,values) { continue; } let storage = plan.storage[leaf.owner];
        if leaf.discriminant { physical[leaf.word] = g.evaluator.valueInfo(values[leaf.owner]).bits; continue; }
        let node = g.representations.store.node(storage.layout); var child: u32 = 0;
        if node.tag == blot_backend_layout::Tag.nominal { assert(storage.tag.present); let payload,error = g.nominalPayload((node.a as u64 << 32) | node.b,storage.tag.value,storage.layout); if error != blot_error::Error.none { return error; } child = payload; }
        else { var index = leaf.offset / 4; if node.tag == blot_backend_layout::Tag.record { index = leaf.offset / 2 + 1; } child = g.representations.store.children(storage.layout)[index]; }
        if g.representations.store.node(child).tag == blot_backend_layout::Tag.unit { continue; }
        let value,error = numericChild(g,values[leaf.owner],storage.layout,leaf.offset); if error != blot_error::Error.none { return error; }
        let bits,serialized = serialize(self_,g,value,child,depth + 1); if serialized != blot_error::Error.none { return serialized; } physical[leaf.word] = bits;
    }
    return words.append(physical[..plan.word_count]);
}
recursive fn serializePackedCollection(self_: State&,g: Generator&,id: ValueId,ty: u32,depth: i64,info: ValueInfo,key: SerializedKey,row_words: u32) -> u32,Error {
    var words = Words {..}; var leaves = Words {..};
    recursive fn build() -> u32,Error {
        if info.kind == blot_eval_eval_values::ValueKind.array { let added = words.push(info.len); if added != blot_error::Error.none { return 0,added; } }
        let element = g.representations.store.node(ty).a; let row_tag = g.representations.store.node(element).tag; let fields = g.representations.store.children(element);
        let nested,error = g.nestedRow(element); if error != blot_error::Error.none { return 0,error; }
        for row in g.evaluator.valueChildren(id) {
            if nested.present { let serialized = serializeNumericRow(self_,g,row,nested.value,depth,words); if serialized != blot_error::Error.none { return 0,serialized; } continue; }
            let values = g.evaluator.valueChildren(row); if values.len != row_words { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); }
            for index in 0..row_words {
                var slot = index as i64; var field_index = index as i64;
                if row_tag == blot_backend_layout::Tag.record {
                    var found = false; var ordinal: i64 = 0; for name in g.evaluator.recordFieldNames(row) { if name == fields[index * 2] { slot = ordinal; found = true; break; } ordinal++; }
                    if !found { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); } field_index = index * 2 + 1;
                }
                let child_type = fields[field_index]; let bits,serialized = serialize(self_,g,values[slot],child_type,depth + 1); if serialized != blot_error::Error.none { return 0,serialized; } let added = words.push(bits); if added != blot_error::Error.none { return 0,added; }
            }
        }
        var address: u32 = 0;
        if info.kind == blot_eval_eval_values::ValueKind.array { let allocated,error = g.module.dataWords(words.items); if error != blot_error::Error.none { return 0,error; } address = allocated; }
        else {
            var offset: i64 = 0; while offset < words.items.len { let count = min(words.items.len - offset,blot_runtime_list_runtime::leafLimit(row_words)); let leaf,error = blot_runtime_list_runtime::staticChunk(g.module,words.items[offset..offset + count]); if error != blot_error::Error.none { return 0,error; } let added = leaves.push(leaf); if added != blot_error::Error.none { return 0,added; } offset += count; }
            let allocated,error = blot_runtime_list_runtime::staticScalarDescriptor(g.module,words.items.len as u32,leaves.items,row_words); if error != blot_error::Error.none { return 0,error; } address = allocated;
        }
        let cached = self_.cache.insert(key,address); return address,cached;
    }
    let address,error = build(); leaves.deinit(); words.deinit(); return address,error;
}
recursive fn serializeAggregate(self_: State&,g: Generator&,id: ValueId,ty: u32,depth: i64,info: ValueInfo,key: SerializedKey) -> u32,Error {
    var words = Words {..}; var word_values = Words {..}; var leaves = Words {..};
    recursive fn build() -> u32,Error {
        if info.kind == blot_eval_eval_values::ValueKind.effect_set || info.kind == blot_eval_eval_values::ValueKind.effect_descriptor { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.backend_const_only); }
        if info.kind == blot_eval_eval_values::ValueKind.nominal {
            var payload_type: u32 = 0; var payload_bits: u32 = 0; var payload_value: u32 = 0;
            if info.len != 0 { let payload,error = g.nominalPayload(info.nominal,info.bits,ty); if error != blot_error::Error.none { return 0,error; } payload_type = payload; payload_value = g.evaluator.valueChildren(id)[0]; let bits,serialized = serialize(self_,g,payload_value,payload_type,depth + 1); if serialized != blot_error::Error.none { return 0,serialized; } payload_bits = bits; }
            let added = words.append([info.bits,payload_bits]); if added != blot_error::Error.none { return 0,added; } let values_added = word_values.append([0,payload_value]); if values_added != blot_error::Error.none { return 0,values_added; }
        } else {
            if info.kind == blot_eval_eval_values::ValueKind.array { let added = words.push(info.len); if added != blot_error::Error.none { return 0,added; } let value_added = word_values.push(0); if value_added != blot_error::Error.none { return 0,value_added; } }
            let node = g.representations.store.node(ty);
            if info.kind == blot_eval_eval_values::ValueKind.record {
                if g.evaluator.recordFieldNames(id).len != info.len || g.representations.store.children(ty).len != info.len as i64 * 2 { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); }
                var index: i64 = 0;
                while index < info.len {
                    let name = g.representations.store.children(ty)[index * 2]; let child_type = g.representations.store.children(ty)[index * 2 + 1]; var found = false; var slot: i64 = 0; var source_slot: i64 = 0;
                    for field in g.evaluator.recordFieldNames(id) { if field == name { source_slot = slot; found = true; break; } slot++; }
                    if !found { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.unresolved_type); } let child = g.evaluator.valueChildren(id)[source_slot];
                    let bits,error = serialize(self_,g,child,child_type,depth + 1); if error != blot_error::Error.none { return 0,error; } let added = words.push(bits); if added != blot_error::Error.none { return 0,added; } let value_added = word_values.push(child); if value_added != blot_error::Error.none { return 0,value_added; } index++;
                }
            } else {
                for index in 0..info.len {
                    var child_type: u32 = 0; if info.kind == blot_eval_eval_values::ValueKind.array || info.kind == blot_eval_eval_values::ValueKind.list { child_type = node.a; } else if info.kind == blot_eval_eval_values::ValueKind.product { child_type = g.representations.store.children(ty)[index]; } else { abort("invalid retained aggregate value"); }
                    let child = g.evaluator.valueChildren(id)[index]; let bits,error = serialize(self_,g,child,child_type,depth + 1); if error != blot_error::Error.none { return 0,error; }
                    let added = words.push(bits); if added != blot_error::Error.none { return 0,added; } let value_added = word_values.push(child); if value_added != blot_error::Error.none { return 0,value_added; }
                }
            }
        }
        if info.kind == blot_eval_eval_values::ValueKind.list {
            if info.len > 268435456 { return 0,staticFailure(g,1,blot_check_diagnostic_code::Code.complexity); }
            var offset: i64 = 0;
            while offset < words.items.len {
                let end = min(words.items.len,offset + blot_runtime_list_runtime::capacity); let chunk,error = blot_runtime_list_runtime::staticChunk(g.module,words.items[offset..end]); if error != blot_error::Error.none { return 0,error; }
                for index in offset..end { let marked = dataValueReference(self_,g,chunk + blot_runtime_list_runtime::header + ((index - offset) * 4) as u32,word_values.items[index],words.items[index]); if marked != blot_error::Error.none { return 0,marked; } }
                let added = leaves.push(chunk); if added != blot_error::Error.none { return 0,added; } offset = end;
            }
            let element = g.representations.store.node(ty).a; var address: u32 = 0;
            if g.layoutRole(element) == blot_backend_runtime_ir::ROLE_scalar { let allocated,error = blot_runtime_list_runtime::staticScalarDescriptor(g.module,info.len,leaves.items,1); if error != blot_error::Error.none { return 0,error; } address = allocated; }
            else { let allocated,error = blot_runtime_list_runtime::staticDescriptor(g.module,info.len,leaves.items); if error != blot_error::Error.none { return 0,error; } address = allocated; }
            let cached = self_.cache.insert(key,address); return address,cached;
        }
        var address: u32 = 0; if words.items.len != 0 { let allocated,error = g.module.dataWords(words.items); if error != blot_error::Error.none { return 0,error; } address = allocated; }
        for index in 0..word_values.items.len { if word_values.items[index] != 0 { let marked = dataValueReference(self_,g,address + (index * 4) as u32,word_values.items[index],words.items[index]); if marked != blot_error::Error.none { return 0,marked; } } }
        let cached = self_.cache.insert(key,address); return address,cached;
    }
    let address,error = build(); leaves.deinit(); word_values.deinit(); words.deinit(); return address,error;
}
import reuse.code_artifacts;
recursive fn serializeClosure(self_: State&,g: Generator&,id: ValueId,ty: u32,depth: i64) -> u32,Error {
    let metadata = g.evaluator.closureInfo(id); let source .= g.unit(metadata.unit); let child_count = g.evaluator.valueInfo(id).len;
    var child_types = Words {..}; var mappings = Mappings {..}; var rows = Rows {..}; var words = Words {..};
    recursive fn build() -> u32,Error {
        let loaded = g.loadSemanticRows(g.evaluator.storage.row_mappings.items[metadata.row_mappings.start..metadata.row_mappings.start + metadata.row_mappings.len],rows); if loaded != blot_error::Error.none { return 0,loaded; }
        var function_id: u32 = 0;
        match metadata.origin {
            anonymous => {
                let closure = source.closures[metadata.identity];
                for mapping in g.evaluator.storage.type_mappings.items[metadata.mappings.start..metadata.mappings.start + metadata.mappings.len] {
                    let concrete,error = g.representations.fromEvidence(g.evaluator.evidenceStore(),mapping.evidence); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0,error; } return 0,g.fail(metadata.unit,closure.body,blot_check_diagnostic_code::Code.unresolved_type); }
                    let mapped = g.mapType(metadata.unit,mappings,mapping.variable,concrete,source.span(closure.body)); if mapped != blot_error::Error.none { return 0,mapped; }
                }
                var implementation = ty; var dictionaries = false;
                if g.representations.store.node(ty).tag == blot_backend_layout::Tag.universal {
                    if source.types.node(closure.function_type).tag != blot_check_types::Tag.forall { return 0,g.fail(metadata.unit,closure.body,blot_check_diagnostic_code::Code.unresolved_type); }
                    let mapped = g.mapTypeDepth(metadata.unit,mappings,rows,closure.function_type,ty,source.span(closure.body),0); if mapped != blot_error::Error.none { return 0,mapped; }
                    dictionaries = source.types.quantifierGoals(closure.function_type).len != 0; implementation = g.representations.store.node(ty).a;
                }
                let function_type = g.representations.store.node(implementation); if function_type.tag != blot_backend_layout::Tag.function { return 0,g.fail(metadata.unit,closure.body,blot_check_diagnostic_code::Code.unresolved_type); }
                if taskCallbackRows(source,closure.parameter.ty,0) { let mapped = g.mapTypeDepth(metadata.unit,mappings,rows,closure.parameter.ty,function_type.a,closure.parameter.span,0); if mapped != blot_error::Error.none { return 0,mapped; } }
                else { let mapped = g.mapType(metadata.unit,mappings,closure.parameter.ty,function_type.a,closure.parameter.span); if mapped != blot_error::Error.none { return 0,mapped; } }
                if taskCallbackRows(source,source.typeOf(closure.body),0) { let mapped = g.mapFunctionResult(metadata.unit,mappings,rows,source.typeOf(closure.body),function_type.b,source.span(closure.body)); if mapped != blot_error::Error.none { return 0,mapped; } }
                else { let mapped = g.mapType(metadata.unit,mappings,source.typeOf(closure.body),function_type.b,source.span(closure.body)); if mapped != blot_error::Error.none { return 0,mapped; } }
                let captures = source.extra[closure.captures.start..closure.captures.start + closure.captures.len]; if captures.len != child_count { return 0,g.fail(metadata.unit,closure.body,blot_check_diagnostic_code::Code.constant_expression); }
                for index in 0..captures.len { let child_type,error = g.captureLayout(metadata.unit,captures[index],g.evaluator.valueChildren(id)[index],mappings,rows); if error != blot_error::Error.none { return 0,error; } let added = child_types.push(child_type); if added != blot_error::Error.none { return 0,added; } }
                for capture_type in child_types.items { var budget: i64 = 1000000; if !g.retainedLayoutConcrete(capture_type,false,0,budget) { return serializeStagedClosure(self_,g,id,ty); } }
                var implementation_type = implementation;
                if closure.function_type != 0 { let concrete,error = g.codeLayoutWithRows(metadata.unit,closure.function_type,mappings.items,rows.items,source.span(closure.body)); if error != blot_error::Error.none { return 0,error; } implementation_type = concrete; }
                if g.representations.store.node(ty).tag == blot_backend_layout::Tag.universal { implementation_type = g.representations.store.node(implementation_type).a; }
                let captures_type,captures_error = g.internLayout(blot_backend_layout::Tag.product,0,0,child_types.items); if captures_error != blot_error::Error.none { return 0,captures_error; }
                let evidence,evidence_error = g.mappingEvidence(mappings.items); if evidence_error != blot_error::Error.none { return 0,evidence_error; }
                let row_evidence,row_error = g.rowMappingEvidence(rows.items); if row_error != blot_error::Error.none { return 0,row_error; }
                let function,error = g.closureFunction(blot_reuse_code_artifacts::ClosureKey { dictionaries: dictionaries, unit: metadata.unit, catalog: metadata.identity, ty: implementation_type, captures: captures_type, evidence: evidence, rows: row_evidence, staged: metadata.staged, .. }); if error != blot_error::Error.none { return 0,error; } function_id = function;
            },
            constructor => {
                var implementation = ty;
                if g.representations.store.node(ty).tag == blot_backend_layout::Tag.universal {
                    let constructor = source.constructor(metadata.identity); implementation = g.representations.store.node(ty).a;
                    let mapped = g.mapTypeDepth(metadata.unit,mappings,rows,constructor.scheme.root,implementation,blot_check_core::Span {..},0); if mapped != blot_error::Error.none { return 0,mapped; }
                    let actual,error = g.codeLayoutWithRows(metadata.unit,constructor.scheme.root,mappings.items,rows.items,blot_check_core::Span {..}); if error != blot_error::Error.none { return 0,error; } if actual != implementation { return 0,staticFailure(g,metadata.unit,blot_check_diagnostic_code::Code.unresolved_type); }
                }
                let function,error = g.constructorFunction(blot_reuse_code_artifacts::ConstructorKey {unit: metadata.unit,catalog: metadata.identity,ty: implementation,..}); if error != blot_error::Error.none { return 0,error; } function_id = function;
            },
            named => { return serializeNamedClosure(self_,g,id,ty,depth); },
            primitive => { return serializePrimitiveClosure(self_,g,id,ty,depth); },
            operation => {
                if metadata.applied != 0 || child_count != 0 { return 0,staticFailure(g,metadata.unit,blot_check_diagnostic_code::Code.unsupported); }
                for mapping in g.evaluator.storage.type_mappings.items[metadata.mappings.start..metadata.mappings.start + metadata.mappings.len] {
                    let concrete,error = representation(g,mapping.evidence,metadata.unit); if error != blot_error::Error.none { return 0,error; } let mapped = g.mapType(metadata.unit,mappings,mapping.variable,concrete,blot_check_core::Span {..}); if mapped != blot_error::Error.none { return 0,mapped; }
                }
                let label,label_error = g.operationLabel(metadata.unit,metadata.identity,mappings.items,rows.items,blot_check_core::Span {..}); if label_error != blot_error::Error.none { return 0,label_error; }
                let operation,operation_error = g.runtimeOperation(label,metadata.unit,blot_check_core::Span {..}); if operation_error != blot_error::Error.none { return 0,operation_error; }
                let function,error = g.operationFunction(blot_reuse_code_artifacts::OperationKey {operation,ty,..}); if error != blot_error::Error.none { return 0,error; } function_id = function;
            },
        }
        for index in 0..child_types.items.len { let bits,error = serialize(self_,g,g.evaluator.valueChildren(id)[index],child_types.items[index],depth + 1); if error != blot_error::Error.none { return 0,error; } let added = words.push(bits); if added != blot_error::Error.none { return 0,added; } }
        var environment: u32 = 0; if words.items.len != 0 { let address,error = g.module.dataWords(words.items); if error != blot_error::Error.none { return 0,error; } environment = address; }
        for slot in 0..words.items.len { let marked = dataValueReference(self_,g,environment + (slot * 4) as u32,g.evaluator.valueChildren(id)[slot],words.items[slot]); if marked != blot_error::Error.none { return 0,marked; } }
        let address,error = closureData(self_,g,function_id,environment); if error != blot_error::Error.none { return 0,error; } let cached = self_.cache.insert(SerializedKey {value: id,ty: ty},address); return address,cached;
    }
    let address,error = build(); words.deinit(); rows.deinit(); mappings.deinit(); child_types.deinit(); return address,error;
}
recursive fn serializeStagedClosure(self_: State&,g: Generator&,value: ValueId,ty: u32) -> u32,Error {
    let header = g.evaluator.closureInfo(value); let source .= g.unit(header.unit); let metadata = source.closures[header.identity]; let bindings = source.extra[metadata.captures.start..metadata.captures.start + metadata.captures.len];
    var captured = Words {..}; var mappings = Mappings {..}; var rows = Rows {..}; var hints = blot_backend_substitution_buffers::Hints {..};
    recursive fn build() -> u32,Error {
        let copied = captured.append(g.evaluator.valueChildren(value)); if copied != blot_error::Error.none { return 0,copied; } if bindings.len != captured.items.len { return 0,g.fail(header.unit,metadata.body,blot_check_diagnostic_code::Code.unsupported); }
        for mapping in g.evaluator.storage.type_mappings.items[header.mappings.start..header.mappings.start + header.mappings.len] {
            let concrete,error = g.representations.fromEvidence(g.evaluator.evidenceStore(),mapping.evidence); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0,error; } return 0,g.fail(header.unit,metadata.body,blot_check_diagnostic_code::Code.unresolved_type); }
            let mapped = g.mapType(header.unit,mappings,mapping.variable,concrete,source.span(metadata.body)); if mapped != blot_error::Error.none { return 0,mapped; }
        }
        let loaded = g.loadSemanticRows(g.evaluator.storage.row_mappings.items[header.row_mappings.start..header.row_mappings.start + header.row_mappings.len],rows); if loaded != blot_error::Error.none { return 0,loaded; }
        let arrow = g.representations.store.node(ty);
        if metadata.function_type != 0 { let mapped = g.mapCapturedFunction(header.unit,metadata.function_type,ty,mappings,rows,source.span(metadata.body)); if mapped != blot_error::Error.none { return 0,mapped; } }
        else { let argument = g.mapType(header.unit,mappings,metadata.parameter.ty,arrow.a,metadata.parameter.span); if argument != blot_error::Error.none { return 0,argument; } let result = g.mapType(header.unit,mappings,source.typeOf(metadata.body),arrow.b,source.span(metadata.body)); if result != blot_error::Error.none { return 0,result; } }
        for index in 0..bindings.len { let added = hints.push(blot_eval_core_eval::RetainedCapture { value: captured.items[index], binding: bindings[index], unit: header.unit, node: 0, .. }); if added != blot_error::Error.none { return 0,added; } }
        let refined = g.refineAccessorMappings(header.unit,header.identity,ty,mappings,rows,source.span(metadata.body),hints.items); if refined != blot_error::Error.none { return 0,refined; }
        let function,error = g.capturedClosureFunction(header,ty,captured.items,mappings.items,rows.items); if error != blot_error::Error.none { return 0,error; }
        let address,allocated = closureData(self_,g,function,0); if allocated != blot_error::Error.none { return 0,allocated; } let cached = self_.cache.insert(SerializedKey {value,ty},address); return address,cached;
    }
    let address,error = build(); hints.deinit(); rows.deinit(); mappings.deinit(); captured.deinit(); return address,error;
}
recursive fn serializeNamedClosure(self_: State&,g: Generator&,id: ValueId,ty: u32,depth: i64) -> u32,Error {
    let metadata = g.evaluator.closureInfo(id); let target = blot_check_core::BindingRef {unit: metadata.unit,binding: metadata.identity}; let source .= g.unit(metadata.unit); let body .= source.body(metadata.identity);
    if !body { return 0,g.decline(metadata.unit,source.binding(metadata.identity).span,blot_check_diagnostic_code::Code.constant_expression); }
    let child_count = g.evaluator.valueInfo(id).len; if child_count != metadata.applied || child_count >= body.parameters.len { return 0,g.decline(metadata.unit,body.span,blot_check_diagnostic_code::Code.constant_expression); }
    var mappings = Mappings {..}; var rows = Rows {..}; var types = Words {..}; var words = Words {..};
    recursive fn build() -> u32,Error {
        let loaded = g.loadSemanticRows(g.evaluator.storage.row_mappings.items[metadata.row_mappings.start..metadata.row_mappings.start + metadata.row_mappings.len],rows); if loaded != blot_error::Error.none { return 0,loaded; }
        for mapping in g.evaluator.storage.type_mappings.items[metadata.mappings.start..metadata.mappings.start + metadata.mappings.len] { let concrete,error = representation(g,mapping.evidence,metadata.unit); if error != blot_error::Error.none { return 0,error; } let mapped = g.mapType(metadata.unit,mappings,mapping.variable,concrete,body.span); if mapped != blot_error::Error.none { return 0,mapped; } }
        let root,root_error = g.functionRoot(metadata.unit,source.binding(metadata.identity).ty,body.span); if root_error != blot_error::Error.none { return 0,root_error; } var source_ty = root;
        for index in 0..child_count {
            let parameter = source.bodyParameters(body)[index]; let child = g.evaluator.valueChildren(id)[index];
            let concrete,error = g.captureTypeLayout(metadata.unit,parameter.ty,parameter.span,child,mappings,rows); if error != blot_error::Error.none { return 0,error; } let added = types.push(concrete); if added != blot_error::Error.none { return 0,added; }
            let node = source.types.node(source_ty); if node.tag != blot_check_types::Tag.function { return 0,g.decline(metadata.unit,body.span,blot_check_diagnostic_code::Code.unresolved_type); } let mapped = g.mapType(metadata.unit,mappings,node.a,concrete,body.span); if mapped != blot_error::Error.none { return 0,mapped; } source_ty = node.b;
        }
        var dictionaries = false;
        if g.representations.store.node(ty).tag == blot_backend_layout::Tag.universal {
            if metadata.applied != 0 || source.types.node(source.binding(metadata.identity).ty).tag != blot_check_types::Tag.forall { return 0,g.decline(metadata.unit,body.span,blot_check_diagnostic_code::Code.unresolved_type); }
            let mapped = g.mapTypeDepth(metadata.unit,mappings,rows,source.binding(metadata.identity).ty,ty,body.span,0); if mapped != blot_error::Error.none { return 0,mapped; } dictionaries = source.types.quantifierGoals(source.binding(metadata.identity).ty).len != 0;
        } else if taskCallbackRows(source,source_ty,0) { let mapped = g.mapFunctionResult(metadata.unit,mappings,rows,source_ty,ty,body.span); if mapped != blot_error::Error.none { return 0,mapped; } }
        else { let mapped = g.mapType(metadata.unit,mappings,source_ty,ty,body.span); if mapped != blot_error::Error.none { return 0,mapped; } }
        let initial_type,type_error = g.codeLayoutWithRows(metadata.unit,source.binding(metadata.identity).ty,mappings.items,rows.items,body.span); if type_error != blot_error::Error.none { return 0,type_error; } var full_type = initial_type; if g.representations.store.node(ty).tag == blot_backend_layout::Tag.universal { full_type = g.representations.store.node(full_type).a; }
        let function,error = g.callable(blot_reuse_code_artifacts::CallableKey { dictionaries: dictionaries, target: target, ty: full_type, applied: metadata.applied, .. }); if error != blot_error::Error.none { return 0,error; }
        for index in 0..types.items.len { let bits,error = serialize(self_,g,g.evaluator.valueChildren(id)[index],types.items[index],depth + 1); if error != blot_error::Error.none { return 0,error; } let added = words.push(bits); if added != blot_error::Error.none { return 0,added; } }
        var environment: u32 = 0;
        if g.directCallableEnvironment(full_type,metadata.applied) { environment = words.items[0]; }
        else if words.items.len != 0 { let address,error = g.module.dataWords(words.items); if error != blot_error::Error.none { return 0,error; } environment = address; for slot in 0..words.items.len { let marked = dataValueReference(self_,g,environment + (slot * 4) as u32,g.evaluator.valueChildren(id)[slot],words.items[slot]); if marked != blot_error::Error.none { return 0,marked; } } }
        let address,allocated = closureData(self_,g,function,environment); if allocated != blot_error::Error.none { return 0,allocated; } let cached = self_.cache.insert(SerializedKey {value: id,ty: ty},address); return address,cached;
    }
    let address,error = build(); words.deinit(); types.deinit(); rows.deinit(); mappings.deinit(); return address,error;
}
recursive fn serializePrimitiveClosure(self_: State&,g: Generator&,id: ValueId,ty: u32,depth: i64) -> u32,Error {
    let metadata = g.evaluator.closureInfo(id); let child_count = g.evaluator.valueInfo(id).len; let primitive = g.unit(metadata.unit).primitives[metadata.identity]; if primitive.kind != blot_check_core::PrimitiveKind.scalar { return 0,staticFailure(g,metadata.unit,blot_check_diagnostic_code::Code.constant_expression); }
    var full_type = ty; var index = child_count;
    while index != 0 {
        index--; let value = g.evaluator.valueScalar(g.evaluator.valueChildren(id)[index]); if !value.present { return 0,staticFailure(g,metadata.unit,blot_check_diagnostic_code::Code.unresolved_type); }
        var argument: u32 = 3; if value.value.scalar == blot_backend_runtime_ir::SC_f32 { argument = 4; }
        let next,error = g.internLayout(blot_backend_layout::Tag.function,argument,full_type,[]); if error != blot_error::Error.none { return 0,error; } full_type = next;
    }
    let function,error = g.primitiveFunction(blot_reuse_code_artifacts::PrimitiveKey {unit: metadata.unit,catalog: metadata.identity,ty: full_type,applied: metadata.applied,..}); if error != blot_error::Error.none { return 0,error; }
    var words = Words {..};
    recursive fn build() -> u32,Error {
        var current = full_type;
        for child_index in 0..child_count { let child = g.evaluator.valueChildren(id)[child_index]; let node = g.representations.store.node(current); let bits,error = serialize(self_,g,child,node.a,depth + 1); if error != blot_error::Error.none { return 0,error; } let added = words.push(bits); if added != blot_error::Error.none { return 0,added; } current = node.b; }
        var environment: u32 = 0; if words.items.len != 0 { let address,error = g.module.dataWords(words.items); if error != blot_error::Error.none { return 0,error; } environment = address; }
        for slot in 0..words.items.len { let marked = dataValueReference(self_,g,environment + (slot * 4) as u32,g.evaluator.valueChildren(id)[slot],words.items[slot]); if marked != blot_error::Error.none { return 0,marked; } }
        let address,allocated = closureData(self_,g,function,environment); if allocated != blot_error::Error.none { return 0,allocated; } let cached = self_.cache.insert(SerializedKey {value: id,ty: ty},address); return address,cached;
    }
    let address,serialized = build(); words.deinit(); return address,serialized;
}
