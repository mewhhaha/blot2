// Partial compiler-owned work result for a scalar parsing helper; not a
// complete per-declaration C09 receipt or public compiler interface.
namespace static_m_core;
import static_core;
import work;
struct Result {meter:work::Meter=work::Meter {},status:i64=1,tree:static_core::Tree=static_core::Tree {}}

struct Check {ok:bool=false,limited:bool=false,work_status:u32=0,meter:work::Meter=work::Meter {}}
