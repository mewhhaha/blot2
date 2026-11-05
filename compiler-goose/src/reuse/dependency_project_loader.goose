// Wire discovery facts become publishable only after current-source admission.
namespace blot_reuse_dependency_project_loader;
import reuse.project;
import reuse.frozen_dependency;
import reuse.dependency_format;
import reuse.dependency_closure;
import reuse.dependency_payload;
import support.native;
import support.error;
type Error=blot_error::Error;
type Frozen=blot_reuse_frozen_dependency::FrozenDependency;
type OwnedFrozen=blot_reuse_dependency_payload::Owned<Frozen>;
type Digest=u8[32];
struct Stats {decode_us:i64=0,validation_us:i64=0,source_us:i64=0,source_bytes:i64=0}
fn elapsed(at:u64)->i64 {let now=blot_native::clock_ns();if now<at {return 0;}return ((now-at)/1000) as i64;}
fn sameKey(left:blot_reuse_dependency_format::Key,right:blot_reuse_dependency_format::Key)->bool {return left.compiler==right.compiler && left.settings==right.settings && left.source==right.source && left.dependencies==right.dependencies;}
fn load<P>(provider:P&,bytes:const u8[:],compiler:Digest,settings:Digest,options:blot_reuse_project::Options,stats:Stats&)->OwnedFrozen,Error {
    var owner,opened=blot_reuse_dependency_payload::init();if opened!=Error.none {return OwnedFrozen{value:default<Frozen>(),..},opened;}let value,error=loadCandidate(provider,owner,bytes,compiler,settings,options,stats);if error!=Error.none {owner.deinit();return OwnedFrozen{value:default<Frozen>(),..},error;}return OwnedFrozen{value,owner},Error.none;
}
fn loadCandidate<P>(provider:P&,owner:blot_reuse_dependency_payload::Owner&,bytes:const u8[:],compiler:Digest,settings:Digest,options:blot_reuse_project::Options,stats:Stats&)->Frozen,Error {
    var expected,header_error=blot_reuse_dependency_format::inspectKey(bytes);if header_error!=Error.none {return default<Frozen>(),header_error;}expected.compiler=compiler;expected.settings=settings;
    var at=blot_native::clock_ns();let candidate,error=blot_reuse_dependency_format::decodeWithOwner<Frozen>(owner,bytes,expected);if error!=Error.none {return default<Frozen>(),error;}stats.decode_us=elapsed(at);
    if candidate.modules.len>=options.max_files {return default<Frozen>(),Error.file_limit;}at=blot_native::clock_ns();let validation_error=blot_reuse_dependency_closure::validate(candidate);if validation_error!=Error.none {return default<Frozen>(),validation_error;}stats.validation_us=elapsed(at);at=blot_native::clock_ns();var found_prelude=false;
    for module in candidate.modules {
        var canonical:u8[>..<]=[];let canonical_error=provider.canonical(module.identity.normalized_path,canonical);if canonical_error!=Error.none {return default<Frozen>(),canonical_error;}
        var source:u8[>..<]=[];let read_error=provider.read(canonical,options.max_source_bytes,source);if read_error!=Error.none {return default<Frozen>(),read_error;}
        let producer_error=blot_reuse_dependency_closure::validateProducer(module,canonical,source);if producer_error!=Error.none {return default<Frozen>(),producer_error;}
        if stats.source_bytes>options.max_total_source_bytes || source.len>options.max_total_source_bytes-stats.source_bytes {return default<Frozen>(),Error.source_limit;}stats.source_bytes+=source.len;
        if module.identity.prelude {if !options.prelude_path.present || canonical!=options.prelude_path.value {return default<Frozen>(),Error.stale_artifact;}found_prelude=true;}
        for request in module.source_imports {
            var resolved:u8[>..<]=[];let resolve_error=provider.resolve(canonical,request.path,options,resolved);if resolve_error!=Error.none {return default<Frozen>(),resolve_error;}var target:u8[>..<]=[];let target_error=provider.canonical(resolved,target);if target_error!=Error.none {return default<Frozen>(),target_error;}
            if request.target==0 || request.target>candidate.modules.len {return default<Frozen>(),Error.invalid_artifact;}if target!=candidate.modules[request.target-1].identity.normalized_path {return default<Frozen>(),Error.stale_artifact;}
        }
    }
    if found_prelude!=options.prelude_path.present || !sameKey(expected,blot_reuse_dependency_closure::payloadKey(compiler,settings,candidate)) {return default<Frozen>(),Error.stale_artifact;}stats.source_us=elapsed(at);return candidate,Error.none;
}
