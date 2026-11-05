// Sparse pages retain copyable lexical facts and exact rollback-by-value.
namespace blot_check_package_row_facts;
import support.error;

struct Page { key: i64 = 0, bits: u64 = 0 }
struct Facts { pages: Page[128] = [Page {..}; 128] }
fn contains(self_: const Facts&, row: i64) -> bool {
    let key = (row >> 6) + 1; var position = (key - 1) % self_.pages.len;
    for attempt in self_.pages.len {
        let page = self_.pages[position]; if page.key == key { return page.bits & ((1 as u64) << (row & 63)) != 0; }
        if page.key == 0 { return false; } position = (position + 1) % self_.pages.len;
    }
    return false;
}
fn set(self_: Facts&, row: i64) -> blot_error::Error {
    let key = (row >> 6) + 1; var position = (key - 1) % self_.pages.len;
    for attempt in self_.pages.len {
        if self_.pages[position].key == 0 || self_.pages[position].key == key {
            self_.pages[position].key = key; self_.pages[position].bits |= (1 as u64) << (row & 63); return blot_error::Error.none;
        }
        position = (position + 1) % self_.pages.len;
    }
    return blot_error::Error.invalid_artifact;
}
fn unset(self_: Facts&, row: i64) {
    let key = (row >> 6) + 1; var position = (key - 1) % self_.pages.len;
    for attempt in self_.pages.len {
        if self_.pages[position].key == key { self_.pages[position].bits &= ~((1 as u64) << (row & 63)); return; }
        if self_.pages[position].key == 0 { return; } position = (position + 1) % self_.pages.len;
    }
}
fn eql(self_: const Facts&, other: const Facts&) -> bool {
    var own_count: i64 = 0; var other_count: i64 = 0;
    for page in self_.pages {
        if page.bits == 0 { continue; } own_count += 1; var matched = false;
        for candidate in other.pages { if candidate.key == page.key { matched = candidate.bits == page.bits; break; } }
        if !matched { return false; }
    }
    for page in other.pages { if page.bits != 0 { other_count += 1; } }
    return own_count == other_count;
}
