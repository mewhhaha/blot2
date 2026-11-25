// C-host entry. Compiler logic remains ordinary Goose code.
namespace blot_main;
import direct.writer;
import driver.cli;
import inference_limits;
import source_identity;
import support.error;
import support.io;
import support.blake3;
import support.bytes;
type Error=blot_error::Error;
var configured_identity:u8[32]=blot_source_identity::digest;
fn inferenceBudget()->u64 {return blot_inference_limits::configured();}
fn refreshIdentity() {
 let limit=blot_inference_limits::configured();
 let relaxed=blot_direct_writer::relaxedSimdEnabled();
 let tails=blot_direct_writer::tailCallsEnabled();
 if limit==blot_source_identity::inference_budget && !relaxed && !tails {
  configured_identity=blot_source_identity::digest;
  return;
 }
 var hash=blot_support_blake3::init();
 hash.update(blot_source_identity::digest);
 if limit!=blot_source_identity::inference_budget {
  hash.update("inference-budget");
  var bytes:u8[8]=[0;8];
  blot_bytes::put_u64(bytes,0,limit);
  hash.update(bytes);
 }
 if relaxed || tails {
  hash.update("wasm-features");
  var flags:u8[1]=[0];
  if relaxed {flags[0]|=1;}
  if tails {flags[0]|=2;}
  hash.update(flags);
 }
 configured_identity=hash.final();
}
fn configureInferenceBudget(limit:u64)->Error {
 let error=blot_inference_limits::configure(limit);if error!=blot_error::Error.none {return error;}
 refreshIdentity();
 return blot_error::Error.none;
}
fn configureWasmFeatures(relaxed_simd:bool,tail_calls:bool) {
 blot_direct_writer::setWasmFeatures(relaxed_simd,tail_calls);
 refreshIdentity();
}
export "blot_goose_main" fn mainEntry()->i32 {
 let configured=configureInferenceBudget(blot_source_identity::inference_budget);if configured!=blot_error::Error.none {return failure(configured);}
 var arguments,error=blot_cli::readArguments();if error!=blot_error::Error.none {return failure(error);}let success,error=blot_cli::run(arguments.items);arguments.deinit();if error!=blot_error::Error.none {return failure(error);}if success {return 0;}return 1;
}
fn failure(error:Error)->i32 {var text:u8[>..<]=[];text.append("blotc: ");text.append(blot_error::error_name(error));text.push('\n');blot_io::write_all(blot_io::Writer{2},text[..]);return 1;}
