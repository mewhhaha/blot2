import static_float;
import static_om_float;
import work;
fn main() {
 for a in [0,1,16777217,4294967295] {for half in [false,true] {
  var m=work::Meter {};let x=static_om_float::literal(a as u32,half,m);
  assert(x.status==0 && x.value==static_float::literal(a as u32,half));let count=m.semantic;
  for allowed in count {var cut=work::Meter {semantic:1048576-allowed};let failed=static_om_float::literal(a as u32,half,cut);assert(failed.status==4 && failed.value==0);}
 }}
 for op in [5,6,7,8] {for a in [0,0x80000000,0x3f800000,0x7f800000,0x7fc00123] {for b in [0,0x80000000,0x3f000000,0x7f800000,0x7fc00234] {
  var m=work::Meter {};let x=static_om_float::arithmetic(op,a as u32,b as u32,m);
  assert(x.status==0 && x.value==static_float::arithmetic(op,a as u32,b as u32));let count=m.semantic;
  for allowed in count {var cut=work::Meter {semantic:1048576-allowed};let failed=static_om_float::arithmetic(op,a as u32,b as u32,cut);assert(failed.status==4 && failed.value==0);}
 }}}
 var bad=work::Meter {gate:2};assert(static_om_float::literal(1,false,bad).status==5);
 print("metered F32 conversion, operation and cutoff controls passed");
}
