// Bounded source-bound ownership analysis for one input Owned[U32] and one
// Bool. The caller independently establishes their exact names/types, the
// scalar alias, and return mode (0 Unit, 1 Owned, 2 U32). It does not admit a
// complete K1 function, determine arbitrary effects or perform full C09 work.
namespace ownership_check;
import validate;
import ownership_syntax;
import ownership_verify;
struct Contract {owner:u8[]=[],flag:u8[]=[],return_mode:i64=0}
struct Context {live:bool=true,owner:i64=1,active:bool[128]=[false;128],kinds:u8[128]=[0;128],
                loan:i64=0,payloads:i64[32]=[0;32]}
// 0 accepted, 1 malformed tree/contract, 2 affine/name/typing failure,
// 3 outstanding loan, 4 branch state/escape, 5 missing terminal/break,
// 6 unreachable, 7 invalid lexical break.
struct Flow {status:i64=0,falls:bool=true,breaks:bool=false,returns:bool=false,ctx:Context=Context {}}
fn ref(s:u8[:],n:ownership_syntax::Node) -> u8[:] {return s[n.ref_start..n.ref_end];}
fn bind(s:u8[:],t:ownership_syntax::Tree&,id:i64) -> u8[:] {let b=t.bindings[id-1];return s[b.start..b.end];}
fn free_name(s:u8[:],t:ownership_syntax::Tree&,ctx:Context,contract:Contract&,id:i64) -> bool {
    if id<1 || id>t.bindings.len {return false;}
    let v=bind(s,t,id);
    if v==contract.owner || v==contract.flag {return false;}
    for i in t.bindings.len {if ctx.active[i] && v==bind(s,t,i+1) {return false;}}
    return true;
}
fn owner_matches(s:u8[:],t:ownership_syntax::Tree&,ctx:Context,contract:Contract&,n:ownership_syntax::Node) -> bool {
    if !ctx.live {return false;}
    if ctx.owner==1 {return ref(s,n)==contract.owner;}
    let id=ctx.owner-1;if id<1 || id>t.bindings.len || !ctx.active[id-1] || ctx.kinds[id-1]!=1 {return false;}
    return ref(s,n)==bind(s,t,id);
}
fn scalar_matches(s:u8[:],t:ownership_syntax::Tree&,ctx:Context,n:ownership_syntax::Node) -> bool {
    for i in t.bindings.len {if ctx.active[i] && ctx.kinds[i]==2 && ref(s,n)==bind(s,t,i+1) {return true;}}
    return false;
}
fn same(a:Context,b:Context) -> bool {
    if a.live!=b.live || (a.live && a.owner!=b.owner) || a.loan!=b.loan {return false;}
    for i in 128 {if a.active[i]!=b.active[i] || (a.active[i] && a.kinds[i]!=b.kinds[i]) {return false;}}
    for i in a.loan {if a.payloads[i]!=b.payloads[i] {return false;}}
    return true;
}
fn scope(f:Flow,outer:Context) -> Flow {
    var r=f;if r.status!=0 || !r.falls {return r;}
    if r.ctx.live && r.ctx.owner>=2 && !outer.active[r.ctx.owner-2] {r.status=4;return r;}
    for i in 128 {r.ctx.active[i]=outer.active[i];r.ctx.kinds[i]=outer.kinds[i];}
    return r;
}
recursive fn visit(t:ownership_syntax::Tree&,id:i64,ctx:Context,c:Contract&,depth:i64) -> Flow {
    if depth>256 || id<1 || id>t.nodes.len {return Flow {status:1};}
    let n=t.nodes[id-1];let s=t.source;var out=Flow {ctx:ctx};
    if n.tag==8 {
        let first=visit(t,n.a,ctx,c,depth+1);if first.status!=0 {return first;}if !first.falls {return Flow {status:6};}
        var second=visit(t,n.b,first.ctx,c,depth+1);if second.status!=0 {return second;}
        second.breaks=first.breaks || second.breaks;second.returns=first.returns || second.returns;return second;
    }
    if n.tag==1 {
        if ctx.loan!=0 {return Flow {status:3};}
        if !owner_matches(s,t,ctx,c,n) || !free_name(s,t,ctx,c,n.bound) {return Flow {status:2};}
        out.ctx.owner=n.bound+1;out.ctx.active[n.bound-1]=true;out.ctx.kinds[n.bound-1]=1;return out;
    }
    if n.tag==2 {
        if ctx.loan!=0 {return Flow {status:3};}
        if !owner_matches(s,t,ctx,c,n) {return Flow {status:2};}
        out.ctx.live=false;return out;
    }
    if n.tag==3 {
        if !owner_matches(s,t,ctx,c,n) || ctx.loan>=32 || !free_name(s,t,ctx,c,n.bound) ||
           !free_name(s,t,ctx,c,n.region) || !free_name(s,t,ctx,c,n.payload) {return Flow {status:2};}
        let outname=bind(s,t,n.bound);let regname=bind(s,t,n.region);let payloadname=bind(s,t,n.payload);
        if regname==payloadname || outname==regname || outname==payloadname {return Flow {status:2};}
        var inner=ctx;inner.active[n.region-1]=true;inner.kinds[n.region-1]=3;
        inner.active[n.payload-1]=true;inner.kinds[n.payload-1]=4;inner.payloads[ctx.loan]=n.payload;inner.loan+=1;
        let body=visit(t,n.a,inner,c,depth+1);
        if body.status!=0 {return body;}
        if body.falls || !body.breaks || body.returns {return Flow {status:5};}
        out.ctx.active[n.bound-1]=true;out.ctx.kinds[n.bound-1]=2;return out;
    }
    if n.tag==4 {
        if ref(s,n)!=c.flag {return Flow {status:2};}
        let y=scope(visit(t,n.a,ctx,c,depth+1),ctx);if y.status!=0 {return y;}
        var z=Flow {ctx:ctx};if n.b!=0 {z=scope(visit(t,n.b,ctx,c,depth+1),ctx);}
        if z.status!=0 {return z;}
        if y.falls && z.falls && !same(y.ctx,z.ctx) {return Flow {status:4};}
        out.falls=y.falls || z.falls;out.breaks=y.breaks || z.breaks;out.returns=y.returns || z.returns;
        if y.falls {out.ctx=y.ctx;}else if z.falls {out.ctx=z.ctx;}return out;
    }
    if n.tag==5 {
        if ctx.loan!=0 {return Flow {status:3};}if c.return_mode!=0 || ctx.live {return Flow {status:2};}
        out.falls=false;out.returns=true;return out;
    }
    if n.tag==6 {
        if ctx.loan!=0 {return Flow {status:3};}
        if c.return_mode==1 && owner_matches(s,t,ctx,c,n) {out.ctx.live=false;}
        else if c.return_mode==2 && !ctx.live && scalar_matches(s,t,ctx,n) {} else {return Flow {status:2};}
        out.falls=false;out.returns=true;return out;
    }
    if n.tag==7 {
        if ctx.loan<=0 || ctx.loan>32 {return Flow {status:7};}
        let payload=ctx.payloads[ctx.loan-1];
        if payload<1 || payload>t.bindings.len || !ctx.active[payload-1] || ctx.kinds[payload-1]!=4 || ref(s,n)!=bind(s,t,payload) {return Flow {status:7};}
        out.falls=false;out.breaks=true;return out;
    }
    return Flow {status:1};
}
fn check(t:ownership_syntax::Tree&,expected:u8[:],c:Contract&) -> i64 {
    if c.return_mode<0 || c.return_mode>2 || !validate::name_valid(c.owner) || !validate::name_valid(c.flag) ||
       c.owner[..]==c.flag[..] || t.source[..]!=expected || !ownership_verify::verify(t) {return 1;}
    let f=visit(t,t.root,Context {},c,0);if f.status!=0 {return f.status;}
    if f.falls || f.breaks || !f.returns {return 5;}return 0;
}
