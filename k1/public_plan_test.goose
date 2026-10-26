import std;
import public_frontend;
import public_artifact;
import public_function;
import public_plan;
import blake3;
import catalog;
fn resign(bytes: u8[>..]&) {
    let digest = blake3::hash(bytes[16..bytes.len - 32]);
    for i in 32 { bytes[bytes.len - 32 + i] = digest[i]; }
}
fn main() {
    let abi: u8[32] = [7; 32]; let other_abi: u8[32] = [8; 32];
    assert(!public_plan::fits_function(-1));
    assert(public_plan::fits_function(16777216 - 88));
    assert(!public_plan::fits_function(16777216 - 88 + 1));
    assert(!public_plan::fits_function(9223372036854775807));
    let source = "pub let id: U32 -> U32 ! {} resources {depth: 3, frame: 64} = fn x => return x\n";
    let candidate = public_frontend::parse(source); assert(candidate.status == 0);
    let intf = public_artifact::encode(source, candidate, "pkg", "main.blot", "id", abi);
    let function = public_function::encode(source, candidate, intf, "pkg", "main.blot", "id", abi);
    let p = public_plan::encode(source, candidate, intf, function, "pkg", "main.blot", "id", abi, 275);
    assert(p.len > 0);
    let d = public_plan::decode(p, intf, function, "pkg", "main.blot", "id", abi, 275);
    assert(d.status == 0 && d.opcode == 0x20 && d.pages == 275);
    assert(public_plan::verify_source(p, source, candidate, intf, function, "pkg", "main.blot", "id", abi, 275) == 0);
    assert(public_plan::decode(p, intf, function, "pkg", "main.blot", "id", abi, 276).status != 0);
    assert(public_plan::decode(p, intf, function, "pkg", "main.blot", "id", other_abi, 275).status != 0);
    assert(public_plan::decode(p, intf, function, "bad", "main.blot", "id", abi, 275).status != 0);
    assert(public_plan::encode(source, candidate, intf, function, "pkg", "main.blot", "id", abi, 0).len == 0);
    assert(public_plan::encode(source, candidate, intf, function, "pkg", "main.blot", "id", abi, 16385).len == 0);
    for n in p.len { assert(public_plan::decode(p[..n], intf, function, "pkg", "main.blot", "id", abi, 275).status != 0); }
    for i in 16 + public_artifact::header_size() {
        var bad: u8[>..] = []; bad.append(p); bad[i] ^= 1;
        assert(public_plan::decode(bad, intf, function, "pkg", "main.blot", "id", abi, 275).status != 0);
    }
    var bad: u8[>..] = []; bad.append(p); bad[bad.len - 1] ^= 1;
    assert(public_plan::decode(bad, intf, function, "pkg", "main.blot", "id", abi, 275).status == 3);
    let field_start = p.len - 32 - 13 * 4;
    for field in 13 {
        var forged: u8[>..] = []; forged.append(p); forged[field_start + field * 4] ^= 1; resign(forged);
        assert(public_plan::decode(forged, intf, function, "pkg", "main.blot", "id", abi, 275).status != 0);
    }
    // Even under an equal (forced-collision) digest the complete linked
    // canonical bytes are required. A modified embedded body with the original
    // function digest is rejected after the enclosing plan is re-signed.
    var forged_link: u8[>..] = []; forged_link.append(p);
    forged_link[16 + public_artifact::header_size() + 76] ^= 1; resign(forged_link);
    assert(public_plan::decode(forged_link, intf, function, "pkg", "main.blot", "id", abi, 275).status != 0);
    let other = "pub let id: U32 -> U32 ! {} resources {depth: 3, frame: 64} = fn x => return 7\n";
    let other_candidate = public_frontend::parse(other);
    assert(public_plan::verify_source(p, other, other_candidate, intf, function, "pkg", "main.blot", "id", abi, 275) != 0);
    let comparison = "pub let less: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < 2";
    let c = public_frontend::parse(comparison);
    let ci = public_artifact::encode(comparison, c, "pkg", "main.blot", "less", abi);
    let cf = public_function::encode(comparison, c, ci, "pkg", "main.blot", "less", abi);
    let cp = public_plan::encode(comparison, c, ci, cf, "pkg", "main.blot", "less", abi, 275);
    assert(public_plan::decode(cp, ci, cf, "pkg", "main.blot", "less", abi, 275).opcode == 0x49);
    assert(public_plan::verify_source(cp, comparison, c, ci, cf, "pkg", "main.blot", "less", abi, 275) == 0);
    // Exact artifact-limit arithmetic, including both nested semantic links.
    let start = 16 + public_artifact::header_size();
    let interface_fixed = 9 + 5 * 4 + catalog::edition().len + catalog::semantic_policy().len + 18 * 4 + "main.blot".len + "id".len;
    let package_len = 16777216 - start - 128 - 157 - 32 - interface_fixed;
    var large: u8[>..] = [];
    for i in package_len { large.push('p'); }
    let li = public_artifact::encode(source, candidate, large, "main.blot", "id", abi);
    let lf = public_function::encode(source, candidate, li, large, "main.blot", "id", abi);
    let lp = public_plan::encode(source, candidate, li, lf, large, "main.blot", "id", abi, 275);
    assert(lp.len == 16777216);
    assert(public_plan::decode(lp, li, lf, large, "main.blot", "id", abi, 275).status == 0);
    large.push('p');
    let li2 = public_artifact::encode(source, candidate, large, "main.blot", "id", abi);
    let lf2 = public_function::encode(source, candidate, li2, large, "main.blot", "id", abi);
    let before_function = copy(lf2);
    assert(public_plan::encode(source, candidate, li2, lf2, large, "main.blot", "id", abi, 275).len == 0);
    assert(lf2[..] == before_function[..]);
    // Exceed the function envelope limit by one byte. Rejection must not
    // mutate the supplied artifact, source or ABI, even for malformed bytes.
    var oversized_interface: u8[>..] = []; oversized_interface.append(li2);
    while oversized_interface.len <= 16777216 - 197 { oversized_interface.push(0); }
    assert(oversized_interface.len == 16777216 - 197 + 1);
    let before_interface = copy(oversized_interface);
    assert(public_function::encode(source, candidate, oversized_interface, large, "main.blot", "id", abi).len == 0);
    assert(oversized_interface[..] == before_interface[..] && source[0] == 'p' && abi[0] == 7);
    print("public scalar plan envelope: passed");
}
