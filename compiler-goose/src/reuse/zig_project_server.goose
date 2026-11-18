// One owned project and serial build stream per child process. Each build
// resolves current inputs and emits a complete module.
// A revision is committed only after its complete reply has been encoded and
// bounded. Failure delivering a committed reply terminates this process.
namespace blot_reuse_zig_project_server;
import std;
import json;
import reuse.zig_project_frames;
import reuse.project;
import reuse.project_check;
import reuse.revision_inputs;
import reuse.source_overlays;
import reuse.partial_dependency;
import reuse.dependency_cli;
import reuse.dependency_consumer;
import reuse.dependency_project_loader;
import reuse.dependency_payload;
import reuse.frozen_dependency;
import reuse.editor_completion;
import backend.native_assets;
import execution_policy;
import parse.ast;
import parse.lexer;
import phase_profile;
import support.error;
import support.option;
import support.native;
import support.io;
import support.json;
import support.json_adapters;
import .zig_project_server_inputs;
import .zig_project_server_build;
import .zig_project_server_completion;
import .zig_project_server_loop;
type Error=blot_error::Error;
type Digest=u8[32];
type Text=blot_support::Option<const u8[:]>;
type Options=blot_reuse_project::Options;
type Source=blot_reuse_source_overlays::Source;
type Emission=blot_reuse_partial_dependency::Result;
type Preparation=blot_reuse_partial_dependency::Preparation;
type Retained=blot_reuse_partial_dependency::Retained;
type Prepared=blot_reuse_partial_dependency::Prepared;
type Frozen=blot_reuse_frozen_dependency::FrozenDependency;
type OwnedFrozen=blot_reuse_dependency_payload::Owned<Frozen>;
type Owner=blot_reuse_dependency_payload::Owner;
type Writer=blot_json::Writer;
type Policy=blot_execution_policy::Policy;
let protocol_version:u32=1;
// Channel-local: a process permits one open and no reopening.
let epoch:const u8[:]="1";
enum RequestKind {open,build,close,complete}
struct SourceRange {path:const u8[:],start:u32,length:u32,deleted:bool=false}
// Pen forwards these from a program's settings. Byte budgets are positive
// multiples of 16 and the owner capacity is positive.
struct StorageBudgets {temporaryBytes:u32=1048576,growerBytes:u32=1048576,persistentBytes:u32=1048576,transportBytes:u32=2097152,ownerCapacity:u32=4096}
fn valid(self_:StorageBudgets)->bool {for value in [self_.temporaryBytes,self_.growerBytes,self_.persistentBytes,self_.transportBytes] {if value==0 || value%16!=0 {return false;}}return self_.ownerCapacity!=0;}
struct Request {
    kind:RequestKind,id:u32,snapshot:blot_support::Option<u32> =blot_support::none<u32>(),filename:Text=blot_support::none<const u8[:]>(),position:blot_support::Option<u32> =blot_support::none<u32>(),version:blot_support::Option<u32> =blot_support::none<u32>(),epoch:Text=blot_support::none<const u8[:]>(),revision:blot_support::Option<u64> =blot_support::none<u64>(),entry:Text=blot_support::none<const u8[:]>(),prelude:Text=blot_support::none<const u8[:]>(),stdRoot:Text=blot_support::none<const u8[:]>(),imports:const blot_reuse_project::Alias[:]=default<const blot_reuse_project::Alias[:]>(),dependencies:Text=blot_support::none<const u8[:]>(),
    profileBackend:bool=false,profileTrace:bool=false,
    // Accepted and validated; the direct backend lays out its own regions.
    storage:blot_support::Option<StorageBudgets> =blot_support::none<StorageBudgets>(),sources:const SourceRange[:]=default<const SourceRange[:]>(),nativeAssets:blot_support::Option<blot_backend_native_assets::Options> =blot_support::none<blot_backend_native_assets::Options>(),assetSources:const SourceRange[:]=default<const SourceRange[:]>(),
}
fn validPath(path:const u8[:])->bool {if path.len==0 || path[0]!='/' {return false;}for byte in path {if byte==0 {return false;}}return true;}
fn utf8(bytes:const u8[:])->bool {var at:i64=0;while at<bytes.len {let width=blot_parse_lexer::utf8_width(bytes[at]);if width==0 || width>bytes.len-at {return false;}let point,error=blot_parse_lexer::decode_point(bytes[at..at+width]);if error!=blot_error::Error.none {return false;}at+=width;}return true;}
fn sourceViews(ranges:const SourceRange[:],payload:const u8[:],result:Source[>..]&)->Error {return rangeViews(ranges,payload,0,true,result);}
// Only invocation-local headers borrow the live request; snapshots own their bytes.
fn rangeViews(ranges:const SourceRange[:],payload:const u8[:],start:i64,require_utf8:bool,result:Source[>..]&)->Error {
    assert(result.len==0);
    if ranges.len>4096 {return blot_error::Error.source_limit;}if start<0 || start>payload.len {return blot_error::Error.invalid_sources;}var end=start;for range in ranges {if !validPath(range.path) || range.start!=end || range.length>payload.len-end || (range.deleted && range.length!=0) {return blot_error::Error.invalid_sources;}end+=range.length;if require_utf8 && !utf8(payload[range.start..end]) {return blot_error::Error.invalid_sources;}}if end!=payload.len {return blot_error::Error.invalid_sources;}
    for range in ranges {
        if range.deleted {result.push(Source{path:range.path,contents:blot_support::none<const u8[:]>()});}
        else {result.push(Source{path:range.path,contents:blot_support::Option<const u8[:]> {true,payload[range.start..range.start+range.length]}});}
    }
    return blot_error::Error.none;
}
// Composition borrows byte payloads; the revision snapshot performs the owned copy.
fn composeSources(sources:const Source[:],assets:const blot_backend_native_assets::Candidate?,merged:Source[>..]&)->const Source[:] {
    if assets {
        merged.append(assets.sources.items);
        merged.append(sources);
        return merged[..];
    }
    return sources;
}
fn validateOpen(request:Request)->Options,Error {
    if !request.version.present || request.version.value!=protocol_version {return Options{..},blot_error::Error.version_mismatch;}if request.storage.present && !request.storage.value.valid() {return Options{..},blot_error::Error.invalid_open;}if !request.entry.present || !validPath(request.entry.value) || request.epoch.present || request.revision.present {return Options{..},blot_error::Error.invalid_open;}
    for path in [request.prelude,request.stdRoot,request.dependencies] {if path.present && !validPath(path.value) {return Options{..},blot_error::Error.invalid_open;}}
    for alias,index in request.imports {if alias.prefix.len==0 || alias.prefix[alias.prefix.len-1]!='/' || !validPath(alias.root) {return Options{..},blot_error::Error.invalid_open;}for byte in alias.prefix {if byte==0 {return Options{..},blot_error::Error.invalid_open;}}for old in request.imports[..index] {if old.prefix==alias.prefix {return Options{..},blot_error::Error.invalid_open;}}}return Options{prelude_path:request.prelude,std_root:request.stdRoot,aliases:request.imports,..},blot_error::Error.none;
}
// `seed` holds the checked modules of the open's dependency bundle, and
// `seed_settings` the settings key they were checked with. A build takes the
// modules whose sources are unchanged and checks the rest. `revisions` counts
// the successful builds so far; each one is a revision.
struct OpenProject {
    profile_trace:bool=false,profile_backend:bool=false,entry:const u8[:]=default<const u8[:]>(),
    options_owner:blot_reuse_revision_inputs::Snapshot=blot_reuse_revision_inputs::Snapshot{..},
    seed:blot_support::Option<OwnedFrozen> =blot_support::none<OwnedFrozen>(),seed_settings:Digest=[0;32],
    assets:blot_support::Option<blot_backend_native_assets::Session> =blot_support::none<blot_backend_native_assets::Session>(),
    policy:Policy=Policy{..},revisions:u64=0,owner:Owner=Owner{..},
    checked:Retained=Retained{..},core:Prepared=Prepared{..},
}
fn deinit(self_:OpenProject&) {self_.core.deinit();self_.checked.deinit();if self_.seed.present {self_.seed.value.deinit();}if self_.assets.present {self_.assets.value.deinit();}self_.options_owner.deinit();self_.owner.deinit();self_=OpenProject{..};}
fn initOpen(request:Request,compiler:Digest,policy:Policy)->OpenProject,Error {
    let raw,error=validateOpen(request);if error!=blot_error::Error.none {return OpenProject{..},error;}var result=OpenProject{profile_trace:request.profileTrace,profile_backend:request.profileBackend,policy:policy,..};
    if request.nativeAssets.present {let assets,error=blot_backend_native_assets::init(request.nativeAssets.value);if error!=blot_error::Error.none {result.deinit();return OpenProject{..},error;}result.assets=blot_support::some(assets);}
    let owner,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {result.deinit();return OpenProject{..},error;}result.owner=owner;let entry,error=result.owner.copy(request.entry.value);if error!=blot_error::Error.none {result.deinit();return OpenProject{..},error;}result.entry=entry;
    let options,error=blot_reuse_revision_inputs::init(raw);if error!=blot_error::Error.none {result.deinit();return OpenProject{..},error;}result.options_owner=options;
    if request.dependencies.present {
        // Wire admission uses the artifact's canonical settings. Builds keep
        // the original absolute options and re-resolve them, so a retargeted
        // symlink stops the bundle's modules being taken.
        var canonical,error=blot_reuse_dependency_cli::initCanonical(raw);if error!=blot_error::Error.none {result.deinit();return OpenProject{..},error;}let actual=canonical.view(raw);
        var files=blot_reuse_project::FileInputs{..};var bytes:u8[>..<]=[];let error=files.read(request.dependencies.value,536870912,bytes);if error!=blot_error::Error.none {canonical.deinit();result.deinit();return OpenProject{..},error;}
        var stats=blot_reuse_dependency_project_loader::Stats{..};result.seed_settings=blot_reuse_dependency_cli::settings(actual);let seed,error=blot_reuse_dependency_project_loader::load(files,bytes[..],compiler,result.seed_settings,actual,stats);canonical.deinit();if error!=blot_error::Error.none {result.deinit();return OpenProject{..},error;}result.seed=blot_support::some(seed);
    }
    return result,blot_error::Error.none;
}
// Lowering is serial here whatever the policy asks.
fn configure(self_:const OpenProject&,source:blot_reuse_project::Project&) {
    var width=self_.policy.frontend_workers;
    if width==0 {
        width=1;
        if source.units.len>=16 && source.source_bytes>=65536 {
            var cap:u8=4;
            if source.source_bytes>=524288 {cap=8;}
            width=min(cap,blot_native::available_workers());
        }
    }
    source.lowering=blot_reuse_project::Lowering{io:true,workers:1};
    source.checking=blot_reuse_project::Lowering{io:true,workers:width};
}
// Loads, checks and lowers this revision's sources. With a dependency bundle,
// the bundle's unchanged modules are taken as checked; a rejection there is
// reported by the fresh check of every module.
fn prepare(self_:OpenProject&,snapshot:blot_reuse_revision_inputs::Snapshot&,candidate:Retained&,allow_reuse:bool,reused:bool&)->Preparation,Error {
    if self_.seed.present {let seeded,error=prepareSeeded(self_,snapshot);if error!=blot_error::Error.none {return blot_reuse_partial_dependency::Preparation.inactive,error;}match seeded {ready payload=>{return seeded,blot_error::Error.none;},_=>{var unused=seeded;unused.deinit();}}}
    var provider=snapshot.provider();let loaded,error=blot_reuse_project::loadWithParseWorkers(self_.entry,snapshot.options(),provider,self_.policy.frontend_workers);if error!=blot_error::Error.none {return blot_reuse_partial_dependency::Preparation.inactive,error;}var source=loaded;self_.configure(source);
    if self_.seed.present {
        let empty=Frozen{..};let value,failure=blot_reuse_partial_dependency::prepareProject(source,self_.entry,blot_support::none<const u8[:]>(),empty);source.deinit();return value,failure;
    }
    if allow_reuse && self_.core.units.len!=0 {
        let retained,failure=blot_reuse_partial_dependency::prepareRetainedProject(source,self_.checked,self_.core,candidate);
        if failure!=blot_error::Error.none {source.deinit();return blot_reuse_partial_dependency::Preparation.inactive,failure;}
        match retained {ready=>{reused=true;source.deinit();return retained,blot_error::Error.none;},_=>{var unused=retained;unused.deinit();}}
    }
    let value,failure=blot_reuse_partial_dependency::prepareRetainableProject(source,self_.entry,candidate);source.deinit();return value,failure;
}
// Inactive when the bundle cannot be used for this revision; only running out
// of memory is an error.
fn prepareSeeded(self_:OpenProject&,snapshot:blot_reuse_revision_inputs::Snapshot&)->Preparation,Error {
    var canonical,error=blot_reuse_dependency_cli::initCanonical(snapshot.options());if error!=blot_error::Error.none {if error==blot_error::Error.out_of_memory {return blot_reuse_partial_dependency::Preparation.inactive,error;}return blot_reuse_partial_dependency::Preparation.inactive,blot_error::Error.none;}
    let same=self_.seed_settings==blot_reuse_dependency_cli::settings(canonical.view(snapshot.options()));canonical.deinit();if !same {return blot_reuse_partial_dependency::Preparation.inactive,blot_error::Error.none;}
    let reuse,error=snapshot.reusableModules(self_.seed.value.value);if error!=blot_error::Error.none {return blot_reuse_partial_dependency::Preparation.inactive,error;}if !reuse.present {return blot_reuse_partial_dependency::Preparation.inactive,blot_error::Error.none;}
    var provider=snapshot.provider();let loaded,error=blot_reuse_project::loadCompiledMixedReadOnly(self_.entry,snapshot.options(),self_.seed.value.value,provider,reuse.value);blot_reuse_revision_inputs::releaseMask(reuse.value);if error!=blot_error::Error.none {if error==blot_error::Error.out_of_memory {return blot_reuse_partial_dependency::Preparation.inactive,error;}return blot_reuse_partial_dependency::Preparation.inactive,blot_error::Error.none;}
    var source=loaded;self_.configure(source);if source.diagnostics.len!=0 {source.deinit();return blot_reuse_partial_dependency::Preparation.inactive,blot_error::Error.none;}
    let value,failure=blot_reuse_partial_dependency::prepareProject(source,self_.entry,blot_support::none<const u8[:]>(),self_.seed.value.value);source.deinit();if failure!=blot_error::Error.none {if failure==blot_error::Error.out_of_memory {return blot_reuse_partial_dependency::Preparation.inactive,failure;}return blot_reuse_partial_dependency::Preparation.inactive,blot_error::Error.none;}return value,blot_error::Error.none;
}
// `details` is a frontend publication's forwarded JSON.
struct Diagnostic {filename:const u8[:],stage:const u8[:],code:const u8[:],start:u32=0,end:u32=0,message:const u8[:],offset_encoding:const u8[:]="utf8_bytes",utf16:blot_support::Option<blot_parse_ast::Span> =blot_support::none<blot_parse_ast::Span>(),details:blot_support::Option<blot_reuse_dependency_consumer::Details> =blot_support::none<blot_reuse_dependency_consumer::Details>()}
fn issue(result:const Emission&,entry:const u8[:])->Diagnostic,Error {
    let filename=blot_reuse_partial_dependency::diagnosticFilename(result,entry);if result.result.diagnostic.present {let item=result.result.diagnostic.value;var diagnostic=Diagnostic{filename:filename,stage:item.stage,code:item.code,start:item.start,end:item.end,message:item.message,..};if item.publication.present {diagnostic.utf16=item.publication.value.utf16;if item.publication.value.forwarded {diagnostic.details=blot_support::some(blot_reuse_dependency_consumer::Details{item.publication.value.details_json});}}return diagnostic,blot_error::Error.none;}
    if result.result.compiled.failed {let item=result.result.compiled.diagnostic;var code:const u8[:]=default<const u8[:]>();match item.code {const for <N,V> in variants<blot_compile::Code> {V=>{code=N;},}}return Diagnostic{filename:filename,stage:"emit",code:code,start:item.span.start,end:item.span.end,message:result.result.compiled.text(),..},blot_error::Error.none;}
    return default<Diagnostic>(),blot_error::Error.missing_rejection_diagnostic;
}
fn encodeMetadata<T>(metadata:T,bytes:u8[>..]&)->Error {return blot_json::toBytes(metadata,bytes);}
fn reply<T>(writer:blot_io::Writer,metadata:T,payload:const u8[:])->Error {var bytes:u8[>..]=[];let error=encodeMetadata(metadata,bytes);if error!=blot_error::Error.none {return error;}return blot_reuse_zig_project_frames::write(writer,bytes[..],payload);}
struct RejectionReply {kind:const u8[:]="build",id:u32,epoch:const u8[:]=epoch,revision:u64,success:bool=false,diagnostics:Diagnostic[1]}
fn reject(writer:blot_io::Writer,id:u32,revision:u64,diagnostic:Diagnostic)->Error {return reply(writer,RejectionReply{id:id,revision:revision,diagnostics:[diagnostic],..},[]);}
fn operationFailure(writer:blot_io::Writer,opened:OpenProject&,id:u32,code:const u8[:],message:const u8[:])->Error {return reject(writer,id,opened.revisions,Diagnostic{filename:opened.entry,stage:"build-project",code:code,message:message,..});}
