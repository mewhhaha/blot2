// Exact-byte target checker for one private guarded-increment module. The
// allowlist includes unsigned comparison, the then-only addition and the else
// return. It is not a general Wasm decoder, manifest or runtime certificate.
namespace increment_target;
fn verify(bytes: u8[:]) -> bool {
    let expected: u8[52] = [0,97,115,109,1,0,0,0,1,7,1,96,2,127,127,1,127,
        3,2,1,0,7,7,1,3,114,117,110,0,0,10,20,1,18,0,32,1,65,127,73,4,127,
        32,1,65,1,106,5,32,1,11,11];
    return bytes == expected[..];
}
