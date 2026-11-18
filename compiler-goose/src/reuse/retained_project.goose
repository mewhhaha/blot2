// A session retains one successful full check and its Core. Each candidate
// reloads the actual project before deciding that its interfaces still hold.
namespace blot_reuse_partial_dependency;
import .partial_dependency;
import reuse.project_check_engine;
import reuse.project_check_owners;
import parse.symbols;
import inference_limits;

type Tree=blot_parse_ast::Tree;
type Unit=blot_reuse_project::Unit;
type ModuleDebit=blot_reuse_project_check::ModuleDebit;

struct Retained {
 source:Project=Project{..},
 checked:CheckedProject=CheckedProject{..},
 parsed_symbols:i64=0,
 inference_limit:u64=0,
 debits:ModuleDebit[:]=default<ModuleDebit[:]>(),
}

fn deinit(self_:Retained&) {
 self_.checked.deinit();
 self_.source.deinit();
 blot_reuse_project_check::releaseModuleDebits(self_.debits);
 self_=Retained{};
}

fn adopt(self_:Retained&,source:Project&,checked:CheckedProject&,parsed_symbols:i64,debits:const ModuleDebit[:]) {
 assert(self_.source.lease==0 && self_.checked.owner.slot==0);
 // This checkpoint owns every loaded unit. Portable dependency catalogs
 // have a separate lifetime in the project session.
 self_.source=blot_reuse_project::canonicalLoaded(source,default<const blot_reuse_frozen_dependency::Module[:]>(),default<const bool[:]>());
 self_.checked=blot_reuse_project_check::canonicalOwnedResult(checked);
 self_.parsed_symbols=parsed_symbols;
 self_.inference_limit=blot_inference_limits::configured();
 self_.debits=blot_reuse_project_check::canonicalModuleDebits(debits);
 source=Project{..};
 checked=CheckedProject{..};
}

fn prepareRetainableProject(source:Project&,entry_path:const u8[:],candidate:Retained&)->Preparation,Error {
 let empty=Frozen{..};
 return prepareProjectMode(source,entry_path,blot_support::none<const u8[:]>(),empty,candidate);
}

fn sameWords(left:const u32[:],right:const u32[:])->bool {
 if left.len!=right.len {return false;}
 for word,index in left {if word!=right[index] {return false;}}
 return true;
}

fn sameGraph(source:const Project&,previous:const Retained&)->bool {
 let old:const Project& =previous.source;
 if old.lease==0 || source.diagnostics.len!=0 || source.compiled_modules.len!=0 || previous.inference_limit!=blot_inference_limits::configured() {return false;}
 if source.input_mode!=old.input_mode || source.entry!=old.entry || source.prelude_unit!=old.prelude_unit || source.units.len!=old.units.len || source.checking.workers!=old.checking.workers {return false;}
 if !sameWords(source.order.items,old.order.items) || source.symbols.entries.len!=previous.parsed_symbols {return false;}
 for index in 0..previous.parsed_symbols {
  let symbol=(index+1) as u32;
  if source.symbols.get(symbol)!=old.symbols.get(symbol) {return false;}
 }
 for unit,index in source.units.items {
  let prior:const Unit& =old.units.items[index];
  if unit.filename!=prior.filename || unit.implicit_prelude!=prior.implicit_prelude {return false;}
  let id=(index+1) as u32;
  let imports=source.unitImports(id);
  let prior_imports=old.unitImports(id);
  if imports.len!=prior_imports.len {return false;}
  for item,at in imports {
   let prior=prior_imports[at];
   if item.path!=prior.path || item.declaration.node!=prior.declaration.node || item.target!=prior.target {return false;}
  }
 }
 return true;
}

recursive fn constructorHead(tree:const Tree&,id:u32,depth:i64)->bool {
 if id==0 || depth==256 {return false;}
 let node=tree.node(id);
 if node.tag==blot_parse_ast::tag_constructor_ref {return true;}
 if node.tag==blot_parse_ast::tag_apply || node.tag==blot_parse_ast::tag_group {return constructorHead(tree,node.a,depth+1);}
 return false;
}

