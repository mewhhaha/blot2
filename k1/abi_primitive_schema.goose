// Private canonical primitive-type record. This format is a bounded fixture,
// not the qualified M10 ABI or an independently authenticated type identity.
namespace abi_primitive_schema;
import public_artifact;
fn canonical(code:u32)->u8[] {
 if code<1 || code>4{return [];}
 let size:u32=if code==1 {0} else {4};let alignment:u32=if code==1 {1} else {4};let flags:u32=if code==1 {7} else {3};
 // validity 0 Unit, 1 all U32 bit patterns, 2 all F32 bits, 3 Bool 0|1.
 // scalar machine representation 0 none, 1 i32, 2 f32. Generic T remains indirect.
 let validity:u32=code-1;let machine:u32=if code==1 {0} else if code==3 {2} else {1};
 var b:u8[>..]=[];b.append("K1PRIM01");for x in [1 as u32,code,size,alignment,flags,validity,machine,1 as u32] {public_artifact::put32(b,x);}return b;
}
