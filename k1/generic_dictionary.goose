// Private bounded dictionary production for four reviewed layout shapes. The
// caller supplies a trusted, canonical semantic identity and compiler-assigned
// schema ID. Numeric IDs/flags alone never establish type or move authority.
namespace generic_dictionary;
import public_artifact;
import lexer;

struct Schema { kind: u32 = 0, words: u32 = 0, producer: u8[] = [] }
struct Dictionary { size: u32 = 0, alignment: u32 = 0, flags: u32 = 0, schema_id: u32 = 0 }
struct Result { status: i64 = 1, dictionary: Dictionary = Dictionary {}, schema: u8[] = [] }
fn valid_schema(s: Schema&) -> bool {
    if s.producer.len == 0 || s.producer.len > 256 || lexer::invalid_utf8(s.producer) >= 0 { return false; }
    for c in s.producer { if c == 0 { return false; } }
    if s.kind == 0 { return s.words == 0; } // Unit
    if s.kind == 1 { return s.words == 1; } // scalar (caller owns scalar validity)
    if s.kind == 2 { return s.words <= 64; } // flat product of U32 words
    if s.kind == 3 { return s.words == 2; } // affine two-word descriptor
    return false;
}
fn make(s: Schema&, id: u32) -> Result {
    if id == 0 || !valid_schema(s) { return Result {}; }
    var encoded: u8[>..] = []; encoded.append("K1GSC001");
    public_artifact::put32(encoded, s.kind); public_artifact::put32(encoded, s.words);
    public_artifact::put32(encoded, s.producer.len as u32); encoded.append(s.producer);
    let size = s.words * 4;
    let flags: u32 = if s.kind == 3 { 0 } else if size == 0 { 7 } else { 3 };
    let alignment: u32 = if size == 0 { 1 } else { 4 };
    return Result { status: 0, dictionary: Dictionary { size: size, alignment: alignment,
        flags: flags, schema_id: id }, schema: encoded };
}
