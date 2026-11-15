// A source-only editor query. Its answer owns all text and semantic snapshots.
namespace blot_reuse_editor_completion;
import reuse.project;
import reuse.project_check;
import reuse.revision_inputs;
import reuse.completion_probe;
import reuse.completion_fit;
import reuse.completion_names;
import reuse.hole_diagnostics;
import reuse.dispatch_explanation;
import reuse.type_display;
import check.check;
import check.types;
import parse.ast;
import parse.symbols;
import support.option;
import support.error;
import support.pooled_buffer;
import support.json;
type Error=blot_error::Error;
type Span=blot_parse_ast::Span;
type Project=blot_reuse_project::Project;
type CheckedProject=blot_reuse_project_check::CheckedProject;
type Checked=blot_check_check::Checked;
type Probe=blot_reuse_completion_probe::Probe;
type ProbeKind=blot_reuse_completion_probe::Kind;
type Match=blot_reuse_completion_fit::Match;
type Budget=blot_reuse_completion_fit::Budget;
type Name=blot_check_check::EditorName;
type Text=blot_support::Option<const u8[:]>;
type Hole=blot_reuse_hole_diagnostics::Snapshot;
enum ItemKind {value,function,type_,constructor,field,member,module}
struct Item {label:const u8[:]=default<const u8[:]>(),insertText:const u8[:]=default<const u8[:]>(),kind:ItemKind=ItemKind.value,detail:Text=blot_support::none<const u8[:]>(),match_:Match=blot_reuse_completion_fit::Match.unknown,distance:u32=0,filename:const u8[:]=default<const u8[:]>(),start:u32=0}
struct DiagnosticDetails {hole:blot_support::Option<Hole> =blot_support::none<Hole>(),explanation:blot_support::Option<blot_reuse_dispatch_explanation::Explanation> =blot_support::none<blot_reuse_dispatch_explanation::Explanation>()}
struct Diagnostic {filename:const u8[:]=default<const u8[:]>(),stage:const u8[:]="check",code:const u8[:]=default<const u8[:]>(),start:u32=0,end:u32=0,message:const u8[:]=default<const u8[:]>(),offset_encoding:const u8[:]="utf8_bytes",utf16:blot_support::Option<Span> =blot_support::none<Span>(),details:blot_support::Option<DiagnosticDetails> =blot_support::none<DiagnosticDetails>()}
struct Result {replace:Span=Span{},context:blot_support::Option<Hole> =blot_support::none<Hole>(),items:Item[:]=default<Item[:]>(),diagnostics:Diagnostic[:]=default<Diagnostic[:]>(),truncated:bool=false}
reusable[] var text_pool:u8[>..]=[];
reusable[] var item_pool:Item[>..]=[];
reusable[] var diagnostic_pool:Diagnostic[>..]=[];
reusable var budgets:Budget[>..]=[];
fn own(text:const u8[:])->const u8[:] {let result=text_pool.alloc_slice(text.len);for byte,index in text {result[index]=byte;}return result;}
fn free(text:const u8[:]) {if text.len!=0 {text_pool.free_slice(text);}}
fn deinit(self_:Item&) {free(self_.label);free(self_.insertText);if self_.detail.present {free(self_.detail.value);}free(self_.filename);self_=Item{};}
fn deinit(self_:Diagnostic&) {free(self_.filename);free(self_.code);free(self_.message);if self_.details.present {if self_.details.value.hole.present {self_.details.value.hole.value.deinit();}if self_.details.value.explanation.present {self_.details.value.explanation.value.deinit();}}self_=Diagnostic{};}
fn deinit(self_:Result&) {if self_.context.present {self_.context.value.deinit();}for &item in self_.items {item.deinit();}if self_.items.len!=0 {item_pool.free_slice(self_.items);}for &issue in self_.diagnostics {issue.deinit();}if self_.diagnostics.len!=0 {diagnostic_pool.free_slice(self_.diagnostics);}self_=Result{};}
fn itemKindName(kind:ItemKind)->const u8[:] {match kind {value=>"value",function=>"function",type_=>"type",constructor=>"constructor",field=>"field",member=>"member",module=>"module"}}
fn matchCode(kind:Match)->u32 {match kind {exact=>0,compatible=>1,unknown=>2,incompatible=>3}}
fn itemKindCode(kind:ItemKind)->u32 {match kind {value=>0,function=>1,type_=>2,constructor=>3,field=>4,member=>5,module=>6}}
fn jsonStringify(self_:Item,writer:blot_json::Writer&)->Error {writer.beginObject();writer.field("label",self_.label);writer.field("insertText",self_.insertText);writer.field("kind",itemKindName(self_.kind));writer.field("detail",self_.detail);writer.key("match");writer.enumValue(self_.match_);writer.endObject();return writer.failure;}
fn jsonStringify(self_:DiagnosticDetails,writer:blot_json::Writer&)->Error {return blot_json::jsonStringify(self_,writer);}
fn jsonStringify(self_:Diagnostic,writer:blot_json::Writer&)->Error {writer.beginObject();writer.field("filename",self_.filename);writer.field("stage",self_.stage);writer.field("code",self_.code);writer.field("start",self_.start);writer.field("end",self_.end);writer.field("message",self_.message);writer.field("offset_encoding",self_.offset_encoding);writer.key("utf16");if self_.utf16.present {writer.beginObject();writer.field("start",self_.utf16.value.start);writer.field("end",self_.utf16.value.end);writer.endObject();}else {writer.nullValue();}writer.field("details",self_.details);writer.endObject();return writer.failure;}
fn jsonStringify(self_:Result,writer:blot_json::Writer&)->Error {writer.beginObject();writer.key("replace");writer.beginObject();writer.field("start",self_.replace.start);writer.field("end",self_.replace.end);writer.endObject();writer.field("context",self_.context);writer.field("items",self_.items);writer.field("diagnostics",self_.diagnostics);writer.field("truncated",self_.truncated);writer.endObject();return writer.failure;}
struct Provider {ordinary:blot_reuse_revision_inputs::Provider,filename:const u8[:],replacement:Text=blot_support::none<const u8[:]>()}
fn canonical(self_:Provider&,path:const u8[:],out:u8[>..<]&)->Error {return self_.ordinary.canonical(path,out);}
fn read(self_:Provider&,path:const u8[:],limit:i64,out:u8[>..<]&)->Error {if self_.replacement.present && self_.filename==path {if self_.replacement.value.len>limit {return blot_error::Error.source_limit;}out.append(self_.replacement.value);return blot_error::Error.none;}return self_.ordinary.read(path,limit,out);}
fn resolve(self_:Provider&,source:const u8[:],request:const u8[:],options:blot_reuse_project::Options,out:u8[>..<]&)->Error {return self_.ordinary.resolve(source,request,options,out);}
fn cause(self_:const Provider&,error:Error)->const u8[:] {return self_.ordinary.cause(error);}
fn bounded(text:const u8[:],limit:i64)->const u8[:] {var end=min(text.len,limit);while end!=text.len && end!=0 && (text[end]&0xc0)==0x80 {end--;}return text[..end];}
fn compare(left:const u8[:],right:const u8[:])->i64 {for index in 0..min(left.len,right.len) {if left[index]<right[index] {return -1;}if left[index]>right[index] {return 1;}}if left.len<right.len {return -1;}if left.len>right.len {return 1;}return 0;}
fn earlier(left:Item,right:Item)->bool {if left.match_!=right.match_ {return matchCode(left.match_)<matchCode(right.match_);}if left.distance!=right.distance {return left.distance<right.distance;}let insertion=compare(left.insertText,right.insertText);if insertion!=0 {return insertion<0;}if left.kind!=right.kind {return itemKindCode(left.kind)<itemKindCode(right.kind);}let filename=compare(left.filename,right.filename);if filename!=0 {return filename<0;}return left.start<right.start;}
struct Display {pool:blot_parse_symbols::Pool&,types:blot_check_types::Store,nominals:const blot_check_check::Nominal[:],contracts:const blot_check_check::Contract[:],effect_templates:const blot_check_check::EffectTemplate[:]}
fn detailText(loaded:Project&,checked:Checked&,name:Name,truncated:bool&)->Text,Error {
 if name.ambiguous {return blot_support::some<const u8[:]>(own("ambiguous field/member")),blot_error::Error.none;}if name.scheme.root==0 {return blot_support::none<const u8[:]>(),blot_error::Error.none;}
 var adapter=Display{loaded.symbols,checked.types,checked.nominals,checked.contracts,checked.effect_templates};var text:u8[>..<]=[];var visits:i64=1024;
 let error=blot_reuse_type_display::appendBounded(adapter,text,name.scheme.root,visits);if error==blot_error::Error.out_of_memory {return blot_support::none<const u8[:]>(),error;}if error!=blot_error::Error.none {truncated=true;return blot_support::none<const u8[:]>(),blot_error::Error.none;}
 if name.scheme.obligations.len!=0 {text.append(" where {");let requirements=checked.obligations[name.scheme.obligations.start..name.scheme.obligations.start+name.scheme.obligations.len];for requirement,index in requirements[..min(32,requirements.len)] {if index!=0 {text.append(", ");}if requirement.name!=0 {let error=blot_reuse_type_display::text(adapter,text,loaded.symbols.get(requirement.name));if error!=blot_error::Error.none {return blot_support::none<const u8[:]>(),error;}}text.push(' ');let error=blot_reuse_type_display::appendBounded(adapter,text,requirement.ty,visits);if error==blot_error::Error.out_of_memory {return blot_support::none<const u8[:]>(),error;}if error!=blot_error::Error.none {truncated=true;}}if requirements.len>32 {truncated=true;}text.push('}');}
 if visits==0 {truncated=true;}let slice=bounded(text[..],1024);if slice.len!=text.len {truncated=true;}return blot_support::some<const u8[:]>(own(slice)),blot_error::Error.none;
}
fn makeItem(loaded:Project&,project_checked:CheckedProject&,checked:Checked&,captured:blot_check_check::EditorCapture,name:Name,prefix_kind:ProbeKind,budget:Budget&,truncated:bool&)->blot_support::Option<Item>,Error {
 let text=loaded.symbols.get(name.name);if text.len>256 {truncated=true;return blot_support::none<Item>(),blot_error::Error.none;}
 let kind_code=blot_check_check::editorName_kindCode(name.kind);var kind=ItemKind.value;match kind_code {0=>{kind=ItemKind.value;},1=>{kind=ItemKind.function;},2=>{kind=ItemKind.type_;},3=>{kind=ItemKind.constructor;},4=>{kind=ItemKind.field;},5=>{kind=ItemKind.member;},6=>{kind=ItemKind.module;},_=>{abort("invalid completion item kind");}}
 var item=Item{label:own(text),kind:kind,distance:name.distance};var published=false;
 if name.kind==blot_check_check::EditorName_kind.constructor && prefix_kind!=blot_reuse_completion_probe::Kind.constructor {if text.len==256 {truncated=true;let __cleanup_result_1_0: blot_support::Option<Item> = blot_support::none<Item>(); let __cleanup_result_1_1: Error = blot_error::Error.none; {if !published {item.deinit();}} return __cleanup_result_1_0, __cleanup_result_1_1;}var insertion:u8[>..<]=[];insertion.push('$');insertion.append(text);item.insertText=own(insertion[..]);}else {item.insertText=own(text);}
 if name.identity.unit!=0 && name.identity.unit<=loaded.units.len {
  item.filename=own(loaded.filename(name.identity.unit));var declaration=name.identity.decl;
  if (declaration&blot_check_types::opaque_name_bit)!=0 {declaration=0;if name.identity.unit<=project_checked.modules.len {let module=project_checked.modules[name.identity.unit-1];if module.present {for nominal in module.value.checked.nominals {if nominal.identity==name.identity {declaration=nominal.declaration;break;}}}}}
  if name.external.present {let external=name.external.value;if external.unit!=0 && external.unit<=project_checked.modules.len {let module=project_checked.modules[external.unit-1];if module.present {declaration=module.value.checked.bindings[external.binding].declaration;}}}
  if declaration!=0 {item.start=loaded.unit(name.identity.unit).tree.span(declaration).start;}
 }else {item.filename=own("");}
 let detail,error=detailText(loaded,checked,name,truncated);if error!=blot_error::Error.none {let __cleanup_result_2_0: blot_support::Option<Item> = blot_support::none<Item>(); let __cleanup_result_2_1: Error = error; {if !published {item.deinit();}} return __cleanup_result_2_0, __cleanup_result_2_1;}item.detail=detail;
 var expected=checked.expr_types[captured.node];if name.receiver && captured.kind!=blot_reuse_completion_probe::Kind.selector {let result,error=checked.types.function(captured.receiver,expected);if error!=blot_error::Error.none {let __cleanup_result_3_0: blot_support::Option<Item> = blot_support::none<Item>(); let __cleanup_result_3_1: Error = error; {if !published {item.deinit();}} return __cleanup_result_3_0, __cleanup_result_3_1;}expected=result;}
 var enclosing=blot_check_types::Scheme{};if captured.owner!=0 {enclosing=checked.bindings[captured.owner].scheme;}let matched,error=blot_reuse_completion_fit::fit(checked.types,expected,name.scheme,enclosing,checked.obligations,budget);if error!=blot_error::Error.none {let __cleanup_result_4_0: blot_support::Option<Item> = blot_support::none<Item>(); let __cleanup_result_4_1: Error = error; {if !published {item.deinit();}} return __cleanup_result_4_0, __cleanup_result_4_1;}item.match_=matched;if name.ambiguous {item.match_=blot_reuse_completion_fit::Match.incompatible;}published=true;let __cleanup_result_5_0: blot_support::Option<Item> = blot_support::some(item); let __cleanup_result_5_1: Error = blot_error::Error.none; {if !published {item.deinit();}} return __cleanup_result_5_0, __cleanup_result_5_1;
 {if !published {item.deinit();}} }
