// Typed reference classes are separate from numeric and nominal identities.
// Only a private owned destination may supply mutable() for rewriting a slice.
namespace blot_reuse_frontend_reference_relocation;
import check.core;
import check.frozen_types;
import check.types;
import reuse.frontend_binding_relocation;
import reuse.frozen_dependency;
import reuse.principal_interface;
import support.error;
import support.option;
import support.structural;

type Error=blot_error::Error;
type Targets=blot_reuse_frontend_binding_relocation::Targets;
fn visit(remaining:i64&)->Error {if remaining==0 {return Error.declined;}remaining--;return Error.none;}
fn admits<T>(value:const T&,targets:Targets)->bool {return changes(value,targets).present;}
fn changes<T>(value:const T&,targets:Targets)->blot_support::Option<bool> {var remaining:i64=65536;var changed=false;let error=scan(value,targets,remaining,changed);if error!=Error.none {return blot_support::none<bool>();}return blot_support::some(changed);}
fn rewrite<O,T>(owner:O&,value:T&,targets:Targets)->Error {var remaining:i64=65536;var changed=false;return rewriteOwned(owner,value,targets,remaining,changed);}

fn relocate(value:blot_check_core::BindingRef&,targets:Targets,changed:bool&)->Error {

if value.binding==0 {return Error.none;}let mapped=targets.target(blot_reuse_principal_interface::ExternalTarget {value.unit,value.binding, ..});if !mapped.present||mapped.value.unit!=value.unit {return Error.declined;}changed=changed||mapped.value.binding!=value.binding;value.binding=mapped.value.binding;

return Error.none;
}

fn relocate(value:blot_reuse_principal_interface::ExternalTarget&,targets:Targets,changed:bool&)->Error {

if value.binding==0 {return Error.none;}let mapped=targets.target(blot_reuse_principal_interface::ExternalTarget {value.unit,value.binding, ..});if !mapped.present||mapped.value.unit!=value.unit {return Error.declined;}changed=changed||mapped.value.binding!=value.binding;value.binding=mapped.value.binding;

return Error.none;
}

fn relocate(value:blot_check_types::Obligation&,targets:Targets,changed:bool&)->Error {

if value.qualification_span.present {let before=value.qualification_span.value;let after=targets.qualification(value.qualification_unit,before);changed=changed||before!=after;value.qualification_span=blot_support::some(after);}
if value.kind==blot_check_types::ObligationKind.callee_use&&value.identity.decl!=0 {let mapped=targets.target(blot_reuse_principal_interface::ExternalTarget {value.identity.unit,value.identity.decl, ..});if !mapped.present||mapped.value.unit!=value.identity.unit {return Error.declined;}changed=changed||mapped.value.binding!=value.identity.decl;value.identity.decl=mapped.value.binding;}

return Error.none;
}

fn relocate(value:blot_check_core::Obligation&,targets:Targets,changed:bool&)->Error {

if value.qualification_span.present {let before=value.qualification_span.value;let after=targets.qualification(value.qualification_unit,before);changed=changed||before!=after;value.qualification_span=blot_support::some(after);}
if value.kind==blot_check_types::ObligationKind.callee_use&&value.identity.decl!=0 {let mapped=targets.target(blot_reuse_principal_interface::ExternalTarget {value.identity.unit,value.identity.decl, ..});if !mapped.present||mapped.value.unit!=value.identity.unit {return Error.declined;}changed=changed||mapped.value.binding!=value.identity.decl;value.identity.decl=mapped.value.binding;}

return Error.none;
}

fn relocate(value:blot_reuse_frozen_dependency::Export&,targets:Targets,changed:bool&)->Error {

let mapped=targets.exported(copy(value));if !mapped.present {return Error.declined;}changed=changed||!blot_structural::equal(copy(value),mapped.value);value=mapped.value;

return Error.none;
}

fn relocate(value:blot_reuse_principal_interface::Implementation&,targets:Targets,changed:bool&)->Error {

if value.origin_span.present {let before=value.origin_span.value;let after=targets.qualification(value.identity.unit,before);changed=changed||before!=after;value.origin_span=blot_support::some(after);}

return Error.none;
}

fn scan(value:const blot_check_core::BindingRef&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

var candidate=copy(value);return relocate(candidate,targets,changed);

}

fn rewriteOwned<O>(owner:O&,value:blot_check_core::BindingRef&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

return relocate(value,targets,changed);

}

