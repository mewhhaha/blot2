import std;
import public_frontend;
import public_artifact;
import blake3;
import catalog;

fn resigned(bytes: u8[>..]&) {
    let digest = blake3::hash(bytes[16 + public_artifact::header_size()..bytes.len - 32]);
    for i in 32 { bytes[bytes.len - 32 + i] = digest[i]; }
}
fn main() {
    let abi: u8[32] = [7; 32];
    let wrong_abi: u8[32] = [8; 32];
    let one = "pub let id: U32 -> U32 ! {} resources {depth: 3, frame: 64} = fn x => return x\n";
    let other = "pub let id: U32 -> U32 ! {} resources {depth: 3, frame: 64} = fn x => return 7\n";
    let changed = "pub let id: U32 -> U32 ! {} resources {depth: 4, frame: 64} = fn x => return x\n";
    let a = public_frontend::parse(one);
    let b = public_frontend::parse(other);
    let c = public_frontend::parse(changed);
    assert(a.status == 0 && b.status == 0 && c.status == 0);
    let x = public_artifact::encode(one, a, "example", "src/main.blot", "id", abi);
    let y = public_artifact::encode(other, b, "example", "src/main.blot", "id", abi);
    assert(x.len > 0 && x[..] == y[..]); // Body and origins do not affect interface bytes.
    assert(public_artifact::decode(x, "example", "src/main.blot", "id", abi).status == 0);
    assert(public_artifact::decode(x, "example", "src/main.blot", "id", wrong_abi).status == 2);
    let changed_abi = public_artifact::encode(one, a, "example", "src/main.blot", "id", wrong_abi);
    assert(changed_abi[..] != x[..]);
    assert(changed_abi[changed_abi.len - 32..] == x[x.len - 32..]);
    assert(public_artifact::verify_source(x, one, a, "example", "src/main.blot", "id", abi) == 0);
    assert(public_artifact::verify_source(x, other, b, "example", "src/main.blot", "id", abi) == 0);
    assert(public_artifact::verify_source(x, changed, c, "example", "src/main.blot", "id", abi) != 0);
    assert(public_artifact::decode(x, "other", "src/main.blot", "id", abi).status != 0);
    assert(public_artifact::decode(x, "example", "../main.blot", "id", abi).status != 0);
    assert(public_artifact::decode(x, "example", "src/main.blot", "wrong", abi).status != 0);
    for n in x.len { assert(public_artifact::decode(x[..n], "example", "src/main.blot", "id", abi).status != 0); }
    for i in 16 {
        var bad: u8[>..] = []; bad.append(x); bad[i] ^= 1;
        assert(public_artifact::decode(bad, "example", "src/main.blot", "id", abi).status != 0);
    }
    for offset in public_artifact::header_size() {
        var bad: u8[>..] = []; bad.append(x); bad[16 + offset] ^= 1;
        assert(public_artifact::decode(bad, "example", "src/main.blot", "id", abi).status != 0);
    }
    // A corrupted payload or digest cannot pass; recomputing a digest still
    // cannot authorize an invalid field.
    var bad_digest: u8[>..] = []; bad_digest.append(x); bad_digest[bad_digest.len - 1] ^= 1;
    assert(public_artifact::decode(bad_digest, "example", "src/main.blot", "id", abi).status == 3);
    var forged: u8[>..] = []; forged.append(x);
    let fields = forged.len - 32 - 18 * 4;
    forged[fields] = 0; resigned(forged); // public visibility cannot be private
    assert(public_artifact::decode(forged, "example", "src/main.blot", "id", abi).status != 0);
    forged[fields] = 1; forged[fields + 8] = 7; resigned(forged); // invalid result type
    assert(public_artifact::decode(forged, "example", "src/main.blot", "id", abi).status != 0);
    // A valid but altered contract must be checked against fresh source.
    forged[fields + 8] = 1; forged[fields + 64] = 4; resigned(forged);
    assert(public_artifact::decode(forged, "example", "src/main.blot", "id", abi).status == 0);
    assert(public_artifact::verify_source(forged, one, a, "example", "src/main.blot", "id", abi) != 0);
    assert(public_artifact::verify_source(forged, changed, c, "example", "src/main.blot", "id", abi) == 0);
    let bool_source = "pub let less: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < 2";
    let d = public_frontend::parse(bool_source);
    let z = public_artifact::encode(bool_source, d, "example", "src/main.blot", "less", abi);
    assert(public_artifact::decode(z, "example", "src/main.blot", "less", abi).result_type == 2);
    assert(public_artifact::verify_source(z, bool_source, d, "example", "src/main.blot", "less", abi) == 0);
    // The complete serialized object, not merely its source or producer tuple,
    // is capped at 16 MiB. An exact-limit object round trips; one byte more
    // must fail before creating an owned interface or allocating the object.
    let fixed = 9 + 5 * 4 + catalog::edition().len + catalog::semantic_policy().len + 18 * 4 + 16 + 32 + public_artifact::header_size();
    let package_len = 16777216 - fixed - "src/main.blot".len - "id".len;
    var large: u8[>..] = [];
    for i in package_len { large.push('p'); }
    let maximum = public_artifact::encode(one, a, large, "src/main.blot", "id", abi);
    assert(maximum.len == 16777216);
    assert(public_artifact::decode(maximum, large, "src/main.blot", "id", abi).status == 0);
    large.push('p');
    let oversized = public_artifact::encode(one, a, large, "src/main.blot", "id", abi);
    assert(oversized.len == 0);
    print("public scalar semantic envelope: passed");
}
