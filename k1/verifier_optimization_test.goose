import std;
import module_frontend;

fn main() {
    var empty = module_frontend::Module {};
    assert(!module_frontend::verifier_unique_names(empty));
    assert(!module_frontend::verifier_graph(empty));
    var text: u8[>..] = [];
    var names: module_frontend::Declaration[>..] = [];
    for i in 256 {
        let start = text.len;
        format(text, "name_with_a_long_common_prefix_", 255 - i);
        let end = text.len; text.push(' ');
        names.push(module_frontend::Declaration { name_start: start, name_end: end, form: 1, depth: 1 });
    }
    var module = module_frontend::Module { source: copy(text), declarations: copy(names) };
    assert(module_frontend::verifier_unique_names(module));
    assert(module_frontend::verifier_graph(module));
    // Duplicate spans and negative/out-of-bounds spans must reject before sort.
    let original = module.declarations[255];
    module.declarations[255].name_start = module.declarations[0].name_start;
    module.declarations[255].name_end = module.declarations[0].name_end;
    assert(!module_frontend::verifier_unique_names(module));
    module.declarations[255] = original;
    module.declarations[255].name_start = -1;
    assert(!module_frontend::verifier_unique_names(module));
    module.declarations[255] = original;
    module.declarations[255].name_end = module.source.len + 1;
    assert(!module_frontend::verifier_unique_names(module));
    module.declarations[255] = original;
    assert(module_frontend::verifier_name_order(module.source, module_frontend::Declaration { name_start: -1, name_end: 1 }, original) == 2);
    // 128-long acyclic chain, 129-long rejection, cycles and invalid edges.
    for i in 128 {
        module.declarations[i].form = if i == 127 { 1 } else { 3 };
        module.declarations[i].callee_id = i + 1;
        module.declarations[i].depth = 128 - i;
    }
    assert(module_frontend::verifier_graph(module));
    module.declarations[127].form = 3;
    module.declarations[127].callee_id = 128;
    assert(!module_frontend::verifier_graph(module));
    module.declarations[127].callee_id = 0;
    assert(!module_frontend::verifier_graph(module));
    module.declarations[127].callee_id = 256;
    assert(!module_frontend::verifier_graph(module));
    module.declarations[127].callee_id = -1;
    assert(!module_frontend::verifier_graph(module));
    module.declarations[127].form = 1;
    module.declarations[0].depth = 1;
    assert(!module_frontend::verifier_graph(module));
    module.declarations[0].depth = 128;
    assert(module_frontend::verifier_graph(module));
    // Helpers reject oversized forged owner before touching fixed arrays.
    names.push(module_frontend::Declaration {});
    var oversized = module_frontend::Module { source: copy(text), declarations: copy(names) };
    assert(!module_frontend::verifier_unique_names(oversized));
    assert(!module_frontend::verifier_graph(oversized));
    print("independent verifier helper laws passed");
}
