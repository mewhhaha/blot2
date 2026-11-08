// Diagnostic evidence is serialized while its concrete source owner is live.
namespace blot_cli;
import .cli;
import support.json;
import support.json_adapters;
import support.io;
import support.error;
import support.option;
import support.path;
import parse.ast;
import parse.symbols;
import parse.syntax_diagnostics;
import check.check;
import check.diagnostic_location;
import backend.core_backend;
import reuse.project;
import reuse.project_check;
import reuse.dependency_consumer;
import reuse.purity_diagnostics;
import reuse.hole_diagnostics;
import reuse.dispatch_explanation;
fn emit<T>(stream:blot_io::Writer,value:T)->Error {var bytes:u8[>..<]=[];let error=blot_json::toBytes(value,bytes);if error!=blot_error::Error.none {return error;}bytes.push('\n');return blot_io::write_all(stream,bytes[..]);}
struct BasicDiagnostic {kind:const u8[:]="diagnostic",filename:const u8[:],stage:const u8[:],code:const u8[:],start:u32,end:u32,message:const u8[:]}
fn diagnostic(writer:blot_io::Writer,filename:const u8[:],stage:const u8[:],code:const u8[:],start:u32,end:u32,message:const u8[:])->Error {return emit(writer,BasicDiagnostic{filename:filename,stage:stage,code:code,start:start,end:end,message:message,..});}
fn enumName<T>(value:T)->const u8[:] {const for <N,V> in variants<T> {if value==V {return N;}}abort("invalid diagnostic enumeration");}
fn frontendDiagnostic<T>(writer:blot_io::Writer,filename:const u8[:],stage:const u8[:],source:const u8[:],publication:blot_parse_syntax_diagnostics::Publication,details:T)->Error {
 var issue,error=blot_reuse_dependency_consumer::publishedDiagnostic(0,stage,source,publication,details);if error!=blot_error::Error.none {return error;}var bytes:u8[>..]=[];let error=issue.write(bytes,filename);issue.deinit();if error!=blot_error::Error.none {return error;}return blot_io::write_all(writer,bytes[..]);
}
fn frontendOneDiagnostic<T>(writer:blot_io::Writer,filename:const u8[:],stage:const u8[:],source:const u8[:],publication:blot_parse_syntax_diagnostics::Publication,detail:T)->Error {let details:T[1]=[detail];return frontendDiagnostic(writer,filename,stage,source,publication,details[..]);}
fn namedDiagnostic(writer:blot_io::Writer,filename:const u8[:],stage:const u8[:],code:const u8[:],span:blot_parse_ast::Span,message:const u8[:],pool:const blot_parse_symbols::Pool&,symbol:u32)->Error {
 if symbol==0 {return diagnostic(writer,filename,stage,code,span.start,span.end,message);}var full:u8[>..<]=[];full.append(message);if code=="unknown_intrinsic"||code=="unknown_record_field" {full.push(' ');}else {full.append(": ");}full.append(pool.get(symbol));return diagnostic(writer,filename,stage,code,span.start,span.end,full[..]);
}
fn purityDiagnostic(writer:blot_io::Writer,filename:const u8[:],stage:const u8[:],source:const u8[:],code:const u8[:],span:blot_parse_ast::Span,pool:blot_parse_symbols::Pool&,module_name:const u8[:],witness:blot_check_check::PurityWitness)->Error {
 var message:u8[>..<]=[];let error=blot_reuse_purity_diagnostics::format(pool,module_name,witness,message);if error!=blot_error::Error.none {return error;}return frontendOneDiagnostic(writer,filename,stage,source,blot_parse_syntax_diagnostics::Publication{cause:blot_parse_syntax_diagnostics::native_detail,code:code,span:span,message:message[..],..},witness);
}
fn purityModuleName(source:const blot_reuse_project::Project&,witness:blot_check_check::PurityWitness,output:u8[>..<]&)->Error {
 if witness.operation_name.present {return blot_error::Error.none;}if witness.foreign {output.append("blot:compiler");return blot_error::Error.none;}if witness.identity.unit==source.prelude_unit {output.append("std/prelude");return blot_error::Error.none;}if source.input_mode==blot_reuse_project::InputMode.source&&witness.identity.unit==source.entry {output.append("main");return blot_error::Error.none;}if witness.identity.unit==0||witness.identity.unit>source.units.len {return blot_error::Error.operation_purity_origin_required;}
 let directory=blot_support_path::dirnameEnd(source.filename(source.entry));if !directory.present {return blot_error::Error.operation_purity_origin_required;}return blot_support_path::relative(source.filename(source.entry)[..directory.value],source.filename(witness.identity.unit),output);
}
fn emitDiagnostic(stream:blot_io::Writer,filename:const u8[:],related_filename:const u8[:],item:blot_backend_core_backend::Diagnostic,explanation:const blot_reuse_dispatch_explanation::Explanation?,origins:const blot_check_diagnostic_location::Origin[:])->Error {
 var bytes:u8[>..<]=[];var writer=blot_json::Writer{out:bytes,..};writer.beginObject();writer.field("kind","diagnostic");writer.field("filename",filename);writer.field("stage","emit");writer.field("code",enumName(item.code));writer.field("start",item.span.start);writer.field("end",item.span.end);writer.field("message",item.message());writer.key("related");if item.related.present {writer.write(blot_check_diagnostic_location::init(related_filename,item.related.value.span));}else {writer.nullValue();}writer.key("details");if explanation {writer.beginObject();writer.field("explanation",explanation);writer.endObject();}else {writer.nullValue();}if origins.len!=0 {writer.field("origins",origins);}writer.endObject();if writer.failure!=blot_error::Error.none {return writer.failure;}bytes.push('\n');return blot_io::write_all(stream,bytes[..]);
}
struct HoleDetail {hole:blot_reuse_hole_diagnostics::Snapshot}
struct ExplanationDetail {explanation:blot_reuse_dispatch_explanation::Explanation}
struct ExplanationContexts {explanation:blot_reuse_dispatch_explanation::Explanation,contexts:const blot_check_check::DiagnosticContext[:]}
struct ContextDetails {contexts:const blot_check_check::DiagnosticContext[:]}
fn checkDiagnostics(writer:blot_io::Writer,filename:const u8[:],source:const u8[:],pool:blot_parse_symbols::Pool&,items:const blot_check_check::Diagnostic[:])->Error {
 for item in items {let code=enumName(item.code);let publication=blot_parse_syntax_diagnostics::Publication{cause:blot_parse_syntax_diagnostics::native_detail,code:code,span:item.span,message:item.message(),..};var error=blot_error::Error.none;
  if item.hole.present {error=frontendDiagnostic(writer,filename,"check",source,publication,HoleDetail{item.hole.value});}
  else if item.explanation.present {error=frontendDiagnostic(writer,filename,"check",source,publication,ExplanationDetail{item.explanation.value});}
  else if item.purity.present {error=purityDiagnostic(writer,filename,"check",source,code,item.span,pool,"main",item.purity.value);}
  else if item.code==blot_check_check::Code.module_loader_required||item.numeric_literal.present {error=frontendOneDiagnostic(writer,filename,"check",source,publication,item);}
  else {error=namedDiagnostic(writer,filename,"check",code,item.span,item.message(),pool,item.symbol);}if error!=blot_error::Error.none {return error;}
 }return blot_error::Error.none;
}
fn projectDiagnostics(writer:blot_io::Writer,filename:const u8[:],loaded:blot_reuse_project::Project&,checked:const blot_reuse_project_check::CheckedProject&)->Error {
 for item in checked.diagnostics {var path=filename;if item.unit!=0 {path=loaded.filename(item.unit);}let contexts=item.contexts[..item.context_len];let publication=blot_parse_syntax_diagnostics::Publication{cause:blot_parse_syntax_diagnostics::native_detail,code:item.codeName(),span:item.span,message:item.message(),..};var error=blot_error::Error.none;
  if item.semantic.present&&item.semantic.value==blot_check_check::Code.module_loader_required {let unit .= loaded.unit(item.unit);let detail=blot_check_check::sourceImportDiagnostic(unit.tree);assert(detail.present);error=frontendOneDiagnostic(writer,path,"check-project",unit.source,publication,detail.value);}
  else if item.hole.present {error=frontendDiagnostic(writer,path,"check-project",loaded.unit(item.unit).source,publication,HoleDetail{item.hole.value});}
  else if item.explanation.present {error=frontendDiagnostic(writer,path,"check-project",loaded.unit(item.unit).source,publication,ExplanationContexts{item.explanation.value,contexts});}
  else if contexts.len!=0 {error=frontendDiagnostic(writer,path,"check-project",loaded.unit(item.unit).source,publication,ContextDetails{contexts});}
  else if item.numeric_literal.present {var detail=publication;detail.has_actual_token=true;detail.actual_token=item.numeric_literal.value.actual_token;error=frontendOneDiagnostic(writer,path,"check-project",loaded.unit(item.unit).source,detail,item.numeric_literal.value);}
  else if item.purity.present {var module_name:u8[>..<]=[];error=purityModuleName(loaded,item.purity.value,module_name);if error==blot_error::Error.none {error=purityDiagnostic(writer,path,"check-project",loaded.unit(item.unit).source,item.codeName(),item.span,loaded.symbols,module_name[..],item.purity.value);}}
  else {error=namedDiagnostic(writer,path,"check-project",item.codeName(),item.span,item.message(),loaded.symbols,item.symbol);}if error!=blot_error::Error.none {return error;}
 }return blot_error::Error.none;
}

fn blot_reuse_dependency_consumer::forwardedDetails(details:blot_cli::ContextDetails)->bool {return true;}
