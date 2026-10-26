// Private F32 primitives. Goose f32 operations are used one operation at a
// time and re-materialized as bits, forbidding fused/reassociated evaluation.
// Host requires IEEE binary32, round-to-nearest and Goose's little-endian
// serialization support. Required-static arithmetic NaNs become +0x7fc00000.
namespace static_float;
fn bits(value:f32) -> u32 {
    let a:f32[1]=[value];let b=bytes_of(a);
    return b[0] | (b[1] as u32 << 8) | (b[2] as u32 << 16) | (b[3] as u32 << 24);
}
fn from_bits(value:u32) -> f32 {
    var a:u8[5]=[4,0,0,0,0];for i in 4 {a[i+1]=(value >> (8*i) & 255) as u8;}
    let v,ok=from_bytes<f32[>..]>(a);assert(ok && v.len==1);return v[0];
}
fn literal(integer:u32,half:bool) -> u32 {
    let x:f32=integer as! f32;
    return bits(if half {x+0.5} else {x});
}
fn arithmetic(op:i64,a:u32,b:u32) -> u32 {
    let x=from_bits(a);let y=from_bits(b);var z:f32=0.0;
    if op==5 {z=x+y;} else if op==6 {z=x-y;} else if op==7 {z=x*y;} else {z=x/y;}
    if z!=z {return 0x7fc00000;}
    return bits(z);
}
