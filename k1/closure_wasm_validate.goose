// Independent exact structural allowlist for one fixed private test module.
// This checks every byte, including fixed table, signatures, memory, element,
// preflight, capture store, indirect call and worker instructions. It is not
// the K1 ABI structural certificate and accepts no general Wasm modules.
namespace closure_wasm_validate;
import closure_core;
import closure_validate;
fn verify(source: u8[:], core: closure_core::Core&, bytes: u8[:]) -> bool {
    if !closure_validate::verify(source,core) { return false; }
    let golden: u8[106] = [
        0,97,115,109,1,0,0,0,1,14,2,96,2,127,127,1,127,96,3,127,127,127,1,126,
        3,3,2,0,1,4,4,1,112,0,1,5,4,1,1,1,1,7,7,1,3,114,117,110,0,1,
        9,7,1,0,65,0,11,1,0,10,45,2,10,0,32,0,40,2,0,32,1,113,11,
        32,0,32,2,65,4,73,4,64,66,127,15,11,65,128,8,32,0,54,2,0,
        65,128,8,32,1,65,0,17,0,0,173,11
    ];
    return bytes == golden[..];
}
