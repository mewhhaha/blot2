// Compiler-side fixed caller operation evidence. Offsets and function numbers
// refer to one source/target snapshot; they are not runtime capabilities.
namespace m12_caller_flow_core;
struct Step {kind:i64=0,site:i64=0,callee:i64=0,depth:i64=0,parent:i64=-1,before:u32=0,after:u32=0}
struct Proof {source:u8[]=[],target:u8[]=[],steps:Step[12]=[Step {};12],padding_load:i64=-1,input_load:i64=-1,input_store:i64=-1,output_load:i64=-1,output_store:i64=-1}
struct Result {status:i64=1,proof:Proof=Proof {}}
fn same(a:Step,b:Step)->bool {return a.kind==b.kind && a.site==b.site && a.callee==b.callee && a.depth==b.depth && a.parent==b.parent && a.before==b.before && a.after==b.after;}
