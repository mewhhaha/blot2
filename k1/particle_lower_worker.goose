// Structured worker emitter. Caller must first independently verify Core and
// its trusted owner/loan context. This private worker accepts a pre-existing
// zero-length builder; it places no storage, imports nothing, calls no helper,
// and advances initialized length only after both output fields are stored.
namespace particle_lower_worker;
import wasm;
import particle_source_backend;
import particle_lower_core;
fn b(out:u8[>..]&,v:u8){particle_source_backend::b(out,v);}
fn c(out:u8[>..]&,v:u32){particle_source_backend::c(out,v);}
fn get(out:u8[>..]&,i:i64){particle_source_backend::get(out,i);}
fn set(out:u8[>..]&,i:i64){particle_source_backend::set(out,i);}
fn indexed(out:u8[>..]&,base:i64,index:i64,stride:u32){particle_source_backend::indexed(out,base,index,stride);}
fn loadf(out:u8[>..]&,offset:i64){particle_source_backend::loadf(out,offset);}
fn storef(out:u8[>..]&,offset:i64){particle_source_backend::storef(out,offset);}
fn nodes(out:u8[>..]&,input:particle_lower_core::Node[:])->bool {
    for node in input {
        if node.kind==1 {
            if node.field>3{return false;}
            indexed(out,0,6,16);loadf(out,node.field as i64*4);
        } else if node.kind==2 {get(out,5);}
        else if node.kind==3 {b(out,0x94);} else if node.kind==4 {b(out,0x92);}
        else {return false;}
    }
    return true;
}
fn emit(core:particle_lower_core::Core&)->u8[] {
    if core.nodes.len<2 || core.x_root==0 || core.x_root>=core.nodes.len || core.y_root!=core.nodes.len {return [];}
    var out:u8[>..]=[2,1,0x7f,2,0x7d]; // i = 6, evaluated x = 7 and y = 8
    c(out,0);set(out,6);b(out,0x02);b(out,0x40);b(out,0x03);b(out,0x40);
    get(out,6);get(out,1);b(out,0x4f);b(out,0x0d);wasm::unsigned_leb(out,1);
    if !nodes(out,core.nodes[..core.x_root]) {return [];}set(out,7);
    if !nodes(out,core.nodes[core.x_root..]) {return [];}set(out,8);
    indexed(out,2,6,8);get(out,7);storef(out,0);
    indexed(out,2,6,8);get(out,8);storef(out,4);
    get(out,3);get(out,6);c(out,1);b(out,0x6a);particle_source_backend::store(out,12);
    get(out,6);c(out,1);b(out,0x6a);set(out,6);b(out,0x0c);wasm::unsigned_leb(out,0);
    b(out,0x0b);b(out,0x0b);
    get(out,1);b(out,0x45);b(out,0x04);b(out,0x40);particle_source_backend::set_field(out,3,8,0);b(out,0x0b);
    particle_source_backend::set_field(out,3,0,2);get(out,1);b(out,0x0b);
    return out;
}
