// Fresh project workers publish their imported interfaces and completed Core.
namespace blot_reuse_partial_dependency;
import .partial_dependency;
import reuse.persistent_names;
import reuse.persistent_unit;
import support.native;
import support.project_packet;
import inference_limits;
import work_counters;
import phase_profile;

fn preparePersistent(source:Project&,retained:Retained?)->Preparation,Error {
 // Plain #run reads checked Core at emission. Quoted code still uses the live
 // source checker; numeric validation is checked per-unit in parallel workers.
 for unit in source.units.items {
  if needsLiveValues(unit.tree,source.symbols) {return Preparation.inactive,blot_error::Error.none;}
 }
 let handle=blot_native::persist_open(source.units.len as u32);
 if handle==0 {return Preparation.inactive,blot_error::Error.none;}
 if !retained {
  let prepared,failure=runPersistent(source,handle,default<const u8[:][:]>(),default<ModuleDebit[:]>());
  blot_native::persist_close(handle);
  return prepared,failure;
 }
 let parsed=source.symbols.entries.len;
 var symbols,error=blot_parse_symbols::initPooled();
 if error!=blot_error::Error.none {blot_native::persist_close(handle);return Preparation.inactive,error;}
 let allocation=blot_reuse_project_check::replaySymbols(symbols,source.symbols,parsed);
 if allocation!=blot_error::Error.none {symbols.deinit();blot_native::persist_close(handle);return Preparation.inactive,allocation;}
 var input=blot_reuse_project::canonicalLoaded(source,source.compiled_modules,source.compiled_reuse);
 input.symbols=blot_parse_symbols::canonical(symbols);
 var packets=allocateRetainedPackets(source.units.len);
 var debits=blot_reuse_project_check::allocateModuleDebits(source.units.len);
 let prepared,failure=runPersistent(input,handle,packets,debits);
 blot_native::persist_close(handle);
 match prepared {
  ready=>{retained.adoptPersistent(source,symbols,parsed,debits,packets);},
  _=>{releaseRetainedPackets(packets);blot_reuse_project_check::releaseModuleDebits(debits);},
 }
 symbols.deinit();
 return prepared,failure;
}

fn registerGraph(source:const Project&,handle:u64)->bool {
 // Longest remaining downstream path, estimated by syntax node count.
 var weight:u32[>..]=[];
 weight.resize(source.units.len,0);
 var at=source.order.items.len;
 while at>0 {
  at--;
  let unit=source.order.items[at];
  let item .= source.unit(unit);
  let priority=min(4294967295 as i64,item.tree.nodes.len+(weight[unit-1] as i64)) as u32;
  if !blot_native::persist_node(handle,unit,priority) {return false;}
  for imported in source.unitImports(unit) {
   weight[imported.target-1]=max(priority,weight[imported.target-1]);
  }
  let prelude=source.prelude_unit;
  if item.implicit_prelude && prelude!=0 && prelude!=unit {
   weight[prelude-1]=max(priority,weight[prelude-1]);
  }
 }
 for unit in source.order.items {
  for imported in source.unitImports(unit) {
   if !blot_native::persist_edge(handle,unit,imported.target) {return false;}
  }
  let prelude=source.prelude_unit;
  if source.unit(unit).implicit_prelude && prelude!=0 && prelude!=unit {
   if !blot_native::persist_edge(handle,unit,prelude) {return false;}
  }
 }
 return true;
}

fn runPersistent(source:Project&,handle:u64,packets:const u8[:][:],debits:ModuleDebit[:])->Preparation,Error {
 if !registerGraph(source,handle) {return Preparation.inactive,blot_error::Error.none;}
 let names,error=blot_reuse_project_check::preparePersistentNames(source);
 if error!=blot_error::Error.none || !names {return Preparation.inactive,error;}
 let width=min(16,min(source.units.len,source.checking.workers as i64));
 let need_interface=packets.len!=0;
 var pids:i64[16]=[0;16];
 let timing=blot_phase_profile::enter(blot_phase_profile::Phase.check);
 var children:u64=0;
 for index in 1..width {
  let pid=blot_native::fork_process();
  if pid==0 {
   blot_phase_profile::installTrace(null);
   let error=runPersistentLane(source,handle,need_interface);
   if error!=blot_error::Error.none {blot_native::persist_fail(handle);blot_native::job_exit(1);}
   blot_native::job_exit(0);
  }
  if pid>0 {pids[index]=pid;children++;}
 }
 let mine=runPersistentLane(source,handle,need_interface);
 if mine!=blot_error::Error.none {
  blot_native::persist_fail(handle);
  for pid in pids {if pid>0 {blot_native::persist_kill_child(pid as u32);}}
 }
 var valid=mine==blot_error::Error.none;
 for pid in pids {
  if pid>0 {if !blot_native::wait_success(pid as u32) {valid=false;}}
 }
 if !valid {blot_phase_profile::recordChecking(blot_work_counters::Frontend{parallel_worker_processes:children,parallel_retries:1,..});}
 timing.exit();
 if !valid {return Preparation.inactive,mine;}
 let owner,error=blot_reuse_dependency_payload::init();
 if error!=blot_error::Error.none {return Preparation.inactive,error;}
 var ready=Prepared{entry:source.entry,source_bytes:source.source_bytes,catalog_owner:owner,..};
 let gather=blot_phase_profile::enter(blot_phase_profile::Phase.lower);
 let failure=gatherPersistent(source,handle,ready,children,packets,debits);
 gather.exit();
 if failure!=blot_error::Error.none {
  let reporting=blot_phase_profile::enter(blot_phase_profile::Phase.check);
  blot_phase_profile::recordChecking(blot_work_counters::Frontend{parallel_worker_processes:children,parallel_retries:1,..});
  reporting.exit();ready.deinit();return Preparation.inactive,failure;
 }
 return Preparation.ready{publishPrepared(ready)},blot_error::Error.none;
}

