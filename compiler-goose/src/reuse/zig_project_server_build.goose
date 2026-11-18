// Encode and bound the complete response before the revision commits.
namespace blot_reuse_zig_project_server;
import .zig_project_server;
struct AssetRange {id:u32,path:const u8[:],mediaType:const u8[:],sha256:const u8[:],start:u32,length:u32}
struct AssetDependency {path:const u8[:],sha256:Text}
struct BuildStats {frontend:blot_reuse_dependency_consumer::Stats,sourceBytes:i64,freshModules:i64,cachedModules:i64,emittedFunctions:i64,phaseProfile:blot_phase_profile::Record}
struct BuildReply {id:u32,revision:u64,stats:BuildStats,wasm_bytes:i64,ranges:const AssetRange[:]=default<const AssetRange[:]>(),dependencies:const AssetDependency[:]=default<const AssetDependency[:]>(),assets:blot_backend_native_assets::Candidate?=null}
fn jsonStringify(self_:BuildReply,writer:Writer&)->Error {writer.beginObject();writer.field("kind","build");writer.field("id",self_.id);writer.field("epoch",epoch);writer.field("revision",self_.revision);writer.field("success",true);writer.field("stats",self_.stats);let assets .= self_.assets;if assets {writer.field("wasmBytes",self_.wasm_bytes);writer.field("assets",self_.ranges);writer.field("assetDependencies",self_.dependencies);writer.field("assetStats",assets.stats);}writer.endObject();return writer.failure;}
// Profiled sessions clock this build until its stats are published.
fn build(writer:blot_io::Writer,opened:OpenProject&,id:u32,sources:const Source[:],asset_sources:const Source[:])->Error {
    var trace=blot_phase_profile::Trace{..};if opened.profile_trace {trace=blot_phase_profile::initTrace(id);}var trace_ref:blot_phase_profile::Trace?=null;if trace.key.slot!=0 {trace_ref .= trace;}let trace_installation=blot_phase_profile::installTrace(trace_ref);
    var profile=blot_phase_profile::Profile{..};if opened.profile_backend {profile=blot_phase_profile::initProfile();}var installation=blot_support::none<blot_phase_profile::Installation>();if profile.key.slot!=0 {installation=blot_support::some(blot_phase_profile::install(profile));}
    let error=buildAssets(writer,opened,id,sources,asset_sources,profile);
    if installation.present {installation.value.restore();}profile.deinit();if trace.key.slot!=0 {trace.flushPasses();}trace_installation.restore();trace.deinit();return error;
}
fn buildAssets(writer:blot_io::Writer,opened:OpenProject&,id:u32,sources:const Source[:],asset_sources:const Source[:],profile:blot_phase_profile::Profile&)->Error {
    var assets:blot_backend_native_assets::Candidate?=null;
    if opened.assets.present {
        let timing=blot_phase_profile::enter(blot_phase_profile::Phase.assets);let candidate,error=opened.assets.value.prepare(opened.entry,sources,asset_sources);timing.exit();if error!=blot_error::Error.none {return operationFailure(writer,opened,id,blot_error::error_name(error),"Unable to prepare native asset inputs");}assert(candidate);assets .= candidate;
        if assets.issue.present {let found=assets.issue.value;let error=reject(writer,id,opened.revisions,Diagnostic{filename:found.filename,stage:"asset",code:found.code,start:found.start,end:found.end,message:found.message,..});assets.deinit();return error;}
    }
    let committed,error=buildSources(writer,opened,id,sources,assets,profile);if assets {if !committed {assets.deinit();}}return error;
}
// All successful builds commit a revision. The asset session takes its
// candidate at that same point.
fn buildSources(writer:blot_io::Writer,opened:OpenProject&,id:u32,sources:const Source[:],assets:blot_backend_native_assets::Candidate?,profile:blot_phase_profile::Profile&)->bool,Error {
    var merged:Source[>..]=[];let complete_sources=composeSources(sources,assets,merged);
    var snapshot,error=blot_reuse_revision_inputs::initWithSources(opened.options_owner.options(),complete_sources);if error!=blot_error::Error.none {if error==blot_error::Error.out_of_memory {return false,error;}return false,operationFailure(writer,opened,id,blot_error::error_name(error),"Compiler operation failed");}
    let committed,failure=buildSnapshot(writer,opened,id,assets,profile,snapshot);snapshot.deinit();return committed,failure;
}
fn buildSnapshot(writer:blot_io::Writer,opened:OpenProject&,id:u32,assets:blot_backend_native_assets::Candidate?,profile:blot_phase_profile::Profile&,snapshot:blot_reuse_revision_inputs::Snapshot&)->bool,Error {
    var allow_reuse=true;
    loop {
        var candidate=Retained{..};var reused=false;
        var preparation,error=opened.prepare(snapshot,candidate,allow_reuse,reused);
        if error!=blot_error::Error.none {candidate.deinit();if error==blot_error::Error.out_of_memory {return false,error;}return false,operationFailure(writer,opened,id,blot_error::error_name(error),"Compiler operation failed");}
        var retry=false;
        let committed,failure=buildPrepared(writer,opened,id,assets,profile,preparation,reused,retry);
        if committed && candidate.source.lease!=0 {
            if reused {candidate.completeFrom(opened.checked);}
            match preparation {ready payload=>{
                opened.core.deinit();opened.checked.deinit();
                opened.checked=candidate;candidate=Retained{..};
                opened.core=payload.value;preparation=blot_reuse_partial_dependency::Preparation.inactive;
            },_=>{abort("committed revision requires prepared Core");}}
        }
        preparation.deinit();candidate.deinit();
        if !retry {return committed,failure;}
        allow_reuse=false;
    }
}
fn buildPrepared(writer:blot_io::Writer,opened:OpenProject&,id:u32,assets:blot_backend_native_assets::Candidate?,profile:blot_phase_profile::Profile&,preparation:Preparation&,reused:bool,retry:bool&)->bool,Error {
    match preparation {
        inactive=>{return false,blot_error::Error.missing_rejection_diagnostic;},
        rejected payload=>{let diagnostic,error=issue(payload.value,opened.entry);if error!=blot_error::Error.none {return false,error;}return false,reject(writer,id,opened.revisions,diagnostic);},
        ready payload=>{
            let timing=blot_phase_profile::enter(blot_phase_profile::Phase.backend);var result,error=payload.value.emit();timing.exit();if error!=blot_error::Error.none {return false,error;}
            if reused && result.result.compiled.failed {result.deinit();retry=true;return false,blot_error::Error.none;}
            let committed,error=buildEmitted(writer,opened,id,assets,profile,result);result.deinit();return committed,error;
        }
    }
}
fn buildEmitted(writer:blot_io::Writer,opened:OpenProject&,id:u32,assets:blot_backend_native_assets::Candidate?,profile:blot_phase_profile::Profile&,result:const Emission&)->bool,Error {
    if result.result.compiled.failed {let diagnostic,error=issue(result,opened.entry);if error!=blot_error::Error.none {return false,error;}return false,reject(writer,id,opened.revisions,diagnostic);}
    let wasm:const u8[:]=result.result.compiled.bytes;var phases=blot_phase_profile::Record{..};if profile.key.slot!=0 {phases=profile.record();}
    let stats=BuildStats{frontend:result.result.stats,sourceBytes:result.source_bytes,freshModules:result.fresh_modules,cachedModules:result.cached_modules,emittedFunctions:result.result.compiled.emitted_functions,phaseProfile:phases};
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
