// A session retains the latest successful checked project and its Core.
// Each candidate reloads the project before deciding which interfaces still hold.
namespace blot_reuse_partial_dependency;
import .partial_dependency;
import reuse.project_check_engine;
import reuse.project_check_owners;
import parse.symbols;
import inference_limits;
import reuse.persistent_unit;
import check.typed_staging_names;

type Tree=blot_parse_ast::Tree;
type Unit=blot_reuse_project::Unit;
type ModuleDebit=blot_reuse_project_check::ModuleDebit;
reusable[] var retained_packet_tables:(const u8[:])[>..]=[];

struct Retained {
 source:Project=Project{..},
 checked:CheckedProject=CheckedProject{..},
 parsed_symbols:i64=0,
 inference_limit:u64=0,
 debits:ModuleDebit[:]=default<ModuleDebit[:]>(),
 packets:const u8[:][:]=default<const u8[:][:]>(),
}

fn deinit(self_:Retained&) {
 self_.checked.deinit();
 self_.source.deinit();
 blot_reuse_project_check::releaseModuleDebits(self_.debits);
 releaseRetainedPackets(self_.packets);
 self_=Retained{};
}

fn adopt(self_:Retained&,source:Project&,checked:CheckedProject&,parsed_symbols:i64,debits:const ModuleDebit[:]) {
 self_.adoptSource(source,parsed_symbols,debits);
 self_.checked=blot_reuse_project_check::canonicalOwnedResult(checked);
 checked=CheckedProject{..};
}

fn adoptSource(self_:Retained&,source:Project&,parsed_symbols:i64,debits:const ModuleDebit[:]) {
 assert(self_.source.lease==0 && self_.checked.owner.slot==0);
 // This checkpoint owns every loaded unit. Portable dependency catalogs
 // have a separate lifetime in the project session.
 self_.source=blot_reuse_project::canonicalLoaded(source,default<const blot_reuse_frozen_dependency::Module[:]>(),default<const bool[:]>());
 self_.parsed_symbols=parsed_symbols;
 self_.inference_limit=blot_inference_limits::configured();
 self_.debits=blot_reuse_project_check::canonicalModuleDebits(debits);
 source=Project{..};
}

fn completeFrom(self_:Retained&,previous:Retained&) {
 if self_.packets.len!=0 {
  let next=retained_packet_tables.realloc_slice(self_.packets,self_.packets.len);
  let old=retained_packet_tables.realloc_slice(previous.packets,previous.packets.len);
  for packet,index in old {
   if next[index].len!=0 {continue;}
   next[index]=packet;
   old[index]=default<const u8[:]>();
  }
  return;
 }
 blot_reuse_project_check::moveSkippedModules(self_.checked,previous.checked);
}

fn allocateRetainedPackets(length:i64)->const u8[:][:] {
 let packets=retained_packet_tables.alloc_slice(length);
 for &entry in packets {entry=default<const u8[:]>();}
 return packets;
}

fn releaseRetainedPackets(packets:const u8[:][:]) {
 if packets.len==0 {return;}
 for packet in packets {blot_reuse_project_check::releaseOwned(packet);}
 retained_packet_tables.free_slice(packets);
}

