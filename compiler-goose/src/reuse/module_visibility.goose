// Check the public type frontier separately from executable bodies and opaque
// owners' private representation.
namespace blot_reuse_module_visibility;
import std;
import dictionary;
import check.types;
import check.frozen_types;
import reuse.principal_interface;
import support.error;
import support.pooled_buffer;
type Error = blot_error::Error;
type Source = blot_check_frozen_types::Source;
type Identity = blot_check_types::NominalIdentity;
struct Work { id: u32, row: bool = false }
fn hash(value: Work) -> u64 { return ::hash_combine(::hash(value.id), ::hash(value.row)); }
type WorkBuffer=blot_support_pooled_buffer::Buffer<Work>;
reusable[] var work_runs:Work[>..]=[];
struct Scan { source: Source, blocked: dictionary<Identity,bool>&, seen: dictionary<Work,bool>&, work:WorkBuffer=WorkBuffer{..}, remaining: i64 = 1000000 }
fn withScan<C,F>(source: Source, nominals: const blot_reuse_principal_interface::Nominal[:], families: const blot_reuse_principal_interface::EffectFamily[:], templates: const blot_reuse_principal_interface::EffectTemplate[:], context: C&) -> Error {
    var blocked: dictionary<Identity,bool> = dictionary<Identity,bool>{}; var seen: dictionary<Work,bool> = dictionary<Work,bool>{};
    var scan = Scan { source:source,blocked:blocked,seen:seen,..};
    for nominal in nominals { if nominal.private && nominal.alias == 0 { blocked.insert(nominal.identity, true); } }
    for family in families { if family.private { blocked.insert(family.identity, true); } }
    for operation in templates { if operation.family < families.len && families[operation.family].private { blocked.insert(operation.identity, true); } }
    let error = F(context, scan); scan.deinit(); return error;
}
fn deinit(self_: Scan&) { self_.blocked.clear();self_.seen.clear();blot_support_pooled_buffer::deinit(self_.work,work_runs); }
fn enqueue(self_: Scan&, item: Work) -> Error {
    if item.id == 0 || self_.seen.contains(item) { return blot_error::Error.none; }
    self_.seen.insert(item, true);
    if self_.remaining == 0 { return blot_error::Error.type_limit; }
    self_.remaining--;return blot_support_pooled_buffer::push(self_.work,item,work_runs);
}
fn allowed(self_: Scan&, root: u32) -> bool, Error {
    self_.seen.clear(); blot_support_pooled_buffer::clear(self_.work);
    let first = self_.enqueue(Work { root , ..}); if first != blot_error::Error.none { return false, first; }
    while self_.work.items.len != 0 {
        let item = self_.work.items[self_.work.items.len - 1]; blot_support_pooled_buffer::resize(self_.work,self_.work.items.len - 1);
        if item.row {
            let row = self_.source.row(item.id);
            let source_visit_1_count=(self_.source.rowLabels(row.labels)).len;for source_visit_1_index in 0..source_visit_1_count {let label=(self_.source.rowLabels(row.labels))[source_visit_1_index];
                let operation = self_.source.operation(label);
                if self_.blocked.contains(operation.identity) { return false, blot_error::Error.none; }
                let source_visit_2_count=(self_.source.list(operation.arguments)).len;for source_visit_2_index in 0..source_visit_2_count {let argument=(self_.source.list(operation.arguments))[source_visit_2_index]; let error = self_.enqueue(Work { argument , ..}); if error != blot_error::Error.none { return false, error; } }
            }
            continue;
        }
        let node = self_.source.node(self_.source.head(item.id, 0));
        match node.tag {
            nominal, projection, type_constructor => {
                if self_.blocked.contains(Identity { node.a, node.b , ..}) { return false, blot_error::Error.none; }
                if node.tag == blot_check_types::Tag.nominal || node.tag == blot_check_types::Tag.projection {
                    let source_visit_3_count=(self_.source.nominalArguments(node)).len;for source_visit_3_index in 0..source_visit_3_count {let argument=(self_.source.nominalArguments(node))[source_visit_3_index]; let error = self_.enqueue(Work { argument , ..}); if error != blot_error::Error.none { return false, error; } }
                }
            },
            function => { { let propagated_error = self_.enqueue(Work { node.a , ..}); if propagated_error != blot_error::Error.none { return false, propagated_error; } } { let propagated_error = self_.enqueue(Work { node.b , ..}); if propagated_error != blot_error::Error.none { return false, propagated_error; } } { let propagated_error = self_.enqueue(Work { node.c, true , ..}); if propagated_error != blot_error::Error.none { return false, propagated_error; } } },
            provider => { { let propagated_error = self_.enqueue(Work { node.a , ..}); if propagated_error != blot_error::Error.none { return false, propagated_error; } } { let propagated_error = self_.enqueue(Work { node.c, true , ..}); if propagated_error != blot_error::Error.none { return false, propagated_error; } } },
            state_provider => { { let propagated_error = self_.enqueue(Work { node.a , ..}); if propagated_error != blot_error::Error.none { return false, propagated_error; } } { let propagated_error = self_.enqueue(Work { node.b , ..}); if propagated_error != blot_error::Error.none { return false, propagated_error; } } { let propagated_error = self_.enqueue(Work { node.c , ..}); if propagated_error != blot_error::Error.none { return false, propagated_error; } } },
            usage, array, list, cursor, resolver => { { let propagated_error = self_.enqueue(Work { node.a , ..}); if propagated_error != blot_error::Error.none { return false, propagated_error; } } },
            product => { let source_visit_4_count=(self_.source.list(blot_check_types::List { node.a, node.b , ..})).len;for source_visit_4_index in 0..source_visit_4_count {let child=(self_.source.list(blot_check_types::List { node.a, node.b , ..}))[source_visit_4_index]; { let propagated_error = self_.enqueue(Work { child , ..}); if propagated_error != blot_error::Error.none { return false, propagated_error; } } } },
            record => { for index in 0..node.b { { let propagated_error = self_.enqueue(Work { self_.source.recordField(node, index).ty , ..}); if propagated_error != blot_error::Error.none { return false, propagated_error; } } } },
            _ => {},
        }
    }
    return true, blot_error::Error.none;
}
