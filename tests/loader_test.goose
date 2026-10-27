import src.loader;
import os;
fn test_loader() {
    assert(within_package("/a/b", "/a/b/c"));
    assert(!within_package("/a/b", "/a/bad/c"));
    assert(!import_path_valid("../x.blot"));
    assert(!import_path_valid("/x.blot"));
    assert(make_dir("build"));
    assert(make_dir("build/loader"));
    assert(write_file("build/loader/a.blot", "import \"./b.blot\" as b\nlet x = 1\n"));
    assert(write_file("build/loader/b.blot", "let x = 2\n"));
    with_core() { b =>
        var order:u32[>..]=[]; var diags:Diagnostic[>..]=[];
        assert(load_package("build/loader/a.blot", "build/loader", b, order, diags));
        assert(order.len == 2 && order[0] == 2 && order[1] == 1);
    };
    assert(write_file("build/loader/b.blot", "import \"./a.blot\" as a\nlet x = 2\n"));
    with_core() { b =>
        var order:u32[>..]=[]; var diags:Diagnostic[>..]=[];
        assert(!load_package("build/loader/a.blot", "build/loader", b, order, diags));
        assert(diags[0].code == 4002);
    };
    print("loader: passed");
}
