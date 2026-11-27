// C-host entry. Compiler logic remains ordinary Goose code.
namespace squid_main;
import direct.writer;
import driver.cli;
import inference_limits;
import source_identity;
import support.error;
import support.io;
import support.blake3;
import support.bytes;
type Error=squid_error::Error;
var configured_identity:u8[32]=squid_source_identity::digest;
fn inferenceBudget()->u64 {return squid_inference_limits::configured();}
fn refreshIdentity() {
 let limit=squid_inference_limits::configured();
 let relaxed=squid_direct_writer::relaxedSimdEnabled();
 let tails=squid_direct_writer::tailCallsEnabled();
 let test_mode=squid_direct_writer::testModeEnabled();
 let sb=squid_direct_writer::stackBudget();
 let hb=squid_direct_writer::heapBudget();
 let tb=squid_direct_writer::transportBudget();
 let default_budgets=sb==squid_direct_writer::default_stack_bytes && hb==squid_direct_writer::default_heap_bytes && tb==squid_direct_writer::default_transport_bytes;
 if limit==squid_source_identity::inference_budget && !relaxed && !tails && !test_mode && default_budgets {
  configured_identity=squid_source_identity::digest;
  return;
 }
 var hash=squid_support_blake3::init();
 hash.update(squid_source_identity::digest);
 if limit!=squid_source_identity::inference_budget {
  hash.update("inference-budget");
  var bytes:u8[8]=[0;8];
  squid_bytes::put_u64(bytes,0,limit);
  hash.update(bytes);
 }
 if relaxed || tails {
  hash.update("wasm-features");
  var flags:u8[1]=[0];
  if relaxed {flags[0]|=1;}
  if tails {flags[0]|=2;}
  hash.update(flags);
 }
 if test_mode {hash.update("test-mode");}
 if !default_budgets {
  hash.update("memory-budgets");
  var bbuf:u8[12]=[0;12];
  squid_bytes::put_u32(bbuf,0,sb);
  squid_bytes::put_u32(bbuf,4,hb);
  squid_bytes::put_u32(bbuf,8,tb);
  hash.update(bbuf);
 }
 configured_identity=hash.final();
}
fn configureInferenceBudget(limit:u64)->Error {
 let error=squid_inference_limits::configure(limit);if error!=squid_error::Error.none {return error;}
 refreshIdentity();
 return squid_error::Error.none;
}
fn configureWasmFeatures(relaxed_simd:bool,tail_calls:bool) {
 squid_direct_writer::setWasmFeatures(relaxed_simd,tail_calls);
 refreshIdentity();
}
fn configureTestMode(enabled:bool) {
 squid_direct_writer::setTestMode(enabled);
 refreshIdentity();
}
fn configureMemoryBudgets(stack_mb:u32,heap_mb:u32,transport_mb:u32) {
 squid_direct_writer::setMemoryBudgets(stack_mb*1048576,heap_mb*1048576,transport_mb*1048576);
 refreshIdentity();
}
export "squid_goose_main" fn mainEntry()->i32 {
 let configured=configureInferenceBudget(squid_source_identity::inference_budget);if configured!=squid_error::Error.none {return failure(configured);}
 var arguments,error=squid_cli::readArguments();if error!=squid_error::Error.none {return failure(error);}let success,error=squid_cli::run(arguments.items);arguments.deinit();if error!=squid_error::Error.none {return failure(error);}if success {return 0;}return 1;
}
fn failure(error:Error)->i32 {var text:u8[>..<]=[];text.append("squidc: ");text.append(squid_error::error_name(error));text.push('\n');squid_io::write_all(squid_io::Writer{2},text[..]);return 1;}
