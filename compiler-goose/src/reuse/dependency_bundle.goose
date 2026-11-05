// One source unit freezes generic semantics before application evaluation.
namespace blot_reuse_dependency_bundle;
import std;
import parse.ast;
import parse.symbols;
import check.check;
import check.core;
import check.core_builder;
import check.types;
import reuse.dependency_snapshot;
import reuse.dependency_payload;
import reuse.dependency_format;
import reuse.frozen_dependency;
import support.error;
type Error=blot_error::Error;
type D=blot_reuse_frozen_dependency::FrozenDependency;
type Owner=blot_reuse_dependency_payload::Owner;
type Owned=blot_reuse_dependency_payload::Owned<D>;
type Export=blot_reuse_frozen_dependency::Export;
type ExportKind=blot_reuse_frozen_dependency::ExportKind;
type Fixity=blot_reuse_frozen_dependency::Fixity;
fn freeze(path:const u8[:],source:const u8[:],pool:const blot_parse_symbols::Pool&,tree:const blot_parse_ast::Tree&,checked:const blot_check_check::Checked&,prelude:bool)->Owned,Error {
    var owner,opened=blot_reuse_dependency_payload::init();if opened!=blot_error::Error.none {return Owned{value:default<D>(),..},opened;}let value,error=freezePayload(owner,path,source,pool,tree,checked,prelude);if error!=blot_error::Error.none {owner.deinit();return Owned{value:default<D>(),..},error;}return Owned{value,owner},blot_error::Error.none;
}
fn freezePayload(owner:Owner&,path:const u8[:],source:const u8[:],pool:const blot_parse_symbols::Pool&,tree:const blot_parse_ast::Tree&,checked:const blot_check_check::Checked&,prelude:bool)->D,Error {
    if checked.unit!=1 || checked.diagnostics.len!=0 || source.len>0xffffffff {return default<D>(),blot_error::Error.invalid_artifact;}
    for id in tree.roots.items {let tag=tree.node(id).tag;if tag==blot_parse_ast::tag_import_decl || tag==blot_parse_ast::tag_export_decl {return default<D>(),blot_error::Error.imported_dependency_unsupported;}}
    var lowered,error=blot_check_core_builder::lower(tree,pool,checked);if error!=blot_error::Error.none {return default<D>(),error;}var ir=lowered.value;ir.unit=1;let adopted=owner.adopt(lowered.owner);if adopted!=blot_error::Error.none {lowered.deinit();return default<D>(),adopted;}if ir.diagnostics.len!=0 {return default<D>(),blot_error::Error.invalid_artifact;}
    for &node in owner.mutable(ir.types.nodes) {node=blot_check_types::Node{tag:node.tag,a:node.a,b:node.b,c:node.c,..};}for body in ir.bodies {if body.exported {return default<D>(),blot_error::Error.entry_dependency_unsupported;}}
    var interface,interface_error=blot_reuse_dependency_snapshot::freezePrincipal(tree,checked);if interface_error!=blot_error::Error.none {return default<D>(),interface_error;}let interface_adopted=owner.adopt(interface.owner);if interface_adopted!=blot_error::Error.none {interface.deinit();return default<D>(),interface_adopted;}
    var exports:Export[>..<]=[];
    for binding,id in checked.bindings {if binding.kind==blot_reuse_principal_interface::Kind.global && !binding.private {exports.push(Export{name:binding.name,target:blot_check_check::ExternalTarget{unit:1,binding:id as u32},kind:blot_reuse_frozen_dependency::ExportKind.value,catalog:0,..});}}
    for nominal,id in checked.nominals {if id!=0 && nominal.identity.unit==1 && !nominal.private {exports.push(Export{name:nominal.name,target:blot_check_check::ExternalTarget{0,0},kind:blot_reuse_frozen_dependency::ExportKind.nominal,catalog:id as u32,..});}}
    for constructor,id in checked.constructors {if id!=0 && constructor.identity.unit==1 && !constructor.private {exports.push(Export{name:constructor.name,target:blot_check_check::ExternalTarget{0,0},kind:blot_reuse_frozen_dependency::ExportKind.constructor,catalog:id as u32,..});}}
    for family,id in checked.effect_families {if id!=0 && family.identity.unit==1 && !family.private {exports.push(Export{name:family.name,target:blot_check_check::ExternalTarget{0,0},kind:blot_reuse_frozen_dependency::ExportKind.effect_family,catalog:id as u32,..});}}
    for contract,id in checked.contracts {if contract.identity.unit==1 && !contract.private {exports.push(Export{name:contract.name,target:blot_check_check::ExternalTarget{0,0},kind:blot_reuse_frozen_dependency::ExportKind.contract,catalog:id as u32,..});}}
    for implementation,id in checked.implementations {if implementation.identity.unit==1 && !implementation.private {exports.push(Export{name:implementation.name,target:blot_check_check::ExternalTarget{0,0},kind:blot_reuse_frozen_dependency::ExportKind.implementation,catalog:id as u32,..});}}
    var fixities:Fixity[>..<]=[];for id in tree.roots.items {if tree.node(id).tag==blot_parse_ast::tag_fixity_decl {let value=tree.fixity(id);let binding=checked.resolved[id];var target=blot_check_check::ExternalTarget{1,binding};if checked.bindings[binding].external.present {target=checked.bindings[binding].external.value;}fixities.push(Fixity{operator:value.operator,target:value.target,precedence:value.precedence,association:value.association,named:value.named,producer:target,..});}}
    let names,error=owner.alloc<blot_reuse_frozen_dependency::Symbol>(pool.entries.len+1);if error!=blot_error::Error.none {return default<D>(),error;}names[0]=blot_reuse_frozen_dependency::Symbol{text:[]};for index in 1..names.len {let bytes,error=owner.copy(pool.get(index as u32));if error!=blot_error::Error.none {return default<D>(),error;}names[index]=blot_reuse_frozen_dependency::Symbol{text:bytes};}
    let owned_path,e1=owner.copy(path);if e1!=blot_error::Error.none {return default<D>(),e1;}let owned_exports,e2=owner.copy(exports[..]);if e2!=blot_error::Error.none {return default<D>(),e2;}let owned_fixities,e3=owner.copy(fixities[..]);if e3!=blot_error::Error.none {return default<D>(),e3;}let modules,e4=owner.alloc<blot_reuse_frozen_dependency::Module>(1);if e4!=blot_error::Error.none {return default<D>(),e4;}
    modules[0]=blot_reuse_frozen_dependency::Module{identity:blot_reuse_frozen_dependency::Identity{normalized_path:owned_path,source_digest:blot_reuse_dependency_format::digest(source),source_bytes:source.len as u32,prelude:prelude,..},imports:[],core:ir,interface:interface.value,exports:owned_exports,fixities:owned_fixities,..};return D{symbols:names,modules:modules,..},blot_error::Error.none;
}
