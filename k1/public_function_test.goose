import std;
import public_frontend;
import public_artifact;
import public_function;
import blake3;

fn resign(bytes: u8[>..]&) {
    let start = 16 + public_artifact::header_size();
    let end = bytes.len - 72;
    let digest = blake3::hash(bytes[start..end]);
    for i in 32 { bytes[end + i] = digest[i]; }
}
// Only owned serialized results leave this producer scope; the mutable source
// builder and parser state are gone before the caller validates them.
fn isolated(abi: u8[:]) -> u8[], u8[] {
    var source: u8[>..] = [];
    source.append("pub let id: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n");
    let c = public_frontend::parse(source);
    let interface = public_artifact::encode(source, c, "pkg", "main.blot", "id", abi);
    let function = public_function::encode(source, c, interface, "pkg", "main.blot", "id", abi);
    return interface, function;
}
fn main() {
    let abi: u8[32] = [7; 32];
    let bad_abi: u8[32] = [8; 32];
    assert(!public_function::fits_interface(-1));
    assert(public_function::fits_interface(16777216 - 197));
    assert(!public_function::fits_interface(16777216 - 197 + 1));
    assert(!public_function::fits_interface(9223372036854775807));
    let isolated_interface, isolated_function = isolated(abi);
    assert(public_function::decode(isolated_function, isolated_interface, "pkg", "main.blot", "id", abi).status == 0);
    let a_src = "pub let id: U32 -> U32 ! {} resources {depth: 3, frame: 64} = fn x => return x\n";
    let b_src = "pub let id: U32 -> U32 ! {} resources {depth: 3, frame: 64} = fn x => return 7\n";
    let c_src = "// source origin shifted\npub let id: U32 -> U32 ! {} resources {depth: 3, frame: 64} = fn x => return x\n";
    let a = public_frontend::parse(a_src); let b = public_frontend::parse(b_src); let c = public_frontend::parse(c_src);
    assert(a.status == 0 && b.status == 0 && c.status == 0);
    let interface = public_artifact::encode(a_src, a, "pkg", "main.blot", "id", abi);
    let f = public_function::encode(a_src, a, interface, "pkg", "main.blot", "id", abi);
    let changed_body = public_function::encode(b_src, b, interface, "pkg", "main.blot", "id", abi);
    let moved = public_function::encode(c_src, c, interface, "pkg", "main.blot", "id", abi);
    assert(f.len > 0 && changed_body.len == f.len && moved.len == f.len);
    let digest_offset = f.len - 72;
    assert(f[digest_offset..digest_offset + 32] != changed_body[digest_offset..digest_offset + 32]);
    assert(f[digest_offset..digest_offset + 32] == moved[digest_offset..digest_offset + 32]);
    assert(f[..] != moved[..]);
    assert(public_function::decode(f, interface, "pkg", "main.blot", "id", abi).status == 0);
    assert(public_function::verify_source(f, a_src, a, interface, "pkg", "main.blot", "id", abi) == 0);
    assert(public_function::verify_source(f, b_src, b, interface, "pkg", "main.blot", "id", abi) != 0);
    assert(public_function::verify_source(f, c_src, c, interface, "pkg", "main.blot", "id", abi) != 0);
    assert(public_function::verify_source(moved, c_src, c, interface, "pkg", "main.blot", "id", abi) == 0);
    assert(public_function::decode(f, interface, "pkg", "main.blot", "id", bad_abi).status != 0);
    assert(public_function::decode(f, interface, "wrong", "main.blot", "id", abi).status != 0);
    for n in f.len { assert(public_function::decode(f[..n], interface, "pkg", "main.blot", "id", abi).status != 0); }
    for i in 16 + public_artifact::header_size() {
        var bad: u8[>..] = []; bad.append(f); bad[i] ^= 1;
        assert(public_function::decode(bad, interface, "pkg", "main.blot", "id", abi).status != 0);
    }
    var bad: u8[>..] = []; bad.append(f); bad[digest_offset] ^= 1;
    assert(public_function::decode(bad, interface, "pkg", "main.blot", "id", abi).status == 3);
    var forged: u8[>..] = []; forged.append(f);
    let start = 16 + public_artifact::header_size();
    let interface_length = interface.len - 32 - (16 + public_artifact::header_size());
    let core_start = start + 13 + interface_length + 32;
    forged[core_start + 4] = 5; resign(forged); // impossible value count
    assert(public_function::decode(forged, interface, "pkg", "main.blot", "id", abi).status != 0);
    forged = []; forged.append(f); forged[forged.len - 40] ^= 1; // altered source origin is not semantic
    assert(public_function::decode(forged, interface, "pkg", "main.blot", "id", abi).status == 0);
    assert(public_function::verify_source(forged, a_src, a, interface, "pkg", "main.blot", "id", abi) != 0);
    // Even a newly signed, structurally valid but altered body cannot claim
    // correspondence with the original source. This covers all value fields.
    for field in 24 {
        var mutated: u8[>..] = []; mutated.append(f);
        mutated[core_start + 16 + field * 4] ^= 1;
        resign(mutated);
        assert(public_function::verify_source(mutated, a_src, a, interface, "pkg", "main.blot", "id", abi) != 0);
    }
    for offset in 40 {
        var mutated: u8[>..] = []; mutated.append(f); mutated[mutated.len - 40 + offset] ^= 1;
        assert(public_function::verify_source(mutated, a_src, a, interface, "pkg", "main.blot", "id", abi) != 0);
    }
    var wrong_link: u8[>..] = []; wrong_link.append(f); wrong_link[start + 13] ^= 1; resign(wrong_link);
    assert(public_function::decode(wrong_link, interface, "pkg", "main.blot", "id", abi).status != 0);
    let collision: u8[32] = [0; 32];
    assert(!public_function::same_link("interface-a", collision, "interface-b", collision));
    assert(public_function::same_link("interface-a", collision, "interface-a", collision));
    let bool_src = "pub let less: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < 2";
    let q = public_frontend::parse(bool_src);
    let qi = public_artifact::encode(bool_src, q, "pkg", "main.blot", "less", abi);
    let qf = public_function::encode(bool_src, q, qi, "pkg", "main.blot", "less", abi);
    assert(public_function::verify_source(qf, bool_src, q, qi, "pkg", "main.blot", "less", abi) == 0);
    print("public scalar function envelope: passed");
}
