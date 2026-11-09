#include "holder-prefix.h"
struct Probe {
    vector<StoreEvent> storeevents;
    HolderStoreIndex holderstoreindex;
    unordered_map<VarDef *, vector<size_t>> storeeventkeys;
    vector<size_t> storeeventclassreads;
    bool pathslive = true;
    set<size_t> retired;
    set<VarDef *> classes;
    unordered_map<VarDef *, int> depths;
    unordered_map<TypeExpr *, vector<TypeExpr *>> refs;
    unordered_map<TypeExpr *, vector<pair<TypeExpr *,bool>>> slots;
    vector<size_t> later_calls;
    bool StoredLater(size_t i) { later_calls.push_back(i); return retired.count(i); }
    TypeExpr *LoadType(TypeExpr *t) { return t; }
    bool CanHoldViewInto(TypeExpr *,TypeExpr *) { return true; }
    bool CanContain(TypeExpr *a,TypeExpr *b) { return a == b; }
    bool IsRefOrSlice(TypeExpr *t) { return t->kind == TY_REF || t->kind == TY_SLICE; }
    bool IsU8(TypeExpr *t) { return t->kind == TY_INT && t->intstorage == IS_U8; }
    bool Viewable(TypeExpr *) { return true; }
    int Depth(VarDef *v) { return depths[v]; }
    bool IsClassRoot(VarDef *v) { return classes.count(v); }
    bool HoldsPlainRef(TypeExpr *t) { return !refs[t].empty(); }
    void RefPointees(TypeExpr *t, vector<TypeExpr *> &out) { out = refs[t]; }
    void ReachedThroughRefs(TypeExpr *t, vector<TypeExpr *> &out) { out = refs[t]; }
    void RefSlots(TypeExpr *t,vector<pair<TypeExpr *,bool>> &out) { out = slots[t]; }
#include "holder-methods.h"
};
// Law assertions remain enabled when the extracted production methods use NDEBUG.
#undef NDEBUG
#include <cassert>
#include <iostream>
static int laws;
static void same(Probe &p,VarDef *h,VarDef *arr,TypeExpr *type,size_t from=0) {
    Line a{-1,-2,-3},b=a; size_t ia=SIZE_MAX,ib=ia; TypeExpr *va=nullptr,*vb=nullptr;
    auto x=p.RawHolderMayPointInto(h,arr,type,from,&a,&ia,&va);
    auto calls=p.later_calls; p.later_calls.clear();
    auto y=p.HolderMayPointInto(h,arr,type,from,&b,&ib,&vb);
    assert(x==y && a.line==b.line && a.fileidx==b.fileidx && a.col==b.col && ia==ib && va==vb);
    assert(calls==p.later_calls); p.later_calls.clear(); ++laws;
}
int main() {
    TypeExpr value{TY_INT,{}},slot{TY_BOOL,{}};
    VarDef h{},arr{},other{},nested{},klass{},global{};
    h.type=&slot; arr.type=&value; other.type=&slot; nested.type=&slot; global.type=&slot; global.isglobal=true;
    Probe p; p.holderstoreindex.profile=true; p.refs[&slot]={&value}; p.slots[&slot]={{&slot,false}};
    auto add=[&](VarDef *holder,VarDef *root,bool exact,TypeExpr *pt=nullptr,VarDef *src=nullptr) {
        StoreEvent e{}; e.container=holder;e.root=root;e.exact=exact;e.pointee=pt;e.src=src;
        e.at={int(p.storeevents.size()+11),7,9};p.AppendStoreEventLog(e);
    };
    same(p,&h,&arr,&value); // absent holder
    for(int i=0;i<40;++i) add(&other,&other,true);
    add(&h,&nested,true,&slot); add(&nested,&arr,true);
    same(p,&h,&arr,&value); // second-pass slot -> recursive first-pass exact root
    for(size_t from=0;from<=p.storeevents.size()+1;++from) same(p,&h,&arr,&value,from);
    p.retired.insert(41); same(p,&h,&arr,&value); p.retired.clear();
    auto moved=p.storeevents[1]; moved.container=&h; moved.root=&nested; moved.pointee=&slot;
    p.ReplaceStoreEventLog(1,moved); same(p,&h,&arr,&value); // historical old ID inserted before tail
    p.ReplaceStoreEventLog(1,moved); same(p,&h,&arr,&value); // duplicate ID
    moved.container=&other;p.ReplaceStoreEventLog(1,moved);same(p,&h,&arr,&value); // stale old posting
    add(&h,nullptr,false,nullptr,&nested);same(p,&h,&arr,&value); // copy source first pass
    add(&h,nullptr,false,&slot,&klass);p.storeevents.back().classread=true;
    add(&klass,&arr,true);same(p,&h,&arr,&value); // classread normalization independent of index
    p.storeevents[p.storeevents.size()-2].classread=false;same(p,&h,&arr,&value);
    add(&nested,nullptr,false,nullptr,&h);same(p,&h,&arr,&value); // seen cycle
    add(&h,nullptr,false,nullptr,&global);same(p,&h,&arr,&value);
    same(p,nullptr,&arr,&value);add(nullptr,&nested,true,&slot);same(p,nullptr,&arr,&value);
    p.holderstoreindex.max_capacity=p.holderstoreindex.capacity;
    add(&h,&nested,true,&slot); add(&h,&nested,true,&slot); add(&h,&nested,true,&slot);
    while(p.holderstoreindex.active) add(&h,&nested,true,&slot);
    same(p,&h,&arr,&value);assert(p.holderstoreindex.postings.empty()); // whole raw fallback
    HolderStoreIndex caps;caps.max_holders=1;caps.Record(&h,9);caps.Record(&h,2);caps.Record(&h,2);
    assert((*caps.Find(&h)==vector<uint32_t>{2,9}));caps.Record(&arr,4);assert(!caps.active && !caps.Find(&h));++laws;
    HolderStoreIndex zero;zero.max_capacity=0;zero.Record(nullptr,0);assert(!zero.active);++laws;
    HolderStoreIndex overflow;overflow.Record(&h,size_t(UINT32_MAX)+1);assert(!overflow.active);++laws;
    // Deterministic mixed graph matrix, with independent absent/hit/recursive paths.
    uint32_t rng=19;
    auto next=[&] { rng=rng*1664525u+1013904223u; return rng; };
    for(int round=0;round<256;++round) {
        Probe q; q.refs[&slot]={&value};q.slots[&slot]={{&slot,false}};
        q.classes.insert(&klass);q.depths[&arr]=1;q.depths[&klass]=2;
        VarDef *holders[]={&h,&other,&nested,&klass,nullptr};
        for(int i=0;i<24;++i) {
            StoreEvent e{};e.container=holders[next()%5];e.root=holders[next()%5];
            e.exact=(next()%2);e.pointee=&slot;e.at={i+101,3,4};
            switch(next()%6) {
                case 0:e.src=&klass;e.classread=true;break;
                case 1:e.src=&klass;break;
                case 2:e.src=&global;break;
                case 3:e.src=&nested;break;
                case 4:e.root=&arr;break;
            }
            q.AppendStoreEventLog(e);
            if(next()%5==0)q.retired.insert(i);
        }
        auto e=q.storeevents[next()%24];e.container=&h;
        q.ReplaceStoreEventLog(next()%24,e);
        same(q,&h,&arr,&value,next()%27);
        same(q,&nested,&arr,nullptr,next()%27);
        same(q,&klass,&arr,&value,next()%27);
        if(round%2==0)q.holderstoreindex.Disable("law");
        same(q,&h,&arr,&value);
    }
    std::cout << "holder event laws " << laws << " passed\n";
}
