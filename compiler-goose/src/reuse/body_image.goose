// An image and its scalar relocations belong to the same committed Core revision.
// Fixed-width constant edits patch bytes in place; single-unit body edits replay
// only the changed bodies against the retained direct-backend state when sound.
namespace blot_reuse_body_image;
import check.core;
import check.types;
import check.wire_schema;
import reuse.body_shape;
import reuse.dependency_consumer;
import reuse.partial_dependency;
import reuse.principal_interface;
import direct.direct;
import direct.emit;
import direct.function;
import direct.types;
import direct.relocations;
import direct.writer;
import direct.map;
import support.error;
import support.option;
import compile;

type Core=blot_check_core::Module;
type Prepared=blot_reuse_partial_dependency::Prepared;
type Emission=blot_reuse_partial_dependency::Result;

struct LayoutReceipt {
    valid:bool=false,
    non_staged:blot_check_wire_schema::NonStagedReceipt=blot_check_wire_schema::NonStagedReceipt{},
    staged_dep_units_valid:bool=false,
    staged_dep_units:u32[:]=default<u32[:]>(),
    staged_value_digest:u64=0
}
fn deinitLayoutReceipt(receipt:LayoutReceipt&) {
    blot_reuse_dependency_consumer::freeU32s(receipt.staged_dep_units);
    receipt=LayoutReceipt{};
}
fn canReuseReceipt(prev:const LayoutReceipt&,cur:blot_check_wire_schema::NonStagedReceipt,next:const Prepared&)->bool {
    if !prev.valid { return false; }
    if !blot_check_wire_schema::sameNonStagedReceipt(prev.non_staged,cur) { return false; }
    if cur.kernel_staging_sites_count!=0 {
        if !prev.staged_dep_units_valid { return false; }
        for u in prev.staged_dep_units {
            if u==0 || (u as i64)>next.borrowed.len || !next.borrowed[u-1] { return false; }
        }
    }
    return true;
}

struct Image {
    layout:blot_direct_relocations::Snapshot=blot_direct_relocations::Snapshot{},
    bytes:u8[:]=default<u8[:]>(),
    functions:i64=0,
    sparks_vectorized:i64=0,
    sparks_scalar_fallback:i64=0,
    receipt:LayoutReceipt=LayoutReceipt{}
}
fn deinit(image:Image&) {
    image.layout.deinit();
    blot_reuse_dependency_consumer::freeBytes(image.bytes);
    deinitLayoutReceipt(image.receipt);
    image=Image{};
}

struct Replay {
    valid:bool=false,
    used:bool=false,
    needs_reset:bool=false,
    types:blot_direct_types::Types&,
    module:blot_direct_writer::Module&,
    state:blot_direct_emit::State&
}

fn encode(out:u8[>..<]&,opcode:u8,value:u32)->bool {
    if opcode==blot_direct_writer::OP_i32_const { blot_direct_writer::sleb(out,value as! i32); return true; }
    if opcode==blot_direct_writer::OP_f32_const { blot_direct_writer::word(out,value); return true; }
    return false;
}

fn relocate(image:const Image&,previous:const Prepared&,next:const Prepared&,replay:Replay&)->u8[:],i64 {
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
        // Keep the retained direct Module text in sync so a later structural replay sees patched constants.
        if replay.valid {
            if (i as i64)<image.layout.body_sites.len {
                let bs=image.layout.body_sites[i];
                let fn_body=replay.module.functions[bs.function].body;
                let text_at=fn_body.start+bs.site.offset+1;
                if text_at>=fn_body.start && text_at+new_bytes.len<=fn_body.start+fn_body.len {
                    for byte,j in new_bytes { replay.module.text[text_at+j]=byte; }
                } else {
                    replay.valid=false;
                }
            } else {
                replay.valid=false;
            }
        }
    }
    return out,edits.len;
}

// --- Structural per-body replay -----------------------------------------

fn sameUnit(a:const Core&,b:const Core&)->bool {
    if !blot_reuse_body_shape::same_check_core_Module(a,b) { return false; }
    for n,i in a.nodes {
        if n.tag==blot_check_core::Tag.constant && n.a!=b.nodes[i].a { return false; }
    }
    return true;
}

fn resolveRef(units:const Core[:],m:const Core&,target:blot_check_core::BindingRef)->blot_check_core::BindingRef {
    var current=blot_check_core::BindingRef{target.unit,target.binding};
    if current.unit==0 { current.unit=m.unit; }
    for step in 0..64 {
        if current.unit==0 || current.unit>units.len { return current; }
        let u .= units[current.unit-1];
        if current.binding>=u.bindings.len { return current; }
        let b=u.bindings[current.binding];
        if b.kind!=blot_reuse_principal_interface::Kind.external { return current; }
        var nu=b.target.unit;
        if nu==0 { nu=current.unit; }
        current=blot_check_core::BindingRef{nu,b.target.binding};
    }
    return current;
}

fn sameImporter(old:const Core[:],updated:const Core[:],i:i64,edit:u32)->bool {
    var a=old[i];
    var b=updated[i];
    if a.bindings.len!=b.bindings.len { return false; }
    for x,at in a.bindings {
        var y=b.bindings[at];
        if x.target!=y.target {
            if x.kind!=blot_reuse_principal_interface::Kind.external || y.kind!=x.kind { return false; }
            let left=resolveRef(old,a,x.target);
            let right=resolveRef(updated,b,y.target);
            if left!=right || left.unit==edit || left.unit==a.unit || left.unit==0 { return false; }
            y.target=x.target;
        }
        if !blot_reuse_body_shape::same_check_core_Binding(x,y) { return false; }
    }
    b.bindings=a.bindings;
    return sameUnit(a,b);
}

