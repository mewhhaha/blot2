// Request metadata is decoded into owned typed runs. Payload views use one
// process-global packet buffer and are released before the next read.
namespace blot_reuse_zig_project_server;
import .zig_project_server;
import support.process_pool;
var request_bytes:u8[>..]=[];
struct Hello {kind:const u8[:]="hello",protocol:const u8[:]="blot-zig-project",version:u32=protocol_version,compilerIdentity:const u8[:],capabilities:const TextSlice[:],maxFrameBytes:i64=blot_reuse_zig_project_frames::max_frame_bytes}
struct OpenReply {kind:const u8[:]="open",id:u32,epoch:const u8[:]=epoch,revision:u64=0}
struct CloseReply {kind:const u8[:]="close",id:u32,epoch:const u8[:]=epoch,revision:u64}
struct CheckpointReply {kind:const u8[:]="checkpoint",id:u32,epoch:const u8[:]=epoch,revision:u64,success:bool,code:Text=blot_support::none<const u8[:]>()}
fn jsonStringify(self_:CheckpointReply,writer:Writer&)->Error {writer.beginObject();writer.field("kind",self_.kind);writer.field("id",self_.id);writer.field("epoch",self_.epoch);writer.field("revision",self_.revision);writer.field("success",self_.success);if self_.code.present {writer.field("code",self_.code.value);}writer.endObject();return writer.failure;}
fn validateFollowing(request:Request,opened:OpenProject&)->Error {
    if request.storage.present || request.nativeAssets.present || request.version.present || request.entry.present || request.prelude.present || request.stdRoot.present || request.imports.len!=0 || request.dependencies.present || request.profileBackend || request.profileTrace || request.explainAllocations || request.codegenTier!=blot_compilation_tier::Tier.optimized || request.shareMachineCode || request.profileMemory || request.requireCollectorFree || request.codegenWorkers!=default_codegen_workers || request.checkpoint {return blot_error::Error.invalid_request;}
    if !request.epoch.present || request.epoch.value!=epoch || !request.revision.present || request.revision.value!=opened.session.state().revisions {return blot_error::Error.revision_mismatch;}return blot_error::Error.none;
}
fn checkpointReply(writer:blot_io::Writer,owner:OpenProject&,request:Request,compiler:Digest)->Error {
    var bytes,error=owner.checkpointBytes(compiler);if error!=blot_error::Error.none {return reply(writer,CheckpointReply{id:request.id,revision:owner.session.state().revisions,success:false,code:blot_support::some<const u8[:]>(blot_error::error_name(error)),..},[]);}
    if bytes.value.len>blot_reuse_zig_project_frames::max_frame_bytes-1024 {let __cleanup_result_1_0: Error = reply(writer,CheckpointReply{id:request.id,revision:owner.session.state().revisions,success:false,code:blot_support::some<const u8[:]>("checkpoint_limit"),..},[]); {bytes.deinit();} return __cleanup_result_1_0;}let __cleanup_result_2_0: Error = reply(writer,CheckpointReply{id:request.id,revision:owner.session.state().revisions,success:true,..},bytes.value); {bytes.deinit();} return __cleanup_result_2_0;
 {bytes.deinit();} }