// Only closed data constructors can introduce an editable leaf. This keeps
// the same types, ownership, effects and dispatch at every use of the value.
recursive fn initializerLeaves(tree:const Tree&,id:u32,leaves:u32[>..<]&,depth:i64)->bool {
 if id==0 || depth==256 {return false;}
 let node=tree.node(id);
 match node.tag {
  blot_parse_ast::tag_boolean=>{leaves.push(id);return true;},
  blot_parse_ast::tag_integer,blot_parse_ast::tag_float,blot_parse_ast::tag_string,blot_parse_ast::tag_unit,blot_parse_ast::tag_constructor_ref=>{return true;},
  blot_parse_ast::tag_group=>{return initializerLeaves(tree,node.a,leaves,depth+1);},
  blot_parse_ast::tag_apply=>{
   if !constructorHead(tree,node.a,depth+1) {return false;}
   return initializerLeaves(tree,node.a,leaves,depth+1) && initializerLeaves(tree,node.b,leaves,depth+1);
  },
  blot_parse_ast::tag_record=>{
   for child in tree.children(id) {
    if !initializerLeaves(tree,tree.node(child).b,leaves,depth+1) {return false;}
   }
   return true;
  },
  blot_parse_ast::tag_product=>{
   for child in tree.children(id) {if !initializerLeaves(tree,child,leaves,depth+1) {return false;}}
   return true;
  },
  _=>{return false;},
 }
}

fn markInitializerLeaves(tree:const Tree&,eligible:bool[:]) {
 var leaves:u32[>..<]=[];
 for root in tree.roots.items {
  if tree.node(root).tag!=blot_parse_ast::tag_value_decl {continue;}
  let decl=tree.value_decl(root);
  if decl.runtime || decl.function_declaration || decl.where.len!=0 || decl.attributes.len!=0 || decl.modifier!=0 {continue;}
  leaves.clear();
  if initializerLeaves(tree,decl.body,leaves,0) {for id in leaves {eligible[id]=true;}}
 }
}

fn boolToken(bytes:const u8[:],start:u32,end:u32,value:u32)->bool {
 if end<start || end>bytes.len {return false;}
 if value==1 {return bytes[start..end]=="true";}
 return value==0 && bytes[start..end]=="false";
}

fn sameInitializerShape(old:const Unit&,new_:const Unit&)->bool {
 let old_tree:const Tree& =old.tree;
 let new_tree:const Tree& =new_.tree;
 if old_tree.nodes.len!=new_tree.nodes.len || !sameWords(old_tree.roots.items,new_tree.roots.items) || !sameWords(old_tree.extra.items,new_tree.extra.items) {return false;}
 var eligible:bool[>..]=[];
 eligible.resize(old_tree.nodes.len,false);
 markInitializerLeaves(old_tree,eligible[..]);
 var old_end:u32=0;
 var new_end:u32=0;
 for node,index in old_tree.nodes.items {
  let next=new_tree.nodes.items[index];
  if node.tag!=next.tag || node.b!=next.b || node.c!=next.c {return false;}
  if node.a==next.a {continue;}
  if !eligible[index] {return false;}
  let old_span=old_tree.spans.items[index];
  let new_span=new_tree.spans.items[index];
  if !boolToken(old.source,old_span.start,old_span.end,node.a) || !boolToken(new_.source,new_span.start,new_span.end,next.a) {return false;}
  if old_span.start<old_end || new_span.start<new_end || old.source[old_end..old_span.start]!=new_.source[new_end..new_span.start] {return false;}
  old_end=old_span.end;
  new_end=new_span.end;
 }
 return old_end!=0 && old.source[old_end..]==new_.source[new_end..];
}

fn planModules(source:const Project&,previous:const Project&,changed:bool[:])->bool,bool {
 var any_changed=false;
 var value_observer=false;
 var propagates=false;
 for unit,index in source.units.items {
  let old:const Unit& =previous.units.items[index];
  value_observer=value_observer || unit.tree.has_numeric_proofs || unit.tree.has_typed_staging;
  if unit.source==old.source {continue;}
  if blot_check_check::hasNumericFailure(unit.tree) {return false,false;}
  if index+1==source.prelude_unit || !sameInitializerShape(old,unit) {propagates=true;}
  changed[index]=true;
  any_changed=true;
 }
 if any_changed && value_observer {return false,false;}
 if propagates {includeDependents(source,changed);}
 return any_changed,true;
}

fn includeDependents(source:const Project&,changed:bool[:]) {
 for unit in source.order.items {
  if changed[unit-1] {continue;}
  if source.unit(unit).implicit_prelude && changed[source.prelude_unit-1] {
   changed[unit-1]=true;
   continue;
  }
  for imported in source.unitImports(unit) {
   if changed[imported.target-1] {changed[unit-1]=true;break;}
  }
 }
}