fn diagnostic(filename:const u8[:],code:const u8[:],message:const u8[:],span:Span,truncated:bool&)->Diagnostic,Error {let text=bounded(message,1024);     if text.len!=message.len {truncated=true;}     let __field_order_591_filename: const u8[:] = own(filename); let __field_order_592_code: const u8[:] = own(code); let __field_order_593_message: const u8[:] = own(text); let __field_order_594_start: u32 = span.start; let __field_order_595_end: u32 = span.end; return Diagnostic{ filename: __field_order_591_filename, code: __field_order_592_code, start: __field_order_594_start, end: __field_order_595_end, message: __field_order_593_message },blot_error::Error.none;}
// Select each borrowed view once; the formatter owns every retained text field.
fn loadedDiagnostic(loaded:const Project&,target:const u8[:],issue:blot_reuse_project::Diagnostic,probe:Probe,unit:u32,truncated:bool&)->Diagnostic,Error {
 let span:Span={if issue.unit==unit {probe.originalSpan(issue.span)}else {issue.span}};
 let path:const u8[:] = {if issue.unit!=0 {loaded.filename(issue.unit)}else {target}};
 return diagnostic(path,issue.codeName(),issue.message(),span,truncated);
}
fn checkedDiagnostic(filename:const u8[:],issue:blot_reuse_project_check::Diagnostic,span:Span,truncated:bool&)->Diagnostic,Error {
 let value,error=diagnostic(filename,issue.codeName(),issue.message(),span,truncated);if error!=blot_error::Error.none {return Diagnostic{},error;}var owned=value;var published=false;
 if issue.hole.present || issue.explanation.present {owned.details=blot_support::some(DiagnosticDetails{});if issue.hole.present {let value,error=issue.hole.value.clone();if error!=blot_error::Error.none {let __cleanup_result_6_0: Diagnostic = Diagnostic{}; let __cleanup_result_6_1: Error = error; {if !published {owned.deinit();}} return __cleanup_result_6_0, __cleanup_result_6_1;}owned.details.value.hole=blot_support::some(value);}if issue.explanation.present {let value,error=issue.explanation.value.clone();if error!=blot_error::Error.none {let __cleanup_result_7_0: Diagnostic = Diagnostic{}; let __cleanup_result_7_1: Error = error; {if !published {owned.deinit();}} return __cleanup_result_7_0, __cleanup_result_7_1;}owned.details.value.explanation=blot_support::some(value);}}
 published=true;let __cleanup_result_8_0: Diagnostic = owned; let __cleanup_result_8_1: Error = blot_error::Error.none; {if !published {owned.deinit();}} return __cleanup_result_8_0, __cleanup_result_8_1;
 {if !published {owned.deinit();}} }
