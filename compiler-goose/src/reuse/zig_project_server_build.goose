// Encode and bound the complete response before the revision commits.
namespace blot_reuse_zig_project_server;
import .zig_project_server;
struct AssetRange {id:u32,path:const u8[:],mediaType:const u8[:],sha256:const u8[:],start:u32,length:u32}
struct AssetDependency {path:const u8[:],sha256:Text}
struct DefinitionRead {filename:const u8[:],start:u32,end:u32}
struct SourceLoad {sourceReads:i64=0,reusedSyntaxModules:i64=0}
struct BuildStats {sourceLoad:SourceLoad=SourceLoad{},relocatedOperands:i64=-1,reusedStagedWasm:bool=false,stagedDefinitions:const DefinitionRead[:]=default<const DefinitionRead[:]>(),frontend:blot_reuse_dependency_consumer::Stats,sourceBytes:i64,freshModules:i64,cachedModules:i64,emittedFunctions:i64,sparksVectorized:i64=0,sparksScalarFallback:i64=0,phaseProfile:blot_phase_profile::Record}
struct BuildReply {id:u32,revision:u64,stats:BuildStats,wasm_bytes:i64,ranges:const AssetRange[:]=default<const AssetRange[:]>(),dependencies:const AssetDependency[:]=default<const AssetDependency[:]>(),assets:blot_backend_native_assets::Candidate?=null}
fn jsonStringify(self_:BuildReply,writer:Writer&)->Error {writer.beginObject();writer.field("kind","build");writer.field("id",self_.id);writer.field("epoch",epoch);writer.field("revision",self_.revision);writer.field("success",true);writer.key("stats");writer.beginObject();
    writer.field("frontend",self_.stats.frontend);writer.field("sourceBytes",self_.stats.sourceBytes);
    writer.field("freshModules",self_.stats.freshModules);writer.field("cachedModules",self_.stats.cachedModules);
    writer.field("sourceLoad",self_.stats.sourceLoad);
    if self_.stats.relocatedOperands>=0 {writer.field("relocatedOperands",self_.stats.relocatedOperands);}
    writer.field("emittedFunctions",self_.stats.emittedFunctions);
    if self_.stats.sparksVectorized!=0 || self_.stats.sparksScalarFallback!=0 {
        writer.field("sparksVectorized",self_.stats.sparksVectorized);
        writer.field("sparksScalarFallback",self_.stats.sparksScalarFallback);
    }
    writer.field("phaseProfile",self_.stats.phaseProfile);
    let inputs .= self_.assets;
    if inputs && inputs.tracks_inputs {writer.field("reusedStagedWasm",self_.stats.reusedStagedWasm);writer.field("stagedDefinitions",self_.stats.stagedDefinitions);}
    writer.endObject();let assets .= self_.assets;if assets {writer.field("wasmBytes",self_.wasm_bytes);writer.field("assets",self_.ranges);writer.field("assetDependencies",self_.dependencies);writer.field("assetStats",assets.stats);}writer.endObject();return writer.failure;}
