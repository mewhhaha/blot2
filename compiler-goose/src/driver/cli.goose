// Command dispatch; mirrors compiler/src/main.zig.
namespace blot_cli;
import .cli_diagnostics;
import .cli_project;
import .cli_migrate_stores;
import main;
import inference_limits;
import execution_policy;
import parse.lexer;
import parse.token;
import parse.parser;
import parse.ast;
import parse.symbols;
import parse.syntax_diagnostics;
import check.check;
import check.core;
import check.core_builder;
import compile;
import reuse.project;
import reuse.dependency_cli;
import reuse.zig_project_server;
import runtime.memory;
import support.error;
import support.option;
import support.native;
import support.io;
import support.json;
type Error=blot_error::Error;
type Text=blot_support::Option<const u8[:]>;
type Policy=blot_execution_policy::Policy;
type Options=blot_reuse_project::Options;
enum Command {lex,parse,check_exports,check,build,dependencies,parse_project,check_project,build_project}
let usage:const u8[:]="Usage: blotc lex|parse|check SOURCE [SOURCE...]\n       blotc check-exports [--include-private] SOURCE [SOURCE...]\n       blotc build ENTRY OUTPUT.wasm [--dependencies FILE] [--profile] [project options]\n       blotc dependencies ENTRY OUTPUT.blotdep [project options]\n       blotc parse-project ENTRY [--std-root DIR] [--alias PREFIX=DIR] [--prelude PATH|none]\n       blotc check-project ENTRY [--std-root DIR] [--alias PREFIX=DIR] [--prelude PATH|none]\n       blotc build-project ENTRY OUTPUT.wasm [--std-root DIR] [--alias PREFIX=DIR] [--prelude PATH|none] [--profile]\n       blotc serve-project (owned project-build byte protocol)\n       blotc migrate-stores ENTRY... [--project PEN_JSON] [--write-root DIR] [--include-std] [--dry-run] [project options]\n       migrate-stores rewrites each := that gets aliased_update into the store =.\n       blotc check|build also accepts explicit --prelude PATH|none (default: none).\n       Project options accept --input-mode project|source (default: project).\n       --profile (build, build-project) adds phase clocks to the stats record.\n       --inference-budget STEPS sets a process-local inference limit (default: 1000000).\n       --frontend-workers 1..16 (build, build-project, serve-project) opts into independent module checks.\n       --semantic-workers 1..16 (build, build-project, serve-project) lowers modules on workers.\n\nBlot compiler written in Goose. JSON-lines diagnostics and stage metrics\nare written to stdout. Parse coverage and executable coverage are distinct.\n\n";
type Argument=const u8[:];
struct Arguments {items:Argument[:]=default<Argument[:]>(),bytes:u8[:]=default<u8[:]>()}
reusable[] var argument_bytes:u8[>..]=[];
reusable[] var argument_headers:Argument[>..]=[];
fn readArguments()->Arguments,Error {
 let count=blot_native::argument_count();if count<0||count>16777216 {return Arguments{..},blot_error::Error.invalid_request;}var total:i64=0;for index in count {let size=blot_native::argument_size(index);if size<0||size>536870912-total {return Arguments{..},blot_error::Error.invalid_request;}total+=size;}
 var result=Arguments{items:argument_headers.alloc_slice(count),bytes:argument_bytes.alloc_slice(total)};var at:i64=0;for index in count {let size=blot_native::argument_size(index);if size<0||size>result.bytes.len-at {result.deinit();return Arguments{..},blot_error::Error.invalid_request;}if size!=0&&blot_native::argument_copy(index,result.bytes[at],size as u64)!=size {result.deinit();return Arguments{..},blot_error::Error.io;}result.items[index]=result.bytes[at..at+size];at+=size;}return result,blot_error::Error.none;
}
fn deinit(self_:Arguments&) {if self_.items.len!=0 {argument_headers.free_slice(self_.items);}if self_.bytes.len!=0 {argument_bytes.free_slice(self_.bytes);}self_=Arguments{..};}
// Decimal std.fmt.parseInt contract: one sign, internal underscores, exact
// unsigned width overflow, and distinct invalid-character/zero-budget errors.
fn unsigned(text:const u8[:],maximum:u64)->u64,Error {
 if text.len==0 {return 0,blot_error::Error.invalid_character;}var start:i64=0;var negative=false;if text[0]=='+'||text[0]=='-' {negative=text[0]=='-';start=1;}if start==text.len||text[start]=='_'||text[text.len-1]=='_' {return 0,blot_error::Error.invalid_character;}
 var result:u64=0;for byte in text[start..] {if byte=='_' {continue;}if byte<'0'||byte>'9' {return 0,blot_error::Error.invalid_character;}let value=(byte-'0') as u64;if negative&&value!=0 {return 0,blot_error::Error.overflow;}if result>maximum/10||(result==maximum/10&&value>maximum%10) {return 0,blot_error::Error.overflow;}result=result*10+value;}return result,blot_error::Error.none;
}
fn workerCount(value:const u8[:])->u8,bool {let workers,error=unsigned(value,255);if error!=blot_error::Error.none||workers==0||workers>16 {return 0,false;}return workers as u8,true;}
fn configure(value:const u8[:])->Error {let limit,error=unsigned(value,0xffffffffffffffff);if error!=blot_error::Error.none {return error;}return blot_main::configureInferenceBudget(limit);}
fn starts(text:const u8[:],prefix:const u8[:])->bool {return text.len>=prefix.len&&text[..prefix.len]==prefix;}
fn commandName(command:Command)->const u8[:] {match command {parse_project=>"parse-project",check_project=>"check-project",build_project=>"build-project",lex=>"lex",parse=>"parse",check_exports=>"check-exports",check=>"check",build=>"build",dependencies=>"dependencies"}}
fn parseCommand(text:const u8[:])->Command,bool {for command in [Command.lex,Command.parse,Command.check,Command.build,Command.dependencies,Command.parse_project,Command.check_project,Command.build_project] {if text==commandName(command) {return command,true;}}return Command.lex,false;}
fn isBuild(command:Command)->bool {return command==Command.build||command==Command.build_project;}
struct Stats {
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
 emitted_functions:i64=0,
 core_nodes:i64=0,
 body_lowerings:i64=0,
 lex_us:i64=0,
 parse_us:i64=0,
 check_us:i64=0,
 lower_us:i64=0,
 emit_us:i64=0,
 checker:blot_check_check::Counters=blot_check_check::Counters{..},
}
// Compare public-only and whole-module signature policies without executing
// initializers, resolving imports or inferring types from function bodies.
fn checkExportSignatures(writer:blot_io::Writer,filename:const u8[:],tree:const blot_parse_ast::Tree&,names:const blot_parse_symbols::Pool&,include_private:bool)->bool,Error {
 var checked:u32=0;
 var missing:u32=0;
 for id in tree.roots.items {
  if tree.node(id).tag!=blot_parse_ast::tag_value_decl {continue;}
  if !include_private && blot_parse_ast::declaration_traits(tree,id).private {continue;}
  checked++;
  let declaration=tree.value_decl(id);
  if declaration.annotation!=0 {continue;}
  var expr=declaration.body;
  var complete=false;
  var problem=id;
  while tree.node(expr).tag==blot_parse_ast::tag_group {expr=tree.node(expr).a;}
  while tree.node(expr).tag==blot_parse_ast::tag_lambda {
   let lambda=tree.node(expr);
   let parameter=tree.parameter(lambda.a);
   if !parameter.is_unit && parameter.annotation==0 {problem=lambda.a;break;}
   if lambda.c!=0 {complete=true;break;}
   expr=lambda.b;
  }
  if complete {continue;}
  missing++;
  let span=tree.span(problem);
  var start=span.start;
  var end=span.end;
  if problem==id {
   let point,found=tree.value_name_point(id);
   if found {start=point;end=start+(names.get(declaration.name).len as u32);}
  }
  let error=diagnostic(writer,filename,"check-exports","missing_signature",start,end,"Write the parameter and result types or give the declaration a type");
  if error!=blot_error::Error.none {return false,error;}
 }
 let error=emit(writer,SignatureSummary{filename:filename,checked:checked,missing:missing,..});
 return missing==0,error;
}
struct SignatureSummary {kind:const u8[:]="signatures",filename:const u8[:],checked:u32,missing:u32}
fn now()->u64 {return blot_native::clock_ns();}
fn elapsed(start:u64)->i64 {let ended=now();if ended<start {return 0;}return ((ended-start)/1000) as i64;}
struct SimpleRecord {kind:const u8[:]="compilation",filename:const u8[:],stage:const u8[:],success:bool,total_us:i64,stats:Stats,memory:blot_runtime_memory::Counts=blot_runtime_memory::Counts{..},memory_scope:const u8[:]="Requested bytes of the compiler's pooled owners; excludes arrays owned by a scope, pool capacity and process RSS. All owners released before this record."}
fn process(writer:blot_io::Writer,command:Command,filename:const u8[:],output:Text)->bool,Error {let meter=blot_runtime_memory::start();var stats=Stats{..};let started=now();let accepted,error=processSingle(writer,command,filename,output,stats);if error!=blot_error::Error.none {return false,error;}let written=emit(writer,SimpleRecord{filename:filename,stage:commandName(command),success:accepted,total_us:elapsed(started),stats:stats,memory:meter.counts(),..});return accepted,written;}
fn processSingle(writer:blot_io::Writer,command:Command,filename:const u8[:],output:Text,stats:Stats&,include_private:bool=false)->bool,Error {
 var input=blot_reuse_project::FileInputs{..};var source:u8[>..<]=[];let read=input.read(filename,33554432,source);if read!=blot_error::Error.none {return false,read;}stats.source_bytes=source.len;
 var names,error=blot_parse_symbols::initPooled();if error!=blot_error::Error.none {return false,error;}
 var tokens:blot_parse_token::Token[>..<]=[];var comments:blot_parse_token::Token[>..<]=[];var diagnostics:blot_parse_lexer::Diagnostic[>..<]=[];var lexed=blot_parse_lexer::init(tokens,comments,diagnostics);let lex_start=now();let error=blot_parse_lexer::lex(source[..],lexed);if error!=blot_error::Error.none {names.deinit();return false,error;}stats.lex_us=elapsed(lex_start);stats.tokens=tokens.len;
 if diagnostics.len!=0 {let error=frontendDiagnostic(writer,filename,"lex",source[..],blot_parse_syntax_diagnostics::lexical(tokens[..],diagnostics[0]),diagnostics[..]);names.deinit();return false,error;}
 if command==Command.lex {names.deinit();return true,blot_error::Error.none;}
 var tree,error=blot_parse_ast::initPooled();if error!=blot_error::Error.none {names.deinit();return false,error;}
 let parse_start=now();let error=blot_parse_parser::parse(source[..],tokens[..],names,tree);if error!=blot_error::Error.none {tree.deinit();names.deinit();return false,error;}
 if tree.diagnostics.len!=0 {let publication,error=blot_parse_syntax_diagnostics::parse(tokens[..],tree.diagnostics.items[0]);if error!=blot_error::Error.none {tree.deinit();names.deinit();return false,error;}let error=frontendDiagnostic(writer,filename,"parse",source[..],publication,tree.diagnostics.items);if error!=blot_error::Error.none {tree.deinit();names.deinit();return false,error;}}
 stats.parse_us=elapsed(parse_start);stats.syntax_nodes=tree.nodes.len-1;stats.syntax_extra_words=tree.extra.len;stats.symbols=names.entries.len;stats.symbol_bytes=names.bytes.len;
 if tree.diagnostics.len!=0 {tree.deinit();names.deinit();return false,blot_error::Error.none;}
 if command==Command.check_exports {
  let accepted,error=checkExportSignatures(writer,filename,tree,names,include_private);
  tree.deinit();names.deinit();return accepted,error;
 }
 if command==Command.parse {tree.deinit();names.deinit();return true,blot_error::Error.none;}
 let check_start=now();var checked,error=blot_check_check::check(tree,names);if error!=blot_error::Error.none {tree.deinit();names.deinit();return false,error;}
 stats.check_us=elapsed(check_start);stats.type_nodes=checked.types.nodes.len;stats.type_versions=checked.types.versions.len;stats.bindings=checked.bindings.len-1;stats.body_elaborations=checked.body_elaborations;stats.checker=checked.counters;
 if checked.diagnostics.len!=0 {let error=checkDiagnostics(writer,filename,source[..],names,checked.diagnostics);checked.deinit();tree.deinit();names.deinit();return false,error;}
 if command==Command.check {checked.deinit();tree.deinit();names.deinit();return true,blot_error::Error.none;}
 let lower_start=now();var lowered,error=blot_check_core_builder::lower(tree,names,checked);if error!=blot_error::Error.none {checked.deinit();tree.deinit();names.deinit();return false,error;}
 lowered.value.unit=1;stats.lower_us=elapsed(lower_start);stats.core_nodes=lowered.value.nodes.len-1;stats.body_lowerings=lowered.value.body_lowerings;
 for item in lowered.value.diagnostics {let error=diagnostic(writer,filename,"lower",enumName(item.code),item.span.start,item.span.end,item.message());if error!=blot_error::Error.none {lowered.deinit();checked.deinit();tree.deinit();names.deinit();return false,error;}}
 if lowered.value.diagnostics.len!=0 {lowered.deinit();checked.deinit();tree.deinit();names.deinit();return false,blot_error::Error.none;}
 checked.deinit();tree.deinit();names.deinit();source.clear();tokens.clear();comments.clear();diagnostics.clear();
 let emit_start=now();var wasm:u8[>..<]=[];var detail:u8[>..<]=[];let units:blot_check_core::Module[1]=[lowered.value];
 let compiled=blot_compile::compile(units[..],1,wasm,detail);stats.emit_us=elapsed(emit_start);stats.emitted_functions=compiled.emitted_functions;
 if compiled.has_diagnostic {var message:u8[>..]=[];message.append(blot_compile::message(compiled.diagnostic,detail[..]));let error=diagnostic(writer,filename,"emit",enumName(compiled.diagnostic.code),compiled.diagnostic.span.start,compiled.diagnostic.span.end,message[..]);lowered.deinit();return false,error;}
 stats.wasm_bytes=wasm.len;let written=blot_io::write_file(output.value,wasm[..]);lowered.deinit();if written!=blot_error::Error.none {return false,written;}return true,blot_error::Error.none;
}
fn stageName(command:Command)->const u8[:] {if command==Command.parse_project {return "parse-project";}if command==Command.check_project {return "check-project";}return "build-project";}
fn run(args:const Argument[:])->bool,Error {
 let stdout=blot_io::Writer{1};let stderr=blot_io::Writer{2};if args.len<=1||args[1]=="--help" {return true,blot_io::write_all(stdout,usage);}
 if args[1]=="check-exports" {
  var start:i64=2;
  let include_private=args.len>2 && args[2]=="--include-private";
  if include_private {start++;}
  if args.len<=start {return false,blot_io::write_all(stderr,usage);}
  var accepted=true;
  for filename in args[start..] {
   if starts(filename,"--") {return false,blot_io::write_all(stderr,usage);}
   var stats=Stats{..};
   let ok,error=processSingle(stdout,Command.check_exports,filename,blot_support::none<const u8[:]>(),stats,include_private);
   if error!=blot_error::Error.none {return false,error;}
   if !ok {accepted=false;}
  }
  return accepted,blot_error::Error.none;
 }
 if args[1]=="serve-project" {
  var policy=Policy{..};var at:i64=2;
  while at<args.len {
   if at+1>=args.len {return false,blot_error::Error.invalid_serve_arguments;}let value=args[at+1];
   if args[at]=="--semantic-workers" {let workers,valid=workerCount(value);if !valid {return false,blot_error::Error.invalid_serve_arguments;}policy.semantic_workers=workers;}
   else if args[at]=="--frontend-workers" {let workers,valid=workerCount(value);if !valid {return false,blot_error::Error.invalid_serve_arguments;}policy.frontend_workers=workers;}
   else if args[at]=="--inference-budget" {let error=configure(value);if error!=blot_error::Error.none {return false,error;}}
   else {return false,blot_error::Error.invalid_serve_arguments;}
   at+=2;
  }
  let error=blot_reuse_zig_project_server::run(blot_io::Reader{0},stdout,blot_main::configured_identity,policy);return error==blot_error::Error.none,error;
 }
 if args[1]=="migrate-stores" {return migrateStores(args[2..]);}
 let command,valid=parseCommand(args[1]);if !valid {let error=blot_io::write_all(stderr,usage);return false,error;}
 if args.len<3||((isBuild(command)||command==Command.dependencies)&&args.len<4) {let error=blot_io::write_all(stderr,usage);return false,error;}
 let project_command=command==Command.parse_project||command==Command.check_project||command==Command.build_project||command==Command.dependencies;
 var first_option:i64=3;if isBuild(command)||command==Command.dependencies {first_option=4;}
 if !project_command&&command!=Command.build {first_option=args.len;for arg,index in args[3..] {if starts(arg,"--") {first_option=index+3;break;}}}
 if project_command||first_option<args.len {
  if command==Command.lex {return false,blot_error::Error.none;}
  var aliases:blot_reuse_project::Alias[>..]=[];var options=Options{..};var dependency_path=blot_support::none<const u8[:]>();var profile=false;var semantic_workers=false;var policy=Policy{..};var at=first_option;
  while at<args.len {
   let arg=args[at];
   // The profiling flag takes no value.
   if arg=="--profile" {if !isBuild(command) {return false,blot_error::Error.none;}profile=true;at+=1;continue;}
   if at+1>=args.len {return false,blot_error::Error.none;}let value=args[at+1];at+=2;
   if arg=="--semantic-workers" {if !isBuild(command) {return false,blot_error::Error.none;}let workers,valid=workerCount(value);if !valid {return false,blot_error::Error.none;}policy.semantic_workers=workers;semantic_workers=true;}
   else if arg=="--frontend-workers" {if !isBuild(command) {return false,blot_error::Error.none;}let workers,valid=workerCount(value);if !valid {return false,blot_error::Error.none;}policy.frontend_workers=workers;}
   else if arg=="--inference-budget" {let error=configure(value);if error!=blot_error::Error.none {return false,error;}}
   else if arg=="--std-root" {options.std_root=blot_support::some<const u8[:]>(value);}
   else if arg=="--alias" {var split:i64=-1;for byte,index in value {if byte=='=' {split=index;break;}}if split<0 {return false,blot_error::Error.none;}aliases.push(blot_reuse_project::Alias{value[..split],value[split+1..]});}
   else if arg=="--input-mode" {if value=="project" {options.input_mode=blot_reuse_project::InputMode.project;}else if value=="source" {options.input_mode=blot_reuse_project::InputMode.source;}else {return false,blot_error::Error.none;}}
   else if arg=="--prelude" {if value=="none" {options.prelude_path=blot_support::none<const u8[:]>();}else {options.prelude_path=blot_support::some<const u8[:]>(value);}}
   else if arg=="--dependencies" {if !isBuild(command)||dependency_path.present {return false,blot_error::Error.none;}dependency_path=blot_support::some<const u8[:]>(value);}
   else {return false,blot_error::Error.none;}
  }
  options.aliases=aliases[..];
  if command==Command.dependencies||dependency_path.present {if profile||semantic_workers {return false,blot_error::Error.none;}var out=stdout;return blot_reuse_dependency_cli::process(out,command==Command.dependencies,args[2],args[3],dependency_path,options,blot_main::configured_identity);}
  var selected=Command.build_project;if command==Command.parse||command==Command.parse_project {selected=Command.parse_project;}else if command==Command.check||command==Command.check_project {selected=Command.check_project;}
  var end=first_option;if selected==Command.build_project||project_command {end=3;}var success=true;
  for filename in args[2..end] {var output=blot_support::none<const u8[:]>();if selected==Command.build_project {output=blot_support::some<const u8[:]>(args[3]);}
   let accepted,error=processProject(stdout,selected,filename,options,profile,output,policy);
   if error!=blot_error::Error.none {let written=diagnostic(stdout,filename,stageName(selected),blot_error::error_name(error),0,0,"Compiler operation failed");return false,written;}
   success=success&&accepted;}
  return success,blot_error::Error.none;
 }
 var success=true;var end=args.len;if command==Command.build {end=3;}
 for filename in args[2..end] {var output=blot_support::none<const u8[:]>();if command==Command.build {output=blot_support::some<const u8[:]>(args[3]);}let accepted,error=process(stdout,command,filename,output);if error!=blot_error::Error.none {let written=diagnostic(stdout,filename,commandName(command),blot_error::error_name(error),0,0,"Compiler operation failed");if written!=blot_error::Error.none {return false,written;}success=false;}else if !accepted {success=false;}}
 return success,blot_error::Error.none;
}