// Rebase only the owning run, keeping initialized prefixes and child ownership intact.
fn diagnosticRun(run:Diagnostic[:])->Diagnostic[:] {let canonical=diagnostic_pool.realloc_slice(run,run.len);assert(blot_support::same_slice_identity(canonical,run));return canonical;}
fn itemRun(run:Item[:])->Item[:] {let canonical=item_pool.realloc_slice(run,run.len);assert(blot_support::same_slice_identity(canonical,run));return canonical;}
fn noteLimit(self_:Result&,filename:const u8[:])->Error {
 self_.truncated=true;for issue in self_.diagnostics {if issue.code=="completion_limit" {return blot_error::Error.none;}}
 let issue,error=diagnostic(filename,"completion_limit","Completion result limit",self_.replace,self_.truncated);if error!=blot_error::Error.none {return error;}
 let source=diagnosticRun(self_.diagnostics);let kept=min(15,source.len);let replacement=diagnostic_pool.alloc_slice(kept+1);replacement[0]=issue;
 for index in 0..kept {replacement[index+1]=source[index];}for &old in source[kept..] {old.deinit();}
 if self_.diagnostics.len!=0 {diagnostic_pool.free_slice(self_.diagnostics);}self_.diagnostics=replacement;return blot_error::Error.none;
}
fn publishDiagnostics(result:Result&,diagnostics:blot_support_pooled_buffer::Buffer<Diagnostic>&,target:const u8[:])->Error {
 let limit:blot_support::Option<Diagnostic> = {
  if result.truncated {
   if diagnostics.items.len==16 {diagnostics.items[15].deinit();diagnostics.resize(15);}
   let issue,error=diagnostic(target,"completion_limit","Completion result limit",result.replace,result.truncated);if error!=blot_error::Error.none {return error;}blot_support::some(issue)
  }else {blot_support::none<Diagnostic>()}
 };
 let source=diagnosticRun(diagnostics.storage);let length=diagnostics.items.len;var offset:i64=0;if limit.present {offset=1;}
 let owned=diagnostic_pool.alloc_slice(length+offset);if limit.present {owned[0]=limit.value;}
 for index in 0..length {owned[index+offset]=source[index];}result.diagnostics=owned;diagnostics.clear();return blot_error::Error.none;
}
fn publishItems(result:Result&,items:blot_support_pooled_buffer::Buffer<Item>&) {
 let source=itemRun(items.storage);::sort<Item>(source[..items.items.len],earlier);
 if items.items.len>128 {for &item in source[128..items.items.len] {item.deinit();}items.resize(128);result.truncated=true;}
 let owned=item_pool.alloc_slice(items.items.len);for index in 0..items.items.len {owned[index]=source[index];}result.items=owned;items.clear();
}
struct Lexical {loaded:Project&,unit:u32,probe:Probe,items:blot_support_pooled_buffer::Buffer<Item> =blot_support_pooled_buffer::Buffer<Item>{},visits:i64=0,truncated:bool&}
fn shiftItems(items:blot_support_pooled_buffer::Buffer<Item>&,removed:i64) {let source=itemRun(items.storage);for at in removed+1..items.items.len {source[at-1]=source[at];}}
fn add(self_:Lexical&,symbol:u32,kind:ItemKind,node:u32,distance:u32)->Error {
 if symbol==0 {return blot_error::Error.none;}let name=self_.loaded.symbols.get(symbol);if name.len<self_.probe.prefix.len || name[..self_.probe.prefix.len]!=self_.probe.prefix {return blot_error::Error.none;}
 if name.len>256 || (kind==ItemKind.constructor && self_.probe.kind!=blot_reuse_completion_probe::Kind.constructor && name.len==256) {self_.truncated=true;return blot_error::Error.none;}
 for old,index in self_.items.items {if old.label==name {if old.distance<=distance {return blot_error::Error.none;}var removed=itemRun(self_.items.storage)[index];shiftItems(self_.items,index);self_.items.resize(self_.items.items.len-1);removed.deinit();break;}}
 if self_.items.items.len==4096 {self_.truncated=true;return blot_error::Error.none;}
 var item=Item{label:own(name),kind:kind,distance:distance,start:self_.loaded.unit(self_.unit).tree.span(node).start};var published=false;
 if kind==ItemKind.constructor && self_.probe.kind!=blot_reuse_completion_probe::Kind.constructor {let result=text_pool.alloc_slice(name.len+1);result[0]='$';for byte,index in name {result[index+1]=byte;}item.insertText=result;}else {item.insertText=own(name);}item.filename=own(self_.loaded.filename(self_.unit));let error=self_.items.push(item,item_pool);if error!=blot_error::Error.none {let __cleanup_result_9_0: Error = error; {if !published {item.deinit();}} return __cleanup_result_9_0;}published=true;let __cleanup_result_10_0: Error = blot_error::Error.none; {if !published {item.deinit();}} return __cleanup_result_10_0;
 {if !published {item.deinit();}} }
