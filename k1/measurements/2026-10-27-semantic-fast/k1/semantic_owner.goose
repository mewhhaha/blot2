// Private single-declaration semantic owner. The expected identity and bytes
// come from a trusted job; this module does not resolve files or issue authority.
namespace semantic_owner;
import source_identity;
import semantic_leaf;
struct Owner {origin:source_identity::Source=source_identity::Source {},core:semantic_leaf::Core=semantic_leaf::Core {}}
struct Build {status:i64=1,owner:Owner=Owner {}}
fn declaration(source:u8[:],c:semantic_leaf::Core&,expected:u8[:])->bool {
 let start=c.program.head.let_start;let a=c.program.name_start;let b=c.program.name_end;
 if start<0 || start>source.len || a<0 || b<=a || b>source.len-start{return false;}
 return source[start+a..start+b]==expected;
}
fn valid(package:u8[:],module:u8[:],name:u8[:],source:u8[:],o:Owner&)->bool {
 return source_identity::verify(o.origin,package,module,name,source) &&
        semantic_leaf::valid(source,o.core) && declaration(source,o.core,name);
}
fn build(package:u8[:],module:u8[:],name:u8[:],source:u8[:])->Build {
 let id=source_identity::make(package,module,name,source);if id.status!=0 {return Build {};}
 var c=semantic_leaf::build(source);if c.status!=0 || !declaration(source,c.core,name){return Build {};}
 var owner=Owner {origin:copy(id.source),core:copy(c.core)};
 if !valid(package,module,name,source,owner){return Build {};}
 return Build {status:0,owner:copy(owner)};
}
fn verify(package:u8[:],module:u8[:],name:u8[:],source:u8[:],o:Owner&,target:u8[:])->bool {
 return valid(package,module,name,source,o) && semantic_leaf::verify(source,o.core,target);
}
fn emit(package:u8[:],module:u8[:],name:u8[:],source:u8[:],o:Owner&,depth_used:u32,depth_limit:u32,frame_used:u32,frame_limit:u32)->semantic_leaf::Output {
 if !valid(package,module,name,source,o){return semantic_leaf::Output {};}
 let output=semantic_leaf::emit(source,o.core,depth_used,depth_limit,frame_used,frame_limit);
 if output.status!=0 {return output;}
 if !verify(package,module,name,source,o,output.wasm){return semantic_leaf::Output {};}
 return output;
}
