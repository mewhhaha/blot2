// Closed U32 copy-into loop Core. This is a private source-bound subset, not
// general K1 type/effect/borrow checking or a portable checked function. IDs
// are compiler-owned fixture symbols supplied by a trusted caller. They cannot
// be manufactured by source values or used as runtime region/domain tags.
namespace loop_core;
struct Context {
    owner: u32 = 0, input: u32 = 0, input_version: u32 = 0, input_region: u32 = 0, input_domain: u32 = 0,
    length: u32 = 0, builder: u32 = 0, builder_version: u32 = 0, output_region: u32 = 0,
    capacity: u32 = 0, index: u32 = 0, next_builder: u32 = 0, next_version: u32 = 0,
    result: u32 = 0, result_version: u32 = 0
}
struct Span { start: i64 = 0, end: i64 = 0 }
struct Sites { requires_site: Span = Span {}, for_site: Span = Span {}, invariant_site: Span = Span {},
    next_site: Span = Span {}, append_site: Span = Span {}, read_site: Span = Span {}, return_site: Span = Span {} }
// Rule IDs: 1 Le(n,c), 2 Eq(Init(b),i), 3 Lt(i,n) at body edge,
// 4 Lt(Init(b),c) from 1/2/3, 5 Eq(Init(b_next),i+1) after append,
// 6 Eq(Init(result),n) on natural exhaustion of this no-stop loop.
// Dependencies and source sites are fixed before lowering. This is not a
// general proof solver or authenticated portable proof object.
struct Evidence { rule: u32 = 0, owner: u32 = 0, left: u32 = 0, right: u32 = 0, version: u32 = 0,
    dep1: u32 = 0, dep2: u32 = 0, dep3: u32 = 0, site: i64 = 0 }
// Source-bound operation IDs: 1 read, 2 append, 3 next edge, 4 return.
struct Op { kind: u32 = 0, owner: u32 = 0, input: u32 = 0, version: u32 = 0, output: u32 = 0, output_version: u32 = 0,
    index: u32 = 0, domain: u32 = 0, proof1: u32 = 0, proof2: u32 = 0, site: i64 = 0 }
struct Core { source: u8[] = [], context: Context = Context {}, sites: Sites = Sites {},
    evidence: Evidence[6] = [Evidence {};6], ops: Op[4] = [Op {};4] }
fn context_valid(c: Context) -> bool {
    // This closed model uses one namespace for compiler-owned symbols. It
    // deliberately rejects equal or zero IDs rather than inferring aliases.
    let ids: u32[15] = [c.owner,c.input,c.input_version,c.input_region,c.input_domain,c.length,c.builder,
        c.builder_version,c.output_region,c.capacity,c.index,c.next_builder,c.next_version,c.result,c.result_version];
    for i in ids.len {
        if ids[i] == 0 { return false; }
        for j in i { if ids[j] == ids[i] { return false; } }
    }
    return true;
}
fn same_context(a: Context, b: Context) -> bool {
    return a.owner == b.owner && a.input == b.input && a.input_version == b.input_version &&
        a.input_region == b.input_region && a.input_domain == b.input_domain && a.length == b.length &&
        a.builder == b.builder && a.builder_version == b.builder_version && a.output_region == b.output_region &&
        a.capacity == b.capacity && a.index == b.index && a.next_builder == b.next_builder && a.next_version == b.next_version &&
        a.result == b.result && a.result_version == b.result_version;
}
fn evidence(c: Context, s: Sites) -> Evidence[6] {
    return [
        Evidence { rule: 1, owner: c.owner, left: c.length, right: c.capacity, site: s.requires_site.start },
        Evidence { rule: 2, owner: c.owner, left: c.builder, right: c.index, version: c.builder_version, site: s.invariant_site.start },
        Evidence { rule: 3, owner: c.owner, left: c.index, right: c.length, version: c.input_version, site: s.for_site.start },
        Evidence { rule: 4, owner: c.owner, left: c.builder, right: c.capacity, version: c.builder_version, dep1: 1, dep2: 2, dep3: 3, site: s.append_site.start },
        Evidence { rule: 5, owner: c.owner, left: c.next_builder, right: c.index, version: c.next_version, dep1: 2, dep2: 4, site: s.next_site.start },
        Evidence { rule: 6, owner: c.owner, left: c.result, right: c.length, version: c.result_version, dep1: 2, dep2: 5, site: s.return_site.start }
    ];
}
fn ops(c: Context, s: Sites) -> Op[4] {
    return [
        Op { kind: 1, owner: c.owner, input: c.input, version: c.input_version, index: c.index, domain: c.input_domain, proof1: 3, site: s.read_site.start },
        Op { kind: 2, owner: c.owner, input: c.builder, version: c.builder_version, output: c.next_builder, output_version: c.next_version, proof1: 4, proof2: 2, site: s.append_site.start },
        Op { kind: 3, owner: c.owner, input: c.next_builder, version: c.next_version, output: c.builder, output_version: c.builder_version, proof1: 5, site: s.next_site.start },
        Op { kind: 4, owner: c.owner, input: c.builder, version: c.builder_version, output: c.result, output_version: c.result_version, proof1: 6, site: s.return_site.start }
    ];
}
fn same_evidence(a: Evidence, b: Evidence) -> bool {
    return a.rule == b.rule && a.owner == b.owner && a.left == b.left && a.right == b.right && a.version == b.version &&
        a.dep1 == b.dep1 && a.dep2 == b.dep2 && a.dep3 == b.dep3 && a.site == b.site;
}
fn same_op(a: Op, b: Op) -> bool {
    return a.kind == b.kind && a.owner == b.owner && a.input == b.input && a.version == b.version && a.output == b.output && a.output_version == b.output_version &&
        a.index == b.index && a.domain == b.domain && a.proof1 == b.proof1 && a.proof2 == b.proof2 && a.site == b.site;
}
