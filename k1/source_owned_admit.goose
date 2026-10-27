// Compose syntax production with independent source replay; a rejected source
// publishes no program. The resulting record is not a bearer capability.
namespace source_owned_admit;
import source_owned_core;
import source_owned_parse;
import source_owned_verify;
fn admit(s:u8[:])->source_owned_core::Result {
 var p=source_owned_parse::build(s);
 if p.status!=0 || !source_owned_verify::verify(s,p.program) {return source_owned_core::Result {};}
 return source_owned_core::Result {status:0,program:copy(p.program)};
}
