// Retained wire restoration owns its payload through Frame reuse and close.
import bootstrap_globals;import driver.cli;import driver.cli_workers;import std;import reuse.retained_revision;import driver.compile_workspace;
fn restore(session:blot_reuse_retained_revision::Session) {
 let files=[blot_reuse_revision_inputs::Pair{key:"/tmp/server-owner.blot",value:"const value = 1\n"}];let wire=blot_reuse_retained_revision::RestoredWire{settings:[0;32],entry_request:"/tmp/server-owner.blot",entry_canonical:"/tmp/server-owner.blot",output_identity:blot_support::none<const u8[:]>(),policy:blot_reuse_retained_revision::Policy{..},wasm:"wasm",source_bytes:16,modules:1,checkpoint_digest:blot_support::none<blot_reuse_retained_revision::Digest>(),inputs:blot_reuse_revision_inputs::Wire{options:blot_reuse_project::Options{..},paths:default<const blot_reuse_revision_inputs::Pair[:]>(),files:files[..],imports:default<const blot_reuse_revision_inputs::PersistedImport[:]>(),}};
 let bytes,error=blot_reuse_retained_revision::encodeRestoredWire([0;32],wire);assert(error==blot_error::Error.none);let restored,error=blot_reuse_retained_revision::decodeRestored([0;32],bytes);assert(error==blot_error::Error.none);blot_reuse_dependency_format::release(bytes);session.publishRestored(restored);
}
fn retained(){var session,error=blot_reuse_retained_revision::initEmpty(blot_reuse_project::Options{..},blot_native::fresh_owner_id());assert(error==blot_error::Error.none);restore(session);var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.valid());assert(frame.release()==blot_error::Error.none);assert(session.state().restored.present && session.state().restored.value.output.bytes=="wasm");let view=session.state().restored.value.inputs.view();assert(view.capturedSource("/tmp/server-owner.blot").value=="const value = 1\n" && view.counts.source_reads==0);let stale=session;session.deinit();assert(!stale.valid());}

fn main(){retained();requestSourceLifetime();}

fn requestSourceSnapshot()->blot_reuse_revision_inputs::Snapshot {
 let metadata="{\"kind\":\"build\",\"id\":1,\"sources\":[{\"path\":\"/tmp/request.blot\",\"start\":0,\"length\":3},{\"path\":\"/tmp/deleted.blot\",\"start\":3,\"length\":0,\"deleted\":true}],\"assetSources\":[{\"path\":\"/tmp/blob.bin\",\"start\":3,\"length\":1}]}";
 var packet:u8[>..]=[];packet.append(metadata);packet.append([97 as u8,98,99,255]);
 let frame=blot_reuse_zig_project_frames::RequestFrame{bytes:packet[..],metadata_length:metadata.len};
 var parsed,error=blot_reuse_zig_project_server::parseRequest(frame.metadata());assert(error==blot_error::Error.none);
 var sources:blot_reuse_source_overlays::Source[>..]=[];
 assert(blot_reuse_zig_project_server::sourceViews(parsed.value.sources,frame.payload()[..3],sources)==blot_error::Error.none);
 assert(sources.len==2&&sources[0].path=="/tmp/request.blot"&&sources[0].contents.present&&sources[0].contents.value=="abc"&&!sources[1].contents.present);
 var assets:blot_reuse_source_overlays::Source[>..]=[];
 assert(blot_reuse_zig_project_server::rangeViews(parsed.value.assetSources,frame.payload(),3,false,assets)==blot_error::Error.none);
 assert(assets.len==1&&assets[0].contents.present&&assets[0].contents.value.len==1&&assets[0].contents.value[0]==255);
 var invalid:blot_reuse_source_overlays::Source[>..]=[];
 assert(blot_reuse_zig_project_server::rangeViews(parsed.value.assetSources,frame.payload(),3,true,invalid)==blot_error::Error.invalid_sources&&invalid.len==0);
 let snapshot,error=blot_reuse_revision_inputs::initWithSources(blot_reuse_project::Options{..},sources[..]);assert(error==blot_error::Error.none);
 parsed.deinit();packet[metadata.len]=120;return snapshot;
}
fn requestSourceLifetime() {
 var snapshot=requestSourceSnapshot();var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 let bytes,error=snapshot.read("/tmp/request.blot");assert(error==blot_error::Error.none&&bytes=="abc");
 let absent,error=snapshot.read("/tmp/deleted.blot");assert(error==blot_error::Error.file_not_found);snapshot.deinit();
}
