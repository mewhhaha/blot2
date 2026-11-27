// Diagnostic evidence is serialized while its concrete source owner is live.
namespace squid_cli;
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
import check.core;
import check.uniqueness;
import reuse.project;
import reuse.project_check;
import reuse.dependency_consumer;
import reuse.purity_diagnostics;
import reuse.hole_diagnostics;
import reuse.dispatch_explanation;
fn emit<T>(stream:squid_io::Writer,value:T)->Error {var bytes:u8[>..]=[];let error=squid_json::toBytes(value,bytes);if error!=squid_error::Error.none {return error;}bytes.push('\n');return squid_io::write_all(stream,bytes[..]);}
struct BasicDiagnostic {kind:const u8[:]="diagnostic",filename:const u8[:],stage:const u8[:],code:const u8[:],start:u32,end:u32,message:const u8[:]}
struct LowerDiagnostic {kind:const u8[:]="diagnostic",filename:const u8[:],stage:const u8[:]="lower",code:const u8[:],start:u32,end:u32,message:const u8[:],origin_kind:const u8[:] = "",origin_start:u32 = 0,origin_end:u32 = 0,subject_start:u32 = 0,subject_end:u32 = 0,holder_start:u32 = 0,holder_end:u32 = 0}
fn diagnostic(writer:squid_io::Writer,filename:const u8[:],stage:const u8[:],code:const u8[:],start:u32,end:u32,message:const u8[:])->Error {return emit(writer,BasicDiagnostic{filename:filename,stage:stage,code:code,start:start,end:end,message:message,..});}
fn lowerDiagnostics(writer:squid_io::Writer,filename:const u8[:],module:const squid_check_core::Module&)->Error {
 if module.diagnostics.len==0 {return squid_error::Error.none;}
 var origins:squid_check_uniqueness::OriginInfo[>..<]=[];
 squid_check_uniqueness::explain(module,origins);
 for item in module.diagnostics {
  var matched=false;
  var origin=squid_check_uniqueness::OriginInfo{..};
  for candidate in origins {
   if candidate.code==item.code&&candidate.span.start==item.span.start&&candidate.span.end==item.span.end&&(candidate.has_origin||candidate.subject_end>candidate.subject_start) {
    origin=candidate;matched=true;break;
   }
  }
  var error=squid_error::Error.none;
  if matched {
   error=emit(writer,LowerDiagnostic{filename:filename,code:enumName(item.code),start:item.span.start,end:item.span.end,message:item.message(),origin_kind:origin.origin_kind,origin_start:origin.origin_start,origin_end:origin.origin_end,subject_start:origin.subject_start,subject_end:origin.subject_end,holder_start:origin.holder_start,holder_end:origin.holder_end,..});
  } else {
   error=diagnostic(writer,filename,"lower",enumName(item.code),item.span.start,item.span.end,item.message());
  }
  if error!=squid_error::Error.none {return error;}
 }
 return squid_error::Error.none;
}
fn enumName<T>(value:T)->const u8[:] {match value {const for <N,V> in variants<T> {V variant=>{return N;},}}}
fn frontendDiagnostic<T>(writer:squid_io::Writer,filename:const u8[:],stage:const u8[:],source:const u8[:],publication:squid_parse_syntax_diagnostics::Publication,details:T)->Error {
 var issue,error=squid_reuse_dependency_consumer::publishedDiagnostic(0,stage,source,publication,details);if error!=squid_error::Error.none {return error;}var bytes:u8[>..]=[];let error=issue.write(bytes,filename);issue.deinit();if error!=squid_error::Error.none {return error;}return squid_io::write_all(writer,bytes[..]);
}
fn frontendOneDiagnostic<T>(writer:squid_io::Writer,filename:const u8[:],stage:const u8[:],source:const u8[:],publication:squid_parse_syntax_diagnostics::Publication,detail:T)->Error {let details:T[1]=[detail];return frontendDiagnostic(writer,filename,stage,source,publication,details[..]);}
fn namedDiagnostic(writer:squid_io::Writer,filename:const u8[:],stage:const u8[:],code:const u8[:],span:squid_parse_ast::Span,message:const u8[:],pool:const squid_parse_symbols::Pool&,symbol:u32)->Error {
 if symbol==0 {return diagnostic(writer,filename,stage,code,span.start,span.end,message);}var full:u8[>..]=[];full.append(message);if code=="unknown_intrinsic"||code=="unknown_record_field" {full.push(' ');}else {full.append(": ");}full.append(pool.get(symbol));return diagnostic(writer,filename,stage,code,span.start,span.end,full[..]);
}
fn purityDiagnostic(writer:squid_io::Writer,filename:const u8[:],stage:const u8[:],source:const u8[:],code:const u8[:],span:squid_parse_ast::Span,pool:squid_parse_symbols::Pool&,module_name:const u8[:],witness:squid_check_check::PurityWitness)->Error {
 var message:u8[>..]=[];let error=squid_reuse_purity_diagnostics::format(pool,module_name,witness,message);if error!=squid_error::Error.none {return error;}return frontendOneDiagnostic(writer,filename,stage,source,squid_parse_syntax_diagnostics::Publication{cause:squid_parse_syntax_diagnostics::native_detail,code:code,span:span,message:message[..],..},witness);
}
fn purityModuleName(source:const squid_reuse_project::Project&,witness:squid_check_check::PurityWitness,output:u8[>..<]&)->Error {
 if witness.operation_name.present {return squid_error::Error.none;}if witness.foreign {output.append("squid:compiler");return squid_error::Error.none;}if witness.identity.unit==source.prelude_unit {output.append("std/prelude");return squid_error::Error.none;}if source.input_mode==squid_reuse_project::InputMode.source&&witness.identity.unit==source.entry {output.append("main");return squid_error::Error.none;}if witness.identity.unit==0||witness.identity.unit>source.units.len {return squid_error::Error.operation_purity_origin_required;}
 let directory=squid_support_path::dirnameEnd(source.filename(source.entry));if !directory.present {return squid_error::Error.operation_purity_origin_required;}return squid_support_path::relative(source.filename(source.entry)[..directory.value],source.filename(witness.identity.unit),output);
}
struct HoleDetail {hole:squid_reuse_hole_diagnostics::Snapshot}
struct ExplanationDetail {explanation:squid_reuse_dispatch_explanation::Explanation}
struct ExplanationContexts {explanation:squid_reuse_dispatch_explanation::Explanation,contexts:const squid_check_check::DiagnosticContext[:]}
struct ContextDetails {contexts:const squid_check_check::DiagnosticContext[:]}
fn checkDiagnostics(writer:squid_io::Writer,filename:const u8[:],source:const u8[:],pool:squid_parse_symbols::Pool&,items:const squid_check_check::Diagnostic[:])->Error {
 for item in items {let code=enumName(item.code);let publication=squid_parse_syntax_diagnostics::Publication{cause:squid_parse_syntax_diagnostics::native_detail,code:code,span:item.span,message:item.message(),..};var error=squid_error::Error.none;
  if item.hole.present {error=frontendDiagnostic(writer,filename,"check",source,publication,HoleDetail{item.hole.value});}
  else if item.explanation.present {error=frontendDiagnostic(writer,filename,"check",source,publication,ExplanationDetail{item.explanation.value});}
  else if item.purity.present {error=purityDiagnostic(writer,filename,"check",source,code,item.span,pool,"main",item.purity.value);}
  else if item.code==squid_check_check::Code.module_loader_required||item.numeric_literal.present {error=frontendOneDiagnostic(writer,filename,"check",source,publication,item);}
  else {var sym=item.symbol;if item.detail.present {sym=0;}error=namedDiagnostic(writer,filename,"check",code,item.span,item.message(),pool,sym);}if error!=squid_error::Error.none {return error;}
 }return squid_error::Error.none;
}
fn projectDiagnostics(writer:squid_io::Writer,filename:const u8[:],loaded:squid_reuse_project::Project&,checked:const squid_reuse_project_check::CheckedProject&)->Error {
 for item in checked.diagnostics {let path=if item.unit!=0 {loaded.filename(item.unit)}else {filename};let contexts=item.contexts[..item.context_len];let publication=squid_parse_syntax_diagnostics::Publication{cause:squid_parse_syntax_diagnostics::native_detail,code:item.codeName(),span:item.span,message:item.message(),..};var error=squid_error::Error.none;
  if item.semantic.present&&item.semantic.value==squid_check_check::Code.module_loader_required {let unit .= loaded.unit(item.unit);let detail=squid_check_check::sourceImportDiagnostic(unit.tree);assert(detail.present);error=frontendOneDiagnostic(writer,path,"check-project",unit.source,publication,detail.value);}
  else if item.hole.present {error=frontendDiagnostic(writer,path,"check-project",loaded.unit(item.unit).source,publication,HoleDetail{item.hole.value});}
  else if item.explanation.present {error=frontendDiagnostic(writer,path,"check-project",loaded.unit(item.unit).source,publication,ExplanationContexts{item.explanation.value,contexts});}
  else if contexts.len!=0 {error=frontendDiagnostic(writer,path,"check-project",loaded.unit(item.unit).source,publication,ContextDetails{contexts});}
  else if item.numeric_literal.present {var detail=publication;detail.has_actual_token=true;detail.actual_token=item.numeric_literal.value.actual_token;error=frontendOneDiagnostic(writer,path,"check-project",loaded.unit(item.unit).source,detail,item.numeric_literal.value);}
  else if item.purity.present {var module_name:u8[>..<]=[];error=purityModuleName(loaded,item.purity.value,module_name);if error==squid_error::Error.none {error=purityDiagnostic(writer,path,"check-project",loaded.unit(item.unit).source,item.codeName(),item.span,loaded.symbols,module_name[..],item.purity.value);}}
  else {var sym=item.symbol;if item.detail.present {sym=0;}error=namedDiagnostic(writer,path,"check-project",item.codeName(),item.span,item.message(),loaded.symbols,sym);}if error!=squid_error::Error.none {return error;}
 }return squid_error::Error.none;
}

