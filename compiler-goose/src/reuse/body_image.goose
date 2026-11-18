// An image and its scalar relocations belong to the same committed Core revision.
// Each successful fixed-width edit keeps the layout and advances both together.
namespace blot_reuse_body_image;
import reuse.body_shape;
import reuse.dependency_consumer;
import reuse.partial_dependency;
import direct.relocations;
import direct.writer;
import direct.map;

type Prepared=blot_reuse_partial_dependency::Prepared;
struct Image {
    layout:blot_direct_relocations::Snapshot=blot_direct_relocations::Snapshot{},
    bytes:u8[:]=default<u8[:]>(),
    functions:i64=0
}
fn deinit(image:Image&) {
    image.layout.deinit();
    blot_reuse_dependency_consumer::freeBytes(image.bytes);
    image=Image{};
}

fn encode(out:u8[>..<]&,opcode:u8,value:u32)->bool {
    if opcode==blot_direct_writer::OP_i32_const { blot_direct_writer::sleb(out,value as! i32); return true; }
    if opcode==blot_direct_writer::OP_f32_const { blot_direct_writer::word(out,value); return true; }
    return false;
}

fn relocate(image:const Image&,previous:const Prepared&,next:const Prepared&)->u8[:],i64 {
    if image.bytes.len==0 || previous.entry!=next.entry || previous.units.len!=next.units.len { return default<u8[:]>(),-1; }
    var changed=blot_direct_map::U64Map{};
    for unit,i in next.units {
        if next.borrowed[i] { continue; }
        let old .= previous.units[i];
        if previous.paths[i]!=next.paths[i] || !blot_reuse_body_shape::same_check_core_Module(old,unit) { return default<u8[:]>(),-1; }
        for node,id in unit.nodes {
            if node.tag==blot_check_core::Tag.constant && node.a!=old.nodes[id].a {
                changed.put(((unit.unit as u64)<<32) | id as u32,0);
            }
        }
    }
    if changed.count==0 { return blot_reuse_dependency_consumer::ownBytes(image.bytes),0; }
    var edits:u32[>..<]=[];
    var old_bytes:u8[>..<]=[];
    var new_bytes:u8[>..<]=[];
    var covered:u32=0;
    for site,i in image.layout.sites {
        let key=((site.unit as u64)<<32) | site.node;
        let count,found=changed.get(key);
        if !found { continue; }
        if site.offset<0 || site.offset>=image.bytes.len { return default<u8[:]>(),-1; }
        let opcode=image.bytes[site.offset];
        old_bytes.clear();new_bytes.clear();
        if !encode(old_bytes,opcode,previous.units[site.unit-1].nodes[site.node].a) { return default<u8[:]>(),-1; }
        let encoded=encode(new_bytes,opcode,next.units[site.unit-1].nodes[site.node].a);
        let start=site.offset+1;
        if new_bytes.len!=old_bytes.len || start+old_bytes.len>image.bytes.len || image.bytes[start..start+old_bytes.len]!=old_bytes[..] { return default<u8[:]>(),-1; }
        edits.push(i as u32);
        if count==0 { covered++;changed.put(key,1); }
    }
    if covered!=changed.count { return default<u8[:]>(),-1; }
    let out=blot_reuse_dependency_consumer::ownBytes(image.bytes);
    for i in edits {
        let site=image.layout.sites[i];
        new_bytes.clear();
        let encoded=encode(new_bytes,out[site.offset],next.units[site.unit-1].nodes[site.node].a);
        for byte,j in new_bytes { out[site.offset+1+j]=byte; }
    }
    return out,edits.len;
}
