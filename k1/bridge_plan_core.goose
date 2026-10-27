// Typed fixed bridge plan, source-associated but not transferable authority.
namespace bridge_plan_core;
struct Case {count:u32=0,input_start:u32=0,input_end:u32=0,output_start:u32=0,output_end:u32=0,result_end:u32=0,capacity:u32=0,frontier:u32=0}
fn same(a:Case,b:Case)->bool {return a.count==b.count && a.input_start==b.input_start && a.input_end==b.input_end && a.output_start==b.output_start && a.output_end==b.output_end && a.result_end==b.result_end && a.capacity==b.capacity && a.frontier==b.frontier;}
struct Branch {kind:u32=0,status:u32=0,cleanup:u32=0,phase:u32=0}
struct Plan {source:u8[]=[],source_sites:i64[5]=[0;5],ops:u32[13]=[0;13],branches:Branch[7]=[Branch {};7],cases:Case[9]=[Case {};9]}
struct Result {status:i64=1,plan:Plan=Plan {}}
