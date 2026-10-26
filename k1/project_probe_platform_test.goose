// This fixture is run only on hosts other than Linux, where both adapters must
// reject access rather than fall back to unconstrained filesystem operations.
import source_resolver;
extern fn k1_project_probe(root:i64,path:const u8[:]) -> i64;
fn main() {
 let root=source_resolver::open_root("untrusted","pkg");
 assert(root.status==4 && root.root.handle<0);
 assert(k1_project_probe(0,"source.blot")==4);
 print("unsupported project source adapters failed closed");
}
