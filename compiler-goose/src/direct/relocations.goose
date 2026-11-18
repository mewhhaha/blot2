// One project backend runs serially in each request process. A recording lives
// only around that emission. The writer reports scalar offsets and body IDs,
// so no borrow of a generator, Core module or scratch buffer can escape.
namespace blot_direct_relocations;
struct Site { unit:u32, node:u32, offset:i64 }
struct BodySite { site:Site, function:u32, generation:i64 }
struct BodyStart { generation:i64, position:i64 }
struct Snapshot { sites:Site[:]=default<Site[:]>() }
reusable[] var site_pool:Site[>..]=[];
var recording:bool=false;
var used:i64=0;
var pending:Site[>..<]=[];
var bodies:BodySite[>..<]=[];
var sites:Site[>..<]=[];
var starts:BodyStart[>..<]=[];

fn deinit(s:Snapshot&) {
    if s.sites.len!=0 { site_pool.free_slice(s.sites); }
    s=Snapshot{};
}
fn begin() { assert(!recording); recording=true; }
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
    if recording { sites.push(Site{unit,node,-1}); }
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
    }
}
fn finish()->Snapshot {
    assert(recording);
    recording=false;
    var snapshot=Snapshot{};
    if sites.len!=0 {
        let owned=site_pool.alloc_slice(sites.len);
        for site,i in sites { owned[i]=site; }
        snapshot.sites=owned;
    }
    used=0; pending=[]; bodies=[]; starts=[]; sites=[];
    return snapshot;
}
