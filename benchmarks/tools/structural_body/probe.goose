import support.project_packet;
import support.native;
import support.error;
import direct.direct;
import direct.emit;
import direct.types;
import direct.map;
import direct.writer;
import direct.function;
import check.core;
import reuse.body_shape;

type Core = squid_check_core::Module;
type Generator = squid_direct_emit::Generator;
type Map = squid_direct_map::U64Map;
let units = 293;

extern fn packetSize(version:u32,unit:u32)->i64="body_packet_size";
extern fn packetRead(version:u32,unit:u32,data:u8&,size:i64)="body_packet_read";
extern fn referenceFirst()->bool="body_reference_first";
extern fn inferred(id:u32)->bool="body_inferred";
extern fn recording()->bool="body_recording";
extern fn jobElapsed()->u64="body_job_elapsed";
extern fn nextEdit()->bool="body_next_edit";
extern fn enable(value:bool)="body_enable";
extern fn staged(unit:u32,binding:u32)->bool="body_staged";
extern fn beginReplay()="body_begin_replay";
extern fn sameLookups(id:u32)->bool="body_trace_match";
extern fn stat(key:u32,value:u64)="body_stat";
extern fn save(kind:u32,data:const u8&,size:i64)="body_save";
extern fn editUnit()->u32="edit_unit";
extern fn editPoint()->u32="edit_point";
extern fn diagnostic(text:const u8&,size:i64)="body_diag";
reusable[] var buffers:u8[>..];


fn readCore(version:u32,owner:squid_project_packet::Owner,unit:u32)->Core {
    let size=packetSize(version,unit);
    let bytes=buffers.alloc_slice(size);
    packetRead(version,unit,bytes[0],size);
    var reader=squid_project_packet::Reader{bytes,owner};
    var id:u32=0;
    var core=default<Core>();
    squid_project_packet::get(reader,id);
    squid_project_packet::getExecutionCore(reader,core);
    assert(reader.failure==squid_error::Error.none && id==unit && core.unit==unit);
    buffers.free_slice(bytes);
    return core;
}

fn reference(updated:const Core[:],entry:u32,out:u8[>..<]&) {
    enable(false);
    var detail:u8[>..<]=[];
    let start=squid_native::clock_ns();
    let result=squid_direct::compile(updated,entry,out,detail);
    stat(8,squid_native::clock_ns()-start);
    assert(!result.failed);
    enable(true);
}

fn bindingAt(m:const Core&,point:u32)->u32 {
    var found:u32=0;
    for body in m.bodies {
        if body.span.start<=point && point<body.span.end {
            assert(found==0);
            found=body.binding;
        }
    }
    return found;
}

// Each process makes one speculative edit. A rejected trial is discarded wholesale.
fn replay(types:squid_direct_types::Types&, module:squid_direct_writer::Module&, state:squid_direct_emit::State&, updated:const Core[:], unit:u32,binding:u32,image:u8[>..<]&)->u32 {
    types.units=updated;
    var g=Generator{types,module,state,updated};
    let m .= updated[unit-1];
    if staged(unit,binding) {return 6;}
    beginReplay();
    let body .= m.body(binding);
    if !body {return 1;}
    let s .= g.s;
    let w .= g.module;
    let functions=w.functions.len;
    let instances=s.instances.len;
    let sections=[w.signatures.len,w.imports.len,w.table.len,w.globals.len,w.exports.len,w.data.len,w.customs.len];
    g.types.resetClosed();
    g.types.nominal_positions=Map{};
    s.resetAllCaches();
    var emitted:u32=0;
    var matched=true;
    for index in 0..instances {
        let item=s.instances[index];
        if item.key.kind!=squid_direct_emit::InstanceKind.named || item.key.unit!=unit || item.key.id!=binding {continue;}
        let id=index as u32;
        var env=squid_direct_types::Env{};
        g.types.match_(m,m.binding(binding).ty,item.key.ty,env);
        if squid_direct_emit::solveObligations(g,m,body.scheme.obligations,env)!=squid_direct_types::Error.none {return 2;}
        s.instances[id].env=env;
        s.instances[id].inferring=inferred(id);
        let err=squid_direct_function::emitInstance(g,id);
        s.instances[id].inferring=false;
        if err!=squid_direct_types::Error.none {return 3;}
        if s.instances[id].result!=item.result {return 9;}
        if !sameLookups(id) {matched=false;}
        emitted++;
    }
    stat(4,emitted);
    if s.has_failure || s.failures.len!=0 {
        for record in s.failures {
            let text=squid_direct_emit::textOf(g,record.failure.message);
            if text.len!=0 {diagnostic(text[0],text.len);}
        }
        return 5;
    }
    if emitted==0 {return 1;}
    if instances!=s.instances.len || functions!=w.functions.len || sections!=[w.signatures.len,w.imports.len,w.table.len,w.globals.len,w.exports.len,w.data.len,w.customs.len] {
        for i in instances..s.instances.len {
            let key=s.instances[i].key;
            stat(20,squid_direct_emit::kindCode(key.kind));stat(21,key.unit);stat(22,key.id);
        }
        return 4;
    }
    if !matched {return 7;}
    squid_direct_writer::assemble(w,image);
    return 0;
}

