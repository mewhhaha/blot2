// Closed particle-source/Core fixture, not general K1 source admission or a
// portable artifact. The supplied Context identifies compiler-owned symbolic
// values in one trusted job; integers do not grant region/loan/domain authority.
// This subset assumes independently established immutable input, exclusive
// builder, independently established disjoint input/output storage ranges,
// and a preflighted host. The formal Region binder IDs must be distinct as
// syntax symbols, but their actual backing owner may be the same only when
// checked range and loan evidence establishes this premise.
namespace particle_source_core;
struct Context {
    owner:u32=0, input:u32=0, input_version:u32=0, input_region:u32=0, input_domain:u32=0, length:u32=0,
    dt:u32=0, dt_version:u32=0, builder:u32=0, builder_version:u32=0, output_region:u32=0, capacity:u32=0,
    index:u32=0, next_builder:u32=0, next_version:u32=0, result:u32=0, result_version:u32=0, result_domain:u32=0
}
struct Span { start:i64=0, end:i64=0 }
struct Sites {
    requires_site:Span=Span {}, for_site:Span=Span {}, invariant_site:Span=Span {}, next_site:Span=Span {},
    append_site:Span=Span {}, read:Span[4]=[Span {};4], field:Span[4]=[Span {};4],
    add:Span[2]=[Span {};2], mul:Span[2]=[Span {};2], freeze_site:Span=Span {}, return_site:Span=Span {}
}
// Rules: 1 Le(n,c) precondition; 2 Init(b)=i loop invariant; 3 i<n
// body edge; 4 Init(b)<c from 1/2/3; 5 next Init=i+1; 6 natural
// exhaustion returns exactly n. These are fixture-owned records, not a
// general K1 proof solver, evidence receipt or authenticated artifact.
struct Evidence { rule:u32=0, owner:u32=0, left:u32=0, right:u32=0, version:u32=0, dep1:u32=0,dep2:u32=0,dep3:u32=0,site:i64=0 }
// Ops: 1 field read, 2 f32.mul, 3 f32.add, 4 row product, 5 builder append,
// 6 next, 7 freeze, 8 return. Child refs are one-based op IDs. The dt input is
// a trusted context symbol, not an op. All source reads link the exact view,
// version/domain/index and the true-edge bounds evidence.
struct Op { kind:u32=0, owner:u32=0, a:u32=0, b:u32=0, symbol:u32=0, version:u32=0, output:u32=0, output_version:u32=0,
    index:u32=0, domain:u32=0, field:u32=0, proof:u32=0, site:i64=0, field_site:i64=0 }
