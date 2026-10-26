import std;
import viewcall_parse;
import viewalloc_verify;
import viewalloc_run;
fn prefix()->u8[] {return "let get: forall [r: Region, n: Nat, d: Domain] => Fn[static, Many, (View[r,U32,n,d], U32, U32), U32] ! {read r} resources {depth: 1, frame: 0} = fn (v,i,j) => do:\n  if i <= j && j < v.length:\n    return v[i]\n  else:\n    return 7\nlet relay: forall [rr: Region, nn: Nat, dd: Domain] => Fn[static, Many, (View[rr,U32,nn,dd], U32, U32), U32] ! {read rr} resources {depth: 2, frame: 0} = fn (vv,ii,jj) => do:\n  return get@[rr,nn,dd](vv,ii,jj)\n";}
fn suffix(reserve:u32,value:u32,index:u32,middle:u32,domain:u8[:],view:u8[:],owner:u8[:],space:u8[:])->u8[] {
 return str("let entry: Unit -> Result[Result[U32,AllocError],ReserveError] ! {reserve,release} = fn () => return region@[Result[U32,AllocError]](",reserve,") as r (owner,free) in do:\n  let (rest,answer): (Space[r],Result[U32,AllocError]) = do:\n    case region.try_alloc@[U32](free,1):\n      #Err((failspace,error)) => break (failspace,#Err(error))\n      #Ok((okspace,dst)) => do:\n        let packed = array.in(dst,#[",value,"])\n        let value = open packed as [d] a in do:\n          break relay@[r,1,",domain,"](",view,",",index,",",middle,")\n        break (okspace,#Ok(value))\n  space.end(",space,")\n  region.close(",owner,")\n  break answer\n");
}
fn main() {
 let a=prefix();var p,status=viewcall_parse::parse(a);assert(status==0);
 for reserve in [0 as u32,4,8] {for index in [0 as u32,1,4294967295] {for middle in [0 as u32,1,4294967295] {
  var source:u8[>..]=[];source.append(a);source.append(suffix(reserve,0xfedcba98,index,middle,"d","a","owner","rest"));let plan=viewalloc_verify::check(source,p);assert(plan.status==0 && plan.reserve==reserve && plan.value==0xfedcba98 && plan.index==index && plan.middle==middle);
  let got=viewalloc_run::run(source,p,true);if reserve==0 {assert(got.status==2 && got.clean);}else {let expected=if index<=middle && middle<1 {0xfedcba98 as u32} else {7 as u32};assert(got.status==0 && got.value==expected && got.clean);}
  let no_backing=viewalloc_run::run(source,p,false);if reserve==0 {assert(no_backing.status==2 && no_backing.clean);}else {assert(no_backing.status==1 && no_backing.clean);}
 }}}
 for k in 4 {let domain=if k==0 {"x"} else {"d"};let view=if k==1 {"dst"} else {"a"};let owner=if k==2 {"free"} else {"owner"};let space=if k==3 {"free"} else {"rest"};var bad:u8[>..]=[];bad.append(a);bad.append(suffix(4,41,0,0,domain,view,owner,space));assert(viewalloc_verify::check(bad,p).status!=0 && viewalloc_run::run(bad,p,true).status==4);}
 var source:u8[>..]=[];source.append(a);source.append(suffix(4,41,0,0,"d","a","owner","rest"));let old=p.callee.evidence.path[0];p.callee.evidence.path[0]=99;assert(viewalloc_verify::check(source,p).status!=0 && viewalloc_run::run(source,p,true).status==4);p.callee.evidence.path[0]=old;
 print("source-owned singleton allocation, read, failures and cleanup passed");
}
