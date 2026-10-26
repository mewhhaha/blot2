// Private formal-parameter/read seam. It does not validate a call, loan,
// allocation, external ABI, or executable memory authority.
namespace viewproof_core;
struct Span {start:i64=0,end:i64=0}
// Terms 1 and 2 are the two immutable scalar formals; 3 is Len(exact View).
struct Guard {left:i64=0,right:i64=0,strict:bool=false,source:Span=Span {}}
struct Evidence {access:Span=Span {},index:Span=Span {},view:Span=Span {},path_len:i64=0,path:i64[6]=[0;6]}
struct Program {source:u8[]=[],name:Span=Span {},region:Span=Span {},nat:Span=Span {},domain:Span=Span {},view:Span=Span {},index:Span=Span {},middle:Span=Span {},guards:Guard[]=[],read:Span=Span {},fallback:u32=0,evidence:Evidence=Evidence {}}
fn span_eq(a:Span,b:Span)->bool{return a.start==b.start && a.end==b.end;}
fn guard_eq(a:Guard,b:Guard)->bool {return a.left==b.left && a.right==b.right && a.strict==b.strict && span_eq(a.source,b.source);}
