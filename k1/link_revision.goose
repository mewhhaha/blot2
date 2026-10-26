// Private sequential source-checked semantic-observation revisions. The graph
// and every declaration are freshly rebuilt each request; unchanged reports a
// comparison cutoff, not skipped compilation or a durable artifact authority.
namespace link_revision;
import source_resolver;
import project_graph;
import link_check;
struct Version {id:u64=0,snapshot:link_check::Snapshot=link_check::Snapshot {}}
struct Session {root_handle:i64=-1,package:u8[]=[],generation:u64=0,versions:Version[>..]=[]}
struct Update {status:i64=0,snapshot:link_check::Snapshot=link_check::Snapshot {},missing:u8[]=[],
               retained:bool=false,unchanged:bool=false,generation:u64=0}
fn begin(root:source_resolver::Root&) -> Session {
 if root.handle<0 {return Session {};}
 return Session {root_handle:root.handle,package:copy(root.package)};
}
// 0 checked, 1..6 link errors, 11..15 graph errors, 20 interrupted,
// 21 root mismatch. A failed link may return negative observations but never
// publishes a new revision. OOM/async/concurrent publication is not recovered.
fn update(session:Session&,root:source_resolver::Root&,entry:u8[:],abi:u8[:],probes:link_check::Probe[:],fault:u32) -> Update {
 if root.handle<0 || root.handle!=session.root_handle || root.package[..]!=session.package[..] || fault>3 {return Update {status:21};}
 if fault==1 {return Update {status:20};}
 let none:project_graph::Probe[]=[];
 let graph=project_graph::build(root,entry,none);
 if graph.status!=0 {return Update {status:10+graph.status,missing:copy(graph.missing)};}
 let checked=link_check::check(graph.graph,root.package,entry,abi,probes);
 if checked.status!=0 {return Update {status:checked.status,snapshot:copy(checked.snapshot)};}
 if fault==2 {return Update {status:20};}
 if fault==0 {
  for version in session.versions {
   if version.id==session.generation && link_check::same(version.snapshot,checked.snapshot) {
    return Update {snapshot:copy(checked.snapshot),retained:true,unchanged:true,generation:session.generation};
   }
  }
 }
 if session.versions.len>=8 || session.generation==18446744073709551615 {return Update {snapshot:copy(checked.snapshot)};}
 let next=session.generation+1;let staged=Version {id:next,snapshot:copy(checked.snapshot)};
 if fault==3 {return Update {status:20};}
 session.versions.push(copy(staged));session.generation=next;
 return Update {snapshot:copy(checked.snapshot),retained:true,generation:next};
}