fn sameFieldSymbol(a:const Core&,sa:u32,b:const Core&,sb:u32)->bool {
    let fa=a.fieldSpelling(sa);
    let fb=b.fieldSpelling(sb);
    if fa.present!=fb.present { return false; }
    if !fa.present { return sa==sb; }
    return fa.value==fb.value;
}

recursive fn sameCoreType(a:const Core&,ta:u32,b:const Core&,tb:u32,depth:i64)->bool {
    if depth>64 { return false; }
    if ta<=blot_check_types::never || tb<=blot_check_types::never { return ta==tb; }
    if ta>=a.types.nodes.len || tb>=b.types.nodes.len { return false; }
    let na=a.types.nodes[ta];
    let nb=b.types.nodes[tb];
    if na.tag!=nb.tag { return false; }
    match na.tag {
        unit,boolean,unsigned32,floating32,never=>{ return true; },
        variable,bound=>{ return na.a==nb.a && na.b==nb.b; },
        usage=>{ return na.b==nb.b && sameCoreType(a,na.a,b,nb.a,depth+1) && sameCoreType(a,na.c,b,nb.c,depth+1); },
        forall,existential=>{ return na.b==nb.b && sameCoreType(a,na.a,b,nb.a,depth+1); },
        array,list,cursor,resolver=>{ return sameCoreType(a,na.a,b,nb.a,depth+1); },
        function=>{
            if !sameCoreType(a,na.a,b,nb.a,depth+1) || !sameCoreType(a,na.b,b,nb.b,depth+1) { return false; }
            return sameEffectRow(a,na.c,b,nb.c,depth+1);
        },
        product=>{
            if na.b!=nb.b { return false; }
            for i in 0..(na.b as i64) {
                if !sameCoreType(a,a.types.extra[na.a+i],b,b.types.extra[nb.a+i],depth+1) { return false; }
            }
            return true;
        },
        record=>{
            if na.b!=nb.b { return false; }
            for i in 0..(na.b as i64) {
                let fa=a.types.recordField(na,i);
                let fb=b.types.recordField(nb,i);
                if !sameFieldSymbol(a,fa.name,b,fb.name) { return false; }
                if !sameCoreType(a,fa.ty,b,fb.ty,depth+1) { return false; }
            }
            return true;
        },
        nominal,projection,instance_selection=>{
            if na.a!=nb.a || na.b!=nb.b { return false; }
            let aa=a.types.nominalArguments(na);
            let bb=b.types.nominalArguments(nb);
            if aa.len!=bb.len { return false; }
            for i in 0..aa.len {
                if !sameCoreType(a,aa[i],b,bb[i],depth+1) { return false; }
            }
            if na.tag==blot_check_types::Tag.projection {
                return sameFieldSymbol(a,a.types.projectionMember(na),b,b.types.projectionMember(nb));
            }
            return true;
        },
        provider=>{ return sameCoreType(a,na.a,b,nb.a,depth+1) && sameEffectRow(a,na.c,b,nb.c,depth+1); },
        state_provider=>{ return sameCoreType(a,na.a,b,nb.a,depth+1) && sameCoreType(a,na.b,b,nb.b,depth+1) && sameCoreType(a,na.c,b,nb.c,depth+1); },
        scoped=>{ return na.b==nb.b && na.c==nb.c && sameCoreType(a,na.a,b,nb.a,depth+1); },
        type_constructor,rigid,instance_version=>{ return na.a==nb.a && na.b==nb.b && na.c==nb.c; },
        _=>{ return false; },
    }
}

recursive fn sameEffectRow(a:const Core&,ra:u32,b:const Core&,rb:u32,depth:i64)->bool {
    if ra==0 && rb==0 { return true; }
    if ra==0 || rb==0 || depth>64 { return false; }
    let row_a=a.types.row(ra);
    let row_b=b.types.row(rb);
    if row_a.tail!=row_b.tail || row_a.labels.len!=row_b.labels.len { return false; }
    let la=a.types.rowLabels(ra);
    let lb=b.types.rowLabels(rb);
    for i in 0..la.len {
        let oa=a.types.operation(la[i]);
        let ob=b.types.operation(lb[i]);
        if oa.identity!=ob.identity || oa.instance!=ob.instance || oa.arguments.len!=ob.arguments.len { return false; }
        let aa=a.types.operationArguments(la[i]);
        let bb=b.types.operationArguments(lb[i]);
        for j in 0..aa.len {
            if !sameCoreType(a,aa[j],b,bb[j],depth+1) { return false; }
        }
    }
    return true;
}

struct LocalPair { old_id:u32, new_id:u32 }
struct LocalMap { items:LocalPair[>..<]=[] }
fn mapBind(m:LocalMap&,o:u32,n:u32) { m.items.push(LocalPair{o,n}); }
fn lookupLocal(m:const LocalMap&,o:u32)->u32,bool {
    var i=m.items.len;
    while i>0 {
        i-=1;
        if m.items[i].old_id==o { return m.items[i].new_id,true; }
    }
    return 0,false;
}

