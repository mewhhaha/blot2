// Request metadata is decoded into owned typed runs. Payload views borrow the
// request buffer and are released before the next read.
namespace blot_reuse_zig_project_server;
import .zig_project_server;
var request_bytes:u8[>..]=[];
struct Hello {kind:const u8[:]="hello",protocol:const u8[:]="blot-zig-project",version:u32=protocol_version,compilerIdentity:const u8[:],capabilities:const TextSlice[:],maxFrameBytes:i64=blot_reuse_zig_project_frames::max_frame_bytes}
struct OpenReply {kind:const u8[:]="open",id:u32,epoch:const u8[:]=epoch,revision:u64=0}
struct CloseReply {kind:const u8[:]="close",id:u32,epoch:const u8[:]=epoch,revision:u64}
fn validateFollowing(request:Request,opened:OpenProject&)->Error {
    if request.storage.present || request.nativeAssets.present || request.version.present || request.entry.present || request.prelude.present || request.stdRoot.present || request.imports.len!=0 || request.dependencies.present || request.profileBackend || request.profileTrace {return blot_error::Error.invalid_request;}
    if !request.epoch.present || request.epoch.value!=epoch || !request.revision.present || request.revision.value!=opened.revisions {return blot_error::Error.revision_mismatch;}return blot_error::Error.none;
}
// True after the close reply.
fn dispatch(writer:blot_io::Writer,compiler:Digest,policy:Policy,opened:blot_support::Option<OpenProject>&,request:Request,payload:const u8[:])->bool,Error {
    if request.kind!=RequestKind.complete && (request.snapshot.present || request.filename.present || request.position.present) {return false,blot_error::Error.invalid_request;}
    if request.kind==RequestKind.open {
        if request.sources.len!=0 || request.assetSources.len!=0 || payload.len!=0 {return false,blot_error::Error.invalid_open;}if opened.present {return false,blot_error::Error.already_open;}let owner,error=initOpen(request,compiler,policy);if error!=blot_error::Error.none {return false,error;}opened=blot_support::some(owner);let error=reply(writer,OpenReply{id:request.id,..},[]);return false,error;
    }
    if !opened.present {return false,blot_error::Error.not_open;}let owner .= opened.value;let error=validateFollowing(request,owner);if error!=blot_error::Error.none {return false,error;}
    if request.kind==RequestKind.complete {
        if !request.snapshot.present || !request.filename.present || !request.position.present || request.filename.value.len>4096 || !validPath(request.filename.value) {return false,blot_error::Error.invalid_completion_request;}if request.assetSources.len!=0 {return false,blot_error::Error.invalid_request;}var sources:Source[>..]=[];let error=sourceViews(request.sources,payload,sources);if error!=blot_error::Error.none {return false,error;}let error=complete(writer,owner,request,sources[..]);return false,error;
    }
    if request.kind==RequestKind.close {
        if request.sources.len!=0 || request.assetSources.len!=0 || payload.len!=0 {return false,blot_error::Error.invalid_request;}let error=reply(writer,CloseReply{id:request.id,revision:owner.revisions,..},[]);return true,error;
    }
    if owner.revisions>=blot_reuse_zig_project_frames::max_revision {return false,blot_error::Error.revision_limit;}if request.assetSources.len!=0 && !owner.assets.present {return false,blot_error::Error.invalid_request;}var source_bytes=payload.len;if request.assetSources.len!=0 {source_bytes=request.assetSources[0].start;}if source_bytes>payload.len {return false,blot_error::Error.invalid_sources;}
    var sources:Source[>..]=[];let error=sourceViews(request.sources,payload[..source_bytes],sources);if error!=blot_error::Error.none {return false,error;}var assets:Source[>..]=[];let error=rangeViews(request.assetSources,payload,source_bytes,false,assets);if error!=blot_error::Error.none {return false,error;}let error=build(writer,owner,request.id,sources[..],assets[..]);return false,error;
}
// No diagnostic or metrics text is written to stdout in serve mode. An error
// ends the process; the client then disposes of the session.
fn run(reader:blot_io::Reader,writer:blot_io::Writer,compiler:Digest,policy:Policy)->Error {
    var identity:u8[64]=[0;64];let digits="0123456789abcdef";for byte,index in compiler {identity[index*2]=digits[byte>>4];identity[index*2+1]=digits[byte&15];}let capabilities=["project-build","utf8_bytes","abort-disposes-process","source-overlays","native-assets-v1","editor-completion-v1"];let error=reply(writer,Hello{compilerIdentity:identity[..],capabilities:capabilities[..],..},[]);if error!=blot_error::Error.none {return error;}
    var opened=blot_support::none<OpenProject>();var last_id:u32=0;
    loop {
        let frame,present,error=blot_reuse_zig_project_frames::readRequestFrame(reader,request_bytes);if error!=blot_error::Error.none {if opened.present {opened.value.deinit();}return error;}if !present {break;}
        var parsed,error=parseRequest(frame.metadata());if error!=blot_error::Error.none {if opened.present {opened.value.deinit();}return error;}let request=parsed.value;
        if request.id==0 || request.id<=last_id {parsed.deinit();if opened.present {opened.value.deinit();}return blot_error::Error.request_order;}last_id=request.id;
        let done,error=dispatch(writer,compiler,policy,opened,request,frame.payload());parsed.deinit();
        if error!=blot_error::Error.none {if opened.present {opened.value.deinit();}return error;}if done {break;}
    }
    if opened.present {opened.value.deinit();}return blot_error::Error.none;
}
