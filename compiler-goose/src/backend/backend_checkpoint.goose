// Portable candidates own no current compilation authority. Current source,
// semantic inputs and optimizer dependencies are always admitted again.
namespace blot_backend_backend_checkpoint;
import reuse.artifact_capture;
import reuse.code_artifacts;
import reuse.principal_archive;
import reuse.optimized_archive;
import reuse.semantic_archive;
import reuse.dependency_format;
import backend.optimized_bodies;
import support.native;
import support.error;
import support.option;
type Error=blot_error::Error;
type Digest=u8[32];
type Capture=blot_reuse_artifact_capture::Capture;
type Factory=blot_reuse_artifact_capture::Factory;
type Principal=blot_reuse_principal_archive::Archive;
type Optimizer=blot_backend_optimized_bodies::Capture;
type Semantic=blot_reuse_semantic_archive::Archive<Factory>;
struct Wire {principal:const u8[:],optimizer:const u8[:],semantic:const u8[:]}
struct Report {semantic_over_limit:bool=false}
fn key(compiler:Digest)->blot_reuse_dependency_format::Key {return blot_reuse_dependency_format::Key{compiler,blot_reuse_dependency_format::digest("blot-backend-checkpoint-v6:selected-implementations"),[0;32],[0;32]};}
reusable[] var digests:Digest[>..]=[];
fn encode(compiler:Digest,source:const Capture&)->u8[:],Error {var report=Report{..};return encodeReporting(compiler,source,report);}
fn encodeReporting(compiler:Digest,source:const Capture&,report:Report&)->u8[:],Error {
    if !source.emission.sealed || !source.metadata.pools.present {return [],Error.invalid_artifact;}let pins=source.metadata.pools.value.modules;let stamps=digests.alloc_slice(pins.len);for pin,index in pins {if pin.stamp.present {stamps[index]=pin.stamp.value;}else {stamps[index]=blot_reuse_code_artifacts::stamp(pin.module);}}
    let principal,error=blot_reuse_principal_archive::encodeWithDigests(compiler,source.metadata,blot_support::some(stamps[:]));if error!=Error.none {if stamps.len!=0 {digests.free_slice(stamps);}return [],error;}
    var optimizer:u8[:]=[];if source.optimized {let bytes,error=blot_reuse_optimized_archive::encode(compiler,source.optimized);if error!=Error.none {blot_reuse_dependency_format::release(principal);if stamps.len!=0 {digests.free_slice(stamps);}return [],error;}optimizer=bytes;}
    let semantic,error=blot_reuse_semantic_archive::encodeWithDigests(compiler,source,blot_support::some(stamps[:]),report.semantic_over_limit);if stamps.len!=0 {digests.free_slice(stamps);}if error!=Error.none {blot_reuse_dependency_format::release(principal);blot_reuse_dependency_format::release(optimizer);return [],error;}var owner:u8[:]=[];if semantic.present {owner=semantic.value;}
    let bytes,error=blot_reuse_dependency_format::encodeWithLimits(key(compiler),Wire{principal,optimizer,owner},blot_reuse_dependency_format::Limits{elements:67108864,..});blot_reuse_dependency_format::release(principal);blot_reuse_dependency_format::release(optimizer);blot_reuse_dependency_format::release(owner);return bytes,error;
}
struct SemanticOwner {archive:Semantic=Semantic.inactive,capture:Capture?=null}
struct Storage {live:bool=false,generation:u64=0,principal:Principal=Principal{..},optimizer:Optimizer=Optimizer{..},optimizer_ref:Optimizer?=null,semantic:SemanticOwner=SemanticOwner{..},semantic_ref:SemanticOwner?=null}
var inactive:Storage=Storage{..};
reusable var storage:Storage[>..]=[];
struct Checkpoint {slot:u32=0,generation:u64=0,principal:Principal&=inactive.principal,optimizer:(Optimizer?)&=inactive.optimizer_ref,semantic:(SemanticOwner?)&=inactive.semantic_ref}
fn valid(self:Checkpoint)->bool {return self.slot!=0 && self.slot-1<storage.len && storage[self.slot-1].live && storage[self.slot-1].generation==self.generation;}
fn deinit(self:Checkpoint&) {if self.slot==0 {return;}assert(self.valid());let at=self.slot-1;let state:Storage&=storage[at];state.principal.deinit();state.optimizer.deinit();state.semantic.archive.deinit();state.live=false;self=Checkpoint{..};storage.free(at);}
fn decode(factory:Factory&,compiler:Digest,bytes:const u8[:])->Checkpoint,Error {
    var wire,error=blot_reuse_dependency_format::decodeWithLimits<Wire>(bytes,key(compiler),blot_reuse_dependency_format::Limits{elements:67108864,..});if error!=Error.none {return Checkpoint{..},error;}
    if storage.len>=0xffffffff {wire.deinit();return Checkpoint{..},Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=storage.alloc_index(Storage{live:true,generation:generation,..});let state:Storage&=storage[at];var result=Checkpoint{slot:(at+1) as u32,generation:generation,principal:state.principal,optimizer:state.optimizer_ref,semantic:state.semantic_ref,..};
    let principal,error=blot_reuse_principal_archive::decode(compiler,wire.value.principal);if error!=Error.none {result.deinit();wire.deinit();return Checkpoint{..},error;}state.principal=principal;
    if wire.value.optimizer.len!=0 {let optimizer,error=blot_reuse_optimized_archive::decode(compiler,wire.value.optimizer);if error!=Error.none {result.deinit();wire.deinit();return Checkpoint{..},error;}state.optimizer=optimizer;state.optimizer_ref .= state.optimizer;}
    if wire.value.semantic.len!=0 {let semantic,error=blot_reuse_semantic_archive::decode(factory,compiler,wire.value.semantic);if error!=Error.none {result.deinit();wire.deinit();return Checkpoint{..},error;}state.semantic.archive=semantic;state.semantic.capture .= state.semantic.archive.capture();state.semantic_ref .= state.semantic;}
    wire.deinit();return result,Error.none;
}
