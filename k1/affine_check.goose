// Independent source-checked, path-sensitive analysis for the restricted
// fixture. This is not general K1 inference, type checking, proof accounting or
// public admission. Input h: Owned[ScalarPayload[_]] and flag: Bool are trusted
// surrounding bindings; the caller also supplies an independently checked
// return mode (0 Unit, 1 Owned). All scope and terminal obligations in this
// subset are checked on every possible branch, without relying on last use.
namespace affine_check;
import affine_syntax;
import affine_verify;
struct Context { owner:i64 = 1, moved_decl:bool = false, value_decl:bool = false, loan:i64 = 0 }
// status: 0 success; 1 invalid source/tree/contract; 2 owner misuse;
// 3 loan conflict; 4 incompatible branch state/escaping branch-local owner;
// 5 missing terminal/break; 6 unreachable statement; 7 invalid break.
struct Flow { status:i64 = 0, falls:bool = true, breaks:bool = false, returns:bool = false, ctx:Context = Context {} }
fn same(a:Context,b:Context) -> bool {
    return a.owner==b.owner && a.moved_decl==b.moved_decl && a.value_decl==b.value_decl && a.loan==b.loan;
}
fn scope(f:Flow, outer:Context) -> Flow {
    var x=f;
    if x.status!=0 || !x.falls {return x;}
    if x.ctx.owner==2 && !outer.moved_decl { x.status=4; return x; }
    x.ctx.moved_decl=outer.moved_decl; x.ctx.value_decl=outer.value_decl;
    return x;
}
recursive fn visit(tree:affine_syntax::Tree&, id:i64, ctx:Context, mode:i64, depth:i64) -> Flow {
    if depth>256 || id<1 || id>tree.nodes.len { return Flow {status:1}; }
    let n=tree.nodes[id-1]; var out=Flow {ctx:ctx};
    if n.tag==8 {
        let first=visit(tree,n.a,ctx,mode,depth+1); if first.status!=0 {return first;}
        if !first.falls {return Flow {status:6};}
        var second=visit(tree,n.b,first.ctx,mode,depth+1); if second.status!=0 {return second;}
        second.breaks = first.breaks || second.breaks; second.returns = first.returns || second.returns;
        return second;
    }
    if n.tag==1 {
        if ctx.loan!=0 {return Flow {status:3};}
        if ctx.owner!=1 || ctx.moved_decl {return Flow {status:2};}
        out.ctx.owner=2; out.ctx.moved_decl=true; return out;
    }
    if n.tag==2 {
        if ctx.loan!=0 {return Flow {status:3};}
        if ctx.owner!=n.owner || ctx.owner==0 {return Flow {status:2};}
        out.ctx.owner=0; return out;
    }
    if n.tag==3 {
        if ctx.owner!=n.owner || ctx.owner==0 || ctx.value_decl {return Flow {status:2};}
        // The fixture names only one r/payload pair and does not implement
        // nested binder shadowing; nested openings are therefore unsupported.
        if ctx.loan!=0 {return Flow {status:3};}
        var inner=ctx; inner.loan+=1;
        let body=visit(tree,n.a,inner,mode,depth+1);
        if body.status!=0 {return body;}
        if body.falls || !body.breaks || body.returns {return Flow {status:5};}
        // The only permitted opened value is U32; ending its lexical scope
        // restores the prior owner and loans. The scalar binding is now live.
        out.ctx.value_decl=true; return out;
    }
    if n.tag==4 {
        let y=scope(visit(tree,n.a,ctx,mode,depth+1),ctx); if y.status!=0 {return y;}
        var z=Flow {ctx:ctx};
        if n.b!=0 {z=scope(visit(tree,n.b,ctx,mode,depth+1),ctx);}
        if z.status!=0 {return z;}
        if y.falls && z.falls && !same(y.ctx,z.ctx) {return Flow {status:4};}
        out.falls=y.falls || z.falls; out.breaks=y.breaks || z.breaks; out.returns=y.returns || z.returns;
        if y.falls {out.ctx=y.ctx;} else if z.falls {out.ctx=z.ctx;}
        return out;
    }
    if n.tag==5 {
        if ctx.loan!=0 {return Flow {status:3};}
        if mode!=0 || ctx.owner!=0 {return Flow {status:2};}
        out.falls=false; out.returns=true; return out;
    }
    if n.tag==6 {
        if ctx.loan!=0 {return Flow {status:3};}
        if mode!=1 || ctx.owner!=n.owner || ctx.owner==0 {return Flow {status:2};}
        out.falls=false; out.returns=true; out.ctx.owner=0; return out;
    }
    if n.tag==7 {
        if ctx.loan==0 {return Flow {status:7};}
        out.falls=false; out.breaks=true; return out;
    }
    return Flow {status:1};
}
fn check(tree:affine_syntax::Tree&, expected_source:u8[:], return_mode:i64) -> i64 {
    if return_mode<0 || return_mode>1 || tree.source[..]!=expected_source || !affine_verify::verify(tree) {return 1;}
    let result=visit(tree,tree.root,Context {},return_mode,0);
    if result.status!=0 {return result.status;}
    if result.falls || result.breaks || !result.returns {return 5;}
    return 0;
}
