// A process compiles one attempt at a time. Frames borrow the explicit global
// backing; published outputs and retained captures have independent owners.
namespace blot_compile_workspace;
import .compile_workspace_backing;
import backend.core_backend;
import backend.result_publication;
import backend.optimized_bodies;
import eval.core_eval;
import reuse.artifact_capture;
import reuse.code_artifacts;
import reuse.dependency_payload;
import check.core;
import support.native;
import support.error;
type Error=blot_error::Error;
type Core=blot_check_core::Module;
type InputOwner=blot_reuse_dependency_payload::Owner;
type Workspace=blot_backend_core_backend::CompileWorkspace;
type Generator=blot_backend_core_backend::Generator;
type Result=blot_backend_core_backend::Result;
type Capture=blot_reuse_artifact_capture::Capture;
type Factory=blot_reuse_artifact_capture::Factory;
struct Frame {slot:u32=0,generation:u64=0}
struct FrameState {
 live:bool=false,generation:u64=0,references:u64=1,allocation_owner:u64=0,
 session:blot_eval_core_eval::Session?=null,generator:Generator?=null,workspace:Workspace?=null,
 factory:Factory=Factory{..},capture:Capture?=null,capture_token:u64=0,
 generator_slot:u32=0,workspace_slot:u32=0,prepared:bool=false,
}
reusable var frames:FrameState[>..]=[];
reusable var generators:Generator[>..]=[];
reusable var workspaces:Workspace[>..]=[];
var active:Frame=Frame{..};
var active_optimized_headers:blot_backend_optimized_bodies::Capture[>..]=[];
fn activeOptimized()->blot_backend_optimized_bodies::Capture& {if active_optimized_headers.len==0 {active_optimized_headers.push(blot_backend_optimized_bodies::Capture{..});}return active_optimized_headers[0];}
fn resetOptimized() {let current:blot_backend_optimized_bodies::Capture& =activeOptimized();current=blot_backend_optimized_bodies::Capture{..};}
fn valid(self_:Frame)->bool {return self_.slot!=0&&self_.slot-1<frames.len&&frames[self_.slot-1].live&&frames[self_.slot-1].generation==self_.generation;}
fn borrow(self_:Frame)->Workspace? {if !self_.valid() {return null;}return frames[self_.slot-1].workspace;}
fn retain(self_:Frame)->Frame,Error {if !self_.valid() {return Frame{..},blot_error::Error.invalid_artifact;}let state:FrameState& =frames[self_.slot-1];if state.references==0xffffffffffffffff {return Frame{..},blot_error::Error.dependency_limit;}state.references++;return self_,blot_error::Error.none;}
fn create(allocation_owner:u64)->Frame,Error {
 if allocation_owner==0||active.slot!=0 {return Frame{..},blot_error::Error.invalid_request;}if frames.len>=0xffffffff {return Frame{..},blot_error::Error.out_of_memory;}
 clearBacking();resetBackingDescriptors();resetOptimized();
 let generation=blot_native::fresh_owner_id();let at=frames.alloc_index(FrameState{live:true,generation:generation,allocation_owner:allocation_owner,factory:Factory{allocation_owner},..});let frame=Frame{(at+1) as u32,generation};active=frame;
 let error=construct(frame);if error!=blot_error::Error.none {let discarded=frame;var failed=discarded;let cleanup=failed.release();assert(cleanup==blot_error::Error.none);return Frame{..},error;}return frame,blot_error::Error.none;
}
fn construct(frame:Frame)->Error {
 assert(frame.valid()&&active==frame);let state:FrameState& =frames[frame.slot-1];
 // Empty catalogs are deliberate: no caller-owned input header is retained
 // before bindPublicationOwner and pinWorkspaceInputs establish real pins.
 let session,error=blot_eval_core_eval::initOwnedSession([],state.allocation_owner);if error!=blot_error::Error.none {return error;}assert(session);state.session .= session;
 let capture,token,error=state.factory.createArchiveCapture();if error!=blot_error::Error.none {return error;}assert(capture);state.capture .= capture;state.capture_token=token;
 let generator_index=generators.alloc_index(makeGenerator(state.allocation_owner,session));state.generator_slot=(generator_index+1) as u32;state.generator .= generators[generator_index];
 let prepared=state.generator.representations.init([]);if prepared!=blot_error::Error.none {return prepared;}state.prepared=true;
 state.generator.planning.init();let initialized=blot_backend_core_backend::init(state.generator,null);if initialized!=blot_error::Error.none {return initialized;}
 let workspace_index=workspaces.alloc_index(makeWorkspace(state.allocation_owner,state.generator,session.ownedSessionTables(),capture,activeOptimized()));state.workspace_slot=(workspace_index+1) as u32;state.workspace .= workspaces[workspace_index];
 return blot_backend_core_backend::bindPublicationOwner(state.workspace,state.generation);
}
fn release(self_:Frame&)->Error {
 if self_.slot==0 {return blot_error::Error.none;}if !self_.valid() {return blot_error::Error.invalid_artifact;}let at=self_.slot-1;let state:FrameState& =frames[at];
 if state.references>1 {state.references--;self_=Frame{..};return blot_error::Error.none;}
 if state.workspace {if state.workspace.publication_owner.slot!=0&&!blot_backend_core_backend::publicationCanReclaim(state.workspace) {return blot_error::Error.invalid_artifact;}}
 assert(active==self_);destroyContexts(state);state.live=false;state.session .= null;state.generator .= null;state.workspace .= null;state.capture .= null;state.capture_token=0;
 frames.free(at);active=Frame{..};self_=Frame{..};return blot_error::Error.none;
}
fn destroyContexts(state:FrameState&) {
 // Result.deinit or detachResult releases its workspace lease first. Capture
 // transfer may already have moved its metadata/token out of this frame.
 var publication=blot_backend_result_publication::Owner{..};
 if state.workspace {
  let workspace .= state.workspace;publication=workspace.publication_owner;
  workspace.origins.deinit();workspace.candidate.deinit();workspace.vectors.deinit();
  workspace.replay_origins.deinit();workspace.replay_candidate.deinit();workspace.replay_vectors.deinit();workspace.replay_module.deinit();
  workspace.retained.deinit();workspace.principal_state.deinit();workspace.persisted_principals.deinit();workspace.query_state.deinit();workspace.constant_state.deinit();
  workspace.module_stamps.deinit();workspace.allocation_snapshot.deinit();workspace.startup_snapshot.deinit();workspace.explanation.deinit();
 }
 if state.generator {
  state.generator.module.artifacts .= null;state.generator.artifacts .= null;state.generator.retained .= null;state.generator.principal_state .= null;state.generator.persisted_principals .= null;state.generator.query_state .= null;state.generator.constant_state .= null;state.generator.refinement_owner .= null;
  // Generator cleanup owns attempt tables; canonical Session ownership belongs
  // to this Frame and is released exactly once below.
  state.generator.deinit();state.generator.units=[];state.generator.spawn_units=[];
 }
 if state.capture_token!=0 {assert(state.capture);state.factory.destroyArchiveCapture(state.capture_token);state.capture_token=0;state.capture .= null;}
 activeOptimized().deinit();
 if state.session {blot_eval_core_eval::deinitOwnedSession(state.session);state.session .= null;}
 if state.workspace_slot!=0 {workspaces.free(state.workspace_slot-1);state.workspace_slot=0;state.workspace .= null;}
 if state.generator_slot!=0 {generators.free(state.generator_slot-1);state.generator_slot=0;state.generator .= null;}
 clearBacking();resetBackingDescriptors();let released=blot_backend_result_publication::destroy(publication);assert(released==blot_error::Error.none);
}

