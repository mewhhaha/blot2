// A complete public relationship precedes every unpublished reference rewrite.
namespace blot_reuse_frontend_binding_relocation;
import std;
import dictionary;
import parse.ast;
import reuse.principal_interface;
import reuse.frozen_dependency;
import reuse.frontend_graph_correspondence;
import reuse.frontend_method_sources;
import check.types;
import check.parameter_patterns;
import check.capability_contracts;
import backend.opaque_storage;
import support.error;
import support.option;
import support.structural;
import support.pooled_buffer;
type Error=blot_error::Error;
type Interface=blot_reuse_principal_interface::Interface;
type Kind=blot_reuse_principal_interface::Kind;
type ExportKind=blot_reuse_frozen_dependency::ExportKind;
type Target=blot_reuse_principal_interface::ExternalTarget;
type List=blot_check_types::List;
type Span=blot_parse_ast::Span;
let unmapped:u32=0xffffffff;
struct Qualification {before:Span,after:Span}
fn qualificationLess(left:Qualification,right:Qualification)->bool {return left.before.start<right.before.start||(left.before.start==right.before.start&&left.before.end<right.before.end);}
reusable[] var owned_words:u32[>..]=[];
reusable[] var owned_qualifications:Qualification[>..]=[];
fn words(length:i64,initial:u32)->u32[:] {let result=owned_words.alloc_slice(length);for &word in result {word=initial;}return result;}
fn release(values:u32[:]) {if values.len!=0 {owned_words.free_slice(values);}}
struct Map {bindings:u32[:]=default<u32[:]>(),nominals:u32[:]=default<u32[:]>(),constructors:u32[:]=default<u32[:]>(),contracts:u32[:]=default<u32[:]>(),implementations:u32[:]=default<u32[:]>(),qualifications:Qualification[:]=default<Qualification[:]>()}
fn deinit(self_:Map&) {release(self_.bindings);release(self_.nominals);release(self_.constructors);release(self_.contracts);release(self_.implementations);if self_.qualifications.len!=0 {owned_qualifications.free_slice(self_.qualifications);}self_=Map {..};}
fn binding(self_:Map,old:u32)->blot_support::Option<u32> {if old==0||old>=self_.bindings.len||self_.bindings[old]==0 {return blot_support::none<u32>();}return blot_support::some(self_.bindings[old]);}
fn qualification(self_:Map,old:Span)->Span {
 var low:i64=0;var high=self_.qualifications.len;while low<high {let middle=low+(high-low)/2;let value=self_.qualifications[middle];if value.before==old {return value.after;}if qualificationLess(value,Qualification {old,old, ..}) {low=middle+1;}else {high=middle;}}return old;
}
fn moved(values:const u32[:],missing:u32)->bool {for current,old in values {if current!=missing&&current!=old {return true;}}return false;}
fn changes(self_:Map)->bool {for value in self_.qualifications {if value.before!=value.after {return true;}}return moved(self_.bindings,0)||moved(self_.nominals,0)||moved(self_.constructors,0)||moved(self_.contracts,unmapped)||moved(self_.implementations,unmapped);}
fn catalog(self_:Map,kind:ExportKind,old:u32)->blot_support::Option<u32> {
 if kind==blot_reuse_frozen_dependency::ExportKind.contract {if old<self_.contracts.len&&self_.contracts[old]!=unmapped {return blot_support::some(self_.contracts[old]);}return blot_support::none<u32>();}
 if kind==blot_reuse_frozen_dependency::ExportKind.implementation {if old<self_.implementations.len&&self_.implementations[old]!=unmapped {return blot_support::some(self_.implementations[old]);}return blot_support::none<u32>();}
 var entries:const u32[:]=default<const u32[:]>();if kind==blot_reuse_frozen_dependency::ExportKind.nominal {entries=self_.nominals;}else if kind==blot_reuse_frozen_dependency::ExportKind.constructor {entries=self_.constructors;}else {return blot_support::some(old);}
 if old==0||old>=entries.len||entries[old]==0 {return blot_support::none<u32>();}return blot_support::some(entries[old]);
}
enum Stage {eligibility,public_index,public_match,nominals,constructors,contracts,implementations,graph,checked}
struct Progress {graph:blot_reuse_frontend_graph_correspondence::Diagnostic=blot_reuse_frontend_graph_correspondence::Diagnostic {..},stage:Stage=Stage.eligibility,binding:u32=0,other:u32=0,unnamed:bool=false,kind:Kind=blot_reuse_principal_interface::Kind.global}
struct Targets {progress:Progress?=null,units:const blot_support::Option<Map>[:]=default<const blot_support::Option<Map>[:]>(),methods:blot_support::Option<blot_reuse_frontend_method_sources::Sources>,comparisons_left:i64?=null}
fn changes(self_:Targets)->bool {for map in self_.units {if map.present&&map.value.changes() {return true;}}return false;}
fn target(self_:Targets,old:Target)->blot_support::Option<Target> {
 if old.binding==0||old.unit==0||old.unit>self_.units.len {return blot_support::some(old);}let map=self_.units[old.unit-1];if !map.present {return blot_support::some(old);}let binding=map.value.binding(old.binding);if !binding.present {return blot_support::none<Target>();}return blot_support::some(Target {old.unit,binding.value, ..});
}
fn qualification(self_:Targets,unit:u32,span:Span)->Span {if unit==0||unit>self_.units.len {return span;}let map=self_.units[unit-1];if !map.present {return span;}return map.value.qualification(span);}
fn exported(self_:Targets,old:blot_reuse_frozen_dependency::Export)->blot_support::Option<blot_reuse_frozen_dependency::Export> {
 var result=old;let target=self_.target(old.target);if !target.present {return blot_support::none<blot_reuse_frozen_dependency::Export>();}result.target=target.value;if old.target.unit==0 {return blot_support::none<blot_reuse_frozen_dependency::Export>();}if old.target.unit>self_.units.len {return blot_support::some(result);}let map=self_.units[old.target.unit-1];if !map.present {return blot_support::some(result);}let catalog=map.value.catalog(old.kind,old.catalog);if !catalog.present {return blot_support::none<blot_reuse_frozen_dependency::Export>();}result.catalog=catalog.value;return blot_support::some(result);
}
fn visible(value:blot_reuse_principal_interface::Binding)->bool {return !value.private&&(value.kind==blot_reuse_principal_interface::Kind.global||value.kind==blot_reuse_principal_interface::Kind.external);}
struct BindingKey {name:u32=0,kind:Kind=blot_reuse_principal_interface::Kind.global,target:Target=Target {0,0, ..}}
fn hash(key:BindingKey)->u64 {var value=(key.name as u64)<<32|key.target.binding as u64;value^=(key.target.unit as u64)*0x9e3779b185ebca87;value^=(kindCode(key.kind) as u64)*0xc2b2ae3d27d4eb4f;return value;}
fn current(value:blot_reuse_principal_interface::Binding)->blot_support::Option<BindingKey> {
 if value.name!=0 {var target=Target {0,0, ..};if value.kind==blot_reuse_principal_interface::Kind.external&&value.external.present {target=value.external.value;}return blot_support::some(BindingKey {value.name,value.kind,target, ..});}
 if value.kind!=blot_reuse_principal_interface::Kind.external||!value.external.present {return blot_support::none<BindingKey>();}return blot_support::some(BindingKey {0,value.kind,value.external.value, ..});
}
struct CatalogKey {name:u32,identity:blot_check_types::NominalIdentity}
fn hash(key:CatalogKey)->u64 {return (key.name as u64)<<32^(key.identity.unit as u64)*0x9e3779b185ebca87^key.identity.decl as u64;}
struct ConstructorKey {parent:u32,tag:u32}
fn hash(key:ConstructorKey)->u64 {return (key.parent as u64)<<32|key.tag as u64;}
fn namedCatalogIndex<E>(entries:const E[:],sentinel:bool,remaining:i64&,result:dictionary<CatalogKey,u32>&)->Error {
 for entry,index in entries {if (sentinel&&index==0)||entry.private {continue;}if remaining==0 {return blot_error::Error.declined;}remaining--;let key=CatalogKey {entry.name,entry.identity, ..};if result.contains(key) {return blot_error::Error.declined;}result.insert(key,index as u32);}return blot_error::Error.none;
}
fn privateContractsOnly(owner:const Interface&)->bool {
 for contract in owner.contracts {if !contract.private {return false;}}for member in owner.contract_members {if member.name!=0||member.root!=0 {return false;}}
 let inert=blot_check_types::Obligation {ty:0,kind:blot_check_types::ObligationKind.type_rep,source:0,explicit:true, ..};for predicate in owner.contract_predicates {if !blot_structural::equal(predicate,inert) {return false;}}return true;
}
fn privateEffectsOnly(owner:const Interface&)->bool {
 for family,index in owner.effect_families {if index==0&&family.identity.unit==0&&family.identity.decl==0 {continue;}if !family.private {return false;}}
 for operation,index in owner.effect_templates {if index==0&&operation.identity.unit==0&&operation.identity.decl==0 {continue;}if operation.family>=owner.effect_families.len||!owner.effect_families[operation.family].private {return false;}}return true;
}
fn eligible(left:const Interface&,right:const Interface&)->bool {
 if left.unit!=right.unit||left.bindings.len>65536||right.bindings.len>65536||left.has_rank_contracts||right.has_rank_contracts||left.has_usage_contracts||right.has_usage_contracts||left.has_numeric_proofs||right.has_numeric_proofs {return false;}
 if left.proof_contracts.len!=0||right.proof_contracts.len!=0||left.selected_proofs.len!=0||right.selected_proofs.len!=0||left.selected_members.len!=0||right.selected_members.len!=0||left.selected_edges.len!=0||right.selected_edges.len!=0 {return false;}
 if left.implementations.len!=0||right.implementations.len!=0 {
  if left.contracts.len>64||right.contracts.len>64||left.implementations.len>64||right.implementations.len>64 {return false;}
  for value in left.implementations {if !value.private&&(value.row_variables.len!=0||value.row_parameters.len!=0) {return false;}}
  for value in right.implementations {if !value.private&&(value.row_variables.len!=0||value.row_parameters.len!=0) {return false;}}
 }
 if !privateEffectsOnly(left)||!privateEffectsOnly(right) {if left.effect_families.len!=right.effect_families.len||left.effect_templates.len!=right.effect_templates.len {return false;}}return true;
}
fn compare(left:const Interface&,right:const Interface&,targets:Targets)->blot_support::Option<Map>,Error {
 let progress=targets.progress;if progress {progress=Progress {..};}let reported=targets.comparisons_left;if reported {reported=65536;}
 if !eligible(left,right) {return blot_support::none<Map>(),blot_error::Error.none;}var map=Map {bindings:words(left.bindings.len,0), ..};var comparisons:i64=65536;
 let error=buildMap(left,right,targets,map,comparisons);if reported {reported=comparisons;}
 if error!=blot_error::Error.none {map.deinit();if error==blot_error::Error.out_of_memory {return blot_support::none<Map>(),error;}return blot_support::none<Map>(),blot_error::Error.none;}
 return blot_support::some(map),blot_error::Error.none;
}
fn stage(targets:Targets,value:Stage) {let progress=targets.progress;if progress {progress.stage=value;}}
fn budget(remaining:i64&)->Error {if remaining==0 {return blot_error::Error.declined;}remaining--;return blot_error::Error.none;}
fn buildMap(left:const Interface&,right:const Interface&,targets:Targets,map:Map&,comparisons:i64&)->Error {
 var used:bool[>..<]=[];used.resize(right.bindings.len,false);var public:dictionary<BindingKey,u32> =dictionary<BindingKey,u32> {};stage(targets,Stage.public_index);
 for value,index in right.bindings {
  if index==0||!visible(value) {continue;}{ let propagated_error = budget(comparisons); if propagated_error != blot_error::Error.none { return propagated_error; } }let key=current(value);if !key.present {return blot_error::Error.declined;}
  let entry=public.get(key.value);
  if entry {
   let progress=targets.progress;if progress {progress.binding=index as u32;progress.other=entry;progress.unnamed=key.value.name==0;progress.kind=key.value.kind;}
   if key.value.name!=0||left.bindings.len!=right.bindings.len {return blot_error::Error.declined;}let expected=current(left.bindings[index]);if !expected.present||key.value!=expected.value {return blot_error::Error.declined;}
   let prior=copy(entry);if prior!=unmapped {let expected=current(left.bindings[prior]);if !expected.present||key.value!=expected.value {return blot_error::Error.declined;}}entry=unmapped;continue;
  }
  public.insert(key.value,index as u32);
 }
 stage(targets,Stage.public_match);
 for old,index in left.bindings {
  if index==0||!visible(old) {continue;}{ let propagated_error = budget(comparisons); if propagated_error != blot_error::Error.none { return propagated_error; } }let progress=targets.progress;if progress {progress.binding=index as u32;}
  let identified=current(old);if !identified.present {return blot_error::Error.declined;}var key=identified.value;if old.kind==blot_reuse_principal_interface::Kind.external&&old.external.present {let mapped=targets.target(key.target);if !mapped.present {return blot_error::Error.declined;}key.target=mapped.value;}
  let found=public.get(key);if !found {return blot_error::Error.declined;}var next:u32=copy(found);
  if next==unmapped {if index>=right.bindings.len {return blot_error::Error.declined;}let identified=current(right.bindings[index]);if !identified.present||key!=identified.value {return blot_error::Error.declined;}next=index as u32;}
  if used[next] {return blot_error::Error.declined;}used[next]=true;map.bindings[index]=next;
 }
 for value,index in right.bindings {if index!=0&&visible(value)&&!used[index] {return blot_error::Error.declined;}}
 stage(targets,Stage.nominals);map.nominals=words(left.nominals.len,0);var nominal_used:bool[>..<]=[];nominal_used.resize(right.nominals.len,false);var nominals_index:dictionary<CatalogKey,u32> =dictionary<CatalogKey,u32> {};
 { let propagated_error = namedCatalogIndex(right.nominals,true,comparisons,nominals_index); if propagated_error != blot_error::Error.none { return propagated_error; } }
 for old,index in left.nominals {if index==0||old.private {continue;}{ let propagated_error = budget(comparisons); if propagated_error != blot_error::Error.none { return propagated_error; } }let next=nominals_index.get(CatalogKey {old.name,old.identity, ..});if !next||nominal_used[next] {return blot_error::Error.declined;}nominal_used[next]=true;map.nominals[index]=next;}
 for value,index in right.nominals {if index!=0&&!value.private&&!nominal_used[index] {return blot_error::Error.declined;}}
 stage(targets,Stage.constructors);map.constructors=words(left.constructors.len,0);var constructor_used:bool[>..<]=[];constructor_used.resize(right.constructors.len,false);var constructor_index:dictionary<ConstructorKey,u32> =dictionary<ConstructorKey,u32> {};
 for value,index in right.constructors {if index==0||value.nominal==0||right.nominals[value.nominal].private {continue;}{ let propagated_error = budget(comparisons); if propagated_error != blot_error::Error.none { return propagated_error; } }let key=ConstructorKey {value.nominal,value.tag, ..};if constructor_index.contains(key) {return blot_error::Error.declined;}constructor_index.insert(key,index as u32);}
 for old,index in left.constructors {
  if index==0||old.nominal==0||old.nominal>=map.nominals.len||left.nominals[old.nominal].private {continue;}let parent=map.nominals[old.nominal];if parent==0 {return blot_error::Error.declined;}{ let propagated_error = budget(comparisons); if propagated_error != blot_error::Error.none { return propagated_error; } }let next=constructor_index.get(ConstructorKey {parent,old.tag, ..});if !next||constructor_used[next] {return blot_error::Error.declined;}constructor_used[next]=true;map.constructors[index]=next;
 }
 for value,index in right.constructors {if index!=0&&value.nominal!=0&&!right.nominals[value.nominal].private&&!constructor_used[index] {return blot_error::Error.declined;}}
 if !privateContractsOnly(left)||!privateContractsOnly(right) {
  stage(targets,Stage.contracts);map.contracts=words(left.contracts.len,unmapped);var contract_used:bool[>..<]=[];contract_used.resize(right.contracts.len,false);var contracts_index:dictionary<CatalogKey,u32> =dictionary<CatalogKey,u32> {};
  { let propagated_error = namedCatalogIndex(right.contracts,false,comparisons,contracts_index); if propagated_error != blot_error::Error.none { return propagated_error; } }
  for old,index in left.contracts {if old.private {continue;}{ let propagated_error = budget(comparisons); if propagated_error != blot_error::Error.none { return propagated_error; } }let next=contracts_index.get(CatalogKey {old.name,old.identity, ..});if !next||contract_used[next] {return blot_error::Error.declined;}contract_used[next]=true;map.contracts[index]=next;}
  for value,index in right.contracts {if !value.private&&!contract_used[index] {return blot_error::Error.declined;}}
 }
 stage(targets,Stage.implementations);map.implementations=words(left.implementations.len,unmapped);var implementation_used:bool[>..<]=[];implementation_used.resize(right.implementations.len,false);var implementations_index:dictionary<CatalogKey,u32> =dictionary<CatalogKey,u32> {};
 { let propagated_error = namedCatalogIndex(right.implementations,false,comparisons,implementations_index); if propagated_error != blot_error::Error.none { return propagated_error; } }
 for old,index in left.implementations {
  if old.private {continue;}{ let propagated_error = budget(comparisons); if propagated_error != blot_error::Error.none { return propagated_error; } }let next=implementations_index.get(CatalogKey {old.name,old.identity, ..});if !next||implementation_used[next] {return blot_error::Error.declined;}implementation_used[next]=true;map.implementations[index]=next;let current=right.implementations[next];if old.members.len!=current.members.len {return blot_error::Error.declined;}
  for from,ordinal in left.implementation_members[old.members.start..old.members.start+old.members.len] {
   let to=right.implementation_members[current.members.start+ordinal];{ let propagated_error = budget(comparisons); if propagated_error != blot_error::Error.none { return propagated_error; } }if from.name!=to.name||from.kind!=to.kind {return blot_error::Error.declined;}if from.kind!=blot_reuse_principal_interface::ImplementationMemberKind.value {continue;}
   if from.target.unit==0||from.target.binding==0||to.target.unit!=from.target.unit||to.target.binding==0 {return blot_error::Error.declined;}
   if from.target.unit!=left.unit {let translated=targets.target(from.target);if !translated.present||translated.value!=to.target {return blot_error::Error.declined;}continue;}
   if from.target.binding>=map.bindings.len||to.target.binding>=right.bindings.len {return blot_error::Error.declined;}let before=left.bindings[from.target.binding];let after=right.bindings[to.target.binding];
   if before.private!=after.private||before.kind!=blot_reuse_principal_interface::Kind.global||after.kind!=blot_reuse_principal_interface::Kind.global {return blot_error::Error.declined;}
   if before.private {
    if !targets.methods.present {return blot_error::Error.declined;}let sources=targets.methods.value;let role=blot_reuse_frontend_method_sources::Role {old.identity,from.name, ..};let old_method=sources.before(role,from.target.binding);let new_method=sources.after(role,to.target.binding);
    if !old_method.present||!new_method.present {return blot_error::Error.declined;}let old_header=old_method.value;let new_header=new_method.value;
    if old_header.flow!=new_header.flow||old_header.parameters!=new_header.parameters||old_header.recipe.present!=new_header.recipe.present {return blot_error::Error.declined;}
    if old_header.recipe.present {let recipe=old_header.recipe.value;let after_recipe=new_header.recipe.value;if recipe.arity!=after_recipe.arity {return blot_error::Error.declined;}let same,error=blot_check_capability_contracts::equivalent(recipe.view(),recipe.root,after_recipe.view(),after_recipe.root);if error==blot_error::Error.out_of_memory {return error;}if error!=blot_error::Error.none||!same {return blot_error::Error.declined;}}
   }
   let prior=map.binding(from.target.binding);if prior.present {if prior.value!=to.target.binding {return blot_error::Error.declined;}}
   else {if !before.private||before.name!=0||after.name!=0||used[to.target.binding] {return blot_error::Error.declined;}map.bindings[from.target.binding]=to.target.binding;used[to.target.binding]=true;}
  }
 }
 for value,index in right.implementations {if !value.private&&!implementation_used[index] {return blot_error::Error.declined;}}
 return checkGraphs(left,right,targets,map);
}

