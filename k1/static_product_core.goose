// Private required-static tuple/array source snapshot. Component scalar trees
// are revalidated against exact slices; IDs do not grant static Domain identity.
namespace static_product_core;
struct Part {start:i64=0,end:i64=0,ty:i64=0}
struct Tree {source:u8[]=[],name_start:i64=0,name_end:i64=0,is_array:bool=false,width:i64=0,rows:i64=0,parts:Part[]=[]}
struct Result {status:i64=1,tree:Tree=Tree {}}
