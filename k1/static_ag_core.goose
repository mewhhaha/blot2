// Partial metered static aggregate results, not complete C09 receipts.
namespace static_ag_core;
import work;
import static_product_core;
import static_product_eval;
import static_publish_core;
struct Parsed {status:i64=1,meter:work::Meter=work::Meter {},tree:static_product_core::Tree=static_product_core::Tree {}}
struct Checked {status:i64=1,meter:work::Meter=work::Meter {}}
struct Evaluated {status:i64=1,meter:work::Meter=work::Meter {},steps:u32=0,value:static_product_eval::Result=static_product_eval::Result {}}

struct ImageResult {status:i64=1,meter:work::Meter=work::Meter {},image:static_publish_core::Image=static_publish_core::Image {}}
