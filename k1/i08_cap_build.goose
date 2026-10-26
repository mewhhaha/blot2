// Compiler constructs source-local capabilities; the integer indices are
// bookkeeping inside this one package, not independently trusted authority.
namespace i08_cap_build;
import i08_job_build;
import i08_cap_core;
fn build(source:u8[:])->i08_cap_core::Package,i64 {
    var job,status=i08_job_build::build(source);if status!=0{return i08_cap_core::Package {},status;}
    var steps:i08_cap_core::Step[>..]=[];
    for e,i in job.events {
        let id=(i+1) as u32;
        if e.kind==1 {steps.push(i08_cap_core::Step {kind:1,event:id,site:e.site});}
        else if e.kind==2 {
            steps.push(i08_cap_core::Step {kind:2,event:id,node:e.node,site:e.site,proof:e.proof});
            steps.push(i08_cap_core::Step {kind:3,event:id,node:e.node,site:e.site,proof:e.proof});
            steps.push(i08_cap_core::Step {kind:4,event:id,node:e.node,site:e.site,proof:e.proof});
        } else if e.kind==3 || e.kind==4 || e.kind==5 {steps.push(i08_cap_core::Step {kind:5,event:id,node:e.node,site:e.site});}
        else if e.kind==6 {steps.push(i08_cap_core::Step {kind:6,event:id,site:e.site});}
        else if e.kind==7 {steps.push(i08_cap_core::Step {kind:7,event:id,site:e.site,proof:e.proof});}
        else if e.kind==8 {steps.push(i08_cap_core::Step {kind:8,event:id,site:e.site,proof:e.proof});}
        else if e.kind==9 {steps.push(i08_cap_core::Step {kind:9,event:id,site:e.site,proof:e.proof});}
        else if e.kind==10 {steps.push(i08_cap_core::Step {kind:10,event:id,site:e.site});}
        else {return i08_cap_core::Package {},3;}
    }
    return i08_cap_core::Package {job:job,steps:copy(steps)},0;
}