recursive fn samePattern(a:const Core&,pa:u32,b:const Core&,pb:u32,locals:LocalMap&,depth:i64)->bool {
    if depth>64 { return false; }
    let na=a.pattern(pa);
    let nb=b.pattern(pb);
    if na.tag!=nb.tag { return false; }
    match na.tag {
        wildcard=>{ return true; },
        bind=>{ mapBind(locals,na.a,nb.a); return true; },
        constant=>{ return na.a==nb.a && na.b==nb.b && na.c==nb.c; },
        constructor=>{
            if na.a!=nb.a || na.c!=nb.c || (na.b==0)!=(nb.b==0) { return false; }
            if na.b!=0 { return samePattern(a,na.b,b,nb.b,locals,depth+1); }
            return true;
        },
        product=>{
            let ca=a.patternChildren(pa);
            let cb=b.patternChildren(pb);
            if ca.len!=cb.len { return false; }
            for i in 0..ca.len {
                if !samePattern(a,ca[i],b,cb[i],locals,depth+1) { return false; }
            }
            return true;
        },
        _=>{ return false; },
    }
}

fn sameProjection(a:const Core&,pa_id:u32,b:const Core&,pb_id:u32)->bool {
    let pa=a.projection(pa_id);
    let pb=b.projection(pb_id);
    if pa.nominal!=pb.nominal || pa.variants.len!=pb.variants.len { return false; }
    if !sameCoreType(a,pa.source_type,b,pb.source_type,0) || !sameCoreType(a,pa.result_type,b,pb.result_type,0) { return false; }
    if pa.field!=0 || pb.field!=0 {
        if !sameFieldSymbol(a,pa.field,b,pb.field) { return false; }
    }
    let va=a.projectionVariants(pa_id);
    let vb=b.projectionVariants(pb_id);
    if va.len!=vb.len { return false; }
    for i in 0..va.len {
        if va[i].tag!=vb[i].tag || !sameFieldSymbol(a,va[i].field,b,vb[i].field) { return false; }
    }
    return true;
}

