// Immutable sequences copy into fixed inline storage instead of aliasing arrays.
namespace blot_backend_storage_collections;
import check.core;
import check.types;
import check.storage_types;
import support.option;
fn element(module: const blot_check_core::Module&,ty: blot_check_types::Id) -> blot_support::Option<blot_check_types::Id> { let node = module.types.node(ty); if node.tag == blot_check_types::Tag.list { return blot_support::some(node.a); } return blot_check_storage_types::arrayElement(module.types,ty); }
fn immutable(module: const blot_check_core::Module&,ty: blot_check_types::Id) -> bool { module.types.node(ty).tag == blot_check_types::Tag.list }
