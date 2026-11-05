// Frontend, lowering, cache admission and emission retain exact owned inputs.
namespace blot_cli;
import .cli;
import .cli_diagnostics;
import .project_executor;
import .compile_workspace;
import parse.lexer;
import parse.parser;
import parse.ast;
import parse.symbols;
import parse.syntax_diagnostics;
import check.check;
import check.core;
import check.core_builder;
import check.parallel_lowering;
import check.diagnostic_location;
import backend.core_backend;
import backend.backend_timing;
import backend.function_facts;
import backend.optimized_bodies;
import backend.array_cost_explanation;
import backend.runtime_identity;
import backend.backend_checkpoint;
import reuse.project;
import reuse.project_check;
import reuse.restart_cache;
import reuse.artifact_capture;
import reuse.dependency_payload;
import reuse.principal_evidence_reuse;
import eval.completed_specialization_query;
import runtime.memory;
import work_counters;
import phase_profile;
import support.error;
import support.option;
import support.native;
import support.io;
import support.blake3;
import main;
import compiler_defaults;
type Core=blot_check_core::Module;
type InputOwner=blot_reuse_dependency_payload::Owner;
type OwnedCore=blot_reuse_dependency_payload::Owned<Core>;
type Identity=blot_backend_runtime_identity::Metadata;
struct CacheMetrics {loaded:bool=false,saved:bool=false,bytes:i64=0,over_limit:bool=false,semantic_over_limit:bool=false}
fn record(self:CacheMetrics&,saved:bool,report:blot_reuse_restart_cache::Report) {self.saved=saved;self.bytes=report.checkpoint_bytes;self.over_limit=report.over_limit;self.semantic_over_limit=report.semantic_over_limit;}
struct Stats {
 backend_timing:blot_backend_backend_timing::Stats=blot_backend_backend_timing::Stats{..},
 work_counters:blot_work_counters::Counters=blot_work_counters::Counters{..},
 optimization:blot_backend_function_facts::Stats=blot_backend_function_facts::Stats{..},
 runtime_optimization:blot_backend_optimized_bodies::Stats=blot_backend_optimized_bodies::Stats{..},
 principals:blot_reuse_principal_evidence_reuse::Stats=blot_reuse_principal_evidence_reuse::Stats{..},
 restart_cache:CacheMetrics=CacheMetrics{..},
 source_bytes:i64=0,
 tokens:i64=0,
 syntax_nodes:i64=0,
 syntax_extra_words:i64=0,
 symbols:i64=0,
 symbol_bytes:i64=0,
 type_nodes:i64=0,
 type_versions:i64=0,
 bindings:i64=0,
 body_elaborations:i64=0,
 wasm_bytes:i64=0,
 code_instances:i64=0,
 callable_wrappers:i64=0,
 emitted_functions:i64=0,
 core_nodes:i64=0,
 body_lowerings:i64=0,
 constant_steps:i64=0,
 lex_us:i64=0,
 parse_us:i64=0,
 check_us:i64=0,
 lower_us:i64=0,
 emit_us:i64=0,
 checker:blot_check_check::Counters=blot_check_check::Counters{..},
}
var compiler_allocation_owner:u64=0;
fn allocationOwner()->u64 {if compiler_allocation_owner==0 {compiler_allocation_owner=blot_native::fresh_owner_id();}return compiler_allocation_owner;}
fn now()->u64 {return blot_native::clock_ns();}
fn elapsed(start:u64)->i64 {let ended=now();if ended<start {return 0;}return ((ended-start)/1000) as i64;}
struct SimpleRecord {kind:const u8[:]="compilation",filename:const u8[:],stage:const u8[:],success:bool,total_us:i64,stats:Stats,memory:blot_runtime_memory::Counts=blot_runtime_memory::Counts{..},memory_scope:const u8[:]="Requested bytes for source and compiler-owned buffers; excludes allocator overhead and process RSS. All owners released before this record."}
fn process(writer:blot_io::Writer,command:Command,filename:const u8[:],output:Text,cache_root:Text)->bool,Error {var stats=Stats{..};let started=now();let accepted,error=processSingle(writer,command,filename,output,cache_root,stats);if error!=Error.none {return false,error;}let written=emit(writer,SimpleRecord{filename:filename,stage:commandName(command),success:accepted,total_us:elapsed(started),stats:stats,..});return accepted,written;}
fn processSingle(writer:blot_io::Writer,command:Command,filename:const u8[:],output:Text,cache_root:Text,stats:Stats&)->bool,Error {
 var input=blot_reuse_project::FileInputs{..};var source:u8[>..<]=[];let read=input.read(filename,33554432,source);if read!=Error.none {return false,read;}stats.source_bytes=source.len;
 var names,error=blot_parse_symbols::initPooled();if error!=Error.none {return false,error;}var names_live=true;defer {if names_live {names.deinit();}}
 var tokens:blot_parse_token::Token[>..<]=[];var comments:blot_parse_token::Token[>..<]=[];var diagnostics:blot_parse_lexer::Diagnostic[>..<]=[];var lexed=blot_parse_lexer::init(tokens,comments,diagnostics);let lex_start=now();let error=blot_parse_lexer::lex(source[:],lexed);if error!=Error.none {return false,error;}stats.lex_us=elapsed(lex_start);stats.tokens=tokens.len;
 if diagnostics.len!=0 {let error=frontendDiagnostic(writer,filename,"lex",source[:],blot_parse_syntax_diagnostics::lexical(tokens[:],diagnostics[0]),diagnostics[:]);return false,error;}if command==Command.lex {return true,Error.none;}
 var tree,error=blot_parse_ast::initPooled();if error!=Error.none {return false,error;}var tree_live=true;defer {if tree_live {tree.deinit();}}let parse_start=now();let error=blot_parse_parser::parse(source[:],tokens[:],names,tree);if error!=Error.none {return false,error;}
 if tree.diagnostics.len!=0 {let publication,error=blot_parse_syntax_diagnostics::parse(tokens[:],tree.diagnostics.items[0]);if error!=Error.none {return false,error;}let error=frontendDiagnostic(writer,filename,"parse",source[:],publication,tree.diagnostics.items);if error!=Error.none {return false,error;}}
 stats.parse_us=elapsed(parse_start);stats.syntax_nodes=tree.nodes.len-1;stats.syntax_extra_words=tree.extra.len;stats.symbols=names.entries.len;stats.symbol_bytes=names.bytes.len;if tree.diagnostics.len!=0 {return false,Error.none;}if command==Command.parse {return true,Error.none;}
 let check_start=now();var checked,error=blot_check_check::check(tree,names);if error!=Error.none {return false,error;}var checked_live=true;defer {if checked_live {checked.deinit();}}stats.check_us=elapsed(check_start);stats.type_nodes=checked.types.nodes.len;stats.type_versions=checked.types.versions.len;stats.bindings=checked.bindings.len-1;stats.body_elaborations=checked.body_elaborations;stats.checker=checked.counters;
 if checked.diagnostics.len!=0 {let error=checkDiagnostics(writer,filename,source[:],names,checked.diagnostics);return false,error;}if command==Command.check {return true,Error.none;}
 let lower_start=now();var lowered,error=blot_check_core_builder::lower(tree,names,checked);if error!=Error.none {return false,error;}defer {lowered.deinit();}lowered.value.unit=1;stats.lower_us=elapsed(lower_start);stats.core_nodes=lowered.value.nodes.len-1;stats.body_lowerings=lowered.value.body_lowerings;for item in lowered.value.diagnostics {let error=diagnostic(writer,filename,"lower",enumName(item.code),item.span.start,item.span.end,item.message());if error!=Error.none {return false,error;}}if lowered.value.diagnostics.len!=0 {return false,Error.none;}
 var identity=blot_support::none<Identity>();defer {if identity.present {identity.value.deinit();}}var cache=blot_support::none<blot_reuse_restart_cache::File>();defer {if cache.present {cache.value.deinit();}}
 if cache_root.present {var absolute:u8[>..<]=[];let path_error=input.canonical(filename,absolute);if path_error==Error.none {let names_owner,error=blot_backend_runtime_identity::capture(names,[blot_backend_runtime_identity::Owner{1,absolute[:]}],1);if error==Error.none {identity=blot_support::some(names_owner);let file,error=blot_reuse_restart_cache::init(cache_root.value,blot_main::configured_identity,absolute[:]);if error==Error.none {cache=blot_support::some(file);}}}}
 var factory=blot_reuse_artifact_capture::Factory{allocationOwner()};var checkpoint=blot_support::none<blot_backend_backend_checkpoint::Checkpoint>();if cache.present {checkpoint=cache.value.load(factory);}defer {if checkpoint.present {checkpoint.value.deinit();}}stats.restart_cache.loaded=checkpoint.present;
 // No mutable source/checker state remains observable during backend emission.
 checked.deinit();checked_live=false;tree.deinit();tree_live=false;names.deinit();names_live=false;source.clear();tokens.clear();comments.clear();diagnostics.clear();
 var catalog,error=blot_reuse_dependency_payload::init();if error!=Error.none {return false,error;}defer {catalog.deinit();}let units,error=catalog.alloc<Core>(1);if error!=Error.none {return false,error;}units[0]=lowered.value;
 var frame,error=blot_compile_workspace::create(allocationOwner());if error!=Error.none {return false,error;}defer {let released=frame.release();assert(released==Error.none);}let workspace=frame.borrow();assert(workspace);let pinned=blot_backend_core_backend::pinWorkspaceInputs(workspace,units,catalog,[lowered.owner],[]);if pinned!=Error.none {return false,pinned;}
 var options=blot_backend_core_backend::CompileOptions{diagnostic_source_mode:true,retain_artifacts:cache.present,artifact_replay:blot_compiler_defaults::artifact_replay,artifact_dump:blot_compiler_defaults::artifact_replay,..};if identity.present {options.identity=blot_support::some(identity.value.view());}if checkpoint.present {options.checkpoint .= checkpoint.value;}
 let emit_start=now();var compiled,error=blot_backend_core_backend::compileWithOptions(workspace,units,1,options);if error!=Error.none {return false,error;}defer {compiled.deinit();}let pinned=blot_backend_core_backend::pinResult(compiled,catalog,[lowered.owner],[]);if pinned!=Error.none {return false,pinned;}stats.emit_us=elapsed(emit_start);stats.code_instances=compiled.code_instances;stats.optimization=compiled.optimization;stats.runtime_optimization=compiled.runtime_optimization;stats.backend_timing=compiled.timing;stats.work_counters=compiled.counters;stats.callable_wrappers=compiled.callable_wrappers;stats.emitted_functions=compiled.emitted_functions;stats.constant_steps=compiled.constant_steps;stats.principals=compiled.principal;
 if compiled.diagnostic.present {let item=compiled.diagnostic.value;var origins:blot_check_diagnostic_location::Origin[>..<]=[];for origin in item.origins.items() {origins.push(blot_check_diagnostic_location::init(origin.kind,filename,origin.location.span));}let error=emitDiagnostic(writer,filename,filename,item,compiled.explanation,origins[:]);return false,error;}
 stats.wasm_bytes=compiled.bytes.len;assert(output.present);let error=blot_io::write_file(output.value,compiled.bytes.items);if error!=Error.none {return false,error;}if cache.present&&compiled.capture {var report=blot_reuse_restart_cache::Report{..};stats.restart_cache.record(cache.value.capture(compiled.capture,report),report);}return true,Error.none;
}

