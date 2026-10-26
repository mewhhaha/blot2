// Private source-fragment proof model. IDs name compiler-supplied symbolic
// fixture values; raw integers do not establish K1 authority, an actual View,
// domain freshness, ownership or a complete function/interface contract.
namespace bounds_core;
struct Context {
    owner: u32 = 0, view: u32 = 0, view_version: u32 = 0,
    index: u32 = 0, index_version: u32 = 0, length: u32 = 0, domain: u32 = 0
}
struct Evidence {
    rule: u32 = 0, owner: u32 = 0, view: u32 = 0, view_version: u32 = 0,
    index: u32 = 0, index_version: u32 = 0, length: u32 = 0, domain: u32 = 0,
    guard_start: i64 = 0, true_read_start: i64 = 0
}
struct Span { start: i64 = 0, end: i64 = 0 }
struct Program {
    source: u8[] = [], context: Context = Context {}, evidence: Evidence = Evidence {},
    branch: Span = Span {}, guard_index: Span = Span {}, guard_view: Span = Span {},
    guard_length: Span = Span {}, read_view: Span = Span {}, read_index: Span = Span {},
    fallback_span: Span = Span {}, fallback: u32 = 0
}
fn context_valid(c: Context) -> bool {
    return c.owner != 0 && c.view != 0 && c.view_version != 0 && c.index != 0 &&
           c.index_version != 0 && c.length != 0 && c.domain != 0;
}
fn same_context(a: Context, b: Context) -> bool {
    return a.owner == b.owner && a.view == b.view && a.view_version == b.view_version &&
           a.index == b.index && a.index_version == b.index_version && a.length == b.length && a.domain == b.domain;
}
fn evidence_for(c: Context, branch: i64, read: i64) -> Evidence {
    return Evidence { rule: 1, owner: c.owner, view: c.view, view_version: c.view_version,
        index: c.index, index_version: c.index_version, length: c.length, domain: c.domain,
        guard_start: branch, true_read_start: read };
}
fn same_evidence(a: Evidence, b: Evidence) -> bool {
    return a.rule == b.rule && a.owner == b.owner && a.view == b.view && a.view_version == b.view_version &&
        a.index == b.index && a.index_version == b.index_version && a.length == b.length && a.domain == b.domain &&
        a.guard_start == b.guard_start && a.true_read_start == b.true_read_start;
}
fn same_span(a: Span, b: Span) -> bool { return a.start == b.start && a.end == b.end; }