struct Core { source:u8[]=[], context:Context=Context {}, sites:Sites=Sites {}, evidence:Evidence[6]=[Evidence {};6], ops:Op[13]=[Op {};13] }
fn context_valid(c:Context) -> bool {
    let ids:u32[18]=[c.owner,c.input,c.input_version,c.input_region,c.input_domain,c.length,c.dt,c.dt_version,c.builder,c.builder_version,
        c.output_region,c.capacity,c.index,c.next_builder,c.next_version,c.result,c.result_version,c.result_domain];
    for i in ids.len { if ids[i]==0 { return false; } for j in i { if ids[i]==ids[j] { return false; } } }
    return true;
}
fn same_context(a:Context,b:Context) -> bool {
    return a.owner==b.owner && a.input==b.input && a.input_version==b.input_version && a.input_region==b.input_region &&
        a.input_domain==b.input_domain && a.length==b.length && a.dt==b.dt && a.dt_version==b.dt_version &&
        a.builder==b.builder && a.builder_version==b.builder_version && a.output_region==b.output_region &&
        a.capacity==b.capacity && a.index==b.index && a.next_builder==b.next_builder && a.next_version==b.next_version &&
        a.result==b.result && a.result_version==b.result_version && a.result_domain==b.result_domain;
}
fn proofs(c:Context,s:Sites) -> Evidence[6] {
    return [
        Evidence {rule:1,owner:c.owner,left:c.length,right:c.capacity,site:s.requires_site.start},
        Evidence {rule:2,owner:c.owner,left:c.builder,right:c.index,version:c.builder_version,site:s.invariant_site.start},
        Evidence {rule:3,owner:c.owner,left:c.index,right:c.length,version:c.input_version,site:s.for_site.start},
        Evidence {rule:4,owner:c.owner,left:c.builder,right:c.capacity,version:c.builder_version,dep1:1,dep2:2,dep3:3,site:s.append_site.start},
        Evidence {rule:5,owner:c.owner,left:c.next_builder,right:c.index,version:c.next_version,dep1:2,dep2:4,site:s.next_site.start},
        Evidence {rule:6,owner:c.owner,left:c.result,right:c.length,version:c.result_version,dep1:2,dep2:5,site:s.return_site.start}
    ];
}
fn operations(c:Context,s:Sites) -> Op[13] {
    return [
        Op {kind:1,owner:c.owner,symbol:c.input,version:c.input_version,index:c.index,domain:c.input_domain,field:0,proof:3,site:s.read[0].start,field_site:s.field[0].start},
        Op {kind:1,owner:c.owner,symbol:c.input,version:c.input_version,index:c.index,domain:c.input_domain,field:2,proof:3,site:s.read[1].start,field_site:s.field[1].start},
        Op {kind:2,owner:c.owner,a:2,symbol:c.dt,version:c.dt_version,site:s.mul[0].start},
        Op {kind:3,owner:c.owner,a:1,b:3,site:s.add[0].start},
        Op {kind:1,owner:c.owner,symbol:c.input,version:c.input_version,index:c.index,domain:c.input_domain,field:1,proof:3,site:s.read[2].start,field_site:s.field[2].start},
        Op {kind:1,owner:c.owner,symbol:c.input,version:c.input_version,index:c.index,domain:c.input_domain,field:3,proof:3,site:s.read[3].start,field_site:s.field[3].start},
        Op {kind:2,owner:c.owner,a:6,symbol:c.dt,version:c.dt_version,site:s.mul[1].start},
        Op {kind:3,owner:c.owner,a:5,b:7,site:s.add[1].start},
        Op {kind:4,owner:c.owner,a:4,b:8,site:s.append_site.start},
        Op {kind:5,owner:c.owner,a:9,symbol:c.builder,version:c.builder_version,output:c.next_builder,output_version:c.next_version,proof:4,site:s.append_site.start},
        Op {kind:6,owner:c.owner,symbol:c.next_builder,version:c.next_version,output:c.builder,output_version:c.builder_version,proof:5,site:s.next_site.start},
        Op {kind:7,owner:c.owner,symbol:c.builder,version:c.builder_version,output:c.result,output_version:c.result_version,domain:c.result_domain,proof:6,site:s.freeze_site.start},
        Op {kind:8,owner:c.owner,symbol:c.result,version:c.result_version,domain:c.result_domain,site:s.return_site.start}
    ];
}
fn same_span(a:Span,b:Span)->bool { return a.start==b.start && a.end==b.end; }
fn same_sites(a:Sites,b:Sites)->bool {
    if !same_span(a.requires_site,b.requires_site)||!same_span(a.for_site,b.for_site)||!same_span(a.invariant_site,b.invariant_site)||
       !same_span(a.next_site,b.next_site)||!same_span(a.append_site,b.append_site)||!same_span(a.freeze_site,b.freeze_site)||!same_span(a.return_site,b.return_site) {return false;}
    for i in 4 { if !same_span(a.read[i],b.read[i]) || !same_span(a.field[i],b.field[i]) {return false;} }
    for i in 2 { if !same_span(a.add[i],b.add[i]) || !same_span(a.mul[i],b.mul[i]) {return false;} }
    return true;
}
fn same_evidence(a:Evidence,b:Evidence)->bool {
    return a.rule==b.rule && a.owner==b.owner && a.left==b.left && a.right==b.right && a.version==b.version &&
        a.dep1==b.dep1 && a.dep2==b.dep2 && a.dep3==b.dep3 && a.site==b.site;
}
fn same_op(a:Op,b:Op)->bool {
    return a.kind==b.kind && a.owner==b.owner && a.a==b.a && a.b==b.b && a.symbol==b.symbol && a.version==b.version &&
        a.output==b.output && a.output_version==b.output_version && a.index==b.index && a.domain==b.domain &&
        a.field==b.field && a.proof==b.proof && a.site==b.site && a.field_site==b.field_site;
}
