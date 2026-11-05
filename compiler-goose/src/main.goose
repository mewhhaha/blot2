// C-host entry. Compiler logic and worker dispatch remain ordinary Goose code.
namespace blot_main;
import driver.cli;
import driver.cli_workers;
import inference_limits;
import source_identity;
import support.error;
import support.json_adapters;
import support.io;
import support.native;
import support.blake3;
import support.bytes;
import support.process_pool;
type Error=blot_error::Error;
var configured_identity:u8[32]=blot_source_identity::digest;
fn inferenceBudget()->u64 {return blot_inference_limits::configured();}
fn configureInferenceBudget(limit:u64)->Error {
 let error=blot_inference_limits::configure(limit);if error!=Error.none {return error;}blot_process_pool::configureBudget(limit);configured_identity=blot_source_identity::digest;
 if limit!=blot_source_identity::inference_budget {var hash=blot_support_blake3::init();hash.update(blot_source_identity::digest);hash.update("inference-budget");var bytes:u8[8]=[0;8];blot_bytes::put_u64(bytes,0,limit);hash.update(bytes);configured_identity=hash.final();}return Error.none;
}
export "blot_goose_main" fn mainEntry()->i32 {
 let configured=configureInferenceBudget(blot_source_identity::inference_budget);if configured!=Error.none {return failure(configured);}
 var arguments,error=blot_cli::readArguments();if error!=Error.none {return failure(error);}let success,error=blot_cli::run(arguments.items);arguments.deinit();blot_process_pool::shutdown();if error!=Error.none {return failure(error);}if success {return 0;}return 1;
}
fn failure(error:Error)->i32 {var text:u8[>..<]=[];text.append("blotc: ");text.append(blot_error::error_name(error));text.push('\n');blot_io::write_all(blot_io::Writer{2},text[:]);return 1;}
