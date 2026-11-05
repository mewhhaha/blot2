// Check the public type frontier separately from executable bodies and opaque
// owners' private representation.
namespace blot_reuse_module_visibility;
import std;
import dictionary;
import check.types;
import check.frozen_types;
import reuse.principal_interface;
import support.error;
type Error = blot_error::Error;
type Source = blot_check_frozen_types::Source;
type Identity = blot_check_types::NominalIdentity;
struct Work { id: u32, row: bool = false }
fn hash(value: Work) -> u64 { return ::hash_combine(::hash(value.id), ::hash(value.row)); }
struct Scan { source: Source, blocked: dictionary<Identity,bool>&, seen: dictionary<Work,bool>&, work: Work[>..<]&, remaining: i64 = 1000000 }
fn withScan<C,F>(source: Source, nominals: const blot_reuse_principal_interface::Nominal[:], families: const blot_reuse_principal_interface::EffectFamily[:], templates: const blot_reuse_principal_interface::EffectTemplate[:], context: C&) -> Error {
    var blocked: dictionary<Identity,bool>; var seen: dictionary<Work,bool>; var work: Work[>..<] = [];
    var scan = Scan { source, blocked, seen, work };
    for nominal in nominals { if nominal.private && nominal.alias == 0 { blocked.insert(nominal.identity, true); } }
    for family in families { if family.private { blocked.insert(family.identity, true); } }
    for operation in templates { if operation.family < families.len && families[operation.family].private { blocked.insert(operation.identity, true); } }
    let error = F(context, scan); scan.deinit(); return error;
}
fn deinit(self: Scan&) { self.blocked.clear(); self.seen.clear(); self.work.clear(); }
fn enqueue(self: Scan&, item: Work) -> Error {
    if item.id == 0 || self.seen.contains(item) { return Error.none; }
    self.seen.insert(item, true);
    if self.remaining == 0 { return Error.type_limit; }
    self.remaining--; self.work.push(item); return Error.none;
}
fn allowed(self: Scan&, root: u32) -> bool, Error {
    self.seen.clear(); self.work.clear();
    let first = self.enqueue(Work { root }); if first != Error.none { return false, first; }
    while self.work.len != 0 {
        let item = self.work[self.work.len - 1]; self.work.resize(self.work.len - 1);
        if item.row {
            let row = self.source.row(item.id);
            for label in self.source.rowLabels(row.labels) {
                let operation = self.source.operation(label);
                if self.blocked.contains(operation.identity) { return false, Error.none; }
                for argument in self.source.list(operation.arguments) { let error = self.enqueue(Work { argument }); if error != Error.none { return false, error; } }
            }
            continue;
        }
        let node = self.source.node(self.source.head(item.id, 0));
        match node.tag {
            blot_check_types::Tag.nominal, blot_check_types::Tag.projection, blot_check_types::Tag.type_constructor => {
                if self.blocked.contains(Identity { node.a, node.b }) { return false, Error.none; }
                if node.tag == blot_check_types::Tag.nominal || node.tag == blot_check_types::Tag.projection {
                    for argument in self.source.nominalArguments(node) { let error = self.enqueue(Work { argument }); if error != Error.none { return false, error; } }
                }
            },
            blot_check_types::Tag.function => { { let propagated_error = self.enqueue(Work { node.a }); if propagated_error != Error.none { return false, propagated_error; } } { let propagated_error = self.enqueue(Work { node.b }); if propagated_error != Error.none { return false, propagated_error; } } { let propagated_error = self.enqueue(Work { node.c, true }); if propagated_error != Error.none { return false, propagated_error; } } },
            blot_check_types::Tag.provider => { { let propagated_error = self.enqueue(Work { node.a }); if propagated_error != Error.none { return false, propagated_error; } } { let propagated_error = self.enqueue(Work { node.c, true }); if propagated_error != Error.none { return false, propagated_error; } } },
            blot_check_types::Tag.state_provider => { { let propagated_error = self.enqueue(Work { node.a }); if propagated_error != Error.none { return false, propagated_error; } } { let propagated_error = self.enqueue(Work { node.b }); if propagated_error != Error.none { return false, propagated_error; } } { let propagated_error = self.enqueue(Work { node.c }); if propagated_error != Error.none { return false, propagated_error; } } },
            blot_check_types::Tag.usage, blot_check_types::Tag.array, blot_check_types::Tag.list, blot_check_types::Tag.cursor, blot_check_types::Tag.resolver => { { let propagated_error = self.enqueue(Work { node.a }); if propagated_error != Error.none { return false, propagated_error; } } },
            blot_check_types::Tag.product => { for child in self.source.list(blot_check_types::List { node.a, node.b }) { { let propagated_error = self.enqueue(Work { child }); if propagated_error != Error.none { return false, propagated_error; } } } },
            blot_check_types::Tag.record => { for index in 0..node.b { { let propagated_error = self.enqueue(Work { self.source.recordField(node, index).ty }); if propagated_error != Error.none { return false, propagated_error; } } } },
            _ => {},
        }
    }
    return true, Error.none;
}
