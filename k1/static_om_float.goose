// Selected explicit F32 conversion/operation work, in the private fixture
// meter. Goose runtime serialization internals remain outside this model.
namespace static_om_float;
import work;
struct Bits {status:i64=0,value:u32=0}
struct Float {status:i64=0,value:f32=0.0}
fn charge(m:work::Meter&,event:u32)->i64 {
 let r=work::charge(m,3,event);return if r.status==0 {0} else if r.status==1 {4} else {5};
}
fn bits(value:f32,m:work::Meter&)->Bits {
 let alloc=charge(m,10);if alloc!=0 {return Bits {status:alloc};}
 let a:f32[1]=[value];
 let convert=charge(m,10);if convert!=0 {return Bits {status:convert};}
 let b=bytes_of(a);var result:u32=0;
 for i in 4 {let read=charge(m,3);if read!=0 {return Bits {status:read};}result|=(b[i] as u32) << (i*8);}
 return Bits {value:result};
}
fn from_bits(value:u32,m:work::Meter&)->Float {
 let alloc=charge(m,10);if alloc!=0 {return Float {status:alloc};}
 var a:u8[5]=[4,0,0,0,0];
 for i in 4 {let write=charge(m,3);if write!=0 {return Float {status:write};}a[i+1]=(value >> (8*i) & 255) as u8;}
 let convert=charge(m,10);if convert!=0 {return Float {status:convert};}
 let v,ok=from_bytes<f32[>..]>(a);assert(ok && v.len==1);
 let read=charge(m,3);if read!=0 {return Float {status:read};}return Float {value:v[0]};
}
fn literal(integer:u32,half:bool,m:work::Meter&)->Bits {
 let convert=charge(m,6);if convert!=0 {return Bits {status:convert};}let x:f32=integer as! f32;
 if half {let add=charge(m,6);if add!=0 {return Bits {status:add};}return bits(x+0.5,m);}
 return bits(x,m);
}
fn arithmetic(op:i64,a:u32,b:u32,m:work::Meter&)->Bits {
 let x=from_bits(a,m);if x.status!=0 {return Bits {status:x.status};}
 let y=from_bits(b,m);if y.status!=0 {return Bits {status:y.status};}
 let op_status=charge(m,6);if op_status!=0 {return Bits {status:op_status};}var z:f32=0.0;
 if op==5 {z=x.value+y.value;} else if op==6 {z=x.value-y.value;} else if op==7 {z=x.value*y.value;} else {z=x.value/y.value;}
 let classify=charge(m,6);if classify!=0 {return Bits {status:classify};}if z!=z {return Bits {value:0x7fc00000};}
 return bits(z,m);
}
