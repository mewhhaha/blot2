// A field footprint changes physical parameters while retaining semantic types.
namespace blot_backend_storage_parameter_fields;
import check.core;
import check.types;
import eval.body_recipe;
import support.error;
import support.option;
import support.pooled_buffer;
type Error = blot_error::Error;
struct Names { storage: u32[:] = [],items: u32[:] = [] }
reusable[] var name_runs: u32[>..] = [];
struct Fields { names: Names,whole: bool = false }
fn deinit(fields: Fields&) { blot_support_pooled_buffer::deinit(fields.names,name_runs); }
fn namedRecordProjection(module: const blot_check_core::Module&,index: u32) -> bool {
    let projection = module.projection(index); if projection.nominal.unit != 0 || projection.nominal.decl != 0 || projection.variants.len != 1 { return false; } let record = module.types.node(projection.source_type); if record.tag != blot_check_types::Tag.record { return false; } let variant = module.projectionVariants(index)[0]; return variant.tag == 0 && variant.field < record.b && module.types.recordField(record,variant.field).name == projection.field;
}
struct NominalRecord { identity: blot_check_types::NominalIdentity,tag: u32 }
fn projection(record: NominalRecord,module: const blot_check_core::Module&,index: u32,remaining: i64&) -> bool {
    let selected = module.projection(index); let name = module.fieldSpelling(selected.field); if !name.present { return false; } let variants = module.projectionVariants(index); if variants.len == 0 { return selected.nominal.unit == 0 && selected.nominal.decl == 0; } if selected.nominal != record.identity || variants.len != 1 || variants[0].tag != record.tag { return false; }
    for constructor in module.constructors { if remaining == 0 { return false; } remaining--; if module.nominal(constructor.nominal).identity != record.identity || constructor.tag != record.tag { continue; } let payload = module.types.node(constructor.payload); if payload.tag != blot_check_types::Tag.record || variants[0].field >= payload.b { return false; } let field_name = module.fieldSpelling(module.types.recordField(payload,variants[0].field).name); if !field_name.present { return false; } return name.value == field_name.value; } return false;
}
fn nominalRecord(module: const blot_check_core::Module&,ty: u32,remaining: i64&) -> blot_support::Option<NominalRecord> {
    let node = module.types.node(ty); if node.tag != blot_check_types::Tag.nominal || module.types.nominalArguments(node).len != 0 { return blot_support::none<NominalRecord>(); }
    for nominal,ordinal in module.nominals { if remaining == 0 { return blot_support::none<NominalRecord>(); } remaining--; if nominal.identity.unit != node.a || nominal.identity.decl != node.b { continue; } if nominal.is_opaque || nominal.affine || nominal.has_usage || nominal.parameters.len != 0 || nominal.variables.len != 0 { return blot_support::none<NominalRecord>(); } let constructors = module.nominalConstructors(ordinal as u32); if constructors.len != 1 { return blot_support::none<NominalRecord>(); } let constructor = module.constructor(constructors[0]); if module.types.node(constructor.payload).tag != blot_check_types::Tag.record { return blot_support::none<NominalRecord>(); } return blot_support::some(NominalRecord { identity: nominal.identity,tag: constructor.tag , ..}); } return blot_support::none<NominalRecord>();
}
struct Walk { module: const blot_check_core::Module&,parameter: u32,nominal: blot_support::Option<NominalRecord>,fields: Fields,remaining: i64 = 100000 }
reusable var walks: Walk[>..] = [];
fn collect(module: const blot_check_core::Module&,root: u32,parameter: u32,nominal: blot_support::Option<NominalRecord>) -> Fields,Error {
    let index = walks.alloc_index(Walk { module,parameter,nominal , ..}); let walk: Walk& = walks[index]; let error = visit(walk,root,0);
    if error != Error.none && error != Error.plan_limit { walk.fields.deinit(); walks.free(index); return Fields {..},error; } if error == Error.plan_limit { walk.fields.whole = true; } let fields = walk.fields; walk.fields = Fields {..}; walks.free(index); return fields,Error.none;
}
fn target(walk: const Walk&,reference: blot_check_core::BindingRef) -> bool { (reference.unit == 0 || reference.unit == walk.module.unit) && reference.binding == walk.parameter }
fn wholeBinding(walk: Walk&,binding: u32) { if binding == walk.parameter { walk.fields.whole = true; } }
struct Children { walk: Walk&,depth: i64 }
fn append(children: Children&,id: u32) -> Error { visit(children.walk,id,children.depth) }
fn appendSlice(children: Children&,ids: const u32[:]) -> Error { for id in ids { let error = append(children,id); if error != Error.none { return error; } } return Error.none; }
recursive fn visit(walk: Walk&,id: u32,depth: i64) -> Error {
    if id == 0 || walk.fields.whole { return Error.none; } if walk.remaining == 0 || depth > 128 { return Error.plan_limit; } walk.remaining--; let module: const blot_check_core::Module& = walk.module; let node = module.node(id);
    match node.tag {
        reference=>{ if target(walk,module.reference(id)) { walk.fields.whole = true; } return Error.none; },
        project=>{ if node.a != 0 && module.node(node.a).tag == blot_check_core::Tag.reference && target(walk,module.reference(node.a)) { let projection = module.projection(node.b); var admitted = false; if walk.nominal.present { admitted = walk.nominal.value.projection(module,node.b,walk.remaining); } else { admitted = (projection.variants.len == 0 || namedRecordProjection(module,node.b)) && module.fieldSpelling(projection.field).present; } if !admitted { walk.fields.whole = true; return Error.none; } var found = false; for name in walk.fields.names.items { if name == projection.field { found = true; break; } } if !found { return blot_support_pooled_buffer::push(walk.fields.names,projection.field,name_runs); } return Error.none; } },
        closure=>{ for binding in module.closureCaptures(id) { wholeBinding(walk,binding); } return Error.none; },
        update=>{ var root = module.updateInfo(id).root; var path_depth = depth; while root != 0 && module.node(root).tag == blot_check_core::Tag.project { if walk.remaining == 0 || path_depth >= 128 { return Error.plan_limit; } walk.remaining--; path_depth++; root = module.node(root).a; } if root != 0 && module.node(root).tag == blot_check_core::Tag.reference && target(walk,module.reference(root)) { walk.fields.whole = true; return Error.none; } },
        if_value,if_stmt=>{ for merge in module.branchMerges(id) { wholeBinding(walk,merge.then_binding); wholeBinding(walk,merge.else_binding); } },
        loop_=>{ for carry in module.loopCarries(id) { wholeBinding(walk,carry.incoming); wholeBinding(walk,carry.backedge); } },
        pattern_bind=>{ match module.pattern(node.a).tag { bind,wildcard=>{},_=>{ return Error.plan_limit; }, } },
        match_=>{ return Error.plan_limit; },
        constant,scalar,associated,logical,apply,record_merge,block_,suite,bind,return_,product,record,construct,array,array_op,storage,call,panic,break_=>{},
        _=>{ return Error.plan_limit; },
    }
    var children = Children { walk,depth: depth + 1 , ..}; return blot_eval_body_recipe::appendChildren(children,module,id,false);
}
