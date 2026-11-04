namespace blot_inference_limits;
import support.error;

var inference_budget: u64 = 1000000;
fn configured() -> u64 { inference_budget }
fn configure(value: u64) -> blot_error::Error {
    if value == 0 { return blot_error::Error.invalid_inference_budget; }
    inference_budget = value;
    return blot_error::Error.none;
}
