import interface_candidate;
import catalog;

fn hex(bytes: u8[:]) -> u8[>..] {
    let digits = "0123456789abcdef";
    var result: u8[>..] = [];
    for b in bytes { result.push(digits[b / 16]); result.push(digits[b % 16]); }
    return result;
}

fn main() {
    var abi: u8[32] = [0; 32];
    for i in 32 { abi[i] = i as u8; }
    let zero: u8[32] = [0; 32];
    // Golden bytes independently assembled from the documented little-endian layout.
    let golden = "4b3141525430303101000100f5000000040000003000000001000000480000005e00000002000000a60000001300000003000000b90000003800000007000000f100000004000000020000006b310f0000004b312d53454d2d504f4c4943592d310f0000004b312d4f50542d504f4c4943592d310e0000004b312d5741534d33322d4142493100000000000000000000000000000000000000000000000000000000000000000100000070010000006d010000000100000078010000000100000001000000010000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000";
    let golden_bytes = interface_candidate::encode("p", "m", "x", zero);
    assert(hex(golden_bytes) == golden);
    assert(interface_candidate::validate(golden_bytes, "p", "m", "x", zero) == 0);
    assert(interface_candidate::get16(golden_bytes, -1) == 0);
    assert(interface_candidate::get32(golden_bytes, golden_bytes.len) == 0);
    let bytes = interface_candidate::encode("pkg:example", "src/main.blot", "answer", abi);
    let again = interface_candidate::encode("pkg:example", "src/main.blot", "answer", abi);
    assert(bytes.len > 72 && bytes == again);
    assert(interface_candidate::validate(bytes, "pkg:example", "src/main.blot", "answer", abi) == 0);
    assert(bytes[0..8] == "K1ART001" && bytes[8] == 1 && bytes[9] == 0 && bytes[10] == 1 && bytes[11] == 0);
    // Every possible truncation, each header/directory byte and every fixed
    // contract field must be rejected. The input is never decoded by offset.
    for n in bytes.len {
        assert(interface_candidate::validate(bytes[0..n], "pkg:example", "src/main.blot", "answer", abi) != 0);
    }
    for i in 72 {
        var changed: u8[>..] = []; changed.append(bytes); changed[i] ^= 1;
        assert(interface_candidate::validate(changed, "pkg:example", "src/main.blot", "answer", abi) != 0);
    }
    let versions_len = 16 + catalog::edition().len + catalog::semantic_policy().len +
        catalog::optimization_policy().len + catalog::wasm_abi().len + 32;
    var bad: u8[>..] = []; bad.append(bytes); bad[76] ^= 1;
    assert(interface_candidate::validate(bad, "pkg:example", "src/main.blot", "answer", abi) == 2);
    for i in 72 + versions_len..bytes.len {
        var changed: u8[>..] = []; changed.append(bytes); changed[i] ^= 1;
        assert(interface_candidate::validate(changed, "pkg:example", "src/main.blot", "answer", abi) != 0);
    }
    assert(interface_candidate::validate(bytes, "pkg:other", "src/main.blot", "answer", abi) != 0);
    assert(interface_candidate::validate(bytes, "pkg:example", "src/other.blot", "answer", abi) != 0);
    assert(interface_candidate::validate(bytes, "pkg:example", "src/main.blot", "other", abi) != 0);
    var different = abi; different[0] ^= 1;
    assert(interface_candidate::validate(bytes, "pkg:example", "src/main.blot", "answer", different) == 2);
    assert(interface_candidate::encode("", "m", "x", abi).len == 0);
    assert(interface_candidate::encode("pkg", "", "x", abi).len == 0);
    assert(interface_candidate::encode("pkg", "/m", "x", abi).len == 0);
    assert(interface_candidate::encode("pkg", "a//b", "x", abi).len == 0);
    assert(interface_candidate::encode("pkg", "a/../b", "x", abi).len == 0);
    assert(interface_candidate::encode("pkg", "a/./b", "x", abi).len == 0);
    assert(interface_candidate::encode("pkg", "a\\b", "x", abi).len == 0);
    assert(interface_candidate::encode("pkg", "C:/a", "x", abi).len == 0);
    assert(interface_candidate::encode("pkg", "m", "return", abi).len == 0);
    assert(interface_candidate::encode("pkg", "m", "9x", abi).len == 0);
    assert(interface_candidate::encode("pkg", "m", "x", abi[0..31]).len == 0);
    let invalid: u8[] = [255];
    assert(interface_candidate::encode(invalid, "m", "x", abi).len == 0);
    assert(interface_candidate::encode("pkg", invalid, "x", abi).len == 0);
    assert(interface_candidate::encode("pkg", "m/文.blot", "x", abi).len > 0);
    // Full object cap, not only component cap. One byte over is rejected.
    let max_package = 16777216 - (72 + versions_len + 16 + 1 + 1 + 56 + 4);
    var large: u8[>..] = [];
    for i in max_package { large.push('p'); }
    let exact = interface_candidate::encode(large, "m", "x", abi);
    assert(exact.len == 16777216);
    assert(interface_candidate::validate(exact, large, "m", "x", abi) == 0);
    large.push('p');
    assert(interface_candidate::encode(large, "m", "x", abi).len == 0);
    print("private interface envelope: passed");
}
