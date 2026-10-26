// Independent source replay for the closed adapter and checked kernel. The
// conclusion is conditional: validated invocation loans, Result-slot/target,
// frame, manifest, C09 and M12 host bridge are not established here.
namespace m12_adapter_verify;
import lexer;
import m12_adapter_core;
import m12_adapter_schema;
import i08_link_affine;
import i08_transition_verify;
fn verify(p:m12_adapter_core::Program&,expected:u8[:])->bool {
 if expected.len>65536 || p.module[..]!=expected || p.split<=0 || p.split>=expected.len || p.events.len!=5 {return false;}
 let kernel=expected[..p.split];let body=expected[p.split..];if kernel[kernel.len-1]!='\n' {return false;}
 if !i08_link_affine::verify(p.linked,kernel,p.affine) || !i08_transition_verify::verify(p.linked,kernel,p.affine,p.transition) {return false;}
 let template=m12_adapter_schema::source();var l=lexer::init(body);var r=lexer::init(template);var count:i64=0;
 while true {let a=lexer::next(body,l);let b=lexer::next(template,r);if a.kind==9 || b.kind==9 || a.kind!=b.kind {return false;}if a.kind==0 {break;}
  if a.kind>=1 && a.kind<=5 {if a.start<0 || a.end<=a.start || a.end>body.len || b.start<0 || b.end<=b.start || b.end>template.len || body[a.start..a.end]!=template[b.start..b.end] {return false;}
   let token=body[a.start..a.end];var k:i64=0;if token=="begin_append" {k=1;}else if token=="project" {k=2;}else if token=="open" {k=3;}else if token=="pack" {k=4;}else if token=="return" {k=5;}
   if k!=0 {if count>=p.events.len || p.events[count].kind!=k || p.events[count].site!=p.split+a.start {return false;}count+=1;}
  }
 }
 return count==5;
}
// Source contract alone can never certify the mandatory host bridge.
fn public_eligible(p:m12_adapter_core::Program&,source:u8[:])->bool {let _=p;let _=source;return false;}
