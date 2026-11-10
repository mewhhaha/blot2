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
    if !source.emission.sealed || !source.metadata().pools.present {return default<u8[:]>(),blot_error::Error.invalid_artifact;}let pins=source.metadata().pools.value.modules;let stamps=digests.alloc_slice(pins.len);for pin,index in pins {if pin.stamp.present {stamps[index]=pin.stamp.value;}else {stamps[index]=blot_reuse_code_artifacts::stamp(pin.module);}}
    let principal,error=blot_reuse_principal_archive::encodeWithDigests(compiler,source.metadata(),blot_support::some<const Digest[:]>(stamps[..]));if error!=blot_error::Error.none {if stamps.len!=0 {digests.free_slice(stamps);}return default<u8[:]>(),error;}
    var optimizer:u8[:] = default<u8[:]>();let optimized .=source.optimized;if optimized {let bytes,error=blot_reuse_optimized_archive::encode(compiler,optimized);if error!=blot_error::Error.none {blot_reuse_dependency_format::release(principal);if stamps.len!=0 {digests.free_slice(stamps);}return default<u8[:]>(),error;}optimizer=bytes;}
    let semantic,error=blot_reuse_semantic_archive::encodeWithDigests(compiler,source,blot_support::some<const Digest[:]>(stamps[..]),report.semantic_over_limit);if stamps.len!=0 {digests.free_slice(stamps);}if error!=blot_error::Error.none {blot_reuse_dependency_format::release(principal);blot_reuse_dependency_format::release(optimizer);return default<u8[:]>(),error;}var owner:u8[:] = default<u8[:]>();if semantic.present {owner=semantic.value;}
    let bytes,error=blot_reuse_dependency_format::encodeWithLimits(key(compiler),Wire{principal,optimizer,owner},blot_reuse_dependency_format::Limits{elements:67108864,..});blot_reuse_dependency_format::release(principal);blot_reuse_dependency_format::release(optimizer);blot_reuse_dependency_format::release(owner);return bytes,error;
}
struct SemanticOwner {archive:Semantic=default<Semantic>(),capture:Capture?=null}
struct OptimizerSlot {value:Optimizer?=null}
struct SemanticSlot {value:SemanticOwner?=null}
struct Storage {live:bool=false,generation:u64=0,principal:Principal=Principal{..},optimizer_header:i64=-1,optimizer_ref:OptimizerSlot=OptimizerSlot{},semantic:SemanticOwner=SemanticOwner{..},semantic_ref:SemanticSlot=SemanticSlot{}}
var inactive:Storage=Storage{..};
reusable var storage:Storage[>..]=[];
reusable var optimizer_headers:Optimizer[>..]=[];
struct Checkpoint {slot:u32=0,generation:u64=0,principal:Principal& =inactive.principal,optimizer:OptimizerSlot& =inactive.optimizer_ref,semantic:SemanticSlot& =inactive.semantic_ref}
fn valid(self_:Checkpoint)->bool {return self_.slot!=0 && self_.slot-1<storage.len && storage[self_.slot-1].live && storage[self_.slot-1].generation==self_.generation;}
fn principalArchive(self_:Checkpoint)->const Principal& {
 assert(self_.valid());let principal:const Principal& =storage[self_.slot-1].principal;
 assert(self_.principal .==principal);return principal;
}
fn deinit(self_:Checkpoint&) {if self_.slot==0 {return;}assert(self_.valid());let at=self_.slot-1;let state:Storage& =storage[at];state.principal.deinit();let optimizer .= state.optimizer_ref.value;if optimizer {optimizer.deinit();assert(state.optimizer_header>=0);optimizer_headers.free(state.optimizer_header);}state.optimizer_ref.value .= null;state.optimizer_header=-1;state.semantic.archive.deinit();state.live=false;self_=Checkpoint{..};storage.free(at);}
fn publishOptimizer(value:Optimizer)->i64 {return optimizer_headers.alloc_index(blot_backend_optimized_bodies::checkedView(value));}
fn decode(factory:Factory&,compiler:Digest,bytes:const u8[:])->Checkpoint,Error {
    var wire,error=blot_reuse_dependency_format::decodeWithLimits<Wire>(bytes,key(compiler),blot_reuse_dependency_format::Limits{elements:67108864,..});if error!=blot_error::Error.none {return Checkpoint{..},error;}
    if storage.len>=0xffffffff {wire.deinit();return Checkpoint{..},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=storage.alloc_index(Storage{live:true,generation:generation,..});let state:Storage& =storage[at];var result=Checkpoint{slot:(at+1) as u32,generation:generation,principal:state.principal,optimizer:state.optimizer_ref,semantic:state.semantic_ref,..};
    let principal,error=blot_reuse_principal_archive::decode(compiler,wire.value.principal);if error!=blot_error::Error.none {result.deinit();wire.deinit();return Checkpoint{..},error;}state.principal=principal;
    if wire.value.optimizer.len!=0 {let optimizer,error=blot_reuse_optimized_archive::decode(compiler,wire.value.optimizer);if error!=blot_error::Error.none {result.deinit();wire.deinit();return Checkpoint{..},error;}let header=publishOptimizer(optimizer);state.optimizer_header=header;state.optimizer_ref.value .= optimizer_headers[header];}
    if wire.value.semantic.len!=0 {let semantic,error=blot_reuse_semantic_archive::decode(factory,compiler,wire.value.semantic);if error!=blot_error::Error.none {result.deinit();wire.deinit();return Checkpoint{..},error;}state.semantic.archive=semantic;state.semantic.capture .= state.semantic.archive.capture();state.semantic_ref.value .= state.semantic;}
    wire.deinit();return result,blot_error::Error.none;
}
