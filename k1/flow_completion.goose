// Experimental syntactic reachability, only on independently re-recognized
// source trees. It is not full K1 completion: typing, effects, name resolution,
// finite facts, affine values, budgets and function contracts remain absent.
namespace flow_completion;
import flow_syntax;
import flow_verify;
struct Summary { truth: i64 = 0, falls: bool = true, breaks: bool = false, unreachable: bool = false, missing_break: bool = false }
// 0 every reachable normal path transfers; 4 may fall through; 8 a
// reachable statement follows an unconditional transfer; 9 value block can
// fall through without a break; 1 invalid tree.
// Truth tags: 0 unknown, 1 false, 2 true. Only a literal and transparent
// grouping are recognized; all operators and calls remain unknown.
fn check(tree: flow_syntax::Tree&) -> i64 {
    if !flow_verify::verify(tree) { return 1; }
    var out: Summary[>..] = [];
    for n in tree.nodes {
        var s = Summary {};
        if n.tag == 3 { s.truth = 1; }
        else if n.tag == 4 { s.truth = 2; }
        else if n.tag == 5 || n.tag == 14 { s = out[n.a-1]; }
        else if n.tag == 6 || n.tag == 13 {
            let a = out[n.a-1]; let b = out[n.b-1];
            s.falls = a.falls && b.falls;
            s.breaks = a.breaks || (a.falls && b.breaks);
            s.unreachable = a.unreachable || b.unreachable;
            s.missing_break = a.missing_break || (a.falls && b.missing_break);
        } else if n.tag == 7 || n.tag == 8 {
            let a = out[n.a-1]; let b = out[n.b-1];
            let skip = if n.tag == 7 { a.truth != 2 } else { a.truth != 1 };
            let take = if n.tag == 7 { a.truth != 1 } else { a.truth != 2 };
            s.falls = a.falls && (skip || (take && b.falls));
            s.breaks = a.breaks || (a.falls && take && b.breaks);
            s.unreachable = a.unreachable || b.unreachable;
            s.missing_break = a.missing_break || (a.falls && take && b.missing_break);
        } else if n.tag == 9 || n.tag == 16 {
            let e = out[n.a-1]; s.falls = false;
            s.breaks = e.breaks || (n.tag == 16 && e.falls);
            s.unreachable = e.unreachable; s.missing_break = e.missing_break;
        } else if n.tag == 15 {
            let body = out[n.a-1]; s.falls = body.breaks;
            s.unreachable = body.unreachable;
            s.missing_break = body.missing_break || body.falls;
        }
        else if n.tag == 10 {
            let cond = out[n.a-1]; let truth = cond.truth; let yes = out[n.b-1];
            var no = Summary {}; if n.c != 0 { no = out[n.c-1]; }
            if truth == 2 { s.falls = cond.falls && yes.falls; s.breaks = cond.breaks || (cond.falls && yes.breaks); s.missing_break = cond.missing_break || (cond.falls && yes.missing_break); }
            else if truth == 1 { s.falls = cond.falls && no.falls; s.breaks = cond.breaks || (cond.falls && no.breaks); s.missing_break = cond.missing_break || (cond.falls && no.missing_break); }
            else { s.falls = cond.falls && (yes.falls || no.falls); s.breaks = cond.breaks || (cond.falls && (yes.breaks || no.breaks)); s.missing_break = cond.missing_break || (cond.falls && (yes.missing_break || no.missing_break)); }
            // Conservatively reject unreachable code even inside a pruned arm.
            s.unreachable = cond.unreachable || yes.unreachable || no.unreachable;
        } else if n.tag == 11 {
            let a = out[n.a-1]; let b = out[n.b-1];
            s.falls = a.falls && b.falls;
            s.breaks = a.breaks || (a.falls && b.breaks);
            s.unreachable = a.unreachable || !a.falls || (a.falls && b.unreachable);
            s.missing_break = a.missing_break || (a.falls && b.missing_break);
        }
        out.push(s);
    }
    let root = out[tree.root-1];
    if root.unreachable { return 8; }
    if root.missing_break { return 9; }
    return if root.falls { 4 } else { 0 };
}