fn scan(value:const blot_check_core::BindingRef[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_check_core::BindingRef[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_check_core::ErasedDeclarationReference&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.target,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_check_core::ErasedDeclarationReference&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.target,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_check_core::ErasedDeclarationReference[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_check_core::ErasedDeclarationReference[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_check_types::Obligation&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

var candidate=copy(value);return relocate(candidate,targets,changed);

}

fn rewriteOwned<O>(owner:O&,value:blot_check_types::Obligation&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

return relocate(value,targets,changed);

}

fn scan(value:const blot_check_types::Obligation[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_check_types::Obligation[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_check_core::Types&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.quantifier_obligations,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_check_core::Types&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.quantifier_obligations,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_check_core::Binding&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.target,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_check_core::Binding&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.target,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_check_core::Binding[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_check_core::Binding[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_check_core::CallInfo&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.target,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_check_core::CallInfo&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.target,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_check_core::CallInfo[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_check_core::CallInfo[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_check_core::Obligation&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

var candidate=copy(value);return relocate(candidate,targets,changed);

}

fn rewriteOwned<O>(owner:O&,value:blot_check_core::Obligation&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

return relocate(value,targets,changed);

}

fn scan(value:const blot_check_core::Obligation[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_check_core::Obligation[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_check_core::Associated&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.target,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_check_core::Associated&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.target,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_check_core::Associated[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_check_core::Associated[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_reuse_principal_interface::Implementation&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

var candidate=copy(value);return relocate(candidate,targets,changed);

}

fn rewriteOwned<O>(owner:O&,value:blot_reuse_principal_interface::Implementation&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

return relocate(value,targets,changed);

}

fn scan(value:const blot_reuse_principal_interface::Implementation[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_reuse_principal_interface::Implementation[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_reuse_principal_interface::ExternalTarget&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

var candidate=copy(value);return relocate(candidate,targets,changed);

}

fn rewriteOwned<O>(owner:O&,value:blot_reuse_principal_interface::ExternalTarget&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

return relocate(value,targets,changed);

}

fn scan(value:const blot_reuse_principal_interface::ImplementationMember&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.target,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_reuse_principal_interface::ImplementationMember&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.target,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_reuse_principal_interface::ImplementationMember[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_reuse_principal_interface::ImplementationMember[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_reuse_principal_interface::SelectedProof&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.predicate_target,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.predicate,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_reuse_principal_interface::SelectedProof&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.predicate_target,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.predicate,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_reuse_principal_interface::SelectedProof[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_reuse_principal_interface::SelectedProof[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_check_core::ResolverInfo&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.method,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_check_core::ResolverInfo&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.method,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_check_core::ResolverInfo[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_check_core::ResolverInfo[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_check_core::Module&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.dependency_references,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.erased_declaration_references,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.types,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.bindings,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.references,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.calls,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.obligations,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.associated,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.implementations,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.implementation_members,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.selected_proofs,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.selected_members,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.resolver_ops,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_check_core::Module&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.dependency_references,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.erased_declaration_references,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.types,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.bindings,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.references,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.calls,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.obligations,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.associated,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.implementations,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.implementation_members,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.selected_proofs,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.selected_members,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.resolver_ops,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_check_frozen_types::Graph&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.quantifier_obligations,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_check_frozen_types::Graph&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.quantifier_obligations,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_support::Option<blot_reuse_principal_interface::ExternalTarget>&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

if value.present {return scan(value.value,targets,remaining,changed);}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_support::Option<blot_reuse_principal_interface::ExternalTarget>&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

if value.present {return rewriteOwned(owner,value.value,targets,remaining,changed);}return Error.none;

}

fn scan(value:const blot_reuse_principal_interface::Binding&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.external,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_reuse_principal_interface::Binding&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.external,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_reuse_principal_interface::Binding[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_reuse_principal_interface::Binding[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_reuse_principal_interface::Interface&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.graph,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.bindings,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.obligations,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.contract_predicates,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.implementations,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.implementation_predicates,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.implementation_members,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.selected_proofs,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.selected_members,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_reuse_principal_interface::Interface&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.graph,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.bindings,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.obligations,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.contract_predicates,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.implementations,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.implementation_predicates,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.implementation_members,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.selected_proofs,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.selected_members,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_reuse_frozen_dependency::Export&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

var candidate=copy(value);return relocate(candidate,targets,changed);

}

fn rewriteOwned<O>(owner:O&,value:blot_reuse_frozen_dependency::Export&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

return relocate(value,targets,changed);

}

fn scan(value:const blot_reuse_frozen_dependency::Export[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_reuse_frozen_dependency::Export[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_reuse_frozen_dependency::Fixity&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.producer,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_reuse_frozen_dependency::Fixity&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.producer,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_reuse_frozen_dependency::Fixity[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_reuse_frozen_dependency::Fixity[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_reuse_frozen_dependency::Module&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.core,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.interface,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.exports,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=scan(value.fixities,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_reuse_frozen_dependency::Module&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.core,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.interface,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.exports,targets,remaining,changed);if error!=Error.none {return error;}}

{let error=rewriteOwned(owner,value.fixities,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn scan(value:const blot_reuse_frozen_dependency::Module[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

for &item in value {let error=scan(item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:const blot_reuse_frozen_dependency::Module[:]&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

let items=owner.mutable(value);for &item in items {let error=rewriteOwned(owner,item,targets,remaining,changed);if error!=Error.none {return error;}}return Error.none;

}

fn scan(value:const blot_reuse_frozen_dependency::FrozenDependency&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=scan(value.modules,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}

fn rewriteOwned<O>(owner:O&,value:blot_reuse_frozen_dependency::FrozenDependency&,targets:Targets,remaining:i64&,changed:bool&)->Error {
let charged=visit(remaining);if charged!=Error.none {return charged;}

{let error=rewriteOwned(owner,value.modules,targets,remaining,changed);if error!=Error.none {return error;}}

return Error.none;

}
