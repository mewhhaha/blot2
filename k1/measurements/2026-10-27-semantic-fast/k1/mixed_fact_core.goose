// Private evidence over source-owned mixed arena. Binding IDs represent local
// values within the current lexical path; facts reset at each loop body.
namespace mixed_fact_core;
struct Evidence {guard_id:i64=0,truth:bool=false,subject:i64=0,reference:i64=0,one:i64=0,addition:i64=0,count:i64=0,guards:i64[16]=[0;16],edges:bool[16]=[false;16]}
struct Result {status:i64=0,events:Evidence[]=[]}
