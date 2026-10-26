// Fixture-only input corpus; compare against independent JavaScript F32 math.
import os;
import static_float;
fn next(s:u64&) -> u32 {s=(s*1664525+1013904223)&4294967295;return s as u32;}
fn put(out:u8[>..]&,x:u32) {for i in 4 {out.push((x >> (8*i) & 255) as u8);}}
fn main() {
 var output:u8[>..]=[];var state:u64=0xc012ef48;
 for _ in 10000 {
    let a=next(state);let b=next(state);put(output,a);put(output,b);
    for op in 5..9 {put(output,static_float::arithmetic(op,a,b));}
 }
 assert(write_file("static-f32-oracle.bin",output));
 print("private static F32 oracle corpus emitted");
}
