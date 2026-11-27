// Owned frontend diagnostics, published after every frontend owner is released.
// Published frontend evidence is snapped to owned JSON before teardown.
namespace squid_reuse_dependency_consumer;
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
import check.wire_schema;
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
type Error=squid_error::Error;
type Span=squid_parse_ast::Span;
type Core=squid_check_core::Module;
type Pool=squid_parse_symbols::Pool;
type Owner=squid_reuse_dependency_payload::Owner;
type Writer=squid_json::Writer;
struct Stats {syntax_nodes:i64=0,body_elaborations:i64=0,body_lowerings:i64=0,imported_schemes:i64=0,normalization:squid_work_counters::Normalization=squid_work_counters::Normalization{}}
struct Publication {
 utf16:squid_support::Option<Span> =squid_support::none<Span>(),cause:squid_parse_syntax_diagnostics::Cause=squid_parse_syntax_diagnostics::grammar,
 expected_token:squid_support::Option<squid_parse_token::Tag> =squid_support::none<squid_parse_token::Tag>(),actual_token:squid_support::Option<squid_parse_token::Tag> =squid_support::none<squid_parse_token::Tag>(),details_json:u8[:]=default<u8[:]>(),forwarded:bool=false,
}
struct Details {bytes:const u8[:]}
fn jsonStringify(self_:Details,writer:Writer&)->Error {return squid_json::write(writer,squid_json::Raw{self_.bytes});}
reusable[] var diagnostic_bytes:u8[>..]=[];
reusable[] var staged_unit_runs:u32[>..]=[];
fn ownBytes(bytes:const u8[:])->u8[:] {let result=diagnostic_bytes.alloc_slice(bytes.len);if bytes.len!=0 {squid_native::copy_u8(result[0],bytes[0],bytes.len as u64);}return result;}
fn freeBytes(bytes:u8[:]) {if bytes.len!=0 {diagnostic_bytes.free_slice(bytes);}}
fn ownU32s(items:const u32[:])->u32[:] {let result=staged_unit_runs.alloc_slice(items.len);for v,i in items {result[i]=v;}return result;}
fn freeU32s(items:u32[:]) {if items.len!=0 {staged_unit_runs.free_slice(items);}}
struct Diagnostic {
 stage:const u8[:]=default<const u8[:]>(),unit:u32=0,code:u8[:]=default<u8[:]>(),start:u32=0,end:u32=0,message:u8[:]=default<u8[:]>(),publication:squid_support::Option<Publication> =squid_support::none<Publication>(),
}
fn init(unit:u32,stage:const u8[:],code:const u8[:],span:Span,message:const u8[:])->Diagnostic,Error {
 return Diagnostic{stage:stage,unit:unit,code:ownBytes(code),start:span.start,end:span.end,message:ownBytes(message)},squid_error::Error.none;
}
fn deinit(self_:Diagnostic&) {if self_.publication.present {freeBytes(self_.publication.value.details_json);}freeBytes(self_.code);freeBytes(self_.message);self_=Diagnostic{};}
fn tokenName(tag:squid_parse_token::Tag)->const u8[:] {
 if tag==squid_parse_token::eof {return "eof";}
 if tag==squid_parse_token::identifier {return "identifier";}
 if tag==squid_parse_token::type_identifier {return "type_identifier";}
 if tag==squid_parse_token::integer {return "integer";}
 if tag==squid_parse_token::float {return "float";}
 if tag==squid_parse_token::string {return "string";}
 if tag==squid_parse_token::intrinsic {return "intrinsic";}
 if tag==squid_parse_token::symbol {return "symbol";}
 if tag==squid_parse_token::comment {return "comment";}
 if tag==squid_parse_token::l_paren {return "l_paren";}
 if tag==squid_parse_token::r_paren {return "r_paren";}
 if tag==squid_parse_token::l_bracket {return "l_bracket";}
 if tag==squid_parse_token::r_bracket {return "r_bracket";}
 if tag==squid_parse_token::l_brace {return "l_brace";}
 if tag==squid_parse_token::r_brace {return "r_brace";}
 if tag==squid_parse_token::comma {return "comma";}
 if tag==squid_parse_token::dot {return "dot";}
 if tag==squid_parse_token::selector {return "selector";}
 if tag==squid_parse_token::dot_dot {return "dot_dot";}
 if tag==squid_parse_token::colon {return "colon";}
 if tag==squid_parse_token::colon_equal {return "colon_equal";}
 if tag==squid_parse_token::arrow {return "arrow";}
 if tag==squid_parse_token::fat_arrow {return "fat_arrow";}
 if tag==squid_parse_token::left_arrow {return "left_arrow";}
 if tag==squid_parse_token::hash {return "hash";}
 if tag==squid_parse_token::at {return "at";}
 if tag==squid_parse_token::ellipsis {return "ellipsis";}
 if tag==squid_parse_token::backtick {return "backtick";}
 if tag==squid_parse_token::dollar {return "dollar";}
 if tag==squid_parse_token::star {return "star";}
 if tag==squid_parse_token::caret {return "caret";}
 if tag==squid_parse_token::pipe {return "pipe";}
 if tag==squid_parse_token::bang {return "bang";}
 if tag==squid_parse_token::equal {return "equal";}
 if tag==squid_parse_token::kw_import {return "kw_import";}
 if tag==squid_parse_token::kw_as {return "kw_as";}
 if tag==squid_parse_token::kw_const {return "kw_const";}
 if tag==squid_parse_token::kw_let {return "kw_let";}
 if tag==squid_parse_token::kw_type {return "kw_type";}
 if tag==squid_parse_token::kw_is {return "kw_is";}
 if tag==squid_parse_token::kw_data {return "kw_data";}
 if tag==squid_parse_token::kw_effect {return "kw_effect";}
 if tag==squid_parse_token::kw_infixl {return "kw_infixl";}
 if tag==squid_parse_token::kw_infixr {return "kw_infixr";}
 if tag==squid_parse_token::kw_infix {return "kw_infix";}
 if tag==squid_parse_token::kw_func {return "kw_func";}
 if tag==squid_parse_token::kw_if {return "kw_if";}
 if tag==squid_parse_token::kw_then {return "kw_then";}
 if tag==squid_parse_token::kw_else {return "kw_else";}
 if tag==squid_parse_token::kw_do {return "kw_do";}
 if tag==squid_parse_token::kw_case {return "kw_case";}
 if tag==squid_parse_token::kw_of {return "kw_of";}
 if tag==squid_parse_token::kw_for {return "kw_for";}
 if tag==squid_parse_token::kw_in {return "kw_in";}
 if tag==squid_parse_token::kw_ever {return "kw_ever";}
 if tag==squid_parse_token::kw_use {return "kw_use";}
 if tag==squid_parse_token::kw_return {return "kw_return";}
 if tag==squid_parse_token::kw_yield {return "kw_yield";}
 if tag==squid_parse_token::kw_break {return "kw_break";}
 if tag==squid_parse_token::kw_continue {return "kw_continue";}
 if tag==squid_parse_token::kw_complete {return "kw_complete";}
 if tag==squid_parse_token::kw_true {return "kw_true";}
 if tag==squid_parse_token::kw_false {return "kw_false";}
 if tag==squid_parse_token::kw_and {return "kw_and";}
 if tag==squid_parse_token::kw_or {return "kw_or";}
 if tag==squid_parse_token::kw_from {return "kw_from";}
 if tag==squid_parse_token::kw_where {return "kw_where";}
 if tag==squid_parse_token::private_from {return "private_from";}
 if tag==squid_parse_token::private_where {return "private_where";}
 if tag==squid_parse_token::newline {return "newline";}
 if tag==squid_parse_token::indent {return "indent";}
 if tag==squid_parse_token::dedent {return "dedent";}
 if tag==squid_parse_token::kw_not {return "kw_not";}
 if tag==squid_parse_token::kw_fork {return "kw_fork";}
 if tag==squid_parse_token::semicolon {return "semicolon";}
 if tag==squid_parse_token::kw_spark {return "kw_spark";}
 if tag==squid_parse_token::char_literal {return "char_literal";}
 if tag==squid_parse_token::byte_string {return "byte_string";}
 abort("invalid source token ordinal");
}
fn causeName(cause:squid_parse_syntax_diagnostics::Cause)->const u8[:] {
 if cause==squid_parse_syntax_diagnostics::grammar {return "grammar";}if cause==squid_parse_syntax_diagnostics::delimiter {return "delimiter";}if cause==squid_parse_syntax_diagnostics::lexical_cause {return "lexical";}if cause==squid_parse_syntax_diagnostics::native_detail {return "native_detail";}abort("invalid diagnostic cause");
}
fn numericCodeName(code:squid_parse_ast::NumericCode)->const u8[:] {if code==squid_parse_ast::numericcode_integer_range {return "integer_range";}if code==squid_parse_ast::numericcode_float_range {return "float_range";}if code==squid_parse_ast::numericcode_float_literal {return "float_literal";}abort("invalid numeric fault ordinal");}
fn detailWrite(writer:Writer&,value:bool)->Error {return squid_json::write(writer,value);}
fn detailWrite(writer:Writer&,value:u8)->Error {return squid_json::write(writer,value);}
fn detailWrite(writer:Writer&,value:u32)->Error {return squid_json::write(writer,value);}
fn detailWrite(writer:Writer&,value:u64)->Error {return squid_json::write(writer,value);}
fn detailWrite(writer:Writer&,value:i64)->Error {return squid_json::write(writer,value);}
fn detailWrite(writer:Writer&,value:const u8[:])->Error {return squid_json::write(writer,value);}
fn detailWrite<T>(writer:Writer&,value:squid_support::Option<T>)->Error {if !value.present {return writer.nullValue();}return detailWrite(writer,value.value);}
fn detailWrite<T>(writer:Writer&,value:const T[:])->Error {let error=writer.beginArray();if error!=squid_error::Error.none {return error;}for item in value {let error=writer.separator(squid_json::FrameKind.array);if error!=squid_error::Error.none {return error;}let error=detailWrite(writer,item);if error!=squid_error::Error.none {return error;}}return writer.endArray();}
fn detailField<T>(writer:Writer&,name:const u8[:],value:T)->Error {let error=writer.key(name);if error!=squid_error::Error.none {return error;}return detailWrite(writer,value);}
fn detailRecord<T>(writer:Writer&,value:T)->Error {let error=writer.beginObject();if error!=squid_error::Error.none {return error;}const for <N,A> in fields<T> {let error=detailField(writer,N,value.A);if error!=squid_error::Error.none {return error;}}return writer.endObject();}
fn detailWrite(writer:Writer&,value:squid_parse_lexer::Diagnostic)->Error {
 writer.beginObject();detailField(writer,"code",squid_parse_lexer::code_name(value.code));detailField(writer,"start",value.start);detailField(writer,"end",value.end);writer.endObject();return writer.failure;
}
fn detailWrite(writer:Writer&,value:squid_parse_ast::Diagnostic)->Error {
 writer.beginObject();detailField(writer,"code",squid_parse_ast::code_name(value.code));detailField(writer,"start",value.start);detailField(writer,"end",value.end);
 writer.key("declaration_origin");if value.has_declaration_origin {detailWrite(writer,value.declaration_origin);}else {writer.nullValue();}
 writer.key("detail_span");if value.has_detail_span {detailWrite(writer,value.detail_span);}else {writer.nullValue();}
 writer.key("actual_token");if value.has_actual_token {detailWrite(writer,tokenName(value.actual_token));}else {writer.nullValue();}
 writer.key("expected_token");if value.has_expected_token {detailWrite(writer,tokenName(value.expected_token));}else {writer.nullValue();}
 writer.endObject();return writer.failure;
}
fn detailWrite(writer:Writer&,value:squid_parse_ast::NumericFault)->Error {writer.beginObject();detailField(writer,"node",value.node);detailField(writer,"code",numericCodeName(value.code));detailField(writer,"span",value.span);detailField(writer,"actual_token",tokenName(value.actual_token));writer.endObject();return writer.failure;}
fn detailWrite(writer:Writer&,value:squid_check_check::DiagnosticContextKind)->Error {return writer.enumValue(value);}
fn detailWrite(writer:Writer&,value:squid_reuse_dispatch_explanation::Explanation)->Error {return value.jsonStringify(writer);}
fn detailWrite(writer:Writer&,value:squid_reuse_hole_diagnostics::Snapshot)->Error {return value.jsonStringify(writer);}
fn terminatorName(value:squid_parse_source_operators::Terminator)->const u8[:] {if value==squid_parse_source_operators::terminator_return {return "return_";}if value==squid_parse_source_operators::terminator_break {return "break_";}if value==squid_parse_source_operators::terminator_continue {return "continue_";}return "none";}
// A checker diagnostic as the oracle's std.json renders it: every field in declaration order.
fn detailWrite(writer:Writer&,value:squid_check_check::Diagnostic)->Error {
 writer.beginObject();detailField(writer,"origin_unit",value.origin_unit);writer.key("code");writer.enumValue(value.code);detailField(writer,"span",value.span);detailField(writer,"node",value.node);
 writer.key("type_application");if value.type_application.present {writer.enumValue(value.type_application.value);}else {writer.nullValue();}
 detailField(writer,"symbol",value.symbol);detailField(writer,"implicit_type_witness",value.implicit_type_witness);detailField(writer,"source_terminator",terminatorName(value.source_terminator));
 detailField(writer,"numeric_literal",value.numeric_literal);detailField(writer,"purity",value.purity);detailField(writer,"detail",value.detail);detailField(writer,"hole",value.hole);detailField(writer,"explanation",value.explanation);
 detailField(writer,"contexts",value.contexts[..]);detailField(writer,"context_len",value.context_len);writer.endObject();return writer.failure;
}
fn forwardedDetails<T>(details:const T[:])->bool {return false;}
fn publishedDiagnostic<T>(unit:u32,stage:const u8[:],source:const u8[:],publication:squid_parse_syntax_diagnostics::Publication,details:T)->Diagnostic,Error {
 var formatted_message:u8[>..<]=[];
 let has_formatted=squid_parse_syntax_diagnostics::format_publication_message(publication,formatted_message);
 var created=Diagnostic{};var error=squid_error::Error.none;
 if has_formatted {let c,e=init(unit,stage,publication.code,publication.span,formatted_message[..]);created=c;error=e;}
 else {let c,e=init(unit,stage,publication.code,publication.span,publication.message);created=c;error=e;}
 if error!=squid_error::Error.none {return Diagnostic{},error;}var result=created;var published=false;
 var bytes:u8[>..]=[];var writer=Writer{out:bytes,options:squid_json::Options{}};let error=detailWrite(writer,details);if error!=squid_error::Error.none {let __cleanup_result_1_0: Diagnostic = Diagnostic{}; let __cleanup_result_1_1: Error = error; {if !published {result.deinit();}} return __cleanup_result_1_0, __cleanup_result_1_1;}if writer.failure!=squid_error::Error.none {let __cleanup_result_2_0: Diagnostic = Diagnostic{}; let __cleanup_result_2_1: Error = writer.failure; {if !published {result.deinit();}} return __cleanup_result_2_0, __cleanup_result_2_1;}
 let span,has_span=squid_parse_syntax_diagnostics::utf16(publication,source);var snap=Publication{cause:publication.cause,details_json:ownBytes(bytes[..]),forwarded:forwardedDetails(details)};
 if has_span {snap.utf16=squid_support::some(span);}if publication.has_expected_token {snap.expected_token=squid_support::some(publication.expected_token);}if publication.has_actual_token {snap.actual_token=squid_support::some(publication.actual_token);}
 result.publication=squid_support::some(snap);published=true;let __cleanup_result_3_0: Diagnostic = result; let __cleanup_result_3_1: Error = squid_error::Error.none; {if !published {result.deinit();}} return __cleanup_result_3_0, __cleanup_result_3_1;
 {if !published {result.deinit();}} }
