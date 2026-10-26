// Independent transition interpreter for the checked source job. The caller
// still owes a separate proof that the input read loan and builder range are
// disjoint, that the argument capabilities actually exist, and that their
// runtime descriptors/ABI/resources meet the function's contract.
namespace i08_cap_verify;
import i08_job_verify;
import i08_cap_core;
fn matches(p:i08_cap_core::Package&,at:i64,kind:u32,event:u32,node:u32,site:i64,proof:u32)->bool {
    if at<0 || at>=p.steps.len{return false;}
    let s=p.steps[at];return s.kind==kind && s.event==event && s.node==node && s.site==site && s.proof==proof;
}
fn verify(p:i08_cap_core::Package&,source:u8[:])->bool {
    if !i08_job_verify::verify(p.job,source) || p.steps.len>800{return false;}
    var pos:i64=0;var builder:u32=0;var loans:u32=0;var row:bool=false;var finished:bool=false;
    let count=p.job.core.nodes.len;var used:u8[256]=[0;256];
    for e,i in p.job.events {
        let event=(i+1) as u32;
        if finished{return false;}
        if e.kind==1 {
            if builder!=0 || loans!=0 || !matches(p,pos,1,event,0,e.site,0){return false;}
            builder=1;pos+=1;
        } else if e.kind==2 {
            if builder!=1 || loans!=0 || e.node==0 || e.node>count as u32 || e.proof!=3 ||
                !matches(p,pos,2,event,e.node,e.site,e.proof) || !matches(p,pos+1,3,event,e.node,e.site,e.proof) ||
                !matches(p,pos+2,4,event,e.node,e.site,e.proof) {return false;}
            loans=1;
            if used[(e.node-1) as i64]!=0 {return false;} used[(e.node-1) as i64]=1;
            loans=0;pos+=3;
        } else if e.kind==3 || e.kind==4 || e.kind==5 {
            if builder!=1 || loans!=0 || e.node==0 || e.node>count as u32 || !matches(p,pos,5,event,e.node,e.site,0){return false;}
            let n=p.job.core.nodes[(e.node-1) as i64];
            if used[(e.node-1) as i64]!=0{return false;}
            if n.kind==3 || n.kind==4 {
                if n.left==0 || n.right==0 || n.left>=e.node || n.right>=e.node ||
                    used[(n.left-1) as i64]!=1 || used[(n.right-1) as i64]!=1{return false;}
                used[(n.left-1) as i64]=2;used[(n.right-1) as i64]=2;
            } else if n.kind!=2 {return false;}
            used[(e.node-1) as i64]=1;pos+=1;
        } else if e.kind==6 {
            let x=p.job.core.x_root;let y=p.job.core.y_root;
            if builder!=1 || loans!=0 || row || x==0 || y==0 || x>count as u32 || y>count as u32 || x==y ||
                used[(x-1) as i64]!=1 || used[(y-1) as i64]!=1 || !matches(p,pos,6,event,0,e.site,0){return false;}
            used[(x-1) as i64]=2;used[(y-1) as i64]=2;
            for u in used[..count] {if u!=2{return false;}} row=true;pos+=1;
        } else if e.kind==7 {
            if builder!=1 || loans!=0 || !row || e.proof!=4 || !matches(p,pos,7,event,0,e.site,4){return false;}
            builder=2;row=false;pos+=1;
        } else if e.kind==8 {
            if builder!=2 || loans!=0 || e.proof!=5 || !matches(p,pos,8,event,0,e.site,5){return false;}
            // The loop carry reestablishes the source-bound Init(b)=i
            // invariant for the next iteration. The checked proof ties the
            // successor's version to the declared next state.
            builder=1;pos+=1;
        } else if e.kind==9 {
            if builder!=1 || loans!=0 || e.proof!=6 || !matches(p,pos,9,event,0,e.site,6){return false;}
            builder=3;pos+=1;
        } else if e.kind==10 {
            if builder!=3 || loans!=0 || !matches(p,pos,10,event,0,e.site,0){return false;}
            builder=4;finished=true;pos+=1;
        } else {return false;}
    }
    return pos==p.steps.len && finished && builder==4 && loans==0 && !row;
}
