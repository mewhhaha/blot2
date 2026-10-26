// Private single-threaded staged linked-Wasm revisions. A new graph and target
// are built and independently validated for each request; there is no cache
// authorization from imported receipts, no recoverable OOM or concurrency.
namespace multilink_revision;
import source_resolver;
import multilink_program;
import multilink_wasm;
import multilink_target;
import link_check;
struct Version {id:u64=0,plan:multilink_program::Plan=multilink_program::Plan {},target:u8[]=[]}
struct Session {root_handle:i64=-1,package:u8[]=[],generation:u64=0,versions:Version[>..]=[]}
struct Update {status:i64=0,bytes:u8[]=[],missing:u8[]=[],lookup:link_check::Snapshot=link_check::Snapshot {},retained:bool=false,
               semantic_unchanged:bool=false,target_unchanged:bool=false,generation:u64=0}
fn begin(root:source_resolver::Root&) -> Session {
 if root.handle<0 {return Session {};}
 return Session {root_handle:root.handle,package:copy(root.package)};
}
fn current(session:Session&,entry:u8[:],abi:u8[:],probes:link_check::Probe[:]) -> u8[] {
 for version in session.versions {
  if version.id==session.generation {
   if !multilink_target::verify(version.plan,session.package,entry,abi,probes,version.target) {return [];}
   return copy(version.target);
  }
 }
 return [];
}
// status 0 success, 1..6 link errors, 11..15 graph errors, 20 interruption,
// 21 root mismatch, 22 invalid freshly generated target. Test failpoints:
// 1 before reading, 2 after target validation, 3 after staging before append.
fn update(session:Session&,root:source_resolver::Root&,entry:u8[:],abi:u8[:],probes:link_check::Probe[:],fault:u32)->Update {
 if root.handle<0 || root.handle!=session.root_handle || root.package[..]!=session.package[..] || fault>3 {return Update {status:21};}
 if fault==1 {return Update {status:20};}
 var made=multilink_program::prepare(root,entry,abi,probes);
 if made.status!=0 {return Update {status:made.status,missing:copy(made.missing),lookup:copy(made.lookup)};}
 let bytes=multilink_wasm::emit(made.plan,root.package,entry,abi,probes);
 if bytes.len==0 || !multilink_target::verify(made.plan,root.package,entry,abi,probes,bytes) {return Update {status:22};}
 if fault==2 {return Update {status:20};}
 var semantic_same=false;var target_same=false;
 for old in session.versions {
  if old.id==session.generation && multilink_target::verify(old.plan,session.package,entry,abi,probes,old.target) {
   semantic_same=link_check::same(old.plan.snapshot,made.plan.snapshot);target_same=old.target[..]==bytes[..];
  }
 }
 if fault==0 && semantic_same && target_same {
  return Update {bytes:copy(bytes),retained:true,semantic_unchanged:true,target_unchanged:true,generation:session.generation};
 }
 if session.versions.len>=8 || session.generation==18446744073709551615 {
  return Update {bytes:copy(bytes),semantic_unchanged:semantic_same,target_unchanged:target_same};
 }
 let next=session.generation+1;let staged=Version {id:next,plan:copy(made.plan),target:copy(bytes)};
 if fault==3 {return Update {status:20};}
 session.versions.push(copy(staged));session.generation=next;
 return Update {bytes:copy(bytes),retained:true,semantic_unchanged:semantic_same,target_unchanged:target_same,generation:next};
}