recursive fn sameCoreExpr(old_units:const Core[:],a:const Core&,ia:u32,new_units:const Core[:],b:const Core&,ib:u32,locals:LocalMap&,blocks:LocalMap&,depth:i64)->bool {
    if depth>96 { return false; }
    if ia==0 || ib==0 { return ia==ib; }
    let na=a.node(ia);
    let nb=b.node(ib);
    if na.tag!=nb.tag || na.op!=nb.op { return false; }
    if !sameCoreType(a,na.ty,b,nb.ty,0) { return false; }
    match na.tag {
        constant=>{ return na.a==nb.a && na.b==nb.b && na.c==nb.c; },
        reference=>{
            let ra=a.references[na.a];
            let rb=b.references[nb.a];
            let local_a=(ra.unit==0 || ra.unit==a.unit) && a.bindings[ra.binding].kind!=blot_reuse_principal_interface::Kind.global && a.bindings[ra.binding].kind!=blot_reuse_principal_interface::Kind.external;
            let local_b=(rb.unit==0 || rb.unit==b.unit) && b.bindings[rb.binding].kind!=blot_reuse_principal_interface::Kind.global && b.bindings[rb.binding].kind!=blot_reuse_principal_interface::Kind.external;
            if local_a!=local_b { return false; }
            if local_a {
                let mapped,ok=lookupLocal(locals,ra.binding);
                return ok && mapped==rb.binding;
            }
            return resolveRef(old_units,a,ra)==resolveRef(new_units,b,rb);
        },
        scalar,logical,apply=>{
            if na.tag==blot_check_core::Tag.scalar && na.c!=nb.c { return false; }
            return sameCoreExpr(old_units,a,na.a,new_units,b,nb.a,locals,blocks,depth+1) &&
                   sameCoreExpr(old_units,a,na.b,new_units,b,nb.b,locals,blocks,depth+1);
        },
        if_value=>{
            if !sameCoreExpr(old_units,a,na.a,new_units,b,nb.a,locals,blocks,depth+1) { return false; }
            let lmark=locals.items.len;
            let ok1=sameCoreExpr(old_units,a,na.b,new_units,b,nb.b,locals,blocks,depth+1);
            locals.items.resize(lmark);
            if !ok1 { return false; }
            let ok2=sameCoreExpr(old_units,a,na.c,new_units,b,nb.c,locals,blocks,depth+1);
            locals.items.resize(lmark);
            return ok2;
        },
        if_stmt=>{
            if !sameCoreExpr(old_units,a,na.a,new_units,b,nb.a,locals,blocks,depth+1) { return false; }
            let ma=a.branchMerges(ia);
            let mb=b.branchMerges(ib);
            if ma.len!=mb.len { return false; }
            let lmark=locals.items.len;
            var ok=sameCoreExpr(old_units,a,na.b,new_units,b,nb.b,locals,blocks,depth+1);
            if ok {
                for i in 0..ma.len {
                    let mapped,found=lookupLocal(locals,ma[i].then_binding);
                    if !found || mapped!=mb[i].then_binding { ok=false; break; }
                }
            }
            locals.items.resize(lmark);
            if !ok { return false; }
            ok=sameCoreExpr(old_units,a,na.c,new_units,b,nb.c,locals,blocks,depth+1);
            if ok {
                for i in 0..ma.len {
                    let mapped,found=lookupLocal(locals,ma[i].else_binding);
                    if !found || mapped!=mb[i].else_binding { ok=false; break; }
                }
            }
            locals.items.resize(lmark);
            if !ok { return false; }
            for i in 0..ma.len { mapBind(locals,ma[i].result,mb[i].result); }
            return true;
        },
        block_,suite=>{
            let bmark=blocks.items.len;
            if na.tag==blot_check_core::Tag.block_ { mapBind(blocks,ia,ib); }
            let ca=a.children(ia);
            let cb=b.children(ib);
            if ca.len!=cb.len { blocks.items.resize(bmark); return false; }
            let lmark=locals.items.len;
            for i in 0..ca.len {
                if !sameCoreExpr(old_units,a,ca[i],new_units,b,cb[i],locals,blocks,depth+1) {
                    locals.items.resize(lmark);
                    blocks.items.resize(bmark);
                    return false;
                }
            }
            blocks.items.resize(bmark);
            return true;
        },
        bind=>{
            if na.c>=2 || nb.c>=2 {
                if na.c<2 || nb.c<2 { return false; }
                let mapped,ok=lookupLocal(locals,na.c-2);
                if !ok || mapped!=nb.c-2 { return false; }
            } else if na.c!=nb.c { return false; }
            if !sameCoreExpr(old_units,a,na.b,new_units,b,nb.b,locals,blocks,depth+1) { return false; }
            if !sameCoreType(a,a.binding(na.a).ty,b,b.binding(nb.a).ty,0) { return false; }
            mapBind(locals,na.a,nb.a);
            return true;
        },
        pattern_bind=>{
            if !sameCoreExpr(old_units,a,na.b,new_units,b,nb.b,locals,blocks,depth+1) { return false; }
            if (na.c==0)!=(nb.c==0) { return false; }
            if na.c!=0 {
                let fb_mark=locals.items.len;
                let ok_fb=sameCoreExpr(old_units,a,na.c,new_units,b,nb.c,locals,blocks,depth+1);
                locals.items.resize(fb_mark);
                if !ok_fb { return false; }
            }
            return samePattern(a,na.a,b,nb.a,locals,0);
        },
        return_=>{
            if !sameCoreExpr(old_units,a,na.a,new_units,b,nb.a,locals,blocks,depth+1) { return false; }
            if na.b==0 || nb.b==0 { return na.b==nb.b; }
            let mapped,ok=lookupLocal(blocks,na.b);
            return ok && mapped==nb.b;
        },
        product,array,construct=>{
            if na.tag==blot_check_core::Tag.construct {
                if na.a!=nb.a { return false; }
                return sameCoreExpr(old_units,a,na.b,new_units,b,nb.b,locals,blocks,depth+1);
            }
            let ca=a.children(ia);
            let cb=b.children(ib);
            if ca.len!=cb.len { return false; }
            for i in 0..ca.len {
                if !sameCoreExpr(old_units,a,ca[i],new_units,b,cb[i],locals,blocks,depth+1) { return false; }
            }
            return true;
        },
        record=>{
            let ca=a.children(ia);
            let cb=b.children(ib);
            if ca.len!=cb.len { return false; }
            let da=a.recordDestinations(ia);
            let db=b.recordDestinations(ib);
            if da.len!=db.len { return false; }
            for i in 0..ca.len {
                if da[i]!=db[i] { return false; }
                if !sameCoreExpr(old_units,a,ca[i],new_units,b,cb[i],locals,blocks,depth+1) { return false; }
            }
            return true;
        },
        project=>{
            if !sameCoreExpr(old_units,a,na.a,new_units,b,nb.a,locals,blocks,depth+1) { return false; }
            return sameProjection(a,na.b,b,nb.b);
        },
        update=>{
            let ua=a.updateInfo(ia);
            let ub=b.updateInfo(ib);
            if ua.store!=ub.store || (ua.self_binding==0)!=(ub.self_binding==0) { return false; }
            if !sameCoreExpr(old_units,a,ua.root,new_units,b,ub.root,locals,blocks,depth+1) { return false; }
            let pa=a.updatePath(ia);
            let pb=b.updatePath(ib);
            if pa.len!=pb.len { return false; }
            for i in 0..pa.len {
                if !sameProjection(a,pa[i],b,pb[i]) { return false; }
            }
            let sa=a.updateSelectors(ia);
            let sb=b.updateSelectors(ib);
            if sa.len!=sb.len { return false; }
            for i in 0..sa.len {
                if sa[i].kind!=sb[i].kind { return false; }
                if !sameCoreType(a,sa[i].source_type,b,sb[i].source_type,0) || !sameCoreType(a,sa[i].result_type,b,sb[i].result_type,0) { return false; }
                if sa[i].kind==blot_check_core::UpdateKind.index {
                    if !sameCoreExpr(old_units,a,sa[i].index,new_units,b,sb[i].index,locals,blocks,depth+1) { return false; }
                } else {
                    if !sameProjection(a,sa[i].projection,b,sb[i].projection) { return false; }
                }
            }
            let lmark=locals.items.len;
            if ua.self_binding!=0 { mapBind(locals,ua.self_binding,ub.self_binding); }
            let ok=sameCoreExpr(old_units,a,ua.value,new_units,b,ub.value,locals,blocks,depth+1);
            locals.items.resize(lmark);
            return ok;
        },
        call=>{
            let ca=a.call(ia);
            let cb=b.call(ib);
            if resolveRef(old_units,a,ca.target)!=resolveRef(new_units,b,cb.target) { return false; }
            if ca.own!=cb.own || !sameCoreType(a,ca.callee_type,b,cb.callee_type,0) { return false; }
            if ca.arguments.len!=cb.arguments.len { return false; }
            for i in 0..ca.arguments.len {
                if !sameCoreExpr(old_units,a,ca.arguments[i],new_units,b,cb.arguments[i],locals,blocks,depth+1) { return false; }
            }
            return true;
        },
        array_op,storage=>{
            if na.c!=nb.c { return false; }
            let ca=a.children(ia);
            let cb=b.children(ib);
            if ca.len!=cb.len { return false; }
            for i in 0..ca.len {
                if !sameCoreExpr(old_units,a,ca[i],new_units,b,cb[i],locals,blocks,depth+1) { return false; }
            }
            return true;
        },
        panic=>{ return sameCoreExpr(old_units,a,na.a,new_units,b,nb.a,locals,blocks,depth+1); },
        spark=>{
            let sa=a.sparkInfo(ia);
            let sb=b.sparkInfo(ib);
            if sa.is_range!=sb.is_range { return false; }
            if !sameCoreExpr(old_units,a,sa.source,new_units,b,sb.source,locals,blocks,depth+1) { return false; }
            if sa.is_range && !sameCoreExpr(old_units,a,sa.end,new_units,b,sb.end,locals,blocks,depth+1) { return false; }
            let lmark=locals.items.len;
            var ok=true;
            if (sa.pattern==0)!=(sb.pattern==0) { ok=false; }
            else if sa.pattern!=0 { ok=samePattern(a,sa.pattern,b,sb.pattern,locals,0); }
            if ok { ok=sameCoreExpr(old_units,a,sa.body,new_units,b,sb.body,locals,blocks,depth+1); }
            locals.items.resize(lmark);
            return ok;
        },
        constructor_function,primitive_function=>{ return na.a==nb.a; },
        result_associated=>{
            if !sameFieldSymbol(a,na.b,b,nb.b) { return false; }
            return sameCoreExpr(old_units,a,na.a,new_units,b,nb.a,locals,blocks,depth+1);
        },
        closure=>{
            let ca=a.closure(ia);
            let cb=b.closure(ib);
            if ca.parameter.inferred!=cb.parameter.inferred { return false; }
            if !sameCoreType(a,ca.function_type,b,cb.function_type,0) || !sameCoreType(a,ca.parameter.ty,b,cb.parameter.ty,0) { return false; }
            let caps_a=a.closureCaptures(ia);
            let caps_b=b.closureCaptures(ib);
            if caps_a.len!=caps_b.len { return false; }
            for i in 0..caps_a.len {
                let mapped,ok=lookupLocal(locals,caps_a[i]);
                if !ok || mapped!=caps_b[i] { return false; }
            }
            let lmark=locals.items.len;
            mapBind(locals,ca.parameter.binding,cb.parameter.binding);
            let ok=sameCoreExpr(old_units,a,ca.body,new_units,b,cb.body,locals,blocks,depth+1);
            locals.items.resize(lmark);
            return ok;
        },
        match_=>{
            let ma=a.matchInfo(ia);
            let mb=b.matchInfo(ib);
            if ma.statement!=mb.statement || ma.inputs.len!=mb.inputs.len || ma.arms.len!=mb.arms.len { return false; }
            let in_a=a.matchInputs(ia);
            let in_b=b.matchInputs(ib);
            for i in 0..in_a.len {
                if !sameCoreExpr(old_units,a,in_a[i],new_units,b,in_b[i],locals,blocks,depth+1) { return false; }
            }
            let arms_a=a.matchArms(ia);
            let arms_b=b.matchArms(ib);
            let merges_a=a.branchMerges(ia);
            let merges_b=b.branchMerges(ib);
            if merges_a.len!=merges_b.len { return false; }
            if merges_a.len!=0 && arms_a.len!=2 { return false; }
            for i in 0..arms_a.len {
                let arm_a=arms_a[i];
                let arm_b=arms_b[i];
                if arm_a.rows.len!=arm_b.rows.len || (arm_a.guard_==0)!=(arm_b.guard_==0) { return false; }
                let rows_a=a.armRows(arm_a);
                let rows_b=b.armRows(arm_b);
                let lmark=locals.items.len;
                for ri in 0..rows_a.len {
                    let pa=a.rowPatterns(rows_a[ri]);
                    let pb=b.rowPatterns(rows_b[ri]);
                    if pa.len!=pb.len { locals.items.resize(lmark); return false; }
                    for pi in 0..pa.len {
                        if !samePattern(a,pa[pi],b,pb[pi],locals,0) { locals.items.resize(lmark); return false; }
                    }
                }
                if arm_a.guard_!=0 && !sameCoreExpr(old_units,a,arm_a.guard_,new_units,b,arm_b.guard_,locals,blocks,depth+1) {
                    locals.items.resize(lmark); return false;
                }
                var ok=sameCoreExpr(old_units,a,arm_a.body,new_units,b,arm_b.body,locals,blocks,depth+1);
                if ok && merges_a.len!=0 {
                    for mi in 0..merges_a.len {
                        var oa=merges_a[mi].else_binding;
                        var ob=merges_b[mi].else_binding;
                        if i==0 { oa=merges_a[mi].then_binding; ob=merges_b[mi].then_binding; }
                        let mapped,found=lookupLocal(locals,oa);
                        if !found || mapped!=ob { ok=false; break; }
                    }
                }
                locals.items.resize(lmark);
                if !ok { return false; }
            }
            for mi in 0..merges_a.len { mapBind(locals,merges_a[mi].result,merges_b[mi].result); }
            return true;
        },
        loop_=>{
            let la=a.loopInfo(ia);
            let lb=b.loopInfo(ib);
            if la.kind!=lb.kind || la.can_exit!=lb.can_exit || la.carries.len!=lb.carries.len { return false; }
            if !sameCoreExpr(old_units,a,la.first,new_units,b,lb.first,locals,blocks,depth+1) { return false; }
            if !sameCoreExpr(old_units,a,la.end,new_units,b,lb.end,locals,blocks,depth+1) { return false; }
            let lmark=locals.items.len;
            let bmark=blocks.items.len;
            mapBind(blocks,ia,ib);
            if (la.pattern==0)!=(lb.pattern==0) { locals.items.resize(lmark); blocks.items.resize(bmark); return false; }
            if la.pattern!=0 && !samePattern(a,la.pattern,b,lb.pattern,locals,0) { locals.items.resize(lmark); blocks.items.resize(bmark); return false; }
            let ca=a.loopCarries(ia);
            let cb=b.loopCarries(ib);
            for i in 0..ca.len {
                let mapped_in,ok_in=lookupLocal(locals,ca[i].incoming);
                if !ok_in || mapped_in!=cb[i].incoming { locals.items.resize(lmark); blocks.items.resize(bmark); return false; }
                mapBind(locals,ca[i].iteration,cb[i].iteration);
            }
            let ok=sameCoreExpr(old_units,a,la.body,new_units,b,lb.body,locals,blocks,depth+1);
            if ok {
                for i in 0..ca.len {
                    let mapped_be,ok_be=lookupLocal(locals,ca[i].backedge);
                    if !ok_be || mapped_be!=cb[i].backedge { locals.items.resize(lmark); blocks.items.resize(bmark); return false; }
                }
            }
            locals.items.resize(lmark);
            blocks.items.resize(bmark);
            if !ok { return false; }
            for i in 0..ca.len { mapBind(locals,ca[i].outgoing,cb[i].outgoing); }
            return true;
        },
        break_=>{
            let mapped,ok=lookupLocal(blocks,na.a);
            if !ok || mapped!=nb.a { return false; }
            let ca=a.breakValues(ia);
            let cb=b.breakValues(ib);
            if ca.len!=cb.len { return false; }
            for i in 0..ca.len {
                if !sameCoreExpr(old_units,a,ca[i],new_units,b,cb[i],locals,blocks,depth+1) { return false; }
            }
            return true;
        },
        associated=>{
            if na.c!=0 || nb.c!=0 {
                if !sameFieldSymbol(a,na.c,b,nb.c) { return false; }
            }
            return sameCoreExpr(old_units,a,na.a,new_units,b,nb.a,locals,blocks,depth+1) &&
                   sameCoreExpr(old_units,a,na.b,new_units,b,nb.b,locals,blocks,depth+1);
        },
        // Any complex or uncommon form conservatively marks the body as changed.
        _=>{ return false; },
    }
}

