// Execute only after a separate complete source/Core check. Handles and loans
// are created internally and never accepted from caller integers. State must
// already be initialized with the shared trusted fixture clock and must not be
// copied, forged or concurrently used. This is not public K1 admission, a
// general borrow checker, a Wasm backend, or a checked payload alias.
namespace owned_program_runtime;
import owned_program_source;
import owned_program_verify;
import owned_scalar_runtime;
// 0 Ok, 1 Body(Cancelled), 2 Reserve(error), 3 invalid/preflight failure.
struct Result { status: u32 = 3, value: u32 = 0, reserve_error: i64 = 0 }
fn run(state: owned_scalar_runtime::State&, source: u8[:], core: owned_program_source::Core) -> Result {
    if !owned_program_verify::verify(source,core) || state.owner == 0 || state.slot != 0 || state.loan_count != 0 ||
       state.next_loan == 18446744073709551615 || state.stamp == 18446744073709551615 ||
       (core.moved && state.stamp == 18446744073709551614) { return Result {}; }
    let made = owned_scalar_runtime::construct(state, source[core.owned_start..core.owned_end], core.owned);
    if made.status == 1 { return Result { status:1 }; }
    if made.status == 3 { return Result { status:2, reserve_error:made.reserve_error }; }
    if made.status != 0 { return Result {}; }
    var handle = made.handle;
    if core.moved {
        let moved = owned_scalar_runtime::move(state,handle);
        assert(moved.status == 0); handle = moved.handle;
    }
    let opened = owned_scalar_runtime::open(state,handle);
    assert(opened.status == 0);
    let value = opened.value; // U32 cannot retain the opening or hidden region.
    assert(owned_scalar_runtime::end_open(state,handle,opened.loan).status == 0);
    assert(owned_scalar_runtime::close(state,handle).status == 0);
    return Result { status:0, value:value };
}
