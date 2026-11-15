// `blotc migrate-stores`: turns each `:=` that the uniqueness analysis
// rejects (`aliased_update`) into the store `=`. A `:=` through storage
// already writes in place, so the rewrite keeps each program's meaning; it
// changes only the `:=` token. Every pass loads, checks and lowers each
// entry and rewrites the rejected sites, and passes repeat until none is
// rejected. Only files under the write root change, and std only on request.
namespace blot_cli;
import .cli;
import .cli_diagnostics;
import .cli_project;
import std;
import json;
import main;
import reuse.project;
import reuse.project_check;
import reuse.project_check_serial;
import reuse.revision_inputs;
import reuse.source_overlays;
import backend.native_assets;
import check.core;
import check.core_builder;
import support.error;
import support.option;
import support.native;
import support.io;
import support.path;
struct MigrationSettings {options:Options=Options{..},assets:blot_support::Option<blot_backend_native_assets::Options> =blot_support::none<blot_backend_native_assets::Options>(),inference_budget:blot_support::Option<u64> =blot_support::none<u64>()}
// `write_root` is absolute; only files below it are rewritten. A dry run
// reports the sites of one pass without writing them.
struct MigrationRequest {entries:const (const u8[:])[:],settings:MigrationSettings,write_root:const u8[:],include_std:bool=false,dry_run:bool=false}
let maximum_migration_passes:i64=16;
struct MigrationOutcome {rewritten:i64=0,blocked:i64=0,failed:bool=false}
struct MigrationSite {unit:u32,start:u32}
struct MigrationSummary {kind:const u8[:]="migrate-stores",success:bool,passes:i64,rewritten:i64,outside:i64}
struct MigrationReport {kind:const u8[:],filename:const u8[:],start:u32,line:i64,column:i64}
fn migrate(writer:blot_io::Writer,request:MigrationRequest)->bool,Error {
 var rewritten:i64=0;var passes:i64=0;
 while passes<maximum_migration_passes {
  passes+=1;var pass=MigrationOutcome{..};
  for entry in request.entries {
   let outcome,error=migrateEntry(writer,request,entry);if error!=blot_error::Error.none {return false,error;}
   if outcome.failed {let error=emit(writer,MigrationSummary{success:false,passes:passes,rewritten:rewritten+pass.rewritten,outside:pass.blocked,..});return false,error;}
   pass.rewritten+=outcome.rewritten;pass.blocked+=outcome.blocked;
  }
  rewritten+=pass.rewritten;
  if pass.rewritten==0 || request.dry_run {let accepted=pass.blocked==0 || request.dry_run;let error=emit(writer,MigrationSummary{success:accepted,passes:passes,rewritten:rewritten,outside:pass.blocked,..});return accepted,error;}
 }
 let error=emit(writer,MigrationSummary{success:false,passes:passes,rewritten:rewritten,outside:0,..});return false,error;
}
fn migrateEntry(writer:blot_io::Writer,request:MigrationRequest,entry:const u8[:])->MigrationOutcome,Error {
 if !request.settings.assets.present {var empty:blot_reuse_source_overlays::Source[>..]=[];return migrateSources(writer,request,entry,empty[..]);}
 var session,error=blot_backend_native_assets::init(request.settings.assets.value);if error!=blot_error::Error.none {return MigrationOutcome{..},error;}
 let candidate,error=session.prepare(entry,[],[]);if error!=blot_error::Error.none {session.deinit();return MigrationOutcome{..},error;}assert(candidate);
 var outcome=MigrationOutcome{failed:true,..};var failure=blot_error::Error.none;
 if candidate.issue.present {let found=candidate.issue.value;failure=diagnostic(writer,found.filename,"assets",found.code,found.start,found.end,found.message);}
 else {let migrated,error=migrateSources(writer,request,entry,candidate.sources.items);outcome=migrated;failure=error;}
 candidate.deinit();session.deinit();return outcome,failure;
}
fn migrateSources(writer:blot_io::Writer,request:MigrationRequest,entry:const u8[:],sources:const blot_reuse_source_overlays::Source[:])->MigrationOutcome,Error {
 var snapshot,error=blot_reuse_revision_inputs::initWithSources(request.settings.options,sources);if error!=blot_error::Error.none {return MigrationOutcome{..},error;}
 var provider=snapshot.provider();var loaded,error=blot_reuse_project::loadWithInputs(entry,request.settings.options,provider);if error!=blot_error::Error.none {snapshot.deinit();return MigrationOutcome{..},error;}
 let outcome,error=migrateLoaded(writer,request,entry,loaded);loaded.deinit();snapshot.deinit();return outcome,error;
}
fn migrateLoaded(writer:blot_io::Writer,request:MigrationRequest,entry:const u8[:],loaded:Project&)->MigrationOutcome,Error {
 if loaded.diagnostics.len!=0 {
  for item in loaded.diagnostics.items {let path=if item.unit!=0 {loaded.filename(item.unit)}else {entry};let error=diagnostic(writer,path,"parse-project",item.codeName(),item.span.start,item.span.end,item.message());if error!=blot_error::Error.none {return MigrationOutcome{..},error;}}
  return MigrationOutcome{failed:true,..},blot_error::Error.none;
 }
 loaded.checking=blot_reuse_project::Lowering{io:true,workers:1};var executor=blot_reuse_project_check::SerialChecks{..};var checked,error=blot_reuse_project_check::checkProject(executor,loaded);if error!=blot_error::Error.none {return MigrationOutcome{..},error;}
 let outcome,error=migrateChecked(writer,request,entry,loaded,checked);checked.deinit();return outcome,error;
}
fn migrateChecked(writer:blot_io::Writer,request:MigrationRequest,entry:const u8[:],loaded:Project&,checked:CheckedProject&)->MigrationOutcome,Error {
 if checked.diagnostics.len!=0 {
  for item in checked.diagnostics {let path=if item.unit!=0 {loaded.filename(item.unit)}else {entry};let error=diagnostic(writer,path,"check-project",item.codeName(),item.span.start,item.span.end,item.message());if error!=blot_error::Error.none {return MigrationOutcome{..},error;}}
  return MigrationOutcome{failed:true,..},blot_error::Error.none;
 }
 var sites:MigrationSite[>..]=[];
 for unit,index in loaded.units.items {
  let id=(index+1) as u32;let owned,error=blot_check_core_builder::lowerWithOrigins(unit.tree,loaded.symbols,checked.module(id).checked,blot_reuse_project_check::moduleOrigins(loaded));if error!=blot_error::Error.none {return MigrationOutcome{..},error;}var lowered=owned;
  for item in lowered.value.diagnostics {
   if item.code!=blot_check_core::Code.aliased_update {let error=diagnostic(writer,loaded.filename(id),"lower",enumName(item.code),item.span.start,item.span.end,item.message());lowered.deinit();if error!=blot_error::Error.none {return MigrationOutcome{..},error;}return MigrationOutcome{failed:true,..},blot_error::Error.none;}
   sites.push(MigrationSite{id,item.span.start});
  }
  lowered.deinit();
 }
 var outcome=MigrationOutcome{..};var at:i64=0;
 while at<sites.len {
  let unit=sites[at].unit;var end=at;while end<sites.len && sites[end].unit==unit {end++;}let group=sites[at..end];at=end;let path=loaded.filename(unit);let source=loaded.unit(unit).source;
  let allowed,error=writable(request,path);if error!=blot_error::Error.none {return MigrationOutcome{..},error;}
  if !allowed {for site in group {let error=reportSite(writer,"outside",path,source,site.start);if error!=blot_error::Error.none {return MigrationOutcome{..},error;}}outcome.blocked+=group.len;continue;}
  var rewritten:u8[>..]=[];rewritten.append(source);
  // Later sites first, so earlier offsets stay valid as colons are dropped.
  for index in 1..group.len {var slot=index;while slot>0 && group[slot-1].start<group[slot].start {let moved=group[slot];group[slot]=group[slot-1];group[slot-1]=moved;slot--;}}
  var length=rewritten.len;var previous:i64=-1;
  for site in group {
   if previous==site.start as i64 {continue;}previous=site.start as i64;
   let operator=rebindOperator(rewritten[..length],site.start);
   if operator<0 {let error=diagnostic(writer,path,"migrate-stores","missing_rebind_operator",site.start,site.start,"No := follows this rejected update's place");if error!=blot_error::Error.none {return MigrationOutcome{..},error;}return MigrationOutcome{failed:true,..},blot_error::Error.none;}
   let error=reportSite(writer,"store",path,source,site.start);if error!=blot_error::Error.none {return MigrationOutcome{..},error;}
   // `:=` becomes `=`: drop the colon.
   for index in operator..length-1 {rewritten[index]=rewritten[index+1];}length-=1;outcome.rewritten+=1;
  }
  if !request.dry_run {let error=blot_io::write_file(path,rewritten[..length]);if error!=blot_error::Error.none {return MigrationOutcome{..},error;}}
 }
 return outcome,blot_error::Error.none;
}
// The offset of the `:=` after the place that starts at `start`: the first
// one outside brackets and string literals. Negative when there is none.
fn rebindOperator(source:const u8[:],start:u32)->i64 {
 var nesting:i64=0;var at:i64=start as i64;
 while at+1<source.len {
  let byte=source[at];
  if byte=='(' || byte=='[' || byte=='{' {nesting+=1;}
  else if byte==')' || byte==']' || byte=='}' {if nesting>0 {nesting-=1;}}
  else if byte=='"' {at+=1;while at<source.len && source[at]!='"' {if source[at]=='\\' {at+=1;}at+=1;}}
  else if byte=='\n' {if nesting==0 {return -1;}}
  else if byte==':' {if nesting==0 && source[at+1]=='=' {return at;}}
  at+=1;
 }
 return -1;
}
// The path with every symbolic link resolved; false when it does not name a file.
fn realPath(path:const u8[:],out:u8[>..]&)->bool {
 for byte in path {if byte==0 {return false;}}var terminated:u8[>..]=[];terminated.append(path);terminated.push(0);var buffer:u8[4096];let length=blot_native::real_path(terminated[0],buffer[0],4096);if length<0 || length>=4096 {return false;}out.append(buffer[..length]);return true;
}
fn writable(request:MigrationRequest,path:const u8[:])->bool,Error {
 var real:u8[>..]=[];if !realPath(path,real) {return false,blot_error::Error.none;}if !under(real[..],request.write_root) {return false,blot_error::Error.none;}if request.include_std {return true,blot_error::Error.none;}
 if !request.settings.options.std_root.present {return true,blot_error::Error.none;}var std_real:u8[>..]=[];if !realPath(request.settings.options.std_root.value,std_real) {return true,blot_error::Error.none;}return !under(real[..],std_real[..]),blot_error::Error.none;
}
fn under(path:const u8[:],root:const u8[:])->bool {var end=root.len;while end>0 && root[end-1]=='/' {end--;}let trimmed=root[..end];return path.len>trimmed.len && path[..trimmed.len]==trimmed && path[trimmed.len]=='/';}
fn reportSite(writer:blot_io::Writer,kind:const u8[:],path:const u8[:],source:const u8[:],start:u32)->Error {
 var line:i64=1;var column:i64=1;for byte in source[..min(start as i64,source.len)] {if byte=='\n' {line+=1;column=1;}else {column+=1;}}return emit(writer,MigrationReport{kind:kind,filename:path,start:start,line:line,column:column});
}
// The strings of the settings and arguments of this command; they live as
// long as the process.
var migration_text:u8[>..]=[];
fn keep(bytes:const u8[:])->const u8[:] {let start=migration_text.len;migration_text.append(bytes);return migration_text[start..];}
// Lexically resolved against `root` unless already absolute.
fn absolutePath(root:const u8[:],path:const u8[:])->const u8[:],Error {
 var joined:u8[>..<]=[];if path.len==0 || path[0]!='/' {joined.append(root);joined.push('/');}joined.append(path);var resolved:u8[>..<]=[];let error=blot_support_path::normalize(joined[..],resolved);if error!=blot_error::Error.none {return default<const u8[:]>(),error;}return keep(resolved[..]),blot_error::Error.none;
}
fn objectMember(node:json::Node?,key:const u8[:])->json::Node? {let found=json::member(node,key);guard found else {return null;}match found.val {Obj=>{return found;},_=>{return null;}}}
fn textMember(root:const u8[:],node:json::Node?,key:const u8[:])->const u8[:],Error {let text,present=json::as_string(json::member(node,key));if !present {return default<const u8[:]>(),blot_error::Error.invalid_project_settings;}return absolutePath(root,text);}
fn optionalText(node:json::Node?,key:const u8[:])->blot_support::Option<const u8[:]>,Error {let found=json::member(node,key);guard found else {return blot_support::none<const u8[:]>(),blot_error::Error.none;}let text,present=json::as_string(found);if !present {return blot_support::none<const u8[:]>(),blot_error::Error.invalid_project_settings;}return blot_support::some<const u8[:]>(keep(text)),blot_error::Error.none;}
// Settings from a pen.json `compiler.settings`: std root and prelude,
// import aliases, native assets and the inference budget. Paths resolve
// against the file's directory. The vectors of the result are the caller's.
fn projectSettings(pen_path:const u8[:],aliases:blot_reuse_project::Alias[>..]&,roots:const u8[:][>..]&,definitions:blot_backend_native_assets::Definition[>..]&)->MigrationSettings,Error {
 var bytes:u8[>..<]=[];let error=blot_io::read_file(pen_path,bytes,1048576);if error!=blot_error::Error.none {return MigrationSettings{..},error;}
 var directory:const u8[:]=".";let split=blot_support_path::dirnameEnd(pen_path);if split.present {directory=pen_path[..split.value];if directory.len==0 {directory="/";}}var real:u8[>..]=[];if !realPath(directory,real) {return MigrationSettings{..},blot_error::Error.file_not_found;}let root=keep(real[..]);
 var text:u8[>..]=[];text.append(bytes[..]);var document:json::Node[>..]=[];var decoded:u8[>..]=[];let parsed,message=json::parse(text[..],document,decoded);guard parsed else {return MigrationSettings{..},blot_error::Error.syntax_error;}
 let settings=objectMember(objectMember(parsed,"compiler"),"settings");guard settings else {return MigrationSettings{..},blot_error::Error.invalid_project_settings;}
 var result=MigrationSettings{..};
 let library=json::member(settings,"std");
 if library {let text,present=json::as_string(library);if !present {return MigrationSettings{..},blot_error::Error.invalid_project_settings;}let std_root,error=absolutePath(root,text);if error!=blot_error::Error.none {return MigrationSettings{..},error;}result.options.std_root=blot_support::some<const u8[:]>(std_root);var prelude:u8[>..<]=[];prelude.append(std_root);prelude.append("/prelude.blot");result.options.prelude_path=blot_support::some<const u8[:]>(keep(prelude[..]));}
 let imports=objectMember(settings,"imports");
 if imports {var item=imports.first;while item {let text,present=json::as_string(item);if !present {return MigrationSettings{..},blot_error::Error.invalid_project_settings;}let path,error=absolutePath(root,text);if error!=blot_error::Error.none {return MigrationSettings{..},error;}aliases.push(blot_reuse_project::Alias{keep(item.key),path});item .= item.next;}result.options.aliases=aliases[..];}
 let budget=json::member(settings,"inferenceBudget");
 if budget {let value,present=json::as_i64(budget);if !present || value<0 {return MigrationSettings{..},blot_error::Error.invalid_project_settings;}result.inference_budget=blot_support::some(value as u64);}
 let native=objectMember(settings,"nativeAssets");
 if native {
  let root_list=json::member(native,"roots");
  if root_list {var item=root_list.first;while item {let text,present=json::as_string(item);if !present {return MigrationSettings{..},blot_error::Error.invalid_project_settings;}let path,error=absolutePath(root,text);if error!=blot_error::Error.none {return MigrationSettings{..},error;}roots.push(path);item .= item.next;}}
  let definition_list=json::member(native,"imports");
  if definition_list {var item=definition_list.first;while item {
   let module,error=textMember(root,item,"module");if error!=blot_error::Error.none {return MigrationSettings{..},error;}let path,error=textMember(root,item,"path");if error!=blot_error::Error.none {return MigrationSettings{..},error;}
   let name,present=json::as_string(json::member(item,"kind"));if !present {return MigrationSettings{..},blot_error::Error.invalid_project_settings;}var kind=blot_backend_native_assets::Kind.json;var known=false;const for <N,V> in variants<blot_backend_native_assets::Kind> {if name==N {kind=V;known=true;}}if !known {return MigrationSettings{..},blot_error::Error.invalid_project_settings;}
   let ty,error=optionalText(item,"type");if error!=blot_error::Error.none {return MigrationSettings{..},error;}let export_name,error=optionalText(item,"export");if error!=blot_error::Error.none {return MigrationSettings{..},error;}let media,error=optionalText(item,"mediaType");if error!=blot_error::Error.none {return MigrationSettings{..},error;}
   definitions.push(blot_backend_native_assets::Definition{module:module,path:path,kind:kind,ty:ty,export_name:export_name,mediaType:media});item .= item.next;
  }}
  result.assets=blot_support::some(blot_backend_native_assets::Options{imports:definitions[..],roots:roots[..]});
 }
 return result,blot_error::Error.none;
}
// The command line of `blotc migrate-stores`.
fn migrateStores(args:const Argument[:])->bool,Error {
 var aliases:blot_reuse_project::Alias[>..]=[];var roots:const u8[:][>..]=[];var definitions:blot_backend_native_assets::Definition[>..]=[];
 var entries:const u8[:][>..]=[];var settings=MigrationSettings{..};var write_root=blot_support::none<const u8[:]>();var include_std=false;var dry_run=false;var at:i64=0;
 while at<args.len {
  let arg=args[at];at+=1;
  if arg=="--include-std" {include_std=true;continue;}if arg=="--dry-run" {dry_run=true;continue;}
  if !starts(arg,"--") {var real:u8[>..]=[];if !realPath(arg,real) {return false,blot_error::Error.file_not_found;}entries.push(keep(real[..]));continue;}
  if at>=args.len {return false,blot_error::Error.none;}let value=args[at];at+=1;
  if arg=="--project" {
   // Aliases given before the project file stay ahead of the file's.
   let read,error=projectSettings(value,aliases,roots,definitions);if error!=blot_error::Error.none {return false,error;}settings=read;
   if !write_root.present {var directory:const u8[:]=".";let split=blot_support_path::dirnameEnd(value);if split.present {directory=value[..split.value];if directory.len==0 {directory="/";}}var real:u8[>..]=[];if !realPath(directory,real) {return false,blot_error::Error.file_not_found;}write_root=blot_support::some<const u8[:]>(keep(real[..]));}
  }
  else if arg=="--write-root" {var real:u8[>..]=[];if !realPath(value,real) {return false,blot_error::Error.file_not_found;}write_root=blot_support::some<const u8[:]>(keep(real[..]));}
  else if arg=="--std-root" {settings.options.std_root=blot_support::some<const u8[:]>(value);}
  else if arg=="--alias" {var split:i64=-1;for byte,index in value {if byte=='=' {split=index;break;}}if split<0 {return false,blot_error::Error.none;}aliases.push(blot_reuse_project::Alias{value[..split],value[split+1..]});}
  else if arg=="--prelude" {if value=="none" {settings.options.prelude_path=blot_support::none<const u8[:]>();}else {settings.options.prelude_path=blot_support::some<const u8[:]>(value);}}
  else if arg=="--inference-budget" {let limit,error=unsigned(value,0xffffffffffffffff);if error!=blot_error::Error.none {return false,error;}settings.inference_budget=blot_support::some(limit);}
  else {return false,blot_error::Error.none;}
 }
 if entries.len==0 {let error=blot_io::write_all(blot_io::Writer{2},usage);return false,error;}
 settings.options.aliases=aliases[..];if settings.inference_budget.present {let error=blot_main::configureInferenceBudget(settings.inference_budget.value);if error!=blot_error::Error.none {return false,error;}}
 if !write_root.present {var real:u8[>..]=[];if !realPath(".",real) {return false,blot_error::Error.file_not_found;}write_root=blot_support::some<const u8[:]>(keep(real[..]));}
 return migrate(blot_io::Writer{1},MigrationRequest{entries:entries[..],settings:settings,write_root:write_root.value,include_std:include_std,dry_run:dry_run});
}