fn sameBodyShape(old_units:const Core[:],a:const Core&,ob:blot_check_core::Body,new_units:const Core[:],b:const Core&,nb:blot_check_core::Body)->bool {
    if ob.scheme.variables.len!=nb.scheme.variables.len || ob.scheme.obligations.len!=nb.scheme.obligations.len { return false; }
    var locals=LocalMap{};
    var blocks=LocalMap{};
    let pa=a.bodyParameters(ob);
    let pb=b.bodyParameters(nb);
    if pa.len!=pb.len { return false; }
    for i in 0..pa.len { mapBind(locals,pa[i].binding,pb[i].binding); }
    return sameCoreExpr(old_units,a,ob.root,new_units,b,nb.root,locals,blocks,0);
}

fn findEditedBindings(old_units:const Core[:],new_units:const Core[:],unit:u32,edited:u32[>..<]&)->bool {
    let a .= old_units[unit-1];
    let b .= new_units[unit-1];
    if a.unit!=b.unit || a.bodies.len!=b.bodies.len || a.diagnostics.len!=0 || b.diagnostics.len!=0 { return false; }
    if a.nominals.len!=b.nominals.len || a.constructors.len!=b.constructors.len ||
       a.contracts.len!=b.contracts.len || a.contract_members.len!=b.contract_members.len ||
       a.implementations.len!=b.implementations.len || a.implementation_members.len!=b.implementation_members.len ||
       a.member_templates.len!=b.member_templates.len || a.associated.len!=b.associated.len ||
       a.primitives.len!=b.primitives.len || a.operation_names.len!=b.operation_names.len ||
       a.type_tags.len!=b.type_tags.len || a.tag_calls.len!=b.tag_calls.len ||
       a.sparks.len!=b.sparks.len || a.kernels.len!=b.kernels.len || a.processes.len!=b.processes.len {
        return false;
    }
    for i in 0..a.nominals.len {
        if a.nominals[i].identity!=b.nominals[i].identity || a.nominals[i].constructors.len!=b.nominals[i].constructors.len { return false; }
    }
    for i in 0..a.constructors.len {
        let ca=a.constructors[i]; let cb=b.constructors[i];
        if ca.tag!=cb.tag || ca.nominal!=cb.nominal || !sameFieldSymbol(a,ca.name,b,cb.name) { return false; }
        if !sameCoreType(a,ca.payload,b,cb.payload,0) || !sameCoreType(a,ca.scheme.root,b,cb.scheme.root,0) { return false; }
    }
    for i in 0..a.associated.len {
        let aa=a.associated[i]; let ab=b.associated[i];
        if aa.identity!=ab.identity || aa.operator!=ab.operator || aa.target!=ab.target { return false; }
        if (aa.member!=0 || ab.member!=0) && !sameFieldSymbol(a,aa.member,b,ab.member) { return false; }
    }
    if a.primitives!=b.primitives || a.operation_names!=b.operation_names || a.type_tags!=b.type_tags || a.tag_calls!=b.tag_calls { return false; }
    if a.contracts.len!=0 && (a.contracts!=b.contracts || a.contract_members!=b.contract_members) { return false; }
    if a.implementations.len!=0 && (!blot_reuse_body_shape::same___reuse_principal_interface_Implementation(a.implementations,b.implementations) || a.implementation_members!=b.implementation_members || a.member_templates!=b.member_templates) { return false; }

    // Check every global/external binding keeps its ID, metadata and structural type.
    for ob,bi in a.bindings {
        if ob.kind!=blot_reuse_principal_interface::Kind.global && ob.kind!=blot_reuse_principal_interface::Kind.external { continue; }
        if bi>=b.bindings.len { return false; }
        let nb=b.bindings[bi];
        if ob.kind!=nb.kind || ob.private!=nb.private || ob.body_id!=nb.body_id ||
           ob.capability_parameters!=nb.capability_parameters || ob.has_explicit!=nb.has_explicit { return false; }
        if ob.kind==blot_reuse_principal_interface::Kind.external && resolveRef(old_units,a,ob.target)!=resolveRef(new_units,b,nb.target) { return false; }
        if !sameCoreType(a,ob.ty,b,nb.ty,0) { return false; }
    }
    for nb,bi in b.bindings {
        if nb.kind!=blot_reuse_principal_interface::Kind.global && nb.kind!=blot_reuse_principal_interface::Kind.external { continue; }
        if bi>=a.bindings.len || a.bindings[bi].kind!=nb.kind { return false; }
    }

    // Check every body header and classify which bodies changed structurally.
    for bi in 1..a.bodies.len {
        let ob=a.bodies[bi];
        let nb=b.bodies[bi];
        if ob.binding!=nb.binding || ob.exported!=nb.exported || ob.runtime!=nb.runtime || ob.is_function!=nb.is_function || ob.is_kernel!=nb.is_kernel { return false; }
        if a.name(ob.declaration_name)!=b.name(nb.declaration_name) || a.name(ob.export_name)!=b.name(nb.export_name) { return false; }
        let pa=a.bodyParameters(ob);
        let pb=b.bodyParameters(nb);
        if pa.len!=pb.len { return false; }
        for pi in 0..pa.len {
            if pa[pi].inferred!=pb[pi].inferred || !sameCoreType(a,pa[pi].ty,b,pb[pi].ty,0) { return false; }
        }
        if !sameBodyShape(old_units,a,ob,new_units,b,nb) {
            if ob.exported && !ob.is_function { return false; }
            edited.push(ob.binding);
            if edited.len>16 { return false; }
        }
    }
    return true;
}