// Profiled sessions clock this build until its stats are published.
fn build(writer:blot_io::Writer,opened:OpenProject&,replay:blot_reuse_body_image::Replay&,id:u32,sources:const Source[:],asset_sources:const Source[:])->Error {
    var trace=blot_phase_profile::Trace{..};if opened.profile_trace {trace=blot_phase_profile::initTrace(id);}var trace_ref:blot_phase_profile::Trace?=null;if trace.key.slot!=0 {trace_ref .= trace;}let trace_installation=blot_phase_profile::installTrace(trace_ref);
    var profile=blot_phase_profile::Profile{..};if opened.profile_backend {profile=blot_phase_profile::initProfile();}var installation=blot_support::none<blot_phase_profile::Installation>();if profile.key.slot!=0 {installation=blot_support::some(blot_phase_profile::install(profile));}
    let error=buildAssets(writer,opened,replay,id,sources,asset_sources,profile);
    if installation.present {installation.value.restore();}profile.deinit();if trace.key.slot!=0 {trace.flushPasses();}trace_installation.restore();trace.deinit();return error;
}
fn buildAssets(writer:blot_io::Writer,opened:OpenProject&,replay:blot_reuse_body_image::Replay&,id:u32,sources:const Source[:],asset_sources:const Source[:],profile:blot_phase_profile::Profile&)->Error {
    var assets:blot_backend_native_assets::Candidate?=null;
    if opened.assets.present {
        let timing=blot_phase_profile::enter(blot_phase_profile::Phase.assets);let candidate,error=opened.assets.value.prepare(opened.entry,sources,asset_sources);timing.exit();if error!=blot_error::Error.none {return operationFailure(writer,opened,id,blot_error::error_name(error),"Unable to prepare native asset inputs");}assert(candidate);assets .= candidate;
        if assets.issue.present {let found=assets.issue.value;let error=reject(writer,id,opened.revisions,Diagnostic{filename:found.filename,stage:"asset",code:found.code,start:found.start,end:found.end,message:found.message,..});assets.deinit();return error;}
    }
    let committed,error=buildSources(writer,opened,replay,id,sources,assets,profile);if assets {if !committed {assets.deinit();}}return error;
}
// All successful builds commit a revision. The asset session takes its
// candidate at that same point.
fn buildSources(writer:blot_io::Writer,opened:OpenProject&,replay:blot_reuse_body_image::Replay&,id:u32,sources:const Source[:],assets:blot_backend_native_assets::Candidate?,profile:blot_phase_profile::Profile&)->bool,Error {
    var merged:Source[>..]=[];let complete_sources=composeSources(sources,assets,merged);
    var snapshot,error=blot_reuse_revision_inputs::initWithSources(opened.options_owner.options(),complete_sources);if error!=blot_error::Error.none {if error==blot_error::Error.out_of_memory {return false,error;}return false,operationFailure(writer,opened,id,blot_error::error_name(error),"Compiler operation failed");}
    let committed,failure=buildSnapshot(writer,opened,replay,id,assets,profile,snapshot);snapshot.deinit();return committed,failure;
}
fn buildSnapshot(writer:blot_io::Writer,opened:OpenProject&,replay:blot_reuse_body_image::Replay&,id:u32,assets:blot_backend_native_assets::Candidate?,profile:blot_phase_profile::Profile&,snapshot:blot_reuse_revision_inputs::Snapshot&)->bool,Error {
    var allow_reuse=true;
    loop {
        var candidate=Retained{..};var reused=false;var load=SourceLoad{};
        var preparation,error=opened.prepare(snapshot,candidate,allow_reuse,reused,load.reusedSyntaxModules);
        load.sourceReads=snapshot.counts().source_reads;
        if error!=blot_error::Error.none {candidate.deinit();if error==blot_error::Error.out_of_memory {return false,error;}return false,operationFailure(writer,opened,id,blot_error::error_name(error),"Compiler operation failed");}
        var retry=false;
        let committed,failure=buildPrepared(writer,opened,replay,id,assets,profile,preparation,reused,candidate.source.lease!=0,load,retry);
        if committed && candidate.source.lease!=0 {
            if reused {candidate.completeFrom(opened.checked);}
            match preparation {ready payload=>{
                opened.core.deinit();opened.checked.deinit();
                opened.checked=candidate;candidate=Retained{..};
                opened.core=payload.value;preparation=blot_reuse_partial_dependency::Preparation.inactive;
                if replay.valid { replay.types.units=opened.core.catalog_owner.mutable(opened.core.units); }
            },_=>{abort("committed revision requires prepared Core");}}
        }
        preparation.deinit();candidate.deinit();
        if !retry {return committed,failure;}
        allow_reuse=false;
    }
}
fn buildPrepared(writer:blot_io::Writer,opened:OpenProject&,replay:blot_reuse_body_image::Replay&,id:u32,assets:blot_backend_native_assets::Candidate?,profile:blot_phase_profile::Profile&,preparation:Preparation&,reused:bool,retainable:bool,load:SourceLoad,retry:bool&)->bool,Error {
    match preparation {
        inactive=>{return false,blot_error::Error.missing_rejection_diagnostic;},
        rejected payload=>{let diagnostic,error=issue(payload.value,opened.entry);if error!=blot_error::Error.none {return false,error;}return false,reject(writer,id,opened.revisions,diagnostic);},
        ready payload=>{
            let timing=blot_phase_profile::enter(blot_phase_profile::Phase.backend);
            // 0-changed-module fast path: every Core unit is borrowed unchanged
            // from the already-validated previous revision, so wire schemas,
            // purity, and NonStagedReceipt are identical without re-running.
            var inputs:i64=-1;
            let all_cached = reused && payload.value.cachedCount()==payload.value.units.len;
            if assets {
                inputs=assets.allocation_index;
                let previous .= opened.assets.value.last;
                if previous && all_cached && previous.cached_receipt_valid && assets.reuseStagedWasm(previous) {
                    timing.exit();
                    let cached_receipt = previous.cached_receipt;
                    let result=Emission{result:blot_reuse_dependency_consumer::Result{compiled:blot_reuse_dependency_consumer::Compiled{bytes:blot_reuse_dependency_consumer::ownBytes(previous.cached_wasm),emitted_functions:previous.cached_functions,..},stats:payload.value.stats,..},source_bytes:payload.value.source_bytes,cached_modules:payload.value.units.len,..};
                    let committed,error=buildEmitted(writer,opened,id,assets,profile,result,payload.value,load,cached_receipt);var owned=result;owned.deinit();return committed,error;
                }
            }
            // The asset evaluator owns its file read set. Projects declaring
            // compile-time inputs use its normal evaluation and publication.
            let track=(retainable || reused) && (!assets || !assets.tracks_inputs);
            var current_non_staged=blot_check_wire_schema::NonStagedReceipt{};
            var pinfo=blot_check_wire_schema::ProgramInfo{};
            var has_analysis=false;
            let skip_unchanged = track && all_cached && opened.image.receipt.valid && opened.image.bytes.len!=0 && (opened.image.receipt.non_staged.kernel_staging_sites_count==0 || opened.image.receipt.staged_dep_units_valid);
            if skip_unchanged {
                current_non_staged=opened.image.receipt.non_staged;
            } else {
                // Validate wire schemas and full non-staged LayoutReceipt
                // once before any retained/cached fast path (§4.1 item 3), and pass `pinfo`
                // straight into emission so the pass never runs twice.
                blot_check_wire_schema::analyze(payload.value.units,payload.value.entry,pinfo);
                if pinfo.issue.failed {
                    timing.exit();
                    if reused { if replay.used { replay.valid=false; replay.needs_reset=true; } retry=true; return false,blot_error::Error.none; }
                    var code:const u8[:]=default<const u8[:]>();
                    match pinfo.issue.code { const for <N,V> in variants<blot_check_diagnostic_code::Code> { V=>{code=N;}, } }
                    if pinfo.issue.unit!=0 && pinfo.issue.unit<=payload.value.paths.len {
                        return false,reject(writer,id,opened.revisions,Diagnostic{filename:payload.value.paths[pinfo.issue.unit-1],stage:"emit",code:code,start:pinfo.issue.span.start,end:pinfo.issue.span.end,message:pinfo.issue.message,..});
                    }
                    return false,reject(writer,id,opened.revisions,Diagnostic{filename:opened.entry,stage:"emit",code:code,start:pinfo.issue.span.start,end:pinfo.issue.span.end,message:pinfo.issue.message,..});
                }
                current_non_staged=blot_check_wire_schema::computeNonStagedReceipt(payload.value.units,payload.value.entry,pinfo);
                has_analysis=true;
            }
            var bytes=default<u8[:]>();
            var operands:i64=-1;
            var replayed=false;
            var pending=blot_direct_relocations::Snapshot{};
            let can_reuse_image=track && reused && blot_reuse_body_image::canReuseReceipt(opened.image.receipt,current_non_staged,payload.value);
            if can_reuse_image {
                bytes,operands=blot_reuse_body_image::relocate(opened.image,opened.core,payload.value,replay);
                if operands<0 && replay.valid {
                    replayed=blot_reuse_body_image::replayEdits(opened.image,opened.core,payload.value,replay,bytes,pending);
                }
            }
            var result=Emission{};
            if operands>=0 || replayed {
                let compiled=blot_reuse_dependency_consumer::Compiled{bytes:bytes,emitted_functions:opened.image.functions,sparks_vectorized:opened.image.sparks_vectorized,sparks_scalar_fallback:opened.image.sparks_scalar_fallback,..};
                let cached=payload.value.cachedCount();
                result=Emission{result:blot_reuse_dependency_consumer::Result{compiled:compiled,stats:payload.value.stats,..},source_bytes:payload.value.source_bytes,fresh_modules:payload.value.units.len-cached,cached_modules:cached,..};
            } else {
                if !has_analysis {
                    blot_check_wire_schema::analyze(payload.value.units,payload.value.entry,pinfo);
                }
                if track { blot_direct_relocations::begin(); }
                var emitted=Emission{};
                var error=blot_error::Error.none;
                if track && !replay.used {
                    emitted,error=blot_reuse_body_image::emitTrackedWithAnalysis(payload.value,replay,pinfo,inputs);
                } else {
                    if replay.used { replay.valid=false; replay.needs_reset=true; }
                    emitted,error=payload.value.emitWithAnalysis(pinfo,inputs);
                }
                if track { pending=blot_direct_relocations::finish(); }
                if error!=blot_error::Error.none { if replay.used { replay.valid=false; replay.needs_reset=true; } pending.deinit();timing.exit();return false,error; }
                result=emitted;
            }
            timing.exit();
            if reused && result.result.compiled.failed { if replay.used { replay.valid=false; replay.needs_reset=true; } pending.deinit();result.deinit();retry=true;return false,blot_error::Error.none; }
            let committed,error=buildEmitted(writer,opened,id,assets,profile,result,payload.value,load,current_non_staged,operands);
            if committed {
                if operands<0 {
                    var preserved_receipt=blot_reuse_body_image::LayoutReceipt{};
                    if replayed {
                        preserved_receipt=opened.image.receipt;
                        opened.image.receipt=blot_reuse_body_image::LayoutReceipt{};
                    }
                    opened.image.deinit();
                    opened.image.layout=pending;
                    pending=blot_direct_relocations::Snapshot{};
                    if replayed {
                        opened.image.receipt=preserved_receipt;
                    }
                }
                if track {
                    blot_reuse_dependency_consumer::freeBytes(opened.image.bytes);
                    opened.image.bytes=result.result.compiled.bytes;
                    result.result.compiled.bytes=default<u8[:]>();
                    opened.image.functions=result.result.compiled.emitted_functions;
                    opened.image.sparks_vectorized=result.result.compiled.sparks_vectorized;
                    opened.image.sparks_scalar_fallback=result.result.compiled.sparks_scalar_fallback;
                    if operands<0 && !replayed {
                        blot_reuse_body_image::deinitLayoutReceipt(opened.image.receipt);
                        opened.image.receipt=blot_reuse_body_image::LayoutReceipt{
                            valid:true,
                            non_staged:current_non_staged,
                            staged_dep_units_valid:result.result.compiled.staged_dep_units_valid,
                            staged_dep_units:result.result.compiled.staged_dep_units,
                            staged_value_digest:result.result.compiled.staged_value_digest,
                        };
                        result.result.compiled.staged_dep_units=default<u32[:]>();
                    }
                }
                if !replay.valid && replay.used { replay.needs_reset=true; }
            } else {
                if operands<0 && replay.used { replay.valid=false; replay.needs_reset=true; }
            }
            pending.deinit();result.deinit();return committed,error;
        }
    }
}
fn buildEmitted(writer:blot_io::Writer,opened:OpenProject&,id:u32,assets:blot_backend_native_assets::Candidate?,profile:blot_phase_profile::Profile&,result:const Emission&,prepared:const blot_reuse_partial_dependency::Prepared&,load:SourceLoad,receipt:blot_check_wire_schema::NonStagedReceipt,operands:i64=-1)->bool,Error {
    if result.result.compiled.failed {let diagnostic,error=issue(result,opened.entry);if error!=blot_error::Error.none {return false,error;}return false,reject(writer,id,opened.revisions,diagnostic);}
    let wasm:const u8[:]=result.result.compiled.bytes;var phases=blot_phase_profile::Record{..};if profile.key.slot!=0 {phases=profile.record();}
    var reads:DefinitionRead[>..]=[];var reused_wasm=false;
    if assets {
        reused_wasm=assets.reused_wasm;
        for use in assets.read_definitions.items {
            let span=prepared.units[use.unit-1].binding(use.binding).span;
            reads.push(DefinitionRead{prepared.paths[use.unit-1],span.start,span.end});
        }
        let saved=assets.keepStagedWasm(wasm,result.result.compiled.emitted_functions,receipt);if saved!=blot_error::Error.none {return false,saved;}
    }
    let stats=BuildStats{sourceLoad:load,relocatedOperands:operands,reusedStagedWasm:reused_wasm,stagedDefinitions:reads[..],frontend:result.result.stats,sourceBytes:result.source_bytes,freshModules:result.fresh_modules,cachedModules:result.cached_modules,emittedFunctions:result.result.compiled.emitted_functions,sparksVectorized:result.result.compiled.sparks_vectorized,sparksScalarFallback:result.result.compiled.sparks_scalar_fallback,phaseProfile:phases};
    var ranges:AssetRange[>..]=[];var dependencies:AssetDependency[>..]=[];var payload_size=wasm.len;
    if assets {
        if payload_size>blot_reuse_zig_project_frames::max_frame_bytes-8 {return false,operationFailure(writer,opened,id,"response_limit","Build reply exceeds protocol limits");}
        for resource in assets.resources.items {if resource.bytes.len>blot_reuse_zig_project_frames::max_frame_bytes-8-payload_size {return false,operationFailure(writer,opened,id,"response_limit","Build reply exceeds protocol limits");}payload_size+=resource.bytes.len;}
        var start=wasm.len;for index in 0..assets.resources.items.len {let resource .= assets.resources.items[index];ranges.push(AssetRange{id:resource.id,path:resource.path,mediaType:resource.mediaType,sha256:assets.resources.items[index].sha256[..],start:start as u32,length:resource.bytes.len as u32});start+=resource.bytes.len;}
        for index in 0..assets.dependencies.items.len {let dependency .= assets.dependencies.items[index];var digest=blot_support::none<const u8[:]>();if dependency.sha256.present {digest=blot_support::some<const u8[:]>(assets.dependencies.items[index].sha256.value[..]);}dependencies.push(AssetDependency{dependency.path,digest});}
    }
    var metadata:u8[>..]=[];let encoded=encodeMetadata(BuildReply{id:id,revision:opened.revisions+1,stats:stats,wasm_bytes:wasm.len,ranges:ranges[..],dependencies:dependencies[..],assets:assets,..},metadata);if encoded!=blot_error::Error.none {return false,operationFailure(writer,opened,id,blot_error::error_name(encoded),"Unable to encode build reply");}
    let bounded=blot_reuse_zig_project_frames::checkLengths(metadata.len,payload_size);if bounded!=blot_error::Error.none {return false,operationFailure(writer,opened,id,"response_limit","Build reply exceeds protocol limits");}
    var parts:const u8[:][>..<]=[];if assets {parts.push(wasm);for index in 0..assets.resources.items.len {parts.push(assets.resources.items[index].bytes);}}
    // Metadata and all segment lengths are encoded and bounded before the
    // revision commits. The asset commit keeps the borrowed asset bytes
    // through the final write.
    opened.revisions+=1;if assets {opened.assets.value.commit(assets);}
    if parts.len!=0 {return true,blot_reuse_zig_project_frames::writeParts(writer,metadata[..],parts[..]);}return true,blot_reuse_zig_project_frames::write(writer,metadata[..],wasm);
}
