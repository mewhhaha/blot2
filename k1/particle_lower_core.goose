// Bounded source-bound particle expression/loop Core. It admits a fixed
// declaration and carry-loop contract but expression trees over source[i].F32
// fields and dt with +/* and parentheses. Context identities are trusted
// compiler-owned fixture symbols, not forgeable runtime brand/loan authority.
// General K1 parsing, type inference, ownership, ABI and C09 remain absent.
namespace particle_lower_core;
import particle_source_core;
struct Sites {
    requires_site:particle_source_core::Span=particle_source_core::Span {},
    for_site:particle_source_core::Span=particle_source_core::Span {},
    invariant_site:particle_source_core::Span=particle_source_core::Span {},
    next_site:particle_source_core::Span=particle_source_core::Span {},
    append_site:particle_source_core::Span=particle_source_core::Span {},
    freeze_site:particle_source_core::Span=particle_source_core::Span {},
    return_site:particle_source_core::Span=particle_source_core::Span {}
}
// kind 1 field read, 2 dt, 3 F32 mul, 4 F32 add. All IDs one-based and
// binary operands are earlier nodes. For kind 1, start/end span the complete
// source[i].field, field_start/end identify the field selector; symbol/version,
// domain/index and proof bind the exact checked input. Kind 2 binds exact dt
// symbol/version. Binary nodes use operator token spans and left/right IDs.
struct Node {kind:u32=0,start:i64=0,end:i64=0,field_start:i64=0,field_end:i64=0,field:u32=0,
    left:u32=0,right:u32=0,symbol:u32=0,version:u32=0,index:u32=0,domain:u32=0,proof:u32=0}
struct Core {source:u8[]=[],context:particle_source_core::Context=particle_source_core::Context {},sites:Sites=Sites {},
    proofs:particle_source_core::Evidence[6]=[particle_source_core::Evidence {};6],nodes:Node[]=[],x_root:u32=0,y_root:u32=0}
fn proof_sites(s:Sites)->particle_source_core::Sites {
    return particle_source_core::Sites {requires_site:s.requires_site,for_site:s.for_site,invariant_site:s.invariant_site,
        next_site:s.next_site,append_site:s.append_site,freeze_site:s.freeze_site,return_site:s.return_site};
}
fn same_node(a:Node,b:Node)->bool {
    return a.kind==b.kind && a.start==b.start && a.end==b.end && a.field_start==b.field_start && a.field_end==b.field_end &&
        a.field==b.field && a.left==b.left && a.right==b.right && a.symbol==b.symbol && a.version==b.version &&
        a.index==b.index && a.domain==b.domain && a.proof==b.proof;
}
fn same_sites(a:Sites,b:Sites)->bool {
    return particle_source_core::same_span(a.requires_site,b.requires_site) && particle_source_core::same_span(a.for_site,b.for_site) &&
        particle_source_core::same_span(a.invariant_site,b.invariant_site) && particle_source_core::same_span(a.next_site,b.next_site) &&
        particle_source_core::same_span(a.append_site,b.append_site) && particle_source_core::same_span(a.freeze_site,b.freeze_site) &&
        particle_source_core::same_span(a.return_site,b.return_site);
}
