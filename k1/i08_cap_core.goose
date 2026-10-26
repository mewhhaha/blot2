// Source-scoped capability trace for the fixed particle job. This models the
// function body's affine builder and transient input read loans. It does not
// establish caller backing disjointness, a runtime capability, public ABI,
// general K1 checking, or M13 resource authority.
namespace i08_cap_core;
import i08_job_core;
// 1 hold builder; 2 begin input loan; 3 read; 4 end loan; 5 scalar
// expression; 6 construct row; 7 consume builder and append; 8 carry;
// 9 consume builder and freeze; 10 return. Event references are one-based.
struct Step {kind:u32=0,event:u32=0,node:u32=0,site:i64=0,proof:u32=0}
struct Package {job:i08_job_core::Job=i08_job_core::Job {},steps:Step[]=[]}
fn eq(a:Step,b:Step)->bool {return a.kind==b.kind && a.event==b.event && a.node==b.node && a.site==b.site && a.proof==b.proof;}