fn kindCode(kind:Kind)->u32 {match kind {global=>0,local=>1,parameter=>2,external=>3}}

type QualificationBuffer=blot_support_pooled_buffer::Buffer<Qualification>;
reusable[] var qualification_runs:Qualification[>..]=[];
struct Checker {qualifications:QualificationBuffer=QualificationBuffer {..},left:const Interface&,right:const Interface&,graph:blot_reuse_frontend_graph_correspondence::Match&,map:Map,targets:Targets,remaining:i64=65536}
fn work(self_:Checker&,depth:i64)->Error {if depth>=128||self_.remaining==0 {return blot_error::Error.declined;}self_.remaining--;return blot_error::Error.none;}
fn checkGraphs(left:const Interface&,right:const Interface&,targets:Targets,map:Map&)->Error {
 stage(targets,Stage.graph);let prepared,error=blot_reuse_frontend_graph_correspondence::init(left.graph,right.graph);if error!=blot_error::Error.none {return error;}
 if !prepared.present {let progress=targets.progress;if progress {progress.graph.reason=blot_reuse_frontend_graph_correspondence::Reason.size_limit;}return blot_error::Error.declined;}
 var graph=prepared.value;var checker=Checker {left:left,right:right,graph:graph,map:copy(map),targets:targets, ..};
 if left.implementations.len!=0||right.implementations.len!=0 {checker.remaining=4096;graph.remaining=4096;}
 let error=checker.check();if error==blot_error::Error.declined&&graph.diagnostic.reason==blot_reuse_frontend_graph_correspondence::Reason.none {graph.diagnostic.reason=blot_reuse_frontend_graph_correspondence::Reason.catalog;}
 let progress=targets.progress;if progress {progress.graph=graph.diagnostic;progress.graph.remaining=graph.remaining;}graph.deinit();
 if error!=blot_error::Error.none {blot_support_pooled_buffer::deinit(checker.qualifications,qualification_runs);return error;}
 map.qualifications=owned_qualifications.alloc_slice(checker.qualifications.items.len);for value,index in checker.qualifications.items {map.qualifications[index]=value;}blot_support_pooled_buffer::deinit(checker.qualifications,qualification_runs);
 sort(map.qualifications) {left,right=>return qualificationLess(left,right);}
 stage(targets,Stage.checked);return blot_error::Error.none;
}
fn check(self_:Checker&)->Error {
 for old,index in self_.left.bindings {
  if !visible(old) {continue;}{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }let mapped=self_.map.binding(index as u32);if !mapped.present {return blot_error::Error.declined;}let current=self_.right.bindings[mapped.value];
  if old.private!=current.private||old.named_function!=current.named_function||old.capability_flow!=current.capability_flow||old.capability_parameters!=current.capability_parameters {return blot_error::Error.declined;}
  if old.external.present {let mapped=self_.targets.target(old.external.value);if !mapped.present||!current.external.present||mapped.value!=current.external.value {return blot_error::Error.declined;}}else if current.external.present {return blot_error::Error.declined;}
  { let propagated_error = self_.graph.ty(old.ty,current.ty); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.scheme(old.scheme,current.scheme); if propagated_error != blot_error::Error.none { return propagated_error; } }
 }
 let old_capabilities=self_.left.capability_contracts;let new_capabilities=self_.right.capability_contracts;
 if old_capabilities.nodes.len!=new_capabilities.nodes.len||old_capabilities.words!=new_capabilities.words||old_capabilities.bindings.len!=new_capabilities.bindings.len {return blot_error::Error.declined;}
 for old,index in old_capabilities.nodes {if old!=new_capabilities.nodes[index] {return blot_error::Error.declined;}}
 for old,index in old_capabilities.bindings {{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }let mapped=self_.map.binding(old.binding);let current=new_capabilities.bindings[index];if !mapped.present||mapped.value!=current.binding||old.root!=current.root {return blot_error::Error.declined;}}
 for old,index in self_.left.nominals {
  if index==0||old.private {continue;}let mapped=self_.map.catalog(blot_reuse_frozen_dependency::ExportKind.nominal,index as u32);if !mapped.present {return blot_error::Error.declined;}let current=self_.right.nominals[mapped.value];{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }
  if old.affine!=current.affine||old.has_usage!=current.has_usage||old.closed_storage!=current.closed_storage||old.private!=current.private||old.is_opaque!=current.is_opaque||old.declaration!=current.declaration||old.identity!=current.identity||old.name!=current.name {return blot_error::Error.declined;}
  if (!old.is_opaque||old.storage.kind==blot_backend_opaque_storage::Kind.unknown||current.storage.kind==blot_backend_opaque_storage::Kind.unknown)&&old.storage!=current.storage {return blot_error::Error.declined;}
  { let propagated_error = self_.graph.typeList(old.parameters,current.parameters); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.typeList(old.variables,current.variables); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.ty(old.alias,current.alias); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.rowVariables(old.alias_rows,current.alias_rows); if propagated_error != blot_error::Error.none { return propagated_error; } }
  if old.parameter_names.len!=current.parameter_names.len {return blot_error::Error.declined;}{ let propagated_error = self_.patternList(old.patterns,current.patterns,0); if propagated_error != blot_error::Error.none { return propagated_error; } }if old.constructors.len!=current.constructors.len {return blot_error::Error.declined;}
  for before,ordinal in self_.left.graph.extra[old.constructors.start..old.constructors.start+old.constructors.len] {{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }let mapped=self_.map.catalog(blot_reuse_frozen_dependency::ExportKind.constructor,before);if !mapped.present||mapped.value!=self_.right.graph.extra[current.constructors.start+ordinal] {return blot_error::Error.declined;}}
 }
 for old,index in self_.left.constructors {
  if index==0||old.nominal==0||self_.left.nominals[old.nominal].private {continue;}let mapped=self_.map.catalog(blot_reuse_frozen_dependency::ExportKind.constructor,index as u32);if !mapped.present {return blot_error::Error.declined;}let current=self_.right.constructors[mapped.value];{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }let parent=self_.map.catalog(blot_reuse_frozen_dependency::ExportKind.nominal,old.nominal);
  if old.private!=current.private||!parent.present||parent.value!=current.nominal||old.tag!=current.tag||old.name!=current.name||old.declared_record!=current.declared_record||old.identity.unit!=current.identity.unit {return blot_error::Error.declined;}
  if old.identity.decl!=current.identity.decl {if !old.private||old.nominal>=self_.left.nominals.len {return blot_error::Error.declined;}let parent=self_.left.nominals[old.nominal];if !parent.is_opaque||parent.storage.kind==blot_backend_opaque_storage::Kind.unknown||self_.right.nominals[current.nominal].storage.kind==blot_backend_opaque_storage::Kind.unknown||old.identity.unit!=parent.identity.unit {return blot_error::Error.declined;}}
  { let propagated_error = self_.graph.ty(old.payload,current.payload); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.scheme(old.scheme,current.scheme); if propagated_error != blot_error::Error.none { return propagated_error; } }
 }
 { let propagated_error = self_.effects(); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.contracts(); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.associated(); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.implementations(); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.memberTemplates(); if propagated_error != blot_error::Error.none { return propagated_error; } }return blot_error::Error.none;
}
fn implementationClaims(self_:Checker&,owner:const Interface&,index:i64,members:bool)->Error {
 var claims:i64=0;for header in owner.implementations {{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }var span=header.predicates;if members {span=header.members;}if !header.private&&index>=span.start&&index-span.start<span.len {claims++;}}if claims!=1 {return blot_error::Error.declined;}return blot_error::Error.none;
}
fn implementations(self_:Checker&)->Error {
 // Preserve source table order: members before predicates, left before right.
 for value,index in self_.left.implementation_members {if value.name==0&&value.root==0&&value.target.unit==0&&value.target.binding==0 {continue;}{ let propagated_error = self_.implementationClaims(self_.left,index,true); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 for value,index in self_.right.implementation_members {if value.name==0&&value.root==0&&value.target.unit==0&&value.target.binding==0 {continue;}{ let propagated_error = self_.implementationClaims(self_.right,index,true); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 let inert=blot_check_types::Obligation {ty:0,kind:blot_check_types::ObligationKind.type_rep,source:0,explicit:true, ..};
 for value,index in self_.left.implementation_predicates {if blot_structural::equal(value,inert) {continue;}{ let propagated_error = self_.implementationClaims(self_.left,index,false); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 for value,index in self_.right.implementation_predicates {if blot_structural::equal(value,inert) {continue;}{ let propagated_error = self_.implementationClaims(self_.right,index,false); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 for old,index in self_.left.implementations {
  if old.private {continue;}{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }let mapped=self_.map.catalog(blot_reuse_frozen_dependency::ExportKind.implementation,index as u32);if !mapped.present {return blot_error::Error.declined;}let current=self_.right.implementations[mapped.value];
  if old.private!=current.private||old.name!=current.name||old.declaration!=current.declaration||old.identity!=current.identity||old.contract!=current.contract||old.parameter_names.len!=current.parameter_names.len||old.row_parameter_names.len!=current.row_parameter_names.len {return blot_error::Error.declined;}
  { let propagated_error = self_.graph.typeList(old.head,current.head); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.typeList(old.variables,current.variables); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.rowVariables(old.row_variables,current.row_variables); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.rowList(old.row_parameters,current.row_parameters); if propagated_error != blot_error::Error.none { return propagated_error; } }
  if old.predicates.len!=current.predicates.len||old.members.len!=current.members.len {return blot_error::Error.declined;}
  for from,ordinal in self_.left.implementation_predicates[old.predicates.start..old.predicates.start+old.predicates.len] {{ let propagated_error = self_.obligation(from,self_.right.implementation_predicates[current.predicates.start+ordinal]); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  for from,ordinal in self_.left.implementation_members[old.members.start..old.members.start+old.members.len] {
   let to=self_.right.implementation_members[current.members.start+ordinal];{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }if from.name!=to.name||from.kind!=to.kind {return blot_error::Error.declined;}{ let propagated_error = self_.graph.ty(from.root,to.root); if propagated_error != blot_error::Error.none { return propagated_error; } }
   if from.kind==blot_reuse_principal_interface::ImplementationMemberKind.type_ {if from.target!=to.target {return blot_error::Error.declined;}}
   else if from.target.unit==self_.left.unit {let mapped=self_.map.binding(from.target.binding);if to.target.unit!=self_.right.unit||!mapped.present||mapped.value!=to.target.binding {return blot_error::Error.declined;}}
   else {let mapped=self_.targets.target(from.target);if !mapped.present||mapped.value!=to.target {return blot_error::Error.declined;}}
  }
  if old.origin_span.present!=current.origin_span.present {return blot_error::Error.declined;}if old.origin_span.present {{ let propagated_error = self_.provenance(old.identity.unit,old.origin_span.value,current.origin_span.value); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 }
 return blot_error::Error.none;
}
fn memberTemplates(self_:Checker&)->Error {
 if self_.left.member_templates.len!=self_.right.member_templates.len {return blot_error::Error.declined;}var used:bool[>..<]=[];used.resize(self_.right.member_templates.len,false);
 for old in self_.left.member_templates {
  let binding=self_.map.binding(old.binding);if !binding.present {return blot_error::Error.declined;}var matched:i64=-1;
  for current,index in self_.right.member_templates {{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }if current.binding!=binding.value||old.name!=current.name||old.contract!=current.contract {continue;}if matched>=0||used[index] {return blot_error::Error.declined;}matched=index;}
  if matched<0 {return blot_error::Error.declined;}used[matched]=true;{ let propagated_error = self_.graph.typeList(old.arguments,self_.right.member_templates[matched].arguments); if propagated_error != blot_error::Error.none { return propagated_error; } }
 }
 for matched in used {if !matched {return blot_error::Error.declined;}}return blot_error::Error.none;
}
fn associated(self_:Checker&)->Error {
 if self_.left.associated.len!=self_.right.associated.len {return blot_error::Error.declined;}if self_.left.associated.len==0 {return blot_error::Error.none;}var used:bool[>..<]=[];used.resize(self_.right.associated.len,false);
 for old in self_.left.associated {
  let binding=self_.map.binding(old.binding);if !binding.present {return blot_error::Error.declined;}var matched:i64=-1;
  for current,index in self_.right.associated {{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }if binding.value!=current.binding||old.member!=current.member||old.operator!=current.operator||old.identity!=current.identity {continue;}if matched>=0||used[index] {return blot_error::Error.declined;}matched=index;}
  if matched<0 {return blot_error::Error.declined;}used[matched]=true;
 }
 for matched in used {if !matched {return blot_error::Error.declined;}}return blot_error::Error.none;
}
fn contracts(self_:Checker&)->Error {
 if privateContractsOnly(self_.left)&&privateContractsOnly(self_.right) {return blot_error::Error.none;}{ let propagated_error = self_.privateContractSlots(self_.left); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.privateContractSlots(self_.right); if propagated_error != blot_error::Error.none { return propagated_error; } }
 for old,index in self_.left.contracts {
  if old.private {continue;}{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }let mapped=self_.map.catalog(blot_reuse_frozen_dependency::ExportKind.contract,index as u32);if !mapped.present {return blot_error::Error.declined;}let current=self_.right.contracts[mapped.value];
  if old.private!=current.private||old.name!=current.name||old.declaration!=current.declaration||old.identity!=current.identity||old.requires_implementation!=current.requires_implementation||old.parameter_names.len!=current.parameter_names.len||old.row_parameter_names.len!=current.row_parameter_names.len {return blot_error::Error.declined;}
  { let propagated_error = self_.graph.typeList(old.parameters,current.parameters); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.typeList(old.variables,current.variables); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.patternList(old.patterns,current.patterns,0); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.rowVariables(old.row_variables,current.row_variables); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.rowList(old.row_parameters,current.row_parameters); if propagated_error != blot_error::Error.none { return propagated_error; } }
  if old.predicates.len!=current.predicates.len||old.members.len!=current.members.len {return blot_error::Error.declined;}
  for from,ordinal in self_.left.contract_predicates[old.predicates.start..old.predicates.start+old.predicates.len] {{ let propagated_error = self_.obligation(from,self_.right.contract_predicates[current.predicates.start+ordinal]); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  for from,ordinal in self_.left.contract_members[old.members.start..old.members.start+old.members.len] {let to=self_.right.contract_members[current.members.start+ordinal];{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }if from.name!=to.name||from.kind!=to.kind||from.contract!=to.contract {return blot_error::Error.declined;}{ let propagated_error = self_.graph.ty(from.root,to.root); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 }
 return blot_error::Error.none;
}
fn privateContractSlots(self_:Checker&,owner:const Interface&)->Error {
 for member,index in owner.contract_members {
  if member.name==0&&member.root==0 {continue;}var public=false;
  for header in owner.contracts {{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }if !header.private&&header.identity==member.contract&&index>=header.members.start&&index-header.members.start<header.members.len {public=true;}}
  if !public {return blot_error::Error.declined;}
 }
 let inert=blot_check_types::Obligation {ty:0,kind:blot_check_types::ObligationKind.type_rep,source:0,explicit:true, ..};
 for predicate,index in owner.contract_predicates {
  if blot_structural::equal(predicate,inert) {continue;}var public=false;
  for header in owner.contracts {{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }if !header.private&&index>=header.predicates.start&&index-header.predicates.start<header.predicates.len {public=true;}}
  if !public {return blot_error::Error.declined;}
 }
 return blot_error::Error.none;
}
fn effects(self_:Checker&)->Error {
 if privateEffectsOnly(self_.left)&&privateEffectsOnly(self_.right) {return blot_error::Error.none;}if self_.left.effect_families.len!=self_.right.effect_families.len||self_.left.effect_templates.len!=self_.right.effect_templates.len {return blot_error::Error.declined;}
 for old,index in self_.left.effect_families {
  let current=self_.right.effect_families[index];{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }if old.private!=current.private {return blot_error::Error.declined;}if old.private {continue;}
  if old.identity!=current.identity||old.name!=current.name||old.callable!=current.callable||old.parameter_names.len!=current.parameter_names.len {return blot_error::Error.declined;}
  { let propagated_error = self_.graph.typeList(old.parameters,current.parameters); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.typeList(old.variables,current.variables); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.patternList(old.patterns,current.patterns,0); if propagated_error != blot_error::Error.none { return propagated_error; } }
  if self_.left.graph.extra[old.operations.start..old.operations.start+old.operations.len]!=self_.right.graph.extra[current.operations.start..current.operations.start+current.operations.len] {return blot_error::Error.declined;}
 }
 for old,index in self_.left.effect_templates {
  let current=self_.right.effect_templates[index];{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }let before=self_.left.effect_families[old.family];let after=self_.right.effect_families[current.family];if before.private&&after.private {continue;}
  if old.family!=current.family||old.name!=current.name||old.identity!=current.identity {return blot_error::Error.declined;}{ let propagated_error = self_.graph.ty(old.parameter,current.parameter); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.ty(old.result,current.result); if propagated_error != blot_error::Error.none { return propagated_error; } }
 }
 return blot_error::Error.none;
}
fn scheme(self_:Checker&,old:blot_check_types::Scheme,current:blot_check_types::Scheme)->Error {
 { let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }if old.generative.len!=0||current.generative.len!=0 {return blot_error::Error.declined;}{ let propagated_error = self_.graph.ty(old.root,current.root); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.typeList(old.variables,current.variables); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.rowVariables(old.row_variables,current.row_variables); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.rowVariables(old.closed_rows,current.closed_rows); if propagated_error != blot_error::Error.none { return propagated_error; } }
 if old.obligations.len!=current.obligations.len {return blot_error::Error.declined;}for from,ordinal in self_.left.obligations[old.obligations.start..old.obligations.start+old.obligations.len] {{ let propagated_error = self_.obligation(from,self_.right.obligations[current.obligations.start+ordinal]); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;
}
fn obligation(self_:Checker&,from:blot_check_types::Obligation,to:blot_check_types::Obligation)->Error {
 { let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }if from.kind!=to.kind||from.name!=to.name||from.operator!=to.operator||from.explicit!=to.explicit||from.qualification_unit!=to.qualification_unit||from.source!=0||to.source!=0 {return blot_error::Error.declined;}
 if from.kind==blot_check_types::ObligationKind.callee_use {if from.identity.unit==0||from.identity.unit!=self_.left.unit||to.identity.unit!=self_.right.unit {return blot_error::Error.declined;}let mapped=self_.map.binding(from.identity.decl);if !mapped.present||mapped.value!=to.identity.decl {return blot_error::Error.declined;}}else if from.identity!=to.identity {return blot_error::Error.declined;}
 { let propagated_error = self_.graph.ty(from.ty,to.ty); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.ty(from.result,to.result); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.ty(from.other,to.other); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.graph.ty(from.signature,to.signature); if propagated_error != blot_error::Error.none { return propagated_error; } }
 if from.qualification_span.present!=to.qualification_span.present {return blot_error::Error.declined;}if !from.qualification_span.present {return blot_error::Error.none;}let before=from.qualification_span.value;let after=to.qualification_span.value;if before.start>before.end||after.start>after.end {return blot_error::Error.declined;}
 if from.explicit {{ let propagated_error = self_.provenance(from.qualification_unit,before,after); if propagated_error != blot_error::Error.none { return propagated_error; } }}else if self_.targets.qualification(from.qualification_unit,before)!=after {return blot_error::Error.declined;}return blot_error::Error.none;
}
fn provenance(self_:Checker&,unit:u32,before:Span,after:Span)->Error {
 if before.start>before.end||after.start>after.end {return blot_error::Error.declined;}if unit!=self_.left.unit {if self_.targets.qualification(unit,before)!=after {return blot_error::Error.declined;}return blot_error::Error.none;}
 for prior in self_.qualifications.items {{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }if prior.before==before {if prior.after!=after {return blot_error::Error.declined;}return blot_error::Error.none;}if prior.after==after {return blot_error::Error.declined;}}
 return blot_support_pooled_buffer::push(self_.qualifications,Qualification {before,after, ..},qualification_runs);
}
recursive fn patternList(self_:Checker&,old:List,current:List,depth:i64)->Error {
 { let propagated_error = self_.work(depth); if propagated_error != blot_error::Error.none { return propagated_error; } }if old.len!=current.len {return blot_error::Error.declined;}let before=self_.left.patterns.extra[old.start..old.start+old.len];let after=self_.right.patterns.extra[current.start..current.start+current.len];for from,index in before {{ let propagated_error = self_.pattern(from,after[index],depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;
}
recursive fn pattern(self_:Checker&,old:u32,current:u32,depth:i64)->Error {
 { let propagated_error = self_.work(depth); if propagated_error != blot_error::Error.none { return propagated_error; } }let from=self_.left.patterns.nodes[old];let to=self_.right.patterns.nodes[current];if from.kind!=to.kind||from.b!=to.b {return blot_error::Error.declined;}if from.kind==blot_check_parameter_patterns::Kind.binding {return self_.graph.ty(from.a,to.a);}
 if from.kind==blot_check_parameter_patterns::Kind.record {for field in 0..from.b {let before=self_.left.patterns.extra[from.a+field*2..from.a+field*2+2];let after=self_.right.patterns.extra[to.a+field*2..to.a+field*2+2];if before[0]!=after[0] {return blot_error::Error.declined;}{ let propagated_error = self_.pattern(before[1],after[1],depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}}
 else {{ let propagated_error = self_.patternList(List {from.a,from.b, ..},List {to.a,to.b, ..},depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;
}
