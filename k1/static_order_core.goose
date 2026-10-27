// Private scalar/aggregate retained candidate and ordered target outcome.
// No full C09, authenticated artifact or K1 Domain authority is implied.
namespace static_order_core;
import work;
import static_core;
import static_product_core;
struct Owned {product:static_product_core::Tree=static_product_core::Tree {},scalars:static_core::Tree[]=[]}
struct Parsed {status:i64=1,owned:Owned=Owned {}}
struct Output {status:i64=1,work:work::ScheduledWork=work::ScheduledWork {},wasm:u8[]=[]}
