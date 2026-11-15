// Command dispatch; mirrors compiler/src/main.zig.
namespace blot_cli;
import .cli_diagnostics;
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
import reuse.project;
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
enum Command {lex,parse,check,build,dependencies,parse_project,check_project,build_project}
let usage:const u8[:]="Usage: blotc lex|parse|check SOURCE [SOURCE...]\n       blotc build ENTRY OUTPUT.wasm [--dependencies FILE] [--profile] [project options]\n       blotc dependencies ENTRY OUTPUT.blotdep [project options]\n       blotc parse-project ENTRY [--std-root DIR] [--alias PREFIX=DIR] [--prelude PATH|none]\n       blotc check-project ENTRY [--std-root DIR] [--alias PREFIX=DIR] [--prelude PATH|none]\n       blotc build-project ENTRY OUTPUT.wasm [--std-root DIR] [--alias PREFIX=DIR] [--prelude PATH|none] [--profile]\n       blotc serve-project (owned project-build byte protocol)\n       blotc migrate-stores ENTRY [--project PEN.json] [--write-root DIR] [--include-std] [--dry-run] [project options]\n";
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
fn semanticPolicy(value:const u8[:])->Policy,bool {let workers,error=unsigned(value,255);if error!=blot_error::Error.none||workers==0||workers>16 {return Policy{..},false;}return Policy{semantic_workers:workers as u8,semantic_components:true,..},true;}
fn configure(value:const u8[:])->Error {let limit,error=unsigned(value,0xffffffffffffffff);if error!=blot_error::Error.none {return error;}return blot_main::configureInferenceBudget(limit);}
fn starts(text:const u8[:],prefix:const u8[:])->bool {return text.len>=prefix.len&&text[..prefix.len]==prefix;}
fn commandName(command:Command)->const u8[:] {match command {parse_project=>"parse-project",check_project=>"check-project",build_project=>"build-project",lex=>"lex",parse=>"parse",check=>"check",build=>"build",dependencies=>"dependencies"}}
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
fn now()->u64 {return blot_native::clock_ns();}
fn elapsed(start:u64)->i64 {let ended=now();if ended<start {return 0;}return ((ended-start)/1000) as i64;}
struct SimpleRecord {kind:const u8[:]="compilation",filename:const u8[:],stage:const u8[:],success:bool,total_us:i64,stats:Stats,memory:blot_runtime_memory::Counts=blot_runtime_memory::Counts{..},memory_scope:const u8[:]="Requested bytes for source and compiler-owned buffers; excludes allocator overhead and process RSS. All owners released before this record."}
fn process(writer:blot_io::Writer,command:Command,filename:const u8[:],output:Text)->bool,Error {var stats=Stats{..};let started=now();let accepted,error=processSingle(writer,command,filename,output,stats);if error!=blot_error::Error.none {return false,error;}let written=emit(writer,SimpleRecord{filename:filename,stage:commandName(command),success:accepted,total_us:elapsed(started),stats:stats,..});return accepted,written;}
fn processSingle(writer:blot_io::Writer,command:Command,filename:const u8[:],output:Text,stats:Stats&)->bool,Error {
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
 // The direct backend is not ported yet.
 lowered.deinit();return false,blot_error::Error.invalid_request;
}
fn run(args:const Argument[:])->bool,Error {
 let stdout=blot_io::Writer{1};let stderr=blot_io::Writer{2};if args.len<=1||args[1]=="--help" {return true,blot_io::write_all(stdout,usage);}
 let command,valid=parseCommand(args[1]);if !valid {let error=blot_io::write_all(stderr,usage);return false,error;}
 if args.len<3||(isBuild(command)&&args.len<4) {let error=blot_io::write_all(stderr,usage);return false,error;}
 var success=true;var end=args.len;if command==Command.build {end=3;}
 for filename in args[2..end] {var output=blot_support::none<const u8[:]>();if command==Command.build {output=blot_support::some<const u8[:]>(args[3]);}let accepted,error=process(stdout,command,filename,output);if error!=blot_error::Error.none {let written=diagnostic(stdout,filename,commandName(command),blot_error::error_name(error),0,0,blot_error::error_name(error));if written!=blot_error::Error.none {return false,written;}success=false;}else if !accepted {success=false;}}
 return success,blot_error::Error.none;
}
