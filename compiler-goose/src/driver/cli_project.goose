// Project commands; mirrors processProject in compiler/src/main.zig.
namespace blot_cli;
import .cli;
import .cli_diagnostics;
import execution_policy;
import phase_profile;
import work_counters;
import check.check;
import check.types;
import check.core;
import check.core_builder;
import compile;
import parse.ast;
import parse.symbols;
import reuse.project;
import reuse.principal_interface;
import reuse.type_display;
import reuse.dependency_consumer;
import reuse.project_check;
import reuse.dependency_payload;
import runtime.memory;
import support.error;
import support.option;
import support.native;
import support.io;
import support.json;
type Core=blot_check_core::Module;
type InputOwner=blot_reuse_dependency_payload::Owner;
type Project=blot_reuse_project::Project;
type CheckedProject=blot_reuse_project_check::CheckedProject;
struct ProjectStats {
 kind:const u8[:]="compilation",
 filename:const u8[:]=default<const u8[:]>(),
 stage:const u8[:]=default<const u8[:]>(),
 success:bool=false,
 total_us:i64=0,
 source_bytes:i64=0,
 files:i64=0,
 syntax_nodes:i64=0,
 symbol_bytes:i64=0,
 type_nodes:i64=0,
 type_versions:i64=0,
 check_occurs_steps:u64=0,
 row_versions:i64=0,
 effect_rows:i64=0,
 body_elaborations:i64=0,
 imported_schemes:i64=0,
 checker:blot_check_check::Counters=blot_check_check::Counters{..},
 core_nodes:i64=0,
 body_lowerings:i64=0,
 emitted_functions:i64=0,
 wasm_bytes:i64=0,
 load_us:i64=0,
 check_us:i64=0,
 lower_us:i64=0,
 emit_us:i64=0,
 write_us:i64=0,
 teardown_us:i64=0,
 phase_profile:blot_phase_profile::Record=blot_phase_profile::Record{..},
 memory:blot_runtime_memory::Counts=blot_runtime_memory::Counts{..},
 memory_scope:const u8[:]="Requested bytes of the compiler's pooled owners; excludes arrays owned by a scope, pool capacity and process RSS. All owners released before this record.",
}
fn processProject(writer:blot_io::Writer,command:Command,filename:const u8[:],options:Options,profile_requested:bool,output:Text,policy:Policy,error_detail:u8[>..]&,check_only:bool=false,include_private:bool=false)->bool,Error {
 // --profile clocks every phase of this compilation until its record.
 var profile=blot_support::none<blot_phase_profile::Profile>();var installation=blot_support::none<blot_phase_profile::Installation>();if profile_requested {profile=blot_support::some(blot_phase_profile::initProfile());installation=blot_support::some(blot_phase_profile::install(profile.value));}
 let meter=blot_runtime_memory::start();let started=now();var stats=ProjectStats{filename:filename,stage:stageName(command),..};let accepted,error=projectLoad(writer,command,filename,options,output,policy,started,stats,error_detail,check_only,include_private);
 var written=error;if error==blot_error::Error.none {stats.success=accepted;stats.total_us=elapsed(started);if profile.present {stats.phase_profile=profile.value.record();}stats.memory=meter.counts();written=emit(writer,stats);}
 if installation.present {installation.value.restore();}if profile.present {profile.value.deinit();}return accepted&&written==blot_error::Error.none,written;
}
fn projectLoad(writer:blot_io::Writer,command:Command,filename:const u8[:],options:Options,output:Text,policy:Policy,started:u64,stats:ProjectStats&,error_detail:u8[>..]&,check_only:bool,include_private:bool)->bool,Error {
 var loaded,error=blot_reuse_project::load(filename,options);if error!=blot_error::Error.none {formatIoError(error_detail,"load",filename,error);return false,error;}loaded.checking=blot_reuse_project::Lowering{io:true,workers:max(1 as u8,policy.frontend_workers)};
 let accepted,error=projectLoaded(writer,command,filename,output,policy,started,stats,loaded,error_detail,check_only,include_private);let release_start=now();loaded.deinit();stats.teardown_us+=elapsed(release_start);return accepted,error;
}
fn projectLoaded(writer:blot_io::Writer,command:Command,filename:const u8[:],output:Text,policy:Policy,started:u64,stats:ProjectStats&,loaded:Project&,error_detail:u8[>..]&,check_only:bool,include_private:bool)->bool,Error {
 stats.source_bytes=loaded.source_bytes;stats.files=loaded.units.len;stats.symbol_bytes=loaded.symbols.bytes.len;for unit in loaded.units.items {if unit.tree.nodes.len!=0 {stats.syntax_nodes+=unit.tree.nodes.len-1;}}
 for item in loaded.diagnostics.items {let path=if item.unit!=0 {loaded.filename(item.unit)}else {filename};var error=blot_error::Error.none;if item.publication.present {let unit .= loaded.unit(item.unit);if item.parse_code.present {error=frontendDiagnostic(writer,path,"parse-project",unit.source,item.publication.value,unit.tree.diagnostics.items);}else {error=frontendDiagnostic(writer,path,"parse-project",unit.source,item.publication.value,item.lexical_details);}}else {error=diagnostic(writer,path,"parse-project",item.codeName(),item.span.start,item.span.end,item.message());}if error!=blot_error::Error.none {return false,error;}}
 stats.load_us=elapsed(started);if loaded.diagnostics.len!=0 {return false,blot_error::Error.none;}if command==Command.parse_project {return true,blot_error::Error.none;}
 let check_start=now();var executor=blot_reuse_project_check::Workers{..};var checked,error=blot_reuse_project_check::checkProject(executor,loaded);if error!=blot_error::Error.none {return false,error;}var checked_live=true;
 let accepted,error=projectChecked(writer,command,filename,output,policy,check_start,stats,loaded,checked,checked_live,error_detail,check_only,include_private);if checked_live {let release_start=now();checked.deinit();stats.teardown_us+=elapsed(release_start);}return accepted,error;
}
struct DocDisplay {
 pool:blot_parse_symbols::Pool&,
 types:blot_check_types::Store,
 nominals:const blot_check_check::Nominal[:],
 contracts:const blot_check_check::Contract[:],
 effect_templates:const blot_check_check::EffectTemplate[:],
}
fn docRenderType(adapter:DocDisplay&,out:u8[>..<]&,ty:u32)->Error {
 out.clear();
 if ty==0 {return blot_error::Error.none;}
 var visits:i64=4096;
 let error=blot_reuse_type_display::appendBounded(adapter,out,ty,visits);
 if error==blot_error::Error.out_of_memory {return error;}
 return blot_error::Error.none;
}
fn docFormatObligation(adapter:DocDisplay&,checked:const blot_check_check::Checked&,out:u8[>..<]&,req:blot_check_types::Obligation)->bool,Error {
 out.clear();
 var visits:i64=1024;
 match req.kind {
  contract=>{
   var cname_sym:u32=0;
   for c in checked.contracts {if c.identity==req.identity {cname_sym=c.name;break;}}
   if cname_sym!=0 {out.append(adapter.pool.get(cname_sym));}else {out.append("Trait");}
   let head=adapter.types.head(req.ty,0);
   let node=adapter.types.node(head);
   if node.tag==blot_check_types::Tag.product {
    let args=adapter.types.list(blot_check_types::List{node.a,node.b,..});
    for arg in args {
     out.push(' ');
     let err=blot_reuse_type_display::appendBounded(adapter,out,arg,visits);
     if err==blot_error::Error.out_of_memory {return false,err;}
    }
   } else if req.ty!=0 {
    out.push(' ');
    let err=blot_reuse_type_display::appendBounded(adapter,out,req.ty,visits);
    if err==blot_error::Error.out_of_memory {return false,err;}
   }
   return true,blot_error::Error.none;
  },
  type_eq=>{
   let e1=blot_reuse_type_display::appendBounded(adapter,out,req.ty,visits);
   if e1==blot_error::Error.out_of_memory {return false,e1;}
   out.append(" == ");
   let e2=blot_reuse_type_display::appendBounded(adapter,out,req.result,visits);
   if e2==blot_error::Error.out_of_memory {return false,e2;}
   return true,blot_error::Error.none;
  },
  arithmetic,ordered,equality,integer=>{
   out.append(blot_check_types::obligationKindName(req.kind));
   out.push(' ');
   let err=blot_reuse_type_display::appendBounded(adapter,out,req.ty,visits);
   if err==blot_error::Error.out_of_memory {return false,err;}
   return true,blot_error::Error.none;
  },
  field,writable_field=>{
   if !req.explicit {return false,blot_error::Error.none;}
   let err=blot_reuse_type_display::appendBounded(adapter,out,req.ty,visits);
   if err==blot_error::Error.out_of_memory {return false,err;}
   if req.name!=0 {out.push('.');out.append(adapter.pool.get(req.name));}
   if req.result!=0 {
    out.append(": ");
    let e2=blot_reuse_type_display::appendBounded(adapter,out,req.result,visits);
    if e2==blot_error::Error.out_of_memory {return false,e2;}
   }
   return true,blot_error::Error.none;
  },
  _=>{return false,blot_error::Error.none;},
 }
}
fn docWriteObligations(jw:blot_json::Writer&,adapter:DocDisplay&,checked:const blot_check_check::Checked&,items:const blot_check_types::Obligation[:],scratch:u8[>..<]&)->Error {
 let err=jw.beginArray();if err!=blot_error::Error.none {return err;}
 for req in items {
  let show,ferr=docFormatObligation(adapter,checked,scratch,req);
  if ferr!=blot_error::Error.none {return ferr;}
  if !show {continue;}
  let e2=jw.element(scratch[..]);if e2!=blot_error::Error.none {return e2;}
 }
 return jw.endArray();
}
fn emitDocModule(stream:blot_io::Writer,loaded:Project&,checked:const blot_check_check::Checked&,unit_id:u32,include_private:bool)->Error {
 let unit .= loaded.unit(unit_id);
 let tree .= unit.tree;
 var adapter=DocDisplay{loaded.symbols,checked.types,checked.nominals,checked.contracts,checked.effect_templates};
 var bytes:u8[>..]=[];
 var jw=blot_json::Writer{bytes,blot_json::Options{..},..};
 var scratch:u8[>..<]=[];
 jw.beginObject();
 jw.field("kind","doc_module");
 jw.field("filename",loaded.filename(unit_id));
 jw.field("is_std",unit.is_std);
 jw.field("is_prelude",unit_id==loaded.prelude_unit);
 // Types (nominals: data, opaque, alias)
 jw.key("types");
 jw.beginArray();
 for nominal in checked.nominals {
  if nominal.identity.unit!=unit_id {continue;}
  if !include_private&&nominal.private {continue;}
  let hide_rep=nominal.is_opaque&&!include_private;
  blot_json::separator(jw,blot_json::FrameKind.array);
  jw.beginObject();
  jw.field("name",loaded.symbols.get(nominal.name));
  var tkind:const u8[:]="data";
  if nominal.is_opaque {tkind="opaque";}
  else if nominal.alias!=0 {tkind="alias";}
  jw.field("kind",tkind);
  jw.field("private",nominal.private);
  jw.field("opaque",nominal.is_opaque);
  jw.key("params");
  jw.beginArray();
  for psym in checked.types.list(nominal.parameter_names) {jw.element(loaded.symbols.get(psym));}
  jw.endArray();
  jw.key("alias");
  if !hide_rep&&nominal.alias!=0 {
   let rerr=docRenderType(adapter,scratch,nominal.alias);if rerr!=blot_error::Error.none {return rerr;}
   blot_json::quoted(jw,scratch[..]);
  } else {jw.nullValue();}
  jw.key("constructors");
  jw.beginArray();
  if !hide_rep&&nominal.alias==0 {
   let has_decl=nominal.declaration!=0&&(nominal.declaration as i64)<tree.nodes.len&&tree.node(nominal.declaration).tag==blot_parse_ast::tag_data_decl;
   for cidx in checked.types.list(nominal.constructors) {
    let ctor=checked.constructors[cidx];
    if !include_private&&ctor.private {continue;}
    var cspan=blot_parse_ast::Span{..};
    var ctor_ast:u32=0;
    if has_decl {
     let cnodes=tree.children(tree.node(nominal.declaration).b);
     if (ctor.tag as i64)<cnodes.len {ctor_ast=cnodes[ctor.tag];cspan=tree.span(ctor_ast);}
    }
    blot_json::separator(jw,blot_json::FrameKind.array);
    jw.beginObject();
    jw.field("name",loaded.symbols.get(ctor.name));
    jw.field("declared_record",ctor.declared_record);
    jw.key("payload");
    if ctor.payload!=0 {
     let rerr=docRenderType(adapter,scratch,ctor.payload);if rerr!=blot_error::Error.none {return rerr;}
     blot_json::quoted(jw,scratch[..]);
    } else {jw.nullValue();}
    jw.key("fields");
    jw.beginArray();
    if ctor.payload!=0 {
     let resolved,perr=adapter.types.resolve(ctor.payload,0);
     if perr==blot_error::Error.none {
      let pnode=adapter.types.node(resolved);
      if pnode.tag==blot_check_types::Tag.record {
       var emitted_from_ast=false;
       if ctor_ast!=0 {
        let pay_ast=tree.node(ctor_ast).b;
        if pay_ast!=0&&tree.node(pay_ast).tag==blot_parse_ast::tag_type_record {
         emitted_from_ast=true;
         for fid in tree.children(pay_ast) {
          let fnode=tree.node(fid);
          let fspan=tree.span(fid);
          var has_default=false;
          if fnode.c!=0&&((fnode.c-1+2) as i64)<tree.extra.items.len {
           has_default=tree.extra.items[fnode.c-1+2]!=0;
          }
          var fty:u32=0;
          for fi in 0..pnode.b {
           let rf=checked.types.recordField(pnode,fi);
           if rf.name==fnode.a {fty=rf.ty;break;}
          }
          let rerr=docRenderType(adapter,scratch,fty);if rerr!=blot_error::Error.none {return rerr;}
          blot_json::separator(jw,blot_json::FrameKind.array);
          jw.beginObject();
          jw.field("name",loaded.symbols.get(fnode.a));
          jw.field("type",scratch[..]);
          jw.field("has_default",has_default);
          jw.field("start",fspan.start);
          jw.field("end",fspan.end);
          jw.endObject();
         }
        }
       }
       if !emitted_from_ast {
        for fi in 0..pnode.b {
         let rf=checked.types.recordField(pnode,fi);
         let rerr=docRenderType(adapter,scratch,rf.ty);if rerr!=blot_error::Error.none {return rerr;}
         blot_json::separator(jw,blot_json::FrameKind.array);
         jw.beginObject();
         jw.field("name",loaded.symbols.get(rf.name));
         jw.field("type",scratch[..]);
         jw.field("has_default",false);
         jw.field("start",0 as u32);
         jw.field("end",0 as u32);
         jw.endObject();
        }
       }
      }
     }
    }
    jw.endArray();
    jw.field("start",cspan.start);
    jw.field("end",cspan.end);
    jw.endObject();
   }
  }
  jw.endArray();
  var nspan=blot_parse_ast::Span{..};
  if nominal.declaration!=0&&(nominal.declaration as i64)<tree.nodes.len {nspan=tree.span(nominal.declaration);}
  jw.field("start",nspan.start);
  jw.field("end",nspan.end);
  jw.endObject();
 }
 jw.endArray();
 // Traits (contracts)
 jw.key("traits");
 jw.beginArray();
 for contract in checked.contracts {
  if contract.identity.unit!=unit_id {continue;}
  if !include_private&&contract.private {continue;}
  blot_json::separator(jw,blot_json::FrameKind.array);
  jw.beginObject();
  jw.field("name",loaded.symbols.get(contract.name));
  jw.field("private",contract.private);
  jw.key("params");
  jw.beginArray();
  for psym in checked.types.list(contract.parameter_names) {jw.element(loaded.symbols.get(psym));}
  jw.endArray();
  jw.key("where");
  let werr=docWriteObligations(jw,adapter,checked,checked.contract_predicates[contract.predicates.start..contract.predicates.start+contract.predicates.len],scratch);
  if werr!=blot_error::Error.none {return werr;}
  jw.key("members");
  jw.beginArray();
  for member in checked.contract_members[contract.members.start..contract.members.start+contract.members.len] {
   blot_json::separator(jw,blot_json::FrameKind.array);
   jw.beginObject();
   jw.field("name",loaded.symbols.get(member.name));
   var mkind:const u8[:]="value";
   if member.kind==blot_reuse_principal_interface::ContractMemberKind.defined_type {mkind="defined_type";}
   else if member.kind==blot_reuse_principal_interface::ContractMemberKind.abstract_type {mkind="abstract_type";}
   jw.field("kind",mkind);
   jw.key("type");
   if member.root!=0 {
    let rerr=docRenderType(adapter,scratch,member.root);if rerr!=blot_error::Error.none {return rerr;}
    blot_json::quoted(jw,scratch[..]);
   } else {jw.nullValue();}
   jw.endObject();
  }
  jw.endArray();
  var tspan=blot_parse_ast::Span{..};
  if contract.declaration!=0&&(contract.declaration as i64)<tree.nodes.len {tspan=tree.span(contract.declaration);}
  jw.field("start",tspan.start);
  jw.field("end",tspan.end);
  jw.endObject();
 }
 jw.endArray();
 // Effects (effect families)
 jw.key("effects");
 jw.beginArray();
 for family in checked.effect_families {
  if family.identity.unit!=unit_id {continue;}
  if !include_private&&family.private {continue;}
  blot_json::separator(jw,blot_json::FrameKind.array);
  jw.beginObject();
  jw.field("name",loaded.symbols.get(family.name));
  jw.field("private",family.private);
  jw.field("callable",family.callable);
  jw.key("params");
  jw.beginArray();
  for psym in checked.types.list(family.parameter_names) {jw.element(loaded.symbols.get(psym));}
  jw.endArray();
  jw.key("operations");
  jw.beginArray();
  for op_idx in checked.types.list(family.operations) {
   let op=checked.effect_templates[op_idx];
   blot_json::separator(jw,blot_json::FrameKind.array);
   jw.beginObject();
   jw.field("name",loaded.symbols.get(op.name));
   let pe=docRenderType(adapter,scratch,op.parameter);if pe!=blot_error::Error.none {return pe;}
   jw.field("parameter",scratch[..]);
   let re=docRenderType(adapter,scratch,op.result);if re!=blot_error::Error.none {return re;}
   jw.field("result",scratch[..]);
   jw.endObject();
  }
  jw.endArray();
  var espan=blot_parse_ast::Span{..};
  for rid in tree.roots.items {
   let rn=tree.node(rid);
   if (rn.tag==blot_parse_ast::tag_effect_decl||rn.tag==blot_parse_ast::tag_effect_type_decl)&&rn.a==family.name {espan=tree.span(rid);break;}
  }
  jw.field("start",espan.start);
  jw.field("end",espan.end);
  jw.endObject();
 }
 jw.endArray();
 // Values & functions
 jw.key("values");
 jw.beginArray();
 for binding,bidx in checked.bindings {
  if binding.kind!=blot_reuse_principal_interface::Kind.global {continue;}
  if binding.external.present||binding.declaration==0 {continue;}
  if (binding.declaration as i64)>=tree.nodes.len {continue;}
  if !include_private&&binding.private {continue;}
  if tree.testMeta(binding.declaration).present {continue;}
  let dtag=tree.node(binding.declaration).tag;
  if dtag!=blot_parse_ast::tag_value_decl&&dtag!=blot_parse_ast::tag_entry_kernel_decl&&dtag!=blot_parse_ast::tag_entry_process_decl {continue;}
  blot_json::separator(jw,blot_json::FrameKind.array);
  jw.beginObject();
  jw.field("name",loaded.symbols.get(binding.name));
  jw.field("private",binding.private);
  var vkind:const u8[:]="const";
  if dtag==blot_parse_ast::tag_entry_kernel_decl {vkind="kernel";}
  else if dtag==blot_parse_ast::tag_entry_process_decl {vkind="process";}
  else if binding.named_function {vkind="func";}
  jw.field("kind",vkind);
  jw.key("modifier");
  if dtag==blot_parse_ast::tag_entry_kernel_decl {blot_json::quoted(jw,"entry");}
  else if dtag==blot_parse_ast::tag_entry_process_decl {blot_json::quoted(jw,"entry");}
  else {
   let vdecl=tree.value_decl(binding.declaration);
   if vdecl.modifier!=0 {blot_json::quoted(jw,loaded.symbols.get(vdecl.modifier));}
   else if vdecl.exported {blot_json::quoted(jw,"entry");}
   else {jw.nullValue();}
  }
  let root_ty=if binding.scheme.root!=0 {binding.scheme.root}else {binding.ty};
  let rerr=docRenderType(adapter,scratch,root_ty);if rerr!=blot_error::Error.none {return rerr;}
  jw.field("type",scratch[..]);
  jw.field("own_mask",binding.capability_parameters.own);
  jw.field("own_count",binding.capability_parameters.own_count);
  jw.key("where");
  let werr=docWriteObligations(jw,adapter,checked,checked.obligations[binding.scheme.obligations.start..binding.scheme.obligations.start+binding.scheme.obligations.len],scratch);
  if werr!=blot_error::Error.none {return werr;}
  var assoc_type:u32=0;
  var assoc_member:u32=0;
  for assoc in checked.associated {
   if assoc.binding==(bidx as u32) {
    assoc_member=assoc.member;
    for nom in checked.nominals {if nom.identity==assoc.identity {assoc_type=nom.name;break;}}
    break;
   }
  }
  jw.key("associated_type");
  if assoc_type!=0 {blot_json::quoted(jw,loaded.symbols.get(assoc_type));}else {jw.nullValue();}
  jw.key("associated_member");
  if assoc_member!=0 {blot_json::quoted(jw,loaded.symbols.get(assoc_member));}else {jw.nullValue();}
  let vspan=tree.span(binding.declaration);
  jw.field("start",vspan.start);
  jw.field("end",vspan.end);
  jw.endObject();
 }
 jw.endArray();
 // Trait implementations
 jw.key("implementations");
 jw.beginArray();
 for impl_ in checked.implementations {
  if impl_.identity.unit!=unit_id {continue;}
  if !include_private&&impl_.private {continue;}
  blot_json::separator(jw,blot_json::FrameKind.array);
  jw.beginObject();
  jw.field("name",if impl_.name!=0 {loaded.symbols.get(impl_.name)}else {""});
  jw.field("private",impl_.private);
  var cname_sym:u32=0;
  for c in checked.contracts {if c.identity==impl_.contract {cname_sym=c.name;break;}}
  if cname_sym!=0 {jw.field("contract",loaded.symbols.get(cname_sym));}else {jw.field("contract","");}
  jw.key("head");
  jw.beginArray();
  for hty in checked.types.list(impl_.head) {
   let rerr=docRenderType(adapter,scratch,hty);if rerr!=blot_error::Error.none {return rerr;}
   jw.element(scratch[..]);
  }
  jw.endArray();
  jw.key("where");
  let werr=docWriteObligations(jw,adapter,checked,checked.implementation_predicates[impl_.predicates.start..impl_.predicates.start+impl_.predicates.len],scratch);
  if werr!=blot_error::Error.none {return werr;}
  var ispan=blot_parse_ast::Span{..};
  if impl_.origin_span.present {ispan=impl_.origin_span.value;}
  else if impl_.declaration!=0&&(impl_.declaration as i64)<tree.nodes.len {ispan=tree.span(impl_.declaration);}
  jw.field("start",ispan.start);
  jw.field("end",ispan.end);
  jw.endObject();
 }
 jw.endArray();
 jw.endObject();
 if jw.failure!=blot_error::Error.none {return jw.failure;}
 bytes.push('\n');
 return blot_io::write_all(stream,bytes[..]);
}
fn emitDocProject(writer:blot_io::Writer,loaded:Project&,checked:const CheckedProject&,include_private:bool)->Error {
 for item,index in checked.modules {
  if !item.present||!item.value.valid {continue;}
  let unit_id=(index+1) as u32;
  let error=emitDocModule(writer,loaded,item.value.checked,unit_id,include_private);
  if error!=blot_error::Error.none {return error;}
 }
 return blot_error::Error.none;
}
fn projectChecked(writer:blot_io::Writer,command:Command,filename:const u8[:],output:Text,policy:Policy,check_start:u64,stats:ProjectStats&,loaded:Project&,checked:CheckedProject&,checked_live:bool&,error_detail:u8[>..]&,check_only:bool,include_private:bool)->bool,Error {
 stats.body_elaborations=checked.body_elaborations;stats.imported_schemes=checked.imported_schemes;for item in checked.modules {if !item.present {continue;}let types=item.value.checked.types;stats.type_nodes+=types.nodes.len;stats.type_versions+=types.versions.len;stats.check_occurs_steps+=types.occurs_steps;stats.row_versions+=types.effects.versions.len;stats.effect_rows+=types.effects.rows.len;stats.checker.add(item.value.checked.counters);}
 let error=projectDiagnostics(writer,filename,loaded,checked);if error!=blot_error::Error.none {return false,error;}stats.check_us=elapsed(check_start);
 if command==Command.doc_project {
  let doc_err=emitDocProject(writer,loaded,checked,include_private);
  if doc_err!=blot_error::Error.none {return false,doc_err;}
  return checked.diagnostics.len==0,blot_error::Error.none;
 }
 if checked.diagnostics.len!=0 {return false,blot_error::Error.none;}if command==Command.check_project&&check_only {return true,blot_error::Error.none;}
 let lower_start=now();var catalog,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {return false,error;}let units,error=catalog.alloc<Core>(loaded.units.len);if error!=blot_error::Error.none {catalog.deinit();return false,error;}
 var unit_owners:InputOwner[>..<]=[];let accepted,error=projectLowered(writer,command,filename,output,lower_start,stats,loaded,checked,checked_live,units,unit_owners,error_detail);
 let release_start=now();for &owner in unit_owners {owner.release();}catalog.deinit();stats.teardown_us+=elapsed(release_start);return accepted,error;
}
fn projectLowered(writer:blot_io::Writer,command:Command,filename:const u8[:],output:Text,lower_start:u64,stats:ProjectStats&,loaded:Project&,checked:CheckedProject&,checked_live:bool&,units:Core[:],unit_owners:InputOwner[>..<]&,error_detail:u8[>..]&)->bool,Error {
 for unit,index in loaded.units.items {let id=(index+1) as u32;let lowering=blot_phase_profile::enter(blot_phase_profile::Phase.lower);let owned,error=blot_check_core_builder::lowerWithOrigins(unit.tree,loaded.symbols,checked.module(id).checked,blot_reuse_project_check::moduleOrigins(loaded));lowering.exit();if error!=blot_error::Error.none {return false,error;}
  var lowered=owned;lowered.value.unit=id;units[index]=lowered.value;unit_owners.push(lowered.owner);stats.core_nodes+=units[index].nodes.len-1;stats.body_lowerings+=units[index].body_lowerings;
  if units[index].diagnostics.len!=0 {let error=lowerDiagnostics(writer,loaded.filename(id),units[index]);stats.lower_us=elapsed(lower_start);return false,error;}
  stats.lower_us=elapsed(lower_start);}
 if command==Command.check_project {return true,blot_error::Error.none;}
 // Paths and the tiny import catalog remain for diagnostics; source, syntax
 // and mutable inference state cannot be consulted by emission.
 let release_start=now();checked.deinit();checked_live=false;for &unit in loaded.units.items {unit.tree.deinit();blot_reuse_project::releaseSource(unit.source);unit.source=default<const u8[:]>();}stats.teardown_us+=elapsed(release_start);
 // The backend's result is an owner of its own, requested in its phase.
 let emit_start=now();let backend=blot_phase_profile::enter(blot_phase_profile::Phase.backend);let compiled,error=blot_reuse_dependency_consumer::compileUnits(units,loaded.entry);backend.exit();if error!=blot_error::Error.none {return false,error;}stats.emitted_functions=compiled.emitted_functions;
 if compiled.failed {let error=diagnostic(writer,loaded.filename(compiled.diagnostic.unit),"emit",enumName(compiled.diagnostic.code),compiled.diagnostic.span.start,compiled.diagnostic.span.end,compiled.text());stats.emit_us=elapsed(emit_start);blot_reuse_dependency_consumer::freeBytes(compiled.message);blot_reuse_dependency_consumer::freeU32s(compiled.staged_dep_units);return false,error;}
 stats.wasm_bytes=compiled.bytes.len;stats.emit_us=elapsed(emit_start);let write_start=now();assert(output.present);let error=blot_io::write_file(output.value,compiled.bytes);blot_reuse_dependency_consumer::freeBytes(compiled.bytes);blot_reuse_dependency_consumer::freeU32s(compiled.staged_dep_units);if error!=blot_error::Error.none {formatIoError(error_detail,"write",output.value,error);return false,error;}stats.write_us=elapsed(write_start);return true,blot_error::Error.none;
}