fn dispatch<E>(executor:E&,reader:blot_io::Reader,writer:blot_io::Writer,compiler:Digest,cache_root:Text,policy:blot_execution_policy::Policy,opened:blot_support::Option<OpenProject>&,request:Request,frame:blot_reuse_zig_project_frames::RequestFrame)->bool,Error {
    if request.kind!=RequestKind.complete && (request.snapshot.present || request.filename.present || request.position.present) {return false,blot_error::Error.invalid_request;}
    if request.kind==RequestKind.open {
        if request.sources.len!=0 || request.assetSources.len!=0 || request.checkpoint!=(frame.payload().len!=0) {return false,blot_error::Error.invalid_open;}if opened.present {return false,blot_error::Error.already_open;}let owner,error=initOpen(request,compiler,frame.payload(),cache_root);if error!=blot_error::Error.none {return false,error;}opened=blot_support::some(owner);let session .= opened.value.session.state();session.policy.semantic_workers=policy.semantic_workers;session.policy.frontend_workers=policy.frontend_workers;session.policy.semantic_components=policy.semantic_components;let error=reply(writer,OpenReply{id:request.id,..},[]);return false,error;
    }
    if !opened.present {return false,blot_error::Error.not_open;}let owner .= opened.value;let error=validateFollowing(request,owner);if error!=blot_error::Error.none {return false,error;}
    if request.kind==RequestKind.complete {
        if !request.snapshot.present || !request.filename.present || !request.position.present || request.filename.value.len>4096 || !validPath(request.filename.value) {return false,blot_error::Error.invalid_completion_request;}if request.assetSources.len!=0 {return false,blot_error::Error.invalid_request;}let sources,error=sourceViews(request.sources,frame.payload());if error!=blot_error::Error.none {return false,error;}let error=complete(executor,writer,owner,request,sources);let __cleanup_result_3_0: bool = false; let __cleanup_result_3_1: Error = error; {releaseSources(sources);} return __cleanup_result_3_0, __cleanup_result_3_1;
     {releaseSources(sources);} }
    if request.kind==RequestKind.checkpoint || request.kind==RequestKind.close {
        if request.sources.len!=0 || request.assetSources.len!=0 || frame.payload().len!=0 {return false,blot_error::Error.invalid_request;}if request.kind==RequestKind.checkpoint {let error=checkpointReply(writer,owner,request,compiler);return false,error;}owner.persist(true);let error=reply(writer,CloseReply{id:request.id,revision:owner.session.state().revisions,..},[]);return true,error;
    }
    if owner.session.state().revisions>=blot_reuse_zig_project_frames::max_revision {return false,blot_error::Error.revision_limit;}if request.assetSources.len!=0 && !owner.assets.present {return false,blot_error::Error.invalid_request;}var source_bytes=frame.payload().len;if request.assetSources.len!=0 {source_bytes=request.assetSources[0].start;}if source_bytes>frame.payload().len {return false,blot_error::Error.invalid_sources;}
    let sources,error=sourceViews(request.sources,frame.payload()[..source_bytes]);if error!=blot_error::Error.none {return false,error;}let assets,error=rangeViews(request.assetSources,frame.payload(),source_bytes,false);if error!=blot_error::Error.none {let __cleanup_result_4_0: bool = false; let __cleanup_result_4_1: Error = error; {releaseSources(sources);} return __cleanup_result_4_0, __cleanup_result_4_1;}let error=build(executor,writer,owner,request.id,sources,assets);let __cleanup_result_5_0: bool = false; let __cleanup_result_5_1: Error = error; {releaseSources(assets);} {releaseSources(sources);} return __cleanup_result_5_0, __cleanup_result_5_1;
 {releaseSources(assets);} {releaseSources(sources);} }
fn runWithPolicy<E>(executor:E&,reader:blot_io::Reader,writer:blot_io::Writer,compiler:Digest,cache_root:Text,policy:blot_execution_policy::Policy)->Error {
    var identity:u8[64]=[0;64];let digits="0123456789abcdef";for byte,index in compiler {identity[index*2]=digits[byte>>4];identity[index*2+1]=digits[byte&15];}let capabilities=["project-build","utf8_bytes","abort-disposes-process","source-overlays","backend-checkpoints","native-assets-v1","editor-completion-v1","allocation-explanations-v1"];let error=reply(writer,Hello{compilerIdentity:identity[..],capabilities:capabilities[..],..},[]);if error!=blot_error::Error.none {return error;}
    // Fork before reading each request; the supervisor publishes only complete
    // replies after candidate cleanup and adoption. The previous heap stays idle.
    var opened=blot_support::none<OpenProject>();var last_id:u32=0;
    let role=blot_native::request_start(blot_reuse_zig_project_frames::max_frame_bytes as u64,blot_reuse_zig_project_frames::max_frame_bytes as u64,120000);
    if role<0 {return blot_error::Error.io;}
    if role==0 {
        if blot_native::request_transport_run(reader.fd,writer.fd)<0 {return blot_error::Error.io;}
        return blot_error::Error.none;
    }
    loop {
        if blot_native::request_begin()<0 {return blot_error::Error.io;}
        blot_process_pool::detachInherited();
        let token=blot_native::request_token();
        let output=blot_native::request_reply_open();if output<0 {failRequest(token,blot_error::Error.io);}
        let input=blot_io::Reader{blot_native::request_input_fd()};let staged=blot_io::Writer{output};
        let frame,present,error=blot_reuse_zig_project_frames::readRequestFrame(input,request_bytes);
        if error!=blot_error::Error.none {failRequest(token,error);}
        if !present {failRequest(token,blot_error::Error.truncated_frame);}
        var parsed,error=parseRequest(frame.metadata());if error!=blot_error::Error.none {failRequest(token,error);}
        let request=parsed.value;
        if request.id==0 || request.id<=last_id {parsed.deinit();failRequest(token,blot_error::Error.request_order);}
        last_id=request.id;
        let done,error=dispatch(executor,input,staged,compiler,cache_root,policy,opened,request,frame);
        parsed.deinit();
        if error!=blot_error::Error.none {failRequest(token,error);}
        if done && opened.present {opened.value.deinit();opened=blot_support::none<OpenProject>();}
        if blot_native::request_finish(token)<0 {return blot_error::Error.io;}
        if done {return blot_error::Error.none;}
    }
}
fn failRequest(token:u64,error:Error) {
    if error==blot_error::Error.out_of_memory {blot_native::request_fail_oom(token);}
    blot_native::request_fail(token);abort("request failure returned");
}

fn run<E>(executor:E&,reader:blot_io::Reader,writer:blot_io::Writer,compiler:Digest,cache_root:Text)->Error {return runWithPolicy(executor,reader,writer,compiler,cache_root,blot_execution_policy::Policy{..});}
