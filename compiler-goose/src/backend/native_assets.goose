// Captured native inputs and generated modules share transactional ownership.
namespace blot_backend_native_assets;
import reuse.source_overlays;
import support.option;
import support.error;
import support.json;
enum Kind {json,catalog,text,tunables,wgsl,reference}
struct Definition {module: const u8[:],path: const u8[:],kind: Kind,ty: blot_support::Option<const u8[:]> = blot_support::none<const u8[:]>(),export_name: blot_support::Option<const u8[:]> = blot_support::none<const u8[:]>(),mediaType: blot_support::Option<const u8[:]> = blot_support::none<const u8[:]>()}
struct Options {imports: const Definition[:] = default<const Definition[:]>(),roots: const (const u8[:])[:] = default<const (const u8[:])[:]>()}
struct Stats {parsed: i64 = 0,reused: i64 = 0,inputBytes: i64 = 0,generatedBytes: i64 = 0}
struct Dependency {path: const u8[:],sha256: blot_support::Option<u8[64]>}
struct Resource {id: u32,path: const u8[:],mediaType: const u8[:],sha256: u8[64],bytes: const u8[:],key: const u8[:]}
struct Issue {filename: const u8[:],start: u32 = 0,end: u32 = 0,code: const u8[:],message: const u8[:]}
struct Module {module: const u8[:],definition: Definition,canonical: const u8[:],bytes: const u8[:],source: const u8[:]}
struct Modules {storage: Module[:] = default<Module[:]>(),items: Module[:] = default<Module[:]>()}
struct Sources {storage: blot_reuse_source_overlays::Source[:] = default<blot_reuse_source_overlays::Source[:]>(),items: blot_reuse_source_overlays::Source[:] = default<blot_reuse_source_overlays::Source[:]>()}
struct Dependencies {storage: Dependency[:] = default<Dependency[:]>(),items: Dependency[:] = default<Dependency[:]>()}
struct Resources {storage: Resource[:] = default<Resource[:]>(),items: Resource[:] = default<Resource[:]>()}
struct TextRun {start:i64=0,len:i64=0}
struct Texts {storage: TextRun[:] = default<TextRun[:]>(),items: TextRun[:] = default<TextRun[:]>()}
struct Candidate {owner_id: u64 = 0,allocation_index:i64=-1,modules: Modules = Modules {..},sources: Sources = Sources {..},dependencies: Dependencies = Dependencies {..},resources: Resources = Resources {..},texts: Texts = Texts {..},stats: Stats = Stats {..},issue: blot_support::Option<Issue> = blot_support::none<Issue>()}
struct Session {options: Options = Options {..},last: Candidate? = null,texts: Texts = Texts {..},owned_definitions: Definition[:] = default<Definition[:]>(),owned_roots: const u8[:][:] = default<const u8[:][:]>()}
fn jsonStringify(self_: Definition,writer: blot_json::Writer&) -> blot_error::Error {writer.beginObject();writer.field("module",self_.module);writer.field("path",self_.path);writer.field("kind",self_.kind);writer.field("type",self_.ty);writer.field("export",self_.export_name);writer.field("mediaType",self_.mediaType);writer.endObject();return writer.failure;}
import dictionary;
import .native_asset_readers;
import .native_asset_wgsl;
import reuse.project;
import support.pooled_buffer;
import support.native;
import support.path;
import support.sha256;
type Error = blot_error::Error;
type Source = blot_reuse_source_overlays::Source;
let maximum_file: i64 = 16777216;
let maximum_total: i64 = 67108864;
reusable var candidates: Candidate[>..] = [];
reusable[] var module_runs: Module[>..] = [];
reusable[] var source_runs: Source[>..] = [];
reusable[] var dependency_runs: Dependency[>..] = [];
reusable[] var resource_runs: Resource[>..] = [];
reusable[] var text_runs: TextRun[>..] = [];
reusable[] var text_bytes: u8[>..] = [];
reusable[] var definition_runs: Definition[>..] = [];
reusable[] var root_runs: const u8[:][>..] = [];
fn own<C>(self_: C&,bytes: const u8[:]) -> const u8[:],Error {if bytes.len == 0 {return default<const u8[:]>(),blot_error::Error.none;}let copied = text_bytes.alloc_slice(bytes.len);for index in 0..bytes.len {copied[index] = bytes[index];}let first:const u8& =copied[0];let start=text_bytes.index_of(first);let error = blot_support_pooled_buffer::push(self_.texts,TextRun{start,copied.len},text_runs);if error != blot_error::Error.none {text_bytes.free_slice(copied);return default<const u8[:]>(),error;}return copied,blot_error::Error.none;}
fn freeTexts(self_: Texts&) {for run in self_.items {if run.len == 0 {continue;}text_bytes.free_slice(text_bytes[run.start..run.start + run.len]);}blot_support_pooled_buffer::deinit(self_,text_runs);}
fn push(self_: Modules&,module: Module) -> Error {return blot_support_pooled_buffer::push(self_,module,module_runs);}
fn push(self_: Sources&,source: Source) -> Error {return blot_support_pooled_buffer::push(self_,source,source_runs);}
fn push(self_: Dependencies&,dependency: Dependency) -> Error {return blot_support_pooled_buffer::push(self_,dependency,dependency_runs);}
fn push(self_: Resources&,resource: Resource) -> Error {return blot_support_pooled_buffer::push(self_,resource,resource_runs);}
fn deinit(self_: Candidate&) {if self_.owner_id == 0 {return;}let index=self_.allocation_index;assert(index>=0 && index<candidates.len);let canonical:Candidate& =candidates[index];assert(self_ .== canonical);blot_support_pooled_buffer::deinit(self_.modules,module_runs);blot_support_pooled_buffer::deinit(self_.sources,source_runs);blot_support_pooled_buffer::deinit(self_.dependencies,dependency_runs);blot_support_pooled_buffer::deinit(self_.resources,resource_runs);self_.texts.freeTexts();self_ = Candidate {..};candidates.free(index);}
fn fail(self_: Candidate&,filename: const u8[:],code: const u8[:],message: const u8[:]) {self_.issue = blot_support::some(Issue {filename: filename,code: code,message: message,..});}
fn validPath(path: const u8[:]) -> bool {if path.len == 0 || path[0] != '/' || !blot_reuse_source_overlays::utf8_valid(path) {return false;}for byte in path {if byte == 0 {return false;}}return true;}
fn validMediaType(value: const u8[:]) -> bool {if value.len == 0 || value.len > 1024 {return false;}for byte in value {if byte == '\r' || byte == '\n' || byte == 0 {return false;}}var at: i64 = 0;var units: i64 = 0;while at < value.len {let point,length,valid = blot_backend_native_asset_readers::decodePoint(value,at);if !valid {return false;}at += length;units++;if point > 65535 {units++;}if units > 256 {return false;}}return true;}
fn identifier(name: const u8[:],upper: bool) -> bool {if name.len == 0 || name == "_" {return false;}if upper {if name[0] < 'A' || name[0] > 'Z' {return false;}for builtin in ["Unit","Bool","U32","F32","Array","List"] {if name == builtin {return false;}}}else if (name[0] < 'a' || name[0] > 'z') && name[0] != '_' {return false;}for byte in name[1..] {if !((byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || (byte >= '0' && byte <= '9') || byte == '_') {return false;}}for word in ["const","let","type","data","effect","is","func","do","use","return","yield","break","for","ever","in","case","of","if","then","else","as","import","infix","infixl","infixr","self","where"] {if word == name {return false;}}return true;}
fn copyDefinition<C>(self_: C&,definition: Definition) -> Definition,Error {
    var result = definition;let module,error = self_.own(definition.module);if error != blot_error::Error.none {return Definition {..},error;}result.module = module;let path,path_error = self_.own(definition.path);if path_error != blot_error::Error.none {return Definition {..},path_error;}result.path = path;
    if definition.ty.present {let value,error = self_.own(definition.ty.value);if error != blot_error::Error.none {return Definition {..},error;}result.ty = blot_support::some(value);}if definition.export_name.present {let value,error = self_.own(definition.export_name.value);if error != blot_error::Error.none {return Definition {..},error;}result.export_name = blot_support::some(value);}if definition.mediaType.present {let value,error = self_.own(definition.mediaType.value);if error != blot_error::Error.none {return Definition {..},error;}result.mediaType = blot_support::some(value);}return result,blot_error::Error.none;
}
fn init(options: Options) -> Session,Error {
    if options.imports.len > 4096 || options.roots.len > 4096 - options.imports.len {return Session {..},blot_error::Error.asset_limit;}var self_ = Session {..};
    fn copy() -> Error {
        if options.imports.len != 0 {self_.owned_definitions = definition_runs.alloc_slice(options.imports.len);}for definition,index in options.imports {if !validPath(definition.module) || !validPath(definition.path) || !blot_backend_native_asset_readers::ends(definition.module,".blot") {return blot_error::Error.invalid_native_assets;}if definition.kind == Kind.reference {if !definition.ty.present || !definition.export_name.present || !definition.mediaType.present || !identifier(definition.ty.value,true) || !identifier(definition.export_name.value,false) || !validMediaType(definition.mediaType.value) {return blot_error::Error.invalid_native_assets;}}else if definition.ty.present || definition.export_name.present || definition.mediaType.present {return blot_error::Error.invalid_native_assets;}let owned,error = self_.copyDefinition(definition);if error != blot_error::Error.none {return error;}self_.owned_definitions[index] = owned;}
        if options.roots.len != 0 {self_.owned_roots = root_runs.alloc_slice(options.roots.len);}for root,index in options.roots {if !validPath(root) {return blot_error::Error.invalid_native_assets;}let owned,error = self_.own(root);if error != blot_error::Error.none {return error;}self_.owned_roots[index] = owned;}self_.options = Options {imports: self_.owned_definitions,roots: self_.owned_roots};return blot_error::Error.none;
    }
    let error = copy();if error != blot_error::Error.none {self_.deinit();}return self_,error;
}
fn deinit(self_: Session&) {let last .=self_.last;if last {last.deinit();self_.last .= null;}self_.options = Options {..};if self_.owned_definitions.len != 0 {definition_runs.free_slice(self_.owned_definitions);}if self_.owned_roots.len != 0 {root_runs.free_slice(self_.owned_roots);}self_.owned_definitions = default<Definition[:]>();self_.owned_roots = default<const u8[:][:]>();self_.texts.freeTexts();}
fn commit(self_: Session&,candidate: Candidate&) {assert(candidate.owner_id != 0 && !candidate.issue.present);let last .=self_.last;if last {last.deinit();}self_.last .= candidate;}
fn reusable_(self_: const Session&,module: const u8[:],input: const u8[:],kind: Kind,bytes: const u8[:]) -> blot_support::Option<Module> {if !self_.last {return blot_support::none<Module>();}for old in self_.last.modules.items {if old.definition.kind == kind && old.module == module && old.canonical == input && old.bytes == bytes {return blot_support::some<Module>(old);}}return blot_support::none<Module>();}
fn utf16Less(left: const u8[:],right: const u8[:]) -> bool {var l: i64 = 0;var r: i64 = 0;while true {if l == left.len {return r != right.len;}if r == right.len {return false;}let lp,ll,lv = blot_backend_native_asset_readers::decodePoint(left,l);let rp,rl,rv = blot_backend_native_asset_readers::decodePoint(right,r);assert(lv && rv);l += ll;r += rl;var lu = lp;var ru = rp;if lp > 65535 {lu = 55296 + ((lp - 65536) >> 10);}if rp > 65535 {ru = 55296 + ((rp - 65536) >> 10);}if lu != ru {return lu < ru;}if lp != rp {return lp < rp;}}}
fn definitionLess(left: Definition,right: Definition) -> bool {return utf16Less(left.module,right.module);}
fn dependencyLess(left: Dependency,right: Dependency) -> bool {return utf16Less(left.path,right.path);}
fn resourceLess(left: Resource,right: Resource) -> bool {return utf16Less(left.key,right.key);}
fn join<C>(self_: C&,left: const u8[:],right: const u8[:]) -> const u8[:],Error {var joined: u8[>..] = [];joined.append(left);if left.len != 0 && right.len != 0 {if left[left.len - 1] != '/' && right[0] != '/' {joined.push('/');}if left[left.len - 1] == '/' && right[0] == '/' {joined.append(right[1..]);}else {joined.append(right);}}else {joined.append(right);}return self_.own(joined);}
fn canonical(self_: Candidate&,path: const u8[:]) -> const u8[:],Error {var name: u8[>..<] = [];let error = blot_reuse_source_overlays::canonicalPath(path,name);if error != blot_error::Error.none {return [],error;}return self_.own(name);}
fn basename(path: const u8[:]) -> const u8[:] {var first = path.len;while first != 0 && path[first - 1] != '/' {first--;}return path[first..];}
struct Definitions {storage: Definition[:] = default<Definition[:]>(),items: Definition[:] = default<Definition[:]>()}
fn push(self_: Definitions&,definition: Definition) -> Error {return blot_support_pooled_buffer::push(self_,definition,definition_runs);}
fn append(self_: Definitions&,definitions: const Definition[:]) -> Error {return blot_support_pooled_buffer::append(self_,definitions,definition_runs);}
fn deinit(self_: Definitions&) {blot_support_pooled_buffer::deinit(self_,definition_runs);}
fn appendDiscovered(candidate: Candidate&,definitions: Definitions&,path: const u8[:],kind: Kind) -> Error {var spelling: u8[>..] = [];format(spelling,path,".blot");for definition in definitions.items {if definition.module == spelling {return blot_error::Error.none;}}if definitions.items.len >= 4096 {return blot_error::Error.asset_limit;}let module,error = candidate.own(spelling);if error != blot_error::Error.none {return error;}return definitions.push(Definition { module: module, path: path, kind: kind, .. });}
fn discover(candidate: Candidate&,root: const u8[:],overrides: const blot_reuse_source_overlays::Set&,definitions: Definitions&) -> Error {
    let paths: const u8[:][3] = ["assets/catalog.json","text.json","tunables.json"];let kinds: Kind[3] = [Kind.catalog,Kind.text,Kind.tunables];
    for known,index in paths {
        let path,error = candidate.join(root,known);if error != blot_error::Error.none {return error;}let name,name_error = candidate.canonical(path);if name_error != blot_error::Error.none {return name_error;}let overridden .= overrides.files.get(name);if overridden {if overridden.present {let appended = appendDiscovered(candidate,definitions,path,kinds[index]);if appended != blot_error::Error.none {return appended;}}continue;}
        var terminated: u8[>..] = [];terminated.append(path);terminated.push(0);let kind = blot_native::path_kind(terminated[0]);if kind < 0 {return blot_error::Error.io;}if kind == 1 {let appended = appendDiscovered(candidate,definitions,path,kinds[index]);if appended != blot_error::Error.none {return appended;}}
    }
    let asset_path,error = candidate.join(root,"assets");if error != blot_error::Error.none {return error;}var terminated: u8[>..] = [];terminated.append(asset_path);terminated.push(0);let directory = blot_native::directory_open(terminated[0]);if directory < 0 {return blot_error::Error.io;}
    if directory > 0 {
        fn enumerate() -> Error {var name: u8[>..<] = [];name.resize(256,0);while true {let count = blot_native::directory_next(directory,name[0],name.len as u64);if count < 0 {return blot_error::Error.io;}if count == 0 {return blot_error::Error.none;}if count > name.len {name.resize(count,0);continue;}let entry = name[..count];if !blot_backend_native_asset_readers::ends(entry,".wgsl") {continue;}let path,error = candidate.join(asset_path,entry);if error != blot_error::Error.none {return error;}let canonical,canonical_error = candidate.canonical(path);if canonical_error != blot_error::Error.none {return canonical_error;}let overridden .= overrides.files.get(canonical);if overridden && !overridden.present {continue;}let appended = appendDiscovered(candidate,definitions,path,Kind.wgsl);if appended != blot_error::Error.none {return appended;}}}
        let discovered = enumerate();blot_native::directory_close(directory);if discovered != blot_error::Error.none {return discovered;}
    }
    let canonical_assets,canonical_error = candidate.canonical(asset_path);if canonical_error != blot_error::Error.none {return canonical_error;}
    for entry in overrides.files.slots {if entry.tag == 0 || !entry.val.present || !blot_backend_native_asset_readers::ends(entry.key,".wgsl") {continue;}let parent = blot_support_path::dirname(entry.key);if !parent.present || parent.value != canonical_assets {continue;}let path,error = candidate.join(asset_path,basename(entry.key));if error != blot_error::Error.none {return error;}let appended = appendDiscovered(candidate,definitions,path,Kind.wgsl);if appended != blot_error::Error.none {return appended;}}
    return blot_error::Error.none;
}
// Zig 0.17's Linux open/read error names are part of the asset diagnostic.
fn ioName(errno: i32,reading: bool) -> const u8[:] {
    match errno {1=>"PermissionDenied",2,3=>"FileNotFound",5=>{if reading {return "InputOutput";}return "Unexpected";},6,19=>"NoDevice",9=>{if reading {return "NotOpenForReading";}return "Unexpected";},11=>"WouldBlock",12,105=>"SystemResources",13=>"AccessDenied",16=>"DeviceBusy",17=>"PathAlreadyExists",20=>"NotDir",21=>"IsDir",22=>{if reading {return "Unexpected";}return "BadPathName";},23=>"SystemFdQuotaExceeded",24=>"ProcessFdQuotaExceeded",26=>"FileBusy",27,75=>"FileTooBig",28=>"NoSpaceLeft",30=>"ReadOnlyFileSystem",36=>"NameTooLong",40=>"SymLinkLoop",84=>"BadPathName",95=>"FileLocksUnsupported",104=>"ConnectionResetByPeer",107=>"SocketUnconnected",_=>"Unexpected",}
}
fn inputFailure(candidate: Candidate&,filename: const u8[:],errno: i32,reading: bool) -> Error {var text: u8[>..] = [];format(text,"Unable to read asset: ",ioName(errno,reading));let message,error = candidate.own(text);if error != blot_error::Error.none {return error;}candidate.fail(filename,"asset_input",message);return blot_error::Error.none;}
fn readInput(candidate: Candidate&,filename: const u8[:],path: const u8[:]) -> const u8[:],bool,Error {
    var terminated: u8[>..] = [];terminated.append(path);terminated.push(0);var fd: i32 = -1;
    loop {fd = blot_native::open_read(terminated[0]);if fd >= 0 {break;}let errno = blot_native::last_errno();if errno == 4 {continue;}let error = inputFailure(candidate,filename,errno,false);return [],false,error;}
    var bytes: u8[>..<] = [];
    fn capture() -> const u8[:],bool,Error {
        loop {
            let start = bytes.len;let amount = min(65536,maximum_file + 1 - start);bytes.resize(start + amount,0);let count = blot_native::read(fd,bytes[start],amount as u64);
            if count < 0 {let errno = blot_native::last_errno();bytes.resize(start);if errno == 4 || errno == 110 {continue;}let error = inputFailure(candidate,filename,errno,true);return [],false,error;}
            bytes.resize(start + count);if bytes.len > maximum_file {candidate.fail(filename,"asset_limit","Asset input exceeds 16 MiB");return [],false,blot_error::Error.none;}if count == 0 {break;}
        }
        let owned,error = candidate.own(bytes);return owned,error == blot_error::Error.none,error;
    }
    let bytes_out,present,error = capture();blot_native::close(fd);return bytes_out,present,error;
}
fn digest(bytes: const u8[:]) -> u8[64] {var state = blot_support_sha256::init();blot_support_sha256::update(state,bytes);let hash = blot_support_sha256::final(state);let alphabet = "0123456789abcdef";var result: u8[64] = [0;64];for byte,index in hash {result[index * 2] = alphabet[byte >> 4];result[index * 2 + 1] = alphabet[byte & 15];}return result;}
fn resourceKey(candidate: Candidate&,path: const u8[:],media: const u8[:],digest: const u8[:]) -> const u8[:],Error {var bytes: u8[>..] = [];var writer = blot_json::Writer {out: bytes,options: blot_json::Options {..},..};writer.beginArray();writer.element(path);writer.element(media);writer.element(digest);writer.endArray();if writer.failure != blot_error::Error.none {return [],writer.failure;}return candidate.own(bytes);}
fn prepare(self_: Session&,entry: const u8[:],sources: const Source[:],asset_sources: const Source[:]) -> Candidate?,Error {
    if candidates.len >= 4294967295 {return null,blot_error::Error.out_of_memory;}let candidate_index=candidates.alloc_index(Candidate {owner_id: blot_native::fresh_owner_id(),..});let candidate:Candidate& =candidates[candidate_index];candidate.allocation_index=candidate_index;let overlay,overlay_error = blot_reuse_source_overlays::init(asset_sources,blot_reuse_project::Options {..});if overlay_error != blot_error::Error.none {candidate.deinit();return null,overlay_error;}var overrides = overlay;var definitions = Definitions {..};var discovered = Definitions {..};
    fn capture() -> Error {
        let imported = definitions.append(self_.options.imports);if imported != blot_error::Error.none {return imported;}for root in self_.options.roots {let error = discover(candidate,root,overrides,discovered);if error != blot_error::Error.none {return error;}}let appended = definitions.append(discovered.items);if appended != blot_error::Error.none {return appended;}if definitions.items.len > 4096 {return blot_error::Error.asset_limit;}for definition in definitions.items {if !validPath(definition.module) || !validPath(definition.path) {return blot_error::Error.invalid_native_assets;}}
        for index in 1..definitions.items.len {let item = definitions.items[index];var at = index;while at > 0 && definitionLess(item,definitions.items[at - 1]) {definitions.items[at] = definitions.items[at - 1];at--;}definitions.items[at] = item;}
        let canonical_entry,entry_error = candidate.canonical(entry);if entry_error != blot_error::Error.none {return entry_error;}var source_names: dictionary<const u8[:],bool> = dictionary<const u8[:],bool> {};for source in sources {let name,error = candidate.canonical(source.path);if error != blot_error::Error.none {return error;}if source_names.get(name) {return blot_error::Error.duplicate_source_path;}source_names.insert(name,true);}var module_names: dictionary<const u8[:],bool> = dictionary<const u8[:],bool> {};var loads: dictionary<const u8[:],const u8[:]> = dictionary<const u8[:],const u8[:]> {};
        for borrowed_definition in definitions.items {
            let owned,definition_error = candidate.copyDefinition(borrowed_definition);if definition_error != blot_error::Error.none {return definition_error;}let definition = owned;let module_path,module_error = candidate.canonical(definition.module);if module_error != blot_error::Error.none {return module_error;}if !validPath(module_path) {return blot_error::Error.invalid_native_assets;}if module_names.get(module_path) || source_names.get(module_path) || module_path == canonical_entry {return blot_error::Error.duplicate_asset_module;}module_names.insert(module_path,true);
            let input_path,input_error = candidate.canonical(definition.path);if input_error != blot_error::Error.none {return input_error;}if !validPath(input_path) {return blot_error::Error.invalid_native_assets;}var input: const u8[:] = default<const u8[:]>();var loaded = false;{let old .= loads.get(input_path);if old {input = old;loaded = true;}}
            if !loaded {
                let overridden .= overrides.files.get(input_path);
                if overridden {if !overridden.present {candidate.fail(definition.path,"asset_missing","Asset hidden by overlay");return blot_error::Error.none;}let bytes,error = candidate.own(overridden.value);if error != blot_error::Error.none {return error;}input = bytes;}
                else {let bytes,present,error = readInput(candidate,definition.path,input_path);if error != blot_error::Error.none {return error;}if !present {return blot_error::Error.none;}input = bytes;}
                if input.len > maximum_file {candidate.fail(definition.path,"asset_limit","Asset input exceeds 16 MiB");return blot_error::Error.none;}if input.len > max(maximum_total - candidate.stats.inputBytes,0) {candidate.fail(definition.path,"asset_limit","Asset inputs exceed 64 MiB");return blot_error::Error.none;}candidate.stats.inputBytes += input.len;loads.insert(input_path,input);
            }
            let hash = digest(input);var dependency_exists = false;for dependency in candidate.dependencies.items {if dependency.path == definition.path {dependency_exists = true;break;}}if !dependency_exists {let appended = candidate.dependencies.push(Dependency {path: definition.path,sha256: blot_support::some(hash)});if appended != blot_error::Error.none {return appended;}}
            var source: const u8[:] = default<const u8[:]>();
            if definition.kind == Kind.reference {
                var found = false;assert(definition.mediaType.present);for resource in candidate.resources.items {if resource.path == input_path && resource.mediaType == definition.mediaType.value && resource.sha256 == hash {found = true;break;}}
                if !found {let key,key_error = resourceKey(candidate,input_path,definition.mediaType.value,hash);if key_error != blot_error::Error.none {return key_error;}let appended = candidate.resources.push(Resource {id: 0,path: input_path,mediaType: definition.mediaType.value,sha256: hash,bytes: input,key: key});if appended != blot_error::Error.none {return appended;}}
                if self_.reusable_(module_path,input_path,Kind.reference,input).present {candidate.stats.reused++;}else {candidate.stats.parsed++;}
            }else {
                let old = self_.reusable_(module_path,input_path,definition.kind,input);
                if old.present {let copied,error = candidate.own(old.value.source);if error != blot_error::Error.none {return error;}source = copied;candidate.stats.reused++;}
                else {
                    if definition.kind == Kind.wgsl {
                        let produced,error = blot_backend_native_asset_wgsl::generate(input);if error != blot_error::Error.none {return error;}var generated = produced;var generated_error = blot_error::Error.none;
                        match generated {source value=>{let copied,error = candidate.own(value.bytes);source = copied;generated_error = error;},issue value=>{let issue = value.value;let message,error = candidate.own(issue.message);generated_error = error;if error == blot_error::Error.none {candidate.issue = blot_support::some(Issue {filename: definition.path,start: issue.start,end: issue.end,code: issue.code,message: message});}},}
                        generated.deinit();if generated_error != blot_error::Error.none {return generated_error;}if candidate.issue.present {return blot_error::Error.none;}
                    }else {
                        var kind = blot_backend_native_asset_readers::Kind.json;match definition.kind {json=>{kind = blot_backend_native_asset_readers::Kind.json;},catalog=>{kind = blot_backend_native_asset_readers::Kind.catalog;},text=>{kind = blot_backend_native_asset_readers::Kind.text;},tunables=>{kind = blot_backend_native_asset_readers::Kind.tunables;},_=>{abort("invalid native reader kind");},}
                        let produced,error = blot_backend_native_asset_readers::generate(kind,input);if error != blot_error::Error.none {return error;}var generated = produced;var generated_error = blot_error::Error.none;
                        match generated {source value=>{let copied,error = candidate.own(value.bytes);source = copied;generated_error = error;},issue value=>{let issue = value.value;let message,error = candidate.own(issue.message);generated_error = error;if error == blot_error::Error.none {candidate.issue = blot_support::some(Issue {filename: definition.path,start: issue.start,end: issue.end,code: issue.code,message: message});}},}
                        generated.deinit();if generated_error != blot_error::Error.none {return generated_error;}if candidate.issue.present {return blot_error::Error.none;}
                    }
                    candidate.stats.parsed++;
                }
            }
            let appended = candidate.modules.push(Module {module: module_path,definition: definition,canonical: input_path,bytes: input,source: source});if appended != blot_error::Error.none {return appended;}
        }
        for index in 1..candidate.resources.items.len {let item = candidate.resources.items[index];var at = index;while at > 0 && resourceLess(item,candidate.resources.items[at - 1]) {candidate.resources.items[at] = candidate.resources.items[at - 1];at--;}candidate.resources.items[at] = item;}for index in 0..candidate.resources.items.len {candidate.resources.items[index].id = (index + 1) as u32;}
        for index in 0..candidate.modules.items.len {
            let module = candidate.modules.items[index];
            if module.definition.kind == Kind.reference {assert(module.definition.ty.present && module.definition.export_name.present && module.definition.mediaType.present);for resource in candidate.resources.items {if resource.path != module.canonical || resource.mediaType != module.definition.mediaType.value {continue;}var text: u8[>..] = [];let ty = module.definition.ty.value;format(text,"type ",ty," is data = $",ty," U32\nconst ",module.definition.export_name.value,": ",ty," = ($",ty," ",resource.id,")\n");let source,error = candidate.own(text);if error != blot_error::Error.none {return error;}candidate.modules.items[index].source = source;break;}}
            let source = candidate.modules.items[index].source;if source.len > maximum_file || source.len > max(maximum_total - candidate.stats.generatedBytes,0) {return blot_error::Error.asset_limit;}candidate.stats.generatedBytes += source.len;let appended = candidate.sources.push(Source {path: module.module,contents: blot_support::some(source)});if appended != blot_error::Error.none {return appended;}
        }
        for index in 1..candidate.dependencies.items.len {let item = candidate.dependencies.items[index];var at = index;while at > 0 && dependencyLess(item,candidate.dependencies.items[at - 1]) {candidate.dependencies.items[at] = candidate.dependencies.items[at - 1];at--;}candidate.dependencies.items[at] = item;}return blot_error::Error.none;
    }
    let error = capture();discovered.deinit();definitions.deinit();overrides.deinit();if error != blot_error::Error.none {candidate.deinit();return null,error;}return candidate,blot_error::Error.none;
}
