// Restricted public U32 call wrapper. Its actual source is independently
// checked as a header plus a qualified call; its interface is constructed
// from an equivalent source-validated identity body and is never body proof.
namespace chain_public;
import public_frontend;
import public_artifact;
import link_consumer;
import link_consumer_check;
import validate;
import lexer;
struct Result {status:i64=1,name_start:i64=0,name_end:i64=0,alias_start:i64=0,alias_end:i64=0,
 target_start:i64=0,target_end:i64=0,param_start:i64=0,param_end:i64=0,depth:u32=0,frame:u32=0,interface:u8[]=[]}
fn parse(s:u8[:],package:u8[:],module:u8[:],abi:u8[:])->Result {
 var c=public_frontend::Cursor {lex:lexer::init(s)};public_frontend::advance(s,c);
 if !public_frontend::take_word(s,c,"pub") {return Result {};}
 let base=c.token.start;
 if !public_frontend::take_word(s,c,"let") || c.token.kind!=1 || !public_frontend::in_bounds(s,c.token) ||
  !validate::name_valid(s[c.token.start..c.token.end]) {return Result {};}
 public_frontend::advance(s,c);
 if !public_frontend::take_sym(s,c,":") || !public_frontend::take_word(s,c,"U32") || !public_frontend::take_sym(s,c,"->") ||
  !public_frontend::take_word(s,c,"U32") {return Result {};}
 let effect=c.token.start;
 if !public_frontend::take_sym(s,c,"!") || !public_frontend::take_sym(s,c,"{") || !public_frontend::take_sym(s,c,"}") ||
  !public_frontend::take_word(s,c,"resources") || !public_frontend::take_sym(s,c,"{") || !public_frontend::take_word(s,c,"depth") ||
  !public_frontend::take_sym(s,c,":") {return Result {};}
 let depth,ok=public_frontend::number(s,c.token);if !ok {return Result {};}public_frontend::advance(s,c);
 if !public_frontend::take_sym(s,c,",") || !public_frontend::take_word(s,c,"frame") || !public_frontend::take_sym(s,c,":") {return Result {};}
 let frame,fok=public_frontend::number(s,c.token);if !fok {return Result {};}public_frontend::advance(s,c);
 let end=c.token.end;if !public_frontend::take_sym(s,c,"}") || !public_frontend::sym(s,c.token,"=") {return Result {};}
 for i in 0..c.token.start {if s[i]=='\n' || s[i]=='\r' {return Result {};}}
 let projected=public_frontend::projected(s,base,effect,end);
 let call=link_consumer::parse(projected);
 if call.status!=0 || !link_consumer_check::verify(projected,call) {return Result {};}
 let alias_start=base+call.alias_start;let alias_end=base+call.alias_end;
 let param_start=base+call.param_start;let param_end=base+call.param_end;
 var synthetic:u8[>..]=[];synthetic.append(s[..alias_start]);synthetic.append(s[param_start..param_end]);
 let candidate=public_frontend::parse(synthetic);
 if candidate.status!=0 || candidate.declared_depth!=depth || candidate.declared_frame!=frame {return Result {};}
 let name=s[base+call.name_start..base+call.name_end];
 let interface=public_artifact::encode(synthetic,candidate,package,module,name,abi);
 if interface.len==0 || public_artifact::verify_source(interface,synthetic,candidate,package,module,name,abi)!=0 {return Result {};}
 return Result {status:0,name_start:base+call.name_start,name_end:base+call.name_end,alias_start:alias_start,alias_end:alias_end,
  target_start:base+call.target_start,target_end:base+call.target_end,param_start:param_start,param_end:param_end,
  depth:depth,frame:frame,interface:interface};
}
