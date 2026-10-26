// Conditional source-local proof schema, not a runtime version/loan/ABI.
namespace i08_transition_core;
struct Step {kind:i64=0,node:i64=0,site:i64=0,subject:u32=0,version:u32=0,result:u32=0,result_version:u32=0,index:u32=0,nat:i64=0,capacity:i64=0,dep1:i64=0,dep2:i64=0,dep3:i64=0}
struct Proof {steps:Step[6]=[Step {};6]}
struct Result {status:i64=0,proof:Proof=Proof {}}
fn same(a:Step,b:Step)->bool {return a.kind==b.kind && a.node==b.node && a.site==b.site && a.subject==b.subject && a.version==b.version && a.result==b.result && a.result_version==b.result_version && a.index==b.index && a.nat==b.nat && a.capacity==b.capacity && a.dep1==b.dep1 && a.dep2==b.dep2 && a.dep3==b.dep3;}
