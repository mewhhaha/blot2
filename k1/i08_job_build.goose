// Closed I08 job constructor. No caller selects symbolic IDs: this isolated
// job creates its own local namespace after copying source. Source spelling is
// still limited to particle_lower's fixed declaration and expression subset.
// Generic actual region aliasing and caller-owned storage authority are not
// inferred from unequal local symbol numbers.
namespace i08_job_build;
import particle_source_core;
import particle_lower_core;
import particle_lower_parse;
import particle_lower_verify;
import i08_job_core;
fn context()->particle_source_core::Context {
    return particle_source_core::Context {owner:1,input:2,input_version:3,input_region:4,input_domain:5,length:6,dt:7,dt_version:8,
        builder:9,builder_version:10,output_region:11,capacity:12,index:13,next_builder:14,next_version:15,result:16,result_version:17,result_domain:18};
}
fn build(source:u8[:])->i08_job_core::Job,i64 {
    if source.len>65536 {return i08_job_core::Job {},2;}
    // This copy belongs to the job; the caller can mutate its own buffer.
    let owned: u8[]=source;
    let c=context();var core,status=particle_lower_parse::parse(owned,c);
    if status!=0{return i08_job_core::Job {},status;}
    if !particle_lower_verify::verify(core,owned,c){return i08_job_core::Job {},3;}
    var events:i08_job_core::Event[>..]=[];
    events.push(i08_job_core::Event {kind:1,site:core.sites.append_site.start,symbol:c.builder,version:c.builder_version,region:c.output_region});
    for n,i in core.nodes {
        if n.kind==1 {events.push(i08_job_core::Event {kind:2,node:(i+1) as u32,site:n.start,symbol:c.input,version:c.input_version,
            region:c.input_region,domain:c.input_domain,index:c.index,proof:3});}
        else if n.kind==2 {events.push(i08_job_core::Event {kind:3,node:(i+1) as u32,site:n.start,symbol:c.dt,version:c.dt_version});}
        else if n.kind==3 || n.kind==4 {events.push(i08_job_core::Event {kind:if n.kind==3 {4} else {5},node:(i+1) as u32,site:n.start,a:n.left,b:n.right});}
        else {return i08_job_core::Job {},3;}
    }
    events.push(i08_job_core::Event {kind:6,site:core.sites.append_site.start,a:core.x_root,b:core.y_root});
    events.push(i08_job_core::Event {kind:7,site:core.sites.append_site.start,symbol:c.builder,version:c.builder_version,region:c.output_region,
        output:c.next_builder,output_version:c.next_version,proof:4});
    events.push(i08_job_core::Event {kind:8,site:core.sites.next_site.start,symbol:c.next_builder,version:c.next_version,output:c.builder,output_version:c.builder_version,proof:5});
    events.push(i08_job_core::Event {kind:9,site:core.sites.freeze_site.start,symbol:c.builder,version:c.builder_version,region:c.output_region,
        domain:c.result_domain,output:c.result,output_version:c.result_version,proof:6});
    events.push(i08_job_core::Event {kind:10,site:core.sites.return_site.start,symbol:c.result,version:c.result_version,domain:c.result_domain});
    return i08_job_core::Job {source:owned,core:core,events:copy(events)},0;
}
