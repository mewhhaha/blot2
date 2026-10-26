// Private checked formatter for the currently admitted tagged fixture subset.
// Invalid/unsupported input or any round-trip disagreement returns no bytes.
namespace format_k1_formatter;
import compiler_frontend;
import format_k1_normalize;
import format_k1_check;
struct Result {status:i64=0,source:u8[]=[]}
// 0 success, 1 invalid/unsupported input, 2 independently detected mismatch.
// These are fixture statuses, not qualified K1 diagnostics or a public CLI.
fn format(source:u8[:]) -> Result {
    var before=compiler_frontend::parse(source);if before.status!=0 {return Result {status:1};}
    let formatted=format_k1_normalize::run(source);
    var after=compiler_frontend::parse(formatted);if after.status!=0 {return Result {status:2};}
    if !format_k1_check::equivalent(before.program,after.program) {return Result {status:2};}
    return Result {source:formatted};
}
