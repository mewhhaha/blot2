// Independent exact-format checker for the fixed one-worker execution
// fixture. This is not a general Wasm validator, K1 certificate or proof of
// callable provenance, initialization, exclusive loans or dynamic dictionary.
namespace generic_identity_wasm_verify;
import generic_identity;
import generic_identity_verify;
import generic_dictionary;
import generic_layout_plan;

fn verify(source: u8[:], body: generic_identity::Body, bytes: u8[:]) -> bool {
    if !generic_identity_verify::verify(source, body) { return false; }
    let name = source[body.name_start..body.name_end];
    if name.len == 0 || name.len > 114 || name == "memory" { return false; }
    let prefix: u8[28] = [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0,
        1, 8, 1, 0x60, 4, 0x7f, 0x7f, 0x7f, 0x7f, 0,
        3, 2, 1, 0, 5, 4, 1, 1, 1, 1];
    let tail: u8[19] = [10, 17, 1, 15, 0, 0x20, 1, 0x20, 3, 0x20, 2,
        0x28, 2, 0, 0xfc, 0x0a, 0, 0, 0x0b];
    if bytes.len != 62 + name.len || bytes[0..28] != prefix[..] ||
       bytes[28] != 7 || bytes[29] != name.len + 13 || bytes[30] != 2 || bytes[31] != 6 ||
       bytes[32..38] != "memory" || bytes[38] != 2 || bytes[39] != 0 || bytes[40] != name.len { return false; }
    let name_end = 41 + name.len;
    if bytes[41..name_end] != name || bytes[name_end] != 0 || bytes[name_end + 1] != 0 { return false; }
    return bytes[name_end + 2..] == tail[..];
}

// Composes independent source, exact expected dictionary and target checks
// for one trusted compiler request. Runtime dictionary bytes and slot/loan
// authority remain separate responsibilities of the caller.
fn verify_linked(source: u8[:], body: generic_identity::Body, concrete: generic_dictionary::Result&,
                 expected_schema: u8[:], expected_id: u32, bytes: u8[:]) -> bool {
    if generic_layout_plan::instantiate(source, body, concrete, expected_schema, expected_id).status != 0 { return false; }
    return verify(source, body, bytes);
}