fn runPersistentLane(source:Project,handle:u64,need_interface:bool=true)->Error {
 var engine,error=blot_reuse_project_check::initPersistentWorker(source);
 if error!=blot_error::Error.none {return error;}
 var packet:u8[>..<]=[];
 var result=blot_error::Error.none;
 loop {
  let claimed=blot_native::persist_claim(handle);
  if claimed==0 {break;}
  if claimed<0 {result=blot_error::Error.invalid_artifact;break;}
  result=blot_reuse_project_check::persistentUnit(engine,claimed as u32,handle,packet,need_interface);
  if result!=blot_error::Error.none {blot_native::persist_fail(handle);break;}
 }
 engine.deinit();
 return result;
}

fn gatherPersistent(source:const Project&,handle:u64,ready:Prepared&,children:u64,packets:const u8[:][:],debits:ModuleDebit[:])->Error {
 let allocated=allocateCatalog(ready,source.units.len);
 if allocated!=blot_error::Error.none {return allocated;}
 let wire,error=blot_project_packet::initOwner();
 if error!=blot_error::Error.none {return error;}
 ready.wire_owner=wire;
 var resolution:i64=1000000;
 var associated=min(blot_inference_limits::configured(),9223372036854775807 as u64) as i64;
 var bytes:u8[>..]=[];
 var stored=default<(const u8[:])[:]>();
 if packets.len!=0 {stored=retained_packet_tables.realloc_slice(packets,packets.len);}
 var counts=blot_work_counters::Frontend{parallel_batches:1,parallel_worker_slots:children+1,parallel_worker_processes:children,..};
 for unit in source.order.items {
  let path,error=ready.catalog_owner.copy(source.filename(unit));
  if error!=blot_error::Error.none {return error;}
  ready.paths[unit-1]=path;
  let size=blot_native::persist_size(handle,unit,2);
  if size<=0 {return blot_error::Error.invalid_artifact;}
  if size>bytes.len {bytes.resize(size,0);}
  if !blot_native::persist_read(handle,unit,2,bytes[0],size as u64) {return blot_error::Error.invalid_artifact;}
  counts.parallel_worker_reply_bytes+=size as u64;
  let interface_size=blot_native::persist_size(handle,unit,1);
  if interface_size>0 {counts.parallel_worker_reply_bytes+=interface_size as u64;}
  let before=resolution;
  let before_associated=associated;
  let failure=readPersistentCore(bytes[..size],unit,ready,resolution,associated,counts);
  if failure!=blot_error::Error.none {return failure;}
  if stored.len!=0 {
   if interface_size<=0 {return blot_error::Error.invalid_artifact;}
   let packet=blot_reuse_project_check::owned_u8.alloc_slice(interface_size);
   if !blot_native::persist_read(handle,unit,1,packet[0],interface_size as u64) {
    blot_reuse_project_check::releaseOwned(packet);
    return blot_error::Error.invalid_artifact;
   }
   stored[unit-1]=packet;
   debits[unit-1]=ModuleDebit{before-resolution,before_associated-associated,source.symbols.entries.len};
  }
  ready.stats.syntax_nodes+=source.unit(unit).tree.nodes.len-1;
 }
 let reporting=blot_phase_profile::enter(blot_phase_profile::Phase.check);
 blot_phase_profile::recordChecking(counts);
 reporting.exit();
 return blot_error::Error.none;
}

fn readPersistentCore(bytes:const u8[:],unit:u32,ready:Prepared&,resolution:i64&,associated:i64&,counts:blot_work_counters::Frontend&)->Error {
 var reader=blot_project_packet::Reader{bytes,ready.wire_owner};
 var id:u32=0;
 var core=default<Core>();
 var bodies:i64=0;var schemes:i64=0;
 var norm=blot_work_counters::Normalization{};
 var work=blot_work_counters::Frontend{};
 var debit:i64=0;var candidates:i64=0;
 var check_cpu:u64=0;var freeze_cpu:u64=0;var lower_cpu:u64=0;var has_fork_byte:u8=0;
 blot_project_packet::get(reader,id);
 blot_project_packet::getExecutionCore(reader,core);
 blot_project_packet::get(reader,bodies);
 blot_project_packet::get(reader,schemes);
 blot_project_packet::get(reader,norm);
 blot_project_packet::get(reader,work);
 blot_project_packet::get(reader,debit);
 blot_project_packet::get(reader,candidates);
 blot_project_packet::get(reader,check_cpu);
 blot_project_packet::get(reader,freeze_cpu);
 blot_project_packet::get(reader,lower_cpu);
 blot_project_packet::get(reader,has_fork_byte);
 if reader.failure!=blot_error::Error.none || reader.at!=reader.bytes.len || unit!=id || core.unit!=unit || core.diagnostics.len!=0 || bodies<0 || schemes<0 || debit<0 || candidates<0 || debit>resolution || candidates>associated {return blot_error::Error.invalid_artifact;}
 ready.units[unit-1]=core;
 ready.unit_has_fork[unit-1]=has_fork_byte;
 ready.stats.body_elaborations+=bodies;
 ready.stats.imported_schemes+=schemes;
 ready.stats.body_lowerings+=core.body_lowerings;
 ready.stats.normalization.merge(norm);
 counts.merge(work);
 counts.parallel_worker_jobs++;
 counts.parallel_worker_cpu_samples++;
 counts.parallel_worker_cpu_us+=check_cpu+freeze_cpu+lower_cpu;
 resolution-=debit;associated-=candidates;
 return blot_error::Error.none;
}
