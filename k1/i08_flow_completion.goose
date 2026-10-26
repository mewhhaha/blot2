// Conservative explicit-transfer completion over independently re-recognized
// source-owned syntax. Not full K1 type/effect/ownership/return checking.
// It handles literal #True/#False reachability, but treats identifiers and
// U32 conditions as unknown; rejecting unreachable code even in a pruned arm
// is a conservative private-subset choice.
namespace i08_flow_completion;
import i08_core;
import i08_header_verify;
struct Summary { falls: bool = true, truth: i64 = 0, unreachable: bool = false, missing_loop_transfer: bool = false }
// 0 no fallthrough/unreachable loop body, 1 invalid tree, 4 function may
// fall through, 8 a statement follows an unconditional transfer, 9 loop body
// may complete without its required explicit transfer.
fn check(tree: i08_core::Tree&, expected_source: u8[:]) -> i64 {
    if !i08_header_verify::verify(tree,expected_source) { return 1; }
    var summaries: Summary[>..] = [];
    for node in tree.nodes {
        var s=Summary {};
        if node.tag==3 { s.truth=2; } else if node.tag==4 { s.truth=1; }
        else if node.tag>=9 && node.tag<=13 { s.falls=false; }
        else if node.tag==14 {
            let condition=summaries[node.a-1]; let yes=summaries[node.b-1]; var no=Summary {};
            if node.c!=0 { no=summaries[node.c-1]; }
            if condition.truth==2 {
                s.falls=yes.falls;
                s.missing_loop_transfer=condition.missing_loop_transfer || yes.missing_loop_transfer;
            } else if condition.truth==1 {
                s.falls=no.falls;
                s.missing_loop_transfer=condition.missing_loop_transfer || no.missing_loop_transfer;
            } else {
                s.falls=yes.falls || no.falls;
                s.missing_loop_transfer=condition.missing_loop_transfer || yes.missing_loop_transfer || no.missing_loop_transfer;
            }
            s.unreachable=condition.unreachable || yes.unreachable || no.unreachable;
        } else if node.tag==15 {
            // Even an always-transferring body may execute zero times.
            let body=summaries[node.e-1]; s.falls=true;
            s.unreachable=body.unreachable;
            s.missing_loop_transfer=body.missing_loop_transfer || body.falls;
        } else if node.tag==16 {
            let child=summaries[node.a-1]; s.falls=child.falls;
            s.unreachable=child.unreachable; s.missing_loop_transfer=child.missing_loop_transfer;
        } else if node.tag==17 {
            let a=summaries[node.a-1]; let b=summaries[node.b-1];
            s.falls=a.falls && b.falls; s.unreachable=a.unreachable || !a.falls || b.unreachable;
            s.missing_loop_transfer=a.missing_loop_transfer || b.missing_loop_transfer;
        } else if node.tag==18 {
            let body=summaries[node.a-1]; s=body;
        }
        summaries.push(s);
    }
    let root=summaries[tree.root-1];
    if root.unreachable { return 8; }
    if root.missing_loop_transfer { return 9; }
    return if root.falls { 4 } else { 0 };
}
