// Bounded syntactic completion for the private unified subset. This is not a
// substitute for source/type checking or full K1 finite-fact reachability.
namespace unified_completion;
import unified_core;
struct Summary { falls:bool=true, unreachable:bool=false, truth:i64=0 }
fn check(nodes:unified_core::Node[:], root:i64) -> i64 {
    if nodes.len<1 || nodes.len>2048 || root<1 || root>nodes.len {return 1;}
    var sums:Summary[>..]=[];
    for n,i in nodes {
        var s=Summary {};
        if n.tag==10 {s.truth=2;}
        else if n.tag==11 {s.truth=1;}
        else if n.tag==8 {
            if n.a<1 || n.a>i {return 1;} s.truth=sums[n.a-1].truth;
        } else if n.tag==3 || n.tag==4 || n.tag==5 || n.tag==6 || n.tag==7 || n.tag==9 || n.tag==18 || n.tag==12 || n.tag==13 || n.tag==17 {
            if n.a<1 || n.a>i || n.b<1 || n.b>i {return 1;}
            if n.tag==17 {let a=sums[n.a-1];let b=sums[n.b-1];s.falls=a.falls && b.falls;s.unreachable=a.unreachable || !a.falls || b.unreachable;}
        } else if n.tag==14 || n.tag==15 {
            if n.a<1 || n.a>i {return 1;} if n.tag==15 {s.falls=false;}
        } else if n.tag==16 {
            if n.a<1 || n.a>i || n.b<1 || n.b>i || n.c<0 || n.c>i {return 1;}
            let cond=sums[n.a-1];let yes=sums[n.b-1];var no=Summary {};if n.c!=0 {no=sums[n.c-1];}
            s.falls=if cond.truth==2 {yes.falls} else if cond.truth==1 {no.falls} else {yes.falls || no.falls};
            s.unreachable=yes.unreachable || no.unreachable;
        } else if n.tag!=1 && n.tag!=2 {return 1;}
        sums.push(s);
    }
    let s=sums[root-1]; if s.unreachable {return 8;} return if s.falls {7} else {0};
}
