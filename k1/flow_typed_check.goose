// Independent rechecking of the experimental flow typing record. Replays the
// source recognizer and computes types and decimal values from source bytes;
// producer annotations and digests are not authority.
namespace flow_typed_check;
import flow_typed;
import flow_verify;
import flow_completion;
import validate;

fn verify(p: flow_typed::Program&) -> bool {
    if !validate::name_valid(p.name) || !validate::name_valid(p.parameter) ||
       p.types.len != p.tree.nodes.len || p.literals.len != p.tree.nodes.len ||
       !flow_verify::verify(p.tree) || flow_completion::check(p.tree) != 0 { return false; }
    var types: u8[>..] = [];
    for n, i in p.tree.nodes {
        var want: u8 = 0; var value: u64 = 0;
        if n.tag == 1 {
            if p.tree.source[n.start..n.end] != p.parameter { return false; }
            want = 1;
        } else if n.tag == 2 {
            for c in p.tree.source[n.start..n.end] {
                if c < '0' || c > '9' { return false; }
                let d = (c-'0') as u64;
                if value > (4294967295-d)/10 { return false; }
                value = value*10+d;
            }
            want = 2;
        } else if n.tag == 3 || n.tag == 4 { want = 1; }
        else if n.tag == 5 { want = types[n.a-1]; }
        else if n.tag == 7 || n.tag == 8 {
            if types[n.a-1] != 1 || types[n.b-1] != 1 { return false; }
            want = 1;
        } else if n.tag == 9 {
            if types[n.a-1] != 2 { return false; }
            want = 3;
        } else if n.tag == 10 {
            if types[n.a-1] != 1 || types[n.b-1] != 3 || (n.c != 0 && types[n.c-1] != 3) { return false; }
            want = 3;
        } else if n.tag == 11 {
            if types[n.a-1] != 3 || types[n.b-1] != 3 { return false; }
            want = 3;
        } else { return false; }
        if p.types[i] != want || p.literals[i] != value as u32 { return false; }
        types.push(want);
    }
    return types[p.tree.root-1] == 3;
}
