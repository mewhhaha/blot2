namespace squid_inference_limits;
import support.error;

var inference_budget: u64 = 1000000;
fn configured() -> u64 { inference_budget }
fn configure(value: u64) -> squid_error::Error {
    if value == 0 { return squid_error::Error.invalid_inference_budget; }
    inference_budget = value;
    return squid_error::Error.none;
}
