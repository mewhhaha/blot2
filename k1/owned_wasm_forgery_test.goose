import owned_wasm_compile;import owned_wasm_check;
fn main(){
 let s="type Scalar[r: Region] = U32\nlet consume: (Owned[Scalar[_]], Bool) -> U32 ! {release} = fn (h, flag) => do:\n  let value = owned.open(h) as r data in do:\n    break data\n  owned.close(h)\n  return value\ntype ScalarPayload[r: Region] = U32\nlet main: Unit -> Result[U32,#Reserve(ReserveError) | #Body(#Cancelled)] ! {reserve,release} = fn () => do:\n  let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n    seal(free,7)\n  case built:\n    #Err(e) => return #Err(e)\n    #Ok(h) => return #Ok(consume(h,#True))\n";
 let other="type Scalar[r: Region] = U32\nlet consume: (Owned[Scalar[_]], Bool) -> U32 ! {release} = fn (h, flag) => do:\n  let value = owned.open(h) as r data in do:\n    break data\n  owned.close(h)\n  return value\ntype ScalarPayload[r: Region] = U32\nlet main: Unit -> Result[U32,#Reserve(ReserveError) | #Body(#Cancelled)] ! {reserve,release} = fn () => do:\n  let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n    seal(free,8)\n  case built:\n    #Err(e) => return #Err(e)\n    #Ok(h) => return #Ok(consume(h,#True))\n";
 let a=owned_wasm_compile::compile(s);let b=owned_wasm_compile::compile(other);assert(a.len>0 && b.len>0 && owned_wasm_check::verify(s,a) && owned_wasm_check::verify(other,b));assert(!owned_wasm_check::verify(s,b) && !owned_wasm_check::verify(other,a));
 for i in a.len {var forged=copy(a);forged[i]^=1;assert(!owned_wasm_check::verify(s,forged));assert(!owned_wasm_check::verify(s,a[..i]));}
 for i in s.len-1 {let truncated=s[..i];assert(owned_wasm_compile::compile(truncated).len==0);}
 print("owned Wasm cross-source, byte mutation and truncation controls passed");
}
