// Candidate-only encoder. A caller must independently verify source, Core,
// evidence and output bytes before publishing it. Not a public K1 ABI.
namespace increment_wasm;
fn section(out: u8[>..]&, id: u8, payload: u8[:]) { out.push(id); out.push(payload.len as u8); out.append(payload); }
fn encode() -> u8[] {
    var out: u8[>..] = [0,97,115,109,1,0,0,0];
    let type_section: u8[7] = [1,96,2,127,127,1,127];
    let function_section: u8[2] = [1,0];
    let export_section: u8[7] = [1,3,'r','u','n',0,0];
    // local.get 1; i32.const -1; i32.lt_u; if i32
    //   local.get 1; i32.const 1; i32.add
    // else local.get 1; end; end
    let code_section: u8[20] = [1,18,0,32,1,65,127,73,4,127,32,1,65,1,106,5,32,1,11,11];
    section(out,1,type_section); section(out,3,function_section);
    section(out,7,export_section); section(out,10,code_section);
    return copy(out);
}
