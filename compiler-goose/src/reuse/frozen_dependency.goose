// Versioned payload IDs remain local until explicit loader validation/relinking.
namespace blot_reuse_frozen_dependency;
import check.core;
import reuse.principal_interface;
struct Symbol { text: u8[:] }
struct Identity { normalized_path: u8[:], source_digest: u8[32], source_bytes: u32, prelude: bool }
enum ExportKind { value, nominal, constructor, effect_family, contract, implementation }
struct Export { name: u32, target: blot_reuse_principal_interface::ExternalTarget, kind: ExportKind, catalog: u32 }
struct Fixity { operator: u32, target: u32, precedence: u32, association: u32, named: bool, producer: blot_reuse_principal_interface::ExternalTarget }
struct ImportResolution { path: u8[:], target: u32 }
struct Module {
    identity: Identity, imports: u32[:], implicit_prelude: bool = false, source_imports: ImportResolution[:] = default<ImportResolution[:]>(),
    core: blot_check_core::Module, interface: blot_reuse_principal_interface::Interface, exports: Export[:], fixities: Fixity[:],
}
struct FrozenDependency { symbols: Symbol[:], modules: Module[:] }
fn exportKindCode(kind: ExportKind) -> u32 { match kind { value => 0, nominal => 1, constructor => 2, effect_family => 3, contract => 4, implementation => 5 } }
fn exportKindFromCode(code: u32) -> ExportKind, bool { match code { 0 => { return ExportKind.value, true; }, 1 => { return ExportKind.nominal, true; }, 2 => { return ExportKind.constructor, true; }, 3 => { return ExportKind.effect_family, true; }, 4 => { return ExportKind.contract, true; }, 5 => { return ExportKind.implementation, true; }, _ => { return ExportKind.value, false; } } }

fn blot_structural::equal(left:blot_reuse_frozen_dependency::ExportKind,right:blot_reuse_frozen_dependency::ExportKind)->bool {return left==right;}
