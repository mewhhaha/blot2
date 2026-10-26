import viewcall_parse;
import viewproof_parse;
import viewcall_verify;
fn callee()->u8[] {return "let get: forall [r: Region, n: Nat, d: Domain] => Fn[static, Many, (View[r,U32,n,d], U32, U32), U32] ! {read r} resources {depth: 1, frame: 0} = fn (v,i,j) => do:\n  if i <= j && j < v.length:\n    return v[i]\n  else:\n    return 0\n";}
fn caller(call:u8[:],depth:u8[:])->u8[] {var out:u8[>..]=[];out.append("let relay: forall [rr: Region, nn: Nat, dd: Domain] => Fn[static, Many, (View[rr,U32,nn,dd], U32, U32), U32] ! {read rr} resources {depth: ");out.append(depth);out.append(", frame: 0} = fn (vv,ii,jj) => do:\n  return ");out.append(call);out.append("\n");return out;}
fn module(call:u8[:],depth:u8[:])->u8[] {var out:u8[>..]=[];out.append(callee());out.append(caller(call,depth));return out;}
fn main(){
 let s=module("get@[rr,nn,dd](vv,ii,jj)","2");var p,status=viewcall_parse::parse(s);assert(status==0 && viewcall_verify::verify(s,p));
 for f in 10 {for edge in 2 {for v in [-1,999999] {
  let name=p.name;let region=p.region;let nat=p.nat;let domain=p.domain;let view=p.view;let index=p.index;let middle=p.middle;let call=p.call;let loan=p.loan_arg;let callee=p.callee.name;
  if f==0 {if edge==0 {p.name.start=v;}else {p.name.end=v;}} else if f==1 {if edge==0 {p.region.start=v;}else {p.region.end=v;}} else if f==2 {if edge==0 {p.nat.start=v;}else {p.nat.end=v;}} else if f==3 {if edge==0 {p.domain.start=v;}else {p.domain.end=v;}} else if f==4 {if edge==0 {p.view.start=v;}else {p.view.end=v;}} else if f==5 {if edge==0 {p.index.start=v;}else {p.index.end=v;}} else if f==6 {if edge==0 {p.middle.start=v;}else {p.middle.end=v;}} else if f==7 {if edge==0 {p.call.start=v;}else {p.call.end=v;}} else if f==8 {if edge==0 {p.loan_arg.start=v;}else {p.loan_arg.end=v;}} else {if edge==0 {p.callee.name.start=v;}else {p.callee.name.end=v;}}
  assert(!viewcall_verify::verify(s,p));p.name=name;p.region=region;p.nat=nat;p.domain=domain;p.view=view;p.index=index;p.middle=middle;p.call=call;p.loan_arg=loan;p.callee.name=callee;
 }}}
 for v in [-1,0,1,999999] {let save=p.split;p.split=v;assert(!viewcall_verify::verify(s,p));p.split=save;}
 for v in [-1,999999] {let save=p.callee.evidence.path[0];p.callee.evidence.path[0]=v;assert(!viewcall_verify::verify(s,p));p.callee.evidence.path[0]=save;}
 assert(!viewcall_verify::verify("wrong",p));
 for call in ["get@[rr,nn,dd](jj,ii,vv)","get@[rr,nn,dd](vv,jj,ii)","get@[rr,nn,dd](vv,ii,ii)","get@[rr,nn,dd](vv,ii,jj) + 1"] {let bad=module(call,"2");let _,code=viewcall_parse::parse(bad);assert(code!=0);}
 print("independent View forwarding malformed authority rejected");
}
