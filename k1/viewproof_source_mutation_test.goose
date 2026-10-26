import std;
import viewproof_parse;
import viewproof_verify;
fn main() {
 let src="let get: forall [r: Region, n: Nat, d: Domain] => Fn[static, Many, (View[r,U32,n,d], U32, U32), U32] ! {read r} resources {depth: 1, frame: 0} = fn (v,i,j) => do:\n  if i <= j && j < v.length:\n    return v[i]\n  else:\n    return 0\n";
 var original,status=viewproof_parse::parse(src);assert(status==0 && viewproof_verify::verify(src,original));var seen:i64=0;
 for i in src.len {for value in ['?',0,'0','x','<','=',']',' ',10,255] {if src[i]==value {continue;}var edit:u8[>..]=[];edit.append(src);edit[i]=value as u8;
  assert(!viewproof_verify::verify(edit,original));var p,st=viewproof_parse::parse(edit);if st==0 {assert(viewproof_verify::verify(edit,p));}seen+=1;
 }}print("malformed byte mutations checked ",seen);
}
