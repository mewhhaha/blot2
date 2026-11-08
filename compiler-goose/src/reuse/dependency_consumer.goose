// A fresh no-import consumer checked against an admitted dependency interface.
// Published frontend evidence is snapped to owned JSON before teardown.
namespace blot_reuse_dependency_consumer;
import dictionary;
import parse.lexer;
import parse.parser;
import parse.symbols;
import parse.ast;
import parse.token;
import parse.syntax_diagnostics;
import check.check;
import check.core;
import check.core_builder;
import check.frozen_types;
import check.numeric_proof_headers;
import reuse.frozen_dependency;
import reuse.principal_interface;
import reuse.dependency_payload;
import reuse.hole_diagnostics;
import reuse.dispatch_explanation;
import reuse.purity_diagnostics;
import reuse.partial_dependency;
import reuse.dependency_project_consumer;
import backend.core_backend;
import work_counters;
import support.error;
import support.option;
import support.json;
type Error=blot_error::Error;
type Span=blot_parse_ast::Span;
type Core=blot_check_core::Module;
type Pool=blot_parse_symbols::Pool;
type Owner=blot_reuse_dependency_payload::Owner;
type Writer=blot_json::Writer;
struct Stats {syntax_nodes:i64=0,body_elaborations:i64=0,body_lowerings:i64=0,imported_schemes:i64=0,normalization:blot_work_counters::Normalization=blot_work_counters::Normalization{}}
struct Publication {
 utf16:blot_support::Option<Span> =blot_support::none<Span>(),cause:blot_parse_syntax_diagnostics::Cause=blot_parse_syntax_diagnostics::grammar,
 expected_token:blot_support::Option<blot_parse_token::Tag> =blot_support::none<blot_parse_token::Tag>(),actual_token:blot_support::Option<blot_parse_token::Tag> =blot_support::none<blot_parse_token::Tag>(),details_json:u8[:]=default<u8[:]>(),forwarded:bool=false,
}
struct Details {bytes:const u8[:]}
fn jsonStringify(self_:Details,writer:Writer&)->Error {return blot_json::write(writer,blot_json::Raw{self_.bytes});}
reusable[] var diagnostic_bytes:u8[>..]=[];
fn ownBytes(bytes:const u8[:])->u8[:] {let result=diagnostic_bytes.alloc_slice(bytes.len);for byte,index in bytes {result[index]=byte;}return result;}
fn freeBytes(bytes:u8[:]) {if bytes.len!=0 {diagnostic_bytes.free_slice(bytes);}}
struct Diagnostic {
 stage:const u8[:]=default<const u8[:]>(),unit:u32=0,code:u8[:]=default<u8[:]>(),start:u32=0,end:u32=0,message:u8[:]=default<u8[:]>(),publication:blot_support::Option<Publication> =blot_support::none<Publication>(),
}
fn init(unit:u32,stage:const u8[:],code:const u8[:],span:Span,message:const u8[:])->Diagnostic,Error {
 return Diagnostic{stage:stage,unit:unit,code:ownBytes(code),start:span.start,end:span.end,message:ownBytes(message)},blot_error::Error.none;
}
fn deinit(self_:Diagnostic&) {if self_.publication.present {freeBytes(self_.publication.value.details_json);}freeBytes(self_.code);freeBytes(self_.message);self_=Diagnostic{};}
fn tokenName(tag:blot_parse_token::Tag)->const u8[:] {
 if tag==blot_parse_token::eof {return "eof";}
 if tag==blot_parse_token::identifier {return "identifier";}
 if tag==blot_parse_token::type_identifier {return "type_identifier";}
 if tag==blot_parse_token::integer {return "integer";}
 if tag==blot_parse_token::float {return "float";}
 if tag==blot_parse_token::string {return "string";}
 if tag==blot_parse_token::intrinsic {return "intrinsic";}
 if tag==blot_parse_token::symbol {return "symbol";}
 if tag==blot_parse_token::comment {return "comment";}
 if tag==blot_parse_token::l_paren {return "l_paren";}
 if tag==blot_parse_token::r_paren {return "r_paren";}
 if tag==blot_parse_token::l_bracket {return "l_bracket";}
 if tag==blot_parse_token::r_bracket {return "r_bracket";}
 if tag==blot_parse_token::l_brace {return "l_brace";}
 if tag==blot_parse_token::r_brace {return "r_brace";}
 if tag==blot_parse_token::comma {return "comma";}
 if tag==blot_parse_token::dot {return "dot";}
 if tag==blot_parse_token::selector {return "selector";}
 if tag==blot_parse_token::dot_dot {return "dot_dot";}
 if tag==blot_parse_token::colon {return "colon";}
 if tag==blot_parse_token::colon_equal {return "colon_equal";}
 if tag==blot_parse_token::arrow {return "arrow";}
 if tag==blot_parse_token::fat_arrow {return "fat_arrow";}
 if tag==blot_parse_token::left_arrow {return "left_arrow";}
 if tag==blot_parse_token::hash {return "hash";}
 if tag==blot_parse_token::at {return "at";}
 if tag==blot_parse_token::ellipsis {return "ellipsis";}
 if tag==blot_parse_token::backtick {return "backtick";}
 if tag==blot_parse_token::dollar {return "dollar";}
 if tag==blot_parse_token::star {return "star";}
 if tag==blot_parse_token::caret {return "caret";}
 if tag==blot_parse_token::pipe {return "pipe";}
 if tag==blot_parse_token::bang {return "bang";}
 if tag==blot_parse_token::equal {return "equal";}
 if tag==blot_parse_token::kw_import {return "kw_import";}
 if tag==blot_parse_token::kw_as {return "kw_as";}
 if tag==blot_parse_token::kw_const {return "kw_const";}
 if tag==blot_parse_token::kw_let {return "kw_let";}
 if tag==blot_parse_token::kw_type {return "kw_type";}
 if tag==blot_parse_token::kw_is {return "kw_is";}
 if tag==blot_parse_token::kw_data {return "kw_data";}
 if tag==blot_parse_token::kw_effect {return "kw_effect";}
 if tag==blot_parse_token::kw_infixl {return "kw_infixl";}
 if tag==blot_parse_token::kw_infixr {return "kw_infixr";}
 if tag==blot_parse_token::kw_infix {return "kw_infix";}
 if tag==blot_parse_token::kw_func {return "kw_func";}
 if tag==blot_parse_token::kw_if {return "kw_if";}
 if tag==blot_parse_token::kw_then {return "kw_then";}
 if tag==blot_parse_token::kw_else {return "kw_else";}
 if tag==blot_parse_token::kw_do {return "kw_do";}
 if tag==blot_parse_token::kw_case {return "kw_case";}
 if tag==blot_parse_token::kw_of {return "kw_of";}
 if tag==blot_parse_token::kw_for {return "kw_for";}
 if tag==blot_parse_token::kw_in {return "kw_in";}
 if tag==blot_parse_token::kw_ever {return "kw_ever";}
 if tag==blot_parse_token::kw_use {return "kw_use";}
 if tag==blot_parse_token::kw_return {return "kw_return";}
 if tag==blot_parse_token::kw_yield {return "kw_yield";}
 if tag==blot_parse_token::kw_break {return "kw_break";}
 if tag==blot_parse_token::kw_continue {return "kw_continue";}
 if tag==blot_parse_token::kw_complete {return "kw_complete";}
 if tag==blot_parse_token::kw_true {return "kw_true";}
 if tag==blot_parse_token::kw_false {return "kw_false";}
 if tag==blot_parse_token::kw_and {return "kw_and";}
 if tag==blot_parse_token::kw_or {return "kw_or";}
 if tag==blot_parse_token::kw_from {return "kw_from";}
 if tag==blot_parse_token::kw_where {return "kw_where";}
 if tag==blot_parse_token::private_from {return "private_from";}
 if tag==blot_parse_token::private_where {return "private_where";}
 if tag==blot_parse_token::newline {return "newline";}
 if tag==blot_parse_token::indent {return "indent";}
 if tag==blot_parse_token::dedent {return "dedent";}
 abort("invalid source token ordinal");
}
fn causeName(cause:blot_parse_syntax_diagnostics::Cause)->const u8[:] {
 if cause==blot_parse_syntax_diagnostics::grammar {return "grammar";}if cause==blot_parse_syntax_diagnostics::delimiter {return "delimiter";}if cause==blot_parse_syntax_diagnostics::lexical_cause {return "lexical";}if cause==blot_parse_syntax_diagnostics::native_detail {return "native_detail";}abort("invalid diagnostic cause");
}
fn numericCodeName(code:blot_parse_ast::NumericCode)->const u8[:] {if code==blot_parse_ast::numericcode_integer_range {return "integer_range";}if code==blot_parse_ast::numericcode_float_range {return "float_range";}if code==blot_parse_ast::numericcode_float_literal {return "float_literal";}abort("invalid numeric fault ordinal");}
fn detailWrite(writer:Writer&,value:bool)->Error {return blot_json::write(writer,value);}
fn detailWrite(writer:Writer&,value:u8)->Error {return blot_json::write(writer,value);}
fn detailWrite(writer:Writer&,value:u32)->Error {return blot_json::write(writer,value);}
fn detailWrite(writer:Writer&,value:u64)->Error {return blot_json::write(writer,value);}
fn detailWrite(writer:Writer&,value:i64)->Error {return blot_json::write(writer,value);}
fn detailWrite(writer:Writer&,value:const u8[:])->Error {return blot_json::write(writer,value);}
fn detailWrite<T>(writer:Writer&,value:blot_support::Option<T>)->Error {if !value.present {return writer.nullValue();}return detailWrite(writer,value.value);}
fn detailWrite<T>(writer:Writer&,value:const T[:])->Error {let error=writer.beginArray();if error!=blot_error::Error.none {return error;}for item in value {let error=writer.separator(blot_json::FrameKind.array);if error!=blot_error::Error.none {return error;}let error=detailWrite(writer,item);if error!=blot_error::Error.none {return error;}}return writer.endArray();}
fn detailField<T>(writer:Writer&,name:const u8[:],value:T)->Error {let error=writer.key(name);if error!=blot_error::Error.none {return error;}return detailWrite(writer,value);}
fn detailRecord<T>(writer:Writer&,value:T)->Error {let error=writer.beginObject();if error!=blot_error::Error.none {return error;}const for <N,A> in fields<T> {let error=detailField(writer,N,value.A);if error!=blot_error::Error.none {return error;}}return writer.endObject();}
fn detailWrite(writer:Writer&,value:blot_parse_lexer::Diagnostic)->Error {
 writer.beginObject();detailField(writer,"code",blot_parse_lexer::code_name(value.code));detailField(writer,"start",value.start);detailField(writer,"end",value.end);writer.endObject();return writer.failure;
}
fn detailWrite(writer:Writer&,value:blot_parse_ast::Diagnostic)->Error {
 writer.beginObject();detailField(writer,"code",blot_parse_ast::code_name(value.code));detailField(writer,"start",value.start);detailField(writer,"end",value.end);
 writer.key("declaration_origin");if value.has_declaration_origin {detailWrite(writer,value.declaration_origin);}else {writer.nullValue();}
 writer.key("detail_span");if value.has_detail_span {detailWrite(writer,value.detail_span);}else {writer.nullValue();}
 writer.key("actual_token");if value.has_actual_token {detailWrite(writer,tokenName(value.actual_token));}else {writer.nullValue();}
 writer.key("expected_token");if value.has_expected_token {detailWrite(writer,tokenName(value.expected_token));}else {writer.nullValue();}
 writer.endObject();return writer.failure;
}
fn detailWrite(writer:Writer&,value:blot_parse_ast::NumericFault)->Error {writer.beginObject();detailField(writer,"node",value.node);detailField(writer,"code",numericCodeName(value.code));detailField(writer,"span",value.span);detailField(writer,"actual_token",tokenName(value.actual_token));writer.endObject();return writer.failure;}
fn detailWrite(writer:Writer&,value:blot_check_check::DiagnosticContextKind)->Error {return writer.enumValue(value);}
fn detailWrite(writer:Writer&,value:blot_reuse_dispatch_explanation::Explanation)->Error {return value.jsonStringify(writer);}
fn detailWrite(writer:Writer&,value:blot_reuse_hole_diagnostics::Snapshot)->Error {return value.jsonStringify(writer);}
fn forwardedDetails<T>(details:const T[:])->bool {return false;}
fn publishedDiagnostic<T>(unit:u32,stage:const u8[:],source:const u8[:],publication:blot_parse_syntax_diagnostics::Publication,details:T)->Diagnostic,Error {
 let created,error=init(unit,stage,publication.code,publication.span,publication.message);if error!=blot_error::Error.none {return Diagnostic{},error;}var result=created;var published=false;
 var bytes:u8[>..]=[];var writer=Writer{out:bytes,options:blot_json::Options{}};let error=detailWrite(writer,details);if error!=blot_error::Error.none {let __cleanup_result_1_0: Diagnostic = Diagnostic{}; let __cleanup_result_1_1: Error = error; {if !published {result.deinit();}} return __cleanup_result_1_0, __cleanup_result_1_1;}if writer.failure!=blot_error::Error.none {let __cleanup_result_2_0: Diagnostic = Diagnostic{}; let __cleanup_result_2_1: Error = writer.failure; {if !published {result.deinit();}} return __cleanup_result_2_0, __cleanup_result_2_1;}
 let span,has_span=blot_parse_syntax_diagnostics::utf16(publication,source);var snap=Publication{cause:publication.cause,details_json:ownBytes(bytes[..]),forwarded:forwardedDetails(details)};
 if has_span {snap.utf16=blot_support::some(span);}if publication.has_expected_token {snap.expected_token=blot_support::some(publication.expected_token);}if publication.has_actual_token {snap.actual_token=blot_support::some(publication.actual_token);}
 result.publication=blot_support::some(snap);published=true;let __cleanup_result_3_0: Diagnostic = result; let __cleanup_result_3_1: Error = blot_error::Error.none; {if !published {result.deinit();}} return __cleanup_result_3_0, __cleanup_result_3_1;
 {if !published {result.deinit();}} }