struct CaptureLease {slot:u32=0,generation:u64=0}
struct CaptureState {
 live:bool=false,generation:u64=0,references:u64=1,factory:Factory=Factory{..},token:u64=0,capture:Capture?=null,
 units:Core[:]=default<Core[:]>(),journals:InputOwner[:]=default<InputOwner[:]>(),optimized_header:u32=0,
}
reusable var retained_captures:CaptureState[>..]=[];
reusable var retained_optimized:blot_backend_optimized_bodies::Capture[>..]=[];
reusable[] var retained_units:Core[>..]=[];
reusable[] var retained_journals:InputOwner[>..]=[];
fn valid(self_:CaptureLease)->bool {return self_.slot!=0&&self_.slot-1<retained_captures.len&&retained_captures[self_.slot-1].live&&retained_captures[self_.slot-1].generation==self_.generation;}
fn borrow(self_:CaptureLease)->Capture? {if !self_.valid() {return null;}return retained_captures[self_.slot-1].capture;}
fn retain(self_:CaptureLease)->CaptureLease,Error {if !self_.valid() {return CaptureLease{..},blot_error::Error.invalid_artifact;}let state:CaptureState& =retained_captures[self_.slot-1];if state.references==0xffffffffffffffff {return CaptureLease{..},blot_error::Error.dependency_limit;}state.references++;return self_,blot_error::Error.none;}
fn deinit(self_:CaptureLease&) {
 if self_.slot==0 {return;}assert(self_.valid());let at=self_.slot-1;let state:CaptureState& =retained_captures[at];assert(state.references!=0);state.references--;
 if state.references==0 {
  if state.token!=0 {state.factory.destroyArchiveCapture(state.token);state.token=0;state.capture .= null;}
  if state.optimized_header!=0 {retained_optimized.free(state.optimized_header-1);state.optimized_header=0;}
  for &journal in state.journals {if journal.lease!=0 {journal.release();}}if state.journals.len!=0 {retained_journals.free_slice(state.journals);}if state.units.len!=0 {retained_units.free_slice(state.units);}
  state=CaptureState{..};retained_captures.free(at);
 }
 self_=CaptureLease{..};
}
fn retainJournal(state:CaptureState&,owner:InputOwner,index:i64&)->Error {
 if owner.lease==0 {return blot_error::Error.none;}let held,error=owner.retain();if error!=blot_error::Error.none {return error;}state.journals[index]=held;index++;return blot_error::Error.none;
}
fn takeCapture(frame:Frame&,result:Result&,units:const Core[:],catalog:InputOwner,unit_owners:const InputOwner[:],seed_owners:const InputOwner[:])->CaptureLease,Error {
 if !frame.valid() {return CaptureLease{..},blot_error::Error.invalid_artifact;}let source:FrameState& =frames[frame.slot-1];if result.capture==null {return CaptureLease{..},blot_error::Error.none;}
 if source.workspace==null||source.capture==null||source.capture_token==0||!(result.capture .== source.capture)||!result.publication_pinned||!result.capture.metadata.pools.present||unit_owners.len!=units.len {return CaptureLease{..},blot_error::Error.invalid_artifact;}
 if !blot_backend_result_publication::resultValid(result.publication_owner,result.publication_epoch,true)||result.publication_owner!=source.workspace.publication_owner||result.publication_units.len!=units.len {return CaptureLease{..},blot_error::Error.invalid_artifact;}
 for module,index in units {let held=result.publication_units[index];if module.owner_id!=held.owner_id||module.unit!=held.unit||!(module.nodes .== held.nodes) {return CaptureLease{..},blot_error::Error.invalid_artifact;}}
 if retained_captures.len>=0xffffffff||retained_optimized.len>=0xffffffff {return CaptureLease{..},blot_error::Error.out_of_memory;}
 var count:i64=0;if catalog.lease!=0 {count++;}for owner in unit_owners {if owner.lease!=0 {count++;}}for owner in seed_owners {if owner.lease!=0 {count++;}}
 let generation=blot_native::fresh_owner_id();let at=retained_captures.alloc_index(CaptureState{live:true,generation:generation,factory:source.factory,..});let state:CaptureState& =retained_captures[at];var lease=CaptureLease{(at+1) as u32,generation};
 state.journals=retained_journals.alloc_slice(count);for &owner in state.journals {owner=InputOwner{..};}var next:i64=0;
 let copied=retainCaptureInputs(state,catalog,unit_owners,seed_owners,next);if copied!=blot_error::Error.none {lease.deinit();return CaptureLease{..},copied;}assert(next==count);
 state.units=retained_units.alloc_slice(units.len);for module,index in units {state.units[index]=module;}
 let rebound=blot_reuse_code_artifacts::rebindModuleHeaders(result.capture.metadata.pools.value,state.units);if rebound!=blot_error::Error.none {lease.deinit();return CaptureLease{..},rebound;}
 // Everything fallible precedes the move. Optimizer payloads and their header
 // move together; no retained capture points back into active compiler backing.
 if result.capture.optimized {
  assert(result.capture.optimized .== activeOptimized());let header=retained_optimized.alloc_index(activeOptimized());state.optimized_header=(header+1) as u32;result.capture.optimized .= retained_optimized[header];resetOptimized();
 }
 state.token=source.capture_token;state.capture .= source.capture;source.capture_token=0;source.capture .= null;result.capture .= null;return lease,blot_error::Error.none;
}
fn retainCaptureInputs(state:CaptureState&,catalog:InputOwner,unit_owners:const InputOwner[:],seed_owners:const InputOwner[:],next:i64&)->Error {
 let error=retainJournal(state,catalog,next);if error!=blot_error::Error.none {return error;}for owner in unit_owners {let error=retainJournal(state,owner,next);if error!=blot_error::Error.none {return error;}}for owner in seed_owners {let error=retainJournal(state,owner,next);if error!=blot_error::Error.none {return error;}}return blot_error::Error.none;
}