fn containsU32(list:const u32[:],value:u32)->bool {
    for item in list { if item==value { return true; } }
    return false;
}

fn hasStagedUnit(sites:const blot_direct_relocations::Site[:],unit:u32)->bool {
    for site in sites {
        if site.offset==-1 && site.unit==unit { return true; }
    }
    return false;
}

fn replayEdits(image:const Image&,previous:const Prepared&,next:const Prepared&,replay:Replay&,out_bytes:u8[:]&,pending:blot_direct_relocations::Snapshot&)->bool {
    if !replay.valid || image.bytes.len==0 { return false; }
    if previous.entry!=next.entry || previous.units.len!=next.units.len { return false; }
    var differing:u32[>..<]=[];
    for unit,i in next.units {
        if next.borrowed[i] { continue; }
        if previous.paths[i]!=next.paths[i] { return false; }
        if sameUnit(previous.units[i],unit) { continue; }
        differing.push(unit.unit);
    }
    if differing.len==0 { return false; }
    var changed_unit:u32=0;
    if differing.len==1 {
        changed_unit=differing[0];
    } else {
        for cand in differing {
            var all_importers=true;
            for other_u in differing {
                if other_u==cand { continue; }
                if !sameImporter(previous.units,next.units,(other_u-1) as i64,cand) { all_importers=false; break; }
            }
            if all_importers { changed_unit=cand; break; }
        }
    }
    if changed_unit==0 { return false; }
    if hasStagedUnit(image.layout.sites,changed_unit) { return false; }
    var edited:u32[>..<]=[];
    if !findEditedBindings(previous.units,next.units,changed_unit,edited) { return false; }

    let m .= next.units[changed_unit-1];
    let old_m .= previous.units[changed_unit-1];
    let s .= replay.state;
    let w .= replay.module;
    let instances=s.instances.len;
    let functions=w.functions.len;
    for eb in edited {
        let _,was_inlined=s.inlined_callees.get(blot_direct_emit::key64(changed_unit,eb));
        if was_inlined { return false; }
    }

    // Collect named instances of edited bindings and ensure no non-named instances depend on them.
    var to_replay:u32[>..<]=[];
    var skip_fn:u8[>..<]=[];
    for i in 0..functions { skip_fn.push(0); }
    for index in 0..instances {
        let item=s.instances[index];
        if item.key.kind==blot_direct_emit::InstanceKind.named && item.key.unit==changed_unit && containsU32(edited[..],item.key.id) {
            to_replay.push(index as u32);
            skip_fn[item.function-w.imports.len]=1;
        }
    }
    for index in 0..instances {
        let item=s.instances[index];
        if item.key.kind==blot_direct_emit::InstanceKind.named { continue; }
        if item.key.unit==changed_unit {
            if item.key.kind==blot_direct_emit::InstanceKind.lambda && containsU32(to_replay[..],item.key.parent) { return false; }
            if containsU32(edited[..],item.key.id) { return false; }
        }
    }

    // If no edited binding has any emitted instance, the Wasm bytes are unchanged!
    if to_replay.len==0 {
        replay.types.units=next.catalog_owner.mutable(next.units);
        replay.types.resetClosedUnit(changed_unit);
        s.resetUnitCaches(changed_unit);
        var drop_unit:u32=0;
        if old_m.nodes.len!=m.nodes.len { drop_unit=changed_unit; }
        var bytes:u8[>..<]=[];
        blot_direct_relocations::beginReplay(image.layout.body_sites,skip_fn[..],drop_unit);
        blot_direct_writer::assemble(w,bytes);
        pending=blot_direct_relocations::finish();
        out_bytes=blot_reuse_dependency_consumer::ownBytes(bytes[..]);
        return true;
    }

    // Speculative replay mutates retained state; invalidate until verified.
    replay.valid=false;
    replay.types.units=next.catalog_owner.mutable(next.units);
    replay.types.resetClosedUnit(changed_unit);
    replay.types.nominal_positions.clear();
    s.resetUnitCaches(changed_unit);
    s.track_deps=true;
    s.replaying=true;
    s.dep_match=true;
    let sections=[w.signatures.len,w.imports.len,w.table.len,w.globals.len,w.exports.len,w.data.len,w.customs.len];
    var drop_unit:u32=0;
    if old_m.nodes.len!=m.nodes.len { drop_unit=changed_unit; }
    blot_direct_relocations::beginReplay(image.layout.body_sites,skip_fn[..],drop_unit);

    var g=blot_direct_emit::Generator{types:replay.types,module:w,s:s,units:next.units};
    for id in to_replay {
        let item=s.instances[id];
        let body .= m.body(item.key.id);
        if !body { s.replaying=false; blot_direct_relocations::abortReplay(); return false; }
        var env=blot_direct_types::Env{};
        g.types.match_(m,m.binding(item.key.id).ty,item.key.ty,env);
        if blot_direct_emit::solveObligationsPublic(g,m,body.scheme.obligations,env)!=blot_direct_types::Error.none {
            s.replaying=false; blot_direct_relocations::abortReplay(); return false;
        }
        s.instances[id].env=env;
        s.instances[id].inferring=item.was_inferred;
        let err=blot_direct_function::emitInstance(g,id);
        s.instances[id].inferring=false;
        if err!=blot_direct_types::Error.none || s.instances[id].result!=item.result {
            s.replaying=false; blot_direct_relocations::abortReplay(); return false;
        }
    }
    s.replaying=false;
    if s.has_failure || s.failures.len!=0 || !s.dep_match {
        blot_direct_relocations::abortReplay();
        return false;
    }
    if instances!=s.instances.len || functions!=w.functions.len ||
       sections!=[w.signatures.len,w.imports.len,w.table.len,w.globals.len,w.exports.len,w.data.len,w.customs.len] {
        blot_direct_relocations::abortReplay();
        return false;
    }
    var bytes:u8[>..<]=[];
    blot_direct_writer::assemble(w,bytes);
    pending=blot_direct_relocations::finish();
    if hasStagedUnit(pending.sites,changed_unit) {
        pending.deinit();
        return false;
    }
    out_bytes=blot_reuse_dependency_consumer::ownBytes(bytes[..]);
    replay.valid=true;
    return true;
}

