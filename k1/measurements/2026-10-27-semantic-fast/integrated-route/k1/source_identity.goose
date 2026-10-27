// Private logical-path and source-identity model. This module performs no
// filesystem access and never authorizes opening a path. In particular, lexical
// normalization does not detect symlinks: an untrusted path must not be opened
// until a separate descriptor-relative, no-escape filesystem resolver has
// established package-root containment. Package identity is a trusted caller
// expectation, not an authority inferred from a host path or digest.
namespace source_identity;
import lexer;
import public_interface;
import blake3;

struct Normalized { status: i64 = 1, path: u8[] = [] }
struct Source {
    package: u8[] = [], module: u8[] = [], declaration: u8[] = [],
    bytes: u8[] = [], fingerprint_domain: u32 = 0, fingerprint: u8[32] = [0; 32]
}
struct Result { status: i64 = 1, source: Source = Source {} }

fn owned(s: u8[:]) -> u8[>..] { var out: u8[>..] = []; out.append(s); return out; }
fn drive_prefix(s: u8[:]) -> bool {
    return s.len >= 2 && ((s[0] >= 'a' && s[0] <= 'z') || (s[0] >= 'A' && s[0] <= 'Z')) && s[1] == ':';
}
// Normalize a decoded relative import against the importing module's canonical
// package-relative path. Returns 0 on success, 1 malformed/unsupported path,
// 2 parent escape, 3 source/path size limit. This only produces a logical name.
// No Unicode or case folding occurs. Repeated/trailing separators and final
// dot segments are outside this narrow model rather than silently interpreted.
fn normalize_import(base: u8[:], relative: u8[:]) -> Normalized {
    if base.len > 16777216 || relative.len > 16777216 { return Normalized { status: 3 }; }
    if !public_interface::module_valid(base) || relative.len == 0 ||
       lexer::invalid_utf8(relative) >= 0 || relative[0] == '/' ||
       relative[relative.len - 1] == '/' || drive_prefix(relative) { return Normalized {}; }
    for c in relative { if c == 0 || c == '\\' { return Normalized {}; } }
    var prefix: i64 = 0;
    for c, i in base { if c == '/' { prefix = i; } }
    var out: u8[>..<] = [];
    if prefix != 0 { out.append(base[..prefix]); }
    var start: i64 = 0;
    while start < relative.len {
        var end = start;
        while end < relative.len && relative[end] != '/' { end += 1; }
        if end == start { return Normalized {}; }
        let part = relative[start..end];
        if part == "." || part == ".." {
            if end == relative.len { return Normalized {}; }
            if part == ".." {
                if out.len == 0 { return Normalized { status: 2 }; }
                while out.len > 0 && out[out.len - 1] != '/' { out.pop(); }
                if out.len > 0 { out.pop(); }
            }
        } else {
            let separator: i64 = if out.len == 0 { 0 } else { 1 };
            if out.len > 16777216 - separator || part.len > 16777216 - out.len - separator {
                return Normalized { status: 3 };
            }
            if separator != 0 { out.push('/'); }
            out.append(part);
        }
        if end == relative.len { break; }
        start = end + 1;
    }
    if !public_interface::module_valid(out) { return Normalized {}; }
    return Normalized { status: 0, path: out };
}

// Build an owned source snapshot. Candidate lookup keys use the pair (domain 1,
// raw-byte digest); the tag keeps source keys distinct from semantic hashes.
// Neither the tag nor digest authorizes a lookup result.
// The package, canonical module and declaration are independently supplied by
// the caller. This constructor does not prove that they came from a resolver.
fn make(package: u8[:], module: u8[:], declaration: u8[:], source: u8[:]) -> Result {
    if source.len > 16777216 || !public_interface::identity_valid(package, module, declaration) ||
       lexer::invalid_utf8(source) >= 0 { return Result {}; }
    return Result { status: 0, source: Source { package: owned(package), module: owned(module),
        declaration: owned(declaration), bytes: owned(source), fingerprint_domain: 1, fingerprint: blake3::hash(source) } };
}
// Compare bytes and fingerprints, not just fingerprints. The helper permits
// forced-equal-digest controls without granting a digest source authority.
fn same_bytes(a: u8[:], digest_a: u8[:], b: u8[:], digest_b: u8[:]) -> bool {
    return digest_a.len == 32 && digest_b.len == 32 && digest_a == digest_b && a == b;
}
// Check against independent request data and exact owned source. A false caller
// expectation can still describe the wrong file: only an external trusted root
// resolver may establish the package/module/source origin.
fn verify(record: Source&, package: u8[:], module: u8[:], declaration: u8[:], expected_source: u8[:]) -> bool {
    if expected_source.len > 16777216 || record.bytes.len > 16777216 ||
       !public_interface::identity_valid(package, module, declaration) ||
       record.package[..] != package || record.module[..] != module || record.declaration[..] != declaration || record.fingerprint_domain != 1 ||
       lexer::invalid_utf8(expected_source) >= 0 { return false; }
    let digest = blake3::hash(expected_source);
    return same_bytes(record.bytes, record.fingerprint, expected_source, digest);
}
