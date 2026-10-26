// Private AST for an Owned lifecycle body with trusted `h: Owned[Scalar]`,
// `flag: Bool` and a U32 payload alias. One-based child IDs are postorder.
// Tags: 1 move h->m; 2 close(owner); 3 open(owner,body); 4 if(flag,yes,no);
// 5 return Unit; 6 return Owned; 7 break payload; 8 sequence(a,b). A zero
// else child means implicit fallthrough. Owner 1 is h, 2 is m. These raw
// records do not establish source, type, loan or runtime authority.
namespace affine_syntax;
struct Node { tag: i64 = 0, start: i64 = 0, end: i64 = 0, owner: i64 = 0, a: i64 = 0, b: i64 = 0 }
struct Tree { source: u8[] = [], nodes: Node[] = [], root: i64 = 0 }
struct Result { status: i64 = 1, tree: Tree = Tree {} }
