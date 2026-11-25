// Source loading retains separate syntax owners and numeric import edges.
namespace blot_reuse_project;
import std;
import phase_profile;
import dictionary;
import parse.ast;
import parse.lexer;
import parse.parser;
import parse.token;
import parse.symbols;
import parse.syntax_diagnostics;
import reuse.frozen_dependency;
import reuse.dependency_relink;
import reuse.dependency_payload;
import support.error;
import support.bytes;
import support.option;
import support.native;
import support.io;
import support.path;
import support.pooled_buffer;
import support.pooled_map;
import reuse.project_check;
import reuse.parse_batch;
import reuse.parse_packet;
import reuse.persistent_names;
type Error = blot_error::Error;
type UnitId = u32;
type Symbol = blot_parse_symbols::Symbol;
type Span = blot_parse_ast::Span;
struct DeclarationId { unit: UnitId, node: blot_parse_ast::Id }
struct Range { start: u32=0, len: u32=0 }
struct Alias { prefix: const u8[:], root: const u8[:] }
enum InputMode { project, source }
struct Options {
    input_mode: InputMode=InputMode.project, prelude_path: blot_support::Option<const u8[:]>, std_root: blot_support::Option<const u8[:]>,
    aliases: const Alias[:]=default<const Alias[:]>(), max_source_bytes: i64=16777216, max_total_source_bytes: i64=67108864, max_files: i64=4096,
}
enum Code { import_path, missing_file, import_cycle, duplicate_alias, invalid_alias, source_limit, file_limit, io_error, lexical_error, syntax_error, invalid_prelude }
struct Diagnostic {
    unit: UnitId, span: Span, code: Code, target: Symbol=0, cause: blot_support::Option<const u8[:]>,
    lex_code: blot_support::Option<blot_parse_lexer::Code>, parse_code: blot_support::Option<blot_parse_ast::Code>,
    publication: blot_support::Option<blot_parse_syntax_diagnostics::Publication>, parse_detail: blot_support::Option<blot_parse_ast::Diagnostic>, lexical_details: const blot_parse_lexer::Diagnostic[:]=default<const blot_parse_lexer::Diagnostic[:]>(),
}
fn codeName(self_: Diagnostic) -> const u8[:] {
    if self_.lex_code.present { return blot_parse_lexer::code_name(self_.lex_code.value); }
    if self_.parse_code.present { return blot_parse_ast::code_name(self_.parse_code.value); }
    match self_.code {
        import_path => "import_path", missing_file => "missing_file", import_cycle => "import_cycle", duplicate_alias => "duplicate_alias",
        invalid_alias => "invalid_alias", source_limit => "source_limit", file_limit => "file_limit", io_error => "io_error",
        lexical_error => "lexical_error", syntax_error => "syntax_error", invalid_prelude => "invalid_prelude",
    }
}
fn message(self_: Diagnostic) -> const u8[:] {
    if self_.lex_code.present { return blot_parse_lexer::message(blot_parse_lexer::Diagnostic {self_.lex_code.value,self_.span.start,self_.span.end, ..}); }
    if self_.parse_code.present { return blot_parse_ast::message(blot_parse_ast::Diagnostic {code:self_.parse_code.value,start:self_.span.start,end:self_.span.end, ..}); }
    match self_.code {
        import_path => "Import requires a relative path or an explicitly configured directory alias", missing_file => "Imported source file does not exist",
        import_cycle => "Source import cycle", duplicate_alias => "Import aliases must have distinct names",
        invalid_alias => "Directory aliases need a nonempty prefix ending in '/' and a local root", source_limit => "Project source byte budget exceeded",
        file_limit => "Project source file budget exceeded", io_error => "Unable to read source file", lexical_error => "Invalid source token",
        syntax_error => "Invalid source syntax", invalid_prelude => "Prelude requires a nonempty local source path",
    }
}
struct Import { declaration: DeclarationId, target: UnitId=0, path: Symbol, namespace_: Symbol, bindings: blot_parse_ast::List, span: Span }
struct Unit { filename: Symbol, source: const u8[:], tree: blot_parse_ast::Tree, imports: Range=Range {..}, implicit_prelude: bool=false, is_std: bool=false, parse_start:i64=0, parse_end:i64=0, parse_names:const u32[:]=default<const u32[:]>(), parser_tree:blot_parse_ast::Tree=blot_parse_ast::Tree{..}, visible_names:i64=0 }
reusable[] var owned_source: u8[>..]=[];
reusable[] var owned_lexical: blot_parse_lexer::Diagnostic[>..]=[];
fn copySource(bytes: const u8[:]) -> const u8[:] { if bytes.len==0 {return default<const u8[:]>();} let result=owned_source.alloc_slice(bytes.len); result.move_from(bytes); return result; }
fn releaseSource(bytes: const u8[:]) { if bytes.len==0 {return;} owned_source.free_slice(bytes); }
fn copyLexical(values: const blot_parse_lexer::Diagnostic[:]) -> const blot_parse_lexer::Diagnostic[:] {if values.len==0 {return default<const blot_parse_lexer::Diagnostic[:]>();}let result=owned_lexical.alloc_slice(values.len);result.move_from(values);return result;}
fn releaseLexical(values: const blot_parse_lexer::Diagnostic[:]) {if values.len==0 {return;}owned_lexical.free_slice(values);}
fn ownCause(value:blot_support::Option<const u8[:]>)->blot_support::Option<const u8[:]> {if !value.present {return blot_support::none<const u8[:]>();}return blot_support::some<const u8[:]>(copySource(value.value));}
fn ownPublication(value:blot_support::Option<blot_parse_syntax_diagnostics::Publication>)->blot_support::Option<blot_parse_syntax_diagnostics::Publication> {
    if !value.present {return blot_support::none<blot_parse_syntax_diagnostics::Publication>();}
    let old=value.value;
    return blot_support::some(blot_parse_syntax_diagnostics::Publication{cause:old.cause,code:copySource(old.code),span:old.span,message:copySource(old.message),has_expected_token:old.has_expected_token,expected_token:old.expected_token,has_actual_token:old.has_actual_token,actual_token:old.actual_token});
}
fn ownDiagnostic(value:Diagnostic)->Diagnostic {return Diagnostic{unit:value.unit,span:value.span,code:value.code,target:value.target,cause:ownCause(value.cause),lex_code:value.lex_code,parse_code:value.parse_code,publication:ownPublication(value.publication),parse_detail:value.parse_detail,lexical_details:copyLexical(value.lexical_details)};}
// Only the Project-owned diagnostic contract admits these registered payload runs.
fn canonicalOwnedDiagnostic(value:Diagnostic)->Diagnostic {
 var cause=blot_support::none<const u8[:]>();if value.cause.present {let text=owned_source.realloc_slice(value.cause.value,value.cause.value.len);assert(blot_support::same_slice_identity(text,value.cause.value));cause=blot_support::some<const u8[:]>(text);}
 var publication=blot_support::none<blot_parse_syntax_diagnostics::Publication>();if value.publication.present {let old=value.publication.value;let code=owned_source.realloc_slice(old.code,old.code.len);let message=owned_source.realloc_slice(old.message,old.message.len);assert(blot_support::same_slice_identity(code,old.code) && blot_support::same_slice_identity(message,old.message));publication=blot_support::some(blot_parse_syntax_diagnostics::Publication{cause:old.cause,code:code,span:old.span,message:message,has_expected_token:old.has_expected_token,expected_token:old.expected_token,has_actual_token:old.has_actual_token,actual_token:old.actual_token});}
 let lexical=owned_lexical.realloc_slice(value.lexical_details,value.lexical_details.len);assert(blot_support::same_slice_identity(lexical,value.lexical_details));
 return Diagnostic{unit:value.unit,span:value.span,code:value.code,target:value.target,cause:cause,lex_code:value.lex_code,parse_code:value.parse_code,publication:publication,parse_detail:value.parse_detail,lexical_details:lexical};
}
fn deinit(self_:Diagnostic&) {if self_.cause.present {releaseSource(self_.cause.value);}if self_.publication.present {releaseSource(self_.publication.value.code);releaseSource(self_.publication.value.message);}releaseLexical(self_.lexical_details);self_=default<Diagnostic>();}
fn canonicalUnit(value:Unit)->Unit {return Unit{filename:value.filename,source:owned_source.realloc_slice(value.source,value.source.len),tree:blot_parse_ast::canonical(value.tree),imports:value.imports,implicit_prelude:value.implicit_prelude,is_std:value.is_std,parse_start:value.parse_start,parse_end:value.parse_end,parse_names:value.parse_names,parser_tree:blot_parse_ast::canonical(value.parser_tree),visible_names:value.visible_names};}
fn isStdPath(canonical:const u8[:],options:Options)->bool {
    if !options.std_root.present {return false;}
    let root=options.std_root.value;
    if root.len==0 || canonical.len<=root.len {return false;}
    if root[root.len-1]=='/' as u8 {return starts(canonical,root);}
    return starts(canonical,root) && canonical[root.len]=='/' as u8;
}
fn deinit(self_: Unit&) {self_.tree.deinit();self_.parser_tree.deinit();blot_reuse_project_check::releaseOwned(self_.parse_names);releaseSource(self_.source);self_.source=default<const u8[:]>();}
struct UnitBuffer {storage:Unit[:]=default<Unit[:]>(),items:Unit[:]=default<Unit[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var project_UnitBuffer_runs:Unit[>..]=[];
var inactive_UnitBuffer:UnitBuffer=UnitBuffer {..};
fn ensure(self_:UnitBuffer&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,project_UnitBuffer_runs);return self_.failure;}
fn push(self_:UnitBuffer&,value:Unit)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let length=self_.items.len;self_.failure=blot_support_pooled_buffer::ensure(self_,length+1,project_UnitBuffer_runs);if self_.failure!=blot_error::Error.none {return self_.failure;}let storage=project_UnitBuffer_runs.realloc_slice(self_.storage,self_.storage.len);assert(blot_support::same_slice_identity(storage,self_.storage));storage[length]=canonicalUnit(value);self_.items=storage[..length+1];self_.len=self_.items.len;return self_.failure;}
fn append(self_:UnitBuffer&,values:const Unit[:])->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let length=self_.items.len;if values.len>0x7fffffffffffffff-length {self_.failure=blot_error::Error.out_of_memory;return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,length+values.len,project_UnitBuffer_runs);if self_.failure!=blot_error::Error.none {return self_.failure;}let storage=project_UnitBuffer_runs.realloc_slice(self_.storage,self_.storage.len);assert(blot_support::same_slice_identity(storage,self_.storage));for value,index in values {storage[length+index]=canonicalUnit(value);}self_.items=storage[..length+values.len];self_.len=self_.items.len;return self_.failure;}
fn resize(self_:UnitBuffer&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn clear(self_:UnitBuffer&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:UnitBuffer&) {blot_support_pooled_buffer::deinit(self_,project_UnitBuffer_runs);self_.len=0;self_.failure=blot_error::Error.none;}
struct WordBuffer {storage:u32[:]=default<u32[:]>(),items:u32[:]=default<u32[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var project_WordBuffer_runs:u32[>..]=[];
var inactive_WordBuffer:WordBuffer=WordBuffer {..};
fn ensure(self_:WordBuffer&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,project_WordBuffer_runs);return self_.failure;}
fn push(self_:WordBuffer&,value:u32)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::push(self_,value,project_WordBuffer_runs);self_.len=self_.items.len;return self_.failure;}
fn append(self_:WordBuffer&,values:const u32[:])->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::append(self_,values,project_WordBuffer_runs);self_.len=self_.items.len;return self_.failure;}
fn resize(self_:WordBuffer&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn clear(self_:WordBuffer&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:WordBuffer&) {blot_support_pooled_buffer::deinit(self_,project_WordBuffer_runs);self_.len=0;self_.failure=blot_error::Error.none;}
struct ImportBuffer {storage:Import[:]=default<Import[:]>(),items:Import[:]=default<Import[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var project_ImportBuffer_runs:Import[>..]=[];
var inactive_ImportBuffer:ImportBuffer=ImportBuffer {..};
fn ensure(self_:ImportBuffer&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,project_ImportBuffer_runs);return self_.failure;}
fn push(self_:ImportBuffer&,value:Import)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::push(self_,value,project_ImportBuffer_runs);self_.len=self_.items.len;return self_.failure;}
fn append(self_:ImportBuffer&,values:const Import[:])->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::append(self_,values,project_ImportBuffer_runs);self_.len=self_.items.len;return self_.failure;}
fn resize(self_:ImportBuffer&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn clear(self_:ImportBuffer&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:ImportBuffer&) {blot_support_pooled_buffer::deinit(self_,project_ImportBuffer_runs);self_.len=0;self_.failure=blot_error::Error.none;}
struct DiagnosticBuffer {storage:Diagnostic[:]=default<Diagnostic[:]>(),items:Diagnostic[:]=default<Diagnostic[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var project_DiagnosticBuffer_runs:Diagnostic[>..]=[];
var inactive_DiagnosticBuffer:DiagnosticBuffer=DiagnosticBuffer {..};
fn ensure(self_:DiagnosticBuffer&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,project_DiagnosticBuffer_runs);return self_.failure;}
fn push(self_:DiagnosticBuffer&,value:Diagnostic)->Error {let length=self_.items.len;let error=self_.ensure(length+1);if error!=blot_error::Error.none {return error;}self_.storage[length]=ownDiagnostic(value);self_.items=self_.storage[..length+1];self_.len=self_.items.len;return blot_error::Error.none;}
// Admit storage before snapshotting a lexer scratch slice into an owned record.
fn pushLexical(self_:DiagnosticBuffer&,unit:UnitId,span:Span,lex_code:blot_parse_lexer::Code,publication:blot_parse_syntax_diagnostics::Publication,lexical:const blot_parse_lexer::Diagnostic[:])->Error {
 let length=self_.items.len;let error=self_.ensure(length+1);if error!=blot_error::Error.none {return error;}
 self_.storage[length]=Diagnostic{unit:unit,span:span,code:Code.lexical_error,lex_code:blot_support::some(lex_code),publication:ownPublication(blot_support::some(publication)),lexical_details:copyLexical(lexical),..};
 self_.items=self_.storage[..length+1];self_.len=self_.items.len;return blot_error::Error.none;
}
fn append(self_:DiagnosticBuffer&,values:const Diagnostic[:])->Error {let length=self_.items.len;if values.len>0x7fffffffffffffff-length {self_.failure=blot_error::Error.out_of_memory;return self_.failure;}let error=self_.ensure(length+values.len);if error!=blot_error::Error.none {return error;}for value,index in values {self_.storage[length+index]=ownDiagnostic(value);}self_.items=self_.storage[..length+values.len];self_.len=self_.items.len;return blot_error::Error.none;}
fn resize(self_:DiagnosticBuffer&,length:i64) {assert(length>=0 && length<=self_.items.len);for &item in self_.items[length..] {item.deinit();}blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn clear(self_:DiagnosticBuffer&) {for &item in self_.items {item.deinit();}blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:DiagnosticBuffer&) {self_.clear();blot_support_pooled_buffer::deinit(self_,project_DiagnosticBuffer_runs);}
struct ProjectState {checking_ids:const u32[:]=default<const u32[:]>(),parser_symbols:blot_parse_symbols::Pool=blot_parse_symbols::Pool{..},parser_seed:i64=0,entry_packet:const u8[:]=default<const u8[:]>(),owner:u64=0,origin_lease:u32=0,units:UnitBuffer=UnitBuffer {..},order:WordBuffer=WordBuffer {..},imports:ImportBuffer=ImportBuffer {..},diagnostics:DiagnosticBuffer=DiagnosticBuffer {..}}
reusable var projects:ProjectState[>..]=[];
struct Lowering { io: bool=false, workers:u8=1 }
struct Project {
    owner_id:u64=0,lease:u32=0,input_mode:InputMode=InputMode.project,compiled_modules:const blot_reuse_frozen_dependency::Module[:]=default<const blot_reuse_frozen_dependency::Module[:]>(),compiled_reuse:const bool[:]=default<const bool[:]>(),
    symbols:blot_parse_symbols::Pool=blot_parse_symbols::Pool {..},units:UnitBuffer& =inactive_UnitBuffer,order:WordBuffer& =inactive_WordBuffer,imports:ImportBuffer& =inactive_ImportBuffer,diagnostics:DiagnosticBuffer& =inactive_DiagnosticBuffer,
    entry:UnitId=0,prelude_unit:UnitId=0,source_bytes:i64=0,reused_syntax:i64=0,lowering:Lowering=Lowering {..},checking:Lowering=Lowering {..},
}
fn init()->Project,Error {
    if projects.len>=0xffffffff {return Project {..},blot_error::Error.out_of_memory;}
    let pool,error=blot_parse_symbols::initPooled();if error!=blot_error::Error.none {return Project {..},error;}
    let owner=blot_native::fresh_owner_id();let index=projects.alloc_index(ProjectState {owner:owner, ..});let state:ProjectState& =projects[index];
    return Project {owner_id:owner,lease:(index+1) as u32,symbols:pool,units:state.units,order:state.order,imports:state.imports,diagnostics:state.diagnostics, ..},blot_error::Error.none;
}
// The loader's scratch never owns a published header. Resolve the same pooled
// cells and take compiled catalogs directly from the caller's load context.
fn canonicalLoaded(self_:const Project&,modules:const blot_reuse_frozen_dependency::Module[:],reuse:const bool[:])->Project {
 assert(self_.lease!=0 && self_.lease-1<projects.len);let state:ProjectState& =projects[self_.lease-1];assert(state.owner==self_.owner_id);
 assert(self_.units .== state.units && self_.order .== state.order && self_.imports .== state.imports && self_.diagnostics .== state.diagnostics);
 assert(blot_support::same_slice_identity(self_.compiled_modules,modules) && blot_support::same_slice_identity(self_.compiled_reuse,reuse));
 return Project{owner_id:self_.owner_id,lease:self_.lease,input_mode:self_.input_mode,compiled_modules:modules,compiled_reuse:reuse,symbols:blot_parse_symbols::canonical(self_.symbols),units:state.units,order:state.order,imports:state.imports,diagnostics:state.diagnostics,entry:self_.entry,prelude_unit:self_.prelude_unit,source_bytes:self_.source_bytes,reused_syntax:self_.reused_syntax,lowering:self_.lowering,checking:self_.checking};
}
// These diagnostics own their payloads; recover the registered run behind the Project view.
fn diagnosticAt(self_:Project,index:i64)->Diagnostic {
 assert(self_.lease!=0 && self_.lease-1<projects.len);let state:ProjectState& =projects[self_.lease-1];assert(state.owner==self_.owner_id);
 assert(self_.units .== state.units && self_.order .== state.order && self_.imports .== state.imports && self_.diagnostics .== state.diagnostics);
 assert(index>=0 && index<state.diagnostics.items.len);
 let storage=project_DiagnosticBuffer_runs.realloc_slice(state.diagnostics.storage,state.diagnostics.storage.len);assert(blot_support::same_slice_identity(storage,state.diagnostics.storage));
 return canonicalOwnedDiagnostic(storage[index]);
}
fn deinit(self_:Project&) {
    if self_.lease==0 {return;}assert(projects[self_.lease-1].owner==self_.owner_id);
    for &unit in self_.units.items {unit.deinit();}self_.units.deinit();self_.order.deinit();self_.imports.deinit();
    self_.diagnostics.deinit();self_.symbols.deinit();
    let index=self_.lease-1;blot_reuse_project_check::releaseOwned(projects[index].checking_ids);projects[index].parser_symbols.deinit();releaseSource(projects[index].entry_packet);blot_reuse_project_check::releaseModuleOrigins(projects[index].origin_lease);projects[index].owner=0;projects.free(index);self_=Project {..};
}
fn compiledModule(self_:const Project&,id:i64)->const blot_reuse_frozen_dependency::Module? {if id==0||id>self_.compiled_modules.len {return null;}if self_.compiled_reuse.len!=0&&!self_.compiled_reuse[id-1] {return null;}return self_.compiled_modules[id-1];}
fn compiledCount(self_:const Project&)->i64 {if self_.compiled_reuse.len==0 {return self_.compiled_modules.len;}var count:i64=0;for reused in self_.compiled_reuse {if reused {count++;}}return count;}
fn unit(self_:const Project&,id:UnitId)->const Unit& {assert(id!=0);return self_.units.items[id-1];}
fn filename(self_:const Project&,id:UnitId)->const u8[:] {return self_.symbols.get(self_.unit(id).filename);}
fn unitImports(self_:const Project&,id:UnitId)->const Import[:] {let range=self_.unit(id).imports;return self_.imports.items[range.start..range.start+range.len];}
fn declaration(self_:const Project&,id:DeclarationId)->blot_parse_ast::Node {return self_.unit(id.unit).tree.node(id.node);}
fn declarationSpan(self_:const Project&,id:DeclarationId)->Span {return self_.unit(id.unit).tree.span(id.node);}
struct Origin {unit:UnitId=0,span:Span=Span {..}}
enum Visit {unloaded,pending,active,finished}
struct Frame {unit:UnitId,next:u32=0}
// Provider operations are compile-time methods on one caller-owned context;
// no untyped function address is retained in a loaded Project.
type LoaderFiles=blot_support_pooled_map::Map<Symbol,UnitId>;
type LoaderVisits=blot_support_pooled_buffer::Buffer<Visit>;
type LoaderStack=blot_support_pooled_buffer::Buffer<Frame>;
reusable[] var loader_file_slots:dictionary_slot<Symbol,UnitId>[>..]=[];
reusable[] var loader_visit_runs:Visit[>..]=[];
reusable[] var loader_frame_runs:Frame[>..]=[];
struct Loader<P> {
    previous:const Project?=null, verified_symbols:i64=0, stable_prefix:bool=true, parser_seed:i64=0, remap:WordBuffer=WordBuffer{}, reading_entry:bool=false,
    parse_batch:ParseBatch=ParseBatch{},options:Options,project:Project,inputs:P&,files:LoaderFiles,visits:LoaderVisits,stack:LoaderStack,prelude_ready:bool=false,
}
fn starts(text: const u8[:], prefix: const u8[:]) -> bool {return prefix.len<=text.len&&text[..prefix.len]==prefix;}
fn ends(text: const u8[:], suffix: const u8[:]) -> bool {return suffix.len<=text.len&&text[text.len-suffix.len..]==suffix;}
fn contains(text: const u8[:], byte: u8) -> bool {for item in text {if item==byte {return true;}}return false;}
fn hexDigit(byte:u8)->u8,bool {
    if byte>='0'&&byte<='9' {return byte-'0',true;}
    if byte>='a'&&byte<='f' {return byte-'a'+10,true;}
    if byte>='A'&&byte<='F' {return byte-'A'+10,true;}
    return 0,false;
}
fn decodePath(path:const u8[:],decoded:u8[>..<]&)->Error {
    let before=decoded.len;var at:i64=0;
    while at<path.len {
        var byte=path[at];
        if byte=='%' {
            if path.len-at<3 {decoded.resize(before);return blot_error::Error.invalid_path;}
            let high,valid_high=hexDigit(path[at+1]);let low,valid_low=hexDigit(path[at+2]);
            if !valid_high||!valid_low {decoded.resize(before);return blot_error::Error.invalid_path;}
            byte=high*16+low;if byte=='/' {decoded.resize(before);return blot_error::Error.invalid_path;}at+=3;
        } else {at++;}
        if byte==0 {decoded.resize(before);return blot_error::Error.invalid_path;}decoded.push(byte);
    }
    if !blot_support_path::validUtf8(decoded[before..]) {decoded.resize(before);return blot_error::Error.invalid_path;}
    return blot_error::Error.none;
}
fn resolveImportPath(source_filename:const u8[:],raw:const u8[:],options:Options,output:u8[>..<]&)->Error {
    if raw.len==0||contains(raw,'?')||contains(raw,'#') {return blot_error::Error.invalid_path;}
    let root,tail,selection_error=selectedImportParts(source_filename,raw,options);if selection_error!=blot_error::Error.none {return selection_error;}
    var decoded:u8[>..<]=[];let decoded_error=decodePath(tail,decoded);if decoded_error!=blot_error::Error.none {return decoded_error;}
    if decoded.len!=0&&decoded[0]=='/' {return blot_error::Error.invalid_path;}
    if !ends(decoded,".blot") {decoded.append(".blot");}
    var joined:u8[>..<]=[];joined.append(root);joined.push('/');joined.append(decoded);
    return blot_support_path::normalize(joined,output);
}
struct FileInputs {last_cause:const u8[:]=default<const u8[:]>()}
fn osCause(code:i64)->const u8[:] {
    match code {
        1=>"PermissionDenied",2=>"FileNotFound",5=>"InputOutput",6=>"NoDevice",11=>"WouldBlock",12=>"SystemResources",13=>"AccessDenied",16=>"DeviceBusy",17=>"PathAlreadyExists",19=>"NoDevice",20=>"NotDir",21=>"IsDir",23=>"SystemFdQuotaExceeded",24=>"ProcessFdQuotaExceeded",26=>"FileBusy",27=>"FileTooBig",28=>"NoSpaceLeft",30=>"ReadOnlyFileSystem",36=>"NameTooLong",40=>"SymLinkLoop",75=>"FileTooBig",122=>"DiskQuota",_=>"Unexpected",
    }
}
fn ioFailure(self_:FileInputs&,negative:i64)->Error {self_.last_cause=osCause(-negative);if negative == -2 {return blot_error::Error.file_not_found;}return blot_error::Error.io;}
fn cause(self_:const FileInputs&,error:Error)->const u8[:] {if self_.last_cause.len!=0 {return self_.last_cause;}return blot_error::error_name(error);}
fn canonical(self_:FileInputs&,path:const u8[:],output:u8[>..<]&)->Error {
    self_.last_cause=default<const u8[:]>();if contains(path,0) {self_.last_cause="BadPathName";return blot_error::Error.io;}
    var terminated:u8[>..<]=[];terminated.append(path);terminated.push(0);
    var buffer:u8[4096];let length=blot_native::real_path(terminated[0],buffer[0],4096);
    if length<0 {return self_.ioFailure(length);}if length>=4096 {self_.last_cause="NameTooLong";return blot_error::Error.io;}
    output.append(buffer[..length]);return blot_error::Error.none;
}
fn read(self_:FileInputs&,path:const u8[:],maximum:i64,output:u8[>..<]&)->Error {
    self_.last_cause=default<const u8[:]>();if contains(path,0) {self_.last_cause="BadPathName";return blot_error::Error.io;}
    var terminated:u8[>..<]=[];terminated.append(path);terminated.push(0);
    let fd=blot_native::open_read(terminated[0]);if fd<0 {return self_.ioFailure(fd);}
    return self_.readOpen(fd,maximum,output);
}
fn readView(self_:FileInputs&,path:const u8[:],maximum:i64,scratch:u8[>..<]&)->const u8[:],Error {
    let err=self_.read(path,maximum,scratch);
    if err!=blot_error::Error.none {return default<const u8[:]>(),err;}
    return scratch[..],blot_error::Error.none;
}
fn readOpen(self_:FileInputs&,fd:i32,maximum:i64,output:u8[>..<]&)->Error {
    let before=output.len;var chunk:u8[65536];var failure=blot_error::Error.none;
    loop {
        let count=blot_native::read(fd,chunk[0],65536);
        if count<0 {failure=self_.ioFailure(count);break;}
        if count==0 {break;}
        if output.len-before>maximum||count>maximum-(output.len-before) {self_.last_cause="StreamTooLong";failure=blot_error::Error.stream_too_long;break;}
        output.append(chunk[..count]);
    }
    let closed=blot_native::close(fd);
    if failure!=blot_error::Error.none {output.resize(before);}return failure;
}
fn probeSource(self_:FileInputs&,path:const u8[:],maximum:i64,name:u8[>..<]&,bytes:u8[>..<]&)->bool {
    if self_.canonical(path,name)!=blot_error::Error.none {return false;}
    var terminated:u8[>..<]=[];terminated.append(name[..]);terminated.push(0);
    let fd=blot_native::open_regular(terminated[0],maximum as u64);
    if fd<0 {return false;}
    return self_.readOpen(fd,maximum,bytes)==blot_error::Error.none;
}
fn recordProbedCanonical(self_:FileInputs&,path:const u8[:],canonical:const u8[:])->Error {self_.last_cause=default<const u8[:]>();return blot_error::Error.none;}
fn recordProbedRead(self_:FileInputs&,canonical:const u8[:],bytes:const u8[:],limit:i64)->Error {self_.last_cause=default<const u8[:]>();if bytes.len>limit {self_.last_cause="StreamTooLong";return blot_error::Error.stream_too_long;}return blot_error::Error.none;}
fn resolve(self_:FileInputs&,source_filename:const u8[:],raw:const u8[:],options:Options,output:u8[>..<]&)->Error {self_.last_cause=default<const u8[:]>();return resolveImportPath(source_filename,raw,options,output);}
fn deinitScratch<P>(self_:Loader<P>&) {self_.remap.deinit();self_.parse_batch.deinit();self_.files.deinit(loader_file_slots);blot_support_pooled_buffer::deinit(self_.visits,loader_visit_runs);blot_support_pooled_buffer::deinit(self_.stack,loader_frame_runs);}
fn report<P>(self_:Loader<P>&,origin:Origin,code:Code,target:const u8[:],cause:blot_support::Option<const u8[:]>)->Error {
    var name:Symbol=0;let interned,error=self_.project.symbols.intern(target);
    if error==blot_error::Error.out_of_memory {return error;}if error==blot_error::Error.none {name=interned;}
    else if error!=blot_error::Error.symbol_limit {return error;}
    return self_.project.diagnostics.push(Diagnostic {unit:origin.unit,span:origin.span,code:code,target:name,cause:cause, ..});
}
fn validateAliases<P>(self_:Loader<P>&)->bool,Error {
    if self_.options.prelude_path.present {let path=self_.options.prelude_path.value;if path.len==0||contains(path,0) {let error=self_.report(Origin {..},Code.invalid_prelude,path,blot_support::none<const u8[:]>());return false,error;}}
    for alias,index in self_.options.aliases {
        if alias.prefix.len==0||!ends(alias.prefix,"/")||alias.root.len==0||contains(alias.prefix,0)||contains(alias.root,0)||starts(alias.prefix,"./")||starts(alias.prefix,"../") {let error=self_.report(Origin {..},Code.invalid_alias,alias.prefix,blot_support::none<const u8[:]>());return false,error;}
        if self_.options.std_root.present&&alias.prefix=="std/" {let error=self_.report(Origin {..},Code.duplicate_alias,alias.prefix,blot_support::none<const u8[:]>());return false,error;}
        for prior in self_.options.aliases[..index] {if alias.prefix==prior.prefix {let error=self_.report(Origin {..},Code.duplicate_alias,alias.prefix,blot_support::none<const u8[:]>());return false,error;}}
    }
    if self_.options.std_root.present {let root=self_.options.std_root.value;if root.len==0||contains(root,0) {let error=self_.report(Origin {..},Code.invalid_alias,"std/",blot_support::none<const u8[:]>());return false,error;}}
    return true,blot_error::Error.none;
}
fn parserSymbols(project:const Project&)->const blot_parse_symbols::Pool& {
    let saved .= projects[project.lease-1].parser_symbols;
    if saved.lease!=0 {return saved;}
    return project.symbols;
}
fn parserTree(unit:const Unit&)->const blot_parse_ast::Tree& {
    if unit.visible_names!=0 {return unit.parser_tree;}
    return unit.tree;
}
fn sameParserPrefix<P>(loader:const Loader<P>&,previous:const Project&,end:i64)->bool {
    if end>parserSymbols(previous).entries.len {return false;}
    for i in loader.verified_symbols..end {
        let id=(i+1) as Symbol;
        if parserSymbols(previous).get(id)!=loader.project.symbols.get(id) {return false;}
    }
    return true;
}

// Parsed trees store project-wide symbol IDs. Verify any names produced by
// intervening fresh parses before adopting a tree, then replay its new IDs.
fn reuseSyntax<P>(loader:Loader<P>&,filename:Symbol,source:const u8[:],tree:blot_parse_ast::Tree&,recorded:blot_parse_parser::ScratchIdBuffer&)->bool,Error {
    let previous .= loader.previous;
    let index=loader.project.units.len;
    if !previous || index>=previous.units.len {return false,blot_error::Error.none;}
    if index+1==previous.entry && entryPacket(previous).len!=0 {return false,blot_error::Error.none;}
    let old=previous.units.items[index];
    let symbols .= loader.project.symbols;
    if old.implicit_prelude!=loader.prelude_ready || old.source!=source ||
       previous.filename((index+1) as u32)!=symbols.get(filename) {return false,blot_error::Error.none;}
    if !loader.stable_prefix || old.parse_start!=symbols.entries.len ||
       !sameParserPrefix(loader,previous,old.parse_start) {
        loader.stable_prefix=false;
        // The seed owns the inherited operators. Later spellings can move, even
        // when this file saw them only because another module used them first.
        let seed=loader.parser_seed;
        if loader.options.prelude_path.present && !loader.prelude_ready {return false,blot_error::Error.none;}
        let map .= loader.remap;
        if map.len==0 {
            let failure=map.ensure(parserSymbols(previous).entries.len);
            if failure!=blot_error::Error.none {return false,failure;}
            map.items=map.storage[..parserSymbols(previous).entries.len];
            map.len=map.items.len;
            for &word in map.items {word=0;}
        }
        for old_id in old.parse_names {
            let actual,error=symbols.intern_hashed(parserSymbols(previous).get(old_id),parserSymbols(previous).entries.items[old_id-1].hash);
            if error!=blot_error::Error.none {return false,error;}
            map.items[old_id-1]=actual;
            recorded.push(actual);
        }
        let copied=tree.copyParsed(parserTree(old));
        if copied!=blot_error::Error.none {return false,copied;}
        if !blot_reuse_parse_packet::relocate_tree(tree,seed as u32,map.items[seed..]) {return false,blot_error::Error.invalid_artifact;}
        loader.project.reused_syntax++;
        return true,recorded.failure;
    }
    let replay_err=symbols.appendUniqueSlice(parserSymbols(previous),old.parse_start,old.parse_end);
    if replay_err!=blot_error::Error.none {return false,replay_err;}
    recorded.append(old.parse_names);
    loader.verified_symbols=old.parse_end;
    if old.parser_tree.lease!=0 {
        let shared,error=old.parser_tree.retainParsed();
        if error!=blot_error::Error.none {return false,error;}
        tree.deinit();
        tree=blot_parse_ast::canonical(shared);
    } else {
        let error=tree.copyParsed(old.tree);
        if error!=blot_error::Error.none {return false,error;}
    }
    loader.project.reused_syntax++;
    return true,blot_error::Error.none;
}

fn entryPacket(project:const Project&)->const u8[:] {return projects[project.lease-1].entry_packet;}

// The entry packet names only its prelude prefix and its own spellings. Its
// imports can be read immediately and its body linked after the dependencies.
fn readEntryPacket<P>(loader:Loader<P>&,filename:Symbol,source:const u8[:],tree:blot_parse_ast::Tree&)->bool {
    let symbols .= loader.project.symbols;
    let previous .= loader.previous;
    if previous && previous.entry!=0 && previous.filename(previous.entry)==symbols.get(filename) &&
       previous.unit(previous.entry).source==source {
        let packet=entryPacket(previous);
        if packet.len>=9 && blot_bytes::get_u32(packet,0)==symbols.entries.len &&
           sameParserPrefix(loader,previous,symbols.entries.len) && blot_reuse_parse_packet::decode(packet,symbols,tree) {
            projects[loader.project.lease-1].entry_packet=copySource(packet);
            loader.project.reused_syntax++;
            return true;
        }
    }
    var packet:u8[>..<]=[];
    if !blot_reuse_parse_packet::encode(source,symbols,packet) ||
       !blot_reuse_parse_packet::decode(packet,symbols,tree) {return false;}
    projects[loader.project.lease-1].entry_packet=copySource(packet);
    return true;
}
fn read<P>(self_:Loader<P>&,path:const u8[:],origin:Origin)->blot_support::Option<UnitId>,Error {
    let no=blot_support::none<UnitId>();
    let probed=self_.parse_batch.probed(path);
    if probed.present {
        let canonical_error=self_.inputs.recordProbedCanonical(path,probed.value.path);
        if canonical_error!=blot_error::Error.none {return no,canonical_error;}
        return readCanonical(self_,probed.value.path,origin,true,probed.value.source);
    }
    var canonical_buf:u8[>..<]=[];
    let canonical_error=self_.inputs.canonical(path,canonical_buf);
    if canonical_error!=blot_error::Error.none {
        if canonical_error==blot_error::Error.out_of_memory {return no,canonical_error;}
        var code=Code.io_error;if canonical_error==blot_error::Error.file_not_found {code=Code.missing_file;}
        let reported=self_.report(origin,code,path,blot_support::some(self_.inputs.cause(canonical_error)));return no,reported;
    }
    return readCanonical(self_,canonical_buf[..],origin,false,default<const u8[:]>());
}
fn readCanonical<P>(self_:Loader<P>&,canonical:const u8[:],origin:Origin,has_probed_source:bool,probed_source:const u8[:])->blot_support::Option<UnitId>,Error {
    let no=blot_support::none<UnitId>();
    let filename,filename_error=self_.project.symbols.intern(canonical);
    if filename_error!=blot_error::Error.none {
        if filename_error==blot_error::Error.out_of_memory {return no,filename_error;}
        if filename_error!=blot_error::Error.symbol_limit {return no,filename_error;}
        let reported=self_.report(origin,Code.file_limit,canonical,blot_support::some(blot_error::error_name(filename_error)));return no,reported;
    }
    var reserved=blot_support::none<UnitId>();let existing=self_.files.get(filename);
    if existing {if self_.visits.items[existing-1]!=Visit.unloaded {return blot_support::some(existing as UnitId),blot_error::Error.none;}reserved=blot_support::some(existing as UnitId);}
    if !reserved.present&&(self_.project.units.len>=self_.options.max_files||self_.project.units.len>=0xffffffff) {let reported=self_.report(origin,Code.file_limit,canonical,blot_support::none<const u8[:]>());return no,reported;}
    let remaining=max(0,self_.options.max_total_source_bytes-self_.project.source_bytes);
    let allowed=min(min(self_.options.max_source_bytes,remaining),0xffffffff as i64);
    if has_probed_source {
        let source_error=self_.inputs.recordProbedRead(canonical,probed_source,allowed+1);
        if source_error!=blot_error::Error.none {
            if source_error==blot_error::Error.out_of_memory {return no,source_error;}
            var code=Code.io_error;if source_error==blot_error::Error.stream_too_long {code=Code.source_limit;}else if source_error==blot_error::Error.file_not_found {code=Code.missing_file;}
            let reported=self_.report(origin,code,canonical,blot_support::some(self_.inputs.cause(source_error)));return no,reported;
        }
        return readSource(self_,filename,reserved,canonical,probed_source,allowed,origin);
    }
    var source_buf:u8[>..<]=[];
    let source_view,source_error=self_.inputs.readView(canonical,allowed+1,source_buf);
    if source_error!=blot_error::Error.none {
        if source_error==blot_error::Error.out_of_memory {return no,source_error;}
        var code=Code.io_error;if source_error==blot_error::Error.stream_too_long {code=Code.source_limit;}else if source_error==blot_error::Error.file_not_found {code=Code.missing_file;}
        let reported=self_.report(origin,code,canonical,blot_support::some(self_.inputs.cause(source_error)));return no,reported;
    }
    return readSource(self_,filename,reserved,canonical,source_view,allowed,origin);
}
fn readSource<P>(self_:Loader<P>&,filename:Symbol,reserved:blot_support::Option<UnitId>,canonical:const u8[:],source:const u8[:],allowed:i64,origin:Origin)->blot_support::Option<UnitId>,Error {
    let no=blot_support::none<UnitId>();
    if source.len>allowed {let reported=self_.report(origin,Code.source_limit,canonical,blot_support::none<const u8[:]>());return no,reported;}
    let initialized,tree_error=blot_parse_ast::initPooled();if tree_error!=blot_error::Error.none {return no,tree_error;}var tree=initialized;
    var tokens:blot_parse_token::Token[>..<]=[];var comments:blot_parse_token::Token[>..<]=[];var diagnostics:blot_parse_lexer::Diagnostic[>..<]=[];
    let parse_start=self_.project.symbols.entries.len;
    var recorded=blot_parse_parser::ScratchIdBuffer{};
    var cached=false;var reuse_error=blot_error::Error.none;
    if self_.reading_entry {cached=readEntryPacket(self_,filename,source,tree);}
    else {cached,reuse_error=self_.reuseSyntax(filename,source,tree,recorded);}
    if reuse_error!=blot_error::Error.none {recorded.deinit();tree.deinit();return no,reuse_error;}
    if !cached && !self_.parse_batch.adopt(canonical,source,self_.project.symbols,tree,recorded) {
        var lexed=blot_parse_lexer::init(tokens,comments,diagnostics);
        let lex_scope=blot_phase_profile::enter(blot_phase_profile::Phase.lex);let lex_error=blot_parse_lexer::lex(source,lexed);lex_scope.exit();
        if lex_error!=blot_error::Error.none {
            if lex_error==blot_error::Error.out_of_memory {tree.deinit();return no,lex_error;}
            if lex_error!=blot_error::Error.source_limit {tree.deinit();return no,lex_error;}
            let reported=self_.report(origin,Code.source_limit,canonical,blot_support::some(blot_error::error_name(lex_error)));tree.deinit();return no,reported;
        }
        if diagnostics.len==0 {
            let parse_scope=blot_phase_profile::enter(blot_phase_profile::Phase.parse);
            let parse_error=blot_parse_parser::parse_with_recorded(source,tokens,self_.project.symbols,tree,recorded);
            parse_scope.exit();if parse_error!=blot_error::Error.none {recorded.deinit();tree.deinit();return no,parse_error;}
        }
    }
    var id=(self_.project.units.len+1) as UnitId;if reserved.present {id=reserved.value;}
    if recorded.failure!=blot_error::Error.none {let error=recorded.failure;recorded.deinit();tree.deinit();return no,error;}
    var loaded=Unit {filename:filename,source:copySource(source),tree:tree,implicit_prelude:self_.prelude_ready,is_std:(self_.options.prelude_path.present && !self_.prelude_ready) || isStdPath(canonical,self_.options),parse_start:parse_start,parse_end:self_.project.symbols.entries.len,parse_names:blot_reuse_project_check::copyOwned(recorded.items), ..};
    recorded.deinit();
    if reserved.present {self_.project.units.items[id-1]=canonicalUnit(loaded);}
    else {let appended=self_.project.units.push(loaded);if appended!=blot_error::Error.none {loaded.deinit();return no,appended;}}
    let finished,failure=self_.finishRead(id,diagnostics,tokens);
    if failure!=blot_error::Error.none {return no,failure;}return blot_support::some(finished),blot_error::Error.none;
}
fn finishRead<P>(self_:Loader<P>&,id:UnitId,lexical:const blot_parse_lexer::Diagnostic[:],tokens:const blot_parse_token::Token[:])->UnitId,Error {
    let source_length:i64=self_.project.units.items[id-1].source.len;let filename:Symbol=self_.project.units.items[id-1].filename;
    self_.project.source_bytes+=source_length;self_.files.insert(filename,id,loader_file_slots);
    if id<=self_.visits.items.len {self_.visits.items[id-1]=Visit.pending;}else {let error=blot_support_pooled_buffer::push(self_.visits,Visit.pending,loader_visit_runs);if error!=blot_error::Error.none {return 0,error;}}
    if lexical.len!=0 {
        let first=lexical[0];
        let appended=self_.project.diagnostics.pushLexical(id,Span{first.start,first.end,..},first.code,blot_parse_syntax_diagnostics::lexical(tokens,first),lexical);
        if appended!=blot_error::Error.none {return 0,appended;}
    }
    let tree=blot_parse_ast::canonical(self_.project.units.items[id-1].tree);
    if tree.diagnostics.len!=0 {
        let first=tree.diagnostics.items[0];let publication,error=blot_parse_syntax_diagnostics::parse(tokens,first);if error!=blot_error::Error.none {return 0,error;}
        let appended=self_.project.diagnostics.push(Diagnostic { unit:id, span:Span {first.start,first.end, ..}, code:Code.syntax_error, parse_code:blot_support::some(first.code), publication:blot_support::some(publication), parse_detail:blot_support::some(first), .. });
        if appended!=blot_error::Error.none {return 0,appended;}
    }
    let start=self_.project.imports.len as u32;
    if lexical.len==0&&tree.diagnostics.len==0 {
        let root_count=tree.roots.items.len;for root_index in 0..root_count {let root=tree.roots.items[root_index];
            let tag=tree.node(root).tag;if tag!=blot_parse_ast::tag_import_decl&&tag!=blot_parse_ast::tag_export_decl {continue;}
            let info=tree.import_decl(root);
            let appended=self_.project.imports.push(Import {declaration:DeclarationId {id,root, ..},path:info.path,namespace_:info.namespace_,bindings:info.bindings,span:info.path_span, ..});
            if appended!=blot_error::Error.none {return 0,appended;}
        }
    }
    self_.project.units.items[id-1].imports=Range {start,(self_.project.imports.len-start) as u32, ..};return id,blot_error::Error.none;
}
fn resolve<P>(self_:Loader<P>&,imported:Import,output:u8[>..<]&)->Error {return self_.inputs.resolve(self_.project.filename(imported.declaration.unit),self_.project.symbols.get(imported.path),self_.options,output);}
fn walk<P>(self_:Loader<P>&,root:UnitId)->Error {
    if self_.visits.items[root-1]==Visit.finished {return blot_error::Error.none;}
    self_.visits.items[root-1]=Visit.active;let error=blot_support_pooled_buffer::push(self_.stack,Frame {root, ..},loader_frame_runs);if error!=blot_error::Error.none {return error;}
    while self_.stack.items.len!=0 {
        let top=self_.stack.items.len-1;let frame=self_.stack.items[top];let imports:Range=self_.project.units.items[frame.unit-1].imports;
        if frame.next==imports.len {let appended=self_.project.order.push(frame.unit);if appended!=blot_error::Error.none {return appended;}self_.visits.items[frame.unit-1]=Visit.finished;blot_support_pooled_buffer::resize(self_.stack,top);continue;}
        let edge=imports.start+frame.next;self_.stack.items[top].next++;let imported=self_.project.imports.items[edge];let origin=Origin {frame.unit,imported.span, ..};
        var resolved:u8[>..<]=[];let resolution_error=self_.resolve(imported,resolved);
        if resolution_error!=blot_error::Error.none {
            if resolution_error==blot_error::Error.out_of_memory {return resolution_error;}
            if resolution_error!=blot_error::Error.invalid_path {return resolution_error;}
            let reported=self_.report(origin,Code.import_path,self_.project.symbols.get(imported.path),blot_support::some(blot_error::error_name(resolution_error)));if reported!=blot_error::Error.none {return reported;}continue;
        }
        let target,error=self_.read(resolved,origin);if error!=blot_error::Error.none {return error;}if !target.present {continue;}
        self_.project.imports.items[edge].target=target.value;
        if self_.visits.items[target.value-1]==Visit.pending {self_.visits.items[target.value-1]=Visit.active;let error=blot_support_pooled_buffer::push(self_.stack,Frame {target.value, ..},loader_frame_runs);if error!=blot_error::Error.none {return error;}}
        else if self_.visits.items[target.value-1]==Visit.active {let reported=self_.report(origin,Code.import_cycle,self_.project.filename(target.value),blot_support::none<const u8[:]>());if reported!=blot_error::Error.none {return reported;}}
    }
    return blot_error::Error.none;
}
struct LoadContext {
    previous:const Project?=null,parse_workers:u8=1,entrypath:const u8[:],result:blot_support::Option<Project>,dependency:const blot_reuse_frozen_dependency::FrozenDependency?=null,mutable:blot_reuse_frozen_dependency::FrozenDependency?=null,mutable_owner:blot_reuse_dependency_payload::Owner?=null,reuse:blot_support::Option<const bool[:]>,library:bool=false,provided:bool=false,
}
fn publishLoaded(context:LoadContext&,project:const Project&,modules:const blot_reuse_frozen_dependency::Module[:]) {
 if context.reuse.present {context.result=blot_support::some<Project>(canonicalLoaded(project,modules,context.reuse.value));}
 else {context.result=blot_support::some<Project>(canonicalLoaded(project,modules,default<const bool[:]>()));}
}
fn withLoader<P,F>(options:Options,inputs:P&,context:LoadContext&)->Error {
    let scope=blot_phase_profile::enter(blot_phase_profile::Phase.load);
    let initialized,error=init();if error!=blot_error::Error.none {scope.exit();return error;}
    var loader=Loader<P> {previous:context.previous,options:options,project:initialized,inputs:inputs,files:LoaderFiles{},visits:LoaderVisits{},stack:LoaderStack{}, ..};loader.project.input_mode=options.input_mode;
    let failure=F(context,loader);scope.exit();
    loader.deinitScratch();
    if failure!=blot_error::Error.none {loader.project.deinit();return failure;}
    let dependency .=context.dependency;
    if dependency {publishLoaded(context,loader.project,dependency.modules);}else {publishLoaded(context,loader.project,default<const blot_reuse_frozen_dependency::Module[:]>());}
    return blot_error::Error.none;
}
fn load(entrypath:const u8[:],options:Options)->Project,Error {
    var inputs=FileInputs {..};var context=LoadContext {entrypath:entrypath, ..};let error=withLoader(options,inputs,context,loadSource);
    if error!=blot_error::Error.none {return Project {..},error;}return canonicalLoaded(context.result.value,default<const blot_reuse_frozen_dependency::Module[:]>(),default<const bool[:]>()),blot_error::Error.none;
}
fn loadWithInputs<P>(entrypath:const u8[:],options:Options,inputs:P&)->Project,Error {
    var context=LoadContext {entrypath:entrypath,provided:true, ..};
    let error=withLoader(options,inputs,context,loadSource);
    if error!=blot_error::Error.none {return Project {..},error;}return canonicalLoaded(context.result.value,default<const blot_reuse_frozen_dependency::Module[:]>(),default<const bool[:]>()),blot_error::Error.none;
}
fn loadWithParseWorkers<P>(entrypath:const u8[:],options:Options,inputs:P&,workers:u8,previous:const Project?)->Project,Error {
    var context=LoadContext {previous:previous,parse_workers:workers,entrypath:entrypath,provided:true, ..};
    let error=withLoader(options,inputs,context,loadSourceParallel);
    if error!=blot_error::Error.none {return Project {..},error;}return canonicalLoaded(context.result.value,default<const blot_reuse_frozen_dependency::Module[:]>(),default<const bool[:]>()),blot_error::Error.none;
}
fn loadSource<P>(context:LoadContext&,loader:Loader<P>&)->Error {return loadSourceUsing(context,loader,serialParser);}
fn loadSourceParallel<P>(context:LoadContext&,loader:Loader<P>&)->Error {return loadSourceUsing(context,loader,prepareParseBatch);}
fn serialParser<P>(loader:Loader<P>&,entry:const u8[:],workers:u8) {}
fn loadSourceUsing<P,F>(context:LoadContext&,loader:Loader<P>&)->Error {
    let valid,error=loader.validateAliases();if error!=blot_error::Error.none {return error;}if !valid {return blot_error::Error.none;}
    if loader.options.prelude_path.present {
        let prelude,failure=loader.read(loader.options.prelude_path.value,Origin {..});if failure!=blot_error::Error.none {return failure;}if !prelude.present {return blot_error::Error.none;}
        loader.project.prelude_unit=prelude.value;let walked=loader.walk(prelude.value);if walked!=blot_error::Error.none {return walked;}
        if loader.options.input_mode==InputMode.source&&loader.project.diagnostics.len!=0 {return blot_error::Error.none;}
        let previous .= loader.previous;
        if previous && (!loader.stable_prefix || previous.prelude_unit!=prelude.value ||
            previous.unit(prelude.value).source!=loader.project.unit(prelude.value).source ||
            previous.filename(prelude.value)!=loader.project.filename(prelude.value)) {loader.previous .= null;}
        loader.prelude_ready=true;
    }
    loader.parser_seed=loader.project.symbols.entries.len;
    projects[loader.project.lease-1].parser_seed=loader.parser_seed;
    let seed_source .= loader.previous;
    if seed_source && (projects[seed_source.lease-1].parser_seed!=loader.parser_seed ||
       !sameParserPrefix(loader,seed_source,loader.parser_seed)) {loader.previous .= null;}
    let parallel=context.parse_workers!=1 && loader.options.input_mode==InputMode.project;
    let previous .= loader.previous;
    if parallel && !previous {F(loader,context.entrypath,context.parse_workers);}
    loader.reading_entry=loader.options.input_mode==InputMode.project;
    let entry,failure=loader.read(context.entrypath,Origin {..});loader.reading_entry=false;if failure!=blot_error::Error.none {return failure;}if !entry.present {return blot_error::Error.none;}
    loader.project.entry=entry.value;
    if entryPacket(loader.project).len!=0 {return loadEntryDependencies(loader,entry.value,parallel);}
    // A new symbol at the root invalidates the IDs of the remaining syntax.
    // Start the ordinary worker batch at its imports before walking them.
    if parallel && previous && loader.visits.items[entry.value-1]!=Visit.finished && loader.project.diagnostics.len==0 {
        let end=loader.project.unit(entry.value).parse_end;
        if !loader.previous || previous.entry!=entry.value || previous.unit(entry.value).parse_end!=end ||
           !sameParserPrefix(loader,previous,end) {
            loader.previous .= null;
            F(loader,context.entrypath,context.parse_workers);
        }
    }
    if loader.options.input_mode==InputMode.source {
        if loader.visits.items[entry.value-1]!=Visit.finished {let appended=loader.project.order.push(entry.value);if appended!=blot_error::Error.none {return appended;}loader.visits.items[entry.value-1]=Visit.finished;}
    } else {return loader.walk(entry.value);}
    return blot_error::Error.none;
}

fn linkSymbol(original:const blot_parse_symbols::Pool&,next:blot_parse_symbols::Pool&,map:u32[:],id:u32)->Error {
    if id==0 || map[id]!=0 {return blot_error::Error.none;}
    let assigned,error=next.intern_hashed(original.get(id),original.entries.items[id-1].hash);
    if error==blot_error::Error.none {map[id]=assigned;}
    return error;
}

// Bucket the existing topological order by maximum import depth. Ties keep
// their source order, and a long import chain takes one pass over its edges.
fn checkingOrder(project:const Project&,order:u32[>..]&) {
    var depth:u32[>..]=[];depth.resize(project.units.len,0);
    var maximum:u32=0;
    for id in project.order.items {
        var level:u32=0;
        for edge in project.unitImports(id) {level=max(level,depth[edge.target-1]+1);}
        if project.unit(id).implicit_prelude {level=max(level,depth[project.prelude_unit-1]+1);}
        depth[id-1]=level;maximum=max(maximum,level);
    }
    var next:u32[>..]=[];next.resize(maximum+1,0);
    for level in depth {next[level]++;}
    var offset:u32=0;
    for &at in next {let count=at;at=offset;offset+=count;}
    order.resize(project.units.len,0);
    for id in project.order.items {
        let level=depth[id-1];
        order[next[level]]=id;
        next[level]++;
    }
}

fn sameSymbolPool(a:const blot_parse_symbols::Pool&,b:const blot_parse_symbols::Pool&)->bool {
    if a.entries.len!=b.entries.len || a.bytes.len!=b.bytes.len {return false;}
    if a.bytes.items!=b.bytes.items {return false;}
    for i in 0..a.entries.len {
        let ea=a.entries.items[i];
        let eb=b.entries.items[i];
        if ea.offset!=eb.offset || ea.len!=eb.len || ea.hash!=eb.hash {return false;}
    }
    return true;
}

// A producer sees its entire dependency chain, including generated names.
// Keep parser coordinates separately so unchanged syntax can serve both views.
fn linkCheckingNames(project:Project&,entry:u32,seed:i64,previous:const Project?)->Error {
    let pool,error=blot_parse_symbols::initPooled();
    if error!=blot_error::Error.none {return error;}
    let original .= projects[project.lease-1].parser_symbols;
    original=blot_parse_symbols::canonical(project.symbols);
    project.symbols=blot_parse_symbols::canonical(pool);
    if previous && previous.units.len==project.units.len && previous.entry==entry &&
       previous.imports.len==project.imports.len && previous.order.items==project.order.items &&
       projects[previous.lease-1].parser_symbols.lease!=0 {
        let prev_ps .= parserSymbols(previous);
        let old_map=projects[previous.lease-1].checking_ids;
        let prev_end=previous.unit(entry).parse_start;
        if old_map.len==original.entries.len+1 && prev_end>0 && prev_end<=previous.symbols.entries.len &&
           sameSymbolPool(original,prev_ps) {
            var all_same=true;
            for id in 1..project.units.len+1 {
                if id as u32==entry {continue;}
                let u .= project.units.items[id-1];
                let pu .= previous.units.items[id-1];
                if pu.parser_tree.lease!=u.tree.lease || pu.parser_tree.lease==0 ||
                   u.imports.start!=pu.imports.start || u.imports.len!=pu.imports.len ||
                   old_map[u.filename]!=pu.filename {
                    all_same=false;break;
                }
            }
            if all_same {
                let cerr=project.symbols.appendUniqueSlice(previous.symbols,0,prev_end);
                if cerr!=blot_error::Error.none {return cerr;}
                for &unit in project.units.items {unit.filename=old_map[unit.filename];}
                for &edge in project.imports.items {edge.path=old_map[edge.path];}
                for id in 1..project.units.len+1 {
                    if id as u32==entry {continue;}
                    let unit .= project.units.items[id-1];
                    let prev_u .= previous.units.items[id-1];
                    let linked,rerr=prev_u.tree.retainParsed();
                    if rerr!=blot_error::Error.none {return rerr;}
                    unit.parser_tree=blot_parse_ast::canonical(unit.tree);
                    unit.tree=blot_parse_ast::canonical(linked);
                    let range=unit.imports;
                    for &edge in project.imports.items[range.start..range.start+range.len] {
                        edge.namespace_=unit.tree.import_decl(edge.declaration.node).namespace_;
                    }
                    unit.visible_names=prev_u.visible_names;
                }
                projects[project.lease-1].checking_ids=blot_reuse_project_check::copyOwned(old_map);
                return blot_error::Error.none;
            }
        }
    }
    // Preserve the entire previous checking symbol table when the project graph
    // is unchanged so adding new identifiers in one non-entry file appends at
    // the end without shifting symbol IDs or invalidating unrelated modules.
    if previous && previous.units.len==project.units.len && previous.entry==entry &&
       previous.imports.len==project.imports.len && previous.order.items==project.order.items &&
       projects[previous.lease-1].parser_symbols.lease!=0 && previous.symbols.entries.len>0 {
        let cerr=project.symbols.appendUniqueSlice(previous.symbols,0,previous.symbols.entries.len);
        if cerr!=blot_error::Error.none {return cerr;}
        var names:u32[>..]=[];names.resize(original.entries.len+1,0);
        for i in 1..original.entries.len+1 {
            let error=linkSymbol(original,project.symbols,names[..],i as u32);
            if error!=blot_error::Error.none {return error;}
        }
        for &unit in project.units.items {
            unit.filename=names[unit.filename];
        }
        for &edge in project.imports.items {
            edge.path=names[edge.path];
        }
        var ranges:Range[>..]=[];ranges.resize(project.units.len,Range{..});
        var contracts:blot_reuse_project_check::ContractName[>..]=[];
        var order:u32[>..]=[];checkingOrder(project,order);
        for id in order {
            if id==entry {continue;}
            let unit .= project.units.items[id-1];
            let prev_u .= previous.units.items[id-1];
            let unchanged_tree=prev_u.source==unit.source && prev_u.implicit_prelude==unit.implicit_prelude &&
                prev_u.filename==unit.filename && prev_u.visible_names!=0 && prev_u.tree.lease!=0;
            var linked=blot_parse_ast::Tree{..};
            var error=blot_error::Error.none;
            var max_vis:i64=prev_u.visible_names;
            if unchanged_tree {
                linked,error=prev_u.tree.retainParsed();
            } else {
                for old in unit.parse_names {
                    if (names[old] as i64)>max_vis {max_vis=names[old] as i64;}
                }
                linked,error=blot_parse_ast::initPooled();
                if error==blot_error::Error.none {error=linked.copyParsed(unit.tree);}
                if error==blot_error::Error.none && !blot_reuse_parse_packet::relocate_tree(linked,0,names[1..]) {error=blot_error::Error.invalid_artifact;}
            }
            if error!=blot_error::Error.none {linked.deinit();return error;}
            unit.parser_tree=blot_parse_ast::canonical(unit.tree);
            unit.tree=blot_parse_ast::canonical(linked);
            let range=unit.imports;
            for &edge in project.imports.items[range.start..range.start+range.len] {
                edge.namespace_=unit.tree.import_decl(edge.declaration.node).namespace_;
            }
            let before_prep=project.symbols.entries.len;
            let prepared=blot_reuse_project_check::prepareUnitNames(project,id,ranges[..],contracts);
            if prepared!=blot_error::Error.none {return prepared;}
            if !unchanged_tree && project.symbols.entries.len>before_prep {max_vis=project.symbols.entries.len;}
            if unchanged_tree {unit.visible_names=prev_u.visible_names;}
            else {unit.visible_names=max_vis;}
        }
        projects[project.lease-1].checking_ids=blot_reuse_project_check::copyOwned(names[..]);
        return blot_error::Error.none;
    }
    if previous {
        let rerr=project.symbols.reserve(previous.symbols.entries.len,previous.symbols.bytes.len);
        if rerr!=blot_error::Error.none {return rerr;}
    }
    var names:u32[>..]=[];names.resize(original.entries.len+1,0);
    for i in 1..seed+1 {
        let error=linkSymbol(original,project.symbols,names[..],i as u32);
        if error!=blot_error::Error.none {return error;}
    }
    for &unit in project.units.items {
        let error=linkSymbol(original,project.symbols,names[..],unit.filename);
        if error!=blot_error::Error.none {return error;}
        unit.filename=names[unit.filename];
    }
    for &edge in project.imports.items {
        let error=linkSymbol(original,project.symbols,names[..],edge.path);
        if error!=blot_error::Error.none {return error;}
        edge.path=names[edge.path];
    }
    var ranges:Range[>..]=[];ranges.resize(project.units.len,Range{..});
    var contracts:blot_reuse_project_check::ContractName[>..]=[];
    var order:u32[>..]=[];checkingOrder(project,order);
    for id in order {
        if id==entry {continue;}
        let unit .= project.units.items[id-1];
        var same_tree=false;
        var old_map=default<const u32[:]>();
        if previous && id<=previous.units.len && previous.unit(id).parser_tree.lease==unit.tree.lease {
            old_map=projects[previous.lease-1].checking_ids;
            same_tree=old_map.len!=0;
        }
        for old in unit.parse_names {
            let error=linkSymbol(original,project.symbols,names[..],old);
            if error!=blot_error::Error.none {return error;}
            if same_tree && names[old]!=old_map[old] {same_tree=false;}
        }
        var linked=blot_parse_ast::Tree{..};
        var error=blot_error::Error.none;
        if previous && same_tree {
            linked,error=previous.unit(id).tree.retainParsed();
        } else {
            linked,error=blot_parse_ast::initPooled();
            if error==blot_error::Error.none {error=linked.copyParsed(unit.tree);}
            if error==blot_error::Error.none && !blot_reuse_parse_packet::relocate_tree(linked,0,names[1..]) {error=blot_error::Error.invalid_artifact;}
        }
        if error!=blot_error::Error.none {linked.deinit();return error;}
        unit.parser_tree=blot_parse_ast::canonical(unit.tree);
        unit.tree=blot_parse_ast::canonical(linked);
        let range=unit.imports;
        for &edge in project.imports.items[range.start..range.start+range.len] {
            edge.namespace_=unit.tree.import_decl(edge.declaration.node).namespace_;
        }
        let prepared=blot_reuse_project_check::prepareUnitNames(project,id,ranges[..],contracts);
        if prepared!=blot_error::Error.none {return prepared;}
        unit.visible_names=project.symbols.entries.len;
    }
    projects[project.lease-1].checking_ids=blot_reuse_project_check::copyOwned(names[..]);
    return blot_error::Error.none;
}

fn loadEntryDependencies<P>(loader:Loader<P>&,entry:UnitId,parallel:bool)->Error {
    let project .= loader.project;
    // Keep only the prelude and entry filename. DFS needs the paths spelled
    // by the entry's edges, but never inspects its body.
    var dependencies,error=blot_parse_symbols::initPooled();
    if error!=blot_error::Error.none {return error;}
    let prefix=project.unit(entry).parse_start;
    let replay=blot_reuse_project_check::replaySymbols(dependencies,project.symbols,prefix);
    if replay!=blot_error::Error.none {dependencies.deinit();return replay;}
    let range=project.unit(entry).imports;
    for &edge in project.imports.items[range.start..range.start+range.len] {
        let path,failure=dependencies.intern(project.symbols.get(edge.path));
        if failure!=blot_error::Error.none {dependencies.deinit();return failure;}
        edge.path=path;
    }
    project.symbols.deinit();
    project.symbols=blot_parse_symbols::canonical(dependencies);
    let walked=loader.walk(entry);
    if walked!=blot_error::Error.none {return walked;}
    if project.diagnostics.len==0 {
        if parallel && project.units.len>=16 {
            let failure=linkCheckingNames(project,entry,prefix,loader.previous);
            if failure!=blot_error::Error.none {return failure;}
        } else {
            let prepared,failure=blot_reuse_project_check::preparePersistentNames(project,entry);
            if failure!=blot_error::Error.none {return failure;}
            assert(prepared);
        }
    }
    let root .= project.units.items[entry-1];
    root.parse_start=project.symbols.entries.len;
    if !blot_reuse_parse_packet::decode(entryPacket(project),project.symbols,root.tree) {return blot_error::Error.out_of_memory;}
    root.parse_end=project.symbols.entries.len;
    for &edge in project.imports.items[range.start..range.start+range.len] {
        let info=root.tree.import_decl(edge.declaration.node);
        assert(edge.path==info.path);
        edge.namespace_=info.namespace_;
    }
    return blot_error::Error.none;
}
fn validateReuseMask(dependency:const blot_reuse_frozen_dependency::FrozenDependency&,reuse:const bool[:])->Error {
    if reuse.len!=dependency.modules.len {return blot_error::Error.invalid_artifact;}
    var prelude=blot_support::none<i64>();
    for module,index in dependency.modules {if module.identity.prelude {if prelude.present {return blot_error::Error.invalid_artifact;}prelude=blot_support::some(index);}}
    for module,index in dependency.modules {
        if !reuse[index] {continue;}
        if module.implicit_prelude {if !prelude.present||!reuse[prelude.value] {return blot_error::Error.invalid_artifact;}}
        for target in module.imports {if target==0||target>reuse.len||!reuse[target-1] {return blot_error::Error.invalid_artifact;}}
        for request in module.source_imports {if request.target==0||request.target>reuse.len||!reuse[request.target-1] {return blot_error::Error.invalid_artifact;}}
    }
    return blot_error::Error.none;
}
reusable[] var owned_order:u32[>..]=[];
fn releaseOrder(order:const u32[:]) {if order.len==0 {return;}owned_order.free_slice(order);}
fn freshOrder(source:const Project&)->u32[:],Error {
    var seen:bool[>..<]=[];seen.resize(source.units.len,false);var order:u32[>..<]=[];var stack:Frame[>..<]=[];
    for root in [source.prelude_unit,source.entry] {
        if root==0 {continue;}if root>seen.len {return default<u32[:]>(),blot_error::Error.invalid_unit;}if seen[root-1] {continue;}
        seen[root-1]=true;if root!=source.entry {order.push(root);}stack.push(Frame {root, ..});
        while stack.len!=0 {
            let top=stack.len-1;let frame=stack[top];let edges=source.unitImports(frame.unit);
            if frame.next==edges.len {stack.resize(top);continue;}
            stack[top].next++;let target=edges[frame.next].target;
            if target==0||target>seen.len||target==source.entry {return default<u32[:]>(),blot_error::Error.invalid_unit;}if seen[target-1] {continue;}
            seen[target-1]=true;order.push(target);stack.push(Frame {target, ..});
        }
    }
    let result=owned_order.alloc_slice(order.len);for id,index in order {result[index]=id;}return result,blot_error::Error.none;
}
fn loadCompiled(entrypath:const u8[:],options:Options,dependency:blot_reuse_dependency_payload::Owned<blot_reuse_frozen_dependency::FrozenDependency>&)->Project,Error {
    var inputs=FileInputs {..};var context=LoadContext {entrypath:entrypath,dependency:dependency.value,mutable:dependency.value,mutable_owner:dependency.owner, ..};
    let error=withLoader(options,inputs,context,loadCompiledMode);if error!=blot_error::Error.none {return Project {..},error;}return canonicalLoaded(context.result.value,dependency.value.modules,default<const bool[:]>()),blot_error::Error.none;
}
fn loadCompiledReadOnly<P>(entrypath:const u8[:],options:Options,dependency:const blot_reuse_frozen_dependency::FrozenDependency&,inputs:P&)->Project,Error {
    var context=LoadContext {entrypath:entrypath,dependency:dependency,provided:true, ..};let error=withLoader(options,inputs,context,loadCompiledMode);
    if error!=blot_error::Error.none {return Project {..},error;}return canonicalLoaded(context.result.value,dependency.modules,default<const bool[:]>()),blot_error::Error.none;
}
fn loadCompiledReadOnly(entrypath:const u8[:],options:Options,dependency:const blot_reuse_frozen_dependency::FrozenDependency&)->Project,Error {
    var inputs=FileInputs {..};var context=LoadContext {entrypath:entrypath,dependency:dependency, ..};let error=withLoader(options,inputs,context,loadCompiledMode);
    if error!=blot_error::Error.none {return Project {..},error;}return canonicalLoaded(context.result.value,dependency.modules,default<const bool[:]>()),blot_error::Error.none;
}
fn loadCompiledMixedReadOnly<P>(entrypath:const u8[:],options:Options,dependency:const blot_reuse_frozen_dependency::FrozenDependency&,inputs:P&,reuse:const bool[:])->Project,Error {
    let valid=validateReuseMask(dependency,reuse);if valid!=blot_error::Error.none {return Project {..},valid;}
    var context=LoadContext {entrypath:entrypath,dependency:dependency,reuse:blot_support::some<const bool[:]>(reuse),provided:true, ..};let error=withLoader(options,inputs,context,loadCompiledMode);
    if error!=blot_error::Error.none {return Project {..},error;}return canonicalLoaded(context.result.value,dependency.modules,reuse),blot_error::Error.none;
}
fn loadLibraryReadOnly<P>(entrypath:const u8[:],options:Options,library:const blot_reuse_frozen_dependency::FrozenDependency&,inputs:P&,reuse:const bool[:])->Project,Error {
    let valid=validateReuseMask(library,reuse);if valid!=blot_error::Error.none {return Project {..},valid;}
    var context=LoadContext {entrypath:entrypath,dependency:library,reuse:blot_support::some<const bool[:]>(reuse),library:true,provided:true, ..};let error=withLoader(options,inputs,context,loadCompiledMode);
    if error!=blot_error::Error.none {return Project {..},error;}return canonicalLoaded(context.result.value,library.modules,reuse),blot_error::Error.none;
}

fn loadCompiledMode<P>(context:LoadContext&,loader:Loader<P>&)->Error {
    let dependency .= context.dependency;assert(dependency);let options=loader.options;
    if options.input_mode!=InputMode.project {return blot_error::Error.input_mode_unsupported;}
    if dependency.modules.len>=options.max_files||dependency.modules.len>=0xffffffff {return blot_error::Error.file_limit;}
    loader.project.compiled_modules=dependency.modules;
    if context.reuse.present {loader.project.compiled_reuse=context.reuse.value;}
    let valid,error=loader.validateAliases();if error!=blot_error::Error.none {return error;}if !valid {return blot_error::Error.none;}
    let mutable=context.mutable;
    if mutable {
        let owner=context.mutable_owner;assert(owner!=null);
        var units:u32[>..]=[];for index in 0..dependency.modules.len {units.push((index+1) as u32);}
        { let propagated_error = blot_reuse_dependency_relink::relink(owner,mutable,loader.project.symbols,units); if propagated_error != blot_error::Error.none { return propagated_error; } }
    } else {
        if dependency.symbols.len==0||dependency.symbols[0].text.len!=0 {return blot_error::Error.invalid_artifact;}
        for name,ordinal in dependency.symbols[1..] {
            let symbol,failure=loader.project.symbols.intern(name.text);if failure!=blot_error::Error.none {return failure;}
            if symbol!=ordinal+1 {return blot_error::Error.invalid_artifact;}
        }
        for module,ordinal in dependency.modules {if module.core.unit!=ordinal+1||module.interface.unit!=ordinal+1 {return blot_error::Error.invalid_artifact;}}
    }
    for module,index in dependency.modules {
        let id=(index+1) as u32;let cached=loader.project.compiledModule(id)!=null;
        if cached&&(module.identity.source_bytes>options.max_source_bytes||module.identity.source_bytes>max(0,options.max_total_source_bytes-loader.project.source_bytes)) {return blot_error::Error.source_limit;}
        let filename,failure=loader.project.symbols.intern(module.identity.normalized_path);if failure!=blot_error::Error.none {return failure;}
        { let propagated_error = loader.project.units.push(Unit {filename:filename,source:default<const u8[:]>(),tree:blot_parse_ast::Tree {..},implicit_prelude:module.implicit_prelude,is_std:module.identity.prelude || isStdPath(module.identity.normalized_path,options), ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }
        if cached {loader.project.source_bytes+=module.identity.source_bytes;}
        loader.files.insert(filename,id,loader_file_slots);var visit=Visit.unloaded;if cached {visit=Visit.finished;}let error=blot_support_pooled_buffer::push(loader.visits,visit,loader_visit_runs);if error!=blot_error::Error.none {return error;}
        let start=loader.project.imports.len as u32;
        for request in module.source_imports {
            let path,path_error=loader.project.symbols.intern(request.path);if path_error!=blot_error::Error.none {return path_error;}
            { let propagated_error = loader.project.imports.push(Import {declaration:DeclarationId {id,0, ..},target:request.target,path:path,namespace_:0,bindings:blot_parse_ast::List {..},span:Span {..}, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }
        }
        loader.project.units.items[id-1].imports=Range {start,(loader.project.imports.len-start) as u32, ..};
        if module.identity.prelude {
            if !cached {return blot_error::Error.dependency_set_changed;}if loader.project.prelude_unit!=0 {return blot_error::Error.invalid_artifact;}
            if !options.prelude_path.present {return blot_error::Error.stale_artifact;}let expected=options.prelude_path.value;
            if context.provided {
                var canonical:u8[>..<]=[];{ let propagated_error = loader.inputs.canonical(expected,canonical); if propagated_error != blot_error::Error.none { return propagated_error; } }
                if canonical!=module.identity.normalized_path {return blot_error::Error.stale_artifact;}
            } else if expected!=module.identity.normalized_path {return blot_error::Error.stale_artifact;}
            loader.project.prelude_unit=id;
        }
    }
    if (loader.project.prelude_unit!=0)!=options.prelude_path.present {return blot_error::Error.stale_artifact;}
    loader.prelude_ready=loader.project.prelude_unit!=0;
    let entry,failure=loader.read(context.entrypath,Origin {..});if failure!=blot_error::Error.none {return failure;}if !entry.present {return blot_error::Error.none;}
    if entry.value<=dependency.modules.len {return blot_error::Error.dependency_set_changed;}
    loader.project.entry=entry.value;{ let propagated_error = loader.walk(entry.value); if propagated_error != blot_error::Error.none { return propagated_error; } }
    if context.library {return blot_error::Error.none;}
    if context.reuse.present&&loader.project.units.len!=dependency.modules.len+1 {return blot_error::Error.dependency_set_changed;}
    if loader.project.diagnostics.len==0 {
        var seen:bool[>..<]=[];seen.resize(loader.project.units.len,false);var stack:UnitId[>..<]=[];stack.push(entry.value);
        while stack.len!=0 {
            let unit=stack[stack.len-1];stack.resize(stack.len-1);
            if unit==0||unit>seen.len {return blot_error::Error.invalid_artifact;}if seen[unit-1] {continue;}seen[unit-1]=true;
            if loader.project.unit(unit).implicit_prelude {stack.push(loader.project.prelude_unit);}
            for edge in loader.project.unitImports(unit) {stack.push(edge.target);}
        }
        for reached in seen {if !reached {return blot_error::Error.dependency_set_changed;}}
    }
    return blot_error::Error.none;
}

fn selectedImportParts(source_filename:const u8[:],raw:const u8[:],options:Options)->const u8[:],const u8[:],Error {
 if starts(raw,"./")||starts(raw,"../") {let directory=blot_support_path::dirnameEnd(source_filename);if !directory.present {return default<const u8[:]>(),default<const u8[:]>(),blot_error::Error.invalid_path;}return source_filename[..directory.value],raw,blot_error::Error.none;}
 var matched:i64=0;var selected:i64=-1;if options.std_root.present&&starts(raw,"std/") {matched=4;}
 for alias,index in options.aliases {if alias.prefix.len>matched&&starts(raw,alias.prefix) {matched=alias.prefix.len;selected=index;}}
 if matched==0 {return default<const u8[:]>(),default<const u8[:]>(),blot_error::Error.invalid_path;}
 if selected>=0 {return options.aliases[selected].root,raw[matched..],blot_error::Error.none;}return options.std_root.value,raw[matched..],blot_error::Error.none;
}
