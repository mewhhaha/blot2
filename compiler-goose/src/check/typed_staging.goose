// Compile-time #run and @build.read opcodes.
namespace blot_check_typed_staging;
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
fn opFromCode(code: u32) -> Op, blot_error::Error {
    match code {
        8 => { return Op.evaluate, blot_error::Error.none; },
        9 => { return Op.read_input, blot_error::Error.none; },
        _ => { return Op.evaluate, blot_error::Error.invalid_artifact; },
    }
}

fn blot_structural::equal(left: blot_check_typed_staging::Op, right: blot_check_typed_staging::Op) -> bool { return left == right; }
fn blot_check_typed_staging::blotStructuralHash<S>(value: blot_check_typed_staging::Op,sink: S&) { blot_structural::hash(sink, blot_check_typed_staging::opCode(value) as! u32); }
