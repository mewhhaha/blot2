// Completion uses the current overlay image without committing a revision.
namespace blot_reuse_zig_project_server;
import .zig_project_server;
import reuse.editor_completion;
import reuse.hole_diagnostics;
import reuse.revision_inputs;
import reuse.project;
import backend.native_assets;
import support.io;
import support.json;
import support.error;
struct CompletionFailureReply {
 kind:const u8[:]="complete",id:u32,epoch:const u8[:]=epoch,revision:u64,snapshot:u32,filename:const u8[:],position:u32,success:bool=false,diagnostics:Diagnostic[1],
}
fn completionFailure(writer:blot_io::Writer,opened:OpenProject&,request:Request,code:const u8[:],message:const u8[:],position:u32)->Error {
 assert(request.snapshot.present&&request.filename.present&&request.position.present);var end=min(message.len,1024);while end!=0&&end<message.len&&(message[end]&0xc0)==0x80 {end--;}
 return reply(writer,CompletionFailureReply{id:request.id,revision:opened.session.state().revisions,snapshot:request.snapshot.value,filename:request.filename.value,position:request.position.value,diagnostics:[Diagnostic{filename:request.filename.value,stage:"complete",code:code,start:position,end:position,message:message[..end],..}],..},[]);
}
struct CompletionReply {
 kind:const u8[:]="complete",id:u32,epoch:const u8[:]=epoch,revision:u64,snapshot:u32,filename:const u8[:],position:u32,success:bool=true,
 replace:blot_parse_ast::Span,context:blot_support::Option<blot_reuse_hole_diagnostics::Snapshot>,items:const blot_reuse_editor_completion::Item[:],truncated:bool,diagnostics:const blot_reuse_editor_completion::Diagnostic[:],
}
fn completionReply(opened:const OpenProject&,request:Request,result:const blot_reuse_editor_completion::Result&,item_count:i64,diagnostic_count:i64)->CompletionReply {
 return CompletionReply{id:request.id,revision:opened.session.state().revisions,snapshot:request.snapshot.value,filename:request.filename.value,position:request.position.value,replace:result.replace,context:result.context,items:result.items[..item_count],truncated:result.truncated,diagnostics:result.diagnostics[..diagnostic_count],..};
}
fn complete<E>(executor:E&,writer:blot_io::Writer,opened:OpenProject&,request:Request,sources:const Source[:])->Error {
 assert(request.snapshot.present&&request.filename.present&&request.position.present);if request.snapshot.value==0 {return completionFailure(writer,opened,request,"invalid_completion","Snapshot must be nonzero",0);}
 var assets:blot_backend_native_assets::Candidate?=null;
 var merged:Source[>..<]=[];
 if opened.assets.present {
  let candidate,error=opened.assets.value.prepare(opened.entry,sources,[]);if error!=Error.none {if error==Error.out_of_memory {let __cleanup_result_1_0: Error = error; {if assets {assets.deinit();}} return __cleanup_result_1_0;}if error==Error.duplicate_source_path {let __cleanup_result_2_0: Error = completionFailure(writer,opened,request,"duplicate_source","Sources identify the same canonical file",0); {if assets {assets.deinit();}} return __cleanup_result_2_0;}let __cleanup_result_3_0: Error = completionFailure(writer,opened,request,"completion_failed",blot_error::error_name(error),0); {if assets {assets.deinit();}} return __cleanup_result_3_0;}assert(candidate);assets .= candidate;
  if assets.issue.present {let __cleanup_result_4_0: Error = completionFailure(writer,opened,request,"completion_failed",assets.issue.value.message,0); {if assets {assets.deinit();}} return __cleanup_result_4_0;}merged.append(assets.sources.items);
 }
 merged.append(sources);var snapshot,error=blot_reuse_revision_inputs::initWithSources(opened.options_owner.options,merged[:]);if error!=Error.none {if error==Error.out_of_memory {let __cleanup_result_5_0: Error = error; {if assets {assets.deinit();}} return __cleanup_result_5_0;}if error==Error.duplicate_source_path {let __cleanup_result_6_0: Error = completionFailure(writer,opened,request,"duplicate_source","Sources identify the same canonical file",0); {if assets {assets.deinit();}} return __cleanup_result_6_0;}if error==Error.source_limit {let __cleanup_result_7_0: Error = completionFailure(writer,opened,request,"source_limit","Completion source acquisition limit",0); {if assets {assets.deinit();}} return __cleanup_result_7_0;}let __cleanup_result_8_0: Error = completionFailure(writer,opened,request,"completion_failed",blot_error::error_name(error),0); {if assets {assets.deinit();}} return __cleanup_result_8_0;}
 var result,error=blot_reuse_editor_completion::query(executor,opened.entry,snapshot,request.filename.value,request.position.value);if error!=Error.none {
  if error==Error.out_of_memory {let __cleanup_result_9_0: Error = error; {snapshot.deinit();} {if assets {assets.deinit();}} return __cleanup_result_9_0;}var position:u32=0;
  if error==Error.invalid_position {let path,canonical_error=snapshot.canonical(request.filename.value);if canonical_error==Error.none {let source=snapshot.capturedSource(path);if source.present {position=min(source.value.len,request.position.value as i64) as u32;while position!=0&&position!=source.value.len&&(source.value[position]&0xc0)==0x80 {position--;}}}}
  var code:const u8[:]="completion_failed";if error==Error.invalid_position {code="invalid_position";}else if error==Error.invalid_completion {code="invalid_completion";}else if error==Error.missing_source {code="missing_source";}else if error==Error.source_limit {code="source_limit";}
  let __cleanup_result_10_0: Error = completionFailure(writer,opened,request,code,blot_error::error_name(error),position); {snapshot.deinit();} {if assets {assets.deinit();}} return __cleanup_result_10_0;
 }
 
 // Context is checked with required fields first. Its removal preserves the
 // already ranked suggestion prefix, matching the native 256 KiB boundary.
 if result.context.present {
  var check=completionReply(opened,request,result,0,0);check.truncated=true;var bytes:u8[>..<]=[];let error=encodeMetadata(check,bytes);if error!=Error.none {let __cleanup_result_11_0: Error = error; {result.deinit();} {snapshot.deinit();} {if assets {assets.deinit();}} return __cleanup_result_11_0;}
  if bytes.len>262144 {result.context.value.deinit();result.context=blot_support::none<blot_reuse_hole_diagnostics::Snapshot>();let error=result.noteLimit(request.filename.value);if error!=Error.none {let __cleanup_result_12_0: Error = error; {result.deinit();} {snapshot.deinit();} {if assets {assets.deinit();}} return __cleanup_result_12_0;}}
 }
 var item_count=result.items.len;var diagnostic_count=result.diagnostics.len;
 loop {
  var bytes:u8[>..<]=[];let error=encodeMetadata(completionReply(opened,request,result,item_count,diagnostic_count),bytes);if error!=Error.none {let __cleanup_result_13_0: Error = error; {result.deinit();} {snapshot.deinit();} {if assets {assets.deinit();}} return __cleanup_result_13_0;}if bytes.len<=262144 {let __cleanup_result_14_0: Error = blot_reuse_zig_project_frames::write(writer,bytes[:],[]); {result.deinit();} {snapshot.deinit();} {if assets {assets.deinit();}} return __cleanup_result_14_0;}
  if !result.truncated {let error=result.noteLimit(request.filename.value);if error!=Error.none {let __cleanup_result_15_0: Error = error; {result.deinit();} {snapshot.deinit();} {if assets {assets.deinit();}} return __cleanup_result_15_0;}diagnostic_count=result.diagnostics.len;continue;}
  if diagnostic_count>1 {diagnostic_count--;}else if item_count!=0 {item_count--;}else if result.context.present {result.context.value.deinit();result.context=blot_support::none<blot_reuse_hole_diagnostics::Snapshot>();}else {let __cleanup_result_16_0: Error = Error.frame_too_large; {result.deinit();} {snapshot.deinit();} {if assets {assets.deinit();}} return __cleanup_result_16_0;}
 }
 {result.deinit();} {snapshot.deinit();} {if assets {assets.deinit();}} }
