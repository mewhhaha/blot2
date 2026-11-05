// Source obligations and representation expectations meet before emission.
namespace blot_eval_specialization;
import backend.substitution_buffers;
import check.core;
import check.types;
import check.task_types;
import check.dictionary_owner;
import check.package_core;
import backend.layout;
import backend.layout_bridge;
import backend.dictionary_layout;
import backend.backend_timing;
import backend.core_backend;
import .core_eval;
import .type_evidence;
import .semantic_handles;
import reuse.refinement_receipt;
import reuse.specialization_receipt;
import reuse.code_artifacts;
import reuse.code_expectation;
import work_counters;
import support.error;
import support.option;
type Error = blot_error::Error;
type Mapping = blot_backend_layout::Mapping;
type RowMapping = blot_backend_layout::RowMapping;
type EvidenceRoot = blot_reuse_refinement_receipt::Root;
enum FailureCode { unresolved_type, complexity, evaluation }
struct Failure { unit: u32, span: blot_check_core::Span, code: FailureCode }
struct Record {
    root: EvidenceRoot, expected: u32, seeds: const blot_eval_type_evidence::Mapping[:], rows: const blot_eval_type_evidence::RowMapping[:],
    result: blot_eval_core_eval::SolvedEvidence, tape: blot_reuse_specialization_receipt::Tape&, observed: blot_reuse_refinement_receipt::Observation,
    before_values: i64, before_children: i64, before_steps: i64,
}
// The sole production cache owner is the native backend Generator.
struct ResolvedBody { source: blot_check_core::BindingRef, root: blot_eval_semantic_handles::Expression, mappings: MappingSink, rows: RowSink }
fn deinit(body: ResolvedBody&) { clearSink(body.mappings); clearSink(body.rows); }
fn appendMapping(mappings: Mapping[>..<]&, value: Mapping) -> Error { mappings.push(value); return Error.none; }
struct PhysicalProjection { layouts: blot_backend_layout::Store? = null,mappings: MappingSink = MappingSink.inactive }
fn physicalProjection(layouts: blot_backend_layout::Store&,mappings: Mapping[>..<]&) -> PhysicalProjection,Error { return PhysicalProjection { layouts,MappingSink.lexical { mappings } },Error.none; }
fn physicalProjection(layouts: blot_backend_layout::Store&,mappings: blot_backend_substitution_buffers::Mappings&) -> PhysicalProjection,Error { let sink,error = mappingSink(mappings); if error != Error.none { return PhysicalProjection {},error; } return PhysicalProjection { layouts,sink },Error.none; }
fn mapping(self: PhysicalProjection&, solver: blot_check_types::Store&, variable: blot_check_types::Id, root: blot_check_types::Id) -> Error {
    assert(self.layouts);
    for &entry in mappingItems(self.mappings) { if entry.variable == variable && entry.layout != blot_backend_layout::erased { return Error.none; } }
    let concrete, error = self.layouts.fromSolver(solver, root);
    if error != Error.none { if error == Error.layout_limit { return Error.type_limit; } return error; }
    if concrete == blot_backend_layout::erased { return Error.none; }
    for &entry in mappingItems(self.mappings) { if entry.variable == variable { entry.layout = concrete; return Error.none; } }
    return appendSink(self.mappings, Mapping { variable: variable, layout: concrete });
}
struct OwnedProjection { unit: u32,mappings: const Mapping[:],physical: PhysicalProjection }
fn mappingTarget(projection: blot_eval_core_eval::CodeProjection) -> PhysicalProjection { match projection { inactive=>{ abort("inactive code projection"); },physical p=>{ return p.value; },static_code p=>{ return p.value; },owned p=>{ return p.value.physical; }, } }
fn mapping(self: OwnedProjection&, solver: blot_check_types::Store&, variable: blot_check_types::Id, root: blot_check_types::Id) -> Error { self.physical.mapping(solver, variable, root) }
fn instance(self: OwnedProjection&, unit: u32, variable: blot_check_types::Id) -> blot_support::Option<blot_check_types::NominalIdentity> {
    if unit != self.unit { return blot_support::none<blot_check_types::NominalIdentity>(); }
    for entry in self.mappings { if entry.variable == variable && entry.instance.unit != 0 { return blot_support::some(entry.instance); } }
    return blot_support::none<blot_check_types::NominalIdentity>();
}
struct Service {
    timing: blot_backend_backend_timing::Work&? = null, units: const blot_check_core::Module[:], evaluator: blot_eval_core_eval::Session&,
    layouts: blot_backend_layout::Store&, bridge: blot_backend_layout_bridge::Store&, refinement_stats: blot_reuse_refinement_receipt::Stats&, refinement_regions: i64&,
    cache: blot_backend_core_backend::Generator&? = null, code_projection: blot_support::Option<blot_eval_core_eval::CodeProjection> = blot_support::none<blot_eval_core_eval::CodeProjection>(), failure: blot_support::Option<Failure>, dictionary_unit: u32 = 0,
}
fn unit(self: Service&, id: u32) -> const blot_check_core::Module& { self.units[id - 1] }
fn decline(self: Service&, id: u32, span: blot_check_core::Span, code: FailureCode) -> Error { self.failure = blot_support::some(Failure { id, span, code }); return Error.declined; }
fn evaluationFailure(self: Service&) -> Error { decline(self, 0, blot_check_core::Span { 0, 0 }, FailureCode.evaluation) }
fn toEvidence(self: Service&, id: u32) -> u32, Error { self.bridge.toEvidence(id) }
fn fromEvidence(self: Service&, id: u32) -> u32, Error { self.bridge.fromEvidence(id) }
fn rowToEvidence(self: Service&, id: u32) -> u32, Error { self.bridge.rowToEvidence(id) }
fn rowFromEvidence(self: Service&, id: u32) -> u32, Error { self.bridge.rowFromEvidence(id) }
fn representationError(self: Service&, error: Error, unit_id: u32, span: blot_check_core::Span, code: FailureCode) -> Error {
    if error == Error.out_of_memory { return error; } return decline(self, unit_id, span, code);
}
fn codeLayoutWithRows(self: Service&, id: u32, ty: blot_check_types::Id, mappings: const Mapping[:], rows: const RowMapping[:], span: blot_check_core::Span) -> u32, Error {
    let value, error = self.layouts.fromTypeWithRows(unit(self, id), ty, mappings, rows, true);
    if error != Error.none { return 0, representationError(self, error, id, span, FailureCode.unresolved_type); } return value, Error.none;
}
fn internFunction(self: Service&, argument: u32, result: u32, row: u32) -> u32, Error {
    let value, error = self.layouts.internWithEffects(blot_backend_layout::Tag.function, argument, result, row, []);
    if error != Error.none { return 0, representationError(self, error, 1, blot_check_core::Span { 0, 0 }, FailureCode.complexity); } return value, Error.none;
}
// Outputs borrow the caller's lexical owners, allowing all mapping counts.
fn named(self: Service&,key: blot_reuse_code_artifacts::Key,instances: const blot_check_types::NominalIdentity[:],mappings: Mapping[>..<]&,rows: RowMapping[>..<]&) -> ResolvedBody,Error { return namedSink(self,key,instances,MappingSink.lexical { mappings },RowSink.lexical { rows }); }
fn named(self: Service&,key: blot_reuse_code_artifacts::Key,instances: const blot_check_types::NominalIdentity[:],mappings: blot_backend_substitution_buffers::Mappings&,rows: blot_backend_substitution_buffers::Rows&) -> ResolvedBody,Error { let selected,error = mappingSink(mappings); if error != Error.none { return default<ResolvedBody>(),error; } let selected_rows,row_error = rowSink(rows); if row_error != Error.none { return default<ResolvedBody>(),row_error; } return namedSink(self,key,instances,selected,selected_rows); }
fn namedSink(self: Service&, key: blot_reuse_code_artifacts::Key, instances: const blot_check_types::NominalIdentity[:], mappings: MappingSink, rows: RowSink) -> ResolvedBody, Error {
    clearSink(mappings); clearSink(rows); let unit_id = key.target.unit; let source .= unit(self, unit_id); let body .= source.body(key.target.binding); assert(body);
    let previous = self.dictionary_unit; self.dictionary_unit = 0; 
    recursive fn cleanup_continuation_13() -> ResolvedBody, Error {

    if key.dictionaries {
        let owner = blot_check_dictionary_owner::forBinding(source, key.target.binding); if !owner.present { return ResolvedBody { source: key.target,root: 0,mappings: mappings,rows: rows }, decline(self, unit_id, body.span, FailureCode.unresolved_type); }
        var remaining: i64 = 65536; let valid = blot_check_package_core::parametricBodyModules(source,key.target.binding,self.units,remaining);
        if valid != Error.none { return ResolvedBody { source: key.target,root: 0,mappings: mappings,rows: rows }, decline(self, unit_id, body.span, FailureCode.unresolved_type); }
        let bound = blot_backend_dictionary_layout::bindOwner(source, self.layouts, mappings, owner.value, 0, owner.value.formals(source), false);
        if bound != Error.none { return ResolvedBody { source: key.target,root: 0,mappings: mappings,rows: rows }, representationError(self, bound, unit_id, body.span, FailureCode.unresolved_type); } self.dictionary_unit = unit_id;
    }
    var ty = source.binding(key.target.binding).ty; var rank_depth = 0;
    while source.types.node(ty).tag == blot_check_types::Tag.forall || source.types.node(ty).tag == blot_check_types::Tag.usage {
        if rank_depth == 128 { return ResolvedBody { source: key.target,root: 0,mappings: mappings,rows: rows }, decline(self, unit_id, body.span, FailureCode.complexity); } rank_depth++; ty = source.types.node(ty).a;
    }
    var source_rows: u32[16] = [0; 16];
    for scalar_type, index in key.parameters[..key.count] {
        let n = source.types.node(ty); if n.tag != blot_check_types::Tag.function { return ResolvedBody { source: key.target,root: 0,mappings: mappings,rows: rows }, decline(self, unit_id, body.span, FailureCode.unresolved_type); }
        let error = mapTypeDepthSink(self, unit_id, mappings, rows, n.a, scalar_type, body.span, 0); if error != Error.none { return ResolvedBody { source: key.target,root: 0,mappings: mappings,rows: rows }, error; }
        if index < instances.len && instances[index].unit != 0 {
            let input = source.types.node(n.a); if input.tag == blot_check_types::Tag.scoped && input.b == 0 { let e = appendSink(mappings, Mapping { variable: input.c, layout: blot_backend_layout::erased, instance: instances[index] }); if e != Error.none { return ResolvedBody { source: key.target,root: 0,mappings: mappings,rows: rows }, e; } }
        }
        source_rows[index] = n.c; ty = n.b;
    }
    let result_error = mapFunctionResultSink(self, unit_id, mappings, rows, ty, key.result, body.span, 0); if result_error != Error.none { return ResolvedBody { source: key.target,root: 0,mappings: mappings,rows: rows }, result_error; }
    for row, index in source_rows[..key.count] { let e = mapRowSink(self, unit_id, mappings, rows, row, key.effects[index], body.span, true); if e != Error.none { return ResolvedBody { source: key.target,root: 0,mappings: mappings,rows: rows }, e; } }
    var full = key.result; var reverse = key.count as i64;
    while reverse > 0 { reverse--; let value, e = internFunction(self, key.parameters[reverse], full, key.effects[reverse]); if e != Error.none { return ResolvedBody { source: key.target,root: 0,mappings: mappings,rows: rows }, e; } full = value; }
    if !key.dictionaries && source.binding(key.target.binding).capability_flow != blot_check_core::CapabilityFlow.consume_task {
        let e = refineMappingsSink(self, unit_id, EvidenceRoot.body { key.target }, full, mappings, rows, body.span); if e != Error.none { return ResolvedBody { source: key.target,root: 0,mappings: mappings,rows: rows }, e; }
    }
    return ResolvedBody { source: key.target, root: body.root, mappings: mappings, rows: rows }, Error.none;

    }
    let cleanup_result_13_0,cleanup_result_13_1 = cleanup_continuation_13();
     self.dictionary_unit = previous; 
    return cleanup_result_13_0,cleanup_result_13_1;
}
enum MappingSink { inactive,lexical { value: Mapping[>..<]& },pooled { value: blot_backend_substitution_buffers::Mappings } }
enum RowSink { empty,lexical { value: RowMapping[>..<]& },pooled { value: blot_backend_substitution_buffers::Rows } }
fn mappingSink(buffer: blot_backend_substitution_buffers::Mappings&) -> MappingSink,Error { let error = buffer.prepare(); if error != Error.none { return MappingSink.inactive,error; } return MappingSink.pooled { buffer },Error.none; }
fn rowSink(rows: blot_backend_substitution_buffers::Rows?) -> RowSink,Error { if rows == null { return RowSink.empty,Error.none; } let error = rows.prepare(); if error != Error.none { return RowSink.empty,error; } return RowSink.pooled { rows },Error.none; }
fn mappingItems(sink: MappingSink) -> Mapping[:] { match sink { inactive=>{ abort("inactive mapping sink"); },lexical s=>{ return s.value[..]; },pooled s=>{ return s.value.items; }, } }
fn rowItems(sink: RowSink) -> RowMapping[:] { match sink { empty=>{ return []; },lexical s=>{ return s.value[..]; },pooled s=>{ return s.value.items; }, } }
fn hasRows(sink: RowSink) -> bool { match sink { empty=>{ return false; },_=>{ return true; }, } }
fn clearSink(sink: MappingSink) { match sink { inactive=>{ abort("inactive mapping sink"); },lexical s=>{ s.value.clear(); },pooled s=>{ var buffer = s.value; buffer.clear(); }, } }
fn clearSink(sink: RowSink) { match sink { empty=>{},lexical s=>{ s.value.clear(); },pooled s=>{ var buffer = s.value; buffer.clear(); }, } }
fn appendSink(sink: MappingSink,value: Mapping) -> Error { match sink { inactive=>{ abort("inactive mapping sink"); },lexical s=>{ s.value.push(value); return Error.none; },pooled s=>{ var buffer = s.value; return buffer.push(value); }, } }
fn appendSink(sink: RowSink,value: RowMapping) -> Error { match sink { empty=>{ return Error.invalid_function_reference; },lexical s=>{ s.value.push(value); return Error.none; },pooled s=>{ var buffer = s.value; return buffer.push(value); }, } }
fn rowSink(rows: RowMapping[>..<]&?) -> RowSink { if rows != null { return RowSink.lexical { rows }; } return RowSink.empty; }
fn mapType(self: Service&,unit_id: u32,mappings: Mapping[>..<]&,ty: u32,concrete: u32,span: blot_check_core::Span) -> Error { return mapTypeDepthSink(self,unit_id,MappingSink.lexical { mappings },RowSink.empty,ty,concrete,span,0); }
fn mapType(self: Service&,unit_id: u32,mappings: blot_backend_substitution_buffers::Mappings&,ty: u32,concrete: u32,span: blot_check_core::Span) -> Error { let selected,error = mappingSink(mappings); if error != Error.none { return error; } return mapTypeDepthSink(self,unit_id,selected,RowSink.empty,ty,concrete,span,0); }
fn mapTypeDepth(self: Service&,unit_id: u32,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&?,ty: u32,concrete: u32,span: blot_check_core::Span,depth: i64) -> Error { return mapTypeDepthSink(self,unit_id,MappingSink.lexical { mappings },rowSink(rows),ty,concrete,span,depth); }
fn mapTypeDepth(self: Service&,unit_id: u32,mappings: blot_backend_substitution_buffers::Mappings&,rows: blot_backend_substitution_buffers::Rows?,ty: u32,concrete: u32,span: blot_check_core::Span,depth: i64) -> Error { let selected,error = mappingSink(mappings); if error != Error.none { return error; } let selected_rows,row_error = rowSink(rows); if row_error != Error.none { return row_error; } return mapTypeDepthSink(self,unit_id,selected,selected_rows,ty,concrete,span,depth); }
fn mapFunctionResult(self: Service&,unit_id: u32,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,ty: u32,concrete: u32,span: blot_check_core::Span,depth: i64) -> Error { return mapFunctionResultSink(self,unit_id,MappingSink.lexical { mappings },RowSink.lexical { rows },ty,concrete,span,depth); }
fn mapFunctionResult(self: Service&,unit_id: u32,mappings: blot_backend_substitution_buffers::Mappings&,rows: blot_backend_substitution_buffers::Rows&,ty: u32,concrete: u32,span: blot_check_core::Span,depth: i64) -> Error { let selected,error = mappingSink(mappings); if error != Error.none { return error; } let selected_rows,row_error = rowSink(rows); if row_error != Error.none { return row_error; } return mapFunctionResultSink(self,unit_id,selected,selected_rows,ty,concrete,span,depth); }
fn mapRow(self: Service&,unit_id: u32,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,source: u32,actual: u32,span: blot_check_core::Span,covariant: bool) -> Error { return mapRowSink(self,unit_id,MappingSink.lexical { mappings },RowSink.lexical { rows },source,actual,span,covariant); }
fn mapRow(self: Service&,unit_id: u32,mappings: blot_backend_substitution_buffers::Mappings&,rows: blot_backend_substitution_buffers::Rows&,source: u32,actual: u32,span: blot_check_core::Span,covariant: bool) -> Error { let selected,error = mappingSink(mappings); if error != Error.none { return error; } let selected_rows,row_error = rowSink(rows); if row_error != Error.none { return row_error; } return mapRowSink(self,unit_id,selected,selected_rows,source,actual,span,covariant); }
recursive fn mapFunctionResultSink(self: Service&, unit_id: u32, mappings: MappingSink, rows: RowSink, ty: blot_check_types::Id, concrete: u32, span: blot_check_core::Span, depth: i64) -> Error {
    if depth >= 1024 { return decline(self, unit_id, span, FailureCode.complexity); }
    let source = unit(self, unit_id).types.node(ty); let physical = self.layouts.node(concrete);
    if source.tag != blot_check_types::Tag.function || physical.tag != blot_backend_layout::Tag.function { return mapTypeDepthSink(self, unit_id, mappings, rows, ty, concrete, span, depth); }
    let a = mapTypeDepthSink(self, unit_id, mappings, rows, source.a, physical.a, span, depth + 1); if a != Error.none { return a; }
    let b = mapFunctionResultSink(self, unit_id, mappings, rows, source.b, physical.b, span, depth + 1); if b != Error.none { return b; }
    return mapRowSink(self, unit_id, mappings, rows, source.c, physical.c, span, true);
}
recursive fn mapTypeDepthSink(self: Service&, unit_id: u32, mappings: MappingSink, rows: RowSink, ty: blot_check_types::Id, concrete: u32, span: blot_check_core::Span, depth: i64) -> Error {
    if depth >= 1024 { return decline(self, unit_id, span, FailureCode.complexity); }
    let source .= unit(self, unit_id); let n = source.types.node(ty);
    if n.tag == blot_check_types::Tag.usage {
        let physical = self.layouts.node(concrete); let callback = blot_check_task_types::scopeCallback(source.types, ty);
        if callback.present && physical.tag == blot_backend_layout::Tag.universal {
            let actual = self.layouts.node(physical.a); if actual.tag != blot_backend_layout::Tag.function { return decline(self, unit_id, span, FailureCode.unresolved_type); }
            let error = mapTypeDepthSink(self, unit_id, mappings, rows, callback.value.b, actual.b, span, depth + 1); if error != Error.none { return error; }
            if hasRows(rows) { let e = mapRowSink(self, unit_id, mappings, rows, callback.value.c, actual.c, span, false); if e != Error.none { return e; } }
        }
        if n.b == blot_check_types::usagekind_unique || n.b == blot_check_types::usagekind_shared {
            if physical.tag != blot_backend_layout::Tag.owning || physical.b != n.b || n.c != 0 { return decline(self, unit_id, span, FailureCode.unresolved_type); }
            return mapTypeDepthSink(self, unit_id, mappings, rows, n.a, physical.a, span, depth + 1);
        }
        return mapTypeDepthSink(self, unit_id, mappings, rows, n.a, concrete, span, depth + 1);
    }
    let representation = self.layouts.node(concrete);
    if n.tag == blot_check_types::Tag.nominal && n.a == blot_check_task_types::handle.unit && n.b == blot_check_task_types::handle.decl {
        let words = self.layouts.children(concrete);
        if representation.tag != blot_backend_layout::Tag.product || words.len != 2 || words[0] != blot_check_types::u32_type || words[1] != blot_check_types::u32_type { return decline(self, unit_id, span, FailureCode.unresolved_type); }
        return Error.none;
    }
    if n.tag == blot_check_types::Tag.forall && representation.tag == blot_backend_layout::Tag.universal {
        var inherited: const RowMapping[:] = []; if hasRows(rows) { inherited = rowItems(rows); }
        let expected, error = self.layouts.fromTypeWithRows(source, ty, mappingItems(mappings), inherited, false);
        if error != Error.none { return representationError(self, error, unit_id, span, FailureCode.unresolved_type); }
        if expected != concrete { return decline(self, unit_id, span, FailureCode.unresolved_type); } return Error.none;
    }
    if n.tag == blot_check_types::Tag.forall { return mapTypeDepthSink(self, unit_id, mappings, rows, n.a, concrete, span, depth + 1); }
    if n.tag == blot_check_types::Tag.scoped {
        let physical = self.layouts.node(concrete);
        if physical.tag == blot_backend_layout::Tag.scoped {
            if n.b != 0 && (n.b != physical.b || n.c != physical.c) { return decline(self, unit_id, span, FailureCode.unresolved_type); }
            if n.b == 0 { let error = appendSink(mappings, Mapping { variable: n.c, layout: blot_backend_layout::erased, instance: blot_check_types::NominalIdentity { physical.b, physical.c } }); if error != Error.none { return error; } }
            return mapTypeDepthSink(self, unit_id, mappings, rows, n.a, physical.a, span, depth + 1);
        }
        if physical.tag != blot_backend_layout::Tag.nominal || physical.a != 4294967295 || physical.b != blot_backend_layout::capability_layout_decl { return decline(self, unit_id, span, FailureCode.unresolved_type); }
        return Error.none;
    }
    if representation.tag == blot_backend_layout::Tag.erased_proof && n.tag != blot_check_types::Tag.erased_proof { return decline(self, unit_id, span, FailureCode.unresolved_type); }
    if n.tag == blot_check_types::Tag.never { return Error.none; }
    if n.tag == blot_check_types::Tag.variable || (n.tag == blot_check_types::Tag.bound && n.b == 0) {
        for &entry in mappingItems(mappings) {
            if entry.variable == ty {
                let merged, error = self.layouts.mergePartial(entry.layout, concrete); if error != Error.none { return representationError(self, error, unit_id, span, FailureCode.unresolved_type); }
                entry.layout = merged; return Error.none;
            }
        }
        return appendSink(mappings, Mapping { variable: ty, layout: concrete });
    }
    if n.tag == blot_check_types::Tag.projection {
        if self.dictionary_unit == unit_id && representation.tag == blot_backend_layout::Tag.associated {
            for &entry in mappingItems(mappings) { if entry.variable == ty && self.layouts.node(entry.layout).tag == blot_backend_layout::Tag.associated { return Error.none; } }
            return decline(self, unit_id, span, FailureCode.unresolved_type);
        }
        var seeds = blot_backend_substitution_buffers::EvidenceMappings {}; defer { seeds.deinit(); } var row_seeds = blot_backend_substitution_buffers::EvidenceRows {}; defer { row_seeds.deinit(); }
        for &entry in mappingItems(mappings) {
            if self.layouts.node(entry.layout).tag == blot_backend_layout::Tag.erased { continue; }
            let actual, error = toEvidence(self, entry.layout); if error != Error.none { if error == Error.out_of_memory { return error; } continue; }
            let appended = seeds.push(blot_eval_type_evidence::Mapping { variable: entry.variable,evidence: actual }); if appended != Error.none { return appended; }
        }
        if hasRows(rows) { for entry in rowItems(rows) {
            if entry.row == blot_backend_layout::unknown_row { continue; }
            let actual, error = rowToEvidence(self, entry.row); if error != Error.none { return representationError(self, error, unit_id, span, FailureCode.unresolved_type); }
            let appended = row_seeds.push(blot_eval_type_evidence::RowMapping { variable: entry.variable,evidence: actual }); if appended != Error.none { return appended; }
        } }
        var use: blot_check_core::Id = 0;
        for selected in source.selected_uses { let location = source.span(selected.node); if location.start >= span.start && location.end <= span.end { use = selected.node; break; } }
        let selected, error = self.evaluator.projectType((unit_id - 1) as i64, use, ty, seeds.items, row_seeds.items);
        if error != Error.none { if error == Error.out_of_memory { return error; } return evaluationFailure(self); }
        if selected == 0 { return decline(self, unit_id, span, FailureCode.unresolved_type); }
        let wanted, wanted_error = toEvidence(self, concrete); if wanted_error != Error.none { return representationError(self, wanted_error, unit_id, span, FailureCode.unresolved_type); }
        if selected != wanted { return decline(self, unit_id, span, FailureCode.unresolved_type); }
        for &entry in mappingItems(mappings) { if entry.variable == ty { entry.layout = concrete; return Error.none; } }
        return appendSink(mappings, Mapping { variable: ty, layout: concrete });
    }
    var valid = false;
    match n.tag {
        existential => {
            if representation.tag == blot_backend_layout::Tag.existential {
                let expected, error = self.layouts.fromTypeWithRows(source, ty, mappingItems(mappings), [], false);
                if error != Error.none { return representationError(self, error, unit_id, span, FailureCode.unresolved_type); } valid = expected == concrete;
            }
        },
        erased_proof => { valid = representation.tag == blot_backend_layout::Tag.erased_proof; },
        unit => { valid = representation.tag == blot_backend_layout::Tag.unit; },
        boolean => { valid = representation.tag == blot_backend_layout::Tag.boolean; },
        unsigned32 => { valid = representation.tag == blot_backend_layout::Tag.unsigned32; },
        floating32 => { valid = representation.tag == blot_backend_layout::Tag.floating32; },
        function => { valid = representation.tag == blot_backend_layout::Tag.function; },
        array => { valid = representation.tag == blot_backend_layout::Tag.array; },
        list => { valid = representation.tag == blot_backend_layout::Tag.list; },
        cursor => { valid = representation.tag == blot_backend_layout::Tag.cursor; },
        type_constructor => { valid = representation.tag == blot_backend_layout::Tag.type_constructor && n.a == representation.a && n.b == representation.b; },
        resolver => { valid = representation.tag == blot_backend_layout::Tag.resolver; },
        provider => { valid = representation.tag == blot_backend_layout::Tag.provider; },
        state_provider => { valid = representation.tag == blot_backend_layout::Tag.state_provider; },
        product => { valid = representation.tag == blot_backend_layout::Tag.product; },
        record => { valid = representation.tag == blot_backend_layout::Tag.record; },
        nominal => { valid = representation.tag == blot_backend_layout::Tag.nominal && n.a == representation.a && n.b == representation.b; },
        _ => {},
    }
    if !valid { return decline(self, unit_id, span, FailureCode.unresolved_type); }
    if n.tag == blot_check_types::Tag.function || n.tag == blot_check_types::Tag.array || n.tag == blot_check_types::Tag.list || n.tag == blot_check_types::Tag.cursor || n.tag == blot_check_types::Tag.resolver || n.tag == blot_check_types::Tag.provider {
        let error = mapTypeDepthSink(self, unit_id, mappings, rows, n.a, representation.a, span, depth + 1); if error != Error.none { return error; }
        if n.tag == blot_check_types::Tag.function { let e = mapTypeDepthSink(self, unit_id, mappings, rows, n.b, representation.b, span, depth + 1); if e != Error.none { return e; } }
        if (n.tag == blot_check_types::Tag.function || n.tag == blot_check_types::Tag.provider) && hasRows(rows) { return mapRowSink(self, unit_id, mappings, rows, n.c, representation.c, span, false); }
    } else if n.tag == blot_check_types::Tag.state_provider {
        let a = mapTypeDepthSink(self, unit_id, mappings, rows, n.a, representation.a, span, depth + 1); if a != Error.none { return a; }
        let b = mapTypeDepthSink(self, unit_id, mappings, rows, n.b, representation.b, span, depth + 1); if b != Error.none { return b; }
        return mapTypeDepthSink(self, unit_id, mappings, rows, n.c, representation.c, span, depth + 1);
    } else if n.tag == blot_check_types::Tag.product || n.tag == blot_check_types::Tag.nominal {
        var children: const blot_check_types::Id[:] = []; if n.tag == blot_check_types::Tag.nominal { children = source.types.nominalArguments(n); } else { children = source.types.list(blot_check_types::List { n.a, n.b }); }
        if children.len != self.layouts.children(concrete).len { return decline(self, unit_id, span, FailureCode.unresolved_type); }
        for child, index in children { let error = mapTypeDepthSink(self, unit_id, mappings, rows, child, self.layouts.children(concrete)[index], span, depth + 1); if error != Error.none { return error; } }
    } else if n.tag == blot_check_types::Tag.record { return mapRecordSink(self, unit_id, mappings, rows, n, concrete, span, depth); }
    return Error.none;
}
fn mapRecordSink(self: Service&, unit_id: u32, mappings: MappingSink, rows: RowSink, n: blot_check_types::Node, concrete: u32, span: blot_check_core::Span, depth: i64) -> Error {
    if self.layouts.children(concrete).len != n.b as i64 * 2 { return decline(self, unit_id, span, FailureCode.unresolved_type); }
    for i in 0..n.b {
        let field = unit(self, unit_id).types.recordField(n, i); var matched = false; var j: i64 = 0;
        while j < n.b as i64 * 2 {
            if self.layouts.children(concrete)[j] == field.name { let error = mapTypeDepthSink(self, unit_id, mappings, rows, field.ty, self.layouts.children(concrete)[j + 1], span, depth + 1); if error != Error.none { return error; } matched = true; break; } j += 2;
        }
        if !matched { return decline(self, unit_id, span, FailureCode.unresolved_type); }
    }
    return Error.none;
}
fn mapRowSink(self: Service&, unit_id: u32, mappings: MappingSink, rows: RowSink, source_row: u32, actual_row: u32, span: blot_check_core::Span, covariant: bool) -> Error {
    if actual_row == blot_backend_layout::unknown_row { return Error.none; }
    let source = unit(self, unit_id).types; let expected = source.row(source_row);
    // Mapping may extend both effect stores. Keep IDs, and reload every view.
    var actuals = blot_backend_substitution_buffers::Words {}; 
    recursive fn cleanup_continuation_12() -> Error {
 let copied = actuals.append(self.layouts.effects.view().rowLabels(actual_row)); if copied != Error.none { return copied; }
    var used = blot_backend_substitution_buffers::Flags {}; 
    recursive fn cleanup_continuation_11() -> Error {
 for actual in actuals.items { let appended = used.push(false); if appended != Error.none { return appended; } }
    var argument_ids = blot_backend_substitution_buffers::Words {}; 
    recursive fn cleanup_continuation_10() -> Error {

    for label in source.rowLabels(source_row) {
        let source_operation = source.operation(label); let bound_instance = blot_backend_layout::mappedInstance(source_operation.instance, mappingItems(mappings));
        if source_operation.instance.unit == 0 && source_operation.instance.decl != 0 && bound_instance.unit != 0 {
            var selected_arguments = blot_support::none<u32>();
            for actual, index in actuals.items {
                if used.items[index] { continue; } let operation = self.layouts.effects.view().operation(actual);
                if operation.identity != source_operation.identity || operation.instance != bound_instance { continue; }
                let count = self.layouts.effects.view().operationArguments(actual).len; if count != source.operationArguments(label).len { continue; }
                if selected_arguments.present {
                    for argument_index in 0..count {
                        let first = self.layouts.effects.view().operationArguments(selected_arguments.value)[argument_index];
                        let next = self.layouts.effects.view().operationArguments(actual)[argument_index];
                        let first_evidence, first_error = toEvidence(self, first); if first_error != Error.none { return representationError(self, first_error, unit_id, span, FailureCode.unresolved_type); }
                        let next_evidence, next_error = toEvidence(self, next); if next_error != Error.none { return representationError(self, next_error, unit_id, span, FailureCode.unresolved_type); }
                        if first_evidence != next_evidence { return decline(self, unit_id, span, FailureCode.unresolved_type); }
                    }
                } else { selected_arguments = blot_support::some(actual); }
            }
            if !selected_arguments.present { return decline(self, unit_id, span, FailureCode.unresolved_type); }
            let actual = selected_arguments.value;
            for argument, index in source.operationArguments(label) {
                let concrete = self.layouts.effects.view().operationArguments(actual)[index];
                let semantic, semantic_error = toEvidence(self, concrete); if semantic_error != Error.none { return representationError(self, semantic_error, unit_id, span, FailureCode.unresolved_type); }
                let error = mapTypeDepthSink(self, unit_id, mappings, rows, argument, concrete, span, 0); if error != Error.none { return error; }
            }
        }
        argument_ids.clear();
        for argument in source.operationArguments(label) {
            let concrete, layout_error = codeLayoutWithRows(self, unit_id, argument, mappingItems(mappings), rowItems(rows), span); if layout_error != Error.none { return layout_error; }
            let semantic, semantic_error = toEvidence(self, concrete); if semantic_error != Error.none { return representationError(self, semantic_error, unit_id, span, FailureCode.unresolved_type); } let appended = argument_ids.push(semantic); if appended != Error.none { return appended; }
        }
        let identity = source.operation(label).identity; let source_instance = source.operation(label).instance;
        let instance = blot_backend_layout::mappedInstance(source_instance, mappingItems(mappings)); let unbound_instance = instance.unit == 0 && instance.decl != 0;
        var selected = blot_support::none<i64>();
        for actual, index in actuals.items {
            if used.items[index] { continue; } let operation = self.layouts.effects.view().operation(actual); if identity != operation.identity { continue; }
            if unbound_instance { if operation.instance.unit == 0 || operation.instance.decl == 0 { continue; } } else if instance != operation.instance { continue; }
            let count = self.layouts.effects.view().operationArguments(actual).len; if count != argument_ids.items.len { continue; }
            var same = true;
            for argument_index in 0..count {
                let argument = self.layouts.effects.view().operationArguments(actual)[argument_index];
                let semantic, error = toEvidence(self, argument); if error != Error.none { return representationError(self, error, unit_id, span, FailureCode.unresolved_type); } same = same && semantic == argument_ids.items[argument_index];
            }
            if same {
                if selected.present { if self.layouts.effects.view().operation(actuals.items[selected.value]).instance != operation.instance { return decline(self, unit_id, span, FailureCode.unresolved_type); } } else { selected = blot_support::some(index); }
                if !unbound_instance { break; }
            }
        }
        if !selected.present { return decline(self, unit_id, span, FailureCode.unresolved_type); }
        let index = selected.value; used.items[index] = true;
        if unbound_instance { let error = appendSink(mappings, Mapping { variable: source_instance.decl, layout: blot_backend_layout::erased, instance: self.layouts.effects.view().operation(actuals.items[index]).instance }); if error != Error.none { return error; } }
    }
    var suffix = blot_backend_substitution_buffers::Words {}; 
    recursive fn cleanup_continuation_9() -> Error {
 for label,index in actuals.items { if !used.items[index] { let appended = suffix.push(label); if appended != Error.none { return appended; } } }
    var variable: u32 = 0;
    match expected.tail {
        closed => { if !covariant && suffix.items.len != 0 { return decline(self, unit_id, span, FailureCode.unresolved_type); } return Error.none; },
        parameter p => { return decline(self, unit_id, span, FailureCode.unresolved_type); },
        variable v => { variable = v.value; },
        formal f => {
            let binder = f.value;
            if binder >= source.nodes.len || source.node(binder).tag != blot_check_types::Tag.bound || source.node(binder).b != 1 || source.node(binder).c != 0 { return decline(self, unit_id, span, FailureCode.unresolved_type); }
            let key, error = blot_check_types::formalRowKey(binder); if error != Error.none { return decline(self, unit_id, span, FailureCode.complexity); } variable = key;
        },
    }
    let remaining, row_error = self.layouts.effects.internRowWithFormal(suffix.items, self.layouts.effects.rows.items[actual_row].formal);
    if row_error != Error.none { return representationError(self, row_error, unit_id, span, FailureCode.complexity); }
    for entry in rowItems(rows) {
        if entry.variable != variable { continue; } if entry.row == remaining { return Error.none; }
        let prior, prior_error = rowToEvidence(self, entry.row); if prior_error != Error.none { return representationError(self, prior_error, unit_id, span, FailureCode.unresolved_type); }
        let current, current_error = rowToEvidence(self, remaining); if current_error != Error.none { return representationError(self, current_error, unit_id, span, FailureCode.unresolved_type); }
        if prior != current { return decline(self, unit_id, span, FailureCode.unresolved_type); } return Error.none;
    }
    return appendSink(rows,RowMapping { variable,remaining });

    }
    let cleanup_result_9_0 = cleanup_continuation_9();
     suffix.deinit(); 
    return cleanup_result_9_0;

    }
    let cleanup_result_10_0 = cleanup_continuation_10();
     argument_ids.deinit(); 
    return cleanup_result_10_0;

    }
    let cleanup_result_11_0 = cleanup_continuation_11();
     used.deinit(); 
    return cleanup_result_11_0;

    }
    let cleanup_result_12_0 = cleanup_continuation_12();
     actuals.deinit(); 
    return cleanup_result_12_0;
}
fn refineMappings(self: Service&,unit_id: u32,root: EvidenceRoot,expected: u32,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,span: blot_check_core::Span) -> Error { return refineMappingsSink(self,unit_id,root,expected,MappingSink.lexical { mappings },RowSink.lexical { rows },span); }
fn refineMappings(self: Service&,unit_id: u32,root: EvidenceRoot,expected: u32,mappings: blot_backend_substitution_buffers::Mappings&,rows: blot_backend_substitution_buffers::Rows&,span: blot_check_core::Span) -> Error { let selected,error = mappingSink(mappings); if error != Error.none { return error; } let selected_rows,row_error = rowSink(rows); if row_error != Error.none { return row_error; } return refineMappingsSink(self,unit_id,root,expected,selected,selected_rows,span); }
fn refineMappingsSink(self: Service&,unit_id: u32,root: EvidenceRoot,expected: u32,mappings: MappingSink,rows: RowSink,span: blot_check_core::Span) -> Error { return refineMappingsCapturesSink(self,unit_id,root,expected,mappings,rows,span,[]); }
struct RefinementCall {
    unit: u32, root: EvidenceRoot, expected: u32, span: blot_check_core::Span,
    seeds: const blot_eval_type_evidence::Mapping[:], rows: const blot_eval_type_evidence::RowMapping[:], captures: const blot_eval_core_eval::RetainedCapture[:],
    shapes: MappingSink, projection: blot_eval_core_eval::CodeProjection, enabled: bool, profiling: bool, has_instances: bool, rejected_candidates: u16,
}
fn refineFresh(self: Service&, call: RefinementCall) -> blot_eval_core_eval::SolvedEvidence, Error {
    let before_nodes = self.evaluator.counters.inference_specialization_nodes; let before_recorded = self.refinement_stats.recorded; let before_record_declines = self.refinement_stats.record_declines;
    self.refinement_regions++;
    let tape,tape_error = blot_reuse_specialization_receipt::initPooled(); if tape_error != Error.none { return default<blot_eval_core_eval::SolvedEvidence>(),tape_error; } 
    recursive fn cleanup_continuation_8() -> blot_eval_core_eval::SolvedEvidence, Error {

    var observation = blot_reuse_refinement_receipt::Observation {};
    let old_tape .= self.evaluator.receipt_tape; let old_observation .= self.evaluator.refinement_observation;
    if call.enabled { self.evaluator.receipt_tape .= tape; self.evaluator.refinement_observation .= observation; }
    
    recursive fn cleanup_continuation_7() -> blot_eval_core_eval::SolvedEvidence, Error {

    let before_values = self.evaluator.storage.values.len; let before_children = self.evaluator.storage.children.len; let before_steps = self.evaluator.steps;
    var output: blot_eval_core_eval::SolvedEvidence; var error: Error = Error.none;
    match call.root {
        body b => { output, error = self.evaluator.bodyEvidencePartialFullCode(b.target, self.bridge.partialView(), call.expected, call.seeds, call.rows, call.projection); },
        closure c => { output, error = self.evaluator.closureEvidencePartialCapturesCode(c.unit, c.catalog, self.bridge.partialView(), call.expected, call.seeds, call.rows, call.captures, call.projection); },
    }
    if error != Error.none { if error == Error.out_of_memory { return default<blot_eval_core_eval::SolvedEvidence>(), error; } return default<blot_eval_core_eval::SolvedEvidence>(), evaluationFailure(self); }
    var publication: u16 = 0;
    if call.enabled && call.profiling {
        if mappingItems(call.shapes).len != 0 { publication |= 1; } if tape.unknown { publication |= 2; } if tape.nested { publication |= 4; }
        if !observation.complete { publication |= 8; } if observation.regions != 1 { publication |= 16; } if output.selected.len != 0 { publication |= 32; }
        if self.evaluator.storage.values.len != before_values { publication |= 64; } if self.evaluator.storage.children.len != before_children { publication |= 128; }
        if self.evaluator.steps != before_steps { publication |= 256; } if tape.views.len != 0 { publication |= 512; }
    }
    if call.enabled && mappingItems(call.shapes).len == 0 {
        assert(self.cache); let recorded = self.cache.recordRefinement(Record { root: call.root, expected: call.expected, seeds: call.seeds, rows: call.rows, result: output, tape: tape, observed: observation, before_values: before_values, before_children: before_children, before_steps: before_steps });
        if recorded != Error.none { output.deinit(); return default<blot_eval_core_eval::SolvedEvidence>(), recorded; }
    }
    if call.profiling && self.timing != null {
        var record_rejections: u8 = 0;
        for before, index in before_record_declines { if self.refinement_stats.record_declines[index] != before { record_rejections |= (1 as u8) << index as u32; } }
        var admission: u8 = 0; if self.cache == null { admission |= 1; } if call.has_instances { admission |= 2; } if call.captures.len != 0 { admission |= 4; } if self.code_projection.present { admission |= 8; } if old_tape != null { admission |= 16; }
        if call.enabled { if self.refinement_stats.recorded != before_recorded { publication |= 2048; } else { publication |= 1024; } }
        var source: u32 = 0; var closure = false; match call.root { body b => { source = b.target.binding; }, closure c => { source = c.catalog; closure = true; } }
        self.timing.refinements.add(blot_backend_backend_timing::RefinementRequest {
            cost: blot_backend_backend_timing::RefinementCost { admission: admission, publication: publication, rejected_candidates: call.rejected_candidates, record_rejections: record_rejections, requests: 1, nodes: (self.evaluator.counters.inference_specialization_nodes - before_nodes) as u64 },
            unit: call.unit, source: source, closure: closure, expected: call.expected, seeds: call.seeds.len, rows: call.rows.len,
        });
    }
    return output, Error.none;

    }
    let cleanup_result_7_0,cleanup_result_7_1 = cleanup_continuation_7();
     self.evaluator.receipt_tape .= old_tape; self.evaluator.refinement_observation .= old_observation; 
    return cleanup_result_7_0,cleanup_result_7_1;

    }
    let cleanup_result_8_0,cleanup_result_8_1 = cleanup_continuation_8();
     tape.deinit(); 
    return cleanup_result_8_0,cleanup_result_8_1;
}
fn refineMappingsCaptures(self: Service&,unit_id: u32,root: EvidenceRoot,expected: u32,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,span: blot_check_core::Span,captures: const blot_eval_core_eval::RetainedCapture[:]) -> Error { return refineMappingsCapturesSink(self,unit_id,root,expected,MappingSink.lexical { mappings },RowSink.lexical { rows },span,captures); }
fn refineMappingsCaptures(self: Service&,unit_id: u32,root: EvidenceRoot,expected: u32,mappings: blot_backend_substitution_buffers::Mappings&,rows: blot_backend_substitution_buffers::Rows&,span: blot_check_core::Span,captures: const blot_eval_core_eval::RetainedCapture[:]) -> Error { let selected,error = mappingSink(mappings); if error != Error.none { return error; } let selected_rows,row_error = rowSink(rows); if row_error != Error.none { return row_error; } return refineMappingsCapturesSink(self,unit_id,root,expected,selected,selected_rows,span,captures); }
fn refineMappingsCapturesSink(self: Service&, unit_id: u32, root: EvidenceRoot, expected: u32, mappings: MappingSink, rows: RowSink, span: blot_check_core::Span, captures: const blot_eval_core_eval::RetainedCapture[:]) -> Error {
    let inference_stage = self.evaluator.enterInferenceStage(blot_work_counters::InferenceStage.specialization); 
    recursive fn cleanup_continuation_6() -> Error {

    var shapes = blot_backend_substitution_buffers::Mappings {}; 
    recursive fn cleanup_continuation_5() -> Error {
 let partial,projection_error = physicalProjection(self.layouts,shapes); if projection_error != Error.none { return projection_error; }
    var physical = partial; if self.code_projection.present { physical = mappingTarget(self.code_projection.value); }
    var owned_projection = OwnedProjection { unit: unit_id, mappings: mappingItems(mappings), physical: physical }; let projection = blot_eval_core_eval::CodeProjection.owned { owned_projection };
    var timing = blot_support::none<blot_backend_backend_timing::Scope>(); if self.timing != null { timing = blot_support::some(self.timing.enter(blot_backend_backend_timing::Phase.specialization)); } 
    recursive fn cleanup_continuation_4() -> Error {

    self.refinement_stats.requests++;
    var seeds = blot_backend_substitution_buffers::EvidenceMappings {}; 
    recursive fn cleanup_continuation_3() -> Error {
 var row_seeds = blot_backend_substitution_buffers::EvidenceRows {}; 
    recursive fn cleanup_continuation_2() -> Error {

    for entry in mappingItems(mappings) {
        if entry.instance.decl != 0 { continue; } let evidence, error = toEvidence(self, entry.layout);
        if error != Error.none { if error == Error.unresolved_type { continue; } return representationError(self, error, unit_id, span, FailureCode.unresolved_type); }
        let appended = seeds.push(blot_eval_type_evidence::Mapping { variable: entry.variable,evidence }); if appended != Error.none { return appended; }
    }
    for entry in rowItems(rows) {
        if entry.row == blot_backend_layout::unknown_row { continue; } let actual, error = rowToEvidence(self, entry.row);
        if error != Error.none { if error == Error.unresolved_type { continue; } return representationError(self, error, unit_id, span, FailureCode.unresolved_type); }
        let appended = row_seeds.push(blot_eval_type_evidence::RowMapping { variable: entry.variable,evidence: actual }); if appended != Error.none { return appended; }
    }
    let result, result_error = self.bridge.toCodeExpectation(expected); if result_error != Error.none { return representationError(self, result_error, unit_id, span, FailureCode.unresolved_type); }
    var has_instances = false; for entry in mappingItems(mappings) { has_instances = has_instances || entry.instance.decl != 0; }
    let enabled = !has_instances && self.cache != null && captures.len == 0 && !self.code_projection.present && self.evaluator.receipt_tape == null;
    var profiling = false; if self.timing != null { profiling = self.timing.clock.enabled; }
    var before_reasons: i64[9] = [0; 9]; if profiling { before_reasons = self.refinement_stats.reasons; }
    var cached = blot_support::none<blot_eval_core_eval::SolvedEvidence>();
    if enabled { assert(self.cache); let value, error = self.cache.lookupRefinement(root, self.bridge.partialView(), result, seeds.items, row_seeds.items); if error != Error.none { return error; } cached = value; }
    var rejected_candidates: u16 = 0;
    if profiling { for before, index in before_reasons { if self.refinement_stats.reasons[index] != before { rejected_candidates |= (1 as u16) << index as u32; } } }
    var solved: blot_eval_core_eval::SolvedEvidence;
    if cached.present { solved = cached.value; } else {
        let value, error = refineFresh(self, RefinementCall { unit: unit_id, root: root, expected: result, span: span, seeds: seeds.items, rows: row_seeds.items, captures: captures, shapes: MappingSink.pooled { shapes }, projection: projection, enabled: enabled, profiling: profiling, has_instances: has_instances, rejected_candidates: rejected_candidates });
        if error != Error.none { return error; } solved = value;
    }
    
    recursive fn cleanup_continuation_1() -> Error {

    for entry in solved.types {
        var retained = false; for seed in seeds.items { if seed.variable == entry.variable && seed.evidence == entry.evidence { retained = true; break; } } if retained { continue; }
        let concrete, error = fromEvidence(self, entry.evidence); if error != Error.none { return representationError(self, error, unit_id, span, FailureCode.unresolved_type); }
        let mapped = mapTypeDepthSink(self, unit_id, mappings, rows, entry.variable, concrete, span, 0); if mapped != Error.none { return mapped; }
    }
    for entry in solved.rows {
        let concrete, error = rowFromEvidence(self, entry.evidence); if error != Error.none { return representationError(self, error, unit_id, span, FailureCode.unresolved_type); }
        var found = false;
        for prior in rowItems(rows) {
            if prior.variable != entry.variable { continue; } let actual, e = rowToEvidence(self, prior.row); if e != Error.none { return representationError(self, e, unit_id, span, FailureCode.unresolved_type); }
            if actual != entry.evidence { return decline(self, unit_id, span, FailureCode.unresolved_type); } found = true; break;
        }
        if !found { let appended = appendSink(rows,RowMapping { entry.variable,concrete }); if appended != Error.none { return appended; } }
    }
    for shape in shapes.items { let error = mapTypeDepthSink(self, unit_id, mappings, rows, shape.variable, shape.layout, span, 0); if error != Error.none { return error; } }
    return Error.none;

    }
    let cleanup_result_1_0 = cleanup_continuation_1();
     solved.deinit(); 
    return cleanup_result_1_0;

    }
    let cleanup_result_2_0 = cleanup_continuation_2();
     row_seeds.deinit(); 
    return cleanup_result_2_0;

    }
    let cleanup_result_3_0 = cleanup_continuation_3();
     seeds.deinit(); 
    return cleanup_result_3_0;

    }
    let cleanup_result_4_0 = cleanup_continuation_4();
     if timing.present { timing.value.deinit(); } 
    return cleanup_result_4_0;

    }
    let cleanup_result_5_0 = cleanup_continuation_5();
     shapes.deinit(); 
    return cleanup_result_5_0;

    }
    let cleanup_result_6_0 = cleanup_continuation_6();
     inference_stage.deinit(); 
    return cleanup_result_6_0;
}
