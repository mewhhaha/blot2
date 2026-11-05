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
import support.option;
import support.native;
import support.io;
import support.path;
import support.pooled_buffer;
import backend.runtime_identity;
import reuse.project_check;
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
    aliases: const Alias[:]=[], max_source_bytes: i64=16777216, max_total_source_bytes: i64=67108864, max_files: i64=4096,
}
enum Code { import_path, missing_file, import_cycle, duplicate_alias, invalid_alias, source_limit, file_limit, io_error, lexical_error, syntax_error, invalid_prelude }
struct Diagnostic {
    unit: UnitId, span: Span, code: Code, target: Symbol=0, cause: blot_support::Option<const u8[:]>,
    lex_code: blot_support::Option<blot_parse_lexer::Code>, parse_code: blot_support::Option<blot_parse_ast::Code>,
    publication: blot_support::Option<blot_parse_syntax_diagnostics::Publication>, parse_detail: blot_support::Option<blot_parse_ast::Diagnostic>, lexical_details: const blot_parse_lexer::Diagnostic[:]=[],
}
fn codeName(self: Diagnostic) -> const u8[:] {
    if self.lex_code.present { return blot_parse_lexer::code_name(self.lex_code.value); }
    if self.parse_code.present { return blot_parse_ast::code_name(self.parse_code.value); }
    match self.code {
        Code.import_path => "import_path", Code.missing_file => "missing_file", Code.import_cycle => "import_cycle", Code.duplicate_alias => "duplicate_alias",
        Code.invalid_alias => "invalid_alias", Code.source_limit => "source_limit", Code.file_limit => "file_limit", Code.io_error => "io_error",
        Code.lexical_error => "lexical_error", Code.syntax_error => "syntax_error", Code.invalid_prelude => "invalid_prelude",
    }
}
fn message(self: Diagnostic) -> const u8[:] {
    if self.lex_code.present { return blot_parse_lexer::message(blot_parse_lexer::Diagnostic {self.lex_code.value,self.span.start,self.span.end}); }
    if self.parse_code.present { return blot_parse_ast::message(blot_parse_ast::Diagnostic {code:self.parse_code.value,start:self.span.start,end:self.span.end}); }
    match self.code {
        Code.import_path => "Import requires a relative path or an explicitly configured directory alias", Code.missing_file => "Imported source file does not exist",
        Code.import_cycle => "Source import cycle", Code.duplicate_alias => "Import aliases must have distinct names",
        Code.invalid_alias => "Directory aliases need a nonempty prefix ending in '/' and a local root", Code.source_limit => "Project source byte budget exceeded",
        Code.file_limit => "Project source file budget exceeded", Code.io_error => "Unable to read source file", Code.lexical_error => "Invalid source token",
        Code.syntax_error => "Invalid source syntax", Code.invalid_prelude => "Prelude requires a nonempty local source path",
    }
}
struct Import { declaration: DeclarationId, target: UnitId=0, path: Symbol, namespace: Symbol, bindings: blot_parse_ast::List, span: Span }
struct Unit { filename: Symbol, source: const u8[:], tree: blot_parse_ast::Tree, imports: Range=Range {}, implicit_prelude: bool=false }
reusable[] var owned_source: u8[>..]=[];
reusable[] var owned_lexical: blot_parse_lexer::Diagnostic[>..]=[];
fn copySource(bytes: const u8[:]) -> const u8[:] { let result=owned_source.alloc_slice(bytes.len); for byte,index in bytes {result[index]=byte;} return result; }
fn releaseSource(bytes: const u8[:]) { if bytes.len==0 {return;} let first:const u8&=bytes[0];let at=owned_source.index_of(first);assert(at>=0);owned_source.free_slice(owned_source[at..at+bytes.len]); }
fn copyLexical(values: const blot_parse_lexer::Diagnostic[:]) -> const blot_parse_lexer::Diagnostic[:] {let result=owned_lexical.alloc_slice(values.len);for value,index in values {result[index]=value;}return result;}
fn releaseLexical(values: const blot_parse_lexer::Diagnostic[:]) {if values.len==0 {return;}let first:const blot_parse_lexer::Diagnostic&=values[0];let at=owned_lexical.index_of(first);assert(at>=0);owned_lexical.free_slice(owned_lexical[at..at+values.len]);}
fn deinit(self: Unit&) {self.tree.deinit();releaseSource(self.source);self.source=[];}
struct UnitBuffer {storage:Unit[:]=[],items:Unit[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var project_UnitBuffer_runs:Unit[>..]=[];
var inactive_UnitBuffer:UnitBuffer=UnitBuffer {};
fn ensure(self:UnitBuffer&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::ensure(self,minimum,project_UnitBuffer_runs);return self.failure;}
fn push(self:UnitBuffer&,value:Unit)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::push(self,value,project_UnitBuffer_runs);self.len=self.items.len;return self.failure;}
fn append(self:UnitBuffer&,values:const Unit[:])->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::append(self,values,project_UnitBuffer_runs);self.len=self.items.len;return self.failure;}
fn resize(self:UnitBuffer&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn clear(self:UnitBuffer&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:UnitBuffer&) {blot_support_pooled_buffer::deinit(self,project_UnitBuffer_runs);self.len=0;self.failure=Error.none;}
struct WordBuffer {storage:u32[:]=[],items:u32[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var project_WordBuffer_runs:u32[>..]=[];
var inactive_WordBuffer:WordBuffer=WordBuffer {};
fn ensure(self:WordBuffer&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::ensure(self,minimum,project_WordBuffer_runs);return self.failure;}
fn push(self:WordBuffer&,value:u32)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::push(self,value,project_WordBuffer_runs);self.len=self.items.len;return self.failure;}
fn append(self:WordBuffer&,values:const u32[:])->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::append(self,values,project_WordBuffer_runs);self.len=self.items.len;return self.failure;}
fn resize(self:WordBuffer&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn clear(self:WordBuffer&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:WordBuffer&) {blot_support_pooled_buffer::deinit(self,project_WordBuffer_runs);self.len=0;self.failure=Error.none;}
struct ImportBuffer {storage:Import[:]=[],items:Import[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var project_ImportBuffer_runs:Import[>..]=[];
var inactive_ImportBuffer:ImportBuffer=ImportBuffer {};
fn ensure(self:ImportBuffer&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::ensure(self,minimum,project_ImportBuffer_runs);return self.failure;}
fn push(self:ImportBuffer&,value:Import)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::push(self,value,project_ImportBuffer_runs);self.len=self.items.len;return self.failure;}
fn append(self:ImportBuffer&,values:const Import[:])->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::append(self,values,project_ImportBuffer_runs);self.len=self.items.len;return self.failure;}
fn resize(self:ImportBuffer&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn clear(self:ImportBuffer&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:ImportBuffer&) {blot_support_pooled_buffer::deinit(self,project_ImportBuffer_runs);self.len=0;self.failure=Error.none;}
struct DiagnosticBuffer {storage:Diagnostic[:]=[],items:Diagnostic[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var project_DiagnosticBuffer_runs:Diagnostic[>..]=[];
var inactive_DiagnosticBuffer:DiagnosticBuffer=DiagnosticBuffer {};
fn ensure(self:DiagnosticBuffer&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::ensure(self,minimum,project_DiagnosticBuffer_runs);return self.failure;}
fn push(self:DiagnosticBuffer&,value:Diagnostic)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::push(self,value,project_DiagnosticBuffer_runs);self.len=self.items.len;return self.failure;}
fn append(self:DiagnosticBuffer&,values:const Diagnostic[:])->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::append(self,values,project_DiagnosticBuffer_runs);self.len=self.items.len;return self.failure;}
fn resize(self:DiagnosticBuffer&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn clear(self:DiagnosticBuffer&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:DiagnosticBuffer&) {blot_support_pooled_buffer::deinit(self,project_DiagnosticBuffer_runs);self.len=0;self.failure=Error.none;}
struct ProjectState {owner:u64=0,origin_lease:u32=0,units:UnitBuffer=UnitBuffer {},order:WordBuffer=WordBuffer {},imports:ImportBuffer=ImportBuffer {},diagnostics:DiagnosticBuffer=DiagnosticBuffer {}}
reusable var projects:ProjectState[>..]=[];
struct Lowering { io: bool=false, workers:u8=1 }
struct Project {
    owner_id:u64=0,lease:u32=0,input_mode:InputMode=InputMode.project,compiled_modules:const blot_reuse_frozen_dependency::Module[:]=[],compiled_reuse:const bool[:]=[],
    symbols:blot_parse_symbols::Pool=blot_parse_symbols::Pool {},units:UnitBuffer&=inactive_UnitBuffer,order:WordBuffer&=inactive_WordBuffer,imports:ImportBuffer&=inactive_ImportBuffer,diagnostics:DiagnosticBuffer&=inactive_DiagnosticBuffer,
    entry:UnitId=0,prelude_unit:UnitId=0,source_bytes:i64=0,lowering:Lowering=Lowering {},checking:Lowering=Lowering {},
}
fn init()->Project,Error {
    if projects.len>=0xffffffff {return Project {},Error.out_of_memory;}
    let pool,error=blot_parse_symbols::initPooled();if error!=Error.none {return Project {},error;}
    let owner=blot_native::fresh_owner_id();let index=projects.alloc_index(ProjectState {owner:owner});let state:ProjectState&=projects[index];
    return Project {owner_id:owner,lease:(index+1) as u32,symbols:pool,units:state.units,order:state.order,imports:state.imports,diagnostics:state.diagnostics},Error.none;
}
fn deinit(self:Project&) {
    if self.lease==0 {return;}assert(projects[self.lease-1].owner==self.owner_id);
    for &unit in self.units.items {unit.deinit();}self.units.deinit();self.order.deinit();self.imports.deinit();
    for item in self.diagnostics.items {releaseLexical(item.lexical_details);}self.diagnostics.deinit();self.symbols.deinit();
    let index=self.lease-1;blot_reuse_project_check::releaseModuleOrigins(projects[index].origin_lease);projects[index].owner=0;projects.free(index);self=Project {};
}
fn compiledModule(self:const Project&,id:i64)->const blot_reuse_frozen_dependency::Module? {if id==0||id>self.compiled_modules.len {return null;}if self.compiled_reuse.len!=0&&!self.compiled_reuse[id-1] {return null;}return self.compiled_modules[id-1];}
fn compiledCount(self:const Project&)->i64 {if self.compiled_reuse.len==0 {return self.compiled_modules.len;}var count:i64=0;for reused in self.compiled_reuse {if reused {count++;}}return count;}
fn unit(self:const Project&,id:UnitId)->const Unit& {assert(id!=0);return self.units.items[id-1];}
fn filename(self:const Project&,id:UnitId)->const u8[:] {return self.symbols.get(self.unit(id).filename);}
fn unitImports(self:const Project&,id:UnitId)->const Import[:] {let range=self.unit(id).imports;return self.imports.items[range.start..range.start+range.len];}
fn declaration(self:const Project&,id:DeclarationId)->blot_parse_ast::Node {return self.unit(id.unit).tree.node(id.node);}
fn declarationSpan(self:const Project&,id:DeclarationId)->Span {return self.unit(id.unit).tree.span(id.node);}
struct Origin {unit:UnitId=0,span:Span=Span {}}
enum Visit {unloaded,pending,active,finished}
struct Frame {unit:UnitId,next:u32=0}
// Provider operations are compile-time methods on one caller-owned context;
// no untyped function address is retained in a loaded Project.
struct Loader<P> {
    options:Options,project:Project,inputs:P&,files:dictionary<Symbol,UnitId>&,visits:Visit[>..<]&,stack:Frame[>..<]&,inherited_fixities:blot_parse_parser::InheritedFixity[>..<]&,prelude_ready:bool=false,
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
            if path.len-at<3 {decoded.resize(before);return Error.invalid_path;}
            let high,valid_high=hexDigit(path[at+1]);let low,valid_low=hexDigit(path[at+2]);
            if !valid_high||!valid_low {decoded.resize(before);return Error.invalid_path;}
            byte=high*16+low;if byte=='/' {decoded.resize(before);return Error.invalid_path;}at+=3;
        } else {at++;}
        if byte==0 {decoded.resize(before);return Error.invalid_path;}decoded.push(byte);
    }
    if !blot_backend_runtime_identity::validUtf8(decoded[before..]) {decoded.resize(before);return Error.invalid_path;}
    return Error.none;
}
fn resolveImportPath(source_filename:const u8[:],raw:const u8[:],options:Options,output:u8[>..<]&)->Error {
    if raw.len==0||contains(raw,'?')||contains(raw,'#') {return Error.invalid_path;}
    var root:const u8[:]=[];var tail:const u8[:]=[];
    if starts(raw,"./")||starts(raw,"../") {
        let directory=blot_support_path::dirname(source_filename);if !directory.present {return Error.invalid_path;}root=directory.value;tail=raw;
    } else {
        var matched:i64=0;
        if options.std_root.present&&starts(raw,"std/") {root=options.std_root.value;matched=4;}
        for alias in options.aliases {if alias.prefix.len>matched&&starts(raw,alias.prefix) {matched=alias.prefix.len;root=alias.root;}}
        if matched==0 {return Error.invalid_path;}tail=raw[matched..];
    }
    var decoded:u8[>..<]=[];let decoded_error=decodePath(tail,decoded);if decoded_error!=Error.none {return decoded_error;}
    if decoded.len!=0&&decoded[0]=='/' {return Error.invalid_path;}
    if !ends(decoded,".blot") {decoded.append(".blot");}
    var joined:u8[>..<]=[];joined.append(root);joined.push('/');joined.append(decoded);
    return blot_support_path::normalize(joined,output);
}
struct FileInputs {last_cause:const u8[:]=[]}
fn osCause(code:i64)->const u8[:] {
    match code {
        1=>"PermissionDenied",2=>"FileNotFound",5=>"InputOutput",6=>"NoDevice",11=>"WouldBlock",12=>"SystemResources",13=>"AccessDenied",16=>"DeviceBusy",17=>"PathAlreadyExists",19=>"NoDevice",20=>"NotDir",21=>"IsDir",23=>"SystemFdQuotaExceeded",24=>"ProcessFdQuotaExceeded",26=>"FileBusy",27=>"FileTooBig",28=>"NoSpaceLeft",30=>"ReadOnlyFileSystem",36=>"NameTooLong",40=>"SymLinkLoop",75=>"FileTooBig",122=>"DiskQuota",_=>"Unexpected",
    }
}
fn ioFailure(self:FileInputs&,negative:i64)->Error {self.last_cause=osCause(-negative);if negative == -2 {return Error.file_not_found;}return Error.io;}
fn cause(self:const FileInputs&,error:Error)->const u8[:] {if self.last_cause.len!=0 {return self.last_cause;}return blot_error::error_name(error);}
fn canonical(self:FileInputs&,path:const u8[:],output:u8[>..<]&)->Error {
    self.last_cause=[];if contains(path,0) {self.last_cause="BadPathName";return Error.io;}
    var terminated:u8[>..<]=[];terminated.append(path);terminated.push(0);
    var buffer:u8[4096];let length=blot_native::real_path(terminated[0],buffer[0],4096);
    if length<0 {return self.ioFailure(length);}if length>=4096 {self.last_cause="NameTooLong";return Error.io;}
    output.append(buffer[..length]);return Error.none;
}
fn read(self:FileInputs&,path:const u8[:],maximum:i64,output:u8[>..<]&)->Error {
    self.last_cause=[];if contains(path,0) {self.last_cause="BadPathName";return Error.io;}
    var terminated:u8[>..<]=[];terminated.append(path);terminated.push(0);
    let fd=blot_native::open_read(terminated[0]);if fd<0 {return self.ioFailure(fd);}
    let before=output.len;var chunk:u8[65536];var failure=Error.none;
    loop {
        let count=blot_native::read(fd,chunk[0],65536);
        if count<0 {failure=self.ioFailure(count);break;}
        if count==0 {break;}
        if output.len-before>maximum||count>maximum-(output.len-before) {self.last_cause="StreamTooLong";failure=Error.stream_too_long;break;}
        output.append(chunk[..count]);
    }
    let closed=blot_native::close(fd);
    if failure!=Error.none {output.resize(before);}return failure;
}
fn resolve(self:FileInputs&,source_filename:const u8[:],raw:const u8[:],options:Options,output:u8[>..<]&)->Error {self.last_cause=[];return resolveImportPath(source_filename,raw,options,output);}
fn deinitScratch<P>(self:Loader<P>&) {self.files.clear();self.visits.clear();self.stack.clear();self.inherited_fixities.clear();}
fn report<P>(self:Loader<P>&,origin:Origin,code:Code,target:const u8[:],cause:blot_support::Option<const u8[:]>)->Error {
    var name:Symbol=0;let interned,error=self.project.symbols.intern(target);
    if error==Error.out_of_memory {return error;}if error==Error.none {name=interned;}
    else if error!=Error.symbol_limit {return error;}
    return self.project.diagnostics.push(Diagnostic {unit:origin.unit,span:origin.span,code:code,target:name,cause:cause});
}
fn validateAliases<P>(self:Loader<P>&)->bool,Error {
    if self.options.prelude_path.present {let path=self.options.prelude_path.value;if path.len==0||contains(path,0) {let error=self.report(Origin {},Code.invalid_prelude,path,blot_support::none<const u8[:]>());return false,error;}}
    for alias,index in self.options.aliases {
        if alias.prefix.len==0||!ends(alias.prefix,"/")||alias.root.len==0||contains(alias.prefix,0)||contains(alias.root,0)||starts(alias.prefix,"./")||starts(alias.prefix,"../") {let error=self.report(Origin {},Code.invalid_alias,alias.prefix,blot_support::none<const u8[:]>());return false,error;}
        if self.options.std_root.present&&alias.prefix=="std/" {let error=self.report(Origin {},Code.duplicate_alias,alias.prefix,blot_support::none<const u8[:]>());return false,error;}
        for prior in self.options.aliases[..index] {if alias.prefix==prior.prefix {let error=self.report(Origin {},Code.duplicate_alias,alias.prefix,blot_support::none<const u8[:]>());return false,error;}}
    }
    if self.options.std_root.present {let root=self.options.std_root.value;if root.len==0||contains(root,0) {let error=self.report(Origin {},Code.invalid_alias,"std/",blot_support::none<const u8[:]>());return false,error;}}
    return true,Error.none;
}
fn read<P>(self:Loader<P>&,path:const u8[:],origin:Origin)->blot_support::Option<UnitId>,Error {
    let no=blot_support::none<UnitId>();var canonical:u8[>..<]=[];
    let canonical_error=self.inputs.canonical(path,canonical);
    if canonical_error!=Error.none {
        if canonical_error==Error.out_of_memory {return no,canonical_error;}
        var code=Code.io_error;if canonical_error==Error.file_not_found {code=Code.missing_file;}
        let reported=self.report(origin,code,path,blot_support::some(self.inputs.cause(canonical_error)));return no,reported;
    }
    let filename,filename_error=self.project.symbols.intern(canonical);
    if filename_error!=Error.none {
        if filename_error==Error.out_of_memory {return no,filename_error;}
        if filename_error!=Error.symbol_limit {return no,filename_error;}
        let reported=self.report(origin,Code.file_limit,canonical,blot_support::some(blot_error::error_name(filename_error)));return no,reported;
    }
    var reserved=blot_support::none<UnitId>();let existing=self.files.get(filename);
    if existing {if self.visits[existing-1]!=Visit.unloaded {return blot_support::some(existing as UnitId),Error.none;}reserved=blot_support::some(existing as UnitId);}
    if !reserved.present&&(self.project.units.len>=self.options.max_files||self.project.units.len>=0xffffffff) {let reported=self.report(origin,Code.file_limit,canonical,blot_support::none<const u8[:]>());return no,reported;}
    let remaining=max(0,self.options.max_total_source_bytes-self.project.source_bytes);
    let allowed=min(min(self.options.max_source_bytes,remaining),0xffffffff as i64);
    var source:u8[>..<]=[];let source_error=self.inputs.read(canonical,allowed+1,source);
    if source_error!=Error.none {
        if source_error==Error.out_of_memory {return no,source_error;}
        var code=Code.io_error;if source_error==Error.stream_too_long {code=Code.source_limit;}else if source_error==Error.file_not_found {code=Code.missing_file;}
        let reported=self.report(origin,code,canonical,blot_support::some(self.inputs.cause(source_error)));return no,reported;
    }
    if source.len>allowed {let reported=self.report(origin,Code.source_limit,canonical,blot_support::none<const u8[:]>());return no,reported;}
    var tokens:blot_parse_token::Token[>..<]=[];var comments:blot_parse_token::Token[>..<]=[];var diagnostics:blot_parse_lexer::Diagnostic[>..<]=[];
    var lexed=blot_parse_lexer::init(tokens,comments,diagnostics);
    let lex_scope=blot_phase_profile::enter(blot_phase_profile::Phase.lex);let lex_error=blot_parse_lexer::lex(source,lexed);lex_scope.exit();
    if lex_error!=Error.none {
        if lex_error==Error.out_of_memory {return no,lex_error;}
        if lex_error!=Error.source_limit {return no,lex_error;}
        let reported=self.report(origin,Code.source_limit,canonical,blot_support::some(blot_error::error_name(lex_error)));return no,reported;
    }
    let initialized,tree_error=blot_parse_ast::initPooled();if tree_error!=Error.none {return no,tree_error;}var tree=initialized;
    if diagnostics.len==0 {
        let parse_scope=blot_phase_profile::enter(blot_phase_profile::Phase.parse);
        let parse_error=blot_parse_parser::parse_with_fixities(source,tokens,self.project.symbols,tree,self.inherited_fixities);
        parse_scope.exit();if parse_error!=Error.none {tree.deinit();return no,parse_error;}
    }
    var id=(self.project.units.len+1) as UnitId;if reserved.present {id=reserved.value;}
    var loaded=Unit {filename:filename,source:copySource(source),tree:tree,implicit_prelude:self.prelude_ready};
    if reserved.present {self.project.units.items[id-1]=loaded;}
    else {let appended=self.project.units.push(loaded);if appended!=Error.none {loaded.deinit();return no,appended;}}
    let finished,failure=self.finishRead(id,diagnostics,tokens);
    if failure!=Error.none {return no,failure;}return blot_support::some(finished),Error.none;
}
fn finishRead<P>(self:Loader<P>&,id:UnitId,lexical:const blot_parse_lexer::Diagnostic[:],tokens:const blot_parse_token::Token[:])->UnitId,Error {
    self.project.source_bytes+=self.project.unit(id).source.len;self.files.insert(self.project.unit(id).filename,id);
    if id<=self.visits.len {self.visits[id-1]=Visit.pending;}else {self.visits.push(Visit.pending);}
    if lexical.len!=0 {
        let first=lexical[0];let details=copyLexical(lexical);
        let appended=self.project.diagnostics.push(Diagnostic {unit:id,span:Span {first.start,first.end},code:Code.lexical_error,lex_code:blot_support::some(first.code),publication:blot_support::some(blot_parse_syntax_diagnostics::lexical(tokens,first)),lexical_details:details});
        if appended!=Error.none {releaseLexical(details);return 0,appended;}
    }
    let tree .= self.project.units.items[id-1].tree;
    if tree.diagnostics.len!=0 {
        let first=tree.diagnostics.items[0];let publication,error=blot_parse_syntax_diagnostics::parse(tokens,first);if error!=Error.none {return 0,error;}
        let appended=self.project.diagnostics.push(Diagnostic {unit:id,span:Span {first.start,first.end},code:Code.syntax_error,parse_code:blot_support::some(first.code),parse_detail:blot_support::some(first),publication:blot_support::some(publication)});
        if appended!=Error.none {return 0,appended;}
    }
    let start=self.project.imports.len as u32;
    if lexical.len==0&&tree.diagnostics.len==0 {
        for root in tree.roots.items {
            let tag=tree.node(root).tag;if tag!=blot_parse_ast::tag_import_decl&&tag!=blot_parse_ast::tag_export_decl {continue;}
            let info=tree.import_decl(root);
            let appended=self.project.imports.push(Import {declaration:DeclarationId {id,root},path:info.path,namespace:info.namespace,bindings:info.bindings,span:info.path_span});
            if appended!=Error.none {return 0,appended;}
        }
    }
    self.project.units.items[id-1].imports=Range {start,(self.project.imports.len-start) as u32};return id,Error.none;
}
fn resolve<P>(self:Loader<P>&,imported:Import,output:u8[>..<]&)->Error {return self.inputs.resolve(self.project.filename(imported.declaration.unit),self.project.symbols.get(imported.path),self.options,output);}
fn walk<P>(self:Loader<P>&,root:UnitId)->Error {
    if self.visits[root-1]==Visit.finished {return Error.none;}
    self.visits[root-1]=Visit.active;self.stack.push(Frame {root});
    while self.stack.len!=0 {
        let top=self.stack.len-1;let frame=self.stack[top];let unit=self.project.unit(frame.unit);
        if frame.next==unit.imports.len {let appended=self.project.order.push(frame.unit);if appended!=Error.none {return appended;}self.visits[frame.unit-1]=Visit.finished;self.stack.resize(top);continue;}
        let edge=unit.imports.start+frame.next;self.stack[top].next++;let imported=self.project.imports.items[edge];let origin=Origin {frame.unit,imported.span};
        var resolved:u8[>..<]=[];let resolution_error=self.resolve(imported,resolved);
        if resolution_error!=Error.none {
            if resolution_error==Error.out_of_memory {return resolution_error;}
            if resolution_error!=Error.invalid_path {return resolution_error;}
            let reported=self.report(origin,Code.import_path,self.project.symbols.get(imported.path),blot_support::some(blot_error::error_name(resolution_error)));if reported!=Error.none {return reported;}continue;
        }
        let target,error=self.read(resolved,origin);if error!=Error.none {return error;}if !target.present {continue;}
        self.project.imports.items[edge].target=target.value;
        if self.visits[target.value-1]==Visit.pending {self.visits[target.value-1]=Visit.active;self.stack.push(Frame {target.value});}
        else if self.visits[target.value-1]==Visit.active {let reported=self.report(origin,Code.import_cycle,self.project.filename(target.value),blot_support::none<const u8[:]>());if reported!=Error.none {return reported;}}
    }
    return Error.none;
}
struct LoadContext {
    entrypath:const u8[:],result:blot_support::Option<Project>,dependency:const blot_reuse_frozen_dependency::FrozenDependency?=null,mutable:blot_reuse_frozen_dependency::FrozenDependency?=null,mutable_owner:blot_reuse_dependency_payload::Owner?=null,reuse:blot_support::Option<const bool[:]>,library:bool=false,provided:bool=false,
}
fn withLoader<P,F>(options:Options,inputs:P&,context:LoadContext&)->Error {
    let scope=blot_phase_profile::enter(blot_phase_profile::Phase.load);
    let initialized,error=init();if error!=Error.none {scope.exit();return error;}
    var files:dictionary<Symbol,UnitId>;var visits:Visit[>..<]=[];var stack:Frame[>..<]=[];var fixities:blot_parse_parser::InheritedFixity[>..<]=[];
    var loader=Loader<P> {options:options,project:initialized,inputs:inputs,files:files,visits:visits,stack:stack,inherited_fixities:fixities};loader.project.input_mode=options.input_mode;
    let failure=F(context,loader);scope.exit();
    loader.deinitScratch();
    if failure!=Error.none {loader.project.deinit();return failure;}
    context.result=blot_support::some(loader.project);return Error.none;
}
fn load(entrypath:const u8[:],options:Options)->Project,Error {
    var inputs=FileInputs {};var context=LoadContext {entrypath:entrypath};let error=withLoader(options,inputs,context,loadSource);
    if error!=Error.none {return Project {},error;}return context.result.value,Error.none;
}
fn loadWithInputs<P>(entrypath:const u8[:],options:Options,inputs:P&)->Project,Error {
    var context=LoadContext {entrypath:entrypath,provided:true};let error=withLoader(options,inputs,context,loadSource);
    if error!=Error.none {return Project {},error;}return context.result.value,Error.none;
}
fn loadSource<P>(context:LoadContext&,loader:Loader<P>&)->Error {
    let valid,error=loader.validateAliases();if error!=Error.none {return error;}if !valid {return Error.none;}
    if loader.options.prelude_path.present {
        let prelude,failure=loader.read(loader.options.prelude_path.value,Origin {});if failure!=Error.none {return failure;}if !prelude.present {return Error.none;}
        loader.project.prelude_unit=prelude.value;let walked=loader.walk(prelude.value);if walked!=Error.none {return walked;}
        if loader.options.input_mode==InputMode.source&&loader.project.diagnostics.len!=0 {return Error.none;}
        let tree .= loader.project.unit(prelude.value).tree;
        for root in tree.roots.items {
            if tree.node(root).tag!=blot_parse_ast::tag_fixity_decl {continue;}let fixity=tree.fixity(root);
            loader.inherited_fixities.push(blot_parse_parser::InheritedFixity {fixity.operator,fixity.precedence,fixity.association,fixity.named});
        }
        loader.prelude_ready=true;
    }
    let entry,failure=loader.read(context.entrypath,Origin {});if failure!=Error.none {return failure;}if !entry.present {return Error.none;}
    loader.project.entry=entry.value;
    if loader.options.input_mode==InputMode.source {
        if loader.visits[entry.value-1]!=Visit.finished {let appended=loader.project.order.push(entry.value);if appended!=Error.none {return appended;}loader.visits[entry.value-1]=Visit.finished;}
    } else {return loader.walk(entry.value);}
    return Error.none;
}
fn validateReuseMask(dependency:const blot_reuse_frozen_dependency::FrozenDependency&,reuse:const bool[:])->Error {
    if reuse.len!=dependency.modules.len {return Error.invalid_artifact;}
    var prelude=blot_support::none<i64>();
    for module,index in dependency.modules {if module.identity.prelude {if prelude.present {return Error.invalid_artifact;}prelude=blot_support::some(index);}}
    for module,index in dependency.modules {
        if !reuse[index] {continue;}
        if module.implicit_prelude {if !prelude.present||!reuse[prelude.value] {return Error.invalid_artifact;}}
        for target in module.imports {if target==0||target>reuse.len||!reuse[target-1] {return Error.invalid_artifact;}}
        for request in module.source_imports {if request.target==0||request.target>reuse.len||!reuse[request.target-1] {return Error.invalid_artifact;}}
    }
    return Error.none;
}
reusable[] var owned_order:u32[>..]=[];
fn releaseOrder(order:const u32[:]) {if order.len==0 {return;}let first:const u32&=order[0];let at=owned_order.index_of(first);assert(at>=0);owned_order.free_slice(owned_order[at..at+order.len]);}
fn freshOrder(source:const Project&)->u32[:],Error {
    var seen:bool[>..<]=[];seen.resize(source.units.len,false);var order:u32[>..<]=[];var stack:Frame[>..<]=[];
    for root in [source.prelude_unit,source.entry] {
        if root==0 {continue;}if root>seen.len {return [],Error.invalid_unit;}if seen[root-1] {continue;}
        seen[root-1]=true;if root!=source.entry {order.push(root);}stack.push(Frame {root});
        while stack.len!=0 {
            let top=stack.len-1;let frame=stack[top];let edges=source.unitImports(frame.unit);
            if frame.next==edges.len {stack.resize(top);continue;}
            stack[top].next++;let target=edges[frame.next].target;
            if target==0||target>seen.len||target==source.entry {return [],Error.invalid_unit;}if seen[target-1] {continue;}
            seen[target-1]=true;order.push(target);stack.push(Frame {target});
        }
    }
    let result=owned_order.alloc_slice(order.len);for id,index in order {result[index]=id;}return result,Error.none;
}
fn loadCompiled(entrypath:const u8[:],options:Options,dependency:blot_reuse_dependency_payload::Owned<blot_reuse_frozen_dependency::FrozenDependency>&)->Project,Error {
    var inputs=FileInputs {};var context=LoadContext {entrypath:entrypath,dependency:dependency.value,mutable:dependency.value,mutable_owner:dependency.owner};
    let error=withLoader(options,inputs,context,loadCompiledMode);if error!=Error.none {return Project {},error;}return context.result.value,Error.none;
}
fn loadCompiledReadOnly<P>(entrypath:const u8[:],options:Options,dependency:const blot_reuse_frozen_dependency::FrozenDependency&,inputs:P&)->Project,Error {
    var context=LoadContext {entrypath:entrypath,dependency:dependency,provided:true};let error=withLoader(options,inputs,context,loadCompiledMode);
    if error!=Error.none {return Project {},error;}return context.result.value,Error.none;
}
fn loadCompiledReadOnly(entrypath:const u8[:],options:Options,dependency:const blot_reuse_frozen_dependency::FrozenDependency&)->Project,Error {
    var inputs=FileInputs {};var context=LoadContext {entrypath:entrypath,dependency:dependency};let error=withLoader(options,inputs,context,loadCompiledMode);
    if error!=Error.none {return Project {},error;}return context.result.value,Error.none;
}
fn loadCompiledMixedReadOnly<P>(entrypath:const u8[:],options:Options,dependency:const blot_reuse_frozen_dependency::FrozenDependency&,inputs:P&,reuse:const bool[:])->Project,Error {
    let valid=validateReuseMask(dependency,reuse);if valid!=Error.none {return Project {},valid;}
    var context=LoadContext {entrypath:entrypath,dependency:dependency,reuse:blot_support::some(reuse),provided:true};let error=withLoader(options,inputs,context,loadCompiledMode);
    if error!=Error.none {return Project {},error;}return context.result.value,Error.none;
}
fn loadLibraryReadOnly<P>(entrypath:const u8[:],options:Options,library:const blot_reuse_frozen_dependency::FrozenDependency&,inputs:P&,reuse:const bool[:])->Project,Error {
    let valid=validateReuseMask(library,reuse);if valid!=Error.none {return Project {},valid;}
    var context=LoadContext {entrypath:entrypath,dependency:library,reuse:blot_support::some(reuse),library:true,provided:true};let error=withLoader(options,inputs,context,loadCompiledMode);
    if error!=Error.none {return Project {},error;}return context.result.value,Error.none;
}

fn loadCompiledMode<P>(context:LoadContext&,loader:Loader<P>&)->Error {
    assert(context.dependency);let dependency .= context.dependency;let options=loader.options;
    if options.input_mode!=InputMode.project {return Error.input_mode_unsupported;}
    if dependency.modules.len>=options.max_files||dependency.modules.len>=0xffffffff {return Error.file_limit;}
    loader.project.compiled_modules=dependency.modules;
    if context.reuse.present {loader.project.compiled_reuse=context.reuse.value;}
    let valid,error=loader.validateAliases();if error!=Error.none {return error;}if !valid {return Error.none;}
    let mutable=context.mutable;
    if mutable {
        let owner=context.mutable_owner;assert(owner!=null);
        var units:u32[>..<]=[];for index in 0..dependency.modules.len {units.push((index+1) as u32);}
        { let propagated_error = blot_reuse_dependency_relink::relink(owner,mutable,loader.project.symbols,units); if propagated_error != Error.none { return propagated_error; } }
    } else {
        if dependency.symbols.len==0||dependency.symbols[0].text.len!=0 {return Error.invalid_artifact;}
        for name,ordinal in dependency.symbols[1..] {
            let symbol,failure=loader.project.symbols.intern(name.text);if failure!=Error.none {return failure;}
            if symbol!=ordinal+1 {return Error.invalid_artifact;}
        }
        for module,ordinal in dependency.modules {if module.core.unit!=ordinal+1||module.interface.unit!=ordinal+1 {return Error.invalid_artifact;}}
    }
    for module,index in dependency.modules {
        let id=(index+1) as u32;let cached=loader.project.compiledModule(id)!=null;
        if cached&&(module.identity.source_bytes>options.max_source_bytes||module.identity.source_bytes>max(0,options.max_total_source_bytes-loader.project.source_bytes)) {return Error.source_limit;}
        let filename,failure=loader.project.symbols.intern(module.identity.normalized_path);if failure!=Error.none {return failure;}
        { let propagated_error = loader.project.units.push(Unit {filename:filename,source:[],tree:blot_parse_ast::Tree {},implicit_prelude:module.implicit_prelude}); if propagated_error != Error.none { return propagated_error; } }
        if cached {loader.project.source_bytes+=module.identity.source_bytes;}
        loader.files.insert(filename,id);var visit=Visit.unloaded;if cached {visit=Visit.finished;}loader.visits.push(visit);
        let start=loader.project.imports.len as u32;
        for request in module.source_imports {
            let path,path_error=loader.project.symbols.intern(request.path);if path_error!=Error.none {return path_error;}
            { let propagated_error = loader.project.imports.push(Import {declaration:DeclarationId {id,0},target:request.target,path:path,namespace:0,bindings:blot_parse_ast::List {},span:Span {}}); if propagated_error != Error.none { return propagated_error; } }
        }
        loader.project.units.items[id-1].imports=Range {start,(loader.project.imports.len-start) as u32};
        if module.identity.prelude {
            if !cached {return Error.dependency_set_changed;}if loader.project.prelude_unit!=0 {return Error.invalid_artifact;}
            if !options.prelude_path.present {return Error.stale_artifact;}let expected=options.prelude_path.value;
            if context.provided {
                var canonical:u8[>..<]=[];{ let propagated_error = loader.inputs.canonical(expected,canonical); if propagated_error != Error.none { return propagated_error; } }
                if canonical!=module.identity.normalized_path {return Error.stale_artifact;}
            } else if expected!=module.identity.normalized_path {return Error.stale_artifact;}
            loader.project.prelude_unit=id;
            for fixity in module.fixities {loader.inherited_fixities.push(blot_parse_parser::InheritedFixity {fixity.operator,fixity.precedence,fixity.association,fixity.named});}
        }
    }
    if (loader.project.prelude_unit!=0)!=options.prelude_path.present {return Error.stale_artifact;}
    loader.prelude_ready=loader.project.prelude_unit!=0;
    let entry,failure=loader.read(context.entrypath,Origin {});if failure!=Error.none {return failure;}if !entry.present {return Error.none;}
    if entry.value<=dependency.modules.len {return Error.dependency_set_changed;}
    loader.project.entry=entry.value;{ let propagated_error = loader.walk(entry.value); if propagated_error != Error.none { return propagated_error; } }
    if context.library {return Error.none;}
    if context.reuse.present&&loader.project.units.len!=dependency.modules.len+1 {return Error.dependency_set_changed;}
    if loader.project.diagnostics.len==0 {
        var seen:bool[>..<]=[];seen.resize(loader.project.units.len,false);var stack:UnitId[>..<]=[];stack.push(entry.value);
        while stack.len!=0 {
            let unit=stack[stack.len-1];stack.resize(stack.len-1);
            if unit==0||unit>seen.len {return Error.invalid_artifact;}if seen[unit-1] {continue;}seen[unit-1]=true;
            if loader.project.unit(unit).implicit_prelude {stack.push(loader.project.prelude_unit);}
            for edge in loader.project.unitImports(unit) {stack.push(edge.target);}
        }
        for reached in seen {if !reached {return Error.dependency_set_changed;}}
    }
    return Error.none;
}