fn squid_reuse_dependency_consumer::detailWrite(writer:squid_reuse_dependency_consumer::Writer&,value:squid_cli::HoleDetail)->squid_error::Error {return squid_reuse_dependency_consumer::detailRecord(writer,value);}
fn squid_reuse_dependency_consumer::detailWrite(writer:squid_reuse_dependency_consumer::Writer&,value:squid_cli::ExplanationDetail)->squid_error::Error {return squid_reuse_dependency_consumer::detailRecord(writer,value);}
fn squid_reuse_dependency_consumer::detailWrite(writer:squid_reuse_dependency_consumer::Writer&,value:squid_cli::ExplanationContexts)->squid_error::Error {return squid_reuse_dependency_consumer::detailRecord(writer,value);}
fn squid_reuse_dependency_consumer::detailWrite(writer:squid_reuse_dependency_consumer::Writer&,value:squid_cli::ContextDetails)->squid_error::Error {return squid_reuse_dependency_consumer::detailRecord(writer,value);}
fn squid_reuse_dependency_consumer::forwardedDetails(details:squid_cli::HoleDetail)->bool {return true;}
fn squid_reuse_dependency_consumer::forwardedDetails(details:squid_cli::ExplanationDetail)->bool {return true;}
fn squid_reuse_dependency_consumer::forwardedDetails(details:squid_cli::ExplanationContexts)->bool {return true;}
fn squid_reuse_dependency_consumer::forwardedDetails(details:squid_cli::ContextDetails)->bool {return true;}
