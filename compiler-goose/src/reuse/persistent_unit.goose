// Each worker owns decoded producer headers and the Checked and Core it makes.
namespace squid_reuse_project_check;
import .project_check;
import check.core_builder;
import reuse.dependency_snapshot;
import support.project_packet;
import phase_profile;

type PersistentSummary=squid_check_check::SchemeSummary;
reusable[] var persistent_summaries:PersistentSummary[>..]=[];
struct PersistentProducer {
    owner:squid_project_packet::Owner=default<squid_project_packet::Owner>(),
    interface:squid_reuse_principal_interface::Interface=default<squid_reuse_principal_interface::Interface>(),
    exports:const Export[:]=default<const Export[:]>(),
    summaries:const PersistentSummary[:]=default<const PersistentSummary[:]>(),
}
reusable[] var persistent_producers:PersistentProducer[>..]=[];
struct PersistentCache {
    producers:PersistentProducer[:]=default<PersistentProducer[:]>(),
    scratch:u8[:]=default<u8[:]>(),
    shared:u64=0,
    current:u32=0,
    error:Error=squid_error::Error.none,
}
reusable var persistent_caches:PersistentCache[>..]=[];

fn initPersistentWorker(source:Project)->Engine,Error {
    if source.input_mode!=squid_reuse_project::InputMode.project || source.diagnostics.len!=0 {
        return Engine{..},squid_error::Error.invalid_artifact;
    }
    var engine,error=initEngine(source,squid_check_check::PrivateExecution{..},Editor.none);
    if error!=squid_error::Error.none {return Engine{..},error;}
    let error=engine.result.allocateModules(source.units.len);
    if error!=squid_error::Error.none {engine.deinit();return Engine{..},error;}
    if persistent_caches.len>=0xffffffff {engine.deinit();return Engine{..},squid_error::Error.out_of_memory;}
    let producers=persistent_producers.alloc_slice(source.units.len);
    for &producer in producers {producer=PersistentProducer{..};}
    let index=persistent_caches.alloc_index(PersistentCache{producers:producers,..});
    engine.persistent_cache=(index+1) as u32;
    engine.source.symbols.read_only=true;
    engine.source.symbols.missing_name=false;
    return engine,squid_error::Error.none;
}

fn persistentCache(self_:const Engine&)->PersistentCache& {
    assert(self_.persistent_cache!=0);
    return persistent_caches[self_.persistent_cache-1];
}

fn deinitPersistentProducer(self_:PersistentProducer&) {
    if self_.summaries.len!=0 {persistent_summaries.free_slice(self_.summaries);}
    self_.owner.deinit();
    self_=PersistentProducer{..};
}
fn deinitPersistentProducers(self_:Engine&) {
    if self_.persistent_cache==0 {return;}
    let cache:PersistentCache& =self_.persistentCache();
    for &producer in cache.producers {
        if producer.owner.slot!=0 {deinitPersistentProducer(producer);}
    }
    if cache.scratch.len!=0 {owned_u8.free_slice(cache.scratch);cache.scratch=default<u8[:]>();}
    persistent_producers.free_slice(cache.producers);
    persistent_caches.free(self_.persistent_cache-1);
    self_.persistent_cache=0;
}

// Frozen catalogs are an immutable view for inference. The lane owns its
// decoded packet cache and remembers the first failure even when a service
// reports an optional result.
fn persistentProducer(self_:const Engine&,unit:u32)->const PersistentProducer? {
    if self_.persistent_cache==0 || unit==0 {return null;}
    let cache:PersistentCache& =self_.persistentCache();
    if unit==cache.current || cache.error!=squid_error::Error.none {return null;}
    if unit>cache.producers.len {cache.error=squid_error::Error.invalid_artifact;return null;}
    let selected:PersistentProducer& =cache.producers[unit-1];
    if selected.owner.slot==0 {
        let retained=self_.retainedPersistentPacket(unit);
        var error=squid_error::Error.none;
        if retained.len!=0 {error=decodePersistentProducer(selected,unit,retained);}
        else {error=readPersistentProducer(cache,selected,unit,cache.shared);}
        if error!=squid_error::Error.none {cache.error=error;return null;}
    }
    return selected;
}

fn readPersistentProducer(cache:PersistentCache&,destination:PersistentProducer&,unit:u32,shared:u64)->Error {
    let size=squid_native::persist_size(shared,unit,1);
    if size<=0 || size>squid_project_packet::limit {return squid_error::Error.invalid_artifact;}
    if size>cache.scratch.len {
        var next_cap=size;
        if cache.scratch.len*2>next_cap {next_cap=cache.scratch.len*2;}
        if cache.scratch.len!=0 {owned_u8.free_slice(cache.scratch);}
        cache.scratch=owned_u8.alloc_slice(next_cap);
    }
    if !squid_native::persist_read(shared,unit,1,cache.scratch[0],size as u64) {
        return squid_error::Error.invalid_artifact;
    }
    return decodePersistentProducer(destination,unit,cache.scratch[..size]);
}

