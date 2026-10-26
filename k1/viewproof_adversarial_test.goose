import std;
import viewproof_core;
import viewproof_parse;
import viewproof_verify;
fn main() {
 let s="let get: forall [r: Region, n: Nat, d: Domain] => Fn[static, Many, (View[r,U32,n,d], U32, U32), U32] ! {read r} resources {depth: 1, frame: 0} = fn (v,i,j) => do:\n  if i <= j && j < v.length:\n    return v[i]\n  else:\n    return 0\n";
 var p,status=viewproof_parse::parse(s);assert(status==0 && viewproof_verify::verify(s,p));
 for field in 18 {for v in [-1,999999,9223372036854775807] {
 let name=p.name;let region=p.region;let nat=p.nat;let domain=p.domain;let view=p.view;let index=p.index;let middle=p.middle;let read=p.read;let evidence=p.evidence;
 if field==0 {p.name.start=v;}else if field==1 {p.name.end=v;}else if field==2 {p.region.start=v;}else if field==3 {p.region.end=v;}
 else if field==4 {p.nat.start=v;}else if field==5 {p.nat.end=v;}else if field==6 {p.domain.start=v;}else if field==7 {p.domain.end=v;}
 else if field==8 {p.view.start=v;}else if field==9 {p.view.end=v;}else if field==10 {p.index.start=v;}else if field==11 {p.index.end=v;}
 else if field==12 {p.middle.start=v;}else if field==13 {p.middle.end=v;}else if field==14 {p.read.start=v;}else if field==15 {p.read.end=v;}
 else if field==16 {p.evidence.path_len=v;}else {p.evidence.index.start=v;}
 assert(!viewproof_verify::verify(s,p));p.name=name;p.region=region;p.nat=nat;p.domain=domain;p.view=view;p.index=index;p.middle=middle;p.read=read;p.evidence=evidence;
 }}
 for i in p.guards.len {for field in 5 {for v in [-1,999999,9223372036854775807] {let old=p.guards[i];
 if field==0 {p.guards[i].left=v;}else if field==1 {p.guards[i].right=v;}else if field==2 {p.guards[i].source.start=v;}else if field==3 {p.guards[i].source.end=v;}else {p.guards[i].strict=!old.strict;}
 assert(!viewproof_verify::verify(s,p));p.guards[i]=old;}}}
 for i in 6 {for v in [-1,0,999999,9223372036854775807] {let old=p.evidence.path[i];if old==v {continue;}p.evidence.path[i]=v;assert(!viewproof_verify::verify(s,p));p.evidence.path[i]=old;}}
 for i in p.source.len {let old=p.source[i];p.source[i]=if old=='?' {'!'} else {'?'};assert(!viewproof_verify::verify(s,p));p.source[i]=old;}
 assert(!viewproof_verify::verify("different",p));print("view declaration, path and source extreme mutations rejected");
}