fn write(self_:const Diagnostic&,out:u8[>..]&,filename:const u8[:])->Error {
 var writer=Writer{out:out,options:squid_json::Options{}};writer.beginObject();detailField(writer,"kind","diagnostic");detailField(writer,"filename",filename);detailField(writer,"stage",self_.stage);
 if self_.publication.present {
  let published=self_.publication.value;detailField(writer,"code",self_.code[..]);detailField(writer,"start",self_.start);detailField(writer,"end",self_.end);detailField(writer,"message",self_.message[..]);detailField(writer,"offset_encoding","utf8_bytes");detailField(writer,"utf16",published.utf16);detailField(writer,"cause",causeName(published.cause));
  writer.key("expected_token");if published.expected_token.present {detailWrite(writer,tokenName(published.expected_token.value));}else {writer.nullValue();}
  writer.key("actual_token");if published.actual_token.present {detailWrite(writer,tokenName(published.actual_token.value));}else {writer.nullValue();}
  writer.key("details");squid_json::write(writer,squid_json::Raw{published.details_json});
 }else {detailField(writer,"unit",self_.unit);detailField(writer,"code",self_.code[..]);detailField(writer,"start",self_.start);detailField(writer,"end",self_.end);detailField(writer,"message",self_.message[..]);}
 writer.endObject();if writer.failure!=squid_error::Error.none {return writer.failure;}out.push('\n');return squid_error::Error.none;
}
fn write<S>(self_:const Diagnostic&,stream:S&,filename:const u8[:])->Error {var bytes:u8[>..]=[];let error=self_.write(bytes,filename);if error!=squid_error::Error.none {return error;}return stream.writeAll(bytes[..]);}
// The result of one project build. `compiled` owns the Wasm bytes or, after a
// backend rejection, the diagnostic and its detail text.
struct Compiled {bytes:u8[:]=default<u8[:]>(),failed:bool=false,diagnostic:squid_compile::Diagnostic=squid_compile::Diagnostic{..},message:u8[:]=default<u8[:]>(),emitted_functions:i64=0,sparks_vectorized:i64=0,sparks_scalar_fallback:i64=0,staged_dep_units_valid:bool=false,staged_dep_units:u32[:]=default<u32[:]>(),staged_value_digest:u64=0}
fn text(self_:const Compiled&)->const u8[:] {return self_.diagnostic.code.message(self_.message);}
struct Result {compiled:Compiled=Compiled{..},stats:Stats=Stats{},diagnostic:squid_support::Option<Diagnostic> =squid_support::none<Diagnostic>()}
fn deinit(self_:Result&) {freeBytes(self_.compiled.bytes);freeBytes(self_.compiled.message);freeU32s(self_.compiled.staged_dep_units);if self_.diagnostic.present {self_.diagnostic.value.deinit();}self_=Result{};}
// Runs the backend and takes ownership of what it produced.
fn compileUnits(units:const Core[:],entry:u32,build_inputs:i64 = -1)->Compiled,Error {
 var bytes:u8[>..<]=[];var message:u8[>..<]=[];var staged_units:u32[>..<]=[];let outcome=squid_compile::compileWithStaged(units,entry,bytes,message,staged_units,build_inputs);
 if outcome.has_diagnostic {return Compiled{failed:true,diagnostic:outcome.diagnostic,message:ownBytes(message[..]),emitted_functions:outcome.emitted_functions,sparks_vectorized:outcome.sparks_vectorized,sparks_scalar_fallback:outcome.sparks_scalar_fallback, ..},squid_error::Error.none;}
 return Compiled{bytes:ownBytes(bytes[..]),emitted_functions:outcome.emitted_functions,sparks_vectorized:outcome.sparks_vectorized,sparks_scalar_fallback:outcome.sparks_scalar_fallback,staged_dep_units_valid:outcome.staged_dep_units_valid,staged_dep_units:ownU32s(staged_units[..]),staged_value_digest:outcome.staged_value_digest, ..},squid_error::Error.none;
}
fn compileUnitsWithAnalysis(units:const Core[:],entry:u32,pinfo:const squid_check_wire_schema::ProgramInfo&,build_inputs:i64 = -1)->Compiled,Error {
 var bytes:u8[>..<]=[];var message:u8[>..<]=[];var staged_units:u32[>..<]=[];let outcome=squid_compile::compileWithStagedAndAnalysis(units,entry,pinfo,bytes,message,staged_units,build_inputs);
 if outcome.has_diagnostic {return Compiled{failed:true,diagnostic:outcome.diagnostic,message:ownBytes(message[..]),emitted_functions:outcome.emitted_functions,sparks_vectorized:outcome.sparks_vectorized,sparks_scalar_fallback:outcome.sparks_scalar_fallback, ..},squid_error::Error.none;}
 return Compiled{bytes:ownBytes(bytes[..]),emitted_functions:outcome.emitted_functions,sparks_vectorized:outcome.sparks_vectorized,sparks_scalar_fallback:outcome.sparks_scalar_fallback,staged_dep_units_valid:outcome.staged_dep_units_valid,staged_dep_units:ownU32s(staged_units[..]),staged_value_digest:outcome.staged_value_digest, ..},squid_error::Error.none;
}
struct HoleDetails {hole:squid_reuse_hole_diagnostics::Snapshot}
struct ExplanationDetails {explanation:squid_reuse_dispatch_explanation::Explanation}
fn codeName(code:squid_check_check::Code)->const u8[:] {match code {const for <N,V> in variants<squid_check_check::Code> {V=>{return N;},}}}
fn coreCodeName(code:squid_check_core::Code)->const u8[:] {match code {const for <N,V> in variants<squid_check_core::Code> {V=>{return N;},}}}
fn detailWrite(writer:Writer&,value:HoleDetails)->Error {return detailRecord(writer,value);}

