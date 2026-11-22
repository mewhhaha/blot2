// One project backend runs serially in each request process. A recording lives
// only around that emission. The writer reports scalar offsets and body IDs,
// so no borrow of a generator, Core module or scratch buffer can escape.
namespace blot_direct_relocations;
struct Site { unit:u32, node:u32, offset:i64 }
struct BodySite { site:Site, function:u32, generation:i64 }
struct BodyStart { generation:i64, position:i64 }
struct Snapshot { sites:Site[:]=default<Site[:]>(), body_sites:BodySite[:]=default<BodySite[:]>(), has_staged:bool=false }
reusable[] var site_pool:Site[>..]=[];
reusable[] var body_site_pool:BodySite[>..]=[];
var recording:bool=false;
var staged_flag:bool=false;
var used:i64=0;
var pending:Site[>..<]=[];
var bodies:BodySite[>..<]=[];
var sites:Site[>..<]=[];
var committed_bodies:BodySite[>..<]=[];
var starts:BodyStart[>..<]=[];

fn deinit(s:Snapshot&) {
    if s.sites.len!=0 { site_pool.free_slice(s.sites); }
    if s.body_sites.len!=0 { body_site_pool.free_slice(s.body_sites); }
    s=Snapshot{};
}
fn begin() { assert(!recording); recording=true; staged_flag=false; }
fn beginReplay(previous:const BodySite[:],skip_fn:const u8[:],drop_unit:u32) {
    assert(!recording);
    recording=true;
    staged_flag=false;
    used=0; pending=[]; bodies=[]; starts=[]; sites=[]; committed_bodies=[];
    for record in previous {
        if record.site.offset<0 {
            if drop_unit!=0 && record.site.unit==drop_unit { continue; }
            staged_flag=true;
            sites.push(record.site);
            committed_bodies.push(record);
            continue;
        }
        if (record.function as i64)<skip_fn.len && skip_fn[record.function]!=0 { continue; }
        if drop_unit!=0 && record.site.unit==drop_unit { continue; }
        bodies.push(record);
    }
}
fn abortReplay() {
    recording=false; staged_flag=false;
    used=0; pending=[]; bodies=[]; starts=[]; sites=[]; committed_bodies=[];
}
fn mark()->i64 { return used; }
fn rewind(first:i64) { if recording { used=first; } }
fn operand(unit:u32,node:u32,offset:i64) {
    if !recording { return; }
    let site=Site{unit,node,offset};
    if used==pending.len { pending.push(site); }
    else { pending[used]=site; }
    used++;
}
fn stagedRead(unit:u32,node:u32) {
    if recording {
        staged_flag=true;
        sites.push(Site{unit,node,-1});
        committed_bodies.push(BodySite{Site{unit,node,-1},0,0});
    }
}
fn insert(first:i64,at:i64,length:i64) {
    if !recording { return; }
    for i in first..used {
        if pending[i].offset>=at { pending[i].offset+=length; }
    }
}
fn finishBody(first:i64,adjust:i64,index:u32,generation:i64) {
    if !recording { return; }
    for site in pending[first..used] {
        bodies.push(BodySite{Site{site.unit,site.node,site.offset+adjust},index,generation});
    }
    rewind(first);
}
fn linkBody(generation:i64,position:i64) {
    if recording { starts.push(BodyStart{generation,position}); }
}
fn finishCode(base:i64) {
    if !recording { return; }
    for record in bodies {
        let body=starts[record.function];
        // Inference can emit a provisional body before the final one.
        if body.generation!=record.generation { continue; }
        let site=record.site;
        sites.push(Site{site.unit,site.node,base+body.position+site.offset});
        committed_bodies.push(record);
    }
}
fn finish()->Snapshot {
    assert(recording);
    recording=false;
    var snapshot=Snapshot{has_staged:staged_flag,..};
    if sites.len!=0 {
        let owned=site_pool.alloc_slice(sites.len);
        for site,i in sites { owned[i]=site; }
        snapshot.sites=owned;
    }
    if committed_bodies.len!=0 {
        let owned_b=body_site_pool.alloc_slice(committed_bodies.len);
        for rec,i in committed_bodies { owned_b[i]=rec; }
        snapshot.body_sites=owned_b;
    }
    staged_flag=false; used=0; pending=[]; bodies=[]; starts=[]; sites=[]; committed_bodies=[];
    return snapshot;
}
