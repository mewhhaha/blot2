import os;
import static_publish_build;
import static_publish_verify;
import static_publish_wasm;
import static_publish_target;
fn main() {
 let source="static let coords = #[(1, -0.0), (3, 0.0 / 0.0)]\n";
 var built=static_publish_build::build(source);assert(built.status==0 && static_publish_verify::verify(source,built.image));
 assert(built.image.rows==2 && built.image.width==2 && built.image.bytes==16 && built.image.steps==10);
 let module=static_publish_wasm::emit(source,built.image);assert(module.len>0 && static_publish_target::verify(source,built.image,module));
 assert(write_file("static-publish.wasm",module));
 for i in module.len {var m=copy(module);m[i]^=1;assert(!static_publish_target::verify(source,built.image,m));}
 for f in 5 {var bad=copy(built.image);if f==0 {bad.width+=1;}else if f==1 {bad.rows+=1;}else if f==2 {bad.bytes+=1;}
    else if f==3 {bad.steps+=1;}else {bad.data[0]^=1;}
    assert(!static_publish_verify::verify(source,bad) && static_publish_wasm::emit(source,bad).len==0);}
 assert(!static_publish_verify::verify("static let wrong = #[(1, -0.0), (3, 0.0 / 0.0)]\n",built.image));
 for fail in ["static let no = (1,2)","static let invalid = #[(4294967295+1,2)]","static let empty = #[]"] {
    let bad=static_publish_build::build(fail);assert(bad.status!=0 && bad.image.data.len==0 && static_publish_wasm::emit(fail,bad.image).len==0);
 }
 let twin="static let other = #[(1, -0.0), (3, 0.0 / 0.0)]\n";var second=static_publish_build::build(twin);
 assert(second.status==0 && !static_publish_verify::verify(twin,built.image));
 let twin_module=static_publish_wasm::emit(twin,second.image);assert(twin_module[..]==module[..] && write_file("static-publish-twin.wasm",twin_module));
 var wide:u8[>..]=[];wide.append("static let wide = #[");for i in 8193 {if i>0 {wide.push(',');}wide.append("(1,2)");}wide.append("]\n");
 var many=static_publish_build::build(wide);assert(many.status==0 && many.image.bytes==65544 && many.image.rows==8193);
 let wide_module=static_publish_wasm::emit(wide,many.image);assert(wide_module.len>0 && write_file("static-publish-wide.wasm",wide_module));
 print("private source-bound static image and exact target passed");
}