fn detailWrite(writer:Writer&,value:ExplanationDetails)->Error {return detailRecord(writer,value);}

fn detailWrite(writer:Writer&,value:squid_parse_ast::Span)->Error {return detailRecord(writer,value);}


fn detailWrite(writer:Writer&,value:squid_check_check::DiagnosticContext)->Error {return detailRecord(writer,value);}







fn squid_reuse_dependency_consumer::forwardedDetails(details:squid_reuse_dependency_consumer::HoleDetails)->bool {return true;}

fn squid_reuse_dependency_consumer::forwardedDetails(details:squid_reuse_dependency_consumer::ExplanationDetails)->bool {return true;}

fn detailWrite(writer:Writer&,value:squid_reuse_purity_diagnostics::Witness)->Error {return detailRecord(writer,value);}
fn detailWrite(writer:Writer&,value:squid_check_types::NominalIdentity)->Error {return detailRecord(writer,value);}
fn detailWrite(writer:Writer&,value:squid_reuse_partial_dependency::HoleDetails)->Error {return detailRecord(writer,value);}
fn detailWrite(writer:Writer&,value:squid_reuse_partial_dependency::ExplanationDetails)->Error {return detailRecord(writer,value);}
fn detailWrite(writer:Writer&,value:squid_reuse_partial_dependency::ContextDetails)->Error {return detailRecord(writer,value);}
fn detailWrite(writer:Writer&,value:squid_reuse_partial_dependency::OriginDetails)->Error {return detailRecord(writer,value);}
