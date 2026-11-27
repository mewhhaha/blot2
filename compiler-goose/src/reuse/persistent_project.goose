// Fresh project workers publish their imported interfaces and completed Core.
namespace squid_reuse_partial_dependency;
import .partial_dependency;
import reuse.persistent_names;
import reuse.persistent_unit;
import binary;
import support.native;
import support.project_packet;
import inference_limits;
import work_counters;
import phase_profile;

fn preparePersistent(source:Project&,retained:Retained?)->Preparation,Error {
 // Plain #run reads checked Core at emission. Quoted code still uses the live
 // source checker; numeric validation is checked per-unit in parallel workers.
 for unit in source.units.items {
  if needsLiveValues(unit.tree,source.symbols) {return Preparation.inactive,squid_error::Error.none;}
 }
 let handle=squid_native::persist_open(source.units.len as u32);
 if handle==0 {return Preparation.inactive,squid_error::Error.none;}
 if !retained {
  let prepared,failure=runPersistent(source,handle,default<const u8[:][:]>(),default<ModuleDebit[:]>());
  squid_native::persist_close(handle);
  return prepared,failure;
 }
 let parsed=source.symbols.entries.len;
 var symbols,error=squid_parse_symbols::initPooled();
 if error!=squid_error::Error.none {squid_native::persist_close(handle);return Preparation.inactive,error;}
 let allocation=squid_reuse_project_check::replaySymbols(symbols,source.symbols,parsed);
 if allocation!=squid_error::Error.none {symbols.deinit();squid_native::persist_close(handle);return Preparation.inactive,allocation;}
 var input=squid_reuse_project::canonicalLoaded(source,source.compiled_modules,source.compiled_reuse);
 input.symbols=squid_parse_symbols::canonical(symbols);
 var packets=allocateRetainedPackets(source.units.len);
 var debits=squid_reuse_project_check::allocateModuleDebits(source.units.len);
 let prepared,failure=runPersistent(input,handle,packets,debits);
 squid_native::persist_close(handle);
 match prepared {
  ready=>{retained.adoptPersistent(source,symbols,parsed,debits,packets);},
  _=>{releaseRetainedPackets(packets);squid_reuse_project_check::releaseModuleDebits(debits);},
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
  if !squid_native::persist_node(handle,unit,priority) {return false;}
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
   if !squid_native::persist_edge(handle,unit,imported.target) {return false;}
  }
  let prelude=source.prelude_unit;
  if source.unit(unit).implicit_prelude && prelude!=0 && prelude!=unit {
   if !squid_native::persist_edge(handle,unit,prelude) {return false;}
  }
 }
 return true;
}

fn runPersistent(source:Project&,handle:u64,packets:const u8[:][:],debits:ModuleDebit[:])->Preparation,Error {
 if !registerGraph(source,handle) {return Preparation.inactive,squid_error::Error.none;}
 let names,error=squid_reuse_project_check::preparePersistentNames(source);
 if error!=squid_error::Error.none || !names {return Preparation.inactive,error;}
 let width=min(16,min(source.units.len,source.checking.workers as i64));
 let need_interface=packets.len!=0;
 var pids:i64[16]=[0;16];
 let timing=squid_phase_profile::enter(squid_phase_profile::Phase.check);
 var children:u64=0;
 for index in 1..width {
  let pid=squid_native::fork_process();
  if pid==0 {
   squid_phase_profile::installTrace(null);
   let error=runPersistentLane(source,handle,need_interface);
   if error!=squid_error::Error.none {squid_native::persist_fail(handle);squid_native::job_exit(1);}
   squid_native::job_exit(0);
  }
  if pid>0 {pids[index]=pid;children++;}
 }
 let mine=runPersistentLane(source,handle,need_interface);
 if mine!=squid_error::Error.none {
  squid_native::persist_fail(handle);
  for pid in pids {if pid>0 {squid_native::persist_kill_child(pid as u32);}}
 }
 var valid=mine==squid_error::Error.none;
 for pid in pids {
  if pid>0 {if !squid_native::wait_success(pid as u32) {valid=false;}}
 }
 if !valid {squid_phase_profile::recordChecking(squid_work_counters::Frontend{parallel_worker_processes:children,parallel_retries:1,..});}
 timing.exit();
 if !valid {return Preparation.inactive,mine;}
 let owner,error=squid_reuse_dependency_payload::init();
 if error!=squid_error::Error.none {return Preparation.inactive,error;}
 var ready=Prepared{entry:source.entry,source_bytes:source.source_bytes,catalog_owner:owner,..};
 let gather=squid_phase_profile::enter(squid_phase_profile::Phase.lower);
 let failure=gatherPersistent(source,handle,ready,children,packets,debits);
 gather.exit();
 if failure!=squid_error::Error.none {
  let reporting=squid_phase_profile::enter(squid_phase_profile::Phase.check);
  squid_phase_profile::recordChecking(squid_work_counters::Frontend{parallel_worker_processes:children,parallel_retries:1,..});
  reporting.exit();ready.deinit();return Preparation.inactive,failure;
 }
 return Preparation.ready{publishPrepared(ready)},squid_error::Error.none;
}

fn runPersistentLane(source:Project,handle:u64,need_interface:bool=true)->Error {
 var engine,error=squid_reuse_project_check::initPersistentWorker(source);
 if error!=squid_error::Error.none {return error;}
 var packet:u8[>..<]=[];
 var result=squid_error::Error.none;
 loop {
  let claimed=squid_native::persist_claim(handle);
  if claimed==0 {break;}
  if claimed<0 {result=squid_error::Error.invalid_artifact;break;}
  result=squid_reuse_project_check::persistentUnit(engine,claimed as u32,handle,packet,need_interface);
  if result!=squid_error::Error.none {squid_native::persist_fail(handle);break;}
 }
 engine.deinit();
 return result;
}

