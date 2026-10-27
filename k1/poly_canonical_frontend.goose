// Existing mixed parser builds both scalar and loop nodes directly in one arena.
namespace poly_canonical_frontend;
import lexer;
import validate;
import common_decl_header;
import mixed_frontend;
import mixed_parse;
import mixed_compiler_core;
import poly_mixed_validate;
import poly_canonical_core;
import poly_canonical_check;
fn parse(source:u8[:])->poly_canonical_core::Result {
 let h=common_decl_header::header(source);if !h.ok {return poly_canonical_core::Result {status:1};}let flat=common_decl_header::project(source,h);
 var c=mixed_frontend::Cursor {lex:lexer::init(flat)};mixed_frontend::advance(flat,c);while !c.bad && c.t.kind==6 {mixed_frontend::advance(flat,c);}
 if !mixed_frontend::take(flat,c,1,"let") {return poly_canonical_core::Result {status:1};}let name=c.t;
 if c.bad || name.kind!=1 || name.start<0 || name.end<=name.start || name.end>flat.len || !validate::name_valid(flat[name.start..name.end]) {return poly_canonical_core::Result {status:1};}mixed_frontend::advance(flat,c);
 if !mixed_frontend::take(flat,c,5,":") || !mixed_frontend::take(flat,c,1,if h.argument==1 {"U32"} else {"Bool"}) || !mixed_frontend::take(flat,c,5,"->") || !mixed_frontend::take(flat,c,1,if h.result==1 {"U32"} else {"Bool"}) || !mixed_frontend::take(flat,c,5,"=") {return poly_canonical_core::Result {status:1};}
 let f=c.t;if c.bad || f.kind!=1 || f.start<0 || f.end<=f.start || f.end>flat.len || flat[f.start..f.end]!="fn" {return poly_canonical_core::Result {status:1};}
 let tree,status=mixed_parse::parse(flat[f.start..]);if status!=0 {return poly_canonical_core::Result {status:status};}
 var old=mixed_compiler_core::Program {source:copy(flat),variant:2,name_start:name.start,name_end:name.end,fn_start:f.start,body:copy(tree)};if !poly_mixed_validate::verify(flat,old,h.argument,h.result) {return poly_canonical_core::Result {status:1};}
 let typing=poly_canonical_check::types(tree,h.argument);var p=poly_canonical_core::Program {source:source,head:h,name_start:name.start,name_end:name.end,fn_start:f.start,tree:copy(tree),types:copy(typing.node),binding_types:copy(typing.binding)};
 if !poly_canonical_check::verify(source,p) {return poly_canonical_core::Result {status:1};}return poly_canonical_core::Result {program:p};
}
