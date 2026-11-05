// Complete source-free dependency closures and live final-context receipts.
namespace blot_reuse_dependency_closure;
import std;
import dictionary;
import reuse.project;
import reuse.project_check;
import reuse.partial_dependency;
import reuse.principal_interface;
import reuse.frozen_dependency;
import reuse.retained_dependency;
import reuse.dependency_snapshot;
import reuse.dependency_format;
import reuse.dependency_relink;
import reuse.dependency_payload;
import reuse.dependency_interface_validation;
import reuse.dependency_core_inputs;
import reuse.module_abstraction_validation;
import check.core;
import check.core_builder;
import check.check;
import check.types;
import check.frozen_core_validation;
import check.parallel_lowering;
import check.associated_admission;
import eval.implementation_admission;
import backend.runtime_identity;
import support.option;
import support.error;
import support.native;
import support.blake3;
import support.path;
import parse.lexer;
import phase_profile;
type Error=blot_error::Error;
type Project=blot_reuse_project::Project;
type CheckedProject=blot_reuse_project_check::CheckedProject;
type Core=blot_check_core::Module;
type Interface=blot_reuse_principal_interface::Interface;
type Module=blot_reuse_frozen_dependency::Module;
type Frozen=blot_reuse_frozen_dependency::FrozenDependency;
type Snapshot=blot_reuse_retained_dependency::Snapshot;
type Stats=blot_reuse_retained_dependency::Stats;
type Owner=blot_reuse_dependency_payload::Owner;
type OwnedModule=blot_reuse_dependency_payload::Owned<Module>;
type OwnedFrozen=blot_reuse_dependency_payload::Owned<Frozen>;
type ModuleRef=blot_check_frozen_core_validation::ModuleRef;
fn require(value: bool) -> Error { if !value { return Error.invalid_artifact; } return Error.none; }
fn ordinal(source: const Project&,unit: u32) -> u32,Error { if unit==0||unit>source.units.len||unit==source.entry { return 0,Error.invalid_artifact; } if unit<source.entry { return unit,Error.none; } return unit-1,Error.none; }
fn mapped(units: const u32[:],id: u32) -> u32,Error { if id==0||id==0xffffffff { return id,Error.none; } if id>units.len||units[id-1]==0 { return 0,Error.invalid_artifact; } return units[id-1],Error.none; }
fn checkInterfaceUnits(owner: const Interface&,units: const u32[:]) -> Error {
 let ignored,first=mapped(units,owner.unit); if first!=Error.none { return first; }
 for node in owner.graph.nodes { if node.tag==blot_check_types::Tag.nominal||node.tag==blot_check_types::Tag.projection||node.tag==blot_check_types::Tag.type_constructor { let ignored,error=mapped(units,node.a); if error!=Error.none { return error; } } }
 for operation in owner.graph.operations { let ignored,error=mapped(units,operation.identity.unit); if error!=Error.none { return error; } }
 for binding in owner.bindings { if binding.external.present { let ignored,error=mapped(units,binding.external.value.unit); if error!=Error.none { return error; } } }
 for obligation in owner.obligations { let ignored,error=mapped(units,obligation.identity.unit); if error!=Error.none { return error; } let unused,e=mapped(units,obligation.qualification_unit); if e!=Error.none { return e; } }
 for nominal in owner.nominals { let ignored,error=mapped(units,nominal.identity.unit); if error!=Error.none { return error; } }
 for contract in owner.contracts { let ignored,error=mapped(units,contract.identity.unit); if error!=Error.none { return error; } }
 for member in owner.contract_members { let ignored,error=mapped(units,member.contract.unit); if error!=Error.none { return error; } }
 for predicate in owner.contract_predicates { let ignored,error=mapped(units,predicate.identity.unit); if error!=Error.none { return error; } let unused,e=mapped(units,predicate.qualification_unit); if e!=Error.none { return e; } }
 for implementation in owner.implementations { let ignored,error=mapped(units,implementation.identity.unit); if error!=Error.none { return error; } let unused,e=mapped(units,implementation.contract.unit); if e!=Error.none { return e; } }
 for predicate in owner.implementation_predicates { let ignored,error=mapped(units,predicate.identity.unit); if error!=Error.none { return error; } let unused,e=mapped(units,predicate.qualification_unit); if e!=Error.none { return e; } }
 for member in owner.implementation_members { let ignored,error=mapped(units,member.target.unit); if error!=Error.none { return error; } }
 for member in owner.member_templates { let ignored,error=mapped(units,member.contract.unit); if error!=Error.none { return error; } }
 for member in owner.selected_members { let ignored,error=mapped(units,member.target.unit); if error!=Error.none { return error; } }
 for proof in owner.selected_proofs { let ignored,error=mapped(units,proof.context); if error!=Error.none { return error; } let unused,e=mapped(units,proof.implementation.unit); if e!=Error.none { return e; } let unused2,e2=mapped(units,proof.contract.unit); if e2!=Error.none { return e2; } let unused3,e3=mapped(units,proof.predicate.identity.unit); if e3!=Error.none { return e3; } }
 for constructor in owner.constructors { let ignored,error=mapped(units,constructor.identity.unit); if error!=Error.none { return error; } }
 for family in owner.effect_families { let ignored,error=mapped(units,family.identity.unit); if error!=Error.none { return error; } }
 for operation in owner.effect_templates { let ignored,error=mapped(units,operation.identity.unit); if error!=Error.none { return error; } }
 for member in owner.associated { let ignored,error=mapped(units,member.identity.unit); if error!=Error.none { return error; } } return Error.none;
}
fn copyCore(value: const Core&) -> blot_reuse_dependency_payload::Owned<Core>,Error { return blot_reuse_dependency_payload::clone(value); }
fn copyModule(value: const Module&) -> OwnedModule,Error { return blot_reuse_dependency_payload::clone(value); }
fn external(value: const Frozen&,current: i64,target: blot_reuse_principal_interface::ExternalTarget) -> Error { var unit=target.unit; if unit==0 { unit=(current+1) as u32; } if unit==0||unit>value.modules.len { return Error.invalid_artifact; } if target.binding==0||target.binding>=value.modules[unit-1].interface.bindings.len { return Error.invalid_artifact; } return Error.none; }
fn validate(value: const Frozen&) -> Error { var stats=Stats {}; let ignored,error=validateMode(value,null,null,stats,false); return error; }
fn emptyCore(unit: u32) -> Core { return Core {unit:unit,types:blot_check_core::Types {nodes:[],extra:[]},nodes:[],spans:[],extra:[],bindings:[],bodies:[],parameters:[],references:[],calls:[],merges:[],merge_ranges:[],names:[],obligations:[],diagnostics:[],body_lowerings:0}; }
struct ValidationRun { value: const Frozen&,current: const Snapshot?,previous: const Snapshot?,stats: Stats&,views: const ModuleRef[:],padded_entry: bool,result: i64=0 }
fn validateMode(value: const Frozen&,current: const Snapshot?,previous: const Snapshot?,stats: Stats&,padded_entry: bool) -> i64,Error {
 let space=blot_phase_profile::enterSpace(blot_phase_profile::Space.core); defer { space.restore(); }
 if blot_phase_profile::currentTrace()!=null { for module in value.modules { blot_phase_profile::traceModule(module.core.unit,module.identity.normalized_path,module.identity.source_bytes); } }
 let timing=blot_phase_profile::enter(blot_phase_profile::Phase.validation); defer { timing.exit(); }
 if value.symbols.len==0||value.symbols[0].text.len!=0 { return 0,Error.invalid_artifact; } var count=value.modules.len; if padded_entry { if count==0x7fffffffffffffff { return 0,Error.out_of_memory; } count++; if count>=0xffffffff { return 0,Error.invalid_artifact; } }
 var views: ModuleRef[>..]=[]; var entry=emptyCore(count as u32); for &module,index in value.modules { if module.core.unit!=index+1||module.interface.unit!=index+1 { return 0,Error.invalid_artifact; } views.push(ModuleRef {module.core}); } if padded_entry { views.push(ModuleRef {entry}); }
 var forbidden=blot_support::none<u32>(); if padded_entry { forbidden=blot_support::some(count as u32); } var run=ValidationRun {value,current,previous,stats,views,padded_entry}; let error=blot_check_frozen_core_validation::withBatch<ValidationRun&,runValidation>(blot_check_frozen_core_validation::Context {units:views,symbol_count:blot_support::some(value.symbols.len),source_length:blot_support::none<u32>(),forbidden_owner:forbidden},run); return run.result,error;
}
fn runValidation(run: ValidationRun&,batch: const blot_check_frozen_core_validation::Batch&) -> Error { let count,error=validateModules(run.value,run.current,run.previous,run.stats,run.views,run.padded_entry,batch); run.result=count; return error; }
fn utf8Path(value: const u8[:]) -> bool { var at=0; while at<value.len { if value[at]==0 { return false; } let width=blot_parse_lexer::utf8_width(value[at]); if width==0||width>value.len-at { return false; } let ignored,error=blot_parse_lexer::decode_point(value[at..at+width]); if error!=Error.none { return false; } at+=width; } return true; }
struct ExportName { name: u32,kind: blot_reuse_frozen_dependency::ExportKind }
fn validateModules(value: const Frozen&,current: const Snapshot?,previous: const Snapshot?,stats: Stats&,views: const ModuleRef[:],padded_entry: bool,batch: const blot_check_frozen_core_validation::Batch&) -> i64,Error {
 var paths: dictionary<const u8[:],bool>; var prelude_count=0; var prelude_unit: u32=0; for module,index in value.modules { if module.identity.prelude { prelude_unit=(index+1) as u32; break; } }
 let closure_views=views[..value.modules.len]; var saved: const Snapshot?=null; if previous { if previous.validated { saved .= previous; } } var previous_views: ModuleRef[>..]=[]; if saved { for &module in saved.value.modules { previous_views.push(ModuleRef {module.core}); } }
 var owner_bounds=false; if saved { owner_bounds=value.modules.len==saved.value.modules.len&&value.symbols.len>=saved.value.symbols.len; } var exact_owners=blot_support::none<blot_reuse_dependency_core_inputs::Owners>(); defer { if exact_owners.present { exact_owners.value.deinit(); } } var owners_examined=false; var resolution_remaining: i64=1000000; var associated_remaining: i64=1000000;
 for &module,id in value.modules {
  var shared=false; if saved { if current { shared=current.shares(saved,id); } } if !blot_path::isAbsolute(module.identity.normalized_path)||paths.contains(module.identity.normalized_path) { return 0,Error.invalid_artifact; } paths.insert(module.identity.normalized_path,true); if module.identity.prelude { prelude_count++; } if prelude_count>1 { return 0,Error.invalid_artifact; }
  if shared&&owner_bounds { stats.interface_reused++; } else { let error=blot_reuse_dependency_interface_validation::validate(module.interface,value.symbols.len,value.modules.len); if error!=Error.none { return 0,error; } let graph=blot_reuse_dependency_interface_validation::validateGraphWithBudget(module.interface,associated_remaining); if graph!=Error.none { return 0,graph; } stats.interface_checked++; }
  var forbidden=blot_support::none<u32>(); if padded_entry { forbidden=blot_support::some(views.len as u32); } let context=blot_check_frozen_core_validation::Context {units:views,symbol_count:blot_support::some(value.symbols.len),source_length:blot_support::some(module.identity.source_bytes),forbidden_owner:forbidden}; var same_core_context=false;
  if shared&&!module.core.has_numeric_proofs { assert(saved); let before: ModuleRef[1]=[ModuleRef {saved.value.modules[id].core}]; let after: ModuleRef[1]=[ModuleRef {module.core}]; same_core_context=blot_check_frozen_core_validation::equivalentContext(blot_check_frozen_core_validation::Context {units:previous_views,symbol_count:blot_support::some(saved.value.symbols.len),source_length:blot_support::some(saved.value.modules[id].identity.source_bytes),forbidden_owner:blot_support::none<u32>()},context,before,after); }
  var same_owned_context=false; if shared&&!same_core_context { if !owners_examined { owners_examined=true; if owner_bounds { assert(current&&saved); let owners,error=blot_reuse_dependency_core_inputs::init(current,saved); if error!=Error.none { return 0,error; } exact_owners=owners; } } if exact_owners.present { same_owned_context=exact_owners.value.stable[id]; } }
  if same_core_context||same_owned_context { stats.core_reused++; } else { let error=batch.validateWithBudget(module.core,blot_support::some(module.identity.source_bytes),associated_remaining); if error!=Error.none { return 0,error; } for field in module.core.field_names { if module.core.name(field.spelling)!=value.symbols[field.symbol].text { return 0,Error.invalid_artifact; } } stats.core_checked++; }
  let abstract=blot_reuse_module_abstraction_validation::publicView(module.interface); if abstract!=Error.none { return 0,abstract; } let associated=blot_check_associated_admission::publicCoreWithBudget(module.interface,module.core,associated_remaining); if associated!=Error.none { return 0,associated; } let implementation=blot_eval_implementation_admission::publicCore(module.interface,module.core,associated_remaining); if implementation!=Error.none { return 0,implementation; }
  for body in module.core.bodies { if body.exported { return 0,Error.invalid_artifact; } } for unit in module.imports { if unit==0||unit>value.modules.len||unit==id+1 { return 0,Error.invalid_artifact; } } var implicit: i64=0; if module.implicit_prelude { implicit=1; } if module.imports.len!=module.source_imports.len+implicit { return 0,Error.invalid_artifact; } if module.implicit_prelude&&(module.identity.prelude||prelude_unit==0||module.imports[0]!=prelude_unit) { return 0,Error.invalid_artifact; }
  for request,index in module.source_imports { if request.target!=module.imports[implicit+index]||request.path.len==0||request.path.len>module.identity.source_bytes||!utf8Path(request.path) { return 0,Error.invalid_artifact; } } for binding in module.interface.bindings { if binding.external.present { let error=external(value,id,binding.external.value); if error!=Error.none { return 0,error; } } }
  var names: dictionary<ExportName,bool>; let reachable,error=forwardedOwners(value,id,resolution_remaining); if error!=Error.none { return 0,error; } defer { closure_bools.free_slice(reachable); }
  for exported in module.exports { let name=ExportName {exported.name,exported.kind}; if exported.name==0||exported.name>=value.symbols.len||names.contains(name) { return 0,Error.invalid_artifact; } names.insert(name,true); var producer=(id+1) as u32; if exported.target.unit!=0 { producer=exported.target.unit; } if producer==0||producer>value.modules.len { return 0,Error.invalid_artifact; } if producer!=id+1&&(reachable.len==0||!reachable[producer-1]) { return 0,Error.invalid_artifact; } let owner=value.modules[producer-1].interface; var valid=false;
   match exported.kind {
    value=>{ let error=external(value,id,exported.target); if error!=Error.none { return 0,error; } let binding=owner.bindings[exported.target.binding]; valid=binding.kind==blot_reuse_principal_interface::Kind.global&&!binding.private&&(producer!=id+1||binding.name==exported.name); },
    nominal=>{ valid=exported.catalog!=0&&exported.catalog<owner.nominals.len; if valid { valid=!owner.nominals[exported.catalog].private&&(producer!=id+1||owner.nominals[exported.catalog].name==exported.name); } },
    constructor=>{ valid=exported.catalog!=0&&exported.catalog<owner.constructors.len; if valid { valid=!owner.constructors[exported.catalog].private&&(producer!=id+1||owner.constructors[exported.catalog].name==exported.name); } },
    effect_family=>{ valid=exported.catalog!=0&&exported.catalog<owner.effect_families.len; if valid { valid=!owner.effect_families[exported.catalog].private&&(producer!=id+1||owner.effect_families[exported.catalog].name==exported.name); } },
    implementation=>{ valid=exported.catalog<owner.implementations.len; if valid { valid=!owner.implementations[exported.catalog].private&&(producer!=id+1||owner.implementations[exported.catalog].name==exported.name); } },
    contract=>{ valid=exported.catalog<owner.contracts.len; if valid { valid=!owner.contracts[exported.catalog].private&&(producer!=id+1||owner.contracts[exported.catalog].name==exported.name); } },
   } if !valid { return 0,Error.invalid_artifact; }
  }
  for fixity in module.fixities { if fixity.operator==0||fixity.operator>=value.symbols.len||fixity.target==0||fixity.target>=value.symbols.len||fixity.precedence>255||fixity.association>2 { return 0,Error.invalid_artifact; } let error=external(value,id,fixity.producer); if error!=Error.none { return 0,error; } }
 }
 let imports=validateImportGraph(value); if imports!=Error.none { return 0,imports; } let storage=blot_reuse_module_abstraction_validation::storageClosure(value.modules,closure_views); if storage!=Error.none { return 0,storage; } let associated=blot_check_associated_admission::originalProducersWithBudget(value.modules,associated_remaining); if associated!=Error.none { return 0,associated; } let implementations=blot_eval_implementation_admission::originalProducers(value.modules,associated_remaining); return views.len,implementations;
}
reusable[] var closure_bools: bool[>..]=[];
fn forwardedOwners(value: const Frozen&,current: i64,remaining: i64&) -> bool[:],Error { var forwarding=false; for entry in value.modules[current].exports { forwarding=forwarding||(entry.target.unit!=0&&entry.target.unit!=current+1); } if !forwarding { return [],Error.none; } let seen=closure_bools.alloc_slice(value.modules.len); for &entry in seen { entry=false; } var work: u32[>..<]=[]; if value.modules[current].imports.len>remaining { closure_bools.free_slice(seen); return [],Error.invalid_artifact; } remaining-=value.modules[current].imports.len; work.append(value.modules[current].imports); while work.len!=0 { let unit=work[work.len-1]; work.resize(work.len-1); if unit==0||unit>seen.len { closure_bools.free_slice(seen); return [],Error.invalid_artifact; } if seen[unit-1] { continue; } seen[unit-1]=true; if value.modules[unit-1].imports.len>remaining { closure_bools.free_slice(seen); return [],Error.invalid_artifact; } remaining-=value.modules[unit-1].imports.len; work.append(value.modules[unit-1].imports); } return seen,Error.none; }
struct ImportFrame { unit: i64,next: i64=0 }
fn validateImportGraph(value: const Frozen&) -> Error { var colors: u8[>..]=[]; var stack: ImportFrame[>..<]=[]; for index in value.modules.len { colors.push(0); } for root in value.modules.len { if colors[root]!=0 { continue; } stack.clear(); stack.push(ImportFrame {root}); colors[root]=1; while stack.len!=0 { let current: ImportFrame&=stack[stack.len-1]; let imports=value.modules[current.unit].imports; if current.next==imports.len { colors[current.unit]=2; stack.resize(stack.len-1); continue; } let child=imports[current.next]-1; current.next++; if colors[child]==1 { return Error.invalid_artifact; } if colors[child]==2 { continue; } colors[child]=1; stack.push(ImportFrame {child}); } } return Error.none; }
struct Ordinals { source: const Project&,ids: const u32[:]=[],explicit_: bool=false }
fn of(self: Ordinals,unit: u32) -> u32,Error { if !self.explicit_ { return ordinal(self.source,unit); } if unit==0||unit>self.ids.len||self.ids[unit-1]==0 { return 0,Error.invalid_artifact; } return self.ids[unit-1],Error.none; }
fn validateSources(value: const Frozen&,source: const Project&) -> Error { let timing=blot_phase_profile::enter(blot_phase_profile::Phase.validation); defer { timing.exit(); } if source.entry==0||source.entry>source.units.len||value.modules.len!=source.units.len-1 { return Error.invalid_artifact; } for index in source.units.len { let unit=(index+1) as u32; if unit==source.entry { continue; } let id,error=ordinal(source,unit); if error!=Error.none { return error; } let checked=validateSource(value,source,unit,id,Ordinals {source}); if checked!=Error.none { return checked; } } return Error.none; }
fn validateSourcesWith(value: const Frozen&,source: const Project&,order: const u32[:]) -> Error { let timing=blot_phase_profile::enter(blot_phase_profile::Phase.validation); defer { timing.exit(); } if value.modules.len!=order.len { return Error.invalid_artifact; } var ids: u32[>..]=[]; for index in source.units.len { ids.push(0); } for unit,index in order { if unit==0||unit>ids.len||unit==source.entry||ids[unit-1]!=0 { return Error.invalid_artifact; } ids[unit-1]=(index+1) as u32; } for unit,index in order { let error=validateSource(value,source,unit,(index+1) as u32,Ordinals {source,ids,true}); if error!=Error.none { return error; } } return Error.none; }
fn validateSource(value: const Frozen&,source: const Project&,source_id: u32,id: u32,ordinals: Ordinals) -> Error {
 let src=source.unit(source_id); let module=value.modules[id-1]; if module.identity.normalized_path!=source.filename(source_id) { return Error.invalid_artifact; } let previous .= source.compiledModule(source_id); if previous { if module.identity.source_bytes!=previous.identity.source_bytes||module.identity.source_digest!=previous.identity.source_digest { return Error.invalid_artifact; } } else { if module.identity.source_bytes!=src.source.len||module.identity.source_digest!=blot_blake3::hash(src.source) { return Error.invalid_artifact; } }
 if module.identity.prelude!=(source_id==source.prelude_unit) { return Error.invalid_artifact; } let prelude=src.implicit_prelude; let edges=source.unitImports(source_id); if module.implicit_prelude!=prelude||module.source_imports.len!=edges.len { return Error.invalid_artifact; } for edge,index in edges { let target,error=ordinals.of(edge.target); if error!=Error.none { return error; } if module.source_imports[index].target!=target||module.source_imports[index].path!=source.symbols.get(edge.path) { return Error.invalid_artifact; } } var next: i64=0; if prelude { next=1; } if module.imports.len!=edges.len+next { return Error.invalid_artifact; } if prelude { let target,error=ordinals.of(source.prelude_unit); if error!=Error.none { return error; } if module.imports[0]!=target { return Error.invalid_artifact; } } for edge in edges { let target,error=ordinals.of(edge.target); if error!=Error.none { return error; } if module.imports[next]!=target { return Error.invalid_artifact; } next++; } return Error.none;
}
fn word(hash: blot_blake3::State&,value: u64) { var bytes: u8[8]=default<u8[8]>(); for index in 8 { bytes[index]=(value>>((index*8) as u32)) as! u8; } hash.update(bytes); }
fn text(hash: blot_blake3::State&,value: const u8[:]) { word(hash,value.len as u64); hash.update(value); }
fn sourceKey(compiler: u8[32],settings: u8[32],source: const Project&) -> blot_reuse_dependency_format::Key,Error {
 if source.diagnostics.len!=0||source.entry==0||source.entry>source.units.len { return default<blot_reuse_dependency_format::Key>(),Error.invalid_artifact; } var content=blot_blake3::init(); var edges=blot_blake3::init(); text(content,"dependency-closure-v1"); text(edges,"dependency-closure-edges-v2"); word(content,(source.units.len-1) as u64); word(edges,(source.units.len-1) as u64);
 for src,index in source.units.items { let source_id=(index+1) as u32; if source_id==source.entry { continue; } let id,error=ordinal(source,source_id); if error!=Error.none { return default<blot_reuse_dependency_format::Key>(),error; } word(content,id); text(content,source.filename(source_id)); word(content,src.source.len as u64); content.update(blot_blake3::hash(src.source)); var prelude: u64=0; if source_id==source.prelude_unit { prelude=1; } word(content,prelude); word(edges,id); var implicit: u64=0; if src.implicit_prelude { implicit=1; } let imports=source.unitImports(source_id); word(edges,implicit); word(edges,imports.len as u64+implicit); if src.implicit_prelude { let target,error=ordinal(source,source.prelude_unit); if error!=Error.none { return default<blot_reuse_dependency_format::Key>(),error; } word(edges,target); } for edge in imports { text(edges,source.symbols.get(edge.path)); let target,error=ordinal(source,edge.target); if error!=Error.none { return default<blot_reuse_dependency_format::Key>(),error; } word(edges,target); } }
 return blot_reuse_dependency_format::Key {compiler,settings,blot_blake3::final(content),blot_blake3::final(edges)},Error.none;
}
fn validateProducer(owner: const Module&,canonical_path: const u8[:],source: const u8[:]) -> Error { return validateProducerDigest(owner,canonical_path,source.len,blot_blake3::hash(source)); }
fn validateProducerDigest(owner: const Module&,canonical_path: const u8[:],source_bytes: i64,digest: u8[32]) -> Error { if owner.identity.normalized_path!=canonical_path||owner.identity.source_bytes!=source_bytes||owner.identity.source_digest!=digest { return Error.invalid_artifact; } return Error.none; }
fn payloadKey(compiler: u8[32],settings: u8[32],value: const Frozen&) -> blot_reuse_dependency_format::Key { var content=blot_blake3::init(); var edges=blot_blake3::init(); text(content,"dependency-closure-v1"); text(edges,"dependency-closure-edges-v2"); word(content,value.modules.len as u64); word(edges,value.modules.len as u64); for owner,index in value.modules { let id=(index+1) as u32; word(content,id); text(content,owner.identity.normalized_path); word(content,owner.identity.source_bytes); content.update(owner.identity.source_digest); var prelude: u64=0; if owner.identity.prelude { prelude=1; } word(content,prelude); word(edges,id); var implicit: u64=0; if owner.implicit_prelude { implicit=1; } word(edges,implicit); word(edges,owner.imports.len as u64); if owner.implicit_prelude { word(edges,owner.imports[0]); } for request in owner.source_imports { text(edges,request.path); word(edges,request.target); } } return blot_reuse_dependency_format::Key {compiler,settings,blot_blake3::final(content),blot_blake3::final(edges)}; }
struct CompletedCoreState { graph: Frozen,validated_context_units: i64,modules: Core[:],source_lengths: u32[:],generation: u64,live: bool=true }
reusable var completed_states: CompletedCoreState[>..]=[];
reusable var completed_receipts: CoreValidationReceipt[>..]=[];
reusable[] var completed_modules: Core[>..]=[];
reusable[] var completed_lengths: u32[>..]=[];
var next_completed_generation: u64=1;
struct CoreValidationReceipt { slot: u32=0,generation: u64=0 }
struct CoreValidationBorrow { receipt: CoreValidationReceipt,graph: Frozen }
fn borrow(self: const CoreValidationReceipt&,graph: const Frozen&) -> CoreValidationBorrow { return CoreValidationBorrow {self,graph}; }
fn prefix(self: CoreValidationBorrow,units: const Core[:],entry: u32,identity: blot_backend_runtime_identity::View) -> i64 { return prefix(self.receipt,self.graph,units,entry,identity); }
fn deinit(self: CoreValidationReceipt&) { if self.slot==0 { return; } let at=self.slot-1; assert(at<completed_states.len&&completed_states[at].live&&completed_states[at].generation==self.generation); let state: CompletedCoreState&=completed_states[at]; completed_modules.free_slice(state.modules); completed_lengths.free_slice(state.source_lengths); state.modules=[]; state.source_lengths=[]; state.graph=Frozen {symbols:[],modules:[]}; state.live=false; completed_states.free(at); self.slot=0; self.generation=0; }
fn sameDescriptors(before: Core,after: Core) -> bool { return blot_check_core::stampView(before)==blot_check_core::stampView(after); }
fn prefix(self: CoreValidationReceipt,graph_owner: const Frozen&,units: const Core[:],entry: u32,identity: blot_backend_runtime_identity::View) -> i64 {
 if self.slot==0||self.slot-1>=completed_states.len { return 0; } let state: const CompletedCoreState&=completed_states[self.slot-1]; if !state.live||state.generation!=self.generation { return 0; } let graph=state.graph; if !(graph_owner.modules .== graph.modules)||!(graph_owner.symbols .== graph.symbols) { return 0; } if units.len!=state.validated_context_units||units.len!=state.modules.len+1||entry!=units.len||identity.symbols.len<graph.symbols.len { return 0; } if units[entry-1].unit!=entry { return 0; } for symbol,index in graph.symbols[1..] { let spelling=identity.symbol((index+1) as u32); if !spelling.present||symbol.text!=spelling.value { return 0; } } for binding in units[entry-1].bindings { if binding.capability_flow==blot_check_check::CapabilityFlow.spawn_task||binding.capability_parameters.inputInvokes() { return 0; } } for saved,index in state.modules { let owner=graph.modules[index]; let current=units[index]; if current.unit!=index+1||owner.identity.source_bytes!=state.source_lengths[index]||!sameDescriptors(saved,owner.core)||!sameDescriptors(saved,current) { return 0; } } return state.modules.len;
}
fn completedCoreValidation(graph: const Frozen&) -> CoreValidationReceipt?,Error { var stats=Stats {}; let units,error=validateMode(graph,null,null,stats,true); if error!=Error.none { return null,error; } if next_completed_generation==0xffffffffffffffff||completed_states.len>=0xffffffff { return null,Error.out_of_memory; } let modules=completed_modules.alloc_slice(graph.modules.len); let lengths=completed_lengths.alloc_slice(graph.modules.len); for owner,index in graph.modules { modules[index]=owner.core; lengths[index]=owner.identity.source_bytes; } let generation=next_completed_generation; next_completed_generation++; let at=completed_states.alloc_index(CompletedCoreState {graph,units,modules,lengths,generation}); return completed_receipts.alloc_ref(CoreValidationReceipt {(at+1) as u32,generation}),Error.none; }
