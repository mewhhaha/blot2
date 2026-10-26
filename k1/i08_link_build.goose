namespace i08_link_build;
import i08_header_parse;
import i08_cap_build;
import i08_link_core;
import i08_link_verify;
fn build(source:u8[:])->i08_link_core::Program,i64 {
 var tree,status=i08_header_parse::parse(source);if status!=0{return i08_link_core::Program {},status;}
 var cap,code=i08_cap_build::build(source);if code!=0{return i08_link_core::Program {},code;}
 var p=i08_link_core::Program {tree:copy(tree),cap:copy(cap)};if !i08_link_verify::verify(p,source) {return i08_link_core::Program {},1;}return p,0;
}