fn write(self_:const Diagnostic&,out:u8[>..]&,filename:const u8[:])->Error {
 var writer=Writer{out:out,options:blot_json::Options{}};writer.beginObject();detailField(writer,"kind","diagnostic");detailField(writer,"filename",filename);detailField(writer,"stage",self_.stage);
 if self_.publication.present {
  let published=self_.publication.value;detailField(writer,"code",self_.code[..]);detailField(writer,"start",self_.start);detailField(writer,"end",self_.end);detailField(writer,"message",self_.message[..]);detailField(writer,"offset_encoding","utf8_bytes");detailField(writer,"utf16",published.utf16);detailField(writer,"cause",causeName(published.cause));
  writer.key("expected_token");if published.expected_token.present {detailWrite(writer,tokenName(published.expected_token.value));}else {writer.nullValue();}
  writer.key("actual_token");if published.actual_token.present {detailWrite(writer,tokenName(published.actual_token.value));}else {writer.nullValue();}
  writer.key("details");blot_json::write(writer,blot_json::Raw{published.details_json});
 }else {detailField(writer,"unit",self_.unit);detailField(writer,"code",self_.code[..]);detailField(writer,"start",self_.start);detailField(writer,"end",self_.end);detailField(writer,"message",self_.message[..]);}
 writer.endObject();if writer.failure!=blot_error::Error.none {return writer.failure;}out.push('\n');return blot_error::Error.none;
}
fn write<S>(self_:const Diagnostic&,stream:S&,filename:const u8[:])->Error {var bytes:u8[>..]=[];let error=self_.write(bytes,filename);if error!=blot_error::Error.none {return error;}return stream.writeAll(bytes[..]);}
struct Result {compiled:blot_backend_core_backend::Result=default<blot_backend_core_backend::Result>(),stats:Stats=Stats{},diagnostic:blot_support::Option<Diagnostic> =blot_support::none<Diagnostic>()}
fn deinit(self_:Result&) {self_.compiled.deinit();if self_.diagnostic.present {self_.diagnostic.value.deinit();}self_=Result{};}
fn rejected(stage:const u8[:],code:const u8[:],span:Span,message:const u8[:])->Result,Error {let diagnostic,error=init(1,stage,code,span,message);if error!=blot_error::Error.none {return Result{},error;}return Result{diagnostic:blot_support::some(diagnostic)},blot_error::Error.none;}
struct HoleDetails {hole:blot_reuse_hole_diagnostics::Snapshot}
struct ExplanationDetails {explanation:blot_reuse_dispatch_explanation::Explanation}
fn exportKind(kind:blot_reuse_frozen_dependency::ExportKind)->blot_check_check::ImportedCatalog_kind {match kind {
 nominal=>{return blot_check_check::ImportedCatalog_kind.nominal;},constructor=>{return blot_check_check::ImportedCatalog_kind.constructor;},effect_family=>{return blot_check_check::ImportedCatalog_kind.effect_family;},contract=>{return blot_check_check::ImportedCatalog_kind.contract;},implementation=>{return blot_check_check::ImportedCatalog_kind.implementation;},value=>{abort("value export is not a catalog");},
}}
fn scheme(dependency:const blot_reuse_frozen_dependency::Module&,binding:u32)->blot_check_check::SchemeInterface {
 let definition=dependency.interface.bindings[binding];                  let __field_order_551_producer_binding: blot_check_check::BindingId = binding; let __field_order_552_proof_contract: const blot_check_numeric_proof_headers::Owned? .= blot_check_numeric_proof_headers::find(dependency.interface.proof_contracts,binding); let __field_order_553_types: blot_check_frozen_types::Source = blot_check_frozen_types::Source.frozen{dependency.interface.graph}; let __field_order_554_scheme: blot_check_types::Scheme = definition.scheme; let __field_order_555_obligations: const blot_check_types::Obligation[:] = dependency.interface.obligations; let __field_order_556_capability_flow: blot_check_check::CapabilityFlow = definition.capability_flow; let __field_order_557_capability_parameters: blot_check_capability_flow::Parameters = definition.capability_parameters; let __field_order_558_named_function: bool = definition.named_function; let __field_order_559_callees: blot_check_check::Callees = blot_check_check::Callees.frozen{dependency.interface}; return blot_check_check::SchemeInterface{ producer_binding: __field_order_551_producer_binding, proof_contract: __field_order_552_proof_contract, capability_flow: __field_order_556_capability_flow, capability_parameters: __field_order_557_capability_parameters, named_function: __field_order_558_named_function, types: __field_order_553_types, scheme: __field_order_554_scheme, obligations: __field_order_555_obligations, callees: __field_order_559_callees };
}
fn codeName(code:blot_check_check::Code)->const u8[:] {match code {const for <N,V> in variants<blot_check_check::Code> {V=>{return N;},}}}
fn coreCodeName(code:blot_check_core::Code)->const u8[:] {match code {const for <N,V> in variants<blot_check_core::Code> {V=>{return N;},}}}
fn compile(workspace:blot_backend_core_backend::CompileWorkspace&,source:const u8[:],pool:Pool&,dependency:const blot_reuse_frozen_dependency::Module&)->Result,Error {
 if dependency.core.unit!=2 || dependency.interface.unit!=2 {return Result{},blot_error::Error.invalid_artifact;}
 var inherited:blot_parse_parser::InheritedFixity[>..<]=[];for fixity in dependency.fixities {inherited.push(blot_parse_parser::InheritedFixity{fixity.operator,fixity.precedence,fixity.association,fixity.named});}
 var token_items:blot_parse_token::Token[>..<]=[];var comments:blot_parse_token::Token[>..<]=[];var lexical_issues:blot_parse_lexer::Diagnostic[>..<]=[];var tokens=blot_parse_lexer::init(token_items,comments,lexical_issues);
 let error=blot_parse_lexer::lex(source,tokens);if error!=blot_error::Error.none {return Result{},error;}
 if lexical_issues.len!=0 {let diagnostic,error=publishedDiagnostic(1,"parse-project",source,blot_parse_syntax_diagnostics::lexical(token_items[..],lexical_issues[0]),lexical_issues[..]);if error!=blot_error::Error.none {return Result{},error;}return Result{diagnostic:blot_support::some(diagnostic)},blot_error::Error.none;}
 let created,error=blot_parse_ast::initPooled();if error!=blot_error::Error.none {return Result{},error;}var tree=created;
 let error=blot_parse_parser::parse_with_fixities(source,token_items[..],pool,tree,inherited[..]);if error!=blot_error::Error.none {let __cleanup_result_4_0: Result = Result{}; let __cleanup_result_4_1: Error = error; {tree.deinit();} return __cleanup_result_4_0, __cleanup_result_4_1;}
 if tree.diagnostics.len!=0 {let publication,error=blot_parse_syntax_diagnostics::parse(token_items[..],tree.diagnostics.items[0]);if error!=blot_error::Error.none {let __cleanup_result_5_0: Result = Result{}; let __cleanup_result_5_1: Error = error; {tree.deinit();} return __cleanup_result_5_0, __cleanup_result_5_1;}let diagnostic,error=publishedDiagnostic(1,"parse-project",source,publication,tree.diagnostics.items);if error!=blot_error::Error.none {let __cleanup_result_6_0: Result = Result{}; let __cleanup_result_6_1: Error = error; {tree.deinit();} return __cleanup_result_6_0, __cleanup_result_6_1;}let __cleanup_result_7_0: Result = Result{diagnostic:blot_support::some(diagnostic)}; let __cleanup_result_7_1: Error = blot_error::Error.none; {tree.deinit();} return __cleanup_result_7_0, __cleanup_result_7_1;}
 var occupied:dictionary<u32,bool> =dictionary<u32,bool>{};
 for id in tree.roots.items {let node=tree.node(id);if node.tag==blot_parse_ast::tag_import_decl {let __cleanup_result_8_0: Result = Result{}; let __cleanup_result_8_1: Error = blot_error::Error.imported_consumer_unsupported; {tree.deinit();} return __cleanup_result_8_0, __cleanup_result_8_1;}
  if node.tag==blot_parse_ast::tag_value_decl || node.tag==blot_parse_ast::tag_data_decl || node.tag==blot_parse_ast::tag_effect_type_decl || node.tag==blot_parse_ast::tag_effect_decl {occupied.insert(node.a,true);}else if node.tag==blot_parse_ast::tag_implementation_decl {occupied.insert(tree.implementation(id).name,true);}
  if node.tag==blot_parse_ast::tag_data_decl {let count=tree.children(node.b).len;for index in count {let name=tree.node(tree.children(node.b)[index]).a;occupied.insert(name,true);}}
 }
 var imports:blot_check_check::ImportedBinding[>..<]=[];var catalogs:blot_check_check::ImportedCatalog[>..<]=[];var fixities:blot_check_check::ImportedFixity[>..]=[];
 catalogs.push(blot_check_check::ImportedCatalog{frozen:dependency.interface,kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0});
 for exported in dependency.exports {
  if occupied.contains(exported.name) {continue;}
  if exported.kind==blot_reuse_frozen_dependency::ExportKind.value {    let __field_order_560_name: blot_parse_symbols::Symbol = exported.name; let __field_order_561_target: blot_check_check::ExternalTarget = exported.target; let __field_order_562_origin: blot_parse_ast::Id = 0; let __field_order_563_interface: blot_check_check::SchemeInterface = scheme(dependency,exported.target.binding); imports.push(blot_check_check::ImportedBinding{ name: __field_order_560_name, target: __field_order_561_target, interface: __field_order_563_interface, origin: __field_order_562_origin });}
  else {catalogs.push(blot_check_check::ImportedCatalog{frozen:dependency.interface,name:exported.name,kind:exportKind(exported.kind),index:exported.catalog,origin:0});}
 }
 for fixity in dependency.fixities {
  if !fixity.named {    let __field_order_564_expose: bool = false; let __field_order_565_target: blot_check_check::ExternalTarget = fixity.producer; let __field_order_566_origin: blot_parse_ast::Id = 0; let __field_order_567_interface: blot_check_check::SchemeInterface = scheme(dependency,fixity.producer.binding); imports.push(blot_check_check::ImportedBinding{ target: __field_order_565_target, interface: __field_order_567_interface, origin: __field_order_566_origin, expose: __field_order_564_expose });}
  var target=blot_support::none<blot_check_check::ExternalTarget>();if !fixity.named {target=blot_support::some(fixity.producer);}fixities.push(blot_check_check::ImportedFixity{operator:fixity.operator,target:fixity.target,named:fixity.named,external:target});
 }
 let value,error=blot_check_check::checkModuleWithOptions(tree,pool,imports[..],catalogs[..],1,blot_check_check::ModuleOptions{prelude_unit:2,inherited_fixities:fixities[..],..});if error!=blot_error::Error.none {let __cleanup_result_9_0: Result = Result{}; let __cleanup_result_9_1: Error = error; {tree.deinit();} return __cleanup_result_9_0, __cleanup_result_9_1;}var checked=value;
 if checked.diagnostics.len!=0 {
  let item=checked.diagnostics[0];let stats=Stats{syntax_nodes:tree.nodes.len-1,body_elaborations:checked.body_elaborations,imported_schemes:checked.imported_schemes};let publication=blot_parse_syntax_diagnostics::Publication{cause:blot_parse_syntax_diagnostics::native_detail,code:codeName(item.code),span:item.span,message:item.message()};
  if item.hole.present {let diagnostic,error=publishedDiagnostic(1,"check",source,publication,HoleDetails{item.hole.value});if error!=blot_error::Error.none {let __cleanup_result_10_0: Result = Result{}; let __cleanup_result_10_1: Error = error; {checked.deinit();} {tree.deinit();} return __cleanup_result_10_0, __cleanup_result_10_1;}let __cleanup_result_11_0: Result = Result{stats:stats,diagnostic:blot_support::some(diagnostic)}; let __cleanup_result_11_1: Error = blot_error::Error.none; {checked.deinit();} {tree.deinit();} return __cleanup_result_11_0, __cleanup_result_11_1;}
  if item.explanation.present {let diagnostic,error=publishedDiagnostic(1,"check",source,publication,ExplanationDetails{item.explanation.value});if error!=blot_error::Error.none {let __cleanup_result_12_0: Result = Result{}; let __cleanup_result_12_1: Error = error; {checked.deinit();} {tree.deinit();} return __cleanup_result_12_0, __cleanup_result_12_1;}let __cleanup_result_13_0: Result = Result{stats:stats,diagnostic:blot_support::some(diagnostic)}; let __cleanup_result_13_1: Error = blot_error::Error.none; {checked.deinit();} {tree.deinit();} return __cleanup_result_13_0, __cleanup_result_13_1;}
  if item.symbol==0 {let __cleanup_result_14_0, __cleanup_result_14_1 = rejected("check",codeName(item.code),item.span,item.message()); {checked.deinit();} {tree.deinit();} return __cleanup_result_14_0, __cleanup_result_14_1;}
  var message:u8[>..];message.append(item.message());if codeName(item.code)=="unknown_intrinsic" || codeName(item.code)=="unknown_record_field" {message.append(" ");}else {message.append(": ");}message.append(pool.get(item.symbol));let __cleanup_result_15_0, __cleanup_result_15_1 = rejected("check",codeName(item.code),item.span,message[..]); {checked.deinit();} {tree.deinit();} return __cleanup_result_15_0, __cleanup_result_15_1;
 }
 let lowered,error=blot_check_core_builder::lower(tree,pool,checked);if error!=blot_error::Error.none {let __cleanup_result_16_0: Result = Result{}; let __cleanup_result_16_1: Error = error; {checked.deinit();} {tree.deinit();} return __cleanup_result_16_0, __cleanup_result_16_1;}var ir=lowered;
 if ir.value.diagnostics.len!=0 {let issue=ir.value.diagnostics[0];let __cleanup_result_17_0, __cleanup_result_17_1 = rejected("lower",coreCodeName(issue.code),issue.span,issue.message()); {ir.deinit();} {checked.deinit();} {tree.deinit();} return __cleanup_result_17_0, __cleanup_result_17_1;}
 let stats=Stats{syntax_nodes:tree.nodes.len-1,body_elaborations:checked.body_elaborations,body_lowerings:ir.value.body_lowerings,imported_schemes:checked.imported_schemes,normalization:checked.types.normalization};
 let copied,error=blot_reuse_dependency_payload::clone(dependency.core);if error!=blot_error::Error.none {let __cleanup_result_18_0: Result = Result{}; let __cleanup_result_18_1: Error = error; {ir.deinit();} {checked.deinit();} {tree.deinit();} return __cleanup_result_18_0, __cleanup_result_18_1;}var dependency_core=copied;
 let opened,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {let __cleanup_result_19_0: Result = Result{}; let __cleanup_result_19_1: Error = error; {dependency_core.deinit();} {ir.deinit();} {checked.deinit();} {tree.deinit();} return __cleanup_result_19_0, __cleanup_result_19_1;}var catalog=opened;
 let units,error=catalog.alloc<Core>(2);if error!=blot_error::Error.none {let __cleanup_result_20_0: Result = Result{}; let __cleanup_result_20_1: Error = error; {catalog.deinit();} {dependency_core.deinit();} {ir.deinit();} {checked.deinit();} {tree.deinit();} return __cleanup_result_20_0, __cleanup_result_20_1;}units[0]=ir.value;units[1]=dependency_core.value;
 let input_owners=[ir.owner,dependency_core.owner];let staged=blot_backend_core_backend::pinWorkspaceInputs(workspace,units,catalog,input_owners[..],[]);if staged!=blot_error::Error.none {return Result{},staged;}
 let emitted,error=blot_backend_core_backend::compileWithOptions(workspace,units,1,blot_backend_core_backend::CompileOptions{..});if error!=blot_error::Error.none {let __cleanup_result_21_0: Result = Result{}; let __cleanup_result_21_1: Error = error; {catalog.deinit();} {dependency_core.deinit();} {ir.deinit();} {checked.deinit();} {tree.deinit();} return __cleanup_result_21_0, __cleanup_result_21_1;}var result=Result{compiled:emitted,stats:stats};
 let unit_owners=[ir.owner,dependency_core.owner];let error=blot_backend_core_backend::pinResult(result.compiled,catalog,unit_owners[..],[]);if error!=blot_error::Error.none {result.deinit();let __cleanup_result_22_0: Result = Result{}; let __cleanup_result_22_1: Error = error; {catalog.deinit();} {dependency_core.deinit();} {ir.deinit();} {checked.deinit();} {tree.deinit();} return __cleanup_result_22_0, __cleanup_result_22_1;}let __cleanup_result_23_0: Result = result; let __cleanup_result_23_1: Error = blot_error::Error.none; {catalog.deinit();} {dependency_core.deinit();} {ir.deinit();} {checked.deinit();} {tree.deinit();} return __cleanup_result_23_0, __cleanup_result_23_1;
 {catalog.deinit();} {dependency_core.deinit();} {ir.deinit();} {checked.deinit();} {tree.deinit();} }

