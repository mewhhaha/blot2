// Compile-time #run and @build.read opcodes.
namespace squid_check_typed_staging;
import .typed_staging_names;
import support.error;
import support.structural;

fn arity(op: Op) -> i64 { return 1; }

fn opCode(value: Op) -> u32 {
    match value {
        evaluate => { return 8; },
        read_input => { return 9; },
    }
}
fn opFromCode(code: u32) -> Op, squid_error::Error {
    match code {
        8 => { return Op.evaluate, squid_error::Error.none; },
        9 => { return Op.read_input, squid_error::Error.none; },
        _ => { return Op.evaluate, squid_error::Error.invalid_artifact; },
    }
}

fn squid_structural::equal(left: squid_check_typed_staging::Op, right: squid_check_typed_staging::Op) -> bool { return left == right; }
fn squid_check_typed_staging::squidStructuralHash<S>(value: squid_check_typed_staging::Op,sink: S&) { squid_structural::hash(sink, squid_check_typed_staging::opCode(value) as! u32); }
