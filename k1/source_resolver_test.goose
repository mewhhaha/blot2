import std;
import os;
import source_identity;
import source_resolver;

fn main() {
    let argv = args();
    assert(argv.len == 2);
    var opened = source_resolver::open_root(argv[1], "pkg");
    if opened.status == 4 { print("unsupported source root platform"); return; }
    assert(opened.status == 0);
    var identity = source_resolver::read(opened.root, "safe/main.blot", "answer");
    assert(identity.status == 0);
    assert(source_identity::verify(identity.source, "pkg", "safe/main.blot", "answer", "safe source\n"));
    var linked = source_resolver::read(opened.root, "inside-link.blot", "answer");
    assert(linked.status == 0 && linked.source.bytes[..] == "safe source\n");
    for bad in ["", "/etc/passwd", "../outside/secret.blot", "safe/../../outside/secret.blot",
                "safe//main.blot", "safe/./main.blot", "safe/../main.blot", "safe/",
                "safe\\main.blot", "C:/escape", "outside-link.blot", "outside-dir/secret.blot",
                "fifo", "safe", "missing"] {
        let result = source_resolver::read(opened.root, bad, "answer");
        assert(result.status != 0 && result.source.bytes.len == 0 && result.source.package.len == 0);
    }
    let embedded_nul: u8[4] = ['a', 0, 'b', 'c'];
    let nul_result = source_resolver::read(opened.root, embedded_nul, "answer");
    assert(nul_result.status != 0 && nul_result.source.bytes.len == 0);
    let oversized = source_resolver::read(opened.root, "too-large.blot", "answer");
    assert(oversized.status == 2 && oversized.source.bytes.len == 0);
    // The C boundary must preserve an existing caller buffer on every failure.
    for bad in ["outside-link.blot", "outside-dir/secret.blot", "fifo", "safe", "missing", "../outside/secret.blot"] {
        var out: u8[>..] = []; out.append("sentinel");
        assert(source_resolver::k1_source_read_under(opened.root.handle, bad, out) != 0);
        assert(out[..] == "sentinel");
    }
    var output: u8[>..] = []; output.append("sentinel");
    assert(source_resolver::k1_source_read_under(opened.root.handle, "too-large.blot", output) == 2);
    assert(output[..] == "sentinel");
    assert(source_resolver::close_root(opened.root));
    assert(!source_resolver::close_root(opened.root));
    let closed = source_resolver::read(opened.root, "safe/main.blot", "answer");
    assert(closed.status != 0 && closed.source.bytes.len == 0);
    assert(identity.source.bytes[..] == "safe source\n");
    print("source resolver confinement and ownership laws passed");
}
