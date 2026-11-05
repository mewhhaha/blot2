// Native command dispatch and option admission preserve the public CLI shape.
namespace blot_cli;
import .cli_workers;
import .cli_diagnostics;
import .cli_pipeline;
import .compile_workspace;
import .project_executor;
import main;
import source_identity;
import inference_limits;
import execution_policy;
import reuse.project;
import reuse.restart_cache;
import reuse.dependency_cli;
import reuse.zig_project_server;
import support.error;
import support.option;
import support.native;
import support.io;
import support.json;
type Error=blot_error::Error;
type Text=blot_support::Option<const u8[:]>;
type Policy=blot_execution_policy::Policy;
type Options=blot_reuse_project::Options;
enum Command {lex,parse,check,build,dependencies,parse_project,check_project,build_project}
let usage:const u8[:]=
 "Usage: blotc lex|parse|check SOURCE [SOURCE...]\n"
 "       blotc build ENTRY OUTPUT.wasm [--dependencies FILE] [--profile] [project options]\n"
 "       blotc dependencies ENTRY OUTPUT.blotdep [project options]\n"
 "       blotc parse-project ENTRY [--std-root DIR] [--alias PREFIX=DIR] [--prelude PATH|none]\n"
 "       blotc check-project ENTRY [--std-root DIR] [--alias PREFIX=DIR] [--prelude PATH|none]\n"
 "       blotc build-project ENTRY OUTPUT.wasm [--std-root DIR] [--alias PREFIX=DIR] [--prelude PATH|none] [--profile]\n"
 "       blotc serve-project (owned project-build byte protocol)\n"
 "       blotc check|build also accepts explicit --prelude PATH|none (default: none).\n"
 "       Project options accept --input-mode project|source (default: project).\n"
 "       --profile (build, build-project) adds detailed backend clocks to the stats record.\n"
 "       --profile-memory instruments executed allocation, copy, RC and cycle costs.\n"
 "       --require-collector-free rejects modules without a whole-arena certificate.\n"
 "       --explain-allocations reports bounded emitted allocation sites and array-edit ownership decisions.\n"
 "       --inference-budget STEPS sets a process-local inference limit (default: 1000000).\n"
 "       --frontend-workers 1..16 (build, build-project, serve-project) opts into independent module checks.\n"
 "       --semantic-workers 1..16 (build, build-project, serve-project) opts into private semantic jobs.\n\n"
 "Goose source compiler. JSON-lines diagnostics and stage metrics are written\n"
 "to stdout. Parse coverage and executable coverage are distinct.\n\n";