fn sameUnit(a:const Core&,b:const Core&)->bool {
    if !squid_reuse_body_shape::same_check_core_Module(a,b) {return false;}
    for n,i in a.nodes {
        if n.tag==squid_check_core::Tag.constant && n.a!=b.nodes[i].a {return false;}
    }
    return true;
}

// An import may point through a numbered alias in the edited module. Compare
// the final declaration before treating another module as a changed input.
fn sameImporter(old:const Core[:],updated:const Core[:],i:i64,edit:u32)->bool {
    var a=old[i];
    var b=updated[i];
    if a.bindings.len!=b.bindings.len {return false;}
    var ta=squid_direct_types::Types{units:old,..};
    var tb=squid_direct_types::Types{units:updated,..};
    var storage=squid_direct_writer::Module{..};
    var scratch=squid_direct_emit::State{..};
    var prior=Generator{ta,storage,scratch,old};
    var next=Generator{tb,storage,scratch,updated};
    for x,at in a.bindings {
        var y=b.bindings[at];
        if x.target!=y.target {
            if x.kind!=squid_reuse_principal_interface::Kind.external || y.kind!=x.kind {return false;}
            let left=prior.resolve(a,x.target);
            let right=next.resolve(b,y.target);
            if left!=right || left.unit==edit || left.unit==a.unit || left.unit==0 {return false;}
            y.target=x.target;
        }
        if !squid_reuse_body_shape::same_check_core_Binding(x,y) {return false;}
    }
    b.bindings=a.bindings;
    return sameUnit(a,b);
}

fn selectBinding(old:const Core[:],updated:const Core[:],unit:u32)->u32,bool {
    var changes:u32=0;
    var other=false;
    let start=squid_native::clock_ns();
    for i in 0..units {
        if !sameUnit(old[i],updated[i]) {
            stat(11,(i+1) as u32);
            if i+1==unit {changes++;}
            else if !sameImporter(old,updated,i,unit) {other=true;}
            else {stat(19,(i+1) as u32);}
        }
    }
    let binding=bindingAt(old[unit-1],editPoint());
    assert(changes==1 && binding!=0);
    // The fixtures insert after this marker. Both revisions must select the same binding.
    assert(bindingAt(updated[unit-1],editPoint())==binding);
    stat(18,squid_native::clock_ns()-start);
    return binding,other;
}

fn checkpoint(old:const Core[:],entry:u32) {
    var types=squid_direct_types::Types{units:old,..};
    squid_direct_types::init(types);
    var module=squid_direct_writer::Module{..};
    var state=squid_direct_emit::State{..};
    var initial=Generator{types,module,state,old};
    var base:u8[>..<]=[];
    enable(recording());
    let setup=squid_native::clock_ns();
    assert(squid_direct::build(initial,entry,base)==squid_direct_types::Error.none);
    stat(26,squid_native::clock_ns()-setup);
    assert(!state.has_failure && state.failures.len==0);
    save(1,base[0],base.len);
    if !nextEdit() {return;}

    let unit=editUnit();
    let decodeStart=squid_native::clock_ns();
    let editOwner,editErr=squid_project_packet::initOwner();
    assert(editErr==squid_error::Error.none);
    var edited:Core[293]=[default<Core>();293];
    for i in 0..units {edited[i]=readCore(1,editOwner,(i+1) as u32);}
    stat(27,squid_native::clock_ns()-decodeStart);
    let updated=edited[..];
    let binding,other=selectBinding(old,updated,unit);
    var fresh:u8[>..<]=[];
    if referenceFirst() {reference(updated,entry,fresh);}
    var image:u8[>..<]=[];
    let start=squid_native::clock_ns();
    var reason:u32=8;
    if !other {reason=replay(types,module,state,updated,unit,binding,image);}
    let elapsed=squid_native::clock_ns()-start;
    stat(2,elapsed);stat(14,reason);
    if reason==0 {save(2,image[0],image.len);}
    if !referenceFirst() {
        stat(30,jobElapsed());
        reference(updated,entry,fresh);
    }
    save(3,fresh[0],fresh.len);
    if reason==0 {assert(image[..]==fresh[..]);}
}

fn main() {
    let owner,err=squid_project_packet::initOwner();
    assert(err==squid_error::Error.none);
    var old:Core[293]=[default<Core>();293];
    var entry:u32=0;
    for i in 0..units {
        old[i]=readCore(0,owner,(i+1) as u32);
        for body in old[i].bodies {if body.exported {entry=old[i].unit;}}
    }
    assert(entry!=0);
    checkpoint(old[..],entry);
}
