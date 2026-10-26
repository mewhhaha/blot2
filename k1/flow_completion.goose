// Experimental syntactic reachability, only on independently re-recognized
// source trees. It is not full K1 completion: typing, effects, name resolution,
// finite facts, affine values, budgets and function contracts remain absent.
namespace flow_completion;
import flow_syntax;
import flow_verify;
struct Summary { truth: i64 = 0, falls: bool = true, unreachable: bool = false }
// 0 every reachable normal path transfers; 4 may fall through; 8 a
// reachable statement follows an unconditional transfer; 1 invalid tree.
// Truth tags: 0 unknown, 1 false, 2 true. Only a literal and transparent
// grouping are recognized; all operators and calls remain unknown.
fn check(tree: flow_syntax::Tree&) -> i64 {
    if !flow_verify::verify(tree) { return 1; }
    var out: Summary[>..] = [];
    for n in tree.nodes {
        var s = Summary {};
        if n.tag == 3 { s.truth = 1; }
        else if n.tag == 4 { s.truth = 2; }
        else if n.tag == 5 { s.truth = out[n.a-1].truth; }
        else if n.tag == 9 { s.falls = false; }
        else if n.tag == 10 {
            let truth = out[n.a-1].truth; let yes = out[n.b-1];
            var no = Summary {}; if n.c != 0 { no = out[n.c-1]; }
            if truth == 2 { s.falls = yes.falls; }
            else if truth == 1 { s.falls = no.falls; }
            else { s.falls = yes.falls || no.falls; }
            // Conservatively reject unreachable code even inside a pruned arm.
            s.unreachable = yes.unreachable || no.unreachable;
        } else if n.tag == 11 {
            let a = out[n.a-1]; let b = out[n.b-1];
            s.falls = a.falls && b.falls;
            s.unreachable = a.unreachable || !a.falls || (a.falls && b.unreachable);
        }
        out.push(s);
    }
    let root = out[tree.root-1];
    if root.unreachable { return 8; }
    return if root.falls { 4 } else { 0 };
}
