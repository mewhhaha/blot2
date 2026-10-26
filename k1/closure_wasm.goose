// Private test-only closure module; it cannot admit or export K1 functions.
// A synchronous `run(capture,arg,capacity)->i64` preflights four frame bytes;
// -1 signals insufficient capacity. Otherwise it writes one U32 capture into
// a bounded local frame, constructs fixed code/env operands and call_indirects
// the canonical (env,arg)->U32 worker. Return values zero-extend into i64.
// The fixed address/table are test geometry, not the K1 runtime frame arena.
// There are no imports, memory.grow, allocation, or host callback/reentrancy.
namespace closure_wasm;
import closure_core;
import closure_validate;
import closure_wasm_validate;
fn section(out: u8[>..]&, id: u8, payload: u8[:]) { out.push(id); out.push(payload.len as u8); out.append(payload); }
fn emit(source: u8[:], core: closure_core::Core&) -> u8[] {
    if !closure_validate::verify(source,core) { return []; }
    var out: u8[>..] = [0,97,115,109,1,0,0,0];
    let types: u8[14] = [2,96,2,127,127,1,127,96,3,127,127,127,1,126];
    let functions: u8[3] = [2,0,1];
    let table: u8[4] = [1,112,0,1];
    let memory: u8[4] = [1,1,1,1];
    let exports: u8[7] = [1,3,'r','u','n',0,1];
    let element: u8[7] = [1,0,65,0,11,1,0];
    let code: u8[45] = [2,10,0,32,0,40,2,0,32,1,113,11,
        32,0,32,2,65,4,73,4,64,66,127,15,11,65,128,8,32,0,54,2,0,
        65,128,8,32,1,65,0,17,0,0,173,11];
    section(out,1,types); section(out,3,functions); section(out,4,table);
    section(out,5,memory); section(out,7,exports); section(out,9,element); section(out,10,code);
    if !closure_wasm_validate::verify(source,core,out) { return []; }
    return copy(out);
}
