// Independent decoder for the restricted dictionary component. Expected schema
// bytes and owner-local ID must be independently established by the caller.
namespace generic_dictionary_verify;
import lexer;
import generic_dictionary;

fn get32(bytes: u8[:], p: i64) -> u32 {
    if p < 0 || p > bytes.len || bytes.len - p < 4 { return 0; }
    return (bytes[p] as u32) | ((bytes[p + 1] as u32) << 8) |
        ((bytes[p + 2] as u32) << 16) | ((bytes[p + 3] as u32) << 24);
}
fn verify(candidate: generic_dictionary::Result&, expected_schema: u8[:], expected_id: u32) -> bool {
    let b = candidate.schema;
    if candidate.status != 0 || expected_id == 0 || candidate.dictionary.schema_id != expected_id ||
       b.len < 21 || b.len > 276 || b[..] != expected_schema || b[0..8] != "K1GSC001" { return false; }
    let kind = get32(b, 8); let words = get32(b, 12); let n = get32(b, 16);
    if n == 0 || n > 256 || n != b.len - 20 || lexer::invalid_utf8(b[20..]) >= 0 { return false; }
    for c in b[20..] { if c == 0 { return false; } }
    if (kind == 0 && words != 0) || (kind == 1 && words != 1) ||
       (kind == 2 && words > 64) || (kind == 3 && words != 2) || kind > 3 { return false; }
    let size = words * 4;
    var flags: u32 = 3;
    if kind == 3 { flags = 0; }
    else if size == 0 { flags = 7; }
    let alignment: u32 = if size == 0 { 1 } else { 4 };
    return candidate.dictionary.size == size && candidate.dictionary.alignment == alignment &&
        candidate.dictionary.flags == flags;
}
