// Owned frontend diagnostics, published after every frontend owner is released.
// Published frontend evidence is snapped to owned JSON before teardown.
namespace blot_reuse_dependency_consumer;
import dictionary;
import parse.lexer;
import parse.parser;
import parse.symbols;
import parse.ast;
import parse.token;
import parse.syntax_diagnostics;
import parse.source_operators;
import check.check;
import check.types;
import check.core;
import check.core_builder;
import check.frozen_types;
import reuse.frozen_dependency;
import reuse.principal_interface;
import reuse.dependency_payload;
import reuse.hole_diagnostics;
import reuse.dispatch_explanation;
import reuse.purity_diagnostics;
import reuse.partial_dependency;
import work_counters;
import compile;
import support.error;
import support.option;
import support.json;
import support.native;
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
fn ownBytes(bytes:const u8[:])->u8[:] {let result=diagnostic_bytes.alloc_slice(bytes.len);if bytes.len!=0 {blot_native::copy_u8(result[0],bytes[0],bytes.len as u64);}return result;}
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
 if tag==blot_parse_token::kw_not {return "kw_not";}
 if tag==blot_parse_token::kw_with {return "kw_with";}
 if tag==blot_parse_token::kw_fork {return "kw_fork";}
 if tag==blot_parse_token::semicolon {return "semicolon";}
 if tag==blot_parse_token::kw_spark {return "kw_spark";}
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
fn terminatorName(value:blot_parse_source_operators::Terminator)->const u8[:] {if value==blot_parse_source_operators::terminator_return {return "return_";}if value==blot_parse_source_operators::terminator_break {return "break_";}return "none";}
// A checker diagnostic as the oracle's std.json renders it: every field in declaration order.
fn detailWrite(writer:Writer&,value:blot_check_check::Diagnostic)->Error {
 writer.beginObject();detailField(writer,"origin_unit",value.origin_unit);writer.key("code");writer.enumValue(value.code);detailField(writer,"span",value.span);detailField(writer,"node",value.node);
 writer.key("type_application");if value.type_application.present {writer.enumValue(value.type_application.value);}else {writer.nullValue();}
 detailField(writer,"symbol",value.symbol);detailField(writer,"implicit_type_witness",value.implicit_type_witness);detailField(writer,"source_terminator",terminatorName(value.source_terminator));
 detailField(writer,"numeric_literal",value.numeric_literal);detailField(writer,"purity",value.purity);detailField(writer,"detail",value.detail);detailField(writer,"hole",value.hole);detailField(writer,"explanation",value.explanation);
 detailField(writer,"contexts",value.contexts[..]);detailField(writer,"context_len",value.context_len);writer.endObject();return writer.failure;
}
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
// The result of one project build. `compiled` owns the Wasm bytes or, after a
// backend rejection, the diagnostic and its detail text.
struct Compiled {bytes:u8[:]=default<u8[:]>(),failed:bool=false,diagnostic:blot_compile::Diagnostic=blot_compile::Diagnostic{..},message:u8[:]=default<u8[:]>(),emitted_functions:i64=0}
fn text(self_:const Compiled&)->const u8[:] {return self_.diagnostic.code.message(self_.message);}
struct Result {compiled:Compiled=Compiled{..},stats:Stats=Stats{},diagnostic:blot_support::Option<Diagnostic> =blot_support::none<Diagnostic>()}
fn deinit(self_:Result&) {freeBytes(self_.compiled.bytes);freeBytes(self_.compiled.message);if self_.diagnostic.present {self_.diagnostic.value.deinit();}self_=Result{};}
// Runs the backend and takes ownership of what it produced.
fn compileUnits(units:const Core[:],entry:u32,build_inputs:i64 = -1)->Compiled,Error {
 var bytes:u8[>..<]=[];var message:u8[>..<]=[];let outcome=blot_compile::compile(units,entry,bytes,message,build_inputs);
 if outcome.has_diagnostic {return Compiled{failed:true,diagnostic:outcome.diagnostic,message:ownBytes(message[..]),emitted_functions:outcome.emitted_functions, ..},blot_error::Error.none;}
 return Compiled{bytes:ownBytes(bytes[..]),emitted_functions:outcome.emitted_functions, ..},blot_error::Error.none;
}
struct HoleDetails {hole:blot_reuse_hole_diagnostics::Snapshot}
struct ExplanationDetails {explanation:blot_reuse_dispatch_explanation::Explanation}
fn codeName(code:blot_check_check::Code)->const u8[:] {match code {const for <N,V> in variants<blot_check_check::Code> {V=>{return N;},}}}
fn coreCodeName(code:blot_check_core::Code)->const u8[:] {match code {const for <N,V> in variants<blot_check_core::Code> {V=>{return N;},}}}
fn detailWrite(writer:Writer&,value:HoleDetails)->Error {return detailRecord(writer,value);}

fn detailWrite(writer:Writer&,value:ExplanationDetails)->Error {return detailRecord(writer,value);}

fn detailWrite(writer:Writer&,value:blot_parse_ast::Span)->Error {return detailRecord(writer,value);}


fn detailWrite(writer:Writer&,value:blot_check_check::DiagnosticContext)->Error {return detailRecord(writer,value);}







fn blot_reuse_dependency_consumer::forwardedDetails(details:blot_reuse_dependency_consumer::HoleDetails)->bool {return true;}

fn blot_reuse_dependency_consumer::forwardedDetails(details:blot_reuse_dependency_consumer::ExplanationDetails)->bool {return true;}

fn detailWrite(writer:Writer&,value:blot_reuse_purity_diagnostics::Witness)->Error {return detailRecord(writer,value);}
fn detailWrite(writer:Writer&,value:blot_check_types::NominalIdentity)->Error {return detailRecord(writer,value);}
fn detailWrite(writer:Writer&,value:blot_reuse_partial_dependency::HoleDetails)->Error {return detailRecord(writer,value);}
fn detailWrite(writer:Writer&,value:blot_reuse_partial_dependency::ExplanationDetails)->Error {return detailRecord(writer,value);}
fn detailWrite(writer:Writer&,value:blot_reuse_partial_dependency::ContextDetails)->Error {return detailRecord(writer,value);}
