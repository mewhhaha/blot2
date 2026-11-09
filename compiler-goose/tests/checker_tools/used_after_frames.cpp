#include "used-after-prefix.h"
// Unused virtual compiler passes fail hard if this focused traversal enters them.
namespace goose {
#define UNUSED_PASSES(T) \
void T::Dump(string &,int) const { abort(); } \
Val T::Check(TypeCheck &,TypeExpr *) { abort(); } \
Node *T::Cp1(Inliner &) const { abort(); } \
Node *T::Opt(Optimizer &) { abort(); } \
string T::CgX(CodeGen &) { abort(); } \
void T::CgAny(CodeGen &,const Dst &) { abort(); } \
void T::CgStmt(CodeGen &) { abort(); }
UNUSED_PASSES(Ident) UNUSED_PASSES(Block) UNUSED_PASSES(Return)
UNUSED_PASSES(Break) UNUSED_PASSES(Continue) UNUSED_PASSES(FnDecl) UNUSED_PASSES(Call)
#undef UNUSED_PASSES
bool Node::BceWalk(BCE &) { abort(); }
void Node::BceMark(BCE &) { abort(); }
void Ident::BceMark(BCE &) { abort(); }
bool Block::BceWalk(BCE &) { abort(); }
bool Return::BceWalk(BCE &) { abort(); }
bool Break::BceWalk(BCE &) { abort(); }
bool Continue::BceWalk(BCE &) { abort(); }
bool Call::BceWalk(BCE &) { abort(); }
void Call::BceMark(BCE &) { abort(); }
}
struct Probe {
    struct Frame { int lexframe=-1,scopebase=0;bool isfunval=false,isdefault=false; };
    enum ScopeKind { SK_PLAIN, SK_FN, SK_LOOP, SK_BLOCK, SK_EXPANSION };
    struct Scope { int kind=SK_PLAIN;Node *node=nullptr; };
    struct BlockPos { Block *block;size_t idx;int scopeidx; };
    vector<Frame> frames;
    vector<Scope> scopes;
    vector<BlockPos> blockpos;
    vector<pair<int,SFunction *>> localfns;
    vector<pair<Node *,int>> later;
    int depth=1;
    uint64_t frame_queries=0;
    vector<pair<Node *,vector<SFunction *>>> seen_log;
    int Depth(VarDef *) { return depth; }
    template<class F> void LaterOperands(F f) { for(auto [n,fi]:later) f(n,fi); }
    bool MentionsName(Node *n,string_view name,set<SFunction *> &seen) {
        seen_log.push_back({n,vector<SFunction *>(seen.begin(),seen.end())});
        auto result=WalkMentionsName(n,name,seen);
        seen_log.push_back({n,vector<SFunction *>(seen.begin(),seen.end())});
        return result;
    }
#include "used-after-methods.h"
};
#undef NDEBUG
#include <cassert>
#include <iostream>
static int laws;
static void same(Probe &p,VarDef *v,bool expected) {
    p.frame_queries=0;p.seen_log.clear();auto raw=p.RawUsedAfter(v);auto seen=p.seen_log;
    p.frame_queries=0;p.seen_log.clear();auto fresh=p.UsedAfter(v);
    assert(raw==fresh && fresh==expected && seen==p.seen_log);++laws;
}
int main() {
    VarDef v{};v.name="wanted";
    Ident named({},"wanted"),none({},"other"),callee({},"nested");
    Return ret({});Break brk({},nullptr);Continue cont({});
    Block ignored({}),valid({}),inner({}),nested_body({});
    SFunction sf{};sf.name="nested";sf.body=&nested_body;
    FnDecl decl({},&sf);Call call({},&callee);
    Probe p;p.frames={{-1,0},{-1,1},{1,2}};p.scopes.resize(3);
    ignored.stmts={&none,&named};p.blockpos={{&ignored,0,1}};
    same(p,&v,false); // unrelated frame cannot name caller's variable
    p.frames[1].lexframe=0;same(p,&v,true); // lexical nested frame
    p.frames[1].lexframe=-1;p.later={{&named,1}};same(p,&v,false);
    p.later={{&named,0}};same(p,&v,true);p.later.clear();
    p.frames[1].isfunval=true;ignored.stmts={&named};
    same(p,&v,false); // unrelated funval body also unnameable
    p.frames[1].lexframe=0;same(p,&v,true); // whole body includes current statement
    p.frames[1].isdefault=true;same(p,&v,false); // default excludes whole-body rule
    p.frames[1].isdefault=false;p.frames[1].isfunval=false;
    ignored.stmts={&none};ignored.tail=&named;same(p,&v,true);
    ignored.tail=nullptr;
    // Return and break cuts computed in the innermost block remain identical.
    p.depth=2;p.frames[1].lexframe=-1;p.scopes[1].kind=Probe::SK_LOOP;
    valid.stmts={&none,&named};inner.stmts={&none,&ret,&named};
    p.blockpos={{&valid,0,1},{&inner,0,2}};
    same(p,&v,true); // outer block retained by return from frame2
    valid.stmts={&none};same(p,&v,false); // inner after return excluded
    inner.stmts={&none,&brk,&named};p.scopes[2].kind=Probe::SK_BLOCK;same(p,&v,false);
    inner.stmts={&none,&cont,&named};same(p,&v,true); // escaping continue prevents exit cut
    inner.stmts={&none};inner.tail=&ret;same(p,&v,false); // tail return
    inner.tail=&named;same(p,&v,true);
    p.scopes[2].kind=Probe::SK_PLAIN;p.scopes[1].kind=Probe::SK_PLAIN;
    // Actual nested-function traversal and shared seen sets, including cycles.
    nested_body.stmts={&decl,&named};inner.tail=nullptr;inner.stmts={&none,&call,&decl};
    p.localfns={{1,&sf}};same(p,&v,true);
    nested_body.stmts={&decl,&none};same(p,&v,false);
    nested_body.stmts={&named};same(p,&v,true);
    p.frames[2].lexframe=-1;same(p,&v,false); // no seen mutation for excluded inner frame
    p.frames[2].lexframe=1;
    // Repeat across moving positions, scope frames, and pruned/expanded AST arrays.
    for(int mode=0;mode<128;++mode) {
        p.depth=1;p.frames[1].lexframe=(mode&1)?0:-1;p.frames[2].lexframe=(mode&2)?1:-1;
        p.frames[1].isfunval=(mode&4);p.frames[1].isdefault=(mode&8);
        ignored.stmts={&none,&decl,&none};ignored.tail=(mode&16)?&named:nullptr;
        nested_body.stmts=(mode&32)?vector<Node *>{&decl,&none}:vector<Node *>{&decl,&named};
        p.blockpos={{&ignored,size_t((mode&64)?2:0),1}};
        p.seen_log.clear();auto expected=p.RawUsedAfter(&v);same(p,&v,expected);
    }
    // Synthetic work-count control: unrelated block of4096 future statements.
    Probe q;q.frames={{-1,0},{-1,1},{1,2}};q.scopes.resize(3);
    Block large({});large.stmts.assign(4097,&none);q.blockpos={{&large,0,1}};
    assert(!q.RawUsedAfter(&v));auto before=q.frame_queries;q.frame_queries=0;
    assert(!q.UsedAfter(&v));auto after=q.frame_queries;
    assert(before==4096 && after==1);++laws;
    std::cout<<"used-after frame laws "<<laws<<" passed; unrelated4096 frame tests "<<before<<" -> "<<after<<"\n";
}
