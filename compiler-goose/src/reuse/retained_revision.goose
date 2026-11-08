// Transactional revisions publish only after exact inputs and emitted output
// succeed. Numeric epochs keep late Candidate cleanup independent of Session.
namespace blot_reuse_retained_revision;
import std;
import execution_policy;
import phase_profile;
import reuse.partial_dependency;
import reuse.dependency_consumer;
import reuse.project;
import reuse.project_check;
import reuse.dependency_cli;
import reuse.dependency_format;
import reuse.dependency_payload;
import reuse.dependency_closure;
import reuse.frozen_dependency;
import reuse.retained_dependency;
import reuse.source_completion;
import reuse.source_overlays;
import reuse.revision_inputs;
import reuse.entry_frontend_cutoff;
import reuse.artifact_capture;
import backend.core_backend;
import backend.backend_checkpoint;
import backend.allocation_emission;
import backend.array_cost_explanation;
import driver.compile_workspace;
import support.error;
import support.option;
import support.native;
import support.json;
import .retained_revision_frontend;
import .retained_revision_prepare;
type Error=blot_error::Error;
type Digest=u8[32];
type Text=blot_support::Option<const u8[:]>;
type Options=blot_reuse_project::Options;
type Policy=blot_execution_policy::Policy;
type Owner=blot_reuse_dependency_payload::Owner;
type Frozen=blot_reuse_frozen_dependency::FrozenDependency;
type OwnedFrozen=blot_reuse_dependency_payload::Owned<Frozen>;
type Seed=blot_reuse_retained_dependency::Seed;
type Snapshot=blot_reuse_retained_dependency::Snapshot;
type Inputs=blot_reuse_revision_inputs::Snapshot;
type FrozenInputs=blot_reuse_revision_inputs::Frozen;
type Prepared=blot_reuse_partial_dependency::Prepared;
type Emission=blot_reuse_partial_dependency::Result;
type PartialPreparation=blot_reuse_partial_dependency::Preparation;
type Previous=blot_reuse_partial_dependency::EntryPrevious;
type CheckedProject=blot_reuse_project_check::CheckedProject;
type Project=blot_reuse_project::Project;
type Capture=blot_reuse_artifact_capture::Capture;
type CaptureLease=blot_compile_workspace::CaptureLease;
let library_source_budget:i64=4194304;
struct Key {slot:u32=0,generation:u64=0}
struct CachedOutput {
    owner:Owner=Owner{..},entry_request:const u8[:]=default<const u8[:]>(),output_identity:Text=blot_support::none<const u8[:]>(),bytes:const u8[:]=default<const u8[:]>(),
    allocation_emission:blot_support::Option<blot_backend_allocation_emission::Snapshot> =blot_support::none<blot_backend_allocation_emission::Snapshot>(),
    array_costs:blot_support::Option<blot_backend_array_cost_explanation::Snapshot> =blot_support::none<blot_backend_array_cost_explanation::Snapshot>(),
    source_bytes:i64=0,modules:i64=0,policy:Policy=Policy{..},
}
fn initOutput(entry:const u8[:],identity:Text,result:const Emission&,modules:i64,policy:Policy)->CachedOutput,Error {
    var cached=CachedOutput{source_bytes:result.source_bytes,modules:modules,policy:policy,..};let owner,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {return cached,error;}cached.owner=owner;
    let failure=cached.copyOutput(entry,identity,result);if failure!=blot_error::Error.none {cached.deinit();return CachedOutput{..},failure;}return cached,blot_error::Error.none;
}
fn copyOutput(self_:CachedOutput&,entry:const u8[:],identity:Text,result:const Emission&)->Error {
    let request,error=self_.owner.copy(entry);if error!=blot_error::Error.none {return error;}self_.entry_request=request;if identity.present {let value,error=self_.owner.copy(identity.value);if error!=blot_error::Error.none {return error;}self_.output_identity=blot_support::some<const u8[:]>(value[..]);}
    let bytes,error=self_.owner.copy(result.result.compiled.bytes.items);if error!=blot_error::Error.none {return error;}self_.bytes=bytes;let allocation_emission .=result.result.compiled.allocation_emission;if allocation_emission {let copy,error=allocation_emission.clone();if error!=blot_error::Error.none {return error;}self_.allocation_emission=blot_support::some(copy);}if result.array_costs.present {let copy,error=result.array_costs.value.clone();if error!=blot_error::Error.none {return error;}self_.array_costs=blot_support::some(copy);}return blot_error::Error.none;
}
fn deinit(self_:CachedOutput&) {if self_.allocation_emission.present {self_.allocation_emission.value.deinit();}if self_.array_costs.present {self_.array_costs.value.deinit();}self_.owner.deinit();self_=CachedOutput{..};}
fn matches(self_:const CachedOutput&,entry:const u8[:],identity:Text,policy:Policy,explain_allocations:bool)->bool {if self_.allocation_emission.present!=explain_allocations || self_.array_costs.present!=explain_allocations || self_.entry_request!=entry || self_.policy!=policy || self_.output_identity.present!=identity.present {return false;}if identity.present && self_.output_identity.value!=identity.value {return false;}return true;}
fn emission(self_:const CachedOutput&)->Emission,Error {let compiled,error=blot_backend_core_backend::ownedResult(self_.bytes,self_.allocation_emission);if error!=blot_error::Error.none {return Emission{..},error;}var result=Emission{result:blot_reuse_dependency_consumer::Result{compiled:compiled,..},source_bytes:self_.source_bytes,cached_modules:self_.modules,..};if self_.array_costs.present {let copy,error=self_.array_costs.value.clone();if error!=blot_error::Error.none {result.deinit();return Emission{..},error;}result.array_costs=blot_support::some(copy);}return result,blot_error::Error.none;}
struct Current {prepared:Prepared=default<Prepared>(),artifacts:CaptureLease=CaptureLease{..},snapshot:FrozenInputs=FrozenInputs{..},output:blot_support::Option<CachedOutput> =blot_support::none<CachedOutput>()}
fn deinit(self_:Current&) {self_.artifacts.deinit();self_.prepared.deinit();self_.snapshot.deinit();if self_.output.present {self_.output.value.deinit();}self_=Current{..};}
struct Restored {inputs:blot_reuse_revision_inputs::Persisted=blot_reuse_revision_inputs::Persisted{..},output:CachedOutput=CachedOutput{..},entry_canonical:const u8[:]=default<const u8[:]>(),settings:Digest=[0;32],checkpoint_digest:blot_support::Option<Digest> =blot_support::none<Digest>(),owner:Owner=Owner{..}}
struct RestoredWire {settings:Digest,entry_request:const u8[:],entry_canonical:const u8[:],output_identity:Text,policy:Policy,wasm:const u8[:],source_bytes:i64,modules:i64,checkpoint_digest:blot_support::Option<Digest>,inputs:blot_reuse_revision_inputs::Wire}
fn restoredKey(compiler:Digest)->blot_reuse_dependency_format::Key {return blot_reuse_dependency_format::Key{compiler,blot_reuse_dependency_format::digest("blot-restored-output-v1"),[0;32],[0;32]};}
fn encodeRestoredWire(compiler:Digest,wire:RestoredWire)->u8[:],Error {return blot_reuse_dependency_format::encodeWithLimits(restoredKey(compiler),wire,blot_reuse_dependency_format::Limits{elements:67108864,..});}
fn decodeRestored(compiler:Digest,bytes:const u8[:])->Restored,Error {
    var wire,error=blot_reuse_dependency_format::decodeWithLimits<RestoredWire>(bytes,restoredKey(compiler),blot_reuse_dependency_format::Limits{elements:67108864,..});if error!=blot_error::Error.none {return Restored{..},error;}var entry_read=false;for file in wire.value.inputs.files {if file.key==wire.value.entry_canonical {entry_read=true;break;}}if !entry_read || wire.value.wasm.len==0 {wire.deinit();return Restored{..},blot_error::Error.invalid_artifact;}
    var result=Restored{settings:wire.value.settings,checkpoint_digest:wire.value.checkpoint_digest,..};let failure=result.copyRestored(wire.value);wire.deinit();if failure!=blot_error::Error.none {result.deinit();return Restored{..},failure;}return result,blot_error::Error.none;
}
fn copyRestored(self_:Restored&,wire:RestoredWire)->Error {
    let input,error=blot_reuse_revision_inputs::cloneWire(wire.inputs);if error!=blot_error::Error.none {return error;}self_.inputs=input;let owner,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {return error;}self_.owner=owner;let canonical,error=self_.owner.copy(wire.entry_canonical);if error!=blot_error::Error.none {return error;}self_.entry_canonical=canonical;let output_owner,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {return error;}self_.output.owner=output_owner;self_.output.policy=wire.policy;self_.output.source_bytes=wire.source_bytes;self_.output.modules=wire.modules;
    let request,error=self_.output.owner.copy(wire.entry_request);if error!=blot_error::Error.none {return error;}self_.output.entry_request=request;let bytes,error=self_.output.owner.copy(wire.wasm);if error!=blot_error::Error.none {return error;}self_.output.bytes=bytes;if wire.output_identity.present {let value,error=self_.output.owner.copy(wire.output_identity.value);if error!=blot_error::Error.none {return error;}self_.output.output_identity=blot_support::some<const u8[:]>(value[..]);}return blot_error::Error.none;
}
fn deinit(self_:Restored&) {self_.inputs.deinit();self_.output.deinit();self_.owner.deinit();self_=Restored{..};}
fn seedKey(compiler:Digest,settings:Digest)->blot_reuse_dependency_format::Key {return blot_reuse_dependency_format::Key{compiler,settings,blot_reuse_dependency_format::digest("blot-restart-seed-v1"),[0;32]};}
fn decodeSeed(compiler:Digest,settings:Digest,bytes:const u8[:])->OwnedFrozen,Error {var owner,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {return default<OwnedFrozen>(),error;}let value,error=blot_reuse_dependency_format::decodeWithOwner<Frozen>(owner,bytes,seedKey(compiler,settings),blot_reuse_dependency_format::Limits{elements:67108864,..});if error!=blot_error::Error.none {owner.deinit();return default<OwnedFrozen>(),error;}return OwnedFrozen{value,owner},blot_error::Error.none;}
struct FallbackStats {validated_modules:i64=0,reused_frontend_modules:i64=0,syntax_nodes:i64=0,body_elaborations:i64=0,body_lowerings:i64=0,recheck_body_elaborations:i64=0,reused_check_body_elaborations:i64=0,frozen_modules:i64=0,reused_core_bodies:i64=0,reused_entry_bodies:i64=0,entry_cutoff:blot_reuse_entry_frontend_cutoff::Stats=blot_reuse_entry_frontend_cutoff::Stats{..},module_cutoff:blot_reuse_entry_frontend_cutoff::Stats=blot_reuse_entry_frontend_cutoff::Stats{..},dependency_storage:blot_reuse_retained_dependency::Stats=blot_reuse_retained_dependency::Stats{..},portable_rejection:bool=false,library_modules:i64=0,relocated_modules:i64=0}
struct Stats {rebuilt_seed:bool=false,reused_output:bool=false,trivia_only:bool=false,restored_output:bool=false,inputs:blot_reuse_revision_inputs::Counts=blot_reuse_revision_inputs::Counts{..},fallback:FallbackStats=FallbackStats{..}}
fn jsonStringify(self_:FallbackStats,writer:blot_json::Writer&)->Error {return blot_json::jsonStringify(self_,writer);}
fn jsonStringify(self_:Stats,writer:blot_json::Writer&)->Error {return blot_json::jsonStringify(self_,writer);}
enum LibraryUpdate {keep,clear,replace{owner:Snapshot&}}
fn deinit(self_:LibraryUpdate&) {match self_ {replace payload=>{payload.owner.deinit();},_=>{}}self_=LibraryUpdate.keep;}
enum CandidateKind {compiled,unchanged}
enum CandidateStatus {prepared,committed,discarded}
struct Candidate {key:Key=Key{..}}
struct Epoch {live:bool=false,generation:u64=0,owner:Key=Key{..},references:u64=1,preparing:bool=false,active:Key=Key{..},token:u64=0}
struct CandidateState {live:bool=false,generation:u64=0,epoch:Key=Key{..},token:u64=0,base_revision:u64=0,settings_key:Digest=[0;32],stats:Stats=Stats{..},pending:blot_support::Option<Current> =blot_support::none<Current>(),seed:blot_support::Option<Seed> =blot_support::none<Seed>(),library:LibraryUpdate=LibraryUpdate.keep,emission:blot_support::Option<Emission> =blot_support::none<Emission>(),kind:CandidateKind=CandidateKind.compiled,status:CandidateStatus=CandidateStatus.prepared}
struct Session {key:Key=Key{..}}
struct SessionState {live:bool=false,generation:u64=0,allocation_owner:u64=0,seed:Seed=Seed{..},seed_settings:Digest=[0;32],current:blot_support::Option<Current> =blot_support::none<Current>(),library:Snapshot?=null,revisions:u64=0,last:Stats=Stats{..},epoch:Key=Key{..},policy:Policy=Policy{..},compiler_identity:blot_support::Option<Digest> =blot_support::none<Digest>(),profile_backend:bool=false,explain_allocations:bool=false,checkpoint:blot_support::Option<blot_backend_backend_checkpoint::Checkpoint> =blot_support::none<blot_backend_backend_checkpoint::Checkpoint>(),restored:blot_support::Option<Restored> =blot_support::none<Restored>()}
reusable var sessions:SessionState[>..]=[];
reusable var epochs:Epoch[>..]=[];
reusable var candidates:CandidateState[>..]=[];
fn valid(self_:Session)->bool {return self_.key.slot!=0 && self_.key.slot-1<sessions.len && sessions[self_.key.slot-1].live && sessions[self_.key.slot-1].generation==self_.key.generation;}
fn valid(self_:Candidate)->bool {return self_.key.slot!=0 && self_.key.slot-1<candidates.len && candidates[self_.key.slot-1].live && candidates[self_.key.slot-1].generation==self_.key.generation;}
fn state(self_:Session)->SessionState& {assert(self_.valid());return sessions[self_.key.slot-1];}
fn state(self_:Candidate)->CandidateState& {assert(self_.valid());return candidates[self_.key.slot-1];}
fn epoch(key:Key)->Epoch& {assert(key.slot!=0 && key.slot-1<epochs.len && epochs[key.slot-1].live && epochs[key.slot-1].generation==key.generation);return epochs[key.slot-1];}
fn releaseEpoch(key:Key) {let owner .= epoch(key);assert(owner.references!=0);owner.references--;if owner.references==0 {owner.live=false;epochs.free(key.slot-1);}}
fn init(seed:OwnedFrozen&,options:Options,allocation_owner:u64)->Session,Error {assert(options.input_mode==blot_reuse_project::InputMode.project && allocation_owner!=0);if sessions.len>=0xffffffff {return Session{..},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let value=Frozen{symbols:seed.owner.mutable(seed.value.symbols),modules:seed.owner.mutable(seed.value.modules)};let at=sessions.alloc_index(SessionState{live:true,generation:generation,allocation_owner:allocation_owner,seed:Seed{value:value,owner:seed.owner,..},seed_settings:blot_reuse_dependency_cli::settings(options),..});seed=default<OwnedFrozen>();return Session{Key{(at+1) as u32,generation}},blot_error::Error.none;}
fn initEmpty(options:Options,allocation_owner:u64)->Session,Error {var owner,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {return Session{..},error;}let symbols,error=blot_reuse_dependency_payload::alloc<blot_reuse_frozen_dependency::Symbol>(owner,1);if error!=blot_error::Error.none {owner.deinit();return Session{..},error;}symbols[0]=blot_reuse_frozen_dependency::Symbol{text:default<u8[:]>()};var seed=OwnedFrozen{Frozen{symbols:symbols,modules:default<blot_reuse_frozen_dependency::Module[:]>()},owner};let result,error=init(seed,options,allocation_owner);if error!=blot_error::Error.none {seed.deinit();}return result,error;}
fn bind(self_:Session)->Key,Error {let data .= self_.state();if data.epoch.slot!=0 {if epoch(data.epoch).owner!=self_.key {return Key{..},blot_error::Error.session_moved;}return data.epoch,blot_error::Error.none;}if epochs.len>=0xffffffff {return Key{..},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=epochs.alloc_index(Epoch{live:true,generation:generation,owner:self_.key,..});data.epoch=Key{(at+1) as u32,generation};return data.epoch,blot_error::Error.none;}
fn releaseSeed(self_:SessionState&) {self_.seed.deinit();}
fn ensureSharedSeed(self_:SessionState&)->Error {if self_.seed.snapshot {return blot_error::Error.none;}let error=blot_reuse_dependency_closure::validate(self_.seed.value);if error!=blot_error::Error.none {return error;}var owned=OwnedFrozen{self_.seed.value,self_.seed.owner};let snapshot,error=blot_reuse_retained_dependency::adopt(owned);if error!=blot_error::Error.none {return error;}assert(snapshot);snapshot.validated=true;self_.seed=Seed{value:snapshot.value,snapshot:snapshot,..};return blot_error::Error.none;}
fn deinit(self_:Session&) {if self_.key.slot==0 {return;}let data .= self_.state();if data.epoch.slot!=0 {let epoch .= epoch(data.epoch);assert(epoch.owner==self_.key && !epoch.preparing);if epoch.active.slot!=0 {Candidate{epoch.active}.discardPending();}epoch.owner=Key{..};}if data.current.present {data.current.value.deinit();}if data.checkpoint.present {data.checkpoint.value.deinit();}if data.restored.present {data.restored.value.deinit();}let library .=data.library;if library {library.deinit();}data.releaseSeed();if data.epoch.slot!=0 {releaseEpoch(data.epoch);}let at=self_.key.slot-1;data.live=false;self_=Session{..};sessions.free(at);}
fn paired(self_:Session,candidate:Candidate)->bool {if !self_.valid() || !candidate.valid() {return false;}let data .= self_.state();let value .= candidate.state();if value.status!=CandidateStatus.prepared || data.epoch.slot==0 {return false;}let owner .= epoch(data.epoch);return owner.owner==self_.key && value.epoch==data.epoch && owner.active==candidate.key && value.token==owner.token && value.base_revision==data.revisions;}
fn result(self_:Candidate)->const Emission? {let data .= self_.state();if !data.emission.present {return null;}return data.emission.value;}
fn stats(self_:Candidate)->Stats {return self_.state().stats;}
fn takeResult(self_:Candidate)->blot_support::Option<Emission> {let data .= self_.state();if data.status==CandidateStatus.prepared {return blot_support::none<Emission>();}let value=data.emission;data.emission=blot_support::none<Emission>();return value;}
fn discardPending(self_:Candidate) {let data .= self_.state();if data.status!=CandidateStatus.prepared {return;}if data.pending.present {data.pending.value.deinit();data.pending=blot_support::none<Current>();}if data.seed.present {data.seed.value.deinit();data.seed=blot_support::none<Seed>();}data.library.deinit();let epoch .= epoch(data.epoch);if epoch.active==self_.key {epoch.active=Key{..};}data.status=CandidateStatus.discarded;}
fn discard(self_:Candidate) {self_.discardPending();}
fn deinit(self_:Candidate&) {if self_.key.slot==0 {return;}self_.discardPending();let data .= self_.state();if data.emission.present {data.emission.value.deinit();}let epoch=data.epoch;let at=self_.key.slot-1;data.live=false;self_=Candidate{..};candidates.free(at);releaseEpoch(epoch);}
fn commit(self_:Session,candidate:Candidate)->bool {
    if !self_.paired(candidate) {return false;}let data .= self_.state();let value .= candidate.state();match value.kind {
        compiled=>{if data.current.present {data.current.value.deinit();}var library=value.library;if data.seed_settings!=value.settings_key {match library {keep=>{library=LibraryUpdate.clear;},_=>{}}}value.library=LibraryUpdate.keep;match library {keep=>{},clear,replace=>{let previous_library .=data.library;if previous_library {previous_library.deinit();data.library .= null;}}}match library {replace payload=>{data.library .= payload.owner;},_=>{}}
            if value.seed.present {data.releaseSeed();data.seed=value.seed.value;value.seed=blot_support::none<Seed>();}assert(value.pending.present);data.current=value.pending;value.pending=blot_support::none<Current>();if data.restored.present {data.restored.value.deinit();data.restored=blot_support::none<Restored>();}},
        unchanged=>{assert((data.current.present || data.restored.present) && !value.pending.present && !value.seed.present);},
    }data.seed_settings=value.settings_key;data.last=value.stats;data.revisions++;epoch(value.epoch).active=Key{..};value.status=CandidateStatus.committed;return true;
}
fn discard(self_:Session,candidate:Candidate)->bool {if !self_.paired(candidate) {return false;}candidate.discardPending();return true;}
struct Rejection {result:Emission=Emission{..},snapshot:Inputs=Inputs{..},stats:Stats=Stats{..}}
fn deinit(self_:Rejection&) {self_.result.deinit();self_.snapshot.deinit();self_=Rejection{..};}
fn takeResult(self_:Rejection&)->Emission {let result=self_.result;self_.result=Emission{..};self_.snapshot.deinit();self_=Rejection{..};return result;}
enum Preparation {inactive,ready{candidate:Candidate},rejected{value:Rejection}}
fn deinit(self_:Preparation&) {match self_ {inactive=>{},ready payload=>{var candidate=payload.candidate;candidate.deinit();},rejected payload=>{var value=payload.value;value.deinit();}}self_=Preparation.inactive;}
fn entryOffer(self_:SessionState&)->blot_support::Option<Previous> {if !self_.current.present {return blot_support::none<Previous>();}let previous .= self_.current.value;let prepared .= previous.prepared;let seed=self_.seed.value;if prepared.units.len==0 || prepared.entry!=prepared.units.len || prepared.units.len!=seed.modules.len+1 || prepared.cached!=seed.modules.len || prepared.paths.len!=prepared.units.len {return blot_support::none<Previous>();}for module,index in seed.modules {if module.core!=prepared.units[index] {return blot_support::none<Previous>();}}let source=previous.snapshot.view().capturedSource(prepared.paths[prepared.entry-1]);if !source.present {return blot_support::none<Previous>();}return blot_support::some(Previous{prepared:prepared,source:source.value,reuse_modules:true,..});}
fn bodyOffer(self_:SessionState&,options:Options)->blot_support::Option<Previous> {if self_.seed_settings!=blot_reuse_dependency_cli::settings(options) || !self_.current.present {return blot_support::none<Previous>();}let previous .= self_.current.value;let prepared .= previous.prepared;if prepared.entry==0 || prepared.entry>prepared.paths.len || prepared.paths.len!=prepared.units.len || prepared.body_caches.len!=prepared.units.len {return blot_support::none<Previous>();}let source=previous.snapshot.view().capturedSource(prepared.paths[prepared.entry-1]);if !source.present {return blot_support::none<Previous>();}return blot_support::some(Previous{prepared:prepared,source:source.value,body_only:true,..});}
fn frontendOffer(self_:SessionState&,options:Options)->blot_support::Option<Previous> {if self_.seed_settings!=blot_reuse_dependency_cli::settings(options) {return blot_support::none<Previous>();}let offer=self_.entryOffer();if offer.present {return offer;}return self_.bodyOffer(options);}
fn currentArtifacts(self_:SessionState&)->Capture? {if !self_.current.present {return null;}return self_.current.value.artifacts.borrow();}
fn busy(self_:SessionState&)->bool {if self_.epoch.slot==0 {return false;}let owner .= epoch(self_.epoch);return owner.preparing || owner.active.slot!=0;}
fn encodeCheckpoint(self_:Session,compiler:Digest,report:blot_backend_backend_checkpoint::Report&)->u8[:],Error {let data .= self_.state();if data.busy() {return default<u8[:]>(),blot_error::Error.revision_busy;}let artifacts .= data.currentArtifacts();if !artifacts {return default<u8[:]>(),blot_error::Error.no_successful_revision;}return blot_backend_backend_checkpoint::encodeReporting(compiler,artifacts,report);}
fn checkpointBytes(self_:Session,compiler:Digest)->u8[:],Error {var report=blot_backend_backend_checkpoint::Report{..};return self_.encodeCheckpoint(compiler,report);}
fn encodeSeed(self_:Session,compiler:Digest)->blot_support::Option<u8[:]>,Error {let data .= self_.state();if data.busy() {return blot_support::none<u8[:]>(),blot_error::Error.revision_busy;}if !data.current.present || data.seed.value.modules.len==0 {return blot_support::none<u8[:]>(),blot_error::Error.none;}let bytes,error=blot_reuse_dependency_format::encodeWithLimits(seedKey(compiler,data.seed_settings),data.seed.value,blot_reuse_dependency_format::Limits{elements:67108864,..});if error!=blot_error::Error.none {return blot_support::none<u8[:]>(),error;}return blot_support::some(bytes),blot_error::Error.none;}
fn encodeRestored(self_:Session,compiler:Digest,checkpoint:blot_support::Option<const u8[:]>)->blot_support::Option<u8[:]>,Error {
    let data .= self_.state();if data.busy() {return blot_support::none<u8[:]>(),blot_error::Error.revision_busy;}if !data.current.present || !data.current.value.output.present {return blot_support::none<u8[:]>(),blot_error::Error.none;}let current .= data.current.value;let output .= current.output.value;let prepared .= current.prepared;if output.allocation_emission.present || prepared.entry==0 || prepared.entry>prepared.paths.len {return blot_support::none<u8[:]>(),blot_error::Error.none;}let observed,error=blot_reuse_revision_inputs::capturePersisted(current.snapshot);if error!=blot_error::Error.none || !observed.present {return blot_support::none<u8[:]>(),error;}var digest=blot_support::none<Digest>();if checkpoint.present {digest=blot_support::some(blot_reuse_dependency_format::digest(checkpoint.value));}let bytes,error=encodeRestoredWire(compiler,RestoredWire{settings:data.seed_settings,entry_request:output.entry_request,entry_canonical:prepared.paths[prepared.entry-1],output_identity:output.output_identity,policy:output.policy,wasm:output.bytes,source_bytes:output.source_bytes,modules:output.modules,checkpoint_digest:digest,inputs:observed.value});blot_reuse_revision_inputs::releaseWire(observed.value);if error!=blot_error::Error.none {return blot_support::none<u8[:]>(),error;}return blot_support::some(bytes),blot_error::Error.none;
}
fn adoptCachedSeed(self_:Session,seed:OwnedFrozen&)->Error {let data .= self_.state();if data.current.present || data.seed.value.modules.len!=0 {return blot_error::Error.seed_in_use;}if data.busy() {return blot_error::Error.candidate_active;}let error=blot_reuse_dependency_closure::validate(seed.value);if error!=blot_error::Error.none {return error;}let owner,error=blot_reuse_retained_dependency::adopt(seed);if error!=blot_error::Error.none {return error;}assert(owner);owner.validated=true;data.releaseSeed();data.seed=Seed{value:owner.value,snapshot:owner,..};return blot_error::Error.none;}
