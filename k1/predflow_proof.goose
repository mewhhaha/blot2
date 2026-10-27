// Independent source-bound U32 successor safety checker for the unified
// fixture. It uses a two-bit abstract domain per immutable value (non-MAX and
// MAX), and replays each producer evidence record against independently tracked
// source guard origins and edge polarity; no success flag grants authority.
// This is not general K1 proof admission or a complete work receipt.
namespace predflow_proof;
import unified_core;
import predflow_guard;
import predflow_shape;
import work;
// Active source comparisons are independently rebuilt from immutable SSA
// references. A fact is available only in the path/branch that produced it.
struct Relation { left:i64=-1, right:i64=-1, strict:bool=false, guard_id:i64=0, guard_true:bool=false }
struct State { reachable:bool=true, possible:u8[129]=[3;129], aliases:i64[129]=[0;129], origin:i64[129]=[0;129], origin_true:bool[129]=[false;129], relations:Relation[64]=[Relation {};64], relation_count:i64=0 }
struct Split { status:i64=0, on_true:State=State {}, on_false:State=State {} }
struct End { status:i64=0, state:State=State {} }
struct Move { kind:i64=0, id:i64=0 }
struct Budget { visits:i64=0, receipt:work::Receipt=work::Receipt {}, must_match:bool=false, matched:i64=0, events:predflow_guard::Evidence[]=[] }
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
struct Join {status:i64=0,state:State=State {}}
fn same_relation(a:Relation,b:Relation)->bool {
    return a.left==b.left && a.right==b.right && a.strict==b.strict && a.guard_id==b.guard_id && a.guard_true==b.guard_true;
}
// Conservatively intersect exact source evidence across reachable predecessors.
fn combine(a:State,b:State,budget:Budget&,meter:work::Meter&)->Join {
    if !a.reachable {return Join {state:b};}if !b.reachable {return Join {state:a};}
    var s=a;for i in 129 {
        s.possible[i]=a.possible[i] | b.possible[i];
        if a.origin[i]!=b.origin[i] || a.origin_true[i]!=b.origin_true[i] {s.origin[i]=0;s.origin_true[i]=false;s.possible[i]=3;}
        if a.aliases[i]!=b.aliases[i] {s.aliases[i]=i;s.possible[i]=3;s.origin[i]=0;s.origin_true[i]=false;}
    }
    s.relation_count=0; s.relations=[Relation {};64];
    for i in a.relation_count {
        var common=false;
        for j in b.relation_count {
            if !spend(budget,meter) {return Join {status:2};}
            if same_relation(a.relations[i],b.relations[j]) {common=true;break;}
        }
        if common {s.relations[s.relation_count]=a.relations[i];s.relation_count+=1;}
    }
    return Join {state:s};
}
// A strict self-edge is unreachable; reflexive <= needs no stored fact.
fn add_relation(st:State,left:i64,right:i64,strict:bool,guard_id:i64,guard_true:bool,b:Budget&,m:work::Meter&)->Join {
    var out=st;if !out.reachable || left<0 || right<0 {return Join {state:out};}
    if left>=129 || right>=129 || guard_id<=0 {return Join {status:1};}
    if left==right {if strict {out.reachable=false;}return Join {state:out};}
    let candidate=Relation {left:left,right:right,strict:strict,guard_id:guard_id,guard_true:guard_true};
    for i in out.relation_count {
        if !spend(b,m) {return Join {status:2};}
        if same_relation(out.relations[i],candidate) {return Join {state:out};}
    }
    if out.relation_count>=64 || !spend(b,m) {return Join {status:2};}
    out.relations[out.relation_count]=candidate;out.relation_count+=1;return Join {state:out};
}
// Used only by standalone safety checks without producer evidence. Each step
// is an available <= or < fact and any known non-MAX destination suffices.
fn reachable_nonmax(st:State,start:i64,b:Budget&,m:work::Meter&)->i64 {
    if start<0 || start>=129 {return 1;}
    var queue:i64[129]=[0;129];var depths:u8[129]=[0;129];var seen:bool[129]=[false;129];
    var head:i64=0;var count:i64=1;queue[0]=start;seen[start]=true;
    while head<count {
        if !spend(b,m) {return 2;}let here=queue[head];let depth=depths[head];head+=1;
        if (st.possible[here] & 2)==0 {return 0;}
        if depth>=16 {continue;}
        for i in st.relation_count {
            if !spend(b,m) {return 2;}let edge=st.relations[i];
            if edge.left!=here || edge.right<0 || edge.right>=129 {continue;}
            if !spend(b,m) {return 2;}
            if !seen[edge.right] {if count>=129 {return 2;}seen[edge.right]=true;queue[count]=edge.right;depths[count]=depth+1;count+=1;}
        }
    }
    return 5;
}
fn narrow(st:State,slot:i64,allowed:u8,origin:i64,edge_true:bool)->State {
    var s=st;if !s.reachable || slot<0 || slot>=129 {return s;}
    let before=s.possible[slot];s.possible[slot]=before & allowed;
    if s.possible[slot]==0 {s.reachable=false;}
    else if before==3 && s.possible[slot]!=3 {s.origin[slot]=origin;s.origin_true[slot]=edge_true;}
    return s;
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
                var subject:i64=-1;var reference_id:i64=0;var one:i64=0;
                if exact(p,n.b,1) {subject=reference(p,n.a,st);reference_id=n.a;one=n.b;}
                else if exact(p,n.a,1) {subject=reference(p,n.b,st);reference_id=n.b;one=n.a;}
                if subject<0 || subject>=129 {return 5;}
                if !b.must_match {
                    let path=reachable_nonmax(st,subject,b,m);if path!=0 {return path;}
                } else {
                    if !spend(b,m) {return 2;}
                    if b.matched<0 || b.matched>=b.events.len {return 1;}
                    let index=b.matched;b.matched+=1;
                    if b.events[index].subject!=subject || b.events[index].reference!=reference_id ||
                       b.events[index].one!=one || b.events[index].addition!=a.id || b.events[index].path_count>16 {return 1;}
                    var current=subject;
                    for path in b.events[index].path_count {
                        // Charge the evidence link before reading its producer
                        // guard ID/polarity, then charge every fact inspected.
                        if !spend(b,m) {return 2;}
                        let guard_id=b.events[index].path_guard[path];let polarity=b.events[index].path_true[path];
                        var found=false;
                        for i in st.relation_count {
                            if !spend(b,m) {return 2;}let edge=st.relations[i];
                            if edge.guard_id==guard_id && edge.guard_true==polarity && edge.left==current {
                                current=edge.right;found=true;break;
                            }
                        }
                        if !found || current<0 || current>=129 {return 1;}
                    }
                    for path in b.events[index].path_count..16 {
                        if !spend(b,m) {return 2;}
                        if b.events[index].path_guard[path]!=0 || b.events[index].path_true[path] {return 1;}
                    }
                    // Charge the terminal fact and its provenance before inspection.
                    if !spend(b,m) {return 2;}
                    if (st.possible[current] & 2)!=0 || st.origin[current]<=0 ||
                       b.events[index].guard_id!=st.origin[current] || b.events[index].guard_true!=st.origin_true[current] {return 1;}
                }
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
    if n.tag==9 || n.tag==18 {
        let l=number(p,n.a,st,b,m);if l!=0{return Split {status:l};}
        let r=number(p,n.b,st,b,m);if r!=0{return Split {status:r};}
        var slot:i64=-1;var on_true:u8=0;var only_true=false;
        if n.tag==9 && exact(p,n.b,4294967295) {slot=reference(p,n.a,st);on_true=1;}
        else if n.tag==18 && exact(p,n.b,4294967294) {slot=reference(p,n.a,st);on_true=1;}
        else if n.tag==9 && exact(p,n.a,4294967294) {slot=reference(p,n.b,st);on_true=2;}
        else if n.tag==18 && exact(p,n.a,4294967295) {slot=reference(p,n.b,st);on_true=2;}
        else if n.tag==9 {slot=reference(p,n.a,st);on_true=1;only_true=true;}
        var yes=st;var no=st;
        if slot>=0 {
            yes=narrow(st,slot,on_true,id,true);
            if !only_true {no=narrow(st,slot,if on_true==1 {2} else {1},id,false);}
        }
        let left=reference(p,n.a,st);let right=reference(p,n.b,st);
        if left>=0 && right>=0 {
            let y=add_relation(yes,left,right,n.tag==9,id,true,b,m);if y.status!=0{return Split {status:y.status};}yes=y.state;
            let z=add_relation(no,right,left,n.tag==18,id,false,b,m);if z.status!=0{return Split {status:z.status};}no=z.state;
            // Strict source edges establish the left endpoint < MAX. The
            // false edge of <= is the reversed strict relation.
            if n.tag==9 {yes=narrow(yes,left,1,id,true);}
            else {no=narrow(no,right,1,id,false);}
        }
        return Split {on_true:yes,on_false:no};
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
            if n.tag==12 {let joined=combine(state.on_false,rhs.on_false,b,m);if joined.status!=0{return Split {status:joined.status};}state.on_false=joined.state;state.on_true=rhs.on_true;}
            else {let joined=combine(state.on_true,rhs.on_true,b,m);if joined.status!=0{return Split {status:joined.status};}state.on_true=joined.state;state.on_false=rhs.on_false;}
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
        else if n.tag==15 {let result=branch(p,n.a,current,b,m,0);if result.status!=0{return End {status:result.status};}current.reachable=false;}
        else if n.tag==16 {
            let s=branch(p,n.a,current,b,m,0);if s.status!=0{return End {status:s.status};}
            var yes=End {state:s.on_true};var no=End {state:s.on_false};
            if s.on_true.reachable {yes=suite(p,n.b,s.on_true,b,m,depth+1);if yes.status!=0{return yes;}}
            if n.c!=0 && s.on_false.reachable {no=suite(p,n.c,s.on_false,b,m,depth+1);if no.status!=0{return no;}}
            let joined=combine(yes.state,no.state,b,m);if joined.status!=0{return End {status:joined.status};}current=joined.state;
        } else {return End {status:1};}
    }
    return End {state:current};
}
fn check_with_work(source:u8[:],p:unified_core::Program&,m:work::Meter&)->i64 {
    if !predflow_shape::verify(source,p){return 1;}
    var start=State {};for i in 129 {start.aliases[i]=i;}
    var budget=Budget {};let result=suite(p,p.root,start,budget,m,0);return result.status;
}
fn check(source:u8[:],p:unified_core::Program&)->bool {var meter=work::Meter {};return check_with_work(source,p,meter)==0;}

// Independently check that every produced proof record names the exact guarded
// value, successor operation and actual dominating source edge; extra records
// are rejected. No portable artifact authority is implied.
fn verify_evidence(source:u8[:],p:unified_core::Program&,events:predflow_guard::Evidence[:])->bool {
    if !predflow_shape::verify(source,p){return false;}
    var start=State {};for i in 129 {start.aliases[i]=i;}
    var owned:predflow_guard::Evidence[>..]=[];owned.append(events);
    var meter=work::Meter {};var budget=Budget {must_match:true,events:copy(owned)};
    let result=suite(p,p.root,start,budget,meter,0);return result.status==0 && budget.matched==budget.events.len;
}
