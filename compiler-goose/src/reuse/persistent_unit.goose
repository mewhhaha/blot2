// Each worker owns decoded producer headers and the Checked and Core it makes.
namespace blot_reuse_project_check;
import .project_check;
import check.core_builder;
import reuse.dependency_snapshot;
import support.project_packet;
import phase_profile;

type PersistentFixity=blot_reuse_frozen_dependency::Fixity;
type PersistentSummary=blot_check_check::SchemeSummary;
reusable[] var persistent_summaries:PersistentSummary[>..]=[];
struct PersistentProducer {
    owner:blot_project_packet::Owner=default<blot_project_packet::Owner>(),
    interface:blot_reuse_principal_interface::Interface=default<blot_reuse_principal_interface::Interface>(),
    exports:const Export[:]=default<const Export[:]>(),
    summaries:const PersistentSummary[:]=default<const PersistentSummary[:]>(),
    fixities:const PersistentFixity[:]=default<const PersistentFixity[:]>(),
}
reusable[] var persistent_producers:PersistentProducer[>..]=[];
struct PersistentCache {
    producers:PersistentProducer[:]=default<PersistentProducer[:]>(),
    shared:u64=0,
    current:u32=0,
    error:Error=blot_error::Error.none,
}
reusable var persistent_caches:PersistentCache[>..]=[];

fn initPersistentWorker(source:Project)->Engine,Error {
    if source.input_mode!=blot_reuse_project::InputMode.project || source.diagnostics.len!=0 {
        return Engine{..},blot_error::Error.invalid_artifact;
    }
    var engine,error=initEngine(source,blot_check_check::PrivateExecution{..},Editor.none);
    if error!=blot_error::Error.none {return Engine{..},error;}
    let error=engine.result.allocateModules(source.units.len);
    if error!=blot_error::Error.none {engine.deinit();return Engine{..},error;}
    if persistent_caches.len>=0xffffffff {engine.deinit();return Engine{..},blot_error::Error.out_of_memory;}
    let producers=persistent_producers.alloc_slice(source.units.len);
    for &producer in producers {producer=PersistentProducer{..};}
    let index=persistent_caches.alloc_index(PersistentCache{producers:producers,..});
    engine.persistent_cache=(index+1) as u32;
    engine.source.symbols.read_only=true;
    engine.source.symbols.missing_name=false;
    return engine,blot_error::Error.none;
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
    if unit==cache.current || cache.error!=blot_error::Error.none {return null;}
    if unit>cache.producers.len {cache.error=blot_error::Error.invalid_artifact;return null;}
    let selected:PersistentProducer& =cache.producers[unit-1];
    if selected.owner.slot==0 {
        let retained=self_.retainedPersistentPacket(unit);
        var error=blot_error::Error.none;
        if retained.len!=0 {error=decodePersistentProducer(selected,unit,retained);}
        else {error=readPersistentProducer(selected,unit,cache.shared);}
        if error!=blot_error::Error.none {cache.error=error;return null;}
    }
    return selected;
}

fn readPersistentProducer(destination:PersistentProducer&,unit:u32,shared:u64)->Error {
    let size=blot_native::persist_size(shared,unit,1);
    if size<=0 || size>blot_project_packet::limit {return blot_error::Error.invalid_artifact;}
    let packet=owned_u8.alloc_slice(size);
    if !blot_native::persist_read(shared,unit,1,packet[0],size as u64) {
        releaseOwned(packet);
        return blot_error::Error.invalid_artifact;
    }
    let error=decodePersistentProducer(destination,unit,packet);
    releaseOwned(packet);
    return error;
}

