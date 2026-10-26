import viewproof_core;
import viewproof_parse;
import viewproof_verify;
fn source(condition:u8[:])->u8[] {var out:u8[>..]=[];out.append("let get: forall [r: Region, n: Nat, d: Domain] => Fn[static, Many, (View[r,U32,n,d], U32, U32), U32] ! {read r} resources {depth: 1, frame: 0} = fn (v,i,j) => do:\n  if ");out.append(condition);out.append(":\n    return v[i]\n  else:\n    return 0\n");return out;}
fn check(condition:u8[:],expected:i64) {let s=source(condition);var p,status=viewproof_parse::parse(s);if status!=expected {print("unexpected status ",status," expected ",expected," guard ",condition);}assert(status==expected);if status==0 {assert(viewproof_verify::verify(s,p));}}
fn main() {
 check("i < v.length",0);check("i <= j && j < v.length",0);check("i < j && j <= v.length",0);check("j < v.length && i <= j",0);check("i <= i && i < v.length",0);check("i <= j && j <= v.length",5);check("j < v.length",5);check("i < j && v.length < j",5);check("i < v.length || j < v.length",1);check("i < v.length && j < v.length && i <= j",0);
 check("i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i < v.length",0);
 check("i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i <= i && i < v.length",2);

 let s="let get: forall [r: Region, n: Nat, d: Domain] => Fn[static, Many, (View[r,U32,n,d], U32, U32), U32] ! {read r} resources {depth: 1, frame: 0} = fn (v,i,j) => do:\n  if i <= j && j < v.length:\n    return v[i]\n  else:\n    return 0\n";
 var p,status=viewproof_parse::parse(s);if status!=0 {print("parse status ",status);}assert(status==0 && viewproof_verify::verify(s,p));
 for k in 6 {let saved=p.evidence;p.evidence.path[k]=99;assert(!viewproof_verify::verify(s,p));p.evidence=saved;}
 for k in p.guards.len {let old=p.guards[k];p.guards[k].strict=!p.guards[k].strict;assert(!viewproof_verify::verify(s,p));p.guards[k]=old;p.guards[k].left=99;assert(!viewproof_verify::verify(s,p));p.guards[k]=old;}
 for k in 9 {var old=p.name;if k==0 {p.name.start+=1;}else if k==1 {old=p.region;p.region.start+=1;}else if k==2 {old=p.nat;p.nat.start+=1;}else if k==3 {old=p.domain;p.domain.start+=1;}else if k==4 {old=p.view;p.view.start+=1;}else if k==5 {old=p.index;p.index.start+=1;}else if k==6 {old=p.middle;p.middle.start+=1;}else if k==7 {old=p.read;p.read.start+=1;}else {p.fallback+=1;}
  assert(!viewproof_verify::verify(s,p));if k==0 {p.name=old;}else if k==1 {p.region=old;}else if k==2 {p.nat=old;}else if k==3 {p.domain=old;}else if k==4 {p.view=old;}else if k==5 {p.index=old;}else if k==6 {p.middle=old;}else if k==7 {p.read=old;}else {p.fallback-=1;}}
 for k in p.source.len {let old=p.source[k];p.source[k]=if old=='?' {'!'} else {'?'};assert(!viewproof_verify::verify(s,p));p.source[k]=old;}
 let bad="let get: forall [r: Region, n: Nat, d: Domain] => Fn[static, Many, (View[r,U32,n,d], U32, U32), U32] ! {read r} resources {depth: 1, frame: 0} = fn (v,i,j) => do:\n  if i <= j && j <= v.length:\n    return v[i]\n  else:\n    return 0\n";let _,reject=viewproof_parse::parse(bad);assert(reject!=0 && !viewproof_verify::verify(bad,p));
 print("typed formal View relation and source-bound forgery checks passed");
}
