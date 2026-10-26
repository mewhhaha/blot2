// Private source-owned aggregate/call candidate. Module and source projections
// are owned bytes, not authenticated K1 artifacts or static Domain identity.
namespace static_compound_core;
import static_product_core;
struct Call {start:i64=0,end:i64=0,name_end:i64=0,argument:u32=0,target:i64=0}
struct Program {source:u8[]=[],split:i64=0,projection:u8[]=[],product:static_product_core::Tree=static_product_core::Tree {},calls:Call[]=[]}
struct Result {status:i64=1,program:Program=Program {}}
