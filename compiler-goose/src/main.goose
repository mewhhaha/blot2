// C-host entry. Compiler logic remains ordinary Goose code.
namespace squid_main;
import config_state;
import driver.cli;
import source_identity;
import support.error;
import support.io;
type Error=squid_error::Error;
export "squid_goose_main" fn mainEntry()->i32 {
 let configured=squid_config_state::configureInferenceBudget(squid_source_identity::inference_budget);if configured!=squid_error::Error.none {return failure(configured);}
 var arguments,error=squid_cli::readArguments();if error!=squid_error::Error.none {return failure(error);}let success,error=squid_cli::run(arguments.items);arguments.deinit();if error!=squid_error::Error.none {return failure(error);}if success {return 0;}return 1;
}
fn failure(error:Error)->i32 {var text:u8[>..<]=[];text.append("squidc: ");text.append(squid_error::error_name(error));text.push('\n');squid_io::write_all(squid_io::Writer{2},text[..]);return 1;}
