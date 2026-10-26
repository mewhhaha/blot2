// Independent final byte checker for the generalized private particle worker.
// It independently rebuilds the exact worker instruction stream from checked
// postorder Core, and compares each trusted setup/helper body and all fixed
// sections to the reviewed snapshot. This is bounded fixture validation, not
// a general Wasm validator, source ownership proof, public ABI or M13 cert.
namespace i08_same_target;
import particle_source_core;
import i08_same_golden;
import particle_lower_core;
import particle_lower_verify;
struct Leb {value:i64=0,next:i64=0,ok:bool=false}
struct Section {start:i64=0,payload:i64=0,end:i64=0,ok:bool=false}
fn read_leb(data:u8[:],pos:i64,limit:i64)->Leb {
    if pos<0 || limit<0 || limit>data.len || pos>=limit{return Leb {};}
    var p=pos;var result:u64=0;var shift:i64=0;var count:i64=0;
    while p<limit && count<5 {
        let byte=data[p];p+=1;count+=1;
        if count==5 && (byte&0xf0)!=0 {return Leb {};}
        result |= ((byte&127) as u64) << shift;
        if (byte&128)==0 {
            if count>1 && (byte&127)==0 {return Leb {};}
            return Leb {value:result as i64,next:p,ok:true};
        }
        shift+=7;
    }
    return Leb {};
}
fn section(data:u8[:],pos:i64,id:u8)->Section {
    if pos<0 || pos>=data.len || data[pos]!=id {return Section {};}
    let size=read_leb(data,pos+1,data.len);if !size.ok || size.value>data.len-size.next{return Section {};}
    return Section {start:pos,payload:size.next,end:size.next+size.value,ok:true};
}
fn independently_rebuild(core:particle_lower_core::Core&)->u8[] {
    if core.x_root==0 || core.x_root>=core.nodes.len || core.y_root!=core.nodes.len {return [];}
    var out:u8[>..]=[2,1,0x7f,2,0x7d, 0x41,0,0x21,6, 0x02,0x40,0x03,0x40, 0x20,6,0x20,1,0x4f,0x0d,1];
    for row in 2 {
        let begin=if row==0 {0} else {core.x_root as i64};
        let end=if row==0 {core.x_root as i64} else {core.nodes.len};
        for i in begin..end {
            let node=core.nodes[i];
            if node.kind==1 {
                if node.field>3{return [];}
                out.append([0x20,0,0x20,6,0x41,16,0x6c,0x6a,0x2a,2,(node.field*4) as u8]);
            } else if node.kind==2 {out.append([0x20,5]);}
            else if node.kind==3 {out.push(0x94);}
            else if node.kind==4 {out.push(0x92);}
            else {return [];}
        }
        out.append([0x21,if row==0 {7} else {8}]);
    }
    out.append([0x20,2,0x20,6,0x41,8,0x6c,0x6a,0x20,7,0x38,2,0,
        0x20,2,0x20,6,0x41,8,0x6c,0x6a,0x20,8,0x38,2,4]);
    out.append([0x20,3,0x20,6,0x41,1,0x6a,0x36,2,12, 0x20,6,0x41,1,0x6a,0x21,6,0x0c,0,
        0x0b,0x0b, 0x20,1,0x45,0x04,0x40,0x20,3,0x41,0,0x36,2,8,0x0b,
        0x20,3,0x41,2,0x36,2,0,0x20,1,0x0b]);
    return out;
}
fn verify(core:particle_lower_core::Core&,source:u8[:],context:particle_source_core::Context,bytes:u8[:])->bool {
    if !particle_lower_verify::verify(core,source,context) || bytes.len<8 || bytes.len>65536{return false;}
    let golden=i08_same_golden::bytes();
    let header:u8[8]=[0,0x61,0x73,0x6d,1,0,0,0];
    if bytes[..8]!=header[..] || golden[..8]!=header[..]{return false;}
    var p:i64=8;var q:i64=8;
    for id in [1,3,5,7] {
        let actual=section(bytes,p,id as u8);let known=section(golden,q,id as u8);
        if !actual.ok || !known.ok || bytes[actual.start..actual.end]!=golden[known.start..known.end]{return false;}
        p=actual.end;q=known.end;
    }
    let ac=section(bytes,p,10);let gc=section(golden,q,10);
    if !ac.ok || !gc.ok || ac.end!=bytes.len || gc.end!=golden.len{return false;}
    let an=read_leb(bytes,ac.payload,ac.end);let gn=read_leb(golden,gc.payload,gc.end);
    if !an.ok || !gn.ok || an.value!=15 || gn.value!=15{return false;}
    p=an.next;q=gn.next;
    // The first ten preflight/setup/owner helper bodies are fixed trusted
    // components; exact comparison includes their canonical body-size LEBs.
    for i in 10 {
        let alen=read_leb(bytes,p,ac.end);let glen=read_leb(golden,q,gc.end);
        if !alen.ok || !glen.ok || alen.value>ac.end-alen.next || glen.value>gc.end-glen.next{return false;}
        let ae=alen.next+alen.value;let ge=glen.next+glen.value;
        if bytes[p..ae]!=golden[q..ge]{return false;}p=ae;q=ge;
    }
    let alen=read_leb(bytes,p,ac.end);let glen=read_leb(golden,q,gc.end);
    if !alen.ok || !glen.ok || alen.value>ac.end-alen.next || glen.value>gc.end-glen.next{return false;}
    let rebuilt=independently_rebuild(core);let ae=alen.next+alen.value;let ge=glen.next+glen.value;
    if rebuilt.len==0 || bytes[alen.next..ae]!=rebuilt[..]{return false;}p=ae;q=ge;
    for i in 4 {
        let ax=read_leb(bytes,p,ac.end);let gx=read_leb(golden,q,gc.end);
        if !ax.ok || !gx.ok || ax.value>ac.end-ax.next || gx.value>gc.end-gx.next{return false;}
        let aend=ax.next+ax.value;let gend=gx.next+gx.value;
        if bytes[p..aend]!=golden[q..gend]{return false;}p=aend;q=gend;
    }
    return p==ac.end && q==gc.end;
}
