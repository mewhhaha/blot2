// Narrow private scalar caller syntax: one U32 parameter returned through one
// qualified import call. It is not a general K1 declaration or type checker.
namespace link_consumer;
import lexer;
import validate;
struct Call {status:i64=1,name_start:i64=0,name_end:i64=0,param_start:i64=0,param_end:i64=0,
             alias_start:i64=0,alias_end:i64=0,target_start:i64=0,target_end:i64=0}
struct Cursor {state:lexer::State=lexer::State {},token:lexer::Token=lexer::Token {}}
fn next(s:u8[:],c:Cursor&) {c.token=lexer::next(s,c.state);}
fn take(s:u8[:],c:Cursor&,kind:i64,text:u8[:]) -> bool {
 let t=c.token;if t.kind!=kind || t.start<0 || t.end<=t.start || t.end>s.len || s[t.start..t.end]!=text {return false;}
 next(s,c);return true;
}
fn name(s:u8[:],c:Cursor&) -> lexer::Token {
 let t=c.token;if t.kind!=1 || t.start<0 || t.end<=t.start || t.end>s.len || !validate::name_valid(s[t.start..t.end]) {return lexer::Token {kind:9};}
 next(s,c);return t;
}
fn parse(s:u8[:]) -> Call {
 var c=Cursor {state:lexer::init(s)};next(s,c);
 if !take(s,c,1,"let") {return Call {};}
 let fnname=name(s,c);if fnname.kind==9 || !take(s,c,5,":") || !take(s,c,1,"U32") || !take(s,c,5,"->") ||
   !take(s,c,1,"U32") || !take(s,c,5,"=") || !take(s,c,1,"fn") {return Call {};}
 let parameter=name(s,c);if parameter.kind==9 || !take(s,c,5,"=>") || !take(s,c,1,"return") {return Call {};}
 let alias=name(s,c);
 // A lexical parameter shadows a same-named module receiver. The fixture
 // cannot resolve member access on U32, so it rejects this ambiguity.
 if alias.kind==9 || s[alias.start..alias.end]==s[parameter.start..parameter.end] ||
    s[alias.start..alias.end]==s[fnname.start..fnname.end] || !take(s,c,5,".") {return Call {};}
 let target=name(s,c);if target.kind==9 || !take(s,c,5,"(") {return Call {};}
 let arg=name(s,c);if arg.kind==9 || s[arg.start..arg.end]!=s[parameter.start..parameter.end] || !take(s,c,5,")") {return Call {};}
 while c.token.kind==6 {next(s,c);}if c.token.kind!=0 {return Call {};}
 return Call {status:0,name_start:fnname.start,name_end:fnname.end,param_start:parameter.start,param_end:parameter.end,
  alias_start:alias.start,alias_end:alias.end,target_start:target.start,target_end:target.end};
}