fn contains(self_:const Lexical&,node:u32)->bool {if node==0 {return false;}let span=self_.loaded.unit(self_.unit).tree.span(node);return span.start<=self_.probe.marker.start && self_.probe.marker.end<=span.end;}
recursive fn pattern(self_:Lexical&,id:u32,distance:u32,depth:i64)->Error {
 if id==0 {return blot_error::Error.none;}if depth>32 || self_.visits==4096 {self_.truncated=true;return blot_error::Error.none;}self_.visits++;let tree .= self_.loaded.unit(self_.unit).tree;let node=tree.node(id);
 if node.tag==blot_parse_ast::tag_pattern_name {let error=self_.add(node.a,ItemKind.value,id,distance);if error!=blot_error::Error.none {return error;}}
 if node.tag==blot_parse_ast::tag_pattern_field || node.tag==blot_parse_ast::tag_pattern_constructor {let error=self_.pattern(node.b,distance,depth+1);if error!=blot_error::Error.none {return error;}}
 for child in tree.children(id) {let error=self_.pattern(child,distance,depth+1);if error!=blot_error::Error.none {return error;}}return blot_error::Error.none;
}
recursive fn scope(self_:Lexical&,id:u32,depth:i64)->Error {
 if !self_.contains(id) {return blot_error::Error.none;}if depth>32 || self_.visits==4096 {self_.truncated=true;return blot_error::Error.none;}self_.visits++;let tree .= self_.loaded.unit(self_.unit).tree;let node=tree.node(id);let distance=(64-depth) as u32;
 if node.tag==blot_parse_ast::tag_lambda {if self_.contains(node.b) {let error=self_.add(tree.parameter(node.a).name,ItemKind.value,node.a,distance);if error!=blot_error::Error.none {return error;}}return self_.scope(node.b,depth+1);}
 if node.tag==blot_parse_ast::tag_block {for child in tree.children(id) {let statement=tree.node(child);if tree.span(child).end<=self_.probe.marker.start && statement.tag==blot_parse_ast::tag_let_stmt {let error=self_.pattern(statement.a,distance,0);if error!=blot_error::Error.none {return error;}}let error=self_.scope(child,depth+1);if error!=blot_error::Error.none {return error;}}return blot_error::Error.none;}
 if node.tag==blot_parse_ast::tag_let_stmt || node.tag==blot_parse_ast::tag_rebind_stmt || node.tag==blot_parse_ast::tag_unary {return self_.scope(node.b,depth+1);}
 if node.tag==blot_parse_ast::tag_return_stmt || node.tag==blot_parse_ast::tag_function_return_stmt || node.tag==blot_parse_ast::tag_yield_stmt || node.tag==blot_parse_ast::tag_group || node.tag==blot_parse_ast::tag_field {return self_.scope(node.a,depth+1);}
 if node.tag==blot_parse_ast::tag_apply || node.tag==blot_parse_ast::tag_field_access || node.tag==blot_parse_ast::tag_index_access {let error=self_.scope(node.a,depth+1);if error!=blot_error::Error.none {return error;}if node.tag!=blot_parse_ast::tag_field_access {return self_.scope(node.b,depth+1);}return blot_error::Error.none;}
 if node.tag==blot_parse_ast::tag_binary {let error=self_.scope(node.b,depth+1);if error!=blot_error::Error.none {return error;}return self_.scope(node.c,depth+1);}
 if node.tag==blot_parse_ast::tag_if_expr {for child in [node.a,node.b,node.c] {let error=self_.scope(child,depth+1);if error!=blot_error::Error.none {return error;}}return blot_error::Error.none;}
 for child in tree.children(id) {let error=self_.scope(child,depth+1);if error!=blot_error::Error.none {return error;}}return blot_error::Error.none;
}
fn lexicalFallback(loaded:Project&,unit:u32,probe:Probe,result:Result&)->Error {
 if probe.kind==blot_reuse_completion_probe::Kind.member || probe.kind==blot_reuse_completion_probe::Kind.selector || probe.kind==blot_reuse_completion_probe::Kind.intrinsic {return blot_error::Error.none;}
 var collector=Lexical{loaded:loaded,unit:unit,probe:probe,truncated:result.truncated};
 var cutoff:u32=0xffffffff;for issue in loaded.diagnostics.items {if issue.unit==unit {var start=issue.span.start;if issue.parse_detail.present && issue.parse_detail.value.has_declaration_origin {start=issue.parse_detail.value.declaration_origin.start;}cutoff=min(cutoff,start);}}
 let tree .= loaded.unit(unit).tree;
 for root in tree.roots.items {
  if tree.span(root).end>cutoff {continue;}let node=tree.node(root);
  if probe.kind==blot_reuse_completion_probe::Kind.expression && node.tag==blot_parse_ast::tag_value_decl {var kind=ItemKind.value;if tree.node(node.b).tag==blot_parse_ast::tag_lambda {kind=ItemKind.function;}let error=collector.add(node.a,kind,root,1000000);if error!=blot_error::Error.none {let __cleanup_result_11_0: Error = error; {for &item in collector.items.items {item.deinit();}collector.items.deinit(item_pool);} return __cleanup_result_11_0;}let error=collector.scope(node.b,0);if error!=blot_error::Error.none {let __cleanup_result_12_0: Error = error; {for &item in collector.items.items {item.deinit();}collector.items.deinit(item_pool);} return __cleanup_result_12_0;}}
  if probe.kind==blot_reuse_completion_probe::Kind.type_ && (node.tag==blot_parse_ast::tag_data_decl || node.tag==blot_parse_ast::tag_type_alias_decl || node.tag==blot_parse_ast::tag_contract_decl) {let error=collector.add(node.a,ItemKind.type_,root,1000000);if error!=blot_error::Error.none {let __cleanup_result_13_0: Error = error; {for &item in collector.items.items {item.deinit();}collector.items.deinit(item_pool);} return __cleanup_result_13_0;}}
  if (probe.kind==blot_reuse_completion_probe::Kind.expression || probe.kind==blot_reuse_completion_probe::Kind.constructor) && node.tag==blot_parse_ast::tag_data_decl {for constructor in tree.children(node.b) {let error=collector.add(tree.node(constructor).a,ItemKind.constructor,constructor,1000000);if error!=blot_error::Error.none {let __cleanup_result_14_0: Error = error; {for &item in collector.items.items {item.deinit();}collector.items.deinit(item_pool);} return __cleanup_result_14_0;}}}
  if probe.kind==blot_reuse_completion_probe::Kind.expression && node.tag==blot_parse_ast::tag_import_decl {let import_=tree.import_decl(root);let error=collector.add(import_.namespace_,ItemKind.module,root,1000001);if error!=blot_error::Error.none {let __cleanup_result_15_0: Error = error; {for &item in collector.items.items {item.deinit();}collector.items.deinit(item_pool);} return __cleanup_result_15_0;}for binding in tree.list(import_.bindings) {let error=collector.add(tree.import_binding(binding).alias,ItemKind.value,binding,1000001);if error!=blot_error::Error.none {let __cleanup_result_16_0: Error = error; {for &item in collector.items.items {item.deinit();}collector.items.deinit(item_pool);} return __cleanup_result_16_0;}}}
 }
 publishItems(result,collector.items);let __cleanup_result_17_0: Error = blot_error::Error.none; {for &item in collector.items.items {item.deinit();}collector.items.deinit(item_pool);} return __cleanup_result_17_0;
 {for &item in collector.items.items {item.deinit();}collector.items.deinit(item_pool);} }
