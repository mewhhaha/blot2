// Source mutations exercise the producer and the independent source verifier.
import flow_parse;
import flow_verify;
import flow_completion;

fn mutations(source: u8[:]) {
    var bytes: u8[>..] = []; bytes.append(source);
    let replacements: u8[6] = [0, '\n', ':', ' ', 'x', 255];
    for p in bytes.len {
        let old = bytes[p];
        for replacement in replacements {
            bytes[p] = replacement;
            var tree, status = flow_parse::parse(bytes);
            if status == 0 {
                assert(flow_verify::verify(tree));
                let checked = flow_completion::check(tree);
                assert(checked == 0 || checked == 4 || checked == 8 || checked == 9);
            } else { assert(tree.nodes.len == 0); }
        }
        bytes[p] = old;
    }
}
fn main() {
    mutations("do:\n  return do:\n    if x:\n      break f(1,2)\n    else:\n      return ()\n");
    mutations("do:\n  if #False:\n    return f()\n  else:\n    return (1,(2,3))\n");
    mutations("do:\n  return do:\n    break do:\n      break (1,2)\n");
    print("flow source mutation checks passed");
}
