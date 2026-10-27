// Independent Wasm instruction typing over emitted bytes, with no Core SSA or
// lowering state. Hash binding does not authenticate code or prove provenance.
namespace wasmcheck;
import .model;
struct Signature { parameters:Span, result:u8 }
struct Control { kind:u8, height:u32, result:u8, unreachable:bool, seen_else:bool }
fn body(bytes:const u8[:], signatures:const Signature[:], parameter_types:const u8[:],
        function_types:const u32[:], current_type:u32, table_size:u32)->bool {
    if current_type>=signatures.len || bytes.len>LIMIT_ARTIFACT { return false; }
    var cursor:u32=0; var valid=true;
    var stack:u8[>..]=[]; var locals:u8[>..]=[]; var controls:Control[>..]=[];
    fn byte()->u8 { if cursor>=bytes.len { valid=false; return 0; } let x=bytes[cursor]; cursor++; return x; }
    fn unsigned()->u32 {
        var value:u32=0;
        for i in 5 { let x=byte(); if i==4 && x>15 { valid=false; return 0; } value|=((x as u32)&127)<<(i*7); if x<128 { return value; } }
        valid=false; return 0;
    }
    fn signed() {
        for i in 5 { let x=byte(); if i==4 && !((x<=7)||(x>=120 && x<=127)) { valid=false; return; } if x<128 { return; } }
        valid=false;
    }
    fn push(ty:u8) { if ty!=0 { if stack.len>=1048576 { valid=false; return; } stack.push(ty); } }
    fn pop_any()->u8 {
        if controls.len==0 { valid=false; return 0; }
        let frame=controls[controls.len-1];
        if stack.len==frame.height && frame.unreachable { return 0; }
        if stack.len<=frame.height { valid=false; return 0; }
        let ty=stack[stack.len-1]; stack.resize(stack.len-1); return ty;
    }
    fn pop(ty:u8) { let actual=pop_any(); if actual!=0 && actual!=ty { valid=false; } }
    fn unreachable() { if controls.len==0 { valid=false; return; } let top=controls.len-1; stack.resize(controls[top].height as i64); controls[top].unreachable=true; }
    fn label(depth:u32)->u8 {
        if depth>=controls.len { valid=false; return 0; }
        let target=controls[controls.len-1-depth]; return if target.kind==0x03 {0} else {target.result};
    }
    fn invoke(type_id:u32) {
        if type_id>=signatures.len { valid=false; return; } let signature=signatures[type_id];
        if !span_ok(signature.parameters,parameter_types.len) { valid=false; return; }
        var n=signature.parameters.count;
        while n!=0 { n--; pop(parameter_types[signature.parameters.start+n]); }
        push(signature.result);
    }
    let signature=signatures[current_type];
    if !span_ok(signature.parameters,parameter_types.len) || (signature.result!=0 && signature.result!=0x7f && signature.result!=0x7d) { return false; }
    locals.append(parameter_types[signature.parameters.start..signature.parameters.start+signature.parameters.count]);
    let groups=unsigned(); if groups>2 { return false; }
    for group in groups {
        let count=unsigned(); let ty=byte();
        if count>1048576-locals.len || (ty!=0x7f && ty!=0x7d) { return false; }
        for i in count { locals.push(ty); }
    }
    controls.push(Control {0xff,0,signature.result,false,false});
    while valid && cursor<bytes.len {
        let instruction=byte();
        if instruction==0x00 { unreachable(); }
        else if instruction==0x02 || instruction==0x03 || instruction==0x04 {
            if instruction==0x04 { pop(0x7f); }
            let encoded=byte(); let result=if encoded==0x40 {0 as u8} else {encoded};
            if result!=0 && result!=0x7f && result!=0x7d { return false; }
            if controls.len>=65536 { return false; }
            controls.push(Control {instruction,stack.len as u32,result,false,false});
        } else if instruction==0x05 {
            if controls.len==0 { return false; } let i=controls.len-1; let frame=controls[i];
            if frame.kind!=0x04 || frame.seen_else { return false; }
            if frame.result!=0 { pop(frame.result); }
            if stack.len!=frame.height { return false; }
            controls[i].unreachable=false; controls[i].seen_else=true;
        } else if instruction==0x0b {
            if controls.len==0 { return false; } let frame=controls[controls.len-1];
            if frame.kind==0x04 && !frame.seen_else && frame.result!=0 { return false; }
            if frame.result!=0 { pop(frame.result); }
            if stack.len!=frame.height { return false; }
            controls.resize(controls.len-1); push(frame.result);
            if controls.len==0 { return valid && cursor==bytes.len && stack.len==(if signature.result==0 {0} else {1}); }
        } else if instruction==0x0c || instruction==0x0d {
            let depth=unsigned(); if instruction==0x0d { pop(0x7f); }
            let ty=label(depth); if ty!=0 { pop(ty); }
            if instruction==0x0c { unreachable(); } else { push(ty); }
        } else if instruction==0x0f {
            if signature.result!=0 { pop(signature.result); } unreachable();
        } else if instruction==0x10 {
            let target=unsigned(); if target>=function_types.len { return false; } invoke(function_types[target]);
        } else if instruction==0x11 {
            let target=unsigned(); let table=unsigned();
            if table!=0 || table_size==0 { return false; } pop(0x7f); invoke(target);
        } else if instruction==0x1a { pop_any(); }
        else if instruction==0x1b {
            pop(0x7f); let right=pop_any(); let left=pop_any();
            if right!=0 && left!=0 && right!=left { return false; }
            // Unknown is a polymorphic stack value in an unreachable frame.
            if left==0 && right==0 { stack.push(0); } else { push(if left==0 {right} else {left}); }
        } else if instruction==0x20 || instruction==0x21 || instruction==0x22 {
            let local=unsigned(); if local>=locals.len { return false; }
            if instruction!=0x20 { pop(locals[local]); } if instruction!=0x21 { push(locals[local]); }
        } else if instruction==0x28 || instruction==0x2a || instruction==0x2d || instruction==0x36 || instruction==0x38 {
            let alignment=unsigned(); unsigned(); if alignment>(if instruction==0x2d {0 as u32} else {2}) { return false; }
            let ty=if instruction==0x2a || instruction==0x38 {0x7d as u8} else {0x7f};
            if instruction==0x36 || instruction==0x38 { pop(ty); pop(0x7f); } else { pop(0x7f); push(ty); }
        } else if instruction==0x41 { signed(); push(0x7f); }
        else if instruction==0x43 { for i in 4 { byte(); } push(0x7d); }
        else if instruction==0x45 { pop(0x7f); push(0x7f); }
        else if instruction>=0x46 && instruction<=0x4f { pop(0x7f); pop(0x7f); push(0x7f); }
        else if instruction>=0x5b && instruction<=0x60 { pop(0x7d); pop(0x7d); push(0x7f); }
        else if instruction>=0x6a && instruction<=0x76 { pop(0x7f); pop(0x7f); push(0x7f); }
        else if instruction>=0x8b && instruction<=0x91 { pop(0x7d); push(0x7d); }
        else if instruction>=0x92 && instruction<=0x97 { pop(0x7d); pop(0x7d); push(0x7d); }
        else if instruction==0xa9 || instruction==0xbc { pop(0x7d); push(0x7f); }
        else if instruction==0xb3 || instruction==0xbe { pop(0x7f); push(0x7d); }
        else if instruction==0xfc {
            let operation=unsigned();
            if operation==10 { if unsigned()!=0 || unsigned()!=0 { return false; } }
            else if operation==11 { if unsigned()!=0 { return false; } }
            else { return false; }
            pop(0x7f); pop(0x7f); pop(0x7f);
        } else { return false; } // Includes memory.grow, imports/global/reference instructions.
    }
    return false;
}