fn readPersistentSummaries(reader:squid_project_packet::Reader&,bindings:i64)->const PersistentSummary[:] {
    let count=squid_project_packet::count(reader);
    if reader.failure!=squid_error::Error.none || count==0 {return default<const PersistentSummary[:]>();}
    if count>=bindings {reader.failure=squid_error::Error.invalid_artifact;return default<const PersistentSummary[:]>();}
    let summaries=persistent_summaries.alloc_slice(bindings);
    for &value in summaries {value=PersistentSummary{..};}
    var previous:u32=0;
    for index in count {
        var binding:u32=0;
        squid_project_packet::get(reader,binding);
        if reader.failure!=squid_error::Error.none || binding<=previous || binding>=bindings {
            reader.failure=squid_error::Error.invalid_artifact;
            break;
        }
        squid_project_packet::get(reader,summaries[binding]);
        if reader.failure!=squid_error::Error.none || !summaries[binding].shareable {
            reader.failure=squid_error::Error.invalid_artifact;
            break;
        }
        previous=binding;
    }
    if reader.failure==squid_error::Error.none {return summaries;}
    persistent_summaries.free_slice(summaries);
    return default<const PersistentSummary[:]>();
}
fn decodePersistentProducer(destination:PersistentProducer&,unit:u32,packet:const u8[:])->Error {
    var owner,error=squid_project_packet::initOwner();
    if error!=squid_error::Error.none {return error;}
    var reader=squid_project_packet::Reader{packet,owner};
    var selected=PersistentProducer{owner:owner, ..};
    squid_project_packet::get(reader,selected.interface);
    var exports:Export[:]=default<Export[:]>();
    squid_project_packet::get(reader,exports);
    selected.exports=exports;
    selected.summaries=readPersistentSummaries(reader,selected.interface.bindings.len);
    if reader.failure!=squid_error::Error.none {
        let error=reader.failure;
        deinitPersistentProducer(selected);
        return error;
    }
    if reader.at!=packet.len || selected.interface.unit!=unit {
        deinitPersistentProducer(selected);
        return squid_error::Error.invalid_artifact;
    }
    destination=selected;
    return squid_error::Error.none;
}

fn cpuMicros(start:u64)->u64 {
    let end=squid_native::thread_cpu_ns();
    if end<start {return 0;}
    return (end-start)/1000;
}

fn selectUnitNames(self_:Engine&,unit:u32) {
    let source .= self_.source;
    var end:i64=0x7fffffffffffffff;
    if unit!=source.entry && squid_reuse_project::entryPacket(source).len!=0 {
        end=source.unit(unit).visible_names;
        if end==0 {end=source.unit(source.entry).parse_start;}
    }
    source.symbols.restrictView(end);
}
fn persistentUnit(self_:Engine&,unit:u32,shared:u64,packet:u8[>..<]&,need_interface:bool=true)->Error {
    self_.selectUnitNames(unit);
    let cache:PersistentCache& =self_.persistentCache();
    if unit==0 || unit>cache.producers.len || self_.diagnostics.items.len!=0 {
        return squid_error::Error.invalid_artifact;
    }
    if squid_check_check::hasNumericFailure(self_.source.unit(unit).tree) {
        return squid_error::Error.invalid_artifact;
    }
    if cache.error!=squid_error::Error.none {return cache.error;}
    if cache.shared!=0 && cache.shared!=shared {return squid_error::Error.invalid_artifact;}
    cache.shared=shared;
    cache.current=unit;
    // Each ready unit gets the normal project bounds. The parent charges the
    // actual debits in source order before it can use any results.
    let resolution=self_.resolution_remaining;
    let associated=self_.associated_remaining;
    self_.source.symbols.missing_name=false;
    var work=squid_work_counters::Frontend{..};
    let capture=squid_phase_profile::captureChecking(work);
    let check_cpu=squid_native::thread_cpu_ns();
    let error=self_.checkModule(unit);
    let check_elapsed=cpuMicros(check_cpu);
    capture.restore(work);
    work.parallel_jobs+=1;
    if cache.error!=squid_error::Error.none {return cache.error;}
    if error!=squid_error::Error.none {return error;}
    if self_.source.symbols.missing_name || self_.diagnostics.items.len!=0 {return squid_error::Error.invalid_artifact;}
    let resolution_used=resolution-self_.resolution_remaining;
    let associated_used=associated-self_.associated_remaining;
    self_.resolution_remaining=resolution;
    self_.associated_remaining=associated;
    let slots=moduleSlots(self_.result);
    if !slots[unit-1].present || !slots[unit-1].value.valid {return squid_error::Error.invalid_artifact;}
    let error=publishPersistentUnit(self_.source,slots[unit-1].value,unit,shared,work,resolution_used,associated_used,check_elapsed,packet,need_interface);
    slots[unit-1].value.deinit();
    slots[unit-1]=squid_support::none<Module>();
    if self_.source.symbols.outsideView() {return squid_error::Error.invalid_artifact;}
    return error;
}

