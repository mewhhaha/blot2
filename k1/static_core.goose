// Source-owned private required-static scalar Core; IDs are postorder, and
// values are not authority until independent source and evaluator checks.
namespace static_core;
// tags: 1 U32 literal, 2 exact restricted F32 literal, 3 group, 4 F32 neg,
// 5 add, 6 sub, 7 mul, 8 div, 9 bit-and, 10/11/12 wrapping add/sub/mul.
struct Node {tag:i64=0,ty:i64=0,start:i64=0,end:i64=0,a:i64=0,b:i64=0,literal:u32=0,half:bool=false}
struct Tree {source:u8[]=[],name_start:i64=0,name_end:i64=0,ty:i64=0,nodes:Node[]=[],root:i64=0}
struct Result {status:i64=1,tree:Tree=Tree {}}