fn prepareRetainedProject(source:Project&,previous:const Retained&,previous_core:const Prepared&)->Preparation,Error {
 if !sameGraph(source,previous) {return Preparation.inactive,blot_error::Error.none;}
 var changed:bool[>..]=[];
 changed.resize(source.units.len,false);
 let edited,admitted=planModules(source,previous.source,changed[..]);
 if !admitted {return Preparation.inactive,blot_error::Error.none;}
 if !edited {
  let empty=CheckedProject{..};
  return prepareWithRetainedCore(source,empty,previous_core,changed[..]);
 }
 if previous.debits.len!=source.units.len {return Preparation.inactive,blot_error::Error.none;}
 var any_reused=false;
 for dirty in changed {any_reused=any_reused || !dirty;}
 if !any_reused {return Preparation.inactive,blot_error::Error.none;}

 // A fallback starts with the loaded parser symbols exactly as they were.
 // Only this private pool receives names while the checker replays the prefix.
 var symbols,error=blot_parse_symbols::initPooled();
 if error!=blot_error::Error.none {return declineRetained(error);}
 let value,error=prepareRetainedWithSymbols(source,previous,previous_core,changed[..],symbols);
 symbols.deinit();
 return value,error;
}

fn prepareRetainedWithSymbols(source:const Project&,previous:const Retained&,previous_core:const Prepared&,changed:const bool[:],symbols:blot_parse_symbols::Pool&)->Preparation,Error {
 let error=blot_reuse_project_check::replaySymbols(symbols,source.symbols,previous.parsed_symbols);
 if error!=blot_error::Error.none {return declineRetained(error);}
 var checking=blot_reuse_project::canonicalLoaded(source,source.compiled_modules,source.compiled_reuse);
 checking.symbols=blot_parse_symbols::canonical(symbols);
 var checked,error=blot_reuse_project_check::checkRetainedModules(checking,previous.checked,changed,previous.debits,previous.source.symbols);
 if error!=blot_error::Error.none {return declineRetained(error);}
 if checked.diagnostics.len!=0 {checked.deinit();return Preparation.inactive,blot_error::Error.none;}
 let result,error=prepareWithRetainedCore(checking,checked,previous_core,changed);
 checked.deinit();
 return result,error;
}

fn declineRetained(error:Error)->Preparation,Error {
 if error==blot_error::Error.out_of_memory {return Preparation.inactive,error;}
 return Preparation.inactive,blot_error::Error.none;
}

fn prepareWithRetainedCore(source:const Project&,checked:const CheckedProject&,previous:const Prepared&,changed:const bool[:])->Preparation,Error {
 let owner,error=blot_reuse_dependency_payload::init();
 if error!=blot_error::Error.none {return Preparation.inactive,error;}
 var ready=Prepared{entry:source.entry,source_bytes:source.source_bytes,stats:Stats{body_elaborations:checked.body_elaborations,imported_schemes:checked.imported_schemes,normalization:checked.normalization},catalog_owner:owner};
 let complete,error=lowerWithRetainedCore(source,checked,previous,changed,ready);
 if !complete || error!=blot_error::Error.none {ready.deinit();return declineRetained(error);}
 return Preparation.ready{publishPrepared(ready)},blot_error::Error.none;
}

fn lowerWithRetainedCore(source:const Project&,checked:const CheckedProject&,previous:const Prepared&,changed:const bool[:],ready:Prepared&)->bool,Error {
 assert(changed.len==previous.units.len && changed.len==source.units.len);
 let error=allocateCatalog(ready,changed.len);
 if error!=blot_error::Error.none {return false,error;}
 for edited,index in changed {
  let id=(index+1) as u32;
  let path,error=ready.catalog_owner.copy(source.filename(id));
  if error!=blot_error::Error.none {return false,error;}
  ready.paths[index]=path;
  if edited {
   let unit .= source.unit(id);
   let timing=blot_phase_profile::enter(blot_phase_profile::Phase.lower);
   var core,error=blot_check_core_builder::lowerWithOrigins(unit.tree,source.symbols,checked.module(id).checked,blot_reuse_project_check::moduleOrigins(source));
   timing.exit();
   if error!=blot_error::Error.none {return false,error;}
   if core.value.diagnostics.len!=0 {core.owner.release();return false,blot_error::Error.none;}
   core.value.unit=id;
   ready.stats.body_lowerings+=core.value.body_lowerings;
   ready.stats.syntax_nodes+=unit.tree.nodes.len-1;
   ready.units[index]=blot_reuse_dependency_owned_headers::canonical(core.owner,core.value);
   ready.unit_owners[index]=core.owner;
  } else {
   // Reattach the table runs to their pool before sharing the lease. The
   // candidate may outlive the previous catalog header, which owns no tables.
   if !previous.unit_owners[index].unique() {return false,blot_error::Error.none;}
   let core=blot_reuse_dependency_owned_headers::canonical(previous.unit_owners[index],previous.units[index]);
   let pin,error=previous.unit_owners[index].retain();
   if error!=blot_error::Error.none {return false,error;}
   ready.unit_owners[index]=pin;
   ready.units[index]=core;
   ready.borrowed[index]=true;
  }
 }
 return true,blot_error::Error.none;
}