fn query<E>(executor:E&,entry:const u8[:],snapshot:blot_reuse_revision_inputs::Snapshot&,filename:const u8[:],position:u32)->Result,Error {
 let target,error=snapshot.canonical(filename);if error==blot_error::Error.out_of_memory {return Result{},error;}if error!=blot_error::Error.none {return Result{},blot_error::Error.missing_source;}
 let original,error=snapshot.read(target);if error==blot_error::Error.out_of_memory {return Result{},error;}if error==blot_error::Error.source_limit || error==blot_error::Error.file_too_big || error==blot_error::Error.stream_too_long {return Result{},blot_error::Error.source_limit;}if error!=blot_error::Error.none {return Result{},blot_error::Error.missing_source;}
 let captured,error=blot_reuse_completion_probe::capture(original,position);if error!=blot_error::Error.none {return Result{},error;}var probe=captured;
 var provider=Provider{ordinary:snapshot.provider(),filename:target};if probe.present {provider.replacement=blot_support::some<const u8[:]>(probe.value.source);}
 let source,error=blot_reuse_project::loadWithInputs(entry,snapshot.options(),provider);if error!=blot_error::Error.none {let __cleanup_result_18_0: Result = Result{}; let __cleanup_result_18_1: Error = error; {if probe.present {probe.value.deinit();}} return __cleanup_result_18_0, __cleanup_result_18_1;}var loaded=source;
 var unit:u32=0;for index in loaded.units.len {let id=(index+1) as u32;if loaded.filename(id)==target {unit=id;break;}}if unit==0 {let __cleanup_result_19_0: Result = Result{}; let __cleanup_result_19_1: Error = blot_error::Error.invalid_completion; {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_19_0, __cleanup_result_19_1;}
 for issue in loaded.diagnostics.items {if issue.code==blot_reuse_project::Code.source_limit || issue.code==blot_reuse_project::Code.file_limit {let __cleanup_result_20_0: Result = Result{}; let __cleanup_result_20_1: Error = blot_error::Error.source_limit; {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_20_0, __cleanup_result_20_1;}}
 if !probe.present {let __cleanup_result_21_0: Result = Result{replace:Span{position,position}}; let __cleanup_result_21_1: Error = blot_error::Error.none; {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_21_0, __cleanup_result_21_1;}
 var result=Result{replace:Span{position,position}};var published=false;
 var diagnostics=blot_support_pooled_buffer::Buffer<Diagnostic>{};
 for issue in loaded.diagnostics.items {
  if diagnostics.items.len==16 {result.truncated=true;break;}
  let owned,error=loadedDiagnostic(loaded,target,issue,probe.value,unit,result.truncated);if error!=blot_error::Error.none {let __cleanup_result_22_0: Result = Result{}; let __cleanup_result_22_1: Error = error; {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_22_0, __cleanup_result_22_1;}let error=diagnostics.push(owned,diagnostic_pool);if error!=blot_error::Error.none {var dropped=owned;dropped.deinit();let __cleanup_result_23_0: Result = Result{}; let __cleanup_result_23_1: Error = error; {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_23_0, __cleanup_result_23_1;}
 }
 let value=probe.value;result.replace=value.replace;
 if loaded.diagnostics.len!=0 {let error=lexicalFallback(loaded,unit,value,result);if error!=blot_error::Error.none {let __cleanup_result_24_0: Result = Result{}; let __cleanup_result_24_1: Error = error; {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_24_0, __cleanup_result_24_1;}let error=publishDiagnostics(result,diagnostics,target);if error!=blot_error::Error.none {let __cleanup_result_25_0: Result = Result{}; let __cleanup_result_25_1: Error = error; {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_25_0, __cleanup_result_25_1;}published=true;let __cleanup_result_26_0: Result = result; let __cleanup_result_26_1: Error = blot_error::Error.none; {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_26_0, __cleanup_result_26_1;}
 let budget_index=budgets.alloc_index(Budget{});let budget:Budget& =budgets[budget_index];
 let name,error=loaded.symbols.intern("self");if error!=blot_error::Error.none {let __cleanup_result_27_0: Result = Result{}; let __cleanup_result_27_1: Error = error; {budgets[budget_index]=Budget{};budgets.free(budget_index);} {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_27_0, __cleanup_result_27_1;}for text in blot_reuse_completion_names::builtin_types {let name,error=loaded.symbols.intern(text);if error!=blot_error::Error.none {let __cleanup_result_28_0: Result = Result{}; let __cleanup_result_28_1: Error = error; {budgets[budget_index]=Budget{};budgets.free(budget_index);} {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_28_0, __cleanup_result_28_1;}}
 let checked_project,error=blot_reuse_project_check::checkProjectForEditor(executor,loaded,blot_reuse_project_check::EditorQuery{unit:unit,marker:blot_check_check::EditorMarker{span:value.marker,kind:value.kind,prefix:value.prefix},budget:budget});if error!=blot_error::Error.none {let __cleanup_result_29_0: Result = Result{}; let __cleanup_result_29_1: Error = error; {budgets[budget_index]=Budget{};budgets.free(budget_index);} {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_29_0, __cleanup_result_29_1;}var checked=checked_project;
 for issue in checked.diagnostics {if diagnostics.items.len==16 {result.truncated=true;break;}var span=issue.span;if issue.unit==unit {span=value.originalSpan(span);}let owned,error=checkedDiagnostic(loaded.filename(issue.unit),issue,span,result.truncated);if error!=blot_error::Error.none {let __cleanup_result_30_0: Result = Result{}; let __cleanup_result_30_1: Error = error; {checked.deinit();} {budgets[budget_index]=Budget{};budgets.free(budget_index);} {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_30_0, __cleanup_result_30_1;}let error=diagnostics.push(owned,diagnostic_pool);if error!=blot_error::Error.none {var dropped=owned;dropped.deinit();let __cleanup_result_31_0: Result = Result{}; let __cleanup_result_31_1: Error = error; {checked.deinit();} {budgets[budget_index]=Budget{};budgets.free(budget_index);} {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_31_0, __cleanup_result_31_1;}}
 if unit<=checked.modules.len && checked.modules[unit-1].present {
  let module .= checked.modules[unit-1].value;
  if module.checked.editor.present {
   let captured=module.checked.editor.value;if captured.context.present {let context,error=captured.context.value.clone();if error!=blot_error::Error.none {let __cleanup_result_32_0: Result = Result{}; let __cleanup_result_32_1: Error = error; {checked.deinit();} {budgets[budget_index]=Budget{};budgets.free(budget_index);} {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_32_0, __cleanup_result_32_1;}result.context=blot_support::some(context);result.truncated=result.truncated || captured.context.value.truncated;}result.truncated=result.truncated || captured.truncated;
   var items=blot_support_pooled_buffer::Buffer<Item>{};
   for name in captured.names {let offered,error=makeItem(loaded,checked,module.checked,captured,name,value.kind,budget,result.truncated);if error!=blot_error::Error.none {let __cleanup_result_33_0: Result = Result{}; let __cleanup_result_33_1: Error = error; {for &item in items.items {item.deinit();}items.deinit(item_pool);} {checked.deinit();} {budgets[budget_index]=Budget{};budgets.free(budget_index);} {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_33_0, __cleanup_result_33_1;}if offered.present {let error=items.push(offered.value,item_pool);if error!=blot_error::Error.none {var dropped=offered.value;dropped.deinit();let __cleanup_result_34_0: Result = Result{}; let __cleanup_result_34_1: Error = error; {for &item in items.items {item.deinit();}items.deinit(item_pool);} {checked.deinit();} {budgets[budget_index]=Budget{};budgets.free(budget_index);} {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_34_0, __cleanup_result_34_1;}}}
   publishItems(result,items);
   {for &item in items.items {item.deinit();}items.deinit(item_pool);} }
 }
 result.truncated=result.truncated || budget.exhausted;let error=publishDiagnostics(result,diagnostics,target);if error!=blot_error::Error.none {let __cleanup_result_35_0: Result = Result{}; let __cleanup_result_35_1: Error = error; {checked.deinit();} {budgets[budget_index]=Budget{};budgets.free(budget_index);} {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_35_0, __cleanup_result_35_1;}published=true;let __cleanup_result_36_0: Result = result; let __cleanup_result_36_1: Error = blot_error::Error.none; {checked.deinit();} {budgets[budget_index]=Budget{};budgets.free(budget_index);} {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} return __cleanup_result_36_0, __cleanup_result_36_1;
 {checked.deinit();} {budgets[budget_index]=Budget{};budgets.free(budget_index);} {for &issue in diagnostics.items {issue.deinit();}diagnostics.deinit(diagnostic_pool);} {if !published {result.deinit();}} {loaded.deinit();} {if probe.present {probe.value.deinit();}} }
