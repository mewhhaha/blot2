// Native execution of a private copy-only wire fixture. All fields/specs are
// compiler-owned; source/ABI provenance, effects and real generated host ABI
// are not established. Runtime State/bitmap are trusted and non-concurrent.
namespace wire_runtime;
import wire_contract;
import wire_validate;
import host_bridge;
import pool;
import builder;
struct State {
    ingress:u8[256]=[0;256],egress:u8[256]=[0;256],memory:u8[8192]=[0;8192],
    slots:pool::Slot[1]=[pool::Slot {};1],bitmap:u32[1]=[0;1],busy:bool=false,frames:u32=0,calls:u32=0
}
fn put(bytes:u8[:],p:i64,v:u32) {for i in 4 {bytes[p+i]=(v >> (8*i) & 255) as u8;}}
fn publish(state:State&,export_id:u32,status:u32,payload:u32,required:u32,items:u32,detail:u32) {
    put(state.egress,0,0x4b310001);put(state.egress,4,export_id);put(state.egress,8,status);put(state.egress,12,payload);
    put(state.egress,16,required);put(state.egress,20,items);put(state.egress,24,detail);put(state.egress,28,0);
}
fn finish(state:State&,export_id:u32,status:u32,payload:u32,required:u32,items:u32,detail:u32,slot:u32,generation:u32,frames:u32) -> u32 {
    if slot!=0 {assert(pool::close(state.slots,state.bitmap,4096,1,slot,generation));}
    state.frames=frames;publish(state,export_id,status,payload,required,items,detail);state.busy=false;return status;
}
// Fault controls: 1 reserve, 2 frame, 3 language error; these are test-only.
// Return 9 is an internal unqualified fixture error and is never published.
fn invoke(state:State&,spec:wire_contract::Spec&,expected_source:u8[:],expected:wire_contract::Contract&,
          export_id:u32,input_bytes:u32,output_capacity:u32,fault:u32) -> u32 {
    if state.busy {return 4;}
    if fault>3 || !wire_validate::verify(spec,expected_source,expected) {return 9;}
    state.busy=true;let old_frames=state.frames;let m=expected.manifest;
    let fs=expected.fields[..expected.field_count];let ps=expected.predicates[..expected.predicate_count];
    let input=host_bridge::inspect(m,fs,ps,state.ingress,export_id,input_bytes,output_capacity,false);
    if input.status!=0 {return finish(state,m.export_id,1,0,0,0,0,0,0,old_frames);}
    if fault==2 || state.frames==4294967295 {return finish(state,m.export_id,5,0,0,0,0,0,0,old_frames);}
    state.frames+=1;
    if fault==1 {return finish(state,m.export_id,3,0,0,0,1,0,0,old_frames);}
    let reserved=pool::reserve(state.slots,state.bitmap,4096,1,m.work_bytes);
    if reserved.status!=0 {return finish(state,m.export_id,3,0,0,0,reserved.status as u32,0,0,old_frames);}
    let slot=reserved.slot;let gen=reserved.generation;
    var clock=builder::Clock {};var frozen:builder::Frozen[8]=[builder::Frozen {};8];var cursor:u32=0;
    for field,i in fs {
        if field.role==0 {cursor+=host_bridge::stride(field.kind);continue;}
        let count=host_bridge::word(state.ingress,32+cursor as i64);
        let offset=host_bridge::word(state.ingress,36+cursor as i64);cursor+=8;
        let stride=host_bridge::stride(field.kind);
        let placement=pool::try_alloc(state.slots,state.bitmap,4096,1,slot,gen,stride,count);assert(placement.status==0);
        var cell=builder::Cell {};let started=builder::begin(cell,clock,state.memory,placement.data,count,field.kind,1);assert(started.status==0);
        var handle=started.handle;
        for j in count {
            let at=32+offset as i64+j as i64*stride as i64;
            let next=builder::try_append(cell,handle,state.memory,state.ingress[at..at+stride]);assert(next.status==0);handle=next.handle;
        }
        frozen[i]=builder::freeze(cell,handle,clock,state.memory);assert(frozen[i].status==0);
    }
    let out_stride=host_bridge::stride(m.output_kind);
    let output=pool::try_alloc(state.slots,state.bitmap,4096,1,slot,gen,out_stride,m.output_capacity);assert(output.status==0);
    var out_cell=builder::Cell {};let start=builder::begin(out_cell,clock,state.memory,output.data,m.output_capacity,m.output_kind,1);assert(start.status==0);
    var out_handle=start.handle;
    if state.calls!=4294967295 {state.calls+=1;}
    if fault==3 {assert(builder::discard(out_cell,out_handle).status==0);return finish(state,m.export_id,6,0,0,0,1,slot,gen,old_frames);}
    let selected=frozen[expected.selected];
    var returned=selected;
    if expected.alias_result {assert(builder::discard(out_cell,out_handle).status==0);}
    else {
        for i in selected.length {
            let p=if out_stride==0 {0} else {selected.data+i*out_stride};
            let next=builder::try_append(out_cell,out_handle,state.memory,state.memory[p..p+out_stride]);assert(next.status==0);out_handle=next.handle;
        }
        returned=builder::freeze(out_cell,out_handle,clock,state.memory);assert(returned.status==0);
    }
    let result=host_bridge::output(m,fs,ps,returned.length,output_capacity);
    if result.status==2 {return finish(state,m.export_id,2,0,result.required_bytes,result.item_count,0,slot,gen,old_frames);}
    assert(result.status==0);
    put(state.egress,32,returned.length);put(state.egress,36,8);
    for i in returned.length*out_stride {state.egress[40+i]=state.memory[returned.data+i];}
    return finish(state,m.export_id,0,result.payload_bytes,result.required_bytes,result.item_count,0,slot,gen,old_frames);
}
