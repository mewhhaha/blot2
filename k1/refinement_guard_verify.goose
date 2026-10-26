// Independent source-bound U32 successor safety checker for the unified
// fixture. It uses a two-bit abstract domain per immutable value (non-MAX and
// MAX), never the producer's guard IDs, evidence records or success flag.
// This is not general K1 proof admission or a complete work receipt.
namespace refinement_guard_verify;
import unified_core;
import unified_shape;
import work;
struct State { reachable:bool=true, possible:u8[129]=[3;129], aliases:i64[129]=[0;129] }
struct Split { status:i64=0, on_true:State=State {}, on_false:State=State {} }
struct End { status:i64=0, state:State=State {} }
struct Move { kind:i64=0, id:i64=0 }
struct Budget { visits:i64=0, receipt:work::Receipt=work::Receipt {} }
fn spend(b:Budget&,m:work::Meter&)->bool {
    if b.visits>=32768 {return false;}
    let r=work::charge(m,4,20);if r.status!=0 {b.receipt=r;return false;}b.visits+=1;return true;
}
fn reference(p:unified_core::Program&,id:i64,st:State)->i64 {
    var i=id;var n=0;
    while i>0 && i<=p.nodes.len && p.nodes[i-1].tag==8 {n+=1;if n>64{return -1;}i=p.nodes[i-1].a;}
    if i<1 || i>p.nodes.len{return -1;}let x=p.nodes[i-1];
    if x.tag!=1 || x.a<0 || x.a>=129 {return -1;}return st.aliases[x.a];
}
fn exact(p:unified_core::Program&,id:i64,value:u32)->bool {return id>0 && id<=p.nodes.len && p.nodes[id-1].tag==2 && p.nodes[id-1].literal==value;}
fn combine(a:State,b:State)->State {
    if !a.reachable {return b;}if !b.reachable {return a;}
    var s=a;for i in 129 {s.possible[i]=a.possible[i] | b.possible[i];if a.aliases[i]!=b.aliases[i] {s.aliases[i]=i;s.possible[i]=3;}}
    return s;
}
fn narrow(st:State,slot:i64,allowed:u8)->State {
    var s=st;if !s.reachable || slot<0 || slot>=129 {return s;}
    s.possible[slot]=s.possible[slot] & allowed;if s.possible[slot]==0 {s.reachable=false;}return s;
}
fn number(p:unified_core::Program&,id:i64,st:State,b:Budget&,m:work::Meter&)->i64 {
    if !st.reachable {return 0;}var pending:Move[>..]=[];pending.push(Move {kind:1,id:id});
    while pending.len>0 {
        if !spend(b,m) {return 2;}let a=pending[pending.len-1];pending.pop();
        if a.id<1 || a.id>p.nodes.len {return 1;}let n=p.nodes[a.id-1];
        if a.kind==2 {
            let l=p.nodes[n.a-1];let r=p.nodes[n.b-1];
            let known=(l.tag==2 && l.literal==0) || (r.tag==2 && r.literal==0) ||
                (l.tag==2 && r.tag==2 && (l.literal as u64)+r.literal<=4294967295);
            if !known {
                var subject:i64=-1;
                if exact(p,n.b,1) {subject=reference(p,n.a,st);} else if exact(p,n.a,1) {subject=reference(p,n.b,st);}
                if subject<0 || subject>=129 || (st.possible[subject] & 2)!=0 {return 5;}
            }
        } else if a.kind==1 {
            if n.tag==1 || n.tag==2 {continue;}
            if n.tag==3 {pending.push(Move {kind:2,id:a.id});pending.push(Move {kind:1,id:n.b});pending.push(Move {kind:1,id:n.a});}
            else if n.tag==4 || n.tag==5 || n.tag==6 || n.tag==7 {pending.push(Move {kind:1,id:n.b});pending.push(Move {kind:1,id:n.a});}
            else if n.tag==8 {pending.push(Move {kind:1,id:n.a});}
            else {return 1;}
        } else {return 1;}
    }
    return 0;
}
recursive fn branch(p:unified_core::Program&,id:i64,st:State,b:Budget&,m:work::Meter&,depth:i64)->Split {
    if depth>64 {return Split {status:2};}
    if !st.reachable {return Split {on_true:st,on_false:st};}
    if !spend(b,m) {return Split {status:2};}
    if id<1 || id>p.nodes.len {return Split {status:1};}let n=p.nodes[id-1];
    if n.tag==8 {return branch(p,n.a,st,b,m,depth+1);}
    if n.tag==10 || n.tag==11 {var yes=st;var no=st;if n.tag==10 {no.reachable=false;}else {yes.reachable=false;}return Split {on_true:yes,on_false:no};}
    if n.tag==9 {
        let l=number(p,n.a,st,b,m);if l!=0{return Split {status:l};}
        let r=number(p,n.b,st,b,m);if r!=0{return Split {status:r};}
        let slot=if exact(p,n.b,4294967295) {reference(p,n.a,st)} else {-1};
        if slot<0 {return Split {on_true:st,on_false:st};}
        return Split {on_true:narrow(st,slot,1),on_false:narrow(st,slot,2)};
    }
    if n.tag==12 || n.tag==13 {
        var todo:i64[2048]=[0;2048];var length:i64=0;var cursor=id;
        while cursor>0 && cursor<=p.nodes.len && p.nodes[cursor-1].tag==n.tag {
            let x=p.nodes[cursor-1];if length>=2048{return Split {status:2};}todo[length]=x.b;length+=1;cursor=x.a;
            if cursor!=id && !spend(b,m){return Split {status:2};}
        }
        var state=branch(p,cursor,st,b,m,depth+1);if state.status!=0{return state;}
        while length>0 {
            length-=1;let next=todo[length];let lhs=if n.tag==12 {state.on_true} else {state.on_false};
            if !lhs.reachable {continue;}let rhs=branch(p,next,lhs,b,m,depth+1);if rhs.status!=0{return rhs;}
            if n.tag==12 {state.on_false=combine(state.on_false,rhs.on_false);state.on_true=rhs.on_true;}
            else {state.on_true=combine(state.on_true,rhs.on_true);state.on_false=rhs.on_false;}
        }
        return state;
    }
    return Split {status:1};
}
recursive fn suite(p:unified_core::Program&,id:i64,initial:State,b:Budget&,m:work::Meter&,depth:i64)->End {
    if depth>64{return End {status:2};}var current=initial;
    var stack:i64[2048]=[0;2048];var count:i64=1;stack[0]=id;
    while count>0 && current.reachable {
        if !spend(b,m){return End {status:2};}count-=1;let id=stack[count];
        if id<1 || id>p.nodes.len{return End {status:1};}let n=p.nodes[id-1];
        if n.tag==17 {if count+2>2048{return End {status:2};}stack[count]=n.b;stack[count+1]=n.a;count+=2;}
        else if n.tag==14 {let status=number(p,n.a,current,b,m);if status!=0{return End {status:status};}let root=reference(p,n.a,current);current.aliases[n.b]=if root<0 {n.b} else {root};}
        else if n.tag==15 {let status=number(p,n.a,current,b,m);if status!=0{return End {status:status};}current.reachable=false;}
        else if n.tag==16 {
            let s=branch(p,n.a,current,b,m,0);if s.status!=0{return End {status:s.status};}
            var yes=End {state:s.on_true};var no=End {state:s.on_false};
            if s.on_true.reachable {yes=suite(p,n.b,s.on_true,b,m,depth+1);if yes.status!=0{return yes;}}
            if n.c!=0 && s.on_false.reachable {no=suite(p,n.c,s.on_false,b,m,depth+1);if no.status!=0{return no;}}
            current=combine(yes.state,no.state);
        } else {return End {status:1};}
    }
    return End {state:current};
}
fn check_with_work(source:u8[:],p:unified_core::Program&,m:work::Meter&)->i64 {
    if !unified_shape::verify(source,p){return 1;}
    var start=State {};for i in 129 {start.aliases[i]=i;}
    var budget=Budget {};let result=suite(p,p.root,start,budget,m,0);return result.status;
}
fn check(source:u8[:],p:unified_core::Program&)->bool {var meter=work::Meter {};return check_with_work(source,p,meter)==0;}