fn detailWrite(writer:Writer&,value:HoleDetails)->Error {return detailRecord(writer,value);}

fn detailWrite(writer:Writer&,value:ExplanationDetails)->Error {return detailRecord(writer,value);}

fn detailWrite(writer:Writer&,value:blot_parse_ast::Span)->Error {return detailRecord(writer,value);}


fn detailWrite(writer:Writer&,value:blot_check_check::DiagnosticContext)->Error {return detailRecord(writer,value);}

fn detailWrite(writer:Writer&,value:blot_reuse_partial_dependency::HoleDetails)->Error {return detailRecord(writer,value);}

fn detailWrite(writer:Writer&,value:blot_reuse_partial_dependency::ExplanationDetails)->Error {return detailRecord(writer,value);}

fn detailWrite(writer:Writer&,value:blot_reuse_partial_dependency::ContextDetails)->Error {return detailRecord(writer,value);}

fn detailWrite(writer:Writer&,value:blot_reuse_dependency_project_consumer::HoleDetails)->Error {return detailRecord(writer,value);}

fn detailWrite(writer:Writer&,value:blot_reuse_dependency_project_consumer::ExplanationDetails)->Error {return detailRecord(writer,value);}

fn detailWrite(writer:Writer&,value:blot_reuse_dependency_project_consumer::ContextDetails)->Error {return detailRecord(writer,value);}

fn blot_reuse_dependency_consumer::forwardedDetails(details:blot_reuse_dependency_consumer::HoleDetails)->bool {return true;}

fn blot_reuse_dependency_consumer::forwardedDetails(details:blot_reuse_dependency_consumer::ExplanationDetails)->bool {return true;}

fn detailWrite(writer:Writer&,value:blot_reuse_purity_diagnostics::Witness)->Error {return detailRecord(writer,value);}
fn detailWrite(writer:Writer&,value:blot_check_types::NominalIdentity)->Error {return detailRecord(writer,value);}