type Argument=const u8[:];
struct Arguments {items:Argument[:]=[],bytes:u8[:]=[]}
reusable[] var argument_bytes:u8[>..]=[];
reusable[] var argument_headers:Argument[>..]=[];
fn readArguments()->Arguments,Error {
 let count=blot_native::argument_count();if count<0||count>16777216 {return Arguments{..},Error.invalid_request;}var total:i64=0;for index in count {let size=blot_native::argument_size(index);if size<0||size>536870912-total {return Arguments{..},Error.invalid_request;}total+=size;}
 var result=Arguments{items:argument_headers.alloc_slice(count),bytes:argument_bytes.alloc_slice(total)};var at:i64=0;for index in count {let size=blot_native::argument_size(index);if size<0||size>result.bytes.len-at {result.deinit();return Arguments{..},Error.invalid_request;}if size!=0&&blot_native::argument_copy(index,result.bytes[at],size as u64)!=size {result.deinit();return Arguments{..},Error.io;}result.items[index]=result.bytes[at..at+size];at+=size;}return result,Error.none;
}
fn deinit(self:Arguments&) {if self.items.len!=0 {argument_headers.free_slice(self.items);}if self.bytes.len!=0 {argument_bytes.free_slice(self.bytes);}self=Arguments{..};}
fn unsigned(text:const u8[:])->u64,bool {if text.len==0 {return 0,false;}var result:u64=0;for byte in text {if byte<'0'||byte>'9' {return 0,false;}let value=(byte-'0') as u64;if result>0xffffffffffffffff/10||(result==0xffffffffffffffff/10&&value>0xffffffffffffffff%10) {return 0,false;}result=result*10+value;}return result,true;}
fn semanticPolicy(value:const u8[:])->Policy,bool {let workers,valid=unsigned(value);if !valid||workers==0||workers>16 {return Policy{..},false;}return Policy{semantic_workers:workers as u8,semantic_components:true,..},true;}
fn configure(value:const u8[:])->Error {let limit,valid=unsigned(value);if !valid {return Error.invalid_inference_budget;}return blot_main::configureInferenceBudget(limit);}
fn starts(text:const u8[:],prefix:const u8[:])->bool {return text.len>=prefix.len&&text[..prefix.len]==prefix;}
fn commandName(command:Command)->const u8[:] {match command {Command.parse_project=>"parse-project",Command.check_project=>"check-project",Command.build_project=>"build-project",Command.lex=>"lex",Command.parse=>"parse",Command.check=>"check",Command.build=>"build",Command.dependencies=>"dependencies"}}
fn parseCommand(text:const u8[:])->Command,bool {for command in [Command.lex,Command.parse,Command.check,Command.build,Command.dependencies,Command.parse_project,Command.check_project,Command.build_project] {if text==commandName(command) {return command,true;}}return Command.lex,false;}
fn isBuild(command:Command)->bool {return command==Command.build||command==Command.build_project;}
fn run(args:const Argument[:])->bool,Error {
 let stdout=blot_io::Writer{1};let stderr=blot_io::Writer{2};if args.len<=1||args[1]=="--help" {return true,blot_io::write_all(stdout,usage);}if args[1]=="--worker" {if args.len!=2 {return false,Error.invalid_request;}let error=worker();return error==Error.none,error;}
 var cache=blot_support::none<u8[:]>();let root,error=blot_reuse_restart_cache::root();if error==Error.none {cache=root;}defer {if cache.present {blot_reuse_restart_cache::releaseRoot(cache.value);}}
 var cache_root=blot_support::none<const u8[:]>();if cache.present {cache_root=blot_support::some(cache.value[:]);}
 var executor=blot_project_executor::init();defer {executor.deinit();}
 if args[1]=="serve-project" {var policy=Policy{..};var at:i64=2;while at<args.len {if at+1>=args.len {return false,Error.invalid_serve_arguments;}if args[at]=="--semantic-workers" {let selected,valid=semanticPolicy(args[at+1]);if !valid {return false,Error.invalid_serve_arguments;}policy.semantic_workers=selected.semantic_workers;policy.semantic_components=true;}else if args[at]=="--frontend-workers" {let selected,valid=semanticPolicy(args[at+1]);if !valid {return false,Error.invalid_serve_arguments;}policy.frontend_workers=selected.semantic_workers;}else if args[at]=="--inference-budget" {let error=configure(args[at+1]);if error!=Error.none {return false,error;}}else {return false,Error.invalid_serve_arguments;}at+=2;}let error=blot_reuse_zig_project_server::runWithPolicy(executor,blot_io::Reader{0},stdout,blot_main::configured_identity,cache_root,policy);return error==Error.none,error;}
 let command,valid=parseCommand(args[1]);if !valid {let error=blot_io::write_all(stderr,usage);return false,error;}if args.len<3||((isBuild(command)||command==Command.dependencies)&&args.len<4) {let error=blot_io::write_all(stderr,usage);return false,error;}
 let project_command=command==Command.parse_project||command==Command.check_project||command==Command.build_project||command==Command.dependencies;var first_option:i64=3;if isBuild(command)||command==Command.dependencies {first_option=4;}
 if !project_command&&command!=Command.build {first_option=args.len;for arg,index in args[3..] {if starts(arg,"--") {first_option=index+3;break;}}}
 if project_command||first_option<args.len {if command==Command.lex {return false,Error.none;}var aliases:blot_reuse_project::Alias[>..<]=[];var options=Options{..};var dependency_path=blot_support::none<const u8[:]>();var profile=false;var explain=false;var policy=Policy{..};var at=first_option;
  while at<args.len {
   let arg=args[at];if arg=="--require-collector-free"||arg=="--profile-memory"||arg=="--profile"||arg=="--explain-allocations" {if !isBuild(command) {return false,Error.none;}if arg=="--require-collector-free" {policy.require_collector_free=true;}else if arg=="--profile-memory" {policy.memory_profile=true;}else if arg=="--profile" {profile=true;}else {explain=true;}at++;continue;}
   if at+1>=args.len {return false,Error.none;}let value=args[at+1];at+=2;
   if arg=="--semantic-workers" {if !isBuild(command) {return false,Error.none;}let selected,valid=semanticPolicy(value);if !valid {return false,Error.none;}policy.semantic_workers=selected.semantic_workers;policy.semantic_components=true;}
   else if arg=="--frontend-workers" {if !isBuild(command) {return false,Error.none;}let selected,valid=semanticPolicy(value);if !valid {return false,Error.none;}policy.frontend_workers=selected.semantic_workers;}
   else if arg=="--inference-budget" {let error=configure(value);if error!=Error.none {return false,error;}}
   else if arg=="--std-root" {options.std_root=blot_support::some(value);}
   else if arg=="--alias" {var split:i64=-1;for byte,index in value {if byte=='=' {split=index;break;}}if split<0 {return false,Error.none;}aliases.push(blot_reuse_project::Alias{value[..split],value[split+1..]});}
   else if arg=="--input-mode" {if value=="project" {options.input_mode=blot_reuse_project::InputMode.project;}else if value=="source" {options.input_mode=blot_reuse_project::InputMode.source;}else {return false,Error.none;}}
   else if arg=="--prelude" {if value=="none" {options.prelude_path=blot_support::none<const u8[:]>();}else {options.prelude_path=blot_support::some(value);}}
   else if arg=="--dependencies" {if !isBuild(command)||dependency_path.present {return false,Error.none;}dependency_path=blot_support::some(value);}
   else {return false,Error.none;}
  }
  options.aliases=aliases[:];if command==Command.dependencies||dependency_path.present {if profile||policy.semantic_components||explain {return false,Error.none;}var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=Error.none {return false,error;}let workspace=frame.borrow();assert(workspace);let success,error=blot_reuse_dependency_cli::processWithOptions(executor,workspace,stdout,command==Command.dependencies,args[2],args[3],dependency_path,options,blot_main::configured_identity,blot_backend_core_backend::CompileOptions{compiler_identity:blot_main::configured_identity,policy:policy,..});let released=frame.release();if error!=Error.none {return false,error;}if released!=Error.none {return false,released;}return success,blot_io::flush(stdout);}
  var selected=Command.build_project;if command==Command.parse||command==Command.parse_project {selected=Command.parse_project;}else if command==Command.check||command==Command.check_project {selected=Command.check_project;}var end=first_option;if selected==Command.build_project||project_command {end=3;}var success=true;for filename in args[2..end] {var output=blot_support::none<const u8[:]>();if selected==Command.build_project {output=blot_support::some(args[3]);}let accepted,error=processProject(executor,stdout,selected,filename,options,profile,explain,output,cache_root,policy);if error!=Error.none {let written=diagnostic(stdout,filename,commandName(selected),blot_error::error_name(error),0,0,"Compiler operation failed");if written!=Error.none {return false,written;}blot_io::flush(stdout);return false,Error.none;}success=success&&accepted;}return success,blot_io::flush(stdout);
 }
 var success=true;var end=args.len;if command==Command.build {end=3;}for filename in args[2..end] {var output=blot_support::none<const u8[:]>();if command==Command.build {output=blot_support::some(args[3]);}let accepted,error=process(stdout,command,filename,output,cache_root);if error!=Error.none {let written=diagnostic(stdout,filename,commandName(command),blot_error::error_name(error),0,0,"Compiler operation failed");if written!=Error.none {return false,written;}success=false;continue;}success=success&&accepted;}return success,blot_io::flush(stdout);
}
