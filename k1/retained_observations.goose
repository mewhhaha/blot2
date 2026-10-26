// Private exact-observation comparison model. The caller supplies a trusted
// complete current-world view; this module does not read modules, discover
// dependencies, authenticate that view, or record compiler-policy receipts.
// A failed or unsupported comparison declines optional reuse. It never changes
// source acceptance and never treats matching digests as identity.
namespace retained_observations;

// Kinds: 1 interface, 2 body, 3 static value, 4 ABI/layout, 5 capture graph,
// 6 operation/provider, 7 source origin, 8 compiler policy, 9 recursion fact.
struct Entry { kind: i64 = 0, key: u8[] = [], value: u8[] = [] }
struct Observation { kind: i64 = 0, key: u8[] = [], found: bool = false, value: u8[] = [] }
// status: 0 match, 1 changed, 2 malformed/unsupported, 3 optional work limit.
struct Result { status: i64 = 2, visits: i64 = 0, bytes: i64 = 0 }

fn valid_kind(k: i64) -> bool { return k >= 1 && k <= 9; }
fn bounded(n: i64) -> bool { return n >= 0 && n <= 16777216; }
fn charge_bytes(current: i64, n: i64) -> i64 {
    if !bounded(n) || current < 0 || current > 134217728 || n > 134217728 - current { return -1; }
    return current + n;
}
// Each observation and each current-world candidate costs a visit. Matching
// key/value bytes are separately bounded to keep optional comparison bounded.
// Duplicate matching entries are ambiguous and decline. Exact key and value
// bytes, kind, and positive/negative presence all matter. Repeated observations
// are allowed and retain their input order. No input is mutated or allocated.
fn compare(observations: Observation[:], entries: Entry[:]) -> Result {
    var visits: i64 = 0; var bytes: i64 = 0;
    for o in observations {
        if visits == 4096 { return Result { status: 3, visits: visits, bytes: bytes }; }
        visits += 1;
        if !valid_kind(o.kind) || !bounded(o.key.len) || o.key.len == 0 ||
           !bounded(o.value.len) || (!o.found && o.value.len != 0) {
            return Result { status: 2, visits: visits, bytes: bytes };
        }
        var found = false; var matched = false;
        for e in entries {
            if visits == 4096 { return Result { status: 3, visits: visits, bytes: bytes }; }
            visits += 1;
            if !valid_kind(e.kind) || !bounded(e.key.len) || e.key.len == 0 || !bounded(e.value.len) {
                return Result { status: 2, visits: visits, bytes: bytes };
            }
            if e.kind != o.kind || e.key.len != o.key.len { continue; }
            bytes = charge_bytes(bytes, e.key.len);
            if bytes < 0 { return Result { status: 3, visits: visits, bytes: 134217728 }; }
            if e.key[..] != o.key[..] { continue; }
            if found { return Result { status: 2, visits: visits, bytes: bytes }; }
            found = true;
            if e.value.len != o.value.len { continue; }
            bytes = charge_bytes(bytes, e.value.len);
            if bytes < 0 { return Result { status: 3, visits: visits, bytes: 134217728 }; }
            matched = e.value[..] == o.value[..];
        }
        if found != o.found || (found && !matched) { return Result { status: 1, visits: visits, bytes: bytes }; }
    }
    return Result { status: 0, visits: visits, bytes: bytes };
}
