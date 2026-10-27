// Experimental paired benchmark driver; source resolver and compile job are
// exercised on every iteration. No persistent compiler cache or public ABI.
import std;
import os;
import source_resolver;
import semantic_job;
import semantic_job_fast;
struct Sample {status:i64=1,bytes:u8[]=[]}
fn once(root:source_resolver::Root&,mode:u8[:],path:u8[:],name:u8[:],depth:u32)->Sample {
 if mode=="baseline" {let x=semantic_job::compile(root,path,name,0,depth,0,4294967295,0);return Sample {status:x.status,bytes:copy(x.wasm)};}
 if mode=="candidate" {let x=semantic_job_fast::compile(root,path,name,0,depth,0,4294967295,0);return Sample {status:x.status,bytes:copy(x.wasm)};}
 return Sample {};
}
fn main() {
 let a=args();if a.len!=7 || (a[1]!="baseline" && a[1]!="candidate") {exit(2);}
 let depth:u32=if a[5]=="depth" {0} else if a[5]=="normal" {128} else {exit(2);};
 let count:i64=if a[6]=="once" {1} else if a[6]=="batch" {32} else {exit(2);};
 var root=source_resolver::open_root(a[2],"pkg");if root.status!=0 {exit(3);}
 let expected=once(root.root,a[1],a[3],a[4],depth);if expected.status<0 || expected.status>255 {exit(4);}
 for _ in 1..count {let current=once(root.root,a[1],a[3],a[4],depth);if current.status!=expected.status || current.bytes[..]!=expected.bytes[..] {exit(5);}}
 if !source_resolver::close_root(root.root){exit(6);}
 let prefix:u8[1]=[expected.status as u8];write_stdout(prefix);write_stdout(expected.bytes);
}
