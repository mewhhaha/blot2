// Independently checks one source-owned job and its closed operation/loan
// ordering. It uses the independent particle_lower source recognizer and
// reconstructs the job-local symbol table and every event from that source.
// The caller supplies the actual trusted source bytes; this is not package
// authentication, a portable artifact, a general ownership/loan proof, or a
// proof that separately supplied runtime regions are globally disjoint.
namespace i08_job_verify;
import particle_source_core;
import particle_lower_verify;
import i08_job_core;
fn check(job:i08_job_core::Job&, i:i64, expected:i08_job_core::Event)->bool {
    return i>=0 && i<job.events.len && i08_job_core::same_event(job.events[i],expected);
}
fn verify(job:i08_job_core::Job&, source:u8[:])->bool {
    if source.len>65536 || job.source[..]!=source || job.core.source[..]!=source || job.core.nodes.len<2 ||
       job.core.nodes.len>256 || job.events.len!=job.core.nodes.len+6 {return false;}
    // This job-local namespace is reconstructed here; callers do not submit
    // numeric view/domain/region IDs to the constructor or validation API.
    let c=particle_source_core::Context {owner:1,input:2,input_version:3,input_region:4,input_domain:5,length:6,dt:7,dt_version:8,
        builder:9,builder_version:10,output_region:11,capacity:12,index:13,next_builder:14,next_version:15,result:16,result_version:17,result_domain:18};
    if !particle_lower_verify::verify(job.core,source,c) {return false;}
    if !check(job,0,i08_job_core::Event {kind:1,site:job.core.sites.append_site.start,symbol:c.builder,version:c.builder_version,region:c.output_region}) {return false;}
    // The builder remains held throughout pure expression evaluation. Each
    // field read is a transient immutable input read, tied to the exact
    // view/version/domain/index and prevalidated true-edge bounds proof.
    for n,i in job.core.nodes {
        var e=i08_job_core::Event {};
        if n.kind==1 {e=i08_job_core::Event {kind:2,node:(i+1) as u32,site:n.start,symbol:c.input,version:c.input_version,
            region:c.input_region,domain:c.input_domain,index:c.index,proof:3};}
        else if n.kind==2 {e=i08_job_core::Event {kind:3,node:(i+1) as u32,site:n.start,symbol:c.dt,version:c.dt_version};}
        else if n.kind==3 || n.kind==4 {e=i08_job_core::Event {kind:if n.kind==3 {4} else {5},node:(i+1) as u32,site:n.start,a:n.left,b:n.right};}
        else {return false;}
        if !check(job,i+1,e) {return false;}
    }
    let p=job.core.nodes.len+1;
    if !check(job,p,i08_job_core::Event {kind:6,site:job.core.sites.append_site.start,a:job.core.x_root,b:job.core.y_root}) {return false;}
    if !check(job,p+1,i08_job_core::Event {kind:7,site:job.core.sites.append_site.start,symbol:c.builder,version:c.builder_version,region:c.output_region,
        output:c.next_builder,output_version:c.next_version,proof:4}) {return false;}
    if !check(job,p+2,i08_job_core::Event {kind:8,site:job.core.sites.next_site.start,symbol:c.next_builder,version:c.next_version,
        output:c.builder,output_version:c.builder_version,proof:5}) {return false;}
    if !check(job,p+3,i08_job_core::Event {kind:9,site:job.core.sites.freeze_site.start,symbol:c.builder,version:c.builder_version,
        region:c.output_region,domain:c.result_domain,output:c.result,output_version:c.result_version,proof:6}) {return false;}
    return check(job,p+4,i08_job_core::Event {kind:10,site:job.core.sites.return_site.start,symbol:c.result,version:c.result_version,domain:c.result_domain});
}