fn emitTracked(prepared:const Prepared&,replay:Replay&,build_inputs:i64)->Emission,blot_error::Error {
    assert(!replay.used);
    replay.used=true;
    replay.valid=false;
    let rooted_units=prepared.catalog_owner.mutable(prepared.units);
    replay.types.units=rooted_units;
    var bytes:u8[>..<]=[];
    var message:u8[>..<]=[];
    let built=blot_direct::compileTracked(rooted_units,prepared.entry,replay.types,replay.module,replay.state,bytes,message,build_inputs);
    var compiled=blot_reuse_dependency_consumer::Compiled{};
    if built.failed {
        compiled=blot_reuse_dependency_consumer::Compiled{
            failed:true,
            diagnostic:blot_compile::Diagnostic{unit:built.unit,span:built.span,code:built.code},
            message:blot_reuse_dependency_consumer::ownBytes(message[..]),
            emitted_functions:built.emitted_functions,..
        };
    } else {
        compiled=blot_reuse_dependency_consumer::Compiled{
            bytes:blot_reuse_dependency_consumer::ownBytes(bytes[..]),
            emitted_functions:built.emitted_functions,
            sparks_vectorized:built.sparks_vectorized,
            sparks_scalar_fallback:built.sparks_scalar_fallback,
            staged_dep_units_valid:built.staged_dep_units_valid,
            staged_dep_units:blot_reuse_dependency_consumer::ownU32s(replay.state.staged_dep_units[..]),
            staged_value_digest:built.staged_value_digest,..
        };
        replay.valid=true;
    }
    var result=Emission{
        result:blot_reuse_dependency_consumer::Result{compiled:compiled,stats:prepared.stats,..},
        source_bytes:prepared.source_bytes,
        fresh_modules:prepared.units.len-prepared.cachedCount(),
        cached_modules:prepared.cachedCount()
    };
    if compiled.failed {
        let unit=compiled.diagnostic.unit;
        if unit==0 || unit>prepared.paths.len { result.deinit(); return Emission{},blot_error::Error.invalid_unit; }
        result.diagnostic_filename=blot_support::some(blot_reuse_partial_dependency::copyResultBytes(prepared.paths[unit-1]));
    }
    return result,blot_error::Error.none;
}
