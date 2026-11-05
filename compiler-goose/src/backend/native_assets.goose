// Captured native inputs and generated modules share transactional ownership.
namespace blot_backend_native_assets;
import reuse.source_overlays;
import support.option;
import support.error;
import support.json;
enum Kind {json,catalog,text,tunables,wgsl,reference}
struct Definition {module: const u8[:],path: const u8[:],kind: Kind,ty: blot_support::Option<const u8[:]> = blot_support::none<const u8[:]>(),export_name: blot_support::Option<const u8[:]> = blot_support::none<const u8[:]>(),mediaType: blot_support::Option<const u8[:]> = blot_support::none<const u8[:]>()}
struct Options {imports: const Definition[:] = [],roots: const const u8[:][:] = []}
struct Stats {parsed: i64 = 0,reused: i64 = 0,inputBytes: i64 = 0,generatedBytes: i64 = 0}
struct Dependency {path: const u8[:],sha256: blot_support::Option<u8[64]>}
struct Resource {id: u32,path: const u8[:],mediaType: const u8[:],sha256: u8[64],bytes: const u8[:],key: const u8[:]}
struct Issue {filename: const u8[:],start: u32 = 0,end: u32 = 0,code: const u8[:],message: const u8[:]}
struct Module {module: const u8[:],definition: Definition,canonical: const u8[:],bytes: const u8[:],source: const u8[:]}
struct Modules {storage: Module[:] = [],items: Module[:] = []}
struct Sources {storage: blot_reuse_source_overlays::Source[:] = [],items: blot_reuse_source_overlays::Source[:] = []}
struct Dependencies {storage: Dependency[:] = [],items: Dependency[:] = []}
struct Resources {storage: Resource[:] = [],items: Resource[:] = []}
struct Texts {storage: const u8[:][:] = [],items: const u8[:][:] = []}
struct Candidate {owner_id: u64 = 0,modules: Modules = Modules {..},sources: Sources = Sources {..},dependencies: Dependencies = Dependencies {..},resources: Resources = Resources {..},texts: Texts = Texts {..},stats: Stats = Stats {..},issue: blot_support::Option<Issue> = blot_support::none<Issue>()}
struct Session {options: Options = Options {..},last: Candidate? = null,texts: Texts = Texts {..},owned_definitions: Definition[:] = [],owned_roots: const u8[:][:] = []}
fn jsonStringify(self: Definition,writer: blot_json::Writer&) {writer.beginObject();writer.field("module",self.module);writer.field("path",self.path);writer.field("kind",self.kind);writer.field("type",self.ty);writer.field("export",self.export_name);writer.field("mediaType",self.mediaType);writer.endObject();}
