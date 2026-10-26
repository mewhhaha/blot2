// Source-local static node/binding identities, not runtime versions, loans,
// capabilities, initialized memory, artifact or host authority.
namespace i08_affine_core;
struct Plan {initial:i64=0,view:i64=0,nat:i64=0,capacity:i64=0,loop_id:i64=0,index:i64=0,carry_id:i64=0,result:i64=0,carry_node:i64=0,invariant_id:i64=0,next_node:i64=0,append:i64=0,row:i64=0,freeze:i64=0,return_node:i64=0,root:i64=0}
struct Result {status:i64=0,plan:Plan=Plan {}}
