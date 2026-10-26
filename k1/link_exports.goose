// Fresh, source-bound export collection for the narrow scalar provider subset.
// This is not a complete K1 interface, module checker, ABI profile or cache.
namespace link_exports;
import project_graph;
import link_lines;
import public_frontend;
import public_artifact;
import frontend;
import scalar_core;
import validate;
import catalog;

struct Export {module:i64=0,name_start:i64=0,name_end:i64=0,line_start:i64=0,line_end:i64=0,interface_start:i64=0,interface_end:i64=0,
               result_type:u32=0,depth:u32=0,frame:u32=0}
struct Declaration {module:i64=0,name_start:i64=0,name_end:i64=0}
struct Result {status:i64=0,values:Export[]=[],interfaces:u8[]=[]}
fn private_check(source:u8[:]) -> i64,i64,bool {
 let p=frontend::parse_scalar(source);if p.status!=0 {return 0,0,false;}
 var c=scalar_core::build(p.result_type,p.binary_op,p.kind,p.literal,p.right_kind,p.right_literal);
 c.name_start=p.name_start;c.name_end=p.name_end;c.parameter_start=p.parameter_start;c.parameter_end=p.parameter_end;
 c.left_start=p.start;c.left_end=p.end;c.operator_start=p.operator_start;c.operator_end=p.operator_end;c.right_start=p.right_start;c.right_end=p.right_end;
 if validate::scalar_v2(source,c,catalog::edition(),catalog::semantic_policy(),catalog::optimization_policy(),catalog::wasm_abi())!=0 {return 0,0,false;}
 return p.name_start,p.name_end,true;
}
// Graph source/path spans must already be independently checked by
// link_graph_check; only a fresh trusted resolver result is passed here.
fn collect(g:project_graph::Graph&,abi:u8[:]) -> Result {
 if abi.len!=32 {return Result {status:1};}
 var values:Export[>..]=[];var interfaces:u8[>..]=[];var names:Declaration[>..]=[];
 for module,mid in g.modules {
  if mid==0 {continue;}
  let source=g.sources[module.source_start..module.source_end];
  let path=g.paths[module.path_start..module.path_end];
  let lines=link_lines::split(source);if lines.status!=0 {return Result {status:1};}
  for span in lines.lines {
   if names.len>=256 {return Result {status:2};}
   let line=source[span.start..span.end];let pub=public_frontend::parse(line);
   var start:i64=0;var end:i64=0;
   if pub.status==0 {start=pub.core.name_start;end=pub.core.name_end;}
   else {
    let a,b,ok=private_check(line);if !ok {return Result {status:1};}start=a;end=b;
   }
   let absolute_start=module.source_start+span.start+start;let absolute_end=module.source_start+span.start+end;
   // Same-scope import aliases cannot collide with provider declarations.
   // Full K1 namespace resolution is outside this restricted fixture.
   for edge in g.edges {
    if edge.from==mid && g.sources[edge.alias_start..edge.alias_end]==g.sources[absolute_start..absolute_end] {return Result {status:3};}
   }
   for n in names {if n.module==mid && g.sources[n.name_start..n.name_end]==g.sources[absolute_start..absolute_end] {return Result {status:3};}}
   names.push(Declaration {module:mid,name_start:absolute_start,name_end:absolute_end});
   if pub.status==0 {
    if !public_frontend::verify(line,pub) {return Result {status:1};}
    let name=line[start..end];let encoded=public_artifact::encode(line,pub,g.package,path,name,abi);
    if encoded.len==0 || encoded.len>1048576-interfaces.len ||
       public_artifact::verify_source(encoded,line,pub,g.package,path,name,abi)!=0 {return Result {status:1};}
    let offset=interfaces.len;interfaces.append(encoded);
    values.push(Export {module:mid,name_start:absolute_start,name_end:absolute_end,
      line_start:module.source_start+span.start,line_end:module.source_start+span.end,
      interface_start:offset,interface_end:interfaces.len,result_type:pub.core.result_type as u32,
      depth:pub.declared_depth,frame:pub.declared_frame});
   }
  }
 }
 return Result {values:values,interfaces:interfaces};
}