fn readPersistentSummaries(reader:blot_project_packet::Reader&,bindings:i64)->const PersistentSummary[:] {
    let count=blot_project_packet::count(reader);
    if reader.failure!=blot_error::Error.none || count==0 {return default<const PersistentSummary[:]>();}
    if count>=bindings {reader.failure=blot_error::Error.invalid_artifact;return default<const PersistentSummary[:]>();}
    let summaries=persistent_summaries.alloc_slice(bindings);
    for &value in summaries {value=PersistentSummary{..};}
    var previous:u32=0;
    for index in count {
        var binding:u32=0;
        blot_project_packet::get(reader,binding);
        if reader.failure!=blot_error::Error.none || binding<=previous || binding>=bindings {
            reader.failure=blot_error::Error.invalid_artifact;
            break;
        }
        blot_project_packet::get(reader,summaries[binding]);
        if reader.failure!=blot_error::Error.none || !summaries[binding].shareable {
            reader.failure=blot_error::Error.invalid_artifact;
            break;
        }
        previous=binding;
    }
    if reader.failure==blot_error::Error.none {return summaries;}
    persistent_summaries.free_slice(summaries);
    return default<const PersistentSummary[:]>();
}
fn decodePersistentProducer(destination:PersistentProducer&,unit:u32,packet:const u8[:])->Error {
    var owner,error=blot_project_packet::initOwner();
    if error!=blot_error::Error.none {return error;}
    var reader=blot_project_packet::Reader{packet,owner};
    var selected=PersistentProducer{owner:owner, ..};
    blot_project_packet::get(reader,selected.interface);
    var exports:Export[:]=default<Export[:]>();
    var fixities:PersistentFixity[:]=default<PersistentFixity[:]>();
    blot_project_packet::get(reader,exports);
    blot_project_packet::get(reader,fixities);
    selected.exports=exports;
    selected.fixities=fixities;
    selected.summaries=readPersistentSummaries(reader,selected.interface.bindings.len);
    if reader.failure!=blot_error::Error.none {
        let error=reader.failure;
        deinitPersistentProducer(selected);
        return error;
    }
    if reader.at!=packet.len || selected.interface.unit!=unit {
        deinitPersistentProducer(selected);
        return blot_error::Error.invalid_artifact;
    }
    destination=selected;
    return blot_error::Error.none;
}

fn cpuMicros(start:u64)->u64 {
    let end=blot_native::thread_cpu_ns();
    if end<start {return 0;}
    return (end-start)/1000;
}

fn selectUnitNames(self_:Engine&,unit:u32) {
    let source .= self_.source;
    var end:i64=0x7fffffffffffffff;
    if unit!=source.entry && blot_reuse_project::entryPacket(source).len!=0 {
        end=source.unit(unit).visible_names;
        if end==0 {end=source.unit(source.entry).parse_start;}
    }
    source.symbols.restrictView(end);
}
fn persistentUnit(self_:Engine&,unit:u32,shared:u64)->Error {
    self_.selectUnitNames(unit);
    let cache:PersistentCache& =self_.persistentCache();
    if unit==0 || unit>cache.producers.len || self_.diagnostics.items.len!=0 {
        return blot_error::Error.invalid_artifact;
    }
    if cache.error!=blot_error::Error.none {return cache.error;}
    if cache.shared!=0 && cache.shared!=shared {return blot_error::Error.invalid_artifact;}
    cache.shared=shared;
    cache.current=unit;
    // Each ready unit gets the normal project bounds. The parent charges the
    // actual debits in source order before it can use any results.
    let resolution=self_.resolution_remaining;
    let associated=self_.associated_remaining;
    self_.source.symbols.missing_name=false;
    var work=blot_work_counters::Frontend{..};
    let capture=blot_phase_profile::captureChecking(work);
    let check_cpu=blot_native::thread_cpu_ns();
    let error=self_.checkModule(unit);
    let check_elapsed=cpuMicros(check_cpu);
    capture.restore(work);
    work.parallel_jobs+=1;
    if cache.error!=blot_error::Error.none {return cache.error;}
    if error!=blot_error::Error.none {return error;}
    if self_.source.symbols.missing_name || self_.diagnostics.items.len!=0 {return blot_error::Error.invalid_artifact;}
    let resolution_used=resolution-self_.resolution_remaining;
    let associated_used=associated-self_.associated_remaining;
    self_.resolution_remaining=resolution;
    self_.associated_remaining=associated;
    let slots=moduleSlots(self_.result);
    if !slots[unit-1].present || !slots[unit-1].value.valid {return blot_error::Error.invalid_artifact;}
    let error=publishPersistentUnit(self_.source,slots[unit-1].value,unit,shared,work,resolution_used,associated_used,check_elapsed);
    slots[unit-1].value.deinit();
    slots[unit-1]=blot_support::none<Module>();
    if self_.source.symbols.outsideView() {return blot_error::Error.invalid_artifact;}
    return error;
}

