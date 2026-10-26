import std;
import viewcall_parse;
import viewalloc_verify;
import viewalloc_run;
fn prefix()->u8[] {return "let get: forall [r: Region, n: Nat, d: Domain] => Fn[static, Many, (View[r,U32,n,d], U32, U32), U32] ! {read r} resources {depth: 1, frame: 0} = fn (v,i,j) => do:\n  if i <= j && j < v.length:\n    return v[i]\n  else:\n    return 7\nlet relay: forall [rr: Region, nn: Nat, dd: Domain] => Fn[static, Many, (View[rr,U32,nn,dd], U32, U32), U32] ! {read rr} resources {depth: 2, frame: 0} = fn (vv,ii,jj) => do:\n  return get@[rr,nn,dd](vv,ii,jj)\n";}
fn suffix(reserve:u32,value:u32,index:u32,middle:u32,domain:u8[:],view:u8[:],owner:u8[:],space:u8[:])->u8[] {
 return str("let entry: Unit -> Result[Result[U32,AllocError],ReserveError] ! {reserve,release} = fn () => return region@[Result[U32,AllocError]](",reserve,") as r (owner,free) in do:\n  let (rest,answer): (Space[r],Result[U32,AllocError]) = do:\n    case region.try_alloc@[U32](free,1):\n      #Err((failspace,error)) => break (failspace,#Err(error))\n      #Ok((okspace,dst)) => do:\n        let packed = array.in(dst,#[",value,"])\n        let value = open packed as [d] a in do:\n          break relay@[r,1,",domain,"](",view,",",index,",",middle,")\n        break (okspace,#Ok(value))\n  space.end(",space,")\n  region.close(",owner,")\n  break answer\n");
}
fn main() {
 let source_prefix=prefix();var owner,st=viewcall_parse::parse(source_prefix);assert(st==0);
 for reserve in [0 as u32,1,3,4,4095,4096,4097,4294963200,4294963201,4294967295] {for available in [false,true] {for i in [0 as u32,1,4294967295] {for middle in [0 as u32,1,4294967295] {
  var src:u8[>..]=[];src.append(source_prefix);src.append(suffix(reserve,4294967295,i,middle,"d","a","owner","rest"));
  let got=viewalloc_run::run(src,owner,available);
  if reserve>4294963200 {assert(got.status==1 && got.detail==1 && got.clean);} else if reserve>0 && (!available || reserve>4096) {assert(got.status==1 && got.detail==3 && got.clean);} else if reserve<4 {assert(got.status==2 && got.detail==2 && got.clean);} else {let expect=if i<=middle && middle<1 {4294967295 as u32} else {7 as u32};assert(got.status==0 && got.value==expect && got.clean);}
 }}}}
 var src:u8[>..]=[];src.append(source_prefix);src.append(suffix(4,41,0,0,"d","a","owner","rest"));
 let oldsplit=owner.split;for n in [-1,0,1,999999] {owner.split=n;assert(viewalloc_verify::check(src,owner).status!=0 && viewalloc_run::run(src,owner,true).status==4);}owner.split=oldsplit;
 for i in owner.source.len {let old=owner.source[i];owner.source[i]=if old=='?' {'!'} else {'?'};assert(viewalloc_verify::check(src,owner).status!=0);owner.source[i]=old;}
 var edits:u8[>..]=[];edits.append(src);var accepted=0;var rejected=0;let repl:u8[6]=['?', 'x','0','1', ' ', '\n'];
 for i in source_prefix.len..edits.len {let old=edits[i];for c in repl {edits[i]=c;let plan=viewalloc_verify::check(edits,owner);if plan.status==0 {accepted+=1;let result=viewalloc_run::run(edits,owner,true);if plan.reserve>=4 && plan.reserve<=4096 {let want=if plan.index<=plan.middle && plan.middle<1 {plan.value} else {7 as u32};assert(result.status==0 && result.value==want && result.clean);}}else {rejected+=1;assert(viewalloc_run::run(edits,owner,true).status==4);}}edits[i]=old;}
 print(str("independent View allocation boundaries and source mutations: ",accepted," accepted, ",rejected," rejected"));
}