fn adoptPersistent(self_:Retained&,source:Project&,symbols:blot_parse_symbols::Pool&,parsed:i64,debits:const ModuleDebit[:],packets:const u8[:][:]) {
 source.symbols.deinit();
 source.symbols=blot_parse_symbols::canonical(symbols);
 symbols=blot_parse_symbols::Pool{..};
 self_.adoptSource(source,parsed,debits);
 let owned=retained_packet_tables.realloc_slice(packets,packets.len);
 assert(blot_support::same_slice_identity(owned,packets));
 self_.packets=owned;
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

// Only the root sees names following the dependency prefix. A committed
// packet from a dependency was checked and lowered within that prefix.
fn entryOnlyEdit(source:const Project&,previous:const Retained&)->bool {
 let old .= previous.source;
 if previous.packets.len==0 || old.lease==0 || source.entry==0 || source.entry!=old.entry ||
    source.units.len!=old.units.len || blot_reuse_project::entryPacket(source).len==0 ||
    blot_reuse_project::entryPacket(old).len==0 {return false;}
 if source.unit(source.entry).source==old.unit(old.entry).source ||
    source.unit(source.entry).parse_start!=old.unit(old.entry).parse_start {return false;}
 for unit,i in source.units.items {
  if i+1!=source.entry && unit.source!=old.units.items[i].source {return false;}
 }
 return true;
}
fn sameGraph(source:const Project&,previous:const Retained&,entry_only:bool,scoped:bool)->bool {
 let old:const Project& =previous.source;
 if old.lease==0 || source.diagnostics.len!=0 || source.compiled_modules.len!=0 || previous.inference_limit!=blot_inference_limits::configured() {return false;}
 if source.input_mode!=old.input_mode || source.entry!=old.entry || source.prelude_unit!=old.prelude_unit || source.units.len!=old.units.len || source.checking.workers!=old.checking.workers {return false;}
 if !sameWords(source.order.items,old.order.items) {return false;}
 var prefix=previous.parsed_symbols;
 if scoped {prefix=0;}
 else if entry_only {prefix=source.unit(source.entry).parse_start;}
 else if source.symbols.entries.len!=prefix {return false;}
 for index in 0..prefix {
  let symbol=(index+1) as u32;
  if source.symbols.get(symbol)!=old.symbols.get(symbol) {return false;}
 }
 for unit,index in source.units.items {
  let prior:const Unit& =old.units.items[index];
  if unit.filename!=prior.filename || source.symbols.get(unit.filename)!=old.symbols.get(prior.filename) || unit.implicit_prelude!=prior.implicit_prelude {return false;}
  let id=(index+1) as u32;
  let imports=source.unitImports(id);
  let prior_imports=old.unitImports(id);
  if imports.len!=prior_imports.len {return false;}
  for item,at in imports {
   let prior=prior_imports[at];
   if item.path!=prior.path || source.symbols.get(item.path)!=old.symbols.get(prior.path) || item.declaration.node!=prior.declaration.node || item.target!=prior.target {return false;}
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

fn needsLiveValues(tree:const Tree&,symbols:const blot_parse_symbols::Pool&)->bool {
 if !tree.has_typed_staging {return false;}
 for node in tree.nodes.items {
  if node.tag!=blot_parse_ast::tag_intrinsic {continue;}
  let operation,staged=blot_check_typed_staging::lookup(symbols.get(node.a));
  if staged && operation!=blot_check_typed_staging::Op.evaluate {return true;}
 }
 return false;
}

fn planModules(source:const Project&,previous:const Project&,changed:bool[:],propagates:bool[:])->bool,bool {
 var any_changed=false;
 var value_observer=false;
 for unit,index in source.units.items {
  let old:const Unit& =previous.units.items[index];
  value_observer=value_observer || needsLiveValues(unit.tree,source.symbols);
  if unit.source==old.source {continue;}
  if blot_check_check::hasNumericFailure(unit.tree) {return false,false;}
  if index+1==source.prelude_unit || !sameInitializerShape(old,unit) {
   propagates[index]=true;
  }
  changed[index]=true;
  any_changed=true;
 }
 if any_changed && value_observer {return false,false;}
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

fn prepareRetainedProject(source:Project&,previous:const Retained&,previous_core:const Prepared&,candidate:Retained&)->Preparation,Error {
 let entry_only=entryOnlyEdit(source,previous);
 let scoped=previous.packets.len!=0 && source.lease!=0 && previous.source.lease!=0 &&
    blot_reuse_project::projects[source.lease-1].parser_symbols.lease!=0 &&
    blot_reuse_project::projects[previous.source.lease-1].parser_symbols.lease!=0;
 var common:i64=0;
 if scoped {
  let limit=min(previous.parsed_symbols,source.symbols.entries.len);
  while common<limit {
   let id=(common+1) as u32;
   if source.symbols.get(id)!=previous.source.symbols.get(id) {break;}
   common++;
  }
 }
 if !sameGraph(source,previous,entry_only,scoped) {return Preparation.inactive,blot_error::Error.none;}
 var changed:bool[>..]=[];
 changed.resize(source.units.len,false);
 var propagates:bool[>..]=[];propagates.resize(changed.len,false);
 let edited,admitted=planModules(source,previous.source,changed[..],propagates[..]);
 if !admitted {return Preparation.inactive,blot_error::Error.none;}
 if !edited {
  let empty=CheckedProject{..};
  return prepareWithRetainedCore(source,empty,previous_core,changed[..]);
 }
 var affected:bool[>..]=[];affected.resize(changed.len,false);
 var symbol_shifted:bool[>..]=[];symbol_shifted.resize(changed.len,false);
 if scoped {
  for unit,i in source.units.items {
   let old=previous.source.units.items[i];
   if i+1==source.entry {
    symbol_shifted[i]=common<previous.parsed_symbols;
    affected[i]=symbol_shifted[i];
   } else {
    symbol_shifted[i]=old.visible_names>common;
    affected[i]=unit.visible_names!=old.visible_names || symbol_shifted[i];
   }
   if affected[i] {propagates[i]=true;}
  }
 }
 includeDependents(source,propagates[..]);
 for dirty,i in propagates {if dirty {changed[i]=true;}}
 if previous.debits.len!=source.units.len {return Preparation.inactive,blot_error::Error.none;}
 var any_reused=false;
 for dirty in changed {any_reused=any_reused || !dirty;}
 if !any_reused {return Preparation.inactive,blot_error::Error.none;}
 if previous.packets.len!=0 {
  return prepareRetainedPersistent(source,previous,previous_core,changed[..],affected[..],symbol_shifted[..],scoped || entry_only,candidate);
 }

 // A fallback starts with the loaded parser symbols exactly as they were.
 // Only this private pool receives names while the checker replays the prefix.
 var symbols,error=blot_parse_symbols::initPooled();
 if error!=blot_error::Error.none {return declineRetained(error);}
 let debits=blot_reuse_project_check::allocateModuleDebits(source.units.len);
 let value,error=prepareRetainedWithSymbols(source,previous,previous_core,changed[..],symbols,debits,candidate);
 symbols.deinit();
 if candidate.source.lease==0 {blot_reuse_project_check::releaseModuleDebits(debits);}
 return value,error;
}

fn prepareRetainedWithSymbols(source:Project&,previous:const Retained&,previous_core:const Prepared&,changed:const bool[:],symbols:blot_parse_symbols::Pool&,debits:ModuleDebit[:],candidate:Retained&)->Preparation,Error {
 let error=blot_reuse_project_check::replaySymbols(symbols,source.symbols,previous.parsed_symbols);
 if error!=blot_error::Error.none {return declineRetained(error);}
 var checking=blot_reuse_project::canonicalLoaded(source,source.compiled_modules,source.compiled_reuse);
 checking.symbols=blot_parse_symbols::canonical(symbols);
 var checked,error=blot_reuse_project_check::checkRetainedModules(checking,previous.checked,changed,previous.debits,debits,previous.source.symbols);
 if error!=blot_error::Error.none {return declineRetained(error);}
 if checked.diagnostics.len!=0 {checked.deinit();return Preparation.inactive,blot_error::Error.none;}
 let result,error=prepareWithRetainedCore(checking,checked,previous_core,changed);
 match result {
  ready=>{
   source.symbols.deinit();
   source.symbols=blot_parse_symbols::canonical(symbols);
   symbols=blot_parse_symbols::Pool{..};
   candidate.adopt(source,checked,previous.parsed_symbols,debits);
  },
  _=>{},
 }
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
  var issue=blot_error::Error.none;
  if edited {issue=lowerRetainedUnit(source,checked.module(id).checked,id,ready);}
  else {issue=reuseRetainedCore(previous,index,ready);}
  if issue!=blot_error::Error.none {return false,issue;}
 }
 return true,blot_error::Error.none;
}

fn lowerRetainedUnit(source:const Project&,checked:const blot_check_check::Checked&,id:u32,ready:Prepared&)->Error {
 let unit .= source.unit(id);
 let timing=blot_phase_profile::enter(blot_phase_profile::Phase.lower);
 var core,error=blot_check_core_builder::lowerWithOrigins(unit.tree,source.symbols,checked,blot_reuse_project_check::moduleOrigins(source),true);
 timing.exit();
 if error!=blot_error::Error.none {return error;}
 if core.value.diagnostics.len!=0 {core.owner.release();return blot_error::Error.invalid_artifact;}
 core.value.unit=id;
 ready.stats.body_lowerings+=core.value.body_lowerings;
 ready.stats.syntax_nodes+=unit.tree.nodes.len-1;
 ready.units[id-1]=blot_reuse_dependency_owned_headers::canonical(core.owner,core.value);
 ready.unit_owners[id-1].tables=core.owner;
 ready.unit_has_fork[id-1]=scanUnitFork(ready.units[id-1]);
 return blot_error::Error.none;
}

fn reuseRetainedCore(previous:const Prepared&,index:i64,ready:Prepared&,literal:u32=0,bits:u32=0)->Error {
 let prior=previous.unit_owners[index];
 if prior.tables.lease!=0 {
  let owner,error=prior.tables.retain();
  if error!=blot_error::Error.none {return error;}
  ready.unit_owners[index].tables=owner;
 } else if ready.wire_owner.slot==0 {
  // The initial parallel check puts every unit's tables in one immutable packet.
  let owner,error=previous.wire_owner.retain();
  if error!=blot_error::Error.none {return error;}
  ready.wire_owner=owner;
 }
 let units=previous.catalog_owner.mutable(previous.units);
 ready.units[index]=units[index];
 if literal!=0 {
  let owner,error=blot_reuse_dependency_payload::init();
  if error!=blot_error::Error.none {return error;}
  ready.unit_owners[index].nodes=owner;
  let nodes,error=blot_reuse_dependency_payload::copy<blot_check_core::Node>(ready.unit_owners[index].nodes,units[index].nodes);
  if error!=blot_error::Error.none {return error;}
  nodes[literal].a=bits;
  ready.units[index].nodes=nodes;
  ready.units[index].owner_id=blot_native::fresh_owner_id();
 } else if prior.nodes.lease!=0 {
  let owner,error=prior.nodes.retain();
  if error!=blot_error::Error.none {return error;}
  ready.unit_owners[index].nodes=owner;
 }
 ready.borrowed[index]=literal==0;
 ready.unit_has_fork[index]=previous.unit_has_fork[index];
 return blot_error::Error.none;
}

fn prepareRetainedPersistent(source:Project&,previous:const Retained&,previous_core:const Prepared&,changed:bool[:],affected:const bool[:],symbol_shifted:const bool[:],verified_suffix:bool,candidate:Retained&)->Preparation,Error {
 var symbols,error=blot_parse_symbols::initPooled();
 if error!=blot_error::Error.none {return declineRetained(error);}
 let packets=allocateRetainedPackets(changed.len);
 let debits=blot_reuse_project_check::allocateModuleDebits(changed.len);
 let value,error=checkRetainedPersistent(source,previous,previous_core,changed,affected,symbol_shifted,symbols,packets,debits,verified_suffix,candidate);
 symbols.deinit();
 if candidate.source.lease==0 {
  releaseRetainedPackets(packets);
  blot_reuse_project_check::releaseModuleDebits(debits);
 }
 return value,error;
}

fn checkRetainedPersistent(source:Project&,previous:const Retained&,previous_core:const Prepared&,changed:bool[:],affected:const bool[:],symbol_shifted:const bool[:],symbols:blot_parse_symbols::Pool&,packets:const u8[:][:],debits:ModuleDebit[:],verified_suffix:bool,candidate:Retained&)->Preparation,Error {
 let parsed=source.symbols.entries.len;
 let error=blot_reuse_project_check::replaySymbols(symbols,source.symbols,parsed);
 if error!=blot_error::Error.none {return declineRetained(error);}
 var input=blot_reuse_project::canonicalLoaded(source,source.compiled_modules,source.compiled_reuse);
 input.symbols=blot_parse_symbols::canonical(symbols);
 let prepared,error=blot_reuse_project_check::preparePersistentNames(input);
 if error!=blot_error::Error.none {return declineRetained(error);}
 let end=symbols.entries.len;
 if !prepared || (!verified_suffix && end!=previous.source.symbols.entries.len) {return Preparation.inactive,blot_error::Error.none;}
 var verified=parsed;
 if verified_suffix {verified=end;}
 for index in verified..end {
  let id=(index+1) as u32;
  if symbols.get(id)!=previous.source.symbols.get(id) {return Preparation.inactive,blot_error::Error.none;}
 }
 var engine,error=blot_reuse_project_check::initPersistentWorker(input);
 if error!=blot_error::Error.none {return declineRetained(error);}
 engine.persistent_previous=previous.packets;
 engine.persistent_candidate=packets;
 engine.persistent_changed=changed;
 let owner,error=blot_reuse_dependency_payload::init();
 if error!=blot_error::Error.none {engine.deinit();return declineRetained(error);}
 var ready=Prepared{entry:source.entry,source_bytes:source.source_bytes,catalog_owner:owner,..};
 let allocated=allocateCatalog(ready,changed.len);
 var failure=allocated;
 if failure==blot_error::Error.none {failure=rebuildRetainedPersistent(engine,previous,previous_core,changed,affected,symbol_shifted,debits,packets,ready);}
 engine.deinit();
 if failure!=blot_error::Error.none {ready.deinit();return declineRetained(failure);}
 candidate.adoptPersistent(source,symbols,parsed,debits,packets);
 return Preparation.ready{publishPrepared(ready)},blot_error::Error.none;
}

// A U32 passed by value to an ordinary function has the same type, effects
// and ownership at every value. Keep source positions and the old interface
// only when the sole change is inside that one decimal token.
fn editedInteger(old:const Unit&,next:const Unit&)->u32 {
 if old.source.len!=next.source.len || old.tree.nodes.len!=next.tree.nodes.len {return 0;}
 var first:i64=0;
 while first<old.source.len && old.source[first]==next.source[first] {first++;}
 if first==old.source.len {return 0;}
 for node,i in next.tree.nodes.items {
  if node.tag!=blot_parse_ast::tag_integer {continue;}
  let span=next.tree.spans.items[i];
  if span.start>first || span.end<=first {continue;}
  let prior=old.tree.nodes.items[i];
  let before=old.tree.spans.items[i];
  if prior.tag!=node.tag || prior.a==node.a || before.start!=span.start || before.end!=span.end {return 0;}
  for at in span.start..span.end {
   if old.source[at]<48 || old.source[at]>57 || next.source[at]<48 || next.source[at]>57 {return 0;}
  }
  if old.source[span.end..]!=next.source[span.end..] {return 0;}
  return i as u32;
 }
 return 0;
}

// Match the syntax and its checked use. An index, loop bound, pattern,
// intrinsic, or proof can depend on the value of an integer during checking.
fn boundIntegerCall(tree:const Tree&,literal:u32)->u32 {
 for node,i in tree.nodes.items {
  if node.tag!=blot_parse_ast::tag_let_stmt {continue;}
  let binding=tree.binding(i as u32);
  if binding.fallback!=0 || binding.where.len!=0 || tree.node(binding.pattern).tag!=blot_parse_ast::tag_pattern_name {continue;}
  var head=binding.value;
  var found=false;
  while tree.node(head).tag==blot_parse_ast::tag_apply {
   let apply=tree.node(head);
   if tree.node(apply.b).tag!=blot_parse_ast::tag_integer {break;}
   found=found || apply.b==literal;
   head=apply.a;
  }
  if found && tree.node(head).tag==blot_parse_ast::tag_name {return binding.value;}
 }
 return 0;
}

fn revisedCallLiteral(old:const Unit&,next:const Unit&,core:const Core&)->u32,u32 {
 let literal=editedInteger(old,next);
 if literal==0 {return 0,0;}
 let call=boundIntegerCall(next.tree,literal);
 if call==0 {return 0,0;}
 let span=next.tree.span(literal);
 let call_span=next.tree.span(call);
 var id:u32=0;
 var target:u32=0;
 for node,i in core.nodes {
  let site=core.spans[i];
  if site.start==span.start && site.end==span.end {
   if id!=0 || node.tag!=blot_check_core::Tag.constant || node.ty!=blot_check_types::u32_type ||
      node.a!=old.tree.node(literal).a {return 0,0;}
   id=i as u32;
  }
  if site.start==call_span.start && site.end==call_span.end && node.tag==blot_check_core::Tag.call {
   if target!=0 || core.calls[node.a].target.unit==0 || core.calls[node.a].target.unit==core.unit {return 0,0;}
   target=i as u32;
  }
 }
 if id==0 || target==0 {return 0,0;}
 let invocation=core.nodes[target];
 for operand in core.extra[invocation.b..invocation.b+invocation.c] {
  if operand==id {return id,next.tree.node(literal).a;}
 }
 return 0,0;
}

fn sameSymbolPrefix(old:const blot_parse_symbols::Pool&,next:const blot_parse_symbols::Pool&)->bool {
 if old.entries.len>next.entries.len || old.bytes.len>next.bytes.len {return false;}
 if old.bytes.items!=next.bytes.items[..old.bytes.len] {return false;}
 for i in 0..old.entries.len {
  let ea=old.entries.items[i];
  let eb=next.entries.items[i];
  if ea.offset!=eb.offset || ea.len!=eb.len || ea.hash!=eb.hash {return false;}
 }
 return true;
}

fn sameTests(old: const Tree&, next: const Tree&) -> bool {
 if old.test_meta.len!=next.test_meta.len {return false;}
 for a,i in old.test_meta.items {
  let b=next.test_meta.items[i];
  if a.declaration!=b.declaration || a.display_name!=b.display_name || a.line!=b.line || a.is_trap!=b.is_trap {return false;}
 }
 return true;
}
fn sameTriviaSyntax(old:const Unit&,next:const Unit&,old_syms:const blot_parse_symbols::Pool&,next_syms:const blot_parse_symbols::Pool&)->bool {
 let ot:const Tree& =old.tree;
 let nt:const Tree& =next.tree;
 if ot.diagnostics.len!=0 || nt.diagnostics.len!=0 {return false;}
 if ot.has_typed_staging!=nt.has_typed_staging {return false;}
 if ot.nodes.len!=nt.nodes.len || !sameWords(ot.roots.items,nt.roots.items) || !sameWords(ot.extra.items,nt.extra.items) {return false;}
 if !sameSymbolPrefix(old_syms,next_syms) {return false;}
 for i in 0..ot.nodes.len {
  let a=ot.nodes.items[i];
  let b=nt.nodes.items[i];
  if a.tag!=b.tag || a.a!=b.a || a.b!=b.b || a.c!=b.c {return false;}
  if a.tag==blot_parse_ast::tag_string {
   let sa=ot.spans.items[i];
   let sb=nt.spans.items[i];
   if sa.end>old.source.len || sb.end>next.source.len || old.source[sa.start..sa.end]!=next.source[sb.start..sb.end] {return false;}
  }
 }
 return true;
}

fn spanInFunctionDecl(tree:const Tree&,span:blot_parse_ast::Span)->bool {
 for root in tree.roots.items {
  let rs=tree.span(root);
  if span.start<rs.start || span.end>rs.end {continue;}
  if tree.node(root).tag!=blot_parse_ast::tag_value_decl {return false;}
  let decl=tree.value_decl(root);
  if !decl.function_declaration || decl.where.len!=0 || decl.attributes.len!=0 {return false;}
  let bs=tree.span(decl.body);
  return span.start>=bs.start && span.end<=bs.end;
 }
 return false;
}

fn isSafeU32LiteralUse(core:const Core&,id:u32,old_bits:u32,new_bits:u32)->bool {
 for n,i in core.nodes {
  let tag=n.tag;
  match tag {
   invalid,constant,reference,constructor_function,primitive_function,panic,type_constructor,operation_value,contract_method,closure=>{},
   scalar=>{
    if n.a==id || n.b==id {
     match n.op {
      equal,not_equal,less,less_equal,greater,greater_equal,bit_and,bit_or,bit_xor=>{},
      add,sub,mul=>{ if old_bits<=1 || new_bits<=1 {return false;} },
      _=>{return false;},
     }
    }
   },
   logical,apply,if_value,if_stmt,bind,pattern_bind,return_,project,associated,result_associated,product,record,construct,block_,suite,array,break_=>{},
   call=>{
    let ci=core.call(i as u32);
    for arg in ci.arguments {
     if arg==id {
      if ci.target.unit==0 && (ci.target.binding as i64)<core.bindings.len {
       if core.bindings[ci.target.binding].kind==blot_reuse_principal_interface::Kind.external && core.bindings[ci.target.binding].target.binding==0 {return false;}
      }
     }
    }
   },
   loop_=>{
    let li=core.loopInfo(i as u32);
    if li.first==id || li.end==id {return false;}
   },
   spark=>{
    let si=core.sparkInfo(i as u32);
    if si.source==id || si.end==id {return false;}
   },
   update=>{
    let ui=core.updateInfo(i as u32);
    if ui.root==id || ui.value==id {return false;}
    for st in core.updateSelectors(i as u32) {if st.index==id {return false;}}
   },
   match_=>{
    for inp in core.matchInputs(i as u32) {if inp==id {return false;}}
   },
   array_op,storage=>{
    for child in core.children(i as u32) {if child==id {return false;}}
   },
   _=>{
    if n.a==id || n.b==id || n.c==id {return false;}
    for child in core.children(i as u32) {if child==id {return false;}}
   },
  }
 }
 return true;
}

fn isSafeF32LiteralPatch(old_bits:u32,new_bits:u32)->bool {
 // Reject NaN/Inf, special peephole constants (0, -0, 1, 2, -2), or bounded-finite class changes.
 if (old_bits & 0x7f800000)==0x7f800000 || (new_bits & 0x7f800000)==0x7f800000 {return false;}
 if old_bits==0 || old_bits==0x80000000 || old_bits==0x3f800000 || old_bits==0x40000000 || old_bits==0xc0000000 {return false;}
 if new_bits==0 || new_bits==0x80000000 || new_bits==0x3f800000 || new_bits==0x40000000 || new_bits==0xc0000000 {return false;}
 let old_le1=(old_bits & 0x7fffffff)<=0x3f800000;
 let new_le1=(new_bits & 0x7fffffff)<=0x3f800000;
 if old_le1!=new_le1 {return false;}
 let old_bf=(old_bits & 0x7f800000)<0x50000000;
 let new_bf=(new_bits & 0x7f800000)<0x50000000;
 return old_bf==new_bf;
}

fn revisedScalarLiteral(old:const Unit&,next:const Unit&,core:const Core&)->u32,u32 {
 let ot:const Tree& =old.tree;
 let nt:const Tree& =next.tree;
 if ot.has_typed_staging || nt.has_typed_staging {return 0,0;}
 if old.source.len!=next.source.len || ot.nodes.len!=nt.nodes.len {return 0,0;}
 if !sameWords(ot.roots.items,nt.roots.items) || !sameWords(ot.extra.items,nt.extra.items) {return 0,0;}
 var first:i64=0;
 while first<old.source.len && old.source[first]==next.source[first] {first++;}
 if first==old.source.len {return 0,0;}
 var lit:u32=0;
 for i in 0..nt.nodes.len {
  let a=ot.nodes.items[i];
  let b=nt.nodes.items[i];
  let sa=ot.spans.items[i];
  let sb=nt.spans.items[i];
  if sa.start!=sb.start || sa.end!=sb.end {return 0,0;}
  if a.tag!=b.tag || a.b!=b.b || a.c!=b.c {return 0,0;}
  if a.a!=b.a {
   if lit!=0 {return 0,0;}
   if a.tag!=blot_parse_ast::tag_integer && a.tag!=blot_parse_ast::tag_float {return 0,0;}
   if (sb.start as i64)>first || (sb.end as i64)<=first {return 0,0;}
   lit=i as u32;
  }
 }
 if lit==0 {return 0,0;}
 let span=nt.spans.items[lit];
 if old.source[span.end..]!=next.source[span.end..] {return 0,0;}
 if !spanInFunctionDecl(nt,span) {return 0,0;}
 for pat in core.patterns {
  if pat.span.start==span.start && pat.span.end==span.end {return 0,0;}
 }
 let old_bits=ot.nodes.items[lit].a;
 let new_bits=nt.nodes.items[lit].a;
 let is_float=nt.nodes.items[lit].tag==blot_parse_ast::tag_float;
 if is_float && !isSafeF32LiteralPatch(old_bits,new_bits) {return 0,0;}
 var want_ty=blot_check_types::u32_type;
 if is_float {want_ty=blot_check_types::f32_type;}
 var id:u32=0;
 for node,i in core.nodes {
  let site=core.spans[i];
  if site.start==span.start && site.end==span.end {
   if id!=0 || node.tag!=blot_check_core::Tag.constant || node.ty!=want_ty || node.a!=old_bits {return 0,0;}
   id=i as u32;
  }
 }
 if id==0 {return 0,0;}
 if !is_float && !isSafeU32LiteralUse(core,id,old_bits,new_bits) {return 0,0;}
 return id,new_bits;
}

// Parsing a declaration with the same source and linked symbol prefix
// produces the same syntax. Compare the complete declaration slice so string
// contents, layout, and syntax stored outside the fixed node fields count.
fn sameAstSubtree(old:const Unit&,a:u32,next:const Unit&,b:u32)->bool {
 if a==0 || b==0 {return a==b;}
 let before=old.tree.span(a);
 let after=next.tree.span(b);
 return before.end>=before.start && after.end>=after.start &&
  old.tree.node(a).tag==next.tree.node(b).tag &&
  old.source[before.start..before.end]==next.source[after.start..after.end];
}

fn selectiveRoots(old:const Unit&,next:const Unit&,skip_root:bool[>..]&)->bool {
 let a:const Tree& =old.tree;
 let b:const Tree& =next.tree;
 if a.diagnostics.len!=0 || b.diagnostics.len!=0 || a.has_typed_staging || b.has_typed_staging ||
    !sameTests(a,b) || a.roots.len!=b.roots.len {return false;}
 var edited:i64=0;
 var unchanged:i64=0;
 for ar,index in a.roots.items {
  let br=b.roots.items[index];
  let tag=a.node(ar).tag;
  if tag!=b.node(br).tag {return false;}
  if tag!=blot_parse_ast::tag_value_decl {
   if !sameAstSubtree(old,ar,next,br) {return false;}
   skip_root.push(true);
   continue;
  }
  let av=a.value_decl(ar);
  let bv=b.value_decl(br);
  let at=blot_parse_ast::declaration_traits(a,ar);
  let bt=blot_parse_ast::declaration_traits(b,br);
  if av.name!=bv.name || at.private!=bt.private || at.is_opaque!=bt.is_opaque ||
     av.runtime!=bv.runtime || av.exported!=bv.exported || av.modifier!=bv.modifier ||
     av.function_declaration!=bv.function_declaration || av.where.len!=bv.where.len ||
     !sameAstSubtree(old,av.annotation,next,bv.annotation) ||
     !sameAstSubtree(old,av.where_node,next,bv.where_node) ||
     av.attributes.len!=bv.attributes.len {return false;}
  for attr,i in a.list(av.attributes) {
   if !sameAstSubtree(old,attr,next,b.list(bv.attributes)[i]) {return false;}
  }
  let a_lambda=a.node(av.body).tag==blot_parse_ast::tag_lambda;
  let b_lambda=b.node(bv.body).tag==blot_parse_ast::tag_lambda;
  if a_lambda!=b_lambda {return false;}
  let same=sameAstSubtree(old,ar,next,br) && sameAstSubtree(old,av.body,next,bv.body);
  if same {unchanged+=1;}
  else {
   if !a_lambda || av.attributes.len!=0 || av.runtime {return false;}
   var first:u32=1;
   if index!=0 {first=a.roots.items[index-1]+1;}
   for node in a.nodes.items[first..ar] {
    if node.tag==blot_parse_ast::tag_fork_expr {return false;}
   }
   edited+=1;
   if edited>16 {return false;}
  }
  skip_root.push(same);
 }
 return edited!=0 && unchanged>=4;
}

fn trySelectiveRetainedUnit(engine:blot_reuse_project_check::Engine&,unit:u32,old_tree:const Tree&,previous:const Core&,skip_root:const bool[:],ready:Prepared&)->bool,Error {
 let source=engine.source.unit(unit);
 // Bound the append-only tables even when one session keeps editing the
 // same body. A normal rebuild drops unreachable versions of edited bodies.
 if previous.nodes.len>2*source.tree.nodes.len || previous.bindings.len>2*source.tree.nodes.len {
  return false,blot_error::Error.none;
 }
 var checked=default<blot_check_check::Checked>();
 let check=blot_phase_profile::enter(blot_phase_profile::Phase.check);
 let error=engine.checkModuleBody(unit,previous,skip_root,checked);
 check.exit();
 if error!=blot_error::Error.none {return false,error;}
 let timing=blot_phase_profile::enter(blot_phase_profile::Phase.lower);
 var shifts:blot_check_core_builder::SourceShift[>..]=[];
 var offset:i64=0;
 for root,index in old_tree.roots.items {
  let start=old_tree.span(root).start;
  let next=source.tree.span(source.tree.roots.items[index]).start as i64-start;
  if next==offset {continue;}
  shifts.push(blot_check_core_builder::SourceShift{start:start,offset:next});
  offset=next;
 }
 let core,error=blot_check_core_builder::lowerRetainedUnitSelective(source.tree,engine.source.symbols,checked,blot_reuse_project_check::moduleOrigins(engine.source),previous,skip_root,shifts[..]);
 timing.exit();
 if error==blot_error::Error.none {
  ready.stats.body_elaborations+=checked.body_elaborations;
  ready.stats.imported_schemes+=checked.imported_schemes;
  ready.stats.normalization.merge(checked.types.normalization);
  ready.stats.body_lowerings+=core.value.body_lowerings;
  ready.stats.syntax_nodes+=source.tree.nodes.len-1;
  ready.units[unit-1]=blot_reuse_dependency_owned_headers::canonical(core.owner,core.value);
  ready.unit_owners[unit-1].tables=core.owner;
  ready.unit_has_fork[unit-1]=scanUnitFork(ready.units[unit-1]);
  ready.spliced_unit=unit;
 }
 checked.deinit();
 return error==blot_error::Error.none,error;
}

fn rebuildRetainedPersistent(engine:blot_reuse_project_check::Engine&,previous:const Retained&,previous_core:const Prepared&,changed:bool[:],affected:const bool[:],symbol_shifted:const bool[:],debits:ModuleDebit[:],packets:const u8[:][:],ready:Prepared&)->Error {
 let owned=retained_packet_tables.realloc_slice(packets,packets.len);
 let cache .= engine.persistentCache();
 // An unchanged packet certifies the complete catalog that a caller reads.
 // Forward a changed transitive origin even through an identical re-export.
 var propagated:bool[>..]=[];propagated.resize(changed.len,false);
 for unit in engine.source.order.items {
  let index=unit-1;
  let path,error=ready.catalog_owner.copy(engine.source.filename(unit));
  if error!=blot_error::Error.none {return error;}
  ready.paths[index]=path;
  var inherited=false;
  if changed[index] {
   if engine.source.unit(unit).implicit_prelude {inherited=propagated[engine.source.prelude_unit-1];}
   for edge in engine.source.unitImports(unit) {if propagated[edge.target-1] {inherited=true;break;}}
   changed[index]=affected[index] || inherited || engine.source.unit(unit).source!=previous.source.unit(unit).source;
  }
  var literal:u32=0;
  var bits:u32=0;
  if changed[index] && !inherited && !affected[index] && sameTests(previous.source.unit(unit).tree,engine.source.unit(unit).tree) {
   if sameTriviaSyntax(previous.source.unit(unit),engine.source.unit(unit),previous.source.symbols,engine.source.symbols) {
    changed[index]=false;
   } else {
    literal,bits=revisedCallLiteral(previous.source.unit(unit),engine.source.unit(unit),previous_core.units[index]);
    if literal==0 {
     literal,bits=revisedScalarLiteral(previous.source.unit(unit),engine.source.unit(unit),previous_core.units[index]);
    }
    if literal!=0 {changed[index]=false;}
   }
  }
  if !changed[index] {
   let debit=previous.debits[index];
   if debit.resolution>engine.resolution_remaining || debit.associated>engine.associated_remaining {return blot_error::Error.invalid_artifact;}
   engine.resolution_remaining-=debit.resolution;
   engine.associated_remaining-=debit.associated;
   debits[index]=debit;
   let error=reuseRetainedCore(previous_core,index,ready,literal,bits);
   if error!=blot_error::Error.none {return error;}
   continue;
  }
  let resolution=engine.resolution_remaining;
  let associated=engine.associated_remaining;
  let symbol_count=engine.source.symbols.entries.len;
  cache.current=unit;
  if inherited && unit!=engine.source.entry && engine.source.units.items[index].visible_names<engine.source.symbols.entries.len {
   engine.source.units.items[index].visible_names=engine.source.symbols.entries.len;
  }
  engine.selectUnitNames(unit);
  if !inherited && !symbol_shifted[index] && sameSymbolPrefix(previous.source.symbols,engine.source.symbols) {
   var skip_root:bool[>..]=[];
   if selectiveRoots(previous.source.unit(unit),engine.source.unit(unit),skip_root) {
    let accepted,error=trySelectiveRetainedUnit(engine,unit,previous.source.unit(unit).tree,previous_core.units[index],skip_root[..],ready);
    if error==blot_error::Error.out_of_memory {return error;}
    if engine.source.symbols.outsideView() || engine.source.symbols.missing_name ||
       engine.source.symbols.entries.len!=symbol_count {return blot_error::Error.invalid_artifact;}
    if accepted {
     owned[index]=blot_reuse_project_check::copyOwned(previous.packets[index]);
     let debit=previous.debits[index];
     // The prior debit covers unchanged work. Charge the trial's projections
     // too, so a selective success cannot give later modules more budget.
     if debit.resolution>resolution || debit.associated>engine.associated_remaining {return blot_error::Error.invalid_artifact;}
     engine.resolution_remaining=resolution-debit.resolution;
     engine.associated_remaining-=debit.associated;
     debits[index]=ModuleDebit{debit.resolution,associated-engine.associated_remaining,symbol_count};
     cache.current=0;
     continue;
    }
    engine.resolution_remaining=resolution;
    engine.associated_remaining=associated;
   }
  }
  let check=blot_phase_profile::enter(blot_phase_profile::Phase.check);
  let continued,error=engine.checkOrdered(unit);
  check.exit();
  if error!=blot_error::Error.none {return error;}
  if !continued || cache.error!=blot_error::Error.none || engine.source.symbols.missing_name || engine.diagnostics.items.len!=0 {
   if cache.error!=blot_error::Error.none {return cache.error;}
   return blot_error::Error.invalid_artifact;
  }
  let slots=blot_reuse_project_check::moduleSlots(engine.result);
  let module:const blot_reuse_project_check::Module& =slots[index].value;
  var packet:u8[>..<]=[];
  let freeze=blot_phase_profile::enter(blot_phase_profile::Phase.freeze);
  let encoded=blot_reuse_project_check::encodePersistentInterface(engine.source.prelude_unit,engine.source.unit(unit).tree,module,unit,packet);
  freeze.exit();
  if encoded!=blot_error::Error.none {return encoded;}
  propagated[index]=inherited || symbol_shifted[index] || packet[..]!=previous.packets[index];
  owned[index]=blot_reuse_project_check::copyOwned(packet[..]);
  let lowered=lowerRetainedUnit(engine.source,module.checked,unit,ready);
  if lowered!=blot_error::Error.none {return lowered;}
  if engine.source.symbols.outsideView() || engine.source.symbols.missing_name || engine.source.symbols.entries.len!=symbol_count {return blot_error::Error.invalid_artifact;}
  ready.stats.body_elaborations+=module.checked.body_elaborations;
  ready.stats.imported_schemes+=module.checked.imported_schemes;
  ready.stats.normalization.merge(module.checked.types.normalization);
  debits[index]=ModuleDebit{resolution-engine.resolution_remaining,associated-engine.associated_remaining,symbol_count};
  slots[index].value.deinit();
  slots[index]=blot_support::none<blot_reuse_project_check::Module>();
  cache.current=0;
 }
 return blot_error::Error.none;
}
