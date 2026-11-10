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
fn canonicalWorkspace(source:Workspace&)->Workspace& {
 assert(active.valid());let state:FrameState& =frames[active.slot-1];
 assert(state.workspace_slot!=0 && state.workspace_slot-1<workspaces.len);
 let registered .=state.workspace;assert(registered);
 let owned:Workspace& =workspaces[state.workspace_slot-1];
 assert(source .==owned && registered .==owned);return owned;
}
fn canonicalGenerator(source:Generator&)->Generator& {
 assert(active.valid());let state:FrameState& =frames[active.slot-1];
 assert(state.generator_slot!=0 && state.generator_slot-1<generators.len);
 assert(state.workspace_slot!=0 && state.workspace_slot-1<workspaces.len);
 let registered .= state.generator;let registered_workspace .= state.workspace;assert(registered && registered_workspace);
 let owned:Generator& =generators[state.generator_slot-1];let workspace:Workspace& =workspaces[state.workspace_slot-1];
 assert(source .== owned && registered .== owned && registered_workspace .== workspace && workspace.generator .== owned);
 return owned;
}
// Session backpointers borrow the existing active frame; they never retain it.
fn generatorForSession(frame:Frame,session:blot_eval_core_eval::Session&)->Generator& {
 assert(frame.valid()&&frame==active);let state:FrameState& =frames[frame.slot-1];
 let registered_ref .=state.generator;let session_ref .=state.session;assert(registered_ref&&session_ref);let registered:Generator& =registered_ref;let registered_session:blot_eval_core_eval::Session& =session_ref;
 let generator:Generator& =canonicalGenerator(registered);
 assert(registered_session .== session && generator.evaluator .== session);
 return generator;
}
fn frameForGenerator(source:Generator&,session:blot_eval_core_eval::Session&)->Frame {
 let generator:Generator& =canonicalGenerator(source);let state:FrameState& =frames[active.slot-1];
 let registered_session .=state.session;assert(registered_session && registered_session .== session && generator.evaluator .== session);
 return active;
}
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
 // Empty catalogs precede the publication owner's real input pins.
 let opened_session,error=blot_eval_core_eval::initOwnedEmptySession(state.allocation_owner);if error!=blot_error::Error.none {return error;}assert(opened_session!=null);let session:blot_eval_core_eval::Session& =opened_session;state.session .= session;
 let opened_capture,token,error=state.factory.createArchiveCapture();if error!=blot_error::Error.none {return error;}assert(opened_capture!=null);let capture:blot_reuse_artifact_capture::Capture& =opened_capture;state.capture .= capture;state.capture_token=token;
 let generator_index=generators.alloc_index(makeGenerator(state.allocation_owner,session));state.generator_slot=(generator_index+1) as u32;let generator:Generator& =generators[generator_index];state.generator .= generator;
 let prepared=generator.representations.initEmpty();if prepared!=blot_error::Error.none {return prepared;}state.prepared=true;
 generator.planning.init();let initialized=blot_backend_core_backend::init(generator,null);if initialized!=blot_error::Error.none {return initialized;}
 let workspace_index=workspaces.alloc_index(makeWorkspace(state.allocation_owner,generator,session.ownedSessionTables(),capture,activeOptimized()));state.workspace_slot=(workspace_index+1) as u32;let workspace:Workspace& =workspaces[workspace_index];state.workspace .= workspace;
 return blot_backend_core_backend::bindPublicationOwner(workspace,state.generation);
}
fn release(self_:Frame&)->Error {
 if self_.slot==0 {return blot_error::Error.none;}if !self_.valid() {return blot_error::Error.invalid_artifact;}let at=self_.slot-1;let state:FrameState& =frames[at];
 if state.references>1 {state.references--;self_=Frame{..};return blot_error::Error.none;}
 let workspace_ref .=state.workspace;if workspace_ref {let workspace:Workspace& =workspace_ref;if workspace.publication_owner.slot!=0&&!blot_backend_core_backend::publicationCanReclaim(workspace) {return blot_error::Error.invalid_artifact;}}
 assert(active==self_);destroyContexts(self_);state.live=false;state.session .= null;state.generator .= null;state.workspace .= null;state.capture .= null;state.capture_token=0;
 frames.free(at);active=Frame{..};self_=Frame{..};return blot_error::Error.none;
}
fn destroyContexts(frame:Frame) {
 assert(frame.valid() && active==frame);let state:FrameState& =frames[frame.slot-1];
 // Result.deinit or detachResult releases its workspace lease first. Capture
 // transfer may already have moved its metadata/token out of this frame.
 var publication=blot_backend_result_publication::Owner{..};
 let workspace_ref .=state.workspace;
 if workspace_ref {
  let workspace:Workspace& =workspace_ref;publication=workspace.publication_owner;
  workspace.origins.deinit();workspace.candidate.deinit();workspace.vectors.deinit();
  workspace.replay_origins.deinit();workspace.replay_candidate.deinit();workspace.replay_vectors.deinit();workspace.replay_module.deinit();
  workspace.retained.deinit();workspace.principal_state.deinit();workspace.persisted_principals.deinit();workspace.query_state.deinit();workspace.constant_state.deinit();
  workspace.allocation_snapshot.deinit();workspace.startup_snapshot.deinit();workspace.explanation.deinit();
 }
 let generator_ref .=state.generator;
 if generator_ref {
  let generator:Generator& =generator_ref;
  generator.module.artifacts .= null;generator.artifacts .= null;generator.retained .= null;generator.principal_state .= null;generator.persisted_principals .= null;generator.query_state .= null;generator.constant_state .= null;generator.refinement_owner .= null;
  // Generator cleanup owns attempt tables; canonical Session ownership belongs
  // to this Frame and is released exactly once below.
  generator.deinit();generator.units=default<const blot_check_core::Module[:]>();generator.spawn_units=default<const blot_check_core::Module[:]>();
 }
 if state.capture_token!=0 {assert(state.capture);state.factory.destroyArchiveCapture(state.capture_token);state.capture_token=0;state.capture .= null;}
 activeOptimized().deinit();
 let session_ref .=state.session;if session_ref {let session:blot_eval_core_eval::Session& =session_ref;blot_eval_core_eval::deinitOwnedSession(session);state.session .= null;}
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
 if source.workspace==null||source.capture==null||source.capture_token==0||!(result.capture .== source.capture)||!result.publication_pinned||!result.capture.metadata().pools.present||unit_owners.len!=units.len {return CaptureLease{..},blot_error::Error.invalid_artifact;}
 if !blot_backend_result_publication::resultValid(result.publication_owner,result.publication_epoch,true)||result.publication_owner!=source.workspace.publication_owner||result.publication_units.len!=units.len {return CaptureLease{..},blot_error::Error.invalid_artifact;}
 for module,index in units {let held=result.publication_units[index];if module.owner_id!=held.owner_id||module.unit!=held.unit||!(module.nodes .== held.nodes) {return CaptureLease{..},blot_error::Error.invalid_artifact;}}
 if retained_captures.len>=0xffffffff||retained_optimized.len>=0xffffffff {return CaptureLease{..},blot_error::Error.out_of_memory;}
 var count:i64=0;if catalog.lease!=0 {count++;}for owner in unit_owners {if owner.lease!=0 {count++;}}for owner in seed_owners {if owner.lease!=0 {count++;}}
 let generation=blot_native::fresh_owner_id();let at=retained_captures.alloc_index(CaptureState{live:true,generation:generation,factory:source.factory,..});let state:CaptureState& =retained_captures[at];var lease=CaptureLease{(at+1) as u32,generation};
 state.journals=retained_journals.alloc_slice(count);for &owner in state.journals {owner=InputOwner{..};}var next:i64=0;
 let copied=retainCaptureInputs(state,catalog,unit_owners,seed_owners,next);if copied!=blot_error::Error.none {lease.deinit();return CaptureLease{..},copied;}assert(next==count);
 state.units=retained_units.alloc_slice(units.len);for module,index in units {state.units[index]=module;}
 let rebound=blot_reuse_code_artifacts::rebindModuleHeaders(result.capture.metadata().pools.value,state.units);if rebound!=blot_error::Error.none {lease.deinit();return CaptureLease{..},rebound;}
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

fn constantSource(source:const blot_reuse_constant_receipt_reuse::State&)->const blot_reuse_code_artifacts::Pools& {assert(source .== backing_constant_state && backing_constant_state.live && backing_constant_state.old.present);return backing_constant_state.old.value;}

fn registeredWorkspaceUnits()->const Core[:] {
 assert(active.valid());let frame:const FrameState& =frames[active.slot-1];
 assert(frame.workspace_slot!=0 && frame.workspace_slot-1<workspaces.len);let workspace:const Workspace& =workspaces[frame.workspace_slot-1];let registered .=frame.workspace;assert(registered && registered .== workspace);
 let units,error=blot_backend_result_publication::registeredInputUnits(workspace.publication_owner);assert(error==blot_error::Error.none);return units;
}
fn principalUnits(source:const blot_reuse_principal_evidence_reuse::State&)->const Core[:] {
 assert(source .== backing_principal_state);let units=registeredWorkspaceUnits();assert(blot_support::same_slice_identity(units,source.gate.units));return units;
}
fn queryUnits(source:const blot_eval_completed_specialization_query::State&)->const Core[:] {
 assert(source .== backing_query_state);let units=registeredWorkspaceUnits();assert(blot_support::same_slice_identity(units,source.gate.units));return units;
}