fn publishPersistentUnit(source:Project&,module:const Module&,unit:u32,shared:u64,work:blot_work_counters::Frontend,resolution_used:i64,associated_used:i64,check_cpu_us:u64)->Error {
    let current=source.unit(unit);
    let freeze_cpu=blot_native::thread_cpu_ns();
    let error=publishPersistentInterface(source.prelude_unit,current.tree,module,unit,shared);
    let freeze_elapsed=cpuMicros(freeze_cpu);
    if error!=blot_error::Error.none {return error;}
    let lower_cpu=blot_native::thread_cpu_ns();
    var core,error=blot_check_core_builder::lowerWithOrigins(current.tree,source.symbols,module.checked,moduleOrigins(source),true);
    let lower_elapsed=cpuMicros(lower_cpu);
    if error!=blot_error::Error.none {return error;}
    if source.symbols.missing_name || core.value.diagnostics.len!=0 {
        core.deinit();
        return blot_error::Error.invalid_artifact;
    }
    core.value.unit=unit;
    var packet:u8[>..<]=[];
    var writer=blot_project_packet::Writer{packet};
    blot_project_packet::put(writer,unit);
    blot_project_packet::putExecutionCore(writer,core.value);
    blot_project_packet::put(writer,module.checked.body_elaborations);
    blot_project_packet::put(writer,module.checked.imported_schemes);
    blot_project_packet::put(writer,module.checked.types.normalization);
    blot_project_packet::put(writer,work);
    blot_project_packet::put(writer,resolution_used);
    blot_project_packet::put(writer,associated_used);
    blot_project_packet::put(writer,check_cpu_us);
    blot_project_packet::put(writer,freeze_elapsed);
    blot_project_packet::put(writer,lower_elapsed);
    core.deinit();
    if writer.failure!=blot_error::Error.none {return writer.failure;}
    if !blot_native::persist_publish(shared,unit,2,packet[0],packet.len as u64) {return blot_error::Error.invalid_artifact;}
    return blot_error::Error.none;
}

fn publishPersistentInterface(prelude:u32,tree:const blot_parse_ast::Tree&,module:const Module&,unit:u32,shared:u64)->Error {
    var packet:u8[>..<]=[];
    let error=encodePersistentInterface(prelude,tree,module,unit,packet);
    if error!=blot_error::Error.none {return error;}
    if !blot_native::persist_publish(shared,unit,1,packet[0],packet.len as u64) {return blot_error::Error.invalid_artifact;}
    return blot_error::Error.none;
}

fn encodePersistentInterface(prelude:u32,tree:const blot_parse_ast::Tree&,module:const Module&,unit:u32,packet:u8[>..<]&)->Error {
    var summaries:blot_reuse_dependency_snapshot::ProjectedSchemeSummary[>..]=[];
    var frozen,error=blot_reuse_dependency_snapshot::freezePersistent(tree,module.checked,summaries);
    if error!=blot_error::Error.none {return error;}
    var fixities:PersistentFixity[>..<]=[];
    if unit==prelude {
        for root in tree.roots.items {
            if tree.node(root).tag!=blot_parse_ast::tag_fixity_decl {continue;}
            let fixity=tree.fixity(root);
            let binding=module.checked.resolved[root];
            let declaration=module.checked.bindings[binding];
            var target=ExternalTarget{unit,binding};
            if declaration.external.present {target=declaration.external.value;}
            fixities.push(PersistentFixity{operator:fixity.operator,target:fixity.target,named:fixity.named,producer:target, ..});
        }
    }
    var writer=blot_project_packet::Writer{packet};
    blot_project_packet::put(writer,frozen.value);
    blot_project_packet::put(writer,module.exports);
    blot_project_packet::put(writer,fixities[..]);
    blot_project_packet::count(writer,summaries.len);
    for entry in summaries {
        blot_project_packet::put(writer,entry.binding);
        blot_project_packet::put(writer,entry.summary);
    }
    blot_reuse_dependency_snapshot::deinit(frozen);
    return writer.failure;
}