struct FunctionBody { bytes:Span }
struct Export { name:Span, kind:u8, index:u32 }
fn module_bytes(code:const u8[:], signatures:const Signature[:], parameter_types:const u8[:],
    function_types:const u32[:], bodies:const FunctionBody[:], expected_bodies:const u8[:],
    table:const u32[:], exports:const Export[:], names:const u8[:], pages:u32,
    static_base:u32, data:const u8[:])->bool {
    if code.len<8 || code.len>LIMIT_ARTIFACT || code[..8]!=[0 as u8,97,115,109,1,0,0,0] { return false; }
    var at:u32=8; var bound=code.len as u32; var valid=true; var previous:u8=0; var seen:u32=0;
    fn byte()->u8 { if at>=bound { valid=false; return 0; } let x=code[at]; at++; return x; }
    fn unsigned()->u32 { var value:u32=0; for i in 5 { let x=byte(); if i==4 && x>15 { valid=false; return 0; } value|=((x as u32)&127)<<(i*7); if x<128 { return value; } } valid=false; return 0; }
    fn bytes(expected:const u8[:])->bool {
        if expected.len>bound-at { return false; } let equal=code[at..at+expected.len as u32]==expected; at+=expected.len as u32; return equal;
    }
    var manifest=false;
    while valid && at<code.len {
        bound=code.len as u32; let section=byte(); let count=unsigned();
        if count>code.len-at { return false; } bound=at+count;
        if section==0 {
            let length=unsigned(); if length>bound-at || manifest { return false; }
            if !bytes("blot.k1.manifest") || length!=16 { return false; }
            manifest=true; at=bound; continue;
        }
        if section<=previous { return false; } previous=section;
        if section==1 {
            if unsigned()!=signatures.len { return false; }
            for sig in signatures {
                if byte()!=0x60 || unsigned()!=sig.parameters.count { return false; }
                if !span_ok(sig.parameters,parameter_types.len) { return false; }
                for ty in parameter_types[sig.parameters.start..sig.parameters.start+sig.parameters.count] { if (ty!=0x7f && ty!=0x7d) || byte()!=ty { return false; } }
                let results=unsigned(); if results!=(if sig.result==0 {0} else {1}) { return false; }
                if sig.result!=0 && ((sig.result!=0x7f && sig.result!=0x7d) || byte()!=sig.result) { return false; }
            } seen|=1;
        } else if section==3 {
            if unsigned()!=function_types.len { return false; }
            for ty in function_types { if ty>=signatures.len || unsigned()!=ty { return false; } } seen|=2;
        } else if section==4 {
            if table.len==0 || unsigned()!=1 || byte()!=0x70 || byte()!=1 || unsigned()!=table.len || unsigned()!=table.len { return false; } seen|=4;
        } else if section==5 {
            if unsigned()!=1 || byte()!=1 || unsigned()!=pages || unsigned()!=pages { return false; } seen|=8;
        } else if section==7 {
            if unsigned()!=exports.len { return false; }
            for ex in exports {
                if !span_ok(ex.name,names.len) || unsigned()!=ex.name.count || !bytes(names[ex.name.start..ex.name.start+ex.name.count]) || byte()!=ex.kind || unsigned()!=ex.index { return false; }
                if ex.kind==0 { if ex.index>=function_types.len { return false; } } else if ex.kind!=2 || ex.index!=0 { return false; }
            } seen|=16;
        } else if section==9 {
            if table.len==0 || unsigned()!=1 || byte()!=0 || byte()!=0x41 || byte()!=0 || byte()!=0x0b || unsigned()!=table.len { return false; }
            for target in table { if target>=function_types.len || unsigned()!=target { return false; } } seen|=32;
        } else if section==10 {
            if unsigned()!=function_types.len || bodies.len!=function_types.len { return false; }
            for span,i in bodies {
                let length=unsigned();
                if length!=span.bytes.count || length>bound-at || !span_ok(span.bytes,expected_bodies.len) { return false; }
                let actual=code[at..at+length];
                if actual!=expected_bodies[span.bytes.start..span.bytes.start+span.bytes.count] || !body(actual,signatures,parameter_types,function_types,function_types[i],table.len as u32) { return false; }
                at+=length;
            } seen|=64;
        } else if section==11 {
            if data.len==0 || unsigned()!=1 || byte()!=0 || byte()!=0x41 || unsigned()!=static_base || byte()!=0x0b || unsigned()!=data.len || !bytes(data) { return false; } seen|=128;
        } else { return false; } // No imports, globals, start hook or mutable tables.
        if !valid || at!=bound { return false; }
    }
    let required=(1 as u32)|2|8|16|64|(if table.len==0 {0} else {4|32})|(if data.len==0 {0} else {128});
    return valid && seen==required && at==code.len;
}
