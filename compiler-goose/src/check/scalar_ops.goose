// Which scalar operations have a machine instruction, and U32 constant
// folding, for the checker's numeric and package proofs.
namespace blot_check_scalar_ops;
import .core;
import support.native;
type Op=blot_check_core::Op;

// Whether `op` is one scalar instruction on F32 operands (`floating`) or on
// U32 and Bool operands.
fn supported(op:Op,floating:bool)->bool {
 match op {
  add,sub,mul,div,equal,not_equal,less,less_equal,greater,greater_equal,convert_u32_f32,convert_f32_u32=>{return true;},
  rem,bit_and,bit_or,bit_xor,shift_left,shift_right,from_bits=>{return !floating;},
  neg,abs,ceil,floor,trunc,sqrt,min,max,bits=>{return floating;},
  _=>{return false;},
 }
}

// Constant folding of a scalar operation on two U32 operands, as the guest
// computes it: `value` with the U32 result, `not_u32` when the result has
// another type (a comparison or a conversion to F32), or `none` when the
// guest has no such U32 instruction or would trap (division by zero).
enum Fold {value,not_u32,none}
fn foldU32(op:Op,a:u32,b:u32)->Fold,u32 {
 match op {
  equal,not_equal,less,less_equal,greater,greater_equal,convert_u32_f32,from_bits=>{return Fold.not_u32,0;},
  div,rem=>{if b==0 {return Fold.none,0;}},
  _=>{},
 }
 match op {
  add=>{return Fold.value,(a as u64+b as u64) as! u32;},
  sub=>{return Fold.value,(a as u64+4294967296-b as u64) as! u32;},
  mul=>{return Fold.value,(a as u64*b as u64) as! u32;},
  div=>{return Fold.value,a/b;},
  rem=>{return Fold.value,a%b;},
  bit_and=>{return Fold.value,a&b;},
  bit_or=>{return Fold.value,a|b;},
  bit_xor=>{return Fold.value,a^b;},
  shift_left=>{return Fold.value,a<<(b&31);},
  shift_right=>{return Fold.value,a>>(b&31);},
  convert_f32_u32=>{return Fold.value,truncate(blot_native::f32_from_bits(a));},
  _=>{return Fold.none,0;},
 }
}
fn truncate(x:f32)->u32 {
 if x!=x||x<=0.0 {return 0;}
 if x>=4294967296.0 {return 0xffffffff;}
 return x as! u32;
}
