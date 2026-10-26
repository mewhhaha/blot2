// Source-owned restricted ownership body; no authority or semantic admission.
// Child and binding IDs are one-based. Nodes are postorder, all bindings are
// numbered by lexical declaration order; root is the final node.
// Tags: 1 move (let bound = ref), 2 close(ref), 3 open(bound,ref,region,
// payload,body), 4 if(ref,yes,no), 5 return Unit, 6 return ref,
// 7 break ref, 8 sequence(a,b). Zero no-child means absent else only.
// Names are exact half-open source spans, never inferred from numeric IDs.
namespace ownership_syntax;
struct Binding {start:i64=0,end:i64=0}
struct Node {tag:i64=0,start:i64=0,end:i64=0,ref_start:i64=0,ref_end:i64=0,
             a:i64=0,b:i64=0,bound:i64=0,region:i64=0,payload:i64=0}
struct Tree {source:u8[]=[],nodes:Node[]=[],bindings:Binding[]=[],root:i64=0}
struct Result {status:i64=1,tree:Tree=Tree {}}
