import std;
import frontend;
import artifact;

fn main() {
    let source = "let id: U32 -> U32 = fn x => return x\n";
    let p = frontend::parse_scalar(source);
    assert(p.status == 0);
    let original = artifact::encode(source, p.start, p.end, p.name_start, p.name_end, p.kind, p.literal);
    assert(original.len > 0);
    let decoded = artifact::decode(original);
    assert(decoded.status == 0 && decoded.kind == 0);
    assert(original[decoded.source_start..decoded.source_end] == source);
    for n in original.len {
        assert(artifact::decode(original[0..n]).status != 0);
    }
    // Corrupt each header byte: every case is rejected before decoding spans.
    for i in artifact::header().len {
        var changed: u8[>..] = [];
        changed.append(original);
        changed[i] ^= 1;
        assert(artifact::decode(changed).status != 0);
    }
    // Edition/policy/ABI mismatches are distinguished from malformed magic.
    var incompatible: u8[>..] = [];
    incompatible.append(original);
    incompatible[9] ^= 1;
    assert(artifact::decode(incompatible).status == 2);
    var bad_magic: u8[>..] = [];
    bad_magic.append(original);
    bad_magic[0] ^= 1;
    assert(artifact::decode(bad_magic).status == 1);
    // Every field of the fixed scalar header has a bounds/meaning check.
    let h = artifact::header().len;
    for field in 7 {
        var changed: u8[>..] = [];
        changed.append(original);
        for j in 4 { changed[h + field * 4 + j] = 255; }
        assert(artifact::decode(changed).status != 0);
    }
    var changed: u8[>..] = [];
    changed.append(original);
    changed[changed.len - 2] = 'z';
    assert(artifact::decode(changed).status != 0);
    // A caller cannot serialize an inconsistent frontend representation.
    let forged = artifact::encode(source, p.start, p.end, p.name_start, p.name_end, 1, 42);
    assert(forged.len == 0);
    let number = "let n: U32 -> U32 = fn x => return 4294967295";
    let q = frontend::parse_scalar(number);
    assert(q.status == 0);
    let encoded = artifact::encode(number, q.start, q.end, q.name_start, q.name_end, q.kind, q.literal);
    let roundtrip = artifact::decode(encoded);
    assert(roundtrip.status == 0 && roundtrip.literal == 4294967295);
    print("scalar artifact tests passed");
}
