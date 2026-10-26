import viewcall_parse;
import viewproof_parse;
import viewcall_verify;
fn callee()->u8[] {return "let get: forall [r: Region, n: Nat, d: Domain] => Fn[static, Many, (View[r,U32,n,d], U32, U32), U32] ! {read r} resources {depth: 1, frame: 0} = fn (v,i,j) => do:\n  if i <= j && j < v.length:\n    return v[i]\n  else:\n    return 0\n";}
fn caller(call:u8[:],depth:u8[:])->u8[] {var out:u8[>..]=[];out.append("let relay: forall [rr: Region, nn: Nat, dd: Domain] => Fn[static, Many, (View[rr,U32,nn,dd], U32, U32), U32] ! {read rr} resources {depth: ");out.append(depth);out.append(", frame: 0} = fn (vv,ii,jj) => do:\n  return ");out.append(call);out.append("\n");return out;}
fn module(call:u8[:],depth:u8[:])->u8[] {var out:u8[>..]=[];out.append(callee());out.append(caller(call,depth));return out;}
fn main() {
 let s=module("get@[rr,nn,dd](vv,ii,jj)","2");var p,status=viewcall_parse::parse(s);if status!=0 {print("unexpected status ",status);}assert(status==0 && viewcall_verify::verify(s,p));
 for k in 8 {let old=p.loan_arg;if k==0 {p.loan_arg.start+=1;}else if k==1 {p.loan_arg.end+=1;}else if k==2 {p.split+=1;}else if k==3 {p.call.start+=1;}else if k==4 {p.region.start+=1;}else if k==5 {p.nat.start+=1;}else if k==6 {p.domain.start+=1;}else {p.view.start+=1;}
 assert(!viewcall_verify::verify(s,p));if k<2 {p.loan_arg=old;}else if k==2 {p.split-=1;}else if k==3 {p.call.start-=1;}else if k==4 {p.region.start-=1;}else if k==5 {p.nat.start-=1;}else if k==6 {p.domain.start-=1;}else {p.view.start-=1;}}
 for k in p.source.len {let old=p.source[k];p.source[k]=if old=='?' {'!'} else {'?'};assert(!viewcall_verify::verify(s,p));p.source[k]=old;}
 let bad_cases=[module("get@[rr,dd,nn](vv,ii,jj)","2"),module("get@[rr,nn,dd](ii,vv,jj)","2"),module("get@[rr,nn,dd](vv,ii,jj)","1"),module("other@[rr,nn,dd](vv,ii,jj)","2")] ;for bad in bad_cases {let _,code=viewcall_parse::parse(bad);assert(code!=0);}
 let oldpath=p.callee.evidence.path[0];p.callee.evidence.path[0]=99;assert(!viewcall_verify::verify(s,p));p.callee.evidence.path[0]=oldpath;
 var shadow:u8[>..]=[];shadow.append(callee());shadow.append("let relay: forall [rr: Region, nn: Nat, dd: Domain] => Fn[static, Many, (View[rr,U32,nn,dd], U32, U32), U32] ! {read rr} resources {depth: 2, frame: 0} = fn (get,ii,jj) => do:\n  return get@[rr,nn,dd](get,ii,jj)\n");let _,shadow_code=viewcall_parse::parse(shadow);assert(shadow_code!=0);
 print("source-linked formal View loan forwarding passed");
}
