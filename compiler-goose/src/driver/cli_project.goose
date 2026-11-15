// Project commands; mirrors processProject in compiler/src/main.zig.
namespace blot_cli;
import .cli;
import .cli_diagnostics;
import execution_policy;
import phase_profile;
import work_counters;
import check.check;
import check.core;
import check.core_builder;
import compile;
import reuse.project;
import reuse.dependency_consumer;
import reuse.project_check;
import reuse.dependency_payload;
import runtime.memory;
import support.error;
import support.option;
import support.native;
import support.io;
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
fn processProject(writer:blot_io::Writer,command:Command,filename:const u8[:],options:Options,profile_requested:bool,output:Text,policy:Policy)->bool,Error {
 // --profile clocks every phase of this compilation until its record.
 var profile=blot_support::none<blot_phase_profile::Profile>();var installation=blot_support::none<blot_phase_profile::Installation>();if profile_requested {profile=blot_support::some(blot_phase_profile::initProfile());installation=blot_support::some(blot_phase_profile::install(profile.value));}
 let meter=blot_runtime_memory::start();let started=now();var stats=ProjectStats{filename:filename,stage:stageName(command),..};let accepted,error=projectLoad(writer,command,filename,options,output,policy,started,stats);
 var written=error;if error==blot_error::Error.none {stats.success=accepted;stats.total_us=elapsed(started);if profile.present {stats.phase_profile=profile.value.record();}stats.memory=meter.counts();written=emit(writer,stats);}
 if installation.present {installation.value.restore();}if profile.present {profile.value.deinit();}return accepted&&written==blot_error::Error.none,written;
}
fn projectLoad(writer:blot_io::Writer,command:Command,filename:const u8[:],options:Options,output:Text,policy:Policy,started:u64,stats:ProjectStats&)->bool,Error {
 var loaded,error=blot_reuse_project::load(filename,options);if error!=blot_error::Error.none {return false,error;}loaded.checking=blot_reuse_project::Lowering{io:true,workers:policy.frontend_workers};
 let accepted,error=projectLoaded(writer,command,filename,output,policy,started,stats,loaded);let release_start=now();loaded.deinit();stats.teardown_us+=elapsed(release_start);return accepted,error;
}
fn projectLoaded(writer:blot_io::Writer,command:Command,filename:const u8[:],output:Text,policy:Policy,started:u64,stats:ProjectStats&,loaded:Project&)->bool,Error {
 stats.source_bytes=loaded.source_bytes;stats.files=loaded.units.len;stats.symbol_bytes=loaded.symbols.bytes.len;for unit in loaded.units.items {if unit.tree.nodes.len!=0 {stats.syntax_nodes+=unit.tree.nodes.len-1;}}
 for item in loaded.diagnostics.items {let path=if item.unit!=0 {loaded.filename(item.unit)}else {filename};var error=blot_error::Error.none;if item.publication.present {let unit .= loaded.unit(item.unit);if item.parse_code.present {error=frontendDiagnostic(writer,path,"parse-project",unit.source,item.publication.value,unit.tree.diagnostics.items);}else {error=frontendDiagnostic(writer,path,"parse-project",unit.source,item.publication.value,item.lexical_details);}}else {error=diagnostic(writer,path,"parse-project",item.codeName(),item.span.start,item.span.end,item.message());}if error!=blot_error::Error.none {return false,error;}}
 stats.load_us=elapsed(started);if loaded.diagnostics.len!=0 {return false,blot_error::Error.none;}if command==Command.parse_project {return true,blot_error::Error.none;}
 let check_start=now();var executor=blot_reuse_project_check::Workers{..};var checked,error=blot_reuse_project_check::checkProject(executor,loaded);if error!=blot_error::Error.none {return false,error;}var checked_live=true;
 let accepted,error=projectChecked(writer,command,filename,output,policy,check_start,stats,loaded,checked,checked_live);if checked_live {let release_start=now();checked.deinit();stats.teardown_us+=elapsed(release_start);}return accepted,error;
}
fn projectChecked(writer:blot_io::Writer,command:Command,filename:const u8[:],output:Text,policy:Policy,check_start:u64,stats:ProjectStats&,loaded:Project&,checked:CheckedProject&,checked_live:bool&)->bool,Error {
 stats.body_elaborations=checked.body_elaborations;stats.imported_schemes=checked.imported_schemes;for item in checked.modules {if !item.present {continue;}let types=item.value.checked.types;stats.type_nodes+=types.nodes.len;stats.type_versions+=types.versions.len;stats.check_occurs_steps+=types.occurs_steps;stats.row_versions+=types.effects.versions.len;stats.effect_rows+=types.effects.rows.len;stats.checker.add(item.value.checked.counters);}
 let error=projectDiagnostics(writer,filename,loaded,checked);if error!=blot_error::Error.none {return false,error;}stats.check_us=elapsed(check_start);if checked.diagnostics.len!=0 {return false,blot_error::Error.none;}if command==Command.check_project {return true,blot_error::Error.none;}
 let lower_start=now();var catalog,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {return false,error;}let units,error=catalog.alloc<Core>(loaded.units.len);if error!=blot_error::Error.none {catalog.deinit();return false,error;}
 var unit_owners:InputOwner[>..<]=[];let accepted,error=projectLowered(writer,filename,output,lower_start,stats,loaded,checked,checked_live,units,unit_owners);
 let release_start=now();for &owner in unit_owners {owner.release();}catalog.deinit();stats.teardown_us+=elapsed(release_start);return accepted,error;
}
fn projectLowered(writer:blot_io::Writer,filename:const u8[:],output:Text,lower_start:u64,stats:ProjectStats&,loaded:Project&,checked:CheckedProject&,checked_live:bool&,units:Core[:],unit_owners:InputOwner[>..<]&)->bool,Error {
 for unit,index in loaded.units.items {let id=(index+1) as u32;let lowering=blot_phase_profile::enter(blot_phase_profile::Phase.lower);let owned,error=blot_check_core_builder::lowerWithOrigins(unit.tree,loaded.symbols,checked.module(id).checked,blot_reuse_project_check::moduleOrigins(loaded));lowering.exit();if error!=blot_error::Error.none {return false,error;}
  var lowered=owned;lowered.value.unit=id;units[index]=lowered.value;unit_owners.push(lowered.owner);stats.core_nodes+=units[index].nodes.len-1;stats.body_lowerings+=units[index].body_lowerings;
  for item in units[index].diagnostics {let error=diagnostic(writer,loaded.filename(id),"lower",enumName(item.code),item.span.start,item.span.end,item.message());if error!=blot_error::Error.none {return false,error;}}
  stats.lower_us=elapsed(lower_start);if units[index].diagnostics.len!=0 {return false,blot_error::Error.none;}}
 // Paths and the tiny import catalog remain for diagnostics; source, syntax
 // and mutable inference state cannot be consulted by emission.
 let release_start=now();checked.deinit();checked_live=false;for &unit in loaded.units.items {unit.tree.deinit();blot_reuse_project::releaseSource(unit.source);unit.source=default<const u8[:]>();}stats.teardown_us+=elapsed(release_start);
 // The backend's result is an owner of its own, requested in its phase.
 let emit_start=now();let backend=blot_phase_profile::enter(blot_phase_profile::Phase.backend);let compiled,error=blot_reuse_dependency_consumer::compileUnits(units,loaded.entry);backend.exit();if error!=blot_error::Error.none {return false,error;}stats.emitted_functions=compiled.emitted_functions;
 if compiled.failed {let error=diagnostic(writer,loaded.filename(compiled.diagnostic.unit),"emit",enumName(compiled.diagnostic.code),compiled.diagnostic.span.start,compiled.diagnostic.span.end,compiled.text());stats.emit_us=elapsed(emit_start);blot_reuse_dependency_consumer::freeBytes(compiled.message);return false,error;}
 stats.wasm_bytes=compiled.bytes.len;stats.emit_us=elapsed(emit_start);let write_start=now();assert(output.present);let error=blot_io::write_file(output.value,compiled.bytes);blot_reuse_dependency_consumer::freeBytes(compiled.bytes);if error!=blot_error::Error.none {return false,error;}stats.write_us=elapsed(write_start);return true,blot_error::Error.none;
}