fn publishPersistentUnit(source:Project&,module:const Module&,unit:u32,shared:u64,work:squid_work_counters::Frontend,resolution_used:i64,associated_used:i64,check_cpu_us:u64,packet:u8[>..<]&,need_interface:bool=true)->Error {
    let current=source.unit(unit);
    var freeze_elapsed:u64=0;
    if need_interface || squid_native::persist_consumers(shared,unit)!=0 {
        let freeze_cpu=squid_native::thread_cpu_ns();
        let error=publishPersistentInterface(source.prelude_unit,current.tree,module,unit,shared,packet);
        freeze_elapsed=cpuMicros(freeze_cpu);
        if error!=squid_error::Error.none {return error;}
    }
    let lower_cpu=squid_native::thread_cpu_ns();
    var core,error=squid_check_core_builder::lowerWithOrigins(current.tree,source.symbols,module.checked,moduleOrigins(source),true);
    let lower_elapsed=cpuMicros(lower_cpu);
    if error!=squid_error::Error.none {return error;}
    if source.symbols.missing_name || core.value.diagnostics.len!=0 {
        core.deinit();
        return squid_error::Error.invalid_artifact;
    }
    core.value.unit=unit;
    var has_fork_byte:u8=1;
    for node in core.value.nodes {
        if node.tag==squid_check_core::Tag.fork_ {has_fork_byte=2;break;}
    }
    packet.clear();
    var hdr:u8[64]=[0;64];
    packet.append(hdr);
    var writer=squid_project_packet::Writer{packet};
    squid_project_packet::put(writer,unit);
    squid_project_packet::putExecutionCoreHeader(writer,core.value);
    squid_project_packet::put(writer,module.checked.body_elaborations);
    squid_project_packet::put(writer,module.checked.imported_schemes);
    squid_project_packet::put(writer,module.checked.types.normalization);
    squid_project_packet::put(writer,work);
    squid_project_packet::put(writer,resolution_used);
    squid_project_packet::put(writer,associated_used);
    squid_project_packet::put(writer,check_cpu_us);
    squid_project_packet::put(writer,freeze_elapsed);
    squid_project_packet::put(writer,lower_elapsed);
    squid_project_packet::put(writer,has_fork_byte);
    squid_project_packet::putExecutionCoreTables(writer,core.value);
    core.deinit();
    if writer.failure!=squid_error::Error.none {return writer.failure;}
    if !squid_native::persist_publish(shared,unit,2,packet[0],packet.len as u64) {return squid_error::Error.invalid_artifact;}
    return squid_error::Error.none;
}

fn publishPersistentInterface(prelude:u32,tree:const squid_parse_ast::Tree&,module:const Module&,unit:u32,shared:u64,packet:u8[>..<]&)->Error {
    packet.clear();
    let error=encodePersistentInterface(prelude,tree,module,unit,packet);
    if error!=squid_error::Error.none {return error;}
    if !squid_native::persist_publish(shared,unit,1,packet[0],packet.len as u64) {return squid_error::Error.invalid_artifact;}
    return squid_error::Error.none;
}

fn encodePersistentInterface(prelude:u32,tree:const squid_parse_ast::Tree&,module:const Module&,unit:u32,packet:u8[>..<]&)->Error {
    var summaries:squid_reuse_dependency_snapshot::ProjectedSchemeSummary[>..]=[];
    var frozen,error=squid_reuse_dependency_snapshot::freezePersistent(tree,module.checked,summaries);
    if error!=squid_error::Error.none {return error;}
    var writer=squid_project_packet::Writer{packet};
    squid_project_packet::put(writer,frozen.value);
    squid_project_packet::put(writer,module.exports);
    squid_project_packet::count(writer,summaries.len);
    for entry in summaries {
        squid_project_packet::put(writer,entry.binding);
        squid_project_packet::put(writer,entry.summary);
    }
    squid_reuse_dependency_snapshot::deinit(frozen);
    return writer.failure;
}