struct ProjectStats {
 kind:const u8[:]="compilation",
 filename:const u8[:]=[],
 stage:const u8[:]=[],
 success:bool=false,
 total_us:i64=0,
 source_bytes:i64=0,
 files:i64=0,
 syntax_nodes:i64=0,
 symbol_bytes:i64=0,
 type_nodes:i64=0,
 type_versions:i64=0,
 row_versions:i64=0,
 effect_rows:i64=0,
 body_elaborations:i64=0,
 imported_schemes:i64=0,
 core_nodes:i64=0,
 body_lowerings:i64=0,
 code_instances:i64=0,
 callable_wrappers:i64=0,
 emitted_functions:i64=0,
 wasm_bytes:i64=0,
 constant_steps:i64=0,
 load_us:i64=0,
 check_us:i64=0,
 lower_us:i64=0,
 emit_us:i64=0,
 write_us:i64=0,
 teardown_us:i64=0,
 check_occurs_steps:u64=0,
 checker:blot_check_check::Counters=blot_check_check::Counters{..},
 optimization:blot_backend_function_facts::Stats=blot_backend_function_facts::Stats{..},
 runtime_optimization:blot_backend_optimized_bodies::Stats=blot_backend_optimized_bodies::Stats{..},
 backend_timing:blot_backend_backend_timing::Stats=blot_backend_backend_timing::Stats{..},
 work_counters:blot_work_counters::Counters=blot_work_counters::Counters{..},
 principals:blot_reuse_principal_evidence_reuse::Stats=blot_reuse_principal_evidence_reuse::Stats{..},
 selected_queries:blot_eval_completed_specialization_query::Stats=blot_eval_completed_specialization_query::Stats{..},
 restart_cache:CacheMetrics=CacheMetrics{..},
 phase_profile:blot_phase_profile::Record=blot_phase_profile::Record{..},
 memory:blot_runtime_memory::Counts=blot_runtime_memory::Counts{..},
 memory_scope:const u8[:]="Requested bytes for project source, syntax, symbols, typed core and compiler scratch; excludes allocator overhead and process RSS. All owners released before this record.",
}
fn processProject<E>(executor:E&,writer:blot_io::Writer,command:Command,filename:const u8[:],options:Options,profile_requested:bool,explain_allocations:bool,output:Text,cache_root:Text,policy:Policy)->bool,Error {
 var profile=blot_support::none<blot_phase_profile::Profile>();var installation=blot_support::none<blot_phase_profile::Installation>();if profile_requested {profile=blot_support::some(blot_phase_profile::initProfile());installation=blot_support::some(blot_phase_profile::install(profile.value));}defer {if installation.present {installation.value.restore();}if profile.present {profile.value.deinit();}}
 let started=now();var stats=ProjectStats{filename:filename,stage:commandName(command),..};let accepted,error=processProjectWork(executor,writer,command,filename,options,profile_requested,explain_allocations,output,cache_root,policy,started,stats);if error!=Error.none {return false,error;}stats.success=accepted;stats.total_us=elapsed(started);if profile.present {stats.phase_profile=profile.value.record();}let error=emit(writer,stats);return accepted,error;
}
fn processProjectWork<E>(executor:E&,writer:blot_io::Writer,command:Command,filename:const u8[:],options:Options,profile_requested:bool,explain_allocations:bool,output:Text,cache_root:Text,policy:Policy,started:u64,stats:ProjectStats&)->bool,Error {
 var loaded,error=blot_reuse_project::load(filename,options);if error!=Error.none {return false,error;}loaded.checking=blot_reuse_project::Lowering{io:true,workers:policy.frontend_workers};defer {let release_start=now();loaded.deinit();stats.teardown_us+=elapsed(release_start);}
 stats.source_bytes=loaded.source_bytes;stats.files=loaded.units.len;stats.symbol_bytes=loaded.symbols.bytes.len;for unit in loaded.units.items {if unit.tree.nodes.len!=0 {stats.syntax_nodes+=unit.tree.nodes.len-1;}}
 for item in loaded.diagnostics.items {var path=filename;if item.unit!=0 {path=loaded.filename(item.unit);}var error=Error.none;if item.publication.present {let unit .= loaded.unit(item.unit);if item.parse_code.present {error=frontendDiagnostic(writer,path,"parse-project",unit.source,item.publication.value,unit.tree.diagnostics.items);}else {error=frontendDiagnostic(writer,path,"parse-project",unit.source,item.publication.value,item.lexical_details);}}else {error=diagnostic(writer,path,"parse-project",item.codeName(),item.span.start,item.span.end,item.message());}if error!=Error.none {return false,error;}}
 stats.load_us=elapsed(started);if loaded.diagnostics.len!=0 {return false,Error.none;}if command==Command.parse_project {return true,Error.none;}
 let check_start=now();var checked,error=blot_reuse_project_check::checkProject(executor,loaded);if error!=Error.none {return false,error;}var checked_live=true;defer {if checked_live {let release_start=now();checked.deinit();stats.teardown_us+=elapsed(release_start);}}
 stats.body_elaborations=checked.body_elaborations;stats.imported_schemes=checked.imported_schemes;for item in checked.modules {if !item.present {continue;}let types=item.value.checked.types;stats.type_nodes+=types.nodes.len;stats.type_versions+=types.versions.len;stats.check_occurs_steps+=types.occurs_steps;stats.row_versions+=types.effects.versions.len;stats.effect_rows+=types.effects.rows.len;stats.checker.add(item.value.checked.counters);}
 let error=projectDiagnostics(writer,filename,loaded,checked);if error!=Error.none {return false,error;}stats.check_us=elapsed(check_start);if checked.diagnostics.len!=0 {return false,Error.none;}if command==Command.check_project {return true,Error.none;}
 let lower_start=now();var catalog,error=blot_reuse_dependency_payload::init();if error!=Error.none {return false,error;}defer {let release_start=now();catalog.deinit();stats.teardown_us+=elapsed(release_start);}let units,error=catalog.alloc<Core>(loaded.units.len);if error!=Error.none {return false,error;}var unit_owners:InputOwner[>..<]=[];defer {let release_start=now();for &owner in unit_owners {owner.release();}stats.teardown_us+=elapsed(release_start);}
 var inputs:blot_support::Option<blot_check_parallel_lowering::Input>[>..<]=[];var slots:blot_check_parallel_lowering::Slot[>..<]=[];var lowered=blot_support::none<blot_check_parallel_lowering::Batch<E>>();defer {if lowered.present {lowered.value.deinit();}}
 if policy.semantic_workers>1 {for unit,index in loaded.units.items {inputs.push(blot_support::some(blot_check_parallel_lowering::Input{unit.tree,checked.module((index+1) as u32).checked}));}let lowering=blot_phase_profile::enter(blot_phase_profile::Phase.lower);let batch,error=blot_check_parallel_lowering::run(executor,true,policy.semantic_workers,loaded.symbols,blot_reuse_project_check::moduleOrigins(loaded),inputs[:],slots);lowering.exit();if error!=Error.none {return false,error;}lowered=batch;}
 for unit,index in loaded.units.items {let id=(index+1) as u32;let lowering=blot_phase_profile::enter(blot_phase_profile::Phase.lower);var owned=default<OwnedCore>();var error=Error.none;if lowered.present {let value,failure=lowered.value.take(index);owned=value;error=failure;}else {let value,failure=blot_check_core_builder::lowerWithOrigins(unit.tree,loaded.symbols,checked.module(id).checked,blot_reuse_project_check::moduleOrigins(loaded));owned=value;error=failure;}lowering.exit();if error!=Error.none {return false,error;}owned.value.unit=id;units[index]=owned.value;unit_owners.push(owned.owner);stats.core_nodes+=units[index].nodes.len-1;stats.body_lowerings+=units[index].body_lowerings;for item in units[index].diagnostics {let error=diagnostic(writer,loaded.filename(id),"lower",enumName(item.code),item.span.start,item.span.end,item.message());if error!=Error.none {return false,error;}}stats.lower_us=elapsed(lower_start);if units[index].diagnostics.len!=0 {return false,Error.none;}}
 var identity_owners:blot_backend_runtime_identity::Owner[>..<]=[];for index in units.len {identity_owners.push(blot_backend_runtime_identity::Owner{(index+1) as u32,loaded.filename((index+1) as u32)});}var identity,error=blot_backend_runtime_identity::capture(loaded.symbols,identity_owners[:],units.len);if error!=Error.none {return false,error;}defer {identity.deinit();}
 var source_digests:u8[32][>..<]=[];if policy.memory_profile||policy.require_collector_free {for index in units.len {source_digests.push(blot_support_blake3::hash(loaded.unit((index+1) as u32).source));}}
 let release_start=now();checked.deinit();checked_live=false;for &unit in loaded.units.items {unit.tree.deinit();blot_reuse_project::releaseSource(unit.source);unit.source=[];}stats.teardown_us+=elapsed(release_start);
 let emit_start=now();var cache=blot_support::none<blot_reuse_restart_cache::File>();if cache_root.present {let file,error=blot_reuse_restart_cache::init(cache_root.value,blot_main::configured_identity,loaded.filename(loaded.entry));if error==Error.none {cache=blot_support::some(file);}}defer {if cache.present {cache.value.deinit();}}var factory=blot_reuse_artifact_capture::Factory{allocationOwner()};var checkpoint=blot_support::none<blot_backend_backend_checkpoint::Checkpoint>();if cache.present {checkpoint=cache.value.load(factory);}defer {if checkpoint.present {checkpoint.value.deinit();}}stats.restart_cache.loaded=checkpoint.present;
 var frame,error=blot_compile_workspace::create(allocationOwner());if error!=Error.none {return false,error;}defer {let released=frame.release();assert(released==Error.none);}let workspace=frame.borrow();assert(workspace);let pinned=blot_backend_core_backend::pinWorkspaceInputs(workspace,units,catalog,unit_owners[:],[]);if pinned!=Error.none {return false,pinned;}
 var compile_options=blot_backend_core_backend::CompileOptions{compiler_identity:blot_main::configured_identity,diagnostic_source_digests:source_digests[:],io:true,policy:policy,profile_backend:profile_requested,explain_allocations:explain_allocations,identity:blot_support::some(identity.view()),unit_order:loaded.order.items,diagnostic_source_mode:loaded.input_mode==blot_reuse_project::InputMode.source,diagnostic_prelude_unit:loaded.prelude_unit,retain_artifacts:cache.present,..};if checkpoint.present {compile_options.checkpoint .= checkpoint.value;}
 let backend=blot_phase_profile::enter(blot_phase_profile::Phase.backend);var compiled,error=blot_backend_core_backend::compileWithOptions(workspace,units,loaded.entry,compile_options);backend.exit();if error!=Error.none {return false,error;}defer {let release_start=now();compiled.deinit();stats.teardown_us+=elapsed(release_start);}let pinned=blot_backend_core_backend::pinResult(compiled,catalog,unit_owners[:],[]);if pinned!=Error.none {return false,pinned;}
 stats.code_instances=compiled.code_instances;stats.optimization=compiled.optimization;stats.runtime_optimization=compiled.runtime_optimization;stats.backend_timing=compiled.timing;stats.work_counters=compiled.counters;stats.callable_wrappers=compiled.callable_wrappers;stats.emitted_functions=compiled.emitted_functions;stats.constant_steps=compiled.constant_steps;stats.principals=compiled.principal;stats.selected_queries=compiled.completed_queries;
 if compiled.diagnostic.present {let item=compiled.diagnostic.value;var origins:blot_check_diagnostic_location::Origin[>..<]=[];for origin in item.origins.items() {origins.push(blot_check_diagnostic_location::init(origin.kind,loaded.filename(origin.location.unit),origin.location.span));}var related:const u8[:]=[];if item.related.present {related=loaded.filename(item.related.value.unit);}let error=emitDiagnostic(writer,loaded.filename(item.unit),related,item,compiled.explanation,origins[:]);stats.emit_us=elapsed(emit_start);return false,error;}
 if compiled.allocation_emission {let snapshot=compiled.allocation_emission;let error=emit(writer,AllocationSites{sites:snapshot.sites,omitted:snapshot.omitted,..});if error!=Error.none {return false,error;}}
 if explain_allocations {var paths:(const u8[:])[>..<]=[];for index in units.len {paths.push(loaded.filename((index+1) as u32));}var costs,error=blot_backend_array_cost_explanation::analyze(units,paths[:],loaded.entry,loaded.prelude_unit);if error!=Error.none {return false,error;}let error=emit(writer,ArrayCosts{sites:costs.sites,omitted:costs.omitted,..});costs.deinit();if error!=Error.none {return false,error;}}
 stats.wasm_bytes=compiled.bytes.len;stats.emit_us=elapsed(emit_start);let write_start=now();assert(output.present);let error=blot_io::write_file(output.value,compiled.bytes.items);if error!=Error.none {return false,error;}if cache.present&&compiled.capture {var report=blot_reuse_restart_cache::Report{..};stats.restart_cache.record(cache.value.capture(compiled.capture,report),report);}stats.write_us=elapsed(write_start);return true,Error.none;
}
struct AllocationSites {kind:const u8[:]="allocation_sites",sites:const blot_backend_allocation_emission::Site[:],omitted:i64}
struct ArrayCosts {kind:const u8[:]="array_costs",sites:const blot_backend_array_cost_explanation::Site[:],omitted:i64}
