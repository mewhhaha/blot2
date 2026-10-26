// Private source/Core adversarial agreement for the narrow Owned program.
import owned_scalar_runtime;
import owned_program_source;
import owned_program_verify;
import owned_program_runtime;
fn main() {
    let source = "let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,7)\ncase built:\n  #Err(e) => return #Err(e)\n  #Ok(h) => do:\n    let m = h\n    let value = owned.open(m) as s payload in do:\n      break payload\n    owned.close(m)\n    return #Ok(value)\n";
    let original = owned_program_source::parse(source);
    assert(original.status == 0 && owned_program_verify::verify(source,original.core));
    var clock = owned_scalar_runtime::Clock {};
    var accepted: i64 = 0; var rejected: i64 = 0;
    for pos in source.len {
        for replacement in [0, 10, 32, 35, 40, 41, 48, 49, 65, 95, 120, 255] {
            var bytes: u8[>..] = []; bytes.append(source); bytes[pos] = replacement as u8;
            let candidate = owned_program_source::parse(bytes);
            if candidate.status == 0 {
                accepted += 1;
                assert(owned_program_verify::verify(bytes,candidate.core));
                var state = owned_scalar_runtime::State {};
                assert(owned_scalar_runtime::initialize(state,clock));
                let result = owned_program_runtime::run(state,bytes,candidate.core);
                assert(result.status != 3 && state.slot == 0 && state.bitmap[0] == 0 && state.loan_count == 0);
            } else {
                rejected += 1;
                assert(!owned_program_verify::verify(bytes,original.core));
            }
            if !owned_program_verify::verify(bytes,original.core) {
                var state = owned_scalar_runtime::State {};
                assert(owned_scalar_runtime::initialize(state,clock));
                assert(owned_program_runtime::run(state,bytes,original.core).status == 3);
                assert(state.slot == 0 && state.slots[0].generation == 0 && state.bitmap[0] == 0);
            }
        }
    }
    assert(accepted > 0 && rejected > 0);
    print("owned program source mutation agreement passed");
}
