// Source-checked closed ownership shape for one U32 singleton. Returns a
// semantic plan only, never accepts caller-supplied owner/domain identities.
// This is not a general K1 compiler or ABI.
namespace viewalloc_verify;
import lexer;
import viewproof_verify;
import viewcall_core;
import viewcall_verify;
struct Plan {status:i64=1,reserve:u32=0,value:u32=0,index:u32=0,middle:u32=0}
fn kw(s:u8[:],c:viewproof_verify::Cursor&,x:u8[:]) {viewproof_verify::kw(s,c,x);}
fn p(s:u8[:],c:viewproof_verify::Cursor&,x:u8[:]) {viewproof_verify::punct(s,c,x);}
fn lay(s:u8[:],c:viewproof_verify::Cursor&,k:i64) {viewproof_verify::layout(s,c,k);}
fn line(s:u8[:],c:viewproof_verify::Cursor&) {lay(s,c,6);}
fn val(s:u8[:],c:viewproof_verify::Cursor&)->u32 {return viewproof_verify::integer(s,c) as u32;}
fn check(src:u8[:],prefix:viewcall_core::Program&)->Plan {
 let split=prefix.source.len;if src.len>65536 || split<=0 || split>=src.len || !viewcall_verify::verify(src[..split],prefix) {return Plan {};}
 if prefix.name.start<0 || prefix.name.end<=prefix.name.start || prefix.name.end>split-prefix.split || prefix.split<0 || prefix.split>=split {return Plan {};}
 let ps=src[prefix.split..split];if ps[prefix.name.start..prefix.name.end]!="relay" || prefix.callee.source[prefix.callee.name.start..prefix.callee.name.end]=="entry" {return Plan {};}
 let s=src[split..];var c=viewproof_verify::Cursor {lex:lexer::init(s)};viewproof_verify::step(s,c);while c.ok && c.tok.kind==6 {viewproof_verify::step(s,c);}
 kw(s,c,"let");kw(s,c,"entry");p(s,c,":");kw(s,c,"Unit");p(s,c,"->");kw(s,c,"Result");p(s,c,"[");kw(s,c,"Result");p(s,c,"[");kw(s,c,"U32");p(s,c,",");kw(s,c,"AllocError");p(s,c,"]");p(s,c,",");kw(s,c,"ReserveError");p(s,c,"]");p(s,c,"!");p(s,c,"{");kw(s,c,"reserve");p(s,c,",");kw(s,c,"release");p(s,c,"}");p(s,c,"=");kw(s,c,"fn");p(s,c,"(");p(s,c,")");p(s,c,"=>");kw(s,c,"return");kw(s,c,"region");p(s,c,"@");p(s,c,"[");kw(s,c,"Result");p(s,c,"[");kw(s,c,"U32");p(s,c,",");kw(s,c,"AllocError");p(s,c,"]");p(s,c,"]");p(s,c,"(");let reserve=val(s,c);p(s,c,")");kw(s,c,"as");kw(s,c,"r");p(s,c,"(");kw(s,c,"owner");p(s,c,",");kw(s,c,"free");p(s,c,")");kw(s,c,"in");kw(s,c,"do");p(s,c,":");line(s,c);lay(s,c,7);
 kw(s,c,"let");p(s,c,"(");kw(s,c,"rest");p(s,c,",");kw(s,c,"answer");p(s,c,")");p(s,c,":");p(s,c,"(");kw(s,c,"Space");p(s,c,"[");kw(s,c,"r");p(s,c,"]");p(s,c,",");kw(s,c,"Result");p(s,c,"[");kw(s,c,"U32");p(s,c,",");kw(s,c,"AllocError");p(s,c,"]");p(s,c,")");p(s,c,"=");kw(s,c,"do");p(s,c,":");line(s,c);lay(s,c,7);
 kw(s,c,"case");kw(s,c,"region");p(s,c,".");kw(s,c,"try_alloc");p(s,c,"@");p(s,c,"[");kw(s,c,"U32");p(s,c,"]");p(s,c,"(");kw(s,c,"free");p(s,c,",");let count=val(s,c);p(s,c,")");p(s,c,":");line(s,c);lay(s,c,7);
 p(s,c,"#");kw(s,c,"Err");p(s,c,"(");p(s,c,"(");kw(s,c,"failspace");p(s,c,",");kw(s,c,"error");p(s,c,")");p(s,c,")");p(s,c,"=>");kw(s,c,"break");p(s,c,"(");kw(s,c,"failspace");p(s,c,",");p(s,c,"#");kw(s,c,"Err");p(s,c,"(");kw(s,c,"error");p(s,c,")");p(s,c,")");line(s,c);
 p(s,c,"#");kw(s,c,"Ok");p(s,c,"(");p(s,c,"(");kw(s,c,"okspace");p(s,c,",");kw(s,c,"dst");p(s,c,")");p(s,c,")");p(s,c,"=>");kw(s,c,"do");p(s,c,":");line(s,c);lay(s,c,7);
 kw(s,c,"let");kw(s,c,"packed");p(s,c,"=");kw(s,c,"array");p(s,c,".");kw(s,c,"in");p(s,c,"(");kw(s,c,"dst");p(s,c,",");p(s,c,"#");p(s,c,"[");let value=val(s,c);p(s,c,"]");p(s,c,")");line(s,c);
 kw(s,c,"let");kw(s,c,"value");p(s,c,"=");kw(s,c,"open");kw(s,c,"packed");kw(s,c,"as");p(s,c,"[");kw(s,c,"d");p(s,c,"]");kw(s,c,"a");kw(s,c,"in");kw(s,c,"do");p(s,c,":");line(s,c);lay(s,c,7);
 kw(s,c,"break");kw(s,c,"relay");p(s,c,"@");p(s,c,"[");kw(s,c,"r");p(s,c,",");let witness=val(s,c);p(s,c,",");kw(s,c,"d");p(s,c,"]");p(s,c,"(");kw(s,c,"a");p(s,c,",");let index=val(s,c);p(s,c,",");let middle=val(s,c);p(s,c,")");line(s,c);lay(s,c,8);
 kw(s,c,"break");p(s,c,"(");kw(s,c,"okspace");p(s,c,",");p(s,c,"#");kw(s,c,"Ok");p(s,c,"(");kw(s,c,"value");p(s,c,")");p(s,c,")");line(s,c);lay(s,c,8);lay(s,c,8);lay(s,c,8);
 kw(s,c,"space");p(s,c,".");kw(s,c,"end");p(s,c,"(");kw(s,c,"rest");p(s,c,")");line(s,c);kw(s,c,"region");p(s,c,".");kw(s,c,"close");p(s,c,"(");kw(s,c,"owner");p(s,c,")");line(s,c);kw(s,c,"break");kw(s,c,"answer");if c.tok.kind==6 {viewproof_verify::step(s,c);}lay(s,c,8);while c.ok && c.tok.kind==6 {viewproof_verify::step(s,c);}
 if !c.ok || c.tok.kind!=0 || count!=1 || witness!=1 {return Plan {};}
 return Plan {status:0,reserve:reserve,value:value,index:index,middle:middle};
}
