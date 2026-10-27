// Private compiler-host resolver. A trusted caller opens and owns one package
// root for its lifetime. Source names are logical, package-relative paths; the
// host adapter rechecks them and uses descriptor-relative openat2 on Linux.
// This is not a package mapper, import graph, cache, or public K1 admission.
namespace source_resolver;
import source_identity;
import public_interface;

extern fn k1_source_root_open(path: const u8[:]) -> i64;
extern fn k1_source_root_close(root: i64) -> i64;
extern fn k1_source_read_under(root: i64, path: const u8[:], out: u8[>..]&) -> i64;

struct Root { handle: i64 = -1, package: u8[] = [] }
struct RootResult { status: i64 = 1, root: Root = Root {} }
// 0 success; 1 path/open/read/close/identity failure; 2 source too large;
// 3 host scratch allocation failure; 4 platform or kernel unsupported.
struct Result { status: i64 = 1, source: source_identity::Source = source_identity::Source {} }

// root_path is a trusted package mapping chosen by the host, not a K1 import.
// Its descriptor anchors later lookups even if the root pathname is renamed.
// Avoid copying Root: close exactly once, with no concurrent close/read.
fn open_root(root_path: u8[:], package: u8[:]) -> RootResult {
    if !public_interface::package_valid(package) { return RootResult {}; }
    let fd = k1_source_root_open(root_path);
    if fd == -2 { return RootResult { status: 4 }; }
    if fd < 0 { return RootResult {}; }
    return RootResult { status: 0, root: Root { handle: fd, package: package } };
}
fn close_root(root: Root&) -> bool {
    if root.handle < 0 { return false; }
    let status = k1_source_root_close(root.handle);
    root.handle = -1;
    return status == 0;
}
fn read(root: Root&, module: u8[:], declaration: u8[:]) -> Result {
    if root.handle < 0 || !public_interface::identity_valid(root.package, module, declaration) { return Result {}; }
    var bytes: u8[>..] = [];
    let status = k1_source_read_under(root.handle, module, bytes);
    if status != 0 { return Result { status: status }; }
    let identity = source_identity::make(root.package, module, declaration, bytes);
    if identity.status != 0 { return Result {}; }
    return Result { status: 0, source: copy(identity.source) };
}
