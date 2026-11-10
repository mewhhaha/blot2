// Scoped emission records only scalar diagnostic data. Text is static.
namespace blot_backend_storage_diagnostic;
import check.core;
import check.diagnostic_code;
struct Diagnostic {unit:u32=0,span:blot_check_core::Span,code:blot_check_diagnostic_code::Code,detail:u32=0}
let detail_count:u32=61;
fn detailId(text:const u8[:])->u32 {
    if text=="" {return 0;}
    if text=="This form is not yet supported by the bounded scoped-storage backend" {return 1;}
    if text=="Storage layout exceeded its nesting bound" {return 2;}
    if text=="Storage layout exceeded its checked node budget" {return 3;}
    if text=="Array elements require a fixed inline layout; resizable and unresolved elements cannot be stored here" {return 4;}
    if text=="A local scalar reference cannot be stored in a data-stack aggregate" {return 5;}
    if text=="The stored borrow would outlive its owner" {return 6;}
    if text=="A loop cannot widen stored variants or borrowed roots after reading them; write the complete shape before its first read" {return 7;}
    if text=="Writer access summary exceeded its checked event budget" {return 8;}
    if text=="This array's growth capability was already consumed" {return 9;}
    if text=="A callback must have a statically known function body" {return 10;}
    if text=="A borrowed result would outlive its local value" {return 11;}
    if text=="A borrowed result would outlive its data-stack owner" {return 12;}
    if text=="Too many simultaneously live data regions" {return 13;}
    if text=="Application storage initializers cannot be recursive" {return 14;}
    if text=="Application array elements currently require scalar or inline record data without borrows" {return 15;}
    if text=="A named pool initializer must build fresh storage; use an explicit copy for an existing pool" {return 16;}
    if text=="A storage reservation requires a compile-time U32 literal" {return 17;}
    if text=="Array capacity exceeds the Wasm32 storage plan" {return 18;}
    if text=="A reference needs a local place with an enclosing lifetime" {return 19;}
    if text=="This array's growth capability was consumed by freeze" {return 20;}
    if text=="Shrinking would invalidate a live borrow or a consumed growth capability" {return 21;}
    if text=="The static callback capture schema exceeds its supported bound" {return 22;}
    if text=="Recursive function plans are not admitted" {return 23;}
    if text=="Recursive access requires initialized live input owners" {return 24;}
    if text=="Recursive writes cannot modify a frozen input owner" {return 25;}
    if text=="Only a direct checked self edge can use a recursive header" {return 26;}
    if text=="Recursive calls must preserve formal input owner correspondence" {return 27;}
    if text=="Recursive calls require live input owners" {return 28;}
    if text=="A recursive header cannot escape its construction transaction" {return 29;}
    if text=="The recursive body does not satisfy its fixed-owner contract" {return 30;}
    if text=="A writer call must preserve its checked read and mutation shape order" {return 31;}
    if text=="The static callback selection tree exceeds the supported bound" {return 32;}
    if text=="Cyclic selected call types cannot form a structural key" {return 33;}
    if text=="The selected call key exceeds its encoded-word or construction-work bound" {return 34;}
    if text=="The selected call type exceeds the supported bound" {return 35;}
    if text=="Source storage validation exceeded its checked work budget" {return 36;}
    if text=="The scoped body lacks complete type evidence" {return 37;}
    if text=="Recursive selected calls are not supported by the owned-storage backend" {return 38;}
    if text=="Selected calls exceeded their active call bound" {return 39;}
    if text=="Scoped helper extraction could not preserve its checked machine state" {return 40;}
    if text=="Shared callback output differs from its checked layout" {return 41;}
    if text=="Recursive callback specialization is not admitted" {return 42;}
    if text=="SIMD lane selectors must be literal integers" {return 43;}
    if text=="SIMD lane selector is outside its source vectors" {return 44;}
    if text=="A loop must retain the same named owners and borrowed roots across iterations" {return 45;}
    if text=="A loop cannot activate a variant without complete incoming payload evidence" {return 46;}
    if text=="Storage source expansion exceeded its expression budget" {return 47;}
    if text=="Storage source expansion exceeded its nesting bound" {return 48;}
    if text=="A loop exit must retain the same named owners and borrowed roots" {return 49;}
    if text=="Language tasks are not part of the data-stack model; use isolated host worker jobs and copied packets" {return 50;}
    if text=="Source module storage validation exceeded its checked work budget" {return 51;}
    if text=="This expression has no admitted storage layout or binding" {return 52;}
    if text=="Application pool initialization dependencies are cyclic" {return 53;}
    if text=="Application pool dependency discovery exceeded its checked node budget" {return 54;}
    if text=="Persistent storage budgets must match the named pool inventory" {return 55;}
    if text=="Invalid copied transport memory plan" {return 56;}
    if text=="Invalid scoped-storage Core bounds" {return 57;}
    if text=="Application pool dependency could not be resolved" {return 58;}
    if text=="Owned storage memory plan exceeds Wasm32 capacity" {return 59;}
    if text=="Invalid scoped-storage Core evidence" {return 60;}
    abort("unregistered scoped diagnostic detail");
}
fn detailText(value:Diagnostic)->const u8[:] {
    match value.detail {
        0=>"",
        1=>"This form is not yet supported by the bounded scoped-storage backend",
        2=>"Storage layout exceeded its nesting bound",
        3=>"Storage layout exceeded its checked node budget",
        4=>"Array elements require a fixed inline layout; resizable and unresolved elements cannot be stored here",
        5=>"A local scalar reference cannot be stored in a data-stack aggregate",
        6=>"The stored borrow would outlive its owner",
        7=>"A loop cannot widen stored variants or borrowed roots after reading them; write the complete shape before its first read",
        8=>"Writer access summary exceeded its checked event budget",
        9=>"This array's growth capability was already consumed",
        10=>"A callback must have a statically known function body",
        11=>"A borrowed result would outlive its local value",
        12=>"A borrowed result would outlive its data-stack owner",
        13=>"Too many simultaneously live data regions",
        14=>"Application storage initializers cannot be recursive",
        15=>"Application array elements currently require scalar or inline record data without borrows",
        16=>"A named pool initializer must build fresh storage; use an explicit copy for an existing pool",
        17=>"A storage reservation requires a compile-time U32 literal",
        18=>"Array capacity exceeds the Wasm32 storage plan",
        19=>"A reference needs a local place with an enclosing lifetime",
        20=>"This array's growth capability was consumed by freeze",
        21=>"Shrinking would invalidate a live borrow or a consumed growth capability",
        22=>"The static callback capture schema exceeds its supported bound",
        23=>"Recursive function plans are not admitted",
        24=>"Recursive access requires initialized live input owners",
        25=>"Recursive writes cannot modify a frozen input owner",
        26=>"Only a direct checked self edge can use a recursive header",
        27=>"Recursive calls must preserve formal input owner correspondence",
        28=>"Recursive calls require live input owners",
        29=>"A recursive header cannot escape its construction transaction",
        30=>"The recursive body does not satisfy its fixed-owner contract",
        31=>"A writer call must preserve its checked read and mutation shape order",
        32=>"The static callback selection tree exceeds the supported bound",
        33=>"Cyclic selected call types cannot form a structural key",
        34=>"The selected call key exceeds its encoded-word or construction-work bound",
        35=>"The selected call type exceeds the supported bound",
        36=>"Source storage validation exceeded its checked work budget",
        37=>"The scoped body lacks complete type evidence",
        38=>"Recursive selected calls are not supported by the owned-storage backend",
        39=>"Selected calls exceeded their active call bound",
        40=>"Scoped helper extraction could not preserve its checked machine state",
        41=>"Shared callback output differs from its checked layout",
        42=>"Recursive callback specialization is not admitted",
        43=>"SIMD lane selectors must be literal integers",
        44=>"SIMD lane selector is outside its source vectors",
        45=>"A loop must retain the same named owners and borrowed roots across iterations",
        46=>"A loop cannot activate a variant without complete incoming payload evidence",
        47=>"Storage source expansion exceeded its expression budget",
        48=>"Storage source expansion exceeded its nesting bound",
        49=>"A loop exit must retain the same named owners and borrowed roots",
        50=>"Language tasks are not part of the data-stack model; use isolated host worker jobs and copied packets",
        51=>"Source module storage validation exceeded its checked work budget",
        52=>"This expression has no admitted storage layout or binding",
        53=>"Application pool initialization dependencies are cyclic",
        54=>"Application pool dependency discovery exceeded its checked node budget",
        55=>"Persistent storage budgets must match the named pool inventory",
        56=>"Invalid copied transport memory plan",
        57=>"Invalid scoped-storage Core bounds",
        58=>"Application pool dependency could not be resolved",
        59=>"Owned storage memory plan exceeds Wasm32 capacity",
        60=>"Invalid scoped-storage Core evidence",
        _=>{abort("invalid scoped diagnostic detail");},
    }
}
