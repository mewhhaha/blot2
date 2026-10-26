// Private, compiler-owned I08 job model. This is not a complete compiler,
// authenticated module identity, portable artifact or general loan checker.
// Numeric symbols are local to this one immutable job; matching numbers from
// two jobs do not equate regions or domains. Runtime disjointness and affine
// caller authority remain separately required. Events describe source-order
// logical evaluation, not the precise machine-store schedule.
namespace i08_job_core;
import particle_lower_core;
struct Event {
    // 1 hold builder argument, 2 immutable field read, 3 copy dt,
    // 4 F32 multiply, 5 F32 add, 6 row, 7 append, 8 next, 9 freeze, 10 return.
    kind:u32=0, node:u32=0, site:i64=0, symbol:u32=0,version:u32=0,region:u32=0,domain:u32=0,
    index:u32=0,a:u32=0,b:u32=0,output:u32=0,output_version:u32=0,proof:u32=0
}
struct Job {source:u8[]=[],core:particle_lower_core::Core=particle_lower_core::Core {},events:Event[]=[]}
fn same_event(a:Event,b:Event)->bool {
    return a.kind==b.kind && a.node==b.node && a.site==b.site && a.symbol==b.symbol && a.version==b.version &&
        a.region==b.region && a.domain==b.domain && a.index==b.index && a.a==b.a && a.b==b.b &&
        a.output==b.output && a.output_version==b.output_version && a.proof==b.proof;
}
