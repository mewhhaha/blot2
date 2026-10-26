// Private sequential graph-revision staging. This retains source/import graphs,
// not checked K1 compilation artifacts. The trusted caller owns the Session
// and must retain its original Root without copying, closing or concurrent use.
namespace project_revision;
import source_resolver;
import project_graph;
struct Version {id:u64=0, graph:project_graph::Graph=project_graph::Graph {}}
struct Session {root_handle:i64=-1,package:u8[]=[],generation:u64=0,versions:Version[>..]=[]}
// status 0 graph built; 1..5 graph errors; 6 interruption; 7 root mismatch.
// On success with retained=false, caller must use returned graph; the old
// retained revision must not be mistaken for the newer unretained result.
struct Update {status:i64=0,graph:project_graph::Graph=project_graph::Graph {},missing:u8[]=[],
               retained:bool=false,unchanged:bool=false,generation:u64=0}
fn begin(root:source_resolver::Root&) -> Session {
    if root.handle<0 {return Session {};}
    return Session {root_handle:root.handle,package:copy(root.package)};
}
// failpoint 1 cancels before reading, 2 after graph construction, and 3 after
// constructing an owned staging value but before appending it. Process OOM/asynchronous cancellation and
// concurrent readers are not recovered or synchronized by this experiment.
fn update(session:Session&,root:source_resolver::Root&,entry:u8[:],probes:project_graph::Probe[:],failpoint:u32) -> Update {
    if root.handle<0 || root.handle!=session.root_handle || root.package[..]!=session.package[..] || failpoint>3 {return Update {status:7};}
    if failpoint==1 {return Update {status:6};}
    let current=project_graph::build(root,entry,probes);
    if current.status!=0 {return Update {status:current.status,missing:copy(current.missing)};}
    if failpoint==2 {return Update {status:6};}
    if failpoint==0 {
        for v in session.versions {
            if v.id==session.generation && project_graph::same(v.graph,current.graph) {
                return Update {graph:copy(current.graph),retained:true,unchanged:true,generation:session.generation};
            }
        }
    }
    if session.versions.len>=8 || session.generation==18446744073709551615 {
        return Update {graph:copy(current.graph)};
    }
    let id=session.generation+1;
    let staged=Version {id:id,graph:copy(current.graph)};
    if failpoint==3 {return Update {status:6};}
    session.versions.push(copy(staged));
    session.generation=id;
    return Update {graph:copy(current.graph),retained:true,generation:id};
}
