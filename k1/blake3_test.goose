import blake3;
import std;

fn hex(bytes: u8[32]) -> u8[>..] {
    let digits = "0123456789abcdef";
    var result: u8[>..] = [];
    for b in bytes { result.push(digits[b / 16]); result.push(digits[b % 16]); }
    return result;
}
fn check(length: i64, expected: u8[:]) {
    var input: u8[>..] = [];
    for i in length { input.push((i % 251) as u8); }
    if hex(blake3::hash(input)) != expected { abort(str("BLAKE3 vector failed at ", length)); }
}
fn main() {
    check(0, "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262");
    check(1, "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213");
    check(1023, "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11");
    check(1024, "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7");
    check(1025, "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444");
    check(2048, "e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a");
    check(2049, "5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030");
    assert(hex(blake3::hash("abc")) == "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85");
    print("BLAKE3 official vectors passed");
}