fn gatherPersistent(source:const Project&,handle:u64,ready:Prepared&,children:u64,packets:const u8[:][:],debits:ModuleDebit[:])->Error {
 let allocated=allocateCatalog(ready,source.units.len);
 if allocated!=squid_error::Error.none {return allocated;}
 let wire,error=squid_project_packet::initOwner();
 if error!=squid_error::Error.none {return error;}
 ready.wire_owner=wire;
 var resolution:i64=1000000;
 var associated=min(squid_inference_limits::configured(),9223372036854775807 as u64) as i64;
 var bytes:u8[>..]=[];
 var stored=default<(const u8[:])[:]>();
 if packets.len!=0 {stored=retained_packet_tables.realloc_slice(packets,packets.len);}
 var counts=squid_work_counters::Frontend{parallel_batches:1,parallel_worker_slots:children+1,parallel_worker_processes:children,..};
 for unit in source.order.items {
  let path,error=ready.catalog_owner.copy(source.filename(unit));
  if error!=squid_error::Error.none {return error;}
  ready.paths[unit-1]=path;
  let size=squid_native::persist_size(handle,unit,2);
  if size<squid_project_packet::execution_core_header_bytes {return squid_error::Error.invalid_artifact;}
  counts.parallel_worker_reply_bytes+=size as u64;
  let interface_size=squid_native::persist_size(handle,unit,1);
  if interface_size>0 {counts.parallel_worker_reply_bytes+=interface_size as u64;}
  let before=resolution;
  let before_associated=associated;
  let failure=readPersistentCoreFromPersist(handle,unit,size,bytes,ready,resolution,associated,counts);
  if failure!=squid_error::Error.none {return failure;}
  if stored.len!=0 {
   if interface_size<=0 {return squid_error::Error.invalid_artifact;}
   let packet=squid_reuse_project_check::owned_u8.alloc_slice(interface_size);
   if !squid_native::persist_read(handle,unit,1,packet[0],interface_size as u64) {
    squid_reuse_project_check::releaseOwned(packet);
    return squid_error::Error.invalid_artifact;
   }
   stored[unit-1]=packet;
   debits[unit-1]=ModuleDebit{before-resolution,before_associated-associated,source.symbols.entries.len};
  }
  ready.stats.syntax_nodes+=source.unit(unit).tree.nodes.len-1;
 }
 let reporting=squid_phase_profile::enter(squid_phase_profile::Phase.check);
 squid_phase_profile::recordChecking(counts);
 reporting.exit();
 return squid_error::Error.none;
}

fn readPersistentCoreFromPersist(handle:u64,unit:u32,total_size:i64,prefix_scratch:u8[>..]&,ready:Prepared&,resolution:i64&,associated:i64&,counts:squid_work_counters::Frontend&)->Error {
 let hdr_len=squid_project_packet::execution_core_header_bytes;
 if total_size<hdr_len {return squid_error::Error.invalid_artifact;}
 var hdr:u8[64]=[0;64];
 if !squid_native::persist_read_at(handle,unit,2,0,hdr[0],hdr_len as u64) {return squid_error::Error.invalid_artifact;}
 let prefix_len=binary::u32le(hdr[..],0) as i64;
 var lens:i64[15]=[0;15];
 var table_total:i64=0;
 for i in 0..15 {
  let l=binary::u32le(hdr[..],4+i*4) as i64;
  lens[i]=l;
  table_total+=l;
 }
 if prefix_len<=0 || prefix_len>squid_project_packet::limit || hdr_len+prefix_len+table_total!=total_size {return squid_error::Error.invalid_artifact;}
 if prefix_len>prefix_scratch.len {prefix_scratch.resize(prefix_len,0);}
 if !squid_native::persist_read_at(handle,unit,2,hdr_len as u64,prefix_scratch[0],prefix_len as u64) {return squid_error::Error.invalid_artifact;}
 var reader=squid_project_packet::Reader{prefix_scratch[..prefix_len],ready.wire_owner};
 var id:u32=0;
 var core=default<Core>();
 var bodies:i64=0;var schemes:i64=0;
 var norm=squid_work_counters::Normalization{};
 var work=squid_work_counters::Frontend{};
 var debit:i64=0;var candidates:i64=0;
 var check_cpu:u64=0;var freeze_cpu:u64=0;var lower_cpu:u64=0;var has_fork_byte:u8=0;
 squid_project_packet::get(reader,id);
 squid_project_packet::getExecutionCoreHeader(reader,core);
 squid_project_packet::get(reader,bodies);
 squid_project_packet::get(reader,schemes);
 squid_project_packet::get(reader,norm);
 squid_project_packet::get(reader,work);
 squid_project_packet::get(reader,debit);
 squid_project_packet::get(reader,candidates);
 squid_project_packet::get(reader,check_cpu);
 squid_project_packet::get(reader,freeze_cpu);
 squid_project_packet::get(reader,lower_cpu);
 squid_project_packet::get(reader,has_fork_byte);
 if reader.failure!=squid_error::Error.none || reader.at!=reader.bytes.len || unit!=id || core.unit!=unit || core.diagnostics.len!=0 || bodies<0 || schemes<0 || debit<0 || candidates<0 || debit>resolution || candidates>associated {return squid_error::Error.invalid_artifact;}
 var at:i64=hdr_len+prefix_len;
 let terr=squid_project_packet::getExecutionCoreTablesFromPersist(handle,unit,2,at,total_size,lens[..],ready.wire_owner,core);
 if terr!=squid_error::Error.none {return terr;}
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
 return squid_error::Error.none;
}
