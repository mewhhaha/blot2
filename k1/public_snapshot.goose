// Private, owned snapshot for the narrow public-scalar experiment. Its source,
// producer bytes, interface, function and plan are owned copies, not borrowed
// checker or caller memory. This is NOT a K1 transaction, package resolver,
// authenticated ABI/manifest, host bridge, structural certificate or work
// receipt. A caller must establish expected producer/ABI independently.
namespace public_snapshot;
import public_frontend;
import public_interface;
import public_artifact;
import public_function;
import public_plan;
import public_fixture;

struct Snapshot {
    source: u8[] = [], package: u8[] = [], module: u8[] = [], declaration: u8[] = [],
    abi: u8[32] = [0; 32], interface: u8[] = [], function: u8[] = [], plan: u8[] = []
}
struct Result { status: i64 = 1, snapshot: Snapshot = Snapshot {} }
fn owned(s: u8[:]) -> u8[>..] { var out: u8[>..] = []; out.append(s); return out; }
// Input objects are already caller-owned. Check each size by comparison,
// without adding potentially overflowing lengths or allocating copies.
fn sizes_fit(source: i64, interface: i64, function: i64, plan: i64) -> bool {
    for n in [source, interface, function, plan] {
        if n < 0 || n > 16777216 { return false; }
    }
    return true;
}

// Exact producer and ABI values are supplied again by the request owner. The
// self-asserted fields in this record never authenticate themselves. The
// current fixture's fixed 275-page layout is not a qualified K1 target profile.
fn validate(s: Snapshot&, package: u8[:], module: u8[:], declaration: u8[:], abi: u8[:]) -> bool {
    if abi.len != 32 || !sizes_fit(s.source.len, s.interface.len, s.function.len, s.plan.len) ||
       !public_interface::identity_valid(package, module, declaration) ||
       s.package[..] != package || s.module[..] != module || s.declaration[..] != declaration ||
       s.abi[..] != abi { return false; }
    // Reconstruct a fresh frontend record solely from the owned source. Every
    // source-to-artifact check below independently re-recognizes that source;
    // no parse flag or caller-supplied serialized receipt grants authority.
    let candidate = public_frontend::parse(s.source);
    if candidate.status != 0 || !public_frontend::verify(s.source, candidate) { return false; }
    if public_artifact::verify_source(s.interface, s.source, candidate, package, module, declaration, abi) != 0 { return false; }
    if public_function::verify_source(s.function, s.source, candidate, s.interface, package, module, declaration, abi) != 0 { return false; }
    if public_plan::verify_source(s.plan, s.source, candidate, s.interface, s.function, package, module, declaration, abi, 275) != 0 { return false; }
    return true;
}

// This constructor builds all three objects privately and validates the owned
// snapshot before returning it. Failure publishes no partial snapshot. Host
// process allocation failure is not modeled or recovered by this experiment.
fn make(source: u8[:], package: u8[:], module: u8[:], declaration: u8[:], abi: u8[:]) -> Result {
    if abi.len != 32 || source.len > 16777216 || !public_interface::identity_valid(package, module, declaration) { return Result {}; }
    let candidate = public_frontend::parse(source);
    if candidate.status != 0 || !public_frontend::verify(source, candidate) { return Result {}; }
    let interface = public_artifact::encode(source, candidate, package, module, declaration, abi);
    if interface.len == 0 { return Result {}; }
    let function = public_function::encode(source, candidate, interface, package, module, declaration, abi);
    if function.len == 0 { return Result {}; }
    let plan = public_plan::encode(source, candidate, interface, function, package, module, declaration, abi, 275);
    if plan.len == 0 { return Result {}; }
    var abi_owned: u8[32] = [0; 32];
    for i in 32 { abi_owned[i] = abi[i]; }
    var snapshot = Snapshot { source: owned(source), package: owned(package), module: owned(module),
        declaration: owned(declaration), abi: abi_owned,
        interface: copy(interface), function: copy(function), plan: copy(plan) };
    if !validate(snapshot, package, module, declaration, abi) { return Result {}; }
    return Result { status: 0, snapshot: snapshot };
}

// Outputs fixture bytes only after rechecking the owned snapshot against fresh
// request expectations. Emission regenerates bytes; the snapshot carries none.
fn emit(s: Snapshot&, package: u8[:], module: u8[:], declaration: u8[:], abi: u8[:]) -> u8[] {
    if !validate(s, package, module, declaration, abi) { return []; }
    return public_fixture::emit(s.source, s.interface, s.function, s.plan,
                                package, module, declaration, abi);
}
