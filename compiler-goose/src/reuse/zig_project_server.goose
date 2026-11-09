// One opened project and ordered transaction stream per compiler process.
// The pinned public project protocol name/version are preserved independently
// of guest ABI/session and the private copied-worker protocol.
namespace blot_reuse_zig_project_server;
import std;
import json;
import reuse.zig_project_frames;
import reuse.project;
import reuse.project_check;
import reuse.revision_inputs;
import reuse.source_overlays;
import reuse.retained_revision;
import reuse.partial_dependency;
import reuse.dependency_cli;
import reuse.dependency_project_loader;
import reuse.dependency_payload;
import reuse.dependency_format;
import reuse.restart_cache;
import reuse.artifact_capture;
import reuse.editor_completion;
import reuse.dispatch_explanation;
import backend.backend_checkpoint;
import backend.native_assets;
import backend.storage_plan;
import compilation_tier;
import execution_policy;
import parse.ast;
import parse.lexer;
import check.diagnostic_location;
import phase_profile;
import support.error;
import support.option;
import support.native;
import support.io;
import support.json;
import support.json_adapters;
import driver.project_executor;
import .zig_project_server_inputs;
import .zig_project_server_lifecycle;
import .zig_project_server_build;
import .zig_project_server_completion;
import .zig_project_server_loop;
type Error=blot_error::Error;
type Digest=u8[32];
type Text=blot_support::Option<const u8[:]>;
type Options=blot_reuse_project::Options;
type Source=blot_reuse_source_overlays::Source;
type Emission=blot_reuse_partial_dependency::Result;
type Owner=blot_reuse_dependency_payload::Owner;
type Writer=blot_json::Writer;
let default_codegen_workers:u8=4;
let protocol_version:u32=1;
let epoch:const u8[:]="1";
enum RequestKind {open,build,close,checkpoint,complete}
struct SourceRange {path:const u8[:],start:u32,length:u32,deleted:bool=false}
struct Request {
    kind:RequestKind,id:u32,snapshot:blot_support::Option<u32> =blot_support::none<u32>(),filename:Text=blot_support::none<const u8[:]>(),position:blot_support::Option<u32> =blot_support::none<u32>(),version:blot_support::Option<u32> =blot_support::none<u32>(),epoch:Text=blot_support::none<const u8[:]>(),revision:blot_support::Option<u64> =blot_support::none<u64>(),entry:Text=blot_support::none<const u8[:]>(),prelude:Text=blot_support::none<const u8[:]>(),stdRoot:Text=blot_support::none<const u8[:]>(),imports:const blot_reuse_project::Alias[:]=default<const blot_reuse_project::Alias[:]>(),dependencies:Text=blot_support::none<const u8[:]>(),
    profileBackend:bool=false,profileTrace:bool=false,explainAllocations:bool=false,codegenTier:blot_compilation_tier::Tier=blot_compilation_tier::Tier.optimized,storage:blot_support::Option<blot_backend_storage_plan::Budgets> =blot_support::none<blot_backend_storage_plan::Budgets>(),shareMachineCode:bool=false,profileMemory:bool=false,requireCollectorFree:bool=false,codegenWorkers:u8=default_codegen_workers,checkpoint:bool=false,sources:const SourceRange[:]=default<const SourceRange[:]>(),nativeAssets:blot_support::Option<blot_backend_native_assets::Options> =blot_support::none<blot_backend_native_assets::Options>(),assetSources:const SourceRange[:]=default<const SourceRange[:]>(),
}
fn validPath(path:const u8[:])->bool {if path.len==0 || path[0]!='/' {return false;}for byte in path {if byte==0 {return false;}}return true;}
fn utf8(bytes:const u8[:])->bool {var at:i64=0;while at<bytes.len {let width=blot_parse_lexer::utf8_width(bytes[at]);if width==0 || width>bytes.len-at {return false;}let point,error=blot_parse_lexer::decode_point(bytes[at..at+width]);if error!=blot_error::Error.none {return false;}at+=width;}return true;}
reusable[] var source_runs:Source[>..]=[];
fn sourceViews(ranges:const SourceRange[:],payload:const u8[:])->Source[:],Error {return rangeViews(ranges,payload,0,true);}
fn rangeViews(ranges:const SourceRange[:],payload:const u8[:],start:i64,require_utf8:bool)->Source[:],Error {
    if ranges.len>4096 {return default<Source[:]>(),blot_error::Error.source_limit;}if start<0 || start>payload.len {return default<Source[:]>(),blot_error::Error.invalid_sources;}var end=start;for range in ranges {if !validPath(range.path) || range.start!=end || range.length>payload.len-end || (range.deleted && range.length!=0) {return default<Source[:]>(),blot_error::Error.invalid_sources;}end+=range.length;if require_utf8 && !utf8(payload[range.start..end]) {return default<Source[:]>(),blot_error::Error.invalid_sources;}}if end!=payload.len {return default<Source[:]>(),blot_error::Error.invalid_sources;}
    let result=source_runs.alloc_slice(ranges.len);for range,index in ranges {var contents=blot_support::none<const u8[:]>();if !range.deleted {contents=blot_support::some<const u8[:]>(payload[range.start..range.start+range.length]);}result[index]=Source{path:range.path,contents:contents};}return result,blot_error::Error.none;
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
fn releaseSources(sources:Source[:]) {if sources.len!=0 {source_runs.free_slice(sources);}}
fn validateOpen(request:Request)->Options,Error {
    if !request.version.present || request.version.value!=protocol_version {return Options{..},blot_error::Error.version_mismatch;}if request.codegenWorkers==0 || request.codegenWorkers>16 {return Options{..},blot_error::Error.invalid_open;}if request.storage.present && !request.storage.value.valid() {return Options{..},blot_error::Error.invalid_open;}if !request.entry.present || !validPath(request.entry.value) || request.epoch.present || request.revision.present {return Options{..},blot_error::Error.invalid_open;}
    for path in [request.prelude,request.stdRoot,request.dependencies] {if path.present && !validPath(path.value) {return Options{..},blot_error::Error.invalid_open;}}
    for alias,index in request.imports {if alias.prefix.len==0 || alias.prefix[alias.prefix.len-1]!='/' || !validPath(alias.root) {return Options{..},blot_error::Error.invalid_open;}for byte in alias.prefix {if byte==0 {return Options{..},blot_error::Error.invalid_open;}}for old in request.imports[..index] {if old.prefix==alias.prefix {return Options{..},blot_error::Error.invalid_open;}}}return Options{prelude_path:request.prelude,std_root:request.stdRoot,aliases:request.imports,..},blot_error::Error.none;
}
struct OpenProject {profile_trace:bool=false,allocation_owner:u64=0,entry:const u8[:]=default<const u8[:]>(),options_owner:blot_reuse_revision_inputs::Snapshot=blot_reuse_revision_inputs::Snapshot{..},session:blot_reuse_retained_revision::Session=blot_reuse_retained_revision::Session{..},assets:blot_support::Option<blot_backend_native_assets::Session> =blot_support::none<blot_backend_native_assets::Session>(),cache_file:blot_support::Option<blot_reuse_restart_cache::File> =blot_support::none<blot_reuse_restart_cache::File>(),cache_loaded:bool=false,checkpoint_pending:bool=false,seed_pending:bool=false,last_write:blot_support::Option<blot_reuse_restart_cache::Report> =blot_support::none<blot_reuse_restart_cache::Report>(),saved_revision:u64=0,owner:Owner=Owner{..}}
fn deinit(self_:OpenProject&) {self_.session.deinit();if self_.assets.present {self_.assets.value.deinit();}if self_.cache_file.present {self_.cache_file.value.deinit();}self_.options_owner.deinit();self_.owner.deinit();self_=OpenProject{..};}
struct CheckpointEncoding {session:blot_reuse_retained_revision::Session,compiler:Digest}
fn encode(self_:CheckpointEncoding&,part:blot_reuse_restart_cache::Part,checkpoint:Text,report:blot_reuse_restart_cache::Report&)->blot_support::Option<u8[:]> {
    match part {checkpoint=>{var notes=blot_backend_backend_checkpoint::Report{..};let bytes,error=self_.session.encodeCheckpoint(self_.compiler,notes);report.semantic_over_limit=notes.semantic_over_limit;if error!=blot_error::Error.none {report.over_limit=report.over_limit || error==blot_error::Error.artifact_limit;return blot_support::none<u8[:]>();}return blot_support::some(bytes);},output=>{let bytes,error=self_.session.encodeRestored(self_.compiler,checkpoint);if error!=blot_error::Error.none {report.over_limit=report.over_limit || error==blot_error::Error.artifact_limit;return blot_support::none<u8[:]>();}return bytes;},seed=>{let bytes,error=self_.session.encodeSeed(self_.compiler);if error!=blot_error::Error.none {report.over_limit=report.over_limit || error==blot_error::Error.artifact_limit;return blot_support::none<u8[:]>();}return bytes;}}
}
fn release(self_:CheckpointEncoding&,bytes:u8[:]) {blot_reuse_dependency_format::release(bytes);}
fn persist(self_:OpenProject&,joined:bool) {let session .= self_.session.state();if self_.saved_revision==session.revisions || !session.current.present || !self_.cache_file.present {return;}var producer=CheckpointEncoding{self_.session,self_.cache_file.value.compiler};var result=blot_reuse_restart_cache::Persisted.failed;if joined {result=self_.cache_file.value.persistJoined(producer);}else {result=self_.cache_file.value.persist(producer);}// A queued transaction is not yet a successful filesystem publication.
    if result!=blot_reuse_restart_cache::Persisted.failed && blot_reuse_restart_cache::requestCacheActive()==0 {self_.saved_revision=session.revisions;}}
enum IssueDetails {bytes{value:const u8[:]},explanation{value:const blot_reuse_dispatch_explanation::Explanation&}}
fn jsonStringify(self_:IssueDetails,writer:Writer&)->Error {match self_ {bytes payload=>{return writer.write(blot_json::Raw{payload.value});},explanation payload=>{writer.beginObject();writer.field("explanation",payload.value);writer.endObject();return writer.failure;}}}
struct Diagnostic {filename:const u8[:],stage:const u8[:],code:const u8[:],start:u32=0,end:u32=0,message:const u8[:],offset_encoding:const u8[:]="utf8_bytes",utf16:blot_support::Option<blot_parse_ast::Span> =blot_support::none<blot_parse_ast::Span>(),details:blot_support::Option<IssueDetails> =blot_support::none<IssueDetails>(),related:blot_support::Option<blot_check_diagnostic_location::Location> =blot_support::none<blot_check_diagnostic_location::Location>(),origins:const blot_check_diagnostic_location::Origin[:]=default<const blot_check_diagnostic_location::Origin[:]>()}
fn jsonStringify(self_:Diagnostic,writer:Writer&)->Error {writer.beginObject();writer.field("filename",self_.filename);writer.field("stage",self_.stage);writer.field("code",self_.code);writer.field("start",self_.start);writer.field("end",self_.end);writer.field("message",self_.message);writer.field("offset_encoding",self_.offset_encoding);writer.field("utf16",self_.utf16);writer.field("details",self_.details);if self_.related.present {writer.field("related",self_.related.value);}if self_.origins.len!=0 {writer.field("origins",self_.origins);}writer.endObject();return writer.failure;}
fn issueFilename(result:const Emission&,entry:const u8[:])->const u8[:] {
    if result.diagnostic_filename.present {return result.diagnostic_filename.value;}
    return entry;
}
fn issue(result:const Emission&,entry:const u8[:])->Diagnostic,Error {
    let filename=issueFilename(result,entry);if result.result.diagnostic.present {let item=result.result.diagnostic.value;var diagnostic=Diagnostic{filename:filename,stage:item.stage,code:item.code,start:item.start,end:item.end,message:item.message,..};if item.publication.present {diagnostic.utf16=item.publication.value.utf16;if item.publication.value.forwarded {diagnostic.details=blot_support::some<IssueDetails>(IssueDetails.bytes{item.publication.value.details_json});}}return diagnostic,blot_error::Error.none;}
    if result.result.compiled.diagnostic.present {let item=result.result.compiled.diagnostic.value;var code:const u8[:]=default<const u8[:]>();match item.code {const for <N,V> in variants<blot_backend_core_backend::Code> {V=>{code=N;},}}var diagnostic=Diagnostic{filename:filename,stage:"emit",code:code,start:item.span.start,end:item.span.end,message:item.message(),origins:result.origins.entries,..};if item.related.present {if !result.related_filename.present {return default<Diagnostic>(),blot_error::Error.missing_related_filename;}diagnostic.related=blot_support::some(blot_check_diagnostic_location::init(result.related_filename.value,item.related.value.span));}let explanation .= result.result.compiled.explanation;if explanation {diagnostic.details=blot_support::some<IssueDetails>(IssueDetails.explanation{explanation});}return diagnostic,blot_error::Error.none;}return default<Diagnostic>(),blot_error::Error.missing_rejection_diagnostic;
}
fn encodeMetadata<T>(metadata:T,bytes:u8[>..]&)->Error {return blot_json::toBytes(metadata,bytes);}
fn reply<T>(writer:blot_io::Writer,metadata:T,payload:const u8[:])->Error {var bytes:u8[>..]=[];let error=encodeMetadata(metadata,bytes);if error!=blot_error::Error.none {return error;}return blot_reuse_zig_project_frames::write(writer,bytes[..],payload);}
struct RejectionReply {kind:const u8[:]="build",id:u32,epoch:const u8[:]=epoch,revision:u64,success:bool=false,diagnostics:Diagnostic[1],attemptStats:blot_support::Option<blot_reuse_retained_revision::Stats>}
fn reject(writer:blot_io::Writer,id:u32,revision:u64,diagnostic:Diagnostic,attempt:blot_support::Option<blot_reuse_retained_revision::Stats>)->Error {return reply(writer,RejectionReply{id:id,revision:revision,diagnostics:[diagnostic],attemptStats:attempt,..},[]);}
fn operationFailure(writer:blot_io::Writer,opened:OpenProject&,id:u32,code:const u8[:],message:const u8[:],attempt:blot_support::Option<blot_reuse_retained_revision::Stats>)->Error {return reject(writer,id,opened.session.state().revisions,Diagnostic{filename:opened.entry,stage:"build-project",code:code,message:message,..},attempt);}
